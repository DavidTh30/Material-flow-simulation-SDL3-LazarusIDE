unit physics;

{ The physics settings, apart from any layout: the world constants and every
  material's properties. They can be saved to / loaded from a .mfphys file
  (plain text) and reset to the built-in values; the Physics Lab edits them
  and builds test scenes to try them on.

    MFPHYS 1
    WORLD <gravity px/s2> <air speed per flow> <feed rate> <gravity feed> <air dots>
    MAT <name> <mass> <gravity> <air couple> <air drag> <friction> <density> <size> <liquid 0/1> <r> <g> <b> <a> [<pH>] }

{$mode objfpc}{$H+}

interface

uses
  simcore;

const
  PHYS_FILE = 'physics.mfphys';    { loaded at start when it is next to the program }
  LAB_PAGE = 'Physics lab';

var
  DefaultMatP: array[TMat] of TMatProps;

procedure PhysicsResetDefaults;
function PhysicsChanged: Boolean;
function SavePhysics(const FileName: UnicodeString; out Err: string): Boolean;
function LoadPhysics(const FileName: UnicodeString; out Err: string): Boolean;
{ a test scene in the live page (it is cleared first): 1 drop test, 2 mix test, 3 air transport }
procedure BuildPhysicsTest(n: Integer);

implementation

uses
  SysUtils, Math;

var
  DefGravity, DefVK, DefEmitK, DefGravFeed, DefAirK: Single;
  FS: TFormatSettings;

procedure PhysicsResetDefaults;
begin
  MatP := DefaultMatP;
  GRAVITY := DefGravity;
  VK := DefVK;
  EMIT_K := DefEmitK;
  GRAV_FEED := DefGravFeed;
  AIR_K := DefAirK;
end;

function PhysicsChanged: Boolean;
var
  m: TMat;
begin
  Result := (GRAVITY <> DefGravity) or (VK <> DefVK) or (EMIT_K <> DefEmitK) or (GRAV_FEED <> DefGravFeed) or
    (AIR_K <> DefAirK);
  for m := Low(TMat) to High(TMat) do
    if not CompareMem(@MatP[m], @DefaultMatP[m], SizeOf(TMatProps)) then Result := True;
end;

function F2S(v: Single): string;
begin
  Result := FloatToStrF(v, ffGeneral, 7, 0, FS);
end;

function SavePhysics(const FileName: UnicodeString; out Err: string): Boolean;
var
  f: TextFile;
  m: TMat;
begin
  Result := False;
  Err := '';
  try
    AssignFile(f, FileName);
    Rewrite(f);
    try
      WriteLn(f, '# Material Flow Simulator physics');
      WriteLn(f, '# WORLD gravity air-speed feed-rate gravity-feed air-dots');
      WriteLn(f, '# MAT name mass gravity couple drag friction density size liquid r g b a pH');
      WriteLn(f, 'MFPHYS 1');
      WriteLn(f, Format('WORLD %s %s %s %s %s', [F2S(GRAVITY), F2S(VK), F2S(EMIT_K), F2S(GRAV_FEED), F2S(AIR_K)]));
      for m := Low(TMat) to High(TMat) do
        with MatP[m] do
          WriteLn(f, Format('MAT %s %s %s %s %s %s %s %s %d %d %d %d %d %s', [Name, F2S(Mass), F2S(Grav), F2S(Couple),
            F2S(Drag), F2S(Fric), F2S(Dens), F2S(Size), Ord(Liquid), R, G, B, A, F2S(PH)]));
    finally
      CloseFile(f);
    end;
    Result := True;
  except
    on E: Exception do Err := E.Message;
  end;
end;

function LoadPhysics(const FileName: UnicodeString; out Err: string): Boolean;
var
  f: TextFile;
  line: string;
  Tok: array[0..14] of string;
  n, i, k, lineNo: Integer;
  m: TMat;
  oldMat: array[TMat] of TMatProps;
  oldW: array[0..4] of Single;
  gotHeader, opened: Boolean;

  procedure Fail(const Msg: string);
  begin
    raise Exception.CreateFmt('line %d: %s', [lineNo, Msg]);
  end;

  function Num(j: Integer): Single;
  begin
    if not TryStrToFloat(Tok[j], Result, FS) then Fail('bad number "' + Tok[j] + '"');
  end;

  function Int(j: Integer): Integer;
  begin
    if not TryStrToInt(Tok[j], Result) then Fail('bad integer "' + Tok[j] + '"');
  end;

begin
  Result := False;
  Err := '';
  oldMat := MatP;
  oldW[0] := GRAVITY;
  oldW[1] := VK;
  oldW[2] := EMIT_K;
  oldW[3] := GRAV_FEED;
  oldW[4] := AIR_K;
  opened := False;
  lineNo := 0;
  gotHeader := False;
  try
    AssignFile(f, FileName);
    Reset(f);
    opened := True;
    while not EOF(f) do
    begin
      ReadLn(f, line);
      Inc(lineNo);
      line := Trim(line);
      if (line = '') or (line[1] = '#') then Continue;
      n := 0;
      i := 1;
      while (i <= Length(line)) and (n <= High(Tok)) do
      begin
        while (i <= Length(line)) and (line[i] in [' ', #9]) do Inc(i);
        if i > Length(line) then Break;
        k := i;
        while (i <= Length(line)) and not (line[i] in [' ', #9]) do Inc(i);
        Tok[n] := Copy(line, k, i - k);
        Inc(n);
      end;
      if not gotHeader then
      begin
        if (n < 2) or not SameText(Tok[0], 'MFPHYS') then Fail('not a physics file (missing MFPHYS header)');
        gotHeader := True;
        Continue;
      end;
      if SameText(Tok[0], 'WORLD') then
      begin
        if n < 6 then Fail('WORLD needs 5 values');
        GRAVITY := EnsureRange(Num(1), 0, 5000);
        VK := EnsureRange(Num(2), 1, 2000);
        EMIT_K := EnsureRange(Num(3), 0, 1000);
        GRAV_FEED := EnsureRange(Num(4), 0, 1000);
        AIR_K := EnsureRange(Num(5), 0, 500);
      end
      else if SameText(Tok[0], 'MAT') then
      begin
        if n < 14 then Fail('MAT needs 13 values');
        k := -1;
        for m := Low(TMat) to High(TMat) do
          if SameText(Tok[1], MatP[m].Name) then k := Ord(m);
        if k < 0 then Fail('unknown material "' + Tok[1] + '"');
        with MatP[TMat(k)] do
        begin
          Mass := EnsureRange(Num(2), 0.001, 100);
          Grav := EnsureRange(Num(3), -10, 10);
          Couple := EnsureRange(Num(4), 0, 200);
          Drag := EnsureRange(Num(5), 0, 100);
          Fric := EnsureRange(Num(6), 0, 1);
          Dens := EnsureRange(Num(7), 0, 20);
          Size := EnsureRange(Num(8), 1, 12);
          Liquid := Int(9) <> 0;
          R := EnsureRange(Int(10), 0, 255);
          G := EnsureRange(Int(11), 0, 255);
          B := EnsureRange(Int(12), 0, 255);
          A := EnsureRange(Int(13), 0, 255);
          if n >= 15 then PH := EnsureRange(Num(14), 0, 14);
        end;
      end
      else
        Fail('unknown keyword "' + Tok[0] + '"');
    end;
    if not gotHeader then Fail('file is empty');
    CloseFile(f);
    opened := False;
    Result := True;
  except
    on E: Exception do
    begin
      if opened then CloseFile(f);
      MatP := oldMat;
      GRAVITY := oldW[0];
      VK := oldW[1];
      EMIT_K := oldW[2];
      GRAV_FEED := oldW[3];
      AIR_K := oldW[4];
      Err := E.Message;
    end;
  end;
end;

{ ---------------------------------------------------------------- test scenes }

{ an endless feeder of one material (or a mix) at x,y with a pipe down to a drop outlet at y + drop }
procedure TestFeeder(x, y, drop: Integer; W, O, F, S: Single);
begin
  PipeLine(x, y, x, y + drop, 3);
  SetKind(x, y, ckVFeeder);
  Grid[x, y].Stock[mWater] := W;
  Grid[x, y].Stock[mOil] := O;
  Grid[x, y].Stock[mFluff] := F;
  Grid[x, y].Stock[mSand] := S;
  Grid[x, y].AirPct := 25;   { a little air carries the light material out of the pipe }
  Grid[x, y].Feed := 60;
  Grid[x, y].Strength := 60;
  SetKind(x, y + drop, ckDrop);
  Grid[x, y + drop].Strength := 100;
end;

procedure FloorBucketAt(cx: Integer; W, H: Single);
begin
  AddBucket(cx * CELL + HALF, FLOOR_Y - WALL_T - H, W, H);
end;

procedure BuildPhysicsTest(n: Integer);
const
  Cols: array[0..3] of Integer = (6, 16, 26, 36);
  Names: array[0..3] of string = ('WATER', 'OIL', 'FLUFF', 'SAND');
var
  k, r, col: Integer;
  v: array[0..3] of Single;
begin
  ClearAll;
  GravityScale := 1;
  case n of
    1:
      { drop test: each material falls from the same height into a bucket of its own }
      for k := 0 to 3 do
      begin
        for r := 0 to 3 do v[r] := 0;
        v[k] := 1000;
        TestFeeder(Cols[k], 3, 3, v[0], v[1], v[2], v[3]);
        FloorBucketAt(Cols[k], 170, 150);
        AddLabel(Cols[k] * CELL - 30, 30, Names[k]);
      end;
    2:
      begin
        { mix test: all four into one bucket: they settle by density }
        TestFeeder(21, 3, 3, 1000, 1000, 1000, 1000);
        FloorBucketAt(21, 340, 260);
        AddLabel(560, 120, 'MIX TEST'#10'Water, oil, fluff and sand'#10'settle by their density.');
      end;
    3:
      { air transport: the same blower on four lines, one material each }
      for k := 0 to 3 do
      begin
        col := 40 - k * 8;
        for r := 0 to 3 do v[r] := 0;
        v[k] := 1000;
        r := 3 + k * 6;
        PipeLine(2, r, col, r, 3);
        PipeLine(col, r, col, r + 2, 3);
        SetKind(2, r, ckVFeeder);
        Grid[2, r].Stock[mWater] := v[0];
        Grid[2, r].Stock[mOil] := v[1];
        Grid[2, r].Stock[mFluff] := v[2];
        Grid[2, r].Stock[mSand] := v[3];
        Grid[2, r].AirPct := 20;
        Grid[2, r].Feed := 60;
        Grid[2, r].Strength := 60;
        SetKind(5, r, ckBlower);
        Grid[5, r].Dir := 0;
        Grid[5, r].Strength := 60;
        SetKind(col, r + 2, ckDrop);
        Grid[col, r + 2].Strength := 100;
        FloorBucketAt(col, 150, 90);
        AddLabel(7 * CELL, r * CELL - 22, Names[k]);
      end;
  end;
end;

initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  DefaultMatP := MatP;
  DefGravity := GRAVITY;
  DefVK := VK;
  DefEmitK := EMIT_K;
  DefGravFeed := GRAV_FEED;
  DefAirK := AIR_K;

end.
