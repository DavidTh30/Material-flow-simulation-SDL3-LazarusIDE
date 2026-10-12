unit mfapp;

{ Window, rendering, immediate-mode control panel and editing tools. }

{$mode objfpc}{$H+}

interface

procedure RunApp;

implementation

uses
  SysUtils, Math, sdl3min, simcore, layoutio, mfexamples, mftheme, edithist, mfpages;

const
  PANEL_X = CANVAS_W;        { the right panel column starts here (when it is open) }
  PANEL_W = 304;
  WIN_H = CANVAS_H;           { height of the area below the menu bar }
  MENU_H = 24;                { the menu bar across the top of the window }
  PX = PANEL_X + 8;

type
  TTool = (tSelect, tPipe, tResize, tErase, tFeeder, tHopper, tSilo, tBlower, tSuction, tNozzle,
    tDrop, tCheck, tValve2, tValve3, tValve4, tBucket, tLabel, tLabelDate, tLabelTime, tFrame, tLink);
  TSelKind = (selNone, selCell, selBucket, selMulti, selLabel, selFrame, selLink);
  TDrag = (dragNone, dragPipe, dragResize, dragErase, dragBucket, dragBox, dragMove, dragLabel,
    dragFrameNew, dragFrameMove, dragFrameSize, dragLink);
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
    'Feeder', 'Hopper', 'Silo', 'Blower', 'Suction', 'Push nozzle', 'Drop out', '1-way pipe',
    '2-way valve', '3-way valve', '4-way valve', 'Bucket', 'Label', 'Date label', 'Time label', 'Frame', 'Link');
  ToolKinds: array[TTool] of TCellKind = (ckEmpty, ckPipe, ckEmpty, ckEmpty,
    ckSource, ckHopper, ckSilo, ckBlower, ckSuction, ckNozzle, ckDrop, ckCheck, ckValve2, ckValve3, ckValve4,
    ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty, ckEmpty);
  ToolHints: array[TTool] of string = (
    'Click to edit; drag box to select',
    'Drag to route; start on pipe=branch',
    'Click/drag pipe: set size (brush)',
    'Click/drag: remove parts, buckets',
    'Click: place a material feeder',
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
    'Click: link to a page / popup');
  KindNames: array[TCellKind] of string = ('Empty', 'Pipe', 'Feeder', 'Blower',
    'Suction head', 'Push-out nozzle', 'Drop outlet', '1-way pipe', '2-way valve', '3-way valve', '4-way valve',
    'Hopper', 'Silo');
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
  Wins: array[0..6] of TWin;
  WinOrder: array[0..6] of Integer = (0, 1, 2, 3, 4, 5, 6);   { drawing order, last = on top }
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
  DlgKind: Integer = 0;         { 1 open, 2 save }
  DlgDefault: string = '';

const
  DlgFilters: array[0..1] of TSDL_DialogFileFilter = (
    (name: 'Material Flow layout (*.mflow)'; pattern: 'mflow'),
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
  if (not Result) and (ActiveId = id) and MDown and Inside(x, y, w, h) then
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
    ckHopper, ckSilo:
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
  if k = 1 then OpenFrom(path) else SaveTo(path);
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
    2: Result := 24;
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
  What: array[1..5] of string = ('the page name', 'the layer name', 'the popup title', 'the popup text',
    'the link caption');
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

const
  WIN_TOOLS = 0;
  WIN_SIM = 1;
  WIN_PROPS = 2;
  WIN_STATUS = 3;
  WIN_HELP = 4;
  WIN_PAGES = 5;
  WIN_POPUPS = 6;
  WIN_COUNT = 7;
  WIN_TITLE_H = 18;
  WinKeys: array[0..WIN_COUNT - 1] of string = ('F2', 'F3', 'F4', 'F5', 'F1', 'F6', 'F7');

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
  end;
begin
  { embedded, they stack down a panel column (right or left of the canvas) }
  Setup(WIN_TOOLS, 'TOOL', 4, 208);
  Setup(WIN_SIM, 'SIMULATION', 214, 124);
  Setup(WIN_PROPS, 'PROPERTIES', 340, 298);
  Setup(WIN_STATUS, 'STATUS', 640, 58);
  Setup(WIN_HELP, 'HELP', 700, 98);
  { the page panels start in the left column }
  Setup(WIN_PAGES, 'PAGE & LAYER', 4, 372);
  Setup(WIN_POPUPS, 'FRAME POPUP', 380, 410);
  Wins[WIN_PAGES].Side := 1;
  Wins[WIN_POPUPS].Side := 1;
  Wins[WIN_PAGES].X := -PANEL_W + 4;
  Wins[WIN_POPUPS].X := -PANEL_W + 4;
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

function InAnyWin(x, y: Single): Boolean;
begin
  Result := WinAt(x, y) >= 0;
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

{ materialflow.ini:  theme=N  and per panel  panelN=visible,side,docked,x,y }
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
        WriteLn(f, Format('panel%d=%d,%d,%d,%d,%d', [i, Ord(Wins[i].Visible), Wins[i].Side,
          Ord(WinDocked(i)), Round(Wins[i].X), Round(Wins[i].Y)]));
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
  v: array[0..4] of Integer;
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
          while (n <= 4) and (rest <> '') do
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
  for i := 0 to WIN_COUNT - 1 do
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
        AddItem('Dock all panels', '', not AllDocked, False, True);
      end;
    MENU_EXAMPLES:
      begin
        AddItem('Original demo');
        for i := 1 to EXAMPLE_COUNT do
          AddItem(Format('%d: %s', [i, ExampleTitles[i]]), '', True, False, i = 1);
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
        0..6: ToggleWin(i);
        7:
          for k := 0 to WIN_COUNT - 1 do DockWin(k);
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

function MenuW(m: Integer): Single;
begin
  case m of
    0: Result := 288;
    1: Result := 200;
    MENU_VIEW: Result := 270;
    MENU_PANELS: Result := 210;
    MENU_EXAMPLES: Result := 240;
  else
    Result := 170;
  end;
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
  if Result + SUB_W > SceneRight then Result := MenuX(m) - SUB_W + 2;
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
    BuildGridMenu;
    inSub := InItemList(SCount, SubX(m), SUB_W, SubTop, True);
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
    BuildGridMenu;
    sx := SubX(m);
    i := DrawItemList(SItems, SCount, sx, SUB_W, SubTop, True, Pressed);
    if i >= 0 then
    begin
      RunGridItem(i);
      Exit;
    end;
    if Pressed and InItemList(SCount, sx, SUB_W, SubTop, True) then Pressed := False;
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

procedure DrawToolsContent(y0: Single);
var
  t: TTool;
  i: Integer;
  hw, y: Single;
begin
  for t := Low(TTool) to High(TTool) do
  begin
    i := Ord(t);
    if Button(10 + i, QX + (i mod 3) * 94, y0 + (i div 3) * 21, 90, 19, ToolNames[t], Tool = t) then
    begin
      Tool := t;
      Drag := dragNone;
    end;
  end;
  SetC(Th.Hint);
  if PasteArmed then
    TextR(QX, y0 + 151, 'Click the canvas to paste (Esc)')
  else
    TextR(QX, y0 + 151, ToolHints[Tool]);
  y := y0 + 165;
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
  gx, gy, L, fr, part: Integer;
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
    if L >= 0 then
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
  HELP_PAGES = 6;
  HelpTitles: array[0..HELP_PAGES - 1] of string = ('Basics', 'Select & move', 'Edit',
    'View & panels', 'Files & labels', 'Pages & links');
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
     'Click a link: go to page / popup', 'Ctrl+click a link: select it'));

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
  closeX, y0: Single;
  hot: Boolean;
begin
  Wn := @Wins[i];
  if not Wn^.Visible then Exit;
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

  QX := Wn^.X + 8;
  y0 := Wn^.Y + WIN_TITLE_H + 6;
  case i of
    WIN_TOOLS: DrawToolsContent(y0);
    WIN_SIM: DrawSimContent(y0);
    WIN_PROPS: DrawPropsContent(y0);
    WIN_STATUS: DrawStatusContent(y0);
    WIN_HELP: DrawHelpContent(y0);
    WIN_PAGES: DrawPagesContent(y0);
    WIN_POPUPS: DrawPopupsContent(y0);
  end;
  QX := PX;
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
  gx, gy, b, L, sx, sy, fr, part, lk: Integer;
  blocked: Boolean;
begin
  if (MWX < 0) or (MWY < 0) then Exit;   { outside the layout when zoomed out }
  gx := Trunc(MWX / CELL);
  gy := Trunc(MWY / CELL);
  if not InGrid(gx, gy) then Exit;
  StopTxt;
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
  if blocked and (Tool in [tPipe, tResize, tFeeder, tHopper, tSilo, tBlower, tSuction, tNozzle, tDrop, tCheck,
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
    tFeeder, tHopper, tSilo, tBlower, tSuction, tNozzle, tDrop, tCheck, tValve2, tValve3, tValve4:
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
  CanvasLabels: array[0..5] of string = ('Cut', 'Copy', 'Paste here', 'Delete', 'Rotate', 'Edit text');
  CanvasKeys: array[0..5] of string = ('Ctrl+X', 'Ctrl+C', 'Ctrl+V', 'Del', 'R', '2x click');
  PanelLabels: array[0..3] of string = ('Right embed', 'Left embed', 'Float', 'Hide');

function PopupCount: Integer;
begin
  if PopupWin >= 0 then Result := 4 else Result := 6;
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
        5: en := SelKind in [selLabel, selFrame, selLink];
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
             else StartEditLabel(SelL);
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
      if ShownPopup >= 0 then
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
    if InAnyWin(MX, MY) then
      OpenPanelPopup(WinAt(MX, MY))   { panel: Right / Left embed, Float, Hide }
    else if (MX >= 0) and (MX < CANVAS_W) and (MY >= 0) then
      CanvasPress(True);
  end;
end;

procedure Render;
var
  pressed, toMenu: Boolean;
  target, k, i: Integer;
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
  if not toMenu then
  begin
    for i := 0 to WIN_COUNT - 1 do
      if Wins[i].Dragging then target := i;
    if target < 0 then target := WinAt(MX, MY);
  end;
  MPressed := pressed and not toMenu and (target < 0);
  DrawPanel;
  order := WinOrder;   { a click may bring a window to the front while drawing }
  for k := 0 to WIN_COUNT - 1 do
  begin
    i := order[k];
    MPressed := pressed and (i = target);
    DrawWin(i);
  end;
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
  for i := 0 to WIN_COUNT - 1 do DockWin(i);
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
  ClickMenu(MENU_EXAMPLES, 4); { Examples > 4 }
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
  Check('Panels menu holds the seven panels + Dock all', (MCount = 8) and (MItems[5].Lbl = 'Page & Layer') and
    (MItems[6].Lbl = 'Frame popup') and (MItems[7].Lbl = 'Dock all panels'));
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
  Check('Examples menu: demo + all examples', (MCount = 1 + EXAMPLE_COUNT) and (MItems[0].Lbl = 'Original demo'));
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
  for i := 0 to WIN_COUNT - 1 do DockWin(i);
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
      (PageCount = 2) and (PageName(0) = 'Plant') and (PageName(1) = 'About') and (LayerCount = 2) and
      (Pages[0].Layers[0].Name = 'Process') and (Pages[0].Layers[1].Name = 'Notes') and
      (FramePopupCount = 2) and (CurPage = 0) and (CurLayer = 0));
    np := 0;
    nb := 0;
    for i := 0 to MAX_LINKS - 1 do
    begin
      if Links[i].Active and (Links[i].Layer = 1) then Inc(np);
      if Pages[1].Links[i].Active then Inc(nb);
    end;
    Check(Format('example %d: 3 links on each page', [k]), (np = 3) and (nb = 3));
    np := 0;
    for cy := 0 to GH - 1 do
      for cx := 0 to GW - 1 do
        if (Grid[cx, cy].Kind <> ckEmpty) and (Grid[cx, cy].Layer <> 0) then Inc(np);
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
    else if ParamStr(5) = 'examples' then OpenMenu := MENU_EXAMPLES
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
      SimFrame(1 / 60, True);
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
            end;
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

    SimFrame(fmin(FrameDt, 1 / 30), Running);
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
