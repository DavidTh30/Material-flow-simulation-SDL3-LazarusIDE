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
  EXAMPLE_COUNT = 35;
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
    'Cooling tower, chiller & pH',
    'Flow chart control',
    'Flow chart: switches & random',
    'Trend charts',
    'Timelines',
    'Rotary dryer system',
    'PVC dry blend plant',
    'Belt conveyor system',
    'Bottles, boxes & toys',
    'Shipping dock & order pickers');
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
    'example26_cooling_tower_chiller_ph.mflow',
    'example27_flow_chart_control.mflow',
    'example28_flow_chart_switches_random.mflow',
    'example29_trend_charts.mflow',
    'example30_timelines.mflow',
    'example31_rotary_dryer.mflow',
    'example32_pvc_dry_blend.mflow',
    'example33_belt_conveyor.mflow',
    'example34_bottles_boxes_toys.mflow',
    'example35_shipping_dock.mflow');

const
  { the Examples menu: one sub-menu per category, examples CatFirst..CatLast }
  EXAMPLE_CATS = 7;
  CatNames: array[1..EXAMPLE_CATS] of string = ('Pipes & air flow', 'Storage & equipment',
    'Electrical circuits', 'Pneumatic systems', 'Hydraulic systems', 'Control & sensors',
    'Plant systems');
  CatFirst: array[1..EXAMPLE_CATS] of Integer = (1, 5, 10, 15, 19, 22, 31);
  CatLast: array[1..EXAMPLE_CATS] of Integer = (4, 9, 14, 18, 21, 30, 35);

procedure BuildExample(n: Integer);

implementation

uses
  simcore, mfpages, elec, fluid, flowchart, mftheme, piecesim;

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
    'Click SB1: K1 latches on and runs the cycle;'#10 +
    'the feed gate lets sand into the hopper.'#10 +
    'With A in (A0) Y1 sends it out: Gate01 opens'#10 +
    'and sand falls into the bin. At A1 timer T1'#10 +
    'counts 2 s, then Y2 brings A back. SB0 stops.',
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
    'water through HX02 to cool stream 2 (30 C).',
    'Every frame the chart starts at Start: it'#10 +
    'reads Pool01 and Well01 (page 3). A dry well'#10 +
    'stops Pump01 and turns the DRY tag on; a low'#10 +
    'pool starts it, a full pool stops it. The'#10 +
    'yellow path is the one the scan takes.',
    'COIN (a random boolean, every 2 s) turns'#10 +
    'switch S1 and air valve V1 on or off. LOAD'#10 +
    '(a random byte) over 235 trips OL1; after 3 s'#10 +
    'the chart resets it. DICE (1..3) sets the'#10 +
    'position of selector SA1 (H3 in position 3).',
    'Trend01 records four pens: TT1 (Heater01''s'#10 +
    'temperature), TIC1.SP (its set point), relay'#10 +
    'K1 (flasher T1: ON / OFF events, the strip at'#10 +
    'the bottom) and DEMAND (a random value from'#10 +
    'the flow chart). Trend02 / 03: mini, curve.',
    'Timeline01 runs 0..20 s over and over (auto'#10 +
    'start). Fix Pin 1 sends S1 0 / 1 / 0 (Pump01'#10 +
    'runs 2-10 s), Fix Pin 2 sends RV1 30 / 100 /'#10 +
    '30 (Pump02''s speed). Input Pin 1 keeps Pool01'#10 +
    'at 10 s and sends it to POOL10 (a display).',
    'Wet sand drops into the hopper; the loading'#10 +
    'feeder pushes it into the drum. The blow fan'#10 +
    'drives furnace air in; hot zones boil the'#10 +
    'water off. Dry sand falls out of the hood,'#10 +
    'the exhaust fan draws dust to the collector.',
    'AUTO on (page 3): the flow chart opens V7.56,'#10 +
    'V7.57, V7.58 in turn until WI7.50 holds 6, 10,'#10 +
    '15 %. Then the Mixing timeline: V7.53 into T3,'#10 +
    'additives V8.03, VT3 to T4, VT4 up to H9.3.'#10 +
    'XM9.03 feeds the extruder unless H9.3 is low.',
    'Click SB1: KM1 runs drive U1 and BC-01 runs;'#10 +
    'the feed gate opens, sand drops through the'#10 +
    'hopper onto the tail end and rides 15 deg up'#10 +
    'to the head, where it falls into the bin.'#10 +
    'SB0 / ES1 stop it; the gate shuts with it.',
    'Item feeders drop whole pieces. Click SB1:'#10 +
    'bottles ride Belt01 into the crate; PE1 counts'#10 +
    'each one (CNT1). At 12 the line stops and H1'#10 +
    'lights. Line 2 carries glasses, boxes and'#10 +
    'dolls up a 12 deg belt into the bin.',
    'Three order pickers take boxes from their'#10 +
    'racks and put them on the roller conveyor.'#10 +
    'Click SB1: it carries them to the dock; the'#10 +
    'dock worker lifts each one into the box van.'#10 +
    'PE1 counts what is shipped.');

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
    'Watch the flow chart: its yellow path is the'#10 +
    'step now; the Timing chart shows the gate'#10 +
    'and Y1 / A1 / Y2. Set T1 longer (select it):'#10 +
    'the gate stays open longer. SB0 stops.',
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
    'Physics lab: set sand''s pH and watch PH1.',
    'Right-click Pool low? > Go to Pool01, then'#10 +
    'right-click > Back to flow chart.'#10 +
    'Change Pool low''s value (Properties).',
    'Set COIN''s True % (Properties) to 100.'#10 +
    'Change Overload?''s value: fewer trips.'#10 +
    'Point Speed > 50? at another name.',
    'Select Trend01: pick or type its pens (< >),'#10 +
    'change its style and time window. Set TIC1''s'#10 +
    'set point (faceplate) and watch the curve.',
    'Press SB1: Timeline02 runs once. Right-click'#10 +
    'a timeline: add a pin there. Drag a pin along'#10 +
    'it. Double-click a timeline: start / stop.',
    'Control panel (page 3): press SB1 and watch'#10 +
    'the start-up, SB2 for the shut-down. Stop'#10 +
    'the burner (S4): the moisture (Monitor) goes'#10 +
    'up. Set TIC1 lower on its faceplate.',
    'Page 3: watch the yellow path pick the valve;'#10 +
    'switch AUTO off: every valve shuts. Change a'#10 +
    'decision''s value (the set point). Theme >'#10 +
    'Background picks another background.',
    'Turn RV1 (wheel): faster or slower belt.'#10 +
    'Select BC-01: change its Incline (-35..35).'#10 +
    'Fault BC-01 (Properties): it stops on the'#10 +
    'slope and the feed gate shuts.',
    'Click SB2: the count starts again. Select'#10 +
    'Bottles: pick what it feeds and how often,'#10 +
    'give it a stock. Add an Item feeder from'#10 +
    'the Equip tab anywhere.',
    'Click SB0: the line stops and the boxes wait'#10 +
    'at the pickers. Select a picker: Every s,'#10 +
    'what it loads. Make the dock worker a slow'#10 +
    'one (Carry s): the line backs up.');

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
    'and the humidity of the tower''s plume.',
    'EXAMPLE 27 - FLOW CHART CONTROL'#10 +
    'A flow chart reads the well and the pool on'#10 +
    'another page, decides, and runs the pump;'#10 +
    'its tags light lamps, its displays show values.',
    'EXAMPLE 28 - FLOW CHART: SWITCHES & RANDOM'#10 +
    'Random boolean, byte, integer and float values'#10 +
    'switch S1, an air valve, an overload and a'#10 +
    'selector through Switch ON / OFF / Position.',
    'EXAMPLE 29 - TREND CHARTS'#10 +
    'Charts record values and ON / OFF events over'#10 +
    'time: a full chart with axes, legend and an'#10 +
    'event strip, a mini chart and just a curve.',
    'EXAMPLE 30 - TIMELINES'#10 +
    'Timelines run in a loop or one cycle and send'#10 +
    'fixed or kept input values to switches, pots'#10 +
    'and names before, at and after each pin.',
    'EXAMPLE 31 - ROTARY DRYER SYSTEM'#10 +
    'A dryer drum, oil furnace, blow, combustion'#10 +
    'and exhaust fans and a dust collector on'#10 +
    'page 1; the control panel with start-up and'#10 +
    'shut-down timelines on page 3; trends and'#10 +
    'meters on page 4.',
    'EXAMPLE 32 - PVC DRY BLEND PLANT'#10 +
    'An HMI screen: three raw material lines, a'#10 +
    'weigh hopper, hot and cool mixers, a storage'#10 +
    'silo and the conveying line to the extruder,'#10 +
    'run by a dosing flow chart and a timeline.',
    'EXAMPLE 33 - BELT CONVEYOR SYSTEM'#10 +
    'An inclined belt conveyor from a technical'#10 +
    'drawing: feed hopper at the tail, gear motor'#10 +
    'at the head, start / stop with E-stop and'#10 +
    'overload, a VFD for its speed.',
    'EXAMPLE 34 - BOTTLES, BOXES & TOYS'#10 +
    'Item feeders drop whole pieces (bottles,'#10 +
    'glasses, boxes, dolls) onto conveyors; a'#10 +
    'photo sensor and a counter fill a crate.',
    'EXAMPLE 35 - SHIPPING DOCK'#10 +
    'Workers (order pickers) load boxes from'#10 +
    'standard racks onto a roller conveyor; a dock'#10 +
    'worker loads them into the box van.');

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
  LayoutBg := -1;
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
      hopper gate; Y1 out when A0, timer T1 holds it open, Y2 in. The feed
      gate lets sand in only while the system is on (K1). A flow chart shows
      the step the cycle is in, a trend chart its timing. }
procedure Example16;
var
  e: Integer;
  n: array[0..9] of Integer;

  { a flow chart node that only reads (sized to fit) }
  function FNode(Kind: Integer; X, Y, W, H: Single; const Caption, Src: string; Op: Integer; Value: Single): Integer;
  begin
    Result := FlowAdd(Kind, X, Y);
    FlowNodes[Result].W := W;
    FlowNodes[Result].H := H;
    FlowNodes[Result].Caption := Caption;
    FlowNodes[Result].Src := Src;
    FlowNodes[Result].Op := Op;
    FlowNodes[Result].Value := Value;
  end;

begin
  FluidLayers('Pneumatic', True);
  Pages[PAGE_PLANT].Layers[2].Name := 'Equipment & chart';
  CurLayer := LAYER_PROCESS;
  Feeder(8, 2, 0, 0, 0, 2600, 0, 40);
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
  e := Eq2(EQ_SLIDE, 172, 84, 56, 44, 'FeedGate', EQS_STOP);
  Equips[e].LinkX := 8;
  Equips[e].LinkY := 2;
  e := Eq2(EQ_COMPRESSOR, 300, 640, 200, 112, 'Comp01', EQS_STOP);
  Equips[e].Src := 'R1';
  Equips[e].RMax := 10;
  { the timing: how far the gate is open, the solenoids and the end switch }
  e := Eq2(EQ_TREND, 240, 446, 330, 150, 'Timing', EQS_STOP);
  Equips[e].Delay := 30;
  Equips[e].RMin := 0;
  Equips[e].RMax := 100;
  Equips[e].Src := 'Gate01';
  Equips[e].Src2 := 'Y1';
  Equips[e].Src3 := 'A1';
  Equips[e].Src4 := 'Y2';

  CurLayer := 3;
  AirSupply(24, 30, 42, 'Comp01');
  ValveCylDA(33, 26, 19, 30, fkV52, 'V1', 'A', 'Gate01', fkSilencer, True);
  FGrid[33, 26].Act := 3;
  FGrid[33, 26].SolA := 'Y1';
  FGrid[33, 26].SolB := 'Y2';

  CurLayer := 4;
  Ladder(24, 42, 33, 1, 16);
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
  { the feed gate is open while the system is on }
  EWireLine(24, 16, 42, 16);
  EP(27, 16, ekNO, 'K1');
  EP(40, 16, ekMotor, 'M1', 'FeedGate');

  { the cycle as a flow chart: it only reads, the yellow path is the step it is in now }
  CurLayer := 2;
  n[0] := FNode(FN_START, 316, 30, 100, 30, 'Cycle', '', 0, 0);
  n[1] := FNode(FN_DECISION, 286, 76, 160, 60, 'System on?', 'K1', FOP_ON, 0);
  n[2] := FNode(FN_DISPLAY, 462, 82, 104, 48, 'Click SB1', 'K1', FOP_OFF, 0);
  n[3] := FNode(FN_DECISION, 286, 156, 160, 60, 'A in?', 'A0', FOP_ON, 0);
  n[4] := FNode(FN_DISPLAY, 286, 236, 160, 48, '1 Y1: A goes out', 'Y1', FOP_ON, 0);
  n[5] := FNode(FN_DECISION, 452, 156, 116, 60, 'A out?', 'A1', FOP_ON, 0);
  n[6] := FNode(FN_DISPLAY, 452, 236, 116, 48, '2 Gate open', 'Gate01', FOP_GT, 50);
  n[7] := FNode(FN_DISPLAY, 452, 300, 116, 48, '3 T1 counts', 'T1', FOP_GE, 0);
  n[8] := FNode(FN_DISPLAY, 452, 364, 116, 48, '4 Y2: A in', 'Y2', FOP_ON, 0);
  n[9] := FNode(FN_DISPLAY, 286, 300, 160, 48, 'A moving', 'Gate01', FOP_GT, 0);
  FlowConnect(n[0], n[1], False);
  FlowConnect(n[1], n[3], False);
  FlowConnect(n[1], n[2], True);
  FlowConnect(n[3], n[4], False);
  FlowConnect(n[3], n[5], True);
  FlowConnect(n[5], n[6], False);
  FlowConnect(n[5], n[9], True);
  FlowConnect(n[6], n[7], False);
  FlowConnect(n[7], n[8], False);

  Notes;
  AddLabel(8, 470, 'HOW TO USE'#10'1 Click SB1: K1'#10'  on, feed opens'#10'2 Y1 pushes A'#10'  out: Gate01'#10 +
    '  opens, sand'#10'  falls in the bin'#10'3 At A1 T1'#10'  counts 2 s'#10'4 Y2 brings A'#10 +
    '  back; again'#10'5 Click SB0:'#10'  stop'#10'Chart: yellow'#10'path = step now');
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

{ a flow chart node on the live page }
function FN(Kind: Integer; X, Y: Single; const Caption: string): Integer;
begin
  Result := FlowAdd(Kind, X, Y);
  FlowNodes[Result].Caption := Caption;
end;

procedure FNRead(i: Integer; const Src: string; Op: Integer; Value: Single);
begin
  FlowNodes[i].Src := Src;
  FlowNodes[i].Op := Op;
  FlowNodes[i].Value := Value;
end;

procedure FNAct(i, Act: Integer; const Target: string; Value: Single = 0);
begin
  FlowNodes[i].Act := Act;
  FlowNodes[i].Target := Target;
  FlowNodes[i].Value := Value;
end;

{ 27. A flow chart on page 1 runs the pump house on page 3: it reads the well and
      the pool, decides, and starts / stops Pump01 there; a Delay and two Tag ON
      actions light lamps through contacts; Displays show the values live. }
procedure Example27;
var
  n: array[0..17] of Integer;
begin
  Pages[PAGE_PLANT].NLayers := 4;
  Pages[PAGE_PLANT].Layers[2].Name := 'Flow chart';
  Pages[PAGE_PLANT].Layers[3].Name := 'Electrical';
  CurLayer := 2;
  n[0] := FN(FN_START, 112, 40, 'Start');
  n[1] := FN(FN_INPUT, 100, 110, 'Pool level');
  FNRead(n[1], 'Pool01', FOP_GT, 0);
  n[2] := FN(FN_DECISION, 88, 190, 'Well dry?');
  FNRead(n[2], 'Well01', FOP_LT, 15);
  n[3] := FN(FN_ACTION, 100, 310, 'Protect pump');
  FNAct(n[3], FA_STOP, 'Pump01');
  n[4] := FN(FN_ACTION, 100, 390, 'Dry alarm');
  FNAct(n[4], FA_TAG, 'DRY');
  n[5] := FN(FN_END, 112, 470, 'End');
  n[6] := FN(FN_DECISION, 330, 190, 'Pool low?');
  FNRead(n[6], 'Pool01', FOP_LT, 40);
  n[7] := FN(FN_ACTION, 342, 310, 'Start pump');
  FNAct(n[7], FA_RUN, 'Pump01');
  n[8] := FN(FN_DELAY, 354, 390, 'Settle');
  FlowNodes[n[8]].Value := 2;
  n[9] := FN(FN_ACTION, 342, 470, 'Filling lamp');
  FNAct(n[9], FA_TAG, 'FILLING');
  n[10] := FN(FN_END, 354, 550, 'End');
  n[11] := FN(FN_DECISION, 570, 190, 'Pool full?');
  FNRead(n[11], 'Pool01', FOP_GT, 80);
  n[12] := FN(FN_ACTION, 582, 310, 'Stop pump');
  FNAct(n[12], FA_STOP, 'Pump01');
  n[13] := FN(FN_END, 594, 390, 'End');
  n[14] := FN(FN_END, 790, 210, 'End');
  n[15] := FN(FN_DISPLAY, 100, 640, 'Pump01');
  FNRead(n[15], 'Pump01', FOP_ON, 0);
  n[16] := FN(FN_DISPLAY, 300, 640, 'Well01 level');
  FNRead(n[16], 'Well01', FOP_GE, 15);
  n[17] := FN(FN_DISPLAY, 500, 640, 'Pool01 level');
  FNRead(n[17], 'Pool01', FOP_GE, 40);
  FlowConnect(n[0], n[1], False);
  FlowConnect(n[1], n[2], False);
  FlowConnect(n[2], n[3], False);
  FlowConnect(n[2], n[6], True);
  FlowConnect(n[3], n[4], False);
  FlowConnect(n[4], n[5], False);
  FlowConnect(n[6], n[7], False);
  FlowConnect(n[6], n[11], True);
  FlowConnect(n[7], n[8], False);
  FlowConnect(n[8], n[9], False);
  FlowConnect(n[9], n[10], False);
  FlowConnect(n[11], n[12], False);
  FlowConnect(n[11], n[14], True);
  FlowConnect(n[12], n[13], False);

  { two lamps follow the chart's tags }
  CurLayer := 3;
  Ladder(30, 42, 36, 24, 28);
  EWireLine(30, 26, 42, 26);
  EP(33, 26, ekNO, 'FILLING');
  EP(39, 26, ekLamp, 'H1');
  EWireLine(30, 28, 42, 28);
  EP(33, 28, ekNO, 'DRY');
  EP(39, 28, ekLamp, 'H2');
  EGrid[39, 28].Pos := 1;

  Notes;
  AddLabel(760, 290, 'FLOW CHART CONTROL'#10'Runs every frame and works the'#10'pump house on page 3.'#10 +
    'Right-click a node that reads or'#10'works something: Go to it. Then'#10'right-click > Back to flow chart.');
  Link(760, 400, 'Pump house', False, 2, 2);
end;

{ page 3 of example 27: the pump house the chart works }
procedure Example27Pages;
var
  p, e: Integer;
begin
  ParkPage(PAGE_PLANT);
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
  Equips[e].Level := 30;
  e := Eq2(EQ_PUMP, 516, 744, 104, 56, 'Pump02', EQS_RUN);
  Equips[e].LinkX := 22;
  Equips[e].LinkY := 29;
  Equips[e].Level := 30;
  e := Eq2(EQ_POND, 760, 720, 264, 90, 'Pond01', EQS_STOP);
  Equips[e].Level := 10;
  CurLayer := 1;
  AddLabel(400, 120, 'PUMP HOUSE (page 3)'#10'No circuit here: the flow chart on page 1'#10 +
    'starts and stops Pump01 over the plant bus.'#10'Pump02 drains the pool all the time.');
  Link(400, 210, 'Flow chart', False, PAGE_PLANT, 1);
  CurLayer := 0;
  ParkPage(p);
  CurPage := PAGE_PLANT;
  UnparkPage(PAGE_PLANT);
end;

{ 28. A flow chart works switches: a random coin turns switch S1 and the air
      valve V1 on or off; a random load trips overload OL1, which is reset after
      a cool-down; a random dice sets selector SA1; a random speed is shown. }
procedure Example28;
var
  n: array[0..19] of Integer;
begin
  Pages[PAGE_PLANT].NLayers := 5;
  Pages[PAGE_PLANT].Layers[2].Name := 'Flow chart';
  Pages[PAGE_PLANT].Layers[3].Name := 'Electrical';
  Pages[PAGE_PLANT].Layers[4].Name := 'Pneumatic';
  CurLayer := 2;
  n[0] := FN(FN_START, 40, 30, 'Start');
  n[1] := FN(FN_RANDOM, 28, 96, 'Coin');
  FlowNodes[n[1]].RType := FR_BOOL;
  FlowNodes[n[1]].Value := 50;
  FlowNodes[n[1]].Period := 2;
  FlowNodes[n[1]].Target := 'COIN';
  n[2] := FN(FN_ACTION, 28, 180, 'S1 on');
  FNAct(n[2], FA_ON, 'S1');
  n[3] := FN(FN_ACTION, 28, 250, 'V1 open');
  FNAct(n[3], FA_ON, 'V1');
  n[4] := FN(FN_ACTION, 232, 180, 'S1 off');
  FNAct(n[4], FA_OFF, 'S1');
  n[5] := FN(FN_ACTION, 232, 250, 'V1 shut');
  FNAct(n[5], FA_OFF, 'V1');
  n[6] := FN(FN_RANDOM, 28, 330, 'Load');
  FlowNodes[n[6]].RType := FR_BYTE;
  FlowNodes[n[6]].Value2 := 0;
  FlowNodes[n[6]].Value := 255;
  FlowNodes[n[6]].Period := 1;
  FlowNodes[n[6]].Target := 'LOAD';
  n[7] := FN(FN_DECISION, 16, 410, 'Overload?');
  FNRead(n[7], 'LOAD', FOP_GT, 235);
  n[8] := FN(FN_ACTION, 28, 530, 'Trip OL1');
  FNAct(n[8], FA_OFF, 'OL1');
  n[9] := FN(FN_END, 40, 610, 'End');
  n[10] := FN(FN_DECISION, 220, 410, 'OL1 tripped?');
  FNRead(n[10], 'OL1', FOP_ON, 0);
  n[11] := FN(FN_DELAY, 244, 530, 'Cool down');
  FlowNodes[n[11]].Value := 3;
  n[12] := FN(FN_ACTION, 232, 610, 'Reset OL1');
  FNAct(n[12], FA_RESET, 'OL1');
  n[13] := FN(FN_RANDOM, 430, 430, 'Dice');
  FlowNodes[n[13]].RType := FR_INT;
  FlowNodes[n[13]].Value2 := 1;
  FlowNodes[n[13]].Value := 3;
  FlowNodes[n[13]].Period := 3;
  FlowNodes[n[13]].Target := 'DICE';
  n[14] := FN(FN_ACTION, 430, 530, 'SA1 = dice');
  FNAct(n[14], FA_POS, 'SA1');
  FlowNodes[n[14]].Src := 'DICE';
  n[15] := FN(FN_END, 442, 610, 'End');
  n[16] := FN(FN_RANDOM, 430, 96, 'Speed');
  FlowNodes[n[16]].RType := FR_FLOAT;
  FlowNodes[n[16]].Value2 := 0;
  FlowNodes[n[16]].Value := 100;
  FlowNodes[n[16]].Period := 2;
  FlowNodes[n[16]].Target := 'SPEED';
  n[17] := FN(FN_DISPLAY, 418, 180, 'Speed > 50?');
  FNRead(n[17], 'SPEED', FOP_GT, 50);
  n[18] := FN(FN_DISPLAY, 418, 260, 'Coin');
  FNRead(n[18], 'COIN', FOP_ON, 0);
  FlowConnect(n[0], n[1], False);
  FlowConnect(n[1], n[2], False);
  FlowConnect(n[1], n[4], True);
  FlowConnect(n[2], n[3], False);
  FlowConnect(n[4], n[5], False);
  FlowConnect(n[3], n[6], False);
  FlowConnect(n[5], n[6], False);
  FlowConnect(n[6], n[7], False);
  FlowConnect(n[7], n[8], False);
  FlowConnect(n[7], n[10], True);
  FlowConnect(n[8], n[9], False);
  FlowConnect(n[10], n[11], False);
  FlowConnect(n[10], n[13], True);
  FlowConnect(n[11], n[12], False);
  FlowConnect(n[13], n[14], False);
  FlowConnect(n[14], n[15], False);

  { the circuit the chart works }
  CurLayer := 3;
  Ladder(26, 43, 34, 1, 9);
  EWireLine(26, 3, 43, 3);
  EP(28, 3, ekBreaker, 'Q1');
  EP(31, 3, ekSwitch, 'S1');
  EP(35, 3, ekOL, 'OL1');
  EP(40, 3, ekLamp, 'H1');
  EWireLine(26, 5, 43, 5);
  EP(32, 5, ekNO, 'OL1');
  EP(40, 5, ekLamp, 'H2');
  EGrid[40, 5].Pos := 1;
  EWireLine(26, 7, 43, 7);
  EP(32, 7, ekSelector, 'SA1');
  EGrid[32, 7].NPos := 3;
  EGrid[32, 7].Pos := 3;
  EP(40, 7, ekLamp, 'H3');
  EGrid[40, 7].Pos := 2;
  EWireLine(26, 9, 43, 9);
  EP(32, 9, ekNO, 'COIN');
  EP(40, 9, ekLamp, 'H4');
  EGrid[40, 9].Pos := 4;
  { the air circuit: a manual 3/2 valve and a single-acting cylinder }
  CurLayer := 4;
  AirSupply(26, 30, 42, '');
  FLineRun(39, 27, 39, 30);
  FLineRun(38, 26, 37, 26);
  FLineRun(37, 26, 37, 19);
  FP(39, 25, fkSilencer, '');
  FP(39, 26, fkV32, 'V1');
  FP(37, 18, fkCylSA, 'B', 3, '');

  Notes;
  AddLabel(640, 260, 'FLOW CHART: SWITCHES & RANDOM'#10'COIN (random boolean) turns S1 and'#10 +
    'valve V1 on / off; LOAD (random byte)'#10'trips OL1, reset after a cool-down;'#10 +
    'DICE (random integer) sets SA1.');
end;

{ 29. Trend charts: a heater under on / off control (TT1, TIC1) and a flasher
      (T1, relay K1) with a random demand (a flow chart) recorded on three
      charts: Trend01 full (values, set point, events), Trend02 mini (the
      temperature), Trend03 just the demand curve. }
procedure Example29;
var
  e: Integer;
  n: array[0..2] of Integer;
begin
  ElecLayers;
  Pages[PAGE_PLANT].NLayers := 5;
  Pages[PAGE_PLANT].Layers[4].Name := 'Flow chart';
  CurLayer := 2;
  e := Eq2(EQ_TREND, 24, 84, 560, 260, 'Trend01', EQS_STOP);
  Equips[e].Mode := 0;
  Equips[e].Delay := 60;
  Equips[e].Src := 'TT1';
  Equips[e].Src2 := 'TIC1.SP';
  Equips[e].Src3 := 'K1';
  Equips[e].Src4 := 'DEMAND';
  e := Eq2(EQ_TREND, 24, 370, 272, 100, 'Trend02', EQS_STOP);
  Equips[e].Mode := 1;
  Equips[e].Delay := 30;
  Equips[e].Src := 'TT1';
  e := Eq2(EQ_TREND, 312, 370, 272, 100, 'Trend03', EQS_STOP);
  Equips[e].Mode := 2;
  Equips[e].Delay := 30;
  Equips[e].Src := 'DEMAND';
  e := Eq2(EQ_HEATER, 60, 640, 120, 56, 'Heater01', EQS_STOP);
  e := Eq2(EQ_CONTROLLER, 640, 300, 168, 112, 'Heater control', EQS_STOP);
  Equips[e].Src := 'TIC1';
  e := Eq2(EQ_DIGITAL, 830, 300, 150, 52, 'Demand', EQS_STOP);
  Equips[e].Src := 'DEMAND';
  Equips[e].RMax := 100;

  CurLayer := 3;
  Ladder(26, 43, 34, 1, 9);
  { TIC1: on / off, holds Heater01 at 80 C }
  EWireLine(26, 3, 43, 3);
  EP(29, 3, ekSwitch, 'S1');
  EGrid[29, 3].On := True;
  EP(40, 3, ekController, 'TIC1');
  EGrid[40, 3].Pos := 0;
  EGrid[40, 3].P1 := 80;
  EGrid[40, 3].P2 := 10;
  EGrid[40, 3].Src := 'TT1';
  EWireLine(26, 5, 43, 5);
  EP(32, 5, ekNO, 'TIC1');
  EP(40, 5, ekMotor, 'M3', 'Heater01');
  { T1 flashes (2 s on, 3 s off): relay K1 and lamp H1 }
  EWireLine(26, 7, 43, 7);
  EP(29, 7, ekSwitch, 'S2');
  EGrid[29, 7].On := True;
  EP(40, 7, ekTimer, 'T1');
  EGrid[40, 7].Pos := 3;
  EGrid[40, 7].P1 := 2;
  EGrid[40, 7].P2 := 3;
  EWireLine(26, 9, 43, 9);
  EP(32, 9, ekNO, 'T1');
  EP(40, 9, ekRelay, 'K1');
  EP(6, 25, ekTempTx, 'TT1', 'Heater01');

  { a random demand, 0..100 every second }
  CurLayer := 4;
  n[0] := FN(FN_START, 932, 470, 'Start');
  n[1] := FN(FN_RANDOM, 920, 540, 'Demand');
  FlowNodes[n[1]].RType := FR_FLOAT;
  FlowNodes[n[1]].Value2 := 0;
  FlowNodes[n[1]].Value := 100;
  FlowNodes[n[1]].Period := 1;
  FlowNodes[n[1]].Target := 'DEMAND';
  n[2] := FN(FN_END, 932, 620, 'End');
  FlowConnect(n[0], n[1], False);
  FlowConnect(n[1], n[2], False);

  Notes;
  AddLabel(624, 470, 'TREND CHARTS'#10'Trend01 (Full): TT1, its set point,'#10 +
    'relay K1 as events, DEMAND.'#10'Trend02 (Mini): TT1 and its value.'#10 +
    'Trend03 (Curve): just the line.');
end;

{ a pin on timeline e: its time, how long "at" it lasts, values and targets before / at / after }
procedure TLPin(e, Kind: Integer; T, W: Single; const Src: string; m0: Integer; v0: Single; const d0: string;
  m1: Integer; v1: Single; const d1: string; m2: Integer; v2: Single; const d2: string);
var
  k: Integer;
begin
  k := TLAddPin(e, Kind, T);
  if k < 0 then Exit;
  Equips[e].Pins[k].W := W;
  Equips[e].Pins[k].Src := Src;
  Equips[e].Pins[k].VMode[0] := m0;
  Equips[e].Pins[k].V[0] := v0;
  Equips[e].Pins[k].Dest[0] := d0;
  Equips[e].Pins[k].VMode[1] := m1;
  Equips[e].Pins[k].V[1] := v1;
  Equips[e].Pins[k].Dest[1] := d1;
  Equips[e].Pins[k].VMode[2] := m2;
  Equips[e].Pins[k].V[2] := v2;
  Equips[e].Pins[k].Dest[2] := d2;
end;

{ 30. Timelines: Timeline01 (loop, auto start, 20 s) runs Pump01 through switch
      S1 from 2 to 10 s, drives Pump02 at full speed (pot RV1) from 12 to 16 s,
      and keeps Pool01's level at 10 s (Input Pin 1) as POOL10. Timeline02 (one
      cycle) is started by push button SB1 and sounds BUZZ (a tag of its own)
      for 3 s. }
procedure Example30;
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
  e := Eq2(EQ_POND, 760, 720, 264, 90, 'Pond01', EQS_STOP);
  Equips[e].Level := 10;
  e := Eq2(EQ_TIMELINE, 420, 272, 600, 130, 'Timeline01', EQS_STOP);
  Equips[e].Delay := 20;
  Equips[e].Mode := TL_LOOP or TL_AUTO;
  TLPin(e, TLP_FIX, 2, 8, '', TLV_FIX, 0, 'S1', TLV_FIX, 1, 'S1', TLV_FIX, 0, 'S1');
  TLPin(e, TLP_FIX, 12, 4, '', TLV_FIX, 30, 'RV1', TLV_FIX, 100, 'RV1', TLV_FIX, 30, 'RV1');
  TLPin(e, TLP_INPUT, 10, 1, 'Pool01', TLV_NONE, 0, '', TLV_LIVE, 0, '', TLV_HELD, 0, 'POOL10');
  e := Eq2(EQ_TIMELINE, 420, 428, 380, 96, 'Timeline02', EQS_STOP);
  Equips[e].Delay := 6;
  Equips[e].Src := 'SB1';
  TLPin(e, TLP_FIX, 1, 3, '', TLV_FIX, 0, 'BUZZ', TLV_FIX, 1, 'BUZZ', TLV_FIX, 0, 'BUZZ');
  e := Eq2(EQ_DIGITAL, 820, 440, 200, 52, 'Pool at 10 s', EQS_STOP);
  Equips[e].Src := 'POOL10';

  CurLayer := 3;
  Ladder(26, 43, 34, 1, 9);
  { S1 runs Pump01: Fix Pin 1 switches it }
  EWireLine(26, 3, 43, 3);
  EP(29, 3, ekSwitch, 'S1');
  EP(40, 3, ekMotor, 'M1', 'Pump01');
  { drive U1 runs Pump02 at the speed of RV1: Fix Pin 2 turns it }
  EWireLine(26, 5, 43, 5);
  EP(29, 5, ekSwitch, 'S2');
  EGrid[29, 5].On := True;
  EP(40, 5, ekDrive, 'U1', 'Pump02');
  EGrid[40, 5].Src := 'RV1';
  EP(28, 10, ekPot, 'RV1');
  EGrid[28, 10].P1 := 30;
  { Timeline02's tag BUZZ lights H2; SB1 starts Timeline02 (and lights H3) }
  EWireLine(26, 7, 43, 7);
  EP(32, 7, ekNO, 'BUZZ');
  EP(40, 7, ekLamp, 'H2');
  EGrid[40, 7].Pos := 1;
  EWireLine(26, 9, 43, 9);
  EP(29, 9, ekPBNO, 'SB1');
  EP(40, 9, ekLamp, 'H3');
  EGrid[40, 9].Pos := 2;

  Notes;
  AddLabel(220, 24, 'TIMELINES'#10'Timeline01: loop, auto start, 20 s.'#10 +
    'Fix Pin 1 switches S1 (Pump01) 2-10 s,'#10'Fix Pin 2 sets RV1 (Pump02) 12-16 s,'#10 +
    'Input Pin 1 keeps Pool01 at 10 s.'#10'Press SB1: Timeline02 sounds BUZZ.');
end;

{ 31. A rotary dryer system, as in a dryer maker's flow sheet. Page 1 "Dryer":
      wet sand with fines drops into the raw material hopper; the loading feeder
      pushes it into the dryer drum (Dryer01, turned by its drive). Outside air
      is heated in the oil furnace and the blow fan drives it into the drum;
      two hot zones in the drum boil the water off. Dried sand falls out of the
      discharge hood into the product bin; the exhaust fan draws the air, steam
      and fines up to the dust collector, which drops the dust into its bin and
      lets the air go to the outside. Page 3 "Control": the motor circuits and
      the burner controller TIC1, worked by start-up and shut-down timelines.
      Page 4 "Monitor": trend chart, faceplate and displays. }
procedure Example31;
var
  e, x: Integer;
begin
  ElecLayers;
  Pages[PAGE_PLANT].Name := 'Dryer';
  Pages[PAGE_PLANT].Layers[3].Name := 'Instruments';
  CurLayer := LAYER_PROCESS;
  { raw material: wet sand with fines, into the hopper }
  Feeder(4, 2, 1600, 0, 350, 3000, 10, 55);
  PipeLine(4, 2, 4, 5, 3);
  Device(4, 5, ckDrop, 100);
  MakePipe(4, 10, 3);
  SetKind(4, 10, ckHopper);
  { the loading feeder pushes it down into the drum; a one-way pipe keeps the hot air out of the hopper }
  PipeLine(4, 10, 4, 16, 3);
  Device(4, 13, ckBlower, 60, 1);
  PipeLine(4, 16, 28, 16, 3);
  Device(6, 16, ckCheck, -1, 0);
  { the drum: wide, its flights move the load along }
  for x := 9 to 26 do Grid[x, 16].Dia := 5;
  Device(10, 16, ckBlower, 25, 0);
  { hot air: outside air -> oil furnace -> blow fan -> into the drum }
  PipeLine(20, 27, 8, 27, 3);
  Device(20, 27, ckSuction, 20);
  Device(12, 27, ckBlower, 45, 2);
  PipeLine(8, 27, 8, 16, 3);
  { discharge hood: the dried product falls out of the drum into its bin; beside the falling
    stream the exhaust intake draws the fines (light) and the air away, hardly the sand (heavy) }
  PipeLine(28, 16, 28, 18, 3);
  Device(28, 18, ckDrop, 100);
  FloorBucket(28, 150, 100);
  PipeLine(30, 21, 34, 21, 3);
  Device(30, 21, ckSuction, 45);
  PipeLine(34, 21, 34, 22, 3);
  PipeLine(34, 21, 34, 5, 3);
  Device(34, 12, ckBlower, 60, 3);
  PipeLine(34, 5, 36, 5, 3);
  PipeLine(36, 5, 36, 10, 3);
  Device(36, 10, ckDrop, 100);
  { the dust collector drops the dust into its funnel and bin; the air goes outside }
  MakePipe(36, 14, 3);
  SetKind(36, 14, ckHopper);
  PipeLine(36, 14, 36, 22, 3);
  Device(36, 22, ckDrop, 100);
  FloorBucket(36, 110, 80);

  CurLayer := 2;
  e := Eq2(EQ_DRYER, 84, 356, 600, 96, 'Dryer01', EQS_STOP);
  Equips[e].LinkX := 10;
  Equips[e].LinkY := 16;
  e := Eq2(EQ_MOTOR, 128, 296, 64, 40, 'LoadFeeder', EQS_STOP);
  Equips[e].LinkX := 4;
  Equips[e].LinkY := 13;
  e := Eq2(EQ_HEATER, 300, 300, 72, 40, 'Zone1', EQS_STOP);
  Equips[e].LinkX := 14;
  Equips[e].LinkY := 16;
  e := Eq2(EQ_HEATER, 468, 470, 72, 40, 'Zone2', EQS_STOP);
  Equips[e].LinkX := 21;
  Equips[e].LinkY := 16;
  e := Eq2(EQ_HEATER, 360, 690, 110, 56, 'Furnace01', EQS_STOP);
  Equips[e].LinkX := 16;
  Equips[e].LinkY := 27;
  e := Eq2(EQ_BLOWER, 480, 712, 84, 80, 'CombFan01', EQS_STOP);
  Equips[e].Flip := True;
  e := Eq2(EQ_BLOWER, 236, 690, 110, 100, 'BlowFan01', EQS_STOP);
  Equips[e].LinkX := 12;
  Equips[e].LinkY := 27;
  e := Eq2(EQ_BLOWER, 712, 236, 104, 96, 'ExhaustFan01', EQS_STOP);
  Equips[e].LinkX := 34;
  Equips[e].LinkY := 12;
  e := Eq2(EQ_CYCLONE, 848, 150, 56, 112, 'DustCol01', EQS_STOP);

  { the instruments: furnace temperature, the product's moisture and weight, the dust's weight }
  CurLayer := 3;
  EP(20, 29, ekTempTx, 'TT1', 'Furnace01');
  EP(28, 33, ekHumidTx, 'MT1');
  EGrid[28, 33].Pos := 1;
  EP(30, 33, ekWeightTx, 'WT1');
  EP(36, 33, ekWeightTx, 'WT2');

  Notes;
  AddLabel(140, 40, 'RAW MATERIAL INLET'#10'wet sand + fines');
  AddLabel(140, 236, 'LOADING FEEDER');
  AddLabel(300, 256, 'DRYER MAIN UNIT - hot zones');
  AddLabel(24, 560, 'HOT AIR'#10'outside air -> oil furnace'#10'-> blow fan -> drum');
  AddLabel(700, 200, 'EXHAUST FAN');
  AddLabel(912, 150, 'DUST'#10'COLLECTOR');
  AddLabel(912, 200, 'exhaust air'#10'to outside');
  AddLabel(530, 480, 'DRIED PRODUCT'#10'OUTLET');
  AddLabel(780, 560, 'exhaust intake:'#10'fines + air');
  Link(24, 470, 'Control panel', False, 2, 2);
  Link(24, 494, 'Monitor', False, 3, 3);
end;

{ pages 3 and 4 of example 31, after its About page }
procedure Example31Pages;
var
  p, e: Integer;

  { a rung on row y: up to three contacts, then the load at column 23 }
  procedure Rung(y: Integer; K1: TEKind; const T1: string; K2: TEKind; const T2: string; K3: TEKind;
    const T3: string; Load: TEKind; const LT, LRef: string);
  begin
    EWireLine(2, y, 26, y);
    if T1 <> '' then EP(5, y, K1, T1);
    if T2 <> '' then EP(9, y, K2, T2);
    if T3 <> '' then EP(13, y, K3, T3);
    EP(23, y, Load, LT, LRef);
  end;

begin
  ParkPage(PAGE_PLANT);
  { page 3: the control panel }
  p := AddPage('Control');
  CurPage := p;
  UnparkPage(p);
  Pages[p].NLayers := 3;
  Pages[p].Layers[0].Name := 'Electrical';
  Pages[p].Layers[1].Name := 'Notes';
  Pages[p].Layers[2].Name := 'Sequence';
  CurLayer := 0;
  Ladder(2, 26, 14, 1, 33);
  Rung(3, ekEStop, 'ES1', ekNone, '', ekNone, '', ekRelay, 'K0', '');
  Rung(5, ekNO, 'K0', ekSwitch, 'S1', ekNone, '', ekContactor, 'KM1', '');
  Rung(7, ekNO, 'KM1', ekSwitch, 'S2', ekNone, '', ekContactor, 'KM2', '');
  Rung(9, ekNO, 'KM2', ekSwitch, 'S3', ekNone, '', ekContactor, 'KM3', '');
  Rung(11, ekNO, 'K0', ekNone, '', ekNone, '', ekController, 'TIC1', '');
  EGrid[23, 11].Pos := 0;
  EGrid[23, 11].P1 := 180;
  EGrid[23, 11].P2 := 20;
  EGrid[23, 11].Src := 'TT1';
  Rung(13, ekNO, 'KM3', ekSwitch, 'S4', ekNO, 'TIC1', ekContactor, 'KM4', '');
  Rung(15, ekNO, 'K0', ekSwitch, 'S5', ekNone, '', ekContactor, 'KM5', '');
  Rung(17, ekNO, 'KM5', ekNO, 'KM2', ekSwitch, 'S6', ekContactor, 'KM6', '');
  Rung(19, ekNO, 'KM1', ekNone, '', ekNone, '', ekMotor, 'M1', 'ExhaustFan01');
  Rung(21, ekNO, 'KM2', ekNone, '', ekNone, '', ekMotor, 'M2', 'BlowFan01');
  Rung(23, ekNO, 'KM3', ekNone, '', ekNone, '', ekMotor, 'M3', 'CombFan01');
  Rung(25, ekNO, 'KM4', ekNone, '', ekNone, '', ekMotor, 'M4', 'Furnace01');
  Rung(27, ekNO, 'KM4', ekNone, '', ekNone, '', ekMotor, 'M5', 'Zone1');
  Rung(29, ekNO, 'KM4', ekNone, '', ekNone, '', ekMotor, 'M6', 'Zone2');
  Rung(31, ekNO, 'KM5', ekNone, '', ekNone, '', ekMotor, 'M7', 'Dryer01');
  Rung(33, ekNO, 'KM6', ekNone, '', ekNone, '', ekMotor, 'M8', 'LoadFeeder');
  { the start and stop buttons: they start the two timelines }
  EP(31, 18, ekPBNO, 'SB1');
  EP(37, 18, ekPBNO, 'SB2');

  CurLayer := 2;
  e := Eq2(EQ_TIMELINE, 680, 40, 360, 130, 'Startup', EQS_STOP);
  Equips[e].Delay := 12;
  Equips[e].Src := 'SB1';
  TLPin(e, TLP_FIX, 0.5, 0.5, '', TLV_NONE, 0, '', TLV_FIX, 1, 'S1', TLV_NONE, 0, '');
  TLPin(e, TLP_FIX, 2, 0.5, '', TLV_NONE, 0, '', TLV_FIX, 1, 'S2', TLV_NONE, 0, '');
  TLPin(e, TLP_FIX, 4, 0.5, '', TLV_NONE, 0, '', TLV_FIX, 1, 'S3', TLV_NONE, 0, '');
  TLPin(e, TLP_FIX, 6, 0.5, '', TLV_NONE, 0, '', TLV_FIX, 1, 'S4', TLV_NONE, 0, '');
  TLPin(e, TLP_FIX, 8, 0.5, '', TLV_NONE, 0, '', TLV_FIX, 1, 'S5', TLV_NONE, 0, '');
  TLPin(e, TLP_FIX, 10.5, 0.5, '', TLV_NONE, 0, '', TLV_FIX, 1, 'S6', TLV_NONE, 0, '');
  e := Eq2(EQ_TIMELINE, 680, 210, 360, 130, 'Shutdown', EQS_STOP);
  Equips[e].Delay := 14;
  Equips[e].Src := 'SB2';
  TLPin(e, TLP_FIX, 0.5, 0.5, '', TLV_NONE, 0, '', TLV_FIX, 0, 'S6', TLV_NONE, 0, '');
  TLPin(e, TLP_FIX, 2.5, 0.5, '', TLV_NONE, 0, '', TLV_FIX, 0, 'S4', TLV_NONE, 0, '');
  TLPin(e, TLP_FIX, 6, 0.5, '', TLV_NONE, 0, '', TLV_FIX, 0, 'S3', TLV_NONE, 0, '');
  TLPin(e, TLP_FIX, 8.5, 0.5, '', TLV_NONE, 0, '', TLV_FIX, 0, 'S5', TLV_NONE, 0, '');
  TLPin(e, TLP_FIX, 11, 0.5, '', TLV_NONE, 0, '', TLV_FIX, 0, 'S2', TLV_NONE, 0, '');
  TLPin(e, TLP_FIX, 13, 0.5, '', TLV_NONE, 0, '', TLV_FIX, 0, 'S1', TLV_NONE, 0, '');

  CurLayer := 1;
  AddLabel(700, 470, 'CONTROL PANEL (page 3)'#10'SB1: start-up - exhaust fan, blow fan,'#10 +
    'combustion fan, burner, drum, feeder.'#10'SB2: shut-down in the other order; the'#10 +
    'fans run on to purge and cool.'#10'TIC1 holds the furnace at 180 C (TT1).'#10 +
    'ES1 (E-stop) drops everything.');
  AddLabel(700, 400, 'SB1 start      SB2 stop');
  Link(700, 660, 'Dryer', False, PAGE_PLANT, 1);
  Link(800, 660, 'Monitor', False, 3, 3);
  CurLayer := 0;
  ParkPage(p);

  { page 4: the monitor }
  p := AddPage('Monitor');
  CurPage := p;
  UnparkPage(p);
  Pages[p].Layers[0].Name := 'Meters';
  CurLayer := 0;
  e := Eq2(EQ_TREND, 24, 40, 640, 300, 'Dryer trend', EQS_STOP);
  Equips[e].Delay := 120;
  Equips[e].Src := 'TT1';
  Equips[e].Src2 := 'MT1';
  Equips[e].Src3 := 'KM4';
  Equips[e].Src4 := 'KM6';
  e := Eq2(EQ_TREND, 24, 380, 300, 110, 'Product', EQS_STOP);
  Equips[e].Mode := 1;
  Equips[e].Delay := 120;
  Equips[e].Src := 'WT1';
  e := Eq2(EQ_TREND, 364, 380, 300, 110, 'Dust', EQS_STOP);
  Equips[e].Mode := 1;
  Equips[e].Delay := 120;
  Equips[e].Src := 'WT2';
  e := Eq2(EQ_CONTROLLER, 720, 40, 196, 128, 'Burner TIC1', EQS_STOP);
  Equips[e].Src := 'TIC1';
  e := Eq2(EQ_DIGITAL, 720, 200, 196, 56, 'Furnace C', EQS_STOP);
  Equips[e].Src := 'TT1';
  Equips[e].RMax := 300;
  e := Eq2(EQ_DIGITAL, 720, 296, 196, 56, 'Product moisture %', EQS_STOP);
  Equips[e].Src := 'MT1';
  e := Eq2(EQ_DIGITAL, 720, 392, 196, 56, 'Product kg', EQS_STOP);
  Equips[e].Src := 'WT1';
  Equips[e].RMax := 200;
  e := Eq2(EQ_DIGITAL, 720, 488, 196, 56, 'Dust kg', EQS_STOP);
  Equips[e].Src := 'WT2';
  Equips[e].RMax := 200;
  AddLabel(24, 540, 'MONITOR (page 4)'#10'The furnace temperature, the moisture of the'#10 +
    'dried product, the burner (KM4) and the feeder'#10'(KM6) as events, and what the bins hold.');
  Link(24, 640, 'Dryer', False, PAGE_PLANT, 1);
  Link(124, 640, 'Control panel', False, 2, 2);
  ParkPage(p);
  CurPage := PAGE_PLANT;
  UnparkPage(PAGE_PLANT);
end;

{ 32. A PVC dry blend plant, as on a mixing plant's HMI screen. Page 1 "Mixing
      plant": three raw material lines (CaCO3, regrind, PVC + additives) are
      conveyed (XM7.14) into weigh hopper WI7.50; it empties through V7.53 into
      the hot mixer T3, which also takes the pre-weighed additives (XM8.03,
      V8.03); T3 empties through VT3 into the cool mixer T4; its batch is blown
      (XM9.01) up to silo H9.3, whose rotary valve XM9.03 feeds the conveying
      line (XM9.13) to the extruder. Page 3 "Batch control": the dosing flow
      chart, the mixing timeline, the AUTO switch and the level switches. Page 4
      "Trends". The layout comes with the HMI blue background. }
procedure Example32;
var
  e, k: Integer;
const
  RawX: array[0..2] of Integer = (2, 5, 8);
  RawName: array[0..2] of string = ('V7.56', 'V7.57', 'V7.58');
  RawLabel: array[0..2] of string = ('CaCO3', 'REGRIND', 'PVC +'#10'ADDITIVES');
begin
  Pages[PAGE_PLANT].Name := 'Mixing plant';
  Pages[PAGE_PLANT].NLayers := 3;
  Pages[PAGE_PLANT].Layers[2].Name := 'Equipment';
  LayoutBg := 3;
  CurLayer := LAYER_PROCESS;
  { the raw material lines: CaCO3 (sand), regrind (sand + fluff), PVC + additives (fluff) }
  Feeder(2, 16, 0, 0, 0, 3000, 10, 90);
  Feeder(5, 16, 0, 0, 1500, 1500, 10, 90);
  Feeder(8, 16, 0, 0, 3000, 0, 10, 90);
  for k := 0 to 2 do
  begin
    PipeLine(RawX[k], 16, RawX[k], 3, 3);
    Device(RawX[k], 14, ckBlower, 80, 3);
  end;
  { the conveying header into the weigh hopper }
  PipeLine(2, 3, 14, 3, 3);
  Device(11, 3, ckBlower, 60, 0);
  PipeLine(14, 3, 14, 5, 3);
  Device(14, 5, ckDrop, 100);
  { weigh hopper WI7.50 (a silo), its outlet one-way down to the hot mixer }
  MakePipe(14, 10, 3);
  SetKind(14, 10, ckSilo);
  Grid[14, 10].Feed := 100;
  PipeLine(14, 10, 14, 13, 3);
  Device(14, 11, ckCheck, -1, 1);
  Device(14, 13, ckDrop, 100);
  { the pre-weighed additives (oil) join the drop into T3 }
  Feeder(26, 12, 0, 1200, 0, 0, 0, 60);
  PipeLine(26, 12, 14, 12, 3);
  Device(24, 12, ckBlower, 50, 2);
  { hot mixer T3, then over to the cool mixer T4 }
  MakePipe(14, 20, 3);
  SetKind(14, 20, ckSilo);
  Grid[14, 20].Feed := 100;
  PipeLine(14, 20, 14, 22, 3);
  PipeLine(14, 22, 19, 22, 3);
  Device(16, 22, ckBlower, 60, 0);
  PipeLine(19, 22, 19, 25, 3);
  Device(19, 25, ckDrop, 100);
  MakePipe(19, 30, 3);
  SetKind(19, 30, ckSilo);
  Grid[19, 30].Feed := 100;
  { the transport line up to silo H9.3 }
  PipeLine(19, 30, 19, 31, 3);
  PipeLine(19, 31, 30, 31, 3);
  Device(22, 31, ckBlower, 95, 0);
  PipeLine(30, 31, 30, 4, 3);
  PipeLine(30, 4, 36, 4, 3);
  PipeLine(36, 4, 36, 11, 3);
  Device(36, 11, ckDrop, 100);
  MakePipe(36, 16, 3);
  SetKind(36, 16, ckSilo);
  Grid[36, 16].Feed := 100;
  { rotary valve and conveying line to the extruder }
  PipeLine(36, 16, 36, 25, 3);
  PipeLine(36, 25, 41, 25, 3);
  Device(38, 25, ckBlower, 70, 0);
  PipeLine(41, 25, 41, 27, 3);
  Device(41, 27, ckDrop, 100);
  FloorBucket(41, 110, 130);

  CurLayer := 2;
  for k := 0 to 2 do
  begin
    e := Eq2(EQ_SLIDE, RawX[k] * CELL - 6, 424 + k * 56, 36, 36, RawName[k], EQS_STOP);
    Equips[e].LinkX := RawX[k];
    Equips[e].LinkY := 16;
  end;
  e := Eq2(EQ_BLOWER, 212, 100, 80, 72, 'XM7.14', EQS_RUN);
  Equips[e].LinkX := 11;
  Equips[e].LinkY := 3;
  e := Eq2(EQ_SILO, 290, 128, 92, 150, 'WI7.50', EQS_STOP);
  Equips[e].LinkX := 14;
  Equips[e].LinkY := 10;
  e := Eq2(EQ_SLIDE, 380, 252, 36, 30, 'V7.53', EQS_STOP);
  Equips[e].LinkX := 14;
  Equips[e].LinkY := 10;
  e := Eq2(EQ_SCREW, 600, 330, 170, 34, 'XM8.03', EQS_RUN);
  Equips[e].LinkX := 24;
  Equips[e].LinkY := 12;
  e := Eq2(EQ_SLIDE, 664, 252, 36, 30, 'V8.03', EQS_STOP);
  Equips[e].LinkX := 26;
  Equips[e].LinkY := 12;
  e := Eq2(EQ_SILO, 286, 372, 100, 128, 'T3', EQS_STOP);
  Equips[e].LinkX := 14;
  Equips[e].LinkY := 20;
  e := Eq2(EQ_MOTOR, 206, 440, 70, 44, 'T3 motor', EQS_STOP);
  Equips[e].LinkX := 14;
  Equips[e].LinkY := 20;
  e := Eq2(EQ_SLIDE, 380, 500, 36, 30, 'VT3', EQS_STOP);
  Equips[e].LinkX := 14;
  Equips[e].LinkY := 20;
  e := Eq2(EQ_SILO, 404, 612, 112, 124, 'T4', EQS_STOP);
  Equips[e].LinkX := 19;
  Equips[e].LinkY := 30;
  e := Eq2(EQ_MOTOR, 324, 684, 70, 44, 'T4 motor', EQS_STOP);
  Equips[e].LinkX := 19;
  Equips[e].LinkY := 30;
  e := Eq2(EQ_SLIDE, 500, 736, 36, 30, 'VT4', EQS_STOP);
  Equips[e].LinkX := 19;
  Equips[e].LinkY := 30;
  e := Eq2(EQ_BLOWER, 556, 680, 84, 76, 'XM9.01', EQS_RUN);
  Equips[e].LinkX := 22;
  Equips[e].LinkY := 31;
  e := Eq2(EQ_SILO, 816, 150, 120, 258, 'H9.3', EQS_STOP);
  Equips[e].LinkX := 36;
  Equips[e].LinkY := 16;
  e := Eq2(EQ_MOTOR, 770, 420, 60, 40, 'XM9.03', EQS_STOP);
  Equips[e].LinkX := 36;
  Equips[e].LinkY := 16;
  e := Eq2(EQ_BLOWER, 852, 640, 72, 66, 'XM9.13', EQS_RUN);
  Equips[e].LinkX := 38;
  Equips[e].LinkY := 25;
  { the weigh panel }
  e := Eq2(EQ_DIGITAL, 428, 64, 132, 52, 'GROSS WEIGHT %', EQS_STOP);
  Equips[e].Src := 'WI7.50';
  Equips[e].RMax := 100;
  e := Eq2(EQ_DIGITAL, 570, 64, 132, 52, 'T3 BATCH %', EQS_STOP);
  Equips[e].Src := 'T3';
  Equips[e].RMax := 100;
  e := Eq2(EQ_DIGITAL, 428, 152, 132, 52, 'H9.3 LEVEL %', EQS_STOP);
  Equips[e].Src := 'H9.3';
  Equips[e].RMax := 100;
  e := Eq2(EQ_DIGITAL, 570, 152, 132, 52, 'MIXING s', EQS_STOP);
  Equips[e].Src := 'Mixing';
  Equips[e].RMax := 60;

  Notes;
  AddFrame(418, 24, 292, 204, 'WI7.50 - weigh panel');
  Frames[0].Color := 1;
  for k := 0 to 2 do AddLabel(RawX[k] * CELL + 14, 186 + k * 34, RawLabel[k]);
  AddLabel(560, 230, 'PRE WEIGHED ADDITIVES');
  AddLabel(220, 560, 'HOT & COOL'#10'MIXERS');
  AddLabel(944, 160, 'H9.3'#10'silo');
  AddLabel(900, 560, 'TO EXTRUDER');
  AddLabel(8, 640, 'Set point 15 %: CaCO3 to 6 %,'#10'regrind to 10 %, PVC to 15 %.'#10 +
    'Switch AUTO on page 3.');
  Link(8, 720, 'Batch control', False, 2, 2);
  Link(140, 720, 'Trends', False, 3, 3);
end;

{ pages 3 and 4 of example 32, after its About page }
procedure Example32Pages;
var
  p, e, k: Integer;
  d: array[1..6] of Integer;
  s: array[0..3] of Integer;
  a: array[0..9] of Integer;

  function Node(Kind: Integer; X, Y, W, H: Single; const Caption: string): Integer;
  begin
    Result := FlowAdd(Kind, X, Y);
    FlowNodes[Result].W := W;
    FlowNodes[Result].H := H;
    FlowNodes[Result].Caption := Caption;
  end;

  function Act(X, Y: Single; Run: Boolean; const Target: string): Integer;
  begin
    if Run then Result := Node(FN_ACTION, X, Y, 120, 36, 'Open ' + Target)
    else Result := Node(FN_ACTION, X, Y, 120, 36, 'Close ' + Target);
    if Run then FNAct(Result, FA_RUN, Target) else FNAct(Result, FA_STOP, Target);
  end;

  { a row of three valve actions (one open), then End }
  procedure Row(Y: Single; Open: Integer; From: Integer; No: Boolean);
  var
    j, prev, n: Integer;
  begin
    prev := From;
    for j := 0 to 2 do
    begin
      n := Act(200 + j * 140, Y, j = Open, 'V7.5' + Chr(Ord('6') + j));
      FlowConnect(prev, n, No and (j = 0));
      prev := n;
    end;
    n := Node(FN_END, 620, Y + 4, 80, 28, 'End');
    FlowConnect(prev, n, False);
  end;

begin
  ParkPage(PAGE_PLANT);
  { page 3: batch control }
  p := AddPage('Batch control');
  CurPage := p;
  UnparkPage(p);
  Pages[p].NLayers := 4;
  Pages[p].Layers[0].Name := 'Flow chart';
  Pages[p].Layers[1].Name := 'Notes';
  Pages[p].Layers[2].Name := 'Timeline';
  Pages[p].Layers[3].Name := 'Electrical';
  CurLayer := 0;
  { dosing: weigh in CaCO3, regrind and PVC one after another, then start the mixing timeline }
  k := Node(FN_START, 35, 16, 120, 30, 'Dosing');
  d[1] := Node(FN_DECISION, 20, 64, 150, 56, 'AUTO on?');
  FNRead(d[1], 'AUTO', FOP_ON, 0);
  d[2] := Node(FN_DECISION, 20, 136, 150, 56, 'Mixing idle?');
  FNRead(d[2], 'Mixing', FOP_OFF, 0);
  d[3] := Node(FN_DECISION, 20, 208, 150, 56, 'H9.3 room?');
  FNRead(d[3], 'H9.3', FOP_LT, 85);
  d[4] := Node(FN_DECISION, 20, 280, 150, 56, 'CaCO3 in?');
  FNRead(d[4], 'WI7.50', FOP_GE, 6);
  d[5] := Node(FN_DECISION, 20, 352, 150, 56, 'Regrind in?');
  FNRead(d[5], 'WI7.50', FOP_GE, 10);
  d[6] := Node(FN_DECISION, 20, 424, 150, 56, 'PVC in? (SP)');
  FNRead(d[6], 'WI7.50', FOP_GE, 15);
  FlowConnect(k, d[1], False);
  for k := 1 to 5 do FlowConnect(d[k], d[k + 1], False);
  { the valves shut: not on, mixing, silo full, or the batch is weighed }
  s[0] := Act(760, 64, False, 'V7.56');
  s[1] := Act(760, 120, False, 'V7.57');
  s[2] := Act(760, 176, False, 'V7.58');
  s[3] := Node(FN_END, 780, 230, 80, 28, 'End');
  FlowConnect(s[0], s[1], False);
  FlowConnect(s[1], s[2], False);
  FlowConnect(s[2], s[3], False);
  FlowConnect(d[1], s[0], True);
  FlowConnect(d[2], s[0], True);
  FlowConnect(d[3], s[0], True);
  { dose the one that is short }
  Row(290, 0, d[4], True);
  Row(362, 1, d[5], True);
  Row(434, 2, d[6], True);
  a[0] := Node(FN_ACTION, 20, 500, 150, 36, 'Batch ready');
  FNAct(a[0], FA_TAG, 'BATCH_READY');
  FlowConnect(d[6], a[0], False);
  FlowConnect(a[0], s[0], False);
  { the silo's rotary valve: stop it when H9.3 runs low (LSL9.03) }
  a[1] := Node(FN_START, 35, 572, 120, 30, 'Silo out');
  a[2] := Node(FN_DECISION, 20, 616, 150, 56, 'H9.3 not low?');
  FNRead(a[2], 'H9.3', FOP_GT, 3);
  a[3] := Act(20, 690, True, 'XM9.03');
  FlowNodes[a[3]].Caption := 'Run XM9.03';
  a[4] := Act(200, 626, False, 'XM9.03');
  FlowNodes[a[4]].Caption := 'Stop XM9.03';
  a[5] := Node(FN_END, 35, 746, 80, 28, 'End');
  a[6] := Node(FN_END, 340, 630, 80, 28, 'End');
  FlowConnect(a[1], a[2], False);
  FlowConnect(a[2], a[3], False);
  FlowConnect(a[2], a[4], True);
  FlowConnect(a[3], a[5], False);
  FlowConnect(a[4], a[6], False);
  { the level switches and the weight }
  a[7] := Node(FN_DISPLAY, 880, 290, 160, 52, 'LSH9.03 (85 %)');
  FNRead(a[7], 'H9.3', FOP_GE, 85);
  a[8] := Node(FN_DISPLAY, 880, 356, 160, 52, 'LSL9.03 (3 %)');
  FNRead(a[8], 'H9.3', FOP_LE, 3);
  a[9] := Node(FN_DISPLAY, 880, 422, 160, 52, 'WI7.50 %');
  FNRead(a[9], 'WI7.50', FOP_GE, 15);

  { the mixing cycle: started by the weighed batch }
  CurLayer := 2;
  e := Eq2(EQ_TIMELINE, 470, 560, 570, 130, 'Mixing', EQS_STOP);
  Equips[e].Delay := 40;
  Equips[e].Src := 'BATCH_READY';
  TLPin(e, TLP_FIX, 0, 12, '', TLV_FIX, 0, 'V7.53', TLV_FIX, 1, 'V7.53', TLV_FIX, 0, 'V7.53');
  TLPin(e, TLP_FIX, 0, 30, '', TLV_FIX, 0, 'T3 motor', TLV_FIX, 1, 'T3 motor', TLV_FIX, 0, 'T3 motor');
  TLPin(e, TLP_FIX, 10, 4, '', TLV_FIX, 0, 'V8.03', TLV_FIX, 1, 'V8.03', TLV_FIX, 0, 'V8.03');
  TLPin(e, TLP_FIX, 20, 10, '', TLV_FIX, 0, 'VT3', TLV_FIX, 1, 'VT3', TLV_FIX, 0, 'VT3');
  TLPin(e, TLP_FIX, 20, 20, '', TLV_FIX, 0, 'T4 motor', TLV_FIX, 1, 'T4 motor', TLV_FIX, 0, 'T4 motor');
  TLPin(e, TLP_FIX, 30, 10, '', TLV_FIX, 0, 'VT4', TLV_FIX, 1, 'VT4', TLV_FIX, 0, 'VT4');
  TLPin(e, TLP_INPUT, 12, 1, 'WI7.50', TLV_NONE, 0, '', TLV_LIVE, 0, '', TLV_HELD, 0, 'LEFT_IN_WI');

  CurLayer := 3;
  EP(40, 2, ekSwitch, 'AUTO');
  EGrid[40, 2].On := True;

  CurLayer := 1;
  AddLabel(900, 84, 'AUTO (click):'#10'the plant runs'#10'batches.');
  AddLabel(200, 490, 'DOSING (flow chart, every scan):'#10'the valve of the material that is'#10 +
    'short opens; at the set point the'#10'batch is ready and starts Mixing.');
  AddLabel(470, 700, 'MIXING (timeline, one cycle per batch): V7.53 empties'#10 +
    'WI7.50 into T3, V8.03 adds the additives, VT3 sends'#10'the hot batch to T4, VT4 blows it to silo H9.3.');
  Link(880, 500, 'Mixing plant', False, PAGE_PLANT, 1);
  Link(880, 524, 'Trends', False, 3, 3);
  CurLayer := 0;
  ParkPage(p);

  { page 4: trends }
  p := AddPage('Trends');
  CurPage := p;
  UnparkPage(p);
  Pages[p].Layers[0].Name := 'Trends';
  CurLayer := 0;
  e := Eq2(EQ_TREND, 24, 40, 640, 300, 'Levels', EQS_STOP);
  Equips[e].Delay := 240;
  Equips[e].Src := 'WI7.50';
  Equips[e].Src2 := 'T3';
  Equips[e].Src3 := 'T4';
  Equips[e].Src4 := 'H9.3';
  e := Eq2(EQ_TREND, 24, 380, 640, 220, 'Dosing valves', EQS_STOP);
  Equips[e].Delay := 240;
  Equips[e].Src := 'V7.56';
  Equips[e].Src2 := 'V7.57';
  Equips[e].Src3 := 'V7.58';
  Equips[e].Src4 := 'V7.53';
  AddLabel(700, 60, 'TRENDS (page 4)'#10'Levels: weigh hopper, hot and'#10'cool mixer, silo H9.3.'#10 +
    'Dosing valves: open = 100.');
  Link(700, 160, 'Mixing plant', False, PAGE_PLANT, 1);
  Link(700, 184, 'Batch control', False, 2, 2);
  ParkPage(p);
  CurPage := PAGE_PLANT;
  UnparkPage(PAGE_PLANT);
end;

{ 33. A belt conveyor system, as on a technical drawing (side elevation): an
      inclined (15 deg) belt conveyor BC-01, 6620 mm long, its feed hopper over
      the tail end and the drive (gear motor) at the head end, which drops the
      material into a bin. A start / stop circuit with E-stop and overload
      runs drive U1 (speed from RV1); the feed gate opens only while the belt
      runs, so nothing piles on a stopped belt. }
procedure Example33;
var
  e: Integer;
begin
  ElecLayers;
  CurLayer := LAYER_PROCESS;
  { the material and the feed hopper (14) over the tail end }
  Feeder(30, 13, 0, 0, 200, 3000, 0, 45);
  PipeLine(30, 13, 30, 19, 3);
  Device(30, 19, ckDrop, 100);
  MakePipe(30, 24, 3);
  SetKind(30, 24, ckHopper);
  PipeLine(30, 24, 30, 26, 3);
  Device(30, 26, ckDrop, 100);
  { the bin under the head end }
  FloorBucket(3, 150, 110);

  CurLayer := 2;
  { the conveyor: 15 deg, rising to the left, where the drive is (the belt runs to the left) }
  e := Eq2(EQ_BELT, 150, 470, 640, 240, 'BC-01', EQS_STOP);
  Equips[e].RMin := -15;
  Equips[e].Flip := True;
  Equips[e].Level := 70;
  e := Eq2(EQ_SLIDE, 742, 300, 40, 36, 'FeedGate', EQS_STOP);
  Equips[e].LinkX := 30;
  Equips[e].LinkY := 13;
  e := Eq2(EQ_DIGITAL, 330, 300, 150, 52, 'Belt speed %', EQS_STOP);
  Equips[e].Src := 'U1';
  e := Eq2(EQ_DIGITAL, 330, 384, 150, 52, 'Delivered kg', EQS_STOP);
  Equips[e].Src := 'WT1';
  Equips[e].RMax := 200;

  CurLayer := 3;
  Ladder(26, 43, 34, 1, 10);
  { start / stop with seal-in, E-stop and the overload's contact }
  EWireLine(26, 3, 43, 3);
  EP(28, 3, ekEStop, 'ES1');
  EP(30, 3, ekPBNC, 'SB0');
  EP(32, 3, ekPBNO, 'SB1');
  SealIn(32, 32, 3, 'KM1');
  EP(36, 3, ekNC, 'OL1');
  EP(40, 3, ekContactor, 'KM1');
  { the drive (VFD) of the belt, its overload, speed from RV1 }
  EWireLine(26, 6, 43, 6);
  EP(30, 6, ekNO, 'KM1');
  EP(35, 6, ekOL, 'OL1');
  EP(40, 6, ekDrive, 'U1', 'BC-01');
  EGrid[40, 6].Src := 'RV1';
  { the feed gate opens only while the belt runs }
  EWireLine(26, 8, 43, 8);
  EP(30, 8, ekNO, 'KM1');
  EP(40, 8, ekMotor, 'M2', 'FeedGate');
  EWireLine(26, 10, 43, 10);
  EP(30, 10, ekNO, 'KM1');
  EP(40, 10, ekLamp, 'H1');
  EP(28, 12, ekPot, 'RV1');
  EGrid[28, 12].P1 := 70;
  EP(3, 33, ekWeightTx, 'WT1');

  Notes;
  AddLabel(8, 24, 'COMPONENTS'#10' 1 Drive pulley'#10' 2 Gear motor'#10' 7 Conveyor belt'#10' 8 Tail pulley'#10 +
    '10 Upper roller set'#10'11 Troughing idlers'#10'12 Lower return rollers'#10'14 Feed hopper'#10 +
    '16 Support legs');
  AddLabel(196, 24, 'KEY FEATURES'#10'Belt width       650 mm'#10'Hopper top  2400 x 1200'#10 +
    'Hopper bottom    380 mm'#10'Length (horiz.) 6620 mm'#10'Inclination     15 deg'#10 +
    'Head end height 2337 mm'#10'Tail end height 2035 mm');
  AddLabel(470, 440, 'head (drive) <-  BC-01, 15 deg');
  AddLabel(8, 176, 'HOW TO USE'#10'Click SB1: the belt runs,'#10'the feed gate opens.'#10 +
    'RV1 (wheel): belt speed.'#10'SB0 or ES1: stop.');
  AddLabel(760, 400, 'FEED HOPPER (14)'#10'tail end');
end;

{ 34. Pieces: item feeders drop whole objects. Line 1: bottles onto a flat belt,
      photo sensor PE1 counts each one (CNT1) as it goes into the crate; at 12
      the crate is full: the feeder and the belt stop and H1 lights; SB2 resets
      the count. Line 2: glasses, boxes and dolls (mixed) up an inclined belt
      into the bin. }
procedure Example34;
var
  e: Integer;
begin
  ElecLayers;
  CurLayer := LAYER_PROCESS;
  { the crate at the end of line 1, the bin at the end of line 2 }
  AddBucket(500, 330, 110, 80);
  FloorBucket(40, 156, 110);

  CurLayer := 2;
  e := Eq2(EQ_ITEMFEEDER, 48, 60, 64, 104, 'Bottles', EQS_STOP);
  Equips[e].Mode := PK_BOTTLE;
  Equips[e].RMin := 2;
  e := Eq2(EQ_BELT, 20, 220, 420, 50, 'Belt01', EQS_STOP);
  Equips[e].Level := 50;
  e := Eq2(EQ_ITEMFEEDER, 600, 300, 64, 104, 'Mixed', EQS_STOP);
  Equips[e].Mode := PK_MIXED;
  Equips[e].RMin := 3.5;
  e := Eq2(EQ_BELT, 580, 500, 380, 200, 'Belt02', EQS_STOP);
  Equips[e].RMin := 12;
  Equips[e].Level := 60;
  e := Eq2(EQ_DIGITAL, 760, 110, 160, 52, 'Bottles counted', EQS_STOP);
  Equips[e].Src := 'CNT1';
  Equips[e].RMax := 12;
  e := Eq2(EQ_DIGITAL, 760, 190, 160, 52, 'Crate kg', EQS_STOP);
  Equips[e].Src := 'WT1';
  Equips[e].RMax := 20;
  e := Eq2(EQ_DIGITAL, 760, 270, 160, 52, 'Bin kg', EQS_STOP);
  Equips[e].Src := 'WT2';
  Equips[e].RMax := 50;

  CurLayer := 3;
  Ladder(1, 22, 11, 17, 33);
  { SB1 starts, SB0 stops: K1 }
  EWireLine(1, 19, 22, 19);
  EP(3, 19, ekPBNC, 'SB0');
  EP(5, 19, ekPBNO, 'SB1');
  SealIn(5, 5, 19, 'K1');
  EP(19, 19, ekRelay, 'K1');
  { line 1 runs until the crate is full (CNT1) }
  EWireLine(1, 21, 22, 21);
  EP(3, 21, ekNO, 'K1');
  EP(7, 21, ekNC, 'CNT1');
  EP(19, 21, ekMotor, 'M1', 'Belt01');
  EWireLine(1, 23, 22, 23);
  EP(3, 23, ekNO, 'K1');
  EP(7, 23, ekNC, 'CNT1');
  EP(19, 23, ekMotor, 'M2', 'Bottles');
  { each bottle through PE1 counts one; SB2 resets }
  EWireLine(1, 25, 22, 25);
  EP(3, 25, ekNO, 'PE1');
  EP(19, 25, ekCounter, 'CNT1');
  EGrid[19, 25].P1 := 12;
  EGrid[19, 25].Src := 'SB2';
  EWireLine(1, 27, 22, 27);
  EP(3, 27, ekNO, 'CNT1');
  EP(19, 27, ekLamp, 'H1');
  { line 2: S2 switches it (K2) }
  EWireLine(1, 29, 22, 29);
  EP(3, 29, ekNO, 'K1');
  EP(7, 29, ekSwitch, 'S2');
  EGrid[7, 29].On := True;
  EP(19, 29, ekRelay, 'K2');
  EWireLine(1, 31, 22, 31);
  EP(3, 31, ekNO, 'K2');
  EP(19, 31, ekMotor, 'M3', 'Belt02');
  EWireLine(1, 33, 22, 33);
  EP(3, 33, ekNO, 'K2');
  EP(19, 33, ekMotor, 'M4', 'Mixed');
  EP(14, 15, ekPBNO, 'SB2');
  { the sensors }
  EP(17, 8, ekPhoto, 'PE1');
  EP(21, 18, ekWeightTx, 'WT1');
  EP(40, 33, ekWeightTx, 'WT2');

  Notes;
  AddLabel(140, 70, 'LINE 1: BOTTLES'#10'PE1 counts each bottle'#10'into the crate; at 12'#10 +
    'the line stops, H1 on.'#10'SB2 resets the count.');
  AddLabel(700, 380, 'LINE 2: MIXED'#10'glasses, boxes, dolls'#10'up the 12 deg belt.');
  AddLabel(560, 460, 'HOW TO USE: click SB1 (start), SB0 (stop);'#10'S2 switches line 2.');
end;

{ 35. A shipping dock, after a warehouse plan, seen from the side: three order
      pickers take boxes from their standard racks and put them on the roller
      conveyor, which carries them to the box van at the dock door; the dock
      worker lifts each one off the end of the line into the van. PE1 counts
      what is shipped; SB1 / SB0 start and stop the conveyor. }
procedure Example35;
var
  e, k: Integer;
const
  RackX: array[0..2] of Integer = (470, 680, 890);
  PickKind: array[0..2] of Integer = (PK_BOX, PK_MIXED, PK_BOX);
begin
  ElecLayers;
  CurLayer := LAYER_PROCESS;
  { the van's cargo floor: what the dock worker puts in it }
  AddBucket(196, 596, 176, 164);

  CurLayer := 2;
  e := Eq2(EQ_VAN, 6, 560, 312, 250, 'Box van', EQS_STOP);
  for k := 0 to 2 do
  begin
    e := Eq2(EQ_RACK, RackX[k], 470, 110, 342, 'Rack' + Chr(Ord('1') + k), EQS_STOP);
    e := Eq2(EQ_WORKER, RackX[k] + 30, 662, 56, 150, 'Picker' + Chr(Ord('1') + k), EQS_RUN);
    Equips[e].Mode := 0;
    Equips[e].Level := PickKind[k];
    Equips[e].RMin := 4.5 + k * 0.7;
    Equips[e].RMax := 25;
  end;
  e := Eq2(EQ_CONVEYOR, 380, 690, 650, 122, 'Conveyor01', EQS_STOP);
  Equips[e].Flip := True;
  Equips[e].Level := 40;
  e := Eq2(EQ_WORKER, 318, 662, 56, 150, 'DockWorker', EQS_RUN);
  Equips[e].Mode := 1;
  Equips[e].Level := PK_MIXED;
  Equips[e].RMin := 0.7;
  e := Eq2(EQ_DIGITAL, 470, 200, 160, 52, 'Shipped', EQS_STOP);
  Equips[e].Src := 'CNT1';
  Equips[e].RMax := 99;
  e := Eq2(EQ_DIGITAL, 650, 200, 160, 52, 'In the van kg', EQS_STOP);
  Equips[e].Src := 'WT1';
  Equips[e].RMax := 100;

  CurLayer := 3;
  Ladder(26, 43, 34, 1, 7);
  EWireLine(26, 3, 43, 3);
  EP(29, 3, ekPBNC, 'SB0');
  EP(31, 3, ekPBNO, 'SB1');
  SealIn(31, 31, 3, 'KM1');
  EP(40, 3, ekContactor, 'KM1');
  EWireLine(26, 6, 43, 6);
  EP(30, 6, ekNO, 'KM1');
  EP(40, 6, ekMotor, 'M1', 'Conveyor01');
  EWireLine(26, 7, 43, 7);
  EP(30, 7, ekNO, 'PE1');
  EP(40, 7, ekCounter, 'CNT1');
  EGrid[40, 7].P1 := 999;
  EP(16, 28, ekPhoto, 'PE1');
  EP(8, 33, ekWeightTx, 'WT1');

  Notes;
  AddLabel(24, 470, 'BOX VAN'#10'at the dock door');
  AddLabel(200, 120, 'SHIPPING DOCK'#10'Order pickers put boxes from the racks'#10 +
    'on the roller conveyor; the dock worker'#10'loads each one into the box van.'#10 +
    'Click SB1: the conveyor runs. SB0 stops it.');
  AddLabel(840, 430, 'STANDARD RACKS');
  AddLabel(450, 440, 'ORDER PICKERS AT THE RACKS  ->  ROLLER CONVEYOR  ->  DOCK');
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
    27: Example27;
    28: Example28;
    29: Example29;
    30: Example30;
    31: Example31;
    32: Example32;
    33: Example33;
    34: Example34;
    35: Example35;
  end;
  if n = 7 then PlantLinks(24, 660)
  else if n = 27 then PlantLinks(900, 450)
  else if n = 28 then PlantLinks(780, 360)
  else if n = 29 then PlantLinks(624, 580)
  else if n = 31 then PlantLinks
  else if n = 32 then PlantLinks(8, 560)
  else if n = 33 then PlantLinks(230, 740)
  else if n = 34 then PlantLinks
  else if n = 35 then PlantLinks(24, 24)
  else if n >= 14 then PlantLinks(24, 24)
  else if n >= 10 then PlantLinks(920, 690)
  else PlantLinks;
  AddAboutPage(n);
  if n = 24 then Example24Pages;
  if n = 27 then Example27Pages;
  if n = 31 then Example31Pages;
  if n = 32 then Example32Pages;
  { new parts the user draws go on the Process layer }
  SetActiveLayer(LAYER_PROCESS);
end;

end.
