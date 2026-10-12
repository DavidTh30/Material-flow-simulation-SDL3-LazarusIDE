unit edithist;

{ Undo / redo for layout editing.

  The history works on snapshots of the layout (pipe cells with their
  settings, buckets, gravity). The app calls HistCheck whenever the user is
  idle (no button held, no drag): if the layout differs from the last
  committed snapshot, that snapshot goes onto the undo stack. So every
  finished gesture - a pipe drag, a slider drag, a menu command - becomes one
  undo step without each editing command having to register itself.

  Tank contents and material in flight are not layout: the simulation drains
  tanks continuously, so they are neither compared nor rolled back (a tank
  that is brought back by undo gets its saved contents). }

{$mode objfpc}{$H+}

interface

uses
  simcore;

type
  TCellLite = record
    Kind: TCellKind;
    Conn: Byte;
    Dia, Dir: Integer;
    Open: Boolean;
    Closed: Byte;
    Strength, AirPct, Feed: Single;
    Stock: array[TMat] of Single;
  end;

  TBucketLite = record
    Active: Boolean;
    X, Y, W, H: Single;
  end;

function CellToLite(const c: TCell): TCellLite;
{ write the lite cell into Grid[x,y]; KeepStock keeps a tank's current contents }
procedure LiteToCell(const L: TCellLite; x, y: Integer; KeepStock: Boolean);

procedure HistReset;
procedure HistCheck;
function CanUndo: Boolean;
function CanRedo: Boolean;
function Undo: Boolean;
function Redo: Boolean;

implementation

const
  MAX_HISTORY = 100;

type
  PSnap = ^TSnap;
  TSnap = record
    Cells: array[0..GW - 1, 0..GH - 1] of TCellLite;
    Bkts: array[0..MAX_BUCKETS - 1] of TBucketLite;
    Lbls: array[0..MAX_LABELS - 1] of TLabelObj;
    Gravity: Single;
  end;

  TSnapArray = array of PSnap;

var
  Committed: PSnap = nil;
  UndoStack: TSnapArray;
  RedoStack: TSnapArray;

function CellToLite(const c: TCell): TCellLite;
begin
  Result.Kind := c.Kind;
  Result.Conn := c.Conn;
  Result.Dia := c.Dia;
  Result.Dir := c.Dir;
  Result.Open := c.Open;
  Result.Closed := c.Closed;
  Result.Strength := c.Strength;
  Result.AirPct := c.AirPct;
  Result.Feed := c.Feed;
  Result.Stock := c.Stock;
end;

procedure LiteToCell(const L: TCellLite; x, y: Integer; KeepStock: Boolean);
var
  c: PCell;
  oldP: Single;
  oldStock: array[TMat] of Single;
begin
  c := @Grid[x, y];
  if L.Kind = ckEmpty then
  begin
    if c^.Kind <> ckEmpty then ResetCell(x, y);
    Exit;
  end;
  KeepStock := KeepStock and (c^.Kind = ckSource) and (L.Kind = ckSource);
  oldP := c^.P;
  oldStock := c^.Stock;
  ResetCell(x, y);
  c^.Kind := L.Kind;
  c^.Conn := L.Conn;
  c^.Dia := L.Dia;
  c^.Dir := L.Dir;
  c^.Open := L.Open;
  c^.Closed := L.Closed;
  c^.Strength := L.Strength;
  c^.AirPct := L.AirPct;
  c^.Feed := L.Feed;
  if KeepStock then c^.Stock := oldStock else c^.Stock := L.Stock;
  c^.P := oldP;
end;

procedure Capture(s: PSnap);
var
  x, y, i: Integer;
begin
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      s^.Cells[x, y] := CellToLite(Grid[x, y]);
  for i := 0 to MAX_BUCKETS - 1 do
  begin
    s^.Bkts[i].Active := Buckets[i].Active;
    s^.Bkts[i].X := Buckets[i].X;
    s^.Bkts[i].Y := Buckets[i].Y;
    s^.Bkts[i].W := Buckets[i].W;
    s^.Bkts[i].H := Buckets[i].H;
  end;
  s^.Lbls := Labels;
  s^.Gravity := GravityScale;
end;

function SameAsCurrent(s: PSnap): Boolean;
var
  x, y, i: Integer;
  c: PCell;
  L: ^TCellLite;
begin
  Result := False;
  if Abs(s^.Gravity - GravityScale) > 1e-6 then Exit;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @Grid[x, y];
      L := @s^.Cells[x, y];
      if c^.Kind <> L^.Kind then Exit;
      if c^.Kind = ckEmpty then Continue;
      if (c^.Conn <> L^.Conn) or (c^.Dia <> L^.Dia) or (c^.Dir <> L^.Dir) or (c^.Open <> L^.Open) or (c^.Closed <> L^.Closed) or
        (c^.Strength <> L^.Strength) or (c^.AirPct <> L^.AirPct) or (c^.Feed <> L^.Feed) then Exit;
    end;
  for i := 0 to MAX_BUCKETS - 1 do
  begin
    if Buckets[i].Active <> s^.Bkts[i].Active then Exit;
    if Buckets[i].Active and ((Buckets[i].X <> s^.Bkts[i].X) or (Buckets[i].Y <> s^.Bkts[i].Y) or
      (Buckets[i].W <> s^.Bkts[i].W) or (Buckets[i].H <> s^.Bkts[i].H)) then Exit;
  end;
  for i := 0 to MAX_LABELS - 1 do
  begin
    if Labels[i].Active <> s^.Lbls[i].Active then Exit;
    if Labels[i].Active and ((Labels[i].X <> s^.Lbls[i].X) or (Labels[i].Y <> s^.Lbls[i].Y) or
      (Labels[i].Text <> s^.Lbls[i].Text)) then Exit;
  end;
  Result := True;
end;

procedure Apply(s: PSnap);
var
  x, y, i: Integer;
begin
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      LiteToCell(s^.Cells[x, y], x, y, True);
  for i := 0 to MAX_BUCKETS - 1 do
    if s^.Bkts[i].Active then
    begin
      if not Buckets[i].Active then
      begin
        Buckets[i].Count := 0;
        Buckets[i].Spilled := 0;
        Buckets[i].Flash := 0;
      end;
      Buckets[i].Active := True;
      Buckets[i].X := s^.Bkts[i].X;
      Buckets[i].Y := s^.Bkts[i].Y;
      Buckets[i].W := s^.Bkts[i].W;
      Buckets[i].H := s^.Bkts[i].H;
    end
    else if Buckets[i].Active then
      DeleteBucket(i);
  Labels := s^.Lbls;
  GravityScale := s^.Gravity;
end;

procedure StackClear(var A: TSnapArray);
var
  i: Integer;
begin
  for i := 0 to High(A) do
    Dispose(A[i]);
  SetLength(A, 0);
end;

procedure StackPush(var A: TSnapArray; s: PSnap);
var
  i: Integer;
begin
  if Length(A) >= MAX_HISTORY then
  begin
    { drop the oldest step }
    Dispose(A[0]);
    for i := 1 to High(A) do
      A[i - 1] := A[i];
    A[High(A)] := s;
  end
  else
  begin
    SetLength(A, Length(A) + 1);
    A[High(A)] := s;
  end;
end;

function StackPop(var A: TSnapArray): PSnap;
begin
  Result := A[High(A)];
  SetLength(A, Length(A) - 1);
end;

procedure HistReset;
begin
  StackClear(UndoStack);
  StackClear(RedoStack);
  if Committed = nil then New(Committed);
  Capture(Committed);
end;

procedure HistCheck;
var
  s: PSnap;
begin
  if Committed = nil then
  begin
    HistReset;
    Exit;
  end;
  if SameAsCurrent(Committed) then Exit;
  StackPush(UndoStack, Committed);
  New(s);
  Capture(s);
  Committed := s;
  StackClear(RedoStack);
end;

function CanUndo: Boolean;
begin
  Result := Length(UndoStack) > 0;
end;

function CanRedo: Boolean;
begin
  Result := Length(RedoStack) > 0;
end;

function Undo: Boolean;
begin
  HistCheck;   { an edit still pending becomes its own step first }
  Result := CanUndo;
  if not Result then Exit;
  StackPush(RedoStack, Committed);
  Committed := StackPop(UndoStack);
  Apply(Committed);
end;

function Redo: Boolean;
begin
  HistCheck;   { a fresh edit clears the redo list }
  Result := CanRedo;
  if not Result then Exit;
  StackPush(UndoStack, Committed);
  Committed := StackPop(RedoStack);
  Apply(Committed);
end;

end.
