unit elec;

{ Electrical circuits: wiring and devices on a grid of their own, laid over
  the process grid (a cell can hold a pipe and a wire at the same time).

  Every cell side is a node. A wire joins the sides it is connected to, two
  neighbouring cells join where both are connected towards each other. A
  two-terminal device (contact, switch, fuse, coil, lamp, motor ...) has its
  terminals on the W / E sides (Dir 0) or N / S sides (Dir 1); a conducting
  one (closed contact, intact fuse, breaker on ...) joins them.

  Each frame the nets are worked out with union-find:
  - a load (coil, timer, lamp, buzzer, motor, drive) is energized when one
    terminal is on a supply's L / + net and the other on its N / - net;
  - contacts follow the coil (relay, contactor), timer or overload with the
    same tag, like a ladder diagram; this repeats until nothing changes, so
    seal-in contacts and interlocks work;
  - L and N joined directly is a short circuit: the fuse or breaker on the
    way blows / trips (or the supply shuts down);
  - motor and drive loads start and stop the equipment whose name is in
    their Ref; an overload trips when that equipment is in fault; a float
    switch follows the water level of a pond / pool / well (or a silo bin). }

{$mode objfpc}{$H+}

interface

uses
  simcore;

type
  TEKind = (ekNone, ekWire, ekCross, ekTerminal, ekAC, ekDC, ekFuse, ekBreaker, ekSwitch, ekSw2, ekSw3,
    ekPBNO, ekPBNC, ekPBLatch, ekSelector, ekEStop, ekNO, ekNC, ekRelay, ekContactor, ekTimer, ekOL,
    ekLamp, ekBuzzer, ekMotor, ekDrive, ekFloat, ekCT, ekPot, ekSolenoid, ekCounter, ekLevelTx, ekPressTx,
    ekFlowTx, ekTempTx, ekSpeedTx, ekWeightTx, ekPhoto, ekController, ekHumidTx, ekPHTx);

  TEKindSet = set of TEKind;
  string12 = string[12];

  PECell = ^TECell;
  TECell = record
    Kind: TEKind;
    Conn: Byte;          { bit d = wired towards the neighbour in direction d (E S W N) }
    Dir: Byte;           { 0: terminals W-E, 1: N-S; 2-way / 3-way switch: 0..3 quarter turns }
    Layer: Byte;
    Tag: string[12];     { designation: K1, KM1, T1, S1, F2, H1 ... }
    Ref: string[24];     { the equipment a motor / drive / overload / float works with }
    Pos: Byte;           { selector: the position it closes in; float: 0 fill, 1 empty; lamp: colour; motor: 1 star }
    NPos: Byte;          { selector: 2 or 3 positions }
    Sel: Byte;           { selector, 2-way and 3-way switch: the position it is in now }
    On: Boolean;         { switch / breaker / latching button on; e-stop pressed; supply on }
    Tripped: Boolean;    { fuse blown, breaker / overload tripped, supply shorted }
    P1, P2: Single;      { timer preset s; float low / high %; drive speed %; motor rated A; overload trip A; pot %;
                           timer off time s (flasher); counter preset; controller set point / hysteresis or band }
    P3: Single;          { controller integral time s }
    Src: string[12];     { a drive's speed from this potentiometer / controller; a counter's reset; a controller's input }
    { worked out each frame (not saved) }
    Held: Boolean;       { a momentary push button held down }
    Latch: Boolean;      { a float switch's contact }
    Energized: Boolean;  { loads: powered; contacts: closed }
    Acc: Single;         { timer / motor: seconds powered; overload: seconds over its trip current }
    Amps: Single;        { current: through a CT / overload, drawn by a load }
    Live: Byte;          { 0 dead, 1 on a live (L / +) net, 2 on a neutral (N / -) net }
    Val: Single;         { a sensor's reading; a controller's actual value (PV) }
    Out: Single;         { a controller's output 0..100 % }
    Integ: Single;       { a controller's integral }
  end;

const
  EKindNames: array[TEKind] of string = ('Empty', 'Wire', 'Wire crossing', 'Terminal', 'AC supply',
    'DC supply', 'Fuse', 'Circuit breaker', 'Switch', '2-way switch', '3-way switch', 'Push button NO',
    'Push button NC', 'Push on / push off', 'Selector switch', 'E-Stop', 'NO contact', 'NC contact',
    'Relay coil', 'Magnetic contactor', 'Timer', 'Overload relay', 'Lamp', 'Buzzer', 'Motor',
    'Drive (VFD)', 'Float switch', 'Current transformer', 'Potentiometer',
    'Valve solenoid', 'Counter', 'Level sensor', 'Pressure sensor', 'Flow sensor', 'Temperature sensor',
    'Speed sensor', 'Weight sensor', 'Photo sensor', 'Controller', 'Humidity sensor', 'pH sensor');
  EKindTags: array[TEKind] of string = ('none', 'wire', 'cross', 'terminal', 'ac', 'dc', 'fuse', 'breaker',
    'switch', 'sw2', 'sw3', 'pbno', 'pbnc', 'pblatch', 'selector', 'estop', 'no', 'nc', 'relay', 'contactor',
    'timer', 'overload', 'lamp', 'buzzer', 'motor', 'drive', 'float', 'ct', 'pot', 'solenoid', 'counter', 'lt', 'pt',
    'ft', 'tt', 'st', 'wt', 'photo', 'controller', 'mt', 'ph');
  TimerModeNames: array[0..3] of string = ('On-delay', 'Off-delay', 'Pulse', 'Flasher');
  CtrlModeNames: array[0..3] of string = ('On/off, on below SP', 'On/off, on above SP', 'PID, direct', 'PID, reverse');
  { the analog sensors and what they read in }
  SensorKinds: TEKindSet = [ekLevelTx, ekPressTx, ekFlowTx, ekTempTx, ekSpeedTx, ekWeightTx, ekHumidTx, ekPHTx];
  { equipment with temperatures in and out: NAME (outlet C), NAME.IN, NAME.HOT, NAME.KW }
  ThermalKinds = [EQ_HEATEX, EQ_COOLTOWER, EQ_CHILLER];
  HumidModeNames: array[0..1] of string = ('Air RH', 'Material');
  LampColorNames: array[0..4] of string = ('Green', 'Red', 'Yellow', 'White', 'Blue');

var
  EGrid: array[0..GW - 1, 0..GH - 1] of TECell;
  { set by the fluid power unit: limit / pressure switches as contacts, pressures for gauges }
  ExtTagActive: function(const Tag: string): Boolean = nil;
  ExtAnalog: function(const Src: string; out Value: Single; out UnitS: string): Boolean = nil;
  ExtSourceName: function(i: Integer): string = nil;
  { a pneumatic / hydraulic tag exists on this page; the i-th one that is on now ('' after the last) }
  ExtTagDefined: function(const Tag: string): Boolean = nil;
  ExtActiveTag: function(i: Integer): string = nil;
  { set by the flow chart unit: a Tag ON action reached in this scan; such a tag on this page; the i-th one on }
  ExtFlowTag: function(const Tag: string): Boolean = nil;
  ExtFlowTagDefined: function(const Tag: string): Boolean = nil;
  ExtFlowTagName: function(i: Integer): string = nil;
  { set by the flow chart unit: a Random node's value by its name; the i-th name }
  ExtFlowValue: function(const Name: string; out V: Single): Boolean = nil;
  ExtFlowSigName: function(i: Integer): string = nil;

function EIsLoad(K: TEKind): Boolean;
{ the Select tool works it: switches, buttons, breakers ... }
function EIsOperable(K: TEKind): Boolean;
function EIsMomentary(K: TEKind): Boolean;
function EHasRef(K: TEKind): Boolean;
function EEmpty(x, y: Integer): Boolean;

procedure EReset(x, y: Integer);
procedure EClearAll;
{ put a device at x,y (keeping its wiring); a wire cell for ekWire }
procedure EPlace(x, y: Integer; K: TEKind);
procedure EConnect(x1, y1, x2, y2: Integer);
{ an L-shaped run of wire: along x first, then along y }
procedure EWireLine(x1, y1, x2, y2: Integer);
procedure EErase(x, y: Integer);
procedure ERotate(x, y: Integer);
{ a click with the Select tool: switch over, step a selector, reset a trip ... }
function EOperate(x, y: Integer): string;
{ a momentary push button pressed / let go }
procedure EPress(x, y: Integer; Down: Boolean);
{ every selector with the tag of x,y to position p (0-based) }
procedure ESetSelectorPos(x, y, p: Integer);
{ the coil / timer / overload with this tag is active }
function TagActive(const Tag: string): Boolean;
{ the contact is closed (conducts) now }
function EConducts(x, y: Integer): Boolean;
function EStateText(x, y: Integer): string;
function ECount: Integer;
{ the level (%) of the equipment called Name, -1 if there is none with a level }
function EquipLevelByName(const Name: string): Single;
function EquipByName(const Name: string): Integer;
{ an analog value by name: a CT / overload / motor (A), potentiometer / drive (%), supply (V), timer (s),
  or the level / speed of the equipment called that; False when there is none }
function AnalogValue(const Src: string; out Value: Single; out UnitS: string): Boolean;
{ the names a gauge / display can show, one after another }
function NextAnalogSource(const Cur: string; Dir: Integer): string;
{ a drive's speed now: its own setting or its potentiometer }
function DriveSpeed(x, y: Integer): Single;
{ a part with this tag is on this page (or a fluid power switch, a flow chart tag), or another page has it on }
function ETagKnown(const Tag: string): Boolean;
{ the part of kind K with this tag; False when there is none }
function ECellByTag(const Tag: string; K: TEKind; out x, y: Integer): Boolean;
{ the unit of a sensor's reading }
function SensorUnit(const c: TECell): string;
{ a tag is on: an active coil / timer / counter / controller, or a closed switch, button or photo sensor with that tag }
function ESignal(const Tag: string): Boolean;
{ the timer / counter / controller with this tag as text for the Properties panel }
function ETimerActive(const c: TECell): Boolean;

procedure SolveElectric(dt: Single; Running: Boolean);
{ tell the other pages what this page has now (the plant bus) }
procedure ElecPublish(Page: Integer);

implementation

uses
  SysUtils, Math, plantbus, piecesim;

var
  Par: array of Integer;
  ActiveTags: array of string;
  NActiveTags: Integer = 0;

function EIsLoad(K: TEKind): Boolean;
begin
  Result := K in [ekRelay, ekContactor, ekTimer, ekLamp, ekBuzzer, ekMotor, ekDrive, ekSolenoid, ekCounter, ekController];
end;

function EIsOperable(K: TEKind): Boolean;
begin
  Result := K in [ekAC, ekDC, ekFuse, ekBreaker, ekSwitch, ekSw2, ekSw3, ekPBNO, ekPBNC, ekPBLatch, ekSelector,
    ekEStop, ekOL, ekCounter];
end;

function EIsMomentary(K: TEKind): Boolean;
begin
  Result := K in [ekPBNO, ekPBNC];
end;

function EHasRef(K: TEKind): Boolean;
begin
  Result := K in [ekOL, ekMotor, ekDrive, ekFloat, ekLevelTx, ekPressTx, ekTempTx, ekSpeedTx];
end;

function EEmpty(x, y: Integer): Boolean;
begin
  Result := (not InGrid(x, y)) or (EGrid[x, y].Kind = ekNone);
end;

procedure EReset(x, y: Integer);
begin
  FillChar(EGrid[x, y], SizeOf(TECell), 0);
  EGrid[x, y].Kind := ekNone;
end;

procedure EClearAll;
var
  x, y: Integer;
begin
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      EReset(x, y);
end;

{ the two terminal sides of a two-terminal device }
procedure TermSides(const c: TECell; out a, b: Integer);
begin
  if c.Dir = 1 then
  begin
    a := 3;
    b := 1;
  end
  else
  begin
    a := 2;
    b := 0;
  end;
end;

function Max2(n: Integer): Integer;
begin
  if n < 2 then Result := 2 else Result := n;
end;

function TwoTerminal(K: TEKind): Boolean;
begin
  Result := not (K in [ekNone, ekWire, ekCross, ekTerminal, ekSw2, ekSw3]);
end;

procedure EPlace(x, y: Integer; K: TEKind);
var
  c: PECell;
  conn: Byte;
  a, b, d, nx, ny: Integer;
  keepTag: string;
begin
  if not InGrid(x, y) then Exit;
  c := @EGrid[x, y];
  conn := c^.Conn;
  keepTag := '';
  if c^.Kind = K then keepTag := c^.Tag;
  EReset(x, y);
  c^.Kind := K;
  c^.Conn := conn;
  c^.Layer := CurLayer;
  c^.Tag := keepTag;
  { lie along the wire it is put on }
  if ((conn and (2 or 8)) <> 0) and ((conn and (1 or 4)) = 0) then c^.Dir := 1 else c^.Dir := 0;
  case K of
    ekAC, ekDC: c^.On := True;
    ekBreaker: c^.On := True;
    ekSelector: begin c^.NPos := 2; c^.Pos := 1; end;
    ekTimer: begin c^.P1 := 5; c^.P2 := 1; end;
    ekCounter: c^.P1 := 10;
    ekController: begin c^.P1 := 50; c^.P2 := 5; c^.P3 := 10; end;
    ekFloat: begin c^.P1 := 30; c^.P2 := 80; end;
    ekDrive: c^.P1 := 60;
    ekMotor: c^.P1 := 5;
    ekPot: c^.P1 := 50;
  end;
  if TwoTerminal(K) then
  begin
    TermSides(c^, a, b);
    c^.Conn := c^.Conn or (1 shl a) or (1 shl b);
  end
  else if K = ekSw2 then
    c^.Conn := c^.Conn or 1 or 2 or 4
  else if K = ekSw3 then
    c^.Conn := 15;
  { join up with what is already wired next to it }
  for d := 0 to 3 do
    if (c^.Conn and (1 shl d)) <> 0 then
    begin
      nx := x + DXS[d];
      ny := y + DYS[d];
      if InGrid(nx, ny) and (EGrid[nx, ny].Kind <> ekNone) then
        EGrid[nx, ny].Conn := EGrid[nx, ny].Conn or (1 shl Opp(d));
    end;
end;

procedure EConnect(x1, y1, x2, y2: Integer);
var
  d: Integer;
begin
  if not (InGrid(x1, y1) and InGrid(x2, y2)) then Exit;
  for d := 0 to 3 do
    if (x1 + DXS[d] = x2) and (y1 + DYS[d] = y2) then
    begin
      EGrid[x1, y1].Conn := EGrid[x1, y1].Conn or (1 shl d);
      EGrid[x2, y2].Conn := EGrid[x2, y2].Conn or (1 shl Opp(d));
    end;
end;

procedure WireAt(x, y: Integer);
begin
  if InGrid(x, y) and (EGrid[x, y].Kind = ekNone) then
  begin
    EReset(x, y);
    EGrid[x, y].Kind := ekWire;
    EGrid[x, y].Layer := CurLayer;
  end;
end;

procedure EWireLine(x1, y1, x2, y2: Integer);
var
  x, y, s: Integer;
begin
  WireAt(x1, y1);
  x := x1;
  y := y1;
  if x2 > x1 then s := 1 else s := -1;
  while x <> x2 do
  begin
    WireAt(x + s, y);
    EConnect(x, y, x + s, y);
    x := x + s;
  end;
  if y2 > y1 then s := 1 else s := -1;
  while y <> y2 do
  begin
    WireAt(x, y + s);
    EConnect(x, y, x, y + s);
    y := y + s;
  end;
end;

procedure EErase(x, y: Integer);
var
  d, nx, ny: Integer;
begin
  if not InGrid(x, y) then Exit;
  for d := 0 to 3 do
  begin
    nx := x + DXS[d];
    ny := y + DYS[d];
    if InGrid(nx, ny) then
      EGrid[nx, ny].Conn := EGrid[nx, ny].Conn and not (1 shl Opp(d));
  end;
  EReset(x, y);
end;

procedure ERotate(x, y: Integer);
var
  c: PECell;
  a, b: Integer;
begin
  if not InGrid(x, y) then Exit;
  c := @EGrid[x, y];
  case c^.Kind of
    ekNone, ekWire, ekCross, ekTerminal: Exit;
    ekSw2, ekSw3:
      begin
        c^.Dir := (c^.Dir + 1) and 3;
        c^.Conn := ((c^.Conn shl 1) or (c^.Conn shr 3)) and 15;
      end;
  else
    begin
      TermSides(c^, a, b);
      c^.Conn := c^.Conn and not ((1 shl a) or (1 shl b));
      c^.Dir := 1 - c^.Dir;
      TermSides(c^, a, b);
      c^.Conn := c^.Conn or (1 shl a) or (1 shl b);
    end;
  end;
end;

{ every selector with this tag goes to position p }
procedure SetSelector(const Tag: string; p: Integer);
var
  x, y: Integer;
begin
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (EGrid[x, y].Kind = ekSelector) and SameText(EGrid[x, y].Tag, Tag) then
        EGrid[x, y].Sel := p;
end;

function EOperate(x, y: Integer): string;
var
  c: PECell;
begin
  Result := '';
  if not InGrid(x, y) then Exit;
  c := @EGrid[x, y];
  case c^.Kind of
    ekAC, ekDC, ekBreaker:
      if c^.Tripped then
      begin
        c^.Tripped := False;
        c^.On := True;
        Result := 'reset';
      end
      else
      begin
        c^.On := not c^.On;
        if c^.On then Result := 'ON' else Result := 'OFF';
      end;
    ekFuse:
      if c^.Tripped then
      begin
        c^.Tripped := False;
        Result := 'replaced';
      end
      else
        Result := 'intact';
    ekOL:
      if c^.Tripped then
      begin
        c^.Tripped := False;
        Result := 'reset';
      end
      else
        Result := 'not tripped';
    ekCounter:
      begin
        c^.Acc := 0;
        Result := 'reset to 0';
      end;
    ekSwitch, ekPBLatch:
      begin
        c^.On := not c^.On;
        if c^.On then Result := 'ON' else Result := 'OFF';
      end;
    ekSw2, ekSw3:
      begin
        c^.Sel := 1 - c^.Sel;
        Result := Format('position %d', [c^.Sel + 1]);
      end;
    ekSelector:
      begin
        SetSelector(c^.Tag, (c^.Sel + 1) mod Max2(c^.NPos));
        Result := Format('position %d', [c^.Sel + 1]);
      end;
    ekEStop:
      begin
        c^.On := not c^.On;
        if c^.On then Result := 'PRESSED - everything stops' else Result := 'released';
      end;
  end;
end;

procedure ESetSelectorPos(x, y, p: Integer);
begin
  if InGrid(x, y) then SetSelector(EGrid[x, y].Tag, p);
end;

procedure EPress(x, y: Integer; Down: Boolean);
begin
  if InGrid(x, y) and EIsMomentary(EGrid[x, y].Kind) then EGrid[x, y].Held := Down;
end;

{ this page has a coil, timer, counter, controller, overload or fluid switch with this tag }
function LocalTagDefined(const Tag: string): Boolean;
var
  x, y: Integer;
begin
  Result := False;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (EGrid[x, y].Kind in [ekRelay, ekContactor, ekTimer, ekOL, ekSolenoid, ekCounter, ekController, ekPhoto]) and
        SameText(EGrid[x, y].Tag, Tag) then Exit(True);
  if Assigned(ExtTagDefined) then Result := ExtTagDefined(Tag);
  if (not Result) and Assigned(ExtFlowTagDefined) then Result := ExtFlowTagDefined(Tag);
end;

function ETagKnown(const Tag: string): Boolean;
var
  x, y: Integer;
begin
  Result := False;
  if Tag = '' then Exit;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (EGrid[x, y].Kind <> ekNone) and SameText(EGrid[x, y].Tag, Tag) then Exit(True);
  Result := LocalTagDefined(Tag) or BusTagActive(Tag);
end;

function TagActive(const Tag: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if Tag = '' then Exit;
  for i := 0 to NActiveTags - 1 do
    if SameText(ActiveTags[i], Tag) then Exit(True);
  if Assigned(ExtTagActive) then Result := ExtTagActive(Tag);
  if (not Result) and Assigned(ExtFlowTag) then Result := ExtFlowTag(Tag);
  { a coil on another page, when this page has no part with that tag }
  if (not Result) and BusTagActive(Tag) and not LocalTagDefined(Tag) then Result := True;
end;

function EConducts(x, y: Integer): Boolean;
var
  c: PECell;
begin
  c := @EGrid[x, y];
  case c^.Kind of
    ekNO: Result := TagActive(c^.Tag);
    ekNC: Result := not TagActive(c^.Tag);
    ekFuse: Result := not c^.Tripped;
    ekBreaker: Result := c^.On and not c^.Tripped;
    ekSwitch, ekPBLatch: Result := c^.On;
    ekPBNO: Result := c^.Held;
    ekPBNC: Result := not c^.Held;
    ekSelector: Result := c^.Sel + 1 = c^.Pos;
    ekEStop: Result := not c^.On;
    ekOL: Result := not c^.Tripped;
    ekFloat, ekPhoto: Result := c^.Latch;
    ekCT: Result := True;
  else
    Result := False;
  end;
end;

function ECount: Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if EGrid[x, y].Kind <> ekNone then Inc(Result);
end;

function EquipByName(const Name: string): Integer;
var
  i: Integer;
begin
  if Name <> '' then
    for i := 0 to MAX_EQUIP - 1 do
      if Equips[i].Active and SameText(Equips[i].Name, Name) then Exit(i);
  Result := -1;
end;

function EquipLevelByName(const Name: string): Single;
var
  i: Integer;
  c: PCell;
  be: TBusEq;
begin
  Result := -1;
  i := EquipByName(Name);
  if i < 0 then
  begin
    { on another page }
    if BusEquip(Name, be) then Result := be.Level;
    Exit;
  end;
  if EquipIsWater(Equips[i].Kind) then Exit(Equips[i].Level);
  if Equips[i].Kind = EQ_SILO then
  begin
    c := EquipLinkCell(i);
    if (c <> nil) and IsStore(c^.Kind) then Result := StoreTotal(c^) / StoreCap(c^.Kind) * 100
    else Result := Equips[i].Level;
  end;
end;

function EStateText(x, y: Integer): string;
var
  c: PECell;
  lv: Single;
begin
  c := @EGrid[x, y];
  case c^.Kind of
    ekWire, ekCross, ekTerminal:
      case c^.Live of
        1: Result := 'live (L / +)';
        2: Result := 'neutral (N / -)';
      else
        Result := 'dead';
      end;
    ekAC, ekDC:
      if c^.Tripped then Result := 'SHORT CIRCUIT - shut down (reset it)'
      else if c^.On then Result := 'ON' else Result := 'OFF';
    ekFuse: if c^.Tripped then Result := 'BLOWN (replace it)' else Result := 'intact';
    ekBreaker:
      if c^.Tripped then Result := 'TRIPPED (reset it)'
      else if c^.On then Result := 'ON' else Result := 'OFF';
    ekOL:
      if c^.Tripped then Result := 'TRIPPED (reset it)'
      else Result := Format('ok, %.2f A', [c^.Amps]);
    ekCT: Result := Format('%.2f A', [c^.Amps]);
    ekPot: Result := Format('set to %.0f%%', [c^.P1]);
    ekTimer:
      if ETimerActive(c^) then Result := Format('%s: ON (%.1f s)', [TimerModeNames[c^.Pos and 3], c^.Acc])
      else if c^.Energized then Result := Format('%s: running %.1f s', [TimerModeNames[c^.Pos and 3], c^.Acc])
      else Result := Format('%s: off', [TimerModeNames[c^.Pos and 3]]);
    ekCounter: Result := Format('count %.0f of %.0f', [c^.Acc, c^.P1]);
    ekLevelTx, ekPressTx, ekFlowTx, ekTempTx, ekSpeedTx, ekWeightTx, ekHumidTx, ekPHTx:
      Result := Format('reads %.2f %s', [c^.Val, SensorUnit(c^)]);
    ekPhoto: if c^.Latch then Result := 'material: CLOSED' else Result := 'clear: open';
    ekController:
      if not c^.Energized then Result := 'no power'
      else Result := Format('PV %.1f  SP %.1f  OUT %.0f%%', [c^.Val, c^.P1, c^.Out]);
    ekFloat:
      begin
        lv := EquipLevelByName(c^.Ref);
        if lv < 0 then Result := 'no level: pick the equipment'
        else if c^.Latch then Result := Format('CLOSED - level %.0f%%', [lv])
        else Result := Format('open - level %.0f%%', [lv]);
      end;
  else
    if EIsLoad(c^.Kind) then
    begin
      if c^.Energized then Result := 'ENERGIZED' else Result := 'off';
    end
    else if c^.Energized then Result := 'closed'
    else Result := 'open';
  end;
end;

{ a drive's speed: its potentiometer or controller (Src) when it has one, else its own setting }
function DriveSpeedOf(const c: TECell): Single;
var
  x, y: Integer;
begin
  Result := c.P1;
  if c.Src = '' then Exit;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if SameText(EGrid[x, y].Tag, c.Src) then
        case EGrid[x, y].Kind of
          ekPot: Exit(EGrid[x, y].P1);
          ekController: Exit(EGrid[x, y].Out);
        end;
end;

function ECellByTag(const Tag: string; K: TEKind; out x, y: Integer): Boolean;
var
  i, j: Integer;
begin
  Result := False;
  x := -1;
  y := -1;
  if Tag <> '' then
    for j := 0 to GH - 1 do
      for i := 0 to GW - 1 do
        if (EGrid[i, j].Kind = K) and SameText(EGrid[i, j].Tag, Tag) then
        begin
          x := i;
          y := j;
          Exit(True);
        end;
end;

function SensorUnit(const c: TECell): string;
begin
  case c.Kind of
    ekLevelTx: Result := '%';
    ekPressTx: if c.Ref <> '' then Result := 'bar' else Result := 'kPa';
    ekFlowTx: Result := 'm/s';
    ekTempTx: Result := 'C';
    ekSpeedTx: Result := 'rpm';
    ekWeightTx: Result := 'kg';
    ekHumidTx: if c.Pos = 0 then Result := '%RH' else Result := '%';
    ekPHTx: Result := 'pH';
    ekCounter: Result := 'pcs';
  else
    Result := '';
  end;
end;

{ a timer's output now, from what it did up to the last frame (Acc, Latch) and its coil (Energized) }
function ETimerActive(const c: TECell): Boolean;
begin
  if c.Kind <> ekTimer then Exit(False);
  case c.Pos and 3 of
    1: Result := c.Energized or c.Latch;
    2: Result := c.Latch or (c.Energized and not c.Held);
    3: Result := c.Energized and (c.Acc - Floor(c.Acc / fmax(0.1, c.P1 + c.P2)) * fmax(0.1, c.P1 + c.P2) < c.P1);
  else
    Result := c.Energized and (c.Acc >= c.P1);
  end;
end;
{ the current a load draws now (A) }
function LoadAmps(const c: TECell): Single;
begin
  Result := 0;
  if not c.Energized then Exit;
  case c.Kind of
    ekLamp: Result := 0.1;
    ekBuzzer: Result := 0.05;
    ekRelay: Result := 0.03;
    ekContactor: Result := 0.15;
    ekTimer: Result := 0.02;
    ekSolenoid: Result := 0.1;
    ekMotor:
      begin
        { inrush: about 6x at start, settling in a second or so; star: a third }
        Result := c.P1 * (1 + 5 * Exp(-3 * c.Acc));
        if c.Pos = 1 then Result := Result / 3;
      end;
    ekDrive: Result := 5 * (0.05 + 0.95 * DriveSpeedOf(c) / 100);
  end;
end;

function DriveSpeed(x, y: Integer): Single;
begin
  Result := DriveSpeedOf(EGrid[x, y]);
end;

{ the unit of what a controller controls: its input's unit }
function CtrlUnit(const c: TECell): string;
var
  v: Single;
begin
  Result := '';
  if (c.Src <> '') and not SameText(c.Src, c.Tag) then AnalogValue(c.Src, v, Result);
end;

function AnalogValue(const Src: string; out Value: Single; out UnitS: string): Boolean;
var
  x, y, i, k: Integer;
  c: PECell;
  lv: Single;
begin
  Value := 0;
  UnitS := '';
  Result := False;
  if Src = '' then Exit;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @EGrid[x, y];
      if (c^.Kind = ekNone) or not SameText(c^.Tag, Src) then Continue;
      Result := True;
      case c^.Kind of
        ekCT, ekOL: begin Value := c^.Amps; UnitS := 'A'; end;
        ekMotor: begin Value := LoadAmps(c^); UnitS := 'A'; end;
        ekPot: begin Value := c^.P1; UnitS := '%'; end;
        ekDrive: begin if c^.Energized then Value := DriveSpeedOf(c^); UnitS := '%'; end;
        ekAC: begin if c^.On and not c^.Tripped then Value := 230; UnitS := 'V'; end;
        ekDC: begin if c^.On and not c^.Tripped then Value := 24; UnitS := 'V'; end;
        ekTimer: begin Value := c^.Acc; UnitS := 's'; end;
        ekCounter: begin Value := c^.Acc; UnitS := 'pcs'; end;
        ekLevelTx, ekPressTx, ekFlowTx, ekTempTx, ekSpeedTx, ekWeightTx, ekHumidTx, ekPHTx: begin Value := c^.Val; UnitS := SensorUnit(c^); end;
        ekController: begin Value := c^.Out; UnitS := '%'; end;
      else
        Result := False;
      end;
      if Result then Exit;
    end;
  { a controller's actual value and set point: TAG.PV, TAG.SP }
  k := Pos('.', Src);
  if k > 1 then
    for y := 0 to GH - 1 do
      for x := 0 to GW - 1 do
      begin
        c := @EGrid[x, y];
        if (c^.Kind = ekController) and SameText(c^.Tag, Copy(Src, 1, k - 1)) then
        begin
          UnitS := CtrlUnit(c^);
          if SameText(Copy(Src, k + 1, 9), 'PV') then Value := c^.Val
          else if SameText(Copy(Src, k + 1, 9), 'SP') then Value := c^.P1
          else Exit;
          Exit(True);
        end;
      end;
  if Assigned(ExtAnalog) and ExtAnalog(Src, Value, UnitS) then Exit(True);
  if Assigned(ExtFlowValue) and ExtFlowValue(Src, Value) then
  begin
    UnitS := '';
    Exit(True);
  end;
  if k > 1 then
  begin
    i := EquipByName(Copy(Src, 1, k - 1));
    if (i >= 0) and (Equips[i].Kind in ThermalKinds) then
    begin
      UnitS := 'C';
      if SameText(Copy(Src, k + 1, 9), 'HOT') then Value := Equips[i].HotOut
      else if SameText(Copy(Src, k + 1, 9), 'IN') then Value := Equips[i].HotIn
      else if SameText(Copy(Src, k + 1, 9), 'KW') then begin Value := Equips[i].Duty; UnitS := 'kW'; end
      else Exit;
      Exit(True);
    end;
  end;
  i := EquipByName(Src);
  if i < 0 then
  begin
    { a value another page has }
    Result := BusSignal(Src, Value, UnitS);
    Exit;
  end;
  Result := True;
  UnitS := '%';
  lv := EquipLevelByName(Src);
  if Equips[i].Kind in ThermalKinds then
  begin
    Value := Equips[i].Temp;
    UnitS := 'C';
  end
  else if lv >= 0 then Value := lv
  else if Equips[i].Kind = EQ_FIRE then Value := Equips[i].Heat
  else if EquipRunning(i) then
  begin
    if Equips[i].Kind in [EQ_PUMP, EQ_CONVEYOR, EQ_BELT, EQ_RAIN] then Value := Equips[i].Level else Value := 100;
  end;
end;

function NextAnalogSource(const Cur: string; Dir: Integer): string;
var
  names: array of string;
  n, x, y, i, k: Integer;
  dup: Boolean;
begin
  n := 0;
  SetLength(names, 0);
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (EGrid[x, y].Kind in [ekCT, ekOL, ekMotor, ekPot, ekDrive, ekAC, ekDC, ekTimer, ekCounter, ekController] + SensorKinds) and
        (EGrid[x, y].Tag <> '') then
      begin
        SetLength(names, n + 1);
        names[n] := EGrid[x, y].Tag;
        Inc(n);
        if EGrid[x, y].Kind = ekController then
        begin
          SetLength(names, n + 2);
          names[n] := EGrid[x, y].Tag + '.PV';
          names[n + 1] := EGrid[x, y].Tag + '.SP';
          Inc(n, 2);
        end;
      end;
  if Assigned(ExtSourceName) then
  begin
    i := 0;
    while ExtSourceName(i) <> '' do
    begin
      SetLength(names, n + 1);
      names[n] := ExtSourceName(i);
      Inc(n);
      Inc(i);
    end;
  end;
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and not (Equips[i].Kind in [EQ_LEGEND, EQ_SEQUENCE, EQ_STAND, EQ_CYCLONE, EQ_PANEL, EQ_LAMP,
      EQ_GAUGE, EQ_DIGITAL, EQ_CONTROLLER, EQ_TREND]) then
    begin
      SetLength(names, n + 1);
      names[n] := Equips[i].Name;
      Inc(n);
      if Equips[i].Kind in ThermalKinds then
      begin
        SetLength(names, n + 3);
        names[n] := Equips[i].Name + '.IN';
        names[n + 1] := Equips[i].Name + '.HOT';
        names[n + 2] := Equips[i].Name + '.KW';
        Inc(n, 3);
      end;
    end;
  { a flow chart's random values }
  if Assigned(ExtFlowSigName) then
  begin
    i := 0;
    while ExtFlowSigName(i) <> '' do
    begin
      SetLength(names, n + 1);
      names[n] := ExtFlowSigName(i);
      Inc(n);
      Inc(i);
    end;
  end;
  { and what the other pages have }
  i := 0;
  while BusSigName(i) <> '' do
  begin
    dup := False;
    for k := 0 to n - 1 do
      if SameText(names[k], BusSigName(i)) then dup := True;
    if not dup then
    begin
      SetLength(names, n + 1);
      names[n] := BusSigName(i);
      Inc(n);
    end;
    Inc(i);
  end;
  Result := Cur;
  if n = 0 then Exit;
  k := -1;
  for i := 0 to n - 1 do
    if SameText(names[i], Cur) then k := i;
  if k < 0 then
  begin
    if Dir > 0 then k := 0 else k := n - 1;
  end
  else
    k := (k + Dir + n) mod n;
  Result := names[k];
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

{ the nets, with device Skip (a fuse / breaker) taken as open }
procedure BuildNets(SkipX, SkipY: Integer);
var
  x, y, d, first, a, b, cs, o1, o2, i1, i2: Integer;
  c: PECell;
begin
  for d := 0 to High(Par) do Par[d] := d;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @EGrid[x, y];
      case c^.Kind of
        ekNone: Continue;
        ekWire, ekTerminal:
          begin
            first := -1;
            for d := 0 to 3 do
              if (c^.Conn and (1 shl d)) <> 0 then
              begin
                if first < 0 then first := d else Union(Node(x, y, d), Node(x, y, first));
              end;
          end;
        ekCross:
          begin
            Union(Node(x, y, 0), Node(x, y, 2));
            Union(Node(x, y, 1), Node(x, y, 3));
          end;
        ekSw2:
          begin
            cs := (2 + c^.Dir) and 3;
            o1 := c^.Dir and 3;
            o2 := (1 + c^.Dir) and 3;
            if c^.Sel = 0 then Union(Node(x, y, cs), Node(x, y, o1)) else Union(Node(x, y, cs), Node(x, y, o2));
          end;
        ekSw3:
          begin
            i1 := (2 + c^.Dir) and 3;
            i2 := (3 + c^.Dir) and 3;
            o1 := c^.Dir and 3;
            o2 := (1 + c^.Dir) and 3;
            if c^.Sel = 0 then
            begin
              Union(Node(x, y, i1), Node(x, y, o1));
              Union(Node(x, y, i2), Node(x, y, o2));
            end
            else
            begin
              Union(Node(x, y, i1), Node(x, y, o2));
              Union(Node(x, y, i2), Node(x, y, o1));
            end;
          end;
      else
        if not ((x = SkipX) and (y = SkipY)) and EConducts(x, y) then
        begin
          TermSides(c^, a, b);
          Union(Node(x, y, a), Node(x, y, b));
        end;
      end;
    end;
  { cells wired to each other }
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @EGrid[x, y];
      if c^.Kind = ekNone then Continue;
      if ((c^.Conn and 1) <> 0) and (x + 1 < GW) and (EGrid[x + 1, y].Kind <> ekNone) and
        ((EGrid[x + 1, y].Conn and 4) <> 0) then Union(Node(x, y, 0), Node(x + 1, y, 2));
      if ((c^.Conn and 2) <> 0) and (y + 1 < GH) and (EGrid[x, y + 1].Kind <> ekNone) and
        ((EGrid[x, y + 1].Conn and 8) <> 0) then Union(Node(x, y, 1), Node(x, y + 1, 3));
    end;
end;

type
  TSupply = record
    X, Y: Integer;
    A, B: Integer;    { nodes: L / + and N / - }
  end;

var
  Sup: array[0..31] of TSupply;
  NSup: Integer;

procedure FindSupplies;
var
  x, y, a, b: Integer;
begin
  NSup := 0;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (EGrid[x, y].Kind in [ekAC, ekDC]) and EGrid[x, y].On and not EGrid[x, y].Tripped and (NSup <= High(Sup)) then
      begin
        TermSides(EGrid[x, y], a, b);
        Sup[NSup].X := x;
        Sup[NSup].Y := y;
        Sup[NSup].A := Node(x, y, a);
        Sup[NSup].B := Node(x, y, b);
        Inc(NSup);
      end;
end;

{ L and N of a supply joined: blow the fuse / trip the breaker that breaks the short, or shut the supply down }
function ClearShorts: Boolean;
var
  s, x, y: Integer;
begin
  Result := False;
  for s := 0 to NSup - 1 do
    if Find(Sup[s].A) = Find(Sup[s].B) then
    begin
      Result := True;
      for y := 0 to GH - 1 do
        for x := 0 to GW - 1 do
          if (EGrid[x, y].Kind in [ekFuse, ekBreaker]) and EConducts(x, y) then
          begin
            BuildNets(x, y);
            if Find(Sup[s].A) <> Find(Sup[s].B) then
            begin
              EGrid[x, y].Tripped := True;
              Exit;
            end;
          end;
      EGrid[Sup[s].X, Sup[s].Y].Tripped := True;
      Exit;
    end;
end;

{ ---------------------------------------------------------------- sensors, timers, counters, controllers }

function ESignal(const Tag: string): Boolean;
var
  x, y: Integer;
begin
  Result := TagActive(Tag);
  if Result or (Tag = '') then Exit;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (EGrid[x, y].Kind in [ekPBNO, ekPBNC, ekPBLatch, ekSwitch, ekSelector, ekPhoto, ekFloat]) and
        SameText(EGrid[x, y].Tag, Tag) and EConducts(x, y) then Exit(True);
end;

{ the temperature of the equipment called Name (C): heaters warm up and cool down, a fire is hot }
function EquipTempByName(const Name: string): Single;
var
  i: Integer;
  be: TBusEq;
begin
  Result := 20;
  i := EquipByName(Name);
  if i < 0 then
  begin
    if BusEquip(Name, be) and (be.Temp > 0) then Result := be.Temp;
    Exit;
  end;
  if Equips[i].Temp > 0 then Result := Equips[i].Temp;
end;

{ the bucket whose column holds cx, the nearest one up or down; -1 if none }
function NearBucket(cx, cy: Single): Integer;
var
  i: Integer;
  best: Single;
begin
  Result := -1;
  best := 1e9;
  for i := 0 to MAX_BUCKETS - 1 do
    if Buckets[i].Active and (cx >= Buckets[i].X - HALF) and (cx <= Buckets[i].X + Buckets[i].W + HALF) and
      (Abs(Buckets[i].Y + Buckets[i].H / 2 - cy) < best) then
    begin
      best := Abs(Buckets[i].Y + Buckets[i].H / 2 - cy);
      Result := i;
    end;
end;

{ the mass of each material in the store or pipe at x,y, else in the bucket above or below it }
procedure SampleMaterial(x, y: Integer; out mm: array of Single);
var
  k, b: Integer;
  m: TMat;
  p: PParticle;
begin
  for k := 0 to High(mm) do mm[k] := 0;
  if IsStore(Grid[x, y].Kind) then
  begin
    for m := mWater to mSand do mm[Ord(m)] := Grid[x, y].Stock[m] * MatP[m].Mass;
    Exit;
  end;
  b := -1;
  if Grid[x, y].Kind = ckEmpty then b := NearBucket(x * CELL + HALF, y * CELL + HALF);
  for k := 0 to NPart - 1 do
  begin
    p := @Parts[k];
    if (p^.Life <= 0) or (p^.Mat = mAir) then Continue;
    if b >= 0 then
    begin
      if p^.Bucket <> b then Continue;
    end
    else if not (p^.InPipe and (p^.CX = x) and (p^.CY = y)) then Continue;
    mm[Ord(p^.Mat)] := mm[Ord(p^.Mat)] + MatP[p^.Mat].Mass;
  end;
end;

{ what a sensor at x,y reads now }
procedure ReadSensor(x, y: Integer; dt: Single; Running: Boolean);
var
  be: TBusEq;
  c: PECell;
  i, k, b, n, m: Integer;
  v, best, cx, cy, wat, tot, d2, pm: Single;
  mm: array[TMat] of Single;
  mt: TMat;
  u: string;
  p: PParticle;
begin
  c := @EGrid[x, y];
  cx := x * CELL + HALF;
  cy := y * CELL + HALF;
  case c^.Kind of
    ekLevelTx:
      c^.Val := fmax(0, EquipLevelByName(c^.Ref));
    ekPressTx:
      { a pneumatic / hydraulic gauge or line by its tag, else the air pressure in the pipe under it }
      if (c^.Ref <> '') and Assigned(ExtAnalog) and ExtAnalog(c^.Ref, v, u) then c^.Val := v
      else if Grid[x, y].Kind <> ckEmpty then c^.Val := Grid[x, y].P
      else c^.Val := 0;
    ekFlowTx:
      if Grid[x, y].Kind <> ckEmpty then c^.Val := CellSpeed(x, y) / CELL else c^.Val := 0;
    ekTempTx:
      c^.Val := EquipTempByName(c^.Ref);
    ekSpeedTx:
      begin
        c^.Val := 0;
        i := EquipByName(c^.Ref);
        if (i < 0) and BusEquip(c^.Ref, be) then c^.Val := 14.5 * be.Speed;
        if (i >= 0) and EquipRunning(i) then
        begin
          if Equips[i].Kind in [EQ_PUMP, EQ_CONVEYOR, EQ_BELT, EQ_RAIN] then c^.Val := 14.5 * Equips[i].Level
          else c^.Val := 1450;
        end;
      end;
    ekWeightTx:
      begin
        { the bucket above or below it: what lies in it }
        b := NearBucket(cx, cy);
        v := 0;
        if b >= 0 then
          for k := 0 to NPart - 1 do
          begin
            p := @Parts[k];
            if (p^.Life > 0) and (p^.Bucket = b) and (p^.Mat <> mAir) then v := v + MatP[p^.Mat].Mass * 0.05;
          end;
        { and the pieces in it }
        if b >= 0 then
        begin
          PiecesInBucket(b, pm);
          v := v + pm;
        end;
        c^.Val := v;
      end;
    ekHumidTx:
      if c^.Pos = 0 then
      begin
        { the air around it (2.5 cells): 45 % RH, wetter with water and steam near it and with
          ponds, pools and rain, drier near hot equipment; it follows in about 2 s }
        n := 0;
        m := 0;
        for k := 0 to NPart - 1 do
        begin
          p := @Parts[k];
          if p^.Life <= 0 then Continue;
          d2 := Sqr(p^.X - cx) + Sqr(p^.Y - cy);
          if d2 > Sqr(2.5 * CELL) then Continue;
          if p^.Mat = mWater then Inc(n)
          else if (p^.Mat = mAir) and not p^.InPipe and (p^.ExitDir = STEAM_MARK) then Inc(m);
        end;
        v := 45 + 1.5 * n + 4 * m;
        for i := 0 to MAX_EQUIP - 1 do
        begin
          if not Equips[i].Active then Continue;
          d2 := Sqr(fmax(0, fmax(Equips[i].X - cx, cx - Equips[i].X - Equips[i].W))) +
            Sqr(fmax(0, fmax(Equips[i].Y - cy, cy - Equips[i].Y - Equips[i].H)));
          if d2 > Sqr(4 * CELL) then Continue;
          if Equips[i].Kind in [EQ_POND, EQ_POOL, EQ_WELL] then v := v + 15 * Equips[i].Level / 100
          else if (Equips[i].Kind = EQ_RAIN) and EquipRunning(i) then v := v + 25
          else if Equips[i].Temp > 25 then v := v - (Equips[i].Temp - 20) * 0.12;
        end;
        v := fclamp(v, 5, 100);
        if c^.Val <= 0 then c^.Val := 45;
        c^.Val := c^.Val + (v - c^.Val) * fmin(1, dt / 2);
      end
      else
      begin
        { the moisture of material: the water share (by mass) of what is in the store or
          pipe under it, else in the bucket above or below it }
        SampleMaterial(x, y, mm);
        tot := mm[mWater] + mm[mOil] + mm[mFluff] + mm[mSand];
        if tot > 0 then c^.Val := 100 * mm[mWater] / tot else c^.Val := 0;
      end;
    ekPHTx:
      begin
        { the pH of the sample: each material's own pH, mixed by mass (as hydrogen ions); 7 when empty }
        SampleMaterial(x, y, mm);
        tot := 0;
        wat := 0;
        for mt := mWater to mSand do
        begin
          tot := tot + mm[mt];
          wat := wat + mm[mt] * Power(10, -MatP[mt].PH);
        end;
        if (tot > 0) and (wat > 0) then c^.Val := -Log10(wat / tot) else c^.Val := 7;
      end;
    ekPhoto:
      begin
        { material in its cell: in the pipe there or falling past }
        n := 0;
        for k := 0 to NPart - 1 do
        begin
          p := @Parts[k];
          if (p^.Life > 0) and (p^.Mat <> mAir) and (p^.X >= x * CELL) and (p^.X < x * CELL + CELL) and
            (p^.Y >= y * CELL) and (p^.Y < y * CELL + CELL) then Inc(n);
        end;
        { it opens again 1 s after the last material, so one batch closes it once; a piece (bottle,
          box ...) in its beam closes it while it is there (Out: how long it stays closed after) }
        if n > 0 then c^.Out := 1.0;
        if PieceIn(x * CELL, y * CELL, x * CELL + CELL, y * CELL + CELL) then
        begin
          Inc(n);
          if c^.Out < 0.15 then c^.Out := 0.15;
        end;
        c^.Val := n;
        if n > 0 then
        begin
          c^.Latch := True;
          c^.Acc := 0;
        end
        else if c^.Latch then
        begin
          if Running then c^.Acc := c^.Acc + dt;
          if c^.Acc >= fmax(0.15, c^.Out) then
          begin
            c^.Latch := False;
            c^.Out := 0;
          end;
        end;
      end;
  end;
end;

{ a timer after this frame: on-delay, off-delay, pulse or flasher }
procedure TimerStep(var c: TECell; dt: Single; Running: Boolean);
begin
  if not Running then dt := 0;
  case c.Pos and 3 of
    1:
      if c.Energized then
      begin
        c.Acc := 0;
        c.Latch := True;
      end
      else if c.Latch then
      begin
        c.Acc := c.Acc + dt;
        if c.Acc >= c.P1 then
        begin
          c.Latch := False;
          c.Acc := 0;
        end;
      end;
    2:
      begin
        if c.Latch then
        begin
          c.Acc := c.Acc + dt;
          if c.Acc >= c.P1 then c.Latch := False;
        end
        else if c.Energized and not c.Held then
        begin
          c.Latch := True;
          c.Acc := 0;
        end;
        c.Held := c.Energized;
      end;
  else
    if c.Energized then c.Acc := c.Acc + dt else c.Acc := 0;
  end;
end;

{ a controller's output is on: on / off, or a PID output of 50 % and more }
function CtrlOn(const c: TECell): Boolean;
begin
  Result := c.Out >= 50;
end;

{ a controller after this frame: reads its input (PV), compares it with its set point (P1) }
procedure ControllerStep(var c: TECell; dt: Single; Running: Boolean);
var
  v, e, kp, o: Single;
  u: string;
begin
  if (c.Src <> '') and not SameText(c.Src, c.Tag) and AnalogValue(c.Src, v, u) then c.Val := v;
  if not c.Energized then
  begin
    c.Out := 0;
    c.Integ := 0;
    Exit;
  end;
  case c.Pos and 3 of
    0:
      { on / off with a hysteresis band of P2 around the set point: on below it }
      if c.Val < c.P1 - c.P2 / 2 then c.Out := 100
      else if c.Val > c.P1 + c.P2 / 2 then c.Out := 0;
    1:
      if c.Val > c.P1 + c.P2 / 2 then c.Out := 100
      else if c.Val < c.P1 - c.P2 / 2 then c.Out := 0;
  else
    begin
      { PID (PI): proportional band P2 (in the input's units), integral time P3 s }
      e := c.P1 - c.Val;
      if (c.Pos and 3) = 3 then e := -e;
      kp := 100 / fmax(0.01, c.P2);
      if Running and (c.P3 > 0) then c.Integ := c.Integ + e * dt / c.P3;
      c.Integ := fclamp(c.Integ, -c.P2, c.P2);
      o := kp * (e + c.Integ);
      c.Out := fclamp(o, 0, 100);
    end;
  end;
end;

{ ---------------------------------------------------------------- the plant bus }

{ equipment that no motor or drive here runs follows the commands from the other pages }
procedure ApplyBusCommands(const driven: array of Boolean);
var
  i: Integer;
  cmd: TBusCmd;
begin
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and not driven[i] and (Equips[i].State in [EQS_STOP, EQS_RUN]) and
      BusCommand(Equips[i].Name, cmd) then
    begin
      if cmd.IsOn then
      begin
        if Equips[i].State <> EQS_RUN then Equips[i].RunTime := 0;
        Equips[i].State := EQS_RUN;
        if (cmd.Speed >= 0) and (Equips[i].Kind in [EQ_PUMP, EQ_CONVEYOR, EQ_BELT] + ThermalKinds) then Equips[i].Level := cmd.Speed;
      end
      else
        Equips[i].State := EQS_STOP;
    end;
end;

procedure ElecPublish(Page: Integer);
var
  x, y, i: Integer;
  v: Single;
  u, s: string;
  c: PECell;
  e: TBusEq;
begin
  BusPage := Page;
  BusBegin(Page);
  { the tags that are on }
  for i := 0 to NActiveTags - 1 do BusAddTag(ActiveTags[i]);
  if Assigned(ExtFlowTagName) then
  begin
    i := 0;
    s := ExtFlowTagName(0);
    while s <> '' do
    begin
      BusAddTag(s);
      Inc(i);
      s := ExtFlowTagName(i);
    end;
  end;
  if Assigned(ExtActiveTag) then
  begin
    i := 0;
    s := ExtActiveTag(0);
    while s <> '' do
    begin
      BusAddTag(s);
      Inc(i);
      s := ExtActiveTag(i);
    end;
  end;
  { the analog values }
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @EGrid[x, y];
      if (c^.Tag = '') or not (c^.Kind in [ekCT, ekOL, ekMotor, ekPot, ekDrive, ekAC, ekDC, ekTimer, ekCounter,
        ekController] + SensorKinds) then Continue;
      if AnalogValue(c^.Tag, v, u) then BusAddSig(c^.Tag, v, u);
      if c^.Kind = ekController then
      begin
        BusAddSig(c^.Tag + '.PV', c^.Val, CtrlUnit(c^));
        BusAddSig(c^.Tag + '.SP', c^.P1, CtrlUnit(c^));
      end;
    end;
  if Assigned(ExtFlowSigName) and Assigned(ExtFlowValue) then
  begin
    i := 0;
    s := ExtFlowSigName(0);
    while s <> '' do
    begin
      if ExtFlowValue(s, v) then BusAddSig(s, v, '');
      Inc(i);
      s := ExtFlowSigName(i);
    end;
  end;
  if Assigned(ExtSourceName) and Assigned(ExtAnalog) then
  begin
    i := 0;
    s := ExtSourceName(0);
    while s <> '' do
    begin
      if ExtAnalog(s, v, u) then BusAddSig(s, v, u);
      Inc(i);
      s := ExtSourceName(i);
    end;
  end;
  { the equipment }
  for i := 0 to MAX_EQUIP - 1 do
  begin
    if not Equips[i].Active or (Equips[i].Name = '') then Continue;
    FillChar(e, SizeOf(e), 0);
    e.Name := Equips[i].Name;
    e.Kind := Equips[i].Kind;
    e.State := Equips[i].State;
    e.Level := EquipLevelByName(Equips[i].Name);
    if EquipRunning(i) then
    begin
      if Equips[i].Kind in [EQ_PUMP, EQ_CONVEYOR, EQ_BELT, EQ_RAIN] then e.Speed := Equips[i].Level else e.Speed := 100;
    end;
    e.Temp := Equips[i].Temp;
    BusAddEq(e);
    if not (Equips[i].Kind in [EQ_LEGEND, EQ_SEQUENCE, EQ_STAND, EQ_CYCLONE, EQ_PANEL, EQ_LAMP, EQ_GAUGE, EQ_DIGITAL,
      EQ_CONTROLLER, EQ_TREND]) and AnalogValue(Equips[i].Name, v, u) then BusAddSig(Equips[i].Name, v, u);
    if Equips[i].Kind in ThermalKinds then
    begin
      BusAddSig(Equips[i].Name + '.IN', Equips[i].HotIn, 'C');
      BusAddSig(Equips[i].Name + '.HOT', Equips[i].HotOut, 'C');
      BusAddSig(Equips[i].Name + '.KW', Equips[i].Duty, 'kW');
    end;
  end;
end;

{ the tags that are on, from the state of the parts of this page; returns them as one text }
function CollectActiveTags: string;
var
  x, y: Integer;
  c: PECell;
begin
  NActiveTags := 0;
  Result := '';
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @EGrid[x, y];
      if (c^.Tag <> '') and (((c^.Kind in [ekRelay, ekContactor, ekSolenoid]) and c^.Energized) or ETimerActive(c^) or
        ((c^.Kind = ekCounter) and (c^.Acc >= c^.P1) and (c^.P1 > 0)) or ((c^.Kind = ekPhoto) and c^.Latch) or
        ((c^.Kind = ekController) and c^.Energized and CtrlOn(c^)) or ((c^.Kind = ekOL) and c^.Tripped)) then
      begin
        if NActiveTags >= Length(ActiveTags) then SetLength(ActiveTags, NActiveTags + 16);
        ActiveTags[NActiveTags] := c^.Tag;
        Inc(NActiveTags);
        Result := Result + UpperCase(c^.Tag) + '|';
      end;
    end;
end;

procedure SolveElectric(dt: Single; Running: Boolean);
var
  x, y, s, iter, a, b, i, nOn, k, x2, y2: Integer;
  c: PECell;
  lv: Single;
  sig, prev: string;
  powered: Boolean;
  driven, isOn: array[0..MAX_EQUIP - 1] of Boolean;
  speed: array[0..MAX_EQUIP - 1] of Single;
  be: TBusEq;
begin
  BusClearCmds(BusPage);
  if ECount = 0 then
  begin
    NActiveTags := 0;
    { equipment run from another page }
    for i := 0 to MAX_EQUIP - 1 do driven[i] := False;
    ApplyBusCommands(driven);
    Exit;
  end;
  if Length(Par) <> GW * GH * 4 then SetLength(Par, GW * GH * 4);
  { inputs from the process }
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @EGrid[x, y];
      if c^.Kind in SensorKinds + [ekPhoto] then ReadSensor(x, y, dt, Running);
      case c^.Kind of
        ekFloat:
          begin
            lv := EquipLevelByName(c^.Ref);
            if lv < 0 then c^.Latch := False
            else if c^.Pos = 0 then
            begin
              { fill: closes when low, opens when high }
              if lv <= c^.P1 then c^.Latch := True else if lv >= c^.P2 then c^.Latch := False;
            end
            else if lv >= c^.P2 then c^.Latch := True
            else if lv <= c^.P1 then c^.Latch := False;
          end;
        ekOL:
          begin
            i := EquipByName(c^.Ref);
            if (i >= 0) and (Equips[i].State = EQS_FAULT) then c^.Tripped := True;
            if (i < 0) and BusEquip(c^.Ref, be) and (be.State = EQS_FAULT) then c^.Tripped := True;
          end;
      end;
    end;
  { what this page had on at the end of its last frame (the list is shared with the other pages) }
  CollectActiveTags;
  { solve until the coils settle }
  prev := #0;
  for iter := 1 to 12 do
  begin
    FindSupplies;
    BuildNets(-1, -1);
    k := 0;
    while ClearShorts and (k < 8) do
    begin
      FindSupplies;
      BuildNets(-1, -1);
      Inc(k);
    end;
    for y := 0 to GH - 1 do
      for x := 0 to GW - 1 do
      begin
        c := @EGrid[x, y];
        if not EIsLoad(c^.Kind) then Continue;
        TermSides(c^, a, b);
        powered := False;
        for s := 0 to NSup - 1 do
          if ((Find(Node(x, y, a)) = Find(Sup[s].A)) and (Find(Node(x, y, b)) = Find(Sup[s].B))) or
            ((Find(Node(x, y, a)) = Find(Sup[s].B)) and (Find(Node(x, y, b)) = Find(Sup[s].A))) then
            powered := True;
        c^.Energized := powered;
      end;
    { the tags that are active now }
    sig := CollectActiveTags;
    if sig = prev then Break;
    prev := sig;
  end;
  { contacts closed / open, and which nets are live, for the drawing }
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @EGrid[x, y];
      if c^.Kind = ekNone then Continue;
      if not EIsLoad(c^.Kind) and not (c^.Kind in [ekWire, ekCross, ekTerminal, ekAC, ekDC]) then
        c^.Energized := (c^.Kind in [ekSw2, ekSw3]) or EConducts(x, y);
      c^.Live := 0;
      for k := 0 to 3 do
        if (c^.Conn and (1 shl k)) <> 0 then
        begin
          for s := 0 to NSup - 1 do
            if Find(Node(x, y, k)) = Find(Sup[s].A) then c^.Live := 1
            else if (c^.Live = 0) and (Find(Node(x, y, k)) = Find(Sup[s].B)) then c^.Live := 2;
          Break;
        end;
    end;
  { timers and motors count while powered; counters count; controllers work }
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @EGrid[x, y];
      case c^.Kind of
        ekMotor:
          if not c^.Energized then c^.Acc := 0
          else if Running then c^.Acc := c^.Acc + dt;
        ekTimer:
          TimerStep(c^, dt, Running);
        ekCounter:
          begin
            { a rising edge of its coil counts one; its reset tag sets it back to 0 }
            if c^.Energized and not c^.Held then c^.Acc := c^.Acc + 1;
            c^.Held := c^.Energized;
            if (c^.Src <> '') and ESignal(c^.Src) then c^.Acc := 0;
          end;
        ekController:
          ControllerStep(c^, dt, Running);
      end;
    end;
  { the current through each CT and overload: every load that loses its power when it is opened }
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @EGrid[x, y];
      if not (c^.Kind in [ekCT, ekOL]) then Continue;
      c^.Amps := 0;
      if (c^.Kind = ekOL) and c^.Tripped then Continue;
      BuildNets(x, y);
      for y2 := 0 to GH - 1 do
        for x2 := 0 to GW - 1 do
        begin
          if not (EIsLoad(EGrid[x2, y2].Kind) and EGrid[x2, y2].Energized) then Continue;
          TermSides(EGrid[x2, y2], a, b);
          powered := False;
          for s := 0 to NSup - 1 do
            if ((Find(Node(x2, y2, a)) = Find(Sup[s].A)) and (Find(Node(x2, y2, b)) = Find(Sup[s].B))) or
              ((Find(Node(x2, y2, a)) = Find(Sup[s].B)) and (Find(Node(x2, y2, b)) = Find(Sup[s].A))) then
              powered := True;
          if not powered then c^.Amps := c^.Amps + LoadAmps(EGrid[x2, y2]);
        end;
      { a thermal overload trips after 2 s over its trip current (P1, 0 = off) }
      if c^.Kind = ekOL then
      begin
        if (c^.P1 > 0) and (c^.Amps > c^.P1) then
        begin
          if Running then c^.Acc := c^.Acc + dt;
          if c^.Acc >= 2 then c^.Tripped := True;
        end
        else
          c^.Acc := 0;
      end;
    end;
  { motors and drives run their equipment }
  for i := 0 to MAX_EQUIP - 1 do
  begin
    driven[i] := False;
    isOn[i] := False;
    speed[i] := -1;
  end;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @EGrid[x, y];
      if not (c^.Kind in [ekMotor, ekDrive]) then Continue;
      i := EquipByName(c^.Ref);
      if i < 0 then
      begin
        { equipment on another page: a command on the bus }
        if c^.Energized and (c^.Kind = ekDrive) then BusAddCmd(c^.Ref, True, DriveSpeedOf(c^))
        else BusAddCmd(c^.Ref, c^.Energized, -1);
        Continue;
      end;
      driven[i] := True;
      if c^.Energized then
      begin
        isOn[i] := True;
        if c^.Kind = ekDrive then speed[i] := DriveSpeedOf(c^);
      end;
    end;
  nOn := 0;
  for i := 0 to MAX_EQUIP - 1 do
    if driven[i] and Equips[i].Active and (Equips[i].State in [EQS_STOP, EQS_RUN]) then
    begin
      if isOn[i] then
      begin
        if Equips[i].State <> EQS_RUN then Equips[i].RunTime := 0;
        Equips[i].State := EQS_RUN;
        if (speed[i] >= 0) and (Equips[i].Kind in [EQ_PUMP, EQ_CONVEYOR, EQ_BELT] + ThermalKinds) then Equips[i].Level := speed[i];
        Inc(nOn);
      end
      else
        Equips[i].State := EQS_STOP;
    end;
  ApplyBusCommands(driven);
end;

procedure ElecHookProc(dt: Single; Running: Boolean);
begin
  SolveElectric(dt, Running);
end;

initialization
  EClearAll;
  ElecHook := @ElecHookProc;
  ClearHook := @EClearAll;

end.
