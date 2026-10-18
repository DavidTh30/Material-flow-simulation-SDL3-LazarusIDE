unit ipcnet;

{ IPC over TCP: this program as a server for many clients and as a client of
  many servers, at the same time.

  The wire is text, one message per line:
    HELLO <name>          who is at the other end (sent first by both sides)
    SET <name> <value>    a value (a number; a tag is 0 or 1)
    PING / PONG           keep alive
  Anything else is ignored.

  I/O points say what goes over it. An Output point reads a name in the
  layout (Link: a tag, sensor, equipment, value ...) and sends it under its
  own Name; an Input point takes the value sent under its Name and works the
  part called Link (a switch, pot, set point, equipment run / stop and speed),
  on this page or another one; a Link that is no part becomes a value / tag
  of its own that displays, flow charts and contacts read. An empty Link
  means the point's own Name. Server points talk to the clients (Peer: one
  client by its HELLO name, empty: all), client points to the servers (Peer:
  one server by its name in the list, empty: all).

  The network settings and the I/O points are kept in their own files
  (ipc_network.ini, ipc_io.ini). Server and client are both off by default.
  Every socket is non-blocking: the program never waits on the network. }

{$mode objfpc}{$H+}

interface

const
  IPC_MAX_CLIENTS = 16;
  IPC_MAX_TARGETS = 8;
  IPC_MAX_POINTS = 128;
  IPC_DEFAULT_PORT = 5020;
  IPC_SERVER = 0;
  IPC_CLIENT = 1;
  IPC_IN = 0;
  IPC_OUT = 1;
  IPC_NET_FILE = 'ipc_network.ini';
  IPC_IO_FILE = 'ipc_io.ini';
  IPCSideNames: array[0..1] of string = ('server', 'client');
  IPCDirNames: array[0..1] of string = ('in', 'out');

type
  TIPCTarget = record
    Used, Enabled: Boolean;
    Name: string[24];
    Host: string[60];
    Port: Integer;
  end;

  TIPCPoint = record
    Used: Boolean;
    Side, Dir: Byte;          { IPC_SERVER / IPC_CLIENT, IPC_IN / IPC_OUT }
    Name: string[32];         { its name on the wire }
    Link: string[32];         { the part in the layout ('' = Name) }
    Peer: string[24];         { only this client / server ('' = all) }
    { worked out (not saved) }
    Value: Single;
    Known, Virtual: Boolean;
    Sent: Single;
    From: string[24];
    Count: Integer;           { values received / sent }
  end;

  TIPCConnInfo = record
    Name, Addr, State: string;
    Rx, Tx: Integer;
  end;

var
  IPCServerOn: Boolean = False;
  IPCServerName: string = 'MaterialFlow';
  IPCServerBind: string = '127.0.0.1';
  IPCServerPort: Integer = IPC_DEFAULT_PORT;
  IPCMaxClients: Integer = 8;
  IPCClientOn: Boolean = False;
  IPCClientName: string = 'MaterialFlow';
  IPCTargets: array[0..IPC_MAX_TARGETS - 1] of TIPCTarget;
  IPCPoints: array[0..IPC_MAX_POINTS - 1] of TIPCPoint;

{ both off, no servers in the list, no points }
procedure IPCDefaults;
procedure IPCStep(dt: Single);
procedure IPCStopAll;
function IPCServerState: string;
function IPCServerListening: Boolean;
function IPCClientCount: Integer;
function IPCClientInfo(i: Integer; out Info: TIPCConnInfo): Boolean;
function IPCTargetState(i: Integer): string;
function IPCTargetConnected(i: Integer): Boolean;
function IPCAddTarget(const Name, Host: string; Port: Integer): Integer;
procedure IPCDeleteTarget(i: Integer);
function IPCAddPoint(Side, Dir: Integer; const Name, Link, Peer: string): Integer;
procedure IPCDeletePoint(i: Integer);
function IPCFindPoint(Side, Dir: Integer; const Name: string): Integer;
function IPCPointCount(Side: Integer): Integer;
function IPCLink(const P: TIPCPoint): string;
function IPCSaveNet(const FileName: string; out Err: string): Boolean;
function IPCLoadNet(const FileName: string; out Err: string): Boolean;
function IPCSaveIO(const FileName: string; out Err: string): Boolean;
function IPCLoadIO(const FileName: string; out Err: string): Boolean;
{ the value an Input point gives a name that is no part }
function IPCValue(const Name: string; out V: Single): Boolean;

type
  { a bare TCP peer for the tests: an outside server (Listen) or client }
  TIPCProbe = record
    LSock, CSock: PtrUInt;
    Buf: string;
    Up: Boolean;
  end;

procedure ProbeInit(out P: TIPCProbe);
function ProbeListen(var P: TIPCProbe; Port: Integer): Boolean;
function ProbeAccept(var P: TIPCProbe): Boolean;
function ProbeConnect(var P: TIPCProbe; Port: Integer): Boolean;
function ProbeSend(var P: TIPCProbe; const Line: string): Boolean;
function ProbeReadLine(var P: TIPCProbe; out Line: string): Boolean;
procedure ProbeClose(var P: TIPCProbe);

implementation

uses
  SysUtils, Math, WinSock2, flowchart;

type
  TConn = record
    Sock: TSocket;
    State: Byte;             { 0 none, 1 connecting, 2 up }
    InBuf, OutBuf: AnsiString;
    Name, Addr, Key, Err: string;
    Rx, Tx: Integer;
    RetryT, WaitT: Single;
    Fresh: Boolean;          { send it every output now }
  end;

var
  WSAOK: Boolean = False;
  Listener: TSocket = INVALID_SOCKET;
  ListenKey, ListenErr: string;
  ListenRetry: Single = 0;
  Clients: array[0..IPC_MAX_CLIENTS - 1] of TConn;
  TConns: array[0..IPC_MAX_TARGETS - 1] of TConn;
  RefreshT: Single = 0;

  FS_DOT: TFormatSettings;     { numbers with a dot, whatever the system uses }

{ ---------------------------------------------------------------- sockets }

procedure EnsureWSA;
var
  d: TWSAData;
begin
  if WSAOK then Exit;
  WSAOK := WSAStartup($0202, d) = 0;
end;

procedure NonBlocking(s: TSocket);
var
  arg: u_long;
begin
  arg := 1;
  ioctlsocket(s, Longint(FIONBIO), arg);
end;

procedure NoDelay(s: TSocket);
var
  one: Longint;
begin
  one := 1;
  setsockopt(s, IPPROTO_TCP, TCP_NODELAY, PChar(@one), SizeOf(one));
end;

function WouldBlock: Boolean;
var
  e: Integer;
begin
  e := WSAGetLastError;
  Result := (e = WSAEWOULDBLOCK) or (e = WSAEINPROGRESS);
end;

function ResolveHost(const Host: string; out Addr: u_long): Boolean;
var
  he: PHostEnt;
begin
  Addr := inet_addr(PChar(AnsiString(Host)));
  if Addr <> u_long(INADDR_NONE) then Exit(True);
  he := gethostbyname(PChar(AnsiString(Host)));
  Result := (he <> nil) and (he^.h_addr_list <> nil) and (he^.h_addr_list^ <> nil);
  if Result then Addr := PLongWord(he^.h_addr_list^)^;
end;

procedure CloseConn(var C: TConn);
begin
  if C.Sock <> INVALID_SOCKET then closesocket(C.Sock);
  C.Sock := INVALID_SOCKET;
  C.State := 0;
  C.InBuf := '';
  C.OutBuf := '';
end;

procedure Queue(var C: TConn; const Line: string);
begin
  if C.State <> 2 then Exit;
  if Length(C.OutBuf) > 1 shl 20 then Exit;     { the other end does not read: drop }
  C.OutBuf := C.OutBuf + Line + #10;
end;

{ send what is queued; False when the connection broke }
function Flush(var C: TConn): Boolean;
var
  n: Integer;
begin
  Result := True;
  while C.OutBuf <> '' do
  begin
    n := send(C.Sock, C.OutBuf[1], Length(C.OutBuf), 0);
    if n > 0 then Delete(C.OutBuf, 1, n)
    else
    begin
      if (n = SOCKET_ERROR) and WouldBlock then Exit(True);
      Exit(False);
    end;
  end;
end;

{ read what has come; False when the other end closed or the connection broke }
function Fill(var C: TConn): Boolean;
var
  buf: array[0..4095] of AnsiChar;
  n: Integer;
begin
  Result := True;
  repeat
    n := recv(C.Sock, buf, SizeOf(buf), 0);
    if n > 0 then
    begin
      SetLength(C.InBuf, Length(C.InBuf) + n);
      Move(buf, C.InBuf[Length(C.InBuf) - n + 1], n);
      if Length(C.InBuf) > 1 shl 20 then C.InBuf := '';
    end
    else if n = 0 then Exit(False)
    else
    begin
      if WouldBlock then Exit(True);
      Exit(False);
    end;
  until False;
end;

function NextLine(var Buf: AnsiString; out Line: string): Boolean;
var
  p: Integer;
begin
  p := Pos(#10, Buf);
  Result := p > 0;
  if not Result then Exit;
  Line := Copy(Buf, 1, p - 1);
  Delete(Buf, 1, p);
  if (Line <> '') and (Line[Length(Line)] = #13) then SetLength(Line, Length(Line) - 1);
end;

function SockAddrText(const a: TSockAddrIn): string;
var
  b: PByteArray;
begin
  b := @a.sin_addr;
  Result := Format('%d.%d.%d.%d:%d', [b^[0], b^[1], b^[2], b^[3], ntohs(a.sin_port)]);
end;

{ ---------------------------------------------------------------- settings }

procedure IPCDefaults;
begin
  IPCStopAll;
  IPCServerOn := False;
  IPCServerName := 'MaterialFlow';
  IPCServerBind := '127.0.0.1';
  IPCServerPort := IPC_DEFAULT_PORT;
  IPCMaxClients := 8;
  IPCClientOn := False;
  IPCClientName := 'MaterialFlow';
  FillChar(IPCTargets, SizeOf(IPCTargets), 0);
  FillChar(IPCPoints, SizeOf(IPCPoints), 0);
end;

function Clean(const s: string; MaxLen: Integer): string;
var
  k: Integer;
begin
  Result := Trim(s);
  for k := 1 to Length(Result) do
    if (Result[k] = '|') or (Result[k] < ' ') or (Result[k] = ' ') then Result[k] := '_';
  Result := Copy(Result, 1, MaxLen);
end;

function IPCAddTarget(const Name, Host: string; Port: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to IPC_MAX_TARGETS - 1 do
    if not IPCTargets[i].Used then
    begin
      IPCTargets[i].Used := True;
      IPCTargets[i].Enabled := True;
      IPCTargets[i].Name := Clean(Name, 24);
      IPCTargets[i].Host := Clean(Host, 60);
      IPCTargets[i].Port := EnsureRange(Port, 1, 65535);
      Exit(i);
    end;
  Result := -1;
end;

procedure IPCDeleteTarget(i: Integer);
begin
  if (i < 0) or (i >= IPC_MAX_TARGETS) then Exit;
  CloseConn(TConns[i]);
  FillChar(IPCTargets[i], SizeOf(TIPCTarget), 0);
end;

function IPCAddPoint(Side, Dir: Integer; const Name, Link, Peer: string): Integer;
var
  i: Integer;
begin
  for i := 0 to IPC_MAX_POINTS - 1 do
    if not IPCPoints[i].Used then
    begin
      FillChar(IPCPoints[i], SizeOf(TIPCPoint), 0);
      IPCPoints[i].Used := True;
      IPCPoints[i].Side := EnsureRange(Side, 0, 1);
      IPCPoints[i].Dir := EnsureRange(Dir, 0, 1);
      IPCPoints[i].Name := Clean(Name, 32);
      IPCPoints[i].Link := Clean(Link, 32);
      IPCPoints[i].Peer := Clean(Peer, 24);
      IPCPoints[i].Sent := NaN;
      Exit(i);
    end;
  Result := -1;
end;

procedure IPCDeletePoint(i: Integer);
begin
  if (i >= 0) and (i < IPC_MAX_POINTS) then FillChar(IPCPoints[i], SizeOf(TIPCPoint), 0);
end;

function IPCFindPoint(Side, Dir: Integer; const Name: string): Integer;
var
  i: Integer;
begin
  for i := 0 to IPC_MAX_POINTS - 1 do
    if IPCPoints[i].Used and (IPCPoints[i].Side = Side) and (IPCPoints[i].Dir = Dir) and SameText(IPCPoints[i].Name, Name) then
      Exit(i);
  Result := -1;
end;

function IPCPointCount(Side: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to IPC_MAX_POINTS - 1 do
    if IPCPoints[i].Used and (IPCPoints[i].Side = Side) then Inc(Result);
end;

function IPCLink(const P: TIPCPoint): string;
begin
  if P.Link <> '' then Result := P.Link else Result := P.Name;
end;

function Fields(const s: string; out F: array of string): Integer;
var
  rest: string;
  p: Integer;
begin
  Result := 0;
  rest := s + '|';
  while (rest <> '') and (Result <= High(F)) do
  begin
    p := Pos('|', rest);
    F[Result] := Copy(rest, 1, p - 1);
    Delete(rest, 1, p);
    Inc(Result);
  end;
end;

function IPCSaveNet(const FileName: string; out Err: string): Boolean;
var
  f: TextFile;
  i: Integer;
begin
  Err := '';
  try
    AssignFile(f, FileName);
    Rewrite(f);
    try
      WriteLn(f, '# Material Flow - IPC network (the server for many clients, the client of many servers)');
      WriteLn(f, 'server=', Ord(IPCServerOn));
      WriteLn(f, 'servername=', IPCServerName);
      WriteLn(f, 'bind=', IPCServerBind);
      WriteLn(f, 'port=', IPCServerPort);
      WriteLn(f, 'maxclients=', IPCMaxClients);
      WriteLn(f, 'client=', Ord(IPCClientOn));
      WriteLn(f, 'clientname=', IPCClientName);
      WriteLn(f, '# target=enabled|name|host|port');
      for i := 0 to IPC_MAX_TARGETS - 1 do
        with IPCTargets[i] do
          if Used then WriteLn(f, Format('target=%d|%s|%s|%d', [Ord(Enabled), Name, Host, Port]));
    finally
      CloseFile(f);
    end;
    Result := True;
  except
    on E: Exception do
    begin
      Err := E.Message;
      Result := False;
    end;
  end;
end;

function IPCLoadNet(const FileName: string; out Err: string): Boolean;
var
  f: TextFile;
  s, k, v: string;
  p, i: Integer;
  F4: array[0..3] of string;
begin
  Err := '';
  Result := False;
  if not FileExists(FileName) then
  begin
    Err := 'no file ' + FileName;
    Exit;
  end;
  IPCStopAll;
  FillChar(IPCTargets, SizeOf(IPCTargets), 0);
  try
    AssignFile(f, FileName);
    Reset(f);
    try
      while not EOF(f) do
      begin
        ReadLn(f, s);
        s := Trim(s);
        if (s = '') or (s[1] = '#') then Continue;
        p := Pos('=', s);
        if p < 2 then Continue;
        k := LowerCase(Trim(Copy(s, 1, p - 1)));
        v := Trim(Copy(s, p + 1, MaxInt));
        if k = 'server' then IPCServerOn := v = '1'
        else if k = 'servername' then IPCServerName := Clean(v, 24)
        else if k = 'bind' then IPCServerBind := Clean(v, 60)
        else if k = 'port' then IPCServerPort := EnsureRange(StrToIntDef(v, IPC_DEFAULT_PORT), 1, 65535)
        else if k = 'maxclients' then IPCMaxClients := EnsureRange(StrToIntDef(v, 8), 1, IPC_MAX_CLIENTS)
        else if k = 'client' then IPCClientOn := v = '1'
        else if k = 'clientname' then IPCClientName := Clean(v, 24)
        else if (k = 'target') and (Fields(v, F4) = 4) then
        begin
          i := IPCAddTarget(F4[1], F4[2], StrToIntDef(F4[3], IPC_DEFAULT_PORT));
          if i >= 0 then IPCTargets[i].Enabled := F4[0] = '1';
        end;
      end;
    finally
      CloseFile(f);
    end;
    Result := True;
  except
    on E: Exception do Err := E.Message;
  end;
end;

function IPCSaveIO(const FileName: string; out Err: string): Boolean;
var
  f: TextFile;
  i: Integer;
begin
  Err := '';
  try
    AssignFile(f, FileName);
    Rewrite(f);
    try
      WriteLn(f, '# Material Flow - IPC inputs and outputs');
      WriteLn(f, '# point=server|client | in|out | name on the wire | link (part in the layout, empty: the name) | peer (empty: all)');
      for i := 0 to IPC_MAX_POINTS - 1 do
        with IPCPoints[i] do
          if Used then
            WriteLn(f, Format('point=%s|%s|%s|%s|%s', [IPCSideNames[Side], IPCDirNames[Dir], Name, Link, Peer]));
    finally
      CloseFile(f);
    end;
    Result := True;
  except
    on E: Exception do
    begin
      Err := E.Message;
      Result := False;
    end;
  end;
end;

function IPCLoadIO(const FileName: string; out Err: string): Boolean;
var
  f: TextFile;
  s: string;
  p: Integer;
  F5: array[0..4] of string;
begin
  Err := '';
  Result := False;
  if not FileExists(FileName) then
  begin
    Err := 'no file ' + FileName;
    Exit;
  end;
  FillChar(IPCPoints, SizeOf(IPCPoints), 0);
  try
    AssignFile(f, FileName);
    Reset(f);
    try
      while not EOF(f) do
      begin
        ReadLn(f, s);
        s := Trim(s);
        if (s = '') or (s[1] = '#') then Continue;
        p := Pos('=', s);
        if (p < 2) or not SameText(Trim(Copy(s, 1, p - 1)), 'point') then Continue;
        if Fields(Copy(s, p + 1, MaxInt), F5) < 5 then Continue;
        if F5[2] = '' then Continue;
        IPCAddPoint(Ord(SameText(F5[0], 'client')), Ord(SameText(F5[1], 'out')), F5[2], F5[3], F5[4]);
      end;
    finally
      CloseFile(f);
    end;
    Result := True;
  except
    on E: Exception do Err := E.Message;
  end;
end;

{ ---------------------------------------------------------------- the values }

function NumText(v: Single): string;
begin
  if (Frac(v) = 0) and (Abs(v) < 1e9) then Result := IntToStr(Round(v))
  else Result := FloatToStrF(v, ffGeneral, 7, 4, FS_DOT);
end;

{ a line from connection C on side Side }
procedure Handle(var C: TConn; Side: Integer; const Line: string);
var
  Pt: ^TIPCPoint;
  s, cmd, nm, vs: string;
  p, i: Integer;
  v: Double;
begin
  s := Trim(Line);
  p := Pos(' ', s);
  if p = 0 then
  begin
    if SameText(s, 'PING') then Queue(C, 'PONG');
    Exit;
  end;
  cmd := UpperCase(Copy(s, 1, p - 1));
  s := Trim(Copy(s, p + 1, MaxInt));
  if cmd = 'HELLO' then
  begin
    if (Side = IPC_SERVER) or (C.Name = '') then C.Name := Clean(s, 24);
    Exit;
  end;
  if cmd <> 'SET' then Exit;
  p := Pos(' ', s);
  if p = 0 then Exit;
  nm := Copy(s, 1, p - 1);
  vs := Trim(Copy(s, p + 1, MaxInt));
  if not TryStrToFloat(vs, v, FS_DOT) then
  begin
    if SameText(vs, 'ON') or SameText(vs, 'TRUE') then v := 1
    else if SameText(vs, 'OFF') or SameText(vs, 'FALSE') then v := 0
    else Exit;
  end;
  for i := 0 to IPC_MAX_POINTS - 1 do
  begin
    Pt := @IPCPoints[i];
    if Pt^.Used and (Pt^.Side = Side) and (Pt^.Dir = IPC_IN) and SameText(Pt^.Name, nm) and
      ((Pt^.Peer = '') or SameText(Pt^.Peer, C.Name)) then
    begin
      Pt^.Value := v;
      Pt^.Known := True;
      Pt^.From := C.Name;
      Inc(Pt^.Count);
    end;
  end;
end;

procedure ReadLines(var C: TConn; Side: Integer; out Broken: Boolean);
var
  line: string;
begin
  Broken := not Fill(C);
  while NextLine(C.InBuf, line) do
  begin
    Inc(C.Rx);
    if Length(line) <= 512 then Handle(C, Side, line);
  end;
end;

{ the outputs of one side for connection C (named Peer): all of them when it is fresh or at the refresh, else what changed }
procedure SendOutputs(var C: TConn; Side: Integer; const PeerName: string; All: Boolean);
var
  i: Integer;
  P: ^TIPCPoint;
begin
  for i := 0 to IPC_MAX_POINTS - 1 do
  begin
    P := @IPCPoints[i];
    if P^.Used and (P^.Side = Side) and (P^.Dir = IPC_OUT) and P^.Known and ((P^.Peer = '') or SameText(P^.Peer, PeerName)) and
      (All or C.Fresh or IsNan(P^.Sent) or (Abs(P^.Value - P^.Sent) > 1e-6)) then
    begin
      Queue(C, 'SET ' + P^.Name + ' ' + NumText(P^.Value));
      Inc(C.Tx);
    end;
  end;
end;

{ ---------------------------------------------------------------- the server }

procedure CloseListener;
var
  i: Integer;
begin
  if Listener <> INVALID_SOCKET then closesocket(Listener);
  Listener := INVALID_SOCKET;
  ListenKey := '';
  for i := 0 to IPC_MAX_CLIENTS - 1 do CloseConn(Clients[i]);
end;

procedure OpenListener;
var
  a: TSockAddrIn;
  addr: u_long;
begin
  CloseListener;
  ListenErr := '';
  EnsureWSA;
  if not ResolveHost(IPCServerBind, addr) then
  begin
    ListenErr := 'bad address ' + IPCServerBind;
    Exit;
  end;
  Listener := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if Listener = INVALID_SOCKET then
  begin
    ListenErr := 'no socket';
    Exit;
  end;
  FillChar(a, SizeOf(a), 0);
  a.sin_family := AF_INET;
  a.sin_port := htons(IPCServerPort);
  a.sin_addr.S_addr := addr;
  if (bind(Listener, PSockAddr(@a), SizeOf(a)) <> 0) or (listen(Listener, 8) <> 0) then
  begin
    ListenErr := Format('port %d is in use (error %d)', [IPCServerPort, WSAGetLastError]);
    closesocket(Listener);
    Listener := INVALID_SOCKET;
    Exit;
  end;
  NonBlocking(Listener);
  ListenKey := Format('%s:%d', [IPCServerBind, IPCServerPort]);
end;

function FreeClient: Integer;
var
  i, n: Integer;
begin
  n := 0;
  Result := -1;
  for i := 0 to IPC_MAX_CLIENTS - 1 do
    if Clients[i].State = 2 then Inc(n)
    else if Result < 0 then Result := i;
  if n >= IPCMaxClients then Result := -1;
end;

procedure ServerStep(dt: Single; Refresh: Boolean);
var
  s: TSocket;
  a: TSockAddrIn;
  alen, i: Integer;
  broken: Boolean;
  full: AnsiString;
begin
  if not IPCServerOn then
  begin
    if Listener <> INVALID_SOCKET then CloseListener;
    ListenErr := '';
    Exit;
  end;
  if (Listener = INVALID_SOCKET) or (ListenKey <> Format('%s:%d', [IPCServerBind, IPCServerPort])) then
  begin
    ListenRetry := ListenRetry - dt;
    if (ListenRetry > 0) and (Listener = INVALID_SOCKET) and (ListenErr <> '') then Exit;
    OpenListener;
    ListenRetry := 2;
    if Listener = INVALID_SOCKET then Exit;
  end;
  { new clients }
  repeat
    alen := SizeOf(a);
    s := accept(Listener, PSockAddr(@a), @alen);
    if s = INVALID_SOCKET then Break;
    i := FreeClient;
    if i < 0 then
    begin
      full := 'ERR full' + #10;
      send(s, full[1], Length(full), 0);
      closesocket(s);
      Continue;
    end;
    NonBlocking(s);
    NoDelay(s);
    FillChar(Clients[i], SizeOf(TConn), 0);
    Clients[i].Sock := s;
    Clients[i].State := 2;
    Clients[i].Addr := SockAddrText(a);
    Clients[i].Fresh := True;
    Queue(Clients[i], 'HELLO ' + IPCServerName);
  until False;
  for i := 0 to IPC_MAX_CLIENTS - 1 do
    if Clients[i].State = 2 then
    begin
      ReadLines(Clients[i], IPC_SERVER, broken);
      if not broken then
      begin
        SendOutputs(Clients[i], IPC_SERVER, Clients[i].Name, Refresh);
        Clients[i].Fresh := False;
        broken := not Flush(Clients[i]);
      end;
      if broken then CloseConn(Clients[i]);
    end;
end;

{ ---------------------------------------------------------------- the client }

procedure StartConnect(var C: TConn; const T: TIPCTarget);
var
  a: TSockAddrIn;
  addr: u_long;
begin
  CloseConn(C);
  C.Err := '';
  EnsureWSA;
  if not ResolveHost(T.Host, addr) then
  begin
    C.Err := 'unknown host ' + T.Host;
    C.RetryT := 3;
    Exit;
  end;
  C.Sock := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if C.Sock = INVALID_SOCKET then
  begin
    C.Err := 'no socket';
    C.RetryT := 3;
    Exit;
  end;
  NonBlocking(C.Sock);
  NoDelay(C.Sock);
  FillChar(a, SizeOf(a), 0);
  a.sin_family := AF_INET;
  a.sin_port := htons(T.Port);
  a.sin_addr.S_addr := addr;
  C.Addr := Format('%s:%d', [T.Host, T.Port]);
  C.Key := Format('%s:%d', [T.Host, T.Port]);
  if connect(C.Sock, PSockAddr(@a), SizeOf(a)) = 0 then
  begin
    C.State := 2;
    C.Fresh := True;
    Queue(C, 'HELLO ' + IPCClientName);
  end
  else if WouldBlock then
  begin
    C.State := 1;
    C.WaitT := 0;
  end
  else
  begin
    C.Err := Format('cannot connect (error %d)', [WSAGetLastError]);
    CloseConn(C);
    C.RetryT := 2;
  end;
end;

{ a connection still being made: up, failed, or still waiting }
procedure CheckConnect(var C: TConn; dt: Single);
var
  wr, ex: TFDSet;
  tv: TTimeVal;
  e, elen: Longint;
begin
  FD_ZERO(wr);
  FD_ZERO(ex);
  FD_SET(C.Sock, wr);
  FD_SET(C.Sock, ex);
  tv.tv_sec := 0;
  tv.tv_usec := 0;
  if select(0, nil, @wr, @ex, @tv) > 0 then
  begin
    e := 0;
    elen := SizeOf(e);
    getsockopt(C.Sock, SOL_SOCKET, SO_ERROR, PChar(@e), elen);
    if FD_ISSET(C.Sock, ex) or (e <> 0) then
    begin
      CloseConn(C);
      if e = 0 then e := WSAECONNREFUSED;
      C.Err := Format('refused / unreachable (error %d)', [e]);
      C.RetryT := 2;
      Exit;
    end;
    C.State := 2;
    C.Fresh := True;
    C.Err := '';
    Queue(C, 'HELLO ' + IPCClientName);
    Exit;
  end;
  C.WaitT := C.WaitT + dt;
  if C.WaitT > 5 then
  begin
    CloseConn(C);
    C.Err := 'no answer';
    C.RetryT := 2;
  end;
end;

procedure ClientStep(dt: Single; Refresh: Boolean);
var
  i: Integer;
  broken: Boolean;
begin
  for i := 0 to IPC_MAX_TARGETS - 1 do
  begin
    if not (IPCClientOn and IPCTargets[i].Used and IPCTargets[i].Enabled) then
    begin
      if TConns[i].State <> 0 then CloseConn(TConns[i]);
      TConns[i].Err := '';
      TConns[i].RetryT := 0;
      Continue;
    end;
    { the address was changed: connect again }
    if (TConns[i].State <> 0) and (TConns[i].Key <> Format('%s:%d', [IPCTargets[i].Host, IPCTargets[i].Port])) then
      CloseConn(TConns[i]);
    case TConns[i].State of
      0:
        begin
          TConns[i].RetryT := TConns[i].RetryT - dt;
          if TConns[i].RetryT <= 0 then StartConnect(TConns[i], IPCTargets[i]);
        end;
      1: CheckConnect(TConns[i], dt);
    end;
    if TConns[i].State = 2 then
    begin
      if TConns[i].Name = '' then TConns[i].Name := IPCTargets[i].Name;
      ReadLines(TConns[i], IPC_CLIENT, broken);
      if not broken then
      begin
        SendOutputs(TConns[i], IPC_CLIENT, IPCTargets[i].Name, Refresh);
        TConns[i].Fresh := False;
        broken := not Flush(TConns[i]);
      end;
      if broken then
      begin
        CloseConn(TConns[i]);
        TConns[i].Err := 'the server closed the connection';
        TConns[i].RetryT := 1;
      end;
    end;
  end;
end;

{ ---------------------------------------------------------------- every frame }

procedure IPCStep(dt: Single);
var
  i: Integer;
  v: Single;
  u: string;
  b, refresh: Boolean;
begin
  { what the outputs give now }
  for i := 0 to IPC_MAX_POINTS - 1 do
    with IPCPoints[i] do
      if Used and (Dir = IPC_OUT) then
      begin
        Known := FlowRead(IPCLink(IPCPoints[i]), v, u, b);
        if Known then Value := v;
      end;
  RefreshT := RefreshT + dt;
  refresh := RefreshT >= 1;
  if refresh then RefreshT := 0;
  ServerStep(dt, refresh);
  ClientStep(dt, refresh);
  for i := 0 to IPC_MAX_POINTS - 1 do
    with IPCPoints[i] do
      if Used and (Dir = IPC_OUT) and Known then Sent := Value;
  { the inputs work the layout }
  for i := 0 to IPC_MAX_POINTS - 1 do
    with IPCPoints[i] do
      if Used and (Dir = IPC_IN) and Known then
        Virtual := not WriteValue(IPCLink(IPCPoints[i]), Value);
end;

procedure IPCStopAll;
var
  i: Integer;
begin
  CloseListener;
  ListenErr := '';
  for i := 0 to IPC_MAX_TARGETS - 1 do
  begin
    CloseConn(TConns[i]);
    TConns[i].Err := '';
    TConns[i].RetryT := 0;
  end;
end;

function IPCServerListening: Boolean;
begin
  Result := Listener <> INVALID_SOCKET;
end;

function IPCServerState: string;
begin
  if not IPCServerOn then Result := 'off'
  else if Listener <> INVALID_SOCKET then Result := Format('listening on %s - %d client(s)', [ListenKey, IPCClientCount])
  else if ListenErr <> '' then Result := 'error: ' + ListenErr
  else Result := 'starting';
end;

function IPCClientCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to IPC_MAX_CLIENTS - 1 do
    if Clients[i].State = 2 then Inc(Result);
end;

function IPCClientInfo(i: Integer; out Info: TIPCConnInfo): Boolean;
var
  k, n: Integer;
begin
  n := 0;
  for k := 0 to IPC_MAX_CLIENTS - 1 do
    if Clients[k].State = 2 then
    begin
      if n = i then
      begin
        Info.Name := Clients[k].Name;
        Info.Addr := Clients[k].Addr;
        Info.State := 'up';
        Info.Rx := Clients[k].Rx;
        Info.Tx := Clients[k].Tx;
        Exit(True);
      end;
      Inc(n);
    end;
  Result := False;
end;

function IPCTargetConnected(i: Integer): Boolean;
begin
  Result := (i >= 0) and (i < IPC_MAX_TARGETS) and (TConns[i].State = 2);
end;

function IPCTargetState(i: Integer): string;
begin
  if (i < 0) or (i >= IPC_MAX_TARGETS) or not IPCTargets[i].Used then Exit('');
  if not IPCClientOn then Exit('client off');
  if not IPCTargets[i].Enabled then Exit('disabled');
  case TConns[i].State of
    2: Result := Format('connected (%s) rx %d tx %d', [TConns[i].Name, TConns[i].Rx, TConns[i].Tx]);
    1: Result := 'connecting';
  else
    if TConns[i].Err <> '' then Result := TConns[i].Err + ', retrying' else Result := 'waiting';
  end;
end;

function IPCValue(const Name: string; out V: Single): Boolean;
var
  i: Integer;
begin
  V := 0;
  Result := False;
  if Name = '' then Exit;
  for i := 0 to IPC_MAX_POINTS - 1 do
    if IPCPoints[i].Used and (IPCPoints[i].Dir = IPC_IN) and IPCPoints[i].Known and IPCPoints[i].Virtual and
      SameText(IPCLink(IPCPoints[i]), Name) then
    begin
      V := IPCPoints[i].Value;
      Exit(True);
    end;
end;

{ ---------------------------------------------------------------- the test peer }

procedure ProbeInit(out P: TIPCProbe);
begin
  P.LSock := INVALID_SOCKET;
  P.CSock := INVALID_SOCKET;
  P.Buf := '';
  P.Up := False;
end;

function ProbeListen(var P: TIPCProbe; Port: Integer): Boolean;
var
  a: TSockAddrIn;
begin
  EnsureWSA;
  P.LSock := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  FillChar(a, SizeOf(a), 0);
  a.sin_family := AF_INET;
  a.sin_port := htons(Port);
  a.sin_addr.S_addr := inet_addr('127.0.0.1');
  Result := (P.LSock <> INVALID_SOCKET) and (bind(P.LSock, PSockAddr(@a), SizeOf(a)) = 0) and (listen(P.LSock, 4) = 0);
  if Result then NonBlocking(P.LSock);
end;

function ProbeAccept(var P: TIPCProbe): Boolean;
var
  s: TSocket;
begin
  s := accept(P.LSock, nil, nil);
  Result := s <> INVALID_SOCKET;
  if Result then
  begin
    NonBlocking(s);
    P.CSock := s;
    P.Up := True;
  end;
end;

function ProbeConnect(var P: TIPCProbe; Port: Integer): Boolean;
var
  a: TSockAddrIn;
begin
  EnsureWSA;
  P.CSock := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  FillChar(a, SizeOf(a), 0);
  a.sin_family := AF_INET;
  a.sin_port := htons(Port);
  a.sin_addr.S_addr := inet_addr('127.0.0.1');
  { a blocking connect on this machine: it is there at once or not at all }
  Result := (P.CSock <> INVALID_SOCKET) and (connect(P.CSock, PSockAddr(@a), SizeOf(a)) = 0);
  if Result then
  begin
    NonBlocking(P.CSock);
    P.Up := True;
  end;
end;

function ProbeSend(var P: TIPCProbe; const Line: string): Boolean;
var
  s: AnsiString;
begin
  s := Line + #10;
  Result := P.Up and (send(P.CSock, s[1], Length(s), 0) = Length(s));
end;

function ProbeReadLine(var P: TIPCProbe; out Line: string): Boolean;
var
  buf: array[0..4095] of AnsiChar;
  n, k: Integer;
begin
  Line := '';
  if P.Up then
    repeat
      n := recv(P.CSock, buf, SizeOf(buf), 0);
      if n > 0 then
      begin
        k := Length(P.Buf);
        SetLength(P.Buf, k + n);
        Move(buf, P.Buf[k + 1], n);
      end
      else if n = 0 then P.Up := False;
    until n <= 0;
  k := Pos(#10, P.Buf);
  Result := k > 0;
  if Result then
  begin
    Line := Copy(P.Buf, 1, k - 1);
    Delete(P.Buf, 1, k);
  end;
end;

procedure ProbeClose(var P: TIPCProbe);
begin
  if P.CSock <> INVALID_SOCKET then closesocket(P.CSock);
  if P.LSock <> INVALID_SOCKET then closesocket(P.LSock);
  ProbeInit(P);
end;

function NetValueHook(const Name: string; out V: Single): Boolean;
begin
  Result := IPCValue(Name, V);
end;

var
  k: Integer;

initialization
  FS_DOT := DefaultFormatSettings;
  FS_DOT.DecimalSeparator := '.';
  for k := 0 to IPC_MAX_CLIENTS - 1 do Clients[k].Sock := INVALID_SOCKET;
  for k := 0 to IPC_MAX_TARGETS - 1 do TConns[k].Sock := INVALID_SOCKET;
  ExtNetValue := @NetValueHook;

finalization
  IPCStopAll;
  if WSAOK then WSACleanup;

end.
