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
  simcore, elec, fluid, flowchart;

type
  TCellLite = record
    Kind: TCellKind;
    Conn: Byte;
    Dia, Dir: Integer;
    Open: Boolean;
    Closed: Byte;
    Layer: Byte;
    Strength, AirPct, Feed: Single;
    Stock: array[TMat] of Single;
  end;

  TBucketLite = record
    Active: Boolean;
    Layer: Byte;
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
    Frms: array[0..MAX_FRAMES - 1] of TFrameObj;
    Tbls: array[0..MAX_TABLES - 1] of TTableObj;
    Lnks: array[0..MAX_LINKS - 1] of TLinkObj;
    Eqs: array[0..MAX_EQUIP - 1] of TEquipObj;
    ECells: array[0..GW - 1, 0..GH - 1] of TECell;
    FCells: array[0..GW - 1, 0..GH - 1] of TFCell;
    Flows: array[0..MAX_FLOW - 1] of TFlowNode;
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
  Result.Layer := c.Layer;
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
  KeepStock := KeepStock and IsStore(c^.Kind) and (c^.Kind = L.Kind);
  oldP := c^.P;
  oldStock := c^.Stock;
  ResetCell(x, y);
  c^.Kind := L.Kind;
  c^.Conn := L.Conn;
  c^.Dia := L.Dia;
  c^.Dir := L.Dir;
  c^.Open := L.Open;
  c^.Closed := L.Closed;
  c^.Layer := L.Layer;
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
    s^.Bkts[i].Layer := Buckets[i].Layer;
    s^.Bkts[i].X := Buckets[i].X;
    s^.Bkts[i].Y := Buckets[i].Y;
    s^.Bkts[i].W := Buckets[i].W;
    s^.Bkts[i].H := Buckets[i].H;
  end;
  s^.Lbls := Labels;
  s^.Frms := Frames;
  s^.Tbls := Tables;
  s^.Lnks := Links;
  s^.Eqs := Equips;
  s^.ECells := EGrid;
  s^.FCells := FGrid;
  s^.Flows := FlowNodes;
  s^.Gravity := GravityScale;
end;

function SamePins(const a, b: TEquipObj): Boolean;
var
  k, p: Integer;
begin
  Result := False;
  for k := 0 to TL_PINS - 1 do
  begin
    if a.Pins[k].Kind <> b.Pins[k].Kind then Exit;
    if a.Pins[k].Kind = TLP_NONE then Continue;
    if (a.Pins[k].T <> b.Pins[k].T) or (a.Pins[k].W <> b.Pins[k].W) or (a.Pins[k].Src <> b.Pins[k].Src) then Exit;
    for p := 0 to 2 do
      if (a.Pins[k].VMode[p] <> b.Pins[k].VMode[p]) or (a.Pins[k].V[p] <> b.Pins[k].V[p]) or
        (a.Pins[k].Dest[p] <> b.Pins[k].Dest[p]) then Exit;
  end;
  Result := True;
end;

function SameAsCurrent(s: PSnap): Boolean;
var
  x, y, i: Integer;
  e1, e2: PECell;
  f1, f2: PFCell;
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
      if (c^.Conn <> L^.Conn) or (c^.Dia <> L^.Dia) or (c^.Dir <> L^.Dir) or (c^.Open <> L^.Open) or (c^.Closed <> L^.Closed) or (c^.Layer <> L^.Layer) or
        (c^.Strength <> L^.Strength) or (c^.AirPct <> L^.AirPct) or (c^.Feed <> L^.Feed) then Exit;
    end;
  for i := 0 to MAX_BUCKETS - 1 do
  begin
    if Buckets[i].Active <> s^.Bkts[i].Active then Exit;
    if Buckets[i].Active and ((Buckets[i].X <> s^.Bkts[i].X) or (Buckets[i].Y <> s^.Bkts[i].Y) or
      (Buckets[i].W <> s^.Bkts[i].W) or (Buckets[i].H <> s^.Bkts[i].H) or (Buckets[i].Layer <> s^.Bkts[i].Layer)) then Exit;
  end;
  for i := 0 to MAX_LABELS - 1 do
  begin
    if Labels[i].Active <> s^.Lbls[i].Active then Exit;
    if Labels[i].Active and ((Labels[i].X <> s^.Lbls[i].X) or (Labels[i].Y <> s^.Lbls[i].Y) or
      (Labels[i].Text <> s^.Lbls[i].Text) or (Labels[i].Kind <> s^.Lbls[i].Kind) or
      (Labels[i].Fmt <> s^.Lbls[i].Fmt) or (Labels[i].Color <> s^.Lbls[i].Color) or
      (Labels[i].NoBox <> s^.Lbls[i].NoBox) or (Labels[i].Layer <> s^.Lbls[i].Layer) or (Labels[i].Scale <> s^.Lbls[i].Scale)) then Exit;
  end;
  for i := 0 to MAX_FRAMES - 1 do
  begin
    if Frames[i].Active <> s^.Frms[i].Active then Exit;
    if Frames[i].Active and ((Frames[i].X <> s^.Frms[i].X) or (Frames[i].Y <> s^.Frms[i].Y) or
      (Frames[i].W <> s^.Frms[i].W) or (Frames[i].H <> s^.Frms[i].H) or (Frames[i].Title <> s^.Frms[i].Title) or
      (Frames[i].Color <> s^.Frms[i].Color) or (Frames[i].Dashed <> s^.Frms[i].Dashed) or
      (Frames[i].Fill <> s^.Frms[i].Fill) or (Frames[i].Carry <> s^.Frms[i].Carry) or (Frames[i].Layer <> s^.Frms[i].Layer)) then Exit;
  end;
  { tables: all of it (it is only ever copied whole) }
  if CompareByte(Tables, s^.Tbls, SizeOf(Tables)) <> 0 then Exit;
  for i := 0 to MAX_LINKS - 1 do
  begin
    if Links[i].Active <> s^.Lnks[i].Active then Exit;
    if Links[i].Active and ((Links[i].X <> s^.Lnks[i].X) or (Links[i].Y <> s^.Lnks[i].Y) or
      (Links[i].Caption <> s^.Lnks[i].Caption) or (Links[i].ToPopup <> s^.Lnks[i].ToPopup) or
      (Links[i].Target <> s^.Lnks[i].Target) or (Links[i].Color <> s^.Lnks[i].Color) or
      (Links[i].Layer <> s^.Lnks[i].Layer)) then Exit;
  end;
  for i := 0 to MAX_EQUIP - 1 do
  begin
    if Equips[i].Active <> s^.Eqs[i].Active then Exit;
    if Equips[i].Active and ((Equips[i].Kind <> s^.Eqs[i].Kind) or (Equips[i].X <> s^.Eqs[i].X) or
      (Equips[i].Y <> s^.Eqs[i].Y) or (Equips[i].W <> s^.Eqs[i].W) or (Equips[i].H <> s^.Eqs[i].H) or
      (Equips[i].Name <> s^.Eqs[i].Name) or (Equips[i].State <> s^.Eqs[i].State) or
      (Equips[i].Flip <> s^.Eqs[i].Flip) or (Equips[i].LinkX <> s^.Eqs[i].LinkX) or
      (Equips[i].LinkY <> s^.Eqs[i].LinkY) or
      ((Equips[i].Level <> s^.Eqs[i].Level) and not EquipIsWater(Equips[i].Kind)) or
      (Equips[i].Layer <> s^.Eqs[i].Layer) or (Equips[i].Mode <> s^.Eqs[i].Mode) or
      (Equips[i].SeqStep <> s^.Eqs[i].SeqStep) or (Equips[i].Delay <> s^.Eqs[i].Delay) or
      (Equips[i].DivA <> s^.Eqs[i].DivA) or (Equips[i].DivB <> s^.Eqs[i].DivB) or (Equips[i].Src <> s^.Eqs[i].Src) or (Equips[i].Src2 <> s^.Eqs[i].Src2) or
      (Equips[i].Src3 <> s^.Eqs[i].Src3) or (Equips[i].Src4 <> s^.Eqs[i].Src4) or
      (Equips[i].RMin <> s^.Eqs[i].RMin) or (Equips[i].RMax <> s^.Eqs[i].RMax) or not SamePins(Equips[i], s^.Eqs[i])) then Exit;
  end;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      e1 := @EGrid[x, y];
      e2 := @s^.ECells[x, y];
      if e1^.Kind <> e2^.Kind then Exit;
      if e1^.Kind = ekNone then Continue;
      if (e1^.Conn <> e2^.Conn) or (e1^.Dir <> e2^.Dir) or (e1^.Layer <> e2^.Layer) or (e1^.Tag <> e2^.Tag) or
        (e1^.Ref <> e2^.Ref) or (e1^.Pos <> e2^.Pos) or (e1^.NPos <> e2^.NPos) or (e1^.P1 <> e2^.P1) or
        (e1^.P2 <> e2^.P2) or (e1^.P3 <> e2^.P3) or (e1^.Src <> e2^.Src) then Exit;
    end;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      f1 := @FGrid[x, y];
      f2 := @s^.FCells[x, y];
      if f1^.Kind <> f2^.Kind then Exit;
      if f1^.Kind = fkNone then Continue;
      if (f1^.Conn <> f2^.Conn) or (f1^.Dir <> f2^.Dir) or (f1^.Layer <> f2^.Layer) or (f1^.Tag <> f2^.Tag) or
        (f1^.Ref <> f2^.Ref) or (f1^.SolA <> f2^.SolA) or (f1^.SolB <> f2^.SolB) or (f1^.Act <> f2^.Act) or
        (f1^.P1 <> f2^.P1) or (f1^.P2 <> f2^.P2) then Exit;
    end;
  for i := 0 to MAX_FLOW - 1 do
    with s^.Flows[i] do
    begin
      if Active <> FlowNodes[i].Active then Exit;
      if not Active then Continue;
      if (Kind <> FlowNodes[i].Kind) or (X <> FlowNodes[i].X) or (Y <> FlowNodes[i].Y) or (W <> FlowNodes[i].W) or
        (H <> FlowNodes[i].H) or (Caption <> FlowNodes[i].Caption) or (Src <> FlowNodes[i].Src) or
        (Op <> FlowNodes[i].Op) or (Value <> FlowNodes[i].Value) or (Target <> FlowNodes[i].Target) or
        (Act <> FlowNodes[i].Act) or (Next <> FlowNodes[i].Next) or (Next2 <> FlowNodes[i].Next2) or
        (RType <> FlowNodes[i].RType) or (Value2 <> FlowNodes[i].Value2) or (Period <> FlowNodes[i].Period) or
        (Layer <> FlowNodes[i].Layer) then Exit;
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
      Buckets[i].Layer := s^.Bkts[i].Layer;
      Buckets[i].X := s^.Bkts[i].X;
      Buckets[i].Y := s^.Bkts[i].Y;
      Buckets[i].W := s^.Bkts[i].W;
      Buckets[i].H := s^.Bkts[i].H;
    end
    else if Buckets[i].Active then
      DeleteBucket(i);
  Labels := s^.Lbls;
  Frames := s^.Frms;
  Tables := s^.Tbls;
  Links := s^.Lnks;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      if (EGrid[x, y].Kind = s^.ECells[x, y].Kind) and (EGrid[x, y].Kind <> ekNone) then
      begin
        s^.ECells[x, y].On := EGrid[x, y].On;
        s^.ECells[x, y].Sel := EGrid[x, y].Sel;
        s^.ECells[x, y].Tripped := EGrid[x, y].Tripped;
        s^.ECells[x, y].Acc := EGrid[x, y].Acc;
        s^.ECells[x, y].Latch := EGrid[x, y].Latch;
        s^.ECells[x, y].Held := EGrid[x, y].Held;
        s^.ECells[x, y].Val := EGrid[x, y].Val;
        s^.ECells[x, y].Out := EGrid[x, y].Out;
        s^.ECells[x, y].Integ := EGrid[x, y].Integ;
      end;
      EGrid[x, y] := s^.ECells[x, y];
      if (FGrid[x, y].Kind = s^.FCells[x, y].Kind) and (FGrid[x, y].Kind <> fkNone) then
      begin
        { what flows and moves stays as it is }
        s^.FCells[x, y].On := FGrid[x, y].On;
        s^.FCells[x, y].Sel := FGrid[x, y].Sel;
        s^.FCells[x, y].Pos := FGrid[x, y].Pos;
        s^.FCells[x, y].Store := FGrid[x, y].Store;
        s^.FCells[x, y].Press := FGrid[x, y].Press;
        s^.FCells[x, y].Latch := FGrid[x, y].Latch;
      end;
      FGrid[x, y] := s^.FCells[x, y];
    end;
  for i := 0 to MAX_EQUIP - 1 do
  begin
    if Equips[i].Active and s^.Eqs[i].Active and (Equips[i].Kind = s^.Eqs[i].Kind) then
    begin
      s^.Eqs[i].RunTime := Equips[i].RunTime;
      s^.Eqs[i].Phase := Equips[i].Phase;
      s^.Eqs[i].Heat := Equips[i].Heat;
      if EquipIsWater(Equips[i].Kind) then s^.Eqs[i].Level := Equips[i].Level;   { the water stays }
      s^.Eqs[i].SeqPos := Equips[i].SeqPos;
      s^.Eqs[i].SeqT := Equips[i].SeqT;
      s^.Eqs[i].ReqT := Equips[i].ReqT;
      s^.Eqs[i].LastReq := Equips[i].LastReq;
    end;
    Equips[i] := s^.Eqs[i];
  end;
  for i := 0 to MAX_FLOW - 1 do
  begin
    if FlowNodes[i].Active and s^.Flows[i].Active then
    begin
      { what the scan worked out stays }
      s^.Flows[i].Hit := FlowNodes[i].Hit;
      s^.Flows[i].Taken := FlowNodes[i].Taken;
      s^.Flows[i].Known := FlowNodes[i].Known;
      s^.Flows[i].Val := FlowNodes[i].Val;
      s^.Flows[i].UnitS := FlowNodes[i].UnitS;
      s^.Flows[i].BoolV := FlowNodes[i].BoolV;
      s^.Flows[i].Yes := FlowNodes[i].Yes;
      s^.Flows[i].Timer := FlowNodes[i].Timer;
    end;
    FlowNodes[i] := s^.Flows[i];
  end;
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
