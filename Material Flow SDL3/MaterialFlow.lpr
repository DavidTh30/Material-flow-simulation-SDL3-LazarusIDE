program MaterialFlow;

{ Material flow simulator - SDL3 + Free Pascal / Lazarus.
  SDL3.dll must sit next to the executable. }

{$mode objfpc}{$H+}
{$APPTYPE GUI}

uses
  SysUtils, sdl3min, simcore, layoutio, mfexamples, mftheme, edithist, mfapp;

procedure DumpError(E: Exception);
var
  f: TextFile;
  i: Integer;
  Frames: PPointer;
begin
  if ParamStr(1) = '--shot' then
    AssignFile(f, ParamStr(3) + '.err')
  else
    AssignFile(f, 'export.err');
  Rewrite(f);
  WriteLn(f, E.ClassName, ': ', E.Message);
  WriteLn(f, BackTraceStrFunc(ExceptAddr));
  Frames := ExceptFrames;
  for i := 0 to ExceptFrameCount - 1 do
    WriteLn(f, BackTraceStrFunc(Frames[i]));
  CloseFile(f);
end;

begin
  try
    RunApp;
  except
    on E: Exception do
    begin
      if (ParamStr(1) = '--shot') or (ParamStr(1) = '--export-examples') or (ParamStr(1) = '--selftest') then
        DumpError(E)
      else
        SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, 'Material Flow', PAnsiChar(AnsiString(E.Message)), nil);
    end;
  end;
end.
