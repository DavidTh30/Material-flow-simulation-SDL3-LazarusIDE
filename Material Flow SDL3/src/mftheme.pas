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
  THEME_COUNT = 23;
  { the menu groups them: the first ones, more dark themes from here, light themes from here }
  THEME_DARK2 = 7;
  THEME_LIGHT2 = 18;

  { canvas backgrounds, chosen apart from the theme }
  BG_COUNT = 12;
  BG_THEME = 0;      { the theme's canvas colour }
  BG_SOFT = 1;       { the theme's colour, lighter at the top }
  BG_CORNERS = 2;    { a gradient between four corner colours }
  BG_VIGNETTE = 3;   { the theme's colour, darker toward the edges }
  BG_STRIPES = 4;    { corner gradient with fine diagonal stripes }
  BG_BRUSHED = 5;    { corner gradient with fine horizontal lines }

type
  TBackground = record
    Name: string;
    Kind: Byte;
    TL, TR, BL, BR: TRGB;
  end;

var
  Themes: array[0..THEME_COUNT - 1] of TTheme;
  Backgrounds: array[0..BG_COUNT - 1] of TBackground;
  BgIndex: Integer = 0;
  { the background a layout comes with (-1: none, the chosen one shows) }
  LayoutBg: Integer = -1;
  Th: TTheme;            { the active theme }
  ThemeIndex: Integer = 0;

procedure SelectTheme(i: Integer);
procedure SelectBackground(i: Integer);
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

procedure SelectBackground(i: Integer);
begin
  if (i < 0) or (i >= BG_COUNT) then i := 0;
  BgIndex := i;
end;

function Bg(const AName: string; AKind: Byte; const ATL, ATR, ABL, ABR: TRGB): TBackground;
begin
  Result.Name := AName;
  Result.Kind := AKind;
  Result.TL := ATL;
  Result.TR := ATR;
  Result.BL := ABL;
  Result.BR := ABR;
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
  { more dark themes }
  Themes[7] := MakeTheme('Midnight', RGB(12, 14, 30), RGB(24, 27, 52), RGB(150, 130, 255),
    RGB(226, 226, 250), RGB(90, 96, 140), RGB(48, 44, 66), False);
  Themes[8] := MakeTheme('Ocean', RGB(6, 26, 34), RGB(12, 44, 56), RGB(60, 215, 220),
    RGB(215, 245, 248), RGB(62, 120, 135), RGB(36, 56, 58), False);
  Themes[9] := MakeTheme('Forest', RGB(14, 22, 14), RGB(26, 38, 24), RGB(160, 210, 90),
    RGB(228, 240, 215), RGB(96, 118, 80), RGB(62, 54, 36), False);
  Themes[10] := MakeTheme('Sunset', RGB(34, 16, 26), RGB(54, 26, 40), RGB(255, 145, 80),
    RGB(255, 232, 220), RGB(140, 90, 100), RGB(82, 52, 44), False);
  Themes[11] := MakeTheme('Purple', RGB(22, 10, 34), RGB(38, 20, 56), RGB(210, 120, 255),
    RGB(242, 228, 255), RGB(120, 90, 150), RGB(60, 44, 64), False);
  Themes[12] := MakeTheme('Amber HMI', RGB(16, 12, 4), RGB(30, 23, 8), RGB(255, 180, 40),
    RGB(255, 222, 165), RGB(130, 100, 50), RGB(60, 48, 30), False);
  Themes[13] := MakeTheme('Terminal', RGB(0, 10, 4), RGB(4, 22, 10), RGB(60, 255, 120),
    RGB(185, 255, 205), RGB(40, 110, 60), RGB(20, 40, 24), False);
  Themes[14] := MakeTheme('Slate', RGB(30, 34, 40), RGB(44, 49, 57), RGB(255, 170, 70),
    RGB(226, 230, 236), RGB(110, 118, 130), RGB(70, 64, 58), False);
  Themes[15] := MakeTheme('High contrast', RGB(0, 0, 0), RGB(0, 0, 0), RGB(255, 235, 0),
    RGB(255, 255, 255), RGB(200, 200, 200), RGB(90, 90, 90), False);
  Themes[16] := MakeTheme('Nord', RGB(46, 52, 64), RGB(59, 66, 82), RGB(136, 192, 208),
    RGB(236, 239, 244), RGB(94, 106, 130), RGB(76, 70, 62), False);
  Themes[17] := MakeTheme('Dracula', RGB(40, 42, 54), RGB(50, 52, 68), RGB(255, 121, 198),
    RGB(248, 248, 242), RGB(98, 114, 164), RGB(68, 60, 72), False);
  { more light themes }
  Themes[18] := MakeTheme('Paper', RGB(244, 244, 240), RGB(255, 255, 252), RGB(60, 90, 140),
    RGB(30, 30, 30), RGB(140, 140, 135), RGB(190, 180, 165), True);
  Themes[19] := MakeTheme('Mint', RGB(230, 246, 239), RGB(246, 253, 250), RGB(0, 140, 100),
    RGB(20, 50, 40), RGB(110, 150, 135), RGB(170, 160, 135), True);
  Themes[20] := MakeTheme('Sky', RGB(224, 238, 251), RGB(244, 250, 255), RGB(0, 115, 215),
    RGB(15, 35, 60), RGB(110, 140, 175), RGB(165, 160, 150), True);
  Themes[21] := MakeTheme('Rose', RGB(251, 235, 240), RGB(255, 248, 250), RGB(200, 40, 105),
    RGB(70, 20, 40), RGB(165, 120, 135), RGB(185, 160, 150), True);
  Themes[22] := MakeTheme('Solarized', RGB(253, 246, 227), RGB(238, 232, 213), RGB(38, 125, 200),
    RGB(50, 70, 78), RGB(147, 161, 161), RGB(190, 175, 140), True);
  SelectTheme(0);
  { the backgrounds; the first ones follow the theme }
  Backgrounds[0] := Bg('Theme colour', BG_THEME, RGB(0, 0, 0), RGB(0, 0, 0), RGB(0, 0, 0), RGB(0, 0, 0));
  Backgrounds[1] := Bg('Soft gradient', BG_SOFT, RGB(0, 0, 0), RGB(0, 0, 0), RGB(0, 0, 0), RGB(0, 0, 0));
  Backgrounds[2] := Bg('Vignette', BG_VIGNETTE, RGB(0, 0, 0), RGB(0, 0, 0), RGB(0, 0, 0), RGB(0, 0, 0));
  Backgrounds[3] := Bg('HMI blue', BG_CORNERS, RGB(214, 230, 240), RGB(160, 205, 232), RGB(110, 186, 228), RGB(38, 148, 214));
  Backgrounds[4] := Bg('Steel', BG_CORNERS, RGB(198, 204, 212), RGB(178, 184, 194), RGB(134, 140, 150), RGB(112, 118, 128));
  Backgrounds[5] := Bg('Brushed metal', BG_BRUSHED, RGB(206, 210, 216), RGB(184, 188, 196), RGB(156, 160, 168), RGB(138, 142, 150));
  Backgrounds[6] := Bg('Night sky', BG_CORNERS, RGB(10, 14, 36), RGB(18, 26, 60), RGB(28, 44, 86), RGB(46, 66, 112));
  Backgrounds[7] := Bg('Ocean deep', BG_CORNERS, RGB(0, 70, 104), RGB(0, 88, 120), RGB(0, 28, 50), RGB(0, 16, 34));
  Backgrounds[8] := Bg('Sunset', BG_CORNERS, RGB(46, 18, 54), RGB(72, 24, 62), RGB(186, 88, 70), RGB(236, 138, 72));
  Backgrounds[9] := Bg('Forest mist', BG_CORNERS, RGB(28, 50, 38), RGB(38, 62, 48), RGB(88, 126, 98), RGB(118, 148, 118));
  Backgrounds[10] := Bg('Warm paper', BG_CORNERS, RGB(252, 244, 226), RGB(248, 238, 216), RGB(232, 218, 190), RGB(222, 206, 174));
  Backgrounds[11] := Bg('Carbon', BG_STRIPES, RGB(30, 31, 36), RGB(24, 25, 30), RGB(20, 21, 25), RGB(14, 15, 18));

end.
