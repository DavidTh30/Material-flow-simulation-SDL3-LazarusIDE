unit aibridge;

{ The AI bridge: a small HTTP server on this PC only (127.0.0.1) through which
  the AI Chat window works the program. The chat page posts JSON to
  http://127.0.0.1:<port>/api with the header X-MF-Token: <token>; the token
  is made when the bridge starts and given only to the chat window the
  program opens (in its URL), so no other page can use it. A request is
  handed to the program (BridgeNext), which answers it (BridgeReply) - now or
  a few frames later. Every socket is non-blocking. }

{$mode objfpc}{$H+}

interface

type
  TBridgeAnswer = function(const Body: string): string;

var
  BridgeToken: string = '';
  BridgePort: Integer = 0;
  { where the port and token are written for the Claude Code MCP server (mfmcp.exe); '' = nowhere (test runs) }
  BridgeInfoFile: string = '';

{ start it (the first free port from 5047); True when it listens }
function BridgeStart: Boolean;
procedure BridgeStop;
function BridgeRunning: Boolean;
{ accept, read and write; once a frame }
procedure BridgePoll;
{ the next request to answer: its id and its JSON body }
function BridgeNext(out Id: Integer; out Body: string): Boolean;
procedure BridgeReply(Id: Integer; const Json: string);
{ for the tests: one request from this program to itself, answered by Answer; returns the reply's body }
function BridgeSelfRequest(const Token, Body: string; Answer: TBridgeAnswer = nil): string;

implementation

uses
  SysUtils, WinSock2;

const
  MAX_CONN = 8;
  MAX_BODY = 40 * 1024 * 1024;

type
  TBConn = record
    Sock: TSocket;
    State: Byte;          { 0 free, 1 reading, 2 waiting for its answer, 3 writing }
    InBuf, OutBuf: AnsiString;
    Id: Integer;
    Body: string;
    Handed: Boolean;
  end;

var
  Listener: TSocket = INVALID_SOCKET;
  Conns: array[0..MAX_CONN - 1] of TBConn;
  NextId: Integer = 1;
  WSAOK: Boolean = False;

procedure EnsureWSA;
var
  d: TWSAData;
begin
  if not WSAOK then WSAOK := WSAStartup($0202, d) = 0;
end;

procedure NonBlocking(s: TSocket);
var
  arg: u_long;
begin
  arg := 1;
  ioctlsocket(s, Longint(FIONBIO), arg);
end;

function MakeToken: string;
var
  k: Integer;
begin
  Result := '';
  for k := 1 to 32 do Result := Result + IntToHex(Random(16), 1);
  Result := LowerCase(Result);
end;

{ the port and token for the MCP server: aichat\bridge.json }
procedure WriteInfo;
var
  f: TextFile;
begin
  if BridgeInfoFile = '' then Exit;
  try
    AssignFile(f, BridgeInfoFile);
    Rewrite(f);
    WriteLn(f, Format('{"port":%d,"token":"%s","pid":%d}', [BridgePort, BridgeToken, GetProcessID]));
    CloseFile(f);
  except
  end;
end;

{ gone with the bridge (unless another copy of the program wrote it since) }
procedure DeleteInfo;
var
  f: TextFile;
  s: string;
begin
  if (BridgeInfoFile = '') or not FileExists(BridgeInfoFile) then Exit;
  s := '';
  try
    AssignFile(f, BridgeInfoFile);
    Reset(f);
    if not EOF(f) then ReadLn(f, s);
    CloseFile(f);
  except
  end;
  if (BridgeToken <> '') and (Pos(BridgeToken, s) > 0) then DeleteFile(BridgeInfoFile);
end;

function BridgeStart: Boolean;
var
  a: TSockAddrIn;
  p: Integer;
begin
  if Listener <> INVALID_SOCKET then Exit(True);
  EnsureWSA;
  if BridgeToken = '' then BridgeToken := MakeToken;
  for p := 5047 to 5066 do
  begin
    Listener := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if Listener = INVALID_SOCKET then Exit(False);
    FillChar(a, SizeOf(a), 0);
    a.sin_family := AF_INET;
    a.sin_port := htons(p);
    a.sin_addr.S_addr := inet_addr('127.0.0.1');
    if (bind(Listener, PSockAddr(@a), SizeOf(a)) = 0) and (listen(Listener, 8) = 0) then
    begin
      NonBlocking(Listener);
      BridgePort := p;
      WriteInfo;
      Exit(True);
    end;
    closesocket(Listener);
    Listener := INVALID_SOCKET;
  end;
  Result := False;
end;

procedure CloseConn(var C: TBConn);
begin
  if C.Sock <> INVALID_SOCKET then closesocket(C.Sock);
  C.Sock := INVALID_SOCKET;
  C.State := 0;
  C.InBuf := '';
  C.OutBuf := '';
  C.Body := '';
  C.Handed := False;
end;

procedure BridgeStop;
var
  i: Integer;
begin
  for i := 0 to MAX_CONN - 1 do CloseConn(Conns[i]);
  if Listener <> INVALID_SOCKET then DeleteInfo;
  if Listener <> INVALID_SOCKET then closesocket(Listener);
  Listener := INVALID_SOCKET;
  BridgePort := 0;
end;

function BridgeRunning: Boolean;
begin
  Result := Listener <> INVALID_SOCKET;
end;

function CORS: string;
begin
  Result := 'Access-Control-Allow-Origin: *'#13#10 +
    'Access-Control-Allow-Methods: POST, OPTIONS'#13#10 +
    'Access-Control-Allow-Headers: content-type, x-mf-token'#13#10 +
    'Access-Control-Allow-Private-Network: true'#13#10 +
    'Access-Control-Max-Age: 600'#13#10;
end;

procedure Respond(var C: TBConn; const Status, Body: string);
var
  b: AnsiString;
begin
  b := Body;    { the body is UTF-8 already }
  C.OutBuf := 'HTTP/1.1 ' + Status + #13#10 + CORS + 'Content-Type: application/json; charset=utf-8'#13#10 +
    'Cache-Control: no-store'#13#10 + Format('Content-Length: %d'#13#10, [Length(b)]) + 'Connection: close'#13#10#13#10 + b;
  C.State := 3;
end;

function Header(const Head, Name: string): string;
var
  lines: TStringArray;
  k, p: Integer;
begin
  Result := '';
  lines := Head.Split([#13#10]);
  for k := 1 to High(lines) do
  begin
    p := Pos(':', lines[k]);
    if (p > 0) and SameText(Trim(Copy(lines[k], 1, p - 1)), Name) then Exit(Trim(Copy(lines[k], p + 1, MaxInt)));
  end;
end;

{ a request that has come in full }
procedure Parse(var C: TBConn);
var
  p, len: Integer;
  head, first, method, path: string;
begin
  p := Pos(#13#10#13#10, C.InBuf);
  if p = 0 then
  begin
    if Length(C.InBuf) > 65536 then Respond(C, '431 Request Header Fields Too Large', '{"ok":false,"error":"headers too large"}');
    Exit;
  end;
  head := Copy(C.InBuf, 1, p - 1);
  len := StrToIntDef(Header(head, 'Content-Length'), 0);
  if (len < 0) or (len > MAX_BODY) then
  begin
    Respond(C, '413 Payload Too Large', '{"ok":false,"error":"too large"}');
    Exit;
  end;
  if Length(C.InBuf) - (p + 3) < len then Exit;     { the body is still coming }
  first := Copy(head, 1, Pos(#13#10, head + #13#10) - 1);
  method := Copy(first, 1, Pos(' ', first) - 1);
  path := Copy(first, Length(method) + 2, MaxInt);
  path := Copy(path, 1, Pos(' ', path + ' ') - 1);
  if method = 'OPTIONS' then
  begin
    C.OutBuf := 'HTTP/1.1 204 No Content'#13#10 + CORS + 'Content-Length: 0'#13#10'Connection: close'#13#10#13#10;
    C.State := 3;
    Exit;
  end;
  if (method <> 'POST') or (path <> '/api') then
  begin
    Respond(C, '404 Not Found', '{"ok":false,"error":"POST /api"}');
    Exit;
  end;
  if (BridgeToken = '') or (Header(head, 'X-MF-Token') <> BridgeToken) then
  begin
    Respond(C, '403 Forbidden', '{"ok":false,"error":"bad token: open the AI Chat from the program"}');
    Exit;
  end;
  C.Body := Copy(C.InBuf, p + 4, len);
  C.Id := NextId;
  Inc(NextId);
  C.State := 2;
  C.Handed := False;
end;

procedure BridgePoll;
var
  s: TSocket;
  i, n: Integer;
  buf: array[0..65535] of AnsiChar;
begin
  if Listener = INVALID_SOCKET then Exit;
  repeat
    s := accept(Listener, nil, nil);
    if s = INVALID_SOCKET then Break;
    n := -1;
    for i := 0 to MAX_CONN - 1 do
      if Conns[i].State = 0 then
      begin
        n := i;
        Break;
      end;
    if n < 0 then
    begin
      closesocket(s);
      Continue;
    end;
    NonBlocking(s);
    CloseConn(Conns[n]);
    Conns[n].Sock := s;
    Conns[n].State := 1;
  until False;
  for i := 0 to MAX_CONN - 1 do
    with Conns[i] do
      case State of
        1:
          begin
            repeat
              n := recv(Sock, buf, SizeOf(buf), 0);
              if n > 0 then
              begin
                SetLength(InBuf, Length(InBuf) + n);
                Move(buf, InBuf[Length(InBuf) - n + 1], n);
              end;
            until n <= 0;
            if (n = 0) or ((n = SOCKET_ERROR) and (WSAGetLastError <> WSAEWOULDBLOCK)) then CloseConn(Conns[i])
            else Parse(Conns[i]);
          end;
        3:
          begin
            while OutBuf <> '' do
            begin
              n := send(Sock, OutBuf[1], Length(OutBuf), 0);
              if n > 0 then Delete(OutBuf, 1, n) else Break;
            end;
            if (OutBuf = '') or ((n = SOCKET_ERROR) and (WSAGetLastError <> WSAEWOULDBLOCK)) then CloseConn(Conns[i]);
          end;
      end;
end;

function BridgeNext(out Id: Integer; out Body: string): Boolean;
var
  i: Integer;
begin
  for i := 0 to MAX_CONN - 1 do
    if (Conns[i].State = 2) and not Conns[i].Handed then
    begin
      Conns[i].Handed := True;
      Id := Conns[i].Id;
      Body := Conns[i].Body;
      Exit(True);
    end;
  Id := 0;
  Body := '';
  Result := False;
end;

procedure BridgeReply(Id: Integer; const Json: string);
var
  i: Integer;
begin
  for i := 0 to MAX_CONN - 1 do
    if (Conns[i].State = 2) and (Conns[i].Id = Id) then
    begin
      Respond(Conns[i], '200 OK', Json);
      Exit;
    end;
end;

function BridgeSelfRequest(const Token, Body: string; Answer: TBridgeAnswer): string;
var
  s: TSocket;
  a: TSockAddrIn;
  req, got: AnsiString;
  buf: array[0..65535] of AnsiChar;
  n, k, id, p: Integer;
  b: string;
begin
  Result := '';
  if Listener = INVALID_SOCKET then Exit;
  s := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  FillChar(a, SizeOf(a), 0);
  a.sin_family := AF_INET;
  a.sin_port := htons(BridgePort);
  a.sin_addr.S_addr := inet_addr('127.0.0.1');
  if connect(s, PSockAddr(@a), SizeOf(a)) <> 0 then
  begin
    closesocket(s);
    Exit;
  end;
  req := 'POST /api HTTP/1.1'#13#10'Host: 127.0.0.1'#13#10'Content-Type: application/json'#13#10 +
    'X-MF-Token: ' + Token + #13#10 + Format('Content-Length: %d'#13#10#13#10, [Length(Body)]) + Body;
  send(s, req[1], Length(req), 0);
  NonBlocking(s);
  got := '';
  for k := 1 to 400 do
  begin
    BridgePoll;
    if BridgeNext(id, b) then
    begin
      if Assigned(Answer) then BridgeReply(id, Answer(b)) else BridgeReply(id, '{"ok":true}');
    end;
    BridgePoll;
    repeat
      n := recv(s, buf, SizeOf(buf), 0);
      if n > 0 then
      begin
        SetLength(got, Length(got) + n);
        Move(buf, got[Length(got) - n + 1], n);
      end;
    until n <= 0;
    if n = 0 then Break;
    Sleep(2);
  end;
  closesocket(s);
  p := Pos(#13#10#13#10, got);
  if p > 0 then Result := Copy(got, 1, 12) + '|' + Copy(got, p + 4, MaxInt);
end;

var
  k: Integer;

initialization
  for k := 0 to MAX_CONN - 1 do Conns[k].Sock := INVALID_SOCKET;

finalization
  BridgeStop;

end.
