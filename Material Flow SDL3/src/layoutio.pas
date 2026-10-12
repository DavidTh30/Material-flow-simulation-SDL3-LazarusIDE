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
  BUCKET <x> <y> <w> <h>
  LABEL <x> <y> <text>            (\n = new line in the text)
  FRAME <x> <y> <w> <h> <colour> <dashed> <fill> <carry> <title>
  LABEL2 <kind> <x> <y> <colour> <box> <format> <caption>
                                  (kind text/date/time; format: FormatDateTime
                                   codes, \s = space, - = none; box 1/0)

  kind: pipe feeder blower suction nozzle drop check valve2 valve3 valve4 hopper silo
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
  SysUtils, Math, simcore, mfpages;

const
  LabelKinds: array[0..2] of string = ('text', 'date', 'time');
  KindTags: array[TCellKind] of string = ('empty', 'pipe', 'feeder', 'blower', 'suction',
    'nozzle', 'drop', 'check', 'valve2', 'valve3', 'valve4', 'hopper', 'silo');
  DirLetters = 'ESWN';
  LinkKinds: array[0..1] of string = ('page', 'popup');

var
  FS: TFormatSettings;
  OldPages: array[0..MAX_PAGES - 1] of TPageData;
  OldPopups: array[0..MAX_POPUPS - 1] of TPopup;

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
procedure WritePageBody(var f: TextFile; L, NL: Integer);

  function Mine(v: Byte): Boolean;
  begin
    if v >= NL then Result := L = NL - 1 else Result := v = L;
  end;

var
  x, y, i: Integer;
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
      WriteLn(f, 'MFLOW 2');
      if LayoutName <> '' then WriteLn(f, 'NAME ', LayoutName);
      for p := 0 to MAX_POPUPS - 1 do
        if Popups[p].Active then
        begin
          WriteLn(f, Format('POPUP %d %d %d %s', [p + 1, Popups[p].GoPage + 1, Popups[p].Color,
            EscapeText(Popups[p].Title)]));
          WriteLn(f, Format('POPUPTEXT %d %s', [p + 1, EscapeText(Popups[p].Text)]));
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
        for L := 0 to P2^.NLayers - 1 do
          WritePageBody(f, L, P2^.NLayers);
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
  Tok: array[0..15] of string;
  n, lineNo, x, y, i, ver, pageActive, oldCount, oldCur: Integer;
  gotHeader, opened, gotPage: Boolean;
  c: PCell;
  K: TCellKind;
  conn: Byte;
  dir, k2: Integer;
  v: array[0..5] of Single;

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
  oldCount := PageCount;
  oldCur := CurPage;
  opened := False;
  lineNo := 0;
  name := '';
  ver := 1;
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
