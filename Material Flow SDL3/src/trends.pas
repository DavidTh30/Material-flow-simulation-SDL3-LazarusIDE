unit trends;

{ Trend charts: what a Trend chart piece of equipment records. Up to four pens
  per chart, each a value by name (a sensor, a meter, a level, a controller,
  a random value ...) or a tag (a coil, a timer, a switch: an event that is ON
  or OFF). Every page is recorded while it runs, whichever page is on screen.
  A chart keeps TREND_N samples over its time window (Delay seconds), and the
  last TREND_EVENTS times a tag pen went ON or OFF. The records are not saved;
  changing a chart's pens starts it afresh. }

{$mode objfpc}{$H+}

interface

uses
  simcore, plantbus;

const
  TREND_N = 240;
  TREND_PENS = 4;
  TREND_EVENTS = 16;
  TS_FULL = 0;
  TS_MINI = 1;
  TS_CURVE = 2;
  TrendStyleNames: array[0..2] of string = ('Full', 'Mini', 'Curve');

type
  TPenHist = record
    V: array[0..TREND_N - 1] of Single;
    Head, Count: Integer;    { a ring: Head is where the next sample goes }
    IsBool, Known: Boolean;  { an ON / OFF tag; the name exists }
    UnitS: string[8];
    Now: Single;             { its value now }
  end;

  TTrendEvent = record
    T: Single;               { seconds since the chart started }
    Pen: Byte;
    IsOn: Boolean;
  end;

  TTrendHist = record
    Sig: string[120];        { which pens it records (a change starts it afresh) }
    Pens: array[0..TREND_PENS - 1] of TPenHist;
    Acc, Time: Single;
    Events: array[0..TREND_EVENTS - 1] of TTrendEvent;
    NEv: Integer;            { events so far (the last TREND_EVENTS are kept) }
  end;
  PTrendHist = ^TTrendHist;

var
  TrendHist: array[0..BUS_PAGES - 1, 0..MAX_EQUIP - 1] of TTrendHist;

procedure TrendsClear;
procedure TrendClear(Page, i: Integer);
{ the name of pen k of equipment i }
function TrendPen(const E: TEquipObj; k: Integer): string;
{ sample k back from the newest (0 = the newest) of a pen }
function PenSample(const P: TPenHist; k: Integer): Single;
{ event k back from the latest (0 = the latest) }
function TrendEvent(const H: TTrendHist; k: Integer; out Ev: TTrendEvent): Boolean;
procedure SampleTrends(dt: Single; Running: Boolean);

implementation

uses
  SysUtils, Math, elec;

procedure TrendClear(Page, i: Integer);
begin
  if (Page < 0) or (Page >= BUS_PAGES) or (i < 0) or (i >= MAX_EQUIP) then Exit;
  FillChar(TrendHist[Page, i], SizeOf(TTrendHist), 0);
end;

procedure TrendsClear;
begin
  FillChar(TrendHist, SizeOf(TrendHist), 0);
end;

function TrendPen(const E: TEquipObj; k: Integer): string;
begin
  case k of
    0: Result := E.Src;
    1: Result := E.Src2;
    2: Result := E.Src3;
  else
    Result := E.Src4;
  end;
end;

function PenSample(const P: TPenHist; k: Integer): Single;
begin
  if (k < 0) or (k >= P.Count) then Exit(0);
  Result := P.V[(P.Head - 1 - k + 2 * TREND_N) mod TREND_N];
end;

function TrendEvent(const H: TTrendHist; k: Integer; out Ev: TTrendEvent): Boolean;
begin
  FillChar(Ev, SizeOf(Ev), 0);
  Result := (k >= 0) and (k < Min(H.NEv, TREND_EVENTS));
  if Result then Ev := H.Events[(H.NEv - 1 - k + 2 * TREND_EVENTS) mod TREND_EVENTS];
end;

{ what a pen reads now: a value (and its unit), or a tag as 0 / 1 }
procedure ReadPen(const Name: string; var P: TPenHist);
var
  v: Single;
  u: string;
begin
  if Name = '' then
  begin
    P.Known := False;
    Exit;
  end;
  if AnalogValue(Name, v, u) then
  begin
    P.IsBool := False;
    P.Known := True;
    P.Now := v;
    P.UnitS := Copy(u, 1, 8);
  end
  else
  begin
    { a tag seen once stays known: one on another page is only on the bus while it is on }
    P.Known := ESignal(Name) or ETagKnown(Name) or (P.IsBool and P.Known);
    P.IsBool := True;
    P.Now := Ord(ESignal(Name));
    P.UnitS := '';
  end;
end;

procedure SampleTrends(dt: Single; Running: Boolean);
var
  i, k, page: Integer;
  H: PTrendHist;
  sig, nm: string;
  period, was: Single;
begin
  page := BusPage;
  if (page < 0) or (page >= BUS_PAGES) then Exit;
  for i := 0 to MAX_EQUIP - 1 do
  begin
    if not (Equips[i].Active and (Equips[i].Kind = EQ_TREND)) then Continue;
    H := @TrendHist[page, i];
    sig := Equips[i].Name + '|' + Equips[i].Src + '|' + Equips[i].Src2 + '|' + Equips[i].Src3 + '|' + Equips[i].Src4;
    if sig <> H^.Sig then
    begin
      TrendClear(page, i);
      H^.Sig := sig;
    end;
    { the pens now; a tag that changes is an event }
    for k := 0 to TREND_PENS - 1 do
    begin
      nm := TrendPen(Equips[i], k);
      was := H^.Pens[k].Now;
      ReadPen(nm, H^.Pens[k]);
      if H^.Pens[k].Known and H^.Pens[k].IsBool and (H^.Pens[k].Count > 0) and (H^.Pens[k].Now <> was) and Running then
      begin
        with H^.Events[H^.NEv mod TREND_EVENTS] do
        begin
          T := H^.Time;
          Pen := k;
          IsOn := H^.Pens[k].Now > 0.5;
        end;
        Inc(H^.NEv);
      end;
    end;
    if not Running then Continue;
    H^.Time := H^.Time + dt;
    H^.Acc := H^.Acc + dt;
    period := fmax(0.02, fmax(1, Equips[i].Delay) / TREND_N);
    while H^.Acc >= period do
    begin
      H^.Acc := H^.Acc - period;
      for k := 0 to TREND_PENS - 1 do
        with H^.Pens[k] do
          if Known then
          begin
            V[Head] := Now;
            Head := (Head + 1) mod TREND_N;
            if Count < TREND_N then Inc(Count);
          end;
    end;
  end;
end;

procedure TrendHookProc(dt: Single; Running: Boolean);
begin
  SampleTrends(dt, Running);
end;

initialization
  TrendsClear;
  TrendHook := @TrendHookProc;

end.
