unit shapes;

{ Custom vector shapes for the equipment: a kind with a shape of its own is
  drawn from it instead of the built-in drawing. A shape is a list of
  primitives (rectangle, ellipse, line, triangle) in the equipment's box, in
  0..1 coordinates, so it stretches with the equipment. A primitive can take
  the state colour (green running, grey stopped, red fault ...) instead of its
  own colour. A kind can also have its own size for new pieces.
  The shapes are kept in a .mfshape file (plain text):

    MFSHAPE 1
    KIND <tag> <new width> <new height>          (0 0: the built-in size)
    PRIM <type> <x1> <y1> <x2> <y2> <r> <g> <b> <a> <fill 0/1> <state colour 0/1> <thickness>

  type: rect, ellipse, line, tri (a triangle: x1,y1 x2,y1 and the apex (x1+x2)/2,y2) }

{$mode objfpc}{$H+}

interface

uses
  simcore;

const
  SHAPE_FILE = 'shapes.mfshape';   { loaded at start when it is next to the program }
  MAX_PRIM = 48;
  PR_RECT = 0;
  PR_ELLIPSE = 1;
  PR_LINE = 2;
  PR_TRI = 3;
  PRIM_TYPES = 4;
  PrimNames: array[0..PRIM_TYPES - 1] of string = ('rect', 'ellipse', 'line', 'tri');

type
  TShapePrim = record
    Typ: Byte;
    X1, Y1, X2, Y2: Single;   { 0..1 in the equipment box }
    R, G, B, A: Byte;
    Fill: Boolean;
    StateCol: Boolean;        { takes the state colour instead of R, G, B }
    Thick: Single;            { outline / line thickness in pixels }
  end;

  TEqShape = record
    N: Integer;                { primitives; 0 = the built-in drawing }
    P: array[0..MAX_PRIM - 1] of TShapePrim;
    W, H: Single;              { size of a new piece; 0 = the built-in size }
  end;

var
  EqShapes: array[0..EQ_KINDS - 1] of TEqShape;

function ShapeDefined(Kind: Integer): Boolean;
procedure ShapeClear(Kind: Integer);
procedure ShapesReset;
function ShapeAdd(Kind, ATyp: Integer; AX1, AY1, AX2, AY2: Single): Integer;
procedure ShapeDelete(Kind, k: Integer);
{ move primitive k one place up (+1, drawn later) or down (-1); returns its new index }
function ShapeMove(Kind, k, Delta: Integer): Integer;
{ the topmost primitive at u, v (0..1), -1 if none }
function ShapeHit(Kind: Integer; u, v, Tol: Single): Integer;
function ShapesCount: Integer;
function SaveShapes(const FileName: UnicodeString; out Err: string): Boolean;
function LoadShapes(const FileName: UnicodeString; out Err: string): Boolean;

implementation

uses
  SysUtils, Math;

var
  FS: TFormatSettings;

function ShapeDefined(Kind: Integer): Boolean;
begin
  Result := (Kind >= 0) and (Kind < EQ_KINDS) and (EqShapes[Kind].N > 0);
end;

procedure ShapeClear(Kind: Integer);
begin
  EqShapes[Kind].N := 0;
  EqShapes[Kind].W := 0;
  EqShapes[Kind].H := 0;
end;

procedure ShapesReset;
var
  k: Integer;
begin
  for k := 0 to EQ_KINDS - 1 do ShapeClear(k);
end;

function ShapeAdd(Kind, ATyp: Integer; AX1, AY1, AX2, AY2: Single): Integer;
begin
  Result := -1;
  if EqShapes[Kind].N >= MAX_PRIM then Exit;
  Result := EqShapes[Kind].N;
  Inc(EqShapes[Kind].N);
  with EqShapes[Kind].P[Result] do
  begin
    Typ := EnsureRange(ATyp, 0, PRIM_TYPES - 1);
    X1 := EnsureRange(AX1, 0, 1);
    Y1 := EnsureRange(AY1, 0, 1);
    X2 := EnsureRange(AX2, 0, 1);
    Y2 := EnsureRange(AY2, 0, 1);
    R := 150;
    G := 156;
    B := 166;
    A := 255;
    Fill := Typ <> PR_LINE;
    StateCol := Typ <> PR_LINE;
    Thick := 2;
  end;
end;

procedure ShapeDelete(Kind, k: Integer);
var
  j: Integer;
begin
  if (k < 0) or (k >= EqShapes[Kind].N) then Exit;
  for j := k to EqShapes[Kind].N - 2 do EqShapes[Kind].P[j] := EqShapes[Kind].P[j + 1];
  Dec(EqShapes[Kind].N);
end;

function ShapeMove(Kind, k, Delta: Integer): Integer;
var
  j: Integer;
  t: TShapePrim;
begin
  Result := k;
  j := k + Delta;
  if (k < 0) or (k >= EqShapes[Kind].N) or (j < 0) or (j >= EqShapes[Kind].N) then Exit;
  t := EqShapes[Kind].P[k];
  EqShapes[Kind].P[k] := EqShapes[Kind].P[j];
  EqShapes[Kind].P[j] := t;
  Result := j;
end;

function ShapeHit(Kind: Integer; u, v, Tol: Single): Integer;
var
  k: Integer;
  hx1, hy1, hx2, hy2, dx, dy, t, d: Single;
begin
  Result := -1;
  for k := EqShapes[Kind].N - 1 downto 0 do
    with EqShapes[Kind].P[k] do
    begin
      if Typ = PR_LINE then
      begin
        dx := X2 - X1;
        dy := Y2 - Y1;
        if dx * dx + dy * dy < 1e-9 then t := 0
        else t := EnsureRange(((u - X1) * dx + (v - Y1) * dy) / (dx * dx + dy * dy), 0, 1);
        d := Sqrt(Sqr(X1 + t * dx - u) + Sqr(Y1 + t * dy - v));
        if d <= Tol then Exit(k);
      end
      else
      begin
        hx1 := Min(X1, X2) - Tol;
        hx2 := Max(X1, X2) + Tol;
        hy1 := Min(Y1, Y2) - Tol;
        hy2 := Max(Y1, Y2) + Tol;
        if (u >= hx1) and (u <= hx2) and (v >= hy1) and (v <= hy2) then Exit(k);
      end;
    end;
end;

function ShapesCount: Integer;
var
  k: Integer;
begin
  Result := 0;
  for k := 0 to EQ_KINDS - 1 do
    if EqShapes[k].N > 0 then Inc(Result);
end;

function F2S(v: Single): string;
begin
  Result := FloatToStrF(v, ffGeneral, 6, 0, FS);
end;

function SaveShapes(const FileName: UnicodeString; out Err: string): Boolean;
var
  f: TextFile;
  k, j: Integer;
begin
  Result := False;
  Err := '';
  try
    AssignFile(f, FileName);
    Rewrite(f);
    try
      WriteLn(f, '# Material Flow Simulator equipment shapes');
      WriteLn(f, '# KIND tag new-width new-height');
      WriteLn(f, '# PRIM rect|ellipse|line|tri x1 y1 x2 y2 r g b a fill state-colour thickness (x, y: 0..1 in the box)');
      WriteLn(f, 'MFSHAPE 1');
      for k := 0 to EQ_KINDS - 1 do
        if EqShapes[k].N > 0 then
        begin
          WriteLn(f, Format('KIND %s %s %s', [EquipTags[k], F2S(EqShapes[k].W), F2S(EqShapes[k].H)]));
          for j := 0 to EqShapes[k].N - 1 do
            with EqShapes[k].P[j] do
              WriteLn(f, Format('PRIM %s %s %s %s %s %d %d %d %d %d %d %s', [PrimNames[Typ], F2S(X1), F2S(Y1), F2S(X2),
                F2S(Y2), R, G, B, A, Ord(Fill), Ord(StateCol), F2S(Thick)]));
        end;
    finally
      CloseFile(f);
    end;
    Result := True;
  except
    on E: Exception do Err := E.Message;
  end;
end;

function LoadShapes(const FileName: UnicodeString; out Err: string): Boolean;
var
  f: TextFile;
  line: string;
  Tok: array[0..13] of string;
  n, i, k, j, cur, lineNo: Integer;
  newShapes: array[0..EQ_KINDS - 1] of TEqShape;
  gotHeader, opened: Boolean;

  procedure Fail(const Msg: string);
  begin
    raise Exception.CreateFmt('line %d: %s', [lineNo, Msg]);
  end;

  function Num(jj: Integer): Single;
  begin
    if not TryStrToFloat(Tok[jj], Result, FS) then Fail('bad number "' + Tok[jj] + '"');
  end;

  function Int(jj: Integer): Integer;
  begin
    if not TryStrToInt(Tok[jj], Result) then Fail('bad integer "' + Tok[jj] + '"');
  end;

begin
  Result := False;
  Err := '';
  for k := 0 to EQ_KINDS - 1 do
  begin
    newShapes[k].N := 0;
    newShapes[k].W := 0;
    newShapes[k].H := 0;
  end;
  opened := False;
  gotHeader := False;
  lineNo := 0;
  cur := -1;
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
        if (n < 2) or not SameText(Tok[0], 'MFSHAPE') then Fail('not a shape file (missing MFSHAPE header)');
        gotHeader := True;
        Continue;
      end;
      if SameText(Tok[0], 'KIND') then
      begin
        if n < 4 then Fail('KIND needs a tag, a width and a height');
        cur := -1;
        for k := 0 to EQ_KINDS - 1 do
          if SameText(Tok[1], EquipTags[k]) then cur := k;
        if cur < 0 then Fail('unknown equipment "' + Tok[1] + '"');
        newShapes[cur].N := 0;
        newShapes[cur].W := EnsureRange(Num(2), 0, 2000);
        newShapes[cur].H := EnsureRange(Num(3), 0, 2000);
      end
      else if SameText(Tok[0], 'PRIM') then
      begin
        if cur < 0 then Fail('PRIM before KIND');
        if n < 13 then Fail('PRIM needs 12 values');
        if newShapes[cur].N >= MAX_PRIM then Fail(Format('more than %d primitives', [MAX_PRIM]));
        j := -1;
        for k := 0 to PRIM_TYPES - 1 do
          if SameText(Tok[1], PrimNames[k]) then j := k;
        if j < 0 then Fail('unknown primitive "' + Tok[1] + '"');
        with newShapes[cur].P[newShapes[cur].N] do
        begin
          Typ := j;
          X1 := EnsureRange(Num(2), 0, 1);
          Y1 := EnsureRange(Num(3), 0, 1);
          X2 := EnsureRange(Num(4), 0, 1);
          Y2 := EnsureRange(Num(5), 0, 1);
          R := EnsureRange(Int(6), 0, 255);
          G := EnsureRange(Int(7), 0, 255);
          B := EnsureRange(Int(8), 0, 255);
          A := EnsureRange(Int(9), 0, 255);
          Fill := Int(10) <> 0;
          StateCol := Int(11) <> 0;
          Thick := EnsureRange(Num(12), 1, 20);
        end;
        Inc(newShapes[cur].N);
      end
      else
        Fail('unknown keyword "' + Tok[0] + '"');
    end;
    if not gotHeader then Fail('file is empty');
    CloseFile(f);
    opened := False;
    EqShapes := newShapes;
    Result := True;
  except
    on E: Exception do
    begin
      if opened then CloseFile(f);
      Err := E.Message;
    end;
  end;
end;

{ new pieces of a kind with a size of its own }
function ShapeSize(Kind: Integer; out W, H: Single): Boolean;
begin
  Result := (Kind >= 0) and (Kind < EQ_KINDS) and (EqShapes[Kind].W >= 8) and (EqShapes[Kind].H >= 8);
  if Result then
  begin
    W := EqShapes[Kind].W;
    H := EqShapes[Kind].H;
  end;
end;

initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  ShapesReset;
  EquipSizeHook := @ShapeSize;

end.
