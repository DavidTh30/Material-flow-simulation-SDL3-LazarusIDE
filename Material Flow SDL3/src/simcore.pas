unit simcore;

{ Material flow simulation core.

  The piping lives on a grid. Every non-empty cell is a node of an air-flow
  network; pipes connect neighbouring cells explicitly (Conn bit mask), so a
  cell with 1 connection is an open end, 2 a straight/elbow, 3 a tee (3-way)
  and 4 a cross.

  Air flow: each edge has a conductance that depends on the smaller pipe size
  (constrictions resist) and an optional pump head (blower, suction head,
  push-out nozzle).  Open mouths and vented tanks are held at atmospheric
  pressure; the remaining pressures are solved with SOR Gauss-Seidel.  The
  resulting edge flows give the local air speed (flow / pipe width), so air
  speeds up in a constriction and slows down in an expansion.

  Material: particles (water, oil, fluff, sand and air tracers).  Inside a
  pipe they are dragged by the air (per-material coupling), feel gravity and
  wall friction and are confined to the pipe shape.  Leaving a mouth they
  become free particles with gravity, air drag, particle-particle contact,
  buoyancy, buckets and the floor. }

{$mode objfpc}{$H+}

interface

const
  CELL = 24;
  HALF = 12;
  GW = 44;
  GH = 34;
  CANVAS_W = GW * CELL;
  CANVAS_H = GH * CELL;
  FLOOR_Y = CANVAS_H - 4;
  MAX_PART = 16000;
  MAX_AIR = 2500;
  MAX_BUCKETS = 8;
  MAX_LABELS = 64;
  MAX_FRAMES = 32;
  MAX_LINKS = 32;
  MAX_EQUIP = 48;
  STEAM_MARK = 7;     { ExitDir of a free steam wisp }
  { equipment kinds (drawn plant equipment, see TEquipObj) }
  EQ_MOTOR = 0;
  EQ_BLOWER = 1;
  EQ_PADDLE = 2;
  EQ_SCREW = 3;
  EQ_CYCLONE = 4;
  EQ_SILO = 5;
  EQ_STAND = 6;
  EQ_LAMP = 7;
  EQ_LEGEND = 8;
  EQ_SEQUENCE = 9;
  EQ_DIVERTER = 10;
  EQ_SHUTTER = 11;
  EQ_SLIDE = 12;
  EQ_HEATER = 13;
  EQ_IRHEATER = 14;
  EQ_RAIN = 15;
  EQ_FIRE = 16;
  EQ_POND = 17;
  EQ_POOL = 18;
  EQ_WELL = 19;
  EQ_PUMP = 20;
  EQ_PANEL = 21;
  EQ_CONVEYOR = 22;
  EQ_BELT = 23;
  EQ_GAUGE = 24;
  EQ_DIGITAL = 25;
  EQ_CYLINDER = 26;
  EQ_COMPRESSOR = 27;
  EQ_HPU = 28;
  EQ_RECEIVER = 29;
  EQ_CONTROLLER = 30;
  EQ_HEATEX = 31;
  EQ_COOLTOWER = 32;
  EQ_CHILLER = 33;
  EQ_TREND = 34;
  EQ_TIMELINE = 35;
  EQ_DRYER = 36;
  EQ_ITEMFEEDER = 37;
  EQ_WORKER = 38;
  EQ_VAN = 39;
  EQ_RACK = 40;
  EQ_KINDS = 41;
  EquipNames: array[0..EQ_KINDS - 1] of string = ('Motor', 'Blower', 'Paddle', 'Screw', 'Cyclone',
    'Silo bin', 'Silo stand', 'Lamp', 'Legend', 'Sequence', 'Diverter valve', 'Shutter valve', 'Slide valve',
    'Heater', 'IR heater', 'Rain', 'Fire', 'Pond', 'Pool', 'Well', 'Pump',
    'Electrical cabinet', 'Roller conveyor', 'Belt conveyor', 'Analog gauge', 'Digital display',
    'Cylinder', 'Air compressor', 'Hydraulic power unit', 'Air receiver', 'Controller faceplate', 'Heat exchanger', 'Cooling tower', 'Chiller', 'Trend chart', 'Timeline', 'Rotary dryer', 'Item feeder', 'Worker', 'Box van', 'Standard rack');
  EquipTags: array[0..EQ_KINDS - 1] of string = ('motor', 'blower', 'paddle', 'screw', 'cyclone',
    'silo', 'stand', 'lamp', 'legend', 'sequence', 'diverter', 'shutter', 'slide', 'heater', 'irheater',
    'rain', 'fire', 'pond', 'pool', 'well', 'pump', 'panel', 'conveyor', 'belt', 'gauge', 'digital', 'cylinder', 'compressor', 'hpu', 'receiver', 'faceplate', 'heatex', 'coolingtower', 'chiller', 'trend', 'timeline', 'dryer', 'itemfeeder', 'worker', 'van', 'rack');
  { equipment states }
  EQS_STOP = 0;
  EQS_RUN = 1;
  EQS_FAULT = 2;
  EQS_MSTART = 3;    { manual start (running) }
  EQS_MSTOP = 4;     { manual stop }
  EQS_DISABLE = 5;   { taken out of service }
  EQS_COUNT = 6;
  { timeline pins: an Input pin keeps what it reads at its time, a Fix pin has fixed values }
  TL_PINS = 8;
  TLP_NONE = 0;
  TLP_INPUT = 1;
  TLP_FIX = 2;
  { what a pin gives before / at / after its time }
  TLV_NONE = 0;
  TLV_FIX = 1;
  TLV_LIVE = 2;
  TLV_HELD = 3;
  TLPhaseNames: array[0..2] of string = ('Before', 'At', 'After');
  TLValueNames: array[0..3] of string = ('-', 'Fixed', 'Input', 'Kept');
  { a timeline's Mode: bits }
  TL_LOOP = 1;
  TL_AUTO = 2;
  { sequence modes }
  SEQ_AUTO = 0;
  SEQ_MANUAL = 1;
  SEQ_ESTOP = 2;
  MAX_SEQ_STEP = 9;
  LBL_TEXT = 0;
  LBL_DATE = 1;
  LBL_TIME = 2;
  PDIAM = 3.0;
  PRAD = 1.5;
  WALL_T = 6.0;
  STOCK_MAX = 3000;
  HOPPER_CAP = 300;   { a hopper holds little: it passes material on }
  SILO_CAP = 4000;    { a silo stores }
  MAX_DIA = 5;

  DXS: array[0..3] of Integer = (1, 0, -1, 0);   { E, S, W, N }
  DYS: array[0..3] of Integer = (0, 1, 0, -1);

type
  TMat = (mWater, mOil, mFluff, mSand, mAir);

  TMatProps = record
    Name: string[8];
    R, G, B, A: Byte;
    Mass, Grav, Couple, Drag, Fric, Dens: Single;
    Liquid: Boolean;
    Size: Single;
    PH: Single;            { its pH when wet (pH sensors) }
  end;

  TCellKind = (ckEmpty, ckPipe, ckSource, ckBlower, ckSuction, ckNozzle,
    ckDrop, ckCheck, ckValve2, ckValve3, ckValve4, ckHopper, ckSilo, ckVFeeder);

  PCell = ^TCell;
  TCell = record
    Kind: TCellKind;
    Conn: Byte;          { bit d = pipe joins the neighbour in direction d }
    Dia: Integer;        { pipe size 1..MAX_DIA }
    Dir: Integer;        { device direction (blower/check: flow, others: mouth; valve3: closed branch or -1) }
    Open: Boolean;       { 2-way valve state }
    Closed: Byte;        { 4-way valve: bit d = branch d is shut }
    Layer: Byte;         { the page layer the part is on }
    Strength: Single;    { 0..100: blow / suction / push-out / drop gate }
    Halted: Boolean;     { stopped: the equipment linked to it is not running }
    Stock: array[TMat] of Single;  { tank contents }
    AirPct, Feed: Single;          { tank air mix % and feed rate % }
    EmitAcc, AirAcc: Single;
    P: Single;                     { pressure }
    F: array[0..3] of Single;      { out-flow through each side (negative = in-flow) }
    ECon, EPf, EPb: array[0..3] of Boolean;
    EG, EH: array[0..3] of Single;
    Mouth: Integer;                { open side to the atmosphere, -1 if none }
    Fixed: Boolean;
    Spin: Single;
  end;

  PParticle = ^TParticle;
  TParticle = record
    X, Y, VX, VY: Single;
    Life: Single;
    CX, CY: SmallInt;
    ExitDir: ShortInt;
    Bucket: ShortInt;
    Mat: TMat;
    InPipe: Boolean;
  end;

  TBucket = record
    Active: Boolean;
    Layer: Byte;
    X, Y, W, H: Single;  { interior; walls are outside it }
    Count: Integer;
    Spilled: Integer;
    Flash: Single;
  end;

  { a text label on the canvas: a free description of part of the layout }
  TLabelObj = record
    Active: Boolean;
    X, Y: Single;          { top-left corner, canvas pixels }
    Text: string[255];     { lines separated by #10; for a date / time label: its caption }
    Kind: Byte;            { LBL_TEXT, LBL_DATE, LBL_TIME }
    Fmt: string[40];       { date / time format (FormatDateTime codes) }
    Color: Byte;           { 0 theme, 1 blue, 2 green, 3 amber, 4 red, 5 white }
    NoBox: Boolean;        { no frame / background behind the text }
    Layer: Byte;
  end;

  { a titled frame drawn behind a group of parts, to group and categorise them }
  TFrameObj = record
    Active: Boolean;
    X, Y, W, H: Single;    { canvas pixels }
    Title: string[60];
    Color: Byte;           { 0 theme, 1 blue, 2 green, 3 amber, 4 red, 5 white }
    Dashed: Boolean;       { dashed outline }
    Fill: Boolean;         { a light tint inside }
    Carry: Boolean;        { moving the frame moves what is inside it }
    Layer: Byte;
  end;

  { a button on the canvas that jumps to a page or opens a frame popup }
  TLinkObj = record
    Active: Boolean;
    X, Y: Single;
    Caption: string[40];
    ToPopup: Boolean;      { False: go to page Target; True: open frame popup Target }
    Target: Integer;
    Color: Byte;
    Layer: Byte;
  end;

  { a piece of plant equipment drawn on the canvas: motor, blower, paddle agitator,
    screw conveyor, cyclone, silo bin, silo stand, status lamp or legend.
    It may be linked to a grid part: while a motor-driven one is not running
    (stopped or faulted) the linked part is halted; a silo bin shows the
    linked store's level; a lamp lights while the linked part carries flow. }
  { a pin on a timeline }
  TTLPin = record
    Kind: Byte;                            { TLP_* }
    T, W: Single;                          { its time and how long "at" it lasts, s }
    Src: string[24];                       { an Input pin: what it reads }
    VMode: array[0..2] of Byte;            { before / at / after: TLV_* }
    V: array[0..2] of Single;              { before / at / after: its fixed value }
    Dest: array[0..2] of string[24];       { before / at / after: where it sends its value }
  end;

  TEquipObj = record
    Active: Boolean;
    Kind: Byte;            { EQ_* }
    X, Y, W, H: Single;    { canvas pixels }
    Name: string[24];
    State: Byte;           { EQS_STOP, EQS_RUN, EQS_FAULT }
    Flip: Boolean;         { mirrored left-right (motor on the other side) }
    LinkX, LinkY: SmallInt;{ linked grid cell, -1 = none }
    Level: Single;         { silo bin level 0..100 when not linked }
    Layer: Byte;
    Mode: Byte;            { sequence: SEQ_AUTO, SEQ_MANUAL, SEQ_ESTOP }
    SeqStep: Byte;         { its step in the start sequence 1..MAX_SEQ_STEP, 0 = not in it }
    Delay: Single;         { seconds the sequence waits before starting / stopping its step }
    DivA, DivB: ShortInt;  { diverter: the branch shut in position 1 (running) / position 2, -1 none }
    RunTime: Single;       { seconds in the running state (not saved) }
    Phase: Single;         { animation: impeller / screw / paddle turn (not saved) }
    Heat: Single;          { fire: how strongly it burns; rain: drops to come (not saved) }
    Wait: Single;          { > 0: the sequence starts it in Wait s, < 0: stops it in -Wait s (not saved) }
    SeqPos: SmallInt;      { sequence: steps started so far (not saved) }
    SeqT, ReqT: Single;    { sequence: time in the current step / the request held (not saved) }
    LastReq: Boolean;
    Src: string[24];       { gauge / display: what it shows (an electrical tag or an equipment name) }
    RMin, RMax: Single;    { gauge / display: its range }
    Temp: Single;          { heater / IR heater / fire: its temperature in C, 0 = not yet worked out; heat exchanger:
                             its cold (shell) outlet (not saved) }
    HotIn, HotOut, ColdIn, Duty: Single;   { heat exchanger: C and kW (not saved) }
    Src2, Src3, Src4: string[24];          { trend chart: its pens 2..4 (Src is pen 1); Mode its style, Delay its time window }
    Pins: array[0..TL_PINS - 1] of TTLPin; { timeline: its pins; Delay its length, Mode TL_LOOP / TL_AUTO, Src what starts it }
  end;

  TIntake = record
    MX, MY, R, CapR, Str: Single;
    CX, CY, D: Integer;
    Suction: Boolean;
  end;

  { a hopper funnel / silo opening that catches falling material, or a solid silo body }
  TCatch = record
    X1, Y1, X2, Y2: Single;
    GX, GY: Integer;
  end;

  TJet = record
    MX, MY, L, Str: Single;
    D: Integer;
  end;

var
  { the world and material physics: variables, so the Physics Lab can change them }
  GRAVITY: Single = 500.0;   { px/s^2 at 100% gravity }
  VK: Single = 120.0;        { air speed (px/s) per unit of flow in a size-3 pipe }
  EMIT_K: Single = 40.0;     { tank particles per second per unit of out-flow }
  GRAV_FEED: Single = 70.0;  { tank particles per second fed by gravity alone }
  AIR_K: Single = 12.0;      { air tracer dots per second per unit of flow }
  MatP: array[TMat] of TMatProps = (
    (Name: 'Water'; R: 40; G: 130; B: 255; A: 255; Mass: 1.0; Grav: 1.0; Couple: 6.0; Drag: 0.15; Fric: 0.02; Dens: 1.0; Liquid: True; Size: 3; PH: 7.0),
    (Name: 'Oil'; R: 230; G: 165; B: 25; A: 255; Mass: 0.85; Grav: 1.0; Couple: 4.5; Drag: 0.2; Fric: 0.08; Dens: 0.85; Liquid: True; Size: 3; PH: 6.5),
    (Name: 'Fluff'; R: 245; G: 220; B: 235; A: 225; Mass: 0.15; Grav: 0.25; Couple: 12.0; Drag: 3.0; Fric: 0.25; Dens: 0.1; Liquid: False; Size: 4; PH: 5.5),
    (Name: 'Sand'; R: 196; G: 158; B: 92; A: 255; Mass: 1.6; Grav: 1.0; Couple: 4.0; Drag: 0.08; Fric: 0.55; Dens: 1.6; Liquid: False; Size: 3; PH: 8.8),
    (Name: 'Air'; R: 190; G: 225; B: 255; A: 80; Mass: 0.05; Grav: -0.2; Couple: 30.0; Drag: 4.0; Fric: 0.0; Dens: 0.0; Liquid: False; Size: 2; PH: 5.6)
  );

var
  Grid: array[0..GW - 1, 0..GH - 1] of TCell;
  Parts: array of TParticle;
  NPart: Integer = 0;
  NAir: Integer = 0;
  Buckets: array[0..MAX_BUCKETS - 1] of TBucket;
  Labels: array[0..MAX_LABELS - 1] of TLabelObj;
  Frames: array[0..MAX_FRAMES - 1] of TFrameObj;
  Links: array[0..MAX_LINKS - 1] of TLinkObj;
  Equips: array[0..MAX_EQUIP - 1] of TEquipObj;
  CurLayer: Byte = 0;      { new parts, buckets, labels, frames and links go on this layer }
  Intakes: array[0..63] of TIntake;
  NIntake: Integer = 0;
  Jets: array[0..63] of TJet;
  NJet: Integer = 0;
  Catches: array[0..63] of TCatch;
  NCatch: Integer = 0;
  Bodies: array[0..63] of TCatch;
  NBody: Integer = 0;
  { the decks of inclined conveyors: solid lines from (X1, Y1) to (X2, Y2) }
  Slopes: array[0..15] of TCatch;
  NSlope: Integer = 0;
  GravityScale: Single = 1.0;
  { set by the electrical unit: solve the circuits before each frame / clear them with the layout }
  ElecHook: procedure(dt: Single; Running: Boolean) = nil;
  ClearHook: procedure = nil;
  { set by the fluid power unit: solve the pneumatic / hydraulic circuits (after the electrical ones) / clear them }
  FluidHook: procedure(dt: Single; Running: Boolean) = nil;
  ClearHook2: procedure = nil;
  { set by the flow chart unit: one scan of the page's flow charts (after the circuits) / clear them }
  FlowHook: procedure(dt: Single; Running: Boolean) = nil;
  ClearHook3: procedure = nil;
  { set by the trend unit: record the trend charts after the frame's logic }
  TrendHook: procedure(dt: Single; Running: Boolean) = nil;
  { set by the pieces unit: move the pieces (bottles, boxes ...) / clear them }
  PieceHook: procedure(dt: Single) = nil;
  ClearHook4: procedure = nil;
  LimitHit: Boolean = False;

function fmin(a, b: Single): Single; inline;
function fmax(a, b: Single): Single; inline;
function fclamp(v, lo, hi: Single): Single; inline;

function InGrid(x, y: Integer): Boolean;
function IsStore(K: TCellKind): Boolean;
function StoreTotal(const c: TCell): Single;
function StoreCap(K: TCellKind): Single;
{ the area a hopper / silo draws above its outlet cell (canvas pixels) }
function StoreShape(gx, gy: Integer; out x1, y1, x2, y2: Single): Boolean;
function HWOf(Dia: Integer): Single;
function Opp(d: Integer): Integer;
function Connected(x, y, d: Integer): Boolean;
function ConnCount(x, y: Integer): Integer;

procedure ClearAll;
procedure ClearParticles;
procedure ClearFloor;
procedure ResetCell(x, y: Integer);
procedure MakePipe(x, y, Dia: Integer);
procedure ConnectCells(x1, y1, x2, y2: Integer);
procedure PipeLine(x1, y1, x2, y2, Dia: Integer);
procedure EraseCell(x, y: Integer);
procedure SetKind(x, y: Integer; K: TCellKind);
procedure RotateCell(x, y: Integer);
procedure RefillTank(x, y: Integer; Amount: Single);
procedure RefillAllTanks;

procedure SimFrame(dt: Single; Running: Boolean);
function CellSpeed(x, y: Integer): Single;
function SuctionRadius(x, y: Integer): Single;

function AddBucket(CenterX, TopY, W, H: Single): Integer;
function BucketAt(px, py: Single): Integer;
procedure ClampBucket(i: Integer);
procedure MoveBucket(i: Integer; dx, dy: Single);
procedure ResizeBucket(i: Integer; NewW, NewH: Single);
procedure EmptyBucket(i: Integer);
procedure DeleteBucket(i: Integer);
function BucketFill(i: Integer): Single;

function AddLabel(X, Y: Single; const Text: string): Integer;
procedure DeleteLabel(i: Integer);
function AddFrame(X, Y, W, H: Single; const Title: string): Integer;
procedure DeleteFrame(i: Integer);
function AddLink(X, Y: Single; const Caption: string; ToPopup: Boolean; Target: Integer): Integer;
procedure DeleteLink(i: Integer);

{ equipment }
function EquipHasMotor(Kind: Integer): Boolean;
{ motors, valves and heaters: the six states, the start sequence and Run / Stop }
function EquipActuated(Kind: Integer): Boolean;
function EquipIsValve(Kind: Integer): Boolean;
{ running: auto start or manual start }
function EquipRunning(i: Integer): Boolean;
{ the distinct sequence steps in use on the page, in order; returns their count }
function SeqStepList(out Steps: array of Byte): Integer;
function StepDelay(Step: Integer): Single;
{ the sequence box that runs the page (the first one), or -1 }
function MasterSequence: Integer;
{ ponds, pools and wells hold water (their Level, % of WaterCap) }
function EquipIsWater(Kind: Integer): Boolean;
function WaterCap(i: Integer): Single;
{ the pond / pool / well a pump draws from: the nearest one, or -1 }
function PumpSource(i: Integer): Integer;
{ a belt / roller conveyor's incline in degrees (RMin; + its right end higher) and the top of its deck }
function ConveyorTilt(i: Integer): Single;
procedure ConveyorDeck(i: Integer; out x1, y1, x2, y2: Single);
{ a free particle at px, py would be inside something solid }
function SolidAt(px, py: Single): Boolean;

type
  TEquipSizeHook = function(Kind: Integer; out W, H: Single): Boolean;

var
  EquipSizeHook: TEquipSizeHook = nil;   { a size of its own for new pieces of a kind (set by shapes) }

procedure EquipDefaultSize(Kind: Integer; out W, H: Single);
function AddEquip(Kind: Integer; X, Y: Single): Integer;
procedure DeleteEquip(i: Integer);
{ the linked grid cell of equipment i, or nil }
function EquipLinkCell(i: Integer): PCell;
{ the blow / suction / push-out / gate strength and the feed % of a part, 0 while it is halted }
function DevStr(c: PCell): Single;
function DevFeed(c: PCell): Single;
{ True while material or air moves through cell x,y }
function CellFlowing(x, y: Integer): Boolean;

procedure LoadDemo;

implementation

uses
  Math, SysUtils;

var
  ActiveIdx: array[0..GW * GH - 1] of Integer;
  NActive: Integer = 0;
  HashHead: array of Integer;
  HashNext: array of Integer;
  PrevX, PrevY: array of Single;

const
  HBIN = 4;
  HBW = CANVAS_W div HBIN + 2;
  HBH = CANVAS_H div HBIN + 2;

{ ---------------------------------------------------------------- helpers }

function fmin(a, b: Single): Single; inline;
begin
  if a < b then Result := a else Result := b;
end;

function fmax(a, b: Single): Single; inline;
begin
  if a > b then Result := a else Result := b;
end;

function fclamp(v, lo, hi: Single): Single; inline;
begin
  if v < lo then Result := lo
  else if v > hi then Result := hi
  else Result := v;
end;

function InGrid(x, y: Integer): Boolean;
begin
  Result := (x >= 0) and (y >= 0) and (x < GW) and (y < GH);
end;

{ tanks, hoppers and silos hold material and feed it into their pipes }
function IsStore(K: TCellKind): Boolean;
begin
  Result := K in [ckSource, ckHopper, ckSilo, ckVFeeder];
end;

function StoreTotal(const c: TCell): Single;
var
  m: TMat;
begin
  Result := 0;
  for m := mWater to mSand do
    Result := Result + c.Stock[m];
end;

function StoreCap(K: TCellKind): Single;
begin
  case K of
    ckHopper: Result := HOPPER_CAP;
    ckSilo: Result := SILO_CAP;
  else
    Result := 4 * STOCK_MAX;
  end;
end;

{ can store c take one more particle of material m }
function StoreAccepts(const c: TCell; m: TMat): Boolean;
begin
  if c.Kind = ckVFeeder then Exit(True);   { a virtual feeder takes anything back }
  if m = mAir then Exit(True);
  Result := (c.Stock[m] < STOCK_MAX) and (StoreTotal(c) < StoreCap(c.Kind));
end;

{ silo: a body 2 cells wide and 3 tall above its outlet cell, with a cone into it;
  hopper: a funnel 2 cells tall above its outlet cell }
function StoreShape(gx, gy: Integer; out x1, y1, x2, y2: Single): Boolean;
var
  cx, top: Single;
begin
  Result := True;
  cx := gx * CELL + HALF;
  top := gy * CELL;
  case Grid[gx, gy].Kind of
    ckSilo: begin x1 := cx - 22; x2 := cx + 22; y1 := top - 3 * CELL; y2 := top + HALF; end;
    ckHopper: begin x1 := cx - 30; x2 := cx + 30; y1 := top - 2 * CELL + 4; y2 := top + HALF; end;
  else
    begin x1 := 0; y1 := 0; x2 := 0; y2 := 0; Result := False; end;
  end;
end;

function HWOf(Dia: Integer): Single;
begin
  Result := 1.6 + Dia * 1.9;   { inner half width in pixels }
end;

function Opp(d: Integer): Integer;
begin
  Result := (d + 2) and 3;
end;

function Connected(x, y, d: Integer): Boolean;
var
  nx, ny: Integer;
begin
  Result := False;
  if not InGrid(x, y) then Exit;
  if Grid[x, y].Kind = ckEmpty then Exit;
  if (Grid[x, y].Conn and (1 shl d)) = 0 then Exit;
  nx := x + DXS[d];
  ny := y + DYS[d];
  if not InGrid(nx, ny) then Exit;
  if Grid[nx, ny].Kind = ckEmpty then Exit;
  Result := (Grid[nx, ny].Conn and (1 shl Opp(d))) <> 0;
end;

function ConnCount(x, y: Integer): Integer;
var
  d: Integer;
begin
  Result := 0;
  for d := 0 to 3 do
    if Connected(x, y, d) then Inc(Result);
end;

{ May air/material move from (x,y) into its neighbour in direction d? }
function PassDir(x, y, d: Integer): Boolean;
var
  a, b: PCell;
begin
  Result := False;
  if not Connected(x, y, d) then Exit;
  a := @Grid[x, y];
  b := @Grid[x + DXS[d], y + DYS[d]];
  if (a^.Kind = ckValve2) and not a^.Open then Exit;
  if (b^.Kind = ckValve2) and not b^.Open then Exit;
  if (a^.Kind = ckValve3) and (a^.Dir = d) then Exit;
  if (b^.Kind = ckValve3) and (b^.Dir = Opp(d)) then Exit;
  if (a^.Kind = ckValve4) and ((a^.Closed and (1 shl d)) <> 0) then Exit;
  if (b^.Kind = ckValve4) and ((b^.Closed and (1 shl Opp(d))) <> 0) then Exit;
  if (a^.Kind = ckCheck) and (a^.Dir <> d) then Exit;
  if (b^.Kind = ckCheck) and (b^.Dir <> d) then Exit;
  Result := True;
end;

function EdgeG(x, y, d: Integer): Single;
var
  a, b: PCell;
begin
  a := @Grid[x, y];
  b := @Grid[x + DXS[d], y + DYS[d]];
  Result := Sqr(Min(a^.Dia, b^.Dia) / 3);
  if a^.Kind = ckDrop then Result := Result * fmax(0.05, DevStr(a) / 100);
  if b^.Kind = ckDrop then Result := Result * fmax(0.05, DevStr(b) / 100);
end;

{ Pump head acting on the flow from (x,y) towards direction d }
function Boost(x, y, d: Integer): Single;
var
  a, b: PCell;
begin
  Result := 0;
  a := @Grid[x, y];
  b := @Grid[x + DXS[d], y + DYS[d]];
  case a^.Kind of
    ckBlower:
      if a^.Dir = d then Result := Result + DevStr(a) * 0.5
      else if a^.Dir = Opp(d) then Result := Result - DevStr(a) * 0.5;
    ckSuction:
      if a^.Mouth >= 0 then Result := Result + DevStr(a);
    ckNozzle:
      if a^.Mouth >= 0 then Result := Result - DevStr(a);
  end;
  case b^.Kind of
    ckBlower:
      if b^.Dir = d then Result := Result + DevStr(b) * 0.5
      else if b^.Dir = Opp(d) then Result := Result - DevStr(b) * 0.5;
    ckSuction:
      if b^.Mouth >= 0 then Result := Result - DevStr(b);
    ckNozzle:
      if b^.Mouth >= 0 then Result := Result + DevStr(b);
  end;
end;

{ ---------------------------------------------------------------- editing }

procedure ResetCell(x, y: Integer);
begin
  FillChar(Grid[x, y], SizeOf(TCell), 0);
  Grid[x, y].Kind := ckEmpty;
  Grid[x, y].Dia := 3;
  Grid[x, y].Mouth := -1;
  Grid[x, y].Open := True;
end;

procedure ClearParticles;
begin
  NPart := 0;
  NAir := 0;
  if Assigned(ClearHook4) then ClearHook4;
end;

procedure ClearFloor;
var
  i: Integer;
begin
  for i := 0 to NPart - 1 do
    if (not Parts[i].InPipe) and (Parts[i].Bucket < 0) then
      Parts[i].Life := -1;
end;

procedure ClearAll;
var
  x, y, i: Integer;
begin
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      ResetCell(x, y);
  for i := 0 to MAX_BUCKETS - 1 do
    Buckets[i].Active := False;
  for i := 0 to MAX_LABELS - 1 do
    Labels[i].Active := False;
  for i := 0 to MAX_FRAMES - 1 do
    Frames[i].Active := False;
  for i := 0 to MAX_LINKS - 1 do
    Links[i].Active := False;
  for i := 0 to MAX_EQUIP - 1 do
    Equips[i].Active := False;
  if Assigned(ClearHook) then ClearHook;
  if Assigned(ClearHook2) then ClearHook2;
  if Assigned(ClearHook3) then ClearHook3;
  ClearParticles;
end;

function AddLabel(X, Y: Single; const Text: string): Integer;
var
  i: Integer;
begin
  for i := 0 to MAX_LABELS - 1 do
    if not Labels[i].Active then
    begin
      Labels[i].Active := True;
      Labels[i].X := fclamp(X, 0, CANVAS_W - 16);
      Labels[i].Y := fclamp(Y, 0, CANVAS_H - 12);
      Labels[i].Text := Text;
      Labels[i].Kind := LBL_TEXT;
      Labels[i].Fmt := '';
      Labels[i].Color := 0;
      Labels[i].NoBox := False;
      Labels[i].Layer := CurLayer;
      Exit(i);
    end;
  Result := -1;
end;

procedure DeleteLabel(i: Integer);
begin
  if (i >= 0) and (i < MAX_LABELS) then Labels[i].Active := False;
end;

function AddFrame(X, Y, W, H: Single; const Title: string): Integer;
var
  i: Integer;
begin
  for i := 0 to MAX_FRAMES - 1 do
    if not Frames[i].Active then
    begin
      Frames[i].Active := True;
      Frames[i].W := fclamp(W, 2 * CELL, CANVAS_W);
      Frames[i].H := fclamp(H, 2 * CELL, CANVAS_H);
      Frames[i].X := fclamp(X, 0, CANVAS_W - Frames[i].W);
      Frames[i].Y := fclamp(Y, 0, CANVAS_H - Frames[i].H);
      Frames[i].Title := Title;
      Frames[i].Color := 0;
      Frames[i].Dashed := False;
      Frames[i].Fill := True;
      Frames[i].Carry := True;
      Frames[i].Layer := CurLayer;
      Exit(i);
    end;
  Result := -1;
end;

procedure DeleteFrame(i: Integer);
begin
  if (i >= 0) and (i < MAX_FRAMES) then Frames[i].Active := False;
end;

function AddLink(X, Y: Single; const Caption: string; ToPopup: Boolean; Target: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to MAX_LINKS - 1 do
    if not Links[i].Active then
    begin
      Links[i].Active := True;
      Links[i].X := fclamp(X, 0, CANVAS_W - 24);
      Links[i].Y := fclamp(Y, 0, CANVAS_H - 18);
      Links[i].Caption := Caption;
      Links[i].ToPopup := ToPopup;
      Links[i].Target := Target;
      Links[i].Color := 1;
      Links[i].Layer := CurLayer;
      Exit(i);
    end;
  Result := -1;
end;

procedure DeleteLink(i: Integer);
begin
  if (i >= 0) and (i < MAX_LINKS) then Links[i].Active := False;
end;

{ ---------------------------------------------------------------- equipment }

function EquipHasMotor(Kind: Integer): Boolean;
begin
  Result := Kind in [EQ_MOTOR, EQ_BLOWER, EQ_PADDLE, EQ_SCREW];
end;

function EquipActuated(Kind: Integer): Boolean;
begin
  Result := Kind in [EQ_MOTOR, EQ_BLOWER, EQ_PADDLE, EQ_SCREW, EQ_DIVERTER, EQ_SHUTTER, EQ_SLIDE, EQ_HEATER, EQ_IRHEATER,
    EQ_PUMP, EQ_CONVEYOR, EQ_BELT, EQ_HEATEX, EQ_COOLTOWER, EQ_CHILLER, EQ_DRYER, EQ_ITEMFEEDER, EQ_WORKER];
end;

function EquipIsValve(Kind: Integer): Boolean;
begin
  Result := Kind in [EQ_DIVERTER, EQ_SHUTTER, EQ_SLIDE];
end;

function EquipRunning(i: Integer): Boolean;
begin
  Result := Equips[i].State in [EQS_RUN, EQS_MSTART];
end;

function SeqStepList(out Steps: array of Byte): Integer;
var
  s, i: Integer;
  used: Boolean;
begin
  Result := 0;
  for s := 1 to MAX_SEQ_STEP do
  begin
    used := False;
    for i := 0 to MAX_EQUIP - 1 do
      if Equips[i].Active and EquipActuated(Equips[i].Kind) and (Equips[i].SeqStep = s) then used := True;
    if used and (Result <= High(Steps)) then
    begin
      Steps[Result] := s;
      Inc(Result);
    end;
  end;
end;

function StepDelay(Step: Integer): Single;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and EquipActuated(Equips[i].Kind) and (Equips[i].SeqStep = Step) then
      Result := fmax(Result, Equips[i].Delay);
end;

function EquipIsWater(Kind: Integer): Boolean;
begin
  Result := Kind in [EQ_POND, EQ_POOL, EQ_WELL];
end;

function WaterCap(i: Integer): Single;
begin
  { water units (particles) when full }
  if Equips[i].Kind = EQ_WELL then Result := 1500
  else Result := fmax(50, Equips[i].W * Equips[i].H / 16);
end;

function PumpSource(i: Integer): Integer;
var
  j: Integer;
  d, best, cx, cy: Single;
begin
  Result := -1;
  best := 360;
  cx := Equips[i].X + Equips[i].W / 2;
  cy := Equips[i].Y + Equips[i].H / 2;
  for j := 0 to MAX_EQUIP - 1 do
    if Equips[j].Active and EquipIsWater(Equips[j].Kind) then
    begin
      d := Sqrt(Sqr(Equips[j].X + Equips[j].W / 2 - cx) + Sqr(Equips[j].Y + Equips[j].H / 2 - cy));
      if d < best then
      begin
        best := d;
        Result := j;
      end;
    end;
end;

function MasterSequence: Integer;
var
  i: Integer;
begin
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and (Equips[i].Kind = EQ_SEQUENCE) then Exit(i);
  Result := -1;
end;

procedure EquipDefaultSize(Kind: Integer; out W, H: Single);
begin
  if Assigned(EquipSizeHook) and EquipSizeHook(Kind, W, H) then Exit;
  case Kind of
    EQ_MOTOR: begin W := 72; H := 36; end;
    EQ_BLOWER: begin W := 120; H := 110; end;
    EQ_PADDLE: begin W := 264; H := 44; end;
    EQ_SCREW: begin W := 336; H := 40; end;
    EQ_CYCLONE: begin W := 48; H := 96; end;
    EQ_SILO: begin W := 240; H := 192; end;
    EQ_STAND: begin W := 264; H := 72; end;
    EQ_LAMP: begin W := 16; H := 16; end;
    EQ_SEQUENCE: begin W := 296; H := 66; end;
    EQ_DIVERTER: begin W := 56; H := 72; end;
    EQ_SHUTTER: begin W := 72; H := 44; end;
    EQ_SLIDE: begin W := 64; H := 64; end;
    EQ_HEATER: begin W := 96; H := 48; end;
    EQ_IRHEATER: begin W := 120; H := 28; end;
    EQ_RAIN: begin W := 192; H := 56; end;
    EQ_FIRE: begin W := 72; H := 80; end;
    EQ_POND: begin W := 264; H := 80; end;
    EQ_POOL: begin W := 216; H := 96; end;
    EQ_WELL: begin W := 96; H := 192; end;
    EQ_PUMP: begin W := 104; H := 56; end;
    EQ_PANEL: begin W := 360; H := 432; end;
    EQ_CONVEYOR: begin W := 288; H := 48; end;
    EQ_BELT: begin W := 312; H := 48; end;
    EQ_GAUGE: begin W := 120; H := 120; end;
    EQ_DIGITAL: begin W := 156; H := 56; end;
    EQ_CYLINDER: begin W := 200; H := 40; end;
    EQ_COMPRESSOR: begin W := 168; H := 100; end;
    EQ_HPU: begin W := 168; H := 112; end;
    EQ_RECEIVER: begin W := 64; H := 144; end;
    EQ_CONTROLLER: begin W := 168; H := 112; end;
    EQ_HEATEX: begin W := 168; H := 64; end;
    EQ_COOLTOWER: begin W := 144; H := 168; end;
    EQ_CHILLER: begin W := 216; H := 120; end;
    EQ_TREND: begin W := 360; H := 200; end;
    EQ_TIMELINE: begin W := 480; H := 130; end;
    EQ_DRYER: begin W := 600; H := 96; end;
    EQ_ITEMFEEDER: begin W := 64; H := 104; end;
    EQ_WORKER: begin W := 56; H := 150; end;
    EQ_VAN: begin W := 312; H := 250; end;
    EQ_RACK: begin W := 110; H := 340; end;
  else
    begin W := 232; H := 136; end;
  end;
end;

function AddEquip(Kind: Integer; X, Y: Single): Integer;
var
  i, k, n: Integer;
  w, h: Single;
begin
  Result := -1;
  if (Kind < 0) or (Kind >= EQ_KINDS) then Exit;
  for i := 0 to MAX_EQUIP - 1 do
    if not Equips[i].Active then
    begin
      EquipDefaultSize(Kind, w, h);
      n := 1;
      for k := 0 to MAX_EQUIP - 1 do
        if Equips[k].Active and (Equips[k].Kind = Kind) then Inc(n);
      FillChar(Equips[i], SizeOf(TEquipObj), 0);
      Equips[i].Active := True;
      Equips[i].Kind := Kind;
      Equips[i].W := w;
      Equips[i].H := h;
      Equips[i].X := fclamp(X, 0, CANVAS_W - w);
      Equips[i].Y := fclamp(Y, 0, CANVAS_H - h);
      if Kind in [EQ_LEGEND, EQ_SEQUENCE] then Equips[i].Name := EquipNames[Kind]
      else if Kind in [EQ_DIVERTER, EQ_SHUTTER, EQ_SLIDE] then
        Equips[i].Name := Copy(EquipNames[Kind], 1, Pos(' ', EquipNames[Kind]) - 1) + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_IRHEATER then Equips[i].Name := 'IRHeater' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_PANEL then Equips[i].Name := 'Panel' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_CONVEYOR then Equips[i].Name := 'Conveyor' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_BELT then Equips[i].Name := 'Belt' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_GAUGE then Equips[i].Name := 'Gauge' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_DIGITAL then Equips[i].Name := 'Display' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_CYLINDER then Equips[i].Name := 'Cyl' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_COMPRESSOR then Equips[i].Name := 'Comp' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_HPU then Equips[i].Name := 'HPU' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_RECEIVER then Equips[i].Name := 'Tank' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_CONTROLLER then Equips[i].Name := 'Faceplate' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_HEATEX then Equips[i].Name := 'HX' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_COOLTOWER then Equips[i].Name := 'Tower' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_CHILLER then Equips[i].Name := 'Chiller' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_TREND then Equips[i].Name := 'Trend' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_TIMELINE then Equips[i].Name := 'Timeline' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_DRYER then Equips[i].Name := 'Dryer' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_ITEMFEEDER then Equips[i].Name := 'Items' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_WORKER then Equips[i].Name := 'Worker' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_VAN then Equips[i].Name := 'Van' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if Kind = EQ_RACK then Equips[i].Name := 'Rack' + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10)
      else if n < 10 then Equips[i].Name := EquipNames[Kind] + '0' + Chr(Ord('0') + n)
      else Equips[i].Name := EquipNames[Kind] + Chr(Ord('0') + n div 10) + Chr(Ord('0') + n mod 10);
      if Kind = EQ_SILO then Equips[i].Name := 'Silo' + Copy(Equips[i].Name, 9, 2);
      if Kind = EQ_STAND then Equips[i].Name := '';
      Equips[i].State := EQS_STOP;
      Equips[i].LinkX := -1;
      Equips[i].LinkY := -1;
      Equips[i].Level := 50;
      if Kind in [EQ_HEATER, EQ_IRHEATER, EQ_FIRE] then Equips[i].Level := 100;
      if Kind in [EQ_PUMP, EQ_CONVEYOR, EQ_BELT] then Equips[i].Level := 60;   { flow / speed % }
      if Kind = EQ_WELL then Equips[i].Level := 80;
      Equips[i].RMax := 100;
      Equips[i].DivA := -1;
      Equips[i].DivB := -1;
      Equips[i].Delay := 2;
      if Kind = EQ_HEATEX then
      begin
        Equips[i].State := EQS_RUN;    { its hot side flows }
        Equips[i].Level := 60;         { hot flow % }
        Equips[i].RMax := 120;         { tube inlet C }
        Equips[i].RMin := 20;          { shell inlet C }
      end;
      if Kind = EQ_COOLTOWER then
      begin
        Equips[i].Level := 80;         { fan % }
        Equips[i].RMax := 38;          { water in C }
        Equips[i].RMin := 21;          { wet bulb C }
      end;
      if Kind = EQ_TIMELINE then Equips[i].Delay := 30;   { its length, s }
      if Kind = EQ_ITEMFEEDER then Equips[i].RMin := 2;
      if Kind = EQ_WORKER then
      begin
        Equips[i].RMin := 3;     { a loader: a piece every 3 s; Mode 0 loader / 1 picker, Level what it handles }
        Equips[i].Level := 2;    { boxes }
        Equips[i].State := EQS_RUN;
      end;  { a piece every 2 s; Mode: what it feeds, RMax: its stock (0 no end) }
      if Kind = EQ_TREND then
      begin
        Equips[i].Delay := 60;         { its time window, s }
        Equips[i].RMax := 0;           { RMin = RMax: the value range follows the values }
      end;
      if Kind = EQ_CHILLER then
      begin
        Equips[i].Level := 100;        { capacity % }
        Equips[i].RMax := 7;           { chilled water set point C }
        Equips[i].RMin := 12;          { return water C }
      end;
      if Kind = EQ_FIRE then
      begin
        Equips[i].State := EQS_RUN;    { a new fire burns }
        Equips[i].Heat := 100;
      end;
      Equips[i].Layer := CurLayer;
      Exit(i);
    end;
end;

procedure DeleteEquip(i: Integer);
begin
  if (i >= 0) and (i < MAX_EQUIP) then Equips[i].Active := False;
end;

function EquipLinkCell(i: Integer): PCell;
begin
  Result := nil;
  if (i < 0) or (i >= MAX_EQUIP) or not Equips[i].Active then Exit;
  if InGrid(Equips[i].LinkX, Equips[i].LinkY) and (Grid[Equips[i].LinkX, Equips[i].LinkY].Kind <> ckEmpty) then
    Result := @Grid[Equips[i].LinkX, Equips[i].LinkY];
end;

function DevStr(c: PCell): Single;
begin
  if c^.Halted then Result := 0 else Result := c^.Strength;
end;

function DevFeed(c: PCell): Single;
begin
  if c^.Halted then Result := 0 else Result := c^.Feed;
end;

function CellFlowing(x, y: Integer): Boolean;
var
  d: Integer;
begin
  Result := False;
  if not InGrid(x, y) or (Grid[x, y].Kind = ckEmpty) then Exit;
  for d := 0 to 3 do
    if Abs(Grid[x, y].F[d]) > 0.02 then Exit(True);
end;

{ the start / stop sequence of the page, run by sequence box q }
procedure RunSequence(q: Integer; dt: Single);
var
  steps: array[0..MAX_SEQ_STEP - 1] of Byte;
  n, j, st: Integer;
  req: Boolean;
  d: Single;
  S: ^TEquipObj;

  function Member(k: Integer): Boolean;
  begin
    Result := Equips[k].Active and EquipActuated(Equips[k].Kind) and (Equips[k].SeqStep > 0);
  end;

begin
  S := @Equips[q];
  n := SeqStepList(steps);
  if S^.SeqPos > n then S^.SeqPos := n;
  if S^.SeqPos < 0 then S^.SeqPos := 0;
  { the external request: its Run state, or flow through the linked part }
  req := (S^.State = EQS_RUN) or ((EquipLinkCell(q) <> nil) and CellFlowing(S^.LinkX, S^.LinkY));
  if req then S^.ReqT := S^.ReqT + dt else S^.ReqT := 0;
  if req <> S^.LastReq then
  begin
    S^.SeqT := 0;
    S^.LastReq := req;
  end;
  case S^.Mode of
    SEQ_ESTOP:
      begin
        { everything in the sequence stops at once }
        for j := 0 to MAX_EQUIP - 1 do
          if Member(j) then
            if Equips[j].State = EQS_RUN then Equips[j].State := EQS_STOP
            else if Equips[j].State = EQS_MSTART then Equips[j].State := EQS_MSTOP;
        S^.SeqPos := 0;
        S^.SeqT := 0;
      end;
    SEQ_AUTO:
      if req and (S^.SeqPos < n) then
      begin
        { auto start: the next step after its delay }
        st := steps[S^.SeqPos];
        d := StepDelay(st);
        S^.SeqT := S^.SeqT + dt;
        for j := 0 to MAX_EQUIP - 1 do
          if Member(j) and (Equips[j].SeqStep = st) and (Equips[j].State = EQS_STOP) then
            Equips[j].Wait := fmax(0.01, d - S^.SeqT);
        if S^.SeqT >= d then
        begin
          for j := 0 to MAX_EQUIP - 1 do
            if Member(j) and (Equips[j].SeqStep = st) and (Equips[j].State = EQS_STOP) then
            begin
              Equips[j].State := EQS_RUN;
              Equips[j].RunTime := 0;
              Equips[j].Wait := 0;
            end;
          Inc(S^.SeqPos);
          S^.SeqT := 0;
        end;
      end
      else if (not req) and (S^.SeqPos > 0) then
      begin
        { auto stop: the steps in reverse order }
        st := steps[S^.SeqPos - 1];
        d := StepDelay(st);
        S^.SeqT := S^.SeqT + dt;
        for j := 0 to MAX_EQUIP - 1 do
          if Member(j) and (Equips[j].SeqStep = st) and (Equips[j].State = EQS_RUN) then
            Equips[j].Wait := -fmax(0.01, d - S^.SeqT);
        if S^.SeqT >= d then
        begin
          for j := 0 to MAX_EQUIP - 1 do
            if Member(j) and (Equips[j].SeqStep = st) and (Equips[j].State = EQS_RUN) then
            begin
              Equips[j].State := EQS_STOP;
              Equips[j].Wait := 0;
            end;
          Dec(S^.SeqPos);
          S^.SeqT := 0;
        end;
      end
      else
        S^.SeqT := 0;
  else
    S^.SeqT := 0;   { manual: the operator starts and stops by hand }
  end;
end;

{ before each frame: the sequence, linked parts follow their equipment, timers and animation }
procedure ApplyEquipment(dt: Single; Running: Boolean);
var
  x, y, i, q: Integer;
  c: PCell;
  E: ^TEquipObj;
  run: Boolean;
begin
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      Grid[x, y].Halted := False;
  if Running then
  begin
    for i := 0 to MAX_EQUIP - 1 do Equips[i].Wait := 0;
    q := MasterSequence;
    if q >= 0 then RunSequence(q, dt);
  end;
  for i := 0 to MAX_EQUIP - 1 do
  begin
    E := @Equips[i];
    if not E^.Active then Continue;
    c := EquipLinkCell(i);
    run := EquipRunning(i);
    case E^.Kind of
      EQ_MOTOR, EQ_BLOWER, EQ_PADDLE, EQ_SCREW, EQ_PUMP, EQ_DRYER:
        if (c <> nil) and not run then c^.Halted := True;
      EQ_SHUTTER, EQ_SLIDE:
        if c <> nil then
        begin
          if c^.Kind = ckValve2 then c^.Open := run
          else if not run then c^.Halted := True;   { a shut gate stops a feeder, hopper, silo or outlet }
        end;
      EQ_DIVERTER:
        if c <> nil then
        begin
          if c^.Kind = ckValve3 then
          begin
            if run then c^.Dir := E^.DivA else c^.Dir := E^.DivB;
          end
          else if c^.Kind = ckValve2 then c^.Open := run
          else if not run then c^.Halted := True;
        end;
      EQ_LAMP:
        if (c <> nil) and not (E^.State in [EQS_FAULT, EQS_DISABLE]) then
        begin
          if CellFlowing(E^.LinkX, E^.LinkY) then E^.State := EQS_RUN
          else E^.State := EQS_STOP;
        end;
      EQ_FIRE:
        if not run then E^.Heat := 0;
    end;
    if run and (EquipActuated(E^.Kind) or (E^.Kind in [EQ_RAIN, EQ_FIRE])) then
    begin
      if Running then
      begin
        E^.RunTime := E^.RunTime + dt;
        E^.Phase := E^.Phase + dt * 6;
        if E^.Phase > 1000 then E^.Phase := E^.Phase - 1000;
      end;
    end
    else if E^.Kind <> EQ_SEQUENCE then
      E^.RunTime := 0;
  end;
end;

function ConveyorTilt(i: Integer): Single;
begin
  Result := fclamp(Equips[i].RMin, -35, 35);
  if Abs(Result) < 0.5 then Result := 0;
end;

procedure ConveyorDeck(i: Integer; out x1, y1, x2, y2: Single);
var
  t, low: Single;
begin
  x1 := Equips[i].X;
  x2 := Equips[i].X + Equips[i].W;
  t := Tan(ConveyorTilt(i) * Pi / 180);
  if t = 0 then
  begin
    y1 := Equips[i].Y + Equips[i].H * 0.2;
    y2 := y1;
    Exit;
  end;
  low := Equips[i].Y + Equips[i].H - 22;
  if t > 0 then
  begin
    y1 := low;
    y2 := low - Equips[i].W * t;
  end
  else
  begin
    y2 := low;
    y1 := low + Equips[i].W * t;
  end;
end;

procedure MakePipe(x, y, Dia: Integer);
begin
  ResetCell(x, y);
  Grid[x, y].Kind := ckPipe;
  Grid[x, y].Layer := CurLayer;
  Grid[x, y].Dia := EnsureRange(Dia, 1, MAX_DIA);
end;

procedure ConnectCells(x1, y1, x2, y2: Integer);
var
  d: Integer;
begin
  if not (InGrid(x1, y1) and InGrid(x2, y2)) then Exit;
  if (Grid[x1, y1].Kind = ckEmpty) or (Grid[x2, y2].Kind = ckEmpty) then Exit;
  for d := 0 to 3 do
    if (x1 + DXS[d] = x2) and (y1 + DYS[d] = y2) then
    begin
      Grid[x1, y1].Conn := Grid[x1, y1].Conn or (1 shl d);
      Grid[x2, y2].Conn := Grid[x2, y2].Conn or (1 shl Opp(d));
      Exit;
    end;
end;

procedure EraseCell(x, y: Integer);
var
  d, i, nx, ny: Integer;
begin
  if not InGrid(x, y) then Exit;
  if Grid[x, y].Kind = ckEmpty then Exit;
  { material inside the removed piece spills out }
  for i := 0 to NPart - 1 do
    if Parts[i].InPipe and (Parts[i].CX = x) and (Parts[i].CY = y) then
    begin
      Parts[i].InPipe := False;
      Parts[i].Bucket := -1;
    end;
  for d := 0 to 3 do
  begin
    nx := x + DXS[d];
    ny := y + DYS[d];
    if InGrid(nx, ny) then
      Grid[nx, ny].Conn := Grid[nx, ny].Conn and not (1 shl Opp(d));
  end;
  ResetCell(x, y);
end;

procedure SetKind(x, y: Integer; K: TCellKind);
var
  c: PCell;
  d, n, one: Integer;
begin
  if not InGrid(x, y) then Exit;
  c := @Grid[x, y];
  if c^.Kind = ckEmpty then
  begin
    ResetCell(x, y);
    c^.Dia := 3;
  end;
  c^.Kind := K;
  c^.Open := True;
  n := 0;
  one := -1;
  for d := 0 to 3 do
    if Connected(x, y, d) then
    begin
      Inc(n);
      one := d;
    end;
  case K of
    ckVFeeder:
      begin
        { a mix ratio, never used up; what it emits lives Strength seconds }
        c^.Stock[mWater] := 1000;
        c^.Stock[mOil] := 0;
        c^.Stock[mFluff] := 0;
        c^.Stock[mSand] := 1000;
        c^.AirPct := 20;
        c^.Feed := 60;
        c^.Strength := 10;
      end;
    ckSource:
      begin
        c^.Stock[mWater] := 1000;
        c^.Stock[mOil] := 400;
        c^.Stock[mFluff] := 300;
        c^.Stock[mSand] := 600;
        c^.AirPct := 20;
        c^.Feed := 60;
      end;
    ckBlower, ckCheck:
      begin
        if Connected(x, y, 0) and Connected(x, y, 2) then c^.Dir := 0
        else if Connected(x, y, 1) and Connected(x, y, 3) then c^.Dir := 3
        else if one >= 0 then c^.Dir := one
        else c^.Dir := 0;
        if K = ckBlower then c^.Strength := 50;
      end;
    ckSuction:
      begin
        if n = 1 then c^.Dir := Opp(one) else c^.Dir := 1;
        c^.Strength := 60;
      end;
    ckNozzle:
      begin
        if n = 1 then c^.Dir := Opp(one) else c^.Dir := 0;
        c^.Strength := 50;
      end;
    ckDrop:
      begin
        if n = 1 then c^.Dir := Opp(one) else c^.Dir := 1;
        c^.Strength := 100;
      end;
    ckValve3:
      c^.Dir := -1;
    ckValve4:
      c^.Closed := 0;
    ckHopper, ckSilo:
      begin
        { they start empty and are filled by what falls or flows in }
        c^.Stock[mWater] := 0;
        c^.Stock[mOil] := 0;
        c^.Stock[mFluff] := 0;
        c^.Stock[mSand] := 0;
        c^.AirPct := 0;
        if K = ckHopper then c^.Feed := 100 else c^.Feed := 40;
      end;
  end;
end;

procedure RotateCell(x, y: Integer);
var
  c: PCell;
  i, d: Integer;
begin
  if not InGrid(x, y) then Exit;
  c := @Grid[x, y];
  case c^.Kind of
    ckBlower, ckCheck:
      begin
        d := c^.Dir;
        for i := 1 to 4 do
        begin
          d := (d + 1) and 3;
          if Connected(x, y, d) then Break;
        end;
        c^.Dir := d;
      end;
    ckSuction, ckNozzle, ckDrop:
      begin
        d := c^.Dir;
        for i := 1 to 4 do
        begin
          d := (d + 1) and 3;
          if not Connected(x, y, d) then Break;
        end;
        c^.Dir := d;
      end;
    ckValve2:
      c^.Open := not c^.Open;
    ckValve3:
      begin
        { cycle: all open -> close each connected branch in turn -> all open }
        d := c^.Dir;
        repeat
          Inc(d);
          if d > 3 then
          begin
            d := -1;
            Break;
          end;
        until Connected(x, y, d);
        c^.Dir := d;
      end;
    ckValve4:
      { all open -> shut E, S, W, N in turn -> straight E-W -> straight N-S -> all open }
      case c^.Closed of
        0: c^.Closed := 1;
        1: c^.Closed := 2;
        2: c^.Closed := 4;
        4: c^.Closed := 8;
        8: c^.Closed := 2 or 8;
        2 or 8: c^.Closed := 1 or 4;
      else
        c^.Closed := 0;
      end;
  end;
end;

procedure RefillTank(x, y: Integer; Amount: Single);
var
  m: TMat;
begin
  if Grid[x, y].Kind <> ckSource then Exit;
  for m := mWater to mSand do
    if Grid[x, y].Stock[m] > 0 then
      Grid[x, y].Stock[m] := fmin(STOCK_MAX, Grid[x, y].Stock[m] + Amount);
end;

procedure RefillAllTanks;
var
  x, y: Integer;
begin
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      RefillTank(x, y, STOCK_MAX);
end;

{ ---------------------------------------------------------------- network }

procedure UpdateTopology;
var
  x, y, d, n, i: Integer;
  c: PCell;
begin
  NActive := 0;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @Grid[x, y];
      if c^.Kind = ckEmpty then Continue;
      n := 0;
      for d := 0 to 3 do
      begin
        c^.ECon[d] := Connected(x, y, d);
        if c^.ECon[d] then Inc(n);
      end;
      c^.Mouth := -1;
      case c^.Kind of
        ckPipe:
          if n = 1 then
            for d := 0 to 3 do
              if c^.ECon[d] then c^.Mouth := Opp(d);
        ckSuction, ckNozzle:
          if (c^.Dir >= 0) and not c^.ECon[c^.Dir] then c^.Mouth := c^.Dir;
        ckDrop:
          if (c^.Dir >= 0) and not c^.ECon[c^.Dir] and (DevStr(c) > 0.5) then
            c^.Mouth := c^.Dir;
      end;
      c^.Fixed := IsStore(c^.Kind) or (c^.Mouth >= 0);
      ActiveIdx[NActive] := x + y * GW;
      Inc(NActive);
    end;

  for i := 0 to NActive - 1 do
  begin
    x := ActiveIdx[i] mod GW;
    y := ActiveIdx[i] div GW;
    c := @Grid[x, y];
    for d := 0 to 3 do
      if c^.ECon[d] then
      begin
        c^.EG[d] := EdgeG(x, y, d);
        c^.EH[d] := Boost(x, y, d);
        c^.EPf[d] := PassDir(x, y, d);
        c^.EPb[d] := PassDir(x + DXS[d], y + DYS[d], Opp(d));
      end
      else
      begin
        c^.EG[d] := 0;
        c^.EH[d] := 0;
        c^.EPf[d] := False;
        c^.EPb[d] := False;
      end;
  end;
end;

function EdgeFlow(c: PCell; d: Integer; Pn: Single): Single;
var
  drive: Single;
begin
  drive := c^.P - Pn + c^.EH[d];
  if drive >= 0 then
  begin
    if not c^.EPf[d] then Exit(0);
  end
  else if not c^.EPb[d] then Exit(0);
  Result := c^.EG[d] * drive;
end;

procedure SolvePressure(Iters: Integer);
var
  it, i, x, y, d: Integer;
  c, nb: PCell;
  sg, s, g, drive, np: Single;
begin
  for it := 1 to Iters do
    for i := 0 to NActive - 1 do
    begin
      x := ActiveIdx[i] mod GW;
      y := ActiveIdx[i] div GW;
      c := @Grid[x, y];
      if c^.Fixed then
      begin
        c^.P := 0;
        Continue;
      end;
      sg := 0;
      s := 0;
      for d := 0 to 3 do
        if c^.ECon[d] then
        begin
          nb := @Grid[x + DXS[d], y + DYS[d]];
          g := c^.EG[d];
          drive := c^.P - nb^.P + c^.EH[d];
          if drive >= 0 then
          begin
            if not c^.EPf[d] then g := 0;
          end
          else if not c^.EPb[d] then g := 0;
          sg := sg + g;
          s := s + g * (nb^.P - c^.EH[d]);
        end;
      if sg > 1e-6 then
      begin
        np := s / sg;
        c^.P := c^.P + 1.6 * (np - c^.P);
      end
      else
        c^.P := c^.P * 0.9;
      c^.P := fclamp(c^.P, -400, 400);
    end;
end;

procedure ComputeFluxes;
var
  i, x, y, d: Integer;
  c, nb: PCell;
  q, sum: Single;
begin
  for i := 0 to NActive - 1 do
  begin
    c := @Grid[ActiveIdx[i] mod GW, ActiveIdx[i] div GW];
    for d := 0 to 3 do
      c^.F[d] := 0;
  end;
  for i := 0 to NActive - 1 do
  begin
    x := ActiveIdx[i] mod GW;
    y := ActiveIdx[i] div GW;
    c := @Grid[x, y];
    for d := 0 to 1 do
      if c^.ECon[d] then
      begin
        nb := @Grid[x + DXS[d], y + DYS[d]];
        q := EdgeFlow(c, d, nb^.P);
        c^.F[d] := q;
        nb^.F[Opp(d)] := -q;
      end;
  end;
  for i := 0 to NActive - 1 do
  begin
    c := @Grid[ActiveIdx[i] mod GW, ActiveIdx[i] div GW];
    if c^.Mouth >= 0 then
    begin
      sum := 0;
      for d := 0 to 3 do
        if d <> c^.Mouth then sum := sum + c^.F[d];
      c^.F[c^.Mouth] := -sum;
    end;
  end;
end;

function CellSpeed(x, y: Integer): Single;
var
  d: Integer;
  s: Single;
begin
  s := 0;
  for d := 0 to 3 do
    s := s + Abs(Grid[x, y].F[d]);
  Result := s * 0.5 * VK * 3 / Grid[x, y].Dia;
end;

function SuctionRadius(x, y: Integer): Single;
begin
  Result := 20 + DevStr(@Grid[x, y]) * 1.3;
end;

procedure BuildDeviceLists;
var
  i, x, y, m: Integer;
  c: PCell;
begin
  NIntake := 0;
  NJet := 0;
  NCatch := 0;
  NBody := 0;
  for i := 0 to NActive - 1 do
  begin
    x := ActiveIdx[i] mod GW;
    y := ActiveIdx[i] div GW;
    c := @Grid[x, y];
    if (c^.Kind in [ckHopper, ckSilo]) and (NCatch <= High(Catches)) then
    begin
      Catches[NCatch].GX := x;
      Catches[NCatch].GY := y;
      if c^.Kind = ckHopper then
      begin
        { the whole funnel catches }
        Catches[NCatch].X1 := x * CELL + HALF - 30;
        Catches[NCatch].X2 := x * CELL + HALF + 30;
        Catches[NCatch].Y1 := y * CELL - 2 * CELL + 4;
        Catches[NCatch].Y2 := y * CELL + HALF - 4;
      end
      else
      begin
        { the silo's top opening catches; its body is solid }
        Catches[NCatch].X1 := x * CELL + HALF - 22;
        Catches[NCatch].X2 := x * CELL + HALF + 22;
        Catches[NCatch].Y1 := y * CELL - 3 * CELL - 14;
        Catches[NCatch].Y2 := y * CELL - 3 * CELL + 6;
        Bodies[NBody].X1 := x * CELL + HALF - 23;
        Bodies[NBody].X2 := x * CELL + HALF + 23;
        Bodies[NBody].Y1 := y * CELL - 3 * CELL + 6;
        Bodies[NBody].Y2 := y * CELL + HALF;
        Inc(NBody);
      end;
      Inc(NCatch);
    end;
    m := c^.Mouth;
    if m < 0 then Continue;
    if (c^.F[m] < -0.02) and (NIntake <= High(Intakes)) then
    begin
      Intakes[NIntake].MX := x * CELL + HALF + DXS[m] * HALF;
      Intakes[NIntake].MY := y * CELL + HALF + DYS[m] * HALF;
      Intakes[NIntake].CapR := HWOf(c^.Dia) + 2.5;
      Intakes[NIntake].CX := x;
      Intakes[NIntake].CY := y;
      Intakes[NIntake].D := m;
      Intakes[NIntake].Suction := c^.Kind = ckSuction;
      if c^.Kind = ckSuction then
      begin
        Intakes[NIntake].R := SuctionRadius(x, y);
        Intakes[NIntake].Str := DevStr(c);
      end
      else
      begin
        Intakes[NIntake].R := 16;
        Intakes[NIntake].Str := fmin(40, -c^.F[m] * 15);
      end;
      Inc(NIntake);
    end
    else if (c^.Kind = ckNozzle) and (c^.F[m] > 0.02) and (NJet <= High(Jets)) then
    begin
      Jets[NJet].MX := x * CELL + HALF + DXS[m] * HALF;
      Jets[NJet].MY := y * CELL + HALF + DYS[m] * HALF;
      Jets[NJet].L := 40 + DevStr(c) * 2.5;
      Jets[NJet].Str := DevStr(c);
      Jets[NJet].D := m;
      Inc(NJet);
    end;
  end;
  { conveyor decks are solid: material lands on them and rides along; an inclined one is a sloped line }
  NSlope := 0;
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and (Equips[i].Kind in [EQ_CONVEYOR, EQ_BELT]) and (ConveyorTilt(i) <> 0) and (NSlope <= High(Slopes)) then
    begin
      ConveyorDeck(i, Slopes[NSlope].X1, Slopes[NSlope].Y1, Slopes[NSlope].X2, Slopes[NSlope].Y2);
      Inc(NSlope);
    end;
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and (Equips[i].Kind in [EQ_CONVEYOR, EQ_BELT]) and (ConveyorTilt(i) = 0) and (NBody <= High(Bodies)) then
    begin
      Bodies[NBody].X1 := Equips[i].X;
      Bodies[NBody].X2 := Equips[i].X + Equips[i].W;
      Bodies[NBody].Y1 := Equips[i].Y + Equips[i].H * 0.2;
      Bodies[NBody].Y2 := Equips[i].Y + Equips[i].H * 0.5;
      Inc(NBody);
    end;
end;

{ ---------------------------------------------------------------- pipe geometry }

{ Clamp a cell-local point into the pipe shape grown by Grow pixels.
  Returns True when the point was already inside. }
function ClampShape(x, y: Integer; var lx, ly: Single; Grow: Single): Boolean;
var
  c: PCell;
  hw, w1, a, b, ac, bc, w, px, py, bd, dd, bx, by: Single;
  d: Integer;
begin
  c := @Grid[x, y];
  hw := fmax(0.3, HWOf(c^.Dia) + Grow);
  px := fclamp(lx, -hw, hw);
  py := fclamp(ly, -hw, hw);
  bd := Sqr(px - lx) + Sqr(py - ly);
  if bd = 0 then Exit(True);
  bx := px;
  by := py;
  for d := 0 to 3 do
  begin
    if d = c^.Mouth then
      w1 := hw
    else if c^.ECon[d] then
      w1 := fmax(0.3, (HWOf(c^.Dia) + HWOf(Grid[x + DXS[d], y + DYS[d]].Dia)) * 0.5 + Grow)
    else
      Continue;
    a := lx * DXS[d] + ly * DYS[d];
    b := -lx * DYS[d] + ly * DXS[d];
    ac := fmax(a, 0);
    w := hw + (w1 - hw) * fmin(ac, HALF) / HALF;
    bc := fclamp(b, -w, w);
    px := ac * DXS[d] - bc * DYS[d];
    py := ac * DYS[d] + bc * DXS[d];
    dd := Sqr(px - lx) + Sqr(py - ly);
    if dd = 0 then Exit(True);
    if dd < bd then
    begin
      bd := dd;
      bx := px;
      by := py;
    end;
  end;
  lx := bx;
  ly := by;
  Result := False;
end;

function ChooseExit(x, y: Integer): Integer;
var
  d: Integer;
  tot, r: Single;
  w: array[0..3] of Single;
  c: PCell;
begin
  c := @Grid[x, y];
  tot := 0;
  for d := 0 to 3 do
  begin
    w[d] := 0;
    if ((d = c^.Mouth) or c^.EPf[d]) and (c^.F[d] > 0.01) then
      w[d] := c^.F[d];
    tot := tot + w[d];
  end;
  Result := -1;
  if tot <= 0 then Exit;
  r := Random * tot;
  for d := 0 to 3 do
    if w[d] > 0 then
    begin
      Result := d;
      r := r - w[d];
      if r <= 0 then Exit;
    end;
end;

procedure AirVel(c: PCell; gx, gy, ExitDir: Integer; lx, ly: Single; out ax, ay: Single);
var
  hw, f, a, dEff, dEnd: Single;
  d: Integer;
begin
  ax := 0;
  ay := 0;
  hw := HWOf(c^.Dia);
  if (Abs(lx) <= hw) and (Abs(ly) <= hw) then
  begin
    d := ExitDir;
    if d < 0 then Exit;
    f := fmax(0, c^.F[d]) * VK * 3 / c^.Dia;
    ax := DXS[d] * f;
    ay := DYS[d] * f;
    { steer towards the centre line of the outgoing arm }
    if DXS[d] <> 0 then ay := ay - ly * 8 else ax := ax - lx * 8;
  end
  else
  begin
    if Abs(lx) > Abs(ly) then
    begin
      if lx > 0 then d := 0 else d := 2;
      a := Abs(lx);
    end
    else
    begin
      if ly > 0 then d := 1 else d := 3;
      a := Abs(ly);
    end;
    if c^.ECon[d] then
      dEnd := (c^.Dia + Grid[gx + DXS[d], gy + DYS[d]].Dia) * 0.5
    else
      dEnd := c^.Dia;
    dEff := c^.Dia + (dEnd - c^.Dia) * fmin(a, HALF) / HALF;
    f := c^.F[d] * VK * 3 / dEff;
    ax := DXS[d] * f;
    ay := DYS[d] * f;
  end;
end;

{ ---------------------------------------------------------------- buckets }

function BucketInterior(px, py: Single): Integer;
var
  i: Integer;
begin
  for i := 0 to MAX_BUCKETS - 1 do
    if Buckets[i].Active and (px >= Buckets[i].X) and (px <= Buckets[i].X + Buckets[i].W) and
      (py >= Buckets[i].Y) and (py <= Buckets[i].Y + Buckets[i].H) then
      Exit(i);
  Result := -1;
end;

procedure WallRect(i, k: Integer; out x1, y1, x2, y2: Single);
begin
  with Buckets[i] do
    case k of
      0: begin x1 := X - WALL_T - PRAD; x2 := X + PRAD; y1 := Y - PRAD; y2 := Y + H + WALL_T + PRAD; end;
      1: begin x1 := X + W - PRAD; x2 := X + W + WALL_T + PRAD; y1 := Y - PRAD; y2 := Y + H + WALL_T + PRAD; end;
    else
      begin x1 := X - WALL_T - PRAD; x2 := X + W + WALL_T + PRAD; y1 := Y + H - PRAD; y2 := Y + H + WALL_T + PRAD; end;
    end;
end;

function InBucketWall(px, py: Single; out bi, bk: Integer): Boolean;
var
  i, k: Integer;
  x1, y1, x2, y2: Single;
begin
  for i := 0 to MAX_BUCKETS - 1 do
    if Buckets[i].Active then
      for k := 0 to 2 do
      begin
        WallRect(i, k, x1, y1, x2, y2);
        if (px > x1) and (px < x2) and (py > y1) and (py < y2) then
        begin
          bi := i;
          bk := k;
          Exit(True);
        end;
      end;
  bi := -1;
  bk := -1;
  Result := False;
end;

function GridSolid(px, py: Single): Boolean;
var
  ix, iy: Integer;
  lx, ly: Single;
begin
  Result := False;
  if (py < 0) or (px < 0) then Exit;
  ix := Trunc(px / CELL);
  iy := Trunc(py / CELL);
  if not InGrid(ix, iy) then Exit;
  if Grid[ix, iy].Kind = ckEmpty then Exit;
  if Grid[ix, iy].Kind in [ckSource, ckBlower, ckHopper, ckSilo, ckVFeeder] then Exit(True);
  lx := px - (ix * CELL + HALF);
  ly := py - (iy * CELL + HALF);
  Result := ClampShape(ix, iy, lx, ly, 2 + PRAD);
end;

{ silo walls are solid for falling material (it gets in only through the top opening) }
function InStoreBody(px, py: Single): Boolean;
var
  i: Integer;
  ly: Single;
begin
  for i := 0 to NBody - 1 do
    if (px > Bodies[i].X1) and (px < Bodies[i].X2) and (py > Bodies[i].Y1) and (py < Bodies[i].Y2) then
      Exit(True);
  for i := 0 to NSlope - 1 do
    with Slopes[i] do
      if (px > X1) and (px < X2) then
      begin
        ly := Y1 + (px - X1) * (Y2 - Y1) / (X2 - X1);
        if (py > ly) and (py < ly + 9) then Exit(True);
      end;
  Result := False;
end;

function SolidAt(px, py: Single): Boolean;
var
  bi, bk: Integer;
begin
  Result := (px < 0.5) or (px > CANVAS_W - 0.5) or (py >= FLOOR_Y) or
    GridSolid(px, py) or InBucketWall(px, py, bi, bk) or InStoreBody(px, py);
end;

{ Push a particle that ended up inside something back to free space }
procedure Depenetrate(var p: TParticle);
var
  bi, bk, r, k: Integer;
  x1, y1, x2, y2, best, ang, nx, ny: Single;
begin
  if p.X < 0.5 then p.X := 1;
  if p.X > CANVAS_W - 0.5 then p.X := CANVAS_W - 1;
  if p.Y >= FLOOR_Y then p.Y := FLOOR_Y - 0.05;
  if InBucketWall(p.X, p.Y, bi, bk) then
  begin
    WallRect(bi, bk, x1, y1, x2, y2);
    if p.Bucket = bi then
    begin
      { contents squeezed into a wall (or a corner) go back inside, never through it }
      p.X := fclamp(p.X, Buckets[bi].X + PRAD + 0.05, Buckets[bi].X + Buckets[bi].W - PRAD - 0.05);
      p.Y := fmin(p.Y, Buckets[bi].Y + Buckets[bi].H - PRAD - 0.05);
      Exit;
    end;
    best := p.X - x1;
    nx := x1 - 0.05;
    ny := p.Y;
    if x2 - p.X < best then begin best := x2 - p.X; nx := x2 + 0.05; ny := p.Y; end;
    if p.Y - y1 < best then begin best := p.Y - y1; nx := p.X; ny := y1 - 0.05; end;
    if y2 - p.Y < best then begin nx := p.X; ny := y2 + 0.05; end;
    p.X := nx;
    p.Y := ny;
  end;
  if GridSolid(p.X, p.Y) then
    for r := 1 to 8 do
      for k := 0 to 7 do
      begin
        ang := k * Pi / 4;
        nx := p.X + Cos(ang) * r * 1.5;
        ny := p.Y + Sin(ang) * r * 1.5;
        if not SolidAt(nx, ny) then
        begin
          p.X := nx;
          p.Y := ny;
          Exit;
        end;
      end;
end;

function AddBucket(CenterX, TopY, W, H: Single): Integer;
var
  i: Integer;
begin
  for i := 0 to MAX_BUCKETS - 1 do
    if not Buckets[i].Active then
    begin
      Buckets[i].Active := True;
      Buckets[i].W := W;
      Buckets[i].H := H;
      Buckets[i].X := CenterX - W / 2;
      Buckets[i].Y := TopY;
      Buckets[i].Count := 0;
      Buckets[i].Spilled := 0;
      Buckets[i].Flash := 0;
      Buckets[i].Layer := CurLayer;
      ClampBucket(i);
      Exit(i);
    end;
  Result := -1;
end;

function BucketAt(px, py: Single): Integer;
var
  i: Integer;
begin
  for i := MAX_BUCKETS - 1 downto 0 do
    if Buckets[i].Active and (px >= Buckets[i].X - WALL_T) and (px <= Buckets[i].X + Buckets[i].W + WALL_T) and
      (py >= Buckets[i].Y - 4) and (py <= Buckets[i].Y + Buckets[i].H + WALL_T) then
      Exit(i);
  Result := -1;
end;

procedure ClampBucket(i: Integer);
begin
  Buckets[i].X := fclamp(Buckets[i].X, WALL_T, CANVAS_W - Buckets[i].W - WALL_T);
  Buckets[i].Y := fclamp(Buckets[i].Y, 0, FLOOR_Y - Buckets[i].H - WALL_T);
end;

procedure MoveBucket(i: Integer; dx, dy: Single);
var
  ox, oy: Single;
  k: Integer;
begin
  if (i < 0) or not Buckets[i].Active then Exit;
  ox := Buckets[i].X;
  oy := Buckets[i].Y;
  Buckets[i].X := Buckets[i].X + dx;
  Buckets[i].Y := Buckets[i].Y + dy;
  ClampBucket(i);
  dx := Buckets[i].X - ox;
  dy := Buckets[i].Y - oy;
  { carry the contents along }
  for k := 0 to NPart - 1 do
    if (not Parts[k].InPipe) and (Parts[k].Bucket = i) then
    begin
      Parts[k].X := Parts[k].X + dx;
      Parts[k].Y := Parts[k].Y + dy;
    end;
end;

procedure ResizeBucket(i: Integer; NewW, NewH: Single);
var
  cx, bottom: Single;
begin
  if (i < 0) or not Buckets[i].Active then Exit;
  cx := Buckets[i].X + Buckets[i].W / 2;
  bottom := Buckets[i].Y + Buckets[i].H;
  Buckets[i].W := NewW;
  Buckets[i].H := NewH;
  Buckets[i].X := cx - NewW / 2;
  Buckets[i].Y := bottom - NewH;
  ClampBucket(i);
end;

procedure EmptyBucket(i: Integer);
var
  k: Integer;
begin
  for k := 0 to NPart - 1 do
    if (not Parts[k].InPipe) and (Parts[k].Bucket = i) then
      Parts[k].Life := -1;
  Buckets[i].Spilled := 0;
  Buckets[i].Flash := 0;
end;

procedure DeleteBucket(i: Integer);
var
  k: Integer;
begin
  if (i < 0) or (i >= MAX_BUCKETS) then Exit;
  Buckets[i].Active := False;
  for k := 0 to NPart - 1 do
    if Parts[k].Bucket = i then Parts[k].Bucket := -1;
end;

function BucketFill(i: Integer): Single;
begin
  Result := Buckets[i].Count * PDIAM * PDIAM * 0.87 / (Buckets[i].W * Buckets[i].H);
end;

{ ---------------------------------------------------------------- particles }

procedure Spawn(gx, gy: Integer; M: TMat; AtMouth: Boolean);
var
  p: PParticle;
  c: PCell;
  hw, t: Single;
  m0: Integer;
begin
  if NPart >= MAX_PART then
  begin
    LimitHit := True;
    Exit;
  end;
  if (M = mAir) and (NAir >= MAX_AIR) then Exit;
  c := @Grid[gx, gy];
  hw := fmax(0.3, HWOf(c^.Dia) - PRAD);
  p := @Parts[NPart];
  Inc(NPart);
  if M = mAir then Inc(NAir);
  if AtMouth and (c^.Mouth >= 0) then
  begin
    m0 := c^.Mouth;
    t := (Random * 2 - 1) * hw * 0.8;
    p^.X := gx * CELL + HALF + DXS[m0] * (HALF - 1) - DYS[m0] * t;
    p^.Y := gy * CELL + HALF + DYS[m0] * (HALF - 1) + DXS[m0] * t;
  end
  else
  begin
    p^.X := gx * CELL + HALF + (Random * 2 - 1) * hw * 0.8;
    p^.Y := gy * CELL + HALF + (Random * 2 - 1) * hw * 0.8;
  end;
  p^.VX := 0;
  p^.VY := 0;
  p^.CX := gx;
  p^.CY := gy;
  p^.Mat := M;
  p^.InPipe := True;
  p^.Bucket := -1;
  if M = mAir then p^.Life := 8 else p^.Life := 1e9;
  p^.ExitDir := ChooseExit(gx, gy);
end;

procedure EmitSources(dt: Single);
var
  i, x, y, d: Integer;
  c: PCell;
  q, rate, tot, r: Single;
  m, chosen: TMat;
begin
  for i := 0 to NActive - 1 do
  begin
    x := ActiveIdx[i] mod GW;
    y := ActiveIdx[i] div GW;
    c := @Grid[x, y];
    if IsStore(c^.Kind) then
    begin
      q := 0;
      for d := 0 to 3 do
        if c^.F[d] > 0 then q := q + c^.F[d];
      rate := q * EMIT_K;
      if c^.EPf[1] then rate := rate + GRAV_FEED * GravityScale;  { gravity discharge downwards }
      rate := rate * DevFeed(c) / 100;
      c^.EmitAcc := fmin(50, c^.EmitAcc + rate * dt);
      while c^.EmitAcc >= 1 do
      begin
        c^.EmitAcc := c^.EmitAcc - 1;
        if Random * 100 < c^.AirPct then
          Spawn(x, y, mAir, False)
        else
        begin
          tot := 0;
          for m := mWater to mSand do
            tot := tot + c^.Stock[m];
          if tot >= 1 then
          begin
            r := Random * tot;
            chosen := mSand;
            for m := mWater to mSand do
              if (c^.Stock[m] >= 1) then
              begin
                chosen := m;
                if r <= c^.Stock[m] then Break;
                r := r - c^.Stock[m];
              end;
            if c^.Stock[chosen] >= 1 then
            begin
              if c^.Kind = ckVFeeder then
              begin
                Spawn(x, y, chosen, False);
                if NPart > 0 then Parts[NPart - 1].Life := fmax(0.5, c^.Strength);
              end
              else
              begin
                c^.Stock[chosen] := c^.Stock[chosen] - 1;
                Spawn(x, y, chosen, False);
              end;
            end;
          end
          else
            Spawn(x, y, mAir, False);
        end;
      end;
      c^.AirAcc := fmin(20, c^.AirAcc + q * AIR_K * dt);
      while c^.AirAcc >= 1 do
      begin
        c^.AirAcc := c^.AirAcc - 1;
        Spawn(x, y, mAir, False);
      end;
    end
    else if (c^.Mouth >= 0) and (c^.F[c^.Mouth] < -0.02) then
    begin
      { air drawn in through an open intake }
      c^.AirAcc := fmin(20, c^.AirAcc - c^.F[c^.Mouth] * AIR_K * dt);
      while c^.AirAcc >= 1 do
      begin
        c^.AirAcc := c^.AirAcc - 1;
        Spawn(x, y, mAir, True);
      end;
    end;
  end;
end;

procedure StepPipe(var p: TParticle; dt: Single);
var
  c: PCell;
  ccx, ccy, lx, ly, ox, oy, ax, ay, k, g, sp, vmax, fr: Single;
  d, nx, ny: Integer;
begin
  c := @Grid[p.CX, p.CY];
  if c^.Kind = ckEmpty then
  begin
    p.InPipe := False;
    Exit;
  end;
  if (p.ExitDir >= 0) and (c^.F[p.ExitDir] <= 0.01) then
    p.ExitDir := ChooseExit(p.CX, p.CY)
  else if (p.ExitDir < 0) and (Random < 0.1) then
    p.ExitDir := ChooseExit(p.CX, p.CY);

  ccx := p.CX * CELL + HALF;
  ccy := p.CY * CELL + HALF;
  lx := p.X - ccx;
  ly := p.Y - ccy;
  AirVel(c, p.CX, p.CY, p.ExitDir, lx, ly, ax, ay);
  k := fmin(1, MatP[p.Mat].Couple * dt);
  g := GRAVITY * GravityScale * MatP[p.Mat].Grav;
  p.VX := p.VX + (ax - p.VX) * k + (Random - 0.5) * 6;
  p.VY := p.VY + (ay - p.VY) * k + g * dt + (Random - 0.5) * 6;
  vmax := 800;
  if (c^.Kind = ckDrop) and (c^.Mouth >= 0) then
  begin
    { drop outlet: extra pull out of the mouth, rate limited by the gate }
    p.VX := p.VX + DXS[c^.Mouth] * GRAVITY * GravityScale * dt * DevStr(c) / 100;
    p.VY := p.VY + DYS[c^.Mouth] * GRAVITY * GravityScale * dt * DevStr(c) / 100;
    vmax := 60 + 7 * DevStr(c);
  end;
  sp := Sqrt(Sqr(p.VX) + Sqr(p.VY));
  if sp > vmax then
  begin
    p.VX := p.VX * vmax / sp;
    p.VY := p.VY * vmax / sp;
  end;
  lx := lx + p.VX * dt;
  ly := ly + p.VY * dt;

  nx := 0;
  ny := 0;
  d := -1;
  if (Abs(lx) > HALF) or (Abs(ly) > HALF) then
  begin
    if Abs(lx) >= Abs(ly) then
    begin
      if lx > 0 then d := 0 else d := 2;
    end
    else if ly > 0 then d := 1
    else d := 3;
  end;
  if d >= 0 then
  begin
    if d = c^.Mouth then
    begin
      p.X := ccx + lx;
      p.Y := ccy + ly;
      p.InPipe := False;
      p.Bucket := -1;
      if p.Mat = mAir then p.Life := fmin(p.Life, 0.5);
      Exit;
    end
    else if c^.EPf[d] then
    begin
      nx := p.CX + DXS[d];
      ny := p.CY + DYS[d];
      if IsStore(Grid[nx, ny].Kind) and StoreAccepts(Grid[nx, ny], p.Mat) then
      begin
        { flowing into a tank, hopper or silo: it is stored }
        if p.Mat <> mAir then
          if Grid[nx, ny].Kind <> ckVFeeder then Grid[nx, ny].Stock[p.Mat] := Grid[nx, ny].Stock[p.Mat] + 1;
        p.Life := -1;
        Exit;
      end;
      if IsStore(Grid[nx, ny].Kind) then
      begin
        { full: the material waits in the pipe }
        if DXS[d] <> 0 then lx := fclamp(lx, -HALF + 0.01, HALF - 0.01)
        else ly := fclamp(ly, -HALF + 0.01, HALF - 0.01);
        p.VX := 0;
        p.VY := 0;
        nx := -1;
      end;
    end;
    if (d >= 0) and (d <> c^.Mouth) and c^.EPf[d] and (nx >= 0) then
    begin
      p.CX := nx;
      p.CY := ny;
      c := @Grid[nx, ny];
      lx := lx - DXS[d] * CELL;
      ly := ly - DYS[d] * CELL;
      ccx := nx * CELL + HALF;
      ccy := ny * CELL + HALF;
      p.ExitDir := ChooseExit(nx, ny);
    end
    else if DXS[d] <> 0 then
    begin
      lx := fclamp(lx, -HALF + 0.01, HALF - 0.01);
      p.VX := -p.VX * 0.2;
    end
    else
    begin
      ly := fclamp(ly, -HALF + 0.01, HALF - 0.01);
      p.VY := -p.VY * 0.2;
    end;
  end;

  ox := lx;
  oy := ly;
  if not ClampShape(p.CX, p.CY, lx, ly, -PRAD) then
  begin
    fr := 1 - MatP[p.Mat].Fric * 0.05;
    if lx <> ox then
    begin
      p.VX := -p.VX * 0.1;
      p.VY := p.VY * fr;
    end;
    if ly <> oy then
    begin
      p.VY := -p.VY * 0.1;
      p.VX := p.VX * fr;
    end;
  end;
  p.X := ccx + lx;
  p.Y := ccy + ly;
end;

procedure Capture(var p: TParticle; i: Integer);
var
  m: Integer;
begin
  m := Intakes[i].D;
  p.InPipe := True;
  p.CX := Intakes[i].CX;
  p.CY := Intakes[i].CY;
  p.X := Intakes[i].MX - DXS[m] * 1.5;
  p.Y := Intakes[i].MY - DYS[m] * 1.5;
  p.Bucket := -1;
  p.ExitDir := ChooseExit(p.CX, p.CY);
end;

procedure StepFree(var p: TParticle; dt: Single);
var
  g, f, dx, dy, dist, acc, ox, oy, nx, ny, sp, along, perp, fr, mass: Single;
  i, b: Integer;
begin
  mass := MatP[p.Mat].Mass;
  g := GRAVITY * GravityScale * MatP[p.Mat].Grav;
  p.VY := p.VY + g * dt;
  f := fmax(0, 1 - MatP[p.Mat].Drag * dt);
  p.VX := p.VX * f;
  p.VY := p.VY * f;
  { liquids keep moving sideways so they level out instead of heaping }
  if p.Mat = mWater then p.VX := p.VX + (Random - 0.5) * 40
  else if p.Mat = mOil then p.VX := p.VX + (Random - 0.5) * 25;

  { falling into a hopper funnel or a silo's top opening: it is stored }
  if p.Mat <> mAir then
    for i := 0 to NCatch - 1 do
      if (p.X >= Catches[i].X1) and (p.X <= Catches[i].X2) and (p.Y >= Catches[i].Y1) and
        (p.Y <= Catches[i].Y2) and (p.VY > -60) and
        StoreAccepts(Grid[Catches[i].GX, Catches[i].GY], p.Mat) then
      begin
        Grid[Catches[i].GX, Catches[i].GY].Stock[p.Mat] := Grid[Catches[i].GX, Catches[i].GY].Stock[p.Mat] + 1;
        p.Life := -1;
        Exit;
      end;

  if p.Mat <> mAir then
    for i := 0 to NIntake - 1 do
    begin
      dx := Intakes[i].MX - p.X;
      dy := Intakes[i].MY - p.Y;
      dist := Sqrt(dx * dx + dy * dy);
      if dist < Intakes[i].CapR then
      begin
        Capture(p, i);
        Exit;
      end;
      if dist < Intakes[i].R then
      begin
        acc := fmin(4000, Intakes[i].Str * 30 * (1 - dist / Intakes[i].R) / mass);
        p.VX := p.VX + dx / dist * acc * dt;
        p.VY := p.VY + dy / dist * acc * dt;
      end;
    end;

  for i := 0 to NJet - 1 do
  begin
    dx := p.X - Jets[i].MX;
    dy := p.Y - Jets[i].MY;
    along := dx * DXS[Jets[i].D] + dy * DYS[Jets[i].D];
    perp := Abs(-dx * DYS[Jets[i].D] + dy * DXS[Jets[i].D]);
    if (along > 0) and (along < Jets[i].L) and (perp < 6 + along * 0.3) then
    begin
      acc := fmin(4000, Jets[i].Str * 18 * (1 - along / Jets[i].L) / mass);
      p.VX := p.VX + DXS[Jets[i].D] * acc * dt;
      p.VY := p.VY + DYS[Jets[i].D] * acc * dt;
    end;
  end;

  sp := Sqrt(Sqr(p.VX) + Sqr(p.VY));
  if sp > 700 then
  begin
    p.VX := p.VX * 700 / sp;
    p.VY := p.VY * 700 / sp;
  end;

  if p.Mat = mAir then
  begin
    p.X := p.X + p.VX * dt;
    p.Y := p.Y + p.VY * dt;
    if (p.X < 0) or (p.X > CANVAS_W) or (p.Y < -50) or (p.Y > FLOOR_Y) then p.Life := -1;
    Exit;
  end;

  if SolidAt(p.X, p.Y) then Depenetrate(p);
  ox := p.X;
  oy := p.Y;
  nx := ox + p.VX * dt;
  ny := oy + p.VY * dt;
  fr := 1 - MatP[p.Mat].Fric * 0.3;
  if SolidAt(nx, ny) then
  begin
    if not SolidAt(nx, oy) then
    begin
      ny := oy;
      p.VY := -p.VY * 0.1;
      p.VX := p.VX * fr;
    end
    else if not SolidAt(ox, ny) then
    begin
      nx := ox;
      p.VX := -p.VX * 0.1;
      p.VY := p.VY * (1 - MatP[p.Mat].Fric * 0.1);
    end
    else
    begin
      nx := ox;
      ny := oy;
      p.VX := -p.VX * 0.1;
      p.VY := -p.VY * 0.1;
    end;
  end;
  p.X := nx;
  p.Y := ny;

  { bucket membership & overflow detection }
  if p.Bucket >= 0 then
  begin
    b := p.Bucket;
    if not Buckets[b].Active then
      p.Bucket := -1
    else if (p.X < Buckets[b].X) or (p.X > Buckets[b].X + Buckets[b].W) or
      (p.Y > Buckets[b].Y + Buckets[b].H + 2) or (p.Y < Buckets[b].Y - 40) then
    begin
      if p.Y < Buckets[b].Y + 8 then
      begin
        Inc(Buckets[b].Spilled);
        Buckets[b].Flash := 2.0;
      end;
      p.Bucket := -1;
    end;
  end;
  if p.Bucket < 0 then
    p.Bucket := BucketInterior(p.X, p.Y);
end;

procedure ResolvePair(var a, b: TParticle);
var
  dx, dy, d2, d, ov, nx, ny, wa, wb, ma, mb, rv, tx, ty, fr, k, da, db: Single;
begin
  dx := b.X - a.X;
  dy := b.Y - a.Y;
  d2 := dx * dx + dy * dy;
  if d2 >= PDIAM * PDIAM then Exit;
  if d2 < 1e-8 then
  begin
    dx := (Random - 0.5) * 0.1;
    dy := (Random - 0.5) * 0.1;
    d2 := dx * dx + dy * dy + 1e-10;
  end;
  d := Sqrt(d2);
  nx := dx / d;
  ny := dy / d;
  ov := PDIAM - d;
  ma := MatP[a.Mat].Mass;
  mb := MatP[b.Mat].Mass;
  wa := mb / (ma + mb);
  wb := ma / (ma + mb);
  if a.InPipe or b.InPipe then k := 0.35 else k := 0.8;
  a.X := a.X - nx * ov * wa * k;
  a.Y := a.Y - ny * ov * wa * k;
  b.X := b.X + nx * ov * wb * k;
  b.Y := b.Y + ny * ov * wb * k;
  rv := (b.VX - a.VX) * nx + (b.VY - a.VY) * ny;
  { free pairs get their normal response from the position correction (PBD) }
  if (rv < 0) and (a.InPipe or b.InPipe) then
  begin
    a.VX := a.VX + nx * rv * wa;
    a.VY := a.VY + ny * rv * wa;
    b.VX := b.VX - nx * rv * wb;
    b.VY := b.VY - ny * rv * wb;
    rv := 0;
  end;
  fr := (MatP[a.Mat].Fric + MatP[b.Mat].Fric) * 0.25;
  tx := (b.VX - a.VX) - nx * rv;
  ty := (b.VY - a.VY) - ny * rv;
  a.VX := a.VX + tx * fr * wa;
  a.VY := a.VY + ty * fr * wa;
  b.VX := b.VX - tx * fr * wb;
  b.VY := b.VY - ty * fr * wb;
  { buoyancy: the denser one sinks, the lighter one floats up }
  if not (a.InPipe or b.InPipe) then
  begin
    da := MatP[a.Mat].Dens;
    db := MatP[b.Mat].Dens;
    if (da > db + 0.05) and (a.Y < b.Y) then
    begin
      a.Y := a.Y + 0.3;
      b.Y := b.Y - 0.3;
    end
    else if (db > da + 0.05) and (b.Y < a.Y) then
    begin
      b.Y := b.Y + 0.3;
      a.Y := a.Y - 0.3;
    end;
  end;
end;

function BinOf(px, py: Single; out bx, by: Integer): Integer;
begin
  bx := EnsureRange(Trunc(fmax(0, px) / HBIN), 0, HBW - 1);
  by := EnsureRange(Trunc(fmax(0, py) / HBIN), 0, HBH - 1);
  Result := by * HBW + bx;
end;

procedure Collide;
var
  i, j, bx, by, cx, cy, h: Integer;
begin
  FillDWord(HashHead[0], Length(HashHead), DWord(-1));
  for i := 0 to NPart - 1 do
    if (Parts[i].Life > 0) and (Parts[i].Mat <> mAir) then
    begin
      h := BinOf(Parts[i].X, Parts[i].Y, bx, by);
      HashNext[i] := HashHead[h];
      HashHead[h] := i;
    end;
  for i := 0 to NPart - 1 do
  begin
    if (Parts[i].Life <= 0) or (Parts[i].Mat = mAir) then Continue;
    BinOf(Parts[i].X, Parts[i].Y, bx, by);
    for cy := by - 1 to by + 1 do
    begin
      if (cy < 0) or (cy >= HBH) then Continue;
      for cx := bx - 1 to bx + 1 do
      begin
        if (cx < 0) or (cx >= HBW) then Continue;
        j := HashHead[cy * HBW + cx];
        while j >= 0 do
        begin
          if j > i then ResolvePair(Parts[i], Parts[j]);
          j := HashNext[j];
        end;
      end;
    end;
  end;
end;

procedure Compact;
var
  i, j: Integer;
begin
  j := 0;
  NAir := 0;
  for i := 0 to NPart - 1 do
    if Parts[i].Life > 0 then
    begin
      if i <> j then Parts[j] := Parts[i];
      if Parts[j].Mat = mAir then Inc(NAir);
      Inc(j);
    end;
  NPart := j;
end;

procedure StepParticles(dt: Single);
var
  i: Integer;
begin
  for i := 0 to NPart - 1 do
  begin
    if Parts[i].Life <= 0 then Continue;
    if Parts[i].Life < 1e8 then
    begin
      { air dots and what a virtual feeder emits fade away }
      Parts[i].Life := Parts[i].Life - dt;
      if Parts[i].Life <= 0 then Continue;
    end;
    if Parts[i].InPipe then
      StepPipe(Parts[i], dt)
    else
      StepFree(Parts[i], dt);
  end;
  for i := 0 to NPart - 1 do
  begin
    PrevX[i] := Parts[i].X;
    PrevY[i] := Parts[i].Y;
  end;
  Collide;
  Collide;
  { position-based dynamics: the contact correction becomes velocity, so a
    resting pile stays at rest instead of accumulating gravity and compressing }
  for i := 0 to NPart - 1 do
    if (Parts[i].Life > 0) and (not Parts[i].InPipe) and (Parts[i].Mat <> mAir) then
    begin
      Parts[i].VX := Parts[i].VX + fclamp((Parts[i].X - PrevX[i]) / dt, -60, 60);
      Parts[i].VY := Parts[i].VY + fclamp((Parts[i].Y - PrevY[i]) / dt, -60, 60);
    end;
  Compact;
end;

procedure CountBuckets;
var
  i, b: Integer;
begin
  for b := 0 to MAX_BUCKETS - 1 do
    Buckets[b].Count := 0;
  for i := 0 to NPart - 1 do
  begin
    b := Parts[i].Bucket;
    if (b >= 0) and (not Parts[i].InPipe) and (Parts[i].Mat <> mAir) and
      (Parts[i].Y >= Buckets[b].Y) then
      Inc(Buckets[b].Count);
  end;
end;

{ a free particle at px, py (rain) }
procedure SpawnFree(px, py: Single; M: TMat; vx, vy: Single);
var
  p: PParticle;
begin
  if NPart >= MAX_PART then
  begin
    LimitHit := True;
    Exit;
  end;
  p := @Parts[NPart];
  Inc(NPart);
  p^.X := px;
  p^.Y := py;
  p^.VX := vx;
  p^.VY := vy;
  p^.CX := EnsureRange(Trunc(px / CELL), 0, GW - 1);
  p^.CY := EnsureRange(Trunc(py / CELL), 0, GH - 1);
  p^.Mat := M;
  p^.InPipe := False;
  p^.Bucket := -1;
  p^.Life := 1e9;
  p^.ExitDir := -1;
end;

{ a water particle boils off: it becomes a rising wisp of steam (an air dot) }
procedure Steam(var p: TParticle);
begin
  p.Mat := mAir;
  p.Life := 1.5;
  p.Bucket := -1;
  if not p.InPipe then p.ExitDir := STEAM_MARK;   { humidity sensors tell steam from blown air }
  if not p.InPipe then p.VY := -40;
end;

{ rain falls from its cloud; fire burns fluff and oil and is put out by water;
  heaters boil water off }
procedure EquipEffects(dt: Single);
var
  i, j, k: Integer;
  E: ^TEquipObj;
  p: PParticle;
  zx1, zy1, zx2, zy2, chance: Single;
begin
  for i := 0 to MAX_EQUIP - 1 do
  begin
    E := @Equips[i];
    if not (E^.Active and EquipRunning(i)) then Continue;
    case E^.Kind of
      EQ_RAIN:
        begin
          E^.Heat := E^.Heat + E^.Level / 100 * E^.W / 240 * 140 * dt;
          while E^.Heat >= 1 do
          begin
            E^.Heat := E^.Heat - 1;
            SpawnFree(E^.X + 8 + Random * (E^.W - 16), E^.Y + E^.H * 0.85, mWater, (Random - 0.5) * 10, 60 + Random * 40);
          end;
        end;
      EQ_FIRE:
        begin
          zx1 := E^.X;
          zx2 := E^.X + E^.W;
          zy1 := E^.Y + E^.H * (1 - fmax(0.2, E^.Heat / 100));
          zy2 := E^.Y + E^.H;
          for k := 0 to NPart - 1 do
          begin
            p := @Parts[k];
            if (p^.Life <= 0) or p^.InPipe or (p^.Mat = mAir) then Continue;
            if (p^.X < zx1) or (p^.X > zx2) or (p^.Y < zy1) or (p^.Y > zy2) then Continue;
            case p^.Mat of
              mWater:
                begin
                  Steam(p^);
                  E^.Heat := E^.Heat - 0.8;
                end;
              mFluff:
                begin
                  p^.Life := -1;
                  E^.Heat := fmin(100, E^.Heat + 0.4);
                end;
              mOil:
                begin
                  p^.Life := -1;
                  E^.Heat := fmin(100, E^.Heat + 0.8);
                end;
            end;
          end;
          { it grows back slowly toward its size }
          if E^.Heat < E^.Level then E^.Heat := fmin(E^.Level, E^.Heat + 3 * dt);
          if E^.Heat <= 0 then
          begin
            E^.Heat := 0;
            E^.State := EQS_STOP;   { put out }
            Continue;
          end;
          { equipment caught in the flames goes to fault }
          for j := 0 to MAX_EQUIP - 1 do
            if Equips[j].Active and EquipActuated(Equips[j].Kind) and
              not (Equips[j].State in [EQS_FAULT, EQS_DISABLE]) and
              (Equips[j].X < zx2) and (Equips[j].X + Equips[j].W > zx1) and
              (Equips[j].Y < zy2) and (Equips[j].Y + Equips[j].H > zy1) then
              Equips[j].State := EQS_FAULT;
        end;
      EQ_IRHEATER:
        begin
          { radiant heat: the area below the panel }
          chance := E^.Level / 100 * 3 * dt;
          for k := 0 to NPart - 1 do
          begin
            p := @Parts[k];
            if (p^.Life <= 0) or p^.InPipe or (p^.Mat <> mWater) then Continue;
            if (p^.X >= E^.X) and (p^.X <= E^.X + E^.W) and (p^.Y >= E^.Y + E^.H) and
              (p^.Y <= E^.Y + E^.H * 6) and (Random < chance) then Steam(p^);
          end;
        end;
      EQ_HEATER:
        begin
          { a duct heater: water in the linked pipe cell (or in its own box) boils off }
          chance := E^.Level / 100 * 4 * dt;
          for k := 0 to NPart - 1 do
          begin
            p := @Parts[k];
            if (p^.Life <= 0) or (p^.Mat <> mWater) or (Random >= chance) then Continue;
            if E^.LinkX >= 0 then
            begin
              if p^.InPipe and (p^.CX = E^.LinkX) and (p^.CY = E^.LinkY) then Steam(p^);
            end
            else if (not p^.InPipe) and (p^.X >= E^.X) and (p^.X <= E^.X + E^.W) and (p^.Y >= E^.Y) and
              (p^.Y <= E^.Y + E^.H) then Steam(p^);
          end;
        end;
    end;
  end;
end;

{ heaters warm up toward 20 + 2.3 x their power % while they run and cool back to 20 C; a fire is as hot as it burns }
procedure EquipTemps(dt: Single);
var
  i: Integer;
  E: ^TEquipObj;
  target: Single;
begin
  for i := 0 to MAX_EQUIP - 1 do
  begin
    E := @Equips[i];
    if not E^.Active then Continue;
    if E^.Temp <= 0 then E^.Temp := 20;
    case E^.Kind of
      EQ_HEATER, EQ_IRHEATER:
        begin
          if EquipRunning(i) then target := 20 + 2.3 * E^.Level else target := 20;
          E^.Temp := E^.Temp + (target - E^.Temp) * fmin(1, dt / 8);
        end;
      EQ_FIRE:
        if EquipRunning(i) then E^.Temp := 20 + 8 * E^.Heat else E^.Temp := E^.Temp + (20 - E^.Temp) * fmin(1, dt / 4);
    end;
  end;
end;

{ the temperature that comes to equipment i from its source (Src): a heat exchanger
  gives its tube outlet, a chiller gives a cooling tower its condenser water, any
  other piece its own temperature; Default when it has none }
function SourceTemp(i: Integer; Default: Single): Single;
var
  j: Integer;
begin
  Result := Default;
  if Equips[i].Src = '' then Exit;
  for j := 0 to MAX_EQUIP - 1 do
    if Equips[j].Active and (j <> i) and SameText(Equips[j].Name, Equips[i].Src) then
    begin
      if (Equips[j].Kind = EQ_HEATEX) and (Equips[j].HotOut > 0) then Result := Equips[j].HotOut
      else if (Equips[j].Kind = EQ_CHILLER) and (Equips[i].Kind = EQ_COOLTOWER) and (Equips[j].HotOut > 0) then
        Result := Equips[j].HotOut
      else if Equips[j].Temp > 0 then Result := Equips[j].Temp;
      Exit;
    end;
end;

{ heat exchangers, cooling towers and chillers; the outlets follow in a few seconds.
  - heat exchanger (shell and tube, counterflow): the process stream through the
    linked pipe is the shell side (RMin C in, 20 when 0), the tube side flows at its
    Level % while it runs and comes in at its source's temperature (Src) or at RMax.
    Effectiveness-NTU: Q = eps * Cmin * (Ttube,in - Tshell,in). Water leaving the
    shell above 100 C boils off.
  - cooling tower: water comes in from its source (or at RMax) and leaves toward the
    wet-bulb temperature (RMin, 21 when 0): out = in - eff * (in - wet bulb), eff 0.15
    with the fan off, up to 0.75 with the fan (Level %) at full speed; the warm moist
    air rises as a plume of vapour.
  - chiller: the return water from its source (or at RMin, 12 when 0) is chilled to its
    set point (RMax) by at most 20 C at its capacity (Level %) while it runs; its
    condenser water leaves at 30 + 0.6 x the cooling (for a cooling tower). }
procedure ThermalEquipment(dt: Single);
var
  i, k: Integer;
  E: ^TEquipObj;
  c: PCell;
  p: PParticle;
  thi, tci, ch, cc, cmin, cmax, cr, ntu, eps, q, tco, tho, ua, a, chance, eff, tin, twb, target: Single;
begin
  for i := 0 to MAX_EQUIP - 1 do
  begin
    E := @Equips[i];
    if not E^.Active then Continue;
    case E^.Kind of
      EQ_HEATEX:
        begin
          thi := SourceTemp(i, E^.RMax);
          if E^.RMin > 0 then tci := E^.RMin else tci := 20;
          if EquipRunning(i) then ch := E^.Level / 100 else ch := 0;
          c := EquipLinkCell(i);
          if c <> nil then cc := fmin(2, CellSpeed(E^.LinkX, E^.LinkY) / CELL / 16) else cc := 0;
          ua := 1.2 * E^.W * E^.H / (168 * 64);
          cmin := fmin(ch, cc);
          cmax := fmax(ch, cc);
          q := 0;
          if cmin < 0.001 then
          begin
            { one side does not flow: no heat moves on; a still side takes the other side's temperature }
            if (ch > 0.001) and (cc <= 0.001) then begin tco := thi; tho := thi; end
            else if (cc > 0.001) and (ch <= 0.001) then begin tco := tci; tho := tci; end
            else begin tco := E^.Temp; tho := E^.HotOut; end;
          end
          else
          begin
            cr := cmin / cmax;
            ntu := ua / cmin;
            if cr > 0.999 then eps := ntu / (1 + ntu)
            else eps := (1 - Exp(-ntu * (1 - cr))) / (1 - cr * Exp(-ntu * (1 - cr)));
            q := eps * cmin * (thi - tci);
            tco := tci + q / cc;
            tho := thi - q / ch;
          end;
          a := fmin(1, dt / 3);
          if E^.Temp <= 0 then E^.Temp := tci;
          if E^.HotOut <= 0 then E^.HotOut := thi;
          E^.Temp := E^.Temp + (tco - E^.Temp) * a;
          E^.HotOut := E^.HotOut + (tho - E^.HotOut) * a;
          E^.HotIn := thi;
          E^.ColdIn := tci;
          E^.Duty := E^.Duty + (q * 10 - E^.Duty) * a;
          { the shell outlet above boiling: its water boils off }
          if (c <> nil) and (E^.Temp > 100) then
          begin
            chance := fmin(1, (E^.Temp - 100) / 50) * 4 * dt;
            for k := 0 to NPart - 1 do
            begin
              p := @Parts[k];
              if (p^.Life > 0) and p^.InPipe and (p^.Mat = mWater) and (p^.CX = E^.LinkX) and (p^.CY = E^.LinkY) and
                (Random < chance) then Steam(p^);
            end;
          end;
        end;
      EQ_COOLTOWER:
        begin
          tin := SourceTemp(i, E^.RMax);
          if E^.RMin > 0 then twb := E^.RMin else twb := 21;
          if EquipRunning(i) then eff := 0.15 + 0.6 * E^.Level / 100 else eff := 0.15;
          target := tin - eff * (tin - twb);
          a := fmin(1, dt / 4);
          if E^.Temp <= 0 then E^.Temp := tin;
          E^.Temp := E^.Temp + (target - E^.Temp) * a;
          E^.HotIn := tin;
          E^.ColdIn := twb;
          E^.Duty := E^.Duty + (fmax(0, tin - E^.Temp) * 12 - E^.Duty) * a;
          { the plume: warm, moist air rising from the fan stack }
          if E^.Duty > 1 then
          begin
            E^.Heat := E^.Heat + E^.Duty / 12 * (0.4 + 0.8 * Ord(EquipRunning(i)) * E^.Level / 100) * dt;
            while E^.Heat >= 1 do
            begin
              E^.Heat := E^.Heat - 1;
              SpawnFree(E^.X + E^.W * (0.25 + 0.5 * Random), E^.Y + 2, mAir, (Random - 0.5) * 20, -30 - Random * 30);
              if NPart > 0 then
              begin
                Parts[NPart - 1].Life := 2.5;
                Parts[NPart - 1].ExitDir := STEAM_MARK;
              end;
            end;
          end;
        end;
      EQ_CHILLER:
        begin
          if E^.RMin > 0 then tin := SourceTemp(i, E^.RMin) else tin := SourceTemp(i, 12);
          if EquipRunning(i) then target := tin - fmin(fmax(0, tin - E^.RMax), 20 * E^.Level / 100)
          else target := tin;
          a := fmin(1, dt / 5);
          if E^.Temp <= 0 then E^.Temp := tin;
          E^.Temp := E^.Temp + (target - E^.Temp) * a;
          E^.HotIn := tin;
          E^.HotOut := 30 + 0.6 * fmax(0, tin - E^.Temp);
          E^.Duty := E^.Duty + (fmax(0, tin - E^.Temp) * 12 - E^.Duty) * a;
        end;
    end;
  end;
end;

{ ponds, pools and wells take in free water that reaches them; a well
  refills from the ground water }
procedure WaterBodies(dt: Single);
var
  i, k: Integer;
  E: ^TEquipObj;
  p: PParticle;
  unitPct: Single;
begin
  for i := 0 to MAX_EQUIP - 1 do
  begin
    E := @Equips[i];
    if not (E^.Active and EquipIsWater(E^.Kind)) then Continue;
    unitPct := 100 / WaterCap(i);
    for k := 0 to NPart - 1 do
    begin
      if E^.Level >= 100 then Break;   { full: the water stays outside, it overflows }
      p := @Parts[k];
      if (p^.Life <= 0) or p^.InPipe or (p^.Mat <> mWater) then Continue;
      if (p^.X >= E^.X) and (p^.X <= E^.X + E^.W) and (p^.Y >= E^.Y + E^.H * 0.15) and (p^.Y <= E^.Y + E^.H + 4) then
      begin
        p^.Life := -1;
        E^.Level := fmin(100, E^.Level + unitPct);
      end;
    end;
    if (E^.Kind = EQ_WELL) and (E^.Level < 80) then E^.Level := fmin(80, E^.Level + 1.5 * dt);
  end;
end;

{ a running pump draws water from the nearest pond / pool / well into the pipe it is linked to }
procedure Pumps(dt: Single);
var
  i, s: Integer;
  E: ^TEquipObj;
begin
  for i := 0 to MAX_EQUIP - 1 do
  begin
    E := @Equips[i];
    if not (E^.Active and (E^.Kind = EQ_PUMP) and EquipRunning(i)) then Continue;
    if EquipLinkCell(i) = nil then Continue;
    s := PumpSource(i);
    if s < 0 then Continue;
    E^.Heat := E^.Heat + E^.Level / 100 * 40 * dt;
    while (E^.Heat >= 1) and (Equips[s].Level > 0) do
    begin
      E^.Heat := E^.Heat - 1;
      Spawn(E^.LinkX, E^.LinkY, mWater, False);
      Equips[s].Level := fmax(0, Equips[s].Level - 100 / WaterCap(s));
    end;
    if Equips[s].Level <= 0 then E^.Heat := 0;   { dry: nothing to pump }
  end;
end;

{ a running conveyor carries the free material lying on its deck }
procedure Conveyors(dt: Single);
var
  i, k: Integer;
  E: ^TEquipObj;
  p: PParticle;
  top, v, x1, y1, x2, y2, len, ux, uy, ly: Single;
begin
  for i := 0 to MAX_EQUIP - 1 do
  begin
    E := @Equips[i];
    if not (E^.Active and (E^.Kind in [EQ_CONVEYOR, EQ_BELT]) and EquipRunning(i)) then Continue;
    top := E^.Y + E^.H * 0.2;
    v := 20 + E^.Level * 1.4;
    if E^.Flip then v := -v;
    if ConveyorTilt(i) <> 0 then
    begin
      { inclined: what lies on the deck moves along the slope }
      ConveyorDeck(i, x1, y1, x2, y2);
      len := Sqrt(Sqr(x2 - x1) + Sqr(y2 - y1));
      ux := (x2 - x1) / len;
      uy := (y2 - y1) / len;
      for k := 0 to NPart - 1 do
      begin
        p := @Parts[k];
        if (p^.Life <= 0) or p^.InPipe or (p^.Mat = mAir) or (p^.X < x1) or (p^.X > x2) then Continue;
        ly := y1 + (p^.X - x1) * (y2 - y1) / (x2 - x1);
        if (p^.Y >= ly - 10) and (p^.Y <= ly + 1) then
        begin
          p^.VX := v * ux;
          p^.VY := v * uy;
          p^.X := p^.X + v * ux * dt * 0.5;
          ly := y1 + (fclamp(p^.X, x1, x2) - x1) * (y2 - y1) / (x2 - x1);
          p^.Y := fmin(p^.Y + v * uy * dt * 0.5, ly - 0.5);
        end;
      end;
      Continue;
    end;
    for k := 0 to NPart - 1 do
    begin
      p := @Parts[k];
      if (p^.Life <= 0) or p^.InPipe or (p^.Mat = mAir) then Continue;
      if (p^.X >= E^.X) and (p^.X <= E^.X + E^.W) and (p^.Y >= top - 10) and (p^.Y <= top + 1) then
      begin
        p^.VX := v;
        p^.X := p^.X + v * dt * 0.5;
      end;
    end;
  end;
end;

procedure SimFrame(dt: Single; Running: Boolean);var
  n, s, i: Integer;
  c: PCell;
begin
  if Assigned(ElecHook) then ElecHook(dt, Running);
  if Assigned(FluidHook) then FluidHook(dt, Running);
  if Assigned(FlowHook) then FlowHook(dt, Running);
  if Assigned(TrendHook) then TrendHook(dt, Running);
  ApplyEquipment(dt, Running);
  UpdateTopology;
  SolvePressure(60);
  ComputeFluxes;
  BuildDeviceLists;
  if not Running then Exit;
  LimitHit := False;
  EmitSources(dt);
  n := EnsureRange(Ceil(dt * 240), 1, 8);
  for s := 1 to n do
    StepParticles(dt / n);
  EquipEffects(dt);
  EquipTemps(dt);
  ThermalEquipment(dt);
  WaterBodies(dt);
  Pumps(dt);
  Conveyors(dt);
  if Assigned(PieceHook) then PieceHook(dt);
  CountBuckets;
  for i := 0 to MAX_BUCKETS - 1 do
    Buckets[i].Flash := fmax(0, Buckets[i].Flash - dt);
  for i := 0 to NActive - 1 do
  begin
    c := @Grid[ActiveIdx[i] mod GW, ActiveIdx[i] div GW];
    if c^.Kind = ckBlower then
      c^.Spin := c^.Spin + dt * DevStr(c) * 0.25;
  end;
end;

{ ---------------------------------------------------------------- demo }

procedure PipeLine(x1, y1, x2, y2, Dia: Integer);
var
  x, y, px, py: Integer;
begin
  x := x1;
  y := y1;
  if Grid[x, y].Kind = ckEmpty then MakePipe(x, y, Dia);
  while (x <> x2) or (y <> y2) do
  begin
    px := x;
    py := y;
    if x <> x2 then x := x + Sign(x2 - x) else y := y + Sign(y2 - y);
    if Grid[x, y].Kind = ckEmpty then MakePipe(x, y, Dia);
    ConnectCells(px, py, x, y);
  end;
end;

procedure LoadDemo;
var
  x, y: Integer;
begin
  ClearAll;

  { Line 1: liquid tank -> blower -> 3-way tee: drop outlet into bucket 1,
    and a constricted / expanded branch to a push-out nozzle into bucket 2 }
  MakePipe(2, 3, 4);
  SetKind(2, 3, ckSource);
  Grid[2, 3].Stock[mWater] := 2400;
  Grid[2, 3].Stock[mOil] := 800;
  Grid[2, 3].Stock[mFluff] := 0;
  Grid[2, 3].Stock[mSand] := 0;
  Grid[2, 3].AirPct := 15;
  Grid[2, 3].Feed := 70;
  PipeLine(2, 3, 11, 3, 3);
  SetKind(6, 3, ckBlower);
  Grid[6, 3].Dir := 0;
  Grid[6, 3].Strength := 60;
  PipeLine(11, 3, 11, 23, 3);
  SetKind(11, 23, ckDrop);
  PipeLine(11, 3, 19, 3, 3);
  SetKind(11, 3, ckValve3);
  Grid[14, 3].Dia := 1;
  Grid[15, 3].Dia := 1;
  for x := 16 to 18 do Grid[x, 3].Dia := 5;
  PipeLine(19, 3, 19, 22, 3);
  SetKind(19, 22, ckNozzle);
  Grid[19, 22].Strength := 45;

  { Line 2: solids tank, gravity discharge through a necked pipe and an on/off valve }
  MakePipe(38, 2, 4);
  SetKind(38, 2, ckSource);
  Grid[38, 2].Stock[mWater] := 0;
  Grid[38, 2].Stock[mOil] := 0;
  Grid[38, 2].Stock[mFluff] := 800;
  Grid[38, 2].Stock[mSand] := 2000;
  Grid[38, 2].AirPct := 25;
  Grid[38, 2].Feed := 60;
  PipeLine(38, 2, 38, 21, 4);
  for y := 10 to 13 do Grid[38, y].Dia := 2;
  SetKind(38, 6, ckValve2);
  SetKind(38, 21, ckDrop);
  Grid[38, 21].Strength := 80;

  { Line 3: suction head dipping into bucket 3, one-way pipe, drop into bucket 2 }
  PipeLine(36, 29, 36, 8, 3);
  PipeLine(36, 8, 25, 8, 3);
  PipeLine(25, 8, 25, 22, 3);
  SetKind(36, 29, ckSuction);
  Grid[36, 29].Strength := 75;
  SetKind(30, 8, ckCheck);
  Grid[30, 8].Dir := 2;
  SetKind(25, 22, ckDrop);

  AddBucket(11 * CELL + HALF, FLOOR_Y - WALL_T - 70, 90, 70);
  AddBucket(22 * CELL, FLOOR_Y - WALL_T - 110, 220, 110);
  AddBucket(38 * CELL + HALF, FLOOR_Y - WALL_T - 110, 150, 110);

  AddLabel(30, 120, 'LINE 1 - liquids'#10'Tank > blower > 3-way valve.'#10'Left: drop outlet.'#10'Right: narrowed, widened,'#10'then push-out nozzle.');
  AddLabel(690, 52, 'LINE 2 - gravity'#10'Sand + fluff drain through'#10'an on/off valve and a neck.');
  AddLabel(640, 260, 'LINE 3 - vacuum'#10'Suction head in bucket 3,'#10'1-way pipe, drop outlet'#10'into bucket 2.');
end;

initialization
  SetLength(Parts, MAX_PART);
  SetLength(HashNext, MAX_PART);
  SetLength(PrevX, MAX_PART);
  SetLength(PrevY, MAX_PART);
  SetLength(HashHead, HBW * HBH);
  ClearAll;

end.
