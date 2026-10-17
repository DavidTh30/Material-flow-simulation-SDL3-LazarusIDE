unit mfapp;

{ Window, rendering, immediate-mode control panel and editing tools. }

{$mode objfpc}{$H+}

interface

procedure RunApp;

implementation

uses
  SysUtils, Math, sdl3min, simcore, layoutio, mfexamples, mftheme, edithist, mfpages, elec, fluid, physics, shapes, plantbus;

const
  PANEL_X = CANVAS_W;        { the right panel column starts here (when it is open) }
  PANEL_W = 304;
  WIN_H = CANVAS_H;           { height of the area below the menu bar }
  MENU_H = 24;                { the menu bar across the top of the window }
  PX = PANEL_X + 8;

type
  TTool = (tSelect, tPipe, tResize, tErase, tFeeder, tVFeeder, tHopper, tSilo, tBlower, tSuction, tNozzle,
    tDrop, tCheck, tValve2, tValve3, tValve4, tBucket, tLabel, tLabelDate, tLabelTime, tFrame, tLink,
    tEqMotor, tEqBlower, tEqPaddle, tEqScrew, tEqCyclone, tEqSilo, tEqStand, tEqLamp, tEqLegend,
    tEqSequence, tEqDiverter, tEqShutter, tEqSlide, tEqHeater, tEqIRHeater, tEqRain, tEqFire,
    tEqPond, tEqPool, tEqWell, tEqPump, tEqPanel, tEqConveyor, tEqBelt, tEqGauge, tEqDigital, tEqCylinder, tEqCompressor, tEqHPU, tEqReceiver, tEqController, tEqHeatEx, tEqCoolTower, tEqChiller,
    tElWire, tElCross, tElTerminal, tElAC, tElDC, tElFuse, tElBreaker, tElSwitch, tElSw2, tElSw3, tElPBNO, tElPBNC,
    tElPBLatch, tElSelector, tElEStop, tElNO, tElNC, tElRelay, tElContactor, tElTimer, tElOL, tElLamp, tElBuzzer,
    tElMotor, tElDrive, tElFloat, tElCT, tElPot, tElSolenoid,
    tFlLine, tFlCross, tFlCompressor, tFlHPump, tFlReceiver, tFlAccum, tFlFRL, tFlRegulator, tFlFilter, tFlCheck,
    tFlThrottle, tFlShuttle, tFlAnd, tFlRelief, tFlV32, tFlV52, tFlV53, tFlV42, tFlV43, tFlCylSA, tFlCylDA,
    tFlAirMotor, tFlHydMotor, tFlSilencer, tFlTank, tFlGauge, tFlPSwitch,
    tCtCounter, tCtLevel, tCtPress, tCtFlow, tCtTemp, tCtSpeed, tCtWeight, tCtPhoto, tCtController, tCtHumid, tCtPH);
  TSelKind = (selNone, selCell, selBucket, selMulti, selLabel, selFrame, selLink, selEquip, selECell, selFCell);
  TDrag = (dragNone, dragPipe, dragResize, dragErase, dragBucket, dragBox, dragMove, dragLabel,
    dragFrameNew, dragFrameMove, dragFrameSize, dragLink, dragEqMove, dragEqSize, dragEWire, dragEPress, dragFLine, dragFPress);
  TClipBucket = record
    DX, DY, W, H: Single;   { relative to the block's top-left corner }
    Layer: Byte;
  end;
  TClipLabel = record
    DX, DY: Single;
    Text: string;
    Kind, Color: Byte;
    Fmt: string;
    NoBox: Boolean;
    Layer: Byte;
  end;
  { a dockable panel window }
  TWin = record
    Title: string;
    Visible: Boolean;
    X, Y, W, H: Single;
    DockX, DockY: Single;   { DockX is for the right column; see DockXOf }
    Side: Integer;          { 0 = embeds in the right column, 1 = in the left column }
    Dragging: Boolean;
    DOX, DOY: Single;
    Scale: Single;          { a resizable panel: its content drawn this much larger }
    BaseW, BaseH: Single;   { its size at scale 1 }
    Sizing: Boolean;        { its size grip is being dragged }
    Scroll, ContentH: Single;   { content scrolled up by Scroll; the content's height (last frame) }
    ScrollDrag: Boolean;    { its scrollbar thumb is being dragged }
    DragOff: Single;
  end;
  { a copied piece of layout: W x H cells (empty ones are skipped) plus buckets }
  TBlock = record
    W, H, Parts: Integer;
    Cells: array of TCellLite;
    Bkts: array of TClipBucket;
    Lbls: array of TClipLabel;
  end;

const
  ToolNames: array[TTool] of string = ('Select', 'Pipe', 'Pipe size', 'Erase',
    'Feeder', 'Virtual fd.', 'Hopper', 'Silo', 'Blower', 'Suction', 'Push nozzle', 'Drop out', '1-way pipe',
    '2-way valve', '3-way valve', '4-way valve', 'Bucket', 'Label', 'Date label', 'Time label', 'Frame', 'Link',
    'Motor', 'Blower', 'Paddle', 'Screw conv.', 'Cyclone', 'Silo bin', 'Silo stand', 'Lamp', 'Legend',
    'Sequence', 'Diverter', 'Shutter', 'Slide valve', 'Heater', 'IR heater', 'Rain', 'Fire', 'Pond', 'Pool', 'Well', 'Water pump',
    'Cabinet', 'Roller conveyor', 'Belt conveyor', 'Needle gauge', 'Digital display',
    'Cylinder', 'Compressor', 'Hydraulic unit', 'Air receiver', 'Faceplate', 'Heat exch.', 'Cool. tower', 'Chiller',
    'Wire', 'Cross', 'Terminal', 'AC supply', 'DC supply', 'Fuse', 'Breaker', 'Switch', '2-way sw.', '3-way sw.',
    'Push NO', 'Push NC', 'Push on/off', 'Selector', 'E-Stop', 'NO contact', 'NC contact', 'Relay', 'Contactor',
    'Timer', 'Overload', 'Lamp', 'Buzzer', 'Motor M', 'Drive VFD', 'Float sw.', 'Current tr.', 'Potentiometer', 'Solenoid Y',
    'Line', 'Cross', 'Compressor', 'Hydr. pump', 'Receiver', 'Accumul.', 'FRL', 'Regulator', 'Filter', 'Check',
    'Throttle', 'Shuttle', 'AND valve', 'Relief', '3/2 valve', '5/2 valve', '5/3 valve', '4/2 valve', '4/3 valve',
    'Cyl. single', 'Cyl. double', 'Air motor', 'Hydr. motor', 'Silencer', 'Tank', 'Gauge', 'P-switch',
    'Counter', 'Level LT', 'Pressure PT', 'Flow FT', 'Temp. TT', 'Speed ST', 'Weight WT', 'Photo eye', 'Controller', 'Humidity MT', 'pH sensor');
  ToolKinds: array[TTool] of TCellKind = (ckEmpty, ckPipe, ckEmpty, ckEmpty,
    ckSource, ckVFeeder, ckHopper, ckSilo, ckBlower, ckSuction, ckNozzle, ckDrop, ckCheck, ckValve2, ckValve3, ckValve4,
    ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty,
    ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty,
    ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty,
    ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty,
    ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty,
    ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty,
    ckEmpty, ckEmpty, ckEmpty, ckEmpty,
    ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty,
    ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty,
    ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty,
    ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty,
    ckEmpty);
  ToolHints: array[TTool] of string = (
    'Click to edit; drag box to select',
    'Drag to route; start on pipe=branch',
    'Click/drag pipe: set size (brush)',
    'Click/drag: remove parts, buckets',
    'Click: place a material feeder',
    'Click: endless feeder, timed material',
    'Click: hopper (funnel above it)',
    'Click: silo (needs 3 cells above)',
    'Click pipe: inline blower (blow)',
    'Click pipe end: suction intake',
    'Click pipe end: push-out nozzle',
    'Click pipe end: gravity drop outlet',
    'Click pipe: one-way (check) pipe',
    'Click pipe: 2-way on/off valve',
    'Click tee: 3-way diverter valve',
    'Click cross: 4-way valve',
    'Click: place bucket (rim at cursor)',
    'Click: add a label, then type',
    'Click: label showing the date',
    'Click: label showing the time',
    'Drag: frame to group & title parts',
    'Click: link to a page / popup',
    'Click: motor (on a device: linked)',
    'Click: centrifugal blower',
    'Click: paddle agitator (motor+shaft)',
    'Click: screw conveyor',
    'Click: cyclone receiver',
    'Click: silo bin (on a silo: level)',
    'Click: silo stand (legs)',
    'Click: status lamp',
    'Click: legend of the state colours',
    'Click: sequence / delays box',
    'Click: diverter (on a 3-way valve)',
    'Click: shutter valve (butterfly)',
    'Click: slide valve (knife gate)',
    'Click: duct heater (on a pipe)',
    'Click: IR heater (heats below it)',
    'Click: rain cloud',
    'Click: fire',
    'Click: pond (holds water)',
    'Click: swimming / water pool',
    'Click: well (ground water)',
    'Click a pipe: water pump',
    'Click: electrical cabinet',
    'Click: roller conveyor',
    'Click: belt conveyor',
    'Click: needle gauge (pick a source)',
    'Click: digital display (source)',
    'Click: cylinder (rod = its stroke)',
    'Click: air compressor on its tank',
    'Click: hydraulic power unit',
    'Click: air receiver tank',
    'Click: controller faceplate SP/PV',
    'Click a pipe: heat exchanger',
    'Click: cooling tower (water from)',
    'Click: water chiller (return from)',
    'Drag: wire (joins where it meets)',
    'Click: wires crossing, not joined',
    'Click: terminal (a joint)',
    'Click: AC supply  W = L, E = N',
    'Click: DC supply  W = +, E = -',
    'Click: fuse (blows on a short)',
    'Click: circuit breaker',
    'Click: on / off switch',
    'Click: 2-way switch (SPDT)',
    'Click: 3-way (intermediate) sw.',
    'Click: push NO - on while held',
    'Click: push NC - stop button',
    'Click: push on / push off',
    'Click: selector contact (S1:pos)',
    'Click: emergency stop (NC)',
    'Click: NO contact of a coil tag',
    'Click: NC contact of a coil tag',
    'Click: relay coil (K)',
    'Click: magnetic contactor (KM)',
    'Click: on-delay timer (T)',
    'Click: overload relay (NC)',
    'Click: pilot lamp',
    'Click: buzzer',
    'Click: motor - runs equipment',
    'Click: drive (VFD) - with speed',
    'Click: float switch (water level)',
    'Click a wire: current transformer',
    'Click: potentiometer (wheel: turn)',
    'Click: valve solenoid coil (Y)',
    'Drag: pneumatic / hydraulic line',
    'Click: lines crossing, not joined',
    'Click: air compressor (out E)',
    'Click: hydraulic pump (out E)',
    'Click: air receiver (stores bar)',
    'Click: accumulator (stores oil)',
    'Click: FRL unit, in W out E',
    'Click: pressure regulator',
    'Click: filter',
    'Click: check valve, W to E only',
    'Click: flow control (wheel)',
    'Click: shuttle valve (OR)',
    'Click: two-pressure valve (AND)',
    'Click: relief valve, in W, tank E',
    'Click: 3/2 valve P=S A=W R=N',
    'Click: 5/2 valve P=S A=W B=E',
    'Click: 5/3 valve, centre closed',
    'Click: 4/2 valve P=S A=W B=E T=N',
    'Click: 4/3 valve, tandem centre',
    'Click: single-acting cyl., A=W',
    'Click: double-acting, A=W B=S',
    'Click: air motor, in W out E',
    'Click: hydraulic motor, W to E',
    'Click: silencer / exhaust',
    'Click: tank (oil return)',
    'Click: pressure gauge (port S)',
    'Click: pressure switch (port S)',
    'Click: counter (C) - counts pulses',
    'Click: level sensor (pick a tank)',
    'Click a pipe: pressure sensor',
    'Click a pipe: flow sensor',
    'Click: temperature sensor (heater)',
    'Click: speed sensor (equipment)',
    'Click: weight sensor (a bucket)',
    'Click: photo sensor (sees material)',
    'Click: controller (PID / on-off)',
    'Click: humidity / moisture sensor',
    'Click: pH sensor (bucket / pipe)');
  KindNames: array[TCellKind] of string = ('Empty', 'Pipe', 'Feeder', 'Blower',
    'Suction head', 'Push-out nozzle', 'Drop outlet', '1-way pipe', '2-way valve', '3-way valve', '4-way valve',
    'Hopper', 'Silo', 'Virtual feeder');
  DirNames: array[0..3] of string = ('East', 'South', 'West', 'North');
  GIdx: array[0..5] of LongInt = (0, 1, 2, 0, 2, 3);

var
  Win: PSDL_Window;
  Ren: PSDL_Renderer;
  Tool: TTool = tSelect;
  BrushDia: Integer = 3;
  SelKind: TSelKind = selNone;
  SelX, SelY, SelB: Integer;
  ShowPressure: Boolean = False;
  ShowAir: Boolean = True;
  Running: Boolean = True;
  MX, MY: Single;
  MDown, MPressed, RDown: Boolean;
  ActiveId: Integer = 0;
  HoldTime, RepeatAcc: Single;
  Drag: TDrag = dragNone;
  LastCX, LastCY: Integer;
  LastMX, LastMY: Single;
  FrameDt: Single = 1 / 60;
  FPS: Single = 60;
  ShotMsPerFrame: Single = 0;
  GV: array[0..63] of TSDL_Vertex;
  GI: array[0..191] of LongInt;
  PRects: array[TMat] of array of TSDL_FRect;
  PCount: array[TMat] of Integer;
  { menus: -1 closed, 0 File, 1 Edit, 2 Theme }
  OpenMenu: Integer = -1;
  QuitRequested: Boolean = False;   { File > Exit, Ctrl+Q }
  { the canvas grid (View > Grid), saved in materialflow.ini }
  GridShow: Boolean = True;
  GridStyle: Integer = 0;        { 0 lines, 1 dots, 2 crosses }
  GridMajor: Integer = 0;        { a stronger line every N cells, 0 = none }
  GridStrength: Integer = 1;     { 0 faint, 1 normal, 2 strong }
  GridColor: Integer = 0;        { 0 theme, 1 blue, 2 green, 3 amber, 4 white }
  GridNumbers: Boolean = False;  { cell numbers along the canvas edges }
  { edit clipboard (one part or one bucket) and pending paste }
  Clip: TBlock;                 { the clipboard }
  { dragging the selection: a copy of it, the press cell and the current offset }
  MoveBuf: TBlock;
  MoveX1, MoveY1, MoveGX0, MoveGY0, MoveDX, MoveDY: Integer;
  MovePressBucket: Integer = -1;
  { properties window (floating; starts docked in the side panel) }
  { dockable panels: Tool, Simulation, Properties }
  Wins: array[0..8] of TWin;
  WinOrder: array[0..8] of Integer = (0, 1, 2, 3, 4, 5, 6, 7, 8);   { drawing order, last = on top }
  { left panel column: when a panel is embedded on the left the whole scene
    shifts right by LeftW. Everything works in canvas coordinates; OX is added
    only when drawing and subtracted from mouse positions }
  LeftW: Integer = 0;
  RightW: Integer = PANEL_W;    { right panel column, open while a panel is embedded there }
  OX: Single = 0;
  OY: Single = MENU_H;          { everything below the menu bar }
  PopupWin: Integer = -1;       { -1 = canvas popup, else the panel it is for }
  { canvas zoom / pan: world point (wx,wy) shows at ((wx-ViewX)*Zoom, (wy-ViewY)*Zoom)
    of the canvas area; only drawing done while CanvasXf is set is transformed }
  Zoom: Single = 1;
  ViewX: Single = 0;
  ViewY: Single = 0;
  CanvasXf: Boolean = False;
  Panning: Boolean = False;
  PanLastX, PanLastY: Single;
  { label being typed into, or -1 }
  EditLabel: Integer = -1;
  EditField: Integer = 0;       { 0 = the text / caption, 1 = a date / time label's format }
  { frames: the selected one, the one whose title is being typed, and a drag in progress }
  SelFr: Integer = -1;
  EditFrame: Integer = -1;
  FrDrag: Integer = -1;
  FrX0, FrY0, FrX1, FrY1: Single;   { drag start / current point (canvas pixels) }
  FrDX, FrDY: Integer;               { a frame move, in cells }
  SelL: Integer = -1;
  SelLk: Integer = -1;           { the selected link }
  SelEq: Integer = -1;           { the selected equipment }
  EqPick: Integer = -1;          { equipment waiting for a click on the part to link it to }
  ToolTab: Integer = 0;          { Tool panel: 0 pipes & parts, 1 equipment, 2 electrical }
  SelEX, SelEY: Integer;         { the selected electrical cell }
  EHX, EHY: Integer;             { the push button held down }
  SelFX, SelFY: Integer;         { the selected fluid power cell }
  FHX, FHY: Integer;             { the push-button valve held down }
  IdBase: Integer = 0;           { added to widget ids while a Focus Properties window draws }
  SelPopup: Integer = -1;        { the frame popup shown in the Frame popup panel }
  FPClick: Boolean = False;      { a click landed in the open frame popup }
  KeepLayers: Boolean = True;    { PlaceBlock: parts keep their layer (move) or go on the active one (paste) }
  { typing into a page name, layer name, popup title / text or link caption }
  TxtEdit: Integer = 0;          { 0 none, 1 page, 2 layer, 3 popup title, 4 popup text, 5 link caption }
  TxtIdx: Integer = -1;
  LastClicks: Integer = 1;
  QX: Single;                   { left edge of the property rows being drawn }
  { box selection (cells, inclusive) and the box being dragged (pixels) }
  SelX1, SelY1, SelX2, SelY2: Integer;
  BoxX0, BoxY0, BoxX1, BoxY1: Single;
  { right-click: a click opens the popup, a drag erases }
  RightPending: Boolean = False;
  RCellX, RCellY: Integer;
  PopupOpen: Boolean = False;
  PopupClick: Boolean = False;
  PopupX, PopupY: Single;
  PopupGX, PopupGY: Integer;
  PasteArmed: Boolean = False;
  WheelIdle: Single = 1;        { seconds since the last mouse-wheel edit }
  SettingsFile: string = '';
  CurrentFile: string = '';     { UTF-8 path of the open layout, '' if unsaved }
  StatusMsg: string = '';
  StatusTime: Single = 0;
  StatusErr: Boolean = False;
  { native file dialog hand-off (its callback may run on another thread) }
  DlgBuf: array[0..4095] of AnsiChar;
  DlgResult: LongInt = 0;       { 0 waiting/none, 1 path ready, 2 cancelled }
  DlgKind: Integer = 0;         { 1 open, 2 save, 3/4 open/save physics, 5/6 open/save shapes }
  DlgDefault: string = '';

const
  DlgFilters: array[0..1] of TSDL_DialogFileFilter = (
    (name: 'Material Flow layout (*.mflow)'; pattern: 'mflow'),
    (name: 'All files'; pattern: '*'));
  PhysFilters: array[0..1] of TSDL_DialogFileFilter = (
    (name: 'Material Flow physics (*.mfphys)'; pattern: 'mfphys'),
    (name: 'All files'; pattern: '*'));
  ShapeFilters: array[0..1] of TSDL_DialogFileFilter = (
    (name: 'Material Flow shapes (*.mfshape)'; pattern: 'mfshape'),
    (name: 'All files'; pattern: '*'));

{ ---------------------------------------------------------------- drawing }

procedure SetCol(r, g, b: Byte; a: Byte = 255);
begin
  SDL_SetRenderDrawColor(Ren, r, g, b, a);
end;

procedure SetC(const c: TRGB; a: Byte = 255);
begin
  SDL_SetRenderDrawColor(Ren, c.R, c.G, c.B, a);
end;

{ ---------------------------------------------------------------- selection }

function ClipEmpty: Boolean;
begin
  Result := (Clip.Parts = 0) and (Length(Clip.Bkts) = 0) and (Length(Clip.Lbls) = 0);
end;

{ ---------------------------------------------------------------- label geometry }

const
  LABEL_PAD = 5;
  LABEL_LINE = 10;

{ a date / time label's value right now }
function LabelValue(i: Integer): string;
begin
  try
    Result := FormatDateTime(string(Labels[i].Fmt), Now);
  except
    Result := '?';
  end;
  if Result = '' then Result := '(empty format)';
end;

{ what a label shows: its text, or for a date / time label the caption (if any) above the value }
function LabelDisplay(i: Integer): string;
begin
  if Labels[i].Kind = LBL_TEXT then Exit(Labels[i].Text);
  if Labels[i].Text <> '' then
    Result := Labels[i].Text + #10 + LabelValue(i)
  else
    Result := LabelValue(i);
end;

procedure LabelLines(const s: string; out Lines: Integer; out Widest: Integer);
var
  i, cur: Integer;
begin
  Lines := 1;
  Widest := 0;
  cur := 0;
  for i := 1 to Length(s) do
    if s[i] = #10 then
    begin
      Widest := Max(Widest, cur);
      cur := 0;
      Inc(Lines);
    end
    else
      Inc(cur);
  Widest := Max(Widest, cur);
end;

{ label i's box in world coordinates (its text keeps its size when zoomed) }
procedure LabelBox(i: Integer; out x, y, w, h: Single);
var
  n, wd: Integer;
begin
  LabelLines(LabelDisplay(i), n, wd);
  wd := Max(wd + 1, 6);
  x := Labels[i].X;
  y := Labels[i].Y;
  w := (wd * 8 + 2 * LABEL_PAD) / Zoom;
  h := (n * LABEL_LINE + 2 * LABEL_PAD - 2) / Zoom;
end;

function LabelAt(wx, wy: Single): Integer;
var
  i: Integer;
  x, y, w, h: Single;
begin
  for i := MAX_LABELS - 1 downto 0 do
    if Labels[i].Active and LayerEditable(Labels[i].Layer) then
    begin
      LabelBox(i, x, y, w, h);
      if (wx >= x) and (wx < x + w) and (wy >= y) and (wy < y + h) then Exit(i);
    end;
  Result := -1;
end;

{ the bucket under px, py on a layer that can be picked, or -1 }
function BucketPick(px, py: Single): Integer;
begin
  Result := simcore.BucketAt(px, py);
  if (Result >= 0) and not LayerEditable(Buckets[Result].Layer) then Result := -1;
end;

{ a part on a hidden or locked layer cannot be picked or changed }
function CellBlocked(gx, gy: Integer): Boolean;
begin
  Result := InGrid(gx, gy) and (Grid[gx, gy].Kind <> ckEmpty) and not LayerEditable(Grid[gx, gy].Layer);
end;

{ in a box selection a label counts when its top-left corner is inside the box }
function SelHasLabel(i: Integer): Boolean;
begin
  Result := False;
  if not Labels[i].Active then Exit;
  case SelKind of
    selLabel: Result := SelL = i;
    selMulti:
      Result := LayerEditable(Labels[i].Layer) and (Labels[i].X >= SelX1 * CELL) and (Labels[i].X < (SelX2 + 1) * CELL) and
        (Labels[i].Y >= SelY1 * CELL) and (Labels[i].Y < (SelY2 + 1) * CELL);
  end;
end;

{ the hopper / silo whose drawing (above its outlet cell) is under wx,wy; False if none }
function StoreAt(wx, wy: Single; out sx, sy: Integer): Boolean;
var
  x, y: Integer;
  x1, y1, x2, y2: Single;
begin
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (Grid[x, y].Kind in [ckHopper, ckSilo]) and LayerEditable(Grid[x, y].Layer) and StoreShape(x, y, x1, y1, x2, y2) and
        (wx >= x1) and (wx <= x2) and (wy >= y1) and (wy <= y2) then
      begin
        sx := x;
        sy := y;
        Exit(True);
      end;
  sx := -1;
  sy := -1;
  Result := False;
end;

function CountSelLabels: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to MAX_LABELS - 1 do
    if SelHasLabel(i) then Inc(Result);
end;

function SelHasCell(x, y: Integer): Boolean;
begin
  case SelKind of
    selCell: Result := (x = SelX) and (y = SelY);
    selMulti: Result := (x >= SelX1) and (x <= SelX2) and (y >= SelY1) and (y <= SelY2) and
      InGrid(x, y) and (Grid[x, y].Kind <> ckEmpty) and LayerEditable(Grid[x, y].Layer);
  else
    Result := False;
  end;
end;

{ a bucket belongs to a box selection when its centre lies inside the box }
function SelHasBucket(i: Integer): Boolean;
var
  cx, cy: Single;
begin
  Result := False;
  if not Buckets[i].Active then Exit;
  case SelKind of
    selBucket: Result := SelB = i;
    selMulti:
      begin
        cx := Buckets[i].X + Buckets[i].W / 2;
        cy := Buckets[i].Y + Buckets[i].H / 2;
        Result := LayerEditable(Buckets[i].Layer) and (cx >= SelX1 * CELL) and (cx < (SelX2 + 1) * CELL) and
          (cy >= SelY1 * CELL) and (cy < (SelY2 + 1) * CELL);
      end;
  end;
end;

{ grid cells covered by bucket i, walls included }
procedure BucketCells(i: Integer; out x1, y1, x2, y2: Integer);
begin
  x1 := EnsureRange(Trunc((Buckets[i].X - WALL_T) / CELL), 0, GW - 1);
  y1 := EnsureRange(Trunc(Buckets[i].Y / CELL), 0, GH - 1);
  x2 := EnsureRange(Trunc((Buckets[i].X + Buckets[i].W + WALL_T) / CELL), 0, GW - 1);
  y2 := EnsureRange(Trunc((Buckets[i].Y + Buckets[i].H + WALL_T) / CELL), 0, GH - 1);
end;

{ the cell rectangle that a copy of the selection spans }
procedure SelRect(out x1, y1, x2, y2: Integer);
begin
  case SelKind of
    selCell: begin x1 := SelX; y1 := SelY; x2 := SelX; y2 := SelY; end;
    selBucket: BucketCells(SelB, x1, y1, x2, y2);
    selLabel:
      begin
        x1 := EnsureRange(Trunc(Labels[SelL].X / CELL), 0, GW - 1);
        y1 := EnsureRange(Trunc(Labels[SelL].Y / CELL), 0, GH - 1);
        x2 := x1;
        y2 := y1;
      end;
  else
    begin x1 := SelX1; y1 := SelY1; x2 := SelX2; y2 := SelY2; end;
  end;
end;

procedure CountSelection(out Parts, Bkts: Integer);
var
  x, y, i: Integer;
begin
  Parts := 0;
  Bkts := 0;
  if SelKind = selNone then Exit;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if SelHasCell(x, y) then Inc(Parts);
  for i := 0 to MAX_BUCKETS - 1 do
    if SelHasBucket(i) then Inc(Bkts);
end;

{ turn a box (cells) into a selection: tightened to what is in it, and
  simplified to a single part / bucket when that is all it holds }
procedure SelectBox(x1, y1, x2, y2: Integer);
var
  x, y, i, nParts, nB, nL, bx1, by1, bx2, by2, lastX, lastY, lastB, lastL: Integer;
  tx1, ty1, tx2, ty2: Integer;
begin
  SelKind := selMulti;
  SelX1 := Min(x1, x2);
  SelY1 := Min(y1, y2);
  SelX2 := Max(x1, x2);
  SelY2 := Max(y1, y2);
  tx1 := GW;
  ty1 := GH;
  tx2 := -1;
  ty2 := -1;
  nParts := 0;
  nB := 0;
  lastX := 0;
  lastY := 0;
  lastB := -1;
  for y := SelY1 to SelY2 do
    for x := SelX1 to SelX2 do
      if SelHasCell(x, y) then
      begin
        Inc(nParts);
        lastX := x;
        lastY := y;
        tx1 := Min(tx1, x);
        ty1 := Min(ty1, y);
        tx2 := Max(tx2, x);
        ty2 := Max(ty2, y);
      end;
  for i := 0 to MAX_BUCKETS - 1 do
    if SelHasBucket(i) then
    begin
      Inc(nB);
      lastB := i;
      BucketCells(i, bx1, by1, bx2, by2);
      tx1 := Min(tx1, bx1);
      ty1 := Min(ty1, by1);
      tx2 := Max(tx2, bx2);
      ty2 := Max(ty2, by2);
    end;
  nL := 0;
  lastL := -1;
  for i := 0 to MAX_LABELS - 1 do
    if SelHasLabel(i) then
    begin
      Inc(nL);
      lastL := i;
      bx1 := EnsureRange(Trunc(Labels[i].X / CELL), 0, GW - 1);
      by1 := EnsureRange(Trunc(Labels[i].Y / CELL), 0, GH - 1);
      tx1 := Min(tx1, bx1);
      ty1 := Min(ty1, by1);
      tx2 := Max(tx2, bx1);
      ty2 := Max(ty2, by1);
    end;
  if nParts + nB + nL = 0 then
    SelKind := selNone
  else if (nParts = 1) and (nB = 0) and (nL = 0) then
  begin
    SelKind := selCell;
    SelX := lastX;
    SelY := lastY;
  end
  else if (nParts = 0) and (nB = 1) and (nL = 0) then
  begin
    SelKind := selBucket;
    SelB := lastB;
  end
  else if (nParts = 0) and (nB = 0) and (nL = 1) then
  begin
    SelKind := selLabel;
    SelL := lastL;
  end
  else
  begin
    SelX1 := tx1;
    SelY1 := ty1;
    SelX2 := tx2;
    SelY2 := ty2;
  end;
end;

{ mouse position in canvas world coordinates (the zoomed / panned view) }
function MWX: Single;
begin
  Result := ViewX + MX / Zoom;
end;

function MWY: Single;
begin
  Result := ViewY + MY / Zoom;
end;

{ drawing coordinates -> renderer coordinates }
function SXf(x: Single): Single; inline;
begin
  if CanvasXf then Result := OX + (x - ViewX) * Zoom else Result := x + OX;
end;

function SYf(y: Single): Single; inline;
begin
  if CanvasXf then Result := OY + (y - ViewY) * Zoom else Result := y + OY;
end;

function SSf(len: Single): Single; inline;
begin
  if CanvasXf then Result := len * Zoom else Result := len;
end;

procedure FillR(x, y, w, h: Single);
var
  rc: TSDL_FRect;
begin
  rc.x := SXf(x); rc.y := SYf(y); rc.w := SSf(w); rc.h := SSf(h);
  SDL_RenderFillRect(Ren, @rc);
end;

procedure RectR(x, y, w, h: Single);
var
  rc: TSDL_FRect;
begin
  rc.x := SXf(x); rc.y := SYf(y); rc.w := SSf(w); rc.h := SSf(h);
  SDL_RenderRect(Ren, @rc);
end;

procedure LineR(x1, y1, x2, y2: Single);
begin
  SDL_RenderLine(Ren, SXf(x1), SYf(y1), SXf(x2), SYf(y2));
end;

procedure TextR(x, y: Single; const s: string);
begin
  { text keeps its size when zoomed; only its position follows the view }
  if s <> '' then SDL_RenderDebugText(Ren, SXf(x), SYf(y), PAnsiChar(s));
end;

procedure SetVtx(i: Integer; x, y: Single; r, g, b, a: Byte);
begin
  GV[i].position.x := SXf(x);
  GV[i].position.y := SYf(y);
  GV[i].color.r := r / 255;
  GV[i].color.g := g / 255;
  GV[i].color.b := b / 255;
  GV[i].color.a := a / 255;
  GV[i].tex_coord.x := 0;
  GV[i].tex_coord.y := 0;
end;

procedure QuadC(x1, y1, x2, y2, x3, y3, x4, y4: Single; r, g, b: Byte; a: Byte = 255);
begin
  SetVtx(0, x1, y1, r, g, b, a);
  SetVtx(1, x2, y2, r, g, b, a);
  SetVtx(2, x3, y3, r, g, b, a);
  SetVtx(3, x4, y4, r, g, b, a);
  SDL_RenderGeometry(Ren, nil, @GV[0], 4, @GIdx[0], 6);
end;

procedure TriC(x1, y1, x2, y2, x3, y3: Single; r, g, b: Byte; a: Byte = 255);
begin
  SetVtx(0, x1, y1, r, g, b, a);
  SetVtx(1, x2, y2, r, g, b, a);
  SetVtx(2, x3, y3, r, g, b, a);
  SDL_RenderGeometry(Ren, nil, @GV[0], 3, nil, 0);
end;

procedure DiscC(cx, cy, rad: Single; r, g, b: Byte; a: Byte = 255);
const
  N = 24;
var
  i: Integer;
begin
  SetVtx(0, cx, cy, r, g, b, a);
  for i := 0 to N do
    SetVtx(i + 1, cx + Cos(i * 2 * Pi / N) * rad, cy + Sin(i * 2 * Pi / N) * rad, r, g, b, a);
  for i := 0 to N - 1 do
  begin
    GI[i * 3] := 0;
    GI[i * 3 + 1] := i + 1;
    GI[i * 3 + 2] := i + 2;
  end;
  SDL_RenderGeometry(Ren, nil, @GV[0], N + 2, @GI[0], N * 3);
end;

procedure RingC(cx, cy, rad: Single; Dashed: Boolean);
const
  N = 48;
var
  i: Integer;
begin
  for i := 0 to N - 1 do
    if (not Dashed) or (i mod 2 = 0) then
      LineR(cx + Cos(i * 2 * Pi / N) * rad, cy + Sin(i * 2 * Pi / N) * rad,
        cx + Cos((i + 1) * 2 * Pi / N) * rad, cy + Sin((i + 1) * 2 * Pi / N) * rad);
end;

{ trapezoid along direction d from the cell centre: width w0 at distance a0, w1 at a1 }
procedure ArmQuad(cx, cy: Single; d: Integer; a0, w0, a1, w1: Single; r, g, b: Byte; a: Byte = 255);
var
  ux, uy, qx, qy: Single;
begin
  ux := DXS[d]; uy := DYS[d];
  qx := -uy; qy := ux;
  QuadC(cx + ux * a0 + qx * w0, cy + uy * a0 + qy * w0,
    cx + ux * a1 + qx * w1, cy + uy * a1 + qy * w1,
    cx + ux * a1 - qx * w1, cy + uy * a1 - qy * w1,
    cx + ux * a0 - qx * w0, cy + uy * a0 - qy * w0, r, g, b, a);
end;

procedure DrawPipeShape(gx, gy: Integer; Grow: Single; r, g, b: Byte);
var
  c: PCell;
  cx, cy, hw, w1: Single;
  d: Integer;
begin
  c := @Grid[gx, gy];
  cx := gx * CELL + HALF;
  cy := gy * CELL + HALF;
  hw := HWOf(c^.Dia) + Grow;
  SetCol(r, g, b);
  FillR(cx - hw, cy - hw, 2 * hw, 2 * hw);
  for d := 0 to 3 do
  begin
    if c^.ECon[d] then
      w1 := (HWOf(c^.Dia) + HWOf(Grid[gx + DXS[d], gy + DYS[d]].Dia)) * 0.5 + Grow
    else if d = c^.Mouth then
      w1 := hw
    else
      Continue;
    ArmQuad(cx, cy, d, 0, hw, HALF, w1, r, g, b);
  end;
end;

procedure PressureColor(P: Single; out r, g, b: Byte);
var
  t: Single;
begin
  t := fclamp(P / 60, -1, 1);
  if t >= 0 then
  begin
    r := Round(30 + t * 200);
    g := Round(32 + t * 30);
    b := Round(40 - t * 10);
  end
  else
  begin
    r := Round(30 + t * 10);
    g := Round(32 - t * 60);
    b := Round(40 - t * 200);
  end;
end;

procedure DrawPipes;
var
  x, y, d: Integer;
  c: PCell;
  r, g, b: Byte;
  cx, cy, hw: Single;
begin
  { outer walls }
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @Grid[x, y];
      if (c^.Kind = ckEmpty) or not LayerShown(c^.Layer) then Continue;
      DrawPipeShape(x, y, 2.5, Th.PipeWall.R, Th.PipeWall.G, Th.PipeWall.B);
      cx := x * CELL + HALF;
      cy := y * CELL + HALF;
      hw := HWOf(c^.Dia);
      if (c^.Kind = ckPipe) and (ConnCount(x, y) >= 3) then
      begin
        SetC(Th.PipeHub);             { tee / cross hub }
        FillR(cx - hw - 4, cy - hw - 4, 2 * hw + 8, 2 * hw + 8);
      end;
      if c^.Mouth >= 0 then          { flange at an open end }
      begin
        d := c^.Mouth;
        ArmQuad(cx, cy, d, HALF - 3, hw + 4.5, HALF, hw + 4.5, Th.PipeFlange.R, Th.PipeFlange.G, Th.PipeFlange.B);
      end;
    end;
  { bores }
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @Grid[x, y];
      if (c^.Kind = ckEmpty) or not LayerShown(c^.Layer) then Continue;
      if ShowPressure then
        PressureColor(c^.P, r, g, b)
      else
      begin
        r := Th.PipeBore.R; g := Th.PipeBore.G; b := Th.PipeBore.B;
      end;
      DrawPipeShape(x, y, 0, r, g, b);
    end;
end;

procedure DrawParticles;
var
  i: Integer;
  m: TMat;
  s: Single;
  rc: PSDL_FRect;
begin
  for m := Low(TMat) to High(TMat) do
    PCount[m] := 0;
  for i := 0 to NPart - 1 do
  begin
    m := Parts[i].Mat;
    if (m = mAir) and not ShowAir then Continue;
    s := MatP[m].Size;
    rc := @PRects[m][PCount[m]];
    rc^.x := SXf(Parts[i].X - s / 2);
    rc^.y := SYf(Parts[i].Y - s / 2);
    rc^.w := SSf(s);
    rc^.h := SSf(s);
    Inc(PCount[m]);
  end;
  for m := Low(TMat) to High(TMat) do
    if PCount[m] > 0 then
    begin
      { air and fluff are pale: their colour follows the theme so they stay visible }
      case m of
        mAir: SetC(Th.Air, Th.AirAlpha);
        mFluff: SetC(Th.Fluff, MatP[m].A);
      else
        SetCol(MatP[m].R, MatP[m].G, MatP[m].B, MatP[m].A);
      end;
      SDL_RenderFillRects(Ren, @PRects[m][0], PCount[m]);
    end;
end;

procedure DrawTank(gx, gy: Integer);
const
  Order: array[0..3] of TMat = (mSand, mWater, mOil, mFluff);
var
  c: PCell;
  x, y, w, h, yy, lh: Single;
  i: Integer;
  m: TMat;
begin
  c := @Grid[gx, gy];
  w := 28; h := 40;
  x := gx * CELL + HALF - w / 2;
  y := gy * CELL + HALF + 10 - h;
  SetC(Th.TankBg);
  FillR(x, y, w, h);
  yy := y + h - 2;
  for i := 0 to 3 do
  begin
    m := Order[i];
    lh := (h - 4) * c^.Stock[m] / (2 * STOCK_MAX);
    if yy - lh < y + 2 then lh := yy - (y + 2);
    if lh > 0 then
    begin
      if m = mFluff then SetC(Th.Fluff) else SetCol(MatP[m].R, MatP[m].G, MatP[m].B);
      FillR(x + 2, yy - lh, w - 4, lh);
      yy := yy - lh;
    end;
  end;
  if c^.AirPct > 0 then
  begin
    SetC(Th.Air, 200);
    for i := 0 to Round(c^.AirPct / 20) do
      FillR(x + 4 + (i * 7) mod (w - 8), y + 4 + (i * 5) mod 8, 2, 2);
  end;
  SetC(Th.TankRim);
  RectR(x, y, w, h);
  RectR(x + 1, y, w - 2, 1);
end;

{ a virtual feeder: the mix ratio fills the box, a dashed violet rim, an infinity sign }
procedure DrawVFeeder(gx, gy: Integer);
const
  Order: array[0..3] of TMat = (mSand, mWater, mOil, mFluff);
var
  c: PCell;
  x, y, w, h, yy, lh, tot: Single;
  i: Integer;
  m: TMat;
begin
  c := @Grid[gx, gy];
  w := 28; h := 40;
  x := gx * CELL + HALF - w / 2;
  y := gy * CELL + HALF + 10 - h;
  SetC(Th.TankBg);
  FillR(x, y, w, h);
  tot := 0;
  for m := mWater to mSand do tot := tot + c^.Stock[m];
  yy := y + h - 2;
  if tot > 0 then
    for i := 0 to 3 do
    begin
      m := Order[i];
      lh := (h - 14) * c^.Stock[m] / tot;
      if lh > 0 then
      begin
        if m = mFluff then SetC(Th.Fluff, 170) else SetCol(MatP[m].R, MatP[m].G, MatP[m].B, 170);
        FillR(x + 2, yy - lh, w - 4, lh);
        yy := yy - lh;
      end;
    end;
  SetCol(170, 110, 240);
  RectR(x, y, w, h);
  RectR(x + 1, y + 1, w - 2, h - 2);
  RingC(x + w / 2 - 3.5, y + 6, 3.5, False);
  RingC(x + w / 2 + 3.5, y + 6, 3.5, False);
end;
{ colour of a store's contents: the materials mixed by amount }
procedure StoreColor(const c: TCell; out r, g, b: Byte);
var
  m: TMat;
  t, fr, fg, fb: Single;
begin
  t := StoreTotal(c);
  if t <= 0 then
  begin
    r := 90; g := 90; b := 90;
    Exit;
  end;
  fr := 0; fg := 0; fb := 0;
  for m := mWater to mSand do
  begin
    if m = mFluff then
    begin
      fr := fr + Th.Fluff.R * c.Stock[m]; fg := fg + Th.Fluff.G * c.Stock[m]; fb := fb + Th.Fluff.B * c.Stock[m];
    end
    else
    begin
      fr := fr + MatP[m].R * c.Stock[m]; fg := fg + MatP[m].G * c.Stock[m]; fb := fb + MatP[m].B * c.Stock[m];
    end;
  end;
  r := Round(fr / t); g := Round(fg / t); b := Round(fb / t);
end;

{ hopper: a funnel above its outlet cell; the fill rises from the narrow end }
procedure DrawHopper(gx, gy: Integer);
var
  c: PCell;
  cx, top, bot, wt, wb, f, ly, wl: Single;
  r, g, b: Byte;
begin
  c := @Grid[gx, gy];
  cx := gx * CELL + HALF;
  top := gy * CELL - 2 * CELL + 4;
  bot := gy * CELL + 6;
  wt := 30;
  wb := HWOf(c^.Dia) + 2;
  { inside }
  QuadC(cx - wt, top, cx + wt, top, cx + wb, bot, cx - wb, bot, Th.PipeBore.R, Th.PipeBore.G, Th.PipeBore.B, 230);
  f := fmin(1, StoreTotal(c^) / HOPPER_CAP);
  if f > 0 then
  begin
    ly := bot - (bot - top) * f;
    wl := wb + (wt - wb) * f;
    StoreColor(c^, r, g, b);
    QuadC(cx - wl, ly, cx + wl, ly, cx + wb, bot, cx - wb, bot, r, g, b);
  end;
  { walls and rim }
  SetC(Th.TankRim);
  LineR(cx - wt, top, cx - wb, bot);
  LineR(cx + wt, top, cx + wb, bot);
  LineR(cx - wt + 1, top, cx - wb + 1, bot);
  LineR(cx + wt - 1, top, cx + wb - 1, bot);
  FillR(cx - wt - 3, top - 2, 7, 3);
  FillR(cx + wt - 4, top - 2, 7, 3);
end;

{ silo: a tall bin with a cone into its outlet cell and an opening in the roof }
procedure DrawSilo(gx, gy: Integer);
const
  Order: array[0..3] of TMat = (mSand, mWater, mOil, mFluff);
var
  c: PCell;
  cx, top, coneY, bot, hw, x1, x2, yy, lh, h: Single;
  i: Integer;
  m: TMat;
  s: string;
  r_, g_, b_: Byte;
begin
  c := @Grid[gx, gy];
  cx := gx * CELL + HALF;
  top := gy * CELL - 3 * CELL;
  coneY := gy * CELL - 10;
  bot := gy * CELL + 8;
  hw := HWOf(c^.Dia) + 2;
  x1 := cx - 22;
  x2 := cx + 22;
  SetC(Th.TankBg);
  FillR(x1, top, 44, coneY - top);
  QuadC(x1, coneY, x2, coneY, cx + hw, bot, cx - hw, bot, Th.TankBg.R, Th.TankBg.G, Th.TankBg.B);
  { contents in layers, heaviest at the bottom (the cone counts as the first part) }
  h := coneY - top - 4;
  yy := coneY;
  if StoreTotal(c^) > 0 then
  begin
    StoreColor(c^, r_, g_, b_);
    QuadC(x1 + 2, coneY, x2 - 2, coneY, cx + hw - 1, bot - 1, cx - hw + 1, bot - 1, r_, g_, b_);
  end;
  for i := 0 to 3 do
  begin
    m := Order[i];
    lh := h * c^.Stock[m] / SILO_CAP;
    if yy - lh < top + 4 then lh := yy - (top + 4);
    if lh > 0 then
    begin
      if m = mFluff then SetC(Th.Fluff) else SetCol(MatP[m].R, MatP[m].G, MatP[m].B);
      FillR(x1 + 2, yy - lh, 40, lh);
      yy := yy - lh;
    end;
  end;
  { shell, roof with its opening, cone }
  SetC(Th.TankRim);
  LineR(x1, top, x1, coneY);
  LineR(x2, top, x2, coneY);
  LineR(x1, coneY, cx - hw, bot);
  LineR(x2, coneY, cx + hw, bot);
  { the whole roof is open: only short rims at the corners }
  FillR(x1 - 2, top - 3, 5, 3);
  FillR(x2 - 3, top - 3, 5, 3);
  SetC(Th.Text);
  s := Format('%.0f%%', [100 * StoreTotal(c^) / SILO_CAP]);
  TextR(cx - Length(s) * 4, top + 6, s);
end;

procedure DrawDevice(gx, gy: Integer);
var
  c: PCell;
  cx, cy, hw, ang, ux, uy, qx, qy, s: Single;
  i, d: Integer;
  r, g, b: Byte;
begin
  c := @Grid[gx, gy];
  cx := gx * CELL + HALF;
  cy := gy * CELL + HALF;
  hw := HWOf(c^.Dia);
  case c^.Kind of
    ckSource:
      DrawTank(gx, gy);
    ckVFeeder:
      DrawVFeeder(gx, gy);
    ckHopper:
      DrawHopper(gx, gy);
    ckSilo:
      DrawSilo(gx, gy);
    ckBlower:
      begin
        DiscC(cx, cy, 11, 140, 152, 170);
        DiscC(cx, cy, 9, 40, 48, 62);
        SetCol(150, 215, 255);
        for i := 0 to 2 do
        begin
          ang := c^.Spin + i * 2 * Pi / 3;
          LineR(cx, cy, cx + Cos(ang) * 8, cy + Sin(ang) * 8);
          LineR(cx + 0.5, cy + 0.5, cx + Cos(ang + 0.25) * 7, cy + Sin(ang + 0.25) * 7);
        end;
        d := c^.Dir;
        ux := DXS[d]; uy := DYS[d]; qx := -uy; qy := ux;
        TriC(cx + ux * 12, cy + uy * 12, cx + ux * 7 + qx * 4, cy + uy * 7 + qy * 4,
          cx + ux * 7 - qx * 4, cy + uy * 7 - qy * 4, 120, 230, 255);
      end;
    ckSuction:
      if c^.Dir >= 0 then
        ArmQuad(cx, cy, c^.Dir, -2, hw + 1, HALF, hw + 6, 165, 105, 225, 220);
    ckNozzle:
      if c^.Dir >= 0 then
        ArmQuad(cx, cy, c^.Dir, -2, hw + 5, HALF, hw + 0.5, 240, 140, 50, 220);
    ckDrop:
      if c^.Dir >= 0 then
      begin
        d := c^.Dir;
        ArmQuad(cx, cy, d, -4, hw + 4, 2, hw + 4, 120, 130, 80);
        s := hw * (1 - c^.Strength / 100);  { gate plates closing from both sides }
        ux := DXS[d]; uy := DYS[d]; qx := -uy; qy := ux;
        SetCol(240, 215, 70);
        QuadC(cx + ux * (HALF - 3) + qx * hw, cy + uy * (HALF - 3) + qy * hw,
          cx + ux * HALF + qx * hw, cy + uy * HALF + qy * hw,
          cx + ux * HALF + qx * (hw - s), cy + uy * HALF + qy * (hw - s),
          cx + ux * (HALF - 3) + qx * (hw - s), cy + uy * (HALF - 3) + qy * (hw - s), 240, 215, 70);
        QuadC(cx + ux * (HALF - 3) - qx * hw, cy + uy * (HALF - 3) - qy * hw,
          cx + ux * HALF - qx * hw, cy + uy * HALF - qy * hw,
          cx + ux * HALF - qx * (hw - s), cy + uy * HALF - qy * (hw - s),
          cx + ux * (HALF - 3) - qx * (hw - s), cy + uy * (HALF - 3) - qy * (hw - s), 240, 215, 70);
      end;
    ckCheck:
      begin
        d := c^.Dir;
        ux := DXS[d]; uy := DYS[d]; qx := -uy; qy := ux;
        s := fmax(3, hw);
        TriC(cx + ux * (s + 2), cy + uy * (s + 2), cx - ux * s + qx * s, cy - uy * s + qy * s,
          cx - ux * s - qx * s, cy - uy * s - qy * s, 90, 220, 110, 230);
      end;
    ckValve2:
      begin
        if Connected(gx, gy, 0) or Connected(gx, gy, 2) then d := 0 else d := 1;
        ux := DXS[d]; uy := DYS[d]; qx := -uy; qy := ux;
        s := hw + 3;
        if c^.Open then begin r := 80; g := 210; b := 100; end
        else begin r := 235; g := 70; b := 60; end;
        TriC(cx, cy, cx - ux * s + qx * s, cy - uy * s + qy * s, cx - ux * s - qx * s, cy - uy * s - qy * s, r, g, b);
        TriC(cx, cy, cx + ux * s + qx * s, cy + uy * s + qy * s, cx + ux * s - qx * s, cy + uy * s - qy * s, r, g, b);
        SetC(Th.Text);
        if c^.Open then
          LineR(cx, cy, cx - qx * (s + 3), cy - qy * (s + 3))
        else
          LineR(cx - ux * (s + 1) - qx * (s + 3), cy - uy * (s + 1) - qy * (s + 3),
            cx + ux * (s + 1) - qx * (s + 3), cy + uy * (s + 1) - qy * (s + 3));
      end;
    ckValve3:
      begin
        DiscC(cx, cy, hw + 2, 150, 160, 180);
        if c^.Dir >= 0 then
          ArmQuad(cx, cy, c^.Dir, hw + 1, hw + 2, hw + 4, hw + 2, 235, 70, 60)
        else
          DiscC(cx, cy, 3, 80, 210, 100);
      end;
    ckValve4:
      begin
        { square body so it reads differently from the round 3-way valve }
        SetCol(150, 160, 180);
        FillR(cx - hw - 3, cy - hw - 3, 2 * hw + 6, 2 * hw + 6);
        SetCol(60, 66, 80);
        RectR(cx - hw - 3, cy - hw - 3, 2 * hw + 6, 2 * hw + 6);
        for d := 0 to 3 do
          if (c^.Closed and (1 shl d)) <> 0 then
            ArmQuad(cx, cy, d, hw + 2, hw + 3, hw + 5, hw + 3, 235, 70, 60);
        if c^.Closed = 0 then
          DiscC(cx, cy, 3, 80, 210, 100)
        else
          DiscC(cx, cy, 2, 60, 66, 80);
      end;
  end;
end;

procedure DrawBucketBack(i: Integer);
begin
  with Buckets[i] do
  begin
    SetC(Th.BucketBack, 200);
    FillR(X, Y, W, H);
  end;
end;

procedure DrawBucketFront(i: Integer);
var
  fill, ly: Single;
  s: string;
begin
  with Buckets[i] do
  begin
    SetC(Th.BucketWall);
    FillR(X - WALL_T, Y, WALL_T, H + WALL_T);
    FillR(X + W, Y, WALL_T, H + WALL_T);
    FillR(X - WALL_T, Y + H, W + 2 * WALL_T, WALL_T);
    SetC(Th.BucketRim);
    FillR(X - WALL_T - 2, Y - 2, WALL_T + 4, 3);
    FillR(X + W - 2, Y - 2, WALL_T + 4, 3);
    fill := BucketFill(i);
    ly := Y + H - H * fmin(1, fill);
    SetC(Th.Text, 70);
    LineR(X, ly, X + W, ly);
    if Flash > 0 then
      SetC(Th.StatusErr)
    else
      SetC(Th.BucketText);
    s := Format('Bucket %d  %3.0f%%', [i + 1, fmin(100, fill * 100)]);
    TextR(X + W / 2 - Length(s) * 4, Y - 24, s);
    if (Flash > 0) and (Frac(Flash * 3) < 0.6) then
    begin
      SetC(Th.StatusErr);
      s := Format('OVERFLOW! %d', [Spilled]);
      TextR(X + W / 2 - Length(s) * 4, Y - 13, s);
    end
    else if Spilled > 0 then
    begin
      SetC(Th.StatusErr, 170);
      s := Format('spilled %d', [Spilled]);
      TextR(X + W / 2 - Length(s) * 4, Y - 13, s);
    end;
    if SelHasBucket(i) then
    begin
      SetC(Th.Select);
      RectR(X - WALL_T - 3, Y - 4, W + 2 * WALL_T + 6, H + WALL_T + 7);
    end;
  end;
end;

function IsSinglePart(const B: TBlock): Boolean;
begin
  Result := (B.Parts = 1) and (Length(B.Bkts) = 0) and (B.W = 1) and (B.H = 1);
end;

{ outline of where block B would land with its top-left corner at cell gx,gy }
procedure DrawBlockGhost(const B: TBlock; gx, gy: Integer; const Verb: string);
var
  s: string;
  ox, oy: Single;
  x, y, i: Integer;
begin
  ox := gx * CELL;
  oy := gy * CELL;
  SetC(Th.Paste, 30);
  FillR(ox, oy, B.W * CELL, B.H * CELL);
  SetC(Th.Paste);
  RectR(ox - 1, oy - 1, B.W * CELL + 2, B.H * CELL + 2);
  for y := 0 to B.H - 1 do
    for x := 0 to B.W - 1 do
      if B.Cells[y * B.W + x].Kind <> ckEmpty then
        RectR(ox + x * CELL + 3, oy + y * CELL + 3, CELL - 6, CELL - 6);
  for i := 0 to High(B.Bkts) do
    with B.Bkts[i] do
    begin
      RectR(ox + DX - WALL_T, oy + DY, W + 2 * WALL_T, H + WALL_T);
      RectR(ox + DX, oy + DY, W, H);
    end;
  if IsSinglePart(B) then
  begin
    s := Verb + ' ' + KindNames[B.Cells[0].Kind];
    if InGrid(gx, gy) and (Grid[gx, gy].Kind <> ckEmpty) and not SelHasCell(gx, gy) then
      s := s + ' (insert)';
  end
  else
    s := Format('%s %d parts, %d buckets', [Verb, B.Parts, Length(B.Bkts)]);
  if Length(B.Lbls) > 0 then s := s + Format(', %d labels', [Length(B.Lbls)]);
  for i := 0 to High(B.Lbls) do
    RectR(ox + B.Lbls[i].DX, oy + B.Lbls[i].DY, 40, 12);
  { the caption sits next to the mouse, unzoomed }
  CanvasXf := False;
  SetC(Th.OverlayBg, 210);
  FillR(MX + 12, MY + 10, Length(s) * 8 + 6, 12);
  SetC(Th.Paste);
  TextR(MX + 15, MY + 12, s);
  CanvasXf := True;
end;

{ ---------------------------------------------------------------- labels }

const
  LabelColorNames: array[0..5] of string = ('Theme', 'Blue', 'Green', 'Amber', 'Red', 'White');

procedure LabelRGB(c: Integer; out r, g, b: Byte);
begin
  case c of
    1: begin r := 90; g := 160; b := 255; end;
    2: begin r := 80; g := 210; b := 120; end;
    3: begin r := 240; g := 175; b := 50; end;
    4: begin r := 240; g := 90; b := 80; end;
    5: begin r := 240; g := 240; b := 245; end;
  else
    begin r := Th.Text.R; g := Th.Text.G; b := Th.Text.B; end;
  end;
end;

procedure DrawLabels;
var
  i, k, n, wd, titleLines: Integer;
  ux, uy, w, h: Single;
  s, line, caret: string;
  editing: Boolean;
  r, g, b: Byte;
begin
  CanvasXf := False;   { drawn at screen size, anchored to the zoomed canvas }
  if (SDL_GetTicksNS div 500000000) mod 2 = 0 then caret := '_' else caret := '';
  for i := 0 to MAX_LABELS - 1 do
  begin
    if (not Labels[i].Active) or not LayerShown(Labels[i].Layer) then Continue;
    editing := EditLabel = i;
    { typing into the caption shows a caret at its end }
    if editing and (EditField = 0) then
    begin
      if Labels[i].Kind = LBL_TEXT then s := Labels[i].Text + caret
      else s := Labels[i].Text + caret + #10 + LabelValue(i);
    end
    else
      s := LabelDisplay(i);
    { the title lines: the first line of a text label, the caption of a date / time label }
    if Labels[i].Kind = LBL_TEXT then titleLines := 1
    else if Labels[i].Text = '' then titleLines := 0
    else LabelLines(Labels[i].Text, titleLines, wd);
    LabelLines(s, n, wd);
    wd := Max(wd + 1, 6);
    ux := (Labels[i].X - ViewX) * Zoom;
    uy := (Labels[i].Y - ViewY) * Zoom;
    w := wd * 8 + 2 * LABEL_PAD;
    h := n * LABEL_LINE + 2 * LABEL_PAD - 2;
    if not Labels[i].NoBox then
    begin
      SetC(Th.OverlayBg, 225);
      FillR(ux, uy, w, h);
      SetC(Th.MenuBorder);
      RectR(ux, uy, w, h);
    end;
    if editing then SetC(Th.Paste) else SetC(Th.Select);
    if SelHasLabel(i) or editing then
    begin
      RectR(ux, uy, w, h);
      RectR(ux - 1, uy - 1, w + 2, h + 2);
    end;
    if (Labels[i].Kind = LBL_TEXT) and (Labels[i].Text = '') and not editing then
    begin
      SetC(Th.TextDim);
      TextR(ux + LABEL_PAD, uy + LABEL_PAD, '(empty)');
    end;
    LabelRGB(Labels[i].Color, r, g, b);
    line := '';
    k := 0;
    for n := 1 to Length(s) + 1 do
      if (n > Length(s)) or (s[n] = #10) then
      begin
        { title lines in the accent colour unless the label has its own colour }
        if (k < titleLines) and (Labels[i].Color = 0) then SetC(Th.Title) else SetCol(r, g, b);
        TextR(ux + LABEL_PAD, uy + LABEL_PAD + k * LABEL_LINE, line);
        line := '';
        Inc(k);
      end
      else
        line := line + s[n];
  end;
  CanvasXf := True;
end;

{ ---------------------------------------------------------------- frames }

const
  FRAME_TAB_H = 16;     { title tab height (canvas pixels) }
  FRAME_EDGE = 5;       { how close to the outline a click grabs the frame }
  FRAME_HANDLE = 10;    { resize handle in the bottom-right corner }

function SnapCell(v: Single): Single;
begin
  Result := Round(v / CELL) * CELL;
end;

procedure FrameRGB(c: Integer; out r, g, b: Byte);
begin
  if c = 0 then
  begin
    r := Th.Title.R; g := Th.Title.G; b := Th.Title.B;
  end
  else
    LabelRGB(c, r, g, b);
end;

{ the frame whose title tab or outline (Part 0, to move it) or corner handle
  (Part 1, to resize it) is under wx, wy; the inside stays free for the parts }
function FrameAt(wx, wy: Single; out Part: Integer): Integer;
var
  i: Integer;
  tw: Single;
begin
  Part := 0;
  for i := MAX_FRAMES - 1 downto 0 do
    with Frames[i] do
      if Active and LayerEditable(Layer) then
      begin
        if (wx >= X + W - FRAME_HANDLE) and (wx <= X + W + 3) and (wy >= Y + H - FRAME_HANDLE) and
          (wy <= Y + H + 3) then
        begin
          Part := 1;
          Exit(i);
        end;
        tw := fmax(48, (Length(Title) * 8 + 12) / Zoom);
        if (wx >= X) and (wx <= X + tw) and (wy >= Y) and (wy <= Y + FRAME_TAB_H) then Exit(i);
        if (wx >= X - FRAME_EDGE) and (wx <= X + W + FRAME_EDGE) and (wy >= Y - FRAME_EDGE) and
          (wy <= Y + H + FRAME_EDGE) and not ((wx > X + FRAME_EDGE) and (wx < X + W - FRAME_EDGE) and
          (wy > Y + FRAME_EDGE) and (wy < Y + H - FRAME_EDGE)) then Exit(i);
      end;
  Result := -1;
end;

{ the cells a frame covers }
procedure FrameCells(i: Integer; out x1, y1, x2, y2: Integer);
begin
  x1 := EnsureRange(Round(Frames[i].X / CELL), 0, GW - 1);
  y1 := EnsureRange(Round(Frames[i].Y / CELL), 0, GH - 1);
  x2 := EnsureRange(Round((Frames[i].X + Frames[i].W) / CELL) - 1, x1, GW - 1);
  y2 := EnsureRange(Round((Frames[i].Y + Frames[i].H) / CELL) - 1, y1, GH - 1);
end;

procedure DashedRect(x, y, w, h, dash: Single);
var
  t: Single;
begin
  t := 0;
  while t < w do
  begin
    LineR(x + t, y, x + fmin(t + dash, w), y);
    LineR(x + t, y + h, x + fmin(t + dash, w), y + h);
    t := t + dash * 2;
  end;
  t := 0;
  while t < h do
  begin
    LineR(x, y + t, x, y + fmin(t + dash, h));
    LineR(x + w, y + t, x + w, y + fmin(t + dash, h));
    t := t + dash * 2;
  end;
end;

{ one frame outline at x, y, w, h (also used for the ghost while placing / moving) }
procedure DrawFrameShape(i: Integer; x, y, w, h: Single; Ghost: Boolean);
var
  r, g, b: Byte;
  tw: Single;
  s, caret: string;
  selected: Boolean;
begin
  FrameRGB(Frames[i].Color, r, g, b);
  selected := (SelKind = selFrame) and (SelFr = i);
  if Frames[i].Fill and not Ghost then
  begin
    SetCol(r, g, b, 22);
    FillR(x, y, w, h);
  end;
  if Ghost then SetC(Th.Paste) else if selected then SetC(Th.Select) else SetCol(r, g, b, 210);
  if Frames[i].Dashed then
    DashedRect(x, y, w, h, 8)
  else
  begin
    RectR(x, y, w, h);
    RectR(x + 1, y + 1, w - 2, h - 2);
  end;
  if Ghost then Exit;
  { title tab: text keeps its size when zoomed, the tab follows the text }
  s := Frames[i].Title;
  caret := '';
  if (EditFrame = i) and ((SDL_GetTicksNS div 500000000) mod 2 = 0) then caret := '_';
  tw := fmax(48, (Length(s + caret) * 8 + 12) / Zoom);
  if selected then SetC(Th.Select) else SetCol(r, g, b, 230);
  FillR(x, y, tw, FRAME_TAB_H / Zoom);
  if Th.Light or (Frames[i].Color in [3, 5]) then SetCol(20, 22, 28) else SetCol(250, 250, 252);
  if selected then SetCol(20, 22, 28);
  TextR(x + 6 / Zoom, y + 4 / Zoom, s + caret);
  if selected then
  begin
    { the resize handle }
    SetC(Th.Select);
    FillR(x + w - 8, y + h - 8, 8, 8);
  end;
end;

procedure DrawFrames;
var
  i: Integer;
begin
  for i := 0 to MAX_FRAMES - 1 do
    if Frames[i].Active and LayerShown(Frames[i].Layer) then
      DrawFrameShape(i, Frames[i].X, Frames[i].Y, Frames[i].W, Frames[i].H, False);
end;

{ ---------------------------------------------------------------- links }

const
  LINK_H = 18;     { link button height on screen }

var
  PendingPage: Integer = -1;    { a page to go to once the frame is drawn (from the frame popup) }

{ what a link button shows: an arrow for a page, a "?" for a frame popup }
function LinkText(i: Integer): string;
begin
  if Links[i].ToPopup then Result := '? ' + Links[i].Caption
  else Result := '> ' + Links[i].Caption;
end;

{ link i's button in world coordinates (it keeps its size on screen when zoomed) }
procedure LinkBox(i: Integer; out x, y, w, h: Single);
begin
  x := Links[i].X;
  y := Links[i].Y;
  w := (Length(LinkText(i)) * 8 + 14) / Zoom;
  h := LINK_H / Zoom;
end;

{ the link under wx, wy on a layer that can be picked, or -1 }
function LinkAt(wx, wy: Single): Integer;
var
  i: Integer;
  x, y, w, h: Single;
begin
  for i := MAX_LINKS - 1 downto 0 do
    if Links[i].Active and LayerEditable(Links[i].Layer) then
    begin
      LinkBox(i, x, y, w, h);
      if (wx >= x) and (wx < x + w) and (wy >= y) and (wy < y + h) then Exit(i);
    end;
  Result := -1;
end;

{ where a link goes, for the status line and the properties }
function LinkTargetName(i: Integer): string;
begin
  if Links[i].ToPopup then
  begin
    if (Links[i].Target >= 0) and (Links[i].Target < MAX_POPUPS) and Popups[Links[i].Target].Active then
      Result := Format('popup %d: %s', [Links[i].Target + 1, Popups[Links[i].Target].Title])
    else
      Result := 'no popup';
  end
  else if (Links[i].Target >= 0) and (Links[i].Target < PageCount) then
    Result := Format('page %d: %s', [Links[i].Target + 1, PageName(Links[i].Target)])
  else
    Result := 'no page';
end;

procedure DrawLinks;
var
  i: Integer;
  ux, uy, w: Single;
  r, g, b: Byte;
  hot: Boolean;
begin
  CanvasXf := False;   { drawn at screen size, anchored to the zoomed canvas }
  for i := 0 to MAX_LINKS - 1 do
  begin
    if (not Links[i].Active) or not LayerShown(Links[i].Layer) then Continue;
    ux := (Links[i].X - ViewX) * Zoom;
    uy := (Links[i].Y - ViewY) * Zoom;
    w := Length(LinkText(i)) * 8 + 14;
    hot := (Tool = tSelect) and (MX >= ux) and (MX < ux + w) and (MY >= uy) and (MY < uy + LINK_H) and
      LayerEditable(Links[i].Layer);
    SetCol(0, 0, 0, 70);
    FillR(ux + 2, uy + 2, w, LINK_H);
    if Links[i].Color = 0 then
    begin
      if hot then SetC(Th.BtnHot) else SetC(Th.BtnBg);
    end
    else
    begin
      LabelRGB(Links[i].Color, r, g, b);
      if hot then SetCol(Min(255, r + 30), Min(255, g + 30), Min(255, b + 30)) else SetCol(r, g, b);
    end;
    FillR(ux, uy, w, LINK_H);
    SetC(Th.BtnBorder);
    RectR(ux, uy, w, LINK_H);
    if Links[i].Color = 0 then SetC(Th.BtnText)
    else if Links[i].Color in [3, 5] then SetCol(20, 22, 28)
    else SetCol(250, 250, 252);
    TextR(ux + 7, uy + 5, LinkText(i));
    if hot then
    begin
      { underline: it is a link }
      LineR(ux + 7, uy + LINK_H - 3, ux + w - 7, uy + LINK_H - 3);
    end;
  end;
  CanvasXf := True;
end;

{ the selection outline around link i }
procedure OutlineLink(i: Integer);
var
  ux, uy, w: Single;
begin
  CanvasXf := False;
  ux := (Links[i].X - ViewX) * Zoom;
  uy := (Links[i].Y - ViewY) * Zoom;
  w := Length(LinkText(i)) * 8 + 14;
  SetC(Th.Select);
  RectR(ux - 2, uy - 2, w + 4, LINK_H + 4);
  RectR(ux - 3, uy - 3, w + 6, LINK_H + 6);
  CanvasXf := True;
end;

{ ---------------------------------------------------------------- frame popup (over the canvas) }

const
  FP_W = 400;

{ the open frame popup's box in canvas-area screen coordinates }
procedure FramePopupBox(out x, y, w, h: Single);
var
  n, wd: Integer;
begin
  w := FP_W;
  n := 1;
  if ShownPopup >= 0 then LabelLines(Popups[ShownPopup].Text, n, wd);
  h := 26 + n * 12 + 16 + 30;
  x := Round((CANVAS_W - w) / 2);
  y := Round(fmax(30, (CANVAS_H - h) / 2 - 60));
end;

function InFramePopup: Boolean;
var
  x, y, w, h: Single;
begin
  Result := False;
  if ShownPopup < 0 then Exit;
  FramePopupBox(x, y, w, h);
  Result := (MX >= x) and (MX < x + w) and (MY >= y) and (MY < y + h);
end;

{ a frame popup: a small window with a title, text, a "go to page" button and a close button.
  Clicks reach it through FPClick (set by MouseDown). }
procedure DrawFramePopup;
var
  x, y, w, h, bx, by, bw: Single;
  r, g, b: Byte;
  P: ^TPopup;
  clicked, hot: Boolean;
  k, n: Integer;
  line, s: string;

  function Btn(px, py, pw: Single; const lbl: string; Strong: Boolean): Boolean;
  begin
    hot := (MX >= px) and (MX < px + pw) and (MY >= py) and (MY < py + 20);
    if Strong then SetCol(r, g, b) else if hot then SetC(Th.BtnHot) else SetC(Th.BtnBg);
    if Strong and hot then SetCol(Min(255, r + 30), Min(255, g + 30), Min(255, b + 30));
    FillR(px, py, pw, 20);
    SetC(Th.BtnBorder);
    RectR(px, py, pw, 20);
    if Strong then SetCol(250, 250, 252) else SetC(Th.BtnText);
    TextR(Round(px + (pw - Length(lbl) * 8) / 2), py + 6, lbl);
    Result := clicked and hot;
  end;

begin
  if (ShownPopup < 0) or (ShownPopup >= MAX_POPUPS) or not Popups[ShownPopup].Active then
  begin
    ShownPopup := -1;
    FPClick := False;
    Exit;
  end;
  clicked := FPClick;
  FPClick := False;
  P := @Popups[ShownPopup];
  FramePopupBox(x, y, w, h);
  if P^.Color = 0 then
  begin
    r := Th.Title.R; g := Th.Title.G; b := Th.Title.B;
  end
  else
    LabelRGB(P^.Color, r, g, b);
  if (P^.Color = 5) or (P^.Color = 3) then
  begin
    { light colours: darker so white text stays readable }
    r := r * 2 div 3; g := g * 2 div 3; b := b * 2 div 3;
  end;
  { dim the canvas behind it }
  SetCol(0, 0, 0, 90);
  FillR(0, 0, CANVAS_W, CANVAS_H);
  SetCol(0, 0, 0, 100);
  FillR(x + 6, y + 6, w, h);
  SetC(Th.PanelBg);
  FillR(x, y, w, h);
  SetCol(r, g, b);
  RectR(x, y, w, h);
  RectR(x + 1, y + 1, w - 2, h - 2);
  FillR(x, y, w, 22);
  SetCol(250, 250, 252);
  TextR(x + 10, y + 7, Copy(P^.Title, 1, 44));
  { close box }
  bx := x + w - 22;
  hot := (MX >= bx) and (MX < bx + 18) and (MY >= y + 2) and (MY < y + 20);
  if hot then
  begin
    SetC(Th.StatusErr);
    FillR(bx, y + 2, 18, 18);
  end;
  SetCol(250, 250, 252);
  TextR(bx + 5, y + 7, 'x');
  if clicked and hot then
  begin
    CloseFramePopup;
    Exit;
  end;
  { text }
  SetC(Th.Text);
  line := '';
  n := 0;
  s := P^.Text;
  for k := 1 to Length(s) + 1 do
    if (k > Length(s)) or (s[k] = #10) then
    begin
      TextR(x + 12, y + 32 + n * 12, Copy(line, 1, 46));
      line := '';
      Inc(n);
    end
    else
      line := line + s[k];
  { buttons }
  by := y + h - 28;
  if (P^.GoPage >= 0) and (P^.GoPage < PageCount) then
  begin
    s := 'Go to: ' + Copy(PageName(P^.GoPage), 1, 26);
    bw := Length(s) * 8 + 20;
    if Btn(x + 12, by, bw, s, True) then
    begin
      PendingPage := P^.GoPage;
      CloseFramePopup;
      Exit;
    end;
  end;
  if Btn(x + w - 92, by, 80, 'Close', False) then
  begin
    CloseFramePopup;
    Exit;
  end;
end;

{ ---------------------------------------------------------------- equipment }

const
  EQ_HANDLE = 10;      { resize handle in the bottom-right corner (canvas pixels) }

{ motors, blowers, paddles and screws and the lamp sit in front of the pipes;
  silo bin, stand and cyclone behind them }
function EquipFront(Kind: Integer): Boolean;
begin
  Result := not (Kind in [EQ_CYCLONE, EQ_SILO, EQ_STAND, EQ_POND, EQ_POOL, EQ_WELL, EQ_PANEL]);
end;

var
  EqManual: Boolean = False;   { the piece being drawn is in a manual state: an orange band }

const
  { the legend: what each state looks like }
  StateLegend: array[0..EQS_COUNT - 1] of string = ('Auto Stop / Interlock / E-Stop', 'Auto Start (run)',
    'Fault', 'Manual Start', 'Manual Stop', 'Disable');
  LegendOrder: array[0..EQS_COUNT - 1] of Integer = (EQS_RUN, EQS_STOP, EQS_MSTART, EQS_MSTOP, EQS_DISABLE, EQS_FAULT);

{ green = running (auto or manual), grey = stopped, dark grey = disabled, red = fault }
procedure EqStateRGB(St: Integer; out r, g, b: Byte);
begin
  case St of
    EQS_RUN, EQS_MSTART: begin r := 62; g := 178; b := 74; end;
    EQS_FAULT: begin r := 222; g := 52; b := 52; end;
    EQS_DISABLE: begin r := 88; g := 90; b := 96; end;
  else
    begin r := 200; g := 202; b := 206; end;
  end;
end;

{ the orange band of a manual state across x, y, w, h }
procedure ManualBand(x, y, w, h: Single);
begin
  if not EqManual then Exit;
  SetCol(245, 145, 35);
  FillR(x, y + h * 0.4, w, h * 0.2);
end;

procedure Shade(r, g, b: Byte; k: Single; a: Byte = 255);
begin
  SetCol(Min(255, Round(r * k)), Min(255, Round(g * k)), Min(255, Round(b * k)), a);
end;

{ the text colour for a state, readable on the canvas background }
procedure EqStateText(St: Integer);
begin
  case St of
    EQS_RUN, EQS_MSTART: if Th.Light then SetCol(30, 130, 45) else SetCol(95, 215, 105);
    EQS_FAULT: if Th.Light then SetCol(200, 30, 30) else SetCol(255, 95, 90);
    EQS_MSTOP: if Th.Light then SetCol(190, 100, 10) else SetCol(245, 160, 70);
  else
    SetC(Th.TextDim);
  end;
end;

{ an electric motor: fan cowl, finned body, terminal box and shaft (ShaftRight: the shaft points right) }
procedure DrawMotorBody(x, y, w, h: Single; ShaftRight: Boolean; r, g, b: Byte);
var
  cw, sw, bx, bw, fx: Single;
begin
  cw := w * 0.17;
  sw := w * 0.1;
  bw := w - cw - sw;
  if ShaftRight then bx := x + cw else bx := x + sw;
  { shaft }
  SetCol(150, 152, 158);
  if ShaftRight then FillR(x + w - sw, y + h * 0.42, sw, h * 0.16)
  else FillR(x, y + h * 0.42, sw, h * 0.16);
  { fan cowl }
  Shade(r, g, b, 0.82);
  if ShaftRight then FillR(x, y + h * 0.12, cw, h * 0.76) else FillR(x + w - cw, y + h * 0.12, cw, h * 0.76);
  Shade(r, g, b, 0.55);
  if ShaftRight then RectR(x, y + h * 0.12, cw, h * 0.76) else RectR(x + w - cw, y + h * 0.12, cw, h * 0.76);
  { body with cooling fins }
  SetCol(r, g, b);
  FillR(bx, y + h * 0.04, bw, h * 0.92);
  Shade(r, g, b, 0.68);
  fx := bx + 4;
  while fx < bx + bw - 3 do
  begin
    LineR(fx, y + h * 0.12, fx, y + h * 0.88);
    fx := fx + 5;
  end;
  ManualBand(bx, y + h * 0.04, bw, h * 0.92);
  Shade(r, g, b, 1.18);
  LineR(bx + 1, y + h * 0.08, bx + bw - 1, y + h * 0.08);
  Shade(r, g, b, 0.5);
  RectR(bx, y + h * 0.04, bw, h * 0.92);
  { terminal box }
  Shade(r, g, b, 0.9);
  FillR(bx + bw * 0.38, y - h * 0.1, bw * 0.24, h * 0.16);
  Shade(r, g, b, 0.5);
  RectR(bx + bw * 0.38, y - h * 0.1, bw * 0.24, h * 0.16);
  { feet }
  SetCol(70, 72, 78);
  FillR(bx + bw * 0.1, y + h * 0.94, bw * 0.15, h * 0.08);
  FillR(bx + bw * 0.75, y + h * 0.94, bw * 0.15, h * 0.08);
end;

{ one 7-segment digit (or '-' / blank) in the box x, y, w, h; the unlit segments faint }
procedure Draw7Seg(x, y, w, h: Single; ch: Char; r, g, b: Byte);
const
  Masks: array[0..9] of Byte = ($3F, $06, $5B, $4F, $66, $6D, $7D, $07, $7F, $6F);
var
  m: Byte;
  th, hh: Single;

  procedure Seg(bit: Byte; sx, sy, sw, sh: Single);
  begin
    if (m and bit) <> 0 then SetCol(r, g, b) else SetCol(r, g, b, 26);
    FillR(sx, sy, sw, sh);
  end;

begin
  case ch of
    '0'..'9': m := Masks[Ord(ch) - Ord('0')];
    '-': m := $40;
  else
    m := 0;
  end;
  th := h * 0.12;
  hh := h / 2 - th * 1.5;
  Seg(1, x + th, y, w - 2 * th, th);
  Seg(2, x + w - th, y + th, th, hh);
  Seg(4, x + w - th, y + h / 2 + th / 2, th, hh);
  Seg(8, x + th, y + h - th, w - 2 * th, th);
  Seg(16, x, y + h / 2 + th / 2, th, hh);
  Seg(32, x, y + th, th, hh);
  Seg(64, x + th, y + h / 2 - th / 2, w - 2 * th, th);
end;
{ a silo bin's level: from the linked hopper / silo, else its own setting }
function EquipLevel(i: Integer): Single;
var
  c: PCell;
begin
  c := EquipLinkCell(i);
  if (c <> nil) and IsStore(c^.Kind) then Result := fclamp(StoreTotal(c^) / StoreCap(c^.Kind) * 100, 0, 100)
  else Result := Equips[i].Level;
end;

{ a colour for a temperature: blue at 20 C through green and yellow to red at 150 C }
procedure TempRGB(T: Single; out r, g, b: Single);
var
  f: Single;
begin
  f := fclamp((T - 20) / 130, 0, 1);
  r := 60 + 190 * f;
  g := 130 + 70 * Sin(Pi * f) - 90 * f;
  b := 235 - 205 * f;
end;

{ the next hot source for heat exchanger Self: none, then every heater, IR heater and fire }
function NextHotSource(const Cur: string; Self: Integer): string;
var
  i: Integer;
  seen: Boolean;
begin
  Result := '';
  seen := Cur = '';
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and (i <> Self) and (Equips[i].Kind in [EQ_HEATER, EQ_IRHEATER, EQ_FIRE, EQ_HEATEX, EQ_COOLTOWER,
      EQ_CHILLER]) then
    begin
      if seen then Exit(Equips[i].Name);
      if SameText(Equips[i].Name, Cur) then seen := True;
    end;
end;
{ a text on 7-segment digits (digits, '-', ' ' and '.'), right-aligned at xr, mh high }
procedure DrawSegStr(xr, y, mh: Single; const s: string; r, g, b: Byte);
var
  k: Integer;
  t, gw: Single;
begin
  gw := mh * 0.55;
  t := xr;
  for k := 1 to Length(s) do
    if s[k] = '.' then t := t - mh * 0.26 else t := t - (gw + mh * 0.16);
  for k := 1 to Length(s) do
  begin
    if s[k] = '.' then
    begin
      SetCol(r, g, b);
      FillR(t, y + mh - mh * 0.12, mh * 0.12, mh * 0.12);
      t := t + mh * 0.26;
      Continue;
    end;
    Draw7Seg(t, y, gw, mh, s[k], r, g, b);
    t := t + gw + mh * 0.16;
  end;
end;

function SegText(v: Single): string;
begin
  if Abs(v) >= 1000 then Result := Format('%5.0f', [v]) else Result := Format('%5.1f', [v]);
end;

{ a controller's actual value, set point and output, from this page or another one }
function FaceValues(const Tag: string; out pv, sp, o: Single; out Powered: Boolean): Boolean;
var
  x, y: Integer;
  u: string;
begin
  pv := 0;
  sp := 0;
  o := 0;
  Powered := False;
  if ECellByTag(Tag, ekController, x, y) then
  begin
    pv := EGrid[x, y].Val;
    sp := EGrid[x, y].P1;
    o := EGrid[x, y].Out;
    Powered := EGrid[x, y].Energized;
    Exit(True);
  end;
  Result := (Tag <> '') and BusSignal(Tag + '.PV', pv, u) and BusSignal(Tag + '.SP', sp, u);
  if Result and BusSignal(Tag, o, u) then Powered := True;
end;

{ the next controller tag ('' after the last one) }
function NextCtrlTag(const Cur: string): string;
var
  x, y: Integer;
  seen: Boolean;
begin
  Result := '';
  seen := Cur = '';
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (EGrid[x, y].Kind = ekController) and (EGrid[x, y].Tag <> '') then
      begin
        if seen then Exit(EGrid[x, y].Tag);
        if SameText(EGrid[x, y].Tag, Cur) then seen := True;
      end;
end;

{ ---------------------------------------------------------------- custom vector shapes }

var
  NoCustomShape: Boolean = False;   { draw the built-in shape even when the kind has its own }

procedure EllipseC(cx, cy, rx, ry: Single; r, g, b: Byte; a: Byte = 255);
const
  N = 24;
var
  i: Integer;
begin
  SetVtx(0, cx, cy, r, g, b, a);
  for i := 0 to N do
    SetVtx(i + 1, cx + Cos(i * 2 * Pi / N) * rx, cy + Sin(i * 2 * Pi / N) * ry, r, g, b, a);
  for i := 0 to N - 1 do
  begin
    GI[i * 3] := 0;
    GI[i * 3 + 1] := i + 1;
    GI[i * 3 + 2] := i + 2;
  end;
  SDL_RenderGeometry(Ren, nil, @GV[0], N + 2, @GI[0], N * 3);
end;

{ a line t pixels thick }
procedure ThickLineC(x1, y1, x2, y2, t: Single; r, g, b: Byte; a: Byte = 255);
var
  dx, dy, l: Single;
begin
  dx := x2 - x1;
  dy := y2 - y1;
  l := Sqrt(dx * dx + dy * dy);
  if l < 0.01 then
  begin
    SetCol(r, g, b, a);
    FillR(x1 - t / 2, y1 - t / 2, t, t);
    Exit;
  end;
  dx := -dy / l * t / 2;
  dy := (x2 - x1) / l * t / 2;
  QuadC(x1 + dx, y1 + dy, x2 + dx, y2 + dy, x2 - dx, y2 - dy, x1 - dx, y1 - dy, r, g, b, a);
end;

{ kind's own shape in the box x, y, w, h; sr, sg, sb: the state colour }
procedure DrawCustomShape(Kind: Integer; x, y, w, h: Single; Flip: Boolean; sr, sg, sb: Byte);
const
  N = 32;
var
  k, j: Integer;
  x1, y1, x2, y2, cx, cy, rx, ry, t: Single;
  r, g, b, dr, dg, db: Byte;
  P: ^TShapePrim;

  function PX(u: Single): Single;
  begin
    if Flip then Result := x + w * (1 - u) else Result := x + w * u;
  end;

begin
  for k := 0 to EqShapes[Kind].N - 1 do
  begin
    P := @EqShapes[Kind].P[k];
    if P^.StateCol then
    begin
      r := sr;
      g := sg;
      b := sb;
    end
    else
    begin
      r := P^.R;
      g := P^.G;
      b := P^.B;
    end;
    { the outline of a filled part: a darker shade of it }
    if P^.Fill then
    begin
      dr := Round(r * 0.55);
      dg := Round(g * 0.55);
      db := Round(b * 0.55);
    end
    else
    begin
      dr := r;
      dg := g;
      db := b;
    end;
    t := P^.Thick;
    x1 := PX(P^.X1);
    x2 := PX(P^.X2);
    y1 := y + h * P^.Y1;
    y2 := y + h * P^.Y2;
    case P^.Typ of
      PR_RECT:
        begin
          if x2 < x1 then
          begin
            cx := x1;
            x1 := x2;
            x2 := cx;
          end;
          if y2 < y1 then
          begin
            cy := y1;
            y1 := y2;
            y2 := cy;
          end;
          if P^.Fill then
          begin
            SetCol(r, g, b, P^.A);
            FillR(x1, y1, x2 - x1, y2 - y1);
          end;
          SetCol(dr, dg, db, P^.A);
          for j := 0 to Max(1, Round(t)) - 1 do
            if (x2 - x1 > 2 * j) and (y2 - y1 > 2 * j) then RectR(x1 + j, y1 + j, x2 - x1 - 2 * j, y2 - y1 - 2 * j);
        end;
      PR_ELLIPSE:
        begin
          cx := (x1 + x2) / 2;
          cy := (y1 + y2) / 2;
          rx := Abs(x2 - x1) / 2;
          ry := Abs(y2 - y1) / 2;
          if P^.Fill then EllipseC(cx, cy, rx, ry, r, g, b, P^.A);
          for j := 0 to N - 1 do
            ThickLineC(cx + Cos(j * 2 * Pi / N) * (rx - t / 2), cy + Sin(j * 2 * Pi / N) * (ry - t / 2),
              cx + Cos((j + 1) * 2 * Pi / N) * (rx - t / 2), cy + Sin((j + 1) * 2 * Pi / N) * (ry - t / 2),
              Max(1, t), dr, dg, db, P^.A);
        end;
      PR_LINE:
        ThickLineC(x1, y1, x2, y2, Max(1, t), r, g, b, P^.A);
      PR_TRI:
        begin
          cx := (x1 + x2) / 2;
          if P^.Fill then TriC(x1, y1, x2, y1, cx, y2, r, g, b, P^.A);
          ThickLineC(x1, y1, x2, y1, Max(1, t), dr, dg, db, P^.A);
          ThickLineC(x2, y1, cx, y2, Max(1, t), dr, dg, db, P^.A);
          ThickLineC(cx, y2, x1, y1, Max(1, t), dr, dg, db, P^.A);
        end;
    end;
  end;
end;

procedure DrawEquipShape(i: Integer);
var
  E: ^TEquipObj;
  r, g, b: Byte;
  x, y, w, h, cx, cy, rad, a, t, mw, mh, gw, lx, ly, ty: Single;
  k, n: Integer;
  s0: string;

  { x of a point t pixels in from the "motor" end, mirrored when the equipment is flipped }
  function FX(tt: Single): Single;
  begin
    if E^.Flip then Result := x + w - tt else Result := x + tt;
  end;

  procedure FRect(tt, yy, ww, hh: Single);
  begin
    if E^.Flip then FillR(x + w - tt - ww, yy, ww, hh) else FillR(x + tt, yy, ww, hh);
  end;

  procedure ORect(tt, yy, ww, hh: Single);
  begin
    if E^.Flip then RectR(x + w - tt - ww, yy, ww, hh) else RectR(x + tt, yy, ww, hh);
  end;

begin
  E := @Equips[i];
  x := E^.X;
  y := E^.Y;
  w := E^.W;
  h := E^.H;
  EqStateRGB(E^.State, r, g, b);
  EqManual := E^.State in [EQS_MSTART, EQS_MSTOP];
  if ShapeDefined(E^.Kind) and not NoCustomShape then
  begin
    DrawCustomShape(E^.Kind, x, y, w, h, E^.Flip, r, g, b);
    EqManual := False;
    Exit;
  end;
  case E^.Kind of
    EQ_MOTOR:
      DrawMotorBody(x, y, w, h, not E^.Flip, r, g, b);

    EQ_BLOWER:
      begin
        rad := fmin(w * 0.4, h * 0.44);
        if E^.Flip then cx := x + w - rad - 4 else cx := x + rad + 4;
        cy := y + h - rad - 8;
        { the motor behind the housing }
        mw := fmin(w - 2 * rad - 4, rad * 1.1);
        if mw > 12 then
        begin
          if E^.Flip then DrawMotorBody(x, cy - rad * 0.3, mw + rad * 0.4, rad * 0.6, True, r, g, b)
          else DrawMotorBody(cx + rad - rad * 0.4, cy - rad * 0.3, mw + rad * 0.4, rad * 0.6, False, r, g, b);
        end;
        { base }
        SetCol(45, 47, 52);
        FillR(cx - rad * 0.8, y + h - 8, rad * 1.6, 8);
        { outlet duct going up from the scroll }
        if E^.Flip then lx := cx - rad else lx := cx + rad * 0.3;
        Shade(r, g, b, 0.9);
        FillR(lx, y, rad * 0.7, cy - y);
        Shade(r, g, b, 0.5);
        RectR(lx, y, rad * 0.7, cy - y);
        { scroll housing and impeller }
        DiscC(cx, cy, rad, r, g, b);
        Shade(r, g, b, 0.5);
        RingC(cx, cy, rad, False);
        DiscC(cx, cy, rad * 0.74, Round(r * 0.72), Round(g * 0.72), Round(b * 0.72));
        if E^.State = EQS_STOP then SetCol(240, 240, 242) else SetCol(235, 248, 236);
        n := 10;
        for k := 0 to n - 1 do
        begin
          a := E^.Phase + k * 2 * Pi / n;
          LineR(cx + Cos(a) * rad * 0.26, cy + Sin(a) * rad * 0.26, cx + Cos(a + 0.35) * rad * 0.68,
            cy + Sin(a + 0.35) * rad * 0.68);
          LineR(cx + Cos(a) * rad * 0.26 + 1, cy + Sin(a) * rad * 0.26, cx + Cos(a + 0.35) * rad * 0.68 + 1,
            cy + Sin(a + 0.35) * rad * 0.68);
        end;
        DiscC(cx, cy, rad * 0.24, 175, 178, 184);
        SetCol(90, 92, 98);
        RingC(cx, cy, rad * 0.24, False);
        DiscC(cx, cy, rad * 0.07, 90, 92, 98);
      end;

    EQ_PADDLE:
      begin
        mw := fmin(80, w * 0.32);
        mh := h * 0.8;
        cy := y + h / 2;
        { shaft }
        SetCol(112, 116, 124);
        FRect(mw, cy - 2, w - mw, 4);
        { paddles turning on the shaft }
        k := 0;
        t := mw + 22;
        while t < w - 6 do
        begin
          a := Abs(Cos(E^.Phase * 0.5 + k * 1.1));
          ty := h * 0.88 * (0.3 + 0.7 * a);
          SetCol(r, g, b);
          FRect(t, cy - ty / 2, 8, ty);
          Shade(r, g, b, 0.55);
          ORect(t, cy - ty / 2, 8, ty);
          SetCol(80, 84, 90);
          FRect(t - 2, cy - 4, 12, 8);
          t := t + 34;
          Inc(k);
        end;
        DrawMotorBody(FX(0) - Ord(E^.Flip) * mw, y + (h - mh) / 2, mw, mh, not E^.Flip, r, g, b);
      end;

    EQ_SCREW:
      begin
        mw := fmin(78, w * 0.24);
        gw := fmin(22, w * 0.07);
        mh := h * 0.86;
        ty := y + h * 0.2;
        { trough }
        SetCol(214, 218, 224);
        FRect(mw + gw, ty, w - mw - gw, h * 0.6);
        { flights moving toward the far end while it runs }
        SetCol(96, 100, 108);
        FRect(mw + gw, y + h / 2 - 1.5, w - mw - gw - 6, 3);
        a := Frac(E^.Phase * 0.35) * 14;
        t := mw + gw + 4 + a;
        while t < w - 14 do
        begin
          LineR(FX(t), ty + 3, FX(t + 7), ty + h * 0.6 - 3);
          LineR(FX(t + 1), ty + 3, FX(t + 8), ty + h * 0.6 - 3);
          t := t + 14;
        end;
        SetCol(120, 124, 132);
        ORect(mw + gw, ty, w - mw - gw, h * 0.6);
        { end bearing }
        SetCol(70, 74, 80);
        FRect(w - 8, ty - 3, 8, h * 0.6 + 6);
        { gearbox }
        Shade(r, g, b, 0.85);
        FRect(mw, y + h * 0.14, gw, h * 0.72);
        Shade(r, g, b, 0.5);
        ORect(mw, y + h * 0.14, gw, h * 0.72);
        DrawMotorBody(FX(0) - Ord(E^.Flip) * mw, y + (h - mh) / 2, mw, mh, not E^.Flip, r, g, b);
      end;

    EQ_CYCLONE:
      begin
        r := 112; g := 168; b := 226;
        { vortex finder, barrel, cone, outlet }
        Shade(r, g, b, 0.85);
        FillR(x + w * 0.34, y, w * 0.32, h * 0.1);
        SetCol(r, g, b);
        FillR(x, y + h * 0.1, w, h * 0.32);
        QuadC(x, y + h * 0.42, x + w, y + h * 0.42, x + w * 0.62, y + h * 0.86, x + w * 0.38, y + h * 0.86, r, g, b);
        Shade(r, g, b, 0.75);
        FillR(x + w * 0.38, y + h * 0.86, w * 0.24, h * 0.14);
        Shade(r, g, b, 0.55);
        RectR(x + w * 0.34, y, w * 0.32, h * 0.1);
        RectR(x, y + h * 0.1, w, h * 0.32);
        LineR(x, y + h * 0.42, x + w * 0.38, y + h * 0.86);
        LineR(x + w, y + h * 0.42, x + w * 0.62, y + h * 0.86);
        RectR(x + w * 0.38, y + h * 0.86, w * 0.24, h * 0.14);
        Shade(r, g, b, 1.15);
        LineR(x + 3, y + h * 0.14, x + 3, y + h * 0.4);
      end;

    EQ_SILO:
      begin
        a := EquipLevel(i) / 100;
        { sky above the material, the material, panel seams, frame }
        SetCol(186, 218, 242);
        FillR(x, y, w, h);
        ly := y + h * (1 - a);
        SetCol(236, 232, 212);
        FillR(x, ly, w, y + h - ly);
        SetCol(200, 190, 160);
        for k := 0 to 60 do
        begin
          lx := x + 4 + ((k * 37) mod 97) / 97 * (w - 8);
          ty := ly + 4 + ((k * 53) mod 89) / 89 * fmax(0, y + h - ly - 8);
          if ty < y + h - 3 then FillR(lx, ty, 2, 2);
        end;
        SetCol(45, 105, 185);
        for k := 1 to 3 do LineR(x + w * k / 4, y, x + w * k / 4, y + h);
        for k := 1 to 2 do LineR(x, y + h * k / 3, x + w, y + h * k / 3);
        RectR(x, y, w, h);
        RectR(x + 1, y + 1, w - 2, h - 2);
        RectR(x + 2, y + 2, w - 4, h - 4);
        FillR(x - 6, y + h - 4, w + 12, 5);
      end;

    EQ_STAND:
      begin
        SetCol(45, 105, 185);
        FillR(x, y, w, 8);
        n := 4;
        for k := 0 to n - 1 do
        begin
          lx := x + 4 + (w - 16) * k / (n - 1);
          FillR(lx, y + 8, 8, h - 14);
          FillR(lx - 4, y + h - 6, 16, 6);
          if k < n - 1 then
          begin
            t := x + 4 + (w - 16) * (k + 1) / (n - 1);
            LineR(lx + 8, y + 12, t, y + h * 0.7);
            LineR(lx + 8, y + h * 0.7, t, y + 12);
          end;
        end;
      end;

    EQ_LAMP:
      begin
        case E^.State of
          EQS_RUN, EQS_MSTART: begin r := 60; g := 205; b := 80; end;
          EQS_FAULT: begin r := 230; g := 50; b := 50; end;
        else
          begin r := 150; g := 152; b := 158; end;
        end;
        rad := fmin(w, h) / 2;
        DiscC(x + w / 2, y + h / 2, rad, r, g, b);
        SetCol(40, 44, 50);
        RingC(x + w / 2, y + h / 2, rad, False);
        DiscC(x + w / 2 - rad * 0.3, y + h / 2 - rad * 0.3, rad * 0.3, 255, 255, 255, 150);
      end;

    EQ_LEGEND, EQ_SEQUENCE:
      begin
        SetC(Th.OverlayBg, 235);
        FillR(x, y, w, h);
        SetC(Th.MenuBorder);
        RectR(x, y, w, h);
      end;

    EQ_DIVERTER:
      begin
        { inlet on top, a body with a flap, two legs; the actuator above }
        cx := x + w / 2;
        ty := y + h * 0.3;
        SetCol(150, 156, 166);
        QuadC(cx - w * 0.2, ty + h * 0.3, cx - w * 0.02, ty + h * 0.3, x + w * 0.22, y + h, x, y + h, 150, 156, 166);
        QuadC(cx + w * 0.02, ty + h * 0.3, cx + w * 0.2, ty + h * 0.3, x + w, y + h, x + w * 0.78, y + h, 150, 156, 166);
        SetCol(170, 176, 186);
        FillR(cx - w * 0.22, ty, w * 0.44, h * 0.32);
        SetCol(90, 96, 106);
        RectR(cx - w * 0.22, ty, w * 0.44, h * 0.32);
        LineR(cx - w * 0.2, ty + h * 0.3, x, y + h);
        LineR(cx + w * 0.2, ty + h * 0.3, x + w, y + h);
        { the flap: position 1 (running) leans right, position 2 left }
        SetCol(40, 44, 52);
        if EquipRunning(i) then
        begin
          LineR(cx, ty + 2, cx + w * 0.18, ty + h * 0.3);
          LineR(cx + 1, ty + 2, cx + w * 0.18 + 1, ty + h * 0.3);
        end
        else
        begin
          LineR(cx, ty + 2, cx - w * 0.18, ty + h * 0.3);
          LineR(cx + 1, ty + 2, cx - w * 0.18 + 1, ty + h * 0.3);
        end;
        { actuator }
        SetCol(r, g, b);
        FillR(cx - w * 0.3, y, w * 0.6, h * 0.22);
        ManualBand(cx - w * 0.3, y, w * 0.6, h * 0.22);
        Shade(r, g, b, 0.5);
        RectR(cx - w * 0.3, y, w * 0.6, h * 0.22);
        SetCol(110, 114, 122);
        FillR(cx - 2, y + h * 0.22, 4, h * 0.08);
      end;

    EQ_SHUTTER:
      begin
        { a butterfly valve between flanges, the disc turns with the state }
        cy := y + h * 0.62;
        mh := h * 0.7;
        SetCol(150, 156, 166);
        FillR(x, cy - mh * 0.35, w, mh * 0.7);
        SetCol(100, 106, 116);
        FillR(x, cy - mh / 2, 6, mh);
        FillR(x + w - 6, cy - mh / 2, 6, mh);
        cx := x + w / 2;
        rad := mh * 0.32;
        SetCol(60, 64, 72);
        RingC(cx, cy, rad, False);
        if EquipRunning(i) then
        begin
          FillR(cx - rad, cy - 1.5, rad * 2, 3);       { open: the disc edge-on }
        end
        else
        begin
          FillR(cx - 1.5, cy - rad, 3, rad * 2);       { shut: across the bore }
          DiscC(cx, cy, rad * 0.9, 110, 116, 126, 160);
        end;
        { actuator box on top }
        SetCol(r, g, b);
        FillR(cx - w * 0.22, y, w * 0.44, h * 0.26);
        ManualBand(cx - w * 0.22, y, w * 0.44, h * 0.26);
        Shade(r, g, b, 0.5);
        RectR(cx - w * 0.22, y, w * 0.44, h * 0.26);
        SetCol(110, 114, 122);
        FillR(cx - 2, y + h * 0.26, 4, cy - rad - y - h * 0.26);
      end;

    EQ_SLIDE:
      begin
        { a knife-gate: the gate slides up into its bonnet when open }
        cx := x + w / 2;
        ty := y + h * 0.5;
        SetCol(150, 156, 166);
        FillR(x, ty, w, h * 0.42);
        SetCol(100, 106, 116);
        FillR(x, ty - 3, w, 4);
        FillR(x, ty + h * 0.42 - 1, w, 4);
        SetCol(205, 210, 218);
        if EquipRunning(i) then FillR(x + 6, ty - h * 0.26, w - 12, h * 0.24)
        else FillR(x + 6, ty + 2, w - 12, h * 0.38);
        SetCol(80, 86, 96);
        if EquipRunning(i) then RectR(x + 6, ty - h * 0.26, w - 12, h * 0.24)
        else RectR(x + 6, ty + 2, w - 12, h * 0.38);
        { bonnet and cylinder }
        SetCol(130, 136, 146);
        RectR(x + 3, y + h * 0.22, w - 6, h * 0.3);
        SetCol(r, g, b);
        FillR(cx - w * 0.16, y, w * 0.32, h * 0.22);
        ManualBand(cx - w * 0.16, y, w * 0.32, h * 0.22);
        Shade(r, g, b, 0.5);
        RectR(cx - w * 0.16, y, w * 0.32, h * 0.22);
      end;

    EQ_HEATER:
      begin
        { a duct heater: flanges, a box with coils that glow while it heats }
        SetCol(100, 106, 116);
        FillR(x, y + h * 0.3, 6, h * 0.55);
        FillR(x + w - 6, y + h * 0.3, 6, h * 0.55);
        SetCol(170, 176, 186);
        FillR(x + 6, y + h * 0.25, w - 12, h * 0.65);
        SetCol(90, 96, 106);
        RectR(x + 6, y + h * 0.25, w - 12, h * 0.65);
        if EquipRunning(i) then
        begin
          a := 0.75 + 0.25 * Sin(E^.Phase * 2);
          SetCol(255, Round(90 * a + 40), 20);
        end
        else
          SetCol(110, 114, 122);
        t := x + 12;
        k := 0;
        while t < x + w - 18 do
        begin
          if k mod 2 = 0 then LineR(t, y + h * 0.35, t + 6, y + h * 0.8)
          else LineR(t, y + h * 0.8, t + 6, y + h * 0.35);
          LineR(t + 1, y + h * 0.35 + Ord(k mod 2 = 1) * h * 0.45, t + 7, y + h * 0.8 - Ord(k mod 2 = 1) * h * 0.45);
          t := t + 6;
          Inc(k);
        end;
        { terminal box }
        SetCol(r, g, b);
        FillR(x + w * 0.35, y, w * 0.3, h * 0.25);
        ManualBand(x + w * 0.35, y, w * 0.3, h * 0.25);
        Shade(r, g, b, 0.5);
        RectR(x + w * 0.35, y, w * 0.3, h * 0.25);
      end;

    EQ_IRHEATER:
      begin
        { the radiant panel and, while it heats, the waves below it }
        if EquipRunning(i) then
        begin
          for k := 0 to 4 do
          begin
            t := x + w * (k + 0.5) / 5;
            SetCol(255, 80, 40, 150);
            ty := y + h;
            while ty < y + h * 5.5 do
            begin
              LineR(t + Sin((ty - y) * 0.25 + E^.Phase * 2) * 3, ty,
                t + Sin((ty + 4 - y) * 0.25 + E^.Phase * 2) * 3, ty + 4);
              ty := ty + 4;
            end;
          end;
        end;
        SetCol(r, g, b);
        FillR(x, y, w, h * 0.45);
        ManualBand(x, y, w, h * 0.45);
        Shade(r, g, b, 0.5);
        RectR(x, y, w, h * 0.45);
        for k := 0 to 2 do
        begin
          if EquipRunning(i) then SetCol(255, 70 + k * 25, 30) else SetCol(120, 124, 132);
          FillR(x + 4, y + h * (0.5 + k * 0.17), w - 8, h * 0.1);
        end;
      end;

    EQ_RAIN:
      begin
        { a cloud: dark while it rains }
        if EquipRunning(i) then
        begin
          r := 120; g := 128; b := 142;
        end
        else
        begin
          r := 228; g := 232; b := 238;
        end;
        DiscC(x + w * 0.25, y + h * 0.6, h * 0.36, r, g, b);
        DiscC(x + w * 0.45, y + h * 0.42, h * 0.44, r, g, b);
        DiscC(x + w * 0.68, y + h * 0.5, h * 0.4, r, g, b);
        DiscC(x + w * 0.84, y + h * 0.64, h * 0.3, r, g, b);
        FillR(x + w * 0.12, y + h * 0.6, w * 0.8, h * 0.32);
        Shade(r, g, b, 0.8);
        LineR(x + w * 0.12, y + h * 0.92, x + w * 0.92, y + h * 0.92);
      end;

    EQ_CYLINDER:
      begin
        { a cylinder: barrel, end caps, the rod out by its stroke (Level %); upright when taller than wide }
        a := fclamp(E^.Level / 100, 0, 1);
        if w >= h then
        begin
          mw := w * 0.55;
          SetCol(185, 190, 198);
          if E^.Flip then FillR(x + w - mw, y + h * 0.15, mw, h * 0.7) else FillR(x, y + h * 0.15, mw, h * 0.7);
          SetCol(120, 126, 136);
          if E^.Flip then RectR(x + w - mw, y + h * 0.15, mw, h * 0.7) else RectR(x, y + h * 0.15, mw, h * 0.7);
          SetCol(r, g, b);
          if E^.Flip then begin FillR(x + w - mw, y + h * 0.1, 6, h * 0.8); FillR(x + w - 6, y + h * 0.1, 6, h * 0.8); end
          else begin FillR(x, y + h * 0.1, 6, h * 0.8); FillR(x + mw - 6, y + h * 0.1, 6, h * 0.8); end;
          { rod and its end }
          t := (w - mw - 10) * a + 6;
          SetCol(215, 220, 228);
          if E^.Flip then FillR(x + w - mw - t, y + h * 0.42, t, h * 0.16) else FillR(x + mw, y + h * 0.42, t, h * 0.16);
          SetCol(90, 96, 106);
          if E^.Flip then FillR(x + w - mw - t - 6, y + h * 0.25, 6, h * 0.5) else FillR(x + mw + t, y + h * 0.25, 6, h * 0.5);
        end
        else
        begin
          mh := h * 0.55;
          SetCol(185, 190, 198);
          FillR(x + w * 0.15, y, w * 0.7, mh);
          SetCol(120, 126, 136);
          RectR(x + w * 0.15, y, w * 0.7, mh);
          SetCol(r, g, b);
          FillR(x + w * 0.1, y, w * 0.8, 6);
          FillR(x + w * 0.1, y + mh - 6, w * 0.8, 6);
          t := (h - mh - 10) * a + 6;
          SetCol(215, 220, 228);
          FillR(x + w * 0.42, y + mh, w * 0.16, t);
          SetCol(90, 96, 106);
          FillR(x + w * 0.2, y + mh + t, w * 0.6, 8);
        end;
      end;

    EQ_COMPRESSOR, EQ_RECEIVER:
      begin
        if E^.Kind = EQ_RECEIVER then
        begin
          { an upright air receiver with its gauge }
          SetCol(200, 60, 55);
          FillR(x + w * 0.1, y + w * 0.4, w * 0.8, h - w * 0.4 - 10);
          DiscC(x + w / 2, y + w * 0.4, w * 0.4, 200, 60, 55);
          DiscC(x + w / 2, y + h - 10, w * 0.4, 200, 60, 55);
          SetCol(70, 74, 82);
          FillR(x + w * 0.2, y + h - 6, 6, 6);
          FillR(x + w * 0.8 - 6, y + h - 6, 6, 6);
          cx := x + w / 2;
          cy := y + h * 0.4;
        end
        else
        begin
          { a horizontal tank on feet, compressor head and motor on top }
          SetCol(200, 60, 55);
          FillR(x + h * 0.25, y + h * 0.45, w - h * 0.5, h * 0.45);
          DiscC(x + h * 0.25, y + h * 0.675, h * 0.225, 200, 60, 55);
          DiscC(x + w - h * 0.25, y + h * 0.675, h * 0.225, 200, 60, 55);
          SetCol(70, 74, 82);
          FillR(x + w * 0.2, y + h * 0.9, 8, h * 0.1);
          FillR(x + w * 0.8 - 8, y + h * 0.9, 8, h * 0.1);
          SetCol(120, 126, 136);
          FillR(x + w * 0.18, y + h * 0.12, w * 0.22, h * 0.33);
          for k := 0 to 3 do
          begin
            SetCol(90, 96, 106);
            LineR(x + w * 0.18, y + h * (0.16 + k * 0.07), x + w * 0.4, y + h * (0.16 + k * 0.07));
          end;
          DrawMotorBody(x + w * 0.45, y + h * 0.15, w * 0.35, h * 0.28, False, r, g, b);
          cx := x + w * 0.88;
          cy := y + h * 0.3;
        end;
        { the gauge (its source, or nothing) }
        DiscC(cx, cy, 9, 240, 241, 243);
        SetCol(40, 44, 52);
        RingC(cx, cy, 9, False);
        if AnalogValue(E^.Src, mw, s0) then a := fclamp(mw / fmax(1, E^.RMax), 0, 1) else a := 0;
        a := Pi * (0.75 + 1.5 * a);
        SetCol(210, 40, 35);
        LineR(cx, cy, cx + Cos(a) * 7, cy + Sin(a) * 7);
      end;

    EQ_HPU:
      begin
        { a hydraulic power unit: oil reservoir, sight glass, motor and pump on the lid }
        SetCol(70, 110, 160);
        FillR(x, y + h * 0.4, w, h * 0.6);
        SetCol(40, 70, 110);
        RectR(x, y + h * 0.4, w, h * 0.6);
        SetCol(235, 150, 50);
        FillR(x + 10, y + h * 0.55, 8, h * 0.3);
        SetCol(30, 34, 40);
        RectR(x + 10, y + h * 0.55, 8, h * 0.3);
        DrawMotorBody(x + w * 0.35, y + h * 0.1, w * 0.4, h * 0.28, False, r, g, b);
        SetCol(110, 116, 126);
        FillR(x + w * 0.78, y + h * 0.16, w * 0.14, h * 0.24);
        cx := x + w * 0.2;
        cy := y + h * 0.24;
        DiscC(cx, cy, 9, 240, 241, 243);
        SetCol(40, 44, 52);
        RingC(cx, cy, 9, False);
        if AnalogValue(E^.Src, mw, s0) then a := fclamp(mw / fmax(1, E^.RMax), 0, 1) else a := 0;
        a := Pi * (0.75 + 1.5 * a);
        SetCol(210, 40, 35);
        LineR(cx, cy, cx + Cos(a) * 7, cy + Sin(a) * 7);
      end;

    EQ_GAUGE:
      begin
        { a needle meter: bezel, face, 240 degree scale with a red end zone, needle }
        rad := fmin(w, h) / 2 - 4;
        cx := x + w / 2;
        cy := y + h / 2 + rad * 0.08;
        DiscC(cx, cy, rad + 4, 66, 70, 78);
        DiscC(cx, cy, rad, 240, 241, 243);
        for k := 0 to 40 do
        begin
          t := 0.8 + 0.2 * k / 40;
          a := Pi * (0.75 + 1.5 * t);
          SetCol(225, 60, 50);
          LineR(cx + Cos(a) * rad * 0.8, cy + Sin(a) * rad * 0.8, cx + Cos(a) * rad * 0.9, cy + Sin(a) * rad * 0.9);
        end;
        SetCol(40, 44, 52);
        for k := 0 to 10 do
        begin
          a := Pi * (0.75 + 1.5 * k / 10);
          if k mod 5 = 0 then t := 0.7 else t := 0.8;
          LineR(cx + Cos(a) * rad * t, cy + Sin(a) * rad * t, cx + Cos(a) * rad * 0.92, cy + Sin(a) * rad * 0.92);
        end;
        if AnalogValue(E^.Src, mw, s0) then
          t := fclamp((mw - E^.RMin) / fmax(0.001, E^.RMax - E^.RMin), -0.02, 1.02)
        else
          t := 0;
        a := Pi * (0.75 + 1.5 * t);
        SetCol(210, 40, 35);
        LineR(cx, cy, cx + Cos(a) * rad * 0.82, cy + Sin(a) * rad * 0.82);
        LineR(cx + 1, cy, cx + 1 + Cos(a) * rad * 0.82, cy + Sin(a) * rad * 0.82);
        LineR(cx, cy + 1, cx + Cos(a) * rad * 0.82, cy + 1 + Sin(a) * rad * 0.82);
        DiscC(cx, cy, rad * 0.08 + 2, 40, 44, 52);
      end;

    EQ_DIGITAL:
      begin
        { a 7-segment display: the value right-aligned, red when out of range }
        SetCol(90, 94, 102);
        FillR(x, y, w, h);
        SetCol(16, 20, 24);
        FillR(x + 4, y + 4, w - 8, h - 8);
        if AnalogValue(E^.Src, mw, s0) then
        begin
          if (mw > E^.RMax) or (mw < E^.RMin) then begin r := 245; g := 70; b := 60; end
          else begin r := 70; g := 235; b := 115; end;
          if Abs(mw) >= 1000 then s0 := Format('%5.0f', [mw]) else s0 := Format('%5.1f', [mw]);
        end
        else
        begin
          r := 150; g := 152; b := 158;
          s0 := ' ----';
        end;
        mh := h * 0.58;            { digit height }
        gw := mh * 0.55;           { digit width }
        t := x + w - 10 - 4 * (gw + mh * 0.16) - mh * 0.26;
        for k := 1 to Length(s0) do
        begin
          if s0[k] = '.' then
          begin
            { the decimal point has a narrow place of its own }
            SetCol(r, g, b);
            FillR(t, y + h / 2 + mh / 2 - mh * 0.12, mh * 0.12, mh * 0.12);
            t := t + mh * 0.26;
            Continue;
          end;
          Draw7Seg(t, y + (h - mh) / 2, gw, mh, s0[k], r, g, b);
          t := t + gw + mh * 0.16;
        end;
      end;

    EQ_CONTROLLER:
      begin
        { a panel controller: the actual value (PV) large, the set point (SP), the output bar }
        SetCol(70, 74, 82);
        FillR(x, y, w, h);
        SetCol(18, 21, 26);
        FillR(x + 4, y + 4, w - 8, h - 8);
        mh := h * 0.3;
        if FaceValues(E^.Src, lx, ly, ty, EqManual) then
        begin
          DrawSegStr(x + w - 10, y + 8, mh, SegText(lx), 245, 70, 60);
          DrawSegStr(x + w - 10, y + 14 + mh, mh * 0.62, SegText(ly), 70, 235, 115);
          t := fclamp(ty / 100, 0, 1);
          if EqManual then SetCol(70, 235, 115) else SetCol(70, 74, 82);
          EqManual := False;
          FillR(x + 10, y + 20 + mh * 1.62, 6, 6);
        end
        else
        begin
          DrawSegStr(x + w - 10, y + 8, mh, ' ----', 150, 152, 158);
          t := 0;
        end;
        SetCol(50, 54, 60);
        FillR(x + 38, y + h - 16, w - 48, 8);
        SetCol(245, 170, 40);
        FillR(x + 38, y + h - 16, (w - 48) * t, 8);
        SetCol(160, 164, 172);
        TextR(x + 10, y + 10, 'PV');
        TextR(x + 10, y + 16 + mh, 'SP');
        TextR(x + 10, y + h - 16, 'OUT');
        TextR(x + 22, y + 19 + mh * 1.62, Copy(E^.Src, 1, Max(1, Round((w - 40) / 8))));
      end;

    EQ_HEATEX:
      begin
        { shell and tube, counterflow: the process (cold) stream through the shell from left to
          right, the hot stream through the tubes from the right-hand head to the left-hand one;
          colours follow the temperatures, the saddles show its state }
        mw := fmin(w * 0.14, 26);
        mh := h * 0.62;
        ty := y + (h - mh) / 2 - 4;
        { saddles }
        SetCol(r, g, b);
        FillR(x + mw + 10, y + h - 10, 14, 10);
        FillR(x + w - mw - 24, y + h - 10, 14, 10);
        { shell: cold in (left) to cold out (right) }
        n := 12;
        for k := 0 to n - 1 do
        begin
          TempRGB(E^.ColdIn + (E^.Temp - E^.ColdIn) * (k + 0.5) / n, lx, ly, t);
          SetCol(Round(lx), Round(ly), Round(t));
          FillR(x + mw + (w - 2 * mw) * k / n, ty, (w - 2 * mw) / n + 1, mh);
        end;
        { the tube bundle: hot in at the right, out at the left }
        for k := 0 to 2 do
          for n := 0 to 11 do
          begin
            TempRGB(E^.HotIn + (E^.HotOut - E^.HotIn) * (1 - (n + 0.5) / 12), lx, ly, t);
            SetCol(Round(lx), Round(ly), Round(t));
            FillR(x + mw + (w - 2 * mw) * n / 12, ty + mh * (0.25 + k * 0.25) - 1.5, (w - 2 * mw) / 12 + 1, 3);
          end;
        { baffles }
        SetCol(60, 64, 72, 200);
        for k := 1 to 4 do
        begin
          a := x + mw + (w - 2 * mw) * k / 5;
          if k mod 2 = 1 then LineR(a, ty, a, ty + mh * 0.7) else LineR(a, ty + mh * 0.3, a, ty + mh);
        end;
        SetCol(50, 54, 62);
        RectR(x + mw, ty, w - 2 * mw, mh);
        { the channel heads, hot in (right) and hot out (left), with their nozzles }
        TempRGB(E^.HotOut, lx, ly, t);
        SetCol(Round(lx), Round(ly), Round(t));
        FillR(x + 4, ty + 4, mw - 4, mh - 8);
        FillR(x + 8, ty - 8, 8, 12);
        TempRGB(E^.HotIn, lx, ly, t);
        SetCol(Round(lx), Round(ly), Round(t));
        FillR(x + w - mw, ty + 4, mw - 4, mh - 8);
        FillR(x + w - 16, ty - 8, 8, 12);
        SetCol(50, 54, 62);
        RectR(x + 4, ty + 4, mw - 4, mh - 8);
        RectR(x + w - mw, ty + 4, mw - 4, mh - 8);
        { the shell nozzles: cold in below on the left, cold out above on the right }
        TempRGB(E^.ColdIn, lx, ly, t);
        SetCol(Round(lx), Round(ly), Round(t));
        FillR(x + mw + 6, ty + mh, 8, 6);
        TempRGB(E^.Temp, lx, ly, t);
        SetCol(Round(lx), Round(ly), Round(t));
        FillR(x + w - mw - 14, ty - 6, 8, 6);
      end;

    EQ_COOLTOWER:
      begin
        { an induced-draft cooling tower: fan stack on top, louvred casing, fill with the water
          falling through it, cold water basin; the water takes the colour of its temperature }
        mh := h * 0.2;            { the fan stack }
        ty := y + mh;             { the casing top }
        ly := y + h * 0.84;       { the basin top }
        SetCol(r, g, b);
        FillR(x + w * 0.22, y + 4, w * 0.56, mh - 4);
        Shade(r, g, b, 0.55);
        RectR(x + w * 0.22, y + 4, w * 0.56, mh - 4);
        { the fan blades turning (seen from the side) }
        if EquipRunning(i) then a := E^.Phase * 3 else a := 0;
        SetCol(60, 64, 72);
        for k := 0 to 2 do
        begin
          t := Cos(a + k * 2.1);
          FillR(x + w / 2 + t * w * 0.24 - 3, y + 2, 6, 4);
        end;
        { the casing }
        SetCol(168, 176, 182);
        FillR(x + 4, ty, w - 8, ly - ty);
        SetCol(110, 116, 124);
        RectR(x + 4, ty, w - 8, ly - ty);
        { the fill: warm water in at the top, falling and cooling }
        n := 10;
        for k := 0 to n - 1 do
        begin
          TempRGB(E^.HotIn + (E^.Temp - E^.HotIn) * (k + 0.5) / n, lx, mw, t);
          SetCol(Round(lx), Round(mw), Round(t), 150);
          FillR(x + 14, ty + 10 + (ly - ty - 34) * k / n, w - 28, (ly - ty - 34) / n + 1);
        end;
        if EquipRunning(i) then
        begin
          SetCol(235, 240, 250, 160);
          for k := 0 to 5 do
          begin
            t := Frac(E^.Phase * 0.4 + k / 6);
            LineR(x + 20 + k * (w - 40) / 5, ty + 10 + t * (ly - ty - 36), x + 20 + k * (w - 40) / 5,
              ty + 18 + t * (ly - ty - 36));
          end;
        end;
        { the air inlet louvres at the bottom of the casing }
        SetCol(110, 116, 124);
        for k := 0 to 3 do
          LineR(x + 6, ly - 22 + k * 5, x + w - 6, ly - 25 + k * 5);
        { the basin and the water in it }
        SetCol(120, 124, 132);
        FillR(x, ly, w, h - (ly - y));
        TempRGB(E^.Temp, lx, mw, t);
        SetCol(Round(lx), Round(mw), Round(t));
        FillR(x + 4, ly + 4, w - 8, h - (ly - y) - 8);
        { the warm water inlet (left, top) and the cold water outlet (right, basin) }
        TempRGB(E^.HotIn, lx, mw, t);
        SetCol(Round(lx), Round(mw), Round(t));
        FillR(x - 6, ty + 6, 12, 8);
        TempRGB(E^.Temp, lx, mw, t);
        SetCol(Round(lx), Round(mw), Round(t));
        FillR(x + w - 6, ly + 6, 12, 8);
      end;

    EQ_CHILLER:
      begin
        { a packaged water chiller: compressor, condenser (top shell), evaporator (bottom
          shell), control panel showing the chilled water temperature }
        SetCol(70, 74, 82);
        FillR(x, y + h - 10, w, 10);
        { condenser: warm }
        TempRGB(E^.HotOut, lx, mw, t);
        SetCol(Round(lx), Round(mw), Round(t));
        FillR(x + 8, y + h * 0.3, w * 0.66, h * 0.24);
        { evaporator: the chilled water }
        TempRGB(E^.Temp, lx, mw, t);
        SetCol(Round(lx), Round(mw), Round(t));
        FillR(x + 8, y + h * 0.58, w * 0.66, h * 0.24);
        SetCol(50, 54, 62);
        RectR(x + 8, y + h * 0.3, w * 0.66, h * 0.24);
        RectR(x + 8, y + h * 0.58, w * 0.66, h * 0.24);
        for k := 0 to 1 do
        begin
          FillR(x + 4, y + h * (0.3 + k * 0.28) + 2, 6, h * 0.24 - 4);
          FillR(x + 4 + w * 0.66, y + h * (0.3 + k * 0.28) + 2, 6, h * 0.24 - 4);
        end;
        { the compressor on top, in the state colour }
        SetCol(r, g, b);
        FillR(x + 18, y + 4, w * 0.4, h * 0.24);
        Shade(r, g, b, 0.55);
        RectR(x + 18, y + 4, w * 0.4, h * 0.24);
        if EquipRunning(i) then
        begin
          SetCol(255, 255, 255, 120);
          t := Frac(E^.Phase * 0.5);
          FillR(x + 22 + t * (w * 0.4 - 12), y + 8, 4, h * 0.24 - 8);
        end;
        { the control panel with the chilled water temperature }
        SetCol(40, 44, 52);
        FillR(x + w * 0.74 + 6, y + 8, w * 0.26 - 10, h - 22);
        SetCol(18, 21, 26);
        FillR(x + w * 0.74 + 10, y + 16, w * 0.26 - 18, h * 0.26);
        DrawSegStr(x + w - 10, y + 20, h * 0.18, Format('%3.0f', [E^.Temp]), 70, 235, 115);
        if EquipRunning(i) then SetCol(70, 235, 115) else SetCol(90, 94, 102);
        FillR(x + w * 0.74 + 12, y + h * 0.5, 6, 6);
      end;

    EQ_PANEL:
      begin
        { an electrical cabinet: steel frame, mounting plate, door seam and handle }
        SetCol(150, 155, 162);
        FillR(x, y, w, h);
        SetC(Th.OverlayBg);
        FillR(x + 6, y + 18, w - 12, h - 24);
        SetCol(95, 100, 108);
        RectR(x, y, w, h);
        RectR(x + 6, y + 18, w - 12, h - 24);
        SetCol(120, 125, 132);
        LineR(x + w / 2, y + 2, x + w / 2, y + 16);
        FillR(x + w - 16, y + h / 2 - 14, 5, 28);
        { name plate }
        SetCol(235, 236, 238);
        FillR(x + 8, y + 3, fmin(w - 16, (Length(E^.Name) * 8 + 8) / Zoom), 12 / Zoom + 1);
        { feet }
        SetCol(80, 84, 90);
        FillR(x + 8, y + h, 14, 4);
        FillR(x + w - 22, y + h, 14, 4);
      end;

    EQ_CONVEYOR, EQ_BELT:
      begin
        ty := y + h * 0.2;       { the deck top }
        mh := h * 0.3;           { deck height }
        { legs }
        SetCol(85, 90, 100);
        n := Max(2, Round(w / 110) + 1);
        for k := 0 to n - 1 do
        begin
          t := x + 6 + (w - 18) * k / (n - 1);
          FillR(t, ty + mh, 6, y + h - ty - mh);
          FillR(t - 3, y + h - 3, 12, 3);
        end;
        if E^.Kind = EQ_CONVEYOR then
        begin
          { side rail and rollers }
          SetCol(70, 76, 86);
          FillR(x, ty + mh * 0.55, w, mh * 0.45);
          rad := mh * 0.45;
          t := x + rad + 2;
          k := 0;
          while t < x + w - rad do
          begin
            DiscC(t, ty + rad, rad, 196, 200, 208);
            SetCol(110, 116, 126);
            RingC(t, ty + rad, rad, False);
            a := E^.Phase * 1.5 * (1 - 2 * Ord(E^.Flip)) + k;
            LineR(t, ty + rad, t + Cos(a) * rad * 0.8, ty + rad + Sin(a) * rad * 0.8);
            t := t + rad * 2 + 3;
            Inc(k);
          end;
        end
        else
        begin
          { two drums and the belt around them; marks move with the belt }
          rad := mh * 0.5;
          DiscC(x + rad, ty + rad, rad, 150, 156, 166);
          DiscC(x + w - rad, ty + rad, rad, 150, 156, 166);
          SetCol(70, 76, 86);
          RingC(x + rad, ty + rad, rad, False);
          RingC(x + w - rad, ty + rad, rad, False);
          SetCol(55, 58, 64);
          FillR(x + rad, ty, w - 2 * rad, 4);
          FillR(x + rad, ty + mh - 3, w - 2 * rad, 3);
          SetCol(150, 154, 160);
          a := Frac(E^.Phase * 0.5) * 18;
          if E^.Flip then a := 18 - a;
          t := x + rad + a;
          while t < x + w - rad - 4 do
          begin
            FillR(t, ty, 4, 2);
            t := t + 18;
          end;
          { the frame under the top belt }
          SetCol(110, 116, 126);
          FillR(x + rad, ty + mh * 0.35, w - 2 * rad, mh * 0.3);
        end;
        { the drive motor under the drive end }
        mw := fmin(64, w * 0.25);
        if E^.Flip then DrawMotorBody(x + 4, ty + mh + 4, mw, h * 0.32, True, r, g, b)
        else DrawMotorBody(x + w - mw - 4, ty + mh + 4, mw, h * 0.32, False, r, g, b);
      end;

    EQ_PUMP:
      begin
        { a centrifugal water pump: base, blue volute with its impeller, discharge, motor }
        SetCol(60, 64, 72);
        FillR(x, y + h - 6, w, 6);
        rad := fmin(h * 0.4, w * 0.24);
        if E^.Flip then cx := x + w - rad - 8 else cx := x + rad + 8;
        cy := y + h - 7 - rad;
        SetCol(40, 100, 180);
        if E^.Flip then FillR(cx - rad, y, rad * 0.7, cy - y) else FillR(cx + rad * 0.3, y, rad * 0.7, cy - y);
        SetCol(25, 70, 130);
        if E^.Flip then RectR(cx - rad, y, rad * 0.7, cy - y) else RectR(cx + rad * 0.3, y, rad * 0.7, cy - y);
        { suction flange on the outer side }
        SetCol(90, 96, 106);
        if E^.Flip then FillR(cx + rad, cy - 5, 8, 10) else FillR(cx - rad - 8, cy - 5, 8, 10);
        DiscC(cx, cy, rad, 50, 120, 200);
        SetCol(25, 70, 130);
        RingC(cx, cy, rad, False);
        SetCol(225, 235, 250);
        for k := 0 to 5 do
        begin
          a := E^.Phase + k * Pi / 3;
          LineR(cx + Cos(a) * rad * 0.3, cy + Sin(a) * rad * 0.3, cx + Cos(a + 0.5) * rad * 0.8, cy + Sin(a + 0.5) * rad * 0.8);
        end;
        DiscC(cx, cy, rad * 0.28, 170, 178, 190);
        mw := w - 2 * rad - 12;
        if mw > 10 then
        begin
          if E^.Flip then DrawMotorBody(x, cy - rad * 0.55, mw, rad * 1.1, True, r, g, b)
          else DrawMotorBody(cx + rad + 2, cy - rad * 0.55, mw, rad * 1.1, False, r, g, b);
        end;
      end;

    EQ_POND:
      begin
        { an earth basin with sloping banks, grass and reeds, and its water }
        a := fclamp(E^.Level / 100, 0, 1);
        ty := y + h * 0.15;
        QuadC(x, ty, x + w, ty, x + w * 0.86, y + h, x + w * 0.14, y + h, 122, 92, 60);
        if a > 0 then
        begin
          ly := ty + (y + h - ty) * (1 - a);
          lx := x + w * 0.14 * (ly - ty) / (y + h - ty);
          QuadC(lx, ly, x + w - (lx - x), ly, x + w * 0.86, y + h, x + w * 0.14, y + h, 55, 128, 205, 230);
          t := SDL_GetTicksNS / 1e9;
          SetCol(175, 212, 245);
          mw := lx + 6;
          while mw < x + w - (lx - x) - 10 do
          begin
            LineR(mw, ly + 2 + Sin(t * 2 + mw * 0.08) * 1.5, mw + 8, ly + 2 + Sin(t * 2 + (mw + 8) * 0.08) * 1.5);
            mw := mw + 14;
          end;
        end;
        SetCol(72, 150, 62);
        FillR(x - 10, ty - 5, w * 0.16 + 10, 6);
        FillR(x + w * 0.84, ty - 5, w * 0.16 + 10, 6);
        SetCol(60, 125, 50);
        for k := 0 to 5 do
        begin
          LineR(x + 4 + k * 5, ty - 5, x + 2 + k * 5, ty - 18 - (k mod 3) * 5);
          LineR(x + w - 6 - k * 5, ty - 5, x + w - 4 - k * 5, ty - 14 - (k mod 2) * 6);
        end;
      end;

    EQ_POOL:
      begin
        { a tiled pool with a rim and a ladder }
        a := fclamp(E^.Level / 100, 0, 1);
        SetCol(176, 222, 236);
        FillR(x, y + 8, w, h - 8);
        SetCol(140, 192, 212);
        t := x + 16;
        while t < x + w do
        begin
          LineR(t, y + 8, t, y + h);
          t := t + 16;
        end;
        t := y + 24;
        while t < y + h do
        begin
          LineR(x, t, x + w, t);
          t := t + 16;
        end;
        ly := y + 8 + (h - 8) * (1 - a);
        if a > 0 then
        begin
          SetCol(45, 125, 220, 175);
          FillR(x, ly, w, y + h - ly);
          SetCol(190, 225, 250);
          LineR(x, ly, x + w, ly);
        end;
        SetCol(120, 126, 134);
        RectR(x, y + 8, w, h - 8);
        SetCol(208, 210, 214);
        FillR(x - 8, y, w + 16, 8);
        SetCol(150, 154, 160);
        RectR(x - 8, y, w + 16, 8);
        { ladder }
        SetCol(196, 200, 206);
        FillR(x + w - 26, y - 14, 3, h * 0.6 + 14);
        FillR(x + w - 12, y - 14, 3, h * 0.6 + 14);
        t := y + 4;
        while t < y + h * 0.6 do
        begin
          FillR(x + w - 26, t, 17, 2);
          t := t + 10;
        end;
      end;

    EQ_WELL:
      begin
        { a stone well: roof on two posts, a winch and bucket, the shaft down to the ground water }
        a := fclamp(E^.Level / 100, 0, 1);
        ty := y + h * 0.45;   { ground level, the top of the stone ring }
        SetCol(42, 38, 36);
        FillR(x + w * 0.16, ty, w * 0.68, y + h - ty);
        mh := (y + h - ty) * 0.7 * a;
        if mh > 0 then
        begin
          SetCol(50, 115, 195);
          FillR(x + w * 0.16, y + h - mh, w * 0.68, mh);
          SetCol(150, 200, 245);
          LineR(x + w * 0.16, y + h - mh, x + w * 0.84, y + h - mh);
        end;
        SetCol(110, 106, 100);
        RectR(x + w * 0.16, ty, w * 0.68, y + h - ty);
        { the stone ring above the ground }
        SetCol(150, 145, 138);
        FillR(x, ty - h * 0.14, w, h * 0.14);
        SetCol(105, 100, 94);
        for k := 0 to 4 do LineR(x + w * k / 5 + Ord(k mod 2 = 1) * 6, ty - h * 0.14, x + w * k / 5 + Ord(k mod 2 = 1) * 6, ty);
        LineR(x, ty - h * 0.07, x + w, ty - h * 0.07);
        RectR(x, ty - h * 0.14, w, h * 0.14);
        { posts, winch, rope and bucket }
        SetCol(120, 80, 45);
        FillR(x + w * 0.06, y + h * 0.1, 6, ty - h * 0.14 - y - h * 0.1);
        FillR(x + w * 0.94 - 6, y + h * 0.1, 6, ty - h * 0.14 - y - h * 0.1);
        SetCol(90, 60, 35);
        FillR(x + w * 0.06, y + h * 0.17, w * 0.88, 4);
        SetCol(200, 190, 160);
        LineR(x + w / 2, y + h * 0.19, x + w / 2, ty - h * 0.22);
        SetCol(110, 80, 50);
        FillR(x + w / 2 - 6, ty - h * 0.22, 12, 10);
        { roof }
        TriC(x - 8, y + h * 0.11, x + w + 8, y + h * 0.11, x + w / 2, y, 160, 62, 44);
        SetCol(110, 40, 30);
        LineR(x - 8, y + h * 0.11, x + w + 8, y + h * 0.11);
      end;

    EQ_FIRE:
      begin
        { logs, and flames as high as the fire is strong (smoke when it is out) }
        SetCol(96, 60, 36);
        FillR(x + w * 0.1, y + h - 8, w * 0.8, 6);
        SetCol(70, 44, 26);
        FillR(x + w * 0.2, y + h - 12, w * 0.6, 5);
        if EquipRunning(i) and (E^.Heat > 0) then
        begin
          a := fmax(0.2, E^.Heat / 100);
          n := 5;
          for k := 0 to n - 1 do
          begin
            t := x + w * (k + 0.5) / n;
            mh := h * a * (0.55 + 0.45 * Abs(Sin(E^.Phase * 1.7 + k * 1.9)));
            if k mod 2 = 0 then mh := mh * 0.85;
            TriC(t - w * 0.13, y + h - 8, t + w * 0.13, y + h - 8, t, y + h - 8 - mh, 230, 60, 30, 230);
            TriC(t - w * 0.08, y + h - 8, t + w * 0.08, y + h - 8, t, y + h - 8 - mh * 0.7, 255, 150, 30, 235);
            TriC(t - w * 0.04, y + h - 8, t + w * 0.04, y + h - 8, t, y + h - 8 - mh * 0.4, 255, 230, 90, 240);
          end;
        end
        else
        begin
          for k := 0 to 2 do
            DiscC(x + w * (0.4 + k * 0.1), y + h - 20 - k * 14, 6 + k * 3, 120, 122, 128, 120);
        end;
      end;
  end;
  EqManual := False;
end;

{ the status words of a piece: RUN / STOP for motors, OPEN / CLOSED for valves ... }
function EquipStateWord(i: Integer): string;
var
  K: Integer;
  run: Boolean;
begin
  K := Equips[i].Kind;
  run := EquipRunning(i);
  case K of
    EQ_DIVERTER: if run then Result := 'POS 1' else Result := 'POS 2';
    EQ_SHUTTER, EQ_SLIDE: if run then Result := 'OPEN' else Result := 'CLOSED';
    EQ_HEATER, EQ_IRHEATER: if run then Result := 'HEAT' else Result := 'OFF';
  else
    if run then Result := 'RUN' else Result := 'STOP';
  end;
  case Equips[i].State of
    EQS_RUN, EQS_STOP: Result := 'AUTO ' + Result;
    EQS_MSTART, EQS_MSTOP: Result := 'MAN ' + Result;
    EQS_DISABLE: Result := 'DISABLED';
    EQS_FAULT: Result := 'FAULT';
  end;
end;

function FmtRunTime(t: Single): string;
var
  hh, mm: Integer;
begin
  hh := Trunc(t) div 3600;
  mm := (Trunc(t) div 60) mod 60;
  Result := Format('%.2d:%.2d:', [hh, mm]) + FormatFloat('00.0', t - hh * 3600 - mm * 60);
end;

{ the sequence box text: mode, request, the step in progress }
procedure DrawSequenceText(i: Integer; ux, uy: Single);
var
  E: ^TEquipObj;
  steps: array[0..MAX_SEQ_STEP - 1] of Byte;
  n, j, st: Integer;
  s, who: string;
  req, starting: Boolean;
begin
  E := @Equips[i];
  SetC(Th.Title);
  TextR(ux + 8, uy + 6, E^.Name + ' / Delays');
  n := SeqStepList(steps);
  req := E^.LastReq;
  SetC(Th.Text);
  if i <> MasterSequence then
  begin
    TextR(ux + 8, uy + 20, 'Inactive: one sequence runs a page');
    Exit;
  end;
  case E^.Mode of
    SEQ_AUTO: if req then s := 'AUTO START' else s := 'AUTO STOP';
    SEQ_MANUAL: s := 'MANUAL';
  else
    s := 'E-STOP';
  end;
  if E^.Mode = SEQ_ESTOP then SetC(Th.StatusErr) else SetC(Th.Text);
  TextR(ux + 8, uy + 20, 'Mode: ' + s);
  SetC(Th.Text);
  if req then s := Format('External Request: ON  (held %.1fs)', [E^.ReqT])
  else s := 'External Request: OFF';
  TextR(ux + 8, uy + 32, s);
  if n = 0 then s := 'No steps: give a motor a step no.'
  else if E^.Mode <> SEQ_AUTO then s := Format('Steps: %d (not automatic now)', [n])
  else
  begin
    starting := req and (E^.SeqPos < n);
    if starting or ((not req) and (E^.SeqPos > 0)) then
    begin
      if starting then st := steps[E^.SeqPos] else st := steps[E^.SeqPos - 1];
      who := '';
      for j := 0 to MAX_EQUIP - 1 do
        if Equips[j].Active and EquipActuated(Equips[j].Kind) and (Equips[j].SeqStep = st) and (who = '') then
          who := Equips[j].Name;
      if starting then s := Format('Start step %d/%d [%s] %.1f/%.1f s', [E^.SeqPos + 1, n, who, E^.SeqT, StepDelay(st)])
      else s := Format('Stop step %d/%d [%s] %.1f/%.1f s', [E^.SeqPos, n, who, E^.SeqT, StepDelay(st)]);
    end
    else if req then s := Format('All %d steps started', [n])
    else s := 'All steps stopped';
  end;
  TextR(ux + 8, uy + 44, s);
end;

{ names, run state and timer, levels: screen-size text anchored to the zoomed canvas }
procedure DrawEquipText(i: Integer);
var
  E: ^TEquipObj;
  ux, uy, uw, uh, v, r0, cxs, cys: Single;
  un: string;
  s, st: string;
  r, g, b: Byte;
  k, n: Integer;
begin
  E := @Equips[i];
  ux := (E^.X - ViewX) * Zoom;
  uy := (E^.Y - ViewY) * Zoom;
  uw := E^.W * Zoom;
  uh := E^.H * Zoom;
  case E^.Kind of
    EQ_SILO:
      begin
        SetCol(25, 40, 70);
        if E^.Name <> '' then TextR(ux + 8, uy + 8, E^.Name);
        TextR(ux + 8, uy + 20, Format('Level %.0f%%', [EquipLevel(i)]));
      end;
    EQ_LAMP:
      begin
        SetC(Th.Text);
        TextR(ux + uw + 5, uy + (uh - 8) / 2, E^.Name);
      end;
    EQ_SEQUENCE:
      DrawSequenceText(i, ux, uy);
    EQ_GAUGE:
      begin
        SetC(Th.Text);
        TextR(ux, uy - 13, E^.Name);
        r0 := (fmin(E^.W, E^.H) / 2 - 4) * Zoom;
        cxs := ux + uw / 2;
        cys := uy + uh / 2 + r0 * 0.08;
        if AnalogValue(E^.Src, v, un) then s := Format('%.1f %s', [v, un]) else s := '--';
        SetCol(25, 28, 34);
        TextR(cxs - Length(s) * 4, cys + r0 * 0.32, s);
        SetCol(90, 94, 102);
        TextR(cxs - Length(E^.Src) * 4, cys - r0 * 0.42, E^.Src);
        s := FloatToStrF(E^.RMin, ffGeneral, 5, 0);
        TextR(cxs - r0 * 0.55 - Length(s) * 4, cys + r0 * 0.62, s);
        s := FloatToStrF(E^.RMax, ffGeneral, 5, 0);
        TextR(cxs + r0 * 0.55 - Length(s) * 4, cys + r0 * 0.62, s);
      end;
    EQ_DIGITAL:
      begin
        SetC(Th.Text);
        TextR(ux, uy - 13, E^.Name);
        if not AnalogValue(E^.Src, v, un) then un := '';
        SetC(Th.Title);
        TextR(ux + uw + 4, uy + uh / 2 - 4, un);
        SetC(Th.TextDim);
        TextR(ux, uy + uh + 3, E^.Src);
      end;    EQ_PANEL:
      begin
        SetCol(30, 34, 40);
        TextR(ux + 11 * Zoom, uy + 5 * Zoom, E^.Name);
      end;
    EQ_POND, EQ_POOL, EQ_WELL:
      begin
        SetC(Th.Text);
        TextR(ux, uy - 13, E^.Name);
        if E^.Level >= 99.5 then SetC(Th.StatusErr) else SetC(Th.Title);
        s := Format('Water %.0f%%', [E^.Level]);
        if E^.Level >= 99.5 then s := s + ' FULL';
        TextR(ux + Length(E^.Name) * 8 + 8, uy - 13, s);
      end;
    EQ_LEGEND:
      begin
        SetC(Th.Title);
        TextR(ux + 8, uy + 6, E^.Name);
        for n := 0 to EQS_COUNT - 1 do
        begin
          k := LegendOrder[n];
          EqStateRGB(k, r, g, b);
          SetCol(r, g, b);
          FillR(ux + 8, uy + 22 + n * 18, 28, 12);
          if k in [EQS_MSTART, EQS_MSTOP] then
          begin
            SetCol(245, 145, 35);
            FillR(ux + 8, uy + 26 + n * 18, 28, 4);
          end;
          SetCol(60, 62, 68);
          RectR(ux + 8, uy + 22 + n * 18, 28, 12);
          SetC(Th.Text);
          TextR(ux + 44, uy + 24 + n * 18, StateLegend[k]);
        end;
      end;
    EQ_RAIN, EQ_FIRE:
      begin
        if E^.Name <> '' then
        begin
          SetC(Th.Text);
          TextR(ux, uy - 13, E^.Name);
        end;
        if E^.Kind = EQ_RAIN then
        begin
          if EquipRunning(i) then st := Format('RAIN %.0f%%', [E^.Level]) else st := 'DRY';
        end
        else if EquipRunning(i) then st := Format('FIRE %.0f%%', [E^.Heat])
        else st := 'OUT';
        if EquipRunning(i) then EqStateText(EQS_FAULT) else SetC(Th.TextDim);
        if E^.Kind = EQ_RAIN then EqStateText(E^.State);
        TextR(ux + Length(E^.Name) * 8 + 8, uy - 13, st);
      end;
  else
    begin
      if E^.Name <> '' then
      begin
        SetC(Th.Text);
        TextR(ux, uy - 24, E^.Name);
        TextR(ux + 1, uy - 24, E^.Name);   { bold }
      end;
      if EquipActuated(E^.Kind) then
      begin
        st := EquipStateWord(i);
        if E^.State = EQS_FAULT then
        begin
          if (SDL_GetTicksNS div 400000000) mod 2 <> 0 then st := '';
        end
        else if EquipRunning(i) then st := st + ' ' + FmtRunTime(E^.RunTime);
        if E^.SeqStep > 0 then st := st + Format('  S%d', [E^.SeqStep]);
        if EquipLinkCell(i) <> nil then st := st + ' [linked]';
        EqStateText(E^.State);
        TextR(ux, uy - 13, st);
        if E^.Kind = EQ_PUMP then
        begin
          n := PumpSource(i);
          if n < 0 then s := 'no water source near'
          else if Equips[n].Level <= 0 then s := 'from ' + Equips[n].Name + ': DRY'
          else s := Format('from %s (%.0f%%)', [Equips[n].Name, Equips[n].Level]);
          if (n < 0) or (Equips[n].Level <= 0) then SetC(Th.StatusErr) else SetC(Th.TextDim);
          TextR(ux, uy + uh + 4, s);
        end;
        SetC(Th.TextDim);
        case E^.Kind of
          EQ_HEATEX:
            TextR(ux, uy + uh + 4, Format('shell %.0f>%.0fC  tube %.0f>%.0fC  %.0f kW', [E^.ColdIn, E^.Temp, E^.HotIn,
              E^.HotOut, E^.Duty]));
          EQ_COOLTOWER:
            TextR(ux, uy + uh + 4, Format('water %.0f>%.0fC  fan %.0f%%  %.0f kW', [E^.HotIn, E^.Temp,
              E^.Level * Ord(EquipRunning(i)), E^.Duty]));
          EQ_CHILLER:
            TextR(ux, uy + uh + 4, Format('CHW %.1f>%.1fC (SP %.1f)  %.0f kW', [E^.HotIn, E^.Temp, E^.RMax, E^.Duty]));
        end;
        { the sequence is about to start / stop it }
        if E^.Wait <> 0 then
        begin
          SetCol(245, 145, 35);
          if E^.Wait > 0 then s := Format('delay: step %d starts in %.1fs', [E^.SeqStep, E^.Wait])
          else s := Format('delay: step %d stops in %.1fs', [E^.SeqStep, -E^.Wait]);
          TextR(ux, uy + uh + 4, s);
        end;
      end;
    end;
  end;
end;

{ Front = the equipment drawn over the pipes, else the one behind them }
procedure DrawEquips(Front: Boolean);
var
  i: Integer;
begin
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and LayerShown(Equips[i].Layer) and (EquipFront(Equips[i].Kind) = Front) then
      DrawEquipShape(i);
end;

procedure DrawEquipTexts;
var
  i: Integer;
begin
  CanvasXf := False;
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and LayerShown(Equips[i].Layer) then DrawEquipText(i);
  CanvasXf := True;
end;

{ the equipment under wx, wy on a layer that can be picked (Part 1 = its resize corner), or -1 }
function EquipAt(wx, wy: Single; out Part: Integer): Integer;
var
  i, pass: Integer;
begin
  Part := 0;
  { front equipment first, it is drawn on top }
  for pass := 0 to 1 do
    for i := MAX_EQUIP - 1 downto 0 do
      with Equips[i] do
        if Active and LayerEditable(Layer) and (EquipFront(Kind) = (pass = 0)) and
          (wx >= X - 2) and (wx <= X + W + 2) and (wy >= Y - 2) and (wy <= Y + H + 2) then
        begin
          if (wx >= X + W - EQ_HANDLE) and (wy >= Y + H - EQ_HANDLE) then Part := 1;
          Exit(i);
        end;
  Result := -1;
end;

{ selection outline, resize corner and a dashed line to the linked part }
procedure OutlineEquip(i: Integer);
var
  c: PCell;
begin
  with Equips[i] do
  begin
    SetC(Th.Select);
    RectR(X - 3, Y - 3, W + 6, H + 6);
    FillR(X + W - 8, Y + H - 8, 8, 8);
    c := EquipLinkCell(i);
    if c <> nil then
    begin
      SetC(Th.Paste);
      RectR(LinkX * CELL - 2, LinkY * CELL - 2, CELL + 4, CELL + 4);
      LineR(X + W / 2, Y + H / 2, LinkX * CELL + HALF, LinkY * CELL + HALF);
    end;
  end;
end;

{ ---------------------------------------------------------------- electrical drawing }

var
  EMapX, EMapY: Single;   { the cell centre being drawn }
  EVert: Boolean;         { its terminals are N / S }

{ local coordinates (u along the terminals, v across them) -> canvas }
function EUx(u, v: Single): Single;
begin
  if EVert then Result := EMapX - v else Result := EMapX + u;
end;

function EVy(u, v: Single): Single;
begin
  if EVert then Result := EMapY + u else Result := EMapY + v;
end;

procedure ELine(u1, v1, u2, v2: Single);
begin
  LineR(EUx(u1, v1), EVy(u1, v1), EUx(u2, v2), EVy(u2, v2));
end;

procedure EBox(u1, v1, u2, v2: Single; Fill: Boolean);
var
  x1, y1, x2, y2: Single;
begin
  x1 := fmin(EUx(u1, v1), EUx(u2, v2));
  x2 := fmax(EUx(u1, v1), EUx(u2, v2));
  y1 := fmin(EVy(u1, v1), EVy(u2, v2));
  y2 := fmax(EVy(u1, v1), EVy(u2, v2));
  if Fill then FillR(x1, y1, x2 - x1, y2 - y1) else RectR(x1, y1, x2 - x1, y2 - y1);
end;

{ the colour of a wire: red on a live net, blue on a neutral one, grey when dead }
procedure EWireCol(Live: Byte);
begin
  case Live of
    1: SetCol(225, 70, 60);
    2: SetCol(70, 125, 235);
  else
    SetCol(128, 134, 142);
  end;
end;

procedure EInk;
begin
  SetC(Th.Text);
end;

procedure EOnCol;
begin
  SetCol(60, 205, 95);
end;

procedure EBadCol;
begin
  SetCol(235, 60, 50);
end;

{ a thick wire from the centre out to side d, from r0 to r1 pixels }
procedure EStub(cx, cy: Single; d: Integer; r0, r1: Single);
begin
  case d of
    0: FillR(cx + r0, cy - 1, r1 - r0, 2);
    2: FillR(cx - r1, cy - 1, r1 - r0, 2);
    1: FillR(cx - 1, cy + r0, 2, r1 - r0);
  else
    FillR(cx - 1, cy - r1, 2, r1 - r0);
  end;
end;

function EPt(cx: Single; d: Integer; r: Single): Single;
begin
  Result := cx + DXS[d] * r;
end;

function EPty(cy: Single; d: Integer; r: Single): Single;
begin
  Result := cy + DYS[d] * r;
end;

procedure DrawECell(x, y: Integer);
const
  LampRGB: array[0..4, 0..2] of Byte = ((60, 210, 90), (235, 60, 50), (245, 205, 40), (240, 240, 245), (70, 140, 245));
var
  c: PECell;
  cx, cy, a, f: Single;
  d, n, cs, o1, o2, i1, i2, k: Integer;
  closed: Boolean;
begin
  c := @EGrid[x, y];
  cx := x * CELL + HALF;
  cy := y * CELL + HALF;
  EMapX := cx;
  EMapY := cy;
  EVert := c^.Dir = 1;
  EWireCol(c^.Live);
  case c^.Kind of
    ekWire, ekTerminal:
      begin
        n := 0;
        for d := 0 to 3 do
          if (c^.Conn and (1 shl d)) <> 0 then
          begin
            EStub(cx, cy, d, 0, HALF);
            Inc(n);
          end;
        if n = 0 then FillR(cx - 2, cy - 2, 4, 4);
        if n >= 3 then FillR(cx - 3, cy - 3, 6, 6);   { a joint }
        if c^.Kind = ekTerminal then
        begin
          DiscC(cx, cy, 4, 200, 204, 210);
          SetCol(70, 74, 80);
          RingC(cx, cy, 4, False);
        end;
        Exit;
      end;
    ekCross:
      begin
        EStub(cx, cy, 0, 0, HALF);
        EStub(cx, cy, 2, 0, HALF);
        EStub(cx, cy, 3, 5, HALF);
        EStub(cx, cy, 1, 5, HALF);
        LineR(cx, cy - 5, cx + 5, cy - 2);
        LineR(cx + 5, cy - 2, cx + 5, cy + 2);
        LineR(cx + 5, cy + 2, cx, cy + 5);
        Exit;
      end;
    ekSw2, ekSw3:
      begin
        if c^.Kind = ekSw2 then
        begin
          cs := (2 + c^.Dir) and 3;
          o1 := c^.Dir and 3;
          o2 := (1 + c^.Dir) and 3;
          EStub(cx, cy, cs, 6, HALF);
          EStub(cx, cy, o1, 6, HALF);
          EStub(cx, cy, o2, 6, HALF);
          EOnCol;
          if c^.Sel = 0 then k := o1 else k := o2;
          LineR(EPt(cx, cs, 6), EPty(cy, cs, 6), EPt(cx, k, 6), EPty(cy, k, 6));
          LineR(EPt(cx, cs, 6) + 1, EPty(cy, cs, 6), EPt(cx, k, 6) + 1, EPty(cy, k, 6));
          EInk;
          DiscC(EPt(cx, cs, 6), EPty(cy, cs, 6), 2, 230, 230, 235);
          DiscC(EPt(cx, o1, 6), EPty(cy, o1, 6), 1.5, 200, 200, 205);
          DiscC(EPt(cx, o2, 6), EPty(cy, o2, 6), 1.5, 200, 200, 205);
        end
        else
        begin
          i1 := (2 + c^.Dir) and 3;
          i2 := (3 + c^.Dir) and 3;
          o1 := c^.Dir and 3;
          o2 := (1 + c^.Dir) and 3;
          for d := 0 to 3 do EStub(cx, cy, d, 7, HALF);
          EOnCol;
          if c^.Sel = 0 then
          begin
            LineR(EPt(cx, i1, 7), EPty(cy, i1, 7), EPt(cx, o1, 7), EPty(cy, o1, 7));
            LineR(EPt(cx, i2, 7), EPty(cy, i2, 7), EPt(cx, o2, 7), EPty(cy, o2, 7));
          end
          else
          begin
            LineR(EPt(cx, i1, 7), EPty(cy, i1, 7), EPt(cx, o2, 7), EPty(cy, o2, 7));
            LineR(EPt(cx, i2, 7), EPty(cy, i2, 7), EPt(cx, o1, 7), EPty(cy, o1, 7));
          end;
          EInk;
          RectR(cx - 8, cy - 8, 16, 16);
        end;
        Exit;
      end;
  end;
  { a two-terminal device: the wire stubs, then its symbol }
  ELine(-12, 0, -7, 0);
  ELine(7, 0, 12, 0);
  ELine(-12, 0.5, -7, 0.5);
  ELine(7, 0.5, 12, 0.5);
  closed := c^.Energized;
  case c^.Kind of
    ekNO, ekNC, ekPBNO, ekPBNC, ekPBLatch, ekSelector, ekEStop, ekOL, ekFloat, ekPhoto:
      begin
        ELine(-7, 0, -4, 0);
        ELine(4, 0, 7, 0);
        if (c^.Kind = ekOL) and c^.Tripped then EBadCol
        else if closed then EOnCol else EInk;
        ELine(-4, -6, -4, 6);
        ELine(4, -6, 4, 6);
        ELine(-3.5, -6, -3.5, 6);
        ELine(4.5, -6, 4.5, 6);
        if c^.Kind in [ekNC, ekPBNC, ekEStop, ekOL] then ELine(-7, 7, 7, -7);
        if closed then
        begin
          EOnCol;
          ELine(-4, 0, 4, 0);
        end;
        EInk;
        case c^.Kind of
          ekPBNO, ekPBNC, ekPBLatch:
            begin
              { the push actuator }
              if c^.Held or ((c^.Kind = ekPBLatch) and c^.On) then EOnCol else EInk;
              ELine(0, -6, 0, -11);
              ELine(-4, -11, 4, -11);
              if c^.Kind = ekPBLatch then
              begin
                ELine(-3, -13, 0, -11);
                ELine(0, -11, 3, -13);
              end;
            end;
          ekSelector:
            begin
              ELine(0, -6, 0, -9);
              ELine(-4, -12, 4, -8);
            end;
          ekEStop:
            begin
              ELine(0, -6, 0, -8);
              if c^.On then DiscC(EUx(0, -10), EVy(0, -10), 5, 150, 20, 20)
              else DiscC(EUx(0, -10), EVy(0, -10), 5, 235, 40, 35);
            end;
          ekOL:
            begin
              ELine(-6, -9, -3, -9);
              ELine(-3, -9, -3, -12);
              ELine(-3, -12, 3, -12);
              ELine(3, -12, 3, -9);
              ELine(3, -9, 6, -9);
            end;
          ekFloat:
            begin
              ELine(0, 6, 0, 9);
              DiscC(EUx(0, 11), EVy(0, 11), 3, 90, 160, 235);
            end;
          ekPhoto:
            begin
              { light falling on it }
              if c^.Latch then SetCol(245, 205, 40) else EInk;
              ELine(-9, -12, -5, -8);
              ELine(-5, -8, -7, -8);
              ELine(-5, -8, -5, -10);
              ELine(-3, -12, 1, -8);
              ELine(1, -8, -1, -8);
              ELine(1, -8, 1, -10);
            end;
        end;
      end;
    ekCounter:
      begin
        if closed then
        begin
          EOnCol;
          EBox(-8, -7, 8, 7, True);
        end;
        EInk;
        EBox(-8, -7, 8, 7, False);
        { a plus: it adds one; the bar: how far to its preset }
        ELine(-4, -1, 2, -1);
        ELine(-1, -4, -1, 2);
        f := fclamp(c^.Acc / fmax(1, c^.P1), 0, 1);
        SetCol(245, 170, 40);
        EBox(-8, 4, -8 + 16 * f, 7, True);
      end;
    ekLevelTx, ekPressTx, ekFlowTx, ekTempTx, ekSpeedTx, ekWeightTx, ekHumidTx, ekPHTx:
      begin
        { an instrument bubble; its letters come with the text }
        DiscC(cx, cy, 10, 238, 240, 244);
        if c^.Val > 0.001 then EOnCol else EInk;
        RingC(cx, cy, 10, False);
        RingC(cx, cy, 9.5, False);
      end;
    ekController:
      begin
        SetCol(30, 34, 40);
        EBox(-10, -9, 10, 9, True);
        if closed then EOnCol else EInk;
        EBox(-10, -9, 10, 9, False);
        { the set point (green line) and the actual value (red mark); the output bar }
        SetCol(70, 235, 115);
        ELine(-8, -5, 8, -5);
        SetCol(245, 70, 60);
        f := fclamp(c^.Val / fmax(0.001, 2 * c^.P1), 0, 1);
        ELine(-8 + 16 * f, -8, -8 + 16 * f, -2);
        SetCol(245, 170, 40);
        f := fclamp(c^.Out / 100, 0, 1);
        EBox(-8, 3, -8 + 16 * f, 7, True);
      end;
    ekSolenoid:
      begin
        if closed then
        begin
          EOnCol;
          EBox(-7, -6, 7, 6, True);
        end;
        EInk;
        EBox(-7, -6, 7, 6, False);
        ELine(-7, 6, 7, -6);
      end;
    ekRelay, ekContactor, ekTimer:
      begin
        if c^.Kind = ekRelay then
        begin
          if closed then DiscC(cx, cy, 7, 60, 205, 95);
          EInk;
          RingC(cx, cy, 7, False);
          ELine(-7, 0, -7, 0);
        end
        else
        begin
          if closed then
          begin
            EOnCol;
            if c^.Kind = ekTimer then
            begin
              f := fclamp(c^.Acc / fmax(0.1, c^.P1), 0, 1);
              EBox(-8, -7, -8 + 16 * f, 7, True);
            end
            else
              EBox(-8, -7, 8, 7, True);
          end;
          EInk;
          EBox(-8, -7, 8, 7, False);
          if c^.Kind = ekContactor then
          begin
            ELine(-8, -4, 8, -4);
          end
          else
          begin
            RingC(cx, cy, 4, False);
            LineR(cx, cy, cx, cy - 3);
            LineR(cx, cy, cx + 2, cy);
          end;
        end;
      end;
    ekLamp:
      begin
        k := EnsureRange(c^.Pos, 0, 4);
        if closed then
        begin
          DiscC(cx, cy, 10, LampRGB[k, 0], LampRGB[k, 1], LampRGB[k, 2], 70);
          DiscC(cx, cy, 7, LampRGB[k, 0], LampRGB[k, 1], LampRGB[k, 2]);
        end;
        EInk;
        RingC(cx, cy, 7, False);
        ELine(-5, -5, 5, 5);
        ELine(-5, 5, 5, -5);
      end;
    ekBuzzer:
      begin
        if closed then EOnCol else EInk;
        EBox(-6, -2, 6, 6, not closed);
        EBox(-6, -2, 6, 6, False);
        ELine(-6, -2, 0, -8);
        ELine(0, -8, 6, -2);
        if closed then
        begin
          ELine(8, -6, 10, -9);
          ELine(-8, -6, -10, -9);
        end;
      end;
    ekMotor:
      begin
        if closed then DiscC(cx, cy, 9, 60, 205, 95);
        EInk;
        RingC(cx, cy, 9, False);
        ELine(-7, 0, -9, 0);
        ELine(7, 0, 9, 0);
      end;
    ekDrive:
      begin
        if closed then
        begin
          EOnCol;
          EBox(-9, -8, 9, 8, True);
        end;
        EInk;
        EBox(-9, -8, 9, 8, False);
        ELine(-9, 8, 9, -8);
        for k := 0 to 3 do
          ELine(-7 + k * 2, -4 + Sin(k * 1.6) * 2, -5 + k * 2, -4 + Sin((k + 1) * 1.6) * 2);
        ELine(2, 4, 7, 4);
        ELine(2, 6, 7, 6);
      end;
    ekCT:
      begin
        { the wire passes through a ring }
        ELine(-7, 0, 7, 0);
        ELine(-7, 0.5, 7, 0.5);
        if c^.Amps > 0.01 then EOnCol else EInk;
        RingC(cx, cy, 7, False);
        RingC(cx, cy, 6.5, False);
      end;
    ekPot:
      begin
        { a resistor with the wiper arrow across it }
        ELine(-7, 0, -6, 0);
        ELine(6, 0, 7, 0);
        EInk;
        EBox(-6, -3, 6, 3, False);
        SetCol(245, 170, 40);
        ELine(-6, 7, 6, -7);
        ELine(6, -7, 2, -6);
        ELine(6, -7, 5, -3);
      end;    ekFuse:
      begin
        if c^.Tripped then EBadCol else EInk;
        EBox(-7, -3, 7, 3, False);
        ELine(-7, 0, 7, 0);
        if c^.Tripped then
        begin
          ELine(-4, -5, 4, 5);
          ELine(-4, 5, 4, -5);
        end;
      end;
    ekBreaker, ekSwitch:
      begin
        if c^.Tripped then EBadCol else if closed then EOnCol else EInk;
        ELine(-7, 0, -5, 0);
        if closed then ELine(-5, 0, 6, 0) else ELine(-5, 0, 5, -7);
        if closed then ELine(-5, 0.6, 6, 0.6) else ELine(-4.5, 0, 5.5, -7);
        DiscC(EUx(6, 0), EVy(6, 0), 1.5, 200, 200, 205);
        if c^.Kind = ekBreaker then
        begin
          ELine(-8, -2, -4, 2);
          ELine(-8, 2, -4, -2);
          ELine(0, -3, 0, -10);
        end
        else
          DiscC(EUx(-5, 0), EVy(-5, 0), 1.5, 200, 200, 205);
      end;
    ekAC, ekDC:
      begin
        if c^.Tripped then EBadCol else if c^.On then EOnCol else EInk;
        RingC(cx, cy, 9, False);
        RingC(cx, cy, 8.5, False);
        if c^.Kind = ekAC then
        begin
          for k := 0 to 5 do
          begin
            a := -6 + k * 2;
            ELine(a, -Sin(k * Pi / 3) * 3, a + 2, -Sin((k + 1) * Pi / 3) * 3);
          end;
        end
        else
        begin
          ELine(-2, -6, -2, 6);
          ELine(3, -3, 3, 3);
        end;
      end;
  end;
end;

{ tags, references, L / N marks: screen-size text }
procedure DrawECellText(x, y: Integer);
var
  c: PECell;
  ux, uy, cs: Single;
  s, r: string;
begin
  c := @EGrid[x, y];
  if c^.Kind in [ekNone, ekWire, ekCross] then Exit;
  ux := (x * CELL - ViewX) * Zoom;
  uy := (y * CELL - ViewY) * Zoom;
  cs := CELL * Zoom;
  s := c^.Tag;
  r := '';
  case c^.Kind of
    ekTimer:
      case c^.Pos and 3 of
        1: s := s + Format(' off %.0fs', [c^.P1]);
        2: s := s + Format(' P%.0fs', [c^.P1]);
        3: s := s + ' FL';
      else
        s := s + Format(' %.0fs', [c^.P1]);
      end;
    ekCounter: s := s + Format(' %.0f/%.0f', [c^.Acc, c^.P1]);
    ekLevelTx, ekPressTx, ekFlowTx, ekTempTx, ekSpeedTx, ekWeightTx, ekHumidTx, ekPHTx: r := Format('%.1f %s', [c^.Val, SensorUnit(c^)]);
    ekController: r := Format('%.0f/%.0f', [c^.Val, c^.P1]);
    ekSelector: s := s + Format(':%d', [c^.Pos]);
    ekSw2, ekSw3: s := s + Format(' %d', [c^.Sel + 1]);
    ekDrive: r := c^.Ref + Format(' %.0f%%', [DriveSpeed(x, y)]);
    ekMotor, ekOL, ekFloat: r := c^.Ref;
    ekCT: s := s + Format(' %.1fA', [c^.Amps]);
    ekPot: s := s + Format(' %.0f%%', [c^.P1]);
  end;
  if c^.Tripped then
  begin
    SetC(Th.StatusErr);
    if c^.Kind in [ekAC, ekDC] then r := 'SHORT' else r := 'TRIP';
    if c^.Kind = ekFuse then r := 'BLOWN';
  end
  else
    SetC(Th.Text);
  if c^.Dir = 1 then
  begin
    TextR(ux + cs + 2, uy + cs / 2 - 9, s);
    SetC(Th.TextDim);
    if c^.Tripped then SetC(Th.StatusErr);
    TextR(ux + cs + 2, uy + cs / 2 + 1, r);
  end
  else
  begin
    TextR(ux + (cs - Length(s) * 8) / 2, uy - 9, s);
    SetC(Th.TextDim);
    if c^.Tripped then SetC(Th.StatusErr);
    TextR(ux + (cs - Length(r) * 8) / 2, uy + cs + 1, r);
  end;
  { the letters in an instrument bubble }
  if (c^.Kind in SensorKinds) and (Zoom >= 0.9) then
  begin
    SetCol(30, 34, 40);
    TextR(ux + cs / 2 - 8, uy + cs / 2 - 4, Copy(EKindTags[c^.Kind], 1, 2));
  end;
  if c^.Kind in [ekAC, ekDC] then
  begin
    SetC(Th.TextDim);
    if c^.Dir = 1 then
    begin
      if c^.Kind = ekAC then begin TextR(ux - 9, uy, 'L'); TextR(ux - 9, uy + cs - 8, 'N'); end
      else begin TextR(ux - 9, uy, '+'); TextR(ux - 9, uy + cs - 8, '-'); end;
    end
    else if c^.Kind = ekAC then
    begin
      TextR(ux - 2, uy + cs - 2, 'L');
      TextR(ux + cs - 6, uy + cs - 2, 'N');
    end
    else
    begin
      TextR(ux - 2, uy + cs - 2, '+');
      TextR(ux + cs - 6, uy + cs - 2, '-');
    end;
  end;
end;

procedure DrawElectric;
var
  x, y: Integer;
begin
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (EGrid[x, y].Kind <> ekNone) and LayerShown(EGrid[x, y].Layer) then DrawECell(x, y);
  CanvasXf := False;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (EGrid[x, y].Kind <> ekNone) and LayerShown(EGrid[x, y].Layer) then DrawECellText(x, y);
  CanvasXf := True;
end;

{ the electrical cell at gx, gy on a layer that can be picked }
function EPick(gx, gy: Integer): Boolean;
begin
  Result := InGrid(gx, gy) and (EGrid[gx, gy].Kind <> ekNone) and LayerEditable(EGrid[gx, gy].Layer);
end;

{ ---------------------------------------------------------------- fluid power drawing }

var
  FMapX, FMapY: Single;   { the cell centre being drawn }
  FTurn: Integer;         { its quarter turns }

{ local (u to the base E side, v to the base S side) -> canvas, turned FTurn times }
procedure FXY(u, v: Single; out x, y: Single);
var
  k: Integer;
  t: Single;
begin
  for k := 1 to FTurn do
  begin
    t := u;
    u := -v;
    v := t;
  end;
  x := FMapX + u;
  y := FMapY + v;
end;

procedure FL(u1, v1, u2, v2: Single);
var
  x1, y1, x2, y2: Single;
begin
  FXY(u1, v1, x1, y1);
  FXY(u2, v2, x2, y2);
  LineR(x1, y1, x2, y2);
end;

procedure FBox(u1, v1, u2, v2: Single; Fill: Boolean);
var
  x1, y1, x2, y2: Single;
begin
  FXY(u1, v1, x1, y1);
  FXY(u2, v2, x2, y2);
  if Fill then FillR(fmin(x1, x2), fmin(y1, y2), Abs(x2 - x1), Abs(y2 - y1))
  else RectR(fmin(x1, x2), fmin(y1, y2), Abs(x2 - x1), Abs(y2 - y1));
end;

procedure FDisc(u, v, r: Single; cr, cg, cb: Byte; a: Byte = 255);
var
  x, y: Single;
begin
  FXY(u, v, x, y);
  DiscC(x, y, r, cr, cg, cb, a);
end;

procedure FRing(u, v, r: Single);
var
  x, y: Single;
begin
  FXY(u, v, x, y);
  RingC(x, y, r, False);
end;

procedure FTri(u1, v1, u2, v2, u3, v3: Single; cr, cg, cb: Byte);
var
  x1, y1, x2, y2, x3, y3: Single;
begin
  FXY(u1, v1, x1, y1);
  FXY(u2, v2, x2, y2);
  FXY(u3, v3, x3, y3);
  TriC(x1, y1, x2, y2, x3, y3, cr, cg, cb);
end;

{ a line's colour by its pressure: air blue, oil orange, grey when empty }
procedure FLineCol(p: Single; Med: Byte);
var
  t: Single;
begin
  if p < 0.05 then
  begin
    SetCol(128, 134, 142);
    Exit;
  end;
  if Med = 2 then t := fclamp(p / 120, 0.3, 1) else t := fclamp(p / 8, 0.3, 1);
  if Med = 2 then SetCol(Round(128 + (240 - 128) * t), Round(134 + (120 - 134) * t), Round(142 + (40 - 142) * t))
  else SetCol(Round(128 + (60 - 128) * t), Round(134 + (150 - 134) * t), Round(142 + (245 - 142) * t));
end;

{ a thick line stub from the centre out to side d, r0..r1 pixels, coloured by that side's pressure }
procedure FStub(const c: TFCell; cx, cy: Single; d: Integer; r0, r1: Single);
begin
  FLineCol(c.Press[d], c.Med[d]);
  case d of
    0: FillR(cx + r0, cy - 1.25, r1 - r0, 2.5);
    2: FillR(cx - r1, cy - 1.25, r1 - r0, 2.5);
    1: FillR(cx - 1.25, cy + r0, 2.5, r1 - r0);
  else
    FillR(cx - 1.25, cy - r1, 2.5, r1 - r0);
  end;
end;

procedure FInk;
begin
  SetC(Th.Text);
end;

procedure FSpring(u0, v0, len: Single);
var
  k: Integer;
begin
  for k := 0 to 3 do
    FL(u0 + len * k / 4, v0 - 2 * (1 - 2 * (k mod 2)), u0 + len * (k + 1) / 4, v0 + 2 * (1 - 2 * (k mod 2)));
end;

procedure DrawFCell(x, y: Integer);
var
  c: PFCell;
  cx, cy, a, p, w0, sx: Single;
  d, n, k, np: Integer;
  act: Boolean;
begin
  c := @FGrid[x, y];
  cx := x * CELL + HALF;
  cy := y * CELL + HALF;
  FMapX := cx;
  FMapY := cy;
  FTurn := c^.Dir;
  case c^.Kind of
    fkLine, fkReceiver, fkAccum, fkSilencer, fkTank:
      begin
        n := 0;
        for d := 0 to 3 do
          if (c^.Conn and (1 shl d)) <> 0 then
          begin
            if c^.Kind = fkLine then FStub(c^, cx, cy, d, 0, HALF) else FStub(c^, cx, cy, d, 7, HALF);
            Inc(n);
          end;
        FTurn := 0;
        case c^.Kind of
          fkLine:
            begin
              if n = 0 then FillR(cx - 2, cy - 2, 4, 4);
              if n >= 3 then
              begin
                FLineCol(Max(Max(c^.Press[0], c^.Press[1]), Max(c^.Press[2], c^.Press[3])), Max(c^.Med[0], c^.Med[2]));
                FillR(cx - 3, cy - 3, 6, 6);
              end;
            end;
          fkReceiver, fkAccum:
            begin
              p := c^.Store;
              if c^.Kind = fkAccum then FLineCol(p, 2) else FLineCol(p, 1);
              FillR(cx - 6, cy - 9 + 18 * (1 - fclamp(p / IfThen(c^.Kind = fkAccum, 160, 10), 0, 1)), 12,
                18 * fclamp(p / IfThen(c^.Kind = fkAccum, 160, 10), 0, 1));
              FInk;
              RectR(cx - 6, cy - 9, 12, 18);
              DiscC(cx, cy - 9, 1.5, 200, 200, 205);
              if c^.Kind = fkAccum then
              begin
                LineR(cx - 6, cy - 1, cx + 6, cy - 1);
                LineR(cx - 2, cy + 9, cx, cy + 6);
                LineR(cx, cy + 6, cx + 2, cy + 9);
              end;
            end;
          fkSilencer:
            begin
              FInk;
              RectR(cx - 5, cy - 7, 10, 14);
              for k := 0 to 3 do LineR(cx - 5, cy - 7 + k * 4, cx + 5, cy - 3 + k * 4);
            end;
          fkTank:
            begin
              SetCol(230, 130, 50, 120);
              FillR(cx - 7, cy, 14, 6);
              FInk;
              LineR(cx - 8, cy - 6, cx - 8, cy + 7);
              LineR(cx - 8, cy + 7, cx + 8, cy + 7);
              LineR(cx + 8, cy + 7, cx + 8, cy - 6);
            end;
        end;
        Exit;
      end;
    fkCross:
      begin
        FStub(c^, cx, cy, 0, 0, HALF);
        FStub(c^, cx, cy, 2, 0, HALF);
        FStub(c^, cx, cy, 1, 5, HALF);
        FStub(c^, cx, cy, 3, 5, HALF);
        FInk;
        LineR(cx, cy - 5, cx + 5, cy - 2);
        LineR(cx + 5, cy - 2, cx + 5, cy + 2);
        LineR(cx + 5, cy + 2, cx, cy + 5);
        Exit;
      end;
  end;
  { the port stubs, then the symbol (turned with the cell) }
  for k := 0 to 3 do
  begin
    d := FSide(c^, k);
    if (c^.Conn and (1 shl d)) <> 0 then
      case c^.Kind of
        fkV32, fkV52, fkV53, fkV42, fkV43:
          if k = 1 then FStub(c^, cx, cy, d, 5, HALF)
          else if k = 3 then FStub(c^, cx, cy, d, 5, HALF)
          else FStub(c^, cx, cy, d, 10, HALF);
      else
        FStub(c^, cx, cy, d, 8, HALF);
      end;
  end;
  act := c^.Running;
  case c^.Kind of
    fkCompressor, fkHPump:
      begin
        if act then FDisc(0, 0, 8, 60, 205, 95);
        FInk;
        FRing(0, 0, 8);
        if c^.Kind = fkHPump then FTri(1, -5, 7, 0, 1, 5, 230, 120, 40)
        else
        begin
          FL(1, -5, 7, 0);
          FL(7, 0, 1, 5);
          FL(1, 5, 1, -5);
        end;
      end;
    fkFRL, fkRegulator, fkFilter:
      begin
        FInk;
        if c^.Kind = fkFilter then
        begin
          FL(-7, 0, 0, -7);
          FL(0, -7, 7, 0);
          FL(7, 0, 0, 7);
          FL(0, 7, -7, 0);
          FL(0, -5, 0, 5);
        end
        else
        begin
          FBox(-8, -7, 8, 7, False);
          if c^.Kind = fkFRL then
          begin
            FL(-7, 0, -4, -3);
            FL(-4, -3, -1, 0);
            FL(-1, 0, -4, 3);
            FL(-4, 3, -7, 0);
          end;
          FL(-2, 6, 7, -6);
          FL(7, -6, 4, -6);
          FL(7, -6, 7, -3);
        end;
      end;
    fkCheck:
      begin
        FInk;
        FRing(-1, 0, 3.5);
        FL(5, -5, 2.5, 0);
        FL(2.5, 0, 5, 5);
        FL(-8, 0, -4.5, 0);
        FL(5, 0, 8, 0);
      end;
    fkThrottle:
      begin
        FInk;
        FL(-8, 0, 8, 0);
        FL(-5, -5, 0, -1.5);
        FL(0, -1.5, 5, -5);
        FL(-5, 5, 0, 1.5);
        FL(0, 1.5, 5, 5);
        SetCol(245, 170, 40);
        FL(-6, 7, 6, -7);
        FL(6, -7, 2, -6);
        FL(6, -7, 5, -3);
      end;
    fkShuttle, fkAndValve:
      begin
        FInk;
        FBox(-8, -5, 8, 5, False);
        FL(0, -5, 0, -12);
        if c^.Kind = fkShuttle then FRing(0, 0, 2.5)
        else
        begin
          FL(-3, -3, -3, 3);
          FL(3, -3, 3, 3);
        end;
      end;
    fkRelief:
      begin
        if act then SetCol(235, 60, 50) else FInk;
        FBox(-6, -7, 6, 7, False);
        FL(-4, 4, 5, -1);
        FL(5, -1, 2, -1);
        FSpring(-4, -9, 8);
        FL(-8, 0, -6, 0);
        FL(6, 0, 8, 0);
      end;
    fkV32, fkV52, fkV53, fkV42, fkV43:
      begin
        np := FPositions(c^.Kind);
        w0 := 18 / np;
        for k := 0 to np - 1 do
        begin
          sx := -9 + k * w0;
          { which envelope is working: left = position 1, right (or the middle of three) = 0, right of three = 2 }
          if ((np = 2) and (((k = 0) and (c^.Sel = 1)) or ((k = 1) and (c^.Sel = 0)))) or
            ((np = 3) and (((k = 0) and (c^.Sel = 1)) or ((k = 1) and (c^.Sel = 0)) or ((k = 2) and (c^.Sel = 2)))) then
          begin
            SetCol(60, 205, 95, 90);
            FBox(sx, -5, sx + w0, 5, True);
            SetCol(60, 205, 95);
          end
          else
            FInk;
          FBox(sx, -5, sx + w0, 5, False);
          { the paths: straight in position 1, crossed in 0 (2), blocked in a centre }
          if (np = 3) and (k = 1) then
          begin
            FL(sx + w0 * 0.3, 5, sx + w0 * 0.3, 2);
            FL(sx + w0 * 0.7, 5, sx + w0 * 0.7, 2);
          end
          else if k = 0 then
          begin
            FL(sx + w0 * 0.3, 4, sx + w0 * 0.3, -4);
            FL(sx + w0 * 0.7, -4, sx + w0 * 0.7, 4);
          end
          else
          begin
            FL(sx + w0 * 0.25, 4, sx + w0 * 0.75, -4);
            FL(sx + w0 * 0.75, 4, sx + w0 * 0.25, -4);
          end;
        end;
        FL(-9, 0, -11, 0);
        FL(9, 0, 11, 0);
        { actuators: left (position 1) and right }
        FInk;
        case c^.Act of
          0: FL(-11, -2, -9, -8);                            { lever }
          1: begin FL(-9, -7, -12, -7); FL(-12, -9, -12, -5); end;   { push button }
        else
          begin
            FBox(-12.5, -9, -9, -5, False);                    { solenoid }
            FL(-12.5, -5, -9, -9);
          end;
        end;
        if (c^.Act = 3) or ((np = 3) and (c^.Act >= 2)) then
        begin
          FBox(9, -9, 12.5, -5, False);
          FL(9, -5, 12.5, -9);
        end
        else if c^.Act > 0 then
          FSpring(9, -7, 3.5);
      end;
    fkCylSA, fkCylDA:
      begin
        p := c^.Pos;
        if act then SetCol(60, 205, 95) else FInk;
        FBox(-10, -5, 6, 5, False);
        a := -9 + p * 12;
        FBox(a, -4, a + 1.5, 4, True);
        FBox(a + 1.5, -1.2, 12, 1.2, True);
        FL(-12, 0, -10, 0);
        if c^.Kind = fkCylDA then
        begin
          FL(4, 5, 4, 8);
          FL(4, 8, 0, 8);
          FL(0, 8, 0, 12);
        end
        else
          FSpring(a + 2, 2.5, 3);
      end;
    fkAirMotor, fkHydMotor:
      begin
        if act then FDisc(0, 0, 7, 60, 205, 95);
        FInk;
        FRing(0, 0, 7);
        if c^.Kind = fkHydMotor then FTri(-6, 0, -1, -4, -1, 4, 230, 120, 40)
        else
        begin
          FL(-6, 0, -1, -4);
          FL(-1, -4, -1, 4);
          FL(-1, 4, -6, 0);
        end;
        FL(-8, 0, -7, 0);
        FL(7, 0, 8, 0);
        if act then
        begin
          a := SDL_GetTicksNS / 2e8;
          FL(Cos(a) * 9, Sin(a) * 9, Cos(a + 0.6) * 9, Sin(a + 0.6) * 9);
        end;
      end;
    fkGauge:
      begin
        DiscC(cx, cy, 8, 240, 241, 243);
        FInk;
        RingC(cx, cy, 8, False);
        p := c^.Press[FSide(c^, 1)];
        if c^.Med[FSide(c^, 1)] = 2 then a := fclamp(p / 160, 0, 1) else a := fclamp(p / 10, 0, 1);
        a := Pi * (0.75 + 1.5 * a);
        SetCol(210, 40, 35);
        LineR(cx, cy, cx + Cos(a) * 6.5, cy + Sin(a) * 6.5);
      end;
    fkPSwitch:
      begin
        if c^.Latch then SetCol(60, 205, 95) else FInk;
        FBox(-7, -7, 7, 5, False);
        FL(-5, -3, 0, -3);
        if c^.Latch then FL(0, -3, 5, -3) else FL(0, -3, 4, -6);
        FSpring(-4, 2, 8);
      end;
  end;
end;

{ tags and values: screen-size text }
procedure DrawFCellText(x, y: Integer);
var
  c: PFCell;
  ux, uy, cs: Single;
  s, r: string;
begin
  c := @FGrid[x, y];
  if c^.Kind in [fkNone, fkLine, fkCross] then Exit;
  ux := (x * CELL - ViewX) * Zoom;
  uy := (y * CELL - ViewY) * Zoom;
  cs := CELL * Zoom;
  s := c^.Tag;
  r := '';
  case c^.Kind of
    fkCompressor, fkHPump: r := Format('%.0f bar', [c^.P1]);
    fkReceiver, fkAccum: r := Format('%.1f bar', [c^.Store]);
    fkFRL, fkRegulator, fkRelief: r := Format('%.0f bar', [c^.P1]);
    fkThrottle: r := Format('%.0f%%', [c^.P1]);
    fkShuttle: r := 'OR';
    fkAndValve: r := 'AND';
    fkGauge: r := Format('%.1f bar', [c^.Press[FSide(c^, 1)]]);
    fkCylSA, fkCylDA, fkAirMotor, fkHydMotor: r := c^.Ref;
    fkV32, fkV52, fkV53, fkV42, fkV43:
      if c^.Act >= 2 then
      begin
        r := c^.SolA;
        if c^.SolB <> '' then r := r + '/' + c^.SolB;
      end;
  end;
  SetC(Th.Text);
  TextR(ux + (cs - Length(s) * 8) / 2, uy - 9, s);
  SetC(Th.TextDim);
  TextR(ux + (cs - Length(r) * 8) / 2, uy + cs + 1, r);
end;

procedure DrawFluid;
var
  x, y: Integer;
begin
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (FGrid[x, y].Kind <> fkNone) and LayerShown(FGrid[x, y].Layer) then DrawFCell(x, y);
  CanvasXf := False;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (FGrid[x, y].Kind <> fkNone) and LayerShown(FGrid[x, y].Layer) then DrawFCellText(x, y);
  CanvasXf := True;
end;

function FPick(gx, gy: Integer): Boolean;
begin
  Result := InGrid(gx, gy) and (FGrid[gx, gy].Kind <> fkNone) and LayerEditable(FGrid[gx, gy].Layer);
end;

{ ---------------------------------------------------------------- grid }

procedure GridRGB(out r, g, b: Byte);
begin
  case GridColor of
    1: begin r := 70; g := 140; b := 255; end;
    2: begin r := 60; g := 200; b := 110; end;
    3: begin r := 235; g := 170; b := 50; end;
    4: begin r := 240; g := 240; b := 245; end;
  else
    begin r := Th.Text.R; g := Th.Text.G; b := Th.Text.B; end;
  end;
end;

function IsMajor(n: Integer): Boolean;
begin
  Result := (GridMajor > 0) and (n mod GridMajor = 0);
end;

{ the cell grid, in the zoomed canvas }
procedure DrawGrid;
const
  ThemeA: array[0..2] of Byte = (12, 24, 48);    { the theme colour is the text colour, kept faint }
  ColourA: array[0..2] of Byte = (40, 80, 150);
var
  x, y: Integer;
  r, g, b, a, am: Byte;
  d, arm: Single;
begin
  if not GridShow then Exit;
  GridRGB(r, g, b);
  if GridColor = 0 then a := ThemeA[GridStrength] else a := ColourA[GridStrength];
  am := Min(255, a * 2 + 30);
  case GridStyle of
    0:
      begin
        for x := 0 to GW do
        begin
          if IsMajor(x) then SetCol(r, g, b, am) else SetCol(r, g, b, a);
          LineR(x * CELL, 0, x * CELL, FLOOR_Y);
        end;
        for y := 0 to GH do
          if y * CELL <= FLOOR_Y then
          begin
            if IsMajor(y) then SetCol(r, g, b, am) else SetCol(r, g, b, a);
            LineR(0, y * CELL, CANVAS_W, y * CELL);
          end;
      end;
    1:
      for y := 0 to GH do
        if y * CELL <= FLOOR_Y then
          for x := 0 to GW do
          begin
            { dots keep a size on screen whatever the zoom }
            if IsMajor(x) and IsMajor(y) then
            begin
              SetCol(r, g, b, am);
              d := 3 / Zoom;
            end
            else
            begin
              SetCol(r, g, b, Min(255, a * 2));
              d := 2 / Zoom;
            end;
            FillR(x * CELL - d / 2, y * CELL - d / 2, d, d);
          end;
    2:
      for y := 0 to GH do
        if y * CELL <= FLOOR_Y then
          for x := 0 to GW do
          begin
            if IsMajor(x) and IsMajor(y) then
            begin
              SetCol(r, g, b, am);
              arm := 5 / Zoom;
            end
            else
            begin
              SetCol(r, g, b, Min(255, a * 2));
              arm := 3 / Zoom;
            end;
            LineR(x * CELL - arm, y * CELL, x * CELL + arm, y * CELL);
            LineR(x * CELL, y * CELL - arm, x * CELL, y * CELL + arm);
          end;
  end;
end;

{ cell numbers along the top and left edges of the canvas area (screen space) }
procedure DrawGridNumbers;
var
  n, step: Integer;
  u: Single;
  s: string;
begin
  if GridMajor > 0 then step := GridMajor else step := 5;
  SetC(Th.OverlayBg, 200);
  FillR(0, 0, CANVAS_W, 11);
  FillR(0, 11, 18, CANVAS_H - 11);
  SetC(Th.TextDim);
  n := 0;
  while n <= GW do
  begin
    u := (n * CELL - ViewX) * Zoom;
    s := IntToStr(n);
    if (u >= 18) and (u + Length(s) * 8 <= CANVAS_W) then TextR(u + 2, 2, s);
    Inc(n, step);
  end;
  n := 0;
  while n <= GH do
  begin
    u := (n * CELL - ViewY) * Zoom;
    if (u >= 11) and (u + 8 <= CANVAS_H) then TextR(1, u + 2, IntToStr(n));
    Inc(n, step);
  end;
end;

procedure DrawCanvas;
var
  x, y, i, gx, gy: Integer;
  c: PCell;
  cr: TSDL_Rect;
begin
  { the area around the layout (seen when zoomed out) }
  CanvasXf := False;
  SetCol(Th.CanvasBg.R div 2, Th.CanvasBg.G div 2, Th.CanvasBg.B div 2);
  FillR(0, 0, CANVAS_W, CANVAS_H);
  { everything on the canvas goes through the zoom and stays inside the canvas area }
  cr.x := Round(OX);
  cr.y := Round(OY);
  cr.w := CANVAS_W;
  cr.h := CANVAS_H;
  SDL_SetRenderClipRect(Ren, @cr);
  CanvasXf := True;
  SetC(Th.CanvasBg);
  FillR(0, 0, CANVAS_W, CANVAS_H);
  DrawGrid;
  DrawFrames;
  SetC(Th.Floor);
  FillR(0, FLOOR_Y, CANVAS_W, CANVAS_H - FLOOR_Y);

  DrawEquips(False);
  for i := 0 to MAX_BUCKETS - 1 do
    if Buckets[i].Active and LayerShown(Buckets[i].Layer) then DrawBucketBack(i);

  { suction pick-up range }
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @Grid[x, y];
      if (c^.Kind = ckSuction) and (c^.Mouth >= 0) and LayerShown(c^.Layer) then
      begin
        if c^.F[c^.Mouth] < -0.02 then SetCol(180, 120, 240, 70) else SetCol(120, 120, 130, 50);
        RingC(x * CELL + HALF + DXS[c^.Mouth] * HALF, y * CELL + HALF + DYS[c^.Mouth] * HALF,
          SuctionRadius(x, y), True);
      end;
    end;

  DrawPipes;
  DrawParticles;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (Grid[x, y].Kind > ckPipe) and LayerShown(Grid[x, y].Layer) then DrawDevice(x, y);
  for i := 0 to MAX_BUCKETS - 1 do
    if Buckets[i].Active and LayerShown(Buckets[i].Layer) then DrawBucketFront(i);
  DrawEquips(True);
  DrawElectric;
  DrawFluid;
  DrawEquipTexts;
  DrawLabels;
  DrawLinks;
  if Drag = dragFrameNew then
  begin
    SetC(Th.Paste);
    RectR(SnapCell(fmin(FrX0, FrX1)), SnapCell(fmin(FrY0, FrY1)),
      SnapCell(fmax(FrX0, FrX1)) - SnapCell(fmin(FrX0, FrX1)), SnapCell(fmax(FrY0, FrY1)) - SnapCell(fmin(FrY0, FrY1)));
  end
  else if (Drag = dragFrameMove) and (FrDrag >= 0) and ((FrDX <> 0) or (FrDY <> 0)) then
    with Frames[FrDrag] do
      DrawFrameShape(FrDrag, X + FrDX * CELL, Y + FrDY * CELL, W, H, True);

  if (SelKind = selLink) and (SelLk >= 0) and Links[SelLk].Active then
    OutlineLink(SelLk);
  if (SelKind = selEquip) and (SelEq >= 0) and Equips[SelEq].Active then
    OutlineEquip(SelEq);
  if SelKind = selECell then
  begin
    SetC(Th.Select);
    RectR(SelEX * CELL - 1, SelEY * CELL - 1, CELL + 2, CELL + 2);
    RectR(SelEX * CELL - 2, SelEY * CELL - 2, CELL + 4, CELL + 4);
  end;
  if SelKind = selFCell then
  begin
    SetC(Th.Select);
    RectR(SelFX * CELL - 1, SelFY * CELL - 1, CELL + 2, CELL + 2);
    RectR(SelFX * CELL - 2, SelFY * CELL - 2, CELL + 4, CELL + 4);
  end;
  if SelKind = selCell then
  begin
    SetC(Th.Select);
    RectR(SelX * CELL - 1, SelY * CELL - 1, CELL + 2, CELL + 2);
  end
  else if SelKind = selMulti then
  begin
    { once the mouse is up the box itself is gone: only the picked parts stay marked
      (selected buckets are outlined in DrawBucketFront) }
    SetC(Th.Select);
    for y := SelY1 to SelY2 do
      for x := SelX1 to SelX2 do
        if SelHasCell(x, y) then
        begin
          RectR(x * CELL - 1, y * CELL - 1, CELL + 2, CELL + 2);
          RectR(x * CELL, y * CELL, CELL, CELL);
        end;
  end;
  if Drag = dragBox then
  begin
    SetC(Th.Select, 35);
    FillR(Min(BoxX0, BoxX1), Min(BoxY0, BoxY1), Abs(BoxX1 - BoxX0), Abs(BoxY1 - BoxY0));
    SetC(Th.Select);
    RectR(Min(BoxX0, BoxX1), Min(BoxY0, BoxY1), Abs(BoxX1 - BoxX0), Abs(BoxY1 - BoxY0));
  end;
  if (MX >= 0) and (MX < CANVAS_W) and (MY >= 0) and (MY < CANVAS_H) then
  begin
    gx := Trunc(MWX / CELL);
    gy := Trunc(MWY / CELL);
    if PasteArmed then
      DrawBlockGhost(Clip, gx, gy, 'Paste')
    else if Drag = dragMove then
    begin
      if (MoveDX <> 0) or (MoveDY <> 0) then
        DrawBlockGhost(MoveBuf, MoveX1 + MoveDX, MoveY1 + MoveDY, 'Move');
    end
    else if InGrid(gx, gy) and (MWX >= 0) and (MWY >= 0) then
    begin
      SetC(Th.Hover, 50);
      RectR(gx * CELL, gy * CELL, CELL, CELL);
    end;
  end;

  { overlays below are fixed to the canvas area, not to the zoomed layout }
  CanvasXf := False;
  if GridShow and GridNumbers then DrawGridNumbers;
  SDL_SetRenderClipRect(Ren, nil);
  if Zoom <> 1 then
  begin
    SetC(Th.OverlayBg, 210);
    FillR(CANVAS_W - 196, CANVAS_H - 22, 190, 16);
    SetC(Th.TextDim);
    TextR(CANVAS_W - 190, CANVAS_H - 18, Format('Zoom %.0f%%  Ctrl+0 resets', [Zoom * 100]));
  end;

  if ShowPressure then
  begin
    SetC(Th.OverlayBg, 210);
    FillR(6, 6, 236, 14);
    SetCol(70, 120, 255);
    TextR(10, 9, 'suction (-)');
    SetC(Th.TextDim);
    TextR(106, 9, '0');
    SetCol(240, 90, 70);
    TextR(122, 9, 'pressure (+)');
  end;
  if StatusTime > 0 then
  begin
    SetC(Th.OverlayBg, 220);
    FillR(6, 26, Length(StatusMsg) * 8 + 12, 16);
    if StatusErr then SetC(Th.StatusErr) else SetC(Th.StatusOk);
    TextR(12, 30, StatusMsg);
  end;
  if not Running then
  begin
    SetC(Th.OverlayBg, 210);
    FillR(CANVAS_W / 2 - 90, 6, 180, 16);
    SetC(Th.Select);
    TextR(CANVAS_W / 2 - 72, 10, 'PAUSED  (Space)');
  end;
  DrawFramePopup;
end;

{ ---------------------------------------------------------------- panel widgets }

function Inside(x, y, w, h: Single): Boolean;
begin
  Result := (MX >= x) and (MX < x + w) and (MY >= y) and (MY < y + h);
end;

function Button(id: Integer; x, y, w, h: Single; const lbl: string; Sel: Boolean = False): Boolean;
var
  hot: Boolean;
begin
  id := id + IdBase;
  hot := Inside(x, y, w, h);
  Result := hot and MPressed;
  if Result then
  begin
    ActiveId := id;
    HoldTime := 0;
    RepeatAcc := 0;
  end;
  if Sel then SetC(Th.BtnSel)
  else if hot then SetC(Th.BtnHot)
  else SetC(Th.BtnBg);
  FillR(x, y, w, h);
  if Sel then SetC(Th.BtnSelBorder) else SetC(Th.BtnBorder);
  RectR(x, y, w, h);
  if Sel then SetC(Th.BtnSelText) else SetC(Th.BtnText);
  TextR(Round(x + (w - Length(lbl) * 8) / 2), Round(y + (h - 8) / 2), lbl);
end;

function RepButton(id: Integer; x, y, w, h: Single; const lbl: string): Boolean;
begin
  Result := Button(id, x, y, w, h, lbl);
  if (not Result) and (ActiveId = id + IdBase) and MDown and Inside(x, y, w, h) then
  begin
    HoldTime := HoldTime + FrameDt;
    if HoldTime > 0.35 then
    begin
      RepeatAcc := RepeatAcc + FrameDt;
      if RepeatAcc >= 0.05 then
      begin
        RepeatAcc := 0;
        Result := True;
      end;
    end;
  end;
end;

function Slider(id: Integer; x, y, w: Single; var v: Single; vmin, vmax: Single): Boolean;
var
  t, nv: Single;
begin
  Result := False;
  id := id + IdBase;
  if MPressed and Inside(x - 4, y - 4, w + 8, 16) then ActiveId := id;
  if (ActiveId = id) and MDown then
  begin
    nv := vmin + fclamp((MX - x) / w, 0, 1) * (vmax - vmin);
    if nv <> v then
    begin
      v := nv;
      Result := True;
    end;
  end;
  t := fclamp((v - vmin) / (vmax - vmin), 0, 1);
  SetC(Th.SliderTrack);
  FillR(x, y + 2, w, 6);
  SetC(Th.SliderFill);
  FillR(x, y + 2, w * t, 6);
  if ActiveId = id then SetC(Th.SliderFill) else SetC(Th.SliderKnob);
  FillR(x + w * t - 3, y - 1, 6, 12);
  SetC(Th.BtnBorder);
  RectR(x + w * t - 3, y - 1, 6, 12);
end;

procedure Header(y: Single; const s: string);
begin
  SetC(Th.HeaderLine);
  LineR(PX, y + 4, PX + 288, y + 4);
  SetC(Th.PanelBg);
  FillR(PX, y, Length(s) * 8 + 6, 9);
  SetC(Th.HeaderTxt);
  TextR(PX, y, s);
end;

procedure ParamRow(id: Integer; y: Single; const lbl: string; var v: Single;
  vmin, vmax, step: Single; Swatch: Boolean = False; sr: Byte = 0; sg: Byte = 0; sb: Byte = 0);
begin
  if Swatch then
  begin
    SetCol(sr, sg, sb);
    FillR(QX, y + 3, 8, 8);
  end;
  SetC(Th.Text);
  TextR(QX + 12, y + 3, lbl);
  if RepButton(id, QX + 64, y, 18, 14, '-') then v := fmax(vmin, v - step);
  Slider(id + 1, QX + 88, y + 2, 120, v, vmin, vmax);
  if RepButton(id + 2, QX + 214, y, 18, 14, '+') then v := fmin(vmax, v + step);
  SetC(Th.Text);
  TextR(QX + 238, y + 3, Format('%4.0f', [v]));
end;

{ a parameter row with decimals: label, -, slider, +, value }
procedure ParamRowD(id: Integer; y: Single; const lbl: string; var v: Single; vmin, vmax, step: Single; Dec: Integer);
begin
  SetC(Th.Text);
  TextR(QX, y + 3, lbl);
  if RepButton(id, QX + 92, y, 18, 14, '-') then v := fmax(vmin, v - step);
  Slider(id + 1, QX + 114, y + 2, 100, v, vmin, vmax);
  if RepButton(id + 2, QX + 218, y, 18, 14, '+') then v := fmin(vmax, v + step);
  SetC(Th.Text);
  TextR(QX + 240, y + 3, FloatToStrF(v, ffFixed, 7, Dec));
end;

procedure Info(y: Single; const s: string);
begin
  SetC(Th.TextDim);
  TextR(QX, y, s);
end;

{ ---------------------------------------------------------------- properties }

procedure DeleteSelected; forward;
procedure SelectCell(gx, gy: Integer); forward;
procedure SaveSettings; forward;

procedure DiaRow(y: Single; c: PCell);
var
  v: Single;
begin
  v := c^.Dia;
  ParamRow(200, y, 'Size', v, 1, MAX_DIA, 1);
  c^.Dia := EnsureRange(Round(v), 1, MAX_DIA);
end;

{ E / S / W / N buttons that set a device's direction directly }
procedure DirButtons(y: Single; c: PCell; const Lbl: string);
const
  Letters: array[0..3] of string = ('E', 'S', 'W', 'N');
var
  d: Integer;
begin
  SetC(Th.Text);
  TextR(QX, y + 5, Lbl);
  for d := 0 to 3 do
    if Button(170 + d, QX + 96 + d * 40, y, 36, 18, Letters[d], c^.Dir = d) then
      c^.Dir := d;
end;

procedure DrawCellProps(y: Single);
const
  ConnNames: array[0..4] of string = ('unconnected', 'open end (1-way)', 'straight/elbow (2-way)',
    'tee (3-way)', 'cross (4-way)');
var
  c: PCell;
  m: TMat;
  q, tot: Single;
  d, n: Integer;
  s: string;
begin
  c := @Grid[SelX, SelY];
  SetC(Th.Title);
  TextR(QX, y, Format('%s  [%d,%d]', [KindNames[c^.Kind], SelX, SelY]));
  y := y + 16;
  n := ConnCount(SelX, SelY);
  case c^.Kind of
    ckSource:
      begin
        Info(y, 'Ingredients (units in feeder):');
        y := y + 13;
        for m := mWater to mSand do
        begin
          if m = mFluff then
            ParamRow(100 + Ord(m) * 3, y, MatP[m].Name, c^.Stock[m], 0, STOCK_MAX, 50,
              True, Th.Fluff.R, Th.Fluff.G, Th.Fluff.B)
          else
            ParamRow(100 + Ord(m) * 3, y, MatP[m].Name, c^.Stock[m], 0, STOCK_MAX, 50,
              True, MatP[m].R, MatP[m].G, MatP[m].B);
          y := y + 20;
        end;
        ParamRow(120, y, 'Air %', c^.AirPct, 0, 95, 5, True, Th.Air.R, Th.Air.G, Th.Air.B);
        y := y + 20;
        ParamRow(123, y, 'Feed %', c^.Feed, 0, 100, 5);
        y := y + 22;
        if Button(126, QX, y, 93, 18, 'Fill +100') then RefillTank(SelX, SelY, 100);
        if Button(127, QX + 97, y, 93, 18, 'Drain') then
          for m := mWater to mSand do c^.Stock[m] := 0;
        if Button(128, QX + 194, y, 94, 18, 'Mix 25/25') then
          for m := mWater to mSand do c^.Stock[m] := 250;
        y := y + 24;
        q := 0;
        for d := 0 to 3 do
          if c^.F[d] > 0 then q := q + c^.F[d];
        tot := 0;
        for m := mWater to mSand do tot := tot + c^.Stock[m];
        Info(y, Format('Air out-flow %.2f   stock %.0f', [q, tot]));
        Info(y + 12, Format('Mix: %.0f%% material / %.0f%% air', [100 - c^.AirPct, c^.AirPct]));
        if q > 0.05 then Info(y + 24, 'Feeding: carried by air flow')
        else if c^.EPf[1] then Info(y + 24, 'Feeding: gravity discharge down')
        else Info(y + 24, 'Idle: add blower/suction or pipe down');
        y := y + 40;
      end;
    ckVFeeder:
      begin
        Info(y, 'Mix ratio (never runs out):');
        y := y + 13;
        for m := mWater to mSand do
        begin
          if m = mFluff then
            ParamRow(100 + Ord(m) * 3, y, MatP[m].Name, c^.Stock[m], 0, STOCK_MAX, 50,
              True, Th.Fluff.R, Th.Fluff.G, Th.Fluff.B)
          else
            ParamRow(100 + Ord(m) * 3, y, MatP[m].Name, c^.Stock[m], 0, STOCK_MAX, 50,
              True, MatP[m].R, MatP[m].G, MatP[m].B);
          y := y + 20;
        end;
        ParamRow(120, y, 'Air %', c^.AirPct, 0, 95, 5, True, Th.Air.R, Th.Air.G, Th.Air.B);
        y := y + 20;
        ParamRow(123, y, 'Feed %', c^.Feed, 0, 100, 5);
        y := y + 20;
        ParamRow(129, y, 'Life s', c^.Strength, 1, 120, 1);
        y := y + 22;
        Info(y, 'Endless: what it emits disappears');
        Info(y + 12, Format('after %.0f s (taken back on return).', [c^.Strength]));
        y := y + 30;
      end;    ckHopper, ckSilo:
      begin
        tot := StoreTotal(c^);
        if c^.Kind = ckHopper then
        begin
          Info(y, 'Its funnel catches what falls in');
          Info(y + 11, 'and passes it on through the gate.');
        end
        else
        begin
          Info(y, 'Fills through its roof opening or');
          Info(y + 11, 'from pipes; the gate meters it out.');
        end;
        y := y + 26;
        { level bar }
        SetC(Th.SliderTrack);
        FillR(QX, y, 280, 10);
        SetC(Th.SliderFill);
        FillR(QX, y, 280 * fmin(1, tot / StoreCap(c^.Kind)), 10);
        SetC(Th.Text);
        TextR(QX, y + 14, Format('Contents %.0f of %.0f  (%.0f%%)', [tot, StoreCap(c^.Kind),
          100 * tot / StoreCap(c^.Kind)]));
        y := y + 28;
        if c^.Kind = ckSilo then
        begin
          for m := mWater to mSand do
          begin
            if m = mFluff then
              ParamRow(100 + Ord(m) * 3, y, MatP[m].Name, c^.Stock[m], 0, STOCK_MAX, 50,
                True, Th.Fluff.R, Th.Fluff.G, Th.Fluff.B)
            else
              ParamRow(100 + Ord(m) * 3, y, MatP[m].Name, c^.Stock[m], 0, STOCK_MAX, 50,
                True, MatP[m].R, MatP[m].G, MatP[m].B);
            y := y + 20;
          end;
        end
        else
        begin
          s := 'Holds:';
          for m := mWater to mSand do
            if c^.Stock[m] >= 1 then s := s + Format(' %s %.0f', [MatP[m].Name, c^.Stock[m]]);
          if tot < 1 then s := 'Empty - drop material into it';
          Info(y, s);
          y := y + 16;
        end;
        ParamRow(123, y, 'Gate %', c^.Feed, 0, 100, 5);
        y := y + 22;
        if Button(127, QX, y, 136, 18, 'Empty it') then
          for m := mWater to mSand do c^.Stock[m] := 0;
        y := y + 24;
        q := 0;
        for d := 0 to 3 do
          if c^.F[d] > 0 then q := q + c^.F[d];
        if tot < 1 then Info(y, 'Waiting for material')
        else if c^.Feed < 1 then Info(y, 'Gate shut: storing')
        else if q > 0.05 then Info(y, 'Discharging: carried by air flow')
        else if c^.EPf[1] then Info(y, 'Discharging by gravity')
        else Info(y, 'Needs a pipe down or air flow');
        y := y + 16;
      end;
    ckBlower:
      begin
        Info(y, 'Blow strength (pump head):');
        ParamRow(130, y + 13, 'Blow', c^.Strength, 0, 100, 5);
        Info(y + 36, Format('Blows %s, flow %.2f', [DirNames[c^.Dir], c^.F[c^.Dir]]));
        DirButtons(y + 52, c, 'Blows to');
        y := y + 78;
      end;
    ckSuction:
      begin
        Info(y, 'Suction strength (intake pull):');
        ParamRow(130, y + 13, 'Suck', c^.Strength, 0, 100, 5);
        if c^.Mouth >= 0 then q := -c^.F[c^.Mouth] else q := 0;
        Info(y + 36, Format('Mouth %s, intake %.2f, reach %.0f', [DirNames[c^.Dir], q, SuctionRadius(SelX, SelY)]));
        DirButtons(y + 52, c, 'Mouth');
        y := y + 78;
      end;
    ckNozzle:
      begin
        Info(y, 'Push-out strength (jet):');
        ParamRow(130, y + 13, 'Push', c^.Strength, 0, 100, 5);
        if c^.Mouth >= 0 then q := c^.F[c^.Mouth] else q := 0;
        Info(y + 36, Format('Mouth %s, out-flow %.2f', [DirNames[c^.Dir], q]));
        DirButtons(y + 52, c, 'Mouth');
        y := y + 78;
      end;
    ckDrop:
      begin
        Info(y, 'Drop discharge (gravity gate %):');
        ParamRow(130, y + 13, 'Drop', c^.Strength, 0, 100, 5);
        if c^.Strength < 0.5 then s := 'closed' else s := DirNames[c^.Dir];
        Info(y + 36, 'Discharges ' + s);
        DirButtons(y + 52, c, 'Mouth');
        y := y + 78;
      end;
    ckCheck:
      begin
        Info(y, 'Single-way pipe: material & air');
        Info(y + 12, 'only pass along the arrow.');
        Info(y + 26, 'Direction: ' + DirNames[c^.Dir]);
        DirButtons(y + 40, c, 'Flows to');
        y := y + 66;
      end;
    ckValve2:
      begin
        Info(y, '2-way valve: on/off in a line.');
        if c^.Open then s := 'OPEN - click to close' else s := 'CLOSED - click to open';
        if Button(133, QX, y + 14, 200, 18, s, c^.Open) then RotateCell(SelX, SelY);
        y := y + 40;
      end;
    ckValve3:
      begin
        Info(y, '3-way valve: diverts at a tee.');
        if c^.Dir < 0 then s := 'all branches open' else s := 'closed: ' + DirNames[c^.Dir];
        Info(y + 13, s);
        if Button(133, QX, y + 28, 160, 18, 'Switch branch R') then RotateCell(SelX, SelY);
        y := y + 54;
      end;
    ckValve4:
      begin
        Info(y, '4-way valve: each branch of the');
        Info(y + 12, 'cross opens or shuts on its own.');
        SetC(Th.Text);
        TextR(QX, y + 31, 'Open');
        for d := 0 to 3 do
          if Button(190 + d, QX + 96 + d * 40, y + 26, 36, 18, DirNames[d][1],
            (c^.Closed and (1 shl d)) = 0) then
            c^.Closed := c^.Closed xor (1 shl d);
        if c^.Closed = 0 then s := 'all branches open'
        else
        begin
          s := 'shut:';
          for d := 0 to 3 do
            if (c^.Closed and (1 shl d)) <> 0 then s := s + ' ' + DirNames[d];
        end;
        Info(y + 50, s);
        y := y + 68;
      end;
    ckPipe:
      begin
        Info(y, 'Joint: ' + ConnNames[n]);
        Info(y + 12, Format('Air speed %.0f px/s  P %.1f', [CellSpeed(SelX, SelY), c^.P]));
        y := y + 28;
      end;
  end;
  Info(y, 'Pipe size (constrict/expand):');
  DiaRow(y + 13, c);
  y := y + 38;
  if Button(140, QX, y, 120, 18, 'Delete (Del)') then DeleteSelected;
end;

procedure DrawBucketProps(y: Single);
var
  nw, nh, nx, ny: Single;
begin
  SetC(Th.Title);
  TextR(QX, y, Format('Bucket %d', [SelB + 1]));
  y := y + 16;
  nw := Buckets[SelB].W;
  nh := Buckets[SelB].H;
  ParamRow(150, y, 'Width', nw, 40, 400, 10);
  ParamRow(153, y + 20, 'Height', nh, 30, 300, 10);
  if (nw <> Buckets[SelB].W) or (nh <> Buckets[SelB].H) then ResizeBucket(SelB, nw, nh);
  nx := Buckets[SelB].X;
  ny := Buckets[SelB].Y;
  ParamRow(180, y + 40, 'Left', nx, 0, CANVAS_W, 4);
  ParamRow(183, y + 60, 'Top', ny, 0, FLOOR_Y, 4);
  if (nx <> Buckets[SelB].X) or (ny <> Buckets[SelB].Y) then
    MoveBucket(SelB, Round(nx) - Buckets[SelB].X, Round(ny) - Buckets[SelB].Y);
  y := y + 40;
  Info(y + 44, Format('Filled %.0f%%   (%d particles)',
    [fmin(100, BucketFill(SelB) * 100), Buckets[SelB].Count]));
  if Buckets[SelB].Spilled > 0 then SetC(Th.StatusErr) else SetC(Th.TextDim);
  TextR(QX, y + 56, Format('Overflowed: %d particles', [Buckets[SelB].Spilled]));
  Info(y + 70, 'Drag with Select tool to move.');
  if Button(156, QX, y + 86, 120, 18, 'Empty bucket') then EmptyBucket(SelB);
  if Button(157, QX + 126, y + 86, 120, 18, 'Delete (Del)') then DeleteSelected;
end;

{ ---------------------------------------------------------------- file menu }

procedure SetStatus(const s: string; IsErr: Boolean = False);
begin
  StatusMsg := s;
  StatusErr := IsErr;
  StatusTime := 4;
end;

{ ---------------------------------------------------------------- zoom / pan }

const
  ZOOM_MIN = 0.5;
  ZOOM_MAX = 4.0;

{ keep the view on the layout: zoomed in it may not scroll past the edges,
  zoomed out the whole layout sits in the middle }
procedure ClampView;
begin
  if Zoom >= 1 then
  begin
    ViewX := fclamp(ViewX, 0, CANVAS_W - CANVAS_W / Zoom);
    ViewY := fclamp(ViewY, 0, CANVAS_H - CANVAS_H / Zoom);
  end
  else
  begin
    ViewX := -(CANVAS_W / Zoom - CANVAS_W) / 2;
    ViewY := -(CANVAS_H / Zoom - CANVAS_H) / 2;
  end;
end;

{ zoom to NewZoom keeping the world point under canvas-area point (sx,sy) still }
procedure ZoomAt(NewZoom, sx, sy: Single);
var
  wx, wy: Single;
begin
  NewZoom := fclamp(NewZoom, ZOOM_MIN, ZOOM_MAX);
  if Abs(NewZoom - 1) < 0.02 then NewZoom := 1;   { snap to 100% when passing it }
  wx := ViewX + sx / Zoom;
  wy := ViewY + sy / Zoom;
  Zoom := NewZoom;
  ViewX := wx - sx / Zoom;
  ViewY := wy - sy / Zoom;
  ClampView;
  OpenMenu := -1;
  SetStatus(Format('Zoom %.0f%%', [Zoom * 100]));
end;

procedure PanBy(dx, dy: Single);
begin
  ViewX := ViewX + dx;
  ViewY := ViewY + dy;
  ClampView;
end;

{ treat the bytes of s as UTF-8 (SDL hands out UTF-8 paths) }
function U8ToU(const s: string): UnicodeString;
var
  r: RawByteString;
begin
  r := s;
  SetCodePage(r, CP_UTF8, False);
  Result := UnicodeString(r);
end;

procedure UpdateTitle;
var
  t: string;
begin
  if LayoutName <> '' then t := LayoutName else t := 'untitled';
  if CurrentFile <> '' then t := t + '  [' + ExtractFileName(CurrentFile) + ']';
  t := 'Material Flow Simulator - ' + t;
  SDL_SetWindowTitle(Win, PAnsiChar(t));
end;

procedure DialogCB(userdata: Pointer; filelist: PPAnsiChar; filter: LongInt); cdecl;
var
  s: PAnsiChar;
  i: Integer;
begin
  { may run on SDL's dialog thread: copy into a static buffer, no heap use }
  if (filelist = nil) or (filelist^ = nil) then
  begin
    InterlockedExchange(DlgResult, 2);
    Exit;
  end;
  s := filelist^;
  i := 0;
  while (s[i] <> #0) and (i < High(DlgBuf)) do
  begin
    DlgBuf[i] := s[i];
    Inc(i);
  end;
  DlgBuf[i] := #0;
  InterlockedExchange(DlgResult, 1);
end;

procedure AfterLayoutChange;
begin
  HistReset;   { the undo history belongs to the page that was shown }
  TxtEdit := 0;
  TxtIdx := -1;
  SelPopup := -1;
  SelKind := selNone;
  Drag := dragNone;
  OpenMenu := -1;
  PasteArmed := False;
  UpdateTitle;
end;

procedure DoNew;
begin
  PagesReset;
  ClearAll;
  GravityScale := 1;
  CurrentFile := '';
  LayoutName := '';
  AfterLayoutChange;
  SetStatus('New blank layout');
end;

procedure DoLoadDemo;
begin
  PagesReset;
  LoadDemo;
  GravityScale := 1;
  CurrentFile := '';
  LayoutName := 'Demo';
  AfterLayoutChange;
  SetStatus('Loaded the original demo');
end;

procedure DoExample(n: Integer);
begin
  BuildExample(n);
  CurrentFile := '';
  LayoutName := ExampleTitles[n];
  AfterLayoutChange;
  SetStatus(Format('Example %d: %s', [n, ExampleTitles[n]]));
end;

procedure SaveTo(path: string);
var
  err: string;
begin
  if ExtractFileExt(path) = '' then path := path + '.mflow';
  if (LayoutName = '') or (CurrentFile = '') then
    LayoutName := ChangeFileExt(ExtractFileName(path), '');
  if SaveLayout(U8ToU(path), err) then
  begin
    CurrentFile := path;
    UpdateTitle;
    SetStatus('Saved ' + ExtractFileName(path));
  end
  else
    SetStatus('Save failed: ' + err, True);
end;

procedure OpenFrom(const path: string);
var
  err: string;
begin
  if LoadLayout(U8ToU(path), err) then
  begin
    CurrentFile := path;
    AfterLayoutChange;
    SetStatus('Loaded ' + ExtractFileName(path));
  end
  else
    SetStatus('Open failed: ' + err, True);
end;

function DefaultLoc(const s: string): PAnsiChar;
begin
  if s = '' then Result := nil else Result := PAnsiChar(s);
end;

procedure DoOpen;
begin
  OpenMenu := -1;
  if DlgKind <> 0 then Exit;
  DlgKind := 1;
  DlgResult := 0;
  SDL_ShowOpenFileDialog(@DialogCB, nil, Win, @DlgFilters[0], Length(DlgFilters), DefaultLoc(DlgDefault), False);
end;

procedure DoSaveAs;
begin
  OpenMenu := -1;
  if DlgKind <> 0 then Exit;
  DlgKind := 2;
  DlgResult := 0;
  if CurrentFile <> '' then
    SDL_ShowSaveFileDialog(@DialogCB, nil, Win, @DlgFilters[0], Length(DlgFilters), DefaultLoc(CurrentFile))
  else
    SDL_ShowSaveFileDialog(@DialogCB, nil, Win, @DlgFilters[0], Length(DlgFilters), DefaultLoc(DlgDefault));
end;

procedure DoSave;
begin
  OpenMenu := -1;
  if CurrentFile = '' then DoSaveAs else SaveTo(CurrentFile);
end;

procedure OpenPhysicsFrom(const path: string);
var
  err: string;
begin
  if LoadPhysics(U8ToU(path), err) then SetStatus('Physics loaded from ' + ExtractFileName(path))
  else SetStatus('Physics open failed: ' + err, True);
end;

procedure SavePhysicsTo(const path: string);
var
  err: string;
  p: string;
begin
  p := path;
  if ExtractFileExt(p) = '' then p := p + '.mfphys';
  if SavePhysics(U8ToU(p), err) then SetStatus('Physics saved to ' + ExtractFileName(p))
  else SetStatus('Physics save failed: ' + err, True);
end;

procedure OpenShapesFrom(const path: string);
var
  err: string;
begin
  if LoadShapes(U8ToU(path), err) then SetStatus(Format('%d shapes loaded from %s', [ShapesCount, ExtractFileName(path)]))
  else SetStatus('Shapes open failed: ' + err, True);
end;

procedure SaveShapesTo(const path: string);
var
  err: string;
  p: string;
begin
  p := path;
  if ExtractFileExt(p) = '' then p := p + '.mfshape';
  if SaveShapes(U8ToU(p), err) then SetStatus('Shapes saved to ' + ExtractFileName(p))
  else SetStatus('Shapes save failed: ' + err, True);
end;

procedure PollDialog;
var
  r: LongInt;
  k: Integer;
  path: string;
begin
  if DlgKind = 0 then Exit;
  r := InterlockedExchange(DlgResult, 0);
  if r = 0 then Exit;
  k := DlgKind;
  DlgKind := 0;
  if r <> 1 then Exit;
  path := PAnsiChar(@DlgBuf[0]);
  case k of
    1: OpenFrom(path);
    3: OpenPhysicsFrom(path);
    4: SavePhysicsTo(path);
    5: OpenShapesFrom(path);
    6: SaveShapesTo(path);
  else
    SaveTo(path);
  end;
end;

{ ---------------------------------------------------------------- edit actions }

function SelName: string;
var
  np, nb: Integer;
begin
  case SelKind of
    selCell: Result := KindNames[Grid[SelX, SelY].Kind];
    selBucket: Result := Format('bucket %d', [SelB + 1]);
    selLabel: Result := 'label';
    selFrame: Result := 'frame';
    selLink: Result := 'link';
    selEquip: Result := Equips[SelEq].Name;
    selECell: Result := EKindNames[EGrid[SelEX, SelEY].Kind] + ' ' + EGrid[SelEX, SelEY].Tag;
    selFCell: Result := FKindNames[FGrid[SelFX, SelFY].Kind] + ' ' + FGrid[SelFX, SelFY].Tag;
    selMulti:
      begin
        CountSelection(np, nb);
        Result := Format('%d parts, %d buckets', [np, nb]);
        if CountSelLabels > 0 then Result := Result + Format(', %d labels', [CountSelLabels]);
      end;
  else
    Result := '';
  end;
end;

{ copy the selection into block B }
function CopySelectionTo(var B: TBlock): Boolean;
var
  x1, y1, x2, y2, x, y, i, n: Integer;
begin
  Result := False;
  if SelKind in [selNone, selFrame, selLink] then Exit;
  SelRect(x1, y1, x2, y2);
  B.W := x2 - x1 + 1;
  B.H := y2 - y1 + 1;
  SetLength(B.Cells, B.W * B.H);
  FillChar(B.Cells[0], SizeOf(TCellLite) * Length(B.Cells), 0);   { Kind = ckEmpty }
  B.Parts := 0;
  for y := y1 to y2 do
    for x := x1 to x2 do
      if SelHasCell(x, y) then
      begin
        B.Cells[(y - y1) * B.W + (x - x1)] := CellToLite(Grid[x, y]);
        Inc(B.Parts);
      end;
  SetLength(B.Bkts, 0);
  for i := 0 to MAX_BUCKETS - 1 do
    if SelHasBucket(i) then
    begin
      n := Length(B.Bkts);
      SetLength(B.Bkts, n + 1);
      B.Bkts[n].DX := Buckets[i].X - x1 * CELL;
      B.Bkts[n].DY := Buckets[i].Y - y1 * CELL;
      B.Bkts[n].W := Buckets[i].W;
      B.Bkts[n].H := Buckets[i].H;
      B.Bkts[n].Layer := Buckets[i].Layer;
    end;
  SetLength(B.Lbls, 0);
  for i := 0 to MAX_LABELS - 1 do
    if SelHasLabel(i) then
    begin
      n := Length(B.Lbls);
      SetLength(B.Lbls, n + 1);
      B.Lbls[n].DX := Labels[i].X - x1 * CELL;
      B.Lbls[n].DY := Labels[i].Y - y1 * CELL;
      B.Lbls[n].Text := Labels[i].Text;
      B.Lbls[n].Kind := Labels[i].Kind;
      B.Lbls[n].Fmt := Labels[i].Fmt;
      B.Lbls[n].Color := Labels[i].Color;
      B.Lbls[n].NoBox := Labels[i].NoBox;
      B.Lbls[n].Layer := Labels[i].Layer;
    end;
  Result := (B.Parts > 0) or (Length(B.Bkts) > 0) or (Length(B.Lbls) > 0);
end;

function CopySelection: Boolean;
begin
  Result := CopySelectionTo(Clip);
end;

procedure ClearClip;
begin
  Clip.W := 0;
  Clip.H := 0;
  Clip.Parts := 0;
  SetLength(Clip.Cells, 0);
  SetLength(Clip.Bkts, 0);
  SetLength(Clip.Lbls, 0);
end;

procedure DoUndo;
begin
  OpenMenu := -1;
  PasteArmed := False;
  Drag := dragNone;
  if Undo then SetStatus('Undo') else SetStatus('Nothing to undo', True);
end;

procedure DoRedo;
begin
  OpenMenu := -1;
  PasteArmed := False;
  Drag := dragNone;
  if Redo then SetStatus('Redo') else SetStatus('Nothing to redo', True);
end;

procedure DoCopy;
var
  n: string;
begin
  OpenMenu := -1;
  n := SelName;
  if CopySelection then SetStatus('Copied ' + n + ' - Ctrl+V to paste')
  else SetStatus('Select parts or a bucket first', True);
end;

procedure DoCut;
var
  n: string;
begin
  OpenMenu := -1;
  n := SelName;
  if CopySelection then
  begin
    DeleteSelected;
    SetStatus('Cut ' + n + ' - Ctrl+V to paste');
  end
  else
    SetStatus('Select parts or a bucket first', True);
end;

procedure DoDelete;
var
  n: string;
begin
  OpenMenu := -1;
  n := SelName;
  if SelKind = selNone then
    SetStatus('Select parts or a bucket first', True)
  else
  begin
    DeleteSelected;
    SetStatus('Deleted ' + n);
  end;
end;

procedure DoPaste;
begin
  OpenMenu := -1;
  if ClipEmpty then
  begin
    SetStatus('Clipboard is empty - Cut or Copy first', True);
    Exit;
  end;
  PasteArmed := True;
  SetStatus('Click on the canvas to paste (Esc cancels)');
end;

{ put block B with its top-left corner at grid cell gx,gy and select it;
  returns a short description for the status line (Lost = items that did not fit) }
function PlaceBlock(const B: TBlock; gx, gy: Integer; out Lost: Integer): string;
var
  L: TCellLite;
  x, y, tx, ty, d, i, bi, placed, bks, lastB, lbs, lastL: Integer;
begin
  Lost := 0;
  Result := '';
  if (B.Parts = 0) and (Length(B.Bkts) = 0) and (Length(B.Lbls) = 0) then Exit;
  gx := EnsureRange(gx, 0, GW - 1);
  gy := EnsureRange(gy, 0, GH - 1);

  { a single part dropped on an existing pipe is inserted into it, keeping its joints }
  if IsSinglePart(B) and (Grid[gx, gy].Kind <> ckEmpty) then
  begin
    L := B.Cells[0];
    L.Conn := Grid[gx, gy].Conn;
    L.Layer := Grid[gx, gy].Layer;
    LiteToCell(L, gx, gy, False);
    SelectCell(gx, gy);
    Result := 'inserted ' + KindNames[L.Kind];
    Exit;
  end;

  placed := 0;
  lastB := -1;
  { 1: put the parts down (whatever was underneath is replaced) }
  for y := 0 to B.H - 1 do
    for x := 0 to B.W - 1 do
    begin
      L := B.Cells[y * B.W + x];
      if L.Kind = ckEmpty then Continue;
      tx := gx + x;
      ty := gy + y;
      if not InGrid(tx, ty) then
      begin
        Inc(Lost);
        Continue;
      end;
      if Grid[tx, ty].Kind <> ckEmpty then EraseCell(tx, ty);
      L.Conn := 0;
      if not KeepLayers then L.Layer := CurLayer;
      LiteToCell(L, tx, ty, False);
      Inc(placed);
    end;
  { 2: rejoin: inside the block as copied, at the edge to whatever is there now }
  for y := 0 to B.H - 1 do
    for x := 0 to B.W - 1 do
    begin
      L := B.Cells[y * B.W + x];
      if L.Kind = ckEmpty then Continue;
      tx := gx + x;
      ty := gy + y;
      if not InGrid(tx, ty) then Continue;
      for d := 0 to 3 do
        if (L.Conn and (1 shl d)) <> 0 then
          ConnectCells(tx, ty, tx + DXS[d], ty + DYS[d]);
    end;
  { 3: buckets }
  bks := 0;
  for i := 0 to High(B.Bkts) do
  begin
    bi := AddBucket(gx * CELL + B.Bkts[i].DX + B.Bkts[i].W / 2, gy * CELL + B.Bkts[i].DY,
      B.Bkts[i].W, B.Bkts[i].H);
    if bi >= 0 then
    begin
      if KeepLayers then Buckets[bi].Layer := B.Bkts[i].Layer;
      Inc(bks);
      lastB := bi;
    end
    else
      Inc(Lost);
  end;

  { 4: labels }
  lbs := 0;
  lastL := -1;
  for i := 0 to High(B.Lbls) do
  begin
    bi := AddLabel(gx * CELL + B.Lbls[i].DX, gy * CELL + B.Lbls[i].DY, B.Lbls[i].Text);
    if bi >= 0 then
    begin
      Labels[bi].Kind := B.Lbls[i].Kind;
      Labels[bi].Fmt := B.Lbls[i].Fmt;
      Labels[bi].Color := B.Lbls[i].Color;
      Labels[bi].NoBox := B.Lbls[i].NoBox;
      if KeepLayers then Labels[bi].Layer := B.Lbls[i].Layer;
      Inc(lbs);
      lastL := bi;
    end
    else
      Inc(Lost);
  end;

  { select what was placed so it can be moved / cut again right away }
  if (placed = 1) and (bks = 0) and (lbs = 0) and (B.W = 1) and (B.H = 1) then
    SelectCell(gx, gy)
  else if (placed = 0) and (bks = 0) and (lbs = 1) then
  begin
    SelKind := selLabel;
    SelL := lastL;
  end
  else if (placed = 0) and (bks = 1) and (lbs = 0) then
  begin
    SelKind := selBucket;
    SelB := lastB;
  end
  else
    SelectBox(gx, gy, Min(GW - 1, gx + B.W - 1), Min(GH - 1, gy + B.H - 1));

  if (placed = 1) and (bks = 0) then
    Result := KindNames[Grid[gx, gy].Kind]
  else
    Result := Format('%d parts, %d buckets', [placed, bks]);
  if lbs > 0 then Result := Result + Format(', %d labels', [lbs]);
  if Lost > 0 then Result := Result + Format(' (%d did not fit)', [Lost]);
end;

{ put the clipboard with its top-left corner at grid cell gx,gy }
procedure PlacePaste(gx, gy: Integer);
var
  s: string;
  lost: Integer;
begin
  PasteArmed := False;
  if ClipEmpty then Exit;
  { pasted items go on the active layer }
  KeepLayers := False;
  s := PlaceBlock(Clip, gx, gy, lost);
  KeepLayers := True;
  if Pos('inserted', s) = 1 then
    SetStatus(UpCase(s[1]) + Copy(s, 2, MaxInt))
  else
    SetStatus('Pasted ' + s, lost > 0);
end;

{ ---------------------------------------------------------------- moving the selection }

{ left press on a selected part (or bucket in a box): get ready to drag it }
procedure StartMove(gx, gy, PressedBucket: Integer);
var
  x2, y2: Integer;
begin
  if not CopySelectionTo(MoveBuf) then Exit;
  SelRect(MoveX1, MoveY1, x2, y2);
  MoveGX0 := gx;
  MoveGY0 := gy;
  MoveDX := 0;
  MoveDY := 0;
  MovePressBucket := PressedBucket;
  Drag := dragMove;
end;

procedure UpdateMove;
var
  gx, gy: Integer;
begin
  gx := EnsureRange(Trunc(MWX / CELL), 0, GW - 1);
  gy := EnsureRange(Trunc(MWY / CELL), 0, GH - 1);
  { keep the whole block on the grid }
  MoveDX := EnsureRange(gx - MoveGX0, -MoveX1, GW - MoveBuf.W - MoveX1);
  MoveDY := EnsureRange(gy - MoveGY0, -MoveY1, GH - MoveBuf.H - MoveY1);
end;

procedure FinishMove;
var
  s: string;
  lost: Integer;
begin
  if (MoveDX = 0) and (MoveDY = 0) then
  begin
    { a plain click inside a box selection picks just that item }
    if SelKind = selMulti then
    begin
      if Grid[MoveGX0, MoveGY0].Kind <> ckEmpty then
        SelectCell(MoveGX0, MoveGY0)
      else if MovePressBucket >= 0 then
      begin
        SelKind := selBucket;
        SelB := MovePressBucket;
      end;
    end;
    Exit;
  end;
  DeleteSelected;
  s := PlaceBlock(MoveBuf, MoveX1 + MoveDX, MoveY1 + MoveDY, lost);
  SetStatus('Moved ' + s, lost > 0);
end;

{ ---------------------------------------------------------------- typing names and texts }

procedure StopEditLabel; forward;
procedure StopEditFrame; forward;

function TxtMax: Integer;
begin
  case TxtEdit of
    1, 5: Result := 40;
    2, 6: Result := 24;
    7, 8: Result := 12;
    3: Result := 60;
    4: Result := 255;
  else
    Result := 0;
  end;
end;

function TxtValue: string;
begin
  Result := '';
  case TxtEdit of
    1: Result := Pages[TxtIdx].Name;
    2: Result := Pages[CurPage].Layers[TxtIdx].Name;
    3: Result := Popups[TxtIdx].Title;
    4: Result := Popups[TxtIdx].Text;
    5: Result := Links[TxtIdx].Caption;
    6: Result := Equips[TxtIdx].Name;
    7: Result := EGrid[TxtIdx mod GW, TxtIdx div GW].Tag;
    8: Result := FGrid[TxtIdx mod GW, TxtIdx div GW].Tag;
  end;
end;

procedure TxtStore(const s: string);
begin
  case TxtEdit of
    1: Pages[TxtIdx].Name := s;
    2: Pages[CurPage].Layers[TxtIdx].Name := s;
    3: Popups[TxtIdx].Title := s;
    4: Popups[TxtIdx].Text := s;
    5: Links[TxtIdx].Caption := s;
    6: Equips[TxtIdx].Name := s;
    7: EGrid[TxtIdx mod GW, TxtIdx div GW].Tag := s;
    8: FGrid[TxtIdx mod GW, TxtIdx div GW].Tag := s;
  end;
end;

procedure StopTxt;
begin
  if TxtEdit = 0 then Exit;
  TxtEdit := 0;
  TxtIdx := -1;
  if Win <> nil then SDL_StopTextInput(Win);
end;

{ Kind: 1 page name, 2 layer name, 3 popup title, 4 popup text, 5 link caption }
procedure StartTxt(Kind, Idx: Integer);
const
  What: array[1..8] of string = ('the page name', 'the layer name', 'the popup title', 'the popup text',
    'the link caption', 'the equipment name', 'the tag', 'the tag');
begin
  StopEditLabel;
  StopEditFrame;
  StopTxt;
  TxtEdit := Kind;
  TxtIdx := Idx;
  OpenMenu := -1;
  PopupOpen := False;
  if Win <> nil then SDL_StartTextInput(Win);
  if Kind = 4 then SetStatus('Type ' + What[Kind] + ' - Enter: new line, Esc: done')
  else SetStatus('Type ' + What[Kind] + ' - Enter or Esc: done');
end;

{ a blinking caret while (Kind, Idx) is being typed into }
function TxtCaret(Kind, Idx: Integer): string;
begin
  if (TxtEdit = Kind) and (TxtIdx = Idx) and ((SDL_GetTicksNS div 500000000) mod 2 = 0) then Result := '_'
  else Result := '';
end;

procedure TxtTypeText(const s: string);
var
  k: Integer;
  t: string;
begin
  if TxtEdit = 0 then Exit;
  t := TxtValue;
  for k := 1 to Length(s) do
    if (s[k] >= ' ') and (s[k] <= '~') and (Length(t) < TxtMax) then t := t + s[k];
  TxtStore(t);
end;

procedure TxtKey(key: UInt32);
var
  t: string;
begin
  if TxtEdit = 0 then Exit;
  t := TxtValue;
  case key of
    SDLK_BACKSPACE:
      if t <> '' then TxtStore(Copy(t, 1, Length(t) - 1));
    SDLK_RETURN, SDLK_KP_ENTER:
      if (TxtEdit = 4) and (Length(t) < TxtMax) then TxtStore(t + #10) else StopTxt;
    SDLK_ESCAPE:
      StopTxt;
  end;
end;

{ ---------------------------------------------------------------- frame editing }

procedure StopEditFrame;
begin
  if EditFrame < 0 then Exit;
  EditFrame := -1;
  if Win <> nil then SDL_StopTextInput(Win);
end;

procedure StartEditFrame(i: Integer);
begin
  if (i < 0) or not Frames[i].Active then Exit;
  StopTxt;
  EditFrame := i;
  SelKind := selFrame;
  SelFr := i;
  OpenMenu := -1;
  PopupOpen := False;
  if Win <> nil then SDL_StartTextInput(Win);
  SetStatus('Type the frame title - Enter or Esc: done');
end;

procedure FrameTypeText(const s: string);
var
  k: Integer;
begin
  if EditFrame < 0 then Exit;
  for k := 1 to Length(s) do
    if (s[k] >= ' ') and (s[k] <= '~') and (Length(Frames[EditFrame].Title) < 60) then
      Frames[EditFrame].Title := Frames[EditFrame].Title + s[k];
end;

procedure FrameKey(key: UInt32);
var
  t: string;
begin
  if EditFrame < 0 then Exit;
  t := Frames[EditFrame].Title;
  case key of
    SDLK_BACKSPACE:
      if t <> '' then Frames[EditFrame].Title := Copy(t, 1, Length(t) - 1);
    SDLK_RETURN, SDLK_KP_ENTER, SDLK_ESCAPE:
      StopEditFrame;
  end;
end;

{ the Frame tool was dragged from FrX0,FrY0 to FrX1,FrY1 (a click gives a default size) }
procedure FinishFrameNew;
var
  x1, y1, x2, y2: Single;
  i, n: Integer;
begin
  x1 := SnapCell(fmin(FrX0, FrX1));
  y1 := SnapCell(fmin(FrY0, FrY1));
  x2 := SnapCell(fmax(FrX0, FrX1));
  y2 := SnapCell(fmax(FrY0, FrY1));
  if (x2 - x1 < 2 * CELL) or (y2 - y1 < 2 * CELL) then
  begin
    x2 := x1 + 8 * CELL;
    y2 := y1 + 6 * CELL;
  end;
  n := 1;
  for i := 0 to MAX_FRAMES - 1 do
    if Frames[i].Active then Inc(n);
  i := AddFrame(x1, y1, x2 - x1, y2 - y1, Format('Group %d', [n]));
  if i < 0 then
  begin
    SetStatus(Format('Too many frames (max %d)', [MAX_FRAMES]), True);
    Exit;
  end;
  StartEditFrame(i);
end;

{ the frame's title was dragged FrDX, FrDY cells: move it, and (Carry) what is inside it }
procedure FinishFrameMove;
var
  f, x1, y1, x2, y2, lost: Integer;
  s: string;
begin
  f := FrDrag;
  if (f < 0) or not Frames[f].Active or ((FrDX = 0) and (FrDY = 0)) then Exit;
  s := '';
  if Frames[f].Carry then
  begin
    FrameCells(f, x1, y1, x2, y2);
    SelectBox(x1, y1, x2, y2);
    if SelKind <> selNone then
    begin
      CopySelectionTo(MoveBuf);
      SelRect(x1, y1, x2, y2);
      DeleteSelected;
      s := PlaceBlock(MoveBuf, x1 + FrDX, y1 + FrDY, lost);
    end;
  end;
  Frames[f].X := Frames[f].X + FrDX * CELL;
  Frames[f].Y := Frames[f].Y + FrDY * CELL;
  SelKind := selFrame;
  SelFr := f;
  if s <> '' then SetStatus('Moved the frame with ' + s) else SetStatus('Moved the frame');
end;

{ while the title is dragged: the move in whole cells, keeping the frame on the canvas }
procedure UpdateFrameMove;
var
  f: Integer;
begin
  f := FrDrag;
  if f < 0 then Exit;
  FrDX := Round((MWX - FrX0) / CELL);
  FrDY := Round((MWY - FrY0) / CELL);
  FrDX := EnsureRange(FrDX, -Round(Frames[f].X / CELL), Round((CANVAS_W - Frames[f].X - Frames[f].W) / CELL));
  FrDY := EnsureRange(FrDY, -Round(Frames[f].Y / CELL), Round((CANVAS_H - Frames[f].Y - Frames[f].H) / CELL));
end;

procedure UpdateFrameSize;
var
  f: Integer;
begin
  f := FrDrag;
  if f < 0 then Exit;
  Frames[f].W := fclamp(SnapCell(MWX - Frames[f].X), 2 * CELL, CANVAS_W - Frames[f].X);
  Frames[f].H := fclamp(SnapCell(MWY - Frames[f].Y), 2 * CELL, CANVAS_H - Frames[f].Y);
end;

procedure SelectFrameContents(f: Integer);
var
  x1, y1, x2, y2, np, nb: Integer;
begin
  FrameCells(f, x1, y1, x2, y2);
  SelectBox(x1, y1, x2, y2);
  CountSelection(np, nb);
  if SelKind = selNone then SetStatus('The frame is empty')
  else SetStatus(Format('Selected %d parts, %d buckets, %d labels in the frame', [np, nb, CountSelLabels]));
end;

procedure DrawFrameProps(y: Single);
var
  f, c, np, nb, x1, y1, x2, y2: Integer;
  r, g, b: Byte;
  caret: string;
begin
  f := SelFr;
  SetC(Th.Title);
  TextR(QX, y, Format('Frame %d', [f + 1]));
  y := y + 16;
  Info(y, 'Groups and titles a part of the layout.');
  y := y + 16;
  if (EditFrame = f) and ((SDL_GetTicksNS div 500000000) mod 2 = 0) then caret := '_' else caret := '';
  SetC(Th.OverlayBg);
  FillR(QX, y, 280, 18);
  SetC(Th.MenuBorder);
  RectR(QX, y, 280, 18);
  SetC(Th.Text);
  TextR(QX + 4, y + 5, Copy(Frames[f].Title + caret, 1, 34));
  y := y + 24;
  if EditFrame = f then
  begin
    if Button(270, QX, y, 136, 18, 'Done', True) then StopEditFrame;
  end
  else if Button(271, QX, y, 136, 18, 'Edit title') then StartEditFrame(f);
  if Button(272, QX + 142, y, 136, 18, 'Select contents') then
  begin
    SelectFrameContents(f);
    Exit;
  end;
  y := y + 26;
  Info(y, 'Colour');
  y := y + 12;
  for c := 0 to 5 do
  begin
    if Button(273 + c, QX + c * 47, y, 44, 18, LabelColorNames[c], Frames[f].Color = c) then Frames[f].Color := c;
    FrameRGB(c, r, g, b);
    SetCol(r, g, b);
    FillR(QX + c * 47 + 2, y + 15, 40, 2);
  end;
  y := y + 24;
  if Button(280, QX, y, 90, 18, 'Solid', not Frames[f].Dashed) then Frames[f].Dashed := False;
  if Button(281, QX + 94, y, 90, 18, 'Dashed', Frames[f].Dashed) then Frames[f].Dashed := True;
  if Frames[f].Fill then
  begin
    if Button(282, QX + 188, y, 92, 18, 'Tint: on', True) then Frames[f].Fill := False;
  end
  else if Button(282, QX + 188, y, 92, 18, 'Tint: off') then Frames[f].Fill := True;
  y := y + 24;
  if Frames[f].Carry then
  begin
    if Button(283, QX, y, 280, 18, 'Moving it moves its contents: on', True) then Frames[f].Carry := False;
  end
  else if Button(283, QX, y, 280, 18, 'Moving it moves its contents: off') then Frames[f].Carry := True;
  y := y + 26;
  FrameCells(f, x1, y1, x2, y2);
  Info(y, Format('Size %d x %d cells at [%d,%d]', [x2 - x1 + 1, y2 - y1 + 1, x1, y1]));
  SelectBox(x1, y1, x2, y2);
  CountSelection(np, nb);
  Info(y + 12, Format('Inside: %d parts, %d buckets, %d labels', [np, nb, CountSelLabels]));
  SelKind := selFrame;   { counting used the selection; the frame stays selected }
  SelFr := f;
  y := y + 30;
  if Button(284, QX, y, 136, 18, 'Delete (Del)') then DeleteSelected;
  Info(y + 26, 'Drag its title to move it, the');
  Info(y + 38, 'corner square to resize it.');
end;

{ ---------------------------------------------------------------- label editing }

const
  { FormatDateTime patterns offered for date / time labels }
  DatePresets: array[0..6] of string = ('yyyy-mm-dd', 'dd/mm/yyyy', 'mm/dd/yyyy', 'd mmm yyyy',
    'dddd, d mmmm yyyy', 'dd.mm.yy', 'ddd d mmm');
  TimePresets: array[0..5] of string = ('hh:nn:ss', 'hh:nn', 'h:nn:ss am/pm', 'h:nn am/pm',
    'hh:nn:ss.zzz', 'hh"h"nn');

{ finish typing; a text label left empty is removed (a date / time label always shows its value) }
procedure StopEditLabel;
var
  i: Integer;
begin
  if EditLabel < 0 then Exit;
  i := EditLabel;
  EditLabel := -1;
  EditField := 0;
  if Win <> nil then SDL_StopTextInput(Win);
  if Labels[i].Active and (Labels[i].Kind = LBL_TEXT) and (Trim(Labels[i].Text) = '') then
  begin
    DeleteLabel(i);
    if (SelKind = selLabel) and (SelL = i) then SelKind := selNone;
  end;
end;

procedure BeginEdit(i, Field: Integer);
begin
  if (i < 0) or not Labels[i].Active then Exit;
  StopTxt;
  if EditLabel <> i then StopEditLabel;
  EditLabel := i;
  EditField := Field;
  SelKind := selLabel;
  SelL := i;
  OpenMenu := -1;
  PopupOpen := False;
  if Win <> nil then SDL_StartTextInput(Win);
end;

{ type into a label's text (for a date / time label: its caption) }
procedure StartEditLabel(i: Integer);
begin
  BeginEdit(i, 0);
  if (i >= 0) and (Labels[i].Kind <> LBL_TEXT) then
    SetStatus('Type a caption - Enter: new line, Esc or click away: done')
  else
    SetStatus('Type the label - Enter: new line, Esc or click away: done');
end;

{ type a date / time label's format }
procedure StartEditFormat(i: Integer);
begin
  BeginEdit(i, 1);
  SetStatus('Type a format, e.g. dd/mm/yyyy or hh:nn - Enter or Esc: done');
end;

{ a label that shows today's date (LBL_DATE) or the time (LBL_TIME) }
function AddClockLabel(X, Y: Single; Kind: Integer): Integer;
begin
  Result := AddLabel(X, Y, '');
  if Result < 0 then Exit;
  Labels[Result].Kind := Kind;
  if Kind = LBL_DATE then Labels[Result].Fmt := DatePresets[0] else Labels[Result].Fmt := TimePresets[0];
end;

{ typed text (UTF-8 from SDL); the built-in font only has plain ASCII }
procedure LabelTypeText(const s: string);
var
  k: Integer;
begin
  if EditLabel < 0 then Exit;
  for k := 1 to Length(s) do
    if (s[k] >= ' ') and (s[k] <= '~') then
    begin
      if EditField = 1 then
      begin
        if Length(Labels[EditLabel].Fmt) < 40 then Labels[EditLabel].Fmt := Labels[EditLabel].Fmt + s[k];
      end
      else if Length(Labels[EditLabel].Text) < 255 then
        Labels[EditLabel].Text := Labels[EditLabel].Text + s[k];
    end;
end;

{ keys while typing into a label; True when the key was used }
function LabelKey(key: UInt32): Boolean;
var
  t: string;
begin
  Result := EditLabel >= 0;
  if not Result then Exit;
  if EditField = 1 then
  begin
    t := Labels[EditLabel].Fmt;
    case key of
      SDLK_BACKSPACE:
        if t <> '' then Labels[EditLabel].Fmt := Copy(t, 1, Length(t) - 1);
      SDLK_RETURN, SDLK_KP_ENTER, SDLK_ESCAPE:
        StopEditLabel;
    end;
    Exit;
  end;
  t := Labels[EditLabel].Text;
  case key of
    SDLK_BACKSPACE:
      if t <> '' then Labels[EditLabel].Text := Copy(t, 1, Length(t) - 1);
    SDLK_RETURN, SDLK_KP_ENTER:
      if Length(t) < 255 then Labels[EditLabel].Text := t + #10;
    SDLK_ESCAPE:
      StopEditLabel;
  end;
end;

{ draw up to MaxLines lines of s in a framed box; the first TitleLines in the accent colour }
procedure PreviewBox(y, h: Single; const s: string; MaxLines, TitleLines: Integer);
var
  k, n: Integer;
  line: string;
begin
  SetC(Th.OverlayBg);
  FillR(QX, y, 280, h);
  SetC(Th.MenuBorder);
  RectR(QX, y, 280, h);
  line := '';
  n := 0;
  for k := 1 to Length(s) + 1 do
    if (k > Length(s)) or (s[k] = #10) then
    begin
      if n < MaxLines then
      begin
        if n < TitleLines then SetC(Th.Title) else SetC(Th.Text);
        TextR(QX + 4, y + 4 + n * 11, Copy(line, 1, 34));
      end;
      line := '';
      Inc(n);
    end
    else
      line := line + s[k];
end;

{ colour buttons and the box switch, for any label }
procedure LabelStyleRows(y: Single);
var
  c: Integer;
  r, g, b: Byte;
begin
  for c := 0 to 5 do
  begin
    if Button(250 + c, QX + c * 47, y, 44, 18, LabelColorNames[c], Labels[SelL].Color = c) then
      Labels[SelL].Color := c;
    if c > 0 then
    begin
      LabelRGB(c, r, g, b);
      SetCol(r, g, b);
      FillR(QX + c * 47 + 2, y + 15, 40, 2);
    end;
  end;
  if Labels[SelL].NoBox then
  begin
    if Button(256, QX, y + 24, 136, 18, 'Box: off') then Labels[SelL].NoBox := False;
  end
  else if Button(256, QX, y + 24, 136, 18, 'Box: on', True) then Labels[SelL].NoBox := True;
  if Button(196, QX + 142, y + 24, 136, 18, 'Delete (Del)') then DeleteSelected;
end;

procedure DrawClockLabelProps(y: Single);
var
  i, n, rows, titles: Integer;
  s, caret: string;
  isDate: Boolean;
begin
  isDate := Labels[SelL].Kind = LBL_DATE;
  SetC(Th.Title);
  if isDate then TextR(QX, y, Format('Date label %d', [SelL + 1]))
  else TextR(QX, y, Format('Time label %d', [SelL + 1]));
  y := y + 14;
  if Labels[SelL].Text = '' then titles := 0 else LabelLines(Labels[SelL].Text, titles, n);
  PreviewBox(y, 30, LabelDisplay(SelL), 2, titles);
  y := y + 36;
  { the format, with a caret while it is being typed }
  if (EditLabel = SelL) and (EditField = 1) and ((SDL_GetTicksNS div 500000000) mod 2 = 0) then caret := '_'
  else caret := '';
  SetC(Th.Text);
  TextR(QX, y, 'Format: ' + Labels[SelL].Fmt + caret);
  y := y + 13;
  if (EditLabel = SelL) and (EditField = 1) then
  begin
    if Button(259, QX, y, 136, 18, 'Done', True) then StopEditLabel;
  end
  else if Button(257, QX, y, 136, 18, 'Type a format') then StartEditFormat(SelL);
  if (EditLabel = SelL) and (EditField = 0) then
  begin
    if Button(258, QX + 142, y, 136, 18, 'Done', True) then StopEditLabel;
  end
  else if Button(258, QX + 142, y, 136, 18, 'Edit caption') then StartEditLabel(SelL);
  y := y + 24;
  { presets, two per row }
  if isDate then n := Length(DatePresets) else n := Length(TimePresets);
  for i := 0 to n - 1 do
  begin
    if isDate then s := DatePresets[i] else s := TimePresets[i];
    if Button(240 + i, QX + (i mod 2) * 142, y + (i div 2) * 21, 138, 18, s, Labels[SelL].Fmt = s) then
    begin
      if EditLabel = SelL then StopEditLabel;
      Labels[SelL].Fmt := s;
    end;
  end;
  rows := (n + 1) div 2;
  y := y + rows * 21 + 2;
  { the codes, for typing a format of one's own }
  if isDate then
  begin
    Info(y, 'd dd ddd dddd   m mm mmm mmmm');
    Info(y + 11, 'yy yyyy   "text" kept as typed');
  end
  else
  begin
    Info(y, 'h hh  n nn (minutes)  s ss  z zzz');
    Info(y + 11, 'am/pm   "text" kept as typed');
  end;
  y := y + 27;
  LabelStyleRows(y);
end;

procedure DrawLabelProps(y: Single);
var
  nx, ny: Single;
begin
  if Labels[SelL].Kind <> LBL_TEXT then
  begin
    DrawClockLabelProps(y);
    Exit;
  end;
  SetC(Th.Title);
  TextR(QX, y, Format('Label %d', [SelL + 1]));
  y := y + 16;
  Info(y, 'Text (first line is the title):');
  PreviewBox(y + 12, 74, Labels[SelL].Text, 6, 1);
  y := y + 92;
  if EditLabel = SelL then
  begin
    if Button(194, QX, y, 136, 18, 'Done typing', True) then StopEditLabel;
  end
  else if Button(195, QX, y, 136, 18, 'Edit text') then StartEditLabel(SelL);
  y := y + 26;
  LabelStyleRows(y);
  y := y + 50;
  nx := Labels[SelL].X;
  ny := Labels[SelL].Y;
  ParamRow(197, y, 'Left', nx, 0, CANVAS_W - 16, 4);
  ParamRow(200 + 7, y + 20, 'Top', ny, 0, CANVAS_H - 12, 4);
  Labels[SelL].X := Round(nx);
  Labels[SelL].Y := Round(ny);
  Info(y + 46, 'Double-click a label to edit it;');
  Info(y + 58, 'drag it with the Select tool.');
end;

{ ---------------------------------------------------------------- rotating the selection }

{ block A turned a quarter turn (clockwise when CW) into B: cells, their joints,
  device directions and bucket positions }
{ ---------------------------------------------------------------- pages, layers, links, popups }

var
  PageDelArmed: Single = 0;      { seconds left to confirm deleting the page }
  LayerDelArmed: Single = 0;

{ leave whatever is being edited on this page; the undo history is per page }
procedure LeavePageEdits;
begin
  StopEditLabel;
  StopEditFrame;
  StopTxt;
  SelKind := selNone;
  Drag := dragNone;
  FrDrag := -1;
  PasteArmed := False;
end;

procedure AppGoToPage(i: Integer);
begin
  if (i < 0) or (i >= PageCount) then
  begin
    SetStatus('That link has no page to go to', True);
    Exit;
  end;
  CloseFramePopup;
  if i = CurPage then
  begin
    SetStatus(Format('Already on page %d: %s', [i + 1, PageName(i)]));
    Exit;
  end;
  LeavePageEdits;
  HistCheck;
  GoToPage(i);
  HistReset;
  SetStatus(Format('Page %d of %d: %s', [i + 1, PageCount, PageName(i)]));
end;

procedure AppFollowLink(i: Integer);
begin
  if (i < 0) or not Links[i].Active then Exit;
  if Links[i].ToPopup then
  begin
    if (Links[i].Target >= 0) and (Links[i].Target < MAX_POPUPS) and Popups[Links[i].Target].Active then
    begin
      ShowFramePopup(Links[i].Target);
      SelPopup := Links[i].Target;
    end
    else
      SetStatus('That link has no frame popup to open', True);
  end
  else
    AppGoToPage(Links[i].Target);
end;

{ the frame popup's "go to page" button asked for a page while it was drawn }
procedure TakePendingPage;
var
  p: Integer;
begin
  if PendingPage < 0 then Exit;
  p := PendingPage;
  PendingPage := -1;
  AppGoToPage(p);
end;

procedure AppAddPage;
var
  i: Integer;
begin
  i := AddPage('');
  if i < 0 then
  begin
    SetStatus(Format('A layout has at most %d pages', [MAX_PAGES]), True);
    Exit;
  end;
  AppGoToPage(i);
  SetStatus(Format('Added page %d - double-click its button to rename it', [i + 1]));
end;

procedure AppDuplicatePage;
var
  i: Integer;
begin
  LeavePageEdits;
  HistCheck;
  i := DuplicatePage(CurPage);
  if i < 0 then
  begin
    SetStatus(Format('A layout has at most %d pages', [MAX_PAGES]), True);
    Exit;
  end;
  AppGoToPage(i);
  SetStatus(Format('Page %d is a copy of the page before', [i + 1]));
end;

procedure AppDeletePage;
var
  n: string;
begin
  if PageCount <= 1 then
  begin
    SetStatus('The last page cannot be deleted', True);
    Exit;
  end;
  if PageDelArmed <= 0 then
  begin
    PageDelArmed := 3;
    SetStatus(Format('Click Delete again to delete page %d: %s (no undo)', [CurPage + 1, PageName(CurPage)]), True);
    Exit;
  end;
  PageDelArmed := 0;
  n := PageName(CurPage);
  LeavePageEdits;
  CloseFramePopup;
  DeletePage(CurPage);
  HistReset;
  SetStatus(Format('Deleted page "%s" - now on page %d', [n, CurPage + 1]));
end;

procedure AppMovePage(Delta: Integer);
var
  j: Integer;
begin
  j := CurPage + Delta;
  if (j < 0) or (j >= PageCount) then Exit;
  LeavePageEdits;
  HistCheck;
  MovePage(CurPage, Delta);
  HistReset;
  SetStatus(Format('"%s" is page %d now', [PageName(CurPage), CurPage + 1]));
end;

procedure AppSetLayer(L: Integer);
begin
  if (L < 0) or (L >= LayerCount) then Exit;
  SetActiveLayer(L);
  Pages[CurPage].Layers[L].Visible := True;
  if Pages[CurPage].Layers[L].Locked then
    SetStatus('Active layer: ' + Pages[CurPage].Layers[L].Name + ' (locked - unlock it to edit)', True)
  else
    SetStatus('Active layer: ' + Pages[CurPage].Layers[L].Name + ' - new items go on it');
end;

{ hiding or locking a layer drops what is selected on it }
procedure DropHiddenSelection;
begin
  case SelKind of
    selCell: if CellBlocked(SelX, SelY) then SelKind := selNone;
    selBucket: if not LayerEditable(Buckets[SelB].Layer) then SelKind := selNone;
    selLabel: if not LayerEditable(Labels[SelL].Layer) then SelKind := selNone;
    selFrame: if not LayerEditable(Frames[SelFr].Layer) then SelKind := selNone;
    selLink: if not LayerEditable(Links[SelLk].Layer) then SelKind := selNone;
    selEquip: if not LayerEditable(Equips[SelEq].Layer) then SelKind := selNone;
    selECell: if not LayerEditable(EGrid[SelEX, SelEY].Layer) then SelKind := selNone;
    selFCell: if not LayerEditable(FGrid[SelFX, SelFY].Layer) then SelKind := selNone;
  end;
  if (EditLabel >= 0) and not LayerEditable(Labels[EditLabel].Layer) then StopEditLabel;
  if (EditFrame >= 0) and not LayerEditable(Frames[EditFrame].Layer) then StopEditFrame;
end;

procedure AppAddLayer;
var
  L: Integer;
begin
  L := AddLayer('');
  if L < 0 then
  begin
    SetStatus(Format('A page has at most %d layers', [MAX_LAYERS]), True);
    Exit;
  end;
  AppSetLayer(L);
end;

procedure AppDeleteLayer;
var
  L: Integer;
begin
  L := CurLayer;
  if LayerCount <= 1 then
  begin
    SetStatus('A page keeps at least one layer', True);
    Exit;
  end;
  if LayerDelArmed <= 0 then
  begin
    LayerDelArmed := 3;
    SetStatus('Click again: delete layer "' + Pages[CurPage].Layers[L].Name + '" (its items move down a layer)', True);
    Exit;
  end;
  LayerDelArmed := 0;
  StopTxt;
  DeleteLayer(L);
  SetStatus('Layer deleted; its items are on "' + Pages[CurPage].Layers[CurLayer].Name + '" now');
end;

{ put what is selected on the active layer }
procedure SelectionToLayer;
var
  x, y, i, n: Integer;
begin
  n := 0;
  case SelKind of
    selCell: begin Grid[SelX, SelY].Layer := CurLayer; n := 1; end;
    selBucket: begin Buckets[SelB].Layer := CurLayer; n := 1; end;
    selLabel: begin Labels[SelL].Layer := CurLayer; n := 1; end;
    selFrame: begin Frames[SelFr].Layer := CurLayer; n := 1; end;
    selLink: begin Links[SelLk].Layer := CurLayer; n := 1; end;
    selEquip: begin Equips[SelEq].Layer := CurLayer; n := 1; end;
    selECell: begin EGrid[SelEX, SelEY].Layer := CurLayer; n := 1; end;
    selFCell: begin FGrid[SelFX, SelFY].Layer := CurLayer; n := 1; end;
    selMulti:
      begin
        for i := 0 to MAX_BUCKETS - 1 do
          if SelHasBucket(i) then begin Buckets[i].Layer := CurLayer; Inc(n); end;
        for i := 0 to MAX_LABELS - 1 do
          if SelHasLabel(i) then begin Labels[i].Layer := CurLayer; Inc(n); end;
        for y := SelY1 to SelY2 do
          for x := SelX1 to SelX2 do
            if SelHasCell(x, y) then begin Grid[x, y].Layer := CurLayer; Inc(n); end;
      end;
  end;
  if n = 0 then SetStatus('Select something first, then move it to the active layer', True)
  else SetStatus(Format('%d item(s) moved to layer "%s"', [n, Pages[CurPage].Layers[CurLayer].Name]));
end;

{ the default caption of a link: the name of what it points at }
function LinkDefaultCaption(ToPopup: Boolean; T: Integer): string;
begin
  if ToPopup then
  begin
    if (T >= 0) and (T < MAX_POPUPS) and Popups[T].Active then Result := Copy(Popups[T].Title, 1, 40)
    else Result := 'Info';
  end
  else if (T >= 0) and (T < PageCount) then Result := Copy(PageName(T), 1, 40)
  else Result := 'Page';
end;

{ the next active popup after T in direction D (+1 / -1), or -1 when there is none }
function NextPopup(T, D: Integer): Integer;
var
  k: Integer;
begin
  for k := 1 to MAX_POPUPS do
  begin
    T := (T + D + MAX_POPUPS) mod MAX_POPUPS;
    if Popups[T].Active then Exit(T);
  end;
  Result := -1;
end;

{ a new link at wx, wy: to the next page (or the first popup when there is just one page) }
function NewLinkAt(wx, wy: Single): Integer;
var
  t: Integer;
  toPop: Boolean;
begin
  toPop := False;
  if PageCount > 1 then t := (CurPage + 1) mod PageCount
  else
  begin
    t := NextPopup(-1, 1);
    if t >= 0 then toPop := True else t := 0;
  end;
  Result := AddLink(wx, wy, LinkDefaultCaption(toPop, t), toPop, t);
end;

{ point link i at another target, keeping a caption the user typed }
procedure SetLinkTarget(i: Integer; ToPopup: Boolean; T: Integer);
var
  auto: Boolean;
begin
  auto := Links[i].Caption = LinkDefaultCaption(Links[i].ToPopup, Links[i].Target);
  Links[i].ToPopup := ToPopup;
  Links[i].Target := T;
  if auto then Links[i].Caption := LinkDefaultCaption(ToPopup, T);
end;

procedure DrawLinkProps(y: Single);
var
  i, c, t: Integer;
  r, g, b: Byte;
begin
  i := SelLk;
  SetC(Th.Title);
  TextR(QX, y, Format('Link %d', [i + 1]));
  y := y + 16;
  Info(y, 'A button: the Select tool follows it.');
  y := y + 14;
  SetC(Th.OverlayBg);
  FillR(QX, y, 280, 18);
  SetC(Th.MenuBorder);
  RectR(QX, y, 280, 18);
  SetC(Th.Text);
  TextR(QX + 4, y + 5, Copy(Links[i].Caption + TxtCaret(5, i), 1, 34));
  y := y + 24;
  if (TxtEdit = 5) and (TxtIdx = i) then
  begin
    if Button(700, QX, y, 136, 18, 'Done', True) then StopTxt;
  end
  else if Button(700, QX, y, 136, 18, 'Edit caption') then StartTxt(5, i);
  if Button(701, QX + 142, y, 136, 18, 'Follow it now') then
  begin
    AppFollowLink(i);
    Exit;
  end;
  y := y + 26;
  Info(y, 'Goes to');
  y := y + 12;
  if Button(702, QX, y, 136, 18, 'A page', not Links[i].ToPopup) and Links[i].ToPopup then
    SetLinkTarget(i, False, (CurPage + 1) mod PageCount);
  if Button(703, QX + 142, y, 136, 18, 'A frame popup', Links[i].ToPopup) and not Links[i].ToPopup then
  begin
    t := NextPopup(-1, 1);
    if t < 0 then SetStatus('Add a frame popup first (Frame popup panel, F7)', True)
    else SetLinkTarget(i, True, t);
  end;
  y := y + 22;
  if Button(704, QX, y, 24, 18, '<') then
  begin
    if Links[i].ToPopup then
    begin
      t := NextPopup(Links[i].Target, -1);
      if t >= 0 then SetLinkTarget(i, True, t);
    end
    else
      SetLinkTarget(i, False, (Max(0, Links[i].Target) + PageCount - 1) mod PageCount);
  end;
  SetC(Th.OverlayBg);
  FillR(QX + 28, y, 224, 18);
  SetC(Th.Text);
  TextR(QX + 32, y + 5, Copy(LinkTargetName(i), 1, 27));
  if Button(705, QX + 256, y, 24, 18, '>') then
  begin
    if Links[i].ToPopup then
    begin
      t := NextPopup(Links[i].Target, 1);
      if t >= 0 then SetLinkTarget(i, True, t);
    end
    else
      SetLinkTarget(i, False, (Max(-1, Links[i].Target) + 1) mod PageCount);
  end;
  y := y + 26;
  Info(y, 'Colour');
  y := y + 12;
  for c := 0 to 5 do
  begin
    if Button(706 + c, QX + c * 47, y, 44, 18, LabelColorNames[c], Links[i].Color = c) then Links[i].Color := c;
    if c > 0 then
    begin
      LabelRGB(c, r, g, b);
      SetCol(r, g, b);
      FillR(QX + c * 47 + 2, y + 15, 40, 2);
    end;
  end;
  y := y + 26;
  Info(y, 'Layer: ' + Pages[CurPage].Layers[Min(Links[i].Layer, LayerCount - 1)].Name);
  y := y + 16;
  if Button(712, QX, y, 136, 18, 'Delete (Del)') then DeleteSelected;
  Info(y + 26, 'Link tool or Ctrl+click selects a');
  Info(y + 38, 'link; drag it to move it.');
end;

{ ---------------------------------------------------------------- equipment editing }

const
  EqStateNames: array[0..EQS_COUNT - 1] of string = ('auto stopped', 'auto started', 'in fault',
    'manually started', 'manually stopped', 'disabled');
  EqStateButtons: array[0..EQS_COUNT - 1] of string = ('Auto stop', 'Auto start', 'Fault', 'Man. start',
    'Man. stop', 'Disable');
  BranchNames: array[-1..3] of string = ('none', 'E', 'S', 'W', 'N');

{ the equipment a click at wx, wy picks: equipment in front always; a silo bin,
  stand or cyclone only where no part, bucket or label is on top of it }
function EquipPick(wx, wy: Single; gx, gy: Integer; out Part: Integer): Integer;
var
  sx, sy: Integer;
begin
  Result := EquipAt(wx, wy, Part);
  if (Result >= 0) and not EquipFront(Equips[Result].Kind) then
    if (InGrid(gx, gy) and (Grid[gx, gy].Kind <> ckEmpty) and not CellBlocked(gx, gy)) or
      (BucketPick(wx, wy) >= 0) or (LabelAt(wx, wy) >= 0) or StoreAt(wx, wy, sx, sy) then Result := -1;
end;

procedure SetEquipState(i, St: Integer);
begin
  if (i < 0) or not Equips[i].Active then Exit;
  Equips[i].State := St;
  if not EquipRunning(i) then Equips[i].RunTime := 0;
  if (Equips[i].Kind = EQ_FIRE) and EquipRunning(i) then Equips[i].Heat := Equips[i].Level;
  case Equips[i].Kind of
    EQ_SEQUENCE:
      if St = EQS_RUN then SetStatus(Equips[i].Name + ': external request ON')
      else SetStatus(Equips[i].Name + ': external request OFF');
    EQ_RAIN:
      if St = EQS_RUN then SetStatus(Equips[i].Name + ' starts to rain') else SetStatus(Equips[i].Name + ' stops');
    EQ_FIRE:
      if St = EQS_RUN then SetStatus(Equips[i].Name + ' is burning', True) else SetStatus(Equips[i].Name + ' is out');
  else
    SetStatus(Equips[i].Name + ' ' + EqStateNames[St], St = EQS_FAULT);
  end;
end;

{ double-click: auto start <-> auto stop, manual start <-> manual stop; a fault
  is reset to (auto) stop; a disabled piece stays disabled }
procedure ToggleEquip(i: Integer);
begin
  case Equips[i].State of
    EQS_RUN: SetEquipState(i, EQS_STOP);
    EQS_STOP: SetEquipState(i, EQS_RUN);
    EQS_MSTART: SetEquipState(i, EQS_MSTOP);
    EQS_MSTOP: SetEquipState(i, EQS_MSTART);
    EQS_FAULT: SetEquipState(i, EQS_STOP);
  else
    SetStatus(Equips[i].Name + ' is disabled - enable it in Properties', True);
  end;
end;

{ a diverter on a 3-way valve: position 1 / 2 shut the first / second branch }
procedure DiverterDefaults(i: Integer);
var
  d, n: Integer;
  c: PCell;
begin
  c := EquipLinkCell(i);
  if (c = nil) or (c^.Kind <> ckValve3) then Exit;
  n := 0;
  for d := 0 to 3 do
    if (c^.Conn and (1 shl d)) <> 0 then
    begin
      if n = 0 then Equips[i].DivA := d
      else if n = 1 then Equips[i].DivB := d;
      Inc(n);
    end;
end;

{ link equipment i to the part at gx, gy (a hopper / silo also by its drawn body) }
function LinkEquipAt(i: Integer; wx, wy: Single; gx, gy: Integer): Boolean;
var
  sx, sy: Integer;
begin
  Result := False;
  if not (InGrid(gx, gy) and (Grid[gx, gy].Kind <> ckEmpty)) then
  begin
    if not StoreAt(wx, wy, sx, sy) then Exit;
    gx := sx;
    gy := sy;
  end;
  Equips[i].LinkX := gx;
  Equips[i].LinkY := gy;
  if Equips[i].Kind = EQ_DIVERTER then DiverterDefaults(i);
  Result := True;
end;

function EquipLinkText(i: Integer): string;
var
  c: PCell;
begin
  c := EquipLinkCell(i);
  if c = nil then
  begin
    if Equips[i].LinkX >= 0 then Result := 'Linked part is gone'
    else Result := 'Not linked to a part';
  end
  else
    Result := Format('Linked: %s at %d,%d', [KindNames[c^.Kind], Equips[i].LinkX, Equips[i].LinkY]);
end;

procedure DuplicateEquip(i: Integer);
var
  j: Integer;
  nm: string;
begin
  j := AddEquip(Equips[i].Kind, Equips[i].X + CELL, Equips[i].Y + CELL);
  if j < 0 then
  begin
    SetStatus(Format('Too much equipment on this page (max %d)', [MAX_EQUIP]), True);
    Exit;
  end;
  nm := Equips[j].Name;
  Equips[j] := Equips[i];
  Equips[j].X := fclamp(Equips[i].X + CELL, 0, CANVAS_W - Equips[i].W);
  Equips[j].Y := fclamp(Equips[i].Y + CELL, 0, CANVAS_H - Equips[i].H);
  Equips[j].Name := nm;
  Equips[j].RunTime := 0;
  Equips[j].LinkX := -1;
  Equips[j].LinkY := -1;
  SelKind := selEquip;
  SelEq := j;
  SetStatus('Duplicated as ' + nm);
end;

{ the link row: Link: click a part / Unlink }
procedure EquipLinkRow(i: Integer; var y: Single; const Explain: string);
begin
  Info(y, Copy(EquipLinkText(i) + ' - ' + Explain, 1, 35));
  y := y + 12;
  if Button(744, QX, y, 180, 18, 'Link: click a part', EqPick = i) then
  begin
    if EqPick = i then EqPick := -1
    else
    begin
      EqPick := i;
      SetStatus('Click the part to link ' + Equips[i].Name + ' to (Esc cancels)');
    end;
  end;
  if Button(745, QX + 184, y, 96, 18, 'Unlink') then
  begin
    Equips[i].LinkX := -1;
    Equips[i].LinkY := -1;
  end;
  y := y + 22;
end;

procedure DrawSequenceProps(i: Integer; y: Single);
const
  ModeNames: array[0..2] of string = ('Auto', 'Manual', 'E-Stop');
var
  m, j, n: Integer;
  E: ^TEquipObj;
  steps: array[0..MAX_SEQ_STEP - 1] of Byte;
  s: string;
begin
  E := @Equips[i];
  Info(y, 'Mode');
  y := y + 12;
  for m := 0 to 2 do
    if Button(760 + m, QX + m * 94, y, 90, 18, ModeNames[m], E^.Mode = m) then
    begin
      E^.Mode := m;
      SetStatus('Sequence mode: ' + ModeNames[m], m = SEQ_ESTOP);
    end;
  y := y + 24;
  Info(y, 'External request');
  y := y + 12;
  if Button(763, QX, y, 136, 18, 'Request ON', E^.State = EQS_RUN) then SetEquipState(i, EQS_RUN);
  if Button(764, QX + 142, y, 138, 18, 'Request OFF', E^.State <> EQS_RUN) then SetEquipState(i, EQS_STOP);
  y := y + 24;
  EquipLinkRow(i, y, 'on while it flows');
  { the steps, in order }
  n := SeqStepList(steps);
  Info(y, Format('Steps (%d):', [n]));
  y := y + 12;
  for m := 0 to Min(n, 5) - 1 do
  begin
    s := '';
    for j := 0 to MAX_EQUIP - 1 do
      if Equips[j].Active and EquipActuated(Equips[j].Kind) and (Equips[j].SeqStep = steps[m]) then
      begin
        if s <> '' then s := s + ', ';
        s := s + Equips[j].Name;
      end;
    Info(y, Copy(Format('%d  after %.1fs: %s', [steps[m], StepDelay(steps[m]), s]), 1, 35));
    y := y + 11;
  end;
  if n = 0 then
  begin
    Info(y, 'Select a motor / valve / heater');
    Info(y + 11, 'and give it a sequence step.');
  end;
end;

const
  TimerShort: array[0..3] of string = ('On-del.', 'Off-del.', 'Pulse', 'Flasher');
  CtrlShort: array[0..3] of string = ('On<SP', 'On>SP', 'PID', 'PID rev');

{ the next thing a sensor (or float / motor ...) reads or works with, in direction Dir }
function NextRefFor(const c: TECell; Dir: Integer): string;
var
  be: TBusEq;
  names: array of string;
  n, i, k: Integer;
  ok: Boolean;

  procedure Add(const s: string);
  begin
    SetLength(names, n + 1);
    names[n] := s;
    Inc(n);
  end;

begin
  n := 0;
  if c.Kind = ekPressTx then
  begin
    { the pipe under it, or a pneumatic / hydraulic part by its tag }
    Add('');
    if Assigned(ExtSourceName) then
    begin
      i := 0;
      while ExtSourceName(i) <> '' do
      begin
        Add(ExtSourceName(i));
        Inc(i);
      end;
    end;
  end
  else
    for i := 0 to MAX_EQUIP - 1 do
    begin
      if not Equips[i].Active then Continue;
      case c.Kind of
        ekFloat, ekLevelTx: ok := EquipIsWater(Equips[i].Kind) or (Equips[i].Kind = EQ_SILO);
        ekTempTx: ok := Equips[i].Kind in [EQ_HEATER, EQ_IRHEATER, EQ_FIRE, EQ_HEATEX, EQ_COOLTOWER, EQ_CHILLER];
      else
        ok := EquipActuated(Equips[i].Kind);
      end;
      if ok then Add(Equips[i].Name);
    end;
  { equipment on the other pages }
  if c.Kind <> ekPressTx then
  begin
    i := 0;
    while BusEqIndex(i, be) do
    begin
      case c.Kind of
        ekFloat, ekLevelTx: ok := EquipIsWater(be.Kind) or (be.Kind = EQ_SILO);
        ekTempTx: ok := be.Kind in [EQ_HEATER, EQ_IRHEATER, EQ_FIRE, EQ_HEATEX, EQ_COOLTOWER, EQ_CHILLER];
      else
        ok := EquipActuated(be.Kind);
      end;
      if ok then Add(be.Name);
      Inc(i);
    end;
  end;
  Result := c.Ref;
  if n = 0 then Exit;
  k := -1;
  for i := 0 to n - 1 do
    if SameText(names[i], c.Ref) then k := i;
  if k < 0 then
  begin
    if Dir > 0 then k := 0 else k := n - 1;
  end
  else
    k := (k + Dir + n) mod n;
  Result := names[k];
end;

{ the next tag that can reset a counter ('' = by hand only): buttons, switches, coils, timers, photo sensors }
function NextSignalTag(const Cur, Own: string): string;
var
  names: array of string;
  n, x, y, i, k: Integer;
  dup: Boolean;
begin
  n := 1;
  SetLength(names, 1);
  names[0] := '';
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (EGrid[x, y].Kind in [ekPBNO, ekPBNC, ekPBLatch, ekSwitch, ekSelector, ekRelay, ekContactor, ekTimer, ekPhoto,
        ekCounter]) and (EGrid[x, y].Tag <> '') and not SameText(EGrid[x, y].Tag, Own) then
      begin
        dup := False;
        for i := 0 to n - 1 do
          if SameText(names[i], EGrid[x, y].Tag) then dup := True;
        if dup then Continue;
        SetLength(names, n + 1);
        names[n] := EGrid[x, y].Tag;
        Inc(n);
      end;
  k := 0;
  for i := 0 to n - 1 do
    if SameText(names[i], Cur) then k := i;
  Result := names[(k + 1) mod n];
end;

{ the next input for a controller: any analog value but its own }
function NextCtrlInput(const c: TECell; Dir: Integer): string;
var
  i: Integer;
  s: string;
begin
  s := c.Src;
  for i := 1 to 60 do
  begin
    s := NextAnalogSource(s, Dir);
    if (s = '') or SameText(s, c.Src) then Exit(c.Src);
    if not (SameText(s, c.Tag) or SameText(Copy(s, 1, Length(c.Tag) + 1), c.Tag + '.')) then Exit(s);
  end;
  Result := c.Src;
end;

{ the range of a controller's set point, from the unit of its input }
function CtrlRange(const c: TECell; out u: string): Single;
var
  v: Single;
begin
  u := '';
  v := 0;
  if c.Src <> '' then AnalogValue(c.Src, v, u);
  if u = 'C' then Result := 300
  else if u = 'bar' then
  begin
    if fmax(Abs(v), c.P1) > 15 then Result := 250 else Result := 10;
  end
  else if u = 'kPa' then Result := 150
  else if u = 'm/s' then Result := 20
  else if u = 'rpm' then Result := 1500
  else if u = 'kg' then Result := 100
  else if u = 'A' then Result := 50
  else if u = 'V' then Result := 250
  else if u = 'pcs' then Result := 999
  else Result := 100;
end;

{ decimals to show for a range }
function Decs(rg: Single): Integer;
begin
  if rg <= 20 then Result := 2 else if rg <= 300 then Result := 1 else Result := 0;
end;

procedure DrawEquipProps(y: Single);
var
  l1, l2, l3: string;
  ex, ey: Integer;
  rg: Single;
  i, s: Integer;
  E: ^TEquipObj;
  v: Single;
  s0: string;
  r, g, b: Byte;
  c: PCell;
begin
  i := SelEq;
  E := @Equips[i];
  SetC(Th.Title);
  TextR(QX, y, EquipNames[E^.Kind] + Format('  (equipment %d)', [i + 1]));
  y := y + 14;
  SetC(Th.OverlayBg);
  FillR(QX, y, 196, 18);
  SetC(Th.MenuBorder);
  RectR(QX, y, 196, 18);
  SetC(Th.Text);
  TextR(QX + 4, y + 5, Copy(E^.Name + TxtCaret(6, i), 1, 24));
  if (TxtEdit = 6) and (TxtIdx = i) then
  begin
    if Button(740, QX + 200, y, 80, 18, 'Done', True) then StopTxt;
  end
  else if Button(740, QX + 200, y, 80, 18, 'Name') then StartTxt(6, i);
  y := y + 24;
  if E^.Kind = EQ_SEQUENCE then
  begin
    DrawSequenceProps(i, y);
    Exit;
  end;
  if EquipActuated(E^.Kind) or (E^.Kind = EQ_LAMP) then
  begin
    { the six states, two rows }
    for s := 0 to EQS_COUNT - 1 do
    begin
      if Button(770 + s, QX + (s mod 3) * 94, y + (s div 3) * 22, 90, 18, EqStateButtons[s], E^.State = s) then
        SetEquipState(i, s);
      EqStateRGB(s, r, g, b);
      SetCol(r, g, b);
      FillR(QX + (s mod 3) * 94 + 2, y + (s div 3) * 22 + 15, 86, 2);
    end;
    y := y + 46;
  end
  else if E^.Kind in [EQ_RAIN, EQ_FIRE] then
  begin
    if E^.Kind = EQ_RAIN then
    begin
      if Button(770, QX, y, 136, 18, 'Rain', EquipRunning(i)) then SetEquipState(i, EQS_RUN);
      if Button(771, QX + 142, y, 138, 18, 'Dry', not EquipRunning(i)) then SetEquipState(i, EQS_STOP);
    end
    else
    begin
      if Button(770, QX, y, 136, 18, 'Ignite', EquipRunning(i)) then SetEquipState(i, EQS_RUN);
      if Button(771, QX + 142, y, 138, 18, 'Put out', not EquipRunning(i)) then SetEquipState(i, EQS_STOP);
    end;
    y := y + 22;
    v := E^.Level;
    if E^.Kind = EQ_RAIN then ParamRow(746, y, 'Rain %', v, 0, 100, 5) else ParamRow(746, y, 'Size %', v, 5, 100, 5);
    E^.Level := v;
    y := y + 20;
    if E^.Kind = EQ_RAIN then Info(y, 'Real water drops: they fill buckets.')
    else Info(y, 'Burns fluff/oil; water puts it out.');
    y := y + 14;
  end;
  if EquipActuated(E^.Kind) then
  begin
    { its place in the start sequence }
    v := E^.SeqStep;
    ParamRow(780, y, 'Seq.st', v, 0, MAX_SEQ_STEP, 1);
    E^.SeqStep := Round(v);
    v := E^.Delay;
    ParamRow(783, y + 20, 'Delay s', v, 0, 60, 1);
    E^.Delay := Round(v);
    y := y + 42;
  end;
  case E^.Kind of
    EQ_MOTOR, EQ_BLOWER, EQ_PADDLE, EQ_SCREW: EquipLinkRow(i, y, 'stop halts it');
    EQ_SHUTTER, EQ_SLIDE: EquipLinkRow(i, y, 'opens / shuts it');
    EQ_DIVERTER:
      begin
        EquipLinkRow(i, y, 'sets its way');
        c := EquipLinkCell(i);
        if (c <> nil) and (c^.Kind = ckValve3) then
        begin
          if Button(786, QX, y, 136, 18, 'Pos 1 shuts: ' + BranchNames[E^.DivA]) then
            E^.DivA := (E^.DivA + 2) mod 5 - 1;
          if Button(787, QX + 142, y, 138, 18, 'Pos 2 shuts: ' + BranchNames[E^.DivB]) then
            E^.DivB := (E^.DivB + 2) mod 5 - 1;
          y := y + 22;
        end;
      end;
    EQ_HEATER: EquipLinkRow(i, y, 'heats that pipe');
    EQ_HEATEX: EquipLinkRow(i, y, 'its shell stream');
    EQ_PUMP:
      begin
        EquipLinkRow(i, y, 'pumps into it');
        s := PumpSource(i);
        if s < 0 then Info(y, 'Source: none - put it near water')
        else Info(y, Format('Source: %s, water %.0f%%', [Equips[s].Name, Equips[s].Level]));
        y := y + 14;
      end;
    EQ_SILO: EquipLinkRow(i, y, 'shows its level');
    EQ_LAMP: EquipLinkRow(i, y, 'lit while it flows');
  end;
  if (E^.Kind in [EQ_SILO, EQ_HEATER, EQ_IRHEATER, EQ_PUMP, EQ_POND, EQ_POOL, EQ_WELL, EQ_CONVEYOR, EQ_BELT, EQ_HEATEX, EQ_COOLTOWER, EQ_CHILLER]) and
    not ((E^.Kind = EQ_SILO) and (EquipLinkCell(i) <> nil)) then
  begin
    v := E^.Level;
    case E^.Kind of
      EQ_SILO: ParamRow(746, y, 'Level', v, 0, 100, 5);
      EQ_PUMP: ParamRow(746, y, 'Flow %', v, 0, 100, 5);
      EQ_CONVEYOR, EQ_BELT: ParamRow(746, y, 'Speed %', v, 0, 100, 5);
      EQ_HEATEX: ParamRow(746, y, 'Tube flow', v, 0, 100, 5);
      EQ_COOLTOWER: ParamRow(746, y, 'Fan %', v, 0, 100, 5);
      EQ_CHILLER: ParamRow(746, y, 'Capacity', v, 0, 100, 5);
      EQ_POND, EQ_POOL, EQ_WELL: ParamRow(746, y, 'Water', v, 0, 100, 5);
    else
      ParamRow(746, y, 'Power', v, 0, 100, 5);
    end;
    E^.Level := v;
    y := y + 20;
  end;
  if E^.Kind in [EQ_HEATEX, EQ_COOLTOWER, EQ_CHILLER] then
  begin
    case E^.Kind of
      EQ_HEATEX: begin l1 := 'Tube in C'; l2 := 'Shell in C'; l3 := 'Tube from'; end;
      EQ_COOLTOWER: begin l1 := 'Water in C'; l2 := 'Wet bulb C'; l3 := 'Water from'; end;
    else
      begin l1 := 'Set point C'; l2 := 'Return C'; l3 := 'Return from'; end;
    end;
    v := E^.RMax;
    if E^.Kind = EQ_CHILLER then ParamRowD(794, y, l1, v, 0, 25, 0.5, 1) else ParamRowD(794, y, l1, v, 0, 300, 1, 0);
    E^.RMax := v;
    v := E^.RMin;
    ParamRowD(799, y + 20, l2, v, 0, 200, 1, 0);
    E^.RMin := v;
    y := y + 40;
    Info(y + 4, l3);
    if Button(797, QX + 88, y, 24, 18, '<') or Button(798, QX + 256, y, 24, 18, '>') then
      E^.Src := NextHotSource(E^.Src, i);
    SetC(Th.OverlayBg);
    FillR(QX + 116, y, 136, 18);
    SetC(Th.Text);
    if E^.Src = '' then TextR(QX + 120, y + 5, '(the setting)') else TextR(QX + 120, y + 5, Copy(E^.Src, 1, 16));
    y := y + 22;
    case E^.Kind of
      EQ_HEATEX:
        begin
          Info(y, Format('Shell %.0f -> %.0f C (the pipe)', [E^.ColdIn, E^.Temp]));
          Info(y + 11, Format('Tube  %.0f -> %.0f C, %.0f kW', [E^.HotIn, E^.HotOut, E^.Duty]));
        end;
      EQ_COOLTOWER:
        begin
          Info(y, Format('Water %.1f -> %.1f C, %.0f kW', [E^.HotIn, E^.Temp, E^.Duty]));
          Info(y + 11, Format('Approach to the wet bulb %.1f C', [E^.Temp - E^.ColdIn]));
        end;
    else
      begin
        Info(y, Format('Chilled water %.1f -> %.1f C', [E^.HotIn, E^.Temp]));
        Info(y + 11, Format('%.0f kW cooling, %.0f kW power', [E^.Duty, E^.Duty / 4]));
      end;
    end;
    y := y + 26;
  end;
  if E^.Kind = EQ_CONTROLLER then
  begin
    Info(y + 4, 'Shows');
    if Button(790, QX + 56, y, 24, 18, '<') or Button(791, QX + 256, y, 24, 18, '>') then
      E^.Src := NextCtrlTag(E^.Src);
    SetC(Th.OverlayBg);
    FillR(QX + 84, y, 168, 18);
    SetC(Th.Text);
    if E^.Src = '' then TextR(QX + 88, y + 5, '(pick a controller)') else TextR(QX + 88, y + 5, Copy(E^.Src, 1, 20));
    y := y + 22;
    if ECellByTag(E^.Src, ekController, ex, ey) then
    begin
      { its set point can be changed here, like on a real faceplate }
      rg := CtrlRange(EGrid[ex, ey], s0);
      v := EGrid[ex, ey].P1;
      ParamRowD(792, y, 'Set point', v, 0, rg, rg / 100, Decs(rg));
      EGrid[ex, ey].P1 := v;
      y := y + 20;
      Info(y, Format('PV %.2f %s   OUT %.0f%%', [EGrid[ex, ey].Val, s0, EGrid[ex, ey].Out]));
      y := y + 14;
    end
    else
    begin
      Info(y, 'Pick a controller (Control tab).');
      y := y + 14;
    end;
  end;
  if E^.Kind in [EQ_GAUGE, EQ_DIGITAL, EQ_COMPRESSOR, EQ_HPU, EQ_RECEIVER] then
  begin
    Info(y + 4, 'Shows');
    if Button(790, QX + 56, y, 24, 18, '<') then E^.Src := NextAnalogSource(E^.Src, -1);
    SetC(Th.OverlayBg);
    FillR(QX + 84, y, 168, 18);
    SetC(Th.Text);
    if E^.Src = '' then TextR(QX + 88, y + 5, '(pick a source)') else TextR(QX + 88, y + 5, Copy(E^.Src, 1, 20));
    if Button(791, QX + 256, y, 24, 18, '>') then E^.Src := NextAnalogSource(E^.Src, 1);
    y := y + 22;
    if AnalogValue(E^.Src, v, s0) then Info(y, Format('Now %.2f %s', [v, s0])) else Info(y, 'Nothing by that name');
    y := y + 14;
    v := E^.RMin;
    ParamRow(792, y, 'Min', v, -1000, 1000, 1);
    E^.RMin := Round(v);
    v := E^.RMax;
    ParamRow(795, y + 20, 'Max', v, -1000, 1000, 5);
    E^.RMax := Round(v);
    y := y + 42;
  end;
  v := E^.W;
  ParamRow(750, y, 'Width', v, 12, CANVAS_W, 8);
  E^.W := Round(v);
  v := E^.H;
  ParamRow(753, y + 20, 'Height', v, 12, CANVAS_H, 8);
  E^.H := Round(v);
  y := y + 42;
  if E^.Kind in [EQ_MOTOR, EQ_BLOWER, EQ_PADDLE, EQ_SCREW, EQ_PUMP, EQ_CONVEYOR, EQ_BELT, EQ_CYLINDER] then
    if Button(756, QX, y, 90, 18, 'Flip (R)', E^.Flip) then E^.Flip := not E^.Flip;
  if Button(757, QX + 94, y, 90, 18, 'Duplicate') then
  begin
    DuplicateEquip(i);
    Exit;
  end;
  if Button(758, QX + 188, y, 92, 18, 'Delete') then DeleteSelected;
end;

{ ---------------------------------------------------------------- electrical editing }

var
  LastCoilTag: string = '';   { the tag a new NO / NC contact gets: the last coil placed }

{ the next free tag with this prefix: K1, K2 ... }
function NextETag(const Prefix: string): string;
var
  n, x, y: Integer;
  used: Boolean;
begin
  n := 1;
  repeat
    Result := Prefix + IntToStr(n);
    used := False;
    for y := 0 to GH - 1 do
      for x := 0 to GW - 1 do
        if (EGrid[x, y].Kind <> ekNone) and SameText(EGrid[x, y].Tag, Result) then used := True;
    Inc(n);
  until not used;
end;

{ a device put down with a tool gets a tag of its own }
procedure DefaultETag(x, y: Integer);
var
  c: PECell;
  p: string;
begin
  c := @EGrid[x, y];
  case c^.Kind of
    ekRelay: p := 'K';
    ekContactor: p := 'KM';
    ekTimer: p := 'T';
    ekLamp: p := 'H';
    ekBuzzer: p := 'HA';
    ekFuse: p := 'F';
    ekBreaker: p := 'Q';
    ekOL: p := 'OL';
    ekSwitch, ekSw2, ekSw3: p := 'S';
    ekPBNO, ekPBNC, ekPBLatch: p := 'SB';
    ekSelector: p := 'SA';
    ekEStop: p := 'ES';
    ekMotor: p := 'M';
    ekDrive: p := 'U';
    ekFloat: p := 'LS';
    ekSolenoid: p := 'Y';
    ekCT: p := 'CT';
    ekPot: p := 'RV';
    ekCounter: p := 'CNT';
    ekLevelTx: p := 'LT';
    ekPressTx: p := 'PT';
    ekFlowTx: p := 'FT';
    ekTempTx: p := 'TT';
    ekSpeedTx: p := 'ST';
    ekWeightTx: p := 'WT';
    ekPhoto: p := 'PE';
    ekController: p := 'IC';
    ekHumidTx: p := 'MT';
    ekPHTx: p := 'PH';
    ekAC: begin c^.Tag := '230VAC'; Exit; end;
    ekDC: begin c^.Tag := '24VDC'; Exit; end;
    ekNO, ekNC: begin c^.Tag := LastCoilTag; Exit; end;
  else
    Exit;
  end;
  c^.Tag := NextETag(p);
  if c^.Kind in [ekRelay, ekContactor, ekTimer, ekCounter, ekController] then LastCoilTag := c^.Tag;
end;

{ the next equipment name for a motor / drive / overload / float, in direction Dir }
function NextEquipName(const Cur: string; Dir: Integer; ForLevel: Boolean): string;
var
  i, j, start: Integer;
  ok: Boolean;
begin
  Result := Cur;
  start := EquipByName(Cur);
  if start < 0 then start := -1;
  j := start;
  for i := 1 to MAX_EQUIP do
  begin
    j := (j + Dir + MAX_EQUIP) mod MAX_EQUIP;
    if not Equips[j].Active then Continue;
    if ForLevel then ok := EquipIsWater(Equips[j].Kind) or (Equips[j].Kind = EQ_SILO)
    else ok := EquipActuated(Equips[j].Kind);
    if ok then Exit(Equips[j].Name);
  end;
end;

procedure SelectECell(gx, gy: Integer);
begin
  SelKind := selECell;
  SelEX := gx;
  SelEY := gy;
end;

{ the next potentiometer tag after Cur ('' = none, then each pot in turn) }
function NextPotTag(const Cur: string): string;
var
  x, y: Integer;
  seen: Boolean;
begin
  Result := '';
  seen := Cur = '';
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (EGrid[x, y].Kind in [ekPot, ekController]) and (EGrid[x, y].Tag <> '') then
      begin
        if seen then Exit(EGrid[x, y].Tag);
        if SameText(EGrid[x, y].Tag, Cur) then seen := True;
      end;
end;

procedure DrawECellProps(y: Single);
var
  rg: Single;
  u: string;
  c: PECell;
  k: Integer;
  v: Single;
  s: string;
  r, g, b: Byte;
const
  LampSw: array[0..4, 0..2] of Byte = ((60, 210, 90), (235, 60, 50), (245, 205, 40), (240, 240, 245), (70, 140, 245));
begin
  c := @EGrid[SelEX, SelEY];
  SetC(Th.Title);
  TextR(QX, y, Format('%s  [%d,%d]', [EKindNames[c^.Kind], SelEX, SelEY]));
  y := y + 14;
  if not (c^.Kind in [ekWire, ekCross]) then
  begin
    SetC(Th.OverlayBg);
    FillR(QX, y, 196, 18);
    SetC(Th.MenuBorder);
    RectR(QX, y, 196, 18);
    SetC(Th.Text);
    TextR(QX + 4, y + 5, 'Tag: ' + c^.Tag + TxtCaret(7, SelEY * GW + SelEX));
    if (TxtEdit = 7) and (TxtIdx = SelEY * GW + SelEX) then
    begin
      if Button(800, QX + 200, y, 80, 18, 'Done', True) then StopTxt;
    end
    else if Button(800, QX + 200, y, 80, 18, 'Tag') then StartTxt(7, SelEY * GW + SelEX);
    y := y + 24;
  end;
  if c^.Tripped then SetC(Th.StatusErr) else if c^.Energized then SetCol(60, 205, 95) else SetC(Th.TextDim);
  TextR(QX, y, Copy('State: ' + EStateText(SelEX, SelEY), 1, 35));
  y := y + 16;
  case c^.Kind of
    ekNO, ekNC:
      begin
        Info(y, 'Follows the coil / contactor / timer /');
        Info(y + 11, 'overload with the same tag.');
        y := y + 28;
      end;
    ekAC, ekDC, ekBreaker, ekSwitch, ekPBLatch:
      begin
        if Button(801, QX, y, 90, 18, 'ON', c^.On and not c^.Tripped) then
        begin
          c^.On := True;
          c^.Tripped := False;
        end;
        if Button(802, QX + 94, y, 90, 18, 'OFF', not c^.On) then c^.On := False;
        if (c^.Kind in [ekAC, ekDC, ekBreaker]) and Button(803, QX + 188, y, 92, 18, 'Reset', c^.Tripped) then
          c^.Tripped := False;
        y := y + 24;
      end;
    ekFuse:
      begin
        if Button(803, QX, y, 136, 18, 'Replace fuse', c^.Tripped) then c^.Tripped := False;
        y := y + 24;
      end;
    ekPBNO, ekPBNC:
      begin
        Info(y, 'Select tool: hold the mouse button');
        Info(y + 11, 'on it to press it.');
        y := y + 28;
      end;
    ekSw2, ekSw3:
      begin
        for k := 0 to 1 do
          if Button(804 + k, QX + k * 94, y, 90, 18, Format('Position %d', [k + 1]), c^.Sel = k) then c^.Sel := k;
        y := y + 24;
      end;
    ekSelector:
      begin
        Info(y, 'Positions');
        for k := 2 to 3 do
          if Button(806 + k, QX + 80 + (k - 2) * 50, y - 4, 44, 16, IntToStr(k), c^.NPos = k) then
          begin
            c^.NPos := k;
            if c^.Pos > k then c^.Pos := k;
          end;
        y := y + 16;
        Info(y + 4, 'Closes in');
        for k := 1 to Max(2, c^.NPos) do
          if Button(810 + k, QX + 80 + (k - 1) * 50, y, 44, 16, IntToStr(k), c^.Pos = k) then c^.Pos := k;
        y := y + 20;
        Info(y + 4, 'Now in');
        for k := 0 to Max(2, c^.NPos) - 1 do
          if Button(814 + k, QX + 80 + k * 50, y, 44, 16, IntToStr(k + 1), c^.Sel = k) then
            ESetSelectorPos(SelEX, SelEY, k);
        y := y + 24;
      end;
    ekEStop:
      begin
        if Button(818, QX, y, 136, 18, 'Press', c^.On) then c^.On := True;
        if Button(819, QX + 142, y, 138, 18, 'Release', not c^.On) then c^.On := False;
        y := y + 24;
      end;
    ekTimer:
      begin
        for k := 0 to 3 do
          if Button(860 + k, QX + k * 70, y, 66, 18, TimerShort[k], (c^.Pos and 3) = k) then c^.Pos := k;
        y := y + 22;
        v := c^.P1;
        if (c^.Pos and 3) = 3 then ParamRowD(820, y, 'On s', v, 0.1, 60, 0.1, 1)
        else ParamRowD(820, y, 'Time s', v, 0, 300, 0.5, 1);
        c^.P1 := v;
        y := y + 20;
        if (c^.Pos and 3) = 3 then
        begin
          v := c^.P2;
          ParamRowD(864, y, 'Off s', v, 0.1, 60, 0.1, 1);
          c^.P2 := v;
          y := y + 20;
        end;
        case c^.Pos and 3 of
          1:
            begin
              Info(y, 'Contacts close with power and open');
              Info(y + 11, 'the time after the power goes.');
            end;
          2:
            begin
              Info(y, 'Power on gives one pulse of the');
              Info(y + 11, 'time, however long power stays.');
            end;
          3:
            begin
              Info(y, 'Contacts blink while it has power:');
              Info(y + 11, 'on s closed, then off s open.');
            end;
        else
          begin
            Info(y, 'Contacts close the time after the');
            Info(y + 11, 'power comes; open without power.');
          end;
        end;
        y := y + 28;
      end;
    ekCounter:
      begin
        v := c^.P1;
        ParamRowD(870, y, 'Preset', v, 1, 999, 1, 0);
        c^.P1 := Round(v);
        y := y + 20;
        Info(y + 4, 'Reset by');
        if Button(874, QX + 80, y, 24, 18, '<') or Button(875, QX + 256, y, 24, 18, '>') then
          c^.Src := NextSignalTag(c^.Src, c^.Tag);
        SetC(Th.OverlayBg);
        FillR(QX + 108, y, 144, 18);
        SetC(Th.Text);
        if c^.Src = '' then TextR(QX + 112, y + 5, '(by hand only)') else TextR(QX + 112, y + 5, c^.Src);
        y := y + 22;
        if Button(873, QX, y, 136, 18, 'Reset to 0') then c^.Acc := 0;
        y := y + 22;
        Info(y, 'Each pulse on its coil counts one;');
        Info(y + 11, 'its contacts close at the preset.');
        y := y + 28;
      end;
    ekFlowTx:
      begin
        Info(y, 'Put it on a pipe: it reads the air');
        Info(y + 11, 'speed there (cells per second).');
        y := y + 28;
      end;
    ekWeightTx:
      begin
        Info(y, 'Put it under or over a bucket: it');
        Info(y + 11, 'weighs what lies in the bucket.');
        y := y + 28;
      end;
    ekPhoto:
      begin
        Info(y, 'Closes while material passes its');
        Info(y + 11, Format('cell (%.0f particles now).', [c^.Val]));
        y := y + 28;
      end;
    ekPHTx:
      begin
        Info(y, 'The pH of what is in the store or');
        Info(y + 11, 'pipe here, or in the bucket: each');
        Info(y + 22, 'material''s pH (Physics lab, F8)');
        Info(y + 33, 'mixed by mass. Empty: 7.');
        y := y + 50;
      end;
    ekHumidTx:
      begin
        for k := 0 to 1 do
          if Button(890 + k, QX + k * 142, y, 136 + 2 * k, 18, HumidModeNames[k], c^.Pos = k) then c^.Pos := k;
        y := y + 22;
        if c^.Pos = 0 then
        begin
          Info(y, 'Air: wetter with water and steam');
          Info(y + 11, 'near it, drier near hot equipment.');
        end
        else
        begin
          Info(y, 'Water share of the material in the');
          Info(y + 11, 'store or pipe here, or the bucket.');
        end;
        y := y + 28;
      end;
    ekController:
      begin
        for k := 0 to 3 do
          if Button(876 + k, QX + k * 70, y, 66, 18, CtrlShort[k], (c^.Pos and 3) = k) then c^.Pos := k;
        y := y + 22;
        Info(y + 4, 'Input');
        if Button(880, QX + 56, y, 24, 18, '<') then c^.Src := NextCtrlInput(c^, -1);
        SetC(Th.OverlayBg);
        FillR(QX + 84, y, 168, 18);
        SetC(Th.Text);
        if c^.Src = '' then TextR(QX + 88, y + 5, '(pick a sensor)') else TextR(QX + 88, y + 5, Copy(c^.Src, 1, 20));
        if Button(881, QX + 256, y, 24, 18, '>') then c^.Src := NextCtrlInput(c^, 1);
        y := y + 22;
        rg := CtrlRange(c^, u);
        v := c^.P1;
        ParamRowD(882, y, 'Set point', v, 0, rg, rg / 100, Decs(rg));
        c^.P1 := v;
        v := c^.P2;
        if (c^.Pos and 3) >= 2 then ParamRowD(885, y + 20, 'Band', v, rg / 1000, rg, rg / 100, Decs(rg))
        else ParamRowD(885, y + 20, 'Hysteresis', v, 0, rg / 2, rg / 200, Decs(rg));
        c^.P2 := v;
        y := y + 40;
        if (c^.Pos and 3) >= 2 then
        begin
          v := c^.P3;
          ParamRowD(888, y, 'Integral s', v, 0, 120, 1, 0);
          c^.P3 := v;
          y := y + 20;
        end;
        { the actual value, the set point and the output }
        SetCol(245, 70, 60);
        TextR(QX, y, Format('PV %.2f %s', [c^.Val, u]));
        SetCol(70, 205, 105);
        TextR(QX + 150, y, Format('SP %.2f', [c^.P1]));
        y := y + 12;
        SetC(Th.SliderTrack);
        FillR(QX, y, 280, 8);
        SetCol(245, 170, 40);
        FillR(QX, y, 280 * fclamp(c^.Out / 100, 0, 1), 8);
        Info(y + 12, Format('Output %.0f%% - a drive can follow it', [c^.Out]));
        y := y + 28;
      end;

    ekPot:
      begin
        v := c^.P1;
        ParamRow(856, y, 'Turn %', v, 0, 100, 5);
        c^.P1 := Round(v);
        y := y + 22;
        Info(y, 'Or the mouse wheel over it.');
        y := y + 14;
      end;
    ekCT:
      begin
        Info(y, 'Measures the current of the loads');
        Info(y + 11, 'it feeds. A gauge can show it.');
        y := y + 28;
      end;
    ekLamp:
      begin
        for k := 0 to 4 do
        begin
          if Button(823 + k, QX + k * 57, y, 54, 18, LampColorNames[k], c^.Pos = k) then c^.Pos := k;
          r := LampSw[k, 0];
          g := LampSw[k, 1];
          b := LampSw[k, 2];
          SetCol(r, g, b);
          FillR(QX + k * 57 + 2, y + 15, 50, 2);
        end;
        y := y + 24;
      end;
  end;
  if EHasRef(c^.Kind) then
  begin
    if c^.Kind in [ekFloat, ekLevelTx] then s := 'Level of'
    else if c^.Kind in SensorKinds then s := 'Reads'
    else s := 'Equipment';
    Info(y + 4, s);
    if Button(828, QX + 80, y, 24, 18, '<') then c^.Ref := NextRefFor(c^, -1);
    SetC(Th.OverlayBg);
    FillR(QX + 108, y, 144, 18);
    SetC(Th.Text);
    if c^.Ref <> '' then TextR(QX + 112, y + 5, Copy(c^.Ref, 1, 17))
    else if c^.Kind = ekPressTx then TextR(QX + 112, y + 5, '(the pipe here)')
    else TextR(QX + 112, y + 5, '(none)');
    if Button(829, QX + 256, y, 24, 18, '>') then c^.Ref := NextRefFor(c^, 1);
    y := y + 24;
    case c^.Kind of
      ekOL:
        begin
          if Button(830, QX, y, 136, 18, 'Reset', c^.Tripped) then c^.Tripped := False;
          if Button(831, QX + 142, y, 138, 18, 'Trip (test)') then c^.Tripped := True;
          y := y + 22;
          v := c^.P1;
          ParamRow(853, y, 'Trip A', v, 0, 100, 1);
          c^.P1 := Round(v);
          y := y + 22;
        end;
      ekFloat:
        begin
          if Button(832, QX, y, 136, 18, 'Fill: on when low', c^.Pos = 0) then c^.Pos := 0;
          if Button(833, QX + 142, y, 138, 18, 'Empty: on when high', c^.Pos = 1) then c^.Pos := 1;
          y := y + 22;
          v := c^.P1;
          ParamRow(834, y, 'Low %', v, 0, 100, 5);
          c^.P1 := Round(v);
          v := c^.P2;
          ParamRow(837, y + 20, 'High %', v, 0, 100, 5);
          c^.P2 := Round(v);
          y := y + 42;
        end;
      ekDrive:
        begin
          Info(y + 4, 'Speed from');
          if Button(846, QX + 88, y, 24, 18, '<') or Button(847, QX + 256, y, 24, 18, '>') then
            c^.Src := NextPotTag(c^.Src);
          SetC(Th.OverlayBg);
          FillR(QX + 116, y, 136, 18);
          SetC(Th.Text);
          if c^.Src = '' then TextR(QX + 120, y + 5, '(its own %)') else TextR(QX + 120, y + 5, 'from ' + c^.Src);
          y := y + 22;
          if c^.Src = '' then
          begin
            v := c^.P1;
            ParamRow(840, y, 'Speed %', v, 0, 100, 5);
            c^.P1 := Round(v);
            y := y + 22;
          end;
        end;
      ekMotor:
        begin
          v := c^.P1;
          ParamRow(848, y, 'Rated A', v, 0, 100, 1);
          c^.P1 := Round(v);
          y := y + 22;
          if Button(851, QX, y, 136, 18, 'Delta / direct', c^.Pos = 0) then c^.Pos := 0;
          if Button(852, QX + 142, y, 138, 18, 'Star (1/3 current)', c^.Pos = 1) then c^.Pos := 1;
          y := y + 22;
        end;
    end;
  end;
  if not (c^.Kind in [ekWire, ekCross, ekTerminal]) then
    if Button(843, QX, y, 136, 18, 'Rotate (R)') then ERotate(SelEX, SelEY);
  if Button(844, QX + 142, y, 138, 18, 'Delete (Del)') then DeleteSelected;
end;

{ the Wire tool dragged to gx, gy: wire cell by cell from the last one }
procedure EWireTo(gx, gy: Integer);
var
  nx, ny: Integer;
begin
  gx := EnsureRange(gx, 0, GW - 1);
  gy := EnsureRange(gy, 0, GH - 1);
  while (LastCX <> gx) or (LastCY <> gy) do
  begin
    nx := LastCX;
    ny := LastCY;
    if Abs(gx - LastCX) >= Abs(gy - LastCY) then nx := nx + Sign(gx - LastCX)
    else ny := ny + Sign(gy - LastCY);
    if (EGrid[nx, ny].Kind <> ekNone) and not LayerEditable(EGrid[nx, ny].Layer) then Exit;
    if EGrid[nx, ny].Kind = ekNone then EWireLine(nx, ny, nx, ny);
    EConnect(LastCX, LastCY, nx, ny);
    LastCX := nx;
    LastCY := ny;
  end;
end;
{ ---------------------------------------------------------------- fluid power editing }

{ the next free tag with this prefix; for cylinders the next free letter A, B ... }
function NextFTag(const Prefix: string): string;
var
  n, x, y: Integer;
  used: Boolean;
begin
  n := 1;
  repeat
    if Prefix = '' then Result := Chr(Ord('A') + (n - 1) mod 26) else Result := Prefix + IntToStr(n);
    used := False;
    for y := 0 to GH - 1 do
      for x := 0 to GW - 1 do
        if (FGrid[x, y].Kind <> fkNone) and SameText(FGrid[x, y].Tag, Result) then used := True;
    Inc(n);
  until (not used) or (n > 60);
end;

procedure DefaultFTag(x, y: Integer);
var
  c: PFCell;
  p: string;
begin
  c := @FGrid[x, y];
  case c^.Kind of
    fkCompressor: p := 'C';
    fkHPump: p := 'P';
    fkReceiver: p := 'R';
    fkAccum: p := 'AC';
    fkFRL: p := 'FRL';
    fkRegulator: p := 'PR';
    fkThrottle: p := 'FC';
    fkRelief: p := 'RV';
    fkV32, fkV52, fkV53, fkV42, fkV43: p := 'V';
    fkCylSA, fkCylDA: p := '';
    fkAirMotor: p := 'AM';
    fkHydMotor: p := 'HM';
    fkGauge: p := 'PG';
    fkPSwitch: p := 'PS';
  else
    Exit;
  end;
  c^.Tag := NextFTag(p);
end;

procedure SelectFCell(gx, gy: Integer);
begin
  SelKind := selFCell;
  SelFX := gx;
  SelFY := gy;
end;

{ the next electrical tag of these kinds after Cur ('' first) }
function NextETagOf(const Cur: string; Kinds: TEKindSet): string;
var
  x, y: Integer;
  seen: Boolean;
begin
  Result := '';
  seen := Cur = '';
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      if (EGrid[x, y].Kind in Kinds) and (EGrid[x, y].Tag <> '') then
      begin
        if seen then Exit(EGrid[x, y].Tag);
        if SameText(EGrid[x, y].Tag, Cur) then seen := True;
      end;
end;

{ a row "label  < value >" that steps through electrical tags }
procedure TagRow(id: Integer; var y: Single; const Lbl: string; var Tag: string12; Kinds: TEKindSet);
begin
  Info(y + 4, Lbl);
  if Button(id, QX + 96, y, 24, 18, '<') or Button(id + 1, QX + 256, y, 24, 18, '>') then
    Tag := NextETagOf(Tag, Kinds);
  SetC(Th.OverlayBg);
  FillR(QX + 124, y, 128, 18);
  SetC(Th.Text);
  if Tag = '' then TextR(QX + 128, y + 5, '(none)') else TextR(QX + 128, y + 5, Tag);
  y := y + 22;
end;

procedure DrawFCellProps(y: Single);
var
  c: PFCell;
  k: Integer;
  v, top: Single;
  s: string;
  sA, sB: string12;
begin
  c := @FGrid[SelFX, SelFY];
  SetC(Th.Title);
  TextR(QX, y, Format('%s  [%d,%d]', [FKindNames[c^.Kind], SelFX, SelFY]));
  y := y + 14;
  if not (c^.Kind in [fkLine, fkCross]) then
  begin
    SetC(Th.OverlayBg);
    FillR(QX, y, 196, 18);
    SetC(Th.MenuBorder);
    RectR(QX, y, 196, 18);
    SetC(Th.Text);
    TextR(QX + 4, y + 5, 'Tag: ' + c^.Tag + TxtCaret(8, SelFY * GW + SelFX));
    if (TxtEdit = 8) and (TxtIdx = SelFY * GW + SelFX) then
    begin
      if Button(860, QX + 200, y, 80, 18, 'Done', True) then StopTxt;
    end
    else if Button(860, QX + 200, y, 80, 18, 'Tag') then StartTxt(8, SelFY * GW + SelFX);
    y := y + 24;
  end;
  if c^.Running or c^.Latch then SetCol(60, 205, 95) else SetC(Th.TextDim);
  TextR(QX, y, Copy(FStateText(SelFX, SelFY), 1, 35));
  y := y + 16;
  if FIsHydraulic(c^.Kind) then top := 250 else top := 10;
  case c^.Kind of
    fkCompressor, fkHPump:
      begin
        if Button(861, QX, y, 136, 18, 'ON', c^.On) then c^.On := True;
        if Button(862, QX + 142, y, 138, 18, 'OFF', not c^.On) then c^.On := False;
        y := y + 22;
        v := c^.P1;
        ParamRow(863, y, 'bar', v, 0, top, top / 50);
        c^.P1 := Round(v * 10) / 10;
        y := y + 22;
        sA := c^.SolA;
        TagRow(866, y, 'Runs while', sA, [ekRelay, ekContactor]);
        c^.SolA := sA;
      end;
    fkReceiver, fkAccum:
      begin
        if Button(868, QX, y, 136, 18, 'Empty it') then c^.Store := 0;
        y := y + 22;
      end;
    fkFRL, fkRegulator, fkRelief:
      begin
        v := c^.P1;
        if c^.Kind = fkRelief then ParamRow(869, y, 'Opens', v, 0, top, top / 50)
        else ParamRow(869, y, 'Out bar', v, 0, top, top / 50);
        c^.P1 := Round(v * 10) / 10;
        y := y + 22;
        Info(y, 'Mouse wheel over it: set it.');
        y := y + 14;
      end;
    fkThrottle:
      begin
        v := c^.P1;
        ParamRow(872, y, 'Open %', v, 2, 100, 5);
        c^.P1 := Round(v);
        y := y + 22;
        Info(y, 'Slows what moves through it.');
        y := y + 14;
      end;
    fkV32, fkV52, fkV53, fkV42, fkV43:
      begin
        for k := 0 to 3 do
          if Button(875 + k, QX + (k mod 2) * 142, y + (k div 2) * 21, 138, 18, ActNames[k], c^.Act = k) then c^.Act := k;
        y := y + 44;
        Info(y + 4, 'Position');
        for k := 0 to FPositions(c^.Kind) - 1 do
          if Button(879 + k, QX + 80 + k * 50, y, 44, 18, IntToStr(k), c^.Sel = k) and (c^.Act = 0) then c^.Sel := k;
        y := y + 22;
        if c^.Act >= 2 then
        begin
          sA := c^.SolA;
          TagRow(882, y, 'Solenoid A', sA, [ekSolenoid]);
          c^.SolA := sA;
          if (c^.Act = 3) or (FPositions(c^.Kind) = 3) then
          begin
            sB := c^.SolB;
            TagRow(884, y, 'Solenoid B', sB, [ekSolenoid]);
            c^.SolB := sB;
          end;
        end
        else if c^.Act = 1 then
        begin
          Info(y, 'Select tool: hold the mouse on it.');
          y := y + 14;
        end
        else
        begin
          Info(y, 'Select tool: click it to switch.');
          y := y + 14;
        end;
      end;
    fkCylSA, fkCylDA:
      begin
        v := c^.P1;
        ParamRow(886, y, 'Stroke s', v, 0.2, 20, 0.2);
        c^.P1 := Round(v * 10) / 10;
        y := y + 22;
        if c^.Tag <> '' then
        begin
          Info(y, Format('Limit switches: %s0 retracted,', [c^.Tag]));
          Info(y + 11, Format('%s1 extended (contacts)', [c^.Tag]));
          y := y + 26;
        end;
      end;
    fkPSwitch:
      begin
        if Button(889, QX, y, 136, 18, 'On when high', c^.Act = 0) then c^.Act := 0;
        if Button(890, QX + 142, y, 138, 18, 'On when low', c^.Act = 1) then c^.Act := 1;
        y := y + 22;
        v := c^.P1;
        ParamRow(891, y, 'Upper', v, 0, 250, 0.5);
        c^.P1 := Round(v * 10) / 10;
        v := c^.P2;
        ParamRow(894, y + 20, 'Lower', v, 0, 250, 0.5);
        c^.P2 := Round(v * 10) / 10;
        y := y + 42;
        Info(y, Format('Its tag %s is a contact.', [c^.Tag]));
        y := y + 14;
      end;
  end;
  if c^.Kind in [fkCompressor, fkHPump, fkCylSA, fkCylDA, fkAirMotor, fkHydMotor] then
  begin
    Info(y + 4, 'Equipment');
    if Button(897, QX + 80, y, 24, 18, '<') then c^.Ref := NextEquipName(c^.Ref, -1, False);
    SetC(Th.OverlayBg);
    FillR(QX + 108, y, 144, 18);
    SetC(Th.Text);
    if c^.Ref = '' then s := '(none)' else s := c^.Ref;
    TextR(QX + 112, y + 5, Copy(s, 1, 17));
    if Button(898, QX + 256, y, 24, 18, '>') then c^.Ref := NextEquipName(c^.Ref, 1, False);
    y := y + 24;
  end;
  if not (c^.Kind in [fkLine, fkCross, fkReceiver, fkAccum, fkSilencer, fkTank]) then
    if Button(899, QX, y, 136, 18, 'Rotate (R)') then FRotate(SelFX, SelFY);
  if Button(900, QX + 142, y, 138, 18, 'Delete (Del)') then DeleteSelected;
end;

{ the Line tool dragged to gx, gy }
procedure FLineTo(gx, gy: Integer);
var
  nx, ny: Integer;
begin
  gx := EnsureRange(gx, 0, GW - 1);
  gy := EnsureRange(gy, 0, GH - 1);
  while (LastCX <> gx) or (LastCY <> gy) do
  begin
    nx := LastCX;
    ny := LastCY;
    if Abs(gx - LastCX) >= Abs(gy - LastCY) then nx := nx + Sign(gx - LastCX)
    else ny := ny + Sign(gy - LastCY);
    if (FGrid[nx, ny].Kind <> fkNone) and not LayerEditable(FGrid[nx, ny].Layer) then Exit;
    if FGrid[nx, ny].Kind = fkNone then FLineRun(nx, ny, nx, ny);
    FConnect(LastCX, LastCY, nx, ny);
    LastCX := nx;
    LastCY := ny;
  end;
end;

{ ---------------------------------------------------------------- Page & Layer panel }

procedure DrawPagesContent(y0: Single);
var
  i, L: Integer;
  y: Single;
  s: string;
  P: ^TPageData;
begin
  SetC(Th.HeaderTxt);
  TextR(QX, y0, Format('PAGES  %d of %d   (PgUp / PgDn)', [PageCount, MAX_PAGES]));
  y := y0 + 14;
  for i := 0 to PageCount - 1 do
  begin
    if (TxtEdit = 1) and (TxtIdx = i) then s := Copy(Pages[i].Name, 1, 9) + TxtCaret(1, i)
    else s := Format('%d %s', [i + 1, Copy(PageName(i), 1, 8)]);
    if Button(600 + i, QX + (i mod 3) * 94, y + (i div 3) * 17, 90, 15, s, i = CurPage) then
    begin
      if (LastClicks >= 2) and (i = CurPage) then StartTxt(1, i) else AppGoToPage(i);
    end;
  end;
  y := y + 7 * 17 + 4;
  if Button(621, QX, y, 40, 18, 'Add') then AppAddPage;
  if Button(622, QX + 44, y, 44, 18, 'Copy') then AppDuplicatePage;
  if PageDelArmed > 0 then s := 'Sure?' else s := 'Delete';
  if Button(623, QX + 92, y, 56, 18, s, PageDelArmed > 0) then AppDeletePage;
  if Button(624, QX + 152, y, 24, 18, '<') then AppMovePage(-1);
  if Button(625, QX + 180, y, 24, 18, '>') then AppMovePage(1);
  if (TxtEdit = 1) and (TxtIdx = CurPage) then
  begin
    if Button(626, QX + 208, y, 72, 18, 'Done', True) then StopTxt;
  end
  else if Button(626, QX + 208, y, 72, 18, 'Rename') then StartTxt(1, CurPage);
  y := y + 28;

  P := @Pages[CurPage];
  SetC(Th.HeaderTxt);
  TextR(QX, y, Format('LAYERS of page %d   %d of %d', [CurPage + 1, P^.NLayers, MAX_LAYERS]));
  y := y + 14;
  for L := 0 to P^.NLayers - 1 do
  begin
    if (TxtEdit = 2) and (TxtIdx = L) then s := Copy(P^.Layers[L].Name, 1, 16) + TxtCaret(2, L)
    else s := Format('%d %s', [L + 1, Copy(P^.Layers[L].Name, 1, 15)]);
    if Button(630 + L, QX, y, 150, 17, s, L = CurLayer) then
    begin
      if (LastClicks >= 2) and (L = CurLayer) then StartTxt(2, L) else AppSetLayer(L);
    end;
    if P^.Layers[L].Visible then s := 'Shown' else s := 'Hidden';
    if Button(636 + L, QX + 154, y, 60, 17, s, not P^.Layers[L].Visible) then
    begin
      P^.Layers[L].Visible := not P^.Layers[L].Visible;
      DropHiddenSelection;
    end;
    if P^.Layers[L].Locked then s := 'Locked' else s := 'Open';
    if Button(642 + L, QX + 218, y, 62, 17, s, P^.Layers[L].Locked) then
    begin
      P^.Layers[L].Locked := not P^.Layers[L].Locked;
      DropHiddenSelection;
    end;
    y := y + 19;
  end;
  y := y + (MAX_LAYERS - P^.NLayers) * 19 + 4;
  if Button(648, QX, y, 90, 18, 'Add layer') then AppAddLayer;
  if LayerDelArmed > 0 then s := 'Sure?' else s := 'Delete';
  if Button(649, QX + 94, y, 90, 18, s, LayerDelArmed > 0) then AppDeleteLayer;
  if (TxtEdit = 2) and (TxtIdx = CurLayer) then
  begin
    if Button(650, QX + 188, y, 92, 18, 'Done', True) then StopTxt;
  end
  else if Button(650, QX + 188, y, 92, 18, 'Rename') then StartTxt(2, CurLayer);
  y := y + 22;
  if Button(651, QX, y, 280, 18, 'Move selection to active layer') then SelectionToLayer;
  y := y + 24;
  if not P^.Layers[CurLayer].Visible then
  begin
    SetC(Th.StatusErr);
    TextR(QX, y, 'The active layer is hidden!');
  end
  else if P^.Layers[CurLayer].Locked then
  begin
    SetC(Th.StatusErr);
    TextR(QX, y, 'The active layer is locked!');
  end
  else
    Info(y, 'New items go on the active layer.');
end;

{ ---------------------------------------------------------------- Frame popup panel }

procedure DrawPopupsContent(y0: Single);
var
  i, k, c: Integer;
  y: Single;
  s: string;
  r, g, b: Byte;
begin
  if (SelPopup >= 0) and not Popups[SelPopup].Active then SelPopup := -1;
  if SelPopup < 0 then SelPopup := NextPopup(-1, 1);
  SetC(Th.HeaderTxt);
  TextR(QX, y0, Format('FRAME POPUPS  %d of %d', [FramePopupCount, MAX_POPUPS]));
  y := y0 + 14;
  k := 0;
  for i := 0 to MAX_POPUPS - 1 do
    if Popups[i].Active then
    begin
      s := Format('%d %s', [i + 1, Copy(Popups[i].Title, 1, 8)]);
      if Button(660 + i, QX + (k mod 3) * 94, y + (k div 3) * 17, 90, 15, s, i = SelPopup) then
      begin
        SelPopup := i;
        if LastClicks >= 2 then ShowFramePopup(i);
      end;
      Inc(k);
    end;
  if k = 0 then Info(y + 4, 'None yet - Add makes one.');
  y := y + 7 * 17 + 4;
  if Button(681, QX, y, 60, 18, 'Add') then
  begin
    i := AddPopup(Format('Popup %d', [FramePopupCount + 1]), 'Type the text here.');
    if i < 0 then SetStatus(Format('A layout has at most %d frame popups', [MAX_POPUPS]), True)
    else
    begin
      SelPopup := i;
      StartTxt(3, i);
    end;
  end;
  if Button(682, QX + 64, y, 64, 18, 'Delete') and (SelPopup >= 0) then
  begin
    StopTxt;
    DeletePopup(SelPopup);
    SetStatus('Popup deleted (links to it do nothing now)');
    SelPopup := -1;
    Exit;
  end;
  if Button(683, QX + 132, y, 60, 18, 'Show', (SelPopup >= 0) and (ShownPopup = SelPopup)) and (SelPopup >= 0) then
  begin
    if ShownPopup = SelPopup then CloseFramePopup else ShowFramePopup(SelPopup);
  end;
  if Button(684, QX + 196, y, 84, 18, 'Add link') and (SelPopup >= 0) then
  begin
    { a link to it in the middle of the visible canvas, ready to drag }
    i := AddLink(SnapCell(ViewX + CANVAS_W / Zoom / 2), SnapCell(ViewY + CANVAS_H / Zoom / 2),
      LinkDefaultCaption(True, SelPopup), True, SelPopup);
    if i < 0 then SetStatus(Format('Too many links on this page (max %d)', [MAX_LINKS]), True)
    else
    begin
      SelKind := selLink;
      SelLk := i;
      SetStatus('Link added in the middle of the canvas - Link tool: drag it into place');
    end;
  end;
  y := y + 28;
  if SelPopup < 0 then
  begin
    Info(y, 'A frame popup is a small window');
    Info(y + 12, 'that a link opens over the canvas:');
    Info(y + 24, 'notes, instructions, an alarm text.');
    Exit;
  end;
  Info(y, Format('Popup %d - title', [SelPopup + 1]));
  y := y + 12;
  SetC(Th.OverlayBg);
  FillR(QX, y, 200, 18);
  SetC(Th.MenuBorder);
  RectR(QX, y, 200, 18);
  SetC(Th.Text);
  TextR(QX + 4, y + 5, Copy(Popups[SelPopup].Title + TxtCaret(3, SelPopup), 1, 24));
  if (TxtEdit = 3) and (TxtIdx = SelPopup) then
  begin
    if Button(685, QX + 204, y, 76, 18, 'Done', True) then StopTxt;
  end
  else if Button(685, QX + 204, y, 76, 18, 'Edit') then StartTxt(3, SelPopup);
  y := y + 24;
  PreviewBox(y, 52, Popups[SelPopup].Text + TxtCaret(4, SelPopup), 4, 0);
  y := y + 56;
  if (TxtEdit = 4) and (TxtIdx = SelPopup) then
  begin
    if Button(686, QX, y, 136, 18, 'Done typing', True) then StopTxt;
  end
  else if Button(686, QX, y, 136, 18, 'Edit text') then StartTxt(4, SelPopup);
  if Button(687, QX + 142, y, 138, 18, 'Clear text') then Popups[SelPopup].Text := '';
  y := y + 24;
  { its "go to page" button }
  if Button(688, QX, y, 24, 18, '<') then
  begin
    if Popups[SelPopup].GoPage < 0 then Popups[SelPopup].GoPage := PageCount - 1
    else Dec(Popups[SelPopup].GoPage);
  end;
  SetC(Th.OverlayBg);
  FillR(QX + 28, y, 224, 18);
  SetC(Th.Text);
  if Popups[SelPopup].GoPage < 0 then s := 'No "go to page" button'
  else s := Format('Button: page %d %s', [Popups[SelPopup].GoPage + 1, PageName(Popups[SelPopup].GoPage)]);
  TextR(QX + 32, y + 5, Copy(s, 1, 27));
  if Button(689, QX + 256, y, 24, 18, '>') then
  begin
    if Popups[SelPopup].GoPage >= PageCount - 1 then Popups[SelPopup].GoPage := -1
    else Inc(Popups[SelPopup].GoPage);
  end;
  y := y + 24;
  for c := 0 to 5 do
  begin
    if Button(690 + c, QX + c * 47, y, 44, 18, LabelColorNames[c], Popups[SelPopup].Color = c) then
      Popups[SelPopup].Color := c;
    if c > 0 then
    begin
      LabelRGB(c, r, g, b);
      SetCol(r, g, b);
      FillR(QX + c * 47 + 2, y + 15, 40, 2);
    end;
  end;
  y := y + 26;
  Info(y, 'Double-click a popup button: show it.');
end;

procedure RotateBlock(const A: TBlock; CW: Boolean; out B: TBlock);
var
  x, y, nx, ny, d, nd, i: Integer;
  L: TCellLite;
  wp, hp, cx, cy, ncx, ncy: Single;
begin
  B.W := A.H;
  B.H := A.W;
  B.Parts := A.Parts;
  SetLength(B.Cells, B.W * B.H);
  FillChar(B.Cells[0], SizeOf(TCellLite) * Length(B.Cells), 0);
  for y := 0 to A.H - 1 do
    for x := 0 to A.W - 1 do
    begin
      L := A.Cells[y * A.W + x];
      if L.Kind = ckEmpty then Continue;
      if CW then
      begin
        nx := A.H - 1 - y;
        ny := x;
      end
      else
      begin
        nx := y;
        ny := A.W - 1 - x;
      end;
      { E,S,W,N: clockwise turns E->S->W->N->E }
      nd := 0;
      for d := 0 to 3 do
        if (L.Conn and (1 shl d)) <> 0 then
          if CW then nd := nd or (1 shl ((d + 1) and 3)) else nd := nd or (1 shl ((d + 3) and 3));
      L.Conn := nd;
      if L.Dir >= 0 then
        if CW then L.Dir := (L.Dir + 1) and 3 else L.Dir := (L.Dir + 3) and 3;
      B.Cells[ny * B.W + nx] := L;
    end;
  { buckets stay upright: only their centres turn with the block }
  wp := A.W * CELL;
  hp := A.H * CELL;
  SetLength(B.Bkts, Length(A.Bkts));
  for i := 0 to High(A.Bkts) do
  begin
    cx := A.Bkts[i].DX + A.Bkts[i].W / 2;
    cy := A.Bkts[i].DY + A.Bkts[i].H / 2;
    if CW then
    begin
      ncx := hp - cy;
      ncy := cx;
    end
    else
    begin
      ncx := cy;
      ncy := wp - cx;
    end;
    B.Bkts[i] := A.Bkts[i];
    B.Bkts[i].DX := ncx - A.Bkts[i].W / 2;
    B.Bkts[i].DY := ncy - A.Bkts[i].H / 2;
  end;
  { labels stay upright too: their corner turns with the block }
  SetLength(B.Lbls, Length(A.Lbls));
  for i := 0 to High(A.Lbls) do
  begin
    B.Lbls[i] := A.Lbls[i];
    if CW then
    begin
      B.Lbls[i].DX := hp - A.Lbls[i].DY - CELL / 2;
      B.Lbls[i].DY := A.Lbls[i].DX;
    end
    else
    begin
      B.Lbls[i].DX := A.Lbls[i].DY;
      B.Lbls[i].DY := wp - A.Lbls[i].DX - CELL / 2;
    end;
  end;
end;

{ R: a single device turns its direction (as before); a single pipe or a box
  selection turns as a whole a quarter turn about its centre }
procedure DoRotate(CW: Boolean);
var
  A, B: TBlock;
  x1, y1, x2, y2, gx, gy, lost: Integer;
  s: string;
begin
  OpenMenu := -1;
  PopupOpen := False;
  case SelKind of
    selNone:
      begin
        SetStatus('Select parts to rotate first', True);
        Exit;
      end;
    selFCell:
      begin
        FRotate(SelFX, SelFY);
        SetStatus('Turned ' + FKindNames[FGrid[SelFX, SelFY].Kind]);
        Exit;
      end;
    selECell:
      begin
        ERotate(SelEX, SelEY);
        SetStatus('Turned ' + EKindNames[EGrid[SelEX, SelEY].Kind]);
        Exit;
      end;
    selEquip:
      begin
        Equips[SelEq].Flip := not Equips[SelEq].Flip;
        SetStatus('Flipped ' + Equips[SelEq].Name);
        Exit;
      end;
    selBucket, selLabel, selFrame, selLink:
      begin
        SetStatus('Buckets, labels, frames and links stay upright - select parts to rotate', True);
        Exit;
      end;
    selCell:
      if Grid[SelX, SelY].Kind <> ckPipe then
      begin
        RotateCell(SelX, SelY);
        if not CW then
        begin
          RotateCell(SelX, SelY);
          RotateCell(SelX, SelY);
        end;
        SetStatus('Rotated ' + KindNames[Grid[SelX, SelY].Kind]);
        Exit;
      end;
  end;
  if not CopySelectionTo(A) then Exit;
  SelRect(x1, y1, x2, y2);
  RotateBlock(A, CW, B);
  { keep the turned block centred where it was, but on the grid }
  gx := EnsureRange(x1 + (A.W - B.W) div 2, 0, Max(0, GW - B.W));
  gy := EnsureRange(y1 + (A.H - B.H) div 2, 0, Max(0, GH - B.H));
  DeleteSelected;
  s := PlaceBlock(B, gx, gy, lost);
  if CW then SetStatus('Rotated right: ' + s, lost > 0) else SetStatus('Rotated left: ' + s, lost > 0);
end;

procedure DoTheme(i: Integer);
begin
  OpenMenu := -1;
  SelectTheme(i);
  SaveSettings;
  SetStatus('Theme: ' + Th.Name);
end;

{ ---------------------------------------------------------------- menu bar }

type
  TMItem = record
    Lbl, Key: string;
    Enabled, Checked, Sep: Boolean;
    HasSub: Boolean;       { opens a sub-menu to the side instead of running }
  end;

const
  MENU_COUNT = 6;
  MenuNames: array[0..MENU_COUNT - 1] of string = ('File', 'Edit', 'View', 'Panels', 'Examples', 'Theme');
  MENU_BAR_W = 72;
  MENU_VIEW = 2;
  MENU_PANELS = 3;
  MENU_EXAMPLES = 4;
  MENU_THEME = 5;
  VIEW_GRID_ITEM = 5;      { View > Grid > }
  DEMO_FILE = 'demo_original.mflow';
  SUB_W = 220;

var
  MItems: array[0..23] of TMItem;
  MCount: Integer;
  SItems: array[0..23] of TMItem;   { the open sub-menu }
  SCount: Integer;
  SubOpen: Integer = -1;             { item of the open menu whose sub-menu is shown }
  MenuCat: array[0..15] of Integer;  { Examples menu item -> example category }
  NMenuCats: Integer = 0;

procedure AddItem(const L: string; const K: string = ''; En: Boolean = True;
  Chk: Boolean = False; Sep: Boolean = False; Sub: Boolean = False);
begin
  MItems[MCount].Lbl := L;
  MItems[MCount].Key := K;
  MItems[MCount].Enabled := En;
  MItems[MCount].Checked := Chk;
  MItems[MCount].Sep := Sep;
  MItems[MCount].HasSub := Sub;
  Inc(MCount);
end;

procedure AddSubItem(const L: string; const K: string = ''; Chk: Boolean = False; Sep: Boolean = False);
begin
  SItems[SCount].Lbl := L;
  SItems[SCount].Key := K;
  SItems[SCount].Enabled := True;
  SItems[SCount].Checked := Chk;
  SItems[SCount].Sep := Sep;
  SItems[SCount].HasSub := False;
  Inc(SCount);
end;

{ ---------------------------------------------------------------- panel windows }

{ ---------------------------------------------------------------- clipping inside panels }

var
  WinContentBottom: Single = -1;   { a scrolling panel's content sets where it ends }
  WinClipOn: Boolean = False;
  WinClipRect: TSDL_Rect;

{ clip the drawing to x, y, w, h (drawing coordinates) }
procedure ClipDraw(x, y, w, h: Single);
var
  rc: TSDL_Rect;
begin
  rc.x := Floor(SXf(x));
  rc.y := Floor(SYf(y));
  rc.w := Ceil(SSf(w));
  rc.h := Ceil(SSf(h));
  SDL_SetRenderClipRect(Ren, @rc);
end;

{ the clip of the panel being drawn, or none }
procedure RestoreWinClip;
begin
  if WinClipOn then SDL_SetRenderClipRect(Ren, @WinClipRect) else SDL_SetRenderClipRect(Ren, nil);
end;
{ ---------------------------------------------------------------- Physics Lab panel }

var
  LabMat: TMat = mWater;

{ the "Physics lab" page: found, or made }
function LabPage: Integer;
var
  i: Integer;
begin
  for i := 0 to PageCount - 1 do
    if PageName(i) = LAB_PAGE then Exit(i);
  Result := AddPage(LAB_PAGE);
end;

procedure LabTest(n: Integer);
const
  Names: array[1..3] of string = ('drop test', 'mix test', 'air transport test');
var
  p: Integer;
begin
  p := LabPage;
  if p < 0 then
  begin
    SetStatus(Format('No room for the lab page (max %d pages)', [MAX_PAGES]), True);
    Exit;
  end;
  AppGoToPage(p);
  LeavePageEdits;
  BuildPhysicsTest(n);
  HistReset;
  Running := True;
  SetStatus('Physics lab: ' + Names[n] + ' on page "' + LAB_PAGE + '"');
end;

{ open / save a physics file: the native dialogs, kinds 3 and 4 }
procedure DoOpenPhysics;
begin
  if DlgKind <> 0 then Exit;
  DlgKind := 3;
  DlgResult := 0;
  SDL_ShowOpenFileDialog(@DialogCB, nil, Win, @PhysFilters[0], Length(PhysFilters), DefaultLoc(DlgDefault), False);
end;

procedure DoSavePhysics;
begin
  if DlgKind <> 0 then Exit;
  DlgKind := 4;
  DlgResult := 0;
  SDL_ShowSaveFileDialog(@DialogCB, nil, Win, @PhysFilters[0], Length(PhysFilters), DefaultLoc(DlgDefault));
end;

procedure DrawLabContent(y0: Single);
var
  m: TMat;
  y, v: Single;
  k: Integer;
  cnt: array[TMat] of Integer;
  spd: array[TMat] of Single;
  err: string;
  sp: Single;
begin
  y := y0;
  SetC(Th.HeaderTxt);
  if PhysicsChanged then TextR(QX, y, 'MATERIAL          (changed)') else TextR(QX, y, 'MATERIAL          (built-in)');
  y := y + 13;
  k := 0;
  for m := Low(TMat) to High(TMat) do
  begin
    if Button(1000 + k, QX + k * 56, y, 53, 17, MatP[m].Name, LabMat = m) then LabMat := m;
    SetCol(MatP[m].R, MatP[m].G, MatP[m].B);
    FillR(QX + k * 56 + 2, y + 14, 49, 2);
    Inc(k);
  end;
  y := y + 22;
  with MatP[LabMat] do
  begin
    ParamRowD(1010, y, 'Mass', Mass, 0.01, 5, 0.05, 2);
    ParamRowD(1013, y + 19, 'Gravity x', Grav, -1, 2, 0.05, 2);
    ParamRowD(1016, y + 38, 'Air couple', Couple, 0, 40, 0.5, 1);
    ParamRowD(1019, y + 57, 'Air drag', Drag, 0, 10, 0.05, 2);
    ParamRowD(1022, y + 76, 'Friction', Fric, 0, 1, 0.02, 2);
    ParamRowD(1025, y + 95, 'Density', Dens, 0, 3, 0.05, 2);
    ParamRowD(1028, y + 114, 'Size px', Size, 1, 8, 0.5, 1);
    ParamRowD(1070, y + 133, 'pH', PH, 0, 14, 0.1, 1);
    y := y + 153;
    if Button(1031, QX, y, 136, 17, 'Liquid', Liquid) then Liquid := not Liquid;
    if Button(1032, QX + 142, y, 138, 17, 'Grain / light', not Liquid) then Liquid := False;
    y := y + 21;
    v := R;
    ParamRowD(1033, y, 'Red', v, 0, 255, 5, 0);
    R := Round(v);
    v := G;
    ParamRowD(1036, y + 19, 'Green', v, 0, 255, 5, 0);
    G := Round(v);
    v := B;
    ParamRowD(1039, y + 38, 'Blue', v, 0, 255, 5, 0);
    B := Round(v);
    y := y + 60;
  end;
  SetC(Th.HeaderTxt);
  TextR(QX, y, 'WORLD');
  y := y + 13;
  ParamRowD(1042, y, 'Gravity', GRAVITY, 0, 1500, 25, 0);
  ParamRowD(1045, y + 19, 'Air speed', VK, 20, 400, 5, 0);
  ParamRowD(1048, y + 38, 'Feed rate', EMIT_K, 5, 150, 5, 0);
  ParamRowD(1051, y + 57, 'Grav. feed', GRAV_FEED, 0, 300, 5, 0);
  ParamRowD(1054, y + 76, 'Air dots', AIR_K, 0, 50, 1, 0);
  y := y + 98;
  SetC(Th.HeaderTxt);
  TextR(QX, y, 'TEST SCENES (page "' + LAB_PAGE + '")');
  y := y + 13;
  if Button(1060, QX, y, 66, 17, 'Drop') then LabTest(1);
  if Button(1061, QX + 70, y, 66, 17, 'Mix') then LabTest(2);
  if Button(1062, QX + 140, y, 66, 17, 'Air') then LabTest(3);
  if Button(1063, QX + 210, y, 70, 17, 'Clear') then ClearParticles;
  y := y + 22;
  { what is on the page now: count and mean speed of the free material }
  for m := Low(TMat) to High(TMat) do
  begin
    cnt[m] := 0;
    spd[m] := 0;
  end;
  for k := 0 to NPart - 1 do
    if Parts[k].Life > 0 then
    begin
      Inc(cnt[Parts[k].Mat]);
      if not Parts[k].InPipe then
      begin
        sp := Sqrt(Sqr(Parts[k].VX) + Sqr(Parts[k].VY));
        spd[Parts[k].Mat] := spd[Parts[k].Mat] + sp;
      end;
    end;
  for m := Low(TMat) to High(TMat) do
  begin
    if cnt[m] > 0 then v := spd[m] / cnt[m] else v := 0;
    SetCol(MatP[m].R, MatP[m].G, MatP[m].B);
    FillR(QX, y + 2, 6, 6);
    Info(y, Format('  %-6s %5d   speed %4.0f px/s', [MatP[m].Name, cnt[m], v]));
    y := y + 11;
  end;
  y := y + 6;
  if Button(1064, QX, y, 66, 17, 'Reset') then
  begin
    PhysicsResetDefaults;
    SetStatus('Physics back to the built-in values');
  end;
  if Button(1065, QX + 70, y, 66, 17, 'Open...') then DoOpenPhysics;
  if Button(1066, QX + 140, y, 66, 17, 'Save...') then DoSavePhysics;
  if Button(1067, QX + 210, y, 70, 17, 'Default') then
  begin
    if SavePhysics(UnicodeString(ExtractFilePath(ParamStr(0)) + PHYS_FILE), err) then
      SetStatus('Saved as the default physics (' + PHYS_FILE + ', loaded at start)')
    else
      SetStatus('Save failed: ' + err, True);
  end;
  WinContentBottom := y + 20;
end;

{ ---------------------------------------------------------------- Shape Editor panel }

const
  SHP_BOX_H = 170;
  ShpToolNames: array[-1..PRIM_TYPES - 1] of string = ('Select', 'Rect', 'Ellipse', 'Line', 'Tri');
  ShpStates: array[0..2] of Integer = (EQS_RUN, EQS_STOP, EQS_FAULT);
  ShpStateNames: array[0..2] of string = ('Run', 'Stop', 'Fault');

var
  ShpKind: Integer = 0;
  ShpTool: Integer = -1;          { -1 select / move, else the primitive to draw }
  ShpSel: Integer = -1;
  ShpRef: Boolean = True;         { the built-in drawing behind the shape }
  ShpState: Integer = 0;          { preview state: index into ShpStates }
  ShpDrag: Integer = 0;           { 0 none, 1 drawing, 2 moving, 3 corner 2, 4 corner 1 }
  ShpU0, ShpV0: Single;
  ShpOrig: TShapePrim;
  ShpBX, ShpBY, ShpBW, ShpBH: Single;   { the drawing box on screen (for the tests too) }

function ShpSnap(v: Single): Single;
begin
  Result := EnsureRange(Round(v * 40) / 40, 0, 1);
end;

{ the built-in drawing of a kind in x, y, w, h, through a free equipment slot }
procedure DrawBuiltInAt(Kind: Integer; x, y, w, h: Single; St: Integer);
var
  j: Integer;
  keep: TEquipObj;
begin
  j := MAX_EQUIP - 1;
  while (j >= 0) and Equips[j].Active do Dec(j);
  if j < 0 then Exit;
  keep := Equips[j];
  FillChar(Equips[j], SizeOf(TEquipObj), 0);
  Equips[j].Kind := Kind;
  Equips[j].X := x;
  Equips[j].Y := y;
  Equips[j].W := w;
  Equips[j].H := h;
  Equips[j].State := St;
  Equips[j].Level := 60;
  NoCustomShape := True;
  try
    DrawEquipShape(j);
  finally
    NoCustomShape := False;
    Equips[j] := keep;
  end;
end;

procedure DoOpenShapes;
begin
  if DlgKind <> 0 then Exit;
  DlgKind := 5;
  DlgResult := 0;
  SDL_ShowOpenFileDialog(@DialogCB, nil, Win, @ShapeFilters[0], Length(ShapeFilters), DefaultLoc(DlgDefault), False);
end;

procedure DoSaveShapes;
begin
  if DlgKind <> 0 then Exit;
  DlgKind := 6;
  DlgResult := 0;
  SDL_ShowSaveFileDialog(@DialogCB, nil, Win, @ShapeFilters[0], Length(ShapeFilters), DefaultLoc(DlgDefault));
end;

procedure ShpPickKind(k: Integer);
begin
  ShpKind := (k + EQ_KINDS) mod EQ_KINDS;
  ShpSel := -1;
  ShpDrag := 0;
end;

{ mouse work in the drawing box }
procedure ShapeBoxMouse;
var
  u, v, du, dv: Single;
  P: ^TShapePrim;

  function Near(pu, pv: Single): Boolean;
  begin
    Result := (Abs(pu - u) * ShpBW < 6) and (Abs(pv - v) * ShpBH < 6);
  end;

begin
  u := EnsureRange((MX - ShpBX) / ShpBW, 0, 1);
  v := EnsureRange((MY - ShpBY) / ShpBH, 0, 1);
  if MPressed and Inside(ShpBX - 4, ShpBY - 4, ShpBW + 8, ShpBH + 8) then
  begin
    MPressed := False;
    if ShpTool >= 0 then
    begin
      ShpSel := ShapeAdd(ShpKind, ShpTool, ShpSnap(u), ShpSnap(v), ShpSnap(u), ShpSnap(v));
      if ShpSel < 0 then SetStatus(Format('A shape holds at most %d parts', [MAX_PRIM]), True)
      else ShpDrag := 1;
    end
    else
    begin
      ShpDrag := 0;
      if ShpSel >= 0 then
      begin
        P := @EqShapes[ShpKind].P[ShpSel];
        if Near(P^.X2, P^.Y2) then ShpDrag := 3
        else if Near(P^.X1, P^.Y1) then ShpDrag := 4;
      end;
      if ShpDrag = 0 then
      begin
        ShpSel := ShapeHit(ShpKind, u, v, 5 / fmin(ShpBW, ShpBH));
        if ShpSel >= 0 then ShpDrag := 2;
      end;
    end;
    ShpU0 := u;
    ShpV0 := v;
    if ShpSel >= 0 then ShpOrig := EqShapes[ShpKind].P[ShpSel];
  end
  else if (ShpDrag > 0) and MDown and (ShpSel >= 0) and (ShpSel < EqShapes[ShpKind].N) then
  begin
    P := @EqShapes[ShpKind].P[ShpSel];
    case ShpDrag of
      1, 3:
        begin
          P^.X2 := ShpSnap(u);
          P^.Y2 := ShpSnap(v);
        end;
      4:
        begin
          P^.X1 := ShpSnap(u);
          P^.Y1 := ShpSnap(v);
        end;
      2:
        begin
          { the whole part, kept inside the box }
          du := ShpSnap(u) - ShpSnap(ShpU0);
          dv := ShpSnap(v) - ShpSnap(ShpV0);
          du := EnsureRange(du, -Min(ShpOrig.X1, ShpOrig.X2), 1 - Max(ShpOrig.X1, ShpOrig.X2));
          dv := EnsureRange(dv, -Min(ShpOrig.Y1, ShpOrig.Y2), 1 - Max(ShpOrig.Y1, ShpOrig.Y2));
          P^.X1 := ShpOrig.X1 + du;
          P^.X2 := ShpOrig.X2 + du;
          P^.Y1 := ShpOrig.Y1 + dv;
          P^.Y2 := ShpOrig.Y2 + dv;
        end;
    end;
  end
  else if (ShpDrag > 0) and not MDown then
  begin
    { a click without a drag draws a part of a usual size }
    if (ShpDrag = 1) and (ShpSel >= 0) then
      with EqShapes[ShpKind].P[ShpSel] do
        if (Abs(X2 - X1) < 0.02) and (Abs(Y2 - Y1) < 0.02) then
        begin
          X1 := EnsureRange(X1, 0, 0.8);
          Y1 := EnsureRange(Y1, 0, 0.8);
          X2 := X1 + 0.2;
          Y2 := Y1 + 0.2;
        end;
    ShpDrag := 0;
  end;
end;

procedure DrawShapeContent(y0: Single);
var
  y, bw, bh, ew, eh, sc, v: Single;
  k: Integer;
  r, g, b: Byte;
  P: ^TShapePrim;
  err, s: string;
begin
  y := y0;
  { the kind }
  if Button(2000, QX, y, 24, 18, '<') then ShpPickKind(ShpKind - 1);
  if Button(2001, QX + 256, y, 24, 18, '>') then ShpPickKind(ShpKind + 1);
  SetC(Th.Title);
  s := EquipNames[ShpKind];
  if ShapeDefined(ShpKind) then s := s + Format(' (%d parts)', [EqShapes[ShpKind].N]) else s := s + ' (built-in)';
  TextR(QX + 140 - Length(s) * 4, y + 5, s);
  y := y + 22;
  { tools }
  for k := -1 to PRIM_TYPES - 1 do
    if Button(2003 + k, QX + (k + 1) * 56, y, 53, 18, ShpToolNames[k], ShpTool = k) then ShpTool := k;
  y := y + 24;

  { the drawing box: the kind's proportions, as large as fits }
  EquipDefaultSize(ShpKind, ew, eh);
  sc := fmin((280 - 16) / ew, (SHP_BOX_H - 16) / eh);
  bw := ew * sc;
  bh := eh * sc;
  ShpBX := QX + (280 - bw) / 2;
  ShpBY := y + (SHP_BOX_H - bh) / 2;
  ShpBW := bw;
  ShpBH := bh;
  SetC(Th.CanvasBg);
  FillR(QX, y, 280, SHP_BOX_H);
  SetC(Th.GridLine);
  for k := 1 to 9 do
  begin
    LineR(ShpBX + bw * k / 10, ShpBY, ShpBX + bw * k / 10, ShpBY + bh);
    LineR(ShpBX, ShpBY + bh * k / 10, ShpBX + bw, ShpBY + bh * k / 10);
  end;
  EqStateRGB(ShpStates[ShpState], r, g, b);
  { nothing drawn in the box spills out of it }
  ClipDraw(QX, y, 280, SHP_BOX_H);
  if ShpRef or not ShapeDefined(ShpKind) then
  begin
    DrawBuiltInAt(ShpKind, ShpBX, ShpBY, bw, bh, ShpStates[ShpState]);
    if ShapeDefined(ShpKind) then
    begin
      { faded behind the shape }
      SetC(Th.CanvasBg, 170);
      FillR(ShpBX, ShpBY, bw, bh);
    end;
  end;
  ShapeBoxMouse;
  DrawCustomShape(ShpKind, ShpBX, ShpBY, bw, bh, False, r, g, b);
  RestoreWinClip;
  SetC(Th.MenuBorder);
  RectR(QX, y, 280, SHP_BOX_H);
  SetC(Th.Hint);
  RectR(ShpBX, ShpBY, bw, bh);
  if (ShpSel >= 0) and (ShpSel < EqShapes[ShpKind].N) then
  begin
    P := @EqShapes[ShpKind].P[ShpSel];
    SetC(Th.Select);
    RectR(ShpBX + bw * Min(P^.X1, P^.X2) - 2, ShpBY + bh * Min(P^.Y1, P^.Y2) - 2, bw * Abs(P^.X2 - P^.X1) + 4,
      bh * Abs(P^.Y2 - P^.Y1) + 4);
    FillR(ShpBX + bw * P^.X1 - 3, ShpBY + bh * P^.Y1 - 3, 6, 6);
    FillR(ShpBX + bw * P^.X2 - 3, ShpBY + bh * P^.Y2 - 3, 6, 6);
  end
  else
    ShpSel := -1;
  y := y + SHP_BOX_H + 6;

  { the selected part }
  if ShpSel >= 0 then
  begin
    P := @EqShapes[ShpKind].P[ShpSel];
    SetC(Th.HeaderTxt);
    TextR(QX, y, Format('PART %d of %d: %s', [ShpSel + 1, EqShapes[ShpKind].N, UpperCase(PrimNames[P^.Typ])]));
    y := y + 13;
    if Button(2010, QX, y, 66, 17, 'Up') then ShpSel := ShapeMove(ShpKind, ShpSel, 1);
    if Button(2011, QX + 70, y, 66, 17, 'Down') then ShpSel := ShapeMove(ShpKind, ShpSel, -1);
    if Button(2012, QX + 140, y, 66, 17, 'Copy') then
    begin
      k := ShapeAdd(ShpKind, P^.Typ, 0, 0, 0, 0);
      if k >= 0 then
      begin
        EqShapes[ShpKind].P[k] := EqShapes[ShpKind].P[ShpSel];
        with EqShapes[ShpKind].P[k] do
        begin
          X1 := fmin(1, X1 + 0.05);
          X2 := fmin(1, X2 + 0.05);
          Y1 := fmin(1, Y1 + 0.05);
          Y2 := fmin(1, Y2 + 0.05);
        end;
        ShpSel := k;
      end;
    end;
    if Button(2013, QX + 210, y, 70, 17, 'Delete') then
    begin
      ShapeDelete(ShpKind, ShpSel);
      ShpSel := -1;
    end;
  end
  else
  begin
    Info(y, 'Pick a tool, drag in the box.');
    Info(y + 11, 'Select: click a part, then drag');
  end;
  y := y + 21;
  if ShpSel >= 0 then
  begin
    P := @EqShapes[ShpKind].P[ShpSel];
    v := P^.R;
    ParamRowD(2020, y, 'Red', v, 0, 255, 5, 0);
    P^.R := Round(v);
    v := P^.G;
    ParamRowD(2023, y + 19, 'Green', v, 0, 255, 5, 0);
    P^.G := Round(v);
    v := P^.B;
    ParamRowD(2026, y + 38, 'Blue', v, 0, 255, 5, 0);
    P^.B := Round(v);
    v := P^.A;
    ParamRowD(2029, y + 57, 'Opacity', v, 10, 255, 5, 0);
    P^.A := Round(v);
    ParamRowD(2032, y + 76, 'Thickness', P^.Thick, 1, 12, 1, 0);
    if P^.StateCol then
    begin
      SetCol(r, g, b);
      FillR(QX + 72, y + 3, 14, 50);
    end;
    if Button(2035, QX, y + 96, 136, 17, 'Filled', P^.Fill) then P^.Fill := not P^.Fill;
    if Button(2036, QX + 142, y + 96, 138, 17, 'State colour', P^.StateCol) then P^.StateCol := not P^.StateCol;
  end
  else
  begin
    Info(y, 'it or one of its corners.');
    Info(y + 19, 'Up / Down: draw a part over or');
    Info(y + 30, 'under the others.');
    Info(y + 49, 'State colour: green run, grey');
    Info(y + 60, 'stop, red fault.');
    Info(y + 79, 'Drag the corner of this window');
    Info(y + 90, 'to make it larger.');
  end;
  y := y + 120;
  SetC(Th.HeaderTxt);
  TextR(QX, y, 'NEW PIECES (0 = built-in size)');
  y := y + 13;
  ParamRowD(2040, y, 'Width', EqShapes[ShpKind].W, 0, 600, 8, 0);
  ParamRowD(2043, y + 19, 'Height', EqShapes[ShpKind].H, 0, 600, 8, 0);
  y := y + 42;
  if Button(2050, QX, y, 66, 17, 'Ref', ShpRef) then ShpRef := not ShpRef;
  if Button(2051, QX + 70, y, 66, 17, ShpStateNames[ShpState]) then ShpState := (ShpState + 1) mod 3;
  if Button(2052, QX + 140, y, 66, 17, 'Clear') then
  begin
    EqShapes[ShpKind].N := 0;
    ShpSel := -1;
    SetStatus(EquipNames[ShpKind] + ': back to the built-in drawing');
  end;
  if Button(2053, QX + 210, y, 70, 17, 'All') then
  begin
    ShapesReset;
    ShpSel := -1;
    SetStatus('Every kind back to its built-in drawing');
  end;
  y := y + 21;
  if Button(2054, QX, y, 88, 17, 'Open...') then DoOpenShapes;
  if Button(2055, QX + 92, y, 88, 17, 'Save...') then DoSaveShapes;
  if Button(2056, QX + 184, y, 96, 17, 'Default') then
  begin
    if SaveShapes(UnicodeString(ExtractFilePath(ParamStr(0)) + SHAPE_FILE), err) then
      SetStatus(Format('Saved %d shapes as the default (%s, loaded at start)', [ShapesCount, SHAPE_FILE]))
    else
      SetStatus('Save failed: ' + err, True);
  end;
  WinContentBottom := y + 20;
end;

const
  WIN_TOOLS = 0;
  WIN_SIM = 1;
  WIN_PROPS = 2;
  WIN_STATUS = 3;
  WIN_HELP = 4;
  WIN_PAGES = 5;
  WIN_POPUPS = 6;
  WIN_LAB = 7;
  WIN_SHAPE = 8;
  WIN_CORE = 7;      { the panels 'Dock all' handles; the lab and the shape editor float }
  WIN_COUNT = 9;
  WIN_TITLE_H = 18;
  WinKeys: array[0..WIN_COUNT - 1] of string = ('F2', 'F3', 'F4', 'F5', 'F1', 'F6', 'F7', 'F8', 'F9');

procedure InitWins;
  procedure Setup(i: Integer; const T: string; DY, H: Single);
  begin
    Wins[i].Title := T;
    Wins[i].Visible := True;
    Wins[i].W := 296;
    Wins[i].H := H;
    Wins[i].DockX := PANEL_X + 4;
    Wins[i].DockY := DY;
    Wins[i].Side := 0;
    Wins[i].X := Wins[i].DockX;
    Wins[i].Y := DY;
    Wins[i].Dragging := False;
    Wins[i].Scale := 1;
    Wins[i].BaseW := 296;
    Wins[i].BaseH := H;
    Wins[i].Sizing := False;
    Wins[i].Scroll := 0;
    Wins[i].ContentH := 0;
    Wins[i].ScrollDrag := False;
  end;
begin
  { embedded, they stack down a panel column (right or left of the canvas) }
  Setup(WIN_TOOLS, 'TOOL', 4, 232);
  Setup(WIN_SIM, 'SIMULATION', 238, 124);
  Setup(WIN_PROPS, 'PROPERTIES', 364, 296);
  Setup(WIN_STATUS, 'STATUS', 662, 56);
  Setup(WIN_HELP, 'HELP', 720, 95);
  { the page panels start in the left column }
  Setup(WIN_PAGES, 'PAGE & LAYER', 4, 372);
  Setup(WIN_POPUPS, 'FRAME POPUP', 380, 410);
  Wins[WIN_PAGES].Side := 1;
  Wins[WIN_POPUPS].Side := 1;
  Wins[WIN_PAGES].X := -PANEL_W + 4;
  Wins[WIN_POPUPS].X := -PANEL_W + 4;
  { the physics lab: hidden, floating; its slot is the top of the left column }
  Setup(WIN_LAB, 'PHYSICS LAB', 4, 520);
  Wins[WIN_LAB].Side := 1;
  Wins[WIN_LAB].Visible := False;
  Wins[WIN_LAB].X := 240;
  Wins[WIN_LAB].Y := 40;
  Setup(WIN_SHAPE, 'SHAPE EDITOR', 4, 512);
  Wins[WIN_SHAPE].Side := 1;
  Wins[WIN_SHAPE].Visible := False;
  Wins[WIN_SHAPE].X := 560;
  Wins[WIN_SHAPE].Y := 40;
end;

{ the Physics lab and the Shape editor can be made larger: their content scales }
function WinResizable(i: Integer): Boolean;
begin
  Result := i in [WIN_LAB, WIN_SHAPE];
end;

procedure SetWinScale(i: Integer; s: Single);
begin
  Wins[i].Scale := fclamp(s, 0.8, 3);
  Wins[i].W := Wins[i].BaseW * Wins[i].Scale;
  Wins[i].H := Wins[i].BaseH * Wins[i].Scale;
end;

{ x of panel i's slot: in the right column, or in the left column (left of the canvas) }
function DockXOf(i: Integer): Single;
begin
  if Wins[i].Side = 1 then Result := -PANEL_W + 4 else Result := Wins[i].DockX;
end;

function WinDocked(i: Integer): Boolean;
begin
  Result := (Wins[i].X = DockXOf(i)) and (Wins[i].Y = Wins[i].DockY);
end;

function EmbeddedLeft(i: Integer): Boolean;
begin
  Result := Wins[i].Visible and (Wins[i].Side = 1) and WinDocked(i);
end;

function EmbeddedRight(i: Integer): Boolean;
begin
  Result := Wins[i].Visible and (Wins[i].Side = 0) and WinDocked(i);
end;

{ right edge of the usable area (canvas plus the right column when it is open) }
function SceneRight: Single;
begin
  Result := CANVAS_W + RightW;
end;

{ open or close the left column to match the panels embedded there, keeping
  the canvas the same size on screen (the window grows / shrinks) }
procedure ApplyLayout;
var
  i, newL, newR, oldTotal, newTotal, ww, wh: Integer;
  db: TSDL_Rect;
begin
  { a column exists only while a panel is embedded in it }
  newL := 0;
  newR := 0;
  for i := 0 to WIN_COUNT - 1 do
  begin
    if EmbeddedLeft(i) then newL := PANEL_W;
    if EmbeddedRight(i) then newR := PANEL_W;
  end;
  if (newL = LeftW) and (newR = RightW) then Exit;
  oldTotal := CANVAS_W + LeftW + RightW;
  newTotal := CANVAS_W + newL + newR;
  LeftW := newL;
  RightW := newR;
  OX := LeftW;
  if Ren = nil then Exit;
  SDL_SetRenderLogicalPresentation(Ren, newTotal, WIN_H + MENU_H, SDL_LOGICAL_PRESENTATION_LETTERBOX);
  if SDL_GetWindowSize(Win, @ww, @wh) then
  begin
    ww := Round(ww * newTotal / oldTotal);
    if SDL_GetDisplayUsableBounds(SDL_GetPrimaryDisplay, @db) then
      ww := Min(ww, db.w - 20);
    SDL_SetWindowSize(Win, ww, wh);
  end;
  { floating panels stay where they are on the canvas, but inside the window }
  for i := 0 to WIN_COUNT - 1 do
    if not WinDocked(i) then
      Wins[i].X := fclamp(Wins[i].X, -LeftW, SceneRight - Wins[i].W);
end;

function InWin(i: Integer; x, y: Single): Boolean;
begin
  Result := Wins[i].Visible and (x >= Wins[i].X) and (x < Wins[i].X + Wins[i].W) and
    (y >= Wins[i].Y) and (y < Wins[i].Y + Wins[i].H);
end;

{ the top-most visible panel under x,y, or -1 }
function WinAt(x, y: Single): Integer;
var
  k: Integer;
begin
  for k := WIN_COUNT - 1 downto 0 do
    if InWin(WinOrder[k], x, y) then Exit(WinOrder[k]);
  Result := -1;
end;

{ the top-most Focus Properties window of this page at x, y, or -1 }
function PinAt(x, y: Single): Integer;
var
  k: Integer;
begin
  for k := High(Pins) downto 0 do
    if (Pins[k].Page = CurPage) and (x >= Pins[k].X) and (x < Pins[k].X + Pins[k].W) and (y >= Pins[k].Y) and
      (y < Pins[k].Y + Pins[k].H) then Exit(k);
  Result := -1;
end;

function InAnyWin(x, y: Single): Boolean;
begin
  Result := (WinAt(x, y) >= 0) or (PinAt(x, y) >= 0);
end;

procedure BringToFront(i: Integer);
var
  k, j: Integer;
begin
  for k := 0 to WIN_COUNT - 1 do
    if WinOrder[k] = i then
    begin
      for j := k to WIN_COUNT - 2 do
        WinOrder[j] := WinOrder[j + 1];
      WinOrder[WIN_COUNT - 1] := i;
      Exit;
    end;
end;

procedure DockWin(i: Integer);
begin
  SetWinScale(i, 1);
  Wins[i].X := DockXOf(i);
  Wins[i].Y := Wins[i].DockY;
  Wins[i].Visible := True;
  OpenMenu := -1;
  ApplyLayout;
  { ApplyLayout may have opened the left column: the slot is final now }
  Wins[i].X := DockXOf(i);
  SaveSettings;
end;

{ Side 0 = right embed, 1 = left embed }
procedure EmbedWin(i, Side: Integer);
begin
  Wins[i].Side := Side;
  DockWin(i);
  if Side = 1 then SetStatus(Wins[i].Title + ' embedded on the left')
  else SetStatus(Wins[i].Title + ' embedded on the right');
end;

procedure FloatWin(i: Integer);
begin
  Wins[i].Visible := True;
  Wins[i].X := 360 + i * 30;
  Wins[i].Y := 120 + i * 30;
  OpenMenu := -1;
  BringToFront(i);
  ApplyLayout;
  SaveSettings;
  SetStatus(Wins[i].Title + ' is floating - drag its title bar');
end;

{ materialflow.ini:  theme=N  and per panel  panelN=visible,side,docked,x,y,scale% }
procedure SaveSettings;
var
  f: TextFile;
  i: Integer;
begin
  if SettingsFile = '' then Exit;
  try
    AssignFile(f, SettingsFile);
    Rewrite(f);
    try
      WriteLn(f, 'theme=', ThemeIndex);
      WriteLn(f, Format('grid=%d,%d,%d,%d,%d,%d', [Ord(GridShow), GridStyle, GridMajor, GridStrength,
        GridColor, Ord(GridNumbers)]));
      for i := 0 to WIN_COUNT - 1 do
        WriteLn(f, Format('panel%d=%d,%d,%d,%d,%d,%d', [i, Ord(Wins[i].Visible), Wins[i].Side,
          Ord(WinDocked(i)), Round(Wins[i].X), Round(Wins[i].Y), Round(Wins[i].Scale * 100)]));
    finally
      CloseFile(f);
    end;
  except
    { settings are optional }
  end;
end;

procedure LoadSettings;
var
  f: TextFile;
  s: string;
  i, p, n: Integer;
  v: array[0..5] of Integer;
  g6: array[0..5] of Integer;
  rest: string;
begin
  if (SettingsFile = '') or not FileExists(SettingsFile) then
  begin
    ApplyLayout;
    Exit;
  end;
  try
    AssignFile(f, SettingsFile);
    Reset(f);
    try
      while not EOF(f) do
      begin
        ReadLn(f, s);
        s := Trim(s);
        if Pos('theme=', s) = 1 then
          SelectTheme(StrToIntDef(Copy(s, 7, 10), 0))
        else if Pos('grid=', s) = 1 then
        begin
          rest := Copy(s, 6, MaxInt) + ',';
          n := 0;
          while (n <= 5) and (rest <> '') do
          begin
            p := Pos(',', rest);
            g6[n] := StrToIntDef(Copy(rest, 1, p - 1), 0);
            Delete(rest, 1, p);
            Inc(n);
          end;
          if n >= 6 then
          begin
            GridShow := g6[0] <> 0;
            GridStyle := EnsureRange(g6[1], 0, 2);
            if g6[2] in [0, 4, 5, 10] then GridMajor := g6[2];
            GridStrength := EnsureRange(g6[3], 0, 2);
            GridColor := EnsureRange(g6[4], 0, 4);
            GridNumbers := g6[5] <> 0;
          end;
        end
        else if (Pos('panel', s) = 1) and (Length(s) > 7) and (s[7] = '=') then
        begin
          i := StrToIntDef(s[6], -1);
          if (i < 0) or (i >= WIN_COUNT) then Continue;
          rest := Copy(s, 8, MaxInt) + ',';
          n := 0;
          while (n <= 5) and (rest <> '') do
          begin
            p := Pos(',', rest);
            v[n] := StrToIntDef(Copy(rest, 1, p - 1), 0);
            Delete(rest, 1, p);
            Inc(n);
          end;
          if n < 5 then Continue;
          Wins[i].Visible := v[0] <> 0;
          Wins[i].Side := EnsureRange(v[1], 0, 1);
          if v[2] <> 0 then
          begin
            Wins[i].X := DockXOf(i);
            Wins[i].Y := Wins[i].DockY;
          end
          else
          begin
            if (n >= 6) and WinResizable(i) then SetWinScale(i, v[5] / 100);
            Wins[i].X := v[3];
            Wins[i].Y := EnsureRange(v[4], 0, WIN_H - WIN_TITLE_H);
          end;
        end;
      end;
    finally
      CloseFile(f);
    end;
  except
    { a broken settings file just means defaults }
  end;
  ApplyLayout;
  { floating panels must still be reachable after the layout is known }
  for i := 0 to WIN_COUNT - 1 do
    if not WinDocked(i) then
      Wins[i].X := fclamp(Wins[i].X, -LeftW, SceneRight - Wins[i].W);
end;

procedure ToggleWin(i: Integer);
var
  n: string;
begin
  Wins[i].Visible := not Wins[i].Visible;
  Wins[i].Dragging := False;
  OpenMenu := -1;
  n := LowerCase(Wins[i].Title);
  n := UpCase(n[1]) + Copy(n, 2, MaxInt);
  if Wins[i].Visible then
  begin
    BringToFront(i);
    SetStatus(n + ' panel shown');
  end
  else
    SetStatus(n + ' panel hidden - ' + WinKeys[i] + ' shows it');
  ApplyLayout;
  SaveSettings;
end;

function AllDocked: Boolean;
var
  i: Integer;
begin
  Result := True;
  for i := 0 to WIN_CORE - 1 do
    if not (Wins[i].Visible and WinDocked(i)) then Exit(False);
end;

procedure DockProperties;
begin
  DockWin(WIN_PROPS);
end;

procedure ToggleProperties;
begin
  ToggleWin(WIN_PROPS);
end;

procedure BuildMenu(m: Integer);
var
  i: Integer;
  s: string;
begin
  MCount := 0;
  case m of
    0:
      begin
        AddItem('New layout', 'Ctrl+N');
        AddItem('Open...', 'Ctrl+O');
        if CurrentFile = '' then s := 'Save (as new file)' else s := 'Save';
        AddItem(s, 'Ctrl+S');
        AddItem('Save as...', 'Ctrl+Shift+S');
        AddItem('Exit', 'Ctrl+Q', True, False, True);
      end;
    1:
      begin
        AddItem('Undo', 'Ctrl+Z', CanUndo);
        AddItem('Redo', 'Ctrl+Y', CanRedo);
        AddItem('Cut', 'Ctrl+X', SelKind <> selNone, False, True);
        AddItem('Copy', 'Ctrl+C', SelKind <> selNone);
        AddItem('Paste', 'Ctrl+V', not ClipEmpty);
        AddItem('Delete', 'Del', SelKind <> selNone);
        AddItem('Rotate right', 'R', SelKind <> selNone, False, True);
        AddItem('Rotate left', 'Shift+R', SelKind <> selNone);
      end;
    MENU_VIEW:
      begin
        AddItem('Zoom in', 'Ctrl+=', Zoom < ZOOM_MAX);
        AddItem('Zoom out', 'Ctrl+-', Zoom > ZOOM_MIN);
        AddItem(Format('Zoom 100%%   (now %.0f%%)', [Zoom * 100]), 'Ctrl+0', Zoom <> 1);
        AddItem('Pressure colours', 'P', True, ShowPressure, True);
        AddItem('Air dots', 'A', True, ShowAir);
        AddItem('Grid', '>', True, GridShow, True, True);   { VIEW_GRID_ITEM }
      end;
    MENU_PANELS:
      begin
        AddItem('Tool', WinKeys[WIN_TOOLS], True, Wins[WIN_TOOLS].Visible);
        AddItem('Simulation', WinKeys[WIN_SIM], True, Wins[WIN_SIM].Visible);
        AddItem('Properties', WinKeys[WIN_PROPS], True, Wins[WIN_PROPS].Visible);
        AddItem('Status', WinKeys[WIN_STATUS], True, Wins[WIN_STATUS].Visible);
        AddItem('Help', WinKeys[WIN_HELP], True, Wins[WIN_HELP].Visible);
        AddItem('Page & Layer', WinKeys[WIN_PAGES], True, Wins[WIN_PAGES].Visible);
        AddItem('Frame popup', WinKeys[WIN_POPUPS], True, Wins[WIN_POPUPS].Visible);
        AddItem('Physics lab', WinKeys[WIN_LAB], True, Wins[WIN_LAB].Visible, True);
        AddItem('Shape editor', WinKeys[WIN_SHAPE], True, Wins[WIN_SHAPE].Visible);
        AddItem('Dock all panels', '', not AllDocked, False, True);
      end;
    MENU_EXAMPLES:
      begin
        AddItem('Original demo');
        NMenuCats := 0;
        for i := 1 to EXAMPLE_CATS do
          if CatFirst[i] <= Min(CatLast[i], EXAMPLE_COUNT) then
          begin
            Inc(NMenuCats);
            MenuCat[NMenuCats] := i;
            AddItem(Format('%s (%d)', [CatNames[i], Min(CatLast[i], EXAMPLE_COUNT) - CatFirst[i] + 1]), '>', True, False,
              NMenuCats = 1, True);
          end;
      end;
    MENU_THEME:
      for i := 0 to THEME_COUNT - 1 do
        AddItem(Themes[i].Name, '', True, i = ThemeIndex);
  end;
end;

{ View > Grid >  (radio groups: style, major lines, strength, colour) }
procedure BuildGridMenu;
begin
  SCount := 0;
  AddSubItem('Show grid', 'G', GridShow);
  AddSubItem('Style: lines', '', GridStyle = 0, True);
  AddSubItem('Style: dots', '', GridStyle = 1);
  AddSubItem('Style: crosses', '', GridStyle = 2);
  AddSubItem('Major: none', '', GridMajor = 0, True);
  AddSubItem('Major: every 4 cells', '', GridMajor = 4);
  AddSubItem('Major: every 5 cells', '', GridMajor = 5);
  AddSubItem('Major: every 10 cells', '', GridMajor = 10);
  AddSubItem('Strength: faint', '', GridStrength = 0, True);
  AddSubItem('Strength: normal', '', GridStrength = 1);
  AddSubItem('Strength: strong', '', GridStrength = 2);
  AddSubItem('Colour: theme', '', GridColor = 0, True);
  AddSubItem('Colour: blue', '', GridColor = 1);
  AddSubItem('Colour: green', '', GridColor = 2);
  AddSubItem('Colour: amber', '', GridColor = 3);
  AddSubItem('Colour: white', '', GridColor = 4);
  AddSubItem('Cell numbers on edges', '', GridNumbers, True);
  AddSubItem('Reset grid to default');
end;

procedure ResetGrid;
begin
  GridShow := True;
  GridStyle := 0;
  GridMajor := 0;
  GridStrength := 1;
  GridColor := 0;
  GridNumbers := False;
end;

procedure RunGridItem(i: Integer);
const
  Majors: array[4..7] of Integer = (0, 4, 5, 10);
begin
  OpenMenu := -1;
  SubOpen := -1;
  case i of
    0: GridShow := not GridShow;
    1..3: GridStyle := i - 1;
    4..7: GridMajor := Majors[i];
    8..10: GridStrength := i - 8;
    11..15: GridColor := i - 11;
    16: GridNumbers := not GridNumbers;
    17: ResetGrid;
  end;
  { choosing a look also turns the grid on }
  if (i > 0) and (i < 17) then GridShow := True;
  SaveSettings;
  if GridShow then SetStatus('Grid: ' + SItems[i].Lbl) else SetStatus('Grid hidden - G shows it');
end;

{ the items of the sub-menu that item SubOpen of menu m opens }
procedure BuildSub(m: Integer);
var
  c, n: Integer;
begin
  SCount := 0;
  if m = MENU_EXAMPLES then
  begin
    if (SubOpen < 1) or (SubOpen > NMenuCats) then Exit;
    c := MenuCat[SubOpen];
    for n := CatFirst[c] to Min(CatLast[c], EXAMPLE_COUNT) do
      AddSubItem(Format('%d: %s', [n, ExampleTitles[n]]));
  end
  else
    BuildGridMenu;
end;

procedure RunSub(m, i: Integer);
begin
  if m = MENU_EXAMPLES then
  begin
    OpenMenu := -1;
    if (SubOpen >= 1) and (SubOpen <= NMenuCats) then DoExample(CatFirst[MenuCat[SubOpen]] + i);
    SubOpen := -1;
  end
  else
    RunGridItem(i);
end;
procedure RunMenuItem(m, i: Integer);
var
  k: Integer;
begin
  OpenMenu := -1;
  SubOpen := -1;
  case m of
    0:
      case i of
        0: DoNew;
        1: DoOpen;
        2: DoSave;
        3: DoSaveAs;
        4: QuitRequested := True;
      end;
    1:
      case i of
        0: DoUndo;
        1: DoRedo;
        2: DoCut;
        3: DoCopy;
        4: DoPaste;
        5: DoDelete;
        6: DoRotate(True);
        7: DoRotate(False);
      end;
    MENU_VIEW:
      case i of
        0: ZoomAt(Zoom * 1.25, CANVAS_W / 2, CANVAS_H / 2);
        1: ZoomAt(Zoom / 1.25, CANVAS_W / 2, CANVAS_H / 2);
        2: ZoomAt(1, CANVAS_W / 2, CANVAS_H / 2);
        3: ShowPressure := not ShowPressure;
        4: ShowAir := not ShowAir;
      end;
    MENU_PANELS:
      case i of
        0..8: ToggleWin(i);
        9:
          for k := 0 to WIN_CORE - 1 do DockWin(k);
      end;
    MENU_EXAMPLES:
      if i = 0 then DoLoadDemo else DoExample(i);
    MENU_THEME:
      DoTheme(i);
  end;
end;

function MenuBarX(m: Integer): Single;
begin
  Result := -LeftW + 8 + m * (MENU_BAR_W + 4);
end;

{ a drop-down wide enough for its widest item: the label from x+20, the key right-aligned }
function ListW(const Items: array of TMItem; Count: Integer): Single;
var
  i: Integer;
begin
  Result := 150;
  for i := 0 to Count - 1 do
    Result := fmax(Result, 20 + Length(Items[i].Lbl) * 8 + 24 + Length(Items[i].Key) * 8 + 10);
end;

function MenuW(m: Integer): Single;
begin
  BuildMenu(m);
  Result := ListW(MItems, MCount);
end;

{ the open sub-menu's width (its items must be built) }
function SubW: Single;
begin
  Result := ListW(SItems, SCount);
end;
function MenuX(m: Integer): Single;
begin
  Result := fmin(MenuBarX(m), SceneRight - MenuW(m) - 4);   { keep drop-downs inside the window }
end;

function ItemY(i: Integer): Single;
var
  k: Integer;
begin
  Result := 6;   { first item just below the menu bar }
  for k := 0 to i do
  begin
    if MItems[k].Sep then Result := Result + 9;
    if k < i then Result := Result + 20;
  end;
end;

{ where the sub-menu of item SubOpen of menu m goes: right of the menu, or left when there is no room }
function SubX(m: Integer): Single;
begin
  Result := MenuX(m) + MenuW(m) - 2;
  if Result + SubW > SceneRight then Result := MenuX(m) - SubW + 2;
end;

function SubTop: Single;
begin
  Result := ItemY(SubOpen) - 4;
end;

function SubItemY(i: Integer): Single;
var
  k: Integer;
begin
  Result := SubTop + 4;
  for k := 0 to i do
  begin
    if SItems[k].Sep then Result := Result + 9;
    if k < i then Result := Result + 20;
  end;
end;

{ one drop-down list; returns the item clicked (Pressed) or -1 }
function DrawItemList(const Items: array of TMItem; Count: Integer; x, w, top: Single; IsSub: Boolean;
  Pressed: Boolean): Integer;
var
  i: Integer;
  y, h: Single;
  hot: Boolean;
begin
  Result := -1;
  if IsSub then h := SubItemY(Count - 1) + 24 - top else h := ItemY(Count - 1) + 24 - top;
  SetCol(0, 0, 0, 90);
  FillR(x + 4, top + 4, w, h);
  SetC(Th.MenuBg);
  FillR(x, top, w, h);
  SetC(Th.MenuBorder);
  RectR(x, top, w, h);
  for i := 0 to Count - 1 do
  begin
    if IsSub then y := SubItemY(i) else y := ItemY(i);
    if Items[i].Sep then
    begin
      SetC(Th.MenuSep);
      LineR(x + 6, y - 5, x + w - 6, y - 5);
    end;
    hot := Items[i].Enabled and Inside(x, y, w, 20);
    { hovering a sub-menu item opens its sub-menu; hovering another item closes it }
    if (not IsSub) and Inside(x, y, w, 20) then
      if Items[i].HasSub then SubOpen := i else SubOpen := -1;
    if hot or ((not IsSub) and (SubOpen = i)) then
    begin
      SetC(Th.MenuHot);
      FillR(x + 2, y, w - 4, 20);
    end;
    if Items[i].Checked then
    begin
      if hot then SetC(Th.BtnSelText) else SetC(Th.Title);
      FillR(x + 7, y + 7, 6, 6);
    end;
    if not Items[i].Enabled then SetC(Th.MenuDisabled)
    else if hot then SetC(Th.BtnSelText)
    else SetC(Th.Text);
    TextR(x + 20, y + 6, Items[i].Lbl);
    if hot then SetC(Th.BtnSelText) else SetC(Th.MenuKey);
    TextR(x + w - 8 - Length(Items[i].Key) * 8, y + 6, Items[i].Key);
    if hot and Pressed then Result := i;
  end;
end;

function InItemList(Count: Integer; x, w, top: Single; IsSub: Boolean): Boolean;
var
  h: Single;
begin
  if IsSub then h := SubItemY(Count - 1) + 24 - top else h := ItemY(Count - 1) + 24 - top;
  Result := Inside(x, top, w, h);
end;

{ the page you are on, in the menu bar: < Page 2/3: name >  and the active layer }
procedure DrawPageBar(Pressed: Boolean);
var
  x, w, y: Single;
  s, ls: string;
  hot: Boolean;

  function Arrow(px: Single; const lbl: string; En: Boolean): Boolean;
  begin
    hot := En and Inside(px, y, 22, 18);
    if hot then SetC(Th.BtnHot) else SetC(Th.BtnBg);
    FillR(px, y, 22, 18);
    SetC(Th.BtnBorder);
    RectR(px, y, 22, 18);
    if En then SetC(Th.BtnText) else SetC(Th.MenuDisabled);
    TextR(px + 7, y + 5, lbl);
    Result := Pressed and hot;
  end;

begin
  y := -MENU_H + 3;
  s := Format('Page %d/%d: %s', [CurPage + 1, PageCount, Copy(PageName(CurPage), 1, 20)]);
  ls := 'Layer: ' + Copy(Pages[CurPage].Layers[CurLayer].Name, 1, 14);
  w := Length(s) * 8 + 16;
  x := MenuBarX(MENU_COUNT) + 20;
  if Arrow(x, '<', CurPage > 0) then AppGoToPage(CurPage - 1);
  { the page name: a click shows the Page & Layer panel }
  hot := Inside(x + 24, y, w, 18);
  if hot then SetC(Th.BtnHot) else SetC(Th.OverlayBg);
  FillR(x + 24, y, w, 18);
  SetC(Th.BtnBorder);
  RectR(x + 24, y, w, 18);
  SetC(Th.Title);
  TextR(x + 32, y + 5, s);
  if Pressed and hot and not Wins[WIN_PAGES].Visible then ToggleWin(WIN_PAGES);
  if Arrow(x + 28 + w, '>', CurPage < PageCount - 1) then AppGoToPage(CurPage + 1);
  SetC(Th.TextDim);
  TextR(x + 60 + w, y + 5, ls);
end;

procedure DrawMenus(Pressed: Boolean);
var
  m, i, hit: Integer;
  bx, x, w, sx: Single;
  hot, inSub: Boolean;
begin
  if OpenMenu < 0 then SubOpen := -1;
  for m := 0 to MENU_COUNT - 1 do
  begin
    bx := MenuBarX(m);
    hot := Inside(bx, -MENU_H + 3, MENU_BAR_W, 18);
    { like a menu bar: with one menu open, hovering another opens that one }
    if (OpenMenu >= 0) and hot and (OpenMenu <> m) and not Pressed then
    begin
      OpenMenu := m;
      SubOpen := -1;
    end;
    if OpenMenu = m then SetC(Th.BtnSel) else if hot then SetC(Th.BtnHot) else SetC(Th.BtnBg);
    FillR(bx, -MENU_H + 3, MENU_BAR_W, 18);
    if OpenMenu = m then SetC(Th.BtnSelBorder) else SetC(Th.BtnBorder);
    RectR(bx, -MENU_H + 3, MENU_BAR_W, 18);
    if OpenMenu = m then SetC(Th.BtnSelText) else SetC(Th.BtnText);
    TextR(Round(bx + (MENU_BAR_W - Length(MenuNames[m]) * 8) / 2), -MENU_H + 8, MenuNames[m]);
    if Pressed and hot then
    begin
      if OpenMenu = m then OpenMenu := -1 else OpenMenu := m;
      SubOpen := -1;
      Pressed := False;
    end;
  end;
  DrawPageBar(Pressed and (OpenMenu < 0));
  if OpenMenu < 0 then Exit;

  m := OpenMenu;
  BuildMenu(m);
  x := MenuX(m);
  w := MenuW(m);
  { while the mouse is in the open sub-menu, the parent keeps it open }
  inSub := False;
  if SubOpen >= 0 then
  begin
    BuildSub(m);
    inSub := InItemList(SCount, SubX(m), SubW, SubTop, True);
    BuildMenu(m);
  end;
  if inSub then
    hit := DrawItemList(MItems, MCount, x, w, 0, False, False)
  else
    hit := DrawItemList(MItems, MCount, x, w, 0, False, Pressed);
  if hit >= 0 then
  begin
    if MItems[hit].HasSub then
      SubOpen := hit           { clicking it just keeps the sub-menu open }
    else
    begin
      RunMenuItem(m, hit);
      Exit;
    end;
    Pressed := False;
  end;
  if SubOpen >= 0 then
  begin
    BuildSub(m);
    sx := SubX(m);
    BuildSub(m);
    i := DrawItemList(SItems, SCount, sx, SubW, SubTop, True, Pressed);
    if i >= 0 then
    begin
      RunSub(m, i);
      Exit;
    end;
    if Pressed and InItemList(SCount, sx, SubW, SubTop, True) then Pressed := False;
  end;
  if Pressed and not InItemList(MCount, x, w, 0, False) then
  begin
    OpenMenu := -1;
    SubOpen := -1;
  end;
end;
procedure DrawMultiProps(y: Single);
var
  np, nb: Integer;
begin
  CountSelection(np, nb);
  SetC(Th.Title);
  TextR(QX, y, 'Selection');
  Info(y + 16, Format('%d parts, %d buckets, %d labels', [np, nb, CountSelLabels]));
  Info(y + 28, Format('Area %d x %d cells at [%d,%d]', [SelX2 - SelX1 + 1, SelY2 - SelY1 + 1, SelX1, SelY1]));
  if Button(160, QX, y + 46, 66, 18, 'Cut') then DoCut;
  if Button(161, QX + 70, y + 46, 66, 18, 'Copy') then DoCopy;
  if Button(163, QX + 140, y + 46, 66, 18, 'Rotate') then DoRotate(True);
  if Button(162, QX + 210, y + 46, 70, 18, 'Delete') then DoDelete;
  Info(y + 74, 'Paste: Ctrl+V over the canvas,');
  Info(y + 86, 'or right-click > Paste here.');
  Info(y + 98, 'Pasted parts keep their joints.');
end;

{ ---------------------------------------------------------------- panel }

{ ---------------------------------------------------------------- panel contents }

{ the button label of a tool: the full name on the 3-column Pipes tab (11 characters fit),
  a short one (8 characters) on the 4-column Equipment and Electric tabs }
function ToolLabel(t: TTool; Cols: Integer): string;
begin
  if Cols <= 3 then Exit(Copy(ToolNames[t], 1, 11));
  case t of
    tEqScrew: Result := 'Screw';
    tEqStand: Result := 'Stand';
    tEqSlide: Result := 'Slide v.';
    tEqIRHeater: Result := 'IR heat.';
    tEqPump: Result := 'Pump';
    tEqConveyor: Result := 'Rollers';
    tEqBelt: Result := 'Belt';
    tElPBLatch: Result := 'Push 1/0';
    tElNO: Result := 'NO';
    tElNC: Result := 'NC';
    tElContactor: Result := 'Contact.';
    tElDrive: Result := 'VFD';
    tElSolenoid: Result := 'Solenoid';
    tEqCylinder: Result := 'Cylinder';
    tEqCompressor: Result := 'Compress';
    tEqHPU: Result := 'Hyd.unit';
    tEqReceiver: Result := 'Receiver';
    tEqController: Result := 'Facepl.';
    tEqHeatEx: Result := 'Heat ex.';
    tEqCoolTower: Result := 'C.tower';
    tFlCompressor: Result := 'Compress';
    tFlHPump: Result := 'Hyd.pump';
    tFlRegulator: Result := 'Regulat.';
    tFlCylSA: Result := 'Cyl.sgl';
    tFlCylDA: Result := 'Cyl.dbl';
    tFlAirMotor: Result := 'Air mot.';
    tFlHydMotor: Result := 'Hyd.mot.';
    tFlV32: Result := '3/2';
    tFlV52: Result := '5/2';
    tFlV53: Result := '5/3';
    tFlV42: Result := '4/2';
    tFlV43: Result := '4/3';
    tFlAnd: Result := 'AND';
    tFlShuttle: Result := 'OR';
    tElAC: Result := 'AC 230V';
    tElDC: Result := 'DC 24V';
    tElSw2: Result := '2-way';
    tElSw3: Result := '3-way';
    tElFloat: Result := 'Float';
    tElCT: Result := 'CT';
    tElPot: Result := 'Pot';
    tEqGauge: Result := 'Gauge';
    tEqDigital: Result := 'Display';
    tElMotor: Result := 'Motor';
  else
    Result := Copy(ToolNames[t], 1, 8);
  end;
end;

{ the electrical part a tool places (ekNone: not an electrical tool, or the wire) }
function ElecToolKind(t: TTool): TEKind;
begin
  if (t > tElWire) and (t <= tElSolenoid) then Result := TEKind(Ord(t) - Ord(tElWire) + 1)
  else if t >= tCtCounter then Result := TEKind(Ord(ekCounter) + Ord(t) - Ord(tCtCounter))
  else Result := ekNone;
end;

function IsElecTool(t: TTool): Boolean;
begin
  Result := ((t >= tElWire) and (t <= tElSolenoid)) or (t >= tCtCounter);
end;

function IsFluidTool(t: TTool): Boolean;
begin
  Result := (t >= tFlLine) and (t <= tFlPSwitch);
end;

function ToolTabOf(t: TTool): Integer;
begin
  if t >= tCtCounter then Result := 4
  else if t >= tFlLine then Result := 3
  else if t >= tElWire then Result := 2
  else if t >= tEqMotor then Result := 1
  else Result := 0;
end;

procedure DrawToolsContent(y0: Single);
const
  TabNames: array[0..4] of string = ('Pipes', 'Equip', 'Elec.', 'Fluid', 'Ctrl');
var
  t: TTool;
  i, k, cols: Integer;
  hw, y, bw: Single;
begin
  if Tool <> tSelect then ToolTab := ToolTabOf(Tool);
  for i := 0 to 4 do
    if Button(22 + i, QX + i * 56, y0, 52, 16, TabNames[i], ToolTab = i) then
    begin
      ToolTab := i;
      if ToolTabOf(Tool) <> i then Tool := tSelect;
    end;
  y0 := y0 + 20;
  if ToolTab in [0, 4] then cols := 3 else cols := 4;
  bw := 280 / cols - 4;
  k := 0;
  for t := Low(TTool) to High(TTool) do
  begin
    { Select is on every tab }
    if (t <> tSelect) and (ToolTabOf(t) <> ToolTab) then Continue;
    i := Ord(t);
    if Button(300 + i, QX + (k mod cols) * (bw + 4), y0 + (k div cols) * 19, bw, 17, ToolLabel(t, cols), Tool = t) then
    begin
      Tool := t;
      Drag := dragNone;
      EqPick := -1;
    end;
    Inc(k);
  end;
  y := y0 + ((k + cols - 1) div cols) * 19 + 4;
  SetC(Th.Hint);
  if PasteArmed then
    TextR(QX, y, 'Click the canvas to paste (Esc)')
  else
    TextR(QX, y, ToolHints[Tool]);
  if ToolTab <> 0 then Exit;
  y := y + 14;
  SetC(Th.Text);
  TextR(QX, y + 4, 'Pipe size');
  if Button(30, QX + 80, y, 18, 16, '-') then BrushDia := Max(1, BrushDia - 1);
  SetC(Th.Text);
  TextR(QX + 106, y + 4, IntToStr(BrushDia));
  if Button(31, QX + 120, y, 18, 16, '+') then BrushDia := Min(MAX_DIA, BrushDia + 1);
  hw := HWOf(BrushDia);
  SetC(Th.PipeWall);
  FillR(QX + 148, y + 8 - hw - 2.5, 130, 2 * hw + 5);
  SetC(Th.PipeBore);
  FillR(QX + 148, y + 8 - hw, 130, 2 * hw);
end;
procedure DrawSimContent(y0: Single);
var
  i: Integer;
  s: string;
begin
  if Running then s := 'Pause' else s := 'Run';
  if Button(40, QX, y0, 90, 20, s, not Running) then Running := not Running;
  if Button(41, QX + 94, y0, 90, 20, 'Pressure', ShowPressure) then ShowPressure := not ShowPressure;
  if Button(42, QX + 188, y0, 90, 20, 'Air dots', ShowAir) then ShowAir := not ShowAir;
  ParamRow(43, y0 + 26, 'Grav.', GravityScale, 0, 2, 0.1);
  SetC(Th.PanelBg);
  FillR(QX + 236, y0 + 26, 44, 14);
  SetC(Th.Text);
  TextR(QX + 238, y0 + 29, Format('%3.0f%%', [GravityScale * 100]));
  if Button(46, QX, y0 + 46, 90, 20, 'Clear flow') then ClearParticles;
  if Button(47, QX + 94, y0 + 46, 90, 20, 'Clear floor') then ClearFloor;
  if Button(48, QX + 188, y0 + 46, 90, 20, 'Load demo') then DoLoadDemo;
  if Button(49, QX, y0 + 70, 90, 20, 'New blank') then DoNew;
  if Button(50, QX + 94, y0 + 70, 90, 20, 'Empty bkts') then
    for i := 0 to MAX_BUCKETS - 1 do
      if Buckets[i].Active then EmptyBucket(i);
  if Button(51, QX + 188, y0 + 70, 90, 20, 'Fill feeders') then RefillAllTanks;
end;

procedure DrawPropsContent(y0: Single);
var
  np, nb: Integer;
begin
  if (SelKind = selCell) and (Grid[SelX, SelY].Kind = ckEmpty) then SelKind := selNone;
  if (SelKind = selBucket) and not Buckets[SelB].Active then SelKind := selNone;
  if (SelKind = selLabel) and not Labels[SelL].Active then SelKind := selNone;
  if (SelKind = selFrame) and ((SelFr < 0) or not Frames[SelFr].Active) then SelKind := selNone;
  if (SelKind = selLink) and ((SelLk < 0) or not Links[SelLk].Active) then SelKind := selNone;
  if (SelKind = selEquip) and ((SelEq < 0) or not Equips[SelEq].Active) then SelKind := selNone;
  if (SelKind = selECell) and EEmpty(SelEX, SelEY) then SelKind := selNone;
  if (SelKind = selFCell) and FEmpty(SelFX, SelFY) then SelKind := selNone;
  if SelKind = selMulti then
  begin
    CountSelection(np, nb);
    if np + nb + CountSelLabels = 0 then SelKind := selNone;   { e.g. emptied by undo }
  end;
  case SelKind of
    selCell: DrawCellProps(y0);
    selLabel: DrawLabelProps(y0);
    selFrame: DrawFrameProps(y0);
    selLink: DrawLinkProps(y0);
    selEquip: DrawEquipProps(y0);
    selECell: DrawECellProps(y0);
    selFCell: DrawFCellProps(y0);
    selBucket: DrawBucketProps(y0);
    selMulti: DrawMultiProps(y0);
  else
    begin
      Info(y0 + 2, 'Nothing selected.');
      Info(y0 + 16, 'Use Select (1) and click a feeder,');
      Info(y0 + 28, 'blower, valve, pipe or bucket,');
      Info(y0 + 40, 'or drag a box around several.');
      Info(y0 + 58, 'Drag a selected part to move it,');
      Info(y0 + 70, 'R rotates it.');
      Info(y0 + 88, 'Materials: water, oil, fluff,');
      Info(y0 + 100, 'sand - each mixed with air.');
    end;
  end;
end;

{ ---------------------------------------------------------------- side panel }

{ the frame around the canvas: the menu bar strip on top, and a column on
  the right / left only while a panel is embedded there }
procedure DrawPanel;
begin
  QX := PX;
  { menu bar strip (its buttons are drawn last, with the drop-downs) }
  SetC(Th.PanelBg);
  FillR(-LeftW, -MENU_H, SceneRight + LeftW, MENU_H);
  SetC(Th.PanelLine);
  LineR(-LeftW, -1, SceneRight, -1);

  if RightW > 0 then
  begin
    SetC(Th.PanelBg);
    FillR(PANEL_X, 0, RightW, WIN_H);
    SetC(Th.PanelLine);
    LineR(PANEL_X, 0, PANEL_X, WIN_H);
  end;
  if LeftW > 0 then
  begin
    SetC(Th.PanelBg);
    FillR(-LeftW, 0, LeftW, WIN_H);
    SetC(Th.PanelLine);
    LineR(-1, 0, -1, WIN_H);
  end;
end;

procedure DrawStatusContent(y0: Single);
var
  gx, gy, L, fr, part, eq: Integer;
  c: PCell;
  s: string;
begin
  s := Format('Particles %d (air %d)', [NPart, NAir]);
  if LimitHit then s := s + ' LIMIT';
  Info(y0, s);
  if Running then s := 'running' else s := 'PAUSED';
  Info(y0 + 11, Format('%.0f fps %s  zoom %.0f%%', [FPS, s, Zoom * 100]));
  s := 'Pointer outside the layout';
  if (MX >= 0) and (MX < CANVAS_W) and (MY >= 0) and (MY < CANVAS_H) and (MWX >= 0) and (MWY >= 0) then
  begin
    gx := Trunc(MWX / CELL);
    gy := Trunc(MWY / CELL);
    L := LabelAt(MWX, MWY);
    fr := FrameAt(MWX, MWY, part);
    eq := EquipPick(MWX, MWY, gx, gy, part);
    if (L < 0) and EPick(gx, gy) then
      s := Copy(EGrid[gx, gy].Tag + ' ' + EStateText(gx, gy), 1, 35)
    else if (L < 0) and FPick(gx, gy) then
      s := Copy(FGrid[gx, gy].Tag + ' ' + FStateText(gx, gy), 1, 35)
    else if (L < 0) and (eq >= 0) then
      s := Equips[eq].Name + ': ' + EquipNames[Equips[eq].Kind]
    else if L >= 0 then
      s := Format('Label %d [%d,%d]', [L + 1, gx, gy])
    else if fr >= 0 then
      s := 'Frame: ' + Frames[fr].Title
    else if InGrid(gx, gy) then
    begin
      c := @Grid[gx, gy];
      if c^.Kind <> ckEmpty then
        s := Format('%s d%d P%.1f v%.0f', [KindNames[c^.Kind], c^.Dia, c^.P, CellSpeed(gx, gy)])
      else
        s := Format('Cell %d,%d (empty)', [gx, gy]);
    end;
  end;
  Info(y0 + 22, s);
end;

const
  HELP_PAGES = 8;
  HelpTitles: array[0..HELP_PAGES - 1] of string = ('Basics', 'Select & move', 'Edit',
    'View & panels', 'Files & labels', 'Pages & links', 'Lab & shapes', 'Control');
  HelpText: array[0..HELP_PAGES - 1, 0..4] of string = (
    ('L-drag: use the current tool', 'R-click: menu   R-drag: erase', 'Wheel on part: strength/size',
     'Space pause  P pressure  A air', 'Keys 1-0: pick a tool'),
    ('Select tool: drag a box', 'Drag a selected part: move it', 'R / Shift+R: rotate right/left',
     'Esc: deselect', 'Del: delete the selection'),
    ('Ctrl+Z undo   Ctrl+Y redo', 'Ctrl+X cut  Ctrl+C copy', 'Ctrl+V paste under the mouse',
     'Device tool on a pipe: insert', 'Pipe from a pipe: tee/cross'),
    ('Ctrl+wheel / Ctrl +/-: zoom', 'Ctrl+0: zoom 100%', 'Middle-drag or arrows: pan',
     'F1-F5: show / hide panels', 'R-click a panel: embed/float'),
    ('Ctrl+S save   Ctrl+O open', 'Examples menu: ready layouts',
     'Label tool: click, then type', 'Double-click a label: edit',
     'Date/Time label: live clock'),
    ('PgUp/PgDn or < > on the menu bar', 'F6: pages and layers (max 20/5)', 'F7: frame popups (max 20)',
     'Click a link: go to page / popup', 'Ctrl+click a link: select it'),
    ('F8: physics lab - materials,', 'world, test scenes, .mfphys files', 'F9: shape editor - draw a kind''s',
     'own vector shape, .mfshape files', 'Drag their corner: make larger'),
    ('Ctrl tab: counter, sensors and', 'controller (set point, actual, out)', 'Timer: on/off-delay, pulse, flasher', 'All pages run at the same time;', 'same tag / name links two pages'));

var
  HelpPage: Integer = 0;

procedure DrawHelpContent(y0: Single);
var
  k: Integer;
begin
  for k := 0 to 4 do
    Info(y0 + k * 11, HelpText[HelpPage, k]);
  if Button(230, QX, y0 + 56, 18, 14, '<') then HelpPage := (HelpPage + HELP_PAGES - 1) mod HELP_PAGES;
  if Button(231, QX + 22, y0 + 56, 18, 14, '>') then HelpPage := (HelpPage + 1) mod HELP_PAGES;
  SetC(Th.HeaderTxt);
  TextR(QX + 48, y0 + 59, Format('%d/%d  %s', [HelpPage + 1, HELP_PAGES, HelpTitles[HelpPage]]));
end;

{ ---------------------------------------------------------------- panel window frame }

procedure DrawWin(i: Integer);
const
  BW = 16;
var
  Wn: ^TWin;
  closeX, y0, sc, kOX, kOY, kMX, kMY, visH, maxS, sbx, sby, sbh, sth, stp: Single;
  hot, keepP, hidP: Boolean;
  k: Integer;
begin
  Wn := @Wins[i];
  if not Wn^.Visible then Exit;
  if Wn^.Sizing then
  begin
    if MDown then
      { as large as the mouse says, but kept on the screen }
      SetWinScale(i, fmin(fmax((MX - Wn^.X) / Wn^.BaseW, (MY - Wn^.Y) / Wn^.BaseH),
        fmin((WIN_H - Wn^.Y) / Wn^.BaseH, (SceneRight - Wn^.X) / Wn^.BaseW)))
    else
    begin
      Wn^.Sizing := False;
      SaveSettings;
    end;
  end;
  if Wn^.Dragging then
  begin
    if MDown then
    begin
      Wn^.X := fclamp(MX - Wn^.DOX, -LeftW, SceneRight - Wn^.W);
      Wn^.Y := fclamp(MY - Wn^.DOY, 0, WIN_H - WIN_TITLE_H);
      { snap into its slot in the right column, or the left one when it is open }
      if Abs(Wn^.Y - Wn^.DockY) < 14 then
        if Abs(Wn^.X - Wn^.DockX) < 14 then
        begin
          Wn^.Side := 0;
          Wn^.X := Wn^.DockX;
          Wn^.Y := Wn^.DockY;
        end
        else if (LeftW > 0) and (Abs(Wn^.X - (-PANEL_W + 4)) < 14) then
        begin
          Wn^.Side := 1;
          Wn^.X := -PANEL_W + 4;
          Wn^.Y := Wn^.DockY;
        end;
    end
    else
    begin
      Wn^.Dragging := False;
      { dragging the last panel out of the left column closes it }
      ApplyLayout;
      SaveSettings;
    end;
  end;
  if MPressed and InWin(i, MX, MY) then BringToFront(i);

  if not WinDocked(i) then
  begin
    SetCol(0, 0, 0, 80);
    FillR(Wn^.X + 5, Wn^.Y + 5, Wn^.W, Wn^.H);
  end;
  SetC(Th.PanelBg);
  FillR(Wn^.X, Wn^.Y, Wn^.W, Wn^.H);
  SetC(Th.MenuBorder);
  RectR(Wn^.X, Wn^.Y, Wn^.W, Wn^.H);
  { title bar }
  if Wn^.Dragging then SetC(Th.BtnSel) else SetC(Th.BtnBg);
  FillR(Wn^.X + 1, Wn^.Y + 1, Wn^.W - 2, WIN_TITLE_H);
  if Wn^.Dragging then SetC(Th.BtnSelText) else SetC(Th.HeaderTxt);
  TextR(Wn^.X + 8, Wn^.Y + 6, Wn^.Title);
  closeX := Wn^.X + Wn^.W - BW - 2;
  hot := Inside(closeX, Wn^.Y + 2, BW, BW);
  if hot then
  begin
    SetC(Th.StatusErr);
    FillR(closeX, Wn^.Y + 2, BW, BW);
  end;
  if hot then SetC(Th.BtnSelText) else SetC(Th.Text);
  TextR(closeX + 4, Wn^.Y + 6, 'x');
  if MPressed and hot then
  begin
    ToggleWin(i);
    MPressed := False;
    Exit;
  end;
  if MPressed and Inside(Wn^.X, Wn^.Y, Wn^.W, WIN_TITLE_H + 2) then
  begin
    Wn^.Dragging := True;
    Wn^.DOX := MX - Wn^.X;
    Wn^.DOY := MY - Wn^.Y;
    MPressed := False;
  end;

  { a resizable panel scales its content: drawing and the mouse go through the panel's scale }
  sc := Wn^.Scale;
  if WinResizable(i) and not WinDocked(i) and MPressed and Inside(Wn^.X + Wn^.W - 14, Wn^.Y + Wn^.H - 14, 14, 14) then
  begin
    Wn^.Sizing := True;
    MPressed := False;
  end;
  kOX := OX;
  kOY := OY;
  kMX := MX;
  kMY := MY;
  if sc <> 1 then
  begin
    OX := OX / sc;
    OY := OY / sc;
    MX := MX / sc;
    MY := MY / sc;
    SDL_SetRenderScale(Ren, sc, sc);
  end;
  { a panel whose content is taller than it scrolls: wheel, the bar on its right, or a click on the bar }
  visH := (Wn^.H - WIN_TITLE_H) / sc - 2;
  maxS := fmax(0, Wn^.ContentH - visH);
  sbx := Wn^.X / sc + Wn^.W / sc - 8;
  sby := (Wn^.Y + WIN_TITLE_H) / sc + 3;
  sbh := visH - 18;
  sth := 0;
  if maxS > 0 then
  begin
    sth := fmax(20, sbh * visH / Wn^.ContentH);
    if Wn^.ScrollDrag then
    begin
      if MDown then Wn^.Scroll := (MY - Wn^.DragOff - sby) / fmax(1, sbh - sth) * maxS
      else Wn^.ScrollDrag := False;
    end;
    Wn^.Scroll := fclamp(Wn^.Scroll, 0, maxS);
    stp := sby + (sbh - sth) * Wn^.Scroll / maxS;
    if MPressed and Inside(sbx - 3, sby, 11, sbh) then
    begin
      if (MY >= stp) and (MY <= stp + sth) then
      begin
        Wn^.ScrollDrag := True;
        Wn^.DragOff := MY - stp;
      end
      else if MY < stp then Wn^.Scroll := fmax(0, Wn^.Scroll - visH * 0.9)
      else Wn^.Scroll := fmin(maxS, Wn^.Scroll + visH * 0.9);
      MPressed := False;
    end;
  end
  else
    Wn^.Scroll := 0;
  QX := Wn^.X / sc + 8;
  y0 := (Wn^.Y + WIN_TITLE_H) / sc + 6 - Wn^.Scroll;  WinClipRect.x := Floor(SXf(Wn^.X / sc + 1));
  WinClipRect.y := Floor(SYf((Wn^.Y + WIN_TITLE_H) / sc + 1));
  WinClipRect.w := Ceil(Wn^.W / sc - 2);
  WinClipRect.h := Ceil((Wn^.H - WIN_TITLE_H) / sc - 2);
  WinClipOn := True;
  RestoreWinClip;
  { a press outside the visible content is not for the content (it may be scrolled away) }
  keepP := MPressed;
  hidP := MPressed and not Inside(Wn^.X / sc, (Wn^.Y + WIN_TITLE_H) / sc, Wn^.W / sc, visH);
  if hidP then MPressed := False;
  WinContentBottom := -1;
  case i of
    WIN_TOOLS: DrawToolsContent(y0);
    WIN_SIM: DrawSimContent(y0);
    WIN_PROPS: DrawPropsContent(y0);
    WIN_STATUS: DrawStatusContent(y0);
    WIN_HELP: DrawHelpContent(y0);
    WIN_PAGES: DrawPagesContent(y0);
    WIN_POPUPS: DrawPopupsContent(y0);
    WIN_LAB:
      begin
        IdBase := 8000;
        DrawLabContent(y0);
        IdBase := 0;
      end;
    WIN_SHAPE:
      begin
        IdBase := 6000;
        DrawShapeContent(y0);
        IdBase := 0;
      end;
  end;
  { how tall the content was: the scroll range for the next frame }
  if WinContentBottom > 0 then Wn^.ContentH := WinContentBottom - (y0 - 6) + 6 else Wn^.ContentH := 0;
  if hidP then MPressed := keepP;
  if maxS > 0 then
  begin
    SetC(Th.SliderTrack);
    FillR(sbx, sby, 6, sbh);
    if Wn^.ScrollDrag or Inside(sbx - 3, stp, 11, sth) then SetC(Th.SliderFill) else SetC(Th.SliderKnob);
    FillR(sbx, stp, 6, sth);
  end;
  SDL_SetRenderClipRect(Ren, nil);
  WinClipOn := False;  if sc <> 1 then
  begin
    SDL_SetRenderScale(Ren, 1, 1);
    OX := kOX;
    OY := kOY;
    MX := kMX;
    MY := kMY;
  end;
  QX := PX;
  { the size grip }
  if WinResizable(i) and not WinDocked(i) then
  begin
    if Wn^.Sizing or Inside(Wn^.X + Wn^.W - 14, Wn^.Y + Wn^.H - 14, 14, 14) then SetC(Th.Select) else SetC(Th.TextDim);
    for k := 0 to 2 do
      LineR(Wn^.X + Wn^.W - 4 - k * 4, Wn^.Y + Wn^.H - 2, Wn^.X + Wn^.W - 2, Wn^.Y + Wn^.H - 4 - k * 4);
  end;
end;

{ ---------------------------------------------------------------- Focus Properties windows }

type
  TSelSave = record
    K: TSelKind;
    X, Y, B, L, Fr, Lk, Eq, EX, EY, X1, Y1, X2, Y2: Integer;
  end;

procedure SaveSel(out S: TSelSave);
begin
  S.K := SelKind;
  S.X := SelX;
  S.Y := SelY;
  S.B := SelB;
  S.L := SelL;
  S.Fr := SelFr;
  S.Lk := SelLk;
  S.Eq := SelEq;
  S.EX := SelEX;
  S.EY := SelEY;
  S.X1 := SelX1;
  S.Y1 := SelY1;
  S.X2 := SelX2;
  S.Y2 := SelY2;
end;

procedure RestoreSel(const S: TSelSave);
begin
  SelKind := S.K;
  SelX := S.X;
  SelY := S.Y;
  SelB := S.B;
  SelL := S.L;
  SelFr := S.Fr;
  SelLk := S.Lk;
  SelEq := S.Eq;
  SelEX := S.EX;
  SelEY := S.EY;
  SelX1 := S.X1;
  SelY1 := S.Y1;
  SelX2 := S.X2;
  SelY2 := S.Y2;
end;

{ make the pinned item the selection (for drawing its properties) }
procedure PinToSel(const P: TPinWin);
begin
  SelKind := TSelKind(P.Kind);
  case TSelKind(P.Kind) of
    selCell: begin SelX := P.A; SelY := P.B; end;
    selBucket: SelB := P.A;
    selLabel: SelL := P.A;
    selFrame: SelFr := P.A;
    selLink: SelLk := P.A;
    selEquip: SelEq := P.A;
    selECell: begin SelEX := P.A; SelEY := P.B; end;
    selFCell: begin SelFX := P.A; SelFY := P.B; end;
  end;
end;

function PinValid(const P: TPinWin): Boolean;
begin
  case TSelKind(P.Kind) of
    selCell: Result := InGrid(P.A, P.B) and (Grid[P.A, P.B].Kind <> ckEmpty);
    selBucket: Result := (P.A >= 0) and (P.A < MAX_BUCKETS) and Buckets[P.A].Active;
    selLabel: Result := (P.A >= 0) and (P.A < MAX_LABELS) and Labels[P.A].Active;
    selFrame: Result := (P.A >= 0) and (P.A < MAX_FRAMES) and Frames[P.A].Active;
    selLink: Result := (P.A >= 0) and (P.A < MAX_LINKS) and Links[P.A].Active;
    selEquip: Result := (P.A >= 0) and (P.A < MAX_EQUIP) and Equips[P.A].Active;
    selECell: Result := not EEmpty(P.A, P.B);
    selFCell: Result := not FEmpty(P.A, P.B);
  else
    Result := False;
  end;
end;

procedure ClosePin(k: Integer);
var
  j: Integer;
begin
  if (k < 0) or (k > High(Pins)) then Exit;
  for j := k to High(Pins) - 1 do Pins[j] := Pins[j + 1];
  SetLength(Pins, Length(Pins) - 1);
end;

{ pin k goes on top of the others; returns its new index }
function PinToFront(k: Integer): Integer;
var
  t: TPinWin;
  j: Integer;
begin
  Result := k;
  if (k < 0) or (k >= High(Pins)) then Exit;
  t := Pins[k];
  for j := k to High(Pins) - 1 do Pins[j] := Pins[j + 1];
  Pins[High(Pins)] := t;
  Result := High(Pins);
end;

{ right-click > Focus properties: a window that keeps showing what is selected now }
procedure OpenPin;
var
  P: TPinWin;
  k, n: Integer;
begin
  if not (SelKind in [selCell, selBucket, selLabel, selFrame, selLink, selEquip, selECell, selFCell]) then
  begin
    SetStatus('Right-click one item to focus its properties', True);
    Exit;
  end;
  FillChar(P, SizeOf(P), 0);
  P.Kind := Ord(SelKind);
  case SelKind of
    selCell: begin P.A := SelX; P.B := SelY; end;
    selBucket: P.A := SelB;
    selLabel: P.A := SelL;
    selFrame: P.A := SelFr;
    selLink: P.A := SelLk;
    selEquip: P.A := SelEq;
    selECell: begin P.A := SelEX; P.B := SelEY; end;
    selFCell: begin P.A := SelFX; P.B := SelFY; end;
  end;
  P.Page := CurPage;
  { it is open already: bring it up }
  for k := 0 to High(Pins) do
    if (Pins[k].Page = P.Page) and (Pins[k].Kind = P.Kind) and (Pins[k].A = P.A) and (Pins[k].B = P.B) then
    begin
      PinToFront(k);
      SetStatus('Its Focus Properties window is open already');
      Exit;
    end;
  P.W := 296;
  case SelKind of
    selBucket: P.H := 160;
    selLabel, selLink: P.H := 270;
    selECell: P.H := 262;
    selFCell: P.H := 300;
  else
    P.H := 316;
  end;
  n := 0;
  for k := 0 to High(Pins) do
    if Pins[k].Page = CurPage then Inc(n);
  P.X := fclamp(PopupX + 24 + (n mod 6) * 18, -LeftW, SceneRight - P.W);
  P.Y := fclamp(PopupY + (n mod 6) * 18, 0, WIN_H - P.H);
  SetLength(Pins, Length(Pins) + 1);
  Pins[High(Pins)] := P;
  SetStatus('Focus Properties: ' + SelName + ' - drag its title, x closes it');
end;

{ one Focus Properties window; a click reaches it only when Press }
procedure DrawPin(k: Integer; Press: Boolean);
const
  BW = 16;
var
  P: ^TPinWin;
  saved: TSelSave;
  closeX, y0: Single;
  hot: Boolean;
  title: string;
begin
  P := @Pins[k];
  MPressed := Press;
  if P^.Dragging then
  begin
    if MDown then
    begin
      P^.X := fclamp(MX - P^.DOX, -LeftW, SceneRight - P^.W);
      P^.Y := fclamp(MY - P^.DOY, 0, WIN_H - WIN_TITLE_H);
    end
    else
      P^.Dragging := False;
  end;
  SaveSel(saved);
  PinToSel(P^);
  if PinValid(P^) then title := 'FOCUS: ' + SelName else title := 'FOCUS: (gone)';
  { frame: shadow, body, a border in the selection colour, title bar }
  SetCol(0, 0, 0, 90);
  FillR(P^.X + 5, P^.Y + 5, P^.W, P^.H);
  SetC(Th.PanelBg);
  FillR(P^.X, P^.Y, P^.W, P^.H);
  SetC(Th.Select);
  RectR(P^.X, P^.Y, P^.W, P^.H);
  RectR(P^.X + 1, P^.Y + 1, P^.W - 2, P^.H - 2);
  if P^.Dragging then SetC(Th.BtnSel) else SetC(Th.Select, 60);
  FillR(P^.X + 2, P^.Y + 2, P^.W - 4, WIN_TITLE_H - 1);
  SetC(Th.Text);
  TextR(P^.X + 8, P^.Y + 6, Copy(title, 1, 32));
  closeX := P^.X + P^.W - BW - 3;
  hot := Inside(closeX, P^.Y + 2, BW, BW);
  if hot then
  begin
    SetC(Th.StatusErr);
    FillR(closeX, P^.Y + 2, BW, BW);
  end;
  if hot then SetC(Th.BtnSelText) else SetC(Th.Text);
  TextR(closeX + 4, P^.Y + 6, 'x');
  if MPressed and hot then
  begin
    RestoreSel(saved);
    MPressed := False;
    ClosePin(k);
    Exit;
  end;
  if MPressed and Inside(P^.X, P^.Y, P^.W, WIN_TITLE_H + 2) then
  begin
    P^.Dragging := True;
    P^.DOX := MX - P^.X;
    P^.DOY := MY - P^.Y;
    MPressed := False;
  end;
  { the properties of the pinned item; widget ids of their own so its sliders and
    buttons do not move with the Properties panel's }
  QX := P^.X + 8;
  y0 := P^.Y + WIN_TITLE_H + 6;
  if PinValid(P^) then
  begin
    IdBase := 10000 * (k + 1);
    case TSelKind(P^.Kind) of
      selCell: DrawCellProps(y0);
      selLabel: DrawLabelProps(y0);
      selFrame: DrawFrameProps(y0);
      selLink: DrawLinkProps(y0);
      selEquip: DrawEquipProps(y0);
      selECell: DrawECellProps(y0);
      selFCell: DrawFCellProps(y0);
      selBucket: DrawBucketProps(y0);
    end;
    IdBase := 0;
  end
  else
  begin
    Info(y0 + 4, 'The item is gone: deleted, or moved');
    Info(y0 + 16, 'to another cell. Close this window.');
  end;
  QX := PX;
  RestoreSel(saved);
end;

{ the Focus Properties windows of this page, the clicked one on top }
procedure DrawPins(Pressed: Boolean; Target: Integer);
var
  k, n: Integer;
begin
  if (Target >= 0) and Pressed then Target := PinToFront(Target);
  k := 0;
  while k <= High(Pins) do
  begin
    n := Length(Pins);
    if Pins[k].Page = CurPage then DrawPin(k, Pressed and (k = Target));
    if Length(Pins) = n then Inc(k);   { a closed window shifts the rest down }
  end;
  MPressed := False;
end;

function InMenuBar(x, y: Single): Boolean;
begin
  Result := (y >= -MENU_H) and (y < 0);   { the whole menu bar strip }
end;

{ ---------------------------------------------------------------- editing }

procedure DeleteSelected;
var
  x, y, i: Integer;
begin
  case SelKind of
    selCell: EraseCell(SelX, SelY);
    selBucket: DeleteBucket(SelB);
    selLabel: DeleteLabel(SelL);
    selLink: DeleteLink(SelLk);
    selEquip: DeleteEquip(SelEq);
    selECell: EErase(SelEX, SelEY);
    selFCell: FErase(SelFX, SelFY);
    selFrame:
      begin
        if EditFrame = SelFr then StopEditFrame;
        DeleteFrame(SelFr);
      end;
    selMulti:
      begin
        { buckets first: their test looks at the box, not at the parts }
        for i := 0 to MAX_BUCKETS - 1 do
          if SelHasBucket(i) then DeleteBucket(i);
        for i := 0 to MAX_LABELS - 1 do
          if SelHasLabel(i) then DeleteLabel(i);
        for y := SelY1 to SelY2 do
          for x := SelX1 to SelX2 do
            if SelHasCell(x, y) then EraseCell(x, y);
      end;
  end;
  SelKind := selNone;
end;

procedure SelectCell(gx, gy: Integer);
begin
  SelKind := selCell;
  SelX := gx;
  SelY := gy;
end;

procedure EraseAt(gx, gy: Integer);
var
  b: Integer;
begin
  if EPick(gx, gy) then
  begin
    EErase(gx, gy);
    if (SelKind = selECell) and (SelEX = gx) and (SelEY = gy) then SelKind := selNone;
    Exit;
  end;
  if FPick(gx, gy) then
  begin
    FErase(gx, gy);
    if (SelKind = selFCell) and (SelFX = gx) and (SelFY = gy) then SelKind := selNone;
    Exit;
  end;
  if CellBlocked(gx, gy) then Exit;
  if InGrid(gx, gy) and (Grid[gx, gy].Kind <> ckEmpty) then
  begin
    EraseCell(gx, gy);
    if (SelKind = selCell) and (SelX = gx) and (SelY = gy) then SelKind := selNone;
    Exit;
  end;
  b := BucketPick(MWX, MWY);
  if b >= 0 then
  begin
    DeleteBucket(b);
    if (SelKind = selBucket) and (SelB = b) then SelKind := selNone;
  end;
end;

procedure ResizeAt(gx, gy: Integer);
begin
  if InGrid(gx, gy) and (Grid[gx, gy].Kind <> ckEmpty) and not CellBlocked(gx, gy) then
    Grid[gx, gy].Dia := BrushDia;
end;

procedure PipeTo(gx, gy: Integer);
var
  nx, ny: Integer;
begin
  gx := EnsureRange(gx, 0, GW - 1);
  gy := EnsureRange(gy, 0, GH - 1);
  while (LastCX <> gx) or (LastCY <> gy) do
  begin
    nx := LastCX;
    ny := LastCY;
    if Abs(gx - LastCX) >= Abs(gy - LastCY) then
      nx := nx + Sign(gx - LastCX)
    else
      ny := ny + Sign(gy - LastCY);
    { a pipe stops at parts on a hidden or locked layer }
    if CellBlocked(nx, ny) or CellBlocked(LastCX, LastCY) then Exit;
    if Grid[nx, ny].Kind = ckEmpty then MakePipe(nx, ny, BrushDia);
    ConnectCells(LastCX, LastCY, nx, ny);
    LastCX := nx;
    LastCY := ny;
  end;
end;

procedure CanvasPress(Right: Boolean);
var
  gx, gy, b, L, sx, sy, fr, part, lk, eq, epart: Integer;
  blocked: Boolean;
begin
  if (MWX < 0) or (MWY < 0) then Exit;   { outside the layout when zoomed out }
  gx := Trunc(MWX / CELL);
  gy := Trunc(MWY / CELL);
  if not InGrid(gx, gy) then Exit;
  StopTxt;
  { a click that picks the part to link equipment to }
  if EqPick >= 0 then
  begin
    if (not Right) and Equips[EqPick].Active then
    begin
      if LinkEquipAt(EqPick, MWX, MWY, gx, gy) then
        SetStatus(Format('%s linked to the %s at %d,%d', [Equips[EqPick].Name,
          KindNames[Grid[Equips[EqPick].LinkX, Equips[EqPick].LinkY].Kind], Equips[EqPick].LinkX, Equips[EqPick].LinkY]))
      else
        SetStatus('No part there - link cancelled', True);
      SelKind := selEquip;
      SelEq := EqPick;
    end;
    EqPick := -1;
    Exit;
  end;
  L := LabelAt(MWX, MWY);
  lk := LinkAt(MWX, MWY);
  { links sit on top of everything: the Select tool follows them, the Link tool (or Ctrl) picks them }
  if (not Right) and (not PasteArmed) and (lk >= 0) then
  begin
    if (Tool = tSelect) and ((SDL_GetModState and SDL_KMOD_CTRL) = 0) then
    begin
      StopEditLabel;
      StopEditFrame;
      AppFollowLink(lk);
      Exit;
    end;
    if Tool in [tSelect, tLink] then
    begin
      StopEditLabel;
      StopEditFrame;
      SelKind := selLink;
      SelLk := lk;
      if LastClicks >= 2 then
        StartTxt(5, lk)
      else
      begin
        Drag := dragLink;
        LastMX := MWX;
        LastMY := MWY;
        SetStatus('Link to ' + LinkTargetName(lk) + ' - drag to move, double-click: caption');
      end;
      Exit;
    end;
  end;
  { electrical: the Select tool works switches and buttons; electrical tools place parts and wire }
  if (not Right) and (not PasteArmed) then
  begin
    if (Tool = tSelect) and EPick(gx, gy) and (L < 0) then
    begin
      StopEditLabel;
      StopEditFrame;
      if EIsOperable(EGrid[gx, gy].Kind) and ((SDL_GetModState and SDL_KMOD_CTRL) = 0) then
      begin
        if EIsMomentary(EGrid[gx, gy].Kind) then
        begin
          EPress(gx, gy, True);
          EHX := gx;
          EHY := gy;
          Drag := dragEPress;
          SetStatus(EGrid[gx, gy].Tag + ' pressed');
        end
        else
          SetStatus(EKindNames[EGrid[gx, gy].Kind] + ' ' + EGrid[gx, gy].Tag + ': ' + EOperate(gx, gy));
      end;
      SelectECell(gx, gy);
      Exit;
    end;
    if IsElecTool(Tool) then
    begin
      StopEditLabel;
      StopEditFrame;
      if (EGrid[gx, gy].Kind <> ekNone) and not LayerEditable(EGrid[gx, gy].Layer) then
      begin
        SetStatus('That electrical part is on a hidden or locked layer', True);
        Exit;
      end;
      if Tool <> tElWire then
      begin
        EPlace(gx, gy, ElecToolKind(Tool));
        DefaultETag(gx, gy);
        SelectECell(gx, gy);
        SetStatus('Placed ' + EKindNames[EGrid[gx, gy].Kind] + ' ' + EGrid[gx, gy].Tag + ' - drag on to wire it');
      end
      else if EGrid[gx, gy].Kind = ekNone then
        EWireLine(gx, gy, gx, gy);
      LastCX := gx;
      LastCY := gy;
      Drag := dragEWire;
      Exit;
    end;
  end;  { pneumatic / hydraulic: the Select tool works manual valves and sources; fluid tools place and pipe }
  if (not Right) and (not PasteArmed) then
  begin
    if (Tool = tSelect) and FPick(gx, gy) and (L < 0) then
    begin
      StopEditLabel;
      StopEditFrame;
      if FOperable(gx, gy) and ((SDL_GetModState and SDL_KMOD_CTRL) = 0) then
      begin
        if FIsValve(FGrid[gx, gy].Kind) and (FGrid[gx, gy].Act = 1) then
        begin
          FPress(gx, gy, True);
          FHX := gx;
          FHY := gy;
          Drag := dragFPress;
          SetStatus(FGrid[gx, gy].Tag + ' pressed');
        end
        else
          SetStatus(FKindNames[FGrid[gx, gy].Kind] + ' ' + FGrid[gx, gy].Tag + ': ' + FOperate(gx, gy));
      end;
      SelectFCell(gx, gy);
      Exit;
    end;
    if IsFluidTool(Tool) then
    begin
      StopEditLabel;
      StopEditFrame;
      if (FGrid[gx, gy].Kind <> fkNone) and not LayerEditable(FGrid[gx, gy].Layer) then
      begin
        SetStatus('That fluid power part is on a hidden or locked layer', True);
        Exit;
      end;
      if Tool <> tFlLine then
      begin
        FPlace(gx, gy, TFKind(Ord(Tool) - Ord(tFlLine) + 1));
        DefaultFTag(gx, gy);
        SelectFCell(gx, gy);
        SetStatus('Placed ' + FKindNames[FGrid[gx, gy].Kind] + ' ' + FGrid[gx, gy].Tag + ' - drag on to pipe it');
      end
      else if FGrid[gx, gy].Kind = fkNone then
        FLineRun(gx, gy, gx, gy);
      LastCX := gx;
      LastCY := gy;
      Drag := dragFLine;
      Exit;
    end;
  end;  blocked := CellBlocked(gx, gy);
  { equipment: select / move / resize, double-click runs or stops it }
  eq := EquipPick(MWX, MWY, gx, gy, epart);
  if L >= 0 then eq := -1;
  if (not Right) and (not PasteArmed) and (eq >= 0) and ((Tool = tSelect) or (Tool >= tEqMotor)) then
  begin
    StopEditLabel;
    StopEditFrame;
    SelKind := selEquip;
    SelEq := eq;
    if (LastClicks >= 2) and (EquipActuated(Equips[eq].Kind) or (Equips[eq].Kind in [EQ_LAMP, EQ_RAIN, EQ_FIRE, EQ_SEQUENCE])) then
      ToggleEquip(eq)
    else
    begin
      if epart = 1 then Drag := dragEqSize else Drag := dragEqMove;
      LastMX := MWX;
      LastMY := MWY;
    end;
    Exit;
  end;
  if (not Right) and (not PasteArmed) and (Tool >= tEqMotor) and (Tool <= tEqChiller) then
  begin
    StopEditLabel;
    StopEditFrame;
    eq := AddEquip(Ord(Tool) - Ord(tEqMotor), SnapCell(MWX), SnapCell(MWY));
    if eq < 0 then
      SetStatus(Format('Too much equipment on this page (max %d)', [MAX_EQUIP]), True)
    else
    begin
      { put on a device (or on a silo / hopper for a silo bin) it links to it }
      if (EquipActuated(Equips[eq].Kind) and (Grid[gx, gy].Kind > ckPipe) and not blocked) or
        ((Equips[eq].Kind in [EQ_HEATER, EQ_PUMP, EQ_HEATEX]) and (Grid[gx, gy].Kind = ckPipe) and not blocked) or
        ((Equips[eq].Kind = EQ_SILO) and (StoreAt(MWX, MWY, sx, sy) or IsStore(Grid[gx, gy].Kind))) then
        LinkEquipAt(eq, MWX, MWY, gx, gy);
      SelKind := selEquip;
      SelEq := eq;
      SetStatus('Added ' + Equips[eq].Name + ' - ' + EquipLinkText(eq));
    end;
    Exit;
  end;
  if (not Right) and (not PasteArmed) and (Tool = tLink) then
  begin
    StopEditLabel;
    StopEditFrame;
    lk := NewLinkAt(SnapCell(MWX), SnapCell(MWY));
    if lk < 0 then
      SetStatus(Format('Too many links on this page (max %d)', [MAX_LINKS]), True)
    else
    begin
      SelKind := selLink;
      SelLk := lk;
      SetStatus('Link to ' + LinkTargetName(lk) + ' - pick its target in Properties');
    end;
    Exit;
  end;
  { clicking anywhere but the label being typed into finishes it }
  if (EditLabel >= 0) and (L <> EditLabel) then StopEditLabel;
  fr := FrameAt(MWX, MWY, part);
  if (EditFrame >= 0) and (fr <> EditFrame) then StopEditFrame;
  { a frame's title / outline / corner (labels on top of it come first) }
  if (not Right) and (not PasteArmed) and (Tool in [tSelect, tFrame]) and (L < 0) and (fr >= 0) then
  begin
    if (part = 0) and (LastClicks >= 2) then
      StartEditFrame(fr)
    else
    begin
      SelKind := selFrame;
      SelFr := fr;
      FrDrag := fr;
      FrX0 := MWX;
      FrY0 := MWY;
      FrDX := 0;
      FrDY := 0;
      if part = 1 then Drag := dragFrameSize else Drag := dragFrameMove;
    end;
    Exit;
  end;
  if (not Right) and (not PasteArmed) and (Tool = tFrame) then
  begin
    { drag out a new frame }
    Drag := dragFrameNew;
    FrX0 := MWX;
    FrY0 := MWY;
    FrX1 := MWX;
    FrY1 := MWY;
    Exit;
  end;
  if (not Right) and (not PasteArmed) and (Tool in [tSelect, tLabel, tLabelDate, tLabelTime]) and (L >= 0) then
  begin
    if (Tool = tLabel) or (LastClicks >= 2) then
      StartEditLabel(L)
    else if (SelKind = selMulti) and SelHasLabel(L) then
      StartMove(gx, gy, -1)
    else if EditLabel <> L then
    begin
      SelKind := selLabel;
      SelL := L;
      Drag := dragLabel;
      LastMX := MWX;
      LastMY := MWY;
    end;
    Exit;
  end;
  if (not Right) and (not PasteArmed) and (Tool = tLabel) then
  begin
    L := AddLabel(MWX, MWY, '');
    if L >= 0 then StartEditLabel(L)
    else SetStatus(Format('Too many labels (max %d)', [MAX_LABELS]), True);
    Exit;
  end;
  if (not Right) and (not PasteArmed) and (Tool in [tLabelDate, tLabelTime]) then
  begin
    if Tool = tLabelDate then L := AddClockLabel(MWX, MWY, LBL_DATE) else L := AddClockLabel(MWX, MWY, LBL_TIME);
    if L < 0 then
      SetStatus(Format('Too many labels (max %d)', [MAX_LABELS]), True)
    else
    begin
      SelKind := selLabel;
      SelL := L;
      SetStatus('Pick or type its format in Properties');
    end;
    Exit;
  end;
  if PasteArmed then
  begin
    if Right then
    begin
      PasteArmed := False;
      SetStatus('Paste cancelled');
    end
    else
      PlacePaste(gx, gy);
    Exit;
  end;
  blocked := CellBlocked(gx, gy);
  if Right then
  begin
    { decided on release: no movement = popup menu, moving = erase drag }
    RightPending := True;
    RCellX := gx;
    RCellY := gy;
    Exit;
  end;
  if blocked and (Tool in [tPipe, tResize, tFeeder, tVFeeder, tHopper, tSilo, tBlower, tSuction, tNozzle, tDrop, tCheck,
    tValve2, tValve3, tValve4]) then
  begin
    SetStatus('That part is on a hidden or locked layer (Page & Layer panel)', True);
    Exit;
  end;
  case Tool of
    tSelect:
      begin
        b := BucketPick(MWX, MWY);
        if (Grid[gx, gy].Kind <> ckEmpty) and not blocked then
        begin
          { press on a part: select it (unless it is already in the selection),
            then dragging moves the whole selection }
          if not SelHasCell(gx, gy) then SelectCell(gx, gy);
          StartMove(gx, gy, -1);
        end
        else if StoreAt(MWX, MWY, sx, sy) then
        begin
          { the body of a silo / funnel of a hopper selects (and drags) it }
          if not SelHasCell(sx, sy) then SelectCell(sx, sy);
          StartMove(gx, gy, -1);
        end
        else if (b >= 0) and (SelKind = selMulti) and SelHasBucket(b) then
          StartMove(gx, gy, b)
        else if b >= 0 then
        begin
          SelKind := selBucket;
          SelB := b;
          Drag := dragBucket;
          LastMX := MWX;
          LastMY := MWY;
        end
        else
        begin
          { empty space: drag a box to select several parts }
          SelKind := selNone;
          Drag := dragBox;
          BoxX0 := MWX;
          BoxY0 := MWY;
          BoxX1 := MWX;
          BoxY1 := MWY;
        end;
      end;
    tPipe:
      begin
        if Grid[gx, gy].Kind = ckEmpty then MakePipe(gx, gy, BrushDia);
        LastCX := gx;
        LastCY := gy;
        Drag := dragPipe;
      end;
    tResize:
      begin
        ResizeAt(gx, gy);
        Drag := dragResize;
      end;
    tErase:
      begin
        EraseAt(gx, gy);
        Drag := dragErase;
      end;
    tFeeder, tVFeeder, tHopper, tSilo, tBlower, tSuction, tNozzle, tDrop, tCheck, tValve2, tValve3, tValve4:
      begin
        if Grid[gx, gy].Kind = ckEmpty then MakePipe(gx, gy, BrushDia);
        if Grid[gx, gy].Kind <> ToolKinds[Tool] then SetKind(gx, gy, ToolKinds[Tool]);
        SelectCell(gx, gy);
        { keep dragging to pipe out of the new device }
        LastCX := gx;
        LastCY := gy;
        Drag := dragPipe;
      end;
    tBucket:
      begin
        b := AddBucket(MWX, MWY, 140, 100);
        if b >= 0 then
        begin
          SelKind := selBucket;
          SelB := b;
        end;
      end;
  end;
end;

procedure CanvasMotion;
var
  gx, gy: Integer;
begin
  gx := EnsureRange(Trunc(MWX / CELL), 0, GW - 1);
  gy := EnsureRange(Trunc(MWY / CELL), 0, GH - 1);
  case Drag of
    dragPipe:
      if (gx <> LastCX) or (gy <> LastCY) then PipeTo(gx, gy);
    dragResize: ResizeAt(gx, gy);
    dragErase: EraseAt(gx, gy);
    dragBucket:
      begin
        MoveBucket(SelB, MWX - LastMX, MWY - LastMY);
        LastMX := MWX;
        LastMY := MWY;
      end;
    dragBox:
      begin
        BoxX1 := fclamp(MWX, 0, CANVAS_W - 1);
        BoxY1 := fclamp(MWY, 0, CANVAS_H - 1);
      end;
    dragMove: UpdateMove;
    dragFrameNew:
      begin
        FrX1 := fclamp(MWX, 0, CANVAS_W);
        FrY1 := fclamp(MWY, 0, CANVAS_H);
      end;
    dragFrameMove: UpdateFrameMove;
    dragFrameSize: UpdateFrameSize;
    dragEWire:
      if (gx <> LastCX) or (gy <> LastCY) then EWireTo(gx, gy);
    dragFLine:
      if (gx <> LastCX) or (gy <> LastCY) then FLineTo(gx, gy);
    dragEqMove:
      if (SelKind = selEquip) and Equips[SelEq].Active then
      begin
        Equips[SelEq].X := fclamp(Equips[SelEq].X + MWX - LastMX, 0, CANVAS_W - Equips[SelEq].W);
        Equips[SelEq].Y := fclamp(Equips[SelEq].Y + MWY - LastMY, 0, CANVAS_H - Equips[SelEq].H);
        LastMX := MWX;
        LastMY := MWY;
      end;
    dragEqSize:
      if (SelKind = selEquip) and Equips[SelEq].Active then
      begin
        Equips[SelEq].W := fclamp(Round(MWX - Equips[SelEq].X), 12, CANVAS_W - Equips[SelEq].X);
        Equips[SelEq].H := fclamp(Round(MWY - Equips[SelEq].Y), 12, CANVAS_H - Equips[SelEq].Y);
      end;
    dragLink:
      if (SelKind = selLink) and Links[SelLk].Active then
      begin
        Links[SelLk].X := fclamp(Links[SelLk].X + MWX - LastMX, 0, CANVAS_W - 24);
        Links[SelLk].Y := fclamp(Links[SelLk].Y + MWY - LastMY, 0, CANVAS_H - 18);
        LastMX := MWX;
        LastMY := MWY;
      end;
    dragLabel:
      if (SelKind = selLabel) and Labels[SelL].Active then
      begin
        Labels[SelL].X := fclamp(Labels[SelL].X + MWX - LastMX, 0, CANVAS_W - 16);
        Labels[SelL].Y := fclamp(Labels[SelL].Y + MWY - LastMY, 0, CANVAS_H - 12);
        LastMX := MWX;
        LastMY := MWY;
      end;
  end;
end;

procedure FinishBox;
var
  np, nb: Integer;
begin
  if (Abs(BoxX1 - BoxX0) < 4) and (Abs(BoxY1 - BoxY0) < 4) then Exit;   { just a click }
  SelectBox(Trunc(fmin(BoxX0, BoxX1) / CELL), Trunc(fmin(BoxY0, BoxY1) / CELL),
    Trunc(fmax(BoxX0, BoxX1) / CELL), Trunc(fmax(BoxY0, BoxY1) / CELL));
  CountSelection(np, nb);
  if SelKind <> selNone then
    SetStatus(Format('Selected %d parts, %d buckets - right-click for Cut/Copy', [np, nb]));
end;

{ ---------------------------------------------------------------- right-click popup }

const
  POPUP_W = 170;
  CanvasLabels: array[0..6] of string = ('Cut', 'Copy', 'Paste here', 'Delete', 'Rotate', 'Edit text',
    'Focus properties');
  CanvasKeys: array[0..6] of string = ('Ctrl+X', 'Ctrl+C', 'Ctrl+V', 'Del', 'R', '2x click', '');
  PanelLabels: array[0..3] of string = ('Right embed', 'Left embed', 'Float', 'Hide');

function PopupCount: Integer;
begin
  if PopupWin >= 0 then Result := 4 else Result := 7;
end;

function PopupH: Single;
begin
  Result := PopupCount * 20 + 8;
end;

procedure PlacePopup;
begin
  OpenMenu := -1;
  PopupX := fclamp(MX, -LeftW, SceneRight - POPUP_W - 4);
  PopupY := fclamp(MY, 0, WIN_H - PopupH - 4);
  PopupOpen := True;
  PopupClick := False;
end;

{ right-click on panel i: where should it live }
procedure OpenPanelPopup(i: Integer);
begin
  PopupWin := i;
  PlacePopup;
end;

procedure OpenPopup;
var
  gx, gy, b, L, sx, sy, fr, part: Integer;
begin
  gx := EnsureRange(Trunc(MWX / CELL), 0, GW - 1);
  gy := EnsureRange(Trunc(MWY / CELL), 0, GH - 1);
  { right-clicking something outside the current selection selects it first }
  if not ((SelKind = selMulti) and (gx >= SelX1) and (gx <= SelX2) and (gy >= SelY1) and (gy <= SelY2)) then
  begin
    b := BucketPick(MWX, MWY);
    L := LabelAt(MWX, MWY);
    fr := FrameAt(MWX, MWY, part);
    if LinkAt(MWX, MWY) >= 0 then
    begin
      SelKind := selLink;
      SelLk := LinkAt(MWX, MWY);
    end
    else if (L < 0) and EPick(gx, gy) then
      SelectECell(gx, gy)
    else if (L < 0) and FPick(gx, gy) then
      SelectFCell(gx, gy)
    else if (L < 0) and (EquipPick(MWX, MWY, gx, gy, part) >= 0) then
    begin
      SelKind := selEquip;
      SelEq := EquipPick(MWX, MWY, gx, gy, part);
    end
    else if L >= 0 then
    begin
      if L <> EditLabel then StopEditLabel;
      SelKind := selLabel;
      SelL := L;
    end
    else if fr >= 0 then
    begin
      SelKind := selFrame;
      SelFr := fr;
    end
    else if (Grid[gx, gy].Kind <> ckEmpty) and not CellBlocked(gx, gy) then
      SelectCell(gx, gy)
    else if StoreAt(MWX, MWY, sx, sy) then
      SelectCell(sx, sy)
    else if b >= 0 then
    begin
      SelKind := selBucket;
      SelB := b;
    end
    else if not ((SelKind = selCell) and (SelX = gx) and (SelY = gy)) then
      SelKind := selNone;
  end;
  PopupWin := -1;
  PopupGX := gx;
  PopupGY := gy;
  PlacePopup;
end;

procedure DrawPopup;
var
  i, w: Integer;
  y, h: Single;
  en, hot, clicked, chk: Boolean;
  lbl, key: string;
begin
  if not PopupOpen then Exit;
  clicked := PopupClick;
  PopupClick := False;
  h := PopupH;
  w := PopupWin;
  SetCol(0, 0, 0, 90);
  FillR(PopupX + 4, PopupY + 4, POPUP_W, h);
  SetC(Th.MenuBg);
  FillR(PopupX, PopupY, POPUP_W, h);
  SetC(Th.MenuBorder);
  RectR(PopupX, PopupY, POPUP_W, h);
  for i := 0 to PopupCount - 1 do
  begin
    y := PopupY + 4 + i * 20;
    chk := False;
    if w >= 0 then
    begin
      { panel popup: where the panel lives (the current place is ticked) }
      lbl := PanelLabels[i];
      if i = 3 then key := WinKeys[w] else key := '';
      case i of
        0: chk := Wins[w].Visible and WinDocked(w) and (Wins[w].Side = 0);
        1: chk := EmbeddedLeft(w);
        2: chk := Wins[w].Visible and not WinDocked(w);
      end;
      en := not chk;
    end
    else
    begin
      lbl := CanvasLabels[i];
      key := CanvasKeys[i];
      case i of
        2: en := not ClipEmpty;
        5: en := SelKind in [selLabel, selFrame, selLink, selEquip, selECell, selFCell];
        6: en := SelKind in [selCell, selBucket, selLabel, selFrame, selLink, selEquip, selECell, selFCell];
      else
        en := SelKind <> selNone;
      end;
    end;
    hot := en and Inside(PopupX, y, POPUP_W, 20);
    if hot then
    begin
      SetC(Th.MenuHot);
      FillR(PopupX + 2, y, POPUP_W - 4, 20);
    end;
    if chk then
    begin
      SetC(Th.Title);
      FillR(PopupX + 7, y + 7, 6, 6);
    end;
    if not en and not chk then SetC(Th.MenuDisabled) else if hot then SetC(Th.BtnSelText) else SetC(Th.Text);
    TextR(PopupX + 20, y + 6, lbl);
    if hot then SetC(Th.BtnSelText) else SetC(Th.MenuKey);
    TextR(PopupX + POPUP_W - 8 - Length(key) * 8, y + 6, key);
    if clicked and hot then
    begin
      PopupOpen := False;
      if w >= 0 then
        case i of
          0: EmbedWin(w, 0);
          1: EmbedWin(w, 1);
          2: FloatWin(w);
          3: ToggleWin(w);
        end
      else
        case i of
          0: DoCut;
          1: DoCopy;
          2: PlacePaste(PopupGX, PopupGY);
          3: DoDelete;
          4: DoRotate(True);
          5: if SelKind = selFrame then StartEditFrame(SelFr)
             else if SelKind = selLink then StartTxt(5, SelLk)
             else if SelKind = selEquip then StartTxt(6, SelEq)
             else if SelKind = selECell then StartTxt(7, SelEY * GW + SelEX)
             else if SelKind = selFCell then StartTxt(8, SelFY * GW + SelFX)
             else StartEditLabel(SelL);
          6: OpenPin;
        end;
      Exit;
    end;
  end;
  if clicked then PopupOpen := False;   { a click anywhere else closes it }
end;

procedure CanvasWheel(wx, wy, amount: Single);
var
  gx, gy, b, st: Integer;
  c: PCell;
begin
  if (wx < 0) or (wx >= CANVAS_W) or (wy < 0) or (wy >= CANVAS_H) then Exit;
  gx := Trunc(wx / CELL);
  gy := Trunc(wy / CELL);
  if amount > 0 then st := 1 else st := -1;
  WheelIdle := 0;   { a burst of wheel ticks becomes one undo step }
  { the wheel sets a regulator, flow control, relief valve or source }
  if FPick(gx, gy) and (FGrid[gx, gy].Kind in [fkFRL, fkRegulator, fkThrottle, fkRelief, fkCompressor, fkHPump]) then
  begin
    with FGrid[gx, gy] do
    begin
      if Kind = fkThrottle then P1 := fclamp(P1 + st * 5, 2, 100)
      else if FIsHydraulic(Kind) then P1 := fclamp(P1 + st * 5, 0, 250)
      else P1 := fclamp(P1 + st * 0.5, 0, 10);
      SetStatus(Format('%s %s set to %.1f', [FKindNames[Kind], Tag, P1]));
    end;
    SelectFCell(gx, gy);
    Exit;
  end;
  { the wheel turns a potentiometer }
  if EPick(gx, gy) and (EGrid[gx, gy].Kind = ekPot) then
  begin
    EGrid[gx, gy].P1 := fclamp(EGrid[gx, gy].P1 + st * 5, 0, 100);
    SelectECell(gx, gy);
    SetStatus(Format('%s at %.0f%%', [EGrid[gx, gy].Tag, EGrid[gx, gy].P1]));
    Exit;
  end;
  if CellBlocked(gx, gy) then Exit;
  if InGrid(gx, gy) and (Grid[gx, gy].Kind <> ckEmpty) then
  begin
    c := @Grid[gx, gy];
    case c^.Kind of
      ckPipe: c^.Dia := EnsureRange(c^.Dia + st, 1, MAX_DIA);
      ckBlower, ckSuction, ckNozzle, ckDrop: c^.Strength := fclamp(c^.Strength + st * 5, 0, 100);
      ckSource: c^.Feed := fclamp(c^.Feed + st * 5, 0, 100);
      ckValve2, ckValve3, ckValve4, ckCheck: RotateCell(gx, gy);
    end;
    SelectCell(gx, gy);
    Exit;
  end;
  b := BucketPick(wx, wy);
  if b >= 0 then
    ResizeBucket(b, fclamp(Buckets[b].W + st * 10, 40, 400), Buckets[b].H);
end;

procedure HandleKey(key: UInt32; Mods: UInt16);
begin
  if (Mods and SDL_KMOD_CTRL) <> 0 then
  begin
    case key of
      Ord('s'): if (Mods and SDL_KMOD_SHIFT) <> 0 then DoSaveAs else DoSave;
      Ord('o'): DoOpen;
      Ord('n'): DoNew;
      Ord('q'): QuitRequested := True;
      Ord('z'): if (Mods and SDL_KMOD_SHIFT) <> 0 then DoRedo else DoUndo;
      Ord('y'): DoRedo;
      SDLK_EQUALS, SDLK_KP_PLUS: ZoomAt(Zoom * 1.25, CANVAS_W / 2, CANVAS_H / 2);
      SDLK_MINUS, SDLK_KP_MINUS: ZoomAt(Zoom / 1.25, CANVAS_W / 2, CANVAS_H / 2);
      SDLK_0: ZoomAt(1, CANVAS_W / 2, CANVAS_H / 2);
      Ord('x'): DoCut;
      Ord('c'): DoCopy;
      Ord('v'):
        { over the canvas Ctrl+V pastes right under the mouse }
        if (not ClipEmpty) and (MX >= 0) and (MX < CANVAS_W) and (MY >= 0) and (MY < CANVAS_H) then
          PlacePaste(Trunc(MWX / CELL), Trunc(MWY / CELL))
        else
          DoPaste;
    end;
    Exit;
  end;
  case key of
    SDLK_SPACE: Running := not Running;
    SDLK_ESCAPE:
      if EqPick >= 0 then
      begin
        EqPick := -1;
        SetStatus('Link cancelled');
      end
      else if ShownPopup >= 0 then
        CloseFramePopup
      else if PopupOpen then
        PopupOpen := False
      else if OpenMenu >= 0 then
        OpenMenu := -1
      else if PasteArmed then
      begin
        PasteArmed := False;
        SetStatus('Paste cancelled');
      end
      else
      begin
        Tool := tSelect;
        SelKind := selNone;
      end;
    SDLK_DELETE, SDLK_BACKSPACE: DeleteSelected;
    SDLK_LEFTBRACKET, SDLK_MINUS: BrushDia := Max(1, BrushDia - 1);
    SDLK_RIGHTBRACKET, SDLK_EQUALS: BrushDia := Min(MAX_DIA, BrushDia + 1);
    Ord('r'): DoRotate((Mods and SDL_KMOD_SHIFT) = 0);
    Ord('p'): ShowPressure := not ShowPressure;
    Ord('g'):
      begin
        GridShow := not GridShow;
        SaveSettings;
      end;
    Ord('a'): ShowAir := not ShowAir;
    Ord('c'): ClearParticles;
    Ord('1'): Tool := tSelect;
    Ord('2'): Tool := tPipe;
    Ord('3'): Tool := tResize;
    Ord('4'): Tool := tErase;
    Ord('5'): Tool := tFeeder;
    Ord('6'): Tool := tBlower;
    Ord('7'): Tool := tSuction;
    Ord('8'): Tool := tNozzle;
    Ord('9'): Tool := tDrop;
    Ord('0'): Tool := tBucket;
    SDLK_F1: ToggleWin(WIN_HELP);
    SDLK_F5: ToggleWin(WIN_STATUS);
    SDLK_LEFT: PanBy(-60 / Zoom, 0);
    SDLK_RIGHT: PanBy(60 / Zoom, 0);
    SDLK_UP: PanBy(0, -60 / Zoom);
    SDLK_DOWN: PanBy(0, 60 / Zoom);
    SDLK_F2: ToggleWin(WIN_TOOLS);
    SDLK_F3: ToggleWin(WIN_SIM);
    SDLK_F4: ToggleWin(WIN_PROPS);
    SDLK_F6: ToggleWin(WIN_PAGES);
    SDLK_F7: ToggleWin(WIN_POPUPS);
    SDLK_F8: ToggleWin(WIN_LAB);
    SDLK_F9: ToggleWin(WIN_SHAPE);
    SDLK_PAGEUP: if CurPage > 0 then AppGoToPage(CurPage - 1);
    SDLK_PAGEDOWN: if CurPage < PageCount - 1 then AppGoToPage(CurPage + 1);
  end;
end;

{ ---------------------------------------------------------------- main loop }

{ a mouse button went down at MX, MY }
procedure MouseDown(Button: Integer);
begin
  if Button = SDL_BUTTON_MIDDLE then
  begin
    { middle-drag pans the canvas }
    if (MX >= 0) and (MX < CANVAS_W) and (MY >= 0) and not InAnyWin(MX, MY) then
    begin
      Panning := True;
      PanLastX := MX;
      PanLastY := MY;
    end;
  end
  else if (Button = SDL_BUTTON_LEFT) and (ShownPopup >= 0) and (OpenMenu < 0) and (not PopupOpen) and
    (MX >= 0) and (MX < CANVAS_W) and (MY >= 0) and (MY < CANVAS_H) and not InAnyWin(MX, MY) then
  begin
    { the frame popup over the canvas: its buttons, or a click beside it closes it }
    if InFramePopup then FPClick := True else CloseFramePopup;
  end
  else if PopupOpen then
  begin
    { the popup takes this click: an item, or closing it }
    if Inside(PopupX, PopupY, POPUP_W, PopupH) then
      PopupClick := True
    else
      PopupOpen := False;
  end
  else if OpenMenu >= 0 then
  begin
    { an open drop-down (it may lie over the canvas) takes the click: DrawMenus
      runs the item under the mouse, or closes the menu when the click is
      elsewhere. Nothing underneath reacts. }
    if Button = SDL_BUTTON_LEFT then
    begin
      MDown := True;
      MPressed := True;
    end
    else
      OpenMenu := -1;
  end
  else if Button = SDL_BUTTON_LEFT then
  begin
    MDown := True;
    MPressed := True;
    if (MX >= 0) and (MX < CANVAS_W) and (MY >= 0) and not InAnyWin(MX, MY) then CanvasPress(False);
  end
  else if Button = SDL_BUTTON_RIGHT then
  begin
    RDown := True;
    if PinAt(MX, MY) >= 0 then
      { a Focus Properties window: nothing }
    else if InAnyWin(MX, MY) then
      OpenPanelPopup(WinAt(MX, MY))   { panel: Right / Left embed, Float, Hide }
    else if (MX >= 0) and (MX < CANVAS_W) and (MY >= 0) then
      CanvasPress(True);
  end;
end;

procedure Render;
var
  pressed, toMenu: Boolean;
  target, k, i, pin: Integer;
  order: array[0..WIN_COUNT - 1] of Integer;
begin
  SetCol(16, 18, 23);
  SDL_RenderClear(Ren);
  DrawCanvas;
  { one click goes to exactly one layer: menus, then the top-most panel window
    under the mouse (or the one being dragged), then the side panel }
  pressed := MPressed;
  toMenu := (OpenMenu >= 0) or InMenuBar(MX, MY);
  target := -1;
  pin := -1;
  if not toMenu then
  begin
    for i := 0 to High(Pins) do
      if Pins[i].Dragging then pin := i;
    if pin < 0 then pin := PinAt(MX, MY);
    for i := 0 to WIN_COUNT - 1 do
      if Wins[i].Dragging then target := i;
    if (target < 0) and (pin < 0) then target := WinAt(MX, MY);
    if target >= 0 then pin := -1;
  end;
  MPressed := pressed and not toMenu and (target < 0) and (pin < 0);
  DrawPanel;
  order := WinOrder;   { a click may bring a window to the front while drawing }
  for k := 0 to WIN_COUNT - 1 do
  begin
    i := order[k];
    MPressed := pressed and (i = target);
    DrawWin(i);
  end;
  DrawPins(pressed and not toMenu, pin);
  MPressed := pressed and toMenu;
  DrawMenus(MPressed);
  MPressed := pressed;
  DrawPopup;
end;

procedure WriteShotStats(const FileName: string);
var
  f: TextFile;
  i, inPipe, onFloor, x, y: Integer;
  c: PCell;
  cnt: array[TMat] of Integer;
  m: TMat;
begin
  for m := Low(TMat) to High(TMat) do cnt[m] := 0;
  inPipe := 0;
  onFloor := 0;
  for i := 0 to NPart - 1 do
  begin
    Inc(cnt[Parts[i].Mat]);
    if Parts[i].InPipe then Inc(inPipe)
    else if (Parts[i].Mat <> mAir) and (Parts[i].Bucket < 0) and (Parts[i].Y > FLOOR_Y - 15) then Inc(onFloor);
  end;
  AssignFile(f, FileName);
  Rewrite(f);
  WriteLn(f, 'sim ms/frame ', ShotMsPerFrame: 0: 2);
  WriteLn(f, 'on floor outside buckets ', onFloor);
  WriteLn(f, 'particles ', NPart, ' inPipe ', inPipe, ' air ', NAir, ' limit ', LimitHit);
  for m := Low(TMat) to High(TMat) do
    WriteLn(f, '  ', MatP[m].Name, ' ', cnt[m]);
  for i := 0 to MAX_BUCKETS - 1 do
    if Buckets[i].Active then
      WriteLn(f, 'bucket ', i + 1, ' count ', Buckets[i].Count, ' fill ', BucketFill(i): 0: 2,
        ' spilled ', Buckets[i].Spilled);
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @Grid[x, y];
      if c^.Kind = ckSource then
        WriteLn(f, Format('tank %d,%d stock W%.0f O%.0f F%.0f S%.0f', [x, y, c^.Stock[mWater],
          c^.Stock[mOil], c^.Stock[mFluff], c^.Stock[mSand]]))
      else if c^.Mouth >= 0 then
        WriteLn(f, Format('%s %d,%d mouth flow %.3f  speed %.0f', [KindNames[c^.Kind], x, y,
          c^.F[c^.Mouth], CellSpeed(x, y)]));
    end;
  CloseFile(f);
end;

{ what the program shows when it starts: a new, empty layout. Test and
  screenshot runs start from the demo instead, which their checks rely on. }
procedure LoadStartupLayout(Testing: Boolean);
begin
  PagesReset;
  if Testing then
  begin
    LoadDemo;
    LayoutName := 'Demo';
  end
  else
  begin
    ClearAll;
    GravityScale := 1;
    LayoutName := '';
    SetStatus('New layout - draw pipes, or pick one from the Examples menu');
  end;
  CurrentFile := '';
  SelKind := selNone;
  UpdateTitle;
  HistReset;
end;

{ --selftest <report.txt> : exercises undo/redo, cut/copy/paste and themes }
procedure RunSelfTest(const FileName: string);
var
  f: TextFile;
  fails, i, b, np, nb, k, lk, lk2, cx, cy: Integer;
  bx, by, fw, fh: Single;
  err: string;
  tf: TextFile;
  b2: Boolean;

  { open menu m and click item i through the real mouse path; m = -1 clicks the Edit button on the bar }
  procedure ClickMenu(m, i: Integer);
  begin
    if m < 0 then
    begin
      OpenMenu := -1;
      MX := MenuBarX(1) + 10;
      MY := -MENU_H + 10;
    end
    else
    begin
      OpenMenu := m;
      BuildMenu(m);
      MX := MenuX(m) + 40;
      MY := ItemY(i) + 10;
    end;
    MouseDown(SDL_BUTTON_LEFT);
    Render;
    MDown := False;
    MPressed := False;
    ActiveId := 0;
  end;

  { click item i of the sub-menu of item Item of menu m through the real mouse path }
  procedure ClickSub(m, Item, i: Integer);
  begin
    OpenMenu := m;
    BuildMenu(m);
    SubOpen := Item;
    BuildSub(m);
    MX := SubX(m) + 40;
    BuildSub(m);
    MY := SubItemY(i) + 10;
    MouseDown(SDL_BUTTON_LEFT);
    Render;
    MDown := False;
    MPressed := False;
  end;

  { click item k of View > Grid > through the real mouse path }
  procedure ClickGrid(k: Integer);
  begin
    OpenMenu := MENU_VIEW;
    BuildMenu(MENU_VIEW);
    SubOpen := VIEW_GRID_ITEM;
    BuildGridMenu;
    MX := SubX(MENU_VIEW) + 40;
    MY := SubItemY(k) + 10;
    MouseDown(SDL_BUTTON_LEFT);
    Render;
    MDown := False;
    MPressed := False;
  end;

  procedure Check(const What: string; Ok: Boolean);
  begin
    if Ok then WriteLn(f, 'PASS  ', What)
    else
    begin
      WriteLn(f, 'FAIL  ', What);
      Inc(fails);
    end;
  end;

begin
  fails := 0;
  AssignFile(f, FileName);
  Rewrite(f);

  { undo / redo of an erase }
  Check('demo: no undo at start', not CanUndo);
  EraseCell(15, 3);
  HistCheck;
  Check('erase makes an undo step', CanUndo and not CanRedo);
  DoUndo;
  Check('undo restores the erased pipe', (Grid[15, 3].Kind = ckPipe) and (Grid[15, 3].Dia = 1));
  Check('undo restores its joints', Connected(15, 3, 0) and Connected(15, 3, 2) and Connected(14, 3, 0));
  Check('redo is available', CanRedo);
  DoRedo;
  Check('redo erases it again', (Grid[15, 3].Kind = ckEmpty) and not Connected(14, 3, 0));
  DoUndo;

  { several steps, then a new edit clears redo }
  Grid[6, 3].Strength := 90;
  HistCheck;
  bx := Buckets[0].X;
  by := Buckets[0].Y;
  MoveBucket(0, -40, -30);
  HistCheck;
  DoUndo;
  Check('undo bucket move', (Buckets[0].X = bx) and (Buckets[0].Y = by));
  DoUndo;
  Check('undo blower strength', Grid[6, 3].Strength = 60);
  Check('two redo steps queued', CanRedo);
  Grid[6, 3].Dir := 2;
  HistCheck;
  Check('new edit clears redo', not CanRedo);
  DoUndo;
  Check('undo blower direction', Grid[6, 3].Dir = 0);

  { tank contents are not rolled back }
  Grid[2, 3].Stock[mWater] := 123;
  EraseCell(12, 3);
  HistCheck;
  DoUndo;
  Check('undo keeps tank contents', (Grid[2, 3].Stock[mWater] = 123) and (Grid[12, 3].Kind = ckPipe));

  { cut + paste a blower back in place }
  SelectCell(6, 3);
  DoCut;
  Check('cut removes the blower', (Grid[6, 3].Kind = ckEmpty) and not Connected(5, 3, 0));
  HistCheck;
  PlacePaste(6, 3);
  Check('paste puts it back', (Grid[6, 3].Kind = ckBlower) and (Grid[6, 3].Strength = 60) and (Grid[6, 3].Dir = 0));
  Check('paste rejoins both sides', Connected(6, 3, 0) and Connected(6, 3, 2));
  HistCheck;
  DoUndo;
  Check('undo the paste', Grid[6, 3].Kind = ckEmpty);
  DoUndo;
  Check('undo the cut', (Grid[6, 3].Kind = ckBlower) and Connected(5, 3, 0));

  { copy a 1-way pipe and paste it into an existing pipe }
  SelectCell(30, 8);
  DoCopy;
  PlacePaste(27, 8);
  Check('paste into a pipe keeps its joints', (Grid[27, 8].Kind = ckCheck) and (Grid[27, 8].Dir = 2) and
    Connected(27, 8, 0) and Connected(27, 8, 2));
  Check('original stays after copy', Grid[30, 8].Kind = ckCheck);

  { copy + paste a bucket }
  SelKind := selBucket;
  SelB := 1;
  DoCopy;
  PlacePaste(25, 5);
  b := SelB;
  Check('bucket pasted', (SelKind = selBucket) and (b <> 1) and Buckets[b].Active and
    (Buckets[b].W = Buckets[1].W) and (Buckets[b].H = Buckets[1].H));
  HistCheck;
  DoUndo;
  Check('undo bucket paste', not Buckets[b].Active);

  { box selection: cut / undo / copy / paste a run of 5 pipes (sizes 1,1,5,5,5) }
  SelectBox(14, 3, 18, 3);
  CountSelection(np, nb);
  Check('box selects 5 parts', (SelKind = selMulti) and (np = 5) and (nb = 0));
  DoCut;
  HistCheck;
  Check('box cut empties the cells', (Grid[14, 3].Kind = ckEmpty) and (Grid[18, 3].Kind = ckEmpty) and
    not Connected(13, 3, 0) and not Connected(19, 3, 2));
  Check('clipboard holds the block', (Clip.W = 5) and (Clip.H = 1) and (Clip.Parts = 5));
  DoUndo;
  Check('undo the box cut', (Grid[16, 3].Kind = ckPipe) and Connected(13, 3, 0) and Connected(18, 3, 0));
  SelectBox(14, 3, 18, 3);
  DoCopy;
  PlacePaste(2, 14);
  Check('block pasted with sizes', (Grid[2, 14].Dia = 1) and (Grid[3, 14].Dia = 1) and (Grid[4, 14].Dia = 5) and
    (Grid[6, 14].Dia = 5));
  Check('block keeps inner joints', Connected(2, 14, 0) and Connected(3, 14, 0) and Connected(5, 14, 0));
  Check('block edges join nothing', not Connected(6, 14, 0) and not Connected(2, 14, 2));
  CountSelection(np, nb);
  Check('pasted block is selected', (SelKind = selMulti) and (np = 5));

  { popup menu: right-click inside the selection keeps it; Copy from the popup }
  ClearClip;
  MX := 4 * CELL + HALF;
  MY := 14 * CELL + HALF;
  OpenPopup;
  Check('popup keeps box selection', PopupOpen and (SelKind = selMulti));
  MX := PopupX + 20;
  MY := PopupY + 4 + 1 * 20 + 10;   { item 1 = Copy }
  PopupClick := True;
  DrawPopup;
  Check('popup Copy fills clipboard', (not PopupOpen) and (Clip.Parts = 5));
  MX := 30 * CELL + HALF;
  MY := 18 * CELL + HALF;
  OpenPopup;
  Check('popup on empty space clears selection', PopupOpen and (SelKind = selNone));
  MX := PopupX + 20;
  MY := PopupY + 4 + 2 * 20 + 10;   { item 2 = Paste here }
  PopupClick := True;
  DrawPopup;
  Check('popup Paste here', (Grid[30, 18].Kind = ckPipe) and (Grid[34, 18].Dia = 5) and Connected(30, 18, 0));

  { box with a bucket inside: parts and the bucket are copied together }
  nb := 0;
  for i := 0 to MAX_BUCKETS - 1 do
    if Buckets[i].Active then Inc(nb);
  SelectBox(9, 22, 13, 33);
  CountSelection(np, b);
  Check('box picks drop outlet and bucket', (SelKind = selMulti) and (np >= 2) and (b = 1));
  DoCopy;
  PlacePaste(28, 22);
  np := 0;
  for i := 0 to MAX_BUCKETS - 1 do
    if Buckets[i].Active then Inc(np);
  Check('pasted bucket with the parts', (np = nb + 1) and (Grid[30, 23].Kind = ckDrop));

  { drag-move a single part, then undo it }
  HistCheck;   { the app commits after every gesture; earlier test edits become their own step }
  SelectCell(6, 3);
  StartMove(6, 3, -1);
  MX := 6 * CELL + HALF;
  MY := 5 * CELL + HALF;
  UpdateMove;
  FinishMove;
  Drag := dragNone;
  Check('move one part', (Grid[6, 5].Kind = ckBlower) and (Grid[6, 3].Kind = ckEmpty) and
    (SelKind = selCell) and (SelX = 6) and (SelY = 5));
  HistCheck;
  DoUndo;
  Check('undo the move', (Grid[6, 3].Kind = ckBlower) and (Grid[6, 5].Kind = ckEmpty) and Connected(6, 3, 0));

  { drag-move a box selection two rows down: joints inside it survive }
  SelectBox(2, 14, 6, 14);
  StartMove(4, 14, -1);
  MX := 4 * CELL + HALF;
  MY := 16 * CELL + HALF;
  UpdateMove;
  FinishMove;
  Drag := dragNone;
  CountSelection(np, nb);
  Check('move a group', (Grid[2, 14].Kind = ckEmpty) and (Grid[2, 16].Dia = 1) and (Grid[6, 16].Dia = 5) and
    Connected(2, 16, 0) and Connected(5, 16, 0) and (SelKind = selMulti) and (np = 5));  { the block may not leave the grid }
  StartMove(4, 16, -1);
  MX := 4 * CELL + HALF;
  MY := 60 * CELL;
  UpdateMove;
  Check('move is clamped to the grid', MoveY1 + MoveDY + MoveBuf.H - 1 = GH - 1);
  MX := 4 * CELL + HALF;
  MY := 16 * CELL + HALF;
  UpdateMove;
  { a click (no movement) inside a box selection picks that one part }
  FinishMove;
  Drag := dragNone;
  Check('click in a box picks one part', (SelKind = selCell) and (SelX = 4) and (SelY = 16));

  { properties window toggles and docking }
  DockProperties;
  Check('properties docked and visible', Wins[WIN_PROPS].Visible and WinDocked(WIN_PROPS));
  ToggleProperties;
  Check('F4 hides properties', not Wins[WIN_PROPS].Visible);
  Wins[WIN_PROPS].X := 500;
  Wins[WIN_PROPS].Y := 200;
  ToggleProperties;
  Check('properties float where they were', Wins[WIN_PROPS].Visible and not WinDocked(WIN_PROPS) and (WinAt(510, 250) = WIN_PROPS));
  DockProperties;

  { tool and simulation panels }
  Check('default tool is Select', Tool = tSelect);
  ToggleWin(WIN_TOOLS);
  ToggleWin(WIN_SIM);
  Check('F2/F3 hide tool and simulation', not Wins[WIN_TOOLS].Visible and not Wins[WIN_SIM].Visible);
  Check('hidden panels take no clicks', WinAt(PANEL_X + 50, 100) = -1);
  Wins[WIN_SIM].X := 300;
  Wins[WIN_SIM].Y := 300;
  ToggleWin(WIN_SIM);
  Check('floating simulation panel on top', (WinAt(320, 320) = WIN_SIM) and InAnyWin(320, 320));
  for i := 0 to WIN_CORE - 1 do DockWin(i);
  Check('dock all panels', WinDocked(0) and WinDocked(1) and WinDocked(2) and Wins[0].Visible and
    Wins[1].Visible and Wins[2].Visible);

  { rotate a box: the 5-pipe run on row 16 (cols 2-6) turns into a column }
  HistCheck;
  SelectBox(2, 16, 6, 16);
  DoRotate(True);
  CountSelection(np, nb);
  Check('rotate right turns a row into a column', (Grid[4, 14].Kind = ckPipe) and (Grid[4, 18].Kind = ckPipe) and
    (Grid[2, 16].Kind = ckEmpty) and (np = 5));
  Check('rotated joints are vertical', Connected(4, 14, 1) and Connected(4, 17, 1) and not Connected(4, 16, 0));
  Check('rotated sizes follow', (Grid[4, 14].Dia = 1) and (Grid[4, 15].Dia = 1) and (Grid[4, 18].Dia = 5));
  HistCheck;   { each key press is its own undo step }
  DoRotate(False);
  Check('rotate left turns it back', (Grid[2, 16].Dia = 1) and (Grid[6, 16].Dia = 5) and Connected(2, 16, 0) and
    (Grid[4, 14].Kind = ckEmpty));
  HistCheck;
  DoUndo;
  Check('undo the left turn', (Grid[4, 14].Kind = ckPipe) and (Grid[2, 16].Kind = ckEmpty));
  DoUndo;
  Check('undo the right turn', (Grid[2, 16].Dia = 1) and Connected(2, 16, 0) and (Grid[4, 14].Kind = ckEmpty));

  { a box with a one-way pipe: its arrow turns with the block }
  SelectBox(29, 8, 31, 8);
  CountSelection(np, nb);
  DoRotate(True);
  Check('1-way pipe arrow turns', (Grid[30, 8].Kind = ckCheck) and (Grid[30, 8].Dir = 3) and
    (Grid[30, 7].Kind = ckPipe) and (Grid[30, 9].Kind = ckPipe) and (Grid[29, 8].Kind = ckEmpty));
  HistCheck;
  DoUndo;
  Check('undo the arrow turn', (Grid[30, 8].Kind = ckCheck) and (Grid[30, 8].Dir = 2));

  { single device: R turns its direction in place }
  SelectCell(6, 3);
  DoRotate(True);
  Check('R turns a single blower', (Grid[6, 3].Kind = ckBlower) and (Grid[6, 3].Dir = 2));
  DoRotate(True);
  Check('R again turns it back', Grid[6, 3].Dir = 0);

  { panel popup actions: left / right embed, float }
  Wins[WIN_PAGES].Visible := False;
  Wins[WIN_POPUPS].Visible := False;
  ApplyLayout;
  EmbedWin(WIN_PROPS, 1);
  Check('left embed opens a left column', (LeftW = PANEL_W) and (OX = PANEL_W) and EmbeddedLeft(WIN_PROPS) and
    (WinAt(-200, 400) = WIN_PROPS));
  Check('canvas keeps its own coordinates', (Trunc((6 * CELL + HALF) / CELL) = 6) and not InAnyWin(6 * CELL, 100));
  MX := -200;
  MY := 400;
  OpenPanelPopup(WIN_PROPS);
  Check('panel popup opens for that panel', PopupOpen and (PopupWin = WIN_PROPS) and (PopupCount = 4));
  MX := PopupX + 20;
  MY := PopupY + 4 + 0 * 20 + 10;   { item 0 = Right embed }
  PopupClick := True;
  DrawPopup;
  Check('Right embed from the popup', (not PopupOpen) and (Wins[WIN_PROPS].Side = 0) and WinDocked(WIN_PROPS) and
    (LeftW = 0) and (OX = 0));
  FloatWin(WIN_SIM);
  Check('Float undocks the panel', Wins[WIN_SIM].Visible and not WinDocked(WIN_SIM));
  ToggleWin(WIN_TOOLS);
  EmbedWin(WIN_TOOLS, 1);
  Check('embedding shows a hidden panel', Wins[WIN_TOOLS].Visible and EmbeddedLeft(WIN_TOOLS));
  ToggleWin(WIN_TOOLS);
  Check('hiding the only left panel closes the column', LeftW = 0);
  ToggleWin(WIN_TOOLS);
  Check('showing it again reopens the column', (LeftW = PANEL_W) and EmbeddedLeft(WIN_TOOLS));

  { settings round trip: theme, sides, floating position, hidden panel }
  SettingsFile := FileName + '.ini';
  SelectTheme(4);
  Wins[WIN_SIM].X := 400;
  Wins[WIN_SIM].Y := 250;
  ToggleWin(WIN_PROPS);   { hidden; also saves }
  InitWins;
  Wins[WIN_PAGES].Visible := False;
  Wins[WIN_POPUPS].Visible := False;
  SelectTheme(0);
  ApplyLayout;
  Check('reset before loading', (LeftW = 0) and WinDocked(WIN_SIM));
  LoadSettings;
  Check('settings: theme restored', ThemeIndex = 4);
  Check('settings: left embed restored', EmbeddedLeft(WIN_TOOLS) and (LeftW = PANEL_W));
  Check('settings: floating position restored', (not WinDocked(WIN_SIM)) and (Wins[WIN_SIM].X = 400) and
    (Wins[WIN_SIM].Y = 250));
  Check('settings: hidden panel restored', not Wins[WIN_PROPS].Visible);
  SettingsFile := '';
  InitWins;
  ApplyLayout;
  SelectTheme(0);

  { zoom and pan }
  ZoomAt(2, 500, 400);
  MX := 500;
  MY := 400;
  Check('zoom keeps the point under the mouse', (Zoom = 2) and (Abs(MWX - 500) < 0.01) and (Abs(MWY - 400) < 0.01));
  PanBy(5000, 5000);
  Check('pan stops at the layout edge', (Abs(ViewX - CANVAS_W / 2) < 0.01) and (Abs(ViewY - CANVAS_H / 2) < 0.01));
  ZoomAt(0.5, CANVAS_W / 2, CANVAS_H / 2);
  Check('zoomed out the layout is centred', (Zoom = 0.5) and (Abs(ViewX + CANVAS_W / 2) < 0.01));
  ZoomAt(4.0, 0, 0);
  ZoomAt(9.0, 0, 0);
  Check('zoom is limited', Zoom = ZOOM_MAX);
  ZoomAt(1, CANVAS_W / 2, CANVAS_H / 2);
  Check('Ctrl+0 back to 100%', (Zoom = 1) and (ViewX = 0) and (ViewY = 0));

  { 4-way valve on a cross }
  HistCheck;
  PipeLine(28, 26, 32, 26, 3);
  PipeLine(30, 24, 30, 28, 3);
  SetKind(30, 26, ckValve4);
  SimFrame(1 / 60, False);
  Check('4-way valve starts all open', (Grid[30, 26].Closed = 0) and Grid[30, 26].EPf[0] and Grid[30, 26].EPf[1] and
    Grid[30, 26].EPf[2] and Grid[30, 26].EPf[3]);
  Grid[30, 26].Closed := 1 or 4;   { shut E and W: N-S runs straight through }
  SimFrame(1 / 60, False);
  Check('4-way valve shuts chosen branches', (not Grid[30, 26].EPf[0]) and (not Grid[30, 26].EPf[2]) and
    Grid[30, 26].EPf[1] and Grid[30, 26].EPf[3] and not Grid[29, 26].EPf[0]);
  RotateCell(30, 26);
  Check('R cycles the 4-way valve', Grid[30, 26].Closed = 0);
  Grid[30, 26].Closed := 2 or 8;

  { labels: typing, empty ones vanish, hit test }
  i := AddLabel(100, 400, '');
  StartEditLabel(i);
  LabelTypeText('Pump room');
  LabelKey(SDLK_RETURN);
  LabelTypeText('Note: high flow');
  LabelKey(SDLK_BACKSPACE);
  Check('typing into a label', Labels[i].Text = 'Pump room'#10'Note: high flo');
  LabelKey(SDLK_ESCAPE);
  Check('Esc ends typing, label stays', (EditLabel = -1) and Labels[i].Active);
  Check('label hit test', LabelAt(105, 405) = i);
  b := AddLabel(200, 500, '');
  StartEditLabel(b);
  StopEditLabel;
  Check('an empty label is removed', not Labels[b].Active);

  { layout file: 4-way valve mask and label text (new line, backslash) survive }
  Labels[i].Text := 'A\B'#10'second line';
  Check('save layout', SaveLayout(UnicodeString(FileName + '.mflow'), err));
  Grid[30, 26].Closed := 0;
  Labels[i].Active := False;
  Check('load layout', LoadLayout(UnicodeString(FileName + '.mflow'), err));
  Check('4-way valve mask saved', (Grid[30, 26].Kind = ckValve4) and (Grid[30, 26].Closed = 2 or 8));
  b := -1;
  for np := 0 to MAX_LABELS - 1 do
    if Labels[np].Active and (Labels[np].Text = 'A\B'#10'second line') then b := np;
  Check('label saved with its text', (b >= 0) and (Labels[b].X = 100) and (Labels[b].Y = 400));
  i := b;

  { undo a label move; copy a label with parts in a box }
  HistCheck;
  Labels[i].X := 300;
  HistCheck;
  DoUndo;
  Check('undo label move', Labels[i].X = 100);
  SelectBox(4, 16, 9, 18);
  Check('box picks up the label', CountSelLabels = 1);
  DoCopy;
  PlacePaste(20, 24);
  nb := 0;
  for np := 0 to MAX_LABELS - 1 do
    if Labels[np].Active and (Labels[np].Text = 'A\B'#10'second line') then Inc(nb);
  Check('label pasted with the block', nb = 2);
  SelKind := selLabel;
  SelL := i;
  DoDelete;
  Check('delete a label', not Labels[i].Active);

  { date and time labels }
  i := AddClockLabel(100, 300, LBL_DATE);
  Check('date label shows today', (Labels[i].Kind = LBL_DATE) and (LabelDisplay(i) = FormatDateTime('yyyy-mm-dd', Now)));
  Labels[i].Fmt := 'dddd, d mmmm yyyy';
  Check('date format: long preset', LabelDisplay(i) = FormatDateTime('dddd, d mmmm yyyy', Now));
  StartEditFormat(i);
  for np := 1 to 40 do LabelKey(SDLK_BACKSPACE);
  LabelTypeText('dd/mm "of" yyyy');
  LabelKey(SDLK_RETURN);
  Check('typing a custom date format', (Labels[i].Fmt = 'dd/mm "of" yyyy') and (EditLabel = -1) and
    (LabelDisplay(i) = FormatDateTime('dd/mm "of" yyyy', Now)));
  StartEditLabel(i);
  LabelTypeText('Today');
  LabelKey(SDLK_ESCAPE);
  Check('date label caption above the value', LabelDisplay(i) = 'Today'#10 + FormatDateTime('dd/mm "of" yyyy', Now));
  b := AddClockLabel(300, 300, LBL_TIME);
  StartEditLabel(b);
  StopEditLabel;
  Check('a time label without caption is kept', Labels[b].Active and (Labels[b].Fmt = 'hh:nn:ss'));
  Labels[b].Fmt := 'h:nn am/pm';
  Check('time format: 12-hour', (Pos('m', LabelDisplay(b)) > 0) and (Pos(':', LabelDisplay(b)) > 0));
  Labels[b].Fmt := 'hh:nn';
  Labels[b].Color := 3;
  Labels[b].NoBox := True;
  Labels[i].Fmt := 'd mmm yyyy';
  Check('save with date / time labels', SaveLayout(UnicodeString(FileName + '.clock.mflow'), err));
  Labels[i].Active := False;
  Labels[b].Active := False;
  Check('load with date / time labels', LoadLayout(UnicodeString(FileName + '.clock.mflow'), err));
  nb := 0;
  for np := 0 to MAX_LABELS - 1 do
    if Labels[np].Active then
    begin
      if (Labels[np].Kind = LBL_DATE) and (Labels[np].Fmt = 'd mmm yyyy') and (Labels[np].Text = 'Today') then
      begin
        Inc(nb);
        i := np;
      end;
      if (Labels[np].Kind = LBL_TIME) and (Labels[np].Fmt = 'hh:nn') and (Labels[np].Color = 3) and
        Labels[np].NoBox then
      begin
        Inc(nb);
        b := np;
      end;
    end;
  Check('date / time labels saved with format, caption, colour, box', nb = 2);
  HistCheck;
  Labels[i].Fmt := 'yy';
  HistCheck;
  DoUndo;
  Check('undo a format change', Labels[i].Fmt = 'd mmm yyyy');
  SelKind := selLabel;
  SelL := b;
  DoCopy;
  PlacePaste(30, 28);
  nb := 0;
  for np := 0 to MAX_LABELS - 1 do
    if Labels[np].Active and (Labels[np].Kind = LBL_TIME) and (Labels[np].Fmt = 'hh:nn') and
      (Labels[np].Color = 3) then Inc(nb);
  Check('copy / paste keeps a time label''s format and style', nb = 2);

  { frames: draw one with the tool, title it, move it with what is inside }
  DoLoadDemo;
  HistCheck;
  Tool := tFrame;
  MX := 2 * CELL + 3;
  MY := 2 * CELL + 3;
  MouseDown(SDL_BUTTON_LEFT);
  MX := 20 * CELL;
  MY := 12 * CELL;
  CanvasMotion;
  FinishFrameNew;
  Drag := dragNone;
  MDown := False;
  MPressed := False;
  Tool := tSelect;
  i := SelFr;
  Check('Frame tool draws a frame snapped to cells', (SelKind = selFrame) and Frames[i].Active and
    (Frames[i].X = 2 * CELL) and (Frames[i].Y = 2 * CELL) and (Frames[i].W = 18 * CELL) and (Frames[i].H = 10 * CELL));
  Check('a new frame starts with its title being typed', EditFrame = i);
  FrameTypeText(' - liquids');
  FrameKey(SDLK_RETURN);
  Check('frame title typed', (Frames[i].Title = 'Group 1 - liquids') and (EditFrame = -1));
  Check('frame grabbed by its title and outline only', (FrameAt(Frames[i].X + 5, Frames[i].Y + 5, np) = i) and
    (np = 0) and (FrameAt(Frames[i].X + 200, Frames[i].Y + 120, np) = -1) and
    (FrameAt(Frames[i].X + Frames[i].W - 1, Frames[i].Y + 100, np) = i));
  Check('frame corner resizes', (FrameAt(Frames[i].X + Frames[i].W - 2, Frames[i].Y + Frames[i].H - 2, np) = i) and (np = 1));
  HistCheck;
  FrDrag := i;
  FrX0 := Frames[i].X + 5;
  FrY0 := Frames[i].Y + 5;
  MX := FrX0 + 2 * CELL;
  MY := FrY0 + 1 * CELL;
  UpdateFrameMove;
  FinishFrameMove;
  Check('moving a frame moves what is inside it', (Frames[i].X = 4 * CELL) and (Frames[i].Y = 3 * CELL) and
    (Grid[4, 4].Kind = ckSource) and (Grid[2, 3].Kind = ckEmpty) and (Grid[8, 4].Kind = ckBlower));
  HistCheck;
  DoUndo;
  Check('undo the frame move', (Frames[i].X = 2 * CELL) and (Grid[2, 3].Kind = ckSource));
  Frames[i].Carry := False;
  FrDrag := i;
  FrX0 := Frames[i].X + 5;
  FrY0 := Frames[i].Y + 5;
  MX := FrX0 + 3 * CELL;
  MY := FrY0;
  UpdateFrameMove;
  FinishFrameMove;
  Check('carry off: only the frame moves', (Frames[i].X = 5 * CELL) and (Grid[2, 3].Kind = ckSource));
  FrDrag := i;
  MX := Frames[i].X + 6 * CELL + 3;
  MY := Frames[i].Y + 4 * CELL - 2;
  UpdateFrameSize;
  Check('resize snaps to cells', (Frames[i].W = 6 * CELL) and (Frames[i].H = 4 * CELL));
  MX := Frames[i].X;
  MY := Frames[i].Y;
  UpdateFrameSize;
  Check('a frame is at least 2 x 2 cells', (Frames[i].W = 2 * CELL) and (Frames[i].H = 2 * CELL));
  Frames[i].X := 0;
  Frames[i].Y := 2 * CELL;
  Frames[i].W := 22 * CELL;
  Frames[i].H := 24 * CELL;
  SelectFrameContents(i);
  CountSelection(np, nb);
  Check('Select contents picks what is inside', (SelKind = selMulti) and (np > 10));
  Frames[i].Color := 2;
  Frames[i].Dashed := True;
  Frames[i].Fill := False;
  Frames[i].Carry := False;
  Check('save with a frame', SaveLayout(UnicodeString(FileName + '.frame.mflow'), err));
  Frames[i].Active := False;
  Check('load with a frame', LoadLayout(UnicodeString(FileName + '.frame.mflow'), err));
  b := -1;
  for np := 0 to MAX_FRAMES - 1 do
    if Frames[np].Active and (Frames[np].Title = 'Group 1 - liquids') then b := np;
  Check('frame saved with title and style', (b >= 0) and (Frames[b].Color = 2) and Frames[b].Dashed and
    (not Frames[b].Fill) and (not Frames[b].Carry) and (Frames[b].W = 22 * CELL));
  MX := Frames[b].X + 5;
  MY := Frames[b].Y + 5;
  OpenPopup;
  Check('right-click a frame title selects it', PopupOpen and (SelKind = selFrame) and (SelFr = b));
  PopupOpen := False;
  DoDelete;
  Check('delete a frame', not Frames[b].Active);
  DoLoadDemo;

  { status and help panels }
  ToggleWin(WIN_STATUS);
  ToggleWin(WIN_HELP);
  Check('F5 / F1 hide status and help', not Wins[WIN_STATUS].Visible and not Wins[WIN_HELP].Visible);
  ToggleWin(WIN_STATUS);
  ToggleWin(WIN_HELP);
  Check('status and help docked by default', WinDocked(WIN_STATUS) and WinDocked(WIN_HELP) and
    (WinAt(PANEL_X + 50, Wins[WIN_STATUS].DockY + 30) = WIN_STATUS) and
    (WinAt(PANEL_X + 50, Wins[WIN_HELP].DockY + 40) = WIN_HELP));

  { menus clicked the way a user does: mouse down, then a frame is drawn }
  ClickMenu(-1, -1);   { open Edit from the menu bar }
  Check('menu bar click opens a menu', OpenMenu = 1);
  OpenMenu := -1;
  b := Ord(ShowAir);
  ClickMenu(MENU_VIEW, 4);    { View > Air dots }
  Check('View > Air dots works by click', (Ord(ShowAir) <> b) and (OpenMenu = -1));
  ClickMenu(MENU_VIEW, 4);
  ClickMenu(MENU_THEME, 2);     { Theme > Daylight }
  Check('Theme > Daylight works by click', ThemeIndex = 2);
  ClickMenu(MENU_THEME, 0);
  Check('Theme > Default works by click', ThemeIndex = 0);
  ClickSub(MENU_EXAMPLES, 1, 3); { Examples > Pipes & air flow > 4 }
  Check('Examples > 4 works by click', LayoutName = '4-way valve switchyard');
  HistCheck;   { the app commits on the idle frame after each action }
  EraseCell(16, 21);
  HistCheck;
  ClickMenu(1, 0);     { Edit > Undo }
  Check('Edit > Undo works by click', Grid[16, 21].Kind = ckDrop);
  ClickMenu(MENU_PANELS, 1);     { Panels > Simulation (hide) }
  Check('Panels > Simulation works by click', not Wins[WIN_SIM].Visible);
  ClickMenu(MENU_PANELS, 1);
  BuildMenu(MENU_PANELS);
  Check('Panels menu holds the panels, the lab + Dock all', (MCount = 10) and (MItems[5].Lbl = 'Page & Layer') and
    (MItems[6].Lbl = 'Frame popup') and (MItems[7].Lbl = 'Physics lab') and (MItems[8].Lbl = 'Shape editor') and
    (MItems[9].Lbl = 'Dock all panels'));
  BuildMenu(MENU_VIEW);
  Check('View menu: zoom, pressure, air, Grid >', (MCount = 6) and MItems[VIEW_GRID_ITEM].HasSub);

  { View > Grid > : hovering opens the sub-menu, its items work by click }
  OpenMenu := MENU_VIEW;
  SubOpen := -1;
  MX := MenuX(MENU_VIEW) + 40;
  MY := ItemY(VIEW_GRID_ITEM) + 10;
  Render;
  Check('hovering Grid opens its sub-menu', (OpenMenu = MENU_VIEW) and (SubOpen = VIEW_GRID_ITEM));
  ClickGrid(2);   { Style: dots }
  Check('Grid > Style: dots', (GridStyle = 1) and (OpenMenu = -1));
  ClickGrid(6);   { Major: every 5 }
  Check('Grid > Major every 5', GridMajor = 5);
  ClickGrid(10);  { Strength: strong }
  ClickGrid(13);  { Colour: green }
  ClickGrid(16);  { cell numbers }
  Check('Grid > strength, colour, numbers', (GridStrength = 2) and (GridColor = 2) and GridNumbers);
  ClickGrid(0);   { Show grid off }
  Check('Grid > Show grid toggles', not GridShow);
  HandleKey(Ord('g'), 0);
  Check('G shows the grid again', GridShow);
  SettingsFile := FileName + '.grid.ini';
  SaveSettings;
  ResetGrid;
  LoadSettings;
  Check('grid look saved in the settings', (GridStyle = 1) and (GridMajor = 5) and (GridStrength = 2) and
    (GridColor = 2) and GridNumbers);
  SettingsFile := '';
  ClickGrid(17);  { reset }
  Check('Grid > reset', (GridStyle = 0) and (GridMajor = 0) and (GridColor = 0) and not GridNumbers and GridShow);
  { a click elsewhere closes the menu and does nothing else }
  OpenMenu := 0;
  SelectCell(16, 10);
  MX := 16 * CELL + HALF;
  MY := 21 * CELL + HALF;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MDown := False;
  MPressed := False;
  Check('click outside closes the menu only', (OpenMenu = -1) and (SelKind = selCell) and (SelY = 10));
  ClickMenu(0, 4);   { File > Exit }
  Check('File > Exit works by click', QuitRequested);
  QuitRequested := False;
  Check('File menu: New, Open, Save, Save as, Exit only', (MCount = 5) and (MItems[4].Lbl = 'Exit'));
  BuildMenu(MENU_EXAMPLES);
  Check('Examples menu: the demo and the categories', (MCount = 1 + NMenuCats) and (MItems[0].Lbl = 'Original demo') and
    MItems[1].HasSub and (NMenuCats >= 3));
  np := 0;
  for i := 1 to NMenuCats do
    Inc(np, Min(CatLast[MenuCat[i]], EXAMPLE_COUNT) - CatFirst[MenuCat[i]] + 1);
  Check('every example is in a category', np = EXAMPLE_COUNT);
  nb := 0;
  for k := 0 to MENU_COUNT - 1 do
  begin
    bx := MenuW(k);
    for i := 0 to MCount - 1 do
      if 20 + Length(MItems[i].Lbl) * 8 + Length(MItems[i].Key) * 8 + 16 > bx then Inc(nb);
  end;
  Check('every menu is as wide as its text', nb = 0);
  ClickMenu(MENU_EXAMPLES, 0);
  Check('Examples > Original demo works by click', LayoutName = 'Demo');
  LoadStartupLayout(False);
  Check('startup is a new empty layout', (LayoutName = '') and (Grid[2, 3].Kind = ckEmpty) and not Buckets[0].Active);
  DoLoadDemo;

  { no fixed side panel: the right column exists only while a panel is embedded there }
  Check('right column open with panels in it', RightW = PANEL_W);
  for i := 0 to WIN_COUNT - 1 do
    if Wins[i].Visible then ToggleWin(i);
  Check('right column closes when it is empty', (RightW = 0) and (LeftW = 0) and (SceneRight = CANVAS_W));
  FloatWin(WIN_PROPS);
  Check('a floating panel does not open a column', (RightW = 0) and InWin(WIN_PROPS, Wins[WIN_PROPS].X + 5,
    Wins[WIN_PROPS].Y + 5) and (Wins[WIN_PROPS].X + Wins[WIN_PROPS].W <= CANVAS_W));
  EmbedWin(WIN_PROPS, 0);
  Check('embedding right reopens it', (RightW = PANEL_W) and EmbeddedRight(WIN_PROPS));
  for i := 0 to WIN_CORE - 1 do DockWin(i);
  Check('menu bar is above the canvas', InMenuBar(10, -10) and not InMenuBar(10, 10) and (OY = MENU_H));

  { drag box: once the mouse is up the box is gone, the parts stay selected }
  Drag := dragBox;
  BoxX0 := 13 * CELL + 5;
  BoxY0 := 2 * CELL + 5;
  BoxX1 := 19 * CELL - 5;
  BoxY1 := 4 * CELL - 5;
  FinishBox;
  Drag := dragNone;
  CountSelection(np, nb);
  Check('box selection after mouse up', (SelKind = selMulti) and (np >= 3) and (Drag <> dragBox));

  { empty clipboard / nothing selected }
  SelKind := selNone;
  ClearClip;
  DoPaste;
  Check('paste with empty clipboard is refused', not PasteArmed);

  { File menu: examples 4-6 and the demo after them }
  RunMenuItem(MENU_EXAMPLES, 6);
  Check('menu loads example 6', LayoutName = 'Silo storage');
  HandleKey(Ord('q'), SDL_KMOD_CTRL);
  Check('Ctrl+Q exits', QuitRequested);
  QuitRequested := False;
  DoLoadDemo;
  Check('demo file in examples folder', FileExists(ExtractFilePath(ParamStr(0)) + 'examples' + PathDelim + DEMO_FILE));

  { 4-way valve example routes to the open branches only }
  RunMenuItem(MENU_EXAMPLES, 4);
  Check('example 4 has a 4-way valve, north shut', (Grid[16, 10].Kind = ckValve4) and (Grid[16, 10].Closed = 8));
  ClearParticles;
  for i := 1 to 900 do SimFrame(1 / 60, True);
  Check('4-way: east and south buckets fill', (Buckets[0].Count > 0) and (Buckets[1].Count > 0));
  Check('4-way: shut north branch carries nothing', (Abs(Grid[16, 9].F[3]) < 0.01) and (Abs(Grid[16, 5].F[3]) < 0.01));

  { hopper: catches the falling sand and passes it on }
  RunMenuItem(MENU_EXAMPLES, 5);
  Check('example 5 has two hoppers', (Grid[6, 15].Kind = ckHopper) and (Grid[34, 13].Kind = ckHopper));
  for i := 1 to 900 do SimFrame(1 / 60, True);
  Check('hopper + blower deliver to the bucket', Buckets[0].Count > 20);
  Check('gravity hopper drains into its bucket', Buckets[1].Count > 20);

  { silo: fills from the roof and from a pipe, gate meters / holds it }
  RunMenuItem(MENU_EXAMPLES, 6);
  Check('example 6 has two silos', (Grid[21, 18].Kind = ckSilo) and (Grid[36, 19].Kind = ckSilo));
  for i := 1 to 1200 do SimFrame(1 / 60, True);
  Check('silo fills through its roof', StoreTotal(Grid[21, 18]) > 20);
  Check('pipe-fed silo fills', StoreTotal(Grid[36, 19]) > 20);
  Check('gate shut: the silo only stores', Buckets[1].Count = 0);
  { full silo takes no more }
  Grid[21, 18].Stock[mSand] := 3000;
  Grid[21, 18].Stock[mFluff] := 1000;
  bx := StoreTotal(Grid[21, 18]);
  for i := 1 to 120 do SimFrame(1 / 60, True);
  Check('a full silo takes no more', StoreTotal(Grid[21, 18]) <= SILO_CAP);
  { hopper / silo in a layout file }
  Grid[36, 19].Stock[mWater] := 777;
  Check('save with silo', SaveLayout(UnicodeString(FileName + '.mflow'), err));
  Check('load with silo', LoadLayout(UnicodeString(FileName + '.mflow'), err));
  Check('silo and its contents saved', (Grid[36, 19].Kind = ckSilo) and (Grid[36, 19].Stock[mWater] = 777) and
    (Grid[21, 18].Feed = 30));

  { ---- Feeder, pages, layers, links and frame popups }
  InitWins;
  ApplyLayout;
  Zoom := 1;
  ViewX := 0;
  ViewY := 0;
  Check('the tank part is called Feeder', (KindNames[ckSource] = 'Feeder') and (ToolNames[tFeeder] = 'Feeder'));
  DoNew;
  Check('a new layout has one page with one layer', (PageCount = 1) and (CurPage = 0) and (LayerCount = 1));
  PipeLine(2, 2, 8, 2, 3);
  AppAddPage;
  Check('Add page shows the new, empty page', (PageCount = 2) and (CurPage = 1) and (Grid[4, 2].Kind = ckEmpty));
  PipeLine(3, 5, 3, 9, 3);
  AppGoToPage(0);
  Check('each page keeps its own parts', (Grid[4, 2].Kind = ckPipe) and (Grid[3, 7].Kind = ckEmpty));
  AppGoToPage(1);
  Check('... and so does the other page', (Grid[3, 7].Kind = ckPipe) and (Grid[4, 2].Kind = ckEmpty));
  for i := 1 to 30 do AppAddPage;
  Check('at most 20 pages', PageCount = MAX_PAGES);
  AppGoToPage(MAX_PAGES - 1);
  PageDelArmed := 0;
  AppDeletePage;
  Check('deleting a page needs a second click', PageCount = MAX_PAGES);
  AppDeletePage;
  Check('the second click deletes the page', (PageCount = MAX_PAGES - 1) and (CurPage = MAX_PAGES - 2));

  { layers }
  AppGoToPage(0);
  for i := 1 to 10 do AppAddLayer;
  Check('at most 5 layers on a page', (LayerCount = MAX_LAYERS) and (CurLayer = MAX_LAYERS - 1));
  AppSetLayer(1);
  PipeLine(10, 10, 14, 10, 3);
  Check('new parts go on the active layer', (Grid[12, 10].Layer = 1) and (Grid[4, 2].Layer = 0));
  Pages[0].Layers[1].Visible := False;
  Tool := tSelect;
  SelKind := selNone;
  MX := 12 * CELL + HALF;
  MY := 10 * CELL + HALF;
  CanvasPress(False);
  Drag := dragNone;
  Check('a part on a hidden layer cannot be picked', SelKind <> selCell);
  SelectBox(9, 9, 15, 11);
  Check('a box selection skips a hidden layer', SelKind = selNone);
  Pages[0].Layers[1].Visible := True;
  Pages[0].Layers[1].Locked := True;
  Tool := tErase;
  CanvasPress(False);
  Drag := dragNone;
  Check('a part on a locked layer cannot be erased', Grid[12, 10].Kind = ckPipe);
  Pages[0].Layers[1].Locked := False;
  Tool := tSelect;
  SelectCell(12, 10);
  AppSetLayer(2);
  SelectionToLayer;
  Check('Move selection to active layer', Grid[12, 10].Layer = 2);
  LayerDelArmed := 0;
  AppDeleteLayer;
  AppDeleteLayer;
  Check('deleting a layer keeps its parts', (LayerCount = MAX_LAYERS - 1) and (Grid[12, 10].Kind = ckPipe) and
    (Grid[12, 10].Layer = 1));
  SelectCell(12, 10);
  DoCopy;
  AppSetLayer(3);
  PlacePaste(12, 14);
  Check('pasted parts go on the active layer', (Grid[12, 14].Kind = ckPipe) and (Grid[12, 14].Layer = 3));
  AppSetLayer(0);

  { frame popups }
  for i := 1 to 30 do AddPopup('Popup', 'text');
  Check('at most 20 frame popups', FramePopupCount = MAX_POPUPS);
  for i := 2 to MAX_POPUPS - 1 do DeletePopup(i);
  Popups[0].Title := 'Help';
  Popups[0].GoPage := 1;

  { links }
  Tool := tLink;
  MX := 20 * CELL;
  MY := 20 * CELL;
  CanvasPress(False);
  Drag := dragNone;
  lk := SelLk;
  Check('the Link tool adds a link to the next page', (SelKind = selLink) and Links[lk].Active and
    (not Links[lk].ToPopup) and (Links[lk].Target = 1));
  Links[lk].Target := 5;
  Tool := tSelect;
  SelKind := selNone;
  MX := Links[lk].X + 6;
  MY := Links[lk].Y + 6;
  MouseDown(SDL_BUTTON_LEFT);
  MDown := False;
  MPressed := False;
  Check('clicking a link goes to its page', CurPage = 5);
  AppGoToPage(0);
  lk2 := AddLink(30 * CELL, 26 * CELL, 'Help', True, 0);
  MX := Links[lk2].X + 6;
  MY := Links[lk2].Y + 6;
  MouseDown(SDL_BUTTON_LEFT);
  MDown := False;
  MPressed := False;
  Check('a popup link opens its frame popup', (ShownPopup = 0) and (CurPage = 0));
  FramePopupBox(bx, by, fw, fh);
  MX := bx + 20;
  MY := by + fh - 20;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  TakePendingPage;
  MDown := False;
  MPressed := False;
  Check('the popup''s "Go to" button opens its page', (ShownPopup = -1) and (CurPage = 1));
  AppGoToPage(0);
  ShowFramePopup(1);
  HandleKey(SDLK_ESCAPE, 0);
  Check('Esc closes a frame popup', ShownPopup = -1);
  ShowFramePopup(1);
  MX := 4;
  MY := 4;
  MouseDown(SDL_BUTTON_LEFT);
  MDown := False;
  MPressed := False;
  Check('a click beside the popup closes it', (ShownPopup = -1) and (CurPage = 0));
  HandleKey(SDLK_PAGEDOWN, 0);
  Check('PgDn: next page', CurPage = 1);
  HandleKey(SDLK_PAGEUP, 0);
  Check('PgUp: previous page', CurPage = 0);

  { typing names and texts }
  Pages[0].Name := '';
  StartTxt(1, 0);
  TxtTypeText('Main hall');
  TxtKey(SDLK_RETURN);
  Check('typing a page name', (PageName(0) = 'Main hall') and (TxtEdit = 0));
  Popups[0].Text := '';
  StartTxt(4, 0);
  TxtTypeText('Line 1');
  TxtKey(SDLK_RETURN);
  TxtTypeText('Line 2');
  TxtKey(SDLK_ESCAPE);
  Check('popup text takes several lines', Popups[0].Text = 'Line 1'#10'Line 2');

  { undo belongs to a page }
  HistCheck;
  EraseCell(4, 2);
  HistCheck;
  DoUndo;
  Check('undo on a page', Grid[4, 2].Kind = ckPipe);
  AppGoToPage(1);
  Check('nothing to undo on a page just entered', not CanUndo);

  { moving a page keeps links pointing at it }
  AppGoToPage(5);
  AppMovePage(-1);
  Check('moving a page keeps links pointing at it', (CurPage = 4) and (Pages[0].Links[lk].Target = 4));

  { all pages in one file }
  AppGoToPage(0);
  Check('save a layout with pages', SaveLayout(UnicodeString(FileName + '.pages.mflow'), err));
  np := PageCount;
  DoNew;
  Check('load a layout with pages', LoadLayout(UnicodeString(FileName + '.pages.mflow'), err));
  Check('pages, names and layers come back', (PageCount = np) and (PageName(0) = 'Main hall') and
    (LayerCount = MAX_LAYERS - 1) and (Grid[12, 10].Layer = 1) and (Grid[12, 14].Layer = 3) and (Grid[4, 2].Kind = ckPipe));
  nb := 0;
  for i := 0 to MAX_LINKS - 1 do
    if Links[i].Active and ((Links[i].ToPopup and (Links[i].Target = 0)) or
      ((not Links[i].ToPopup) and (Links[i].Target = 4))) then Inc(nb);
  Check('frame popups and links come back', (FramePopupCount = 2) and (Popups[0].Text = 'Line 1'#10'Line 2') and
    (Popups[0].GoPage = 1) and (nb = 2));
  AppGoToPage(1);
  Check('the second page comes back with its parts', Grid[3, 7].Kind = ckPipe);
  { a version 1 file (one page, "tank" parts) still loads }
  AssignFile(tf, FileName + '.v1.mflow');
  Rewrite(tf);
  WriteLn(tf, 'MFLOW 1');
  WriteLn(tf, 'CELL 5 5 tank E 4 E 1 100.00');
  WriteLn(tf, 'CELL 6 5 pipe W 3 E 1 100.00');
  WriteLn(tf, 'TANK 5 5 100.00 0.00 0.00 0.00 10.00 50.00');
  CloseFile(tf);
  Check('a version 1 file loads as one page', LoadLayout(UnicodeString(FileName + '.v1.mflow'), err) and
    (PageCount = 1) and (Grid[5, 5].Kind = ckSource) and (Grid[5, 5].Stock[mWater] = 100));
  Check('feeders are saved as "feeder"', SaveLayout(UnicodeString(FileName + '.v1.mflow'), err) and
    LoadLayout(UnicodeString(FileName + '.v1.mflow'), err) and (Grid[5, 5].Kind = ckSource));

  { every example follows the same plan }
  for k := 1 to EXAMPLE_COUNT do
  begin
    RunMenuItem(MENU_EXAMPLES, k);
    Check(Format('example %d: pages Plant + About, layers Process + Notes, 2 popups', [k]),
      ((PageCount = 2) or ((k = 24) and (PageCount = 4))) and (PageName(0) = 'Plant') and (PageName(1) = 'About') and (LayerCount >= 2) and
      (Pages[0].Layers[0].Name = 'Process') and (Pages[0].Layers[1].Name = 'Notes') and
      (FramePopupCount = 2) and (CurPage = 0) and (CurLayer = 0));
    np := 0;
    nb := 0;
    for i := 0 to MAX_LINKS - 1 do
    begin
      if Links[i].Active and (Links[i].Layer = 1) then Inc(np);
      if Pages[1].Links[i].Active then Inc(nb);
    end;
    { example 24 also links to its pages 3 and 4 }
    Check(Format('example %d: 3 links on each page', [k]), ((np = 3) or ((k = 24) and (np = 5))) and (nb = 3));
    np := 0;
    for cy := 0 to GH - 1 do
      for cx := 0 to GW - 1 do
        if (Grid[cx, cy].Kind <> ckEmpty) and not (Grid[cx, cy].Layer in [0, 3]) then Inc(np);
    for i := 0 to MAX_LABELS - 1 do
      if Labels[i].Active and (Labels[i].Layer <> 1) then Inc(np);
    Check(Format('example %d: parts on Process, notes on Notes', [k]), np = 0);
  end;
  { the links of an example work }
  RunMenuItem(MENU_EXAMPLES, 4);
  for i := 0 to MAX_LINKS - 1 do
    if Links[i].Active and not Links[i].ToPopup then AppFollowLink(i);
  Check('example: About link goes to page 2', (CurPage = 1) and (Labels[1].Active));
  for i := 0 to MAX_LINKS - 1 do
    if Links[i].Active and not Links[i].ToPopup then lk := i;
  AppFollowLink(lk);
  Check('example: Back link returns to the plant', (CurPage = 0) and (Grid[16, 10].Kind = ckValve4));
  { a page that is not shown is paused: its flow carries on when it is shown again }
  for i := 1 to 200 do SimFrame(1 / 60, True);
  np := NPart;
  AppGoToPage(1);
  Check('the About page has no flow of its own', NPart = 0);
  AppGoToPage(0);
  Check('the plant page keeps its material in flight', NPart = np);

  { ---- plant equipment: motor, blower, paddle, screw, cyclone, silo bin, stand, lamp, legend }
  Check('every equipment kind has a tool', (ToolNames[tEqMotor] = 'Motor') and (ToolNames[tEqBlower] = 'Blower') and
    (ToolNames[tEqLegend] = 'Legend') and (Ord(tEqChiller) - Ord(tEqMotor) + 1 = EQ_KINDS));
  DoNew;
  Zoom := 1;
  ViewX := 0;
  ViewY := 0;
  PipeLine(4, 10, 20, 10, 3);
  SetKind(4, 10, ckSource);
  Grid[4, 10].Stock[mWater] := 2000;
  SetKind(10, 10, ckBlower);
  Grid[10, 10].Dir := 0;
  Grid[10, 10].Strength := 80;
  Tool := tEqMotor;
  MX := 10 * CELL + HALF;
  MY := 10 * CELL + HALF;
  CanvasPress(False);
  Drag := dragNone;
  k := SelEq;
  Check('a motor put on a blower links to it', (SelKind = selEquip) and Equips[k].Active and
    (Equips[k].Kind = EQ_MOTOR) and (Equips[k].LinkX = 10) and (Equips[k].LinkY = 10) and (Equips[k].Name = 'Motor01'));
  Check('new equipment is stopped (grey)', Equips[k].State = EQS_STOP);
  for i := 1 to 30 do SimFrame(1 / 60, True);
  Check('a stopped motor halts its blower', Grid[10, 10].Halted and (DevStr(@Grid[10, 10]) = 0) and
    (Abs(Grid[10, 10].F[0]) < 0.01));
  SetEquipState(k, EQS_RUN);
  for i := 1 to 60 do SimFrame(1 / 60, True);
  Check('a running motor lets it blow', (not Grid[10, 10].Halted) and (Grid[10, 10].F[0] > 0.05) and
    (Equips[k].RunTime > 0.5));
  SetEquipState(k, EQS_FAULT);
  for i := 1 to 30 do SimFrame(1 / 60, True);
  Check('a motor in fault halts it too', Grid[10, 10].Halted and (Equips[k].RunTime = 0));
  Tool := tSelect;
  MX := Equips[k].X + 20;
  MY := Equips[k].Y + 10;
  LastClicks := 2;
  CanvasPress(False);
  LastClicks := 1;
  Drag := dragNone;
  Check('double-click resets a fault to stop', Equips[k].State = EQS_STOP);
  CanvasPress(False);
  LastClicks := 2;
  CanvasPress(False);
  LastClicks := 1;
  Drag := dragNone;
  Check('double-click runs it', Equips[k].State = EQS_RUN);
  { the other kinds }
  for i := Ord(tEqBlower) to Ord(tEqChiller) do
  begin
    Tool := TTool(i);
    MX := 25 * CELL;
    MY := 4 * CELL;
    CanvasPress(False);
    Drag := dragNone;
    { park it out of the way of the next click }
    Equips[SelEq].X := (i - Ord(tEqBlower)) * 40;
    Equips[SelEq].Y := 560;
  end;
  np := 0;
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active then Inc(np);
  Check('every kind can be placed', np = EQ_KINDS);
  { silo bin shows the level of a linked silo }
  MakePipe(30, 6, 3);
  SetKind(30, 6, ckSilo);
  Grid[30, 6].Stock[mSand] := SILO_CAP / 4;
  Tool := tEqSilo;
  MX := 30 * CELL + HALF;
  MY := 6 * CELL + HALF;
  CanvasPress(False);
  Drag := dragNone;
  Check('a silo bin put on a silo shows its level', (Equips[SelEq].Kind = EQ_SILO) and
    (Abs(EquipLevel(SelEq) - 25) < 0.5));
  { link by picking }
  lk := SelEq;
  EqPick := lk;
  MX := 4 * CELL + HALF;
  MY := 10 * CELL + HALF;
  CanvasPress(False);
  Check('Link: click a part', (EqPick = -1) and (Equips[lk].LinkX = 4) and (Equips[lk].LinkY = 10));
  { flip, name, move }
  SelKind := selEquip;
  SelEq := k;
  DoRotate(True);
  Check('R flips equipment', Equips[k].Flip);
  StartTxt(6, k);
  TxtKey(SDLK_BACKSPACE);
  TxtKey(SDLK_BACKSPACE);
  TxtTypeText('77');
  TxtKey(SDLK_RETURN);
  Check('typing an equipment name', Equips[k].Name = 'Motor77');
  bx := Equips[k].X;
  Tool := tSelect;
  MX := Equips[k].X + 20;
  MY := Equips[k].Y + 10;
  CanvasPress(False);
  MX := MX + 48;
  CanvasMotion;
  Drag := dragNone;
  Check('drag moves equipment', Abs(Equips[k].X - (bx + 48)) < 0.5);
  { saved with the layout }
  Check('save equipment', SaveLayout(UnicodeString(FileName + '.eq.mflow'), err));
  DoNew;
  Check('load equipment', LoadLayout(UnicodeString(FileName + '.eq.mflow'), err));
  np := -1;
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and (Equips[i].Name = 'Motor77') then np := i;
  Check('equipment comes back with its state, link and flip', (np >= 0) and (Equips[np].Kind = EQ_MOTOR) and
    (Equips[np].State = EQS_RUN) and (Equips[np].LinkX = 10) and (Equips[np].LinkY = 10) and Equips[np].Flip);
  { undo }
  HistCheck;
  SelKind := selEquip;
  SelEq := np;
  DeleteSelected;
  HistCheck;
  DoUndo;
  Check('undo brings deleted equipment back', Equips[np].Active and (Equips[np].Name = 'Motor77'));
  { each page has its own equipment }
  AppAddPage;
  Check('a new page has no equipment', not Equips[np].Active);
  AppGoToPage(0);
  Check('the first page keeps its equipment', Equips[np].Active);

  { example 7: the fluff silo system from the drawing }
  RunMenuItem(MENU_EXAMPLES, 7);
  np := 0;
  b := -1;
  lk := -1;
  lk2 := -1;
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active then
    begin
      Inc(np);
      if Equips[i].Name = 'Blower01' then b := i;
      if Equips[i].Name = 'Screw01' then lk := i;
      if Equips[i].Kind = EQ_SEQUENCE then lk2 := i;
    end;
  Check('example 7 has the plant equipment', (np >= 10) and (b >= 0) and (lk >= 0) and (lk2 >= 0) and
    (Grid[Equips[b].LinkX, Equips[b].LinkY].Kind = ckBlower) and (Grid[Equips[lk].LinkX, Equips[lk].LinkY].Kind = ckSilo));
  Check('example 7: the sequence starts with everything stopped', (Equips[b].State = EQS_STOP) and
    (Equips[lk].State = EQS_STOP));
  for i := 1 to 150 do SimFrame(1 / 60, True);
  Check('example 7: step 1 (blower) starts after its delay, step 2 waits', (Equips[b].State = EQS_RUN) and
    (Equips[lk].State = EQS_STOP) and (Equips[lk].Wait > 0));
  for i := 1 to 900 do SimFrame(1 / 60, True);
  Check('example 7: all steps started', (Equips[lk].State = EQS_RUN) and (Equips[lk2].SeqPos = 4));
  Check('example 7: the blower moves air while it runs', Abs(Grid[33, 27].F[0]) > 0.05);
  Equips[lk2].Mode := SEQ_MANUAL;
  SetEquipState(b, EQS_STOP);
  for i := 1 to 60 do SimFrame(1 / 60, True);
  Check('example 7: stopping Blower01 stops the air', Abs(Grid[33, 27].F[0]) < 0.02);
  bx := StoreTotal(Grid[16, 16]);
  SetEquipState(lk, EQS_STOP);
  for i := 1 to 120 do SimFrame(1 / 60, True);
  Check('example 7: stopping Screw01 stops the silo discharge', StoreTotal(Grid[16, 16]) >= bx - 1);

  { ---- the six states, the sequence, valves, heaters, rain and fire }
  DoNew;
  PipeLine(4, 10, 20, 10, 3);
  SetKind(4, 10, ckSource);
  Grid[4, 10].Stock[mWater] := 2000;
  SetKind(8, 10, ckBlower);
  Grid[8, 10].Dir := 0;
  SetKind(14, 10, ckBlower);
  Grid[14, 10].Dir := 0;
  k := AddEquip(EQ_MOTOR, 100, 300);
  Equips[k].LinkX := 8;
  Equips[k].LinkY := 10;
  b := AddEquip(EQ_MOTOR, 300, 300);
  Equips[b].LinkX := 14;
  Equips[b].LinkY := 10;
  SetEquipState(k, EQS_MSTART);
  SimFrame(1 / 60, True);
  Check('manual start runs the part', (not Grid[8, 10].Halted) and EquipRunning(k));
  SetEquipState(k, EQS_MSTOP);
  SimFrame(1 / 60, True);
  Check('manual stop halts it', Grid[8, 10].Halted);
  SetEquipState(k, EQS_DISABLE);
  SimFrame(1 / 60, True);
  Check('disable halts it', Grid[8, 10].Halted and not EquipRunning(k));
  ToggleEquip(k);
  Check('a disabled piece stays disabled on double-click', Equips[k].State = EQS_DISABLE);
  SetEquipState(k, EQS_MSTOP);
  ToggleEquip(k);
  Check('double-click: manual stop -> manual start', Equips[k].State = EQS_MSTART);
  { the sequence: step 1 after 1 s, step 2 after 2 s; reverse on request off }
  SetEquipState(k, EQS_STOP);
  Equips[k].SeqStep := 1;
  Equips[k].Delay := 1;
  Equips[b].SeqStep := 2;
  Equips[b].Delay := 2;
  lk := AddEquip(EQ_SEQUENCE, 500, 40);
  SetEquipState(lk, EQS_RUN);
  for i := 1 to 30 do SimFrame(1 / 60, True);
  Check('sequence: nothing starts before the delay', (Equips[k].State = EQS_STOP) and (Equips[k].Wait > 0));
  for i := 1 to 40 do SimFrame(1 / 60, True);
  Check('sequence: step 1 starts after 1 s', (Equips[k].State = EQS_RUN) and (Equips[b].State = EQS_STOP));
  for i := 1 to 130 do SimFrame(1 / 60, True);
  Check('sequence: step 2 starts 2 s later', (Equips[b].State = EQS_RUN) and (Equips[lk].SeqPos = 2));
  SetEquipState(lk, EQS_STOP);
  for i := 1 to 130 do SimFrame(1 / 60, True);
  Check('sequence: request off stops the last step first', (Equips[b].State = EQS_STOP) and
    (Equips[k].State = EQS_RUN));
  for i := 1 to 70 do SimFrame(1 / 60, True);
  Check('sequence: then the first step', (Equips[k].State = EQS_STOP) and (Equips[lk].SeqPos = 0));
  SetEquipState(k, EQS_MSTART);
  SetEquipState(lk, EQS_RUN);
  for i := 1 to 300 do SimFrame(1 / 60, True);
  Check('sequence: a manual start is left alone, the auto one starts', (Equips[k].State = EQS_MSTART) and
    (Equips[b].State = EQS_RUN));
  Equips[lk].Mode := SEQ_ESTOP;
  SimFrame(1 / 60, True);
  Check('E-Stop stops everything at once', (Equips[k].State = EQS_MSTOP) and (Equips[b].State = EQS_STOP));
  { the settings are saved }
  Equips[lk].Mode := SEQ_MANUAL;
  Check('save the sequence', SaveLayout(UnicodeString(FileName + '.seq.mflow'), err));
  DoNew;
  Check('load the sequence', LoadLayout(UnicodeString(FileName + '.seq.mflow'), err));
  Check('sequence step, delay, mode and manual states come back', (Equips[k].SeqStep = 1) and
    (Equips[k].Delay = 1) and (Equips[b].SeqStep = 2) and (Equips[k].State = EQS_MSTOP) and
    (Equips[lk].Kind = EQ_SEQUENCE) and (Equips[lk].Mode = SEQ_MANUAL));
  { shutter / slide valve on a 2-way valve, diverter on a 3-way valve }
  DoNew;
  PipeLine(4, 5, 12, 5, 3);
  PipeLine(8, 5, 8, 9, 3);
  SetKind(6, 5, ckValve2);
  SetKind(8, 5, ckValve3);
  k := AddEquip(EQ_SHUTTER, 100, 300);
  Equips[k].LinkX := 6;
  Equips[k].LinkY := 5;
  SetEquipState(k, EQS_STOP);
  SimFrame(1 / 60, True);
  Check('a closed shutter valve shuts its 2-way valve', not Grid[6, 5].Open);
  SetEquipState(k, EQS_RUN);
  SimFrame(1 / 60, True);
  Check('an open shutter valve opens it', Grid[6, 5].Open);
  b := AddEquip(EQ_DIVERTER, 300, 300);
  MX := 8 * CELL + HALF;
  MY := 5 * CELL + HALF;
  Check('a diverter links to a 3-way valve', LinkEquipAt(b, MX, MY, 8, 5) and (Equips[b].DivA >= 0) and
    (Equips[b].DivB >= 0) and (Equips[b].DivA <> Equips[b].DivB));
  SetEquipState(b, EQS_RUN);
  SimFrame(1 / 60, True);
  np := Grid[8, 5].Dir;
  SetEquipState(b, EQS_STOP);
  SimFrame(1 / 60, True);
  Check('the diverter switches its valve between two ways', (np = Equips[b].DivA) and (Grid[8, 5].Dir = Equips[b].DivB));

  { example 8: rain, fire, heaters }
  RunMenuItem(MENU_EXAMPLES, 8);
  k := -1;
  b := -1;
  lk := -1;
  lk2 := -1;
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active then
    begin
      if Equips[i].Name = 'Fire01' then k := i;
      if Equips[i].Name = 'Rain02' then b := i;
      if Equips[i].Name = 'IRHeater01' then lk := i;
      if Equips[i].Name = 'Heater01' then lk2 := i;
    end;
  Check('example 8 has rain, fire and heaters', (k >= 0) and (b >= 0) and (lk >= 0) and (lk2 >= 0));
  for i := 1 to 300 do SimFrame(1 / 60, True);
  np := 0;
  for i := 0 to NPart - 1 do
    if (Parts[i].Mat = mWater) and not Parts[i].InPipe then Inc(np);
  Check('rain drops real water', np > 100);
  Check('the fire burns on fluff', (Equips[k].State = EQS_RUN) and (Equips[k].Heat > 20));
  { equipment in the flames goes to fault }
  i := AddEquip(EQ_MOTOR, Equips[k].X, Equips[k].Y + Equips[k].H - 30);
  SetEquipState(i, EQS_RUN);
  SimFrame(1 / 60, True);
  Check('a motor in the fire goes to fault', Equips[i].State = EQS_FAULT);
  DeleteEquip(i);
  SetEquipState(b, EQS_RUN);
  for i := 1 to 900 do SimFrame(1 / 60, True);
  Check('rain puts the fire out', (Equips[k].State = EQS_STOP) and (Equips[k].Heat = 0));
  { heaters boil water off: compare runs with the heater off and on }
  RunMenuItem(MENU_EXAMPLES, 8);
  for i := 1 to 600 do SimFrame(1 / 60, True);
  np := Buckets[0].Count;
  nb := Buckets[1].Count;
  RunMenuItem(MENU_EXAMPLES, 8);
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and (Equips[i].Kind in [EQ_IRHEATER, EQ_HEATER]) then SetEquipState(i, EQS_RUN);
  for i := 1 to 600 do SimFrame(1 / 60, True);
  Check('the IR heater dries rain falling past it', Buckets[0].Count < np * 0.7);
  Check('the duct heater boils the water in its pipe', Buckets[1].Count < nb * 0.7);
  Check('steam rises (air dots)', NAir > 0);

  { ---- well, pool, pond and water pumps }
  RunMenuItem(MENU_EXAMPLES, 9);
  k := -1;
  b := -1;
  lk := -1;
  lk2 := -1;
  cx := -1;
  cy := -1;
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active then
    begin
      if Equips[i].Name = 'Well01' then k := i;
      if Equips[i].Name = 'Pool01' then b := i;
      if Equips[i].Name = 'Pond01' then lk := i;
      if Equips[i].Name = 'Pump01' then lk2 := i;
      if Equips[i].Name = 'Pump02' then cx := i;
      if Equips[i].Name = 'Rain01' then cy := i;
    end;
  Check('example 9 has a well, pool, pond and two pumps', (k >= 0) and (b >= 0) and (lk >= 0) and (lk2 >= 0) and (cx >= 0));
  Check('each pump draws from the nearest water', (PumpSource(lk2) = k) and (PumpSource(cx) = b));
  bx := Equips[b].Level;
  by := Equips[k].Level;
  HistCheck;
  for i := 1 to 900 do SimFrame(1 / 60, True);
  Check('Pump01 lifts well water into the pool', (Equips[b].Level > bx + 3));
  HistCheck;
  Check('the water levels are not undo steps', not CanUndo);
  SetEquipState(lk2, EQS_STOP);
  SimFrame(1 / 60, True);
  Check('a stopped pump halts its push', Grid[Equips[lk2].LinkX, Equips[lk2].LinkY].Halted);
  for i := 1 to 120 do SimFrame(1 / 60, True);
  bx := Equips[b].Level;
  fw := Equips[lk].Level;
  SetEquipState(cx, EQS_RUN);
  for i := 1 to 900 do SimFrame(1 / 60, True);
  Check('Pump02 drains the pool', Equips[b].Level < bx - 3);
  Check('... into the pond', Equips[lk].Level > fw + 3);
  { a dry source: the pump stops delivering }
  Equips[b].Level := 0;
  for i := 1 to 120 do SimFrame(1 / 60, True);
  Check('a pump cannot take water from an empty pool', Equips[b].Level = 0);
  { the well refills from the ground water }
  Equips[k].Level := 10;
  for i := 1 to 300 do SimFrame(1 / 60, True);
  Check('the well refills', Equips[k].Level > 10);
  { rain fills the pond }
  SetEquipState(cx, EQS_STOP);
  fw := Equips[lk].Level;
  SetEquipState(cy, EQS_RUN);
  for i := 1 to 600 do SimFrame(1 / 60, True);
  Check('rain fills the pond', Equips[lk].Level > fw + 1);
  { saved with the layout }
  fw := Equips[lk].Level;
  Check('save water levels', SaveLayout(UnicodeString(FileName + '.water.mflow'), err));
  DoNew;
  Check('load water levels', LoadLayout(UnicodeString(FileName + '.water.mflow'), err));
  np := 0;
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and (Equips[i].Name = 'Pond01') and (Abs(Equips[i].Level - fw) < 0.05) and
      (Equips[i].Kind = EQ_POND) then Inc(np);
  Check('the pond comes back with its water', np = 1);
  { the tools }
  Check('pond, pool, well and pump tools', (ToolNames[tEqPond] = 'Pond') and (ToolNames[tEqPool] = 'Pool') and
    (ToolNames[tEqWell] = 'Well') and (ToolNames[tEqPump] = 'Water pump') and EquipActuated(EQ_PUMP));

  { ---- electrical circuits }
  DoNew;
  Check('electrical tools: 26 parts', (Ord(tElFloat) - Ord(tElWire) + 1 = 26) and (ToolNames[tElContactor] = 'Contactor'));
  { a lamp on a switch: AC at (5,2), L rail down column 2, N rail down column 8 }
  EWireLine(4, 2, 2, 2);
  EWireLine(2, 2, 2, 9);
  EWireLine(6, 2, 8, 2);
  EWireLine(8, 2, 8, 9);
  EPlace(5, 2, ekAC);
  EWireLine(2, 4, 8, 4);
  EPlace(4, 4, ekSwitch);
  EPlace(6, 4, ekLamp);
  SimFrame(1 / 60, True);
  Check('an open switch: the lamp is off', not EGrid[6, 4].Energized);
  Check('the rails show live and neutral', (EGrid[2, 3].Live = 1) and (EGrid[8, 3].Live = 2));
  EOperate(4, 4);
  SimFrame(1 / 60, True);
  Check('switch on: the lamp lights', EGrid[6, 4].Energized);
  { a relay: its NO contact follows the coil }
  EWireLine(2, 6, 8, 6);
  EPlace(6, 6, ekRelay);
  EGrid[6, 6].Tag := 'K1';
  EPlace(4, 6, ekPBNO);
  EWireLine(2, 8, 8, 8);
  EPlace(4, 8, ekNO);
  EGrid[4, 8].Tag := 'K1';
  EPlace(6, 8, ekLamp);
  SimFrame(1 / 60, True);
  Check('relay off: its NO contact is open', not EGrid[6, 8].Energized);
  EPress(4, 6, True);
  SimFrame(1 / 60, True);
  Check('push button held: relay on, its contact lights the lamp', EGrid[6, 6].Energized and EGrid[6, 8].Energized);
  EPress(4, 6, False);
  SimFrame(1 / 60, True);
  Check('released: the relay drops out', not EGrid[6, 6].Energized and not EGrid[6, 8].Energized);
  { a short circuit blows the fuse on its way }
  EPlace(2, 3, ekFuse);
  EWireLine(3, 5, 7, 5);
  EConnect(2, 5, 3, 5);
  EConnect(7, 5, 8, 5);
  SimFrame(1 / 60, True);
  Check('a short circuit blows the fuse', EGrid[2, 3].Tripped and not EGrid[6, 4].Energized);
  EErase(5, 5);
  EOperate(2, 3);
  SimFrame(1 / 60, True);
  Check('short removed, fuse replaced: the lamp is back', (not EGrid[2, 3].Tripped) and EGrid[6, 4].Energized);
  { undo: wiring is an undo step, working a switch is not }
  HistReset;
  EOperate(4, 4);
  HistCheck;
  Check('working a switch is not an undo step', not CanUndo);
  EPlace(5, 9, ekLamp);
  HistCheck;
  DoUndo;
  Check('placing a part can be undone', EGrid[5, 9].Kind <> ekLamp);
  { the circuit is saved with the layout }
  Check('save a circuit', SaveLayout(UnicodeString(FileName + '.elec.mflow'), err));
  np := ECount;
  DoNew;
  Check('a new layout has no circuit', ECount = 0);
  Check('load a circuit', LoadLayout(UnicodeString(FileName + '.elec.mflow'), err));
  Check('the circuit comes back', (ECount = np) and (EGrid[6, 6].Kind = ekRelay) and (EGrid[6, 6].Tag = 'K1') and
    (EGrid[5, 2].Kind = ekAC));

  { a 2-way switch sends L to one way or the other }
  DoNew;
  EWireLine(4, 2, 2, 2);
  EWireLine(2, 2, 2, 6);
  EWireLine(6, 2, 8, 2);
  EWireLine(8, 2, 8, 9);
  EWireLine(4, 6, 8, 6);
  EWireLine(3, 7, 3, 8);
  EWireLine(3, 8, 8, 8);
  EPlace(5, 2, ekAC);
  EPlace(3, 6, ekSw2);
  EPlace(6, 6, ekLamp);
  EPlace(6, 8, ekLamp);
  SimFrame(1 / 60, True);
  Check('2-way switch, position 1: the first lamp', EGrid[6, 6].Energized and not EGrid[6, 8].Energized);
  EOperate(3, 6);
  SimFrame(1 / 60, True);
  Check('2-way switch, position 2: the second lamp', EGrid[6, 8].Energized and not EGrid[6, 6].Energized);

  { example 11: start / stop with seal-in }
  RunMenuItem(MENU_EXAMPLES, 11);
  k := EquipByName('Belt01');
  SimFrame(1 / 60, True);
  Check('example 11: stopped at first', (Equips[k].State = EQS_STOP) and not EGrid[38, 11].Energized);
  EPress(30, 11, True);
  for i := 1 to 10 do SimFrame(1 / 60, True);
  EPress(30, 11, False);
  for i := 1 to 10 do SimFrame(1 / 60, True);
  Check('example 11: start seals KM1 in, the belt runs', EGrid[38, 11].Energized and (Equips[k].State = EQS_RUN) and
    EGrid[38, 14].Energized);
  for i := 1 to 240 do SimFrame(1 / 60, True);
  np := 0;
  for i := 0 to NPart - 1 do
    if (not Parts[i].InPipe) and (Parts[i].X > Equips[k].X + Equips[k].W) then Inc(np);
  Check('example 11: the belt carries the sand off its end', np > 5);
  EPress(27, 11, True);
  for i := 1 to 5 do SimFrame(1 / 60, True);
  EPress(27, 11, False);
  for i := 1 to 5 do SimFrame(1 / 60, True);
  Check('example 11: stop drops KM1, the belt stops', (not EGrid[38, 11].Energized) and (Equips[k].State = EQS_STOP) and
    EGrid[38, 16].Energized);
  EPress(30, 11, True);
  for i := 1 to 5 do SimFrame(1 / 60, True);
  EPress(30, 11, False);
  EOperate(24, 9);
  SimFrame(1 / 60, True);
  Check('example 11: the E-Stop stops it', not EGrid[38, 11].Energized);
  EOperate(24, 9);
  EPress(30, 11, True);
  for i := 1 to 5 do SimFrame(1 / 60, True);
  EPress(30, 11, False);
  SetEquipState(k, EQS_FAULT);
  for i := 1 to 5 do SimFrame(1 / 60, True);
  Check('example 11: a motor fault trips the overload and lights H3', EGrid[31, 6].Tripped and
    (not EGrid[38, 11].Energized) and EGrid[38, 18].Energized and EGrid[38, 20].Energized);

  { example 12: star, then delta }
  RunMenuItem(MENU_EXAMPLES, 12);
  k := EquipByName('Blower01');
  EPress(28, 11, True);
  for i := 1 to 10 do SimFrame(1 / 60, True);
  EPress(28, 11, False);
  for i := 1 to 50 do SimFrame(1 / 60, True);
  Check('star-delta: first star (KM1 + KM2, not KM3)', EGrid[40, 11].Energized and EGrid[40, 15].Energized and
    (not EGrid[40, 17].Energized) and (Equips[k].State = EQS_RUN));
  for i := 1 to 300 do SimFrame(1 / 60, True);
  Check('star-delta: after T1, delta (KM3, not KM2)', EGrid[40, 11].Energized and EGrid[40, 17].Energized and
    (not EGrid[40, 15].Energized) and (Equips[k].State = EQS_RUN));

  { example 13: the belt first, the rollers after T1 through the drive }
  RunMenuItem(MENU_EXAMPLES, 13);
  k := EquipByName('Conveyor01');
  b := EquipByName('Belt01');
  EPress(28, 12, True);
  for i := 1 to 10 do SimFrame(1 / 60, True);
  EPress(28, 12, False);
  for i := 1 to 30 do SimFrame(1 / 60, True);
  Check('conveyor line: the belt runs first', (Equips[b].State = EQS_RUN) and (Equips[k].State = EQS_STOP));
  for i := 1 to 200 do SimFrame(1 / 60, True);
  Check('conveyor line: then the rollers, at the drive speed', (Equips[k].State = EQS_RUN) and
    (Abs(Equips[k].Level - 70) < 0.5));

  { example 10: the well pump in AUTO follows the pool's float }
  RunMenuItem(MENU_EXAMPLES, 10);
  k := EquipByName('Pump01');
  b := EquipByName('Pool01');
  for i := 1 to 30 do SimFrame(1 / 60, True);
  Check('well pump: AUTO and a low pool start the pump', (Equips[k].State = EQS_RUN) and EGrid[38, 11].Energized);
  Equips[b].Level := 85;
  for i := 1 to 5 do SimFrame(1 / 60, True);
  Check('well pump: a full pool stops it', Equips[k].State = EQS_STOP);
  Equips[b].Level := 50;
  for i := 1 to 5 do SimFrame(1 / 60, True);
  Check('well pump: in between it stays off (hysteresis)', Equips[k].State = EQS_STOP);
  ESetSelectorPos(27, 11, 1);
  for i := 1 to 5 do SimFrame(1 / 60, True);
  Check('well pump: HAND runs it whatever the level', Equips[k].State = EQS_RUN);
  ESetSelectorPos(27, 11, 0);
  for i := 1 to 5 do SimFrame(1 / 60, True);
  Check('well pump: OFF stops it', Equips[k].State = EQS_STOP);
  ESetSelectorPos(27, 11, 2);
  Equips[b].Level := 10;
  Equips[EquipByName('Well01')].Level := 5;
  for i := 1 to 5 do SimFrame(1 / 60, True);
  Check('well pump: a dry well keeps it off (LS2)', Equips[k].State = EQS_STOP);

  { ---- potentiometer, current transformers, gauges and displays (example 14) }
  RunMenuItem(MENU_EXAMPLES, 14);
  k := EquipByName('Pump01');
  b := EquipByName('Motor01');
  for i := 1 to 60 do SimFrame(1 / 60, True);
  Check('meters: the pump runs at the potentiometer''s speed', (Equips[k].State = EQS_RUN) and
    (Abs(Equips[k].Level - 60) < 0.5) and (Abs(DriveSpeed(37, 5) - 60) < 0.5));
  Check('meters: CT1 measures the drive current', Abs(EGrid[29, 5].Amps - 5 * (0.05 + 0.95 * 0.6)) < 0.3);
  Check('meters: a gauge reads the CT', AnalogValue('CT1', bx, err) and (Abs(bx - EGrid[29, 5].Amps) < 0.001) and (err = 'A'));
  Check('meters: a display reads the potentiometer and a level', AnalogValue('RV1', bx, err) and (bx = 60) and
    AnalogValue('Pool01', by, err) and (Abs(by - Equips[EquipByName('Pool01')].Level) < 0.001));
  Check('meters: the supply voltage', AnalogValue('230VAC', bx, err) and (bx = 230) and (err = 'V'));
  { the mouse wheel turns the potentiometer }
  CanvasWheel(28 * CELL + HALF, 20 * CELL + HALF, 1);
  CanvasWheel(28 * CELL + HALF, 20 * CELL + HALF, 1);
  for i := 1 to 5 do SimFrame(1 / 60, True);
  Check('meters: the wheel turns RV1 up, the pump speeds up', (EGrid[28, 20].P1 = 70) and (Abs(Equips[k].Level - 70) < 0.5));
  { a direct-on-line start: inrush, then the rated current }
  EOperate(27, 13);
  for i := 1 to 3 do SimFrame(1 / 60, True);
  Check('meters: Motor01 starts with an inrush (CT2 > 20 A)', (Equips[b].State = EQS_RUN) and (EGrid[29, 7].Amps > 20));
  for i := 1 to 150 do SimFrame(1 / 60, True);
  Check('meters: ... settling to its rated 5 A', (EGrid[29, 7].Amps > 4.5) and (EGrid[29, 7].Amps < 6));
  Check('meters: the overload sees the same current', Abs(EGrid[32, 7].Amps - EGrid[29, 7].Amps) < 0.01);
  { the thermal overload trips after 2 s over its setting }
  EGrid[32, 7].P1 := 3;
  for i := 1 to 60 do SimFrame(1 / 60, True);
  Check('meters: not tripped within 2 s', not EGrid[32, 7].Tripped);
  for i := 1 to 120 do SimFrame(1 / 60, True);
  Check('meters: over the trip current for 2 s: OL2 trips, the motor stops', EGrid[32, 7].Tripped and
    (Equips[b].State = EQS_STOP) and (EGrid[29, 7].Amps < 0.01));
  { saved with the layout }
  Check('save the meters', SaveLayout(UnicodeString(FileName + '.meters.mflow'), err));
  DoNew;
  Check('load the meters', LoadLayout(UnicodeString(FileName + '.meters.mflow'), err));
  np := 0;
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and (Equips[i].Kind = EQ_GAUGE) and (Equips[i].Src = 'CT2') and (Equips[i].RMax = 40) then Inc(np);
  Check('the gauge, the drive''s potentiometer and the CT come back', (np = 1) and (EGrid[37, 5].Src = 'RV1') and
    (EGrid[29, 5].Kind = ekCT) and (EGrid[28, 20].Kind = ekPot) and (EGrid[32, 7].P1 = 3));
  Check('gauge, display, CT and pot tools', (ToolNames[tEqGauge] = 'Needle gauge') and (ToolNames[tEqDigital] = 'Digital display') and
    (TEKind(Ord(tElCT) - Ord(tElWire) + 1) = ekCT) and (TEKind(Ord(tElPot) - Ord(tElWire) + 1) = ekPot));

  { ---- Focus Properties windows }
  RunMenuItem(MENU_EXAMPLES, 7);
  InitWins;
  ApplyLayout;
  Zoom := 1;
  ViewX := 0;
  ViewY := 0;
  b := EquipByName('Blower01');
  k := EquipByName('Screw01');
  Equips[MasterSequence].Mode := SEQ_MANUAL;
  Check('no Focus windows at first', Length(Pins) = 0);
  { right-click Blower01, then Focus properties (popup item 7) }
  MX := Equips[b].X + Equips[b].W / 2;
  MY := Equips[b].Y + Equips[b].H - 20;
  OpenPopup;
  Check('right-click selects the equipment, the popup has Focus properties', PopupOpen and (SelKind = selEquip) and
    (SelEq = b) and (PopupCount = 7));
  MX := PopupX + 20;
  MY := PopupY + 4 + 6 * 20 + 10;
  PopupClick := True;
  DrawPopup;
  Check('Focus properties opens a window for it', (Length(Pins) = 1) and (TSelKind(Pins[0].Kind) = selEquip) and (Pins[0].A = b));
  MX := Equips[k].X + 40;
  MY := Equips[k].Y + 20;
  OpenPopup;
  MX := PopupX + 20;
  MY := PopupY + 4 + 6 * 20 + 10;
  PopupClick := True;
  DrawPopup;
  Check('any number of Focus windows: a second one', (Length(Pins) = 2) and (Pins[1].A = k));
  MX := Equips[k].X + 40;
  MY := Equips[k].Y + 20;
  OpenPopup;
  MX := PopupX + 20;
  MY := PopupY + 4 + 6 * 20 + 10;
  PopupClick := True;
  DrawPopup;
  Check('the same item twice: no second window', Length(Pins) = 2);
  Pins[0].X := 20;
  Pins[0].Y := 120;
  Pins[1].X := 420;
  Pins[1].Y := 120;
  { the selection goes elsewhere: the windows keep their items }
  SelKind := selNone;
  Render;
  Check('Focus windows stay on their items', (Pins[0].A = b) and (Pins[1].A = k) and (SelKind = selNone));
  { a click on a button of a Focus window works on its own item, not on the selection }
  SelKind := selEquip;
  SelEq := k;
  MX := Pins[0].X + 8 + 2 * 94 + 10;
  MY := Pins[0].Y + WIN_TITLE_H + 6 + 38 + 8;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MDown := False;
  MPressed := False;
  Check('a Focus window button works on its own item', (Equips[b].State = EQS_FAULT) and (Equips[k].State <> EQS_FAULT) and
    (SelKind = selEquip) and (SelEq = k));
  Check('a click on a Focus window does not reach the canvas', SelEq = k);
  { drag a window by its title }
  bx := Pins[0].X;
  MX := Pins[0].X + 60;
  MY := Pins[0].Y + 8;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MX := MX + 100;
  MPressed := False;
  Render;
  MDown := False;
  Render;
  Check('drag a Focus window by its title', (Abs(Pins[High(Pins)].X - (bx + 100)) < 0.5) and not Pins[High(Pins)].Dragging);
  { the windows belong to their page }
  AppAddPage;
  Check('another page: its Focus windows are not shown there', PinAt(20 + 100 + 60, 128) < 0);
  AppGoToPage(0);
  Check('back on the page: they are', PinAt(20 + 100 + 60, 128) >= 0);
  { the item goes: the window says so }
  i := -1;
  for np := 0 to High(Pins) do
    if Pins[np].A = k then i := np;
  DeleteEquip(k);
  Render;
  Check('a deleted item: its window stays, marked gone', (i >= 0) and not PinValid(Pins[i]));
  { close with x }
  np := Length(Pins);
  MX := Pins[High(Pins)].X + Pins[High(Pins)].W - 16 - 3 + 8;
  MY := Pins[High(Pins)].Y + 8;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MDown := False;
  MPressed := False;
  Check('x closes a Focus window', Length(Pins) = np - 1);
  { saved with the layout, on their page }
  np := Length(Pins);
  bx := Pins[0].X;
  Check('save the Focus windows', SaveLayout(UnicodeString(FileName + '.pins.mflow'), err));
  DoNew;
  Check('a new layout has no Focus windows', Length(Pins) = 0);
  Check('load the Focus windows', LoadLayout(UnicodeString(FileName + '.pins.mflow'), err));
  Check('the Focus windows come back where they were', (Length(Pins) = np) and (Pins[0].X = bx) and
    (TSelKind(Pins[0].Kind) = selEquip) and (Pins[0].Page = 0));
  DoNew;
  Check('a new layout closes them all', Length(Pins) = 0);

  { ---- virtual feeder: endless, what it emits has a lifetime }
  DoNew;
  PipeLine(5, 3, 5, 12, 3);
  SetKind(5, 3, ckVFeeder);
  SetKind(5, 12, ckDrop);
  Grid[5, 12].Strength := 100;
  Grid[5, 3].Strength := 2;
  bx := StoreTotal(Grid[5, 3]);
  for i := 1 to 150 do SimFrame(1 / 60, True);
  np := 0;
  nb := 0;
  for i := 0 to NPart - 1 do
    if Parts[i].Mat <> mAir then
    begin
      Inc(np);
      if Parts[i].Life > 2.01 then Inc(nb);
    end;
  Check('virtual feeder: material flows out', np > 20);
  Check('virtual feeder: its mix is never used up', StoreTotal(Grid[5, 3]) = bx);
  Check('virtual feeder: what it emits has its lifetime', nb = 0);
  Grid[5, 3].Feed := 0;
  for i := 1 to 200 do SimFrame(1 / 60, True);
  np := 0;
  for i := 0 to NPart - 1 do
    if Parts[i].Mat <> mAir then Inc(np);
  Check('virtual feeder: at the end of its life the material is gone', np = 0);
  Check('save a virtual feeder', SaveLayout(UnicodeString(FileName + '.vf.mflow'), err));
  DoNew;
  Check('load a virtual feeder', LoadLayout(UnicodeString(FileName + '.vf.mflow'), err) and
    (Grid[5, 3].Kind = ckVFeeder) and (Grid[5, 3].Strength = 2));
  Check('virtual feeder tool', (ToolKinds[tVFeeder] = ckVFeeder) and (KindNames[ckVFeeder] = 'Virtual feeder'));

  { ---- pneumatic and hydraulic circuits }
  Check('fluid power tools: 27 parts and the solenoid', (Ord(tFlPSwitch) - Ord(tFlLine) + 1 = 27) and
    (TFKind(Ord(tFlV52) - Ord(tFlLine) + 1) = fkV52) and (TEKind(Ord(tElSolenoid) - Ord(tElWire) + 1) = ekSolenoid));
  { 15: the supply, a manual 5/2 valve with throttles, a push-button 3/2 valve }
  RunMenuItem(MENU_EXAMPLES, 15);
  for i := 1 to 200 do SimFrame(1 / 60, True);
  Check('pneumatic: the FRL gives 6 bar', AnalogValue('PG1', bx, err) and (Abs(bx - 6) < 0.05) and (err = 'bar'));
  Check('pneumatic: the receiver fills', AnalogValue('R1', bx, err) and (bx > 3));
  Check('pneumatic: valve at rest, cylinder A in, A0 closed', (FGrid[33, 18].Sel = 0) and (FGrid[31, 10].Pos < 0.02) and
    TagActive('A0') and not TagActive('A1'));
  FOperate(33, 18);
  for i := 1 to 60 do SimFrame(1 / 60, True);
  bx := FGrid[31, 10].Pos;
  Check('pneumatic: V1 switched, A goes out (throttled)', (FGrid[33, 18].Sel = 1) and (bx > 0.1) and (bx < 0.6));
  for i := 1 to 300 do SimFrame(1 / 60, True);
  Check('pneumatic: A out, A1 closed, the equipment follows', (FGrid[31, 10].Pos > 0.98) and TagActive('A1') and
    (Equips[EquipByName('Cyl01')].Level > 98));
  FGrid[31, 14].P1 := 100;
  FGrid[35, 14].P1 := 100;
  FOperate(33, 18);
  for i := 1 to 60 do SimFrame(1 / 60, True);
  Check('pneumatic: throttles open: A comes back faster', 1 - FGrid[31, 10].Pos > bx * 1.5);
  FPress(39, 18, True);
  for i := 1 to 150 do SimFrame(1 / 60, True);
  Check('pneumatic: holding V2, single-acting B goes out', FGrid[37, 10].Pos > 0.98);
  FPress(39, 18, False);
  for i := 1 to 150 do SimFrame(1 / 60, True);
  Check('pneumatic: let go, its spring brings B back', FGrid[37, 10].Pos < 0.02);
  FOperate(24, 22);
  for i := 1 to 30 do SimFrame(1 / 60, True);
  Check('pneumatic: compressor off, the receiver keeps its pressure', (not FGrid[24, 22].Running) and (FGrid[27, 22].Store > 3));
  { saved with the layout }
  np := FCount;
  Check('save a fluid circuit', SaveLayout(UnicodeString(FileName + '.fluid.mflow'), err));
  DoNew;
  Check('a new layout has no fluid circuit', FCount = 0);
  Check('load a fluid circuit', LoadLayout(UnicodeString(FileName + '.fluid.mflow'), err));
  Check('the fluid circuit comes back', (FCount = np) and (FGrid[39, 18].Kind = fkV32) and (FGrid[39, 18].Act = 1) and
    (FGrid[31, 10].Kind = fkCylDA) and (FGrid[31, 10].Ref = 'Cyl01'));

  { 16: the electro-pneumatic gate runs its cycle }
  RunMenuItem(MENU_EXAMPLES, 16);
  for i := 1 to 60 do SimFrame(1 / 60, True);
  EPress(28, 5, True);
  for i := 1 to 10 do SimFrame(1 / 60, True);
  EPress(28, 5, False);
  bx := 0;
  k := 0;
  b := 0;
  for i := 1 to 900 do
  begin
    SimFrame(1 / 60, True);
    if FGrid[31, 19].Pos > bx then bx := FGrid[31, 19].Pos;
    if (bx > 0.98) and (FGrid[31, 19].Pos < 0.02) then k := 1;
    if Equips[EquipByName('Gate01')].State = EQS_RUN then b := 1;
  end;
  Check('electro-pneumatic: Y1 sends A out and the gate opens', (bx > 0.98) and (b = 1));
  Check('electro-pneumatic: after T1, Y2 brings A back', k = 1);

  { 17: AND / OR }
  RunMenuItem(MENU_EXAMPLES, 17);
  for i := 1 to 60 do SimFrame(1 / 60, True);
  FOperate(27, 20);
  for i := 1 to 120 do SimFrame(1 / 60, True);
  Check('AND: S1 alone does not move A', FGrid[30, 10].Pos < 0.02);
  FOperate(33, 20);
  for i := 1 to 120 do SimFrame(1 / 60, True);
  Check('AND: S1 and S2 move A', FGrid[30, 10].Pos > 0.98);
  FOperate(41, 20);
  for i := 1 to 120 do SimFrame(1 / 60, True);
  Check('OR: S4 alone moves B', FGrid[38, 10].Pos > 0.98);

  { 18: the pressure switch runs the compressor between 6 and 8 bar }
  RunMenuItem(MENU_EXAMPLES, 18);
  k := 0;
  b := 0;
  for i := 1 to 2400 do
  begin
    SimFrame(1 / 60, True);
    if FGrid[24, 28].Running and (k = 0) then k := 1;
    if (k = 1) and not FGrid[24, 28].Running then k := 2;
    if (k = 2) and FGrid[24, 28].Running then k := 3;
    if Equips[EquipByName('Belt01')].State = EQS_RUN then b := 1;
  end;
  Check('pressure switch: the compressor starts, stops at 8 bar and starts again', k = 3);
  Check('the air motor drives the belt', b = 1);

  { 19: hydraulic power unit, relief valve, 4/3 valve }
  RunMenuItem(MENU_EXAMPLES, 19);
  for i := 1 to 30 do SimFrame(1 / 60, True);
  Check('hydraulic: tandem centre, the pump unloads', AnalogValue('PG1', bx, err) and (bx < 10));
  FOperate(31, 22);
  for i := 1 to 30 do SimFrame(1 / 60, True);
  Check('hydraulic: V1 to 1: the relief valve caps it at 100 bar', AnalogValue('PG1', bx, err) and (Abs(bx - 100) < 0.5) and
    FGrid[27, 28].Running);
  for i := 1 to 180 do SimFrame(1 / 60, True);
  Check('hydraulic: the cylinder lifts', (FGrid[29, 12].Pos > 0.98) and (Equips[EquipByName('Lift01')].Level > 98));
  FOperate(31, 22);
  for i := 1 to 180 do SimFrame(1 / 60, True);
  Check('hydraulic: V1 to 2: it lowers', FGrid[29, 12].Pos < 0.02);

  { 20: the press cycle }
  RunMenuItem(MENU_EXAMPLES, 20);
  EPress(28, 4, True);
  for i := 1 to 10 do SimFrame(1 / 60, True);
  EPress(28, 4, False);
  bx := 0;
  k := 0;
  for i := 1 to 600 do
  begin
    SimFrame(1 / 60, True);
    if FGrid[29, 12].Pos > bx then bx := FGrid[29, 12].Pos;
    if (bx > 0.98) and (FGrid[29, 12].Pos < 0.02) then k := 1;
  end;
  Check('press: down to A1, then up to A0', (bx > 0.98) and (k = 1) and (FGrid[31, 22].Sel = 0));

  { 21: the hydraulic motor and its flow control }
  RunMenuItem(MENU_EXAMPLES, 21);
  for i := 1 to 60 do SimFrame(1 / 60, True);
  b := EquipByName('Conveyor01');
  Check('hydraulic motor: it drives the conveyor at the flow control''s 50%', FGrid[29, 15].Running and
    (Equips[b].State = EQS_RUN) and (Abs(Equips[b].Level - 50) < 0.5));
  FGrid[29, 19].P1 := 100;
  SimFrame(1 / 60, True);
  Check('hydraulic motor: FC1 open: full speed', Abs(Equips[b].Level - 100) < 0.5);
  Check('the accumulator stores the pressure', FGrid[29, 27].Store > 90);
  FOperate(31, 22);
  for i := 1 to 10 do SimFrame(1 / 60, True);
  Check('hydraulic motor: V1 back, it stops', (not FGrid[29, 15].Running) and (Equips[b].State = EQS_STOP));

  { ---- the physics lab }
  DoNew;
  HandleKey(SDLK_F8, 0);
  Check('F8 shows the physics lab, floating', Wins[WIN_LAB].Visible and not WinDocked(WIN_LAB));
  BringToFront(WIN_LAB);
  Render;
  Check('the lab starts with the built-in physics', not PhysicsChanged);
  MX := Wins[WIN_LAB].X + 8 + 3 * 56 + 10;
  MY := Wins[WIN_LAB].Y + WIN_TITLE_H + 6 + 13 + 8;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MDown := False;
  MPressed := False;
  Check('lab: pick a material (sand)', LabMat = mSand);
  bx := MatP[mSand].Mass;
  MX := Wins[WIN_LAB].X + 8 + 218 + 5;
  MY := Wins[WIN_LAB].Y + WIN_TITLE_H + 6 + 35 + 7;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MDown := False;
  MPressed := False;
  Check('lab: + raises the sand mass', (Abs(MatP[mSand].Mass - (bx + 0.05)) < 1e-4) and PhysicsChanged);
  GRAVITY := 1200;
  MatP[mWater].Liquid := False;
  Check('save the physics', SavePhysics(UnicodeString(FileName + '.mfphys'), err));
  PhysicsResetDefaults;
  Check('Reset gives the built-in physics', (not PhysicsChanged) and (MatP[mSand].Mass = bx) and MatP[mWater].Liquid);
  Check('load the physics', LoadPhysics(UnicodeString(FileName + '.mfphys'), err));
  Check('the physics comes back', (Abs(MatP[mSand].Mass - (bx + 0.05)) < 1e-4) and (GRAVITY = 1200) and
    not MatP[mWater].Liquid);
  { a broken file changes nothing }
  AssignFile(tf, FileName + '.bad.mfphys');
  Rewrite(tf);
  WriteLn(tf, 'MFPHYS 1');
  WriteLn(tf, 'WORLD 100 100 10 10 10');
  WriteLn(tf, 'MAT gold 1 1 1 1 1 1 1 0 1 1 1 1');
  CloseFile(tf);
  Check('a bad physics file is refused', (not LoadPhysics(UnicodeString(FileName + '.bad.mfphys'), err)) and
    (Pos('gold', err) > 0));
  Check('... and changes nothing', (GRAVITY = 1200) and not MatP[mWater].Liquid);
  Check('a layout file is not a physics file', not LoadPhysics(UnicodeString(FileName + '.fluid.mflow'), err));
  PhysicsResetDefaults;
  { the test scenes, on a page of their own }
  np := PageCount;
  LabTest(1);
  Check('lab: the drop test makes the "Physics lab" page', (PageCount = np + 1) and (PageName(CurPage) = LAB_PAGE));
  for i := 1 to 240 do SimFrame(1 / 60, True);
  k := 0;
  for i := 0 to MAX_BUCKETS - 1 do
    if Buckets[i].Active and (Buckets[i].Count > 0) then Inc(k);
  Check('lab: water, oil and sand fall into their buckets (fluff floats down slowly)', k >= 3);
  LabTest(2);
  Check('lab: a second test reuses the page', (PageCount = np + 1) and (PageName(CurPage) = LAB_PAGE));
  for i := 1 to 120 do SimFrame(1 / 60, True);
  Check('lab: the mix test runs', NPart > 20);
  LabTest(3);
  for i := 1 to 240 do SimFrame(1 / 60, True);
  k := 0;
  for i := 0 to NPart - 1 do
    if (Parts[i].Life > 0) and (Parts[i].Mat = mFluff) and Parts[i].InPipe then Inc(k);
  Check('lab: the air test blows material along its pipes', k > 0);
  { virtual feeders: their material does not last }
  b := 0;
  for i := 0 to NPart - 1 do
    if (Parts[i].Life > 0) and (Parts[i].Life > 1e8) then b := 1;
  Check('lab: the test material has a lifetime', b = 0);
  HandleKey(SDLK_F8, 0);
  Check('F8 hides the lab', not Wins[WIN_LAB].Visible);
  DoNew;

  { ---- the shape editor }
  DoNew;
  ShapesReset;
  HandleKey(SDLK_F9, 0);
  Check('F9 shows the shape editor, floating', Wins[WIN_SHAPE].Visible and not WinDocked(WIN_SHAPE));
  BringToFront(WIN_SHAPE);
  ShpPickKind(EQ_RECEIVER);
  ShpTool := PR_RECT;
  Render;
  Check('shape editor: a box in the receiver''s proportions', (ShpBW > 10) and (Abs(ShpBW / ShpBH - 64 / 144) < 0.01));
  { draw a rectangle: drag from 0.1, 0.2 to 0.9, 0.8 }
  MX := ShpBX + ShpBW * 0.1;
  MY := ShpBY + ShpBH * 0.2;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MPressed := False;
  MX := ShpBX + ShpBW * 0.9;
  MY := ShpBY + ShpBH * 0.8;
  Render;
  MDown := False;
  Render;
  Check('shape editor: drag draws a rectangle', (EqShapes[EQ_RECEIVER].N = 1) and (EqShapes[EQ_RECEIVER].P[0].Typ = PR_RECT) and
    (Abs(EqShapes[EQ_RECEIVER].P[0].X1 - 0.1) < 0.03) and (Abs(EqShapes[EQ_RECEIVER].P[0].Y2 - 0.8) < 0.03) and
    ShapeDefined(EQ_RECEIVER));
  { a click without a drag: an ellipse of a usual size }
  ShpTool := PR_ELLIPSE;
  MX := ShpBX + ShpBW * 0.5;
  MY := ShpBY + ShpBH * 0.1;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MDown := False;
  MPressed := False;
  Render;
  Check('shape editor: a click draws an ellipse of a usual size', (EqShapes[EQ_RECEIVER].N = 2) and
    (Abs(EqShapes[EQ_RECEIVER].P[1].X2 - EqShapes[EQ_RECEIVER].P[1].X1 - 0.2) < 0.01) and (ShpSel = 1));
  { select the rectangle and move it }
  ShpTool := -1;
  MX := ShpBX + ShpBW * 0.5;
  MY := ShpBY + ShpBH * 0.6;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MPressed := False;
  MY := MY + ShpBH * 0.1;
  Render;
  MDown := False;
  Render;
  Check('shape editor: select and move a part', (ShpSel = 0) and (Abs(EqShapes[EQ_RECEIVER].P[0].Y1 - 0.3) < 0.03) and
    (Abs(EqShapes[EQ_RECEIVER].P[0].Y2 - 0.9) < 0.03));
  { its corner }
  MX := ShpBX + ShpBW * EqShapes[EQ_RECEIVER].P[0].X2;
  MY := ShpBY + ShpBH * EqShapes[EQ_RECEIVER].P[0].Y2;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MPressed := False;
  MX := ShpBX + ShpBW * 0.7;
  Render;
  MDown := False;
  Render;
  Check('shape editor: drag a corner to resize', (ShpSel = 0) and (Abs(EqShapes[EQ_RECEIVER].P[0].X2 - 0.7) < 0.03) and
    (Abs(EqShapes[EQ_RECEIVER].P[0].X1 - 0.1) < 0.03));
  ShpSel := ShapeMove(EQ_RECEIVER, 0, 1);
  Check('shape editor: Up puts the part over the next one', (ShpSel = 1) and (EqShapes[EQ_RECEIVER].P[1].Typ = PR_RECT) and
    (EqShapes[EQ_RECEIVER].P[0].Typ = PR_ELLIPSE));
  EqShapes[EQ_RECEIVER].P[1].StateCol := False;
  EqShapes[EQ_RECEIVER].P[1].R := 12;
  ShapeAdd(EQ_RECEIVER, PR_LINE, 0, 0, 1, 1);
  ShapeAdd(EQ_RECEIVER, PR_TRI, 0, 1, 1, 0);
  EqShapes[EQ_RECEIVER].W := 80;
  EqShapes[EQ_RECEIVER].H := 120;
  { the canvas draws the shape, flipped too; new pieces take its size }
  b := AddEquip(EQ_RECEIVER, 300, 200);
  Check('a kind''s own size for new pieces', (b >= 0) and (Equips[b].W = 80) and (Equips[b].H = 120));
  Equips[b].Flip := True;
  Render;
  Check('the canvas draws the custom shape', ShapeDefined(Equips[b].Kind));
  { saved and loaded apart from the layout }
  Check('save the shapes', SaveShapes(UnicodeString(FileName + '.mfshape'), err));
  ShapesReset;
  Check('All: every kind built-in again', (ShapesCount = 0) and not ShapeDefined(EQ_RECEIVER));
  Check('load the shapes', LoadShapes(UnicodeString(FileName + '.mfshape'), err));
  Check('the shapes come back', (ShapesCount = 1) and (EqShapes[EQ_RECEIVER].N = 4) and (EqShapes[EQ_RECEIVER].P[1].R = 12) and
    not EqShapes[EQ_RECEIVER].P[1].StateCol and (EqShapes[EQ_RECEIVER].P[3].Typ = PR_TRI) and (EqShapes[EQ_RECEIVER].W = 80));
  AssignFile(tf, FileName + '.bad.mfshape');
  Rewrite(tf);
  WriteLn(tf, 'MFSHAPE 1');
  WriteLn(tf, 'KIND motor 0 0');
  WriteLn(tf, 'PRIM star 0 0 1 1 1 1 1 255 1 1 2');
  CloseFile(tf);
  Check('a bad shape file is refused', (not LoadShapes(UnicodeString(FileName + '.bad.mfshape'), err)) and (Pos('star', err) > 0));
  Check('... and changes nothing', (ShapesCount = 1) and (EqShapes[EQ_RECEIVER].N = 4));
  { Clear on the panel: the kind's built-in drawing again }
  ShpPickKind(EQ_RECEIVER);
  Render;
  MX := Wins[WIN_SHAPE].X + 8 + 140 + 10;
  MY := Wins[WIN_SHAPE].Y + WIN_TITLE_H + 6 + 46 + SHP_BOX_H + 6 + 21 + 120 + 13 + 42 + 8;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MDown := False;
  MPressed := False;
  Check('Clear gives the kind its built-in drawing', not ShapeDefined(EQ_RECEIVER));
  ShapesReset;
  EquipDefaultSize(EQ_RECEIVER, bx, by);
  Check('... and its built-in size', (bx = 64) and (by = 144));
  HandleKey(SDLK_F9, 0);
  Check('F9 hides the shape editor', not Wins[WIN_SHAPE].Visible);
  DoNew;

  { ---- resizable panels: the lab grows by its corner, its content scales and still works }
  DoNew;
  HandleKey(SDLK_F8, 0);
  Wins[WIN_LAB].X := 300;
  Wins[WIN_LAB].Y := 20;
  BringToFront(WIN_LAB);
  Render;
  MX := Wins[WIN_LAB].X + Wins[WIN_LAB].W - 5;
  MY := Wins[WIN_LAB].Y + Wins[WIN_LAB].H - 5;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MPressed := False;
  MX := Wins[WIN_LAB].X + 296 * 1.4 - 5;
  MY := Wins[WIN_LAB].Y + 10;
  Render;
  MDown := False;
  Render;
  Check('drag the corner: the lab grows, its content with it', (Abs(Wins[WIN_LAB].Scale - 1.4) < 0.02) and
    (Abs(Wins[WIN_LAB].W - 296 * Wins[WIN_LAB].Scale) < 0.1) and not Wins[WIN_LAB].Sizing);
  bx := Wins[WIN_LAB].Scale;
  LabMat := mWater;
  MX := (Wins[WIN_LAB].X / bx + 8 + 3 * 56 + 10) * bx;
  MY := ((Wins[WIN_LAB].Y + WIN_TITLE_H) / bx + 6 + 13 + 8) * bx;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MDown := False;
  MPressed := False;
  Check('a button in a scaled panel works where it is drawn', LabMat = mSand);
  SettingsFile := FileName + '.scale.ini';
  SaveSettings;
  SetWinScale(WIN_LAB, 1);
  LoadSettings;
  Check('the size of a panel is kept in the settings', Abs(Wins[WIN_LAB].Scale - bx) < 0.02);
  SettingsFile := '';
  DockWin(WIN_LAB);
  Check('docking puts it back to its normal size', Wins[WIN_LAB].Scale = 1);
  InitWins;
  ApplyLayout;

  { ---- control tools: the Control tab places sensors and controllers, fluid tools place fluid parts }
  DoNew;
  Check('a Control tab with the counter, 7 sensors and the controller', (ToolTabOf(tCtCounter) = 4) and
    (ElecToolKind(tCtController) = ekController) and (ElecToolKind(tCtLevel) = ekLevelTx) and
    (ElecToolKind(tElSolenoid) = ekSolenoid) and (Ord(tCtController) - Ord(tCtCounter) = 8));
  Tool := tCtFlow;
  MX := 6 * CELL + HALF;
  MY := 6 * CELL + HALF;
  CanvasPress(False);
  Drag := dragNone;
  Check('the Flow FT tool places a flow sensor FT1', (EGrid[6, 6].Kind = ekFlowTx) and (EGrid[6, 6].Tag = 'FT1'));
  Tool := tFlV52;
  MX := 9 * CELL + HALF;
  CanvasPress(False);
  Drag := dragNone;
  Check('a fluid tool places its fluid part', FGrid[9, 6].Kind = fkV52);
  Tool := tSelect;

  { ---- timers: on-delay, off-delay, pulse, flasher }
  DoNew;
  EWireLine(2, 2, 6, 2);
  EWireLine(8, 2, 14, 2);
  EWireLine(2, 2, 2, 8);
  EWireLine(14, 2, 14, 8);
  EPlace(7, 2, ekAC);
  EWireLine(2, 4, 14, 4);
  EPlace(5, 4, ekSwitch);
  EGrid[5, 4].Tag := 'S1';
  EPlace(11, 4, ekTimer);
  EGrid[11, 4].Tag := 'T1';
  EGrid[11, 4].P1 := 1;
  EGrid[11, 4].P2 := 1;
  { the counter: push button SB1 pulses it, SB2 resets it }
  EWireLine(2, 6, 14, 6);
  EPlace(5, 6, ekPBNO);
  EGrid[5, 6].Tag := 'SB1';
  EPlace(11, 6, ekCounter);
  EGrid[11, 6].Tag := 'CNT1';
  EGrid[11, 6].P1 := 3;
  EGrid[11, 6].Src := 'SB2';
  EPlace(5, 10, ekPBNO);
  EGrid[5, 10].Tag := 'SB2';
  { on-delay }
  EGrid[5, 4].On := True;
  for i := 1 to 30 do SimFrame(1 / 60, True);
  b := Ord(TagActive('T1'));
  for i := 1 to 40 do SimFrame(1 / 60, True);
  Check('on-delay: on 1 s after its power comes', (b = 0) and TagActive('T1'));
  EGrid[5, 4].On := False;
  SimFrame(1 / 60, True);
  Check('on-delay: off with the power', not TagActive('T1'));
  { off-delay }
  EGrid[11, 4].Pos := 1;
  EGrid[5, 4].On := True;
  SimFrame(1 / 60, True);
  b := Ord(TagActive('T1'));
  EGrid[5, 4].On := False;
  for i := 1 to 30 do SimFrame(1 / 60, True);
  k := Ord(TagActive('T1'));
  for i := 1 to 40 do SimFrame(1 / 60, True);
  Check('off-delay: on at once, still on 0.5 s after, off after 1 s', (b = 1) and (k = 1) and not TagActive('T1'));
  { pulse }
  EGrid[11, 4].Pos := 2;
  EGrid[5, 4].On := True;
  SimFrame(1 / 60, True);
  b := Ord(TagActive('T1'));
  for i := 1 to 90 do SimFrame(1 / 60, True);
  Check('pulse: one pulse of 1 s while the power stays', (b = 1) and not TagActive('T1') and EGrid[11, 4].Energized);
  EGrid[5, 4].On := False;
  SimFrame(1 / 60, True);
  { flasher: 1 s on, 1 s off }
  EGrid[11, 4].Pos := 3;
  EGrid[5, 4].On := True;
  k := 0;
  b := Ord(TagActive('T1'));
  for i := 1 to 240 do
  begin
    SimFrame(1 / 60, True);
    if Ord(TagActive('T1')) <> b then
    begin
      Inc(k);
      b := Ord(TagActive('T1'));
    end;
  end;
  Check(Format('flasher: blinks (%d changes in 4 s)', [k]), (k >= 3) and (k <= 5));
  EGrid[5, 4].On := False;
  Check('timer text names its mode', Pos('Flasher', EStateText(11, 4)) > 0);
  { counter }
  for k := 1 to 3 do
  begin
    EPress(5, 6, True);
    SimFrame(1 / 60, True);
    SimFrame(1 / 60, True);
    EPress(5, 6, False);
    SimFrame(1 / 60, True);
    if k = 2 then b := Ord(TagActive('CNT1'));
  end;
  Check('counter: three pulses, its contacts close at the preset 3', (EGrid[11, 6].Acc = 3) and (b = 0) and
    TagActive('CNT1') and AnalogValue('CNT1', bx, err) and (bx = 3) and (err = 'pcs'));
  EPress(5, 10, True);
  SimFrame(1 / 60, True);
  EPress(5, 10, False);
  SimFrame(1 / 60, True);
  Check('counter: its reset button sets it back to 0', (EGrid[11, 6].Acc = 0) and not TagActive('CNT1'));
  EGrid[11, 6].Acc := 2;
  EOperate(11, 6);
  Check('counter: a click resets it too', EGrid[11, 6].Acc = 0);
  { saved with the layout: mode, preset, reset tag, controller integral }
  EGrid[11, 4].P2 := 2.5;
  EPlace(11, 8, ekController);
  EGrid[11, 8].Tag := 'IC1';
  EGrid[11, 8].P3 := 7.5;
  EGrid[11, 8].Src := 'CNT1';
  Check('save timers and counters', SaveLayout(UnicodeString(FileName + '.ctrl.mflow'), err));
  DoNew;
  Check('load timers and counters', LoadLayout(UnicodeString(FileName + '.ctrl.mflow'), err));
  Check('they come back', (EGrid[11, 4].Pos = 3) and (EGrid[11, 4].P2 = 2.5) and (EGrid[11, 6].Kind = ekCounter) and
    (EGrid[11, 6].P1 = 3) and (EGrid[11, 6].Src = 'SB2') and (EGrid[11, 8].P3 = 7.5) and (EGrid[11, 8].Src = 'CNT1'));

  { ---- example 22: timers & counter dose five batches }
  RunMenuItem(MENU_EXAMPLES, 22);
  k := 0;
  for i := 1 to 60 * 30 do
  begin
    SimFrame(1 / 60, True);
    if (k = 0) and TagActive('CNT1') then k := i;
  end;
  Check(Format('batching: the count reaches 5 (%.0f) and H1 lights', [EGrid[39, 11].Acc]), (k > 0) and
    (EGrid[39, 11].Acc = 5) and EGrid[39, 13].Energized);
  Check('batching: the flasher stopped, the gate is shut', (not EGrid[39, 5].Energized) and
    (Equips[EquipByName('Slide01')].State = EQS_STOP));
  Check('batching: the weight sensor weighs the batches', AnalogValue('WT1', bx, err) and (bx > 1) and (err = 'kg'));
  EPress(28, 19, True);
  SimFrame(1 / 60, True);
  EPress(28, 19, False);
  for i := 1 to 30 do SimFrame(1 / 60, True);
  Check('batching: SB1 resets the count and the flasher starts again', (EGrid[39, 11].Acc < 5) and EGrid[39, 5].Energized);

  { ---- example 23: sensors, a PID level loop and an on / off temperature loop }
  RunMenuItem(MENU_EXAMPLES, 23);
  for i := 1 to 60 * 20 do SimFrame(1 / 60, True);
  Check('level sensor LT1 reads Pool01', Abs(EGrid[13, 30].Val - Equips[EquipByName('Pool01')].Level) < 0.5);
  Check('pressure, flow and speed sensors read the running pump line', (EGrid[8, 20].Val > 1) and (EGrid[8, 14].Val > 0.5) and
    (EGrid[4, 30].Val > 100));
  Check('LIC1 (PID) runs drive U1 hard while the level is low', (EGrid[40, 3].Val < 60) and (EGrid[40, 3].Out > 50) and
    (DriveSpeed(40, 5) = EGrid[40, 3].Out));
  bx := 1e9;
  by := -1e9;
  for i := 1 to 60 * 40 do
  begin
    SimFrame(1 / 60, True);
    if i > 60 * 20 then
    begin
      bx := fmin(bx, Equips[EquipByName('Heater01')].Temp);
      by := fmax(by, Equips[EquipByName('Heater01')].Temp);
    end;
  end;
  Check(Format('TIC1 (on / off) holds Heater01 near 150 C (%.0f..%.0f)', [bx, by]), (bx > 125) and (by < 175) and (by > 148));
  Check(Format('LIC1 brings Pool01 near its 60%% set point (%.1f)', [EGrid[40, 3].Val]), Abs(EGrid[40, 3].Val - 60) < 12);
  Check('a controller''s PV, SP and output by name', AnalogValue('LIC1.SP', bx, err) and (bx = 60) and
    AnalogValue('LIC1.PV', by, err) and (by = EGrid[40, 3].Val) and AnalogValue('TIC1', bx, err) and (err = '%'));
  EGrid[40, 3].P1 := 40;
  for i := 1 to 60 * 3 do SimFrame(1 / 60, True);
  Check('a lower set point: LIC1 slows the pump down', EGrid[40, 3].Out < 30);
  SelKind := selEquip;
  SelEq := EquipByName('Level control');
  Render;
  Check('the faceplate shows its controller', Equips[SelEq].Kind = EQ_CONTROLLER);

  { ---- example 24: every page runs at the same time }
  RunMenuItem(MENU_EXAMPLES, 24);
  Check('example 24 has four pages', (PageCount = 4) and (PageName(2) = 'Pump house') and (PageName(3) = 'Monitor'));
  for i := 1 to 10 do SimAllPages(1 / 60, True);
  Check('page 1 reads the pool on page 3 over the plant bus', AnalogValue('Pool01', bx, err) and (Abs(bx - 40) < 2) and
    (Abs(EGrid[20, 22].Val - bx) < 0.5));
  b := -1;
  for k := 0 to MAX_EQUIP - 1 do
    if Pages[2].Equips[k].Active and (Pages[2].Equips[k].Name = 'Pump01') then b := k;
  Check('the pump on page 3 waits', (b >= 0) and (Pages[2].Equips[b].State = EQS_STOP));
  EPress(14, 8, True);
  for i := 1 to 10 do SimAllPages(1 / 60, True);
  EPress(14, 8, False);
  for i := 1 to 60 do SimAllPages(1 / 60, True);
  Check('SB1 on page 1: K1, LIC1 and KM1 run the pump on page 3', TagActive('K1') and TagActive('KM1') and
    (Pages[2].Equips[b].State = EQS_RUN));
  Check('page 1 measures the current of the pump on page 3', AnalogValue('CT1', bx, err) and (bx > 1));
  for i := 1 to 60 * 20 do SimAllPages(1 / 60, True);
  for k := 0 to MAX_EQUIP - 1 do
    if Pages[2].Equips[k].Active and (Pages[2].Equips[k].Name = 'Pool01') then np := k;
  Check(Format('the pool on page 3 fills while page 1 is shown (%.0f%%)', [Pages[2].Equips[np].Level]),
    (Pages[2].Equips[np].Level > 45) and (Pages[2].NPart > 0));
  AppGoToPage(3);
  for i := 1 to 3 do SimAllPages(1 / 60, True);
  Check('page 4 shows values from pages 1 and 3', AnalogValue('LIC1.SP', bx, err) and (bx = 70) and
    AnalogValue('Pool01', by, err) and (by > 45) and AnalogValue('LT1', fw, err));
  Check('a faceplate shows a controller on another page', FaceValues('LIC1', bx, by, fw, b2) and (by = 70) and b2);
  AppGoToPage(2);
  for i := 1 to 3 do SimAllPages(1 / 60, True);
  Check('page 3 shown: the pump still runs from page 1', Equips[EquipByName('Pump01')].State = EQS_RUN);
  AppGoToPage(0);
  DoNew;
  Check('a new layout clears the plant bus', not BusTagActive('K1'));

  { ---- humidity sensor and heat exchanger }
  Check('humidity and heat exchanger tools', (ElecToolKind(tCtHumid) = ekHumidTx) and (ToolTabOf(tCtHumid) = 4) and
    (ToolTabOf(tEqHeatEx) = 1) and (EquipTags[EQ_HEATEX] = 'heatex') and EquipActuated(EQ_HEATEX));
  DoNew;
  EPlace(10, 10, ekHumidTx);
  EGrid[10, 10].Tag := 'MT1';
  for i := 1 to 60 * 4 do SimFrame(1 / 60, True);
  Check(Format('air RH: about 45 %% in dry air (%.1f)', [EGrid[10, 10].Val]), Abs(EGrid[10, 10].Val - 45) < 2);
  b := AddEquip(EQ_RAIN, 10 * CELL - 60, 10 * CELL - 120);
  SetEquipState(b, EQS_RUN);
  for i := 1 to 60 * 5 do SimFrame(1 / 60, True);
  Check(Format('air RH: rain near it makes it wetter (%.1f %%RH)', [EGrid[10, 10].Val]), (EGrid[10, 10].Val > 65) and
    AnalogValue('MT1', bx, err) and (err = '%RH'));
  { the heat exchanger tool links to the pipe it is put on }
  DoNew;
  PipeLine(4, 6, 20, 6, 3);
  Tool := tEqHeatEx;
  MX := 12 * CELL + HALF;
  MY := 6 * CELL + HALF;
  CanvasPress(False);
  Drag := dragNone;
  Tool := tSelect;
  b := EquipByName('HX01');
  Check('the heat exchanger tool: HX01 on the pipe, linked, its hot side on', (b >= 0) and (Equips[b].Kind = EQ_HEATEX) and
    (Equips[b].LinkX = 12) and (Equips[b].LinkY = 6) and (Equips[b].State = EQS_RUN) and (Equips[b].RMax = 120));

  { example 25: TIC1 holds the shell outlet at 80 C; humidity of the air and of the sand }
  RunMenuItem(MENU_EXAMPLES, 25);
  b := EquipByName('HX01');
  for i := 1 to 60 * 40 do SimFrame(1 / 60, True);
  Check(Format('heat exchanger: TIC1 holds the shell outlet near 80 C (%.1f, hot flow %.0f%%)', [Equips[b].Temp,
    Equips[b].Level]), (Abs(Equips[b].Temp - 80) < 8) and (Equips[b].Level > 5) and (Equips[b].Level < 100));
  Check(Format('heat exchanger: hot side cools %.0f -> %.0f C, %.0f kW', [Equips[b].HotIn, Equips[b].HotOut, Equips[b].Duty]),
    (Equips[b].HotIn = 160) and (Equips[b].HotOut < 155) and (Equips[b].HotOut > 20) and (Equips[b].Duty > 1));
  Check('TT1 reads the shell outlet; HX01, HX01.HOT, HX01.KW by name', (Abs(EGrid[13, 9].Val - Equips[b].Temp) < 0.5) and
    AnalogValue('HX01', bx, err) and (err = 'C') and AnalogValue('HX01.HOT', by, err) and (by = Equips[b].HotOut) and
    AnalogValue('HX01.KW', fw, err) and (err = 'kW'));
  Check(Format('MT2: the moisture of the wet sand in the bucket (%.0f %%)', [EGrid[20, 33].Val]),
    (EGrid[20, 33].Val > 35) and (EGrid[20, 33].Val < 90) and AnalogValue('MT2', bx, err) and (err = '%'));
  Check(Format('MT1: the air by the falling stream is wet (%.0f %%RH)', [EGrid[21, 15].Val]), EGrid[21, 15].Val > 50);
  { energy balance: what the shell takes is what the tubes give }
  bx := CellSpeed(13, 6) / CELL / 16;
  if bx > 2 then bx := 2;
  by := Equips[b].Level / 100;
  Check(Format('heat exchanger: energy balance (%.1f / %.1f)', [bx * (Equips[b].Temp - 20), by * (160 - Equips[b].HotOut)]),
    Abs(bx * (Equips[b].Temp - 20) - by * (160 - Equips[b].HotOut)) < 0.15 * by * (160 - Equips[b].HotOut) + 2);
  { no hot flow: the shell stream leaves as cold as it came }
  EGrid[28, 4].On := False;
  for i := 1 to 60 * 15 do SimFrame(1 / 60, True);
  Check(Format('no hot flow: the outlet cools to 20 C (%.1f), no duty', [Equips[b].Temp]), (Equips[b].Temp < 25) and
    (Equips[b].Duty < 10));
  { no cold flow: the still shell takes the hot side's temperature }
  EGrid[28, 4].On := True;
  EGrid[39, 6].Src := '';
  EGrid[39, 6].P1 := 100;
  Equips[b].LinkX := -1;
  for i := 1 to 60 * 15 do SimFrame(1 / 60, True);
  Check(Format('no cold flow: the still shell heats up to the hot side (%.1f)', [Equips[b].Temp]), Equips[b].Temp > 130);
  Equips[b].LinkX := 13;
  { saved with the layout }
  Check('save a heat exchanger and humidity sensors', SaveLayout(UnicodeString(FileName + '.hx.mflow'), err));
  DoNew;
  Check('load them', LoadLayout(UnicodeString(FileName + '.hx.mflow'), err));
  b := EquipByName('HX01');
  Check('they come back', (b >= 0) and (Equips[b].Kind = EQ_HEATEX) and (Equips[b].RMax = 160) and
    (EGrid[20, 33].Kind = ekHumidTx) and (EGrid[20, 33].Pos = 1) and (EGrid[21, 15].Pos = 0));
  DoNew;

  { ---- a panel too short for its content scrolls }
  DoNew;
  HandleKey(SDLK_F8, 0);
  Wins[WIN_LAB].BaseH := 300;
  SetWinScale(WIN_LAB, 1);
  Wins[WIN_LAB].X := 300;
  Wins[WIN_LAB].Y := 40;
  BringToFront(WIN_LAB);
  Render;
  Render;
  bx := Wins[WIN_LAB].ContentH - (Wins[WIN_LAB].H - WIN_TITLE_H - 2);
  Check(Format('the lab: content taller than the window (%.0f px more)', [bx]), bx > 100);
  Wins[WIN_LAB].Scroll := 5000;
  Render;
  Check('scrolled to the end and no further', Abs(Wins[WIN_LAB].Scroll - bx) < 1);
  LabMat := mWater;
  MX := Wins[WIN_LAB].X + 8 + 3 * 56 + 10;
  MY := Wins[WIN_LAB].Y + WIN_TITLE_H + 6 - Wins[WIN_LAB].Scroll + 13 + 8;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MDown := False;
  MPressed := False;
  Check('a button scrolled out of sight does not take a click', LabMat = mWater);
  { drag the thumb back to the top }
  MX := Wins[WIN_LAB].X + Wins[WIN_LAB].W - 5;
  MY := Wins[WIN_LAB].Y + WIN_TITLE_H + 3 + (Wins[WIN_LAB].H - WIN_TITLE_H - 2 - 18) - 4;
  MouseDown(SDL_BUTTON_LEFT);
  Render;
  MPressed := False;
  MY := MY - 400;
  Render;
  MDown := False;
  Render;
  Check(Format('drag the scrollbar back to the top (%.0f)', [Wins[WIN_LAB].Scroll]), Wins[WIN_LAB].Scroll < 1);
  { the mouse wheel over the panel }
  MX := Wins[WIN_LAB].X + 100;
  MY := Wins[WIN_LAB].Y + 100;
  with Wins[WinAt(MX, MY)] do Scroll := Scroll - (-2) * 40;
  Render;
  Check('the wheel scrolls it', Abs(Wins[WIN_LAB].Scroll - 80) < 1);
  InitWins;
  ApplyLayout;

  { ---- pH: each material's own pH, mixed by mass; saved with the physics }
  Check('cooling tower, chiller and pH sensor tools', (ElecToolKind(tCtPH) = ekPHTx) and (ToolTabOf(tEqChiller) = 1) and
    EquipActuated(EQ_COOLTOWER) and EquipActuated(EQ_CHILLER) and (Abs(MatP[mSand].PH - 8.8) < 0.01) and (MatP[mWater].PH = 7));
  MatP[mSand].PH := 9.5;
  Check('save the physics with pH', SavePhysics(UnicodeString(FileName + '.ph.mfphys'), err));
  PhysicsResetDefaults;
  Check('load it: the pH comes back', LoadPhysics(UnicodeString(FileName + '.ph.mfphys'), err) and (Abs(MatP[mSand].PH - 9.5) < 0.01));
  PhysicsResetDefaults;

  { ---- example 26: cooling tower loop, chiller loop, pH }
  RunMenuItem(MENU_EXAMPLES, 26);
  for i := 1 to 60 * 60 do SimFrame(1 / 60, True);
  b := EquipByName('HX01');
  k := EquipByName('Tower01');
  np := EquipByName('Chiller01');
  Check(Format('cooling tower: TIC1 holds stream 1 near 40 C (%.1f, fan %.0f%%)', [Equips[b].Temp, Equips[k].Level]),
    (Abs(Equips[b].Temp - 40) < 5) and (Equips[k].Level > 5));
  Check(Format('cooling tower: water %.1f -> %.1f C, above the wet bulb', [Equips[k].HotIn, Equips[k].Temp]),
    (Equips[k].Temp < Equips[k].HotIn - 3) and (Equips[k].Temp > 21) and (Abs(Equips[k].HotIn - Equips[b].HotOut) < 0.5) and
    AnalogValue('Tower01.KW', bx, err) and (bx > 10));
  nb := 0;
  for i := 0 to NPart - 1 do
    if (Parts[i].Life > 0) and (Parts[i].Mat = mAir) and (Parts[i].ExitDir = STEAM_MARK) then Inc(nb);
  Check(Format('cooling tower: a plume of vapour (%d), the air above it is moist (%.0f %%RH)', [nb, EGrid[28, 22].Val]),
    (nb > 3) and (EGrid[28, 22].Val > 50));
  Check(Format('chiller: chilled water at its 7 C set point (%.1f), stream 2 cooled to %.1f C', [Equips[np].Temp,
    Equips[EquipByName('HX02')].Temp]), (Abs(Equips[np].Temp - 7) < 1.5) and (Equips[EquipByName('HX02')].Temp < 25) and
    AnalogValue('Chiller01.IN', bx, err) and (bx > Equips[np].Temp + 3));
  Check(Format('pH: stream 1 (water and sand) %.2f, stream 2 (water and fluff) %.2f', [EGrid[22, 33].Val, EGrid[13, 33].Val]),
    (EGrid[22, 33].Val > 7) and (EGrid[22, 33].Val < 8.8) and (EGrid[13, 33].Val > 5.5) and (EGrid[13, 33].Val < 7) and
    AnalogValue('PH1', bx, err) and (err = 'pH'));
  MatP[mSand].PH := 10;
  SimFrame(1 / 60, True);
  Check('pH: the sand made more alkaline in the Physics lab, PH1 rises', EGrid[22, 33].Val > 7.2);
  PhysicsResetDefaults;
  EGrid[29, 7].On := False;
  for i := 1 to 60 * 20 do SimFrame(1 / 60, True);
  Check(Format('chiller off: the water comes back warm (%.1f C)', [Equips[np].Temp]), Equips[np].Temp > 12);
  Check('save the tower and the chiller', SaveLayout(UnicodeString(FileName + '.ct.mflow'), err));
  DoNew;
  Check('load them', LoadLayout(UnicodeString(FileName + '.ct.mflow'), err));
  k := EquipByName('Tower01');
  np := EquipByName('Chiller01');
  Check('they come back', (k >= 0) and (Equips[k].Kind = EQ_COOLTOWER) and (Equips[k].Src = 'HX01') and (np >= 0) and
    (Equips[np].RMax = 7) and (Equips[np].Src = 'HX02') and (EGrid[22, 33].Kind = ekPHTx));
  DoNew;

  { themes }
  for i := 0 to THEME_COUNT - 1 do
  begin
    SelectTheme(i);
    Check('theme ' + Th.Name, (ThemeIndex = i) and (Th.Name = Themes[i].Name));
  end;
  SelectTheme(0);

  WriteLn(f, Format('%d failure(s)', [fails]));
  CloseFile(f);
end;

procedure RunApp;
var
  ev: TSDL_Event;
  last, now: UInt64;
  shotFrames, frame: Integer;
  shotFile: string;
  ww, wh: Integer;
  db: TSDL_Rect;
  sc: Single;
  m: TMat;
  surf: PSDL_Surface;
  n: Integer;
  err: string;
begin
  Randomize;
  { C libraries (SDL, GPU drivers) expect FPU exceptions to be masked }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  if not SDL_Init(SDL_INIT_VIDEO) then
    raise Exception.Create('SDL_Init failed: ' + string(SDL_GetError));

  { --export-examples <dir> : write the built-in examples as .mflow files }
  if (ParamCount >= 2) and (ParamStr(1) = '--export-examples') then
  begin
    { the original demo as a file too }
    PagesReset;
    LoadDemo;
    GravityScale := 1;
    LayoutName := 'Original demo';
    if not SaveLayout(UnicodeString(IncludeTrailingPathDelimiter(ParamStr(2)) + DEMO_FILE), err) then
      raise Exception.Create(err);
    for n := 1 to EXAMPLE_COUNT do
    begin
      BuildExample(n);
      LayoutName := ExampleTitles[n];
      if not SaveLayout(UnicodeString(IncludeTrailingPathDelimiter(ParamStr(2)) + ExampleFiles[n]), err) then
        raise Exception.Create(err);
    end;
    SDL_Quit;
    Exit;
  end;

  { --shot <frames> <out.bmp> [layout.mflow] : simulate without input and save a screenshot }
  shotFrames := 0;
  shotFile := '';
  if (ParamCount >= 3) and (ParamStr(1) = '--shot') then
  begin
    shotFrames := StrToIntDef(ParamStr(2), 300);
    shotFile := ParamStr(3);
  end;

  { starts with the panels in the right column; ApplyLayout adjusts it to the saved layout }
  ww := CANVAS_W + RightW;
  wh := WIN_H + MENU_H;
  if SDL_GetDisplayUsableBounds(SDL_GetPrimaryDisplay, @db) then
  begin
    sc := fmin(1, fmin((db.w - 20) / ww, (db.h - 60) / wh));
    if sc > 0.3 then
    begin
      ww := Round(ww * sc);
      wh := Round(wh * sc);
    end;
  end;
  Win := SDL_CreateWindow('Material Flow Simulator - SDL3', ww, wh, SDL_WINDOW_RESIZABLE);
  if Win = nil then
    raise Exception.Create('SDL_CreateWindow failed: ' + string(SDL_GetError));
  Ren := SDL_CreateRenderer(Win, nil);
  if Ren = nil then
    raise Exception.Create('SDL_CreateRenderer failed: ' + string(SDL_GetError));
  SDL_SetRenderLogicalPresentation(Ren, CANVAS_W + RightW, WIN_H + MENU_H, SDL_LOGICAL_PRESENTATION_LETTERBOX);
  SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_BLEND);
  if shotFrames = 0 then SDL_SetRenderVSync(Ren, 1);

  for m := Low(TMat) to High(TMat) do
    SetLength(PRects[m], MAX_PART);

  DlgDefault := ExtractFilePath(ParamStr(0)) + 'examples';
  if not DirectoryExists(DlgDefault) then DlgDefault := ExtractFilePath(ParamStr(0));
  DlgDefault := UTF8Encode(UnicodeString(DlgDefault));

  InitWins;
  { test / screenshot runs (--shot, --selftest) neither read nor change the user's settings }
  if Copy(ParamStr(1), 1, 2) = '--' then
    SettingsFile := ''
  else
    SettingsFile := ExtractFilePath(ParamStr(0)) + 'materialflow.ini';
  LoadSettings;
  { the default physics (Physics lab > Default), not in test runs }
  if (SettingsFile <> '') and FileExists(ExtractFilePath(ParamStr(0)) + PHYS_FILE) then
    if LoadPhysics(UnicodeString(ExtractFilePath(ParamStr(0)) + PHYS_FILE), err) then
      SetStatus('Physics from ' + PHYS_FILE)
    else
      SetStatus(PHYS_FILE + ': ' + err, True);
  { the default shapes (Shape editor > Default) }
  if (SettingsFile <> '') and FileExists(ExtractFilePath(ParamStr(0)) + SHAPE_FILE) then
    if not LoadShapes(UnicodeString(ExtractFilePath(ParamStr(0)) + SHAPE_FILE), err) then
      SetStatus(SHAPE_FILE + ': ' + err, True);

  LoadStartupLayout(Copy(ParamStr(1), 1, 2) = '--');
  MX := -1;
  MY := -1;

  if (ParamCount >= 2) and (ParamStr(1) = '--selftest') then
  begin
    RunSelfTest(ParamStr(2));
    SDL_DestroyRenderer(Ren);
    SDL_DestroyWindow(Win);
    SDL_Quit;
    Exit;
  end;

  { --shot <frames> <out.bmp> [layout.mflow|-] [file|edit|theme] [theme#] }
  if shotFrames > 0 then
  begin
    Tool := tSelect;
    SelectCell(2, 3);
    if (ParamCount >= 4) and (ParamStr(4) <> '-') then
    begin
      if not LoadLayout(UnicodeString(ParamStr(4)), err) then
        raise Exception.Create('load: ' + err);
      SelKind := selNone;
    end;
    if ParamStr(5) = 'file' then OpenMenu := 0
    else if ParamStr(5) = 'examples' then
    begin
      OpenMenu := MENU_EXAMPLES;
      BuildMenu(MENU_EXAMPLES);
      SubOpen := 3;
    end
    else if ParamStr(5) = 'edit' then OpenMenu := 1
    else if ParamStr(5) = 'view' then OpenMenu := MENU_VIEW
    else if ParamStr(5) = 'panels' then OpenMenu := MENU_PANELS
    else if ParamStr(5) = 'grid' then
    begin
      { the Grid sub-menu open, with a customised grid behind it }
      OpenMenu := MENU_VIEW;
      SubOpen := VIEW_GRID_ITEM;
      GridStyle := 0;
      GridMajor := 5;
      GridColor := 1;
      GridStrength := 1;
      GridNumbers := True;
      BuildMenu(MENU_VIEW);
      MX := MenuX(MENU_VIEW) + 40;
      MY := ItemY(VIEW_GRID_ITEM) + 10;
    end
    else if ParamStr(5) = 'equip' then
    begin
      { the Equipment tab, one motor in fault, the blower selected }
      ToolTab := 1;
      Tool := tEqBlower;
      for n := 0 to MAX_EQUIP - 1 do
        if Equips[n].Active and (Equips[n].Name = 'Paddle02') then Equips[n].State := EQS_FAULT
        else if Equips[n].Active and (Equips[n].Name = 'Blower01') then
        begin
          SelKind := selEquip;
          SelEq := n;
        end;
    end
    else if ParamStr(5) = 'start' then
    begin
      { hold every start button (push NO) for half a second }
      for n := 0 to GW * GH - 1 do
        if EGrid[n mod GW, n div GW].Kind = ekPBNO then EGrid[n mod GW, n div GW].Held := True;
      for n := 1 to 30 do SimFrame(1 / 60, True);
      for n := 0 to GW * GH - 1 do EGrid[n mod GW, n div GW].Held := False;
    end
    else if ParamStr(5) = 'elec' then
    begin
      { the Electric tab, the contactor at 38,11 selected }
      ToolTab := 2;
      Tool := tElContactor;
      SelKind := selECell;
      SelEX := 38;
      SelEY := 11;
    end
    else if ParamStr(5) = 'pins' then
    begin
      { two Focus Properties windows (Pump01, drive U1); Motor01 selected }
      SelKind := selEquip;
      SelEq := EquipByName('Pump01');
      PopupX := 0;
      PopupY := 60;
      OpenPin;
      SelKind := selECell;
      SelEX := 37;
      SelEY := 5;
      PopupX := 300;
      PopupY := 150;
      OpenPin;
      SelKind := selEquip;
      SelEq := EquipByName('Motor01');
    end
    else if ParamStr(5) = 'lab' then
    begin
      { the physics lab over its drop test, sand picked }
      LabTest(1);
      ToggleWin(WIN_LAB);
      Wins[WIN_LAB].X := 900;
      Wins[WIN_LAB].Y := 20;
      LabMat := mSand;
    end
    else if ParamStr(5) = 'ctrl' then
    begin
      { the Control tab, controller LIC1 (example 23 at 40,3) selected }
      ToolTab := 4;
      Tool := tCtLevel;
      SelKind := selECell;
      SelEX := 40;
      SelEY := 3;
    end
    else if ParamStr(5) = 'timer' then
    begin
      { the Control tab, flasher T1 (example 22 at 39,5) selected }
      ToolTab := 4;
      SelKind := selECell;
      SelEX := 39;
      SelEY := 5;
    end
    else if (ParamStr(5) = 'page3') or (ParamStr(5) = 'page4') then
      AppGoToPage(StrToInt(Copy(ParamStr(5), 5, 1)) - 1)
    else if ParamStr(5) = 'big' then
    begin
      { both resizable panels made larger: the lab at 150%, the shape editor at 130% on the IR heater }
      LabTest(1);
      ToggleWin(WIN_LAB);
      SetWinScale(WIN_LAB, 1.5);
      Wins[WIN_LAB].X := 20;
      Wins[WIN_LAB].Y := 10;
      ShpPickKind(EQ_IRHEATER);
      ToggleWin(WIN_SHAPE);
      SetWinScale(WIN_SHAPE, 1.3);
      Wins[WIN_SHAPE].X := 480;
      Wins[WIN_SHAPE].Y := 10;
    end
    else if ParamStr(5) = 'shape' then
    begin
      { a custom receiver drawn in the shape editor, and on the canvas next to the built-in blower }
      n := ShapeAdd(EQ_RECEIVER, PR_RECT, 0.2, 0.12, 0.8, 0.9);
      n := ShapeAdd(EQ_RECEIVER, PR_ELLIPSE, 0.2, 0.04, 0.8, 0.2);
      n := ShapeAdd(EQ_RECEIVER, PR_ELLIPSE, 0.2, 0.82, 0.8, 0.98);
      n := ShapeAdd(EQ_RECEIVER, PR_RECT, 0.3, 0.98, 0.7, 1);
      EqShapes[EQ_RECEIVER].P[n].StateCol := False;
      EqShapes[EQ_RECEIVER].P[n].R := 70;
      EqShapes[EQ_RECEIVER].P[n].G := 74;
      EqShapes[EQ_RECEIVER].P[n].B := 80;
      n := ShapeAdd(EQ_RECEIVER, PR_LINE, 0.5, 0.2, 0.5, 0.82);
      EqShapes[EQ_RECEIVER].P[n].R := 255;
      EqShapes[EQ_RECEIVER].P[n].G := 255;
      EqShapes[EQ_RECEIVER].P[n].B := 255;
      EqShapes[EQ_RECEIVER].P[n].A := 120;
      n := ShapeAdd(EQ_RECEIVER, PR_TRI, 0.35, 0.45, 0.65, 0.6);
      EqShapes[EQ_RECEIVER].P[n].StateCol := False;
      EqShapes[EQ_RECEIVER].P[n].R := 250;
      EqShapes[EQ_RECEIVER].P[n].G := 200;
      EqShapes[EQ_RECEIVER].P[n].B := 40;
      n := AddEquip(EQ_RECEIVER, 520, 300);
      Equips[n].State := EQS_RUN;
      n := AddEquip(EQ_RECEIVER, 620, 300);
      Equips[n].State := EQS_FAULT;
      ShpPickKind(EQ_RECEIVER);
      ShpSel := 1;
      ToggleWin(WIN_SHAPE);
      Wins[WIN_SHAPE].X := 900;
      Wins[WIN_SHAPE].Y := 20;
    end
    else if ParamStr(5) = 'framepopup' then ShowFramePopup(0)
    else if ParamStr(5) = 'about' then AppGoToPage(1)
    else if ParamStr(5) = 'notes' then
    begin
      { the Notes layer hidden, a link selected }
      Pages[CurPage].Layers[1].Visible := False;
      SelKind := selNone;
    end
    else if ParamStr(5) = 'theme' then OpenMenu := MENU_THEME
    else if ParamStr(5) = 'clock' then
    begin
      { date and time labels in a few styles; the date label selected }
      n := AddClockLabel(420, 420, LBL_TIME);
      Labels[n].Fmt := 'hh:nn:ss';
      Labels[n].Text := 'Shift clock';
      Labels[n].Color := 2;
      n := AddClockLabel(420, 470, LBL_TIME);
      Labels[n].Fmt := 'h:nn am/pm';
      Labels[n].NoBox := True;
      Labels[n].Color := 3;
      n := AddClockLabel(420, 360, LBL_DATE);
      Labels[n].Fmt := 'dddd, d mmmm yyyy';
      Labels[n].Text := 'Report date';
      SelKind := selLabel;
      SelL := n;
    end
    else if ParamStr(5) = 'bare' then
    begin
      { every panel hidden: just the menu bar and the canvas }
      for n := 0 to WIN_COUNT - 1 do
        if Wins[n].Visible then ToggleWin(n);
    end
    else if ParamStr(5) = 'zoom' then
    begin
      { a 4-way valve with a label, zoomed in, valve selected }
      PipeLine(28, 26, 32, 26, 3);
      PipeLine(30, 24, 30, 28, 3);
      SetKind(30, 26, ckValve4);
      Grid[30, 26].Closed := 1 or 4;
      AddLabel(33 * CELL, 23 * CELL, '4-WAY VALVE'#10'E and W shut,'#10'N-S runs through.');
      ZoomAt(2.5, 30 * CELL + HALF, 26 * CELL);
      SelectCell(30, 26);
    end
    else if ParamStr(5) = 'left' then
    begin
      { Tool embedded on the left, a box selection, and the panel popup open }
      EmbedWin(WIN_TOOLS, 1);
      SelectBox(12, 2, 20, 4);
      MX := -150;
      MY := 60;
      OpenPanelPopup(WIN_TOOLS);
    end
    else if ParamStr(5) = 'float' then
    begin
      Wins[WIN_PROPS].X := 640;
      Wins[WIN_PROPS].Y := 300;
      Wins[WIN_SIM].Visible := False;
      Wins[WIN_TOOLS].X := 330;
      Wins[WIN_TOOLS].Y := 420;
      SelectCell(6, 3);
    end
    else if ParamStr(5) = 'popup' then
    begin
      { box-select line 1's right branch, copy it, and show the right-click menu }
      SelectBox(12, 2, 20, 12);
      CopySelection;
      MX := 16 * CELL + HALF;
      MY := 6 * CELL;
      OpenPopup;
      MX := PopupX + 20;
      MY := PopupY + 30;
    end;
    if ParamCount >= 6 then SelectTheme(StrToIntDef(ParamStr(6), 0));
    last := SDL_GetTicksNS;
    for frame := 1 to shotFrames do
    begin
      while SDL_PollEvent(@ev) do ;
      SimAllPages(1 / 60, True);
    end;
    now := SDL_GetTicksNS;
    ShotMsPerFrame := (now - last) / 1e6 / shotFrames;
    Render;
    surf := SDL_RenderReadPixels(Ren, nil);
    if surf <> nil then
    begin
      SDL_SaveBMP(surf, PAnsiChar(shotFile));
      SDL_DestroySurface(surf);
    end;
    WriteShotStats(shotFile + '.txt');
    SDL_DestroyRenderer(Ren);
    SDL_DestroyWindow(Win);
    SDL_Quit;
    Exit;
  end;

  QuitRequested := False;
  last := SDL_GetTicksNS;
  while not QuitRequested do
  begin
    MPressed := False;
    while SDL_PollEvent(@ev) do
    begin
      SDL_ConvertEventToRenderCoordinates(Ren, @ev);
      case ev.type_ of
        SDL_EVENT_QUIT:
          QuitRequested := True;
        SDL_EVENT_KEY_DOWN:
          { while a label is being typed into, keys belong to it }
          if TxtEdit > 0 then TxtKey(ev.key.key)
          else if EditLabel >= 0 then LabelKey(ev.key.key)
          else if EditFrame >= 0 then FrameKey(ev.key.key)
          else HandleKey(ev.key.key, ev.key.mod_);
        SDL_EVENT_TEXT_INPUT:
          if ev.text.text <> nil then
          begin
            if TxtEdit > 0 then TxtTypeText(string(ev.text.text))
            else if EditFrame >= 0 then FrameTypeText(string(ev.text.text))
            else LabelTypeText(string(ev.text.text));
          end;
        SDL_EVENT_MOUSE_MOTION:
          begin
            MX := ev.motion.x - OX;
            MY := ev.motion.y - OY;
            if Panning then
            begin
              PanBy((PanLastX - MX) / Zoom, (PanLastY - MY) / Zoom);
              PanLastX := MX;
              PanLastY := MY;
            end;
            { a right press that moves to another cell becomes an erase drag }
            if RightPending and RDown and
              ((EnsureRange(Trunc(MWX / CELL), 0, GW - 1) <> RCellX) or
               (EnsureRange(Trunc(MWY / CELL), 0, GH - 1) <> RCellY)) then
            begin
              RightPending := False;
              Drag := dragErase;
              EraseAt(RCellX, RCellY);
            end;
            if Drag <> dragNone then CanvasMotion;
          end;
        SDL_EVENT_MOUSE_BUTTON_DOWN:
          begin
            MX := ev.button.x - OX;
            MY := ev.button.y - OY;
            LastClicks := ev.button.clicks;
            MouseDown(ev.button.button);
          end;
        SDL_EVENT_MOUSE_BUTTON_UP:
          if ev.button.button = SDL_BUTTON_MIDDLE then
            Panning := False
          else
          begin
            if ev.button.button = SDL_BUTTON_LEFT then
            begin
              MDown := False;
              ActiveId := 0;
              if Drag = dragEPress then EPress(EHX, EHY, False);
        if Drag = dragFPress then FPress(FHX, FHY, False);
              if Drag = dragFPress then FPress(FHX, FHY, False);
              if Drag = dragBox then FinishBox
              else if Drag = dragMove then FinishMove
              else if Drag = dragFrameNew then FinishFrameNew
              else if Drag = dragFrameMove then FinishFrameMove;
            end
            else if ev.button.button = SDL_BUTTON_RIGHT then
            begin
              RDown := False;
              if RightPending then
              begin
                RightPending := False;
                OpenPopup;
              end;
            end;
            Drag := dragNone;
          end;
        SDL_EVENT_MOUSE_WHEEL:
          begin
            MX := ev.wheel.mouse_x - OX;
            MY := ev.wheel.mouse_y - OY;
            if (MX >= 0) and (MX < CANVAS_W) and (MY >= 0) and (MY < CANVAS_H) and not InAnyWin(MX, MY) then
            begin
              if (SDL_GetModState and SDL_KMOD_CTRL) <> 0 then
              begin
                { Ctrl+wheel zooms around the mouse }
                if ev.wheel.y > 0 then ZoomAt(Zoom * 1.15, MX, MY)
                else if ev.wheel.y < 0 then ZoomAt(Zoom / 1.15, MX, MY);
              end
              else
                CanvasWheel(MWX, MWY, ev.wheel.y);
            end
            else if WinAt(MX, MY) >= 0 then
              { over a panel: scroll it }
              with Wins[WinAt(MX, MY)] do Scroll := Scroll - ev.wheel.y * 40;
          end;
      end;
    end;

    if Panning and ((SDL_GetMouseState(nil, nil) and 2) = 0) then Panning := False;

    { if a button-up was missed (released outside the window, focus lost),
      finish the drag now so no box or ghost is left on screen }
    if (MDown or RDown) and ((SDL_GetMouseState(nil, nil) and 5) = 0) then
    begin
      if MDown then
      begin
        if Drag = dragEPress then EPress(EHX, EHY, False);
        if Drag = dragFPress then FPress(FHX, FHY, False);
        if Drag = dragBox then FinishBox
        else if Drag = dragMove then FinishMove
        else if Drag = dragFrameNew then FinishFrameNew
        else if Drag = dragFrameMove then FinishFrameMove;
      end;
      MDown := False;
      RDown := False;
      RightPending := False;
      ActiveId := 0;
      Drag := dragNone;
    end;

    now := SDL_GetTicksNS;
    FrameDt := fclamp((now - last) / 1e9, 0.001, 0.05);
    last := now;
    FPS := FPS * 0.95 + (1 / FrameDt) * 0.05;

    PollDialog;
    StatusTime := fmax(0, StatusTime - FrameDt);
    WheelIdle := WheelIdle + FrameDt;
    { a finished gesture (nothing held, no drag, wheel at rest) becomes an undo step }
    { (typing into a label becomes one step when the typing is done) }
    if (not MDown) and (not RDown) and (Drag = dragNone) and (WheelIdle > 0.5) and (EditLabel < 0) and (EditFrame < 0) and
      (TxtEdit = 0) then
      HistCheck;
    PageDelArmed := fmax(0, PageDelArmed - FrameDt);
    LayerDelArmed := fmax(0, LayerDelArmed - FrameDt);

    SimAllPages(fmin(FrameDt, 1 / 30), Running);
    Render;
    SDL_RenderPresent(Ren);
    TakePendingPage;
  end;

  SaveSettings;   { panel places and theme for next time }
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
end;

end.
