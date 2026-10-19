program mfmcp;

{ The Material Flow MCP server: makes the simulator a part of Claude Code on this PC.

  Claude Code starts it (stdio, JSON-RPC 2.0, one message per line); its tools are the AI bridge's
  commands. Each call goes to the running program over HTTP on 127.0.0.1 with the port and token the
  program wrote in aichat\bridge.json (menu AI Chat > Claude Code link); when the program is not running,
  it starts it (MaterialFlow.exe next to this file) and waits for it. Screenshots come back as PNG images.

  Register it with Claude Code:  claude mcp add material-flow -- "<folder>\mfmcp.exe"
  (or the .mcp.json in the project folder). }

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, fpjson, jsonparser, fphttpclient, base64, Windows, ShellApi, fpimage, fpreadbmp, fpwritepng;

const
  SERVER_NAME = 'material-flow';
  SERVER_VERSION = '1.0';
  INSTRUCTIONS =
    'Material Flow SDL3 is a 2D simulator of material flow and plants on this PC (pipes, blowers, feeders, ' +
    'silos, buckets, conveyors, vibratory feeders, electrical ladder circuits, pneumatics, hydraulics, sensors, ' +
    'PID controllers, flow charts, timelines, trend charts, tables, several pages). These tools work the running ' +
    'program (it is started when needed). Before building call mf_help (coordinates, every build step, part names) ' +
    'and mf_status; to learn the .mflow format read one example close to the task (mf_examples n). Build in a few ' +
    'large mf_build calls, check with mf_screenshot, fix what is wrong. A build is one undo step for the user ' +
    '(Ctrl+Z); loading a layout or example keeps the old one as a backup (mf_restore_backup). Save the user''s work ' +
    'to a file with mf_get_layout (the .mflow text) when asked.';

var
  Port: Integer = 0;
  Token: string = '';

function Dir: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

{ aichat\bridge.json: the running program's port and token }
function ReadInfo: Boolean;
var
  sl: TStringList;
  d: TJSONData;
begin
  Result := False;
  if not FileExists(Dir + 'aichat\bridge.json') then Exit;
  sl := TStringList.Create;
  try
    try
      sl.LoadFromFile(Dir + 'aichat\bridge.json');
      d := GetJSON(sl.Text);
      try
        Port := TJSONObject(d).Get('port', 0);
        Token := TJSONObject(d).Get('token', '');
        Result := (Port > 0) and (Token <> '');
      finally
        d.Free;
      end;
    except
      Result := False;
    end;
  finally
    sl.Free;
  end;
end;

{ one command to the program; False when it does not answer }
function Post(const Body: string; out Resp: string): Boolean;
var
  c: TFPHTTPClient;
  rs: TStringStream;
begin
  Result := False;
  Resp := '';
  if Port <= 0 then Exit;
  c := TFPHTTPClient.Create(nil);
  rs := TStringStream.Create(Body);
  try
    try
      c.ConnectTimeout := 3000;
      c.IOTimeout := 120000;
      c.AddHeader('Content-Type', 'application/json');
      c.AddHeader('X-MF-Token', Token);
      c.RequestBody := rs;
      Resp := c.Post(Format('http://127.0.0.1:%d/api', [Port]));
      Result := c.ResponseStatusCode = 200;
    except
      Result := False;
    end;
  finally
    rs.Free;
    c.Free;
  end;
end;

{ the program is there and answers; started when it is not }
function EnsureProgram(out Err: string): Boolean;
var
  r: string;
  k: Integer;
begin
  Err := '';
  if ReadInfo and Post('{"cmd":"status"}', r) then Exit(True);
  if not FileExists(Dir + 'MaterialFlow.exe') then
  begin
    Err := 'MaterialFlow.exe is not next to mfmcp.exe (' + Dir + ')';
    Exit(False);
  end;
  if ShellExecuteW(0, 'open', PWideChar(UnicodeString(Dir + 'MaterialFlow.exe')), nil, PWideChar(UnicodeString(Dir)),
    SW_SHOWNORMAL) <= 32 then
  begin
    Err := 'could not start MaterialFlow.exe';
    Exit(False);
  end;
  for k := 1 to 60 do
  begin
    Sleep(500);
    if ReadInfo and Post('{"cmd":"status"}', r) then Exit(True);
  end;
  Err := 'Material Flow did not answer - is its link on? (menu AI Chat > Claude Code link)';
  Result := False;
end;

{ a BMP (base64) as a PNG (base64) }
function BmpToPng(const B64: string): string;
var
  img: TFPMemoryImage;
  src, dst: TMemoryStream;
  raw, png: string;
begin
  Result := '';
  raw := DecodeStringBase64(B64);
  src := TMemoryStream.Create;
  dst := TMemoryStream.Create;
  img := TFPMemoryImage.Create(1, 1);
  try
    try
      if raw <> '' then src.WriteBuffer(raw[1], Length(raw));
      src.Position := 0;
      img.LoadFromStream(src, TFPReaderBMP.Create);
      img.SaveToStream(dst, TFPWriterPNG.Create);
      SetLength(png, dst.Size);
      if dst.Size > 0 then Move(dst.Memory^, png[1], dst.Size);
      Result := EncodeStringBase64(png);
    except
      Result := '';
    end;
  finally
    img.Free;
    src.Free;
    dst.Free;
  end;
end;

procedure AddTool(A: TJSONArray; const Name, Cmd, Desc, Schema: string);
var
  o: TJSONObject;
begin
  o := TJSONObject.Create;
  o.Add('name', Name);
  o.Add('description', Desc);
  o.Add('inputSchema', GetJSON(Schema));
  A.Add(o);
end;

const
  EMPTY = '{"type":"object","properties":{}}';

function ToolList: TJSONArray;
begin
  Result := TJSONArray.Create;
  AddTool(Result, 'mf_help', 'help', 'How to build in Material Flow: coordinates, every build step (op) with its fields, the part and equipment names. Read it before building.', EMPTY);
  AddTool(Result, 'mf_status', 'status', 'The program now: layout, pages, current page and layer, grid size, canvas, running or not, counts.', EMPTY);
  AddTool(Result, 'mf_get_layout', 'get_layout', 'The whole layout (all pages) as .mflow text - to save the user''s work to a file, or to study it.', EMPTY);
  AddTool(Result, 'mf_load_layout', 'load_layout', 'Replace the layout with .mflow text (the old one is kept as a backup).',
    '{"type":"object","properties":{"mflow":{"type":"string"}},"required":["mflow"]}');
  AddTool(Result, 'mf_restore_backup', 'restore_backup', 'Go back to the layout from before the last load.', EMPTY);
  AddTool(Result, 'mf_examples', 'examples', 'Without n: the list of built-in examples. With n: that example''s .mflow text (long: read one only when needed).',
    '{"type":"object","properties":{"n":{"type":"integer"}}}');
  AddTool(Result, 'mf_load_example', 'load_example', 'Open built-in example n (the old layout is kept as a backup).',
    '{"type":"object","properties":{"n":{"type":"integer"}},"required":["n"]}');
  AddTool(Result, 'mf_build', 'build', 'Build on the current page: a list of steps done in order, e.g. {op:"pipe",x1,y1,x2,y2}, {op:"device",kind,x,y}, ' +
    '{op:"equip",kind,x,y,name}, {op:"label",x,y,text}, {op:"table",...}. See mf_help for every op. Each step answers ok or its error. One undo step.',
    '{"type":"object","properties":{"ops":{"type":"array","items":{"type":"object"}}},"required":["ops"]}');
  AddTool(Result, 'mf_run', 'run', 'Start (on=true) or stop (on=false) the simulation.',
    '{"type":"object","properties":{"on":{"type":"boolean"}},"required":["on"]}');
  AddTool(Result, 'mf_read', 'read', 'Read values by name: equipment, tags, sensors, switches (1 on / 0 off), plant bus names.',
    '{"type":"object","properties":{"names":{"type":"array","items":{"type":"string"}}},"required":["names"]}');
  AddTool(Result, 'mf_write', 'write', 'Write a value to a part by name (a set point, a valve %, 1/0 for on/off...).',
    '{"type":"object","properties":{"name":{"type":"string"},"value":{"type":"number"}},"required":["name","value"]}');
  AddTool(Result, 'mf_page', 'page', 'Go to page n (1-based), or make a new page with the name in "new".',
    '{"type":"object","properties":{"n":{"type":"integer"},"new":{"type":"string"}}}');
  AddTool(Result, 'mf_screenshot', 'screenshot', 'A picture of the program window now (to check your work).', EMPTY);
end;

function CmdOf(const Tool: string): string;
begin
  if Copy(Tool, 1, 3) = 'mf_' then Result := Copy(Tool, 4, MaxInt) else Result := '';
  if Result = 'get_layout' then Exit;
end;

function TextContent(const S: string; IsError: Boolean): TJSONObject;
var
  a: TJSONArray;
  t: TJSONObject;
begin
  Result := TJSONObject.Create;
  a := TJSONArray.Create;
  t := TJSONObject.Create;
  t.Add('type', 'text');
  t.Add('text', S);
  a.Add(t);
  Result.Add('content', a);
  Result.Add('isError', IsError);
end;

{ tools/call }
function CallTool(Params: TJSONObject): TJSONObject;
var
  name, cmd, err, resp, png: string;
  args, req: TJSONObject;
  d, r: TJSONData;
  a: TJSONArray;
  o: TJSONObject;
  ok: Boolean;
begin
  name := Params.Get('name', '');
  cmd := CmdOf(name);
  if (cmd = '') or (Pos(cmd + ',', 'help,status,get_layout,load_layout,restore_backup,examples,load_example,build,run,read,write,page,screenshot,') = 0) then
    Exit(TextContent('unknown tool ' + name, True));
  if not EnsureProgram(err) then Exit(TextContent(err, True));
  d := Params.Find('arguments');
  if (d <> nil) and (d.JSONType = jtObject) then req := TJSONObject(d.Clone) else req := TJSONObject.Create;
  try
    req.Delete('cmd');
    req.Add('cmd', cmd);
    if not Post(req.AsJSON, resp) then Exit(TextContent('Material Flow did not answer: ' + Copy(resp, 1, 300), True));
  finally
    req.Free;
  end;
  try
    r := GetJSON(resp);
  except
    Exit(TextContent(resp, True));
  end;
  try
    ok := (r is TJSONObject) and TJSONObject(r).Get('ok', False);
    if (cmd = 'screenshot') and ok then
    begin
      png := BmpToPng(TJSONObject(r).Get('bmp', ''));
      if png = '' then Exit(TextContent('the screenshot could not be turned into a PNG', True));
      Result := TJSONObject.Create;
      a := TJSONArray.Create;
      o := TJSONObject.Create;
      o.Add('type', 'image');
      o.Add('data', png);
      o.Add('mimeType', 'image/png');
      a.Add(o);
      o := TJSONObject.Create;
      o.Add('type', 'text');
      o.Add('text', 'The Material Flow window now.');
      a.Add(o);
      Result.Add('content', a);
      Exit;
    end;
    { the .mflow text and the help as plain text, the rest as it came }
    if ok and (cmd = 'get_layout') then Exit(TextContent(TJSONObject(r).Get('mflow', ''), False));
    if ok and (cmd = 'help') then Exit(TextContent(TJSONObject(r).Get('text', ''), False));
    if ok and (cmd = 'examples') and (TJSONObject(r).Find('mflow') <> nil) then
      Exit(TextContent(TJSONObject(r).Get('title', '') + LineEnding + TJSONObject(r).Get('mflow', ''), False));
    Result := TextContent(resp, not ok);
  finally
    r.Free;
  end;
end;

procedure Send(Resp: TJSONObject);
begin
  WriteLn(Resp.AsJSON);
  Flush(Output);
  Resp.Free;
end;

procedure Reply(Id: TJSONData; Res: TJSONData);
var
  o: TJSONObject;
begin
  o := TJSONObject.Create;
  o.Add('jsonrpc', '2.0');
  o.Add('id', Id.Clone);
  o.Add('result', Res);
  Send(o);
end;

procedure ReplyError(Id: TJSONData; Code: Integer; const Msg: string);
var
  o, e: TJSONObject;
begin
  o := TJSONObject.Create;
  o.Add('jsonrpc', '2.0');
  if Id <> nil then o.Add('id', Id.Clone) else o.Add('id', TJSONNull.Create);
  e := TJSONObject.Create;
  e.Add('code', Code);
  e.Add('message', Msg);
  o.Add('error', e);
  Send(o);
end;

procedure Handle(const Line: string);
var
  d, id, p: TJSONData;
  m: TJSONObject;
  method: string;
  res, caps, info: TJSONObject;
begin
  try
    d := GetJSON(Line);
  except
    ReplyError(nil, -32700, 'parse error');
    Exit;
  end;
  try
    if not (d is TJSONObject) then Exit;
    m := TJSONObject(d);
    method := m.Get('method', '');
    id := m.Find('id');
    p := m.Find('params');
    if id = nil then Exit;   { a notification: nothing to answer }
    if method = 'initialize' then
    begin
      res := TJSONObject.Create;
      if (p is TJSONObject) and (TJSONObject(p).Find('protocolVersion') <> nil) then
        res.Add('protocolVersion', TJSONObject(p).Get('protocolVersion', '2025-06-18'))
      else
        res.Add('protocolVersion', '2025-06-18');
      caps := TJSONObject.Create;
      caps.Add('tools', TJSONObject.Create);
      res.Add('capabilities', caps);
      info := TJSONObject.Create;
      info.Add('name', SERVER_NAME);
      info.Add('version', SERVER_VERSION);
      res.Add('serverInfo', info);
      res.Add('instructions', INSTRUCTIONS);
      Reply(id, res);
    end
    else if method = 'ping' then
      Reply(id, TJSONObject.Create)
    else if method = 'tools/list' then
    begin
      res := TJSONObject.Create;
      res.Add('tools', ToolList);
      Reply(id, res);
    end
    else if method = 'tools/call' then
    begin
      if p is TJSONObject then Reply(id, CallTool(TJSONObject(p)))
      else ReplyError(id, -32602, 'params please');
    end
    else
      ReplyError(id, -32601, 'no method ' + method);
  finally
    d.Free;
  end;
end;

var
  line: string;
begin
  { UTF-8 in, UTF-8 out, untouched }
  DefaultSystemCodePage := CP_UTF8;
  SetTextCodePage(Input, CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
  while not EOF(Input) do
  begin
    ReadLn(Input, line);
    if Trim(line) <> '' then Handle(line);
  end;
end.
