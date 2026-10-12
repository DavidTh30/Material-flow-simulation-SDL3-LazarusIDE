unit mfapp;

{ Window, rendering, immediate-mode control panel and editing tools. }

{$mode objfpc}{$H+}

interface

procedure RunApp;

implementation

uses
  SysUtils, Math, sdl3min, simcore, layoutio, mfexamples, mftheme, edithist;

const
  PANEL_X = CANVAS_W;
  PANEL_W = 304;
  WIN_W = CANVAS_W + PANEL_W;
  WIN_H = CANVAS_H;
  PX = PANEL_X + 8;

type
  TTool = (tSelect, tPipe, tResize, tErase, tTank, tBlower, tSuction, tNozzle,
    tDrop, tCheck, tValve2, tValve3, tValve4, tBucket, tLabel);
  TSelKind = (selNone, selCell, selBucket, selMulti, selLabel);
  TDrag = (dragNone, dragPipe, dragResize, dragErase, dragBucket, dragBox, dragMove, dragLabel);
  TClipBucket = record
    DX, DY, W, H: Single;   { relative to the block's top-left corner }
  end;
  TClipLabel = record
    DX, DY: Single;
    Text: string;
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
    'Tank', 'Blower', 'Suction', 'Push nozzle', 'Drop out', '1-way pipe',
    '2-way valve', '3-way valve', '4-way valve', 'Bucket', 'Label');
  ToolKinds: array[TTool] of TCellKind = (ckEmpty, ckPipe, ckEmpty, ckEmpty,
    ckSource, ckBlower, ckSuction, ckNozzle, ckDrop, ckCheck, ckValve2, ckValve3, ckValve4, ckEmpty, ckEmpty);
  ToolHints: array[TTool] of string = (
    'Click to edit; drag box to select',
    'Drag to route; start on pipe=branch',
    'Click/drag pipe: set size (brush)',
    'Click/drag: remove parts, buckets',
    'Click: place a material tank',
    'Click pipe: inline blower (blow)',
    'Click pipe end: suction intake',
    'Click pipe end: push-out nozzle',
    'Click pipe end: gravity drop outlet',
    'Click pipe: one-way (check) pipe',
    'Click pipe: 2-way on/off valve',
    'Click tee: 3-way diverter valve',
    'Click cross: 4-way valve',
    'Click: place bucket (rim at cursor)',
    'Click: add a label, then type');
  KindNames: array[TCellKind] of string = ('Empty', 'Pipe', 'Tank', 'Blower',
    'Suction head', 'Push-out nozzle', 'Drop outlet', '1-way pipe', '2-way valve', '3-way valve', '4-way valve');
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
  { edit clipboard (one part or one bucket) and pending paste }
  Clip: TBlock;                 { the clipboard }
  { dragging the selection: a copy of it, the press cell and the current offset }
  MoveBuf: TBlock;
  MoveX1, MoveY1, MoveGX0, MoveGY0, MoveDX, MoveDY: Integer;
  MovePressBucket: Integer = -1;
  { properties window (floating; starts docked in the side panel) }
  { dockable panels: Tool, Simulation, Properties }
  Wins: array[0..4] of TWin;
  WinOrder: array[0..4] of Integer = (0, 1, 2, 3, 4);   { drawing order, last = on top }
  { left panel column: when a panel is embedded on the left the whole scene
    shifts right by LeftW. Everything works in canvas coordinates; OX is added
    only when drawing and subtracted from mouse positions }
  LeftW: Integer = 0;
  OX: Single = 0;
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
  SelL: Integer = -1;
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
  LabelLines(Labels[i].Text, n, wd);
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
    if Labels[i].Active then
    begin
      LabelBox(i, x, y, w, h);
      if (wx >= x) and (wx < x + w) and (wy >= y) and (wy < y + h) then Exit(i);
    end;
  Result := -1;
end;

{ in a box selection a label counts when its top-left corner is inside the box }
function SelHasLabel(i: Integer): Boolean;
begin
  Result := False;
  if not Labels[i].Active then Exit;
  case SelKind of
    selLabel: Result := SelL = i;
    selMulti:
      Result := (Labels[i].X >= SelX1 * CELL) and (Labels[i].X < (SelX2 + 1) * CELL) and
        (Labels[i].Y >= SelY1 * CELL) and (Labels[i].Y < (SelY2 + 1) * CELL);
  end;
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
      InGrid(x, y) and (Grid[x, y].Kind <> ckEmpty);
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
        Result := (cx >= SelX1 * CELL) and (cx < (SelX2 + 1) * CELL) and
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
  if CanvasXf then Result := (y - ViewY) * Zoom else Result := y;
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
      if c^.Kind = ckEmpty then Continue;
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
      if c^.Kind = ckEmpty then Continue;
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

procedure DrawLabels;
var
  i, k, n, wd: Integer;
  ux, uy, w, h: Single;
  s, line: string;
  editing: Boolean;
begin
  CanvasXf := False;   { drawn at screen size, anchored to the zoomed canvas }
  for i := 0 to MAX_LABELS - 1 do
  begin
    if not Labels[i].Active then Continue;
    editing := EditLabel = i;
    s := Labels[i].Text;
    if editing and ((SDL_GetTicksNS div 500000000) mod 2 = 0) then s := s + '_';
    LabelLines(s, n, wd);
    wd := Max(wd + 1, 6);
    ux := (Labels[i].X - ViewX) * Zoom;
    uy := (Labels[i].Y - ViewY) * Zoom;
    w := wd * 8 + 2 * LABEL_PAD;
    h := n * LABEL_LINE + 2 * LABEL_PAD - 2;
    SetC(Th.OverlayBg, 225);
    FillR(ux, uy, w, h);
    if editing then SetC(Th.Paste)
    else if SelHasLabel(i) then SetC(Th.Select)
    else SetC(Th.MenuBorder);
    RectR(ux, uy, w, h);
    if SelHasLabel(i) or editing then RectR(ux - 1, uy - 1, w + 2, h + 2);
    if Labels[i].Text = '' then
    begin
      SetC(Th.TextDim);
      if not editing then TextR(ux + LABEL_PAD, uy + LABEL_PAD, '(empty)');
    end;
    SetC(Th.Text);
    line := '';
    k := 0;
    for n := 1 to Length(s) + 1 do
      if (n > Length(s)) or (s[n] = #10) then
      begin
        { the first line is the label's title }
        if k = 0 then SetC(Th.Title) else SetC(Th.Text);
        TextR(ux + LABEL_PAD, uy + LABEL_PAD + k * LABEL_LINE, line);
        line := '';
        Inc(k);
      end
      else
        line := line + s[n];
  end;
  CanvasXf := True;
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
  cr.y := 0;
  cr.w := CANVAS_W;
  cr.h := CANVAS_H;
  SDL_SetRenderClipRect(Ren, @cr);
  CanvasXf := True;
  SetC(Th.CanvasBg);
  FillR(0, 0, CANVAS_W, CANVAS_H);
  SetC(Th.GridLine);
  for x := 0 to GW do
    LineR(x * CELL, 0, x * CELL, FLOOR_Y);
  for y := 0 to GH do
    LineR(0, y * CELL, CANVAS_W, y * CELL);
  SetC(Th.Floor);
  FillR(0, FLOOR_Y, CANVAS_W, CANVAS_H - FLOOR_Y);

  for i := 0 to MAX_BUCKETS - 1 do
    if Buckets[i].Active then DrawBucketBack(i);

  { suction pick-up range }
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @Grid[x, y];
      if (c^.Kind = ckSuction) and (c^.Mouth >= 0) then
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
      if Grid[x, y].Kind > ckPipe then DrawDevice(x, y);
  for i := 0 to MAX_BUCKETS - 1 do
    if Buckets[i].Active then DrawBucketFront(i);
  DrawLabels;

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
        Info(y, 'Ingredients (units in tank):');
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
  SelKind := selNone;
  Drag := dragNone;
  OpenMenu := -1;
  PasteArmed := False;
  UpdateTitle;
end;

procedure DoNew;
begin
  ClearAll;
  GravityScale := 1;
  CurrentFile := '';
  LayoutName := '';
  AfterLayoutChange;
  SetStatus('New blank layout');
end;

procedure DoLoadDemo;
begin
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
  if SelKind = selNone then Exit;
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
  s := PlaceBlock(Clip, gx, gy, lost);
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

{ ---------------------------------------------------------------- label editing }

{ finish typing; a label left empty is removed }
procedure StopEditLabel;
var
  i: Integer;
begin
  if EditLabel < 0 then Exit;
  i := EditLabel;
  EditLabel := -1;
  if Win <> nil then SDL_StopTextInput(Win);
  if Labels[i].Active and (Trim(Labels[i].Text) = '') then
  begin
    DeleteLabel(i);
    if (SelKind = selLabel) and (SelL = i) then SelKind := selNone;
  end;
end;

procedure StartEditLabel(i: Integer);
begin
  if (i < 0) or not Labels[i].Active then Exit;
  if EditLabel <> i then StopEditLabel;
  EditLabel := i;
  SelKind := selLabel;
  SelL := i;
  OpenMenu := -1;
  PopupOpen := False;
  if Win <> nil then SDL_StartTextInput(Win);
  SetStatus('Type the label - Enter: new line, Esc or click away: done');
end;

{ typed text (UTF-8 from SDL); the built-in font only has plain ASCII }
procedure LabelTypeText(const s: string);
var
  k: Integer;
begin
  if EditLabel < 0 then Exit;
  for k := 1 to Length(s) do
    if (s[k] >= ' ') and (s[k] <= '~') and (Length(Labels[EditLabel].Text) < 255) then
      Labels[EditLabel].Text := Labels[EditLabel].Text + s[k];
end;

{ keys while typing into a label; True when the key was used }
function LabelKey(key: UInt32): Boolean;
var
  t: string;
begin
  Result := EditLabel >= 0;
  if not Result then Exit;
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

procedure DrawLabelProps(y: Single);
var
  nx, ny: Single;
  s, line: string;
  k, n: Integer;
begin
  SetC(Th.Title);
  TextR(QX, y, Format('Label %d', [SelL + 1]));
  y := y + 16;
  Info(y, 'Text (first line is the title):');
  { a preview of the text, as many lines as fit }
  SetC(Th.OverlayBg);
  FillR(QX, y + 12, 280, 96);
  SetC(Th.MenuBorder);
  RectR(QX, y + 12, 280, 96);
  s := Labels[SelL].Text;
  line := '';
  n := 0;
  for k := 1 to Length(s) + 1 do
    if (k > Length(s)) or (s[k] = #10) then
    begin
      if n < 8 then
      begin
        if n = 0 then SetC(Th.Title) else SetC(Th.Text);
        TextR(QX + 4, y + 16 + n * 11, Copy(line, 1, 34));
      end;
      line := '';
      Inc(n);
    end
    else
      line := line + s[k];
  y := y + 114;
  if EditLabel = SelL then
  begin
    if Button(194, QX, y, 136, 18, 'Done typing', True) then StopEditLabel;
  end
  else if Button(195, QX, y, 136, 18, 'Edit text') then StartEditLabel(SelL);
  if Button(196, QX + 142, y, 136, 18, 'Delete (Del)') then DeleteSelected;
  y := y + 26;
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
    selBucket, selLabel:
      begin
        SetStatus('Buckets and labels stay upright - select parts to rotate', True);
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
  end;

const
  MENU_COUNT = 4;
  MenuNames: array[0..MENU_COUNT - 1] of string = ('File', 'Edit', 'View', 'Theme');
  MENU_BAR_W = 58;
  MENU_THEME = 3;

var
  MItems: array[0..15] of TMItem;
  MCount: Integer;

procedure AddItem(const L: string; const K: string = ''; En: Boolean = True;
  Chk: Boolean = False; Sep: Boolean = False);
begin
  MItems[MCount].Lbl := L;
  MItems[MCount].Key := K;
  MItems[MCount].Enabled := En;
  MItems[MCount].Checked := Chk;
  MItems[MCount].Sep := Sep;
  Inc(MCount);
end;

{ ---------------------------------------------------------------- panel windows }

const
  WIN_TOOLS = 0;
  WIN_SIM = 1;
  WIN_PROPS = 2;
  WIN_STATUS = 3;
  WIN_HELP = 4;
  WIN_COUNT = 5;
  WIN_TITLE_H = 18;
  WinKeys: array[0..WIN_COUNT - 1] of string = ('F2', 'F3', 'F4', 'F5', 'F1');

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
  { docked, they stack down the side panel between the menu bar and STATUS }
  Setup(WIN_TOOLS, 'TOOL', 40, 180);
  Setup(WIN_SIM, 'SIMULATION', 222, 124);
  Setup(WIN_PROPS, 'PROPERTIES', 348, 306);
  Setup(WIN_STATUS, 'STATUS', 656, 58);
  Setup(WIN_HELP, 'HELP', 716, 98);
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

{ open or close the left column to match the panels embedded there, keeping
  the canvas the same size on screen (the window grows / shrinks) }
procedure ApplyLayout;
var
  i, newW, oldTotal, newTotal, ww, wh: Integer;
  db: TSDL_Rect;
begin
  newW := 0;
  for i := 0 to WIN_COUNT - 1 do
    if EmbeddedLeft(i) then newW := PANEL_W;
  if newW = LeftW then Exit;
  oldTotal := WIN_W + LeftW;
  newTotal := WIN_W + newW;
  LeftW := newW;
  OX := LeftW;
  if Ren = nil then Exit;
  SDL_SetRenderLogicalPresentation(Ren, newTotal, WIN_H, SDL_LOGICAL_PRESENTATION_LETTERBOX);
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
      Wins[i].X := fclamp(Wins[i].X, -LeftW, WIN_W - Wins[i].W);
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
  rest: string;
begin
  if (SettingsFile = '') or not FileExists(SettingsFile) then Exit;
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
      Wins[i].X := fclamp(Wins[i].X, -LeftW, WIN_W - Wins[i].W);
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
        for i := 1 to EXAMPLE_COUNT do
          AddItem(Format('Example %d: %s', [i, ExampleTitles[i]]), '', True, False, i = 1);
        AddItem('Original demo', '', True, False, True);
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
    2:
      begin
        AddItem('Tool', WinKeys[WIN_TOOLS], True, Wins[WIN_TOOLS].Visible);
        AddItem('Simulation', WinKeys[WIN_SIM], True, Wins[WIN_SIM].Visible);
        AddItem('Properties', WinKeys[WIN_PROPS], True, Wins[WIN_PROPS].Visible);
        AddItem('Status', WinKeys[WIN_STATUS], True, Wins[WIN_STATUS].Visible);
        AddItem('Help', WinKeys[WIN_HELP], True, Wins[WIN_HELP].Visible);
        AddItem('Dock all panels', '', not AllDocked);
        AddItem('Zoom in', 'Ctrl+=', Zoom < ZOOM_MAX, False, True);
        AddItem('Zoom out', 'Ctrl+-', Zoom > ZOOM_MIN);
        AddItem(Format('Zoom 100%%   (now %.0f%%)', [Zoom * 100]), 'Ctrl+0', Zoom <> 1);
        AddItem('Pressure colours', 'P', True, ShowPressure, True);
        AddItem('Air dots', 'A', True, ShowAir);
      end;
    MENU_THEME:
      for i := 0 to THEME_COUNT - 1 do
        AddItem(Themes[i].Name, '', True, i = ThemeIndex);
  end;
end;

procedure RunMenuItem(m, i: Integer);
var
  k: Integer;
begin
  OpenMenu := -1;
  case m of
    0:
      case i of
        0: DoNew;
        1: DoOpen;
        2: DoSave;
        3: DoSaveAs;
        7: DoLoadDemo;
      else
        DoExample(i - 3);
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
    2:
      case i of
        0..4: ToggleWin(i);
        5:
          for k := 0 to WIN_COUNT - 1 do DockWin(k);
        6: ZoomAt(Zoom * 1.25, CANVAS_W / 2, CANVAS_H / 2);
        7: ZoomAt(Zoom / 1.25, CANVAS_W / 2, CANVAS_H / 2);
        8: ZoomAt(1, CANVAS_W / 2, CANVAS_H / 2);
        9: ShowPressure := not ShowPressure;
        10: ShowAir := not ShowAir;
      end;
    MENU_THEME:
      DoTheme(i);
  end;
end;

function MenuBarX(m: Integer): Single;
begin
  Result := PX + m * (MENU_BAR_W + 4);
end;

function MenuW(m: Integer): Single;
begin
  case m of
    0: Result := 288;
    1: Result := 200;
    2: Result := 270;
  else
    Result := 170;
  end;
end;

function MenuX(m: Integer): Single;
begin
  Result := fmin(MenuBarX(m), PX + 288 - MenuW(m));   { keep drop-downs inside the window }
end;

function ItemY(i: Integer): Single;
var
  k: Integer;
begin
  Result := 30;
  for k := 0 to i do
  begin
    if MItems[k].Sep then Result := Result + 9;
    if k < i then Result := Result + 20;
  end;
end;

procedure DrawMenus(Pressed: Boolean);
var
  m, i: Integer;
  bx, x, w, y, top, h: Single;
  hot: Boolean;
begin
  for m := 0 to MENU_COUNT - 1 do
  begin
    bx := MenuBarX(m);
    hot := Inside(bx, 4, MENU_BAR_W, 18);
    { like a menu bar: with one menu open, hovering another opens that one }
    if (OpenMenu >= 0) and hot and (OpenMenu <> m) and not Pressed then OpenMenu := m;
    if OpenMenu = m then SetC(Th.BtnSel) else if hot then SetC(Th.BtnHot) else SetC(Th.BtnBg);
    FillR(bx, 4, MENU_BAR_W, 18);
    if OpenMenu = m then SetC(Th.BtnSelBorder) else SetC(Th.BtnBorder);
    RectR(bx, 4, MENU_BAR_W, 18);
    if OpenMenu = m then SetC(Th.BtnSelText) else SetC(Th.BtnText);
    TextR(Round(bx + (MENU_BAR_W - Length(MenuNames[m]) * 8) / 2), 9, MenuNames[m]);
    if Pressed and hot then
    begin
      if OpenMenu = m then OpenMenu := -1 else OpenMenu := m;
      Pressed := False;
    end;
  end;
  if OpenMenu < 0 then Exit;

  m := OpenMenu;
  BuildMenu(m);
  x := MenuX(m);
  w := MenuW(m);
  top := 24;
  h := ItemY(MCount - 1) + 24 - top;
  SetCol(0, 0, 0, 90);
  FillR(x + 4, top + 4, w, h);
  SetC(Th.MenuBg);
  FillR(x, top, w, h);
  SetC(Th.MenuBorder);
  RectR(x, top, w, h);
  for i := 0 to MCount - 1 do
  begin
    y := ItemY(i);
    if MItems[i].Sep then
    begin
      SetC(Th.MenuSep);
      LineR(x + 6, y - 5, x + w - 6, y - 5);
    end;
    hot := MItems[i].Enabled and Inside(x, y, w, 20);
    if hot then
    begin
      SetC(Th.MenuHot);
      FillR(x + 2, y, w - 4, 20);
    end;
    if MItems[i].Checked then
    begin
      if hot then SetC(Th.BtnSelText) else SetC(Th.Title);
      FillR(x + 7, y + 7, 6, 6);
    end;
    if not MItems[i].Enabled then SetC(Th.MenuDisabled)
    else if hot then SetC(Th.BtnSelText)
    else SetC(Th.Text);
    TextR(x + 20, y + 6, MItems[i].Lbl);
    if hot then SetC(Th.BtnSelText) else SetC(Th.MenuKey);
    TextR(x + w - 8 - Length(MItems[i].Key) * 8, y + 6, MItems[i].Key);
    if hot and Pressed then
    begin
      RunMenuItem(m, i);
      Exit;
    end;
  end;
  if Pressed and not Inside(x, top, w, h) then OpenMenu := -1;
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
    if Button(10 + i, QX + (i mod 3) * 94, y0 + (i div 3) * 23, 90, 20, ToolNames[t], Tool = t) then
    begin
      Tool := t;
      Drag := dragNone;
    end;
  end;
  SetC(Th.Hint);
  if PasteArmed then
    TextR(QX, y0 + 118, 'Click the canvas to paste (Esc)')
  else
    TextR(QX, y0 + 118, ToolHints[Tool]);
  y := y0 + 134;
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
  if Button(51, QX + 188, y0 + 70, 90, 20, 'Fill tanks') then RefillAllTanks;
end;

procedure DrawPropsContent(y0: Single);
var
  np, nb: Integer;
begin
  if (SelKind = selCell) and (Grid[SelX, SelY].Kind = ckEmpty) then SelKind := selNone;
  if (SelKind = selBucket) and not Buckets[SelB].Active then SelKind := selNone;
  if (SelKind = selLabel) and not Labels[SelL].Active then SelKind := selNone;
  if SelKind = selMulti then
  begin
    CountSelection(np, nb);
    if np + nb + CountSelLabels = 0 then SelKind := selNone;   { e.g. emptied by undo }
  end;
  case SelKind of
    selCell: DrawCellProps(y0);
    selLabel: DrawLabelProps(y0);
    selBucket: DrawBucketProps(y0);
    selMulti: DrawMultiProps(y0);
  else
    begin
      Info(y0 + 2, 'Nothing selected.');
      Info(y0 + 16, 'Use Select (1) and click a tank,');
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

procedure DrawPanel;
var
  i: Integer;
  dy: Single;
begin
  QX := PX;
  SetC(Th.PanelBg);
  FillR(PANEL_X, 0, PANEL_W, WIN_H);
  SetC(Th.PanelLine);
  LineR(PANEL_X, 0, PANEL_X, WIN_H);

  { the menu bar buttons are drawn last (with the drop-downs) }
  SetC(Th.Title);
  TextR(PX, 28, 'MATERIAL FLOW');
  SetC(Th.TextDim);
  TextR(PX + 112, 28, 'pipes, pumps & bulk');

  { a panel that is hidden, floating or embedded left leaves a note in its right slot }
  for i := 0 to WIN_COUNT - 1 do
    if not (Wins[i].Visible and WinDocked(i) and (Wins[i].Side = 0)) then
    begin
      dy := Wins[i].DockY;
      Header(dy + 4, Wins[i].Title);
      if not Wins[i].Visible then
      begin
        Info(dy + 20, 'This panel is hidden.');
        if Button(52 + i * 2, PX, dy + 34, 160, 18, 'Show (' + WinKeys[i] + ')') then ToggleWin(i);
      end
      else
      begin
        if WinDocked(i) then Info(dy + 20, 'Embedded on the left.')
        else Info(dy + 20, 'This panel is floating.');
        if Button(53 + i * 2, PX, dy + 34, 160, 18, 'Embed it here') then EmbedWin(i, 0);
      end;
      if Wins[i].H >= 80 then Info(dy + 58, 'Right-click a panel for options.');
    end;

  { the left column, when a panel is embedded there }
  if LeftW > 0 then
  begin
    SetC(Th.PanelBg);
    FillR(-LeftW, 0, LeftW, WIN_H);
    SetC(Th.PanelLine);
    LineR(-1, 0, -1, WIN_H);
    SetC(Th.TextDim);
    TextR(-LeftW + 8, 14, 'Right-click a panel to move it');
  end;

end;

procedure DrawStatusContent(y0: Single);
var
  gx, gy, L: Integer;
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
    if L >= 0 then
      s := Format('Label %d [%d,%d]', [L + 1, gx, gy])
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
  HELP_PAGES = 5;
  HelpTitles: array[0..HELP_PAGES - 1] of string = ('Basics', 'Select & move', 'Edit',
    'View & panels', 'Files & labels');
  HelpText: array[0..HELP_PAGES - 1, 0..4] of string = (
    ('L-drag: use the current tool', 'R-click: menu   R-drag: erase', 'Wheel on part: strength/size',
     'Space pause  P pressure  A air', 'Keys 1-0: pick a tool'),
    ('Select tool: drag a box', 'Drag a selected part: move it', 'R / Shift+R: rotate right/left',
     'Esc: deselect', 'Del: delete the selection'),
    ('Ctrl+Z undo   Ctrl+Y redo', 'Ctrl+X cut  Ctrl+C copy', 'Ctrl+V paste under the mouse',
     'Device tool on a pipe: insert', 'Pipe from a pipe: tee/cross'),
    ('Ctrl+wheel / Ctrl +/-: zoom', 'Ctrl+0: zoom 100%', 'Middle-drag or arrows: pan',
     'F1-F5: show / hide panels', 'R-click a panel: embed/float'),
    ('Ctrl+S save   Ctrl+O open', 'Ctrl+N new layout', 'File menu: 3 examples',
     'Label tool: click, then type', 'Double-click a label: edit'));

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
      Wn^.X := fclamp(MX - Wn^.DOX, -LeftW, WIN_W - Wn^.W);
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
  end;
  QX := PX;
end;

function InMenuBar(x, y: Single): Boolean;
begin
  Result := (y >= 4) and (y < 22) and (x >= PX) and (x < PX + MENU_COUNT * (MENU_BAR_W + 4));
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
  if InGrid(gx, gy) and (Grid[gx, gy].Kind <> ckEmpty) then
  begin
    EraseCell(gx, gy);
    if (SelKind = selCell) and (SelX = gx) and (SelY = gy) then SelKind := selNone;
    Exit;
  end;
  b := BucketAt(MWX, MWY);
  if b >= 0 then
  begin
    DeleteBucket(b);
    if (SelKind = selBucket) and (SelB = b) then SelKind := selNone;
  end;
end;

procedure ResizeAt(gx, gy: Integer);
begin
  if InGrid(gx, gy) and (Grid[gx, gy].Kind <> ckEmpty) then
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
    if Grid[nx, ny].Kind = ckEmpty then MakePipe(nx, ny, BrushDia);
    ConnectCells(LastCX, LastCY, nx, ny);
    LastCX := nx;
    LastCY := ny;
  end;
end;

procedure CanvasPress(Right: Boolean);
var
  gx, gy, b, L: Integer;
begin
  if (MWX < 0) or (MWY < 0) then Exit;   { outside the layout when zoomed out }
  gx := Trunc(MWX / CELL);
  gy := Trunc(MWY / CELL);
  if not InGrid(gx, gy) then Exit;
  L := LabelAt(MWX, MWY);
  { clicking anywhere but the label being typed into finishes it }
  if (EditLabel >= 0) and (L <> EditLabel) then StopEditLabel;
  if (not Right) and (not PasteArmed) and (Tool in [tSelect, tLabel]) and (L >= 0) then
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
  if Right then
  begin
    { decided on release: no movement = popup menu, moving = erase drag }
    RightPending := True;
    RCellX := gx;
    RCellY := gy;
    Exit;
  end;
  case Tool of
    tSelect:
      begin
        b := BucketAt(MWX, MWY);
        if Grid[gx, gy].Kind <> ckEmpty then
        begin
          { press on a part: select it (unless it is already in the selection),
            then dragging moves the whole selection }
          if not SelHasCell(gx, gy) then SelectCell(gx, gy);
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
    tTank, tBlower, tSuction, tNozzle, tDrop, tCheck, tValve2, tValve3, tValve4:
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
  CanvasLabels: array[0..5] of string = ('Cut', 'Copy', 'Paste here', 'Delete', 'Rotate', 'Edit label');
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
  PopupX := fclamp(MX, -LeftW, WIN_W - POPUP_W - 4);
  PopupY := fmin(MY, WIN_H - PopupH - 4);
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
  gx, gy, b, L: Integer;
begin
  gx := EnsureRange(Trunc(MWX / CELL), 0, GW - 1);
  gy := EnsureRange(Trunc(MWY / CELL), 0, GH - 1);
  { right-clicking something outside the current selection selects it first }
  if not ((SelKind = selMulti) and (gx >= SelX1) and (gx <= SelX2) and (gy >= SelY1) and (gy <= SelY2)) then
  begin
    b := BucketAt(MWX, MWY);
    L := LabelAt(MWX, MWY);
    if L >= 0 then
    begin
      if L <> EditLabel then StopEditLabel;
      SelKind := selLabel;
      SelL := L;
    end
    else if Grid[gx, gy].Kind <> ckEmpty then
      SelectCell(gx, gy)
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
        5: en := SelKind = selLabel;
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
          5: StartEditLabel(SelL);
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
  b := BucketAt(wx, wy);
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
      if PopupOpen then
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
    Ord('a'): ShowAir := not ShowAir;
    Ord('c'): ClearParticles;
    Ord('1'): Tool := tSelect;
    Ord('2'): Tool := tPipe;
    Ord('3'): Tool := tResize;
    Ord('4'): Tool := tErase;
    Ord('5'): Tool := tTank;
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
  end;
end;

{ ---------------------------------------------------------------- main loop }

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

{ --selftest <report.txt> : exercises undo/redo, cut/copy/paste and themes }
procedure RunSelfTest(const FileName: string);
var
  f: TextFile;
  fails, i, b, np, nb: Integer;
  bx, by: Single;
  err: string;

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

  { status and help panels }
  ToggleWin(WIN_STATUS);
  ToggleWin(WIN_HELP);
  Check('F5 / F1 hide status and help', not Wins[WIN_STATUS].Visible and not Wins[WIN_HELP].Visible);
  ToggleWin(WIN_STATUS);
  ToggleWin(WIN_HELP);
  Check('status and help docked by default', WinDocked(WIN_STATUS) and WinDocked(WIN_HELP) and
    (WinAt(PANEL_X + 50, 690) = WIN_STATUS) and (WinAt(PANEL_X + 50, 760) = WIN_HELP));

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
  quit: Boolean;
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

  ww := WIN_W;
  wh := WIN_H;
  if SDL_GetDisplayUsableBounds(SDL_GetPrimaryDisplay, @db) then
  begin
    sc := fmin(1, fmin((db.w - 20) / WIN_W, (db.h - 60) / WIN_H));
    if sc > 0.3 then
    begin
      ww := Round(WIN_W * sc);
      wh := Round(WIN_H * sc);
    end;
  end;
  Win := SDL_CreateWindow('Material Flow Simulator - SDL3', ww, wh, SDL_WINDOW_RESIZABLE);
  if Win = nil then
    raise Exception.Create('SDL_CreateWindow failed: ' + string(SDL_GetError));
  Ren := SDL_CreateRenderer(Win, nil);
  if Ren = nil then
    raise Exception.Create('SDL_CreateRenderer failed: ' + string(SDL_GetError));
  SDL_SetRenderLogicalPresentation(Ren, WIN_W, WIN_H, SDL_LOGICAL_PRESENTATION_LETTERBOX);
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

  LoadDemo;
  LayoutName := 'Demo';
  UpdateTitle;
  HistReset;
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
    else if ParamStr(5) = 'edit' then OpenMenu := 1
    else if ParamStr(5) = 'view' then OpenMenu := 2
    else if ParamStr(5) = 'theme' then OpenMenu := MENU_THEME
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

  quit := False;
  last := SDL_GetTicksNS;
  while not quit do
  begin
    MPressed := False;
    while SDL_PollEvent(@ev) do
    begin
      SDL_ConvertEventToRenderCoordinates(Ren, @ev);
      case ev.type_ of
        SDL_EVENT_QUIT:
          quit := True;
        SDL_EVENT_KEY_DOWN:
          { while a label is being typed into, keys belong to it }
          if EditLabel >= 0 then LabelKey(ev.key.key)
          else HandleKey(ev.key.key, ev.key.mod_);
        SDL_EVENT_TEXT_INPUT:
          if ev.text.text <> nil then LabelTypeText(string(ev.text.text));
        SDL_EVENT_MOUSE_MOTION:
          begin
            MX := ev.motion.x - OX;
            MY := ev.motion.y;
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
            MY := ev.button.y;
            LastClicks := ev.button.clicks;
            if ev.button.button = SDL_BUTTON_MIDDLE then
            begin
              { middle-drag pans the canvas }
              if (MX >= 0) and (MX < CANVAS_W) and not InAnyWin(MX, MY) then
              begin
                Panning := True;
                PanLastX := MX;
                PanLastY := MY;
              end;
            end
            else if PopupOpen then
            begin
              { the popup takes this click: an item, or closing it }
              if Inside(PopupX, PopupY, POPUP_W, PopupH) then
                PopupClick := True
              else
                PopupOpen := False;
            end
            else if (MX < CANVAS_W) and (OpenMenu >= 0) then
              OpenMenu := -1        { a click outside the open menu just closes it }
            else if ev.button.button = SDL_BUTTON_LEFT then
            begin
              MDown := True;
              MPressed := True;
              if (MX >= 0) and (MX < CANVAS_W) and not InAnyWin(MX, MY) then CanvasPress(False);
            end
            else if ev.button.button = SDL_BUTTON_RIGHT then
            begin
              RDown := True;
              if InAnyWin(MX, MY) then
                OpenPanelPopup(WinAt(MX, MY))   { panel: Right / Left embed, Float, Hide }
              else if (MX >= 0) and (MX < CANVAS_W) then
                CanvasPress(True);
            end;
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
              else if Drag = dragMove then FinishMove;
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
            MY := ev.wheel.mouse_y;
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
        else if Drag = dragMove then FinishMove;
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
    if (not MDown) and (not RDown) and (Drag = dragNone) and (WheelIdle > 0.5) and (EditLabel < 0) then
      HistCheck;

    SimFrame(fmin(FrameDt, 1 / 30), Running);
    Render;
    SDL_RenderPresent(Ren);
  end;

  SaveSettings;   { panel places and theme for next time }
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
end;

end.
