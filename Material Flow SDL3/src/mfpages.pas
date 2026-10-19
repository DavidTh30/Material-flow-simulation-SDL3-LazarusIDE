unit mfpages;

{ Pages, layers and frame popups.

  A layout holds up to MAX_PAGES pages. Each page is a full canvas of its
  own: pipe cells, tanks / feeders, buckets, labels, frames, links, gravity
  and the material in flight. The simulation always works on the live
  globals of simcore (Grid, Parts, Buckets, ...); those belong to the page
  being shown (CurPage). Going to another page parks the live state in
  Pages[CurPage] and brings the other page's state in, so a page that is not
  shown is paused and carries on where it stopped.

  Every page has 1..MAX_LAYERS layers. Every part, bucket, label, frame and
  link sits on one layer (its Layer field). A layer can be hidden (not drawn,
  cannot be picked) or locked (drawn, but cannot be picked or changed).
  Hiding a layer does not stop its parts from working.

  Frame popups (max MAX_POPUPS per layout) are small windows with a title,
  text and an optional "go to page" button, opened over the canvas by a link. }

{$mode objfpc}{$H+}

interface

uses
  simcore, elec, fluid, plantbus, flowchart, trends, piecesim;

const
  MAX_PAGES = 20;
  MAX_LAYERS = 5;
  MAX_POPUPS = 20;

type
  TLayerInfo = record
    Name: string[24];
    Visible: Boolean;
    Locked: Boolean;
  end;

  TPageData = record
    Name: string[40];
    NLayers: Integer;
    Layers: array[0..MAX_LAYERS - 1] of TLayerInfo;
    ActiveLayer: Integer;
    { the parked content (valid while the page is not the current one) }
    Grid: array[0..GW - 1, 0..GH - 1] of TCell;
    Parts: array of TParticle;
    NPart, NAir: Integer;
    Buckets: array[0..MAX_BUCKETS - 1] of TBucket;
    Labels: array[0..MAX_LABELS - 1] of TLabelObj;
    Frames: array[0..MAX_FRAMES - 1] of TFrameObj;
    Tables: array[0..MAX_TABLES - 1] of TTableObj;
    Links: array[0..MAX_LINKS - 1] of TLinkObj;
    Equips: array[0..MAX_EQUIP - 1] of TEquipObj;
    EGrid: array[0..GW - 1, 0..GH - 1] of TECell;
    FGrid: array[0..GW - 1, 0..GH - 1] of TFCell;
    Flows: array[0..MAX_FLOW - 1] of TFlowNode;
    Pieces: array[0..MAX_PIECES - 1] of TPiece;
    Gravity: Single;
  end;

  { a Focus Properties window (the app draws it): which item, where, on which page }
  TPinWin = record
    Kind: Byte;            { the app's selection kind (TSelKind) }
    A, B: Integer;         { cell x, y / the index of the item }
    X, Y, W, H: Single;
    Page: Integer;
    Dragging: Boolean;
    DOX, DOY: Single;
    Scale: Single;            { its content drawn this much larger (0 = 1) }
    Sizing: Boolean;          { its size grip is being dragged }
    Scroll, ContentH: Single; { its content scrolled; how tall it was }
    ScrollDrag: Boolean;
    DragOff: Single;
  end;

  TPopup = record
    Active: Boolean;
    Title: string[60];
    Text: string[255];     { lines separated by #10 }
    GoPage: Integer;       { -1: no button, else a "Go to page" button }
    Color: Byte;           { 0 theme, 1 blue, 2 green, 3 amber, 4 red, 5 white }
    BX, BY, BW, BH: Single; { where it was moved / sized to; BW = 0: centred, sized to its text }
  end;

var
  Pages: array[0..MAX_PAGES - 1] of TPageData;
  PageCount: Integer = 1;
  CurPage: Integer = 0;
  Popups: array[0..MAX_POPUPS - 1] of TPopup;
  ShownPopup: Integer = -1;       { the popup shown over the canvas, -1 none }
  Pins: array of TPinWin;         { the Focus Properties windows of every page }

{ one empty page with one layer; popups cleared. The live globals become page 1. }
procedure PagesReset;
{ copy the live globals into Pages[i] / back }
procedure ParkPage(i: Integer);
procedure UnparkPage(i: Integer);
{ show another page (the current one is parked) }
procedure GoToPage(i: Integer);
{ add an empty page after the last one (does not switch); -1 when full }
function AddPage(const Name: string): Integer;
{ a copy of page i after the last page; -1 when full }
function DuplicatePage(i: Integer): Integer;
procedure DeletePage(i: Integer);
{ swap page i with page i + Delta (-1 / +1) }
procedure MovePage(i, Delta: Integer);
function PageName(i: Integer): string;

function AddLayer(const Name: string): Integer;
procedure DeleteLayer(L: Integer);
procedure SetActiveLayer(L: Integer);
function LayerShown(L: Integer): Boolean;
{ shown and not locked: its objects can be picked and changed }
function LayerEditable(L: Integer): Boolean;
function LayerCount: Integer;

function AddPopup(const Title, Text: string): Integer;
procedure DeletePopup(i: Integer);
function FramePopupCount: Integer;
procedure ShowFramePopup(i: Integer);
procedure CloseFramePopup;

{ follow a link: go to its page or open its popup }
procedure FollowLink(i: Integer);

{ one frame of every page at the same time (the page on screen last), sharing the plant bus }
procedure SimAllPages(dt: Single; Running: Boolean);

implementation

uses
  SysUtils;

var
  TmpPage: TPageData;

{ page links after page Gone was deleted: links to it lose their target, later pages move up }
procedure FixLinksAfterDelete(var A: array of TLinkObj; Gone: Integer);
var
  k: Integer;
begin
  for k := 0 to High(A) do
    if A[k].Active and not A[k].ToPopup then
    begin
      if A[k].Target = Gone then A[k].Target := -1
      else if A[k].Target > Gone then Dec(A[k].Target);
    end;
end;

procedure SwapLinkTargets(var A: array of TLinkObj; i, j: Integer);
var
  k: Integer;
begin
  for k := 0 to High(A) do
    if A[k].Active and not A[k].ToPopup then
    begin
      if A[k].Target = i then A[k].Target := j
      else if A[k].Target = j then A[k].Target := i;
    end;
end;

procedure DefaultLayers(var P: TPageData);
var
  L: Integer;
begin
  P.NLayers := 1;
  for L := 0 to MAX_LAYERS - 1 do
  begin
    P.Layers[L].Name := 'Layer ' + Chr(Ord('1') + L);
    P.Layers[L].Visible := True;
    P.Layers[L].Locked := False;
  end;
  P.Layers[0].Name := 'Main';
  P.ActiveLayer := 0;
end;

procedure EmptyContent(var P: TPageData);
var
  x, y, i: Integer;
begin
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      FillChar(P.Grid[x, y], SizeOf(TCell), 0);
      P.Grid[x, y].Kind := ckEmpty;
      P.Grid[x, y].Dia := 3;
      P.Grid[x, y].Mouth := -1;
      P.Grid[x, y].Open := True;
    end;
  SetLength(P.Parts, 0);
  P.NPart := 0;
  P.NAir := 0;
  for i := 0 to MAX_BUCKETS - 1 do P.Buckets[i].Active := False;
  for i := 0 to MAX_LABELS - 1 do P.Labels[i].Active := False;
  for i := 0 to MAX_FRAMES - 1 do P.Frames[i].Active := False;
  for i := 0 to MAX_TABLES - 1 do P.Tables[i].Active := False;
  for i := 0 to MAX_LINKS - 1 do P.Links[i].Active := False;
  for i := 0 to MAX_EQUIP - 1 do P.Equips[i].Active := False;
  FillChar(P.EGrid, SizeOf(P.EGrid), 0);
  FillChar(P.FGrid, SizeOf(P.FGrid), 0);
  FillChar(P.Flows, SizeOf(P.Flows), 0);
  FillChar(P.Pieces, SizeOf(P.Pieces), 0);
  P.Gravity := 1.0;
end;

procedure PagesReset;
var
  i: Integer;
begin
  for i := 0 to MAX_PAGES - 1 do
  begin
    Pages[i].Name := '';
    DefaultLayers(Pages[i]);
    SetLength(Pages[i].Parts, 0);
  end;
  Pages[0].Name := 'Page 1';
  PageCount := 1;
  CurPage := 0;
  BusPage := 0;
  CurLayer := 0;
  for i := 0 to MAX_POPUPS - 1 do Popups[i].Active := False;
  ShownPopup := -1;
  SetLength(Pins, 0);
  BusClear;
  TrendsClear;
  TimelinesClear;
end;

procedure ParkPage(i: Integer);
var
  k: Integer;
begin
  if (i < 0) or (i >= MAX_PAGES) then Exit;
  Pages[i].Grid := Grid;
  SetLength(Pages[i].Parts, NPart);
  for k := 0 to NPart - 1 do Pages[i].Parts[k] := Parts[k];
  Pages[i].NPart := NPart;
  Pages[i].NAir := NAir;
  Pages[i].Buckets := Buckets;
  Pages[i].Labels := Labels;
  Pages[i].Frames := Frames;
  Pages[i].Tables := Tables;
  Pages[i].Links := Links;
  Pages[i].Equips := Equips;
  Pages[i].EGrid := EGrid;
  Pages[i].FGrid := FGrid;
  Pages[i].Flows := FlowNodes;
  Pages[i].Pieces := Pieces;
  Pages[i].Gravity := GravityScale;
  Pages[i].ActiveLayer := CurLayer;
end;

procedure UnparkPage(i: Integer);
var
  k, n: Integer;
begin
  if (i < 0) or (i >= MAX_PAGES) then Exit;
  Grid := Pages[i].Grid;
  n := Pages[i].NPart;
  if n > Length(Parts) then n := Length(Parts);
  if n > Length(Pages[i].Parts) then n := Length(Pages[i].Parts);
  for k := 0 to n - 1 do Parts[k] := Pages[i].Parts[k];
  NPart := n;
  NAir := Pages[i].NAir;
  SetLength(Pages[i].Parts, 0);   { the live copy is the real one now }
  Buckets := Pages[i].Buckets;
  Labels := Pages[i].Labels;
  Frames := Pages[i].Frames;
  Tables := Pages[i].Tables;
  Links := Pages[i].Links;
  Equips := Pages[i].Equips;
  EGrid := Pages[i].EGrid;
  FGrid := Pages[i].FGrid;
  FlowNodes := Pages[i].Flows;
  Pieces := Pages[i].Pieces;
  GravityScale := Pages[i].Gravity;
  if Pages[i].ActiveLayer >= Pages[i].NLayers then Pages[i].ActiveLayer := 0;
  CurLayer := Pages[i].ActiveLayer;
end;

procedure GoToPage(i: Integer);
begin
  if (i < 0) or (i >= PageCount) or (i = CurPage) then Exit;
  ParkPage(CurPage);
  CurPage := i;
  BusPage := i;
  UnparkPage(i);
  ShownPopup := -1;
end;

function AddPage(const Name: string): Integer;
begin
  if PageCount >= MAX_PAGES then Exit(-1);
  Result := PageCount;
  Inc(PageCount);
  DefaultLayers(Pages[Result]);
  EmptyContent(Pages[Result]);
  if Name = '' then Pages[Result].Name := 'Page ' + IntToStr(Result + 1)
  else Pages[Result].Name := Name;
end;

function DuplicatePage(i: Integer): Integer;
var
  k: Integer;
begin
  if (PageCount >= MAX_PAGES) or (i < 0) or (i >= PageCount) then Exit(-1);
  if i = CurPage then ParkPage(CurPage);
  Result := PageCount;
  Inc(PageCount);
  Pages[Result] := Pages[i];
  { a real copy of the particle array, not a shared reference }
  SetLength(Pages[Result].Parts, Length(Pages[i].Parts));
  for k := 0 to High(Pages[i].Parts) do Pages[Result].Parts[k] := Pages[i].Parts[k];
  Pages[Result].Name := Copy(Pages[i].Name + ' copy', 1, 40);
  if i = CurPage then SetLength(Pages[i].Parts, 0);
end;

procedure DeletePage(i: Integer);
var
  k: Integer;
begin
  if (PageCount <= 1) or (i < 0) or (i >= PageCount) then Exit;
  if i = CurPage then
  begin
    { show a neighbour first so the live state is a page that stays }
    if i > 0 then GoToPage(i - 1) else GoToPage(1);
  end;
  ParkPage(CurPage);
  BusClear;
  TrendsClear;
  TimelinesClear;
  SetLength(Pages[i].Parts, 0);
  for k := i to PageCount - 2 do Pages[k] := Pages[k + 1];
  Dec(PageCount);
  { a fresh, unshared particle array in the slot that fell off the end }
  Pages[PageCount].Parts := nil;
  if CurPage > i then Dec(CurPage);
  UnparkPage(CurPage);
  { links and popups that pointed at the deleted page or past it }
  for k := 0 to PageCount - 1 do
    if k <> CurPage then
      FixLinksAfterDelete(Pages[k].Links, i);
  FixLinksAfterDelete(Links, i);
  for k := 0 to MAX_POPUPS - 1 do
    if Popups[k].Active then
    begin
      if Popups[k].GoPage = i then Popups[k].GoPage := -1
      else if Popups[k].GoPage > i then Dec(Popups[k].GoPage);
    end;
  k := 0;
  while k <= High(Pins) do
    if Pins[k].Page = i then
    begin
      Pins[k] := Pins[High(Pins)];
      SetLength(Pins, Length(Pins) - 1);
    end
    else
    begin
      if Pins[k].Page > i then Dec(Pins[k].Page);
      Inc(k);
    end;
end;

procedure MovePage(i, Delta: Integer);
var
  j, k: Integer;
begin
  j := i + Delta;
  if (i < 0) or (i >= PageCount) or (j < 0) or (j >= PageCount) then Exit;
  ParkPage(CurPage);
  BusClear;
  TrendsClear;
  TimelinesClear;
  TmpPage := Pages[i];
  Pages[i] := Pages[j];
  Pages[j] := TmpPage;
  TmpPage.Parts := nil;
  if CurPage = i then CurPage := j
  else if CurPage = j then CurPage := i;
  BusPage := CurPage;
  UnparkPage(CurPage);
  { links keep pointing at the same page }
  for k := 0 to PageCount - 1 do
    if k <> CurPage then SwapLinkTargets(Pages[k].Links, i, j);
  SwapLinkTargets(Links, i, j);
  for k := 0 to MAX_POPUPS - 1 do
    if Popups[k].GoPage = i then Popups[k].GoPage := j
    else if Popups[k].GoPage = j then Popups[k].GoPage := i;
  for k := 0 to High(Pins) do
    if Pins[k].Page = i then Pins[k].Page := j
    else if Pins[k].Page = j then Pins[k].Page := i;
end;

function PageName(i: Integer): string;
begin
  if (i < 0) or (i >= PageCount) then Exit('(none)');
  Result := Pages[i].Name;
  if Result = '' then Result := 'Page ' + IntToStr(i + 1);
end;

{ ------------------------------------------------------------------ layers }

function LayerCount: Integer;
begin
  Result := Pages[CurPage].NLayers;
end;

function AddLayer(const Name: string): Integer;
var
  P: ^TPageData;
begin
  P := @Pages[CurPage];
  if P^.NLayers >= MAX_LAYERS then Exit(-1);
  Result := P^.NLayers;
  Inc(P^.NLayers);
  if Name = '' then P^.Layers[Result].Name := 'Layer ' + IntToStr(Result + 1)
  else P^.Layers[Result].Name := Name;
  P^.Layers[Result].Visible := True;
  P^.Layers[Result].Locked := False;
end;

{ remove layer L of the current page; its objects move to the layer below it }
procedure DeleteLayer(L: Integer);
var
  P: ^TPageData;
  x, y, i, k: Integer;

  function Shift(v: Byte): Byte;
  begin
    if v > L then Result := v - 1
    else if v = L then
    begin
      if L > 0 then Result := L - 1 else Result := 0;
    end
    else Result := v;
  end;

begin
  P := @Pages[CurPage];
  if (P^.NLayers <= 1) or (L < 0) or (L >= P^.NLayers) then Exit;
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
      Grid[x, y].Layer := Shift(Grid[x, y].Layer);
  for i := 0 to MAX_BUCKETS - 1 do Buckets[i].Layer := Shift(Buckets[i].Layer);
  for i := 0 to MAX_LABELS - 1 do Labels[i].Layer := Shift(Labels[i].Layer);
  for i := 0 to MAX_FRAMES - 1 do Frames[i].Layer := Shift(Frames[i].Layer);
  for i := 0 to MAX_TABLES - 1 do Tables[i].Layer := Shift(Tables[i].Layer);
  for i := 0 to MAX_LINKS - 1 do Links[i].Layer := Shift(Links[i].Layer);
  for i := 0 to MAX_EQUIP - 1 do Equips[i].Layer := Shift(Equips[i].Layer);
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      EGrid[x, y].Layer := Shift(EGrid[x, y].Layer);
      FGrid[x, y].Layer := Shift(FGrid[x, y].Layer);
    end;
  for k := L to P^.NLayers - 2 do P^.Layers[k] := P^.Layers[k + 1];
  Dec(P^.NLayers);
  P^.Layers[P^.NLayers].Name := 'Layer ' + IntToStr(P^.NLayers + 1);
  P^.Layers[P^.NLayers].Visible := True;
  P^.Layers[P^.NLayers].Locked := False;
  if CurLayer >= P^.NLayers then CurLayer := P^.NLayers - 1
  else if CurLayer > L then Dec(CurLayer);
  P^.ActiveLayer := CurLayer;
end;

procedure SetActiveLayer(L: Integer);
begin
  if (L < 0) or (L >= Pages[CurPage].NLayers) then Exit;
  CurLayer := L;
  Pages[CurPage].ActiveLayer := L;
end;

function LayerShown(L: Integer): Boolean;
begin
  if L >= Pages[CurPage].NLayers then Exit(True);
  Result := Pages[CurPage].Layers[L].Visible;
end;

function LayerEditable(L: Integer): Boolean;
begin
  if L >= Pages[CurPage].NLayers then Exit(True);
  Result := Pages[CurPage].Layers[L].Visible and not Pages[CurPage].Layers[L].Locked;
end;

{ ------------------------------------------------------------------ popups }

function AddPopup(const Title, Text: string): Integer;
var
  i: Integer;
begin
  for i := 0 to MAX_POPUPS - 1 do
    if not Popups[i].Active then
    begin
      Popups[i].Active := True;
      Popups[i].Title := Title;
      Popups[i].Text := Text;
      Popups[i].GoPage := -1;
      Popups[i].Color := 1;
      Popups[i].BW := 0;
      Exit(i);
    end;
  Result := -1;
end;

procedure DeletePopup(i: Integer);
begin
  if (i < 0) or (i >= MAX_POPUPS) then Exit;
  Popups[i].Active := False;
  if ShownPopup = i then ShownPopup := -1;
end;

function FramePopupCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to MAX_POPUPS - 1 do
    if Popups[i].Active then Inc(Result);
end;

procedure ShowFramePopup(i: Integer);
begin
  if (i >= 0) and (i < MAX_POPUPS) and Popups[i].Active then ShownPopup := i;
end;

procedure CloseFramePopup;
begin
  ShownPopup := -1;
end;

{ ------------------------------------------------------------------ every page at once }

{ like ParkPage / UnparkPage, but the particle arrays change places instead of being copied }
procedure ParkFast(i: Integer);
var
  tmp: array of TParticle;
begin
  Pages[i].Grid := Grid;
  Pages[i].NPart := NPart;
  Pages[i].NAir := NAir;
  Pages[i].Buckets := Buckets;
  Pages[i].Labels := Labels;
  Pages[i].Frames := Frames;
  Pages[i].Tables := Tables;
  Pages[i].Links := Links;
  Pages[i].Equips := Equips;
  Pages[i].EGrid := EGrid;
  Pages[i].FGrid := FGrid;
  Pages[i].Flows := FlowNodes;
  Pages[i].Pieces := Pieces;
  Pages[i].Gravity := GravityScale;
  Pages[i].ActiveLayer := CurLayer;
  tmp := Pages[i].Parts;
  Pages[i].Parts := Parts;
  Parts := tmp;
  tmp := nil;
  if Length(Parts) < MAX_PART then SetLength(Parts, MAX_PART);
end;

procedure UnparkFast(i: Integer);
var
  tmp: array of TParticle;
begin
  Grid := Pages[i].Grid;
  Buckets := Pages[i].Buckets;
  Labels := Pages[i].Labels;
  Frames := Pages[i].Frames;
  Tables := Pages[i].Tables;
  Links := Pages[i].Links;
  Equips := Pages[i].Equips;
  EGrid := Pages[i].EGrid;
  FGrid := Pages[i].FGrid;
  FlowNodes := Pages[i].Flows;
  Pieces := Pages[i].Pieces;
  GravityScale := Pages[i].Gravity;
  tmp := Parts;
  Parts := Pages[i].Parts;
  Pages[i].Parts := tmp;
  tmp := nil;
  if Length(Parts) < MAX_PART then SetLength(Parts, MAX_PART);
  NPart := Pages[i].NPart;
  if NPart > Length(Parts) then NPart := Length(Parts);
  if NPart < 0 then NPart := 0;
  NAir := Pages[i].NAir;
  if Pages[i].ActiveLayer >= Pages[i].NLayers then Pages[i].ActiveLayer := 0;
  CurLayer := Pages[i].ActiveLayer;
end;

procedure SimAllPages(dt: Single; Running: Boolean);
var
  k: Integer;
begin
  if PageCount > 1 then
  begin
    ParkFast(CurPage);
    for k := 0 to PageCount - 1 do
      if k <> CurPage then
      begin
        UnparkFast(k);
        BusPage := k;
        SimFrame(dt, Running);
        ElecPublish(k);
        ParkFast(k);
      end;
    UnparkFast(CurPage);
  end;
  BusPage := CurPage;
  SimFrame(dt, Running);
  ElecPublish(CurPage);
end;

procedure FollowLink(i: Integer);
begin
  if (i < 0) or (i >= MAX_LINKS) or not Links[i].Active then Exit;
  if Links[i].ToPopup then ShowFramePopup(Links[i].Target)
  else GoToPage(Links[i].Target);
end;

end.
