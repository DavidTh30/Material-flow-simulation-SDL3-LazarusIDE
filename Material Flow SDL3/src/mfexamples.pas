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
  EXAMPLE_COUNT = 26;
  ExampleTitles: array[1..EXAMPLE_COUNT] of string = (
    'Gravity merge/overflow',
    'Pneumatic conveyor',
    'Vacuum & push nozzle',
    '4-way valve switchyard',
    'Hopper feed',
    'Silo storage',
    'Fluff silo system',
    'Rain, fire & heaters',
    'Well, pool, pond & pumps',
    'Circuit: well pump',
    'Circuit: start / stop (DOL)',
    'Circuit: star-delta starter',
    'Circuit: conveyor line',
    'Circuit: meters, pot & CT',
    'Pneumatic: cylinders & valves',
    'Electro-pneumatic: gate cycle',
    'Pneumatic logic: AND / OR',
    'Compressor control & air motor',
    'Hydraulic: power unit & 4/3',
    'Electro-hydraulic press',
    'Hydraulic motor & flow control',
    'Timers & counter',
    'Sensors & PID control',
    'Every page at once',
    'Heat exchanger & humidity',
    'Cooling tower, chiller & pH');
  ExampleFiles: array[1..EXAMPLE_COUNT] of string = (
    'example1_gravity_merge.mflow',
    'example2_pneumatic_conveyor.mflow',
    'example3_vacuum_nozzle.mflow',
    'example4_4way_switchyard.mflow',
    'example5_hopper_feed.mflow',
    'example6_silo_storage.mflow',
    'example7_fluff_silo_system.mflow',
    'example8_rain_fire_heaters.mflow',
    'example9_well_pool_pond_pumps.mflow',
    'example10_circuit_well_pump.mflow',
    'example11_circuit_start_stop.mflow',
    'example12_circuit_star_delta.mflow',
    'example13_circuit_conveyor_line.mflow',
    'example14_circuit_meters_pot_ct.mflow',
    'example15_pneumatic_cylinders.mflow',
    'example16_electro_pneumatic_gate.mflow',
    'example17_pneumatic_logic.mflow',
    'example18_compressor_air_motor.mflow',
    'example19_hydraulic_power_unit.mflow',
    'example20_electro_hydraulic_press.mflow',
    'example21_hydraulic_motor.mflow',
    'example22_timers_counter.mflow',
    'example23_sensors_pid_control.mflow',
    'example24_every_page_at_once.mflow',
    'example25_heat_exchanger_humidity.mflow',
    'example26_cooling_tower_chiller_ph.mflow');

const
  { the Examples menu: one sub-menu per category, examples CatFirst..CatLast }
  EXAMPLE_CATS = 6;
  CatNames: array[1..EXAMPLE_CATS] of string = ('Pipes & air flow', 'Storage & equipment',
    'Electrical circuits', 'Pneumatic systems', 'Hydraulic systems', 'Control & sensors');
  CatFirst: array[1..EXAMPLE_CATS] of Integer = (1, 5, 10, 15, 19, 22);
  CatLast: array[1..EXAMPLE_CATS] of Integer = (4, 9, 14, 18, 21, 26);

procedure BuildExample(n: Integer);

implementation

uses
  simcore, mfpages, elec, fluid;

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
    'its gate is shut, so it only stores.',
    'Screw01 empties the silo into the funnel;'#10 +
    'Blower01 blows the fluff up the riser to the'#10 +
    'cyclone on the silo roof (a loop), and part of'#10 +
    'it goes on to the consumer.'#10 +
    'Each motor drives a real part: stop or fault'#10 +
    'it and that part stops.',
    'Rain01 rains on the left bucket; IRHeater01'#10 +
    'boils the drops below it off as steam.'#10 +
    'Fluff drops on Fire01 and keeps it burning;'#10 +
    'start Rain02 to put the fire out. Heater01'#10 +
    'boils the water in its pipe to steam.',
    'Pump01 draws ground water from the well and'#10 +
    'pumps it up and over into the pool. Pump02'#10 +
    'pumps the pool on into the pond.'#10 +
    'A pump takes water from the nearest pond,'#10 +
    'pool or well; the levels change for real.',
    'Q1 feeds the circuit (red L, blue N rails).'#10 +
    'SA1 in AUTO: LS1 closes while Pool01 is below'#10 +
    '30% and opens at 80%; LS2 opens if Well01'#10 +
    'runs dry. KM1 then runs motor M1 = Pump01.',
    'SB0 (NC) and SB1 (NO) are push buttons: hold'#10 +
    'SB1 to start. KM1 closes its own NO contact'#10 +
    'beside SB1 (seal-in), so it keeps running.'#10 +
    'M1 runs Belt01; OL1 trips if it faults.',
    'SB1 starts KM1; KM2 joins it: the motor runs'#10 +
    'in star (low current). T1 counts 5 s, then'#10 +
    'its NC opens (KM2 off) and its NO closes'#10 +
    '(KM3 on): delta, full power. Both motor'#10 +
    'loads drive Blower01.',
    'SB1 starts KM2: the belt runs. T1 (3 s) then'#10 +
    'closes KM1: drive U1 runs the roller'#10 +
    'conveyor at 70%. Sand rides both conveyors'#10 +
    'into the bucket. SB0 / ES1 stop the line.',
    'S1 runs KM1: drive U1 runs Pump01 at the'#10 +
    'speed of potentiometer RV1. CT1 measures its'#10 +
    'current, Gauge01 shows it. S2 starts Motor01'#10 +
    'direct on line: CT2 shows the inrush (about'#10 +
    '6x) settling to the rated 5 A.',
    'C1 fills receiver R1; FRL1 gives 6 bar.'#10 +
    'V1 (5/2) sends air to A (out) or B side (in)'#10 +
    'of cylinder A; FC1 / FC2 throttle the air.'#10 +
    'V2 (3/2, push button) fills single-acting'#10 +
    'cylinder B; its spring brings it back.',
    'K1 runs the cycle: with A in (A0) Y1 sends'#10 +
    'it out; it opens Gate01 and the hopper'#10 +
    'empties. At A1 timer T1 counts 2 s, then'#10 +
    'Y2 brings it back. The valve keeps its'#10 +
    'position between the pulses.',
    'The AND valve passes air only when both S1'#10 +
    'and S2 give it; the shuttle valve passes'#10 +
    'whichever of S3 / S4 does.',
    'PS1 closes below 6 bar and opens at 8: KM1'#10 +
    'runs C1 only then. AM1 uses air from R1, so'#10 +
    'the pressure falls and C1 starts again.',
    'P1 pumps oil at up to 120 bar, RV1 relieves'#10 +
    'above 100. In the centre of V1 the pump'#10 +
    'unloads to tank; 1 lifts, 2 lowers.',
    'SB1 latches K1: Y1 shifts V1 down. At A1 K1'#10 +
    'drops, K2 latches: Y2 shifts V1 up until A0.'#10 +
    'With no solenoid V1 springs to its centre.',
    'V1 sends oil through FC1 to HM1 and back to'#10 +
    'tank. FC1''s opening is the motor''s speed:'#10 +
    'Conveyor01 carries the sand faster or slower.',
    'Flasher T1 (1 s on, 2.5 s off) runs KM1 / M1:'#10 +
    'Slide01 opens and one batch of sand falls.'#10 +
    'Photo sensor PE1 closes while it passes, and'#10 +
    'counter CNT1 counts one. At 5 its NC opens'#10 +
    'the flasher line and its NO lights H1.',
    'LT1 reads Pool01; PID controller LIC1 sets'#10 +
    'the speed of U1 (Pump01) to hold 60% while'#10 +
    'Pump02 drains the pool. TT1 reads Heater01;'#10 +
    'TIC1 switches it on below 145 C and off'#10 +
    'above 155 C. PT1, FT1, ST1 feed displays.',
    'All four pages run every frame. KM1 on page 1'#10 +
    'runs Pump01 on page 3 over the plant bus; LT1'#10 +
    'on page 1 reads Pool01 on page 3; the meters'#10 +
    'on page 4 show values from pages 1 and 3.',
    'The blower pushes wet sand through the shell'#10 +
    'of HX01; hot water at 160 C runs through its'#10 +
    'tubes. TT1 reads the shell outlet, TIC1 sets'#10 +
    'the hot flow (drive U1) to hold 80 C. MT1 and'#10 +
    'MT2 measure the air and the sand''s moisture.',
    'Stream 1 (90 C) runs through HX01; Tower01'#10 +
    'cools its tube water and gets it back (a loop).'#10 +
    'TIC1 (PID, reverse) sets the fan (drive U1)'#10 +
    'to hold stream 1 at 40 C. Chiller01 sends 7 C'#10 +
    'water through HX02 to cool stream 2 (30 C).');

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
    'be changed, but they still work.',
    'Double-click Blower01: it stops (grey) and'#10 +
    'so does the air; Screw01 stops the silo.'#10 +
    'Select a motor and press Fault: it turns red.'#10 +
    'Show the hidden layer "Silo core" (F6).',
    'Rain02: Rain - the fire goes out (OUT).'#10 +
    'Fire01: Ignite again; shut Shutter01 to stop'#10 +
    'the fluff. IRHeater01 / Heater01: Auto start.'#10 +
    'Slide01 shuts the water line.',
    'Start Pump02 (double-click): the pool drains'#10 +
    'into the pond. Stop Pump01: the pool stops'#10 +
    'rising. Start Rain01 over the pond.'#10 +
    'Run the pond full: it overflows.',
    'Click SA1 to switch OFF / HAND / AUTO.'#10 +
    'Set Pool01 low (Properties): the pump starts.'#10 +
    'Press ES1, open Q1, or trip OL1 (Properties):'#10 +
    'H2 shows the fault. Reset to run again.',
    'Hold SB1 to start, hold SB0 to stop.'#10 +
    'Click ES1 (E-Stop) and click it again.'#10 +
    'Select Belt01 and press Fault: OL1 trips,'#10 +
    'H3 and HA1 come on. Reset OL1.',
    'Hold SB1 and watch H1 (star), then H2'#10 +
    '(delta). Change T1 in Properties.'#10 +
    'Fault Blower01: OL1 trips everything.',
    'Hold SB1: the belt first, then the rollers.'#10 +
    'Change U1''s speed in Properties.'#10 +
    'Fault Belt01: OL2 stops the whole line.',
    'Turn RV1 with the mouse wheel: the pump speed,'#10 +
    'its current and the pool filling all change.'#10 +
    'Click S2 and watch Gauge02 kick and settle.'#10 +
    'Set OL2''s Trip A to 3: it trips after 2 s.',
    'Turn FC1 down (wheel): A goes out slower.'#10 +
    'Switch C1 off (click it): R1 runs down.'#10 +
    'Focus Properties on R1 (right-click).',
    'Hold SB0 to stop the cycle. Change T1.'#10 +
    'Click V1 in Ctrl: see its solenoids Y1 / Y2.',
    'Switch S1 and S2: only both move A.'#10 +
    'Switch S3 or S4: either moves B.',
    'Turn FC1 up: the belt speeds up and the'#10 +
    'compressor has to start more often.',
    'Click V1 three times: centre, up, down.'#10 +
    'Set RV1 lower (wheel): the gauge follows.',
    'Hold SB1, watch the press go down and up.'#10 +
    'Slow it down: Stroke s of cylinder A.',
    'Turn FC1 with the mouse wheel.'#10 +
    'Click V1 to stop the motor.',
    'Hold SB1 to reset the count.'#10 +
    'Set CNT1''s Preset, T1''s On / Off times.'#10 +
    'Switch T2 to Pulse or On-delay.',
    'Change LIC1''s set point on its faceplate'#10 +
    '(select it). Switch S2 off: no draining.'#10 +
    'Set TIC1 to PID; try other Band values.',
    'Hold SB1 and stay on this page: the pool on'#10 +
    'page 3 fills anyway. Go to page 3 or 4 and'#10 +
    'come back: nothing stopped while away.',
    'Set TIC1 to 120 C (faceplate): the water'#10 +
    'boils off and MT1 rises. Turn the blower'#10 +
    'down (wheel): less flow, hotter outlet.'#10 +
    'Add more water to the feeder: MT2 goes up.',
    'Set TIC1 to 30 C: the fan runs flat out.'#10 +
    'Switch S2 off: the chiller stops, HX02 warms.'#10 +
    'Physics lab: set sand''s pH and watch PH1.');

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
    'and let out slowly, one filled through a pipe.',
    'EXAMPLE 7 - FLUFF SILO SYSTEM'#10 +
    'Plant equipment (Equipment layer) drawn over'#10 +
    'a working process: silo bin, cyclone, paddles,'#10 +
    'screw conveyor, blower, lamp and legend.'#10 +
    'Green = running, grey = stopped, red = fault.',
    'EXAMPLE 8 - RAIN, FIRE & HEATERS'#10 +
    'Rain drops real water; the IR heater dries the'#10 +
    'drops below it; fluff feeds a fire that rain'#10 +
    'puts out; a duct heater boils water to steam.'#10 +
    'Shutter and slide valves open and shut lines.',
    'EXAMPLE 9 - WELL, POOL, POND & PUMPS'#10 +
    'Water pumps move water between a well (ground'#10 +
    'water that refills), a pool and a pond. Each'#10 +
    'holds its water as a level that rises with'#10 +
    'the drops that reach it.',
    'EXAMPLE 10 - WELL PUMP CIRCUIT'#10 +
    'An electrical cabinet runs the well pump:'#10 +
    'breaker, fuse, E-Stop, a HAND / AUTO selector,'#10 +
    'float switches, contactor, overload, lamps.',
    'EXAMPLE 11 - START / STOP (DOL)'#10 +
    'The classic motor circuit: stop and start'#10 +
    'buttons and a seal-in contact run a belt'#10 +
    'conveyor that carries sand to a bucket.',
    'EXAMPLE 12 - STAR-DELTA STARTER'#10 +
    'Three contactors and a timer start a big'#10 +
    'blower in star, then switch it to delta.',
    'EXAMPLE 13 - CONVEYOR LINE'#10 +
    'Two conveyors in a line: the belt starts'#10 +
    'first, the roller conveyor (on a VFD) after'#10 +
    'a timer, so nothing piles up.',
    'EXAMPLE 14 - METERS, POTENTIOMETER & CT'#10 +
    'A potentiometer sets the speed of a pump on'#10 +
    'a VFD; current transformers measure the pump'#10 +
    'and a direct-on-line motor (see its inrush);'#10 +
    'needle gauges and digital displays show it.',
    'EXAMPLE 15 - PNEUMATIC CYLINDERS'#10 +
    'A compressor, receiver and FRL supply a 5/2'#10 +
    'valve and a 3/2 valve. ISO symbols, lines'#10 +
    'coloured by pressure (blue: air).',
    'EXAMPLE 16 - ELECTRO-PNEUMATIC GATE'#10 +
    'A double-solenoid valve, limit switches and a'#10 +
    'timer open a hopper gate batch after batch.',
    'EXAMPLE 17 - PNEUMATIC LOGIC'#10 +
    'A two-pressure valve (AND) and a shuttle'#10 +
    'valve (OR) combine manual 3/2 valves.',
    'EXAMPLE 18 - COMPRESSOR & AIR MOTOR'#10 +
    'A pressure switch keeps the receiver between'#10 +
    '6 and 8 bar; an air motor drives a belt.',
    'EXAMPLE 19 - HYDRAULIC POWER UNIT'#10 +
    'Pump, relief valve, tandem-centre 4/3 valve'#10 +
    'and a lifting cylinder (orange: oil).',
    'EXAMPLE 20 - ELECTRO-HYDRAULIC PRESS'#10 +
    'Solenoids, relays and limit switches run a'#10 +
    'press down and up automatically.',
    'EXAMPLE 21 - HYDRAULIC MOTOR'#10 +
    'A hydraulic motor turns a conveyor; a flow'#10 +
    'control sets its speed.',
    'EXAMPLE 22 - TIMERS & COUNTER'#10 +
    'A flasher, an off-delay timer, a photo sensor'#10 +
    'and a counter dose sand in batches of five.',
    'EXAMPLE 23 - SENSORS & PID CONTROL'#10 +
    'Level, temperature, pressure, flow and speed'#10 +
    'sensors; a PID level loop and an on / off'#10 +
    'temperature loop, each with a faceplate.',
    'EXAMPLE 24 - EVERY PAGE AT ONCE'#10 +
    'A control room, a pump house and a monitor'#10 +
    'on pages of their own, all running together.',
    'EXAMPLE 25 - HEAT EXCHANGER & HUMIDITY'#10 +
    'A shell-and-tube heat exchanger under PID'#10 +
    'temperature control, and humidity sensors for'#10 +
    'the air and for the moisture of the material.',
    'EXAMPLE 26 - COOLING TOWER, CHILLER & PH'#10 +
    'A cooling water loop with a tower under PID'#10 +
    'fan control, a chilled water loop, pH sensors'#10 +
    'and the humidity of the tower''s plume.');

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
procedure PlantLinks(X: Single = CANVAS_W - 136; Y: Single = 6);
begin
  Notes;
  Link(X, Y, 'About', False, PAGE_ABOUT, 1);
  Link(X, Y + 22, 'How it works', True, POPUP_HOW, 2);
  Link(X, Y + 44, 'Try this', True, POPUP_TRY, 3);
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

{ 7. The fluff silo system: a silo bin with three paddle agitators and a
     cyclone on its roof, a screw conveyor under it discharging into a
     funnel, and a centrifugal blower that blows the fluff up the riser back
     to the cyclone (a loop), with a branch to the consumer. The plant
     equipment sits on its own layer and drives the real parts it is linked
     to; the real silo is on a hidden layer inside the bin. }
procedure Example7;
var
  e: Integer;

  function Eq(Kind: Integer; X, Y, W, H: Single; const Name: string; St: Integer): Integer;
  begin
    Result := AddEquip(Kind, X, Y);
    Equips[Result].W := W;
    Equips[Result].H := H;
    Equips[Result].Name := Name;
    Equips[Result].State := St;
  end;

  procedure Seq(i, Step: Integer; Delay: Single);
  begin
    Equips[i].SeqStep := Step;
    Equips[i].Delay := Delay;
  end;

  procedure LinkTo(i, gx, gy: Integer);
  begin
    Equips[i].LinkX := gx;
    Equips[i].LinkY := gy;
  end;

begin
  Pages[PAGE_PLANT].NLayers := 4;
  Pages[PAGE_PLANT].Layers[2].Name := 'Equipment';
  Pages[PAGE_PLANT].Layers[3].Name := 'Silo core';
  Pages[PAGE_PLANT].Layers[3].Visible := False;

  { the real silo, inside the bin (hidden layer); it starts part full }
  CurLayer := 3;
  MakePipe(16, 16, 3);
  SetKind(16, 16, ckSilo);
  Grid[16, 16].Stock[mFluff] := 1600;
  Grid[16, 16].Feed := 70;

  CurLayer := LAYER_PROCESS;
  { screw line: silo outlet along under the bin to the drop over the funnel }
  PipeLine(16, 16, 16, 17, 3);
  PipeLine(16, 17, 24, 17, 3);
  PipeLine(24, 17, 24, 19, 3);
  Device(24, 19, ckDrop, 100);
  { funnel and the blower line }
  MakePipe(24, 23, 3);
  SetKind(24, 23, ckHopper);
  PipeLine(24, 23, 24, 27, 3);
  PipeLine(24, 27, 40, 27, 3);
  Device(33, 27, ckBlower, 95, 0);
  { fresh fluff fed into the suction side of the blower }
  Feeder(28, 24, 0, 0, 2500, 0, 20, 25);
  PipeLine(28, 24, 28, 27, 3);
  { riser, across the top and down into the cyclone on the silo roof }
  PipeLine(40, 27, 40, 2, 3);
  PipeLine(40, 2, 16, 2, 3);
  PipeLine(16, 2, 16, 4, 3);
  Device(16, 4, ckDrop, 100);
  { branch to the consumer }
  PipeLine(40, 8, 41, 8, 3);
  PipeLine(41, 8, 41, 20, 3);
  Device(40, 8, ckValve3);
  Grid[40, 8].Dir := -1;
  Device(41, 20, ckDrop, 100);
  FloorBucket(41, 80, 80);

  { the plant equipment }
  CurLayer := 2;
  e := Eq(EQ_STAND, 252, 448, 264, 112, '', EQS_STOP);
  e := Eq(EQ_SILO, 264, 144, 240, 264, 'Silo01', EQS_STOP);
  LinkTo(e, 16, 16);
  e := Eq(EQ_CYCLONE, 368, 40, 56, 104, 'Cyclone01', EQS_STOP);
  e := Eq(EQ_PADDLE, 176, 196, 320, 40, 'Paddle03', EQS_DISABLE);
  e := Eq(EQ_PADDLE, 176, 262, 320, 40, 'Paddle02', EQS_MSTOP);
  e := Eq(EQ_PADDLE, 176, 328, 320, 40, 'Paddle01', EQS_STOP);
  Seq(e, 3, 3);
  e := Eq(EQ_SCREW, 160, 400, 440, 44, 'Screw01', EQS_STOP);
  LinkTo(e, 16, 16);
  Seq(e, 2, 4);
  e := Eq(EQ_BLOWER, 744, 560, 120, 112, 'Blower01', EQS_STOP);
  LinkTo(e, 33, 27);
  Seq(e, 1, 2);
  { the diverter on the tee: position 1 splits to the consumer, position 2 sends all back to the silo }
  e := Eq(EQ_DIVERTER, 940, 156, 56, 72, 'Diverter01', EQS_STOP);
  LinkTo(e, 40, 8);
  Equips[e].DivA := -1;
  Equips[e].DivB := 0;
  Seq(e, 4, 5);
  { the sequence: request on, it starts the steps one after another }
  e := Eq(EQ_SEQUENCE, 552, 80, 296, 66, 'Sequence', EQS_RUN);
  e := Eq(EQ_LAMP, 800, 232, 16, 16, 'Ext. Request', EQS_STOP);
  LinkTo(e, 41, 20);
  e := Eq(EQ_LEGEND, 24, 24, 232, 136, 'Legend', EQS_STOP);

  Notes;
  AddLabel(600, 30, 'Fluff feed / return to the silo');
  AddLabel(860, 250, 'to consumer');
  AddLabel(560, 470, 'Funnel');
  AddLabel(24, 470, 'FLUFF SILO SYSTEM'#10'Screw01 empties the silo,'#10'Blower01 blows the fluff'#10'back up to the cyclone.'#10'Double-click a motor:'#10'run / stop.');
end;

{ 8. Rain, fire and heaters: a rain cloud fills a bucket and an IR heater
     dries the drops falling past it; fluff dropped on a fire keeps it
     burning until a second cloud rains on it; a duct heater boils the water
     in a pipe; a shutter valve and a slide valve open and shut the lines. }
procedure Example8;
var
  e: Integer;

  function Eq(Kind: Integer; X, Y, W, H: Single; const Name: string; St: Integer): Integer;
  begin
    Result := AddEquip(Kind, X, Y);
    Equips[Result].W := W;
    Equips[Result].H := H;
    Equips[Result].Name := Name;
    Equips[Result].State := St;
  end;

begin
  Pages[PAGE_PLANT].NLayers := 3;
  Pages[PAGE_PLANT].Layers[2].Name := 'Equipment';

  CurLayer := LAYER_PROCESS;
  FloorBucket(6, 200, 80);
  { fluff line onto the fire, with a 2-way valve for the shutter valve }
  Feeder(20, 3, 0, 0, 2500, 0, 20, 60);
  PipeLine(20, 3, 20, 10, 3);
  Device(20, 7, ckValve2);
  Device(20, 10, ckDrop, 100);
  { water line through a 2-way valve (slide valve) and a heated cell }
  Feeder(34, 3, 2500, 0, 0, 0, 10, 70);
  PipeLine(34, 3, 34, 20, 3);
  Device(34, 8, ckValve2);
  Device(34, 20, ckDrop, 100);
  FloorBucket(34, 140, 80);

  CurLayer := 2;
  e := Eq(EQ_RAIN, 56, 200, 200, 56, 'Rain01', EQS_RUN);
  Equips[e].Level := 50;
  e := Eq(EQ_IRHEATER, 56, 520, 200, 28, 'IRHeater01', EQS_STOP);
  e := Eq(EQ_FIRE, 444, 728, 96, 84, 'Fire01', EQS_RUN);
  Equips[e].Heat := 100;
  e := Eq(EQ_RAIN, 412, 480, 160, 48, 'Rain02', EQS_STOP);
  Equips[e].Level := 80;
  e := Eq(EQ_SHUTTER, 456, 150, 72, 44, 'Shutter01', EQS_RUN);
  Equips[e].LinkX := 20;
  Equips[e].LinkY := 7;
  e := Eq(EQ_SLIDE, 784, 168, 64, 64, 'Slide01', EQS_RUN);
  Equips[e].LinkX := 34;
  Equips[e].LinkY := 8;
  e := Eq(EQ_HEATER, 768, 328, 96, 48, 'Heater01', EQS_STOP);
  Equips[e].LinkX := 34;
  Equips[e].LinkY := 14;
  e := Eq(EQ_LEGEND, 24, 24, 232, 136, 'Legend', EQS_STOP);

  Notes;
  AddLabel(280, 240, 'RAIN'#10'Real water drops:'#10'they fill the bucket.'#10'IRHeater01 dries them.');
  AddLabel(600, 600, 'FIRE'#10'Fluff keeps it burning.'#10'Rain02 puts it out.');
  AddLabel(880, 360, 'DUCT HEATER'#10'Water boils to'#10'steam in the pipe.');
end;

{ 9. Well, pool, pond and pumps: a pump lifts ground water from a well up and
     over into a pool; a second pump moves the pool on into a pond; a rain
     cloud can fill the pond. }
procedure Example9;
var
  e: Integer;

  function Eq(Kind: Integer; X, Y, W, H: Single; const Name: string; St: Integer): Integer;
  begin
    Result := AddEquip(Kind, X, Y);
    Equips[Result].W := W;
    Equips[Result].H := H;
    Equips[Result].Name := Name;
    Equips[Result].State := St;
  end;

begin
  Pages[PAGE_PLANT].NLayers := 3;
  Pages[PAGE_PLANT].Layers[2].Name := 'Equipment';

  CurLayer := LAYER_PROCESS;
  { well -> pool: the pump's own push (an inline blower) lifts the water }
  PipeLine(9, 31, 9, 8, 3);
  PipeLine(9, 8, 20, 8, 3);
  PipeLine(20, 8, 20, 10, 3);
  Device(9, 29, ckBlower, 95, 3);
  Device(20, 10, ckDrop, 100);
  { pool -> pond }
  PipeLine(28, 31, 28, 12, 3);
  PipeLine(28, 12, 37, 12, 3);
  PipeLine(37, 12, 37, 16, 3);
  Device(28, 29, ckBlower, 95, 3);
  Device(37, 16, ckDrop, 100);

  CurLayer := 2;
  e := Eq(EQ_WELL, 40, 612, 104, 200, 'Well01', EQS_STOP);
  Equips[e].Level := 80;
  e := Eq(EQ_PUMP, 160, 728, 104, 56, 'Pump01', EQS_RUN);
  Equips[e].LinkX := 9;
  Equips[e].LinkY := 29;
  Equips[e].Level := 70;
  e := Eq(EQ_POOL, 392, 716, 216, 96, 'Pool01', EQS_STOP);
  Equips[e].Level := 15;
  e := Eq(EQ_PUMP, 616, 728, 104, 56, 'Pump02', EQS_STOP);
  Equips[e].LinkX := 28;
  Equips[e].LinkY := 29;
  Equips[e].Level := 70;
  Equips[e].Flip := True;
  e := Eq(EQ_POND, 760, 732, 272, 80, 'Pond01', EQS_STOP);
  Equips[e].Level := 25;
  e := Eq(EQ_RAIN, 790, 300, 220, 52, 'Rain01', EQS_STOP);
  Equips[e].Level := 60;
  e := Eq(EQ_LEGEND, 24, 24, 232, 136, 'Legend', EQS_STOP);

  Notes;
  AddLabel(160, 480, 'WELL + PUMP01'#10'Ground water is lifted'#10'up and over to the pool.');
  AddLabel(560, 470, 'POOL -> PUMP02 -> POND'#10'Double-click Pump02'#10'to start it.');
  AddLabel(820, 420, 'POND'#10'Rain01 can fill it too.');
end;

{ ---------------------------------------------------------------- electrical examples }

{ a device on the wiring at x,y with its tag (and the equipment it works with) }
procedure EP(x, y: Integer; K: TEKind; const Tag: string; const Ref: string = '');
begin
  EPlace(x, y, K);
  EGrid[x, y].Tag := Tag;
  EGrid[x, y].Ref := Ref;
end;

{ the supply at (xs, y0) and the two rails: L down column xl, N down column xn, to row y1 }
procedure Ladder(xl, xn, xs, y0, y1: Integer);
begin
  EWireLine(xl, y0, xs - 1, y0);
  EWireLine(xs + 1, y0, xn, y0);
  EWireLine(xl, y0, xl, y1);
  EWireLine(xn, y0, xn, y1);
  EP(xs, y0, ekAC, '230VAC');
end;

{ a seal-in branch on row y+1 around the cells xa..xb of row y, with a NO contact of Tag }
procedure SealIn(xa, xb, y: Integer; const Tag: string);
begin
  EWireLine(xa - 1, y, xa - 1, y + 1);
  EWireLine(xa - 1, y + 1, xb + 1, y + 1);
  EWireLine(xb + 1, y + 1, xb + 1, y);
  EP((xa + xb) div 2, y + 1, ekNO, Tag);
end;

function Eq2(Kind: Integer; X, Y, W, H: Single; const Name: string; St: Integer): Integer;
begin
  Result := AddEquip(Kind, X, Y);
  Equips[Result].W := W;
  Equips[Result].H := H;
  Equips[Result].Name := Name;
  Equips[Result].State := St;
end;

{ the layers of an electrical example: Process, Notes, Equipment, Electrical }
procedure ElecLayers;
begin
  Pages[PAGE_PLANT].NLayers := 4;
  Pages[PAGE_PLANT].Layers[2].Name := 'Equipment';
  Pages[PAGE_PLANT].Layers[3].Name := 'Electrical';
end;

{ 10. The well pump circuit: Q1, F1 and an E-Stop protect it; selector SA1
      (1 OFF / 2 HAND / 3 AUTO); in AUTO the pool's float LS1 (on when low,
      off when high) and the well's float LS2 (dry-run protection) run the
      pump through contactor KM1; overload OL1; run and fault lamps. }
procedure Example10;
var
  e: Integer;
begin
  ElecLayers;
  CurLayer := LAYER_PROCESS;
  PipeLine(8, 31, 8, 8, 3);
  PipeLine(8, 8, 16, 8, 3);
  PipeLine(16, 8, 16, 10, 3);
  Device(8, 29, ckBlower, 95, 3);
  Device(16, 10, ckDrop, 100);

  CurLayer := 2;
  e := Eq2(EQ_WELL, 32, 612, 104, 200, 'Well01', EQS_STOP);
  Equips[e].Level := 80;
  e := Eq2(EQ_PUMP, 140, 728, 104, 56, 'Pump01', EQS_STOP);
  Equips[e].LinkX := 8;
  Equips[e].LinkY := 29;
  Equips[e].Level := 80;
  e := Eq2(EQ_POOL, 300, 716, 210, 96, 'Pool01', EQS_STOP);
  Equips[e].Level := 20;
  e := Eq2(EQ_PANEL, 540, 12, 504, 456, 'Panel01 - well pump', EQS_STOP);
  e := Eq2(EQ_LEGEND, 24, 24, 232, 136, 'Legend', EQS_STOP);

  CurLayer := 3;
  Ladder(24, 41, 32, 3, 18);
  EP(24, 4, ekBreaker, 'Q1');
  { power: KM1 main contact, overload, the pump motor }
  EWireLine(24, 6, 41, 6);
  EP(28, 6, ekNO, 'KM1');
  EP(31, 6, ekOL, 'OL1', 'Pump01');
  EP(36, 6, ekMotor, 'M1', 'Pump01');
  { control: fuse and E-Stop on the rail }
  EP(24, 8, ekFuse, 'F1');
  EP(24, 9, ekEStop, 'ES1');
  { HAND: SA1 in position 2 }
  EWireLine(24, 11, 41, 11);
  EP(27, 11, ekSelector, 'SA1');
  EGrid[27, 11].NPos := 3;
  EGrid[27, 11].Pos := 2;
  EP(34, 11, ekNC, 'OL1');
  EP(38, 11, ekContactor, 'KM1');
  { AUTO: SA1 in position 3, the pool needs water and the well has some }
  EWireLine(24, 13, 33, 13);
  EWireLine(33, 13, 33, 11);
  EP(27, 13, ekSelector, 'SA1');
  EGrid[27, 13].NPos := 3;
  EGrid[27, 13].Pos := 3;
  EP(29, 13, ekFloat, 'LS1', 'Pool01');
  EGrid[29, 13].P1 := 30;
  EGrid[29, 13].P2 := 80;
  EP(32, 13, ekFloat, 'LS2', 'Well01');
  EGrid[32, 13].Pos := 1;
  EGrid[32, 13].P1 := 10;
  EGrid[32, 13].P2 := 25;
  ESetSelectorPos(27, 11, 2);   { start in AUTO }
  { lamps }
  EWireLine(24, 16, 41, 16);
  EP(30, 16, ekNO, 'KM1');
  EP(38, 16, ekLamp, 'H1');
  EWireLine(24, 18, 41, 18);
  EP(30, 18, ekNO, 'OL1');
  EP(38, 18, ekLamp, 'H2');
  EGrid[38, 18].Pos := 1;

  Notes;
  AddLabel(552, 486, 'WELL PUMP CIRCUIT'#10'SA1: 1 OFF / 2 HAND / 3 AUTO (click it).'#10 +
    'AUTO: LS1 starts the pump when the pool'#10'is low (30%) and stops it when high (80%);'#10 +
    'LS2 stops it when the well runs dry.'#10'Red wires: L (live), blue: N.');
end;

{ 11. Start / stop (direct on line) of a belt conveyor: stop button SB0 (NC),
      start button SB1 (NO) with the KM1 seal-in contact, overload, E-Stop,
      run / stop / fault lamps. }
procedure Example11;
var
  e: Integer;
begin
  ElecLayers;
  CurLayer := LAYER_PROCESS;
  Feeder(5, 3, 0, 0, 0, 2600, 0, 30);
  PipeLine(5, 3, 5, 9, 3);
  Device(5, 9, ckDrop, 100);
  FloorBucket(17, 150, 90);

  CurLayer := 2;
  e := Eq2(EQ_BELT, 48, 300, 336, 48, 'Belt01', EQS_STOP);
  Equips[e].Level := 60;
  e := Eq2(EQ_PANEL, 540, 12, 504, 504, 'Panel01 - start / stop', EQS_STOP);
  e := Eq2(EQ_LEGEND, 24, 440, 232, 136, 'Legend', EQS_STOP);

  CurLayer := 3;
  Ladder(24, 41, 32, 3, 20);
  EP(24, 4, ekBreaker, 'Q1');
  EWireLine(24, 6, 41, 6);
  EP(28, 6, ekNO, 'KM1');
  EP(31, 6, ekOL, 'OL1', 'Belt01');
  EP(36, 6, ekMotor, 'M1', 'Belt01');
  EP(24, 8, ekFuse, 'F1');
  EP(24, 9, ekEStop, 'ES1');
  { stop - start (sealed in by KM1) - overload - contactor }
  EWireLine(24, 11, 41, 11);
  EP(27, 11, ekPBNC, 'SB0');
  EP(30, 11, ekPBNO, 'SB1');
  SealIn(30, 30, 11, 'KM1');
  EP(34, 11, ekNC, 'OL1');
  EP(38, 11, ekContactor, 'KM1');
  { lamps: run, stop, fault }
  EWireLine(24, 14, 41, 14);
  EP(30, 14, ekNO, 'KM1');
  EP(38, 14, ekLamp, 'H1');
  EWireLine(24, 16, 41, 16);
  EP(30, 16, ekNC, 'KM1');
  EP(38, 16, ekLamp, 'H2');
  EGrid[38, 16].Pos := 1;
  EWireLine(24, 18, 41, 18);
  EP(30, 18, ekNO, 'OL1');
  EP(38, 18, ekLamp, 'H3');
  EGrid[38, 18].Pos := 2;
  EWireLine(24, 20, 41, 20);
  EP(30, 20, ekNO, 'OL1');
  EP(38, 20, ekBuzzer, 'HA1');

  Notes;
  AddLabel(552, 534, 'START / STOP (DOL)'#10'Hold SB1 (Select tool) to start: KM1'#10 +
    'seals itself in. SB0 or ES1 stops.'#10'H1 run, H2 stop, H3 overload.');
end;

{ 12. Star-delta starter of a big blower: KM1 main, KM2 star, KM3 delta,
      timer T1 switches from star to delta; KM2 / KM3 interlock each other. }
procedure Example12;
var
  e: Integer;
begin
  ElecLayers;
  CurLayer := LAYER_PROCESS;
  Feeder(3, 27, 0, 0, 200, 2600, 30, 70);
  PipeLine(3, 27, 12, 27, 3);
  Device(7, 27, ckBlower, 100, 0);
  PipeLine(12, 27, 12, 6, 3);
  PipeLine(12, 6, 18, 6, 3);
  PipeLine(18, 6, 18, 20, 3);
  Device(18, 20, ckDrop, 100);
  FloorBucket(18, 140, 90);

  CurLayer := 2;
  e := Eq2(EQ_BLOWER, 120, 560, 120, 112, 'Blower01', EQS_STOP);
  Equips[e].LinkX := 7;
  Equips[e].LinkY := 27;
  e := Eq2(EQ_PANEL, 552, 12, 492, 552, 'Panel01 - star-delta', EQS_STOP);
  e := Eq2(EQ_LEGEND, 24, 24, 232, 136, 'Legend', EQS_STOP);

  CurLayer := 3;
  Ladder(24, 42, 33, 2, 21);
  EP(24, 3, ekBreaker, 'Q1');
  { power: KM1 - OL1, then KM2 (star) or KM3 (delta) to the motor windings }
  EWireLine(24, 5, 42, 5);
  EP(26, 5, ekNO, 'KM1');
  EP(28, 5, ekOL, 'OL1', 'Blower01');
  EP(32, 5, ekNO, 'KM2');
  EP(36, 5, ekMotor, 'M1-Y', 'Blower01');
  EWireLine(30, 5, 30, 7);
  EWireLine(30, 7, 42, 7);
  EP(32, 7, ekNO, 'KM3');
  EP(36, 7, ekMotor, 'M1-D', 'Blower01');
  EP(24, 8, ekFuse, 'F1');
  EP(24, 9, ekEStop, 'ES1');
  { KM1: stop, start sealed in, overload }
  EWireLine(24, 11, 42, 11);
  EP(26, 11, ekPBNC, 'SB0');
  EP(28, 11, ekPBNO, 'SB1');
  SealIn(28, 28, 11, 'KM1');
  EP(32, 11, ekNC, 'OL1');
  EP(40, 11, ekContactor, 'KM1');
  { from the bus at column 34: T1, KM2 (star), KM3 (delta) }
  EWireLine(34, 11, 34, 17);
  EWireLine(34, 13, 42, 13);
  EP(40, 13, ekTimer, 'T1');
  EGrid[40, 13].P1 := 5;
  EWireLine(34, 15, 42, 15);
  EP(36, 15, ekNC, 'T1');
  EP(38, 15, ekNC, 'KM3');
  EP(40, 15, ekContactor, 'KM2');
  EWireLine(34, 17, 42, 17);
  EP(36, 17, ekNO, 'T1');
  EP(38, 17, ekNC, 'KM2');
  EP(40, 17, ekContactor, 'KM3');
  { lamps: star, delta }
  EWireLine(24, 19, 42, 19);
  EP(30, 19, ekNO, 'KM2');
  EP(40, 19, ekLamp, 'H1');
  EGrid[40, 19].Pos := 2;
  EWireLine(24, 21, 42, 21);
  EP(30, 21, ekNO, 'KM3');
  EP(40, 21, ekLamp, 'H2');

  Notes;
  AddLabel(560, 584, 'STAR-DELTA STARTER'#10'Hold SB1: KM1 + KM2 start the motor in'#10 +
    'star (H1); after T1 (5 s) KM2 drops and'#10'KM3 runs it in delta (H2).'#10 +
    'KM2 and KM3 lock each other out.');
end;

{ 13. A conveyor line: the belt (downstream) starts first, then after T1 the
      roller conveyor through a drive (VFD) at 70% speed; one stop for both. }
procedure Example13;
var
  e: Integer;
begin
  ElecLayers;
  CurLayer := LAYER_PROCESS;
  Feeder(3, 3, 0, 0, 0, 2600, 0, 30);
  PipeLine(3, 3, 3, 6, 3);
  Device(3, 6, ckDrop, 100);
  FloorBucket(10, 150, 90);

  CurLayer := 2;
  e := Eq2(EQ_CONVEYOR, 24, 220, 300, 48, 'Conveyor01', EQS_STOP);
  e := Eq2(EQ_BELT, 264, 440, 240, 48, 'Belt01', EQS_STOP);
  Equips[e].Flip := True;
  Equips[e].Level := 70;
  e := Eq2(EQ_PANEL, 552, 12, 492, 516, 'Panel01 - conveyor line', EQS_STOP);
  e := Eq2(EQ_LEGEND, 560, 580, 232, 136, 'Legend', EQS_STOP);

  CurLayer := 3;
  Ladder(24, 42, 33, 2, 20);
  EP(24, 3, ekBreaker, 'Q1');
  { power: KM2 - OL2 - belt motor; KM1 - OL1 - drive of the roller conveyor }
  EWireLine(24, 5, 42, 5);
  EP(26, 5, ekNO, 'KM2');
  EP(28, 5, ekOL, 'OL2', 'Belt01');
  EP(36, 5, ekMotor, 'M2', 'Belt01');
  EWireLine(24, 7, 42, 7);
  EP(26, 7, ekNO, 'KM1');
  EP(28, 7, ekOL, 'OL1', 'Conveyor01');
  EP(36, 7, ekDrive, 'U1', 'Conveyor01');
  EGrid[36, 7].P1 := 70;
  EP(24, 9, ekFuse, 'F1');
  EP(24, 10, ekEStop, 'ES1');
  { start / stop: KM2 (belt) sealed in }
  EWireLine(24, 12, 42, 12);
  EP(26, 12, ekPBNC, 'SB0');
  EP(28, 12, ekPBNO, 'SB1');
  SealIn(28, 28, 12, 'KM2');
  EP(32, 12, ekNC, 'OL2');
  EP(40, 12, ekContactor, 'KM2');
  { T1 and KM1 from the bus at column 34 }
  EWireLine(34, 12, 34, 16);
  EWireLine(34, 14, 42, 14);
  EP(40, 14, ekTimer, 'T1');
  EGrid[40, 14].P1 := 3;
  EWireLine(34, 16, 42, 16);
  EP(36, 16, ekNO, 'T1');
  EP(38, 16, ekNC, 'OL1');
  EP(40, 16, ekContactor, 'KM1');
  { lamps }
  EWireLine(24, 18, 42, 18);
  EP(30, 18, ekNO, 'KM2');
  EP(40, 18, ekLamp, 'H1');
  EWireLine(24, 20, 42, 20);
  EP(30, 20, ekNO, 'KM1');
  EP(40, 20, ekLamp, 'H2');

  Notes;
  AddLabel(560, 536, 'CONVEYOR LINE'#10'Hold SB1: the belt (KM2) starts first,'#10 +
    'T1 (3 s) later the roller conveyor (KM1)'#10'through drive U1 at 70%. SB0 stops both.');
end;

{ 14. Meters: potentiometer RV1 sets drive U1's speed (Pump01); CT1 and CT2
      measure the pump and a direct-on-line motor; gauges and displays. }
procedure Example14;
var
  e: Integer;
begin
  ElecLayers;
  CurLayer := LAYER_PROCESS;
  PipeLine(8, 31, 8, 8, 3);
  PipeLine(8, 8, 16, 8, 3);
  PipeLine(16, 8, 16, 10, 3);
  Device(8, 29, ckBlower, 95, 3);
  Device(16, 10, ckDrop, 100);

  CurLayer := 2;
  e := Eq2(EQ_WELL, 32, 612, 104, 200, 'Well01', EQS_STOP);
  Equips[e].Level := 90;
  e := Eq2(EQ_PUMP, 140, 728, 104, 56, 'Pump01', EQS_STOP);
  Equips[e].LinkX := 8;
  Equips[e].LinkY := 29;
  e := Eq2(EQ_POOL, 300, 716, 210, 96, 'Pool01', EQS_STOP);
  Equips[e].Level := 10;
  e := Eq2(EQ_MOTOR, 330, 440, 96, 48, 'Motor01', EQS_STOP);
  e := Eq2(EQ_PANEL, 540, 12, 504, 516, 'Panel01 - meters', EQS_STOP);
  { the meters }
  e := Eq2(EQ_GAUGE, 556, 552, 128, 128, 'Pump A', EQS_STOP);
  Equips[e].Src := 'CT1';
  Equips[e].RMax := 10;
  e := Eq2(EQ_GAUGE, 700, 552, 128, 128, 'Motor A', EQS_STOP);
  Equips[e].Src := 'CT2';
  Equips[e].RMax := 40;
  e := Eq2(EQ_DIGITAL, 852, 556, 156, 52, 'Pump speed', EQS_STOP);
  Equips[e].Src := 'RV1';
  e := Eq2(EQ_DIGITAL, 852, 638, 156, 52, 'Pool level', EQS_STOP);
  Equips[e].Src := 'Pool01';
  Equips[e].RMax := 90;
  e := Eq2(EQ_DIGITAL, 852, 720, 156, 52, 'Supply V', EQS_STOP);
  Equips[e].Src := '230VAC';
  Equips[e].RMin := 200;
  Equips[e].RMax := 250;

  CurLayer := 3;
  Ladder(24, 42, 33, 2, 17);
  EP(24, 3, ekBreaker, 'Q1');
  { power: KM1 - CT1 - OL1 - drive U1 (pump); KM2 - CT2 - OL2 - motor M2 }
  EWireLine(24, 5, 42, 5);
  EP(26, 5, ekNO, 'KM1');
  EP(29, 5, ekCT, 'CT1');
  EP(32, 5, ekOL, 'OL1', 'Pump01');
  EP(37, 5, ekDrive, 'U1', 'Pump01');
  EGrid[37, 5].Src := 'RV1';
  EWireLine(24, 7, 42, 7);
  EP(26, 7, ekNO, 'KM2');
  EP(29, 7, ekCT, 'CT2');
  EP(32, 7, ekOL, 'OL2', 'Motor01');
  EGrid[32, 7].P1 := 12;
  EP(37, 7, ekMotor, 'M2', 'Motor01');
  EGrid[37, 7].P1 := 5;
  EP(24, 9, ekFuse, 'F1');
  { control: S1 / S2 switches run the contactors }
  EWireLine(24, 11, 42, 11);
  EP(27, 11, ekSwitch, 'S1');
  EGrid[27, 11].On := True;
  EP(32, 11, ekNC, 'OL1');
  EP(40, 11, ekContactor, 'KM1');
  EWireLine(24, 13, 42, 13);
  EP(27, 13, ekSwitch, 'S2');
  EP(32, 13, ekNC, 'OL2');
  EP(40, 13, ekContactor, 'KM2');
  EWireLine(24, 15, 42, 15);
  EP(30, 15, ekNO, 'KM1');
  EP(40, 15, ekLamp, 'H1');
  EWireLine(24, 17, 42, 17);
  EP(30, 17, ekNO, 'KM2');
  EP(40, 17, ekLamp, 'H2');
  { the speed potentiometer on the door }
  EP(28, 20, ekPot, 'RV1');
  EGrid[28, 20].P1 := 60;

  Notes;
  AddLabel(196, 260, 'METERS, POT & CT'#10'RV1 (mouse wheel) sets the pump speed.'#10 +
    'CT1 / CT2 measure the currents.'#10'Click S2: Motor01 starts direct on line,'#10'Motor A shows the inrush.');
end;

{ ---------------------------------------------------------------- fluid power examples }

{ a fluid power part on the lines at x,y, turned Dir quarter turns }
procedure FP(x, y: Integer; K: TFKind; const Tag: string; Dir: Integer = 0; const Ref: string = '');
begin
  FPlace(x, y, K, Dir);
  FGrid[x, y].Tag := Tag;
  FGrid[x, y].Ref := Ref;
end;

{ the layers of a fluid power example: Process, Notes, Equipment, the circuit (and Electrical) }
procedure FluidLayers(const FluidName: string; Electrical: Boolean);
begin
  Pages[PAGE_PLANT].NLayers := 4 + Ord(Electrical);
  Pages[PAGE_PLANT].Layers[2].Name := 'Equipment';
  Pages[PAGE_PLANT].Layers[3].Name := FluidName;
  if Electrical then Pages[PAGE_PLANT].Layers[4].Name := 'Electrical';
end;

{ the air supply along row y from column x0 to x1: compressor C1, receiver R1, FRL1 (6 bar), gauge PG1 }
procedure AirSupply(x0, y, x1: Integer; const CompRef: string);
begin
  FLineRun(x0, y, x1, y);
  FP(x0, y, fkCompressor, 'C1', 0, CompRef);
  FP(x0 + 3, y, fkReceiver, 'R1');
  FP(x0 + 6, y, fkFRL, 'FRL1');
  FP(x0 + 7, y - 1, fkGauge, 'PG1');
end;

{ the oil supply along row y: pump P1 (120 bar), relief RV1 (100 bar) down to a tank, gauge PG1 }
procedure OilSupply(x0, y, x1: Integer; const UnitRef: string);
begin
  FLineRun(x0, y, x1, y);
  FLineRun(x0 + 3, y, x0 + 3, y + 1);
  FP(x0 + 3, y + 3, fkTank, 'T1');
  FP(x0 + 3, y + 2, fkRelief, 'RV1', 1);
  FP(x0, y, fkHPump, 'P1', 0, UnitRef);
  FP(x0 + 6, y - 1, fkGauge, 'PG1');
end;

{ a double-acting cylinder (rod up) at (vx - 2, cy) on a 4- / 5-port valve at (vx, vy) whose P comes down to row ys;
  with Throttles the two lines get flow controls; R goes to Exhaust (a silencer or a tank) above the valve }
procedure ValveCylDA(vx, vy, cy, ys: Integer; VK: TFKind; const VTag, CTag, CRef: string; Exhaust: TFKind;
  Throttles: Boolean);
begin
  FLineRun(vx, vy + 1, vx, ys);
  FLineRun(vx - 1, vy, vx - 2, vy);
  FLineRun(vx - 2, vy, vx - 2, cy + 1);
  FLineRun(vx + 1, vy, vx + 2, vy);
  FLineRun(vx + 2, vy, vx + 2, cy);
  FLineRun(vx + 2, cy, vx - 1, cy);
  FP(vx, vy - 1, Exhaust, '');
  FP(vx, vy, VK, VTag);
  FP(vx - 2, cy, fkCylDA, CTag, 3, CRef);
  if Throttles then
  begin
    FP(vx - 2, (vy + cy) div 2, fkThrottle, 'FC1', 1);
    FP(vx + 2, (vy + cy) div 2, fkThrottle, 'FC2', 1);
  end;
end;

{ 15. A double-acting cylinder on a manual 5/2 valve with flow controls, and a
      single-acting cylinder on a push-button 3/2 valve. }
procedure Example15;
var
  e: Integer;
begin
  FluidLayers('Pneumatic', False);
  CurLayer := 2;
  e := Eq2(EQ_COMPRESSOR, 40, 600, 200, 112, 'Comp01', EQS_STOP);
  Equips[e].Src := 'R1';
  Equips[e].RMax := 10;
  e := Eq2(EQ_CYLINDER, 40, 300, 320, 56, 'Cyl01', EQS_STOP);
  e := Eq2(EQ_CYLINDER, 420, 260, 56, 220, 'Cyl02', EQS_STOP);
  e := Eq2(EQ_DIGITAL, 300, 640, 156, 52, 'Supply bar', EQS_STOP);
  Equips[e].Src := 'PG1';
  Equips[e].RMax := 7;
  CurLayer := 3;
  AirSupply(24, 22, 42, 'Comp01');
  ValveCylDA(33, 18, 10, 22, fkV52, 'V1', 'A', 'Cyl01', fkSilencer, True);
  { the single-acting cylinder: 3/2 push button }
  FLineRun(39, 19, 39, 22);
  FLineRun(38, 18, 37, 18);
  FLineRun(37, 18, 37, 11);
  FP(39, 17, fkSilencer, '');
  FP(39, 18, fkV32, 'V2');
  FGrid[39, 18].Act := 1;
  FP(37, 10, fkCylSA, 'B', 3, 'Cyl02');
  Notes;
  AddFrame(23 * CELL, 7 * CELL, 20 * CELL, 17 * CELL, 'PNEUMATIC CIRCUIT');
  AddLabel(24, 120, 'PNEUMATIC CYLINDERS'#10'Click V1 (Select tool) to switch it:'#10 +
    'cylinder A goes out / in, slowed by'#10'FC1 / FC2 (mouse wheel over them).'#10'Hold V2: cylinder B goes out.');
end;

{ 16. Electro-pneumatic gate: cylinder A on a double-solenoid 5/2 valve opens a
      hopper gate; Y1 out when A0, timer T1 holds it open, Y2 in. }
procedure Example16;
var
  e: Integer;
begin
  FluidLayers('Pneumatic', True);
  CurLayer := LAYER_PROCESS;
  Feeder(8, 2, 0, 0, 0, 2600, 0, 70);
  PipeLine(8, 2, 8, 6, 3);
  Device(8, 6, ckDrop, 100);
  MakePipe(8, 13, 3);
  SetKind(8, 13, ckHopper);
  PipeLine(8, 13, 8, 18, 3);
  Device(8, 18, ckDrop, 100);
  FloorBucket(8, 160, 90);

  CurLayer := 2;
  e := Eq2(EQ_SLIDE, 172, 336, 56, 56, 'Gate01', EQS_STOP);
  Equips[e].LinkX := 8;
  Equips[e].LinkY := 13;
  e := Eq2(EQ_COMPRESSOR, 300, 640, 200, 112, 'Comp01', EQS_STOP);
  Equips[e].Src := 'R1';
  Equips[e].RMax := 10;

  CurLayer := 3;
  AirSupply(24, 30, 42, 'Comp01');
  ValveCylDA(33, 26, 19, 30, fkV52, 'V1', 'A', 'Gate01', fkSilencer, True);
  FGrid[33, 26].Act := 3;
  FGrid[33, 26].SolA := 'Y1';
  FGrid[33, 26].SolB := 'Y2';

  CurLayer := 4;
  Ladder(24, 42, 33, 1, 14);
  EP(24, 2, ekBreaker, 'Q1');
  EP(24, 3, ekFuse, 'F1');
  EWireLine(24, 5, 42, 5);
  EP(26, 5, ekPBNC, 'SB0');
  EP(28, 5, ekPBNO, 'SB1');
  SealIn(28, 28, 5, 'K1');
  EP(40, 5, ekRelay, 'K1');
  EWireLine(24, 8, 42, 8);
  EP(27, 8, ekNO, 'K1');
  EP(30, 8, ekNO, 'A0');
  EP(40, 8, ekSolenoid, 'Y1');
  EWireLine(24, 10, 42, 10);
  EP(27, 10, ekNO, 'A1');
  EP(40, 10, ekTimer, 'T1');
  EGrid[40, 10].P1 := 2;
  EWireLine(24, 12, 42, 12);
  EP(27, 12, ekNO, 'T1');
  EP(40, 12, ekSolenoid, 'Y2');
  EWireLine(24, 14, 42, 14);
  EP(27, 14, ekNO, 'A1');
  EP(40, 14, ekLamp, 'H1');

  Notes;
  AddLabel(24, 470, 'ELECTRO-PNEUMATIC GATE'#10'Hold SB1: K1 runs the cycle. Retracted'#10 +
    '(A0) gives Y1: A goes out and opens'#10'Gate01; at A1 T1 counts 2 s, then Y2'#10 +
    'brings A back. Again and again until SB0.');
end;

{ 17. Pneumatic logic: S1 AND S2 drive cylinder A, S3 OR S4 drive cylinder B. }
procedure Example17;
var
  e: Integer;
  procedure Valve32(vx: Integer; const Tag: string);
  begin
    FLineRun(vx, 21, vx, 24);
    FP(vx, 19, fkSilencer, '');
    FP(vx, 20, fkV32, Tag);
  end;
begin
  FluidLayers('Pneumatic', False);
  CurLayer := 2;
  e := Eq2(EQ_CYLINDER, 120, 220, 56, 240, 'CylAND', EQS_STOP);
  e := Eq2(EQ_CYLINDER, 300, 220, 56, 240, 'CylOR', EQS_STOP);
  e := Eq2(EQ_COMPRESSOR, 40, 640, 200, 112, 'Comp01', EQS_STOP);
  CurLayer := 3;
  FLineRun(16, 24, 42, 24);
  FP(16, 24, fkCompressor, 'C1', 0, 'Comp01');
  FP(19, 24, fkReceiver, 'R1');
  FP(22, 24, fkFRL, 'FRL1');
  { AND }
  FLineRun(26, 20, 26, 14);
  FLineRun(26, 14, 29, 14);
  FLineRun(32, 20, 32, 14);
  FLineRun(32, 14, 31, 14);
  FLineRun(30, 13, 30, 11);
  Valve32(27, 'S1');
  Valve32(33, 'S2');
  FP(30, 14, fkAndValve, 'AND1');
  FP(30, 10, fkCylSA, 'A', 3, 'CylAND');
  { OR }
  FLineRun(35, 20, 35, 14);
  FLineRun(35, 14, 37, 14);
  FLineRun(40, 20, 40, 14);
  FLineRun(40, 14, 39, 14);
  FLineRun(38, 13, 38, 11);
  Valve32(36, 'S3');
  Valve32(41, 'S4');
  FP(38, 14, fkShuttle, 'OR1');
  FP(38, 10, fkCylSA, 'B', 3, 'CylOR');
  Notes;
  AddLabel(24, 90, 'PNEUMATIC LOGIC'#10'Click the 3/2 valves to switch them.'#10 +
    'A goes out only with S1 AND S2,'#10'B with S3 OR S4.');
end;

{ 18. The compressor is switched by pressure switch PS1 through contactor KM1;
      an air motor drives a belt conveyor through flow control FC1. }
procedure Example18;
var
  e: Integer;
begin
  FluidLayers('Pneumatic', True);
  CurLayer := LAYER_PROCESS;
  Feeder(4, 6, 0, 0, 0, 2600, 0, 30);
  PipeLine(4, 6, 4, 9, 3);
  Device(4, 9, ckDrop, 100);
  FloorBucket(16, 150, 90);

  CurLayer := 2;
  e := Eq2(EQ_BELT, 24, 300, 336, 48, 'Belt01', EQS_STOP);
  e := Eq2(EQ_COMPRESSOR, 40, 600, 200, 112, 'Comp01', EQS_STOP);
  Equips[e].Src := 'R1';
  Equips[e].RMax := 10;
  e := Eq2(EQ_DIGITAL, 300, 480, 156, 52, 'Receiver bar', EQS_STOP);
  Equips[e].Src := 'R1';
  Equips[e].RMin := 5;
  Equips[e].RMax := 9;

  CurLayer := 3;
  FLineRun(24, 28, 39, 28);
  FP(24, 28, fkCompressor, 'C1', 0, 'Comp01');
  FGrid[24, 28].P1 := 9;
  FGrid[24, 28].SolA := 'KM1';
  FP(27, 28, fkReceiver, 'R1');
  FP(27, 27, fkPSwitch, 'PS1');
  FGrid[27, 27].Act := 1;
  FGrid[27, 27].P1 := 8;
  FGrid[27, 27].P2 := 6;
  FP(30, 27, fkGauge, 'PG1');
  FP(33, 28, fkFRL, 'FRL1');
  FLineRun(36, 25, 36, 28);
  FLineRun(35, 24, 35, 19);
  FP(36, 24, fkV32, 'V1');
  FGrid[36, 24].Sel := 1;
  FP(35, 21, fkThrottle, 'FC1', 1);
  FP(35, 18, fkAirMotor, 'AM1', 3, 'Belt01');

  CurLayer := 4;
  Ladder(24, 42, 33, 2, 9);
  EP(24, 3, ekBreaker, 'Q1');
  EWireLine(24, 5, 42, 5);
  EP(28, 5, ekNO, 'PS1');
  EP(40, 5, ekContactor, 'KM1');
  EWireLine(24, 7, 42, 7);
  EP(28, 7, ekNO, 'KM1');
  EP(40, 7, ekLamp, 'H1');
  EWireLine(24, 9, 42, 9);
  EP(28, 9, ekNC, 'KM1');
  EP(40, 9, ekLamp, 'H2');
  EGrid[40, 9].Pos := 2;

  Notes;
  AddLabel(24, 400, 'COMPRESSOR CONTROL & AIR MOTOR'#10'PS1 closes below 6 bar: KM1 runs C1'#10 +
    'until 8 bar. The air motor AM1 drives'#10'Belt01; FC1 (wheel) sets its speed.');
end;

{ 19. Hydraulic power unit, relief valve, manual 4/3 valve (tandem centre) and a lifting cylinder. }
procedure Example19;
var
  e: Integer;
begin
  FluidLayers('Hydraulic', False);
  CurLayer := 2;
  e := Eq2(EQ_HPU, 40, 620, 200, 120, 'HPU01', EQS_STOP);
  Equips[e].Src := 'PG1';
  Equips[e].RMax := 160;
  e := Eq2(EQ_CYLINDER, 200, 180, 72, 300, 'Lift01', EQS_STOP);
  e := Eq2(EQ_GAUGE, 320, 300, 120, 120, 'System bar', EQS_STOP);
  Equips[e].Src := 'PG1';
  Equips[e].RMax := 160;
  CurLayer := 3;
  OilSupply(24, 26, 36, 'HPU01');
  ValveCylDA(31, 22, 12, 26, fkV43, 'V1', 'A', 'Lift01', fkTank, False);
  Notes;
  AddLabel(24, 90, 'HYDRAULIC LIFT'#10'Click V1 to step it: 0 centre (the pump'#10 +
    'unloads to tank), 1 up, 2 down.'#10'RV1 limits the pressure to 100 bar.');
end;

{ 20. Electro-hydraulic press: Y1 down until A1, then K2 / Y2 up until A0. }
procedure Example20;
var
  e: Integer;
begin
  FluidLayers('Hydraulic', True);
  CurLayer := 2;
  e := Eq2(EQ_HPU, 40, 620, 200, 120, 'HPU01', EQS_STOP);
  Equips[e].Src := 'PG1';
  Equips[e].RMax := 160;
  e := Eq2(EQ_CYLINDER, 400, 170, 80, 330, 'Press01', EQS_STOP);
  e := Eq2(EQ_GAUGE, 220, 300, 120, 120, 'Press bar', EQS_STOP);
  Equips[e].Src := 'PG1';
  Equips[e].RMax := 160;
  CurLayer := 3;
  OilSupply(24, 26, 36, 'HPU01');
  ValveCylDA(31, 22, 12, 26, fkV43, 'V1', 'A', 'Press01', fkTank, False);
  FGrid[31, 22].Act := 2;
  FGrid[31, 22].SolA := 'Y1';
  FGrid[31, 22].SolB := 'Y2';
  CurLayer := 4;
  Ladder(24, 42, 33, 1, 10);
  EP(24, 2, ekBreaker, 'Q1');
  EP(24, 3, ekFuse, 'F1');
  EWireLine(24, 4, 42, 4);
  EP(26, 4, ekPBNC, 'SB0');
  EP(28, 4, ekPBNO, 'SB1');
  SealIn(28, 28, 4, 'K1');
  EP(32, 4, ekNC, 'A1');
  EP(40, 4, ekRelay, 'K1');
  EWireLine(24, 6, 42, 6);
  EP(27, 6, ekNO, 'K1');
  EP(40, 6, ekSolenoid, 'Y1');
  EWireLine(24, 8, 42, 8);
  EP(27, 8, ekNO, 'A1');
  SealIn(27, 27, 8, 'K2');
  EP(32, 8, ekNC, 'A0');
  EP(40, 8, ekRelay, 'K2');
  EWireLine(24, 10, 42, 10);
  EP(27, 10, ekNO, 'K2');
  EP(40, 10, ekSolenoid, 'Y2');
  Notes;
  AddLabel(24, 90, 'ELECTRO-HYDRAULIC PRESS'#10'Hold SB1: K1 / Y1 drive the press down;'#10 +
    'at the bottom (A1) K1 drops, K2 / Y2'#10'take it up until A0. SB0 stops it.');
end;

{ 21. A hydraulic motor drives a conveyor through flow control FC1; an accumulator on the supply. }
procedure Example21;
var
  e: Integer;
begin
  FluidLayers('Hydraulic', False);
  CurLayer := LAYER_PROCESS;
  Feeder(4, 6, 0, 0, 0, 2600, 0, 30);
  PipeLine(4, 6, 4, 9, 3);
  Device(4, 9, ckDrop, 100);
  FloorBucket(15, 150, 90);
  CurLayer := 2;
  e := Eq2(EQ_CONVEYOR, 24, 300, 312, 48, 'Conveyor01', EQS_STOP);
  e := Eq2(EQ_HPU, 40, 620, 200, 120, 'HPU01', EQS_STOP);
  Equips[e].Src := 'PG1';
  Equips[e].RMax := 160;
  CurLayer := 3;
  OilSupply(24, 26, 36, 'HPU01');
  FLineRun(29, 26, 29, 27);
  FP(29, 27, fkAccum, 'AC1');
  FLineRun(31, 23, 31, 26);
  FLineRun(30, 22, 29, 22);
  FLineRun(29, 22, 29, 16);
  FLineRun(29, 14, 29, 13);
  FLineRun(29, 13, 33, 13);
  FLineRun(33, 13, 33, 22);
  FLineRun(33, 22, 32, 22);
  FP(31, 21, fkTank, 'T2');
  FP(31, 22, fkV42, 'V1');
  FGrid[31, 22].Sel := 1;
  FP(29, 19, fkThrottle, 'FC1', 1);
  FP(29, 15, fkHydMotor, 'HM1', 3, 'Conveyor01');
  Notes;
  AddLabel(24, 90, 'HYDRAULIC MOTOR'#10'V1 runs HM1, which drives Conveyor01;'#10 +
    'FC1 (mouse wheel) sets its speed.'#10'AC1 stores oil pressure.');
end;

{ ---------------------------------------------------------------- control examples }

{ 22. Timers and a counter: flasher T1 pulses the slide gate of a sand feeder;
      photo sensor PE1 sees each batch fall; counter CNT1 counts them and stops
      the flasher at 5; SB1 resets it. Off-delay T2 keeps a lamp on after the
      last batch; weight sensor WT1 weighs the bucket. }
procedure Example22;
var
  e: Integer;
begin
  ElecLayers;
  CurLayer := LAYER_PROCESS;
  Feeder(8, 7, 0, 0, 0, 2500, 0, 80);
  PipeLine(8, 7, 8, 10, 3);
  Device(8, 10, ckDrop, 100);
  FloorBucket(8, 170, 120);

  CurLayer := 2;
  e := Eq2(EQ_SLIDE, 216, 216, 64, 64, 'Slide01', EQS_STOP);
  Equips[e].LinkX := 8;
  Equips[e].LinkY := 10;
  e := Eq2(EQ_PANEL, 552, 12, 492, 456, 'Panel01 - batching', EQS_STOP);
  e := Eq2(EQ_DIGITAL, 572, 500, 150, 52, 'Batches', EQS_STOP);
  Equips[e].Src := 'CNT1';
  Equips[e].RMax := 5;
  e := Eq2(EQ_DIGITAL, 740, 500, 150, 52, 'Flasher s', EQS_STOP);
  Equips[e].Src := 'T1';
  Equips[e].RMax := 3;
  e := Eq2(EQ_DIGITAL, 572, 590, 150, 52, 'Bucket kg', EQS_STOP);
  Equips[e].Src := 'WT1';
  Equips[e].RMax := 200;

  CurLayer := 3;
  Ladder(24, 42, 33, 2, 17);
  { T1 flashes (1 s on, 2 s off) while S1 is on and the count is not reached }
  EWireLine(24, 5, 42, 5);
  EP(28, 5, ekSwitch, 'S1');
  EGrid[28, 5].On := True;
  EP(32, 5, ekNC, 'CNT1');
  EP(39, 5, ekTimer, 'T1');
  EGrid[39, 5].Pos := 3;
  EGrid[39, 5].P1 := 1;
  EGrid[39, 5].P2 := 2.5;
  { its pulses open the slide gate through KM1 / M1 }
  EWireLine(24, 7, 42, 7);
  EP(32, 7, ekNO, 'T1');
  EP(39, 7, ekContactor, 'KM1');
  EWireLine(24, 9, 42, 9);
  EP(32, 9, ekNO, 'KM1');
  EP(39, 9, ekMotor, 'M1', 'Slide01');
  { the photo sensor counts each batch that falls past it }
  EWireLine(24, 11, 42, 11);
  EP(32, 11, ekNO, 'PE1');
  EP(39, 11, ekCounter, 'CNT1');
  EGrid[39, 11].P1 := 5;
  EGrid[39, 11].Src := 'SB1';
  EWireLine(24, 13, 42, 13);
  EP(32, 13, ekNO, 'CNT1');
  EP(39, 13, ekLamp, 'H1');
  { off-delay: H2 stays on 3 s after the last pulse }
  EWireLine(24, 15, 42, 15);
  EP(32, 15, ekNO, 'KM1');
  EP(39, 15, ekTimer, 'T2');
  EGrid[39, 15].Pos := 1;
  EGrid[39, 15].P1 := 3;
  EWireLine(24, 17, 42, 17);
  EP(32, 17, ekNO, 'T2');
  EP(39, 17, ekLamp, 'H2');
  EGrid[39, 17].Pos := 2;
  { the sensors and the reset button, on their own }
  EP(8, 12, ekPhoto, 'PE1');
  EP(8, 33, ekWeightTx, 'WT1');
  EP(28, 19, ekPBNO, 'SB1');

  Notes;
  AddLabel(250, 250, 'TIMERS & COUNTER'#10'T1 (flasher) pulses the slide gate:'#10 +
    'one batch of sand per pulse.'#10'PE1 sees each batch, CNT1 counts them.'#10 +
    'At 5, CNT1 stops T1 and lights H1.'#10'Hold SB1 to reset the count.');
end;

{ 23. Sensors and controllers: LT1 measures Pool01, PID controller LIC1 sets the
      speed of Pump01 (drive U1) to hold 60 % while Pump02 drains the pool;
      TT1 measures Heater01, on / off controller TIC1 holds it at 150 C.
      Pressure, flow and speed sensors show on displays; two faceplates. }
procedure Example23;
var
  e: Integer;
begin
  ElecLayers;
  CurLayer := LAYER_PROCESS;
  { Pump01: well -> pool }
  PipeLine(8, 31, 8, 8, 3);
  PipeLine(8, 8, 16, 8, 3);
  PipeLine(16, 8, 16, 10, 3);
  Device(8, 29, ckBlower, 95, 3);
  Device(16, 10, ckDrop, 100);
  { Pump02: pool -> pond }
  PipeLine(22, 31, 22, 22, 3);
  PipeLine(22, 22, 34, 22, 3);
  PipeLine(34, 22, 34, 24, 3);
  Device(22, 29, ckBlower, 95, 3);
  Device(34, 24, ckDrop, 100);

  CurLayer := 2;
  e := Eq2(EQ_WELL, 24, 600, 104, 200, 'Well01', EQS_STOP);
  Equips[e].Level := 90;
  e := Eq2(EQ_PUMP, 132, 744, 104, 56, 'Pump01', EQS_STOP);
  Equips[e].LinkX := 8;
  Equips[e].LinkY := 29;
  e := Eq2(EQ_POOL, 300, 716, 210, 96, 'Pool01', EQS_STOP);
  Equips[e].Level := 30;
  e := Eq2(EQ_PUMP, 516, 744, 104, 56, 'Pump02', EQS_STOP);
  Equips[e].LinkX := 22;
  Equips[e].LinkY := 29;
  Equips[e].Level := 35;
  e := Eq2(EQ_POND, 760, 720, 264, 90, 'Pond01', EQS_STOP);
  Equips[e].Level := 10;
  e := Eq2(EQ_HEATER, 250, 380, 120, 56, 'Heater01', EQS_STOP);
  e := Eq2(EQ_CONTROLLER, 610, 312, 168, 112, 'Level control', EQS_STOP);
  Equips[e].Src := 'LIC1';
  e := Eq2(EQ_CONTROLLER, 800, 312, 168, 112, 'Heater control', EQS_STOP);
  Equips[e].Src := 'TIC1';
  e := Eq2(EQ_DIGITAL, 560, 448, 150, 52, 'Pipe kPa', EQS_STOP);
  Equips[e].Src := 'PT1';
  e := Eq2(EQ_DIGITAL, 720, 448, 150, 52, 'Flow m/s', EQS_STOP);
  Equips[e].Src := 'FT1';
  e := Eq2(EQ_DIGITAL, 880, 448, 150, 52, 'Pump rpm', EQS_STOP);
  Equips[e].Src := 'ST1';
  Equips[e].RMax := 1500;

  CurLayer := 3;
  Ladder(26, 43, 34, 1, 11);
  { LIC1: PID, holds Pool01 at 60 % through the speed of drive U1 }
  EWireLine(26, 3, 43, 3);
  EP(29, 3, ekSwitch, 'S1');
  EGrid[29, 3].On := True;
  EP(40, 3, ekController, 'LIC1');
  EGrid[40, 3].Pos := 2;
  EGrid[40, 3].P1 := 60;
  EGrid[40, 3].P2 := 25;
  EGrid[40, 3].P3 := 8;
  EGrid[40, 3].Src := 'LT1';
  EWireLine(26, 5, 43, 5);
  EP(40, 5, ekDrive, 'U1', 'Pump01');
  EGrid[40, 5].Src := 'LIC1';
  { Pump02 drains the pool all the time }
  EWireLine(26, 7, 43, 7);
  EP(29, 7, ekSwitch, 'S2');
  EGrid[29, 7].On := True;
  EP(40, 7, ekMotor, 'M2', 'Pump02');
  { TIC1: on / off, heats Heater01 up to 150 C }
  EWireLine(26, 9, 43, 9);
  EP(29, 9, ekSwitch, 'S3');
  EGrid[29, 9].On := True;
  EP(40, 9, ekController, 'TIC1');
  EGrid[40, 9].Pos := 0;
  EGrid[40, 9].P1 := 150;
  EGrid[40, 9].P2 := 10;
  EGrid[40, 9].Src := 'TT1';
  EWireLine(26, 11, 43, 11);
  EP(32, 11, ekNO, 'TIC1');
  EP(40, 11, ekMotor, 'M3', 'Heater01');
  { the sensors }
  EP(13, 30, ekLevelTx, 'LT1', 'Pool01');
  EP(16, 16, ekTempTx, 'TT1', 'Heater01');
  EP(8, 20, ekPressTx, 'PT1');
  EP(8, 14, ekFlowTx, 'FT1');
  EP(4, 30, ekSpeedTx, 'ST1', 'Pump01');

  Notes;
  AddLabel(196, 470, 'SENSORS & CONTROL'#10'LT1 -> LIC1 (PID) -> U1: Pump01 holds'#10 +
    'Pool01 at 60% while Pump02 drains it.'#10'TT1 -> TIC1 (on/off): Heater01 at 150 C.');
end;

{ 24. Every page at once: page 1 "Control room" holds the circuit and the
      controller, page 3 "Pump house" the well, pumps and pool, page 4 "Monitor"
      the meters. The pump on page 3 runs from the contactor on page 1; the
      level sensor on page 1 reads the pool on page 3. }
procedure Example24;
var
  e: Integer;
begin
  ElecLayers;
  CurLayer := 2;
  e := Eq2(EQ_PANEL, 180, 96, 492, 440, 'Panel01 - control room', EQS_STOP);
  e := Eq2(EQ_CONTROLLER, 720, 120, 196, 128, 'Pool level', EQS_STOP);
  Equips[e].Src := 'LIC1';
  e := Eq2(EQ_DIGITAL, 720, 290, 196, 56, 'Pool01 %', EQS_STOP);
  Equips[e].Src := 'Pool01';
  e := Eq2(EQ_DIGITAL, 720, 370, 196, 56, 'Well01 %', EQS_STOP);
  Equips[e].Src := 'Well01';
  e := Eq2(EQ_GAUGE, 740, 450, 150, 150, 'Pump A', EQS_STOP);
  Equips[e].Src := 'CT1';
  Equips[e].RMax := 15;

  CurLayer := 3;
  Ladder(8, 26, 17, 5, 19);
  { SB1 starts, SB0 stops: K1 = the system is on }
  EWireLine(8, 8, 26, 8);
  EP(11, 8, ekPBNC, 'SB0');
  EP(14, 8, ekPBNO, 'SB1');
  SealIn(14, 14, 8, 'K1');
  EP(23, 8, ekRelay, 'K1');
  { LIC1: on below 70 % - 10, off above 70 % + 10 }
  EWireLine(8, 11, 26, 11);
  EP(14, 11, ekNO, 'K1');
  EP(23, 11, ekController, 'LIC1');
  EGrid[23, 11].Pos := 0;
  EGrid[23, 11].P1 := 70;
  EGrid[23, 11].P2 := 20;
  EGrid[23, 11].Src := 'LT1';
  EWireLine(8, 13, 26, 13);
  EP(14, 13, ekNO, 'LIC1');
  EP(23, 13, ekContactor, 'KM1');
  { the pump motor is on page 3: the command goes over the plant bus }
  EWireLine(8, 15, 26, 15);
  EP(11, 15, ekNO, 'KM1');
  EP(15, 15, ekCT, 'CT1');
  EP(23, 15, ekMotor, 'M1', 'Pump01');
  EWireLine(8, 17, 26, 17);
  EP(14, 17, ekNO, 'KM1');
  EP(23, 17, ekLamp, 'H1');
  EWireLine(8, 19, 26, 19);
  EP(14, 19, ekNO, 'K1');
  EP(23, 19, ekLamp, 'H2');
  EGrid[23, 19].Pos := 4;
  { the level sensor reads Pool01 on page 3 }
  EP(20, 22, ekLevelTx, 'LT1', 'Pool01');

  Notes;
  AddLabel(196, 560, 'CONTROL ROOM (page 1)'#10'Hold SB1: K1 on. LIC1 runs KM1 below 60%'#10 +
    'and stops it above 80% - the pump is on'#10'page 3, the meters on page 4. Every page'#10 +
    'runs at the same time.');
  Link(196, 680, 'Pump house', False, 2, 2);
  Link(330, 680, 'Monitor', False, 3, 3);
end;

{ pages 3 and 4 of example 24, after its About page }
procedure Example24Pages;
var
  p, e: Integer;
begin
  ParkPage(PAGE_PLANT);
  { page 3: the pump house }
  p := AddPage('Pump house');
  CurPage := p;
  UnparkPage(p);
  Pages[p].NLayers := 2;
  Pages[p].Layers[0].Name := 'Process';
  Pages[p].Layers[1].Name := 'Notes';
  CurLayer := 0;
  PipeLine(8, 31, 8, 8, 3);
  PipeLine(8, 8, 16, 8, 3);
  PipeLine(16, 8, 16, 10, 3);
  Device(8, 29, ckBlower, 95, 3);
  Device(16, 10, ckDrop, 100);
  PipeLine(22, 31, 22, 22, 3);
  PipeLine(22, 22, 34, 22, 3);
  PipeLine(34, 22, 34, 24, 3);
  Device(22, 29, ckBlower, 95, 3);
  Device(34, 24, ckDrop, 100);
  e := Eq2(EQ_WELL, 24, 600, 104, 200, 'Well01', EQS_STOP);
  Equips[e].Level := 90;
  e := Eq2(EQ_PUMP, 132, 744, 104, 56, 'Pump01', EQS_STOP);
  Equips[e].LinkX := 8;
  Equips[e].LinkY := 29;
  Equips[e].Level := 100;
  e := Eq2(EQ_POOL, 300, 716, 210, 96, 'Pool01', EQS_STOP);
  Equips[e].Level := 40;
  { Pump02 drains the pool into the pond all the time }
  e := Eq2(EQ_PUMP, 516, 744, 104, 56, 'Pump02', EQS_RUN);
  Equips[e].LinkX := 22;
  Equips[e].LinkY := 29;
  Equips[e].Level := 30;
  e := Eq2(EQ_POND, 760, 720, 264, 90, 'Pond01', EQS_STOP);
  Equips[e].Level := 10;
  CurLayer := 1;
  AddLabel(400, 120, 'PUMP HOUSE (page 3)'#10'Pump01 has no circuit here: KM1 on page 1'#10 +
    'runs it over the plant bus. Pump02 drains'#10'the pool into the pond all the time.');
  Link(400, 220, 'Control room', False, PAGE_PLANT, 1);
  Link(540, 220, 'Monitor', False, 3, 3);
  CurLayer := 0;
  ParkPage(p);

  { page 4: the monitor }
  p := AddPage('Monitor');
  CurPage := p;
  UnparkPage(p);
  Pages[p].Layers[0].Name := 'Meters';
  CurLayer := 0;
  e := Eq2(EQ_GAUGE, 80, 120, 200, 200, 'Pool01 level', EQS_STOP);
  Equips[e].Src := 'Pool01';
  e := Eq2(EQ_GAUGE, 320, 120, 200, 200, 'Well01 level', EQS_STOP);
  Equips[e].Src := 'Well01';
  e := Eq2(EQ_GAUGE, 560, 120, 200, 200, 'Pump current A', EQS_STOP);
  Equips[e].Src := 'CT1';
  Equips[e].RMax := 15;
  e := Eq2(EQ_CONTROLLER, 800, 140, 196, 128, 'LIC1 faceplate', EQS_STOP);
  Equips[e].Src := 'LIC1';
  e := Eq2(EQ_DIGITAL, 80, 400, 200, 60, 'LT1 %', EQS_STOP);
  Equips[e].Src := 'LT1';
  e := Eq2(EQ_DIGITAL, 320, 400, 200, 60, 'Set point %', EQS_STOP);
  Equips[e].Src := 'LIC1.SP';
  e := Eq2(EQ_DIGITAL, 560, 400, 200, 60, 'Pond01 %', EQS_STOP);
  Equips[e].Src := 'Pond01';
  AddLabel(80, 520, 'MONITOR (page 4)'#10'Every meter here shows a value from another'#10 +
    'page: the pool and well on page 3, the'#10'current and the controller on page 1.');
  Link(80, 620, 'Control room', False, PAGE_PLANT, 1);
  Link(220, 620, 'Pump house', False, 2, 2);
  ParkPage(p);
  CurPage := PAGE_PLANT;
  UnparkPage(PAGE_PLANT);
end;

{ 25. A heat exchanger warms a stream of wet sand: its hot side (140 C in) is
      run by drive U1, whose speed PID controller TIC1 sets to hold the shell
      outlet at 80 C (TT1). Humidity sensor MT1 measures the air by the
      falling stream, MT2 the moisture of the material in the bucket. }
procedure Example25;
var
  e: Integer;
begin
  ElecLayers;
  CurLayer := LAYER_PROCESS;
  Feeder(4, 6, 2500, 0, 0, 900, 10, 60);
  PipeLine(4, 6, 20, 6, 3);
  Device(7, 6, ckBlower, 70, 0);
  PipeLine(20, 6, 20, 10, 3);
  Device(20, 10, ckDrop, 100);
  FloorBucket(20, 200, 140);

  CurLayer := 2;
  e := Eq2(EQ_HEATEX, 240, 124, 168, 64, 'HX01', EQS_RUN);
  Equips[e].LinkX := 13;
  Equips[e].LinkY := 6;
  Equips[e].RMax := 160;
  Equips[e].Level := 50;
  e := Eq2(EQ_CONTROLLER, 660, 220, 168, 112, 'Outlet control', EQS_STOP);
  Equips[e].Src := 'TIC1';
  e := Eq2(EQ_DIGITAL, 560, 380, 150, 52, 'Cold out C', EQS_STOP);
  Equips[e].Src := 'HX01';
  Equips[e].RMax := 150;
  e := Eq2(EQ_DIGITAL, 720, 380, 150, 52, 'Hot out C', EQS_STOP);
  Equips[e].Src := 'HX01.HOT';
  Equips[e].RMax := 150;
  e := Eq2(EQ_DIGITAL, 880, 380, 150, 52, 'Duty kW', EQS_STOP);
  Equips[e].Src := 'HX01.KW';
  Equips[e].RMax := 2000;
  e := Eq2(EQ_DIGITAL, 560, 470, 150, 52, 'Air RH %', EQS_STOP);
  Equips[e].Src := 'MT1';
  e := Eq2(EQ_DIGITAL, 720, 470, 150, 52, 'Moisture %', EQS_STOP);
  Equips[e].Src := 'MT2';

  CurLayer := 3;
  Ladder(24, 42, 33, 2, 6);
  { TIC1: PID, holds the shell outlet at 80 C through the hot flow (drive U1 on HX01) }
  EWireLine(24, 4, 42, 4);
  EP(28, 4, ekSwitch, 'S1');
  EGrid[28, 4].On := True;
  EP(39, 4, ekController, 'TIC1');
  EGrid[39, 4].Pos := 2;
  EGrid[39, 4].P1 := 80;
  EGrid[39, 4].P2 := 60;
  EGrid[39, 4].P3 := 5;
  EGrid[39, 4].Src := 'TT1';
  EWireLine(24, 6, 42, 6);
  EP(39, 6, ekDrive, 'U1', 'HX01');
  EGrid[39, 6].Src := 'TIC1';
  { the sensors }
  EP(13, 9, ekTempTx, 'TT1', 'HX01');
  EP(21, 15, ekHumidTx, 'MT1');
  EP(20, 33, ekHumidTx, 'MT2');
  EGrid[20, 33].Pos := 1;

  Notes;
  AddLabel(250, 250, 'HEAT EXCHANGER & HUMIDITY'#10'Wet sand is blown through the shell of HX01.'#10 +
    'TIC1 (PID) sets its hot flow through U1 to'#10'hold the outlet at 80 C (TT1).'#10 +
    'MT1: the air by the stream (% RH).'#10'MT2: the moisture of the sand in the bucket.');
end;

{ 26. Cooling water: a hot (90 C) stream of wet sand is cooled in HX01 by water
      from cooling tower Tower01, whose return is HX01's tube outlet (a loop).
      PID controller TIC1 (reverse) sets the tower fan through drive U1 to hold
      the stream at 40 C. A second stream (30 C, water and fluff) is cooled in
      HX02 by chilled water from Chiller01 (7 C). pH sensors on both buckets,
      a humidity sensor in the tower's plume. }
procedure Example26;
var
  e: Integer;
begin
  ElecLayers;
  CurLayer := LAYER_PROCESS;
  { line 1: hot wet sand }
  Feeder(3, 4, 2000, 0, 0, 700, 10, 60);
  PipeLine(3, 4, 22, 4, 3);
  Device(6, 4, ckBlower, 45, 0);
  PipeLine(22, 4, 22, 9, 3);
  Device(22, 9, ckDrop, 100);
  FloorBucket(22, 170, 110);
  { line 2: water and fluff }
  Feeder(3, 14, 2000, 0, 300, 0, 10, 35);
  PipeLine(3, 14, 13, 14, 3);
  Device(5, 14, ckBlower, 45, 0);
  PipeLine(13, 14, 13, 18, 3);
  Device(13, 18, ckDrop, 100);
  FloorBucket(13, 200, 130);

  CurLayer := 2;
  e := Eq2(EQ_HEATEX, 168, 60, 216, 80, 'HX01', EQS_RUN);
  Equips[e].LinkX := 11;
  Equips[e].LinkY := 4;
  Equips[e].RMin := 90;
  Equips[e].Level := 100;
  Equips[e].Src := 'Tower01';
  e := Eq2(EQ_HEATEX, 120, 300, 168, 64, 'HX02', EQS_RUN);
  Equips[e].LinkX := 9;
  Equips[e].LinkY := 14;
  Equips[e].RMin := 30;
  Equips[e].Level := 80;
  Equips[e].Src := 'Chiller01';
  e := Eq2(EQ_COOLTOWER, 640, 560, 144, 168, 'Tower01', EQS_STOP);
  Equips[e].Src := 'HX01';
  e := Eq2(EQ_CHILLER, 816, 600, 216, 120, 'Chiller01', EQS_STOP);
  Equips[e].Src := 'HX02';
  e := Eq2(EQ_CONTROLLER, 600, 250, 168, 112, 'Stream 1 control', EQS_STOP);
  Equips[e].Src := 'TIC1';
  e := Eq2(EQ_DIGITAL, 790, 250, 150, 52, 'Stream 1 out C', EQS_STOP);
  Equips[e].Src := 'HX01';
  e := Eq2(EQ_DIGITAL, 790, 320, 150, 52, 'Tower out C', EQS_STOP);
  Equips[e].Src := 'Tower01';
  e := Eq2(EQ_DIGITAL, 600, 390, 150, 52, 'CHW supply C', EQS_STOP);
  Equips[e].Src := 'Chiller01';
  e := Eq2(EQ_DIGITAL, 790, 390, 150, 52, 'Stream 2 out C', EQS_STOP);
  Equips[e].Src := 'HX02';
  e := Eq2(EQ_DIGITAL, 600, 460, 150, 52, 'pH 1', EQS_STOP);
  Equips[e].Src := 'PH1';
  Equips[e].RMax := 14;
  e := Eq2(EQ_DIGITAL, 790, 460, 150, 52, 'pH 2', EQS_STOP);
  Equips[e].Src := 'PH2';
  Equips[e].RMax := 14;

  CurLayer := 3;
  Ladder(26, 43, 34, 1, 7);
  { TIC1: PID, reverse: the hotter stream 1 is, the faster the tower fan (drive U1) }
  EWireLine(26, 3, 43, 3);
  EP(29, 3, ekSwitch, 'S1');
  EGrid[29, 3].On := True;
  EP(40, 3, ekController, 'TIC1');
  EGrid[40, 3].Pos := 3;
  EGrid[40, 3].P1 := 40;
  EGrid[40, 3].P2 := 30;
  EGrid[40, 3].P3 := 6;
  EGrid[40, 3].Src := 'TT1';
  EWireLine(26, 5, 43, 5);
  EP(40, 5, ekDrive, 'U1', 'Tower01');
  EGrid[40, 5].Src := 'TIC1';
  { S2 runs the chiller }
  EWireLine(26, 7, 43, 7);
  EP(29, 7, ekSwitch, 'S2');
  EGrid[29, 7].On := True;
  EP(40, 7, ekMotor, 'M2', 'Chiller01');
  { the sensors }
  EP(11, 8, ekTempTx, 'TT1', 'HX01');
  EP(22, 33, ekPHTx, 'PH1');
  EP(13, 33, ekPHTx, 'PH2');
  EP(28, 22, ekHumidTx, 'MT1');

  Notes;
  AddLabel(24, 470, 'COOLING WATER & CHILLER'#10'Stream 1, 90 C: HX01 + Tower01'#10 +
    'TIC1 sets the fan: 40 C out.'#10'Stream 2, 30 C: HX02 + Chiller01'#10 +
    'PH1 / PH2: pH in the buckets.');
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
    7: Example7;
    8: Example8;
    9: Example9;
    10: Example10;
    11: Example11;
    12: Example12;
    13: Example13;
    14: Example14;
    15: Example15;
    16: Example16;
    17: Example17;
    18: Example18;
    19: Example19;
    20: Example20;
    21: Example21;
    22: Example22;
    23: Example23;
    24: Example24;
    25: Example25;
    26: Example26;
  end;
  if n = 7 then PlantLinks(24, 660)
  else if n >= 14 then PlantLinks(24, 24)
  else if n >= 10 then PlantLinks(920, 690)
  else PlantLinks;
  AddAboutPage(n);
  if n = 24 then Example24Pages;
  { new parts the user draws go on the Process layer }
  SetActiveLayer(LAYER_PROCESS);
end;

end.
