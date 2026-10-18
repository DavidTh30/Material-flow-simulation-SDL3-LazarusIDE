unit piecesim;

{ Pieces: whole objects much bigger than the material particles - bottles,
  glasses, boxes, dolls. An Item feeder (equipment) drops them one by one.
  A piece stands upright: it falls, lands on pipes, bucket walls, the floor,
  conveyor decks (flat or inclined) and on other pieces, is carried by a
  running conveyor, and counts in the bucket it lands in. Photo sensors see
  them and weight sensors weigh them. Pieces are not saved with the layout. }

{$mode objfpc}{$H+}

interface

uses
  simcore;

const
  MAX_PIECES = 120;
  PK_BOTTLE = 0;
  PK_GLASS = 1;
  PK_BOX = 2;
  PK_DOLL = 3;
  PK_KINDS = 4;
  PK_MIXED = 4;          { an item feeder's mode: a mix of all of them }
  PieceNames: array[0..PK_KINDS] of string = ('Bottle', 'Glass', 'Box', 'Doll', 'Mixed');
  PieceW: array[0..PK_KINDS - 1] of Single = (14, 18, 32, 24);
  PieceH: array[0..PK_KINDS - 1] of Single = (36, 22, 26, 30);
  PieceMass: array[0..PK_KINDS - 1] of Single = (0.6, 0.3, 1.5, 0.4);   { kg }

type
  TPiece = record
    Active: Boolean;
    Kind, Tint: Byte;
    X, Y: Single;          { the middle of its bottom edge }
    VX, VY: Single;
    Bucket: SmallInt;      { the bucket it is in, -1 none }
    Resting: Boolean;      { standing on something }
  end;
  PPiece = ^TPiece;

var
  Pieces: array[0..MAX_PIECES - 1] of TPiece;

procedure PiecesClear;
function PieceCount: Integer;
{ a new piece standing with its bottom middle at X, Y; -1 when there is no room }
function AddPiece(Kind: Integer; X, Y: Single): Integer;
{ some piece covers part of the rectangle }
function PieceIn(x1, y1, x2, y2: Single): Boolean;
{ the pieces in bucket b and their mass in kg }
function PiecesInBucket(b: Integer; out Mass: Single): Integer;
procedure StepPieces(dt: Single);

implementation

uses
  Math;

procedure PiecesClear;
begin
  FillChar(Pieces, SizeOf(Pieces), 0);
end;

function PieceCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to MAX_PIECES - 1 do
    if Pieces[i].Active then Inc(Result);
end;

function Overlaps(const P: TPiece; x1, y1, x2, y2: Single): Boolean;
var
  hw: Single;
begin
  hw := PieceW[P.Kind] / 2;
  Result := (P.X + hw > x1) and (P.X - hw < x2) and (P.Y > y1) and (P.Y - PieceH[P.Kind] < y2);
end;

function PieceIn(x1, y1, x2, y2: Single): Boolean;
var
  i: Integer;
begin
  for i := 0 to MAX_PIECES - 1 do
    if Pieces[i].Active and Overlaps(Pieces[i], x1, y1, x2, y2) then Exit(True);
  Result := False;
end;

function AddPiece(Kind: Integer; X, Y: Single): Integer;
var
  i: Integer;
  hw, h: Single;
begin
  Result := -1;
  Kind := EnsureRange(Kind, 0, PK_KINDS - 1);
  hw := PieceW[Kind] / 2;
  h := PieceH[Kind];
  if PieceIn(X - hw, Y - h, X + hw, Y) then Exit;
  for i := 0 to MAX_PIECES - 1 do
    if not Pieces[i].Active then
    begin
      FillChar(Pieces[i], SizeOf(TPiece), 0);
      Pieces[i].Active := True;
      Pieces[i].Kind := Kind;
      Pieces[i].Tint := Random(3);
      Pieces[i].X := X;
      Pieces[i].Y := Y;
      Pieces[i].Bucket := -1;
      Exit(i);
    end;
end;

function PiecesInBucket(b: Integer; out Mass: Single): Integer;
var
  i: Integer;
begin
  Result := 0;
  Mass := 0;
  for i := 0 to MAX_PIECES - 1 do
    if Pieces[i].Active and (Pieces[i].Bucket = b) then
    begin
      Inc(Result);
      Mass := Mass + PieceMass[Pieces[i].Kind];
    end;
end;

{ its bottom edge (three points) or its sides touch something solid }
function BottomSolid(const P: TPiece; y: Single): Boolean;
var
  hw: Single;
begin
  hw := PieceW[P.Kind] / 2 - 2;
  Result := SolidAt(P.X - hw, y) or SolidAt(P.X, y) or SolidAt(P.X + hw, y);
end;

function SideSolid(const P: TPiece; x: Single): Boolean;
var
  hw, h: Single;
begin
  hw := PieceW[P.Kind] / 2;
  h := PieceH[P.Kind];
  Result := SolidAt(x - hw, P.Y - h * 0.5) or SolidAt(x + hw, P.Y - h * 0.5) or
    SolidAt(x - hw, P.Y - h + 3) or SolidAt(x + hw, P.Y - h + 3) or
    SolidAt(x - hw, P.Y - 5) or SolidAt(x + hw, P.Y - 5);
end;

{ the deck of a running conveyor right under the piece: the deck's height there and the belt's velocity }
function OnConveyor(const P: TPiece; out DeckY, VX, VY: Single): Boolean;
var
  i: Integer;
  x1, y1, x2, y2, v, len: Single;
begin
  Result := False;
  for i := 0 to MAX_EQUIP - 1 do
    with Equips[i] do
      if Active and (Kind in [EQ_CONVEYOR, EQ_BELT]) and (P.X >= X) and (P.X <= X + W) then
      begin
        ConveyorDeck(i, x1, y1, x2, y2);
        DeckY := y1 + (P.X - x1) * (y2 - y1) / Max(1, x2 - x1);
        if Abs(P.Y - DeckY) > 4 then Continue;
        if EquipRunning(i) then v := 20 + Level * 1.4 else v := 0;
        if Flip then v := -v;
        len := Sqrt(Sqr(x2 - x1) + Sqr(y2 - y1));
        VX := v * (x2 - x1) / len;
        VY := v * (y2 - y1) / len;
        Exit(True);
      end;
end;

procedure StepOne(var P: TPiece; idx: Integer; dt: Single);
var
  k, j, steps: Integer;
  nx, ny, dy, vx, vy, hw, ow, top, ov: Single;
  Q: PPiece;
  onBelt: Boolean;
begin
  hw := PieceW[P.Kind] / 2;
  onBelt := OnConveyor(P, dy, vx, vy);
  if onBelt then
  begin
    { a conveyor carries it along its deck }
    P.VX := vx;
    P.VY := vy;
    P.Y := dy;
  end
  else
    P.VY := P.VY + GRAVITY * GravityScale * dt;
  P.VY := Min(P.VY, 900);
  { sideways }
  nx := P.X + P.VX * dt;
  if SideSolid(P, nx) then P.VX := -P.VX * 0.2 else P.X := nx;
  { up / down }
  ny := P.Y + P.VY * dt;
  P.Resting := False;
  if P.VY >= 0 then
  begin
    if BottomSolid(P, ny) then
    begin
      { landed: lift it out of what it hit }
      steps := 0;
      while BottomSolid(P, ny) and (steps < 14) do
      begin
        ny := ny - 1;
        Inc(steps);
      end;
      if not onBelt then
      begin
        P.VY := 0;
        P.VX := P.VX * Max(0, 1 - 6 * dt);
      end;
      P.Resting := True;
    end;
    P.Y := ny;
  end
  else
  begin
    if SolidAt(P.X, ny - PieceH[P.Kind]) then P.VY := 0 else P.Y := ny;
  end;
  { other pieces: stand on the one below, or move apart }
  for k := 0 to MAX_PIECES - 1 do
  begin
    if k = idx then Continue;
    Q := @Pieces[k];
    if not Q^.Active then Continue;
    ow := hw + PieceW[Q^.Kind] / 2;
    if Abs(P.X - Q^.X) >= ow then Continue;
    top := Q^.Y - PieceH[Q^.Kind];
    if (P.Y > top) and (P.Y - PieceH[P.Kind] < Q^.Y) then
    begin
      if P.Y - top <= 8 then
      begin
        { on top of it }
        P.Y := top;
        if P.VY > Q^.VY then P.VY := Q^.VY;
        if not onBelt then P.VX := P.VX + (Q^.VX - P.VX) * Min(1, 8 * dt);
        P.Resting := True;
      end
      else if P.Y <= Q^.Y + 0.01 then
      begin
        { side by side: half the overlap each }
        ov := ow - Abs(P.X - Q^.X);
        if P.X < Q^.X then j := -1 else j := 1;
        if not SideSolid(P, P.X + j * ov * 0.5) then P.X := P.X + j * ov * 0.5;
        if (P.VX * j < 0) then P.VX := P.VX * 0.5;
      end;
    end;
  end;
  { in a bucket? }
  P.Bucket := -1;
  for k := 0 to MAX_BUCKETS - 1 do
    if Buckets[k].Active and (P.X >= Buckets[k].X) and (P.X <= Buckets[k].X + Buckets[k].W) and
      (P.Y > Buckets[k].Y) and (P.Y <= Buckets[k].Y + Buckets[k].H + 2) then
      P.Bucket := k;
  if (P.X < -40) or (P.X > CANVAS_W + 40) or (P.Y > CANVAS_H + 40) then P.Active := False;
end;

{ item feeders drop pieces while they run }
procedure Feeders(dt: Single);
var
  i, kind: Integer;
  E: ^TEquipObj;
  sx, sy: Single;
begin
  for i := 0 to MAX_EQUIP - 1 do
  begin
    E := @Equips[i];
    if not (E^.Active and (E^.Kind = EQ_ITEMFEEDER) and EquipRunning(i)) then Continue;
    { HotIn: how many it has dropped, HotOut: the time since the last one (not saved) }
    if (E^.RMax > 0) and (E^.HotIn >= E^.RMax) then Continue;     { its stock is used up }
    E^.HotOut := E^.HotOut + dt;
    if E^.HotOut < Max(0.2, E^.RMin) then Continue;
    if E^.Mode >= PK_MIXED then kind := Random(PK_KINDS) else kind := E^.Mode;
    sx := E^.X + E^.W / 2;
    sy := E^.Y + E^.H + PieceH[kind] + 2;
    if AddPiece(kind, sx, sy) >= 0 then
    begin
      E^.HotOut := 0;
      E^.HotIn := E^.HotIn + 1;
    end;
  end;
end;

{ workers (order pickers): a Loader takes pieces from its stock (the rack behind it) and puts them
  down in front of it (on a conveyor); a Picker lifts the pieces in reach in front of it (from the belt
  or the floor) and puts them down behind it (into a van, a cart). Mode: 0 loader, 1 picker; Level: the
  kind it handles (PK_MIXED: a mix / any); RMin: s between pieces (loader) or to carry one (picker);
  RMax: a loader's stock (0 no end). Heat: the kind in its hands + 1 (0 empty); HotOut: its timer;
  HotIn: how many it has handled (none of these saved). }
procedure Workers(dt: Single);
var
  i, k, kind, dir, put: Integer;
  E: ^TEquipObj;
  cx, x1, x2, y1, y2, px, py: Single;
  P: PPiece;
begin
  for i := 0 to MAX_EQUIP - 1 do
  begin
    E := @Equips[i];
    if not (E^.Active and (E^.Kind = EQ_WORKER)) then Continue;
    if E^.Flip then dir := -1 else dir := 1;
    cx := E^.X + E^.W / 2;
    if not EquipRunning(i) then Continue;
    E^.HotOut := E^.HotOut + dt;
    if E^.Heat > 0 then
    begin
      { carrying one: put it down when it has been carried long enough }
      if E^.HotOut < Max(0.4, Min(E^.RMin, 1.2)) then Continue;
      kind := Round(E^.Heat) - 1;
      put := -1;
      if E^.Mode = 0 then
        put := AddPiece(kind, cx + dir * E^.W * 0.4, E^.Y + E^.H * 0.33)
      else
        { behind it: a free spot, higher and higher (on top of what is there already) }
        for k := 0 to 11 do
        begin
          px := cx - dir * (E^.W * 1.6 + Random * E^.W * 1.4);
          py := E^.Y + E^.H * (0.4 - 0.2 * (k div 3));
          put := AddPiece(kind, px, py);
          if put >= 0 then Break;
        end;
      if put >= 0 then
      begin
        E^.Heat := 0;
        E^.HotOut := 0;
        E^.HotIn := E^.HotIn + 1;
      end;
      Continue;
    end;
    if E^.Mode = 0 then
    begin
      { a loader: the next piece from its stock }
      if (E^.RMax > 0) and (E^.HotIn >= E^.RMax) then Continue;
      if E^.HotOut < Max(0.5, E^.RMin) - Min(E^.RMin, 1.2) then Continue;
      if Round(E^.Level) >= PK_MIXED then kind := Random(PK_KINDS) else kind := EnsureRange(Round(E^.Level), 0, PK_KINDS - 1);
      E^.Heat := kind + 1;
      E^.HotOut := 0;
    end
    else
    begin
      { a picker: a piece in reach in front of it }
      if dir > 0 then
      begin
        x1 := cx;
        x2 := cx + E^.W * 2.2;
      end
      else
      begin
        x1 := cx - E^.W * 2.2;
        x2 := cx;
      end;
      y1 := E^.Y - E^.H * 0.25;     { from a little above its head down to its feet }
      y2 := E^.Y + E^.H + 2;
      for k := 0 to MAX_PIECES - 1 do
      begin
        P := @Pieces[k];
        if not P^.Active then Continue;
        if (Round(E^.Level) < PK_MIXED) and (P^.Kind <> Round(E^.Level)) then Continue;
        if (P^.X >= x1) and (P^.X <= x2) and (P^.Y >= y1) and (P^.Y <= y2) then
        begin
          P^.Active := False;
          E^.Heat := P^.Kind + 1;
          E^.HotOut := 0;
          Break;
        end;
      end;
    end;
  end;
end;

procedure StepPieces(dt: Single);
var
  i, s, n: Integer;
begin
  Feeders(dt);
  Workers(dt);
  n := 3;
  for s := 1 to n do
    for i := 0 to MAX_PIECES - 1 do
      if Pieces[i].Active then StepOne(Pieces[i], i, dt / n);
end;

procedure PieceHookProc(dt: Single);
begin
  StepPieces(dt);
end;

initialization
  PiecesClear;
  PieceHook := @PieceHookProc;
  ClearHook4 := @PiecesClear;

end.
