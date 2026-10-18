unit layoutio;

{ Save / load pipe layouts as plain text (.mflow).

  # comment
  MFLOW 2
  NAME <free text>
  POPUP <n> <go page|-1> <colour> <title>      frame popup n (1..20)
  POPUPTEXT <n> <text>                         (\n = new line)
  PAGE <name>                                  starts a page (max 20)
  LAYERS <count> <active>                      layers of this page (max 5)
  LAYER <n> <visible> <locked> <name>
  ON <n>                                       what follows is on layer n
  GRAVITY <scale>
  CELL <x> <y> <kind> <conn> <dia> <dir> <open> <strength>
  STOCK <x> <y> <water> <oil> <fluff> <sand> <air%> <feed%>   (TANK in old files)
  LINK <x> <y> <colour> <page|popup> <n> <caption>
  EQUIP <kind> <x> <y> <w> <h> <stop|run|fault> <flip> <link x> <link y> <level%> <name>
        kind: motor blower paddle screw cyclone silo stand lamp legend sequence diverter
              shutter slide heater irheater rain fire pond pool well pump;
        state: stop run fault mstart mstop disable
  EQX <mode> <seq step> <delay s> <pos 1 shuts> <pos 2 shuts>   (after an EQUIP line)
  EQSRC <min> <max> <source>                   (after an EQUIP line: what a gauge / display shows)
  PIN <kind> <a> <b> <x> <y> <w> <h>           a Focus Properties window on the page
  FCELL <x> <y> <kind> <conn> <dir> <act> <sel> <on> <p1> <p2> <tag> <ref> <sol a> <sol b>
        a pneumatic / hydraulic cell (strings: - when empty, \s = space)
        kind: cell bucket label frame link equip ecell; a b: cell x y, or the item's index
  ECELL <x> <y> <kind> <conn> <dir> <pos> <npos> <sel> <on> <tripped> <p1> <p2> <tag> <ref> [<src> [<p3>]]
        an electrical cell (tag / ref: - when empty, \s = space)
        link -1 -1 = not linked to a part
  BUCKET <x> <y> <w> <h>
  LABEL <x> <y> <text>            (\n = new line in the text)
  FRAME <x> <y> <w> <h> <colour> <dashed> <fill> <carry> <title>
  LABEL2 <kind> <x> <y> <colour> <box> <format> <caption>
                                  (kind text/date/time; format: FormatDateTime
                                   codes, \s = space, - = none; box 1/0)

  kind: pipe feeder blower suction nozzle drop check valve2 valve3 valve4 hopper silo vfeeder
  ("tank" is read as feeder; STOCK lines hold the contents of feeders, hoppers, silos)
  A version 1 file (no PAGE lines) loads as a single page with one layer.
  Pages, layers, links and popups are numbered from 1 in the file.
  a valve4 CELL has a 10th value: its shut branches (ESWN letters or "-")
  conn: joined sides as letters from ESWN (e.g. "EW"), "-" for none
  dir : E S W N, "-" for none (3-way valve with every branch open)
  Particles are not saved - only the layout and its settings. }

{$mode objfpc}{$H+}

interface

var
  LayoutName: string = '';

function SaveLayout(const FileName: UnicodeString; out Err: string): Boolean;
function LoadLayout(const FileName: UnicodeString; out Err: string): Boolean;

implementation

uses
  SysUtils, Math, simcore, mfpages, elec, fluid, flowchart, mftheme;

const
  LabelKinds: array[0..2] of string = ('text', 'date', 'time');
  KindTags: array[TCellKind] of string = ('empty', 'pipe', 'feeder', 'blower', 'suction',
    'nozzle', 'drop', 'check', 'valve2', 'valve3', 'valve4', 'hopper', 'silo', 'vfeeder');
  DirLetters = 'ESWN';
  EquipStates: array[0..EQS_COUNT - 1] of string = ('stop', 'run', 'fault', 'mstart', 'mstop', 'disable');
  LinkKinds: array[0..1] of string = ('page', 'popup');
  { the app's selection kinds, in their order }
  PinKinds: array[0..10] of string = ('none', 'cell', 'bucket', 'multi', 'label', 'frame', 'link', 'equip', 'ecell',
    'fcell', 'flow');

var
  FS: TFormatSettings;
  OldPages: array[0..MAX_PAGES - 1] of TPageData;
  OldPopups: array[0..MAX_POPUPS - 1] of TPopup;
  OldPins: array of TPinWin;

function F2S(v: Single): string;
begin
  Result := FloatToStrF(v, ffFixed, 10, 2, FS);
end;

function ConnStr(c: Byte): string;
var
  d: Integer;
begin
  Result := '';
  for d := 0 to 3 do
    if (c and (1 shl d)) <> 0 then Result := Result + DirLetters[d + 1];
  if Result = '' then Result := '-';
end;

function DirStr(d: Integer): string;
begin
  if (d < 0) or (d > 3) then Result := '-' else Result := DirLetters[d + 1];
end;

{ 4-way valve: the shut branches as letters, "-" when all are open }
function ClosedStr(c: Byte): string;
begin
  Result := ConnStr(c);
end;

{ label text on one line: newline -> \n, backslash -> \\ }
function EscapeText(const s: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(s) do
    case s[i] of
      #10: Result := Result + '\n';
      '\': Result := Result + '\\';
      #13: ;
    else
      Result := Result + s[i];
    end;
end;

{ one word: like EscapeText, plus space -> \s; empty -> - }
function EscapeToken(const s: string): string;
var
  i: Integer;
  e: string;
begin
  if s = '' then Exit('-');
  e := EscapeText(s);
  Result := '';
  for i := 1 to Length(e) do
    if e[i] = ' ' then Result := Result + '\s' else Result := Result + e[i];
end;

function UnescapeText(const s: string): string;
var
  i: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(s) do
  begin
    if (s[i] = '\') and (i < Length(s)) then
    begin
      Inc(i);
      if s[i] = 'n' then Result := Result + #10
      else if s[i] = 's' then Result := Result + ' '
      else Result := Result + s[i];
    end
    else
      Result := Result + s[i];
    Inc(i);
  end;
end;
{ the objects of the live page that sit on layer L (objects on a layer past the last count as the last) }
const
  TLPinKinds: array[0..2] of string = ('-', 'in', 'fix');

procedure WritePageBody(var f: TextFile; L, NL: Integer);

  function Mine(v: Byte): Boolean;
  begin
    if v >= NL then Result := L = NL - 1 else Result := v = L;
  end;

var
  x, y, i, k: Integer;
  c: PCell;
begin
  WriteLn(f, 'ON ', L + 1);
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @Grid[x, y];
      if (c^.Kind = ckEmpty) or not Mine(c^.Layer) then Continue;
      if c^.Kind = ckValve4 then
        WriteLn(f, Format('CELL %d %d %s %s %d %s %d %s %s', [x, y, KindTags[c^.Kind],
          ConnStr(c^.Conn), c^.Dia, DirStr(c^.Dir), Ord(c^.Open), F2S(c^.Strength), ClosedStr(c^.Closed)]))
      else
        WriteLn(f, Format('CELL %d %d %s %s %d %s %d %s', [x, y, KindTags[c^.Kind],
          ConnStr(c^.Conn), c^.Dia, DirStr(c^.Dir), Ord(c^.Open), F2S(c^.Strength)]));
      if IsStore(c^.Kind) then
        WriteLn(f, Format('STOCK %d %d %s %s %s %s %s %s', [x, y, F2S(c^.Stock[mWater]),
          F2S(c^.Stock[mOil]), F2S(c^.Stock[mFluff]), F2S(c^.Stock[mSand]), F2S(c^.AirPct), F2S(c^.Feed)]));
    end;
  for i := 0 to MAX_BUCKETS - 1 do
    if Buckets[i].Active and Mine(Buckets[i].Layer) then
      WriteLn(f, Format('BUCKET %s %s %s %s', [F2S(Buckets[i].X), F2S(Buckets[i].Y),
        F2S(Buckets[i].W), F2S(Buckets[i].H)]));
  for i := 0 to MAX_FRAMES - 1 do
    if Frames[i].Active and Mine(Frames[i].Layer) then
      WriteLn(f, Format('FRAME %s %s %s %s %d %d %d %d %s', [F2S(Frames[i].X), F2S(Frames[i].Y),
        F2S(Frames[i].W), F2S(Frames[i].H), Frames[i].Color, Ord(Frames[i].Dashed), Ord(Frames[i].Fill),
        Ord(Frames[i].Carry), EscapeText(Frames[i].Title)]));
  for i := 0 to MAX_LABELS - 1 do
    if Labels[i].Active and Mine(Labels[i].Layer) then
    begin
      if (Labels[i].Kind = LBL_TEXT) and (Labels[i].Color = 0) and not Labels[i].NoBox then
        WriteLn(f, Format('LABEL %s %s %s', [F2S(Labels[i].X), F2S(Labels[i].Y), EscapeText(Labels[i].Text)]))
      else
        WriteLn(f, Format('LABEL2 %s %s %s %d %d %s %s', [LabelKinds[Labels[i].Kind], F2S(Labels[i].X),
          F2S(Labels[i].Y), Labels[i].Color, Ord(not Labels[i].NoBox), EscapeToken(Labels[i].Fmt),
          EscapeText(Labels[i].Text)]));
    end;
  for i := 0 to MAX_LINKS - 1 do
    if Links[i].Active and Mine(Links[i].Layer) then
      WriteLn(f, Format('LINK %s %s %d %s %d %s', [F2S(Links[i].X), F2S(Links[i].Y), Links[i].Color,
        LinkKinds[Ord(Links[i].ToPopup)], Links[i].Target + 1, EscapeText(Links[i].Caption)]));
  for i := 0 to MAX_EQUIP - 1 do
    if Equips[i].Active and Mine(Equips[i].Layer) then
    begin
      WriteLn(f, Format('EQUIP %s %s %s %s %s %s %d %d %d %s %s', [EquipTags[Equips[i].Kind], F2S(Equips[i].X),
        F2S(Equips[i].Y), F2S(Equips[i].W), F2S(Equips[i].H), EquipStates[Min(Equips[i].State, EQS_COUNT - 1)],
        Ord(Equips[i].Flip), Equips[i].LinkX, Equips[i].LinkY, F2S(Equips[i].Level), EscapeText(Equips[i].Name)]));
      if (Equips[i].Mode <> 0) or (Equips[i].SeqStep <> 0) or (Equips[i].DivA >= 0) or (Equips[i].DivB >= 0) or
        (Equips[i].Delay <> 2) then
        WriteLn(f, Format('EQX %d %d %s %d %d', [Equips[i].Mode, Equips[i].SeqStep, F2S(Equips[i].Delay),
          Equips[i].DivA, Equips[i].DivB]));
      if (Equips[i].Kind in [EQ_GAUGE, EQ_DIGITAL, EQ_CONTROLLER, EQ_HEATEX, EQ_COOLTOWER, EQ_CHILLER, EQ_TREND, EQ_TIMELINE,
        EQ_ITEMFEEDER, EQ_WORKER]) or
        ((Equips[i].Kind in [EQ_CONVEYOR, EQ_BELT]) and (Equips[i].RMin <> 0)) then
        WriteLn(f, Format('EQSRC %s %s %s', [F2S(Equips[i].RMin), F2S(Equips[i].RMax), EscapeText(Equips[i].Src)]));
      if Equips[i].Kind in [EQ_TREND, EQ_TIMELINE] then
        WriteLn(f, Format('EQPENS %s %s %s', [EscapeToken(Equips[i].Src2), EscapeToken(Equips[i].Src3),
          EscapeToken(Equips[i].Src4)]));
      if Equips[i].Kind = EQ_TIMELINE then
        for k := 0 to TL_PINS - 1 do
          if Equips[i].Pins[k].Kind in [TLP_INPUT, TLP_FIX] then
            WriteLn(f, Format('TLPIN %d %s %s %s %s %d %s %s %d %s %s %d %s %s', [k + 1, TLPinKinds[Equips[i].Pins[k].Kind],
              F2S(Equips[i].Pins[k].T), F2S(Equips[i].Pins[k].W), EscapeToken(Equips[i].Pins[k].Src),
              Equips[i].Pins[k].VMode[0], F2S(Equips[i].Pins[k].V[0]), EscapeToken(Equips[i].Pins[k].Dest[0]),
              Equips[i].Pins[k].VMode[1], F2S(Equips[i].Pins[k].V[1]), EscapeToken(Equips[i].Pins[k].Dest[1]),
              Equips[i].Pins[k].VMode[2], F2S(Equips[i].Pins[k].V[2]), EscapeToken(Equips[i].Pins[k].Dest[2])]));
    end;
  for i := 0 to MAX_FLOW - 1 do
    if FlowNodes[i].Active and Mine(FlowNodes[i].Layer) then
      with FlowNodes[i] do
        WriteLn(f, Format('FLOW %d %s %s %s %s %s %d %d %d %d %s %s %s %s', [i + 1, FlowKindTags[Kind], F2S(X), F2S(Y),
          F2S(W), F2S(H), Op, Act, Next + 1, Next2 + 1, F2S(Value), EscapeToken(Src), EscapeToken(Target),
          EscapeText(Caption)]));
  for i := 0 to MAX_FLOW - 1 do
    if FlowNodes[i].Active and (FlowNodes[i].Kind = FN_RANDOM) and Mine(FlowNodes[i].Layer) then
      WriteLn(f, Format('FLOWX %d %d %s %s', [i + 1, FlowNodes[i].RType, F2S(FlowNodes[i].Value2), F2S(FlowNodes[i].Period)]));
end;

{ the electrical cells of the live page on layer L }
procedure WriteElec(var f: TextFile; L, NL: Integer);
var
  x, y: Integer;
  c: PECell;
  lay: Integer;
begin
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @EGrid[x, y];
      if c^.Kind = ekNone then Continue;
      lay := c^.Layer;
      if lay >= NL then lay := NL - 1;
      if lay <> L then Continue;
      WriteLn(f, Format('ECELL %d %d %s %s %d %d %d %d %d %d %s %s %s %s %s %s', [x, y, EKindTags[c^.Kind], ConnStr(c^.Conn),
        c^.Dir, c^.Pos, c^.NPos, c^.Sel, Ord(c^.On), Ord(c^.Tripped), F2S(c^.P1), F2S(c^.P2), EscapeToken(c^.Tag),
        EscapeToken(c^.Ref), EscapeToken(c^.Src), F2S(c^.P3)]));
    end;
end;
{ the fluid power cells of the live page on layer L }
procedure WriteFluid(var f: TextFile; L, NL: Integer);
var
  x, y, lay: Integer;
  c: PFCell;
begin
  for y := 0 to GH - 1 do
    for x := 0 to GW - 1 do
    begin
      c := @FGrid[x, y];
      if c^.Kind = fkNone then Continue;
      lay := c^.Layer;
      if lay >= NL then lay := NL - 1;
      if lay <> L then Continue;
      WriteLn(f, Format('FCELL %d %d %s %s %d %d %d %d %s %s %s %s %s %s', [x, y, FKindTags[c^.Kind], ConnStr(c^.Conn),
        c^.Dir, c^.Act, c^.Sel, Ord(c^.On), F2S(c^.P1), F2S(c^.P2), EscapeToken(c^.Tag), EscapeToken(c^.Ref),
        EscapeToken(c^.SolA), EscapeToken(c^.SolB)]));
    end;
end;
function SaveLayout(const FileName: UnicodeString; out Err: string): Boolean;
var
  f: TextFile;
  p, L, keep: Integer;
  P2: ^TPageData;
begin
  Result := False;
  Err := '';
  keep := CurPage;
  ParkPage(CurPage);
  try
    AssignFile(f, FileName);
    Rewrite(f);
    try
      WriteLn(f, '# Material Flow Simulator layout');
      WriteLn(f, '# POPUP n page colour title / POPUPTEXT n text');
      WriteLn(f, '# PAGE name / LAYERS count active / LAYER n visible locked name / ON layer');
      WriteLn(f, '# CELL x y kind conn dia dir open strength');
      WriteLn(f, '# STOCK x y water oil fluff sand air% feed%');
      WriteLn(f, '# BUCKET x y w h');
      WriteLn(f, '# LABEL x y text   (\n = new line)');
      WriteLn(f, '# LABEL2 kind x y colour box format caption   (kind text/date/time, \s = space)');
      WriteLn(f, '# FRAME x y w h colour dashed fill carry title');
      WriteLn(f, '# LINK x y colour page|popup n caption');
      WriteLn(f, '# EQUIP kind x y w h state flip linkx linky level name');
      WriteLn(f, '# ECELL x y kind conn dir pos npos sel on tripped p1 p2 tag ref src p3');
      WriteLn(f, '# FLOW n kind x y w h op act next no value src target caption   (next / no: node n, 0 = none)');
      WriteLn(f, '# FLOWX n type low period   (a random node: 0 boolean, 1 byte, 2 integer, 3 float)');
      WriteLn(f, 'MFLOW 2');
      if LayoutName <> '' then WriteLn(f, 'NAME ', LayoutName);
      for p := 0 to MAX_POPUPS - 1 do
        if Popups[p].Active then
        begin
          WriteLn(f, Format('POPUP %d %d %d %s', [p + 1, Popups[p].GoPage + 1, Popups[p].Color,
            EscapeText(Popups[p].Title)]));
          WriteLn(f, Format('POPUPTEXT %d %s', [p + 1, EscapeText(Popups[p].Text)]));
          if Popups[p].BW > 0 then
            WriteLn(f, Format('POPUPBOX %d %s %s %s %s', [p + 1, F2S(Popups[p].BX), F2S(Popups[p].BY), F2S(Popups[p].BW),
              F2S(Popups[p].BH)]));
        end;
      for p := 0 to PageCount - 1 do
      begin
        { bring the page into the live globals, write it, park it again }
        UnparkPage(p);
        P2 := @Pages[p];
        WriteLn(f);
        WriteLn(f, 'PAGE ', EscapeText(PageName(p)));
        WriteLn(f, Format('LAYERS %d %d', [P2^.NLayers, P2^.ActiveLayer + 1]));
        for L := 0 to P2^.NLayers - 1 do
          WriteLn(f, Format('LAYER %d %d %d %s', [L + 1, Ord(P2^.Layers[L].Visible), Ord(P2^.Layers[L].Locked),
            EscapeText(P2^.Layers[L].Name)]));
        WriteLn(f, 'GRAVITY ', F2S(GravityScale));
        if LayoutBg >= 0 then WriteLn(f, 'BACKGROUND ', LayoutBg);
        for L := 0 to P2^.NLayers - 1 do
        begin
          WritePageBody(f, L, P2^.NLayers);
          WriteElec(f, L, P2^.NLayers);
          WriteFluid(f, L, P2^.NLayers);
        end;
        for L := 0 to High(Pins) do
          if (Pins[L].Page = p) and (Pins[L].Kind <= High(PinKinds)) then
            WriteLn(f, Format('PIN %s %d %d %s %s %s %s %s', [PinKinds[Pins[L].Kind], Pins[L].A, Pins[L].B, F2S(Pins[L].X),
              F2S(Pins[L].Y), F2S(Pins[L].W), F2S(Pins[L].H), F2S(fmax(1, Pins[L].Scale))]));
        ParkPage(p);
      end;
    finally
      CloseFile(f);
    end;
    Result := True;
  except
    on E: Exception do Err := E.Message;
  end;
  CurPage := keep;
  UnparkPage(CurPage);
end;
procedure Tokenize(const s: string; var Tok: array of string; out N: Integer);
var
  i, start: Integer;
begin
  N := 0;
  i := 1;
  while (i <= Length(s)) and (N <= High(Tok)) do
  begin
    while (i <= Length(s)) and (s[i] in [' ', #9]) do Inc(i);
    if i > Length(s) then Break;
    start := i;
    while (i <= Length(s)) and not (s[i] in [' ', #9]) do Inc(i);
    Tok[N] := Copy(s, start, i - start);
    Inc(N);
  end;
end;

{ the rest of s after its first n whitespace-separated words }
function AfterTokens(const s: string; n: Integer): string;
var
  i, k: Integer;
begin
  i := 1;
  for k := 1 to n do
  begin
    while (i <= Length(s)) and (s[i] in [' ', #9]) do Inc(i);
    while (i <= Length(s)) and not (s[i] in [' ', #9]) do Inc(i);
  end;
  while (i <= Length(s)) and (s[i] in [' ', #9]) do Inc(i);
  Result := Copy(s, i, MaxInt);
end;

function ParseKind(const s: string; out K: TCellKind): Boolean;
var
  k2: TCellKind;
begin
  for k2 := ckPipe to High(TCellKind) do
    if SameText(s, KindTags[k2]) then
    begin
      K := k2;
      Exit(True);
    end;
  Result := False;
end;

function ParseConn(const s: string; out C: Byte): Boolean;
var
  i, p: Integer;
begin
  C := 0;
  if s = '-' then Exit(True);
  for i := 1 to Length(s) do
  begin
    p := Pos(UpCase(s[i]), DirLetters);
    if p = 0 then Exit(False);
    C := C or (1 shl (p - 1));
  end;
  Result := True;
end;

function ParseDir(const s: string; out D: Integer): Boolean;
begin
  D := -1;
  if s = '-' then Exit(True);
  if Length(s) <> 1 then Exit(False);
  D := Pos(UpCase(s[1]), DirLetters) - 1;
  Result := D >= 0;
end;

function LoadLayout(const FileName: UnicodeString; out Err: string): Boolean;
var
  f: TextFile;
  line, name: string;
  Tok: array[0..16] of string;
  n, lineNo, x, y, i, q, ver, pageActive, oldCount, oldCur, lastEq: Integer;
  gotHeader, opened, gotPage: Boolean;
  c: PCell;
  K: TCellKind;
  conn: Byte;
  dir, k2: Integer;
  v: array[0..5] of Single;
  ek, e2: TEKind;
  fk, f2: TFKind;

  procedure Fail(const Msg: string);
  begin
    raise Exception.CreateFmt('line %d: %s', [lineNo, Msg]);
  end;

  function Num(i: Integer): Single;
  begin
    if not TryStrToFloat(Tok[i], Result, FS) then Fail('bad number "' + Tok[i] + '"');
  end;

  function Int(i: Integer): Integer;
  begin
    if not TryStrToInt(Tok[i], Result) then Fail('bad integer "' + Tok[i] + '"');
  end;

  procedure Need(Count: Integer);
  begin
    if n < Count then Fail(Format('%s needs %d values', [Tok[0], Count - 1]));
  end;

  procedure GridPos;
  begin
    x := Int(1);
    y := Int(2);
    if not InGrid(x, y) then Fail(Format('cell %d,%d is outside the %dx%d grid', [x, y, GW, GH]));
  end;

  { the page being read is complete: park it with its active layer }
  procedure EndPage;
  begin
    ParkPage(CurPage);
    Pages[CurPage].ActiveLayer := EnsureRange(pageActive, 0, Pages[CurPage].NLayers - 1);
  end;

begin
  Result := False;
  Err := '';
  { everything needed to put the old layout back if the file is bad }
  ParkPage(CurPage);
  OldPages := Pages;
  OldPopups := Popups;
  OldPins := Copy(Pins, 0, Length(Pins));
  oldCount := PageCount;
  oldCur := CurPage;
  opened := False;
  lineNo := 0;
  name := '';
  ver := 1;
  lastEq := -1;
  LayoutBg := -1;
  try
    AssignFile(f, FileName);
    Reset(f);
    opened := True;
    PagesReset;
    for i := 0 to MAX_PAGES - 1 do Pages[i].Parts := nil;
    ClearAll;
    gotHeader := False;
    gotPage := False;
    pageActive := 0;
    while not EOF(f) do
    begin
      ReadLn(f, line);
      Inc(lineNo);
      line := Trim(line);
      if (line = '') or (line[1] = '#') then Continue;
      Tokenize(line, Tok, n);
      if not gotHeader then
      begin
        if (n < 2) or not SameText(Tok[0], 'MFLOW') then Fail('not a Material Flow layout (missing MFLOW header)');
        ver := Int(1);
        if (ver < 1) or (ver > 2) then Fail('unsupported layout version ' + Tok[1]);
        gotHeader := True;
        Continue;
      end;
      if SameText(Tok[0], 'NAME') then
        name := Trim(Copy(line, 5, MaxInt))
      else if SameText(Tok[0], 'POPUP') then
      begin
        Need(4);
        i := Int(1) - 1;
        if (i < 0) or (i >= MAX_POPUPS) then Fail(Format('popup number must be 1..%d', [MAX_POPUPS]));
        Popups[i].Active := True;
        Popups[i].GoPage := Max(-1, Int(2) - 1);
        Popups[i].Color := EnsureRange(Int(3), 0, 5);
        Popups[i].Title := Copy(UnescapeText(AfterTokens(line, 4)), 1, 60);
        Popups[i].Text := '';
        Popups[i].BW := 0;
      end
      else if SameText(Tok[0], 'POPUPBOX') then
      begin
        { where a popup was moved to and its size }
        Need(6);
        i := Int(1) - 1;
        if (i < 0) or (i >= MAX_POPUPS) or not Popups[i].Active then Fail('POPUPBOX for a popup that has no POPUP line');
        Popups[i].BX := fclamp(Num(2), 0, CANVAS_W);
        Popups[i].BY := fclamp(Num(3), 0, CANVAS_H);
        Popups[i].BW := fclamp(Num(4), 0, CANVAS_W);
        Popups[i].BH := fclamp(Num(5), 0, CANVAS_H);
      end
      else if SameText(Tok[0], 'POPUPTEXT') then
      begin
        Need(2);
        i := Int(1) - 1;
        if (i < 0) or (i >= MAX_POPUPS) or not Popups[i].Active then Fail('POPUPTEXT for a popup that has no POPUP line');
        Popups[i].Text := Copy(UnescapeText(AfterTokens(line, 2)), 1, 255);
      end
      else if SameText(Tok[0], 'PAGE') then
      begin
        if gotPage then
        begin
          EndPage;
          i := AddPage('');
          if i < 0 then Fail(Format('too many pages (max %d)', [MAX_PAGES]));
          CurPage := i;
          UnparkPage(i);
        end;
        gotPage := True;
        Pages[CurPage].Name := Copy(UnescapeText(AfterTokens(line, 1)), 1, 40);
        CurLayer := 0;
        pageActive := 0;
      end
      else if SameText(Tok[0], 'LAYERS') then
      begin
        Need(3);
        Pages[CurPage].NLayers := EnsureRange(Int(1), 1, MAX_LAYERS);
        pageActive := Int(2) - 1;
      end
      else if SameText(Tok[0], 'LAYER') then
      begin
        Need(4);
        i := Int(1) - 1;
        if (i < 0) or (i >= MAX_LAYERS) then Fail(Format('layer number must be 1..%d', [MAX_LAYERS]));
        if i >= Pages[CurPage].NLayers then Pages[CurPage].NLayers := i + 1;
        Pages[CurPage].Layers[i].Visible := Int(2) <> 0;
        Pages[CurPage].Layers[i].Locked := Int(3) <> 0;
        Pages[CurPage].Layers[i].Name := Copy(UnescapeText(AfterTokens(line, 4)), 1, 24);
      end
      else if SameText(Tok[0], 'ON') then
      begin
        Need(2);
        i := Int(1) - 1;
        if (i < 0) or (i >= MAX_LAYERS) then Fail(Format('layer number must be 1..%d', [MAX_LAYERS]));
        if i >= Pages[CurPage].NLayers then Pages[CurPage].NLayers := i + 1;
        CurLayer := i;
      end
      else if SameText(Tok[0], 'BACKGROUND') then
      begin
        Need(2);
        LayoutBg := EnsureRange(Int(1), 0, BG_COUNT - 1);
      end
      else if SameText(Tok[0], 'GRAVITY') then
      begin
        Need(2);
        GravityScale := fclamp(Num(1), 0, 2);
      end
      else if SameText(Tok[0], 'CELL') then
      begin
        Need(9);
        GridPos;
        if SameText(Tok[3], 'tank') then K := ckSource
        else if not ParseKind(Tok[3], K) then Fail('unknown part "' + Tok[3] + '"');
        if not ParseConn(Tok[4], conn) then Fail('bad connections "' + Tok[4] + '"');
        if not ParseDir(Tok[6], dir) then Fail('bad direction "' + Tok[6] + '"');
        c := @Grid[x, y];
        ResetCell(x, y);
        c^.Kind := K;
        c^.Layer := CurLayer;
        c^.Conn := conn;
        c^.Dia := EnsureRange(Int(5), 1, MAX_DIA);
        if (dir < 0) and (K <> ckValve3) then dir := 0;
        c^.Dir := dir;
        c^.Open := Int(7) <> 0;
        c^.Strength := fclamp(Num(8), 0, 100);
        if (K = ckValve4) and (n >= 10) then
        begin
          if not ParseConn(Tok[9], conn) then Fail('bad shut branches "' + Tok[9] + '"');
          c^.Closed := conn;
        end;
      end
      else if SameText(Tok[0], 'FRAME') then
      begin
        Need(9);
        for i := 0 to 3 do v[i] := Num(1 + i);
        i := AddFrame(v[0], v[1], v[2], v[3], UnescapeText(AfterTokens(line, 9)));
        if i < 0 then Fail(Format('too many frames (max %d)', [MAX_FRAMES]));
        Frames[i].Color := EnsureRange(Int(5), 0, 5);
        Frames[i].Dashed := Int(6) <> 0;
        Frames[i].Fill := Int(7) <> 0;
        Frames[i].Carry := Int(8) <> 0;
      end
      else if SameText(Tok[0], 'LINK') then
      begin
        Need(6);
        for i := 0 to 1 do v[i] := Num(1 + i);
        k2 := -1;
        for i := 0 to 1 do
          if SameText(Tok[4], LinkKinds[i]) then k2 := i;
        if k2 < 0 then Fail('a LINK goes to "page" or "popup", not "' + Tok[4] + '"');
        i := AddLink(v[0], v[1], Copy(UnescapeText(AfterTokens(line, 6)), 1, 40), k2 = 1, Int(5) - 1);
        if i < 0 then Fail(Format('too many links (max %d)', [MAX_LINKS]));
        Links[i].Color := EnsureRange(Int(3), 0, 5);
      end
      else if SameText(Tok[0], 'FCELL') then
      begin
        Need(15);
        GridPos;
        fk := fkNone;
        for f2 := Succ(fkNone) to High(TFKind) do
          if SameText(Tok[3], FKindTags[f2]) then fk := f2;
        if fk = fkNone then Fail('unknown fluid power part "' + Tok[3] + '"');
        if not ParseConn(Tok[4], conn) then Fail('bad connections "' + Tok[4] + '"');
        FReset(x, y);
        FGrid[x, y].Kind := fk;
        FGrid[x, y].Conn := conn;
        FGrid[x, y].Dir := EnsureRange(Int(5), 0, 3);
        FGrid[x, y].Act := EnsureRange(Int(6), 0, 3);
        FGrid[x, y].Sel := EnsureRange(Int(7), 0, 2);
        FGrid[x, y].On := Int(8) <> 0;
        FGrid[x, y].P1 := Num(9);
        FGrid[x, y].P2 := Num(10);
        if Tok[11] <> '-' then FGrid[x, y].Tag := Copy(UnescapeText(Tok[11]), 1, 12);
        if Tok[12] <> '-' then FGrid[x, y].Ref := Copy(UnescapeText(Tok[12]), 1, 24);
        if Tok[13] <> '-' then FGrid[x, y].SolA := Copy(UnescapeText(Tok[13]), 1, 12);
        if Tok[14] <> '-' then FGrid[x, y].SolB := Copy(UnescapeText(Tok[14]), 1, 12);
        FGrid[x, y].Layer := CurLayer;
      end
      else if SameText(Tok[0], 'FLOW') then
      begin
        Need(14);
        i := Int(1) - 1;
        if (i < 0) or (i >= MAX_FLOW) then Fail(Format('a flow chart node is 1..%d', [MAX_FLOW]));
        k2 := -1;
        for q := 0 to FN_KINDS - 1 do
          if SameText(Tok[2], FlowKindTags[q]) then k2 := q;
        if k2 < 0 then Fail('unknown flow chart node "' + Tok[2] + '"');
        FillChar(FlowNodes[i], SizeOf(TFlowNode), 0);
        with FlowNodes[i] do
        begin
          Active := True;
          Kind := k2;
          X := Num(3);
          Y := Num(4);
          W := fclamp(Num(5), 24, 600);
          H := fclamp(Num(6), 16, 400);
          Op := EnsureRange(Int(7), 0, FLOW_OPS - 1);
          Act := EnsureRange(Int(8), 0, FLOW_ACTS - 1);
          Next := EnsureRange(Int(9), 0, MAX_FLOW) - 1;
          Next2 := EnsureRange(Int(10), 0, MAX_FLOW) - 1;
          Value := Num(11);
          if Tok[12] <> '-' then Src := Copy(UnescapeText(Tok[12]), 1, 24);
          if Tok[13] <> '-' then Target := Copy(UnescapeText(Tok[13]), 1, 24);
          Caption := Copy(UnescapeText(AfterTokens(line, 14)), 1, 40);
          Layer := CurLayer;
        end;
      end
      else if SameText(Tok[0], 'FLOWX') then
      begin
        Need(5);
        i := Int(1) - 1;
        if (i < 0) or (i >= MAX_FLOW) or not FlowNodes[i].Active then Fail('FLOWX without its FLOW line');
        FlowNodes[i].RType := EnsureRange(Int(2), 0, 3);
        FlowNodes[i].Value2 := Num(3);
        FlowNodes[i].Period := fclamp(Num(4), 0, 3600);
      end
      else if SameText(Tok[0], 'PIN') then
      begin
        Need(8);
        q := -1;
        for i := 1 to High(PinKinds) do
          if SameText(Tok[1], PinKinds[i]) then q := i;
        if q < 0 then Fail('unknown Focus Properties item "' + Tok[1] + '"');
        SetLength(Pins, Length(Pins) + 1);
        with Pins[High(Pins)] do
        begin
          Kind := q;
          A := Int(2);
          B := Int(3);
          X := Num(4);
          Y := Num(5);
          W := fclamp(Num(6), 120, 1000);
          H := fclamp(Num(7), 60, 2400);
          if n >= 9 then Scale := fclamp(Num(8), 0.8, 3) else Scale := 1;
          Page := CurPage;
          Dragging := False;
        end;
      end
      else if SameText(Tok[0], 'ECELL') then
      begin
        Need(15);
        GridPos;
        ek := ekNone;
        for e2 := Succ(ekNone) to High(TEKind) do
          if SameText(Tok[3], EKindTags[e2]) then ek := e2;
        if ek = ekNone then Fail('unknown electrical part "' + Tok[3] + '"');
        if not ParseConn(Tok[4], conn) then Fail('bad connections "' + Tok[4] + '"');
        EReset(x, y);
        EGrid[x, y].Kind := ek;
        EGrid[x, y].Conn := conn;
        EGrid[x, y].Dir := EnsureRange(Int(5), 0, 3);
        EGrid[x, y].Pos := EnsureRange(Int(6), 0, 9);
        EGrid[x, y].NPos := EnsureRange(Int(7), 0, 9);
        EGrid[x, y].Sel := EnsureRange(Int(8), 0, 9);
        EGrid[x, y].On := Int(9) <> 0;
        EGrid[x, y].Tripped := Int(10) <> 0;
        EGrid[x, y].P1 := Num(11);
        EGrid[x, y].P2 := Num(12);
        if Tok[13] <> '-' then EGrid[x, y].Tag := Copy(UnescapeText(Tok[13]), 1, 12);
        if Tok[14] <> '-' then EGrid[x, y].Ref := Copy(UnescapeText(Tok[14]), 1, 24);
        if (n >= 16) and (Tok[15] <> '-') then EGrid[x, y].Src := Copy(UnescapeText(Tok[15]), 1, 12);
        if n >= 17 then EGrid[x, y].P3 := Num(16);
        EGrid[x, y].Layer := CurLayer;
      end
      else if SameText(Tok[0], 'TLPIN') then
      begin
        { a timeline's pin: slot, in / fix, time, "at" s, what it reads, then mode value target before / at / after }
        Need(15);
        if lastEq < 0 then Fail('TLPIN without an EQUIP line before it');
        q := Int(1) - 1;
        if (q < 0) or (q >= TL_PINS) then Fail(Format('a timeline pin is 1..%d', [TL_PINS]));
        FillChar(Equips[lastEq].Pins[q], SizeOf(TTLPin), 0);
        if SameText(Tok[2], 'in') then Equips[lastEq].Pins[q].Kind := TLP_INPUT
        else if SameText(Tok[2], 'fix') then Equips[lastEq].Pins[q].Kind := TLP_FIX
        else Fail('a timeline pin is "in" or "fix", not "' + Tok[2] + '"');
        Equips[lastEq].Pins[q].T := fclamp(Num(3), 0, 3600);
        Equips[lastEq].Pins[q].W := fclamp(Num(4), 0.05, 3600);
        if Tok[5] <> '-' then Equips[lastEq].Pins[q].Src := Copy(UnescapeText(Tok[5]), 1, 24);
        for k2 := 0 to 2 do
        begin
          Equips[lastEq].Pins[q].VMode[k2] := EnsureRange(Int(6 + k2 * 3), 0, 3);
          Equips[lastEq].Pins[q].V[k2] := Num(7 + k2 * 3);
          if Tok[8 + k2 * 3] <> '-' then Equips[lastEq].Pins[q].Dest[k2] := Copy(UnescapeText(Tok[8 + k2 * 3]), 1, 24);
        end;
      end
      else if SameText(Tok[0], 'EQPENS') then
      begin
        Need(4);
        if lastEq < 0 then Fail('EQPENS without an EQUIP line before it');
        if Tok[1] <> '-' then Equips[lastEq].Src2 := Copy(UnescapeText(Tok[1]), 1, 24);
        if Tok[2] <> '-' then Equips[lastEq].Src3 := Copy(UnescapeText(Tok[2]), 1, 24);
        if Tok[3] <> '-' then Equips[lastEq].Src4 := Copy(UnescapeText(Tok[3]), 1, 24);
      end
      else if SameText(Tok[0], 'EQSRC') then
      begin
        Need(3);
        if lastEq < 0 then Fail('EQSRC without an EQUIP line before it');
        Equips[lastEq].RMin := Num(1);
        Equips[lastEq].RMax := Num(2);
        Equips[lastEq].Src := Copy(UnescapeText(AfterTokens(line, 3)), 1, 24);
      end
      else if SameText(Tok[0], 'EQX') then
      begin
        { the sequence settings of the EQUIP line before it }
        Need(6);
        if lastEq < 0 then Fail('EQX without an EQUIP line before it');
        Equips[lastEq].Mode := EnsureRange(Int(1), 0, 4);
        Equips[lastEq].SeqStep := EnsureRange(Int(2), 0, MAX_SEQ_STEP);
        Equips[lastEq].Delay := fclamp(Num(3), 0, 3600);
        Equips[lastEq].DivA := EnsureRange(Int(4), -1, 3);
        Equips[lastEq].DivB := EnsureRange(Int(5), -1, 3);
      end
      else if SameText(Tok[0], 'EQUIP') then
      begin
        Need(11);
        k2 := -1;
        for i := 0 to EQ_KINDS - 1 do
          if SameText(Tok[1], EquipTags[i]) then k2 := i;
        if k2 < 0 then Fail('unknown equipment "' + Tok[1] + '"');
        for i := 0 to 3 do v[i] := Num(2 + i);
        i := AddEquip(k2, v[0], v[1]);
        if i < 0 then Fail(Format('too many equipment items (max %d)', [MAX_EQUIP]));
        Equips[i].W := fclamp(v[2], 8, CANVAS_W);
        Equips[i].H := fclamp(v[3], 8, CANVAS_H);
        Equips[i].X := v[0];
        Equips[i].Y := v[1];
        Equips[i].State := EQS_STOP;
        for q := 0 to EQS_COUNT - 1 do
          if SameText(Tok[6], EquipStates[q]) then Equips[i].State := q;
        if (Equips[i].Kind = EQ_FIRE) and (Equips[i].State = EQS_RUN) then Equips[i].Heat := Equips[i].Level;
        lastEq := i;
        Equips[i].Flip := Int(7) <> 0;
        Equips[i].LinkX := EnsureRange(Int(8), -1, GW - 1);
        Equips[i].LinkY := EnsureRange(Int(9), -1, GH - 1);
        Equips[i].Level := fclamp(Num(10), 0, 100);
        Equips[i].Name := Copy(UnescapeText(AfterTokens(line, 11)), 1, 24);
      end
      else if SameText(Tok[0], 'LABEL2') then
      begin
        Need(7);
        k2 := -1;
        for i := 0 to 2 do
          if SameText(Tok[1], LabelKinds[i]) then k2 := i;
        if k2 < 0 then Fail('unknown label kind "' + Tok[1] + '"');
        for i := 0 to 1 do v[i] := Num(2 + i);
        i := AddLabel(v[0], v[1], UnescapeText(AfterTokens(line, 7)));
        if i < 0 then Fail(Format('too many labels (max %d)', [MAX_LABELS]));
        Labels[i].Kind := k2;
        Labels[i].Color := EnsureRange(Int(4), 0, 5);
        Labels[i].NoBox := Int(5) = 0;
        if Tok[6] = '-' then Labels[i].Fmt := '' else Labels[i].Fmt := Copy(UnescapeText(Tok[6]), 1, 40);
      end
      else if SameText(Tok[0], 'LABEL') then
      begin
        Need(3);
        for i := 0 to 1 do v[i] := Num(1 + i);
        { the text is everything after "LABEL x y" }
        if AddLabel(v[0], v[1], UnescapeText(AfterTokens(line, 3))) < 0 then
          Fail(Format('too many labels (max %d)', [MAX_LABELS]));
      end
      else if SameText(Tok[0], 'TANK') or SameText(Tok[0], 'STOCK') then
      begin
        Need(9);
        GridPos;
        c := @Grid[x, y];
        if not IsStore(c^.Kind) then Fail(Format('%s at %d,%d has no feeder, hopper or silo CELL before it', [Tok[0], x, y]));
        for i := 0 to 5 do v[i] := Num(3 + i);
        c^.Stock[mWater] := fclamp(v[0], 0, STOCK_MAX);
        c^.Stock[mOil] := fclamp(v[1], 0, STOCK_MAX);
        c^.Stock[mFluff] := fclamp(v[2], 0, STOCK_MAX);
        c^.Stock[mSand] := fclamp(v[3], 0, STOCK_MAX);
        c^.AirPct := fclamp(v[4], 0, 95);
        c^.Feed := fclamp(v[5], 0, 100);
      end
      else if SameText(Tok[0], 'BUCKET') then
      begin
        Need(5);
        for i := 0 to 3 do v[i] := Num(1 + i);
        if AddBucket(v[0] + fclamp(v[2], 40, 400) / 2, v[1], fclamp(v[2], 40, 400), fclamp(v[3], 30, 300)) < 0 then
          Fail(Format('too many buckets (max %d)', [MAX_BUCKETS]));
      end
      else
        Fail('unknown keyword "' + Tok[0] + '"');
    end;
    if not gotHeader then Fail('file is empty');
    CloseFile(f);
    opened := False;
    EndPage;
    { links and popups that point past the last page lose their target }
    for i := 0 to MAX_POPUPS - 1 do
      if Popups[i].GoPage >= PageCount then Popups[i].GoPage := -1;
    CurPage := 0;
    UnparkPage(0);
    if name = '' then name := ChangeFileExt(ExtractFileName(UTF8Encode(FileName)), '');
    LayoutName := name;
    Result := True;
  except
    on E: Exception do
    begin
      if opened then CloseFile(f);
      { keep the previous layout when the file can't be read }
      Pages := OldPages;
      Popups := OldPopups;
      Pins := Copy(OldPins, 0, Length(OldPins));
      PageCount := oldCount;
      CurPage := oldCur;
      ShownPopup := -1;
      UnparkPage(CurPage);
      Err := E.Message;
    end;
  end;
  for i := 0 to MAX_PAGES - 1 do OldPages[i].Parts := nil;
end;
initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

end.
