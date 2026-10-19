unit aichat;

{ AI Chat: a window of its own, apart from the program. It is the page
  aichat\index.html next to the program, opened in Microsoft Edge as an app
  window (no address bar, its own profile in aichat\profile, so its API key
  stays there); Chrome when there is no Edge, else the default browser. The
  page talks to the Anthropic API itself; through the AI bridge (aibridge) it
  also works this program: its URL carries the bridge's port and token.

  It also prints a page to a PDF with Edge in the background (headless): the
  chat exported as a PDF keeps its text as text and its images as images. }

{$mode objfpc}{$H+}

interface

const
  AICHAT_PAGE = 'aichat\index.html';
  AICHAT_PROFILE = 'aichat\profile';
  AICHAT_WORK = 'aichat\work\';

{ the page's path and its file: URL (with the bridge in its #fragment when Port > 0) }
function AIChatPage: string;
function AIChatURL(Port: Integer = 0; const Token: string = ''): string;
{ the command line for an app window of the page in a Chromium browser }
function AIChatArgs(Port: Integer = 0; const Token: string = ''): string;
{ open it; DefaultBrowser: in the default browser; False (and Err) when it cannot }
function OpenAIChat(DefaultBrowser: Boolean; Port: Integer; const Token: string; out Err: string): Boolean;
{ the folder the AI bridge works in (made when needed) }
function AIWorkDir: string;
{ Edge prints an HTML file to a PDF in the background: the process (0 when it could not start) }
function StartPrintPDF(const HtmlFile, PdfFile: string): PtrUInt;
{ the printing is over (or there is none) }
function PrintDone(H: PtrUInt): Boolean;
function EdgePath: string;

implementation

uses
  SysUtils, Windows, ShellApi;

function AIChatPage: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + AICHAT_PAGE;
end;

function FileURL(const Path: string): string;
var
  s: string;
  k: Integer;
begin
  s := StringReplace(Path, '\', '/', [rfReplaceAll]);
  Result := '';
  for k := 1 to Length(s) do
    if s[k] = ' ' then Result := Result + '%20'
    else if s[k] = '#' then Result := Result + '%23'
    else Result := Result + s[k];
  Result := 'file:///' + Result;
end;

function AIChatURL(Port: Integer; const Token: string): string;
begin
  Result := FileURL(AIChatPage);
  if Port > 0 then Result := Result + Format('#bridge=%d&token=%s', [Port, Token]);
end;

function AIChatArgs(Port: Integer; const Token: string): string;
begin
  Result := Format('--app="%s" --user-data-dir="%s" --window-size=480,676 --no-first-run --no-default-browser-check',
    [AIChatURL(Port, Token), ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)) + AICHAT_PROFILE)]);
end;

function Run(const Exe, Args: string): Boolean;
begin
  Result := ShellExecuteW(0, 'open', PWideChar(UnicodeString(Exe)), PWideChar(UnicodeString(Args)), nil, SW_SHOWNORMAL) > 32;
end;

function OpenAIChat(DefaultBrowser: Boolean; Port: Integer; const Token: string; out Err: string): Boolean;
begin
  Err := '';
  if not FileExists(AIChatPage) then
  begin
    Err := 'the chat page is missing: ' + AIChatPage;
    Exit(False);
  end;
  if not DefaultBrowser then
  begin
    if Run('msedge.exe', AIChatArgs(Port, Token)) then Exit(True);
    if Run('chrome.exe', AIChatArgs(Port, Token)) then Exit(True);
  end;
  Result := Run(AIChatPage, '');
  if not Result then Err := 'no browser could open ' + AIChatPage;
end;

function AIWorkDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + AICHAT_WORK;
  ForceDirectories(Result);
end;

function EdgePath: string;
const
  Places: array[0..2] of string = ('C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Google\Chrome\Application\chrome.exe');
var
  k: Integer;
begin
  for k := 0 to High(Places) do
    if FileExists(Places[k]) then Exit(Places[k]);
  Result := '';
end;

function StartPrintPDF(const HtmlFile, PdfFile: string): PtrUInt;
var
  si: Windows.STARTUPINFOW;
  pi: Windows.PROCESS_INFORMATION;
  cmd: UnicodeString;
  exe: string;
begin
  Result := 0;
  exe := EdgePath;
  if exe = '' then Exit;
  SysUtils.DeleteFile(PdfFile);
  cmd := UnicodeString(Format('"%s" --headless --disable-gpu --no-pdf-header-footer --no-first-run --user-data-dir="%s" ' +
    '--print-to-pdf="%s" "%s"', [exe, ExcludeTrailingPathDelimiter(AIWorkDir + 'printprofile'), PdfFile, FileURL(HtmlFile)]));
  FillChar(si, SizeOf(si), 0);
  si.cb := SizeOf(si);
  si.dwFlags := STARTF_USESHOWWINDOW;
  si.wShowWindow := SW_HIDE;
  FillChar(pi, SizeOf(pi), 0);
  if CreateProcessW(nil, PWideChar(cmd), nil, nil, False, CREATE_NO_WINDOW, nil, nil, si, pi) then
  begin
    CloseHandle(pi.hThread);
    Result := PtrUInt(pi.hProcess);
  end;
end;

function PrintDone(H: PtrUInt): Boolean;
begin
  if H = 0 then Exit(True);
  Result := WaitForSingleObject(THandle(H), 0) <> WAIT_TIMEOUT;
  if Result then CloseHandle(THandle(H));
end;

end.
