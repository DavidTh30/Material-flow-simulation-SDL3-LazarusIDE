unit plantbus;

{ The plant bus: what the pages tell each other. Every page is simulated
  every frame (the page on screen last); after its frame a page publishes
  - the tags that are on (coils, timers, counters, controllers, limit and
    pressure switches),
  - its analog values by name (sensors, controllers, meters, pressures,
    equipment levels),
  - its equipment (state, level, speed, temperature),
  - the run / stop commands its motors and drives give to equipment that is
    on another page.
  A page reads what the other pages published: a contact on page 1 follows a
  coil on page 2, a motor on page 1 runs a pump on page 2, a gauge on page 3
  shows a level on page 2. What a page publishes is read by the pages after
  it in the same frame and by the pages before it in the next one. }

{$mode objfpc}{$H+}

interface

const
  BUS_PAGES = 20;

type
  TBusSig = record
    Name: string[24];
    Value: Single;
    UnitS: string[8];
  end;

  TBusEq = record
    Name: string[24];
    Kind, State: Byte;
    Level: Single;         { the level of a pond / pool / well / silo, -1 if it has none }
    Speed: Single;         { 0..100 % while running }
    Temp: Single;          { C }
  end;

  TBusCmd = record
    Name: string[24];
    IsOn: Boolean;
    Speed: Single;         { a drive's speed, -1 for a motor }
  end;

  TBusPage = record
    Valid: Boolean;
    Tags: array of string;
    NTags: Integer;
    Sigs: array of TBusSig;
    NSigs: Integer;
    Eqs: array of TBusEq;
    NEqs: Integer;
    Cmds: array of TBusCmd;
    NCmds: Integer;
  end;

var
  BusPages: array[0..BUS_PAGES - 1] of TBusPage;
  BusPage: Integer = 0;     { the page being simulated now }

procedure BusClear;
{ forget what page p published (it is about to publish again) }
procedure BusBegin(p: Integer);
procedure BusClearCmds(p: Integer);
procedure BusAddTag(const Tag: string);
procedure BusAddSig(const Name: string; Value: Single; const UnitS: string);
procedure BusAddEq(const E: TBusEq);
procedure BusAddCmd(const Name: string; IsOn: Boolean; Speed: Single);
{ what the other pages published }
function BusTagActive(const Tag: string): Boolean;
function BusSignal(const Name: string; out Value: Single; out UnitS: string): Boolean;
function BusEquip(const Name: string; out E: TBusEq): Boolean;
function BusCommand(const Name: string; out C: TBusCmd): Boolean;
{ the i-th analog name / equipment published by another page, '' after the last }
function BusSigName(i: Integer): string;
function BusEqIndex(i: Integer; out E: TBusEq): Boolean;

implementation

uses
  SysUtils;

procedure BusClear;
var
  p: Integer;
begin
  for p := 0 to BUS_PAGES - 1 do
  begin
    BusPages[p].Valid := False;
    BusPages[p].NTags := 0;
    BusPages[p].NSigs := 0;
    BusPages[p].NEqs := 0;
    BusPages[p].NCmds := 0;
  end;
end;

procedure BusBegin(p: Integer);
begin
  if (p < 0) or (p >= BUS_PAGES) then Exit;
  BusPages[p].Valid := True;
  BusPages[p].NTags := 0;
  BusPages[p].NSigs := 0;
  BusPages[p].NEqs := 0;
end;

procedure BusClearCmds(p: Integer);
begin
  if (p >= 0) and (p < BUS_PAGES) then BusPages[p].NCmds := 0;
end;

procedure BusAddTag(const Tag: string);
begin
  if (BusPage < 0) or (BusPage >= BUS_PAGES) or (Tag = '') then Exit;
  with BusPages[BusPage] do
  begin
    if NTags >= Length(Tags) then SetLength(Tags, NTags + 32);
    Tags[NTags] := Tag;
    Inc(NTags);
  end;
end;

procedure BusAddSig(const Name: string; Value: Single; const UnitS: string);
begin
  if (BusPage < 0) or (BusPage >= BUS_PAGES) or (Name = '') then Exit;
  with BusPages[BusPage] do
  begin
    if NSigs >= Length(Sigs) then SetLength(Sigs, NSigs + 32);
    Sigs[NSigs].Name := Name;
    Sigs[NSigs].Value := Value;
    Sigs[NSigs].UnitS := UnitS;
    Inc(NSigs);
  end;
end;

procedure BusAddEq(const E: TBusEq);
begin
  if (BusPage < 0) or (BusPage >= BUS_PAGES) or (E.Name = '') then Exit;
  with BusPages[BusPage] do
  begin
    if NEqs >= Length(Eqs) then SetLength(Eqs, NEqs + 16);
    Eqs[NEqs] := E;
    Inc(NEqs);
  end;
end;

procedure BusAddCmd(const Name: string; IsOn: Boolean; Speed: Single);
var
  k: Integer;
begin
  if (BusPage < 0) or (BusPage >= BUS_PAGES) or (Name = '') then Exit;
  with BusPages[BusPage] do
  begin
    { two motors on one piece: it runs when either runs }
    for k := 0 to NCmds - 1 do
      if SameText(Cmds[k].Name, Name) then
      begin
        if IsOn and not Cmds[k].IsOn then
        begin
          Cmds[k].IsOn := True;
          Cmds[k].Speed := Speed;
        end;
        Exit;
      end;
    if NCmds >= Length(Cmds) then SetLength(Cmds, NCmds + 16);
    Cmds[NCmds].Name := Name;
    Cmds[NCmds].IsOn := IsOn;
    Cmds[NCmds].Speed := Speed;
    Inc(NCmds);
  end;
end;

function BusTagActive(const Tag: string): Boolean;
var
  p, k: Integer;
begin
  Result := False;
  if Tag = '' then Exit;
  for p := 0 to BUS_PAGES - 1 do
    if (p <> BusPage) and BusPages[p].Valid then
      for k := 0 to BusPages[p].NTags - 1 do
        if SameText(BusPages[p].Tags[k], Tag) then Exit(True);
end;

function BusSignal(const Name: string; out Value: Single; out UnitS: string): Boolean;
var
  p, k: Integer;
begin
  Result := False;
  Value := 0;
  UnitS := '';
  if Name = '' then Exit;
  for p := 0 to BUS_PAGES - 1 do
    if (p <> BusPage) and BusPages[p].Valid then
      for k := 0 to BusPages[p].NSigs - 1 do
        if SameText(BusPages[p].Sigs[k].Name, Name) then
        begin
          Value := BusPages[p].Sigs[k].Value;
          UnitS := BusPages[p].Sigs[k].UnitS;
          Exit(True);
        end;
end;

function BusEquip(const Name: string; out E: TBusEq): Boolean;
var
  p, k: Integer;
begin
  Result := False;
  FillChar(E, SizeOf(E), 0);
  if Name = '' then Exit;
  for p := 0 to BUS_PAGES - 1 do
    if (p <> BusPage) and BusPages[p].Valid then
      for k := 0 to BusPages[p].NEqs - 1 do
        if SameText(BusPages[p].Eqs[k].Name, Name) then
        begin
          E := BusPages[p].Eqs[k];
          Exit(True);
        end;
end;

function BusCommand(const Name: string; out C: TBusCmd): Boolean;
var
  p, k: Integer;
begin
  Result := False;
  FillChar(C, SizeOf(C), 0);
  if Name = '' then Exit;
  for p := 0 to BUS_PAGES - 1 do
    if (p <> BusPage) and BusPages[p].Valid then
      for k := 0 to BusPages[p].NCmds - 1 do
        if SameText(BusPages[p].Cmds[k].Name, Name) then
        begin
          if Result and C.IsOn then Continue;   { one that runs it wins }
          C := BusPages[p].Cmds[k];
          Result := True;
        end;
end;

function BusSigName(i: Integer): string;
var
  p: Integer;
begin
  Result := '';
  if i < 0 then Exit;
  for p := 0 to BUS_PAGES - 1 do
    if (p <> BusPage) and BusPages[p].Valid then
    begin
      if i < BusPages[p].NSigs then Exit(BusPages[p].Sigs[i].Name);
      Dec(i, BusPages[p].NSigs);
    end;
end;

function BusEqIndex(i: Integer; out E: TBusEq): Boolean;
var
  p: Integer;
begin
  Result := False;
  FillChar(E, SizeOf(E), 0);
  if i < 0 then Exit;
  for p := 0 to BUS_PAGES - 1 do
    if (p <> BusPage) and BusPages[p].Valid then
    begin
      if i < BusPages[p].NEqs then
      begin
        E := BusPages[p].Eqs[i];
        Exit(True);
      end;
      Dec(i, BusPages[p].NEqs);
    end;
end;

initialization
  BusClear;

end.
