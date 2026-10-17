unit fluid;

{ Fluid power: pneumatic and hydraulic circuits on a grid of their own,
  laid over the process grid like the electrical circuits.

  Every cell side is a node; lines join the sides they are connected to,
  neighbouring cells join where both are connected towards each other.
  Each frame the pressure (bar) of every net is worked out:
  - a running compressor / hydraulic pump holds its net at its pressure;
  - a receiver / accumulator stores pressure: it fills from a source and
    is drawn down by what runs (motors, moving cylinders);
  - exhausts, silencers, tanks and the exhaust ports of valves vent a net;
  - regulators / FRLs pass on at most their setting, check valves one way
    only, shuttle valves the higher and two-pressure valves the lower of
    their inputs; a relief valve caps its inlet net at its setting;
  - directional valves (3/2, 5/2, 5/3, 4/2, 4/3) join their ports by their
    position: manual, push button, solenoid with spring return or double
    solenoid (it stays where it was put), the solenoids being electrical
    coils (their tags);
  - cylinders move by the pressure on their sides, as fast as their
    throttles let them; their limit switches (tag + 0 retracted, tag + 1
    extended) and the pressure switches are contacts for the electrical
    circuits; cylinders, motors and sources run the equipment named in Ref. }

{$mode objfpc}{$H+}

interface

uses
  simcore, elec;

type
  TFKind = (fkNone, fkLine, fkCross, fkCompressor, fkHPump, fkReceiver, fkAccum, fkFRL, fkRegulator, fkFilter,
    fkCheck, fkThrottle, fkShuttle, fkAndValve, fkRelief, fkV32, fkV52, fkV53, fkV42, fkV43,
    fkCylSA, fkCylDA, fkAirMotor, fkHydMotor, fkSilencer, fkTank, fkGauge, fkPSwitch);

  PFCell = ^TFCell;
  TFCell = record
    Kind: TFKind;
    Conn: Byte;          { bit d = a line towards the neighbour in direction d (E S W N) }
    Dir: Byte;           { quarter turns of the symbol }
    Layer: Byte;
    Tag: string[12];     { 1V1, 1A, P1 ... }
    Ref: string[24];     { the equipment a cylinder / motor / source runs }
    SolA, SolB: string[12];  { valve: solenoid tags (position 1 / 2); source: the tag that switches it on }
    Act: Byte;           { valve: 0 manual, 1 push button, 2 solenoid + spring, 3 double solenoid;
                           pressure switch: 0 closes when high, 1 closes when low }
    Sel: Byte;           { valve position 0 (rest / centre), 1, 2 }
    On: Boolean;         { a source switched on }
    P1, P2: Single;      { source bar; regulator / relief bar; throttle %; cylinder stroke s;
                           pressure switch: P1 upper, P2 lower bar }
    { worked out each frame (not saved) }
    Held: Boolean;       { a push-button valve held down }
    Pos: Single;         { cylinder: 0 retracted .. 1 extended }
    Store: Single;       { receiver / accumulator: bar }
    Press: array[0..3] of Single;   { the pressure on each side (bar) }
    Med: array[0..3] of Byte;       { 0 none, 1 air, 2 oil }
    Latch: Boolean;      { pressure switch closed }
    Running: Boolean;    { source running, motor turning, cylinder moving, relief blowing off }
  end;

const
  FKindNames: array[TFKind] of string = ('Empty', 'Line', 'Line crossing', 'Compressor', 'Hydraulic pump',
    'Air receiver', 'Accumulator', 'FRL unit', 'Pressure regulator', 'Filter', 'Check valve', 'Flow control',
    'Shuttle valve (OR)', 'Two-pressure valve (AND)', 'Relief valve', '3/2 valve', '5/2 valve', '5/3 valve',
    '4/2 valve', '4/3 valve', 'Single-acting cylinder', 'Double-acting cylinder', 'Air motor', 'Hydraulic motor',
    'Silencer / exhaust', 'Tank', 'Pressure gauge', 'Pressure switch');
  FKindTags: array[TFKind] of string = ('none', 'line', 'cross', 'compressor', 'hpump', 'receiver', 'accum', 'frl',
    'regulator', 'filter', 'check', 'throttle', 'shuttle', 'and', 'relief', 'v32', 'v52', 'v53', 'v42', 'v43',
    'cylsa', 'cylda', 'airmotor', 'hydmotor', 'silencer', 'tank', 'gauge', 'pswitch');
  ActNames: array[0..3] of string = ('Manual', 'Push button', 'Solenoid + spring', 'Double solenoid');

var
  FGrid: array[0..GW - 1, 0..GH - 1] of TFCell;

function FIsValve(K: TFKind): Boolean;
function FPositions(K: TFKind): Integer;
function FIsHydraulic(K: TFKind): Boolean;
function FEmpty(x, y: Integer): Boolean;
function FCount: Integer;
procedure FReset(x, y: Integer);
procedure FClearAll;
procedure FPlace(x, y: Integer; K: TFKind; ADir: Integer = 0);
procedure FConnect(x1, y1, x2, y2: Integer);
procedure FLineRun(x1, y1, x2, y2: Integer);
procedure FErase(x, y: Integer);
procedure FRotate(x, y: Integer);
{ a click with the Select tool: a manual valve steps, a source switches }
function FOperate(x, y: Integer): string;
procedure FPress(x, y: Integer; Down: Boolean);
function FOperable(x, y: Integer): Boolean;
function FStateText(x, y: Integer): string;
{ the side (E S W N) of a port of the cell: Base before turning }
function FSide(const c: TFCell; Base: Integer): Integer;
procedure SolveFluid(dt: Single; Running: Boolean);

implementation

uses
  SysUtils, Math;

const
  { port bases (before the cell is turned): E 0, S 1, W 2, N 3 }
  PORT_P = 1;
  PORT_A = 2;
  PORT_B = 0;
  PORT_R = 3;

var
  Par: array of Integer;
  NodeP: array of Single;     { each node's pressure last frame }
  NodeM: array of Byte;
  NP, NSrc, NStoreP, NFed, NFactor: array of Single;
  NVent, NHasStore: array of Boolean;
  NMed: array of Byte;

function FIsValve(K: TFKind): Boolean;
begin
  Result := K in [fkV32, fkV52, fkV53, fkV42, fkV43];
end;

function FPositions(K: TFKind): Integer;
begin
  if K in [fkV53, fkV43] then Result := 3 else Result := 2;
end;

function FIsHydraulic(K: TFKind): Boolean;
begin
  Result := K in [fkHPump, fkAccum, fkRelief, fkV42, fkV43, fkHydMotor, fkTank];
end;

function FEmpty(x, y: Integer): Boolean;
begin
  Result := (not InGrid(x, y)) or (FGrid[x, y].Kind = fkNone);
end;

function FCount: Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if FGrid[x, y].Kind <> fkNone then Inc(Result);
end;

procedure FReset(x, y: Integer);
begin
  FillChar(FGrid[x, y], SizeOf(TFCell), 0);
  FGrid[x, y].Kind := fkNone;
end;

procedure FClearAll;
var
  x, y: Integer;
begin
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      FReset(x, y);
end;

function FSide(const c: TFCell; Base: Integer): Integer;
begin
  Result := (Base + c.Dir) and 3;
end;

{ the port bases of a kind; -1 = no more }
function PortBase(K: TFKind; i: Integer): Integer;
const
  Ports: array[TFKind, 0..3] of ShortInt = (
    (-1, -1, -1, -1),          { none }
    (-1, -1, -1, -1),          { line: its connections }
    (0, 1, 2, 3),              { cross }
    (0, -1, -1, -1),           { compressor: out E }
    (0, -1, -1, -1),           { hydraulic pump }
    (-1, -1, -1, -1),          { receiver: its connections }
    (-1, -1, -1, -1),          { accumulator }
    (2, 0, -1, -1),            { FRL: in W, out E }
    (2, 0, -1, -1),            { regulator }
    (2, 0, -1, -1),            { filter }
    (2, 0, -1, -1),            { check }
    (2, 0, -1, -1),            { throttle }
    (2, 0, 3, -1),             { shuttle: in W, E, out N }
    (2, 0, 3, -1),             { and }
    (2, 0, -1, -1),            { relief: in W, out E (tank) }
    (1, 2, 3, -1),             { 3/2: P, A, R }
    (1, 2, 0, 3),              { 5/2: P, A, B, R }
    (1, 2, 0, 3),              { 5/3 }
    (1, 2, 0, 3),              { 4/2 }
    (1, 2, 0, 3),              { 4/3 }
    (2, -1, -1, -1),           { single-acting cylinder: A }
    (2, 1, -1, -1),            { double-acting: A W, B S }
    (2, 0, -1, -1),            { air motor: in W, out E }
    (2, 0, -1, -1),            { hydraulic motor }
    (-1, -1, -1, -1),          { silencer: its connections }
    (-1, -1, -1, -1),          { tank }
    (1, -1, -1, -1),           { gauge: S }
    (1, -1, -1, -1));          { pressure switch }
begin
  Result := Ports[K, i];
end;

procedure FPlace(x, y: Integer; K: TFKind; ADir: Integer = 0);
var
  c: PFCell;
  conn: Byte;
  i, b, d, nx, ny: Integer;
  keepTag: string;
begin
  if not InGrid(x, y) then Exit;
  c := @FGrid[x, y];
  conn := c^.Conn;
  keepTag := '';
  if c^.Kind = K then keepTag := c^.Tag;
  FReset(x, y);
  c^.Kind := K;
  c^.Conn := conn;
  c^.Layer := CurLayer;
  c^.Tag := keepTag;
  c^.Dir := ADir and 3;
  case K of
    fkCompressor: begin c^.On := True; c^.P1 := 8; end;
    fkHPump: begin c^.On := True; c^.P1 := 120; end;
    fkFRL, fkRegulator: c^.P1 := 6;
    fkRelief: c^.P1 := 100;
    fkThrottle: c^.P1 := 50;
    fkCylSA, fkCylDA: c^.P1 := 2;
    fkPSwitch: begin c^.P1 := 7; c^.P2 := 5; end;
    fkV52, fkV53, fkV42, fkV43, fkV32: c^.Act := 0;
  end;
  for i := 0 to 3 do
  begin
    b := PortBase(K, i);
    if b >= 0 then c^.Conn := c^.Conn or (1 shl FSide(c^, b));
  end;
  for d := 0 to 3 do
    if (c^.Conn and (1 shl d)) <> 0 then
    begin
      nx := x + DXS[d];
      ny := y + DYS[d];
      if InGrid(nx, ny) and (FGrid[nx, ny].Kind <> fkNone) then
        FGrid[nx, ny].Conn := FGrid[nx, ny].Conn or (1 shl Opp(d));
    end;
end;

procedure FConnect(x1, y1, x2, y2: Integer);
var
  d: Integer;
begin
  if not (InGrid(x1, y1) and InGrid(x2, y2)) then Exit;
  for d := 0 to 3 do
    if (x1 + DXS[d] = x2) and (y1 + DYS[d] = y2) then
    begin
      FGrid[x1, y1].Conn := FGrid[x1, y1].Conn or (1 shl d);
      FGrid[x2, y2].Conn := FGrid[x2, y2].Conn or (1 shl Opp(d));
    end;
end;

procedure LineAt(x, y: Integer);
begin
  if InGrid(x, y) and (FGrid[x, y].Kind = fkNone) then
  begin
    FReset(x, y);
    FGrid[x, y].Kind := fkLine;
    FGrid[x, y].Layer := CurLayer;
  end;
end;

procedure FLineRun(x1, y1, x2, y2: Integer);
var
  x, y, s: Integer;
begin
  LineAt(x1, y1);
  x := x1;
  y := y1;
  if x2 > x1 then s := 1 else s := -1;
  while x <> x2 do
  begin
    LineAt(x + s, y);
    FConnect(x, y, x + s, y);
    x := x + s;
  end;
  if y2 > y1 then s := 1 else s := -1;
  while y <> y2 do
  begin
    LineAt(x, y + s);
    FConnect(x, y, x, y + s);
    y := y + s;
  end;
end;

procedure FErase(x, y: Integer);
var
  d, nx, ny: Integer;
begin
  if not InGrid(x, y) then Exit;
  for d := 0 to 3 do
  begin
    nx := x + DXS[d];
    ny := y + DYS[d];
    if InGrid(nx, ny) then FGrid[nx, ny].Conn := FGrid[nx, ny].Conn and not (1 shl Opp(d));
  end;
  FReset(x, y);
end;

procedure FRotate(x, y: Integer);
var
  c: PFCell;
begin
  if not InGrid(x, y) then Exit;
  c := @FGrid[x, y];
  if c^.Kind in [fkNone, fkLine, fkCross, fkReceiver, fkAccum, fkSilencer, fkTank] then Exit;
  c^.Dir := (c^.Dir + 1) and 3;
  c^.Conn := ((c^.Conn shl 1) or (c^.Conn shr 3)) and 15;
end;

function FOperable(x, y: Integer): Boolean;
var
  c: PFCell;
begin
  c := @FGrid[x, y];
  Result := (c^.Kind in [fkCompressor, fkHPump]) or (FIsValve(c^.Kind) and (c^.Act <= 1));
end;

function FOperate(x, y: Integer): string;
var
  c: PFCell;
begin
  Result := '';
  if not InGrid(x, y) then Exit;
  c := @FGrid[x, y];
  if c^.Kind in [fkCompressor, fkHPump] then
  begin
    c^.On := not c^.On;
    if c^.On then Result := 'ON' else Result := 'OFF';
  end
  else if FIsValve(c^.Kind) and (c^.Act = 0) then
  begin
    c^.Sel := (c^.Sel + 1) mod FPositions(c^.Kind);
    Result := Format('position %d', [c^.Sel]);
  end;
end;

procedure FPress(x, y: Integer; Down: Boolean);
begin
  if InGrid(x, y) and FIsValve(FGrid[x, y].Kind) and (FGrid[x, y].Act = 1) then FGrid[x, y].Held := Down;
end;

function FStateText(x, y: Integer): string;
var
  c: PFCell;
begin
  c := @FGrid[x, y];
  case c^.Kind of
    fkLine, fkCross:
      if c^.Press[0] + c^.Press[1] + c^.Press[2] + c^.Press[3] > 0.05 then
        Result := Format('%.1f bar', [Max(Max(c^.Press[0], c^.Press[1]), Max(c^.Press[2], c^.Press[3]))])
      else Result := 'no pressure';
    fkCompressor, fkHPump:
      if c^.Running then Result := Format('RUNNING %.0f bar', [c^.P1])
      else if c^.On then Result := 'waiting (its tag is off)' else Result := 'OFF';
    fkReceiver, fkAccum: Result := Format('%.1f bar stored', [c^.Store]);
    fkFRL, fkRegulator: Result := Format('in %.1f / out %.1f bar (set %.1f)', [c^.Press[FSide(c^, 2)], c^.Press[FSide(c^, 0)], c^.P1]);
    fkRelief:
      if c^.Running then Result := Format('BLOWING OFF at %.0f bar', [c^.P1])
      else Result := Format('closed (opens at %.0f bar)', [c^.P1]);
    fkThrottle: Result := Format('open %.0f%%', [c^.P1]);
    fkCylSA, fkCylDA:
      if c^.Pos >= 0.98 then Result := 'EXTENDED'
      else if c^.Pos <= 0.02 then Result := 'retracted'
      else Result := Format('moving, %.0f%%', [c^.Pos * 100]);
    fkAirMotor, fkHydMotor: if c^.Running then Result := 'TURNING' else Result := 'stopped';
    fkGauge: Result := Format('%.1f bar', [c^.Press[FSide(c^, 1)]]);
    fkPSwitch:
      if c^.Latch then Result := Format('CLOSED at %.1f bar', [c^.Press[FSide(c^, 1)]])
      else Result := Format('open at %.1f bar', [c^.Press[FSide(c^, 1)]]);
  else
    if FIsValve(c^.Kind) then Result := Format('position %d (%s)', [c^.Sel, ActNames[c^.Act]])
    else Result := '';
  end;
end;

{ ---------------------------------------------------------------- solving }

function Node(x, y, d: Integer): Integer; inline;
begin
  Result := (y * GW + x) * 4 + d;
end;

function Find(i: Integer): Integer;
var
  r, n: Integer;
begin
  r := i;
  while Par[r] <> r do r := Par[r];
  while Par[i] <> r do
  begin
    n := Par[i];
    Par[i] := r;
    i := n;
  end;
  Result := r;
end;

procedure Union(a, b: Integer);
var
  ra, rb: Integer;
begin
  ra := Find(a);
  rb := Find(b);
  if ra <> rb then Par[ra] := rb;
end;

function RootOf(x, y, Base: Integer): Integer;
begin
  Result := Find(Node(x, y, FSide(FGrid[x, y], Base)));
end;

procedure JoinAll(x, y: Integer);
var
  d, first: Integer;
begin
  first := -1;
  for d := 0 to 3 do
    if (FGrid[x, y].Conn and (1 shl d)) <> 0 then
    begin
      if first < 0 then first := d else Union(Node(x, y, d), Node(x, y, first));
    end;
end;

procedure J(x, y, b1, b2: Integer);
begin
  Union(Node(x, y, FSide(FGrid[x, y], b1)), Node(x, y, FSide(FGrid[x, y], b2)));
end;

{ the nets: lines, receivers, filters, throttles, the valves by their positions }
procedure BuildNets;
var
  x, y, d: Integer;
  c: PFCell;
begin
  for d := 0 to High(Par) do Par[d] := d;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @FGrid[x, y];
      case c^.Kind of
        fkLine, fkReceiver, fkAccum, fkSilencer, fkTank: JoinAll(x, y);
        fkCross:
          begin
            Union(Node(x, y, 0), Node(x, y, 2));
            Union(Node(x, y, 1), Node(x, y, 3));
          end;
        fkFilter, fkThrottle: J(x, y, 2, 0);
        fkV32:
          if c^.Sel = 1 then J(x, y, PORT_P, PORT_A) else J(x, y, PORT_A, PORT_R);
        fkV52, fkV42:
          if c^.Sel = 1 then
          begin
            J(x, y, PORT_P, PORT_A);
            J(x, y, PORT_B, PORT_R);
          end
          else
          begin
            J(x, y, PORT_P, PORT_B);
            J(x, y, PORT_A, PORT_R);
          end;
        fkV53, fkV43:
          case c^.Sel of
            1:
              begin
                J(x, y, PORT_P, PORT_A);
                J(x, y, PORT_B, PORT_R);
              end;
            2:
              begin
                J(x, y, PORT_P, PORT_B);
                J(x, y, PORT_A, PORT_R);
              end;
          else
            if c^.Kind = fkV43 then J(x, y, PORT_P, PORT_R);   { tandem centre: the pump unloads to tank }
          end;
      end;
    end;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @FGrid[x, y];
      if c^.Kind = fkNone then Continue;
      if ((c^.Conn and 1) <> 0) and (x + 1 < GW) and (FGrid[x + 1, y].Kind <> fkNone) and
        ((FGrid[x + 1, y].Conn and 4) <> 0) then Union(Node(x, y, 0), Node(x + 1, y, 2));
      if ((c^.Conn and 2) <> 0) and (y + 1 < GH) and (FGrid[x, y + 1].Kind <> fkNone) and
        ((FGrid[x, y + 1].Conn and 8) <> 0) then Union(Node(x, y, 1), Node(x, y + 1, 3));
    end;
end;

procedure SolveFluid(dt: Single; Running: Boolean);
var
  x, y, d, n, i, r, ra, rb, pass, nStores, k: Integer;
  c: PFCell;
  pa, pb, f, v, demand, pin: Single;
  extend, retract, src: Boolean;
begin
  if FCount = 0 then Exit;
  n := GW * GH * 4;
  if Length(Par) <> n then
  begin
    SetLength(Par, n);
    SetLength(NodeP, n);
    SetLength(NodeM, n);
    SetLength(NP, n);
    SetLength(NSrc, n);
    SetLength(NStoreP, n);
    SetLength(NFed, n);
    SetLength(NFactor, n);
    SetLength(NVent, n);
    SetLength(NHasStore, n);
    SetLength(NMed, n);
    for i := 0 to n - 1 do
    begin
      NodeP[i] := 0;
      NodeM[i] := 0;
    end;
  end;
  { valve positions from solenoids and buttons; sources from their switch tag }
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @FGrid[x, y];
      if FIsValve(c^.Kind) then
        case c^.Act of
          1: c^.Sel := Ord(c^.Held);
          2:
            if TagActive(c^.SolA) then c^.Sel := 1
            else if (FPositions(c^.Kind) = 3) and TagActive(c^.SolB) then c^.Sel := 2
            else c^.Sel := 0;
          3:
            if TagActive(c^.SolA) then c^.Sel := 1
            else if TagActive(c^.SolB) then
            begin
              if FPositions(c^.Kind) = 3 then c^.Sel := 2 else c^.Sel := 0;
            end
            else if FPositions(c^.Kind) = 3 then c^.Sel := 0;
        end
      else if c^.Kind in [fkCompressor, fkHPump] then
        c^.Running := c^.On and ((c^.SolA = '') or TagActive(c^.SolA));
    end;
  BuildNets;
  for i := 0 to n - 1 do
  begin
    NSrc[i] := 0;
    NStoreP[i] := 0;
    NHasStore[i] := False;
    NVent[i] := False;
    NFed[i] := -1;
    NFactor[i] := 1;
    NMed[i] := 0;
    NP[i] := 0;
  end;
  { what each net holds from last frame (a closed-off line keeps its pressure, slowly leaking) }
  for i := 0 to n - 1 do
  begin
    r := Find(i);
    NP[r] := Max(NP[r], NodeP[i] * (1 - 0.05 * dt));
    if NodeM[i] > NMed[r] then NMed[r] := NodeM[i];
  end;
  nStores := 0;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @FGrid[x, y];
      case c^.Kind of
        fkCompressor, fkHPump:
          if c^.Running then
          begin
            r := RootOf(x, y, 0);
            NSrc[r] := Max(NSrc[r], c^.P1);
            if c^.Kind = fkHPump then NMed[r] := 2 else NMed[r] := 1;
          end;
        fkReceiver, fkAccum:
          for d := 0 to 3 do
            if (c^.Conn and (1 shl d)) <> 0 then
            begin
              r := Find(Node(x, y, d));
              NHasStore[r] := True;
              NStoreP[r] := Max(NStoreP[r], c^.Store);
              Inc(nStores);
              Break;
            end;
        fkSilencer, fkTank:
          for d := 0 to 3 do
            if (c^.Conn and (1 shl d)) <> 0 then NVent[Find(Node(x, y, d))] := True;
        fkRelief: NVent[RootOf(x, y, 0)] := True;
        fkAirMotor: NVent[RootOf(x, y, 0)] := True;   { its exhaust }
        fkV32, fkV52, fkV53, fkV42, fkV43: NVent[RootOf(x, y, PORT_R)] := True;
        fkThrottle:
          begin
            r := RootOf(x, y, 2);
            NFactor[r] := Min(NFactor[r], Max(0.02, c^.P1 / 100));
          end;
      end;
    end;
  { the pressure of every net }
  for i := 0 to n - 1 do
  begin
    if Par[i] <> i then Continue;
    if NHasStore[i] then
    begin
      { an air receiver fills in seconds, a hydraulic accumulator faster }
      if NSrc[i] > 0 then NStoreP[i] := NStoreP[i] + (NSrc[i] - NStoreP[i]) * Min(1, IfThen(NMed[i] = 2, 3, 0.8) * dt);
      NP[i] := NStoreP[i];
    end
    else if NSrc[i] > 0 then NP[i] := NSrc[i];
    if NVent[i] then
    begin
      if NHasStore[i] then
      begin
        NStoreP[i] := Max(0, NStoreP[i] - 6 * dt);
        NP[i] := NStoreP[i] * 0.3;
      end
      else if NSrc[i] > 0 then
      begin
        { a source blowing straight out; a pump unloading to its tank }
        if NMed[i] = 2 then NP[i] := NSrc[i] * 0.03 else NP[i] := NSrc[i] * 0.3;
      end
      else NP[i] := 0;
    end;
  end;
  { one-way elements: regulators, checks, shuttle / two-pressure valves }
  for pass := 1 to 8 do
  begin
    for y := 0 to GH - 1 do
      for x := 0 to GW - 1 do
      begin
        c := @FGrid[x, y];
        case c^.Kind of
          fkFRL, fkRegulator, fkCheck:
            begin
              pin := NP[RootOf(x, y, 2)];
              if c^.Kind <> fkCheck then pin := Min(pin, c^.P1);
              r := RootOf(x, y, 0);
              NFed[r] := Max(NFed[r], pin);
              if NMed[RootOf(x, y, 2)] > 0 then NMed[r] := NMed[RootOf(x, y, 2)];
            end;
          fkShuttle, fkAndValve:
            begin
              ra := RootOf(x, y, 2);
              rb := RootOf(x, y, 0);
              if c^.Kind = fkShuttle then pin := Max(NP[ra], NP[rb]) else pin := Min(NP[ra], NP[rb]);
              r := RootOf(x, y, 3);
              NFed[r] := Max(NFed[r], pin);
              NMed[r] := Max(NMed[ra], NMed[rb]);
            end;
        end;
      end;
    for i := 0 to n - 1 do
      if (Par[i] = i) and (NFed[i] >= 0) and (NSrc[i] = 0) and not NHasStore[i] then
      begin
        if NVent[i] then NP[i] := NFed[i] * 0.3 else NP[i] := NFed[i];
        NFed[i] := -1;
      end;
  end;
  { relief valves cap their inlet }
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if FGrid[x, y].Kind = fkRelief then
      begin
        c := @FGrid[x, y];
        r := RootOf(x, y, 2);
        c^.Running := NP[r] > c^.P1 + 0.01;
        if c^.Running then
        begin
          NP[r] := c^.P1;
          if NHasStore[r] then NStoreP[r] := Min(NStoreP[r], c^.P1);
        end;
      end;
  { cylinders, motors and switches; what they use draws the stores down }
  demand := 0;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @FGrid[x, y];
      case c^.Kind of
        fkCylSA, fkCylDA:
          begin
            ra := RootOf(x, y, 2);
            pa := NP[ra];
            f := NFactor[ra];
            if c^.Kind = fkCylDA then
            begin
              rb := RootOf(x, y, 1);
              pb := NP[rb];
              f := Min(f, NFactor[rb]);
              extend := pa - pb > 0.5;
              retract := pb - pa > 0.5;
            end
            else
            begin
              extend := pa > 1;
              retract := pa < 0.5;   { the spring }
            end;
            v := f / Max(0.2, c^.P1);
            c^.Running := False;
            if Running then
            begin
              if extend and (c^.Pos < 1) then
              begin
                c^.Pos := Min(1, c^.Pos + v * dt);
                c^.Running := True;
              end
              else if retract and (c^.Pos > 0) then
              begin
                c^.Pos := Max(0, c^.Pos - v * dt);
                c^.Running := True;
              end;
            end;
            if c^.Running then demand := demand + 0.4;
            i := EquipByName(c^.Ref);
            if i >= 0 then
            begin
              Equips[i].Level := c^.Pos * 100;
              if Equips[i].State in [EQS_STOP, EQS_RUN] then
                if c^.Pos >= 0.98 then Equips[i].State := EQS_RUN else Equips[i].State := EQS_STOP;
            end;
          end;
        fkAirMotor, fkHydMotor:
          begin
            ra := RootOf(x, y, 2);
            rb := RootOf(x, y, 0);
            pa := NP[ra];
            pb := NP[rb];
            if c^.Kind = fkAirMotor then pb := 0;
            c^.Running := pa - pb > 0.5;
            f := Min(NFactor[ra], NFactor[rb]);
            if c^.Running then demand := demand + 1.5 * f;
            i := EquipByName(c^.Ref);
            if (i >= 0) and (Equips[i].State in [EQS_STOP, EQS_RUN]) then
            begin
              if c^.Running then
              begin
                if Equips[i].State <> EQS_RUN then Equips[i].RunTime := 0;
                Equips[i].State := EQS_RUN;
                Equips[i].Level := f * 100;
              end
              else
                Equips[i].State := EQS_STOP;
            end;
          end;
        fkCompressor, fkHPump:
          begin
            i := EquipByName(c^.Ref);
            if (i >= 0) and (Equips[i].State in [EQS_STOP, EQS_RUN]) then
              if c^.Running then Equips[i].State := EQS_RUN else Equips[i].State := EQS_STOP;
          end;
        fkPSwitch:
          begin
            pa := NP[RootOf(x, y, 1)];
            if c^.Act = 0 then
            begin
              if pa >= c^.P1 then c^.Latch := True else if pa <= c^.P2 then c^.Latch := False;
            end
            else if pa <= c^.P2 then c^.Latch := True
            else if pa >= c^.P1 then c^.Latch := False;
          end;
      end;
    end;
  { the stores: what was used comes out of them; write them back }
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @FGrid[x, y];
      if not (c^.Kind in [fkReceiver, fkAccum]) then Continue;
      for d := 0 to 3 do
        if (c^.Conn and (1 shl d)) <> 0 then
        begin
          r := Find(Node(x, y, d));
          src := NSrc[r] > 0;
          c^.Store := NStoreP[r];
          if Running and (nStores > 0) and not src then
            c^.Store := Max(0, c^.Store - demand * dt / Max(1, nStores));
          Break;
        end;
    end;
  { remember each node's pressure, and show it on every cell side }
  for i := 0 to n - 1 do
  begin
    r := Find(i);
    NodeP[i] := NP[r];
    NodeM[i] := NMed[r];
  end;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @FGrid[x, y];
      if c^.Kind = fkNone then Continue;
      for d := 0 to 3 do
      begin
        k := Node(x, y, d);
        c^.Press[d] := NodeP[k];
        c^.Med[d] := NodeM[k];
      end;
    end;
end;

{ ---------------------------------------------------------------- the electrical side }

{ limit switches (tag + 0 / tag + 1) and pressure switches are contacts }
function FluidTagActive(const Tag: string): Boolean;
var
  x, y: Integer;
  c: PFCell;
begin
  Result := False;
  if Tag = '' then Exit;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @FGrid[x, y];
      case c^.Kind of
        fkCylSA, fkCylDA:
          if c^.Tag <> '' then
          begin
            if SameText(Tag, c^.Tag + '0') and (c^.Pos <= 0.02) then Exit(True);
            if SameText(Tag, c^.Tag + '1') and (c^.Pos >= 0.98) then Exit(True);
          end;
        fkPSwitch:
          if SameText(Tag, c^.Tag) and c^.Latch then Exit(True);
      end;
    end;
end;

{ a limit switch (cylinder tag + 0 / 1) or pressure switch with this tag is on this page }
function FluidTagDefined(const Tag: string): Boolean;
var
  x, y: Integer;
  c: PFCell;
begin
  Result := False;
  if Tag = '' then Exit;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @FGrid[x, y];
      if c^.Tag = '' then Continue;
      case c^.Kind of
        fkCylSA, fkCylDA:
          if SameText(Tag, c^.Tag + '0') or SameText(Tag, c^.Tag + '1') then Exit(True);
        fkPSwitch:
          if SameText(Tag, c^.Tag) then Exit(True);
      end;
    end;
end;

{ the i-th limit / pressure switch tag that is on now, '' after the last }
function FluidActiveTag(i: Integer): string;
var
  x, y, n: Integer;
  c: PFCell;
  s: string;
begin
  Result := '';
  n := 0;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @FGrid[x, y];
      if c^.Tag = '' then Continue;
      s := '';
      case c^.Kind of
        fkCylSA, fkCylDA:
          if c^.Pos <= 0.02 then s := c^.Tag + '0'
          else if c^.Pos >= 0.98 then s := c^.Tag + '1';
        fkPSwitch:
          if c^.Latch then s := c^.Tag;
      end;
      if s = '' then Continue;
      if n = i then Exit(s);
      Inc(n);
    end;
end;

{ gauges, switches, sources, stores (bar) and cylinders (%) for gauges and displays }
function FluidAnalog(const Src: string; out Value: Single; out UnitS: string): Boolean;
var
  x, y: Integer;
  c: PFCell;
begin
  Result := False;
  Value := 0;
  UnitS := '';
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @FGrid[x, y];
      if (c^.Kind = fkNone) or (c^.Tag = '') or not SameText(c^.Tag, Src) then Continue;
      Result := True;
      UnitS := 'bar';
      case c^.Kind of
        fkGauge, fkPSwitch: Value := c^.Press[FSide(c^, 1)];
        fkReceiver, fkAccum: Value := c^.Store;
        fkCompressor, fkHPump: Value := c^.Press[FSide(c^, 0)];
        fkCylSA, fkCylDA: begin Value := c^.Pos * 100; UnitS := '%'; end;
      else
        Value := Max(Max(c^.Press[0], c^.Press[1]), Max(c^.Press[2], c^.Press[3]));
      end;
      Exit;
    end;
end;

{ the i-th name a gauge can show }
function FluidSourceName(i: Integer): string;
var
  x, y, n: Integer;
begin
  n := 0;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (FGrid[x, y].Kind in [fkGauge, fkPSwitch, fkReceiver, fkAccum, fkCompressor, fkHPump, fkCylSA, fkCylDA]) and
        (FGrid[x, y].Tag <> '') then
      begin
        if n = i then Exit(FGrid[x, y].Tag);
        Inc(n);
      end;
  Result := '';
end;

procedure FluidHookProc(dt: Single; Running: Boolean);
begin
  SolveFluid(dt, Running);
end;

initialization
  FClearAll;
  FluidHook := @FluidHookProc;
  ClearHook2 := @FClearAll;
  ExtTagActive := @FluidTagActive;
  ExtAnalog := @FluidAnalog;
  ExtSourceName := @FluidSourceName;
  ExtTagDefined := @FluidTagDefined;
  ExtActiveTag := @FluidActiveTag;

end.
