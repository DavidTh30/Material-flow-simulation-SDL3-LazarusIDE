unit flowchart;

{ Flow charts on the canvas, worked out live every frame (like a PLC scan).

  A chart is made of nodes joined by arrows:
    Start     where a scan begins (every Start node, every frame)
    Input     reads a value (Src) and shows it, then goes on
    Decision  tests what it reads (Src <op> Value, or ON / OFF): Yes goes to
              Next, No to Next2; it shows green for Yes, red for No
    Action    works a piece: Run / Stop equipment, Set its % (or a pot /
              drive), Set a controller's set point, Tag ON (the tag is on
              while the scan reaches the node - contacts can follow it), or
              Reset a counter / trip / fault
    Display   shows what it reads, green / red by its test, off any path too
    Delay     lets the scan through only after it has been reached for Value s
    End       where a path ends
  What a node reads can be on this page or another one (the plant bus), and
  so can what an action works: equipment on another page runs or stops through
  the bus. A path that comes back to a node it has passed in this scan ends
  there, so a loop cannot hang the program. }

{$mode objfpc}{$H+}

interface

uses
  simcore, plantbus;

const
  MAX_FLOW = 64;
  FN_START = 0;
  FN_INPUT = 1;
  FN_DECISION = 2;
  FN_ACTION = 3;
  FN_DISPLAY = 4;
  FN_DELAY = 5;
  FN_END = 6;
  FN_RANDOM = 7;
  FN_KINDS = 8;
  FlowKindNames: array[0..FN_KINDS - 1] of string = ('Start', 'Input', 'Decision', 'Action', 'Display', 'Delay', 'End',
    'Random');
  FlowKindTags: array[0..FN_KINDS - 1] of string = ('start', 'input', 'decision', 'action', 'display', 'delay', 'end',
    'random');
  FOP_GT = 0;
  FOP_LT = 1;
  FOP_GE = 2;
  FOP_LE = 3;
  FOP_EQ = 4;
  FOP_NE = 5;
  FOP_ON = 6;
  FOP_OFF = 7;
  FLOW_OPS = 8;
  FlowOpNames: array[0..FLOW_OPS - 1] of string = ('>', '<', '>=', '<=', '=', '<>', 'is ON', 'is OFF');
  FA_RUN = 0;
  FA_STOP = 1;
  FA_SET = 2;
  FA_SP = 3;
  FA_TAG = 4;
  FA_RESET = 5;
  FA_ON = 6;
  FA_OFF = 7;
  FA_POS = 8;
  FLOW_ACTS = 9;
  FlowActNames: array[0..FLOW_ACTS - 1] of string = ('Run', 'Stop', 'Set %', 'Set SP', 'Tag ON', 'Reset',
    'Switch ON', 'Switch OFF', 'Position');
  { a Random node's value }
  FR_BOOL = 0;
  FR_BYTE = 1;
  FR_INT = 2;
  FR_FLOAT = 3;
  RandomTypeNames: array[0..3] of string = ('Boolean', 'Byte', 'Integer', 'Float');

type
  TFlowNode = record
    Active: Boolean;
    Kind: Byte;
    X, Y, W, H: Single;     { canvas pixels }
    Caption: string[40];
    Src: string[24];        { input / decision / display: what it reads }
    Op: Byte;               { decision / display: its test }
    Value: Single;          { decision / display: compared with; action: the value it sets; delay: seconds }
    Target: string[24];     { action: what it works (equipment, tag); random: the name of its value }
    Act: Byte;              { action: FA_* }
    RType: Byte;            { random: FR_* }
    Value2: Single;         { random: the lowest value (Value: the highest; a boolean: Value = % true) }
    Period: Single;         { random: seconds between new values, 0 = every scan }
    Next, Next2: SmallInt;  { the next node, -1 none; a decision: Next = Yes, Next2 = No }
    Layer: Byte;
    { worked out each frame (not saved) }
    Hit: Boolean;           { the scan reached it }
    Taken: Byte;            { the way the scan left it: 1 Next, 2 Next2 }
    Known: Boolean;         { what it reads exists }
    Val: Single;            { what it reads now }
    UnitS: string[8];
    BoolV: Boolean;         { what it reads, as on / off }
    Yes: Boolean;           { decision / display: its test }
    Timer: Single;          { delay: seconds reached }
  end;

var
  FlowNodes: array[0..MAX_FLOW - 1] of TFlowNode;

procedure FlowClear;
procedure FlowDefaultSize(Kind: Integer; out W, H: Single);
function FlowAdd(Kind: Integer; X, Y: Single): Integer;
{ delete node i and every arrow to it }
procedure FlowDelete(i: Integer);
{ a decision, or a random boolean: Yes and No ways }
function FlowTwoWays(i: Integer): Boolean;
{ an arrow from a to b: a's Next, or (No) its Next2 }
procedure FlowConnect(a, b: Integer; No: Boolean);
function FlowCount: Integer;
{ the topmost node at wx, wy, -1 if none }
function FlowAt(wx, wy: Single): Integer;
{ what a name reads: a value (and its unit) and on / off; False when there is nothing by that name }
function FlowRead(const Src: string; out V: Single; out UnitS: string; out B: Boolean): Boolean;
function FlowTest(const N: TFlowNode): Boolean;
{ one scan of the charts on this page }
procedure SolveFlow(dt: Single; Running: Boolean);
{ an action node with Tag ON is reached in this scan }
function FlowTagOn(const Tag: string): Boolean;
function FlowTagDefined(const Tag: string): Boolean;
function FlowTagName(i: Integer): string;
{ the text a node shows: its caption and its line of values }
function FlowLine2(const N: TFlowNode): string;
{ a Random node's value by its name; the i-th name ('' after the last) }
function FlowValue(const Name: string; out V: Single): Boolean;
function FlowSigName(i: Integer): string;

var
  { set by the IPC unit: a value received from the network under a name that is no part }
  ExtNetValue: function(const Name: string; out V: Single): Boolean = nil;

{ ---------------------------------------------------------------- timelines

  A Timeline (equipment) runs a clock from 0 to its Length (Delay s), once
  (one cycle) or over and over (loop). Pins stand at times on it. An Input
  pin reads a name (Src) and keeps the value it has when the clock reaches
  the pin; a Fix pin has fixed values. Before, at and after its time a pin
  has a value (none, fixed, the input now, the kept input) and sends it to a
  name of its own for each of the three: equipment (on / off, > 1 a speed),
  a switch, button, breaker, overload, selector, valve, pot, drive or
  controller set point (TAG.SP), on this page or another one; a name that is
  no part becomes a tag / value of its own. A timeline that has started
  keeps sending until it is reset. }

type
  TTLPinRun = record
    Phase: Byte;             { 0 before its time, 1 at it, 2 after it }
    Live, Held, HeldT, Out: Single;
    LiveOK, HeldOK, OutOK: Boolean;
    HeldCycle: Integer;
    Virtual: Boolean;        { what it sends to is no part: the name is a tag / value of its own }
  end;

  TTLRun = record
    Pos: Single;             { the clock, s }
    Started, Done, HoldStop, AutoDone, RunTag, StopTag, WasRun: Boolean;
    Cycles: Integer;
    P: array[0..TL_PINS - 1] of TTLPinRun;
  end;
  PTLRun = ^TTLRun;

var
  TLRun: array[0..BUS_PAGES - 1, 0..MAX_EQUIP - 1] of TTLRun;

procedure TimelinesClear;
{ timeline i on the page being worked out (BusPage) }
function TLState(i: Integer): PTLRun;
procedure TimelineStart(i: Integer);
procedure TimelineStop(i: Integer);
procedure TimelineReset(i: Integer);
{ 'Input Pin 2', 'Fix Pin 1'; the name its value is read by: 'Timeline01.IN2', 'Timeline01.FIX1' }
function TLPinLabel(const E: TEquipObj; k: Integer): string;
function TLPinName(const E: TEquipObj; k: Integer): string;
function TLAddPin(i, Kind: Integer; T: Single): Integer;
procedure TLDeletePin(i, k: Integer);
{ the track of a timeline: from x0 to x1 at height ty }
procedure TLTrack(const E: TEquipObj; out x0, x1, ty: Single);
function TLTimeAt(const E: TEquipObj; wx: Single): Single;
{ the pin of timeline i at wx, wy, -1 if none }
function TLPinAt(i: Integer; wx, wy: Single): Integer;
{ send v to a name: equipment, a switch, a set point ...; False when there is no such part }
function WriteValue(const Name: string; v: Single): Boolean;
procedure SolveTimelines(dt: Single; Running: Boolean);

implementation

uses
  SysUtils, Math, elec, fluid;

{ ---------------------------------------------------------------- timelines }

procedure TimelinesClear;
begin
  FillChar(TLRun, SizeOf(TLRun), 0);
end;

function TLState(i: Integer): PTLRun;
begin
  Result := @TLRun[EnsureRange(BusPage, 0, BUS_PAGES - 1), EnsureRange(i, 0, MAX_EQUIP - 1)];
end;

procedure TimelineStart(i: Integer);
var
  R: PTLRun;
begin
  if (i < 0) or (i >= MAX_EQUIP) or (Equips[i].Kind <> EQ_TIMELINE) then Exit;
  R := TLState(i);
  R^.HoldStop := False;
  if Equips[i].State in [EQS_STOP, EQS_RUN, EQS_MSTOP] then Equips[i].State := EQS_RUN;
end;

procedure TimelineStop(i: Integer);
begin
  if (i < 0) or (i >= MAX_EQUIP) or (Equips[i].Kind <> EQ_TIMELINE) then Exit;
  if Equips[i].State in [EQS_RUN, EQS_MSTART] then Equips[i].State := EQS_STOP;
end;

procedure TimelineReset(i: Integer);
var
  R: PTLRun;
  tag, tag2: Boolean;
begin
  if (i < 0) or (i >= MAX_EQUIP) then Exit;
  R := TLState(i);
  tag := R^.RunTag;
  tag2 := R^.StopTag;
  FillChar(R^, SizeOf(TTLRun), 0);
  R^.RunTag := tag;
  R^.StopTag := tag2;
  if Equips[i].State in [EQS_RUN, EQS_MSTART] then Equips[i].State := EQS_STOP;
end;

function TLPinNum(const E: TEquipObj; k: Integer): Integer;
var
  j: Integer;
begin
  Result := 0;
  for j := 0 to k do
    if E.Pins[j].Kind = E.Pins[k].Kind then Inc(Result);
end;

function TLPinLabel(const E: TEquipObj; k: Integer): string;
begin
  if (k < 0) or (k >= TL_PINS) or (E.Pins[k].Kind = TLP_NONE) then Exit('');
  if E.Pins[k].Kind = TLP_INPUT then Result := 'Input Pin ' + IntToStr(TLPinNum(E, k))
  else Result := 'Fix Pin ' + IntToStr(TLPinNum(E, k));
end;

function TLPinName(const E: TEquipObj; k: Integer): string;
begin
  if (k < 0) or (k >= TL_PINS) or (E.Pins[k].Kind = TLP_NONE) then Exit('');
  if E.Pins[k].Kind = TLP_INPUT then Result := E.Name + '.IN' + IntToStr(TLPinNum(E, k))
  else Result := E.Name + '.FIX' + IntToStr(TLPinNum(E, k));
end;

function TLAddPin(i, Kind: Integer; T: Single): Integer;
var
  k: Integer;
  P: ^TTLPin;
begin
  Result := -1;
  if (i < 0) or (i >= MAX_EQUIP) or (Equips[i].Kind <> EQ_TIMELINE) then Exit;
  for k := 0 to TL_PINS - 1 do
    if Equips[i].Pins[k].Kind = TLP_NONE then
    begin
      P := @Equips[i].Pins[k];
      FillChar(P^, SizeOf(TTLPin), 0);
      if Kind = TLP_INPUT then
      begin
        P^.Kind := TLP_INPUT;
        P^.VMode[0] := TLV_NONE;
        P^.VMode[1] := TLV_LIVE;
        P^.VMode[2] := TLV_HELD;
      end
      else
      begin
        P^.Kind := TLP_FIX;
        P^.VMode[0] := TLV_FIX;
        P^.VMode[1] := TLV_FIX;
        P^.VMode[2] := TLV_FIX;
        P^.V[1] := 1;
      end;
      P^.T := fclamp(T, 0, fmax(0.1, Equips[i].Delay));
      P^.W := 1;
      FillChar(TLState(i)^.P[k], SizeOf(TTLPinRun), 0);
      Exit(k);
    end;
end;

procedure TLDeletePin(i, k: Integer);
begin
  if (i < 0) or (i >= MAX_EQUIP) or (k < 0) or (k >= TL_PINS) then Exit;
  FillChar(Equips[i].Pins[k], SizeOf(TTLPin), 0);
  FillChar(TLState(i)^.P[k], SizeOf(TTLPinRun), 0);
end;

procedure TLTrack(const E: TEquipObj; out x0, x1, ty: Single);
begin
  x0 := E.X + 16;
  x1 := E.X + E.W - 16;
  ty := E.Y + fmin(64, E.H * 0.5);
end;

function TLTimeAt(const E: TEquipObj; wx: Single): Single;
var
  x0, x1, ty: Single;
begin
  TLTrack(E, x0, x1, ty);
  Result := fclamp((wx - x0) / fmax(1, x1 - x0), 0, 1) * fmax(0.1, E.Delay);
end;

function TLPinAt(i: Integer; wx, wy: Single): Integer;
var
  k: Integer;
  x0, x1, ty, px: Single;
begin
  Result := -1;
  if (i < 0) or (i >= MAX_EQUIP) or (Equips[i].Kind <> EQ_TIMELINE) then Exit;
  TLTrack(Equips[i], x0, x1, ty);
  for k := 0 to TL_PINS - 1 do
    with Equips[i].Pins[k] do
      if Kind <> TLP_NONE then
      begin
        px := x0 + (x1 - x0) * fclamp(T / fmax(0.1, Equips[i].Delay), 0, 1);
        if (Abs(wx - px) <= 7) and (((Kind = TLP_INPUT) and (wy >= ty - 40) and (wy <= ty + 5)) or
          ((Kind = TLP_FIX) and (wy >= ty - 5) and (wy <= ty + 40))) then Exit(k);
      end;
end;

{ v to the parts with this tag on this page; False when there is none }
function WriteLocal(const Name: string; v: Single): Boolean;
var
  x, y, n: Integer;
  c: PECell;
  f: PFCell;
  on: Boolean;
begin
  Result := False;
  on := v >= 0.5;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @EGrid[x, y];
      if (c^.Kind = ekNone) or not SameText(c^.Tag, Name) then Continue;
      case c^.Kind of
        ekSwitch, ekPBLatch, ekAC, ekDC, ekBreaker, ekEStop: c^.On := on;
        ekPBNO, ekPBNC: c^.Held := on;
        ekSw2, ekSw3: c^.Sel := Ord(on);
        ekSelector: ESetSelectorPos(x, y, EnsureRange(Round(v) - 1, 0, Max(2, c^.NPos) - 1));
        ekOL: c^.Tripped := not on;
        ekFuse: if on then c^.Tripped := False;
        ekPot, ekDrive: c^.P1 := fclamp(v, 0, 100);
        ekController: c^.P1 := v;
      else
        Continue;
      end;
      Result := True;
    end;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      f := @FGrid[x, y];
      if (f^.Kind = fkNone) or not SameText(f^.Tag, Name) then Continue;
      Result := True;
      if FIsValve(f^.Kind) then
      begin
        n := FPositions(f^.Kind);
        if (n > 2) and (v >= 2) then f^.Sel := EnsureRange(Round(v) - 1, 0, n - 1)
        else if f^.Act = 1 then FPress(x, y, on)
        else f^.Sel := Ord(on);
      end
      else
        f^.On := on;
    end;
end;

function WriteValue(const Name: string; v: Single): Boolean;
var
  i, k, x, y: Integer;
  be: TBusEq;
  sp: Single;
begin
  Result := False;
  if Name = '' then Exit;
  i := EquipByName(Name);
  if i >= 0 then
  begin
    { equipment: on = run, off = stop; above 1 its speed / level too }
    if Equips[i].State in [EQS_STOP, EQS_RUN] then
    begin
      if (v >= 0.5) and (Equips[i].State <> EQS_RUN) then Equips[i].RunTime := 0;
      if v >= 0.5 then Equips[i].State := EQS_RUN else Equips[i].State := EQS_STOP;
    end;
    if (v > 1) and (Equips[i].Kind in [EQ_PUMP, EQ_CONVEYOR, EQ_BELT, EQ_VIBFEEDER, EQ_RAIN, EQ_HEATEX, EQ_COOLTOWER, EQ_CHILLER]) then
      Equips[i].Level := fclamp(v, 0, 100);
    Exit(True);
  end;
  { a controller's set point: TAG.SP }
  k := Pos('.', Name);
  if (k > 1) and SameText(Copy(Name, k + 1, 9), 'SP') and ECellByTag(Copy(Name, 1, k - 1), ekController, x, y) then
  begin
    EGrid[x, y].P1 := v;
    Exit(True);
  end;
  if WriteLocal(Name, v) then Exit(True);
  { on another page }
  if BusEquip(Name, be) then
  begin
    if v > 1 then sp := fclamp(v, 0, 100) else sp := -1;
    BusAddCmd(Name, v >= 0.5, sp);
    Exit(True);
  end;
  if v >= 2 then BusAddSw(Name, FA_POS, v)
  else if v >= 0.5 then BusAddSw(Name, FA_ON, v)
  else BusAddSw(Name, FA_OFF, v);
end;

procedure SolveTimelines(dt: Single; Running: Boolean);
var
  i, k: Integer;
  E: ^TEquipObj;
  R: PTLRun;
  P: ^TTLPinRun;
  L, w: Single;
  run, b: Boolean;
  u: string;
  ph: Byte;
begin
  for i := 0 to MAX_EQUIP - 1 do
  begin
    E := @Equips[i];
    if not (E^.Active and (E^.Kind = EQ_TIMELINE)) then Continue;
    R := TLState(i);
    L := fmax(0.1, E^.Delay);
    { started / stopped by a name: the moment it turns ON }
    if E^.Src <> '' then
    begin
      FlowRead(E^.Src, w, u, b);
      if b and not R^.RunTag then TimelineStart(i);
      R^.RunTag := b;
    end;
    if E^.Src2 <> '' then
    begin
      FlowRead(E^.Src2, w, u, b);
      if b and not R^.StopTag then TimelineStop(i);
      R^.StopTag := b;
    end;
    { auto start: when the simulation runs }
    if Running and ((E^.Mode and TL_AUTO) <> 0) and not R^.AutoDone then
    begin
      R^.AutoDone := True;
      TimelineStart(i);
    end;
    run := E^.State in [EQS_RUN, EQS_MSTART];
    { one cycle is over: a run request still held does not start it again }
    if R^.HoldStop then
    begin
      if run then
      begin
        E^.State := EQS_STOP;
        run := False;
      end
      else
        R^.HoldStop := False;
    end;
    if run and not R^.WasRun then
    begin
      { (re)started: after a finished cycle from 0 again }
      if R^.Done or (R^.Pos >= L) then
      begin
        R^.Pos := 0;
        for k := 0 to TL_PINS - 1 do R^.P[k].Phase := 0;
      end;
      R^.Done := False;
      R^.Started := True;
    end;
    if run and Running then
    begin
      R^.Pos := R^.Pos + dt;
      if R^.Pos >= L then
      begin
        if (E^.Mode and TL_LOOP) <> 0 then
        begin
          { the pins it passed at the very end still see their time }
          for k := 0 to TL_PINS - 1 do
            if (E^.Pins[k].Kind <> TLP_NONE) and (R^.P[k].Phase = 0) and (E^.Pins[k].T <= L) then
              R^.P[k].Phase := 3;
          while R^.Pos >= L do R^.Pos := R^.Pos - L;
          Inc(R^.Cycles);
        end
        else
        begin
          R^.Pos := L;
          R^.Done := True;
          R^.HoldStop := True;
          E^.State := EQS_STOP;
          run := False;
        end;
      end;
    end;
    R^.WasRun := run;
    { the pins }
    for k := 0 to TL_PINS - 1 do
    begin
      P := @R^.P[k];
      with E^.Pins[k] do
      begin
        if Kind = TLP_NONE then Continue;
        if Kind = TLP_INPUT then P^.LiveOK := FlowRead(Src, P^.Live, u, b)
        else P^.LiveOK := False;
        if R^.Pos < T then ph := 0
        else if R^.Pos < T + fmax(0.05, W) then ph := 1
        else ph := 2;
        { reached now (Phase 3: in the frame the loop started again) }
        if R^.Started and (((ph >= 1) and (P^.Phase = 0)) or (P^.Phase = 3)) and (Kind = TLP_INPUT) and P^.LiveOK then
        begin
          { the input as the clock reaches the pin: kept }
          P^.Held := P^.Live;
          P^.HeldOK := True;
          P^.HeldT := T;
          P^.HeldCycle := R^.Cycles;
        end;
        P^.Phase := ph;
        P^.OutOK := False;
        P^.Virtual := False;
        if not R^.Started then Continue;
        case VMode[ph] of
          TLV_FIX:
            begin
              P^.Out := V[ph];
              P^.OutOK := True;
            end;
          TLV_LIVE:
            begin
              P^.Out := P^.Live;
              P^.OutOK := P^.LiveOK;
            end;
          TLV_HELD:
            begin
              P^.Out := P^.Held;
              P^.OutOK := P^.HeldOK;
            end;
        end;
        if P^.OutOK and (Dest[ph] <> '') then P^.Virtual := not WriteValue(Dest[ph], P^.Out);
      end;
    end;
  end;
end;

{ what the timelines on this page give by name: a pin's value, a name a pin sends to that is no part, a timeline's clock }
function TLValue(const Name: string; out V: Single): Boolean;
var
  i, k: Integer;
  R: PTLRun;
begin
  V := 0;
  Result := False;
  if Name = '' then Exit;
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and (Equips[i].Kind = EQ_TIMELINE) then
    begin
      R := TLState(i);
      if SameText(Equips[i].Name, Name) then
      begin
        V := R^.Pos;
        Exit(True);
      end;
      for k := 0 to TL_PINS - 1 do
        if Equips[i].Pins[k].Kind <> TLP_NONE then
        begin
          if R^.P[k].OutOK and (SameText(TLPinName(Equips[i], k), Name) or
            (R^.P[k].Virtual and SameText(Equips[i].Pins[k].Dest[R^.P[k].Phase], Name))) then
          begin
            V := R^.P[k].Out;
            Exit(True);
          end;
        end;
    end;
end;

{ the n-th name the timelines give (Ons: only those on now) }
function TLName(n: Integer; Ons: Boolean): string;
var
  i, k, c: Integer;
  R: PTLRun;
  s: string;
begin
  Result := '';
  c := 0;
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and (Equips[i].Kind = EQ_TIMELINE) then
    begin
      R := TLState(i);
      for k := 0 to TL_PINS - 1 do
        if Equips[i].Pins[k].Kind <> TLP_NONE then
        begin
          if Ons and not (R^.P[k].OutOK and (R^.P[k].Out >= 0.5)) then Continue;
          s := TLPinName(Equips[i], k);
          if c = n then Exit(s);
          Inc(c);
          if R^.P[k].Virtual and R^.P[k].OutOK and ((R^.P[k].Out >= 0.5) or not Ons) then
          begin
            if c = n then Exit(Equips[i].Pins[k].Dest[R^.P[k].Phase]);
            Inc(c);
          end;
        end;
    end;
end;

function TLTagOn(const Tag: string): Boolean;
var
  v: Single;
begin
  Result := TLValue(Tag, v) and (v >= 0.5) and (EquipByName(Tag) < 0);
end;

function TLTagDefined(const Tag: string): Boolean;
var
  n, k: Integer;
  s: string;
begin
  Result := False;
  n := 0;
  repeat
    s := TLName(n, False);
    if SameText(s, Tag) and (s <> '') then Exit(True);
    Inc(n);
  until s = '';
  { a pin's own name, also while it gives nothing }
  for n := 0 to MAX_EQUIP - 1 do
    if Equips[n].Active and (Equips[n].Kind = EQ_TIMELINE) then
      for k := 0 to TL_PINS - 1 do
        if SameText(TLPinName(Equips[n], k), Tag) and (Tag <> '') then Exit(True);
end;


procedure FlowClear;
var
  i: Integer;
begin
  for i := 0 to MAX_FLOW - 1 do
  begin
    FillChar(FlowNodes[i], SizeOf(TFlowNode), 0);
    FlowNodes[i].Next := -1;
    FlowNodes[i].Next2 := -1;
  end;
end;

procedure FlowDefaultSize(Kind: Integer; out W, H: Single);
begin
  case Kind of
    FN_START, FN_END: begin W := 120; H := 40; end;
    FN_DECISION: begin W := 168; H := 80; end;
    FN_DISPLAY: begin W := 168; H := 56; end;
    FN_DELAY: begin W := 120; H := 48; end;
  else
    begin W := 144; H := 48; end;
  end;
end;

function FlowAdd(Kind: Integer; X, Y: Single): Integer;
var
  i: Integer;
  fw, fh: Single;
  N: ^TFlowNode;
begin
  Result := -1;
  for i := 0 to MAX_FLOW - 1 do
    if not FlowNodes[i].Active then
    begin
      N := @FlowNodes[i];
      FillChar(N^, SizeOf(TFlowNode), 0);
      FlowDefaultSize(Kind, fw, fh);
      N^.Active := True;
      N^.Kind := EnsureRange(Kind, 0, FN_KINDS - 1);
      N^.W := fw;
      N^.H := fh;
      N^.X := fclamp(X, 0, CANVAS_W - fw);
      N^.Y := fclamp(Y, 0, CANVAS_H - fh);
      N^.Next := -1;
      N^.Next2 := -1;
      N^.Layer := CurLayer;
      case N^.Kind of
        FN_START: N^.Caption := 'Start';
        FN_INPUT: N^.Caption := 'Read';
        FN_DECISION: N^.Caption := 'Check';
        FN_ACTION: N^.Caption := 'Do';
        FN_DISPLAY: N^.Caption := 'Show';
        FN_DELAY:
          begin
            N^.Caption := 'Wait';
            N^.Value := 2;
          end;
        FN_END: N^.Caption := 'End';
        FN_RANDOM:
          begin
            N^.Caption := 'Random';
            N^.RType := FR_BOOL;
            N^.Value := 50;
            N^.Value2 := 0;
            N^.Period := 1;
            N^.Target := 'RND' + IntToStr(i + 1);
          end;
      end;
      Exit(i);
    end;
end;
procedure FlowDelete(i: Integer);
var
  k: Integer;
begin
  if (i < 0) or (i >= MAX_FLOW) then Exit;
  FlowNodes[i].Active := False;
  for k := 0 to MAX_FLOW - 1 do
  begin
    if FlowNodes[k].Next = i then FlowNodes[k].Next := -1;
    if FlowNodes[k].Next2 = i then FlowNodes[k].Next2 := -1;
  end;
end;

function FlowTwoWays(i: Integer): Boolean;
begin
  Result := (FlowNodes[i].Kind = FN_DECISION) or ((FlowNodes[i].Kind = FN_RANDOM) and (FlowNodes[i].RType = FR_BOOL));
end;

procedure FlowConnect(a, b: Integer; No: Boolean);
begin
  if (a < 0) or (a >= MAX_FLOW) or (b < 0) or (b >= MAX_FLOW) or (a = b) then Exit;
  if not (FlowNodes[a].Active and FlowNodes[b].Active) or (FlowNodes[a].Kind = FN_END) then Exit;
  if No and FlowTwoWays(a) then FlowNodes[a].Next2 := b else FlowNodes[a].Next := b;
end;

function FlowCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to MAX_FLOW - 1 do
    if FlowNodes[i].Active then Inc(Result);
end;

function FlowAt(wx, wy: Single): Integer;
var
  i: Integer;
begin
  for i := MAX_FLOW - 1 downto 0 do
    with FlowNodes[i] do
      if Active and (wx >= X) and (wx < X + W) and (wy >= Y) and (wy < Y + H) then Exit(i);
  Result := -1;
end;

function FlowRead(const Src: string; out V: Single; out UnitS: string; out B: Boolean): Boolean;
var
  i: Integer;
  be: TBusEq;
begin
  V := 0;
  UnitS := '';
  B := False;
  Result := False;
  if Src = '' then Exit;
  { equipment: running or not, and its level / speed / temperature }
  i := EquipByName(Src);
  if i >= 0 then
  begin
    B := EquipRunning(i);
    if not AnalogValue(Src, V, UnitS) then V := Ord(B);
    Exit(True);
  end;
  if BusEquip(Src, be) then
  begin
    B := be.State in [EQS_RUN, EQS_MSTART];
    if not BusSignal(Src, V, UnitS) then V := Ord(B);
    Exit(True);
  end;
  { a value by name; a tag (coil, timer, switch, sensor contact ...) }
  if AnalogValue(Src, V, UnitS) then
  begin
    B := ESignal(Src) or (V > 0.5);
    Exit(True);
  end;
  B := ESignal(Src);
  V := Ord(B);
  Result := B or ETagKnown(Src);
end;

function FlowTest(const N: TFlowNode): Boolean;
begin
  if not N.Known then Exit(False);
  case N.Op of
    FOP_GT: Result := N.Val > N.Value;
    FOP_LT: Result := N.Val < N.Value;
    FOP_GE: Result := N.Val >= N.Value;
    FOP_LE: Result := N.Val <= N.Value;
    FOP_EQ: Result := Abs(N.Val - N.Value) < 1e-3 * fmax(1, Abs(N.Value));
    FOP_NE: Result := Abs(N.Val - N.Value) >= 1e-3 * fmax(1, Abs(N.Value));
    FOP_ON: Result := N.BoolV;
  else
    Result := not N.BoolV;
  end;
end;

{ an ON / OFF / Reset / Position command to the switches, buttons, breakers, overloads, valves and
  compressors with this tag on this page; False when there is none }
function SwitchLocal(const Name: string; Act: Integer; Value: Single): Boolean;
var
  x, y, p: Integer;
  c: PECell;
  f: PFCell;
begin
  Result := False;
  if Name = '' then Exit;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @EGrid[x, y];
      if (c^.Kind = ekNone) or not SameText(c^.Tag, Name) then Continue;
      Result := True;
      case Act of
        FA_ON:
          case c^.Kind of
            ekSwitch, ekPBLatch, ekAC, ekDC, ekBreaker, ekEStop: c^.On := True;
            ekPBNO, ekPBNC: c^.Held := True;
            ekSw2, ekSw3: c^.Sel := 1;
            ekSelector: c^.Sel := EnsureRange(c^.Pos - 1, 0, 9);
            ekOL, ekFuse: c^.Tripped := False;
          end;
        FA_OFF:
          case c^.Kind of
            ekSwitch, ekPBLatch, ekAC, ekDC, ekBreaker, ekEStop: c^.On := False;
            ekPBNO, ekPBNC: c^.Held := False;
            ekSw2, ekSw3: c^.Sel := 0;
            ekSelector: c^.Sel := 0;
            ekOL: c^.Tripped := True;     { an overload switched off: tripped }
          end;
        FA_RESET:
          begin
            if c^.Kind in [ekOL, ekFuse, ekBreaker, ekAC, ekDC] then c^.Tripped := False;
            if c^.Kind = ekCounter then c^.Acc := 0;
          end;
        FA_POS:
          begin
            p := Round(Value) - 1;
            case c^.Kind of
              ekSelector: ESetSelectorPos(x, y, EnsureRange(p, 0, Max(2, c^.NPos) - 1));
              ekSw2, ekSw3: c^.Sel := EnsureRange(p, 0, 1);
            end;
          end;
        FA_SET:
          if c^.Kind in [ekPot, ekDrive] then c^.P1 := fclamp(Value, 0, 100);
      end;
    end;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      f := @FGrid[x, y];
      if (f^.Kind = fkNone) or not SameText(f^.Tag, Name) then Continue;
      Result := True;
      case Act of
        FA_ON:
          if FIsValve(f^.Kind) then
          begin
            if f^.Act = 1 then FPress(x, y, True) else f^.Sel := 1;
          end
          else
            f^.On := True;
        FA_OFF:
          if FIsValve(f^.Kind) then
          begin
            if f^.Act = 1 then FPress(x, y, False) else f^.Sel := 0;
          end
          else
            f^.On := False;
        FA_POS:
          if FIsValve(f^.Kind) then f^.Sel := EnsureRange(Round(Value) - 1, 0, Max(1, FPositions(f^.Kind) - 1));
        FA_SET:
          f^.P1 := Value;
      end;
    end;
end;

procedure DoAction(var N: TFlowNode);
var
  i, x, y: Integer;
  v, rv: Single;
  u: string;
  rb: Boolean;
begin
  if N.Target = '' then Exit;
  { the value it sets: its own, or what it reads (Src) }
  v := N.Value;
  if (N.Src <> '') and FlowRead(N.Src, rv, u, rb) then v := rv;
  i := EquipByName(N.Target);
  case N.Act of
    FA_RUN, FA_STOP:
      if i >= 0 then
      begin
        if Equips[i].State in [EQS_STOP, EQS_RUN] then
        begin
          if (N.Act = FA_RUN) and (Equips[i].State <> EQS_RUN) then Equips[i].RunTime := 0;
          if N.Act = FA_RUN then Equips[i].State := EQS_RUN else Equips[i].State := EQS_STOP;
        end;
      end
      else
        BusAddCmd(N.Target, N.Act = FA_RUN, -1);
    FA_SET:
      if i >= 0 then Equips[i].Level := fclamp(v, 0, 100)
      else if not SwitchLocal(N.Target, FA_SET, v) then
        BusAddCmd(N.Target, True, fclamp(v, 0, 100));
    FA_SP:
      if ECellByTag(N.Target, ekController, x, y) then EGrid[x, y].P1 := v;
    FA_RESET:
      if i >= 0 then
      begin
        if Equips[i].State = EQS_FAULT then Equips[i].State := EQS_STOP;
      end
      else if not SwitchLocal(N.Target, FA_RESET, v) then
        BusAddSw(N.Target, FA_RESET, v);
    FA_ON, FA_OFF:
      if i >= 0 then
      begin
        { equipment: on = run, off = stop }
        if Equips[i].State in [EQS_STOP, EQS_RUN] then
        begin
          if (N.Act = FA_ON) and (Equips[i].State <> EQS_RUN) then Equips[i].RunTime := 0;
          if N.Act = FA_ON then Equips[i].State := EQS_RUN else Equips[i].State := EQS_STOP;
        end;
      end
      else if not SwitchLocal(N.Target, N.Act, v) then
        BusAddSw(N.Target, N.Act, v);
    FA_POS:
      if not SwitchLocal(N.Target, FA_POS, v) then BusAddSw(N.Target, FA_POS, v);
  end;
end;

{ a new value for a Random node }
procedure RollRandom(var N: TFlowNode);
var
  lo, hi: Single;
begin
  lo := fmin(N.Value2, N.Value);
  hi := fmax(N.Value2, N.Value);
  case N.RType of
    FR_BOOL:
      begin
        N.BoolV := Random * 100 < N.Value;
        N.Val := Ord(N.BoolV);
      end;
    FR_BYTE:
      begin
        lo := EnsureRange(Round(lo), 0, 255);
        hi := EnsureRange(Round(hi), 0, 255);
        N.Val := Round(lo) + Random(Round(hi) - Round(lo) + 1);
        N.BoolV := N.Val > 0.5;
      end;
    FR_INT:
      begin
        N.Val := Round(lo) + Random(Round(hi) - Round(lo) + 1);
        N.BoolV := N.Val > 0.5;
      end;
  else
    begin
      N.Val := lo + Random * (hi - lo);
      N.BoolV := N.Val > 0.5;
    end;
  end;
  N.UnitS := '';
  N.Known := True;
  N.Yes := N.BoolV;
end;
procedure SolveFlow(dt: Single; Running: Boolean);
var
  u: string;
  sw: TBusSw;
  i, s, cur, steps: Integer;
  N: ^TFlowNode;
begin
  { commands from the other pages' charts to switches here; then this page's own commands start afresh }
  i := 0;
  while BusSwIndex(i, sw) do
  begin
    SwitchLocal(sw.Name, sw.Act, sw.Value);
    Inc(i);
  end;
  BusClearSws(BusPage);
  SolveTimelines(dt, Running);
  if FlowCount = 0 then Exit;
  { random values: a new one every Period s }
  for i := 0 to MAX_FLOW - 1 do
  begin
    N := @FlowNodes[i];
    if not (N^.Active and (N^.Kind = FN_RANDOM)) then Continue;
    if Running then N^.Timer := N^.Timer + dt;
    if (not N^.Known) or (N^.Period <= 0) or (N^.Timer >= N^.Period) then
    begin
      RollRandom(N^);
      N^.Timer := 0;
    end;
  end;
  { what every node reads now; displays and decisions off any path show it too }
  for i := 0 to MAX_FLOW - 1 do
  begin
    N := @FlowNodes[i];
    N^.Hit := False;
    N^.Taken := 0;
    if not N^.Active then Continue;
    if N^.Kind in [FN_INPUT, FN_DECISION, FN_DISPLAY] then
    begin
      N^.Known := FlowRead(N^.Src, N^.Val, u, N^.BoolV);
      N^.UnitS := Copy(u, 1, 8);
      N^.Yes := FlowTest(N^);
    end;
  end;
  { the scan: from every Start along the arrows }
  for s := 0 to MAX_FLOW - 1 do
  begin
    if not (FlowNodes[s].Active and (FlowNodes[s].Kind = FN_START)) then Continue;
    cur := s;
    steps := 0;
    while (cur >= 0) and (cur < MAX_FLOW) and (steps <= MAX_FLOW) do
    begin
      N := @FlowNodes[cur];
      if (not N^.Active) or N^.Hit then Break;   { a loop ends the scan }
      N^.Hit := True;
      Inc(steps);
      case N^.Kind of
        FN_DECISION, FN_RANDOM:
          if (N^.Kind = FN_RANDOM) and (N^.RType <> FR_BOOL) then
          begin
            N^.Taken := 1;
            cur := N^.Next;
          end
          else if N^.Yes then
          begin
            N^.Taken := 1;
            cur := N^.Next;
          end
          else
          begin
            N^.Taken := 2;
            cur := N^.Next2;
          end;
        FN_ACTION:
          begin
            DoAction(N^);
            N^.Taken := 1;
            cur := N^.Next;
          end;
        FN_DELAY:
          begin
            if Running then N^.Timer := N^.Timer + dt;
            if N^.Timer >= N^.Value then
            begin
              N^.Taken := 1;
              cur := N^.Next;
            end
            else
              Break;
          end;
        FN_END:
          Break;
      else
        begin
          N^.Taken := 1;
          cur := N^.Next;
        end;
      end;
    end;
  end;
  { a delay the scan no longer reaches starts again from 0 }
  for i := 0 to MAX_FLOW - 1 do
    if FlowNodes[i].Active and (FlowNodes[i].Kind = FN_DELAY) and not FlowNodes[i].Hit then FlowNodes[i].Timer := 0;
end;

function FlowTagOn(const Tag: string): Boolean;
var
  i: Integer;
  v: Single;
begin
  Result := False;
  if Tag = '' then Exit;
  for i := 0 to MAX_FLOW - 1 do
    with FlowNodes[i] do
      if Active and ((Hit and (Kind = FN_ACTION) and (Act = FA_TAG)) or ((Kind = FN_RANDOM) and (RType = FR_BOOL) and BoolV)) and
        SameText(Target, Tag) then Exit(True);
  Result := TLTagOn(Tag);
  if (not Result) and Assigned(ExtNetValue) and ExtNetValue(Tag, v) and (EquipByName(Tag) < 0) then Result := v >= 0.5;
end;

function FlowTagDefined(const Tag: string): Boolean;
var
  i: Integer;
  v: Single;
begin
  Result := False;
  if Tag = '' then Exit;
  for i := 0 to MAX_FLOW - 1 do
    with FlowNodes[i] do
      if Active and (((Kind = FN_ACTION) and (Act = FA_TAG)) or ((Kind = FN_RANDOM) and (RType = FR_BOOL))) and
        SameText(Target, Tag) then Exit(True);
  Result := TLTagDefined(Tag);
  if (not Result) and Assigned(ExtNetValue) then Result := ExtNetValue(Tag, v);
end;

function FlowTagName(i: Integer): string;
var
  k, n: Integer;
begin
  Result := '';
  n := 0;
  for k := 0 to MAX_FLOW - 1 do
    with FlowNodes[k] do
      if Active and (Target <> '') and ((Hit and (Kind = FN_ACTION) and (Act = FA_TAG)) or
        ((Kind = FN_RANDOM) and (RType = FR_BOOL) and BoolV)) then
      begin
        if n = i then Exit(Target);
        Inc(n);
      end;
  Result := TLName(i - n, True);
end;

function ValueText(const N: TFlowNode): string;
begin
  if not N.Known then Exit('----');
  if (N.UnitS = '') and ((N.Val = 0) or (N.Val = 1)) then
  begin
    if N.BoolV then Result := 'ON' else Result := 'OFF';
  end
  else if Abs(N.Val) >= 100 then Result := Format('%.0f %s', [N.Val, N.UnitS])
  else Result := Format('%.1f %s', [N.Val, N.UnitS]);
  Result := Trim(Result);
end;

function FlowLine2(const N: TFlowNode): string;
begin
  case N.Kind of
    FN_INPUT: Result := N.Src + ' = ' + ValueText(N);
    FN_DECISION, FN_DISPLAY:
      begin
        if N.Op in [FOP_ON, FOP_OFF] then Result := N.Src + ' ' + FlowOpNames[N.Op]
        else Result := Format('%s %s %g', [N.Src, FlowOpNames[N.Op], N.Value]);
        if N.Kind = FN_DISPLAY then Result := ValueText(N);
      end;
    FN_ACTION:
      if (N.Act in [FA_SET, FA_SP, FA_POS]) and (N.Src <> '') then Result := Format('%s %s = %s', [FlowActNames[N.Act], N.Target, N.Src])
      else if N.Act in [FA_SET, FA_SP, FA_POS] then Result := Format('%s %s %g', [FlowActNames[N.Act], N.Target, N.Value])
      else Result := FlowActNames[N.Act] + ' ' + N.Target;
    FN_DELAY: Result := Format('%.1f / %.1f s', [N.Timer, N.Value]);
    FN_RANDOM:
      case N.RType of
        FR_BOOL: if N.BoolV then Result := N.Target + ' = TRUE' else Result := N.Target + ' = FALSE';
        FR_FLOAT: Result := Format('%s = %.3f', [N.Target, N.Val]);
      else
        Result := Format('%s = %.0f', [N.Target, N.Val]);
      end;
  else
    Result := '';
  end;
end;

function FlowValue(const Name: string; out V: Single): Boolean;
var
  i: Integer;
begin
  V := 0;
  Result := False;
  if Name = '' then Exit;
  for i := 0 to MAX_FLOW - 1 do
    with FlowNodes[i] do
      if Active and (Kind = FN_RANDOM) and Known and SameText(Target, Name) then
      begin
        V := Val;
        Exit(True);
      end;
  Result := TLValue(Name, V);
  if (not Result) and Assigned(ExtNetValue) then Result := ExtNetValue(Name, V);
end;

function FlowSigName(i: Integer): string;
var
  k, n: Integer;
begin
  Result := '';
  n := 0;
  for k := 0 to MAX_FLOW - 1 do
    with FlowNodes[k] do
      if Active and (Kind = FN_RANDOM) and (Target <> '') then
      begin
        if n = i then Exit(Target);
        Inc(n);
      end;
  Result := TLName(i - n, False);
end;

procedure FlowHookProc(dt: Single; Running: Boolean);
begin
  SolveFlow(dt, Running);
end;

initialization
  FlowClear;
  TimelinesClear;
  FlowHook := @FlowHookProc;
  ClearHook3 := @FlowClear;
  ExtFlowTag := @FlowTagOn;
  ExtFlowTagDefined := @FlowTagDefined;
  ExtFlowTagName := @FlowTagName;
  ExtFlowValue := @FlowValue;
  ExtFlowSigName := @FlowSigName;

end.
