unit mfexamples;

{ Six built-in example pipe layouts (also shipped as examples\*.mflow). }

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
  simcore;

procedure Tank(x, y: Integer; Water, Oil, Fluff, Sand, Air, Feed: Single);
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

{ 1. Two tanks merge at a tee: water falls by gravity through a one-way pipe,
     oil + fluff is blown in through a constriction. A small bucket overflows
     into a wide tray. }
procedure Example1;
begin
  Tank(14, 2, 2500, 0, 0, 0, 10, 70);
  PipeLine(14, 2, 14, 25, 3);
  Device(14, 5, ckCheck, -1, 1);
  Device(14, 17, ckValve2);
  Device(14, 25, ckDrop, 100);

  Tank(26, 3, 0, 1500, 500, 0, 20, 60);
  PipeLine(26, 3, 26, 9, 3);
  PipeLine(26, 9, 14, 9, 3);
  Grid[17, 9].Dia := 2;
  Grid[18, 9].Dia := 2;
  Device(21, 9, ckBlower, 55, 2);

  { small bucket first so it owns the particles inside it, standing in a wide tray }
  AddBucket(14 * CELL + HALF, FLOOR_Y - 2 * WALL_T - 70, 90, 70);
  AddBucket(14 * CELL + HALF, FLOOR_Y - WALL_T - 30, 320, 30);
  AddLabel(380, 40, 'Water falls by gravity'#10'through a 1-way pipe.'#10'Oil + fluff are blown in'#10'through a narrow section.');
  AddLabel(520, 700, 'The small bucket overflows'#10'into the wide tray.');
end;

{ 2. A strong blower pushes sand (with a little fluff) through an expansion and
     up a tall riser to a 3-way diverter at the top, which splits it into two
     long lines ending in drop outlets over two buckets. }
procedure Example2;
begin
  Tank(15, 27, 0, 0, 300, 2500, 30, 70);
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
  AddLabel(560, 300, 'A strong blower lifts sand'#10'up the riser. The 3-way'#10'valve at the top splits it:'#10'select it and press R.');
end;

{ 3. Water + fluff drops into a bucket; a suction head sucks it out through a
     one-way pipe and a push-out nozzle shoots it sideways into a far bucket. }
procedure Example3;
begin
  Tank(6, 2, 1500, 0, 600, 0, 10, 60);
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
  AddLabel(620, 400, 'The suction head drains'#10'the left bucket; the push-'#10'out nozzle shoots it across.');
end;

{ 4. A blower drives water + oil into a 4-way valve on a cross. Each branch
     (east, south, north) leads to its own bucket; open and shut branches to
     route the flow. North starts shut. }
procedure Example4;
begin
  Tank(4, 10, 2500, 900, 0, 0, 10, 75);
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
  AddLabel(430, 130, '4-WAY VALVE'#10'Select the valve and use its'#10'E S W N buttons (or R) to'#10'open and shut each branch.'#10'North starts shut.');
end;

{ 5. A sand tank drops into a hopper; a blower carries the hopper's output
     across to a bucket. A second, gravity-only hopper catches water and
     drains straight down. }
procedure Example5;
begin
  Tank(6, 2, 0, 0, 300, 2500, 0, 70);
  PipeLine(6, 2, 6, 8, 4);
  Device(6, 8, ckDrop, 60);
  MakePipe(6, 15, 3);
  SetKind(6, 15, ckHopper);
  PipeLine(6, 15, 24, 15, 3);
  Device(10, 15, ckBlower, 80, 0);
  PipeLine(24, 15, 24, 22, 3);
  Device(24, 22, ckDrop, 100);
  FloorBucket(24, 130, 90);

  Tank(34, 2, 2000, 0, 0, 0, 0, 70);
  PipeLine(34, 2, 34, 6, 3);
  Device(34, 6, ckDrop, 100);
  MakePipe(34, 13, 3);
  SetKind(34, 13, ckHopper);
  PipeLine(34, 13, 34, 22, 3);
  Device(34, 22, ckDrop, 100);
  FloorBucket(34, 130, 90);

  AddLabel(120, 400, 'HOPPER + BLOWER'#10'Sand falls into the funnel,'#10'the blower carries it on.');
  AddLabel(560, 230, 'GRAVITY HOPPER'#10'Water falls in and'#10'drains straight down.');
end;

{ 6. A blower lifts sand + fluff up a riser and drops it into the top of a
     silo. The silo stores it and its gate lets it out slowly into a bucket.
     A second silo is filled straight through a pipe. }
procedure Example6;
begin
  Tank(3, 20, 0, 0, 150, 2600, 20, 70);
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

  { silo 2: fed by a pipe from a water tank, gate shut (pure storage) }
  Tank(32, 3, 2500, 0, 0, 0, 10, 80);
  PipeLine(32, 3, 32, 19, 3);
  Device(32, 12, ckBlower, 60, 1);
  MakePipe(36, 19, 3);
  SetKind(36, 19, ckSilo);
  PipeLine(32, 19, 36, 19, 3);   { into the silo's side }
  Grid[36, 19].Feed := 0;
  PipeLine(36, 19, 36, 25, 3);
  Device(36, 25, ckDrop, 100);
  FloorBucket(36, 120, 80);

  AddLabel(560, 120, 'SILO'#10'Sand drops in through the'#10'roof; the gate (30%) lets'#10'it out slowly.');
  AddLabel(880, 300, 'Pipe-fed silo,'#10'gate shut: it'#10'only stores.');
end;

procedure BuildExample(n: Integer);
begin
  ClearAll;
  GravityScale := 1.0;
  case n of
    1: Example1;
    2: Example2;
    3: Example3;
    4: Example4;
    5: Example5;
    6: Example6;
  end;
end;

end.
