unit mfexamples;

{ Six built-in example layouts (also shipped as examples\*.mflow).

  Every example is built on the same principle:

    Page 1 "Plant"  the working process
                    layer 1 "Process": pipes, feeders, devices, buckets
                    layer 2 "Notes":   labels, frames and the link buttons
    Page 2 "About"  what the example shows and how the layout is built,
                    with links back to the plant

    Frame popup 1 "How it works"  (its button goes to the About page)
    Frame popup 2 "Try this"      things to change and watch

  The links on both pages jump between the pages and open the popups. }

{$mode objfpc}{$H+}

interface

const
  EXAMPLE_COUNT = 6;
  ExampleTitles: array[1..EXAMPLE_COUNT] of string = (
    'Gravity merge/overflow',
    'Pneumatic conveyor',
    'Vacuum & push nozzle',
    '4-way valve switchyard',
    'Hopper feed',
    'Silo storage');
  ExampleFiles: array[1..EXAMPLE_COUNT] of string = (
    'example1_gravity_merge.mflow',
    'example2_pneumatic_conveyor.mflow',
    'example3_vacuum_nozzle.mflow',
    'example4_4way_switchyard.mflow',
    'example5_hopper_feed.mflow',
    'example6_silo_storage.mflow');

procedure BuildExample(n: Integer);

implementation

uses
  simcore, mfpages;

const
  LAYER_PROCESS = 0;
  LAYER_NOTES = 1;
  POPUP_HOW = 0;
  POPUP_TRY = 1;
  PAGE_PLANT = 0;
  PAGE_ABOUT = 1;

  { "How it works" popup text, per example (lines up to 46 characters) }
  HowText: array[1..EXAMPLE_COUNT] of string = (
    'Feeder 1 drops water by gravity through a'#10 +
    'one-way pipe and a 2-way valve.'#10 +
    'Feeder 2 holds oil and fluff; a blower pushes'#10 +
    'them through a narrow section into the tee.'#10 +
    'Both streams leave by the drop outlet into a'#10 +
    'small bucket, which overflows into the tray.',
    'A strong blower picks sand and some fluff up'#10 +
    'from the feeder, through an expansion and up'#10 +
    'the tall riser.'#10 +
    'The 3-way valve at the top splits the flow'#10 +
    'into two long lines with drop outlets.',
    'Water and fluff drop into the left bucket.'#10 +
    'The suction head drains that bucket through a'#10 +
    'one-way pipe; the push-out nozzle shoots the'#10 +
    'mix across into the far bucket.',
    'A blower drives water and oil into a 4-way'#10 +
    'valve on a cross. East, south and north each'#10 +
    'lead to a bucket of their own.'#10 +
    'Open and shut the branches to route the flow.'#10 +
    'North starts shut.',
    'Sand drops from its feeder into a hopper; a'#10 +
    'blower carries what the hopper lets out across'#10 +
    'to a bucket.'#10 +
    'The second hopper only catches water and lets'#10 +
    'it drain straight down by gravity.',
    'A blower lifts sand and fluff up the riser and'#10 +
    'drops it through the roof of silo 1. Its gate'#10 +
    '(30%) lets the store out slowly.'#10 +
    'Silo 2 is filled through a pipe in its side;'#10 +
    'its gate is shut, so it only stores.');

  { "Try this" popup text }
  TryText: array[1..EXAMPLE_COUNT] of string = (
    'Select the 2-way valve and shut it.'#10 +
    'Mouse wheel on the blower: change its strength.'#10 +
    'Widen the narrow section (Pipe size tool).'#10 +
    'Hide the Notes layer (F6) to see the process.',
    'Select the 3-way valve and press R to send all'#10 +
    'the sand one way.'#10 +
    'Turn the blower down until the sand falls back.'#10 +
    'Add water to the feeder and compare.',
    'Turn the suction head down: the left bucket'#10 +
    'overflows.'#10 +
    'Turn the nozzle up: it shoots further.'#10 +
    'Remove the one-way pipe and watch the flow.',
    'Select the valve: its E S W N buttons open and'#10 +
    'shut each branch, R steps through the cases.'#10 +
    'Open north as well and see the flow split.',
    'Turn the blower off: the hopper fills up and'#10 +
    'spills over its rim.'#10 +
    'Change the hopper gate in Properties.',
    'Open the gate of silo 2 to empty it.'#10 +
    'Shut the gate of silo 1 and watch it fill.'#10 +
    'Lock the Process layer (F6): the parts cannot'#10 +
    'be changed, but they still work.');

  { the About page: what the example is for }
  AboutText: array[1..EXAMPLE_COUNT] of string = (
    'EXAMPLE 1 - GRAVITY MERGE / OVERFLOW'#10 +
    'Two feeders merge at a tee: water by gravity,'#10 +
    'oil + fluff blown in through a constriction.'#10 +
    'A small bucket overflows into a wide tray.',
    'EXAMPLE 2 - PNEUMATIC CONVEYOR'#10 +
    'A blower conveys sand up a riser to a 3-way'#10 +
    'diverter that splits it between two lines.',
    'EXAMPLE 3 - VACUUM & PUSH NOZZLE'#10 +
    'A suction head empties a bucket; a push-out'#10 +
    'nozzle shoots the material into another one.',
    'EXAMPLE 4 - 4-WAY VALVE SWITCHYARD'#10 +
    'One 4-way valve routes a blown flow to any of'#10 +
    'three buckets.',
    'EXAMPLE 5 - HOPPER FEED'#10 +
    'A hopper takes material from a feeder and'#10 +
    'passes it on: blown, or by gravity alone.',
    'EXAMPLE 6 - SILO STORAGE'#10 +
    'Silos store material: one filled from the roof'#10 +
    'and let out slowly, one filled through a pipe.');

procedure Feeder(x, y: Integer; Water, Oil, Fluff, Sand, Air, Feed: Single);
begin
  MakePipe(x, y, 4);
  SetKind(x, y, ckSource);
  Grid[x, y].Stock[mWater] := Water;
  Grid[x, y].Stock[mOil] := Oil;
  Grid[x, y].Stock[mFluff] := Fluff;
  Grid[x, y].Stock[mSand] := Sand;
  Grid[x, y].AirPct := Air;
  Grid[x, y].Feed := Feed;
end;

procedure Device(x, y: Integer; K: TCellKind; Strength: Single = -1; Dir: Integer = -2);
begin
  SetKind(x, y, K);
  if Strength >= 0 then Grid[x, y].Strength := Strength;
  if Dir > -2 then Grid[x, y].Dir := Dir;
end;

{ Bucket standing on the floor, centred on grid column cx }
procedure FloorBucket(cx: Integer; W, H: Single);
begin
  AddBucket(cx * CELL + HALF, FLOOR_Y - WALL_T - H, W, H);
end;

{ what follows goes on the Notes layer (labels, frames, links) }
procedure Notes;
begin
  CurLayer := LAYER_NOTES;
end;

procedure Link(X, Y: Single; const Caption: string; ToPopup: Boolean; Target, Color: Integer);
var
  i: Integer;
begin
  i := AddLink(X, Y, Caption, ToPopup, Target);
  if i >= 0 then Links[i].Color := Color;
end;

{ the three link buttons every plant page has, top right }
procedure PlantLinks;
begin
  Notes;
  Link(CANVAS_W - 136, 6, 'About', False, PAGE_ABOUT, 1);
  Link(CANVAS_W - 136, 28, 'How it works', True, POPUP_HOW, 2);
  Link(CANVAS_W - 136, 50, 'Try this', True, POPUP_TRY, 3);
end;

{ an empty layout set up for example n: page 1 "Plant" with its two layers, and the two popups }
procedure StartExample(n: Integer);
var
  p: Integer;
begin
  PagesReset;
  ClearAll;
  GravityScale := 1.0;
  Pages[PAGE_PLANT].Name := 'Plant';
  Pages[PAGE_PLANT].NLayers := 2;
  Pages[PAGE_PLANT].Layers[LAYER_PROCESS].Name := 'Process';
  Pages[PAGE_PLANT].Layers[LAYER_NOTES].Name := 'Notes';
  CurLayer := LAYER_PROCESS;
  p := AddPopup('How it works', HowText[n]);
  Popups[p].GoPage := PAGE_ABOUT;
  Popups[p].Color := 2;
  p := AddPopup('Try this', TryText[n]);
  Popups[p].Color := 3;
end;

{ page 2 "About", built in the live globals and parked; then page 1 is shown again }
procedure AddAboutPage(n: Integer);
var
  p: Integer;
begin
  ParkPage(PAGE_PLANT);
  Pages[PAGE_PLANT].ActiveLayer := LAYER_PROCESS;
  p := AddPage('About');
  CurPage := p;
  UnparkPage(p);
  Pages[p].Layers[0].Name := 'Text';
  CurLayer := 0;
  AddFrame(2 * CELL, 2 * CELL, 26 * CELL, 26 * CELL, 'ABOUT THIS EXAMPLE');
  Frames[0].Color := 1;
  Frames[0].Fill := True;
  AddLabel(4 * CELL, 4 * CELL, AboutText[n]);
  AddLabel(4 * CELL, 10 * CELL,
    'HOW THIS LAYOUT IS BUILT'#10 +
    'Page 1 "Plant" - the working process:'#10 +
    '  layer 1 "Process": pipes, feeders, buckets'#10 +
    '  layer 2 "Notes":   labels, frames, links'#10 +
    'Page 2 "About" - this page.'#10 +
    'Frame popups: "How it works", "Try this".');
  AddLabel(4 * CELL, 17 * CELL,
    'GETTING AROUND'#10 +
    'Click a link button (Select tool) to jump.'#10 +
    'PgUp / PgDn, or < > in the menu bar.'#10 +
    'Page & Layer panel (F6): pages and layers.'#10 +
    'Frame popup panel (F7): edit the popups.');
  Link(4 * CELL, 24 * CELL, 'Back to the plant', False, PAGE_PLANT, 1);
  Link(14 * CELL, 24 * CELL, 'How it works', True, POPUP_HOW, 2);
  Link(21 * CELL, 24 * CELL, 'Try this', True, POPUP_TRY, 3);
  ParkPage(p);
  CurPage := PAGE_PLANT;
  UnparkPage(PAGE_PLANT);
end;

{ 1. Two feeders merge at a tee: water falls by gravity through a one-way pipe,
     oil + fluff is blown in through a constriction. A small bucket overflows
     into a wide tray. }
procedure Example1;
begin
  Feeder(14, 2, 2500, 0, 0, 0, 10, 70);
  PipeLine(14, 2, 14, 25, 3);
  Device(14, 5, ckCheck, -1, 1);
  Device(14, 17, ckValve2);
  Device(14, 25, ckDrop, 100);

  Feeder(26, 3, 0, 1500, 500, 0, 20, 60);
  PipeLine(26, 3, 26, 9, 3);
  PipeLine(26, 9, 14, 9, 3);
  Grid[17, 9].Dia := 2;
  Grid[18, 9].Dia := 2;
  Device(21, 9, ckBlower, 55, 2);

  { small bucket first so it owns the particles inside it, standing in a wide tray }
  AddBucket(14 * CELL + HALF, FLOOR_Y - 2 * WALL_T - 70, 90, 70);
  AddBucket(14 * CELL + HALF, FLOOR_Y - WALL_T - 30, 320, 30);
  Notes;
  AddLabel(380, 40, 'Water falls by gravity'#10'through a 1-way pipe.'#10'Oil + fluff are blown in'#10'through a narrow section.');
  AddLabel(520, 700, 'The small bucket overflows'#10'into the wide tray.');
end;

{ 2. A strong blower pushes sand (with a little fluff) through an expansion and
     up a tall riser to a 3-way diverter at the top, which splits it into two
     long lines ending in drop outlets over two buckets. }
procedure Example2;
begin
  Feeder(15, 27, 0, 0, 300, 2500, 30, 70);
  PipeLine(15, 27, 22, 27, 3);
  Device(17, 27, ckBlower, 100, 0);
  Grid[19, 27].Dia := 5;
  Grid[20, 27].Dia := 5;
  PipeLine(22, 27, 22, 6, 3);
  PipeLine(22, 6, 9, 6, 3);
  PipeLine(22, 6, 35, 6, 3);
  PipeLine(9, 6, 9, 22, 3);
  PipeLine(35, 6, 35, 22, 3);
  Device(22, 6, ckValve3);
  Device(9, 22, ckDrop, 100);
  Device(35, 22, ckDrop, 100);
  FloorBucket(9, 130, 90);
  FloorBucket(35, 130, 90);
  Notes;
  AddLabel(560, 300, 'A strong blower lifts sand'#10'up the riser. The 3-way'#10'valve at the top splits it:'#10'select it and press R.');
end;

{ 3. Water + fluff drops into a bucket; a suction head sucks it out through a
     one-way pipe and a push-out nozzle shoots it sideways into a far bucket. }
procedure Example3;
begin
  Feeder(6, 2, 1500, 0, 600, 0, 10, 60);
  PipeLine(6, 2, 6, 20, 3);
  Device(6, 20, ckDrop, 100);
  AddBucket(7 * CELL, FLOOR_Y - WALL_T - 100, 150, 100);

  PipeLine(9, 29, 9, 14, 3);
  PipeLine(9, 14, 24, 14, 3);
  PipeLine(24, 14, 24, 26, 3);
  PipeLine(24, 26, 25, 26, 3);
  Device(9, 29, ckSuction, 70);
  Device(16, 14, ckCheck, -1, 0);
  Device(25, 26, ckNozzle, 40);
  AddBucket(37 * CELL, FLOOR_Y - WALL_T - 90, 220, 90);
  Notes;
  AddLabel(620, 400, 'The suction head drains'#10'the left bucket; the push-'#10'out nozzle shoots it across.');
end;

{ 4. A blower drives water + oil into a 4-way valve on a cross. Each branch
     (east, south, north) leads to its own bucket; open and shut branches to
     route the flow. North starts shut. }
procedure Example4;
begin
  Feeder(4, 10, 2500, 900, 0, 0, 10, 75);
  PipeLine(4, 10, 16, 10, 3);
  Device(8, 10, ckBlower, 75, 0);
  { east branch }
  PipeLine(16, 10, 26, 10, 3);
  PipeLine(26, 10, 26, 21, 3);
  Device(26, 21, ckDrop, 100);
  { south branch }
  PipeLine(16, 10, 16, 21, 3);
  Device(16, 21, ckDrop, 100);
  { north branch, up and over to the far bucket }
  PipeLine(16, 10, 16, 4, 3);
  PipeLine(16, 4, 35, 4, 3);
  PipeLine(35, 4, 35, 21, 3);
  Device(35, 21, ckDrop, 100);
  Device(16, 10, ckValve4);
  Grid[16, 10].Closed := 8;   { north shut }
  FloorBucket(16, 120, 90);
  FloorBucket(26, 120, 90);
  FloorBucket(35, 120, 90);
  Notes;
  AddLabel(430, 130, '4-WAY VALVE'#10'Select the valve and use its'#10'E S W N buttons (or R) to'#10'open and shut each branch.'#10'North starts shut.');
end;

{ 5. A sand feeder drops into a hopper; a blower carries the hopper's output
     across to a bucket. A second, gravity-only hopper catches water and
     drains straight down. }
procedure Example5;
begin
  Feeder(6, 2, 0, 0, 300, 2500, 0, 70);
  PipeLine(6, 2, 6, 8, 4);
  Device(6, 8, ckDrop, 60);
  MakePipe(6, 15, 3);
  SetKind(6, 15, ckHopper);
  PipeLine(6, 15, 24, 15, 3);
  Device(10, 15, ckBlower, 80, 0);
  PipeLine(24, 15, 24, 22, 3);
  Device(24, 22, ckDrop, 100);
  FloorBucket(24, 130, 90);

  Feeder(34, 2, 2000, 0, 0, 0, 0, 70);
  PipeLine(34, 2, 34, 6, 3);
  Device(34, 6, ckDrop, 100);
  MakePipe(34, 13, 3);
  SetKind(34, 13, ckHopper);
  PipeLine(34, 13, 34, 22, 3);
  Device(34, 22, ckDrop, 100);
  FloorBucket(34, 130, 90);

  Notes;
  AddLabel(120, 400, 'HOPPER + BLOWER'#10'Sand falls into the funnel,'#10'the blower carries it on.');
  AddLabel(870, 330, 'GRAVITY HOPPER'#10'Water falls in and'#10'drains straight down.');
  { frames group the two lines }
  AddFrame(1 * CELL, 0, 27 * CELL, GH * CELL, 'SAND LINE - hopper + blower');
  AddFrame(29 * CELL, 0, 15 * CELL, GH * CELL, 'WATER LINE - gravity hopper');
  Frames[1].Color := 1;
end;

{ 6. A blower lifts sand + fluff up a riser and drops it into the top of a
     silo. The silo stores it and its gate lets it out slowly into a bucket.
     A second silo is filled straight through a pipe. }
procedure Example6;
begin
  Feeder(3, 20, 0, 0, 150, 2600, 20, 70);
  PipeLine(3, 20, 10, 20, 3);
  Device(6, 20, ckBlower, 85, 0);
  PipeLine(10, 20, 10, 4, 3);
  PipeLine(10, 4, 21, 4, 3);
  PipeLine(21, 4, 21, 6, 3);
  Device(21, 6, ckDrop, 100);
  MakePipe(21, 18, 3);
  SetKind(21, 18, ckSilo);
  Grid[21, 18].Feed := 30;
  PipeLine(21, 18, 21, 25, 3);
  Device(21, 25, ckDrop, 100);
  FloorBucket(21, 140, 80);

  { silo 2: fed by a pipe from a water feeder, gate shut (pure storage) }
  Feeder(32, 3, 2500, 0, 0, 0, 10, 80);
  PipeLine(32, 3, 32, 19, 3);
  Device(32, 12, ckBlower, 60, 1);
  MakePipe(36, 19, 3);
  SetKind(36, 19, ckSilo);
  PipeLine(32, 19, 36, 19, 3);   { into the silo's side }
  Grid[36, 19].Feed := 0;
  PipeLine(36, 19, 36, 25, 3);
  Device(36, 25, ckDrop, 100);
  FloorBucket(36, 120, 80);

  Notes;
  AddLabel(280, 140, 'SILO'#10'Sand drops in through the'#10'roof; the gate (30%) lets'#10'it out slowly.');
  AddLabel(880, 300, 'Pipe-fed silo,'#10'gate shut: it'#10'only stores.');
  AddFrame(1 * CELL, 0, 27 * CELL, GH * CELL, 'SILO 1 - filled from the roof');
  AddFrame(29 * CELL, 0, 15 * CELL, GH * CELL, 'SILO 2 - filled by pipe, stores');
  Frames[0].Color := 3;
  Frames[1].Color := 1;
  Frames[1].Dashed := True;
end;

procedure BuildExample(n: Integer);
begin
  if (n < 1) or (n > EXAMPLE_COUNT) then Exit;
  StartExample(n);
  case n of
    1: Example1;
    2: Example2;
    3: Example3;
    4: Example4;
    5: Example5;
    6: Example6;
  end;
  PlantLinks;
  AddAboutPage(n);
  { new parts the user draws go on the Process layer }
  SetActiveLayer(LAYER_PROCESS);
end;

end.
