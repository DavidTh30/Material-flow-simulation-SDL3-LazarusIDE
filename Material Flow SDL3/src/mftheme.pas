unit mftheme;

{ Colour themes. Each theme is derived from a handful of base colours so all
  UI, pipe and bucket colours stay consistent. }

{$mode objfpc}{$H+}

interface

type
  TRGB = record
    R, G, B: Byte;
  end;

  TTheme = record
    Name: string;
    Light: Boolean;
    CanvasBg, GridLine, Floor: TRGB;
    PanelBg, PanelLine, Title, Text, TextDim, Hint, HeaderTxt, HeaderLine: TRGB;
    BtnBg, BtnHot, BtnSel, BtnBorder, BtnSelBorder, BtnText, BtnSelText: TRGB;
    SliderTrack, SliderFill, SliderKnob: TRGB;
    PipeWall, PipeHub, PipeFlange, PipeBore, TankBg, TankRim: TRGB;
    BucketBack, BucketWall, BucketRim, BucketText: TRGB;
    Select, Hover, Paste: TRGB;
    MenuBg, MenuBorder, MenuHot, MenuSep, MenuKey, MenuDisabled: TRGB;
    OverlayBg, StatusOk, StatusErr: TRGB;
    Air, Fluff: TRGB;
    AirAlpha: Byte;
  end;

const
  THEME_COUNT = 7;

var
  Themes: array[0..THEME_COUNT - 1] of TTheme;
  Th: TTheme;            { the active theme }
  ThemeIndex: Integer = 0;

procedure SelectTheme(i: Integer);
procedure LoadThemeSetting(const FileName: string);
procedure SaveThemeSetting(const FileName: string);

implementation

uses
  SysUtils;

function RGB(r, g, b: Byte): TRGB;
begin
  Result.R := r;
  Result.G := g;
  Result.B := b;
end;

function Mix(const a, b: TRGB; t: Single): TRGB;
begin
  Result.R := Round(a.R + (b.R - a.R) * t);
  Result.G := Round(a.G + (b.G - a.G) * t);
  Result.B := Round(a.B + (b.B - a.B) * t);
end;

function MakeTheme(const AName: string; Canvas, Panel, Accent, Txt, Wall, Flr: TRGB; IsLight: Boolean): TTheme;
begin
  with Result do
  begin
    Name := AName;
    Light := IsLight;
    CanvasBg := Canvas;
    GridLine := Mix(Canvas, Txt, 0.06);
    Floor := Flr;
    PanelBg := Panel;
    PanelLine := Mix(Panel, Txt, 0.25);
    Title := Accent;
    Text := Txt;
    TextDim := Mix(Txt, Panel, 0.3);
    if IsLight then Hint := RGB(30, 130, 60) else Hint := RGB(140, 210, 150);
    HeaderTxt := Mix(Accent, Txt, 0.2);
    HeaderLine := Mix(Panel, Txt, 0.18);
    BtnBg := Mix(Panel, Txt, 0.1);
    BtnHot := Mix(Panel, Txt, 0.2);
    BtnSel := Mix(Panel, Accent, 0.6);
    BtnBorder := Mix(Panel, Txt, 0.28);
    BtnSelBorder := Accent;
    BtnText := Txt;
    if IsLight then BtnSelText := RGB(255, 255, 255) else BtnSelText := Txt;
    SliderTrack := Mix(Panel, Txt, 0.14);
    SliderFill := Accent;
    SliderKnob := Mix(Txt, Panel, 0.1);
    PipeWall := Wall;
    PipeHub := Mix(Wall, Txt, 0.15);
    PipeFlange := Mix(Wall, Txt, 0.25);
    if IsLight then
    begin
      PipeBore := Mix(Canvas, Wall, 0.18);
      TankBg := Mix(Canvas, Wall, 0.3);
    end
    else
    begin
      PipeBore := Mix(Canvas, Wall, 0.08);
      TankBg := Mix(Canvas, Wall, 0.12);
    end;
    TankRim := Mix(Wall, Txt, 0.5);
    BucketBack := Mix(Canvas, Wall, 0.12);
    BucketWall := Mix(Wall, Txt, 0.35);
    BucketRim := Mix(Wall, Txt, 0.6);
    BucketText := Txt;
    if IsLight then Select := RGB(225, 120, 0) else Select := RGB(255, 220, 60);
    Hover := Txt;
    if IsLight then Paste := RGB(0, 150, 190) else Paste := RGB(80, 230, 255);
    MenuBg := Mix(Panel, Txt, 0.05);
    MenuBorder := Mix(Panel, Txt, 0.4);
    MenuHot := BtnSel;
    MenuSep := HeaderLine;
    MenuKey := Mix(Txt, Panel, 0.35);
    MenuDisabled := Mix(Txt, Panel, 0.6);
    OverlayBg := Panel;
    if IsLight then
    begin
      StatusOk := RGB(20, 130, 40);
      StatusErr := RGB(200, 40, 30);
      Air := RGB(60, 130, 200);
      AirAlpha := 120;
      Fluff := RGB(215, 120, 175);
    end
    else
    begin
      StatusOk := RGB(140, 230, 150);
      StatusErr := RGB(255, 110, 90);
      Air := RGB(190, 225, 255);
      AirAlpha := 80;
      Fluff := RGB(245, 220, 235);
    end;
  end;
end;

procedure SelectTheme(i: Integer);
begin
  if (i < 0) or (i >= THEME_COUNT) then i := 0;
  ThemeIndex := i;
  Th := Themes[i];
end;

procedure LoadThemeSetting(const FileName: string);
var
  f: TextFile;
  s: string;
begin
  if not FileExists(FileName) then Exit;
  try
    AssignFile(f, FileName);
    Reset(f);
    try
      while not EOF(f) do
      begin
        ReadLn(f, s);
        if Pos('theme=', s) = 1 then SelectTheme(StrToIntDef(Copy(s, 7, 10), 0));
      end;
    finally
      CloseFile(f);
    end;
  except
    { a broken settings file just means default theme }
  end;
end;

procedure SaveThemeSetting(const FileName: string);
var
  f: TextFile;
begin
  try
    AssignFile(f, FileName);
    Rewrite(f);
    WriteLn(f, 'theme=', ThemeIndex);
    CloseFile(f);
  except
    { settings are optional }
  end;
end;

initialization
  Themes[0] := MakeTheme('Default', RGB(18, 20, 26), RGB(32, 35, 42), RGB(120, 190, 255),
    RGB(232, 236, 244), RGB(96, 106, 122), RGB(70, 62, 52), False);
  Themes[1] := MakeTheme('Dark', RGB(6, 6, 7), RGB(18, 18, 20), RGB(110, 160, 210),
    RGB(210, 210, 212), RGB(78, 78, 84), RGB(40, 38, 36), False);
  Themes[2] := MakeTheme('Daylight', RGB(234, 239, 245), RGB(250, 251, 253), RGB(30, 110, 210),
    RGB(25, 30, 40), RGB(118, 128, 145), RGB(165, 155, 140), True);
  Themes[3] := MakeTheme('Warm white', RGB(250, 243, 228), RGB(255, 250, 240), RGB(190, 105, 35),
    RGB(62, 45, 30), RGB(150, 128, 105), RGB(180, 158, 125), True);
  Themes[4] := MakeTheme('Red', RGB(30, 9, 11), RGB(50, 16, 20), RGB(255, 95, 95),
    RGB(252, 226, 226), RGB(135, 72, 78), RGB(80, 48, 42), False);
  Themes[5] := MakeTheme('Green', RGB(7, 24, 13), RGB(14, 40, 23), RGB(90, 230, 130),
    RGB(222, 250, 228), RGB(70, 122, 86), RGB(55, 60, 40), False);
  Themes[6] := MakeTheme('Blue', RGB(7, 15, 36), RGB(14, 28, 62), RGB(95, 175, 255),
    RGB(222, 236, 255), RGB(70, 100, 152), RGB(45, 50, 72), False);
  SelectTheme(0);

end.
