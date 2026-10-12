unit mfexamples;

{ Three built-in example pipe layouts (also shipped as examples\*.mflow). }

{$mode objfpc}{$H+}

interface

const
  EXAMPLE_COUNT = 3;
  ExampleTitles: array[1..EXAMPLE_COUNT] of string = (
    'Gravity merge/overflow',
    'Pneumatic conveyor',
    'Vacuum & push nozzle');
  ExampleFiles: array[1..EXAMPLE_COUNT] of string = (
    'example1_gravity_merge.mflow',
    'example2_pneumatic_conveyor.mflow',
    'example3_vacuum_nozzle.mflow');

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

procedure BuildExample(n: Integer);
begin
  ClearAll;
  GravityScale := 1.0;
  case n of
    1: Example1;
    2: Example2;
    3: Example3;
  end;
end;

end.
