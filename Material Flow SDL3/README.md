# Material Flow Simulator (SDL3 + Lazarus / Free Pascal)

This is an interactive 2D simulator for moving water, oil, fluff and sand through pipes, mixed with air. You route piping on a grid, add blowers, suction heads, nozzles, drop outlets and valves, and then watch the material fall into buckets and overflow them.

## Build & run

- Open `MaterialFlow.lpi` in Lazarus, then press **Run** (F9). You can also build from a command line:
  `C:\lazarus\lazbuild.exe MaterialFlow.lpi`
- `SDL3.dll` must sit next to `MaterialFlow.exe`. It's already in this folder. The app only uses `SDL3.dll`; SDL3_image, SDL3_ttf and SDL3_mixer aren't needed.
- The project doesn't depend on the LCL. It uses a small hand-written SDL3 binding (`src/sdl3min.pas`), so it needs no third-party Pascal packages.

## Files

| File | Purpose |
|---|---|
| `MaterialFlow.lpr` | Program entry point |
| `src/sdl3min.pas` | Minimal SDL3 import unit (window, renderer, events, debug text) |
| `src/simcore.pas` | Simulation: pipe network, air-pressure solver, particles, buckets, demo layout |
| `src/mfapp.pas` | Rendering, control panel, File menu, mouse/keyboard editing |
| `src/layoutio.pas` | Save/load of layouts (`.mflow` text files) |
| `src/edithist.pas` | Undo / redo history |
| `src/mftheme.pas` | The seven colour themes |
| `src/mfpages.pas` | Pages, layers and frame popups |
| `src/elec.pas` | Electrical circuits: wiring grid, devices and the circuit solver |
| `src/fluid.pas` | Pneumatic and hydraulic circuits: parts, ports and the pressure solver |
| `src/physics.pas` | Physics settings: load / save `.mfphys`, the Physics Lab test scenes |
| `src/shapes.pas` | Custom equipment shapes: load / save `.mfshape` |
| `src/plantbus.pas` | The plant bus: what the pages tell each other while they all run |
| `src/mfexamples.pas` | The 26 built-in example layouts |
| `examples/*.mflow` | The same 26 examples, plus the original demo, as files you can open |

## Pages, layers, links and frame popups

A layout is a small set of screens, like an HMI / SCADA project.

### Pages (up to 20)

- Each page is a full canvas of its own: its own parts, feeders, buckets, labels, frames, links, gravity and material.
- Every page runs all the time, not only the one on screen, and pages can work together (see **Every page at once** below).
- The menu bar shows the current page, e.g. **< Page 1/2: Plant >**. The arrows, **PgUp / PgDn** and link buttons all change the page. Clicking the page name opens the Page & Layer panel.
- Undo works page by page: going to another page starts a fresh undo history.

### Layers (up to 5 per page)

- Every part, bucket, label, frame and link sits on one layer of its page.
- New items go on the **active** layer.
- A **hidden** layer is not drawn and cannot be picked. Hidden parts keep working: a hidden blower still blows.
- A **locked** layer is drawn but cannot be picked, moved, erased or changed. A pipe drag stops at it.
- Pasted items go on the active layer. Moved and rotated items keep their own layer.

### Links

- The **Link** tool places a button on the canvas. A link either jumps to a page (shown as **> name**) or opens a frame popup (shown as **? name**).
- With the **Select** tool, clicking a link follows it.
- To edit a link instead, select it with the Link tool or **Ctrl+click**. Drag it to move it; double-click it to type its caption.
- In Properties, a link has its caption, **Follow it now**, **A page / A frame popup**, the target (**< >**), its colour and **Delete**. A caption you never changed follows the target's name.

### Frame popups (up to 20 per layout)

- A frame popup is a small window that opens over the canvas: notes, instructions or an alarm text.
- It has a title, text, a colour and, optionally, a **Go to: page** button.
- It opens from a link (or the panel's **Show** button). It closes with **x**, **Close**, **Esc**, or a click beside it.

### Page & Layer panel (F6)

- **Pages:** one button per page. Click one to go to it; double-click the current page to rename it.
- **Page buttons:**
  - **Add** a new empty page.
  - **Copy** the current page.
  - **Delete** the current page. This needs a second click and can't be undone; links to a deleted page lose their target.
  - **< >** move the page earlier or later. Links keep pointing at the same page.
  - **Rename**.
- **Layers:** one row per layer.
  - Click a layer's name to make it active; double-click to rename it.
  - **Shown / Hidden** and **Open / Locked** toggle visibility and locking.
- **Layer buttons:**
  - **Add layer**.
  - **Delete**. This needs a second click; the layer's items move down one layer.
  - **Rename**.
  - **Move selection to active layer**.

### Frame popup panel (F7)

- **Popups:** one button per popup; double-click one to show it.
- **Buttons:**
  - **Add** a popup (you type its title next).
  - **Delete** it.
  - **Show** or close it.
  - **Add link** places a link to it in the middle of the canvas.
- **For the selected popup:**
  - its title (**Edit**);
  - its text (**Edit text**: Enter starts a new line, Esc finishes);
  - its **Go to page** button (**< >**, or none);
  - its colour.

## Plant equipment

The Tool panel has five tabs: **Pipes** (the pipe tools), **Equip** (34 kinds), **Elec.** (the electrical parts), **Fluid** (pneumatic and hydraulic parts) and **Ctrl** (counter, sensors and controller). The Equip tab places drawn plant equipment on the canvas:

| Tool | What it is |
|---|---|
| Motor | An electric motor with cooling fins, fan cowl, terminal box and shaft |
| Blower | A centrifugal blower: scroll housing with an impeller that turns while it runs, outlet duct and motor |
| Paddle | A paddle agitator: motor and shaft with paddles that turn while it runs |
| Screw conv. | A screw conveyor: motor, gearbox and trough with flights that move while it runs |
| Cyclone | A cyclone receiver (for the top of a silo) |
| Silo bin | A silo bin with panel seams that shows its fill level |
| Silo stand | The legs and braces under a silo |
| Lamp | A status lamp with its name beside it |
| Legend | A key to the six state colours |
| Sequence | The **Sequence / Delays** box: starts and stops the equipment in steps |
| Diverter | A diverter valve: two positions, on a 3-way valve it sets which way the flow goes |
| Shutter | A shutter (butterfly) valve: the disc turns open / shut |
| Slide valve | A slide (knife-gate) valve: the gate slides up when open |
| Heater | A duct heater: its coils glow while it heats |
| IR heater | A radiant panel: heat waves below it while it heats |
| Rain | A rain cloud that drops real water |
| Fire | A fire that burns fluff and oil and is put out by water |
| Pond | A pond: an earth basin with banks, grass and reeds that holds water |
| Pool | A tiled water pool with a rim and a ladder that holds water |
| Well | A stone well with a roof and winch; its shaft holds ground water that refills |
| Water pump | A centrifugal water pump with motor (the six states, sequence steps) |
| Cabinet | An electrical cabinet (panel) to hold a circuit |
| Rollers | A roller conveyor: rollers turn while it runs |
| Belt | A belt conveyor: the belt moves around its drums while it runs |
| Gauge | A needle gauge: a 240 degree dial with a red end zone |
| Display | A digital display with 7-segment digits: green in range, red outside it |
| Cylinder, Compressor, Hydraulic unit, Air receiver | Fluid power equipment that follows the pneumatic / hydraulic circuit |
| Faceplate | A panel controller face: actual value, set point and output of a controller (see **Sensors and controllers**) |
| Heat exch. | A shell-and-tube heat exchanger: put it on a pipe (see **Heat exchanger** below) |
| Cool. tower | An induced-draft cooling tower with a turning fan, fill and basin (see **Cooling tower and chiller**) |
| Chiller | A packaged water chiller: compressor, condenser, evaporator and a panel showing the chilled water temperature |

- **Six states**, as in the legend:

  | State | Look | Meaning |
  |---|---|---|
  | Auto Start (run) | green | started by the sequence (or by hand in auto) |
  | Auto Stop / Interlock / E-Stop | grey | stopped |
  | Manual Start | green with an orange band | started by hand; the sequence leaves it alone |
  | Manual Stop | grey with an orange band | stopped by hand; the sequence leaves it alone |
  | Disable | dark grey | out of service; it cannot run |
  | Fault | red | failed; it stops (and halts what it drives) until reset |

  Properties has a button for each. Double-click toggles Auto Start <-> Auto Stop and Manual Start <-> Manual Stop, and resets a fault to Auto Stop.
- **Status words:** `AUTO RUN 00:00:12.3`, `MAN STOP`, `DISABLED`, `FAULT`. Valves show `OPEN` / `CLOSED` (a diverter `POS 1` / `POS 2`), and heaters `HEAT` / `OFF`.
- **Name and status:** each piece shows its name and status above it; while it runs, with a running timer, and a fault blinks.
- **Properties:** the six state buttons, its sequence step and delay, a name, width and height, **Flip** (motor on the other side; **R** does the same), **Duplicate** and **Delete**.
- **Linked to a part:** equipment can be linked to a part of the process (**Link: click a part** in Properties, then click the part).
  - A motor, blower, paddle or screw that is stopped or in fault **halts** the linked part. A halted blower, suction head or nozzle stops pushing, a feeder stops feeding, and a hopper or silo stops discharging.
  - A silo bin shows the linked silo's or hopper's fill level.
  - A lamp lights green while material or air flows through the linked part.
  - Placing a motor-driven piece on a device, or a silo bin on a silo, links it at once.
- **Drawing order and editing:** silo bins, stands and cyclones are drawn behind the pipes; the others in front. Equipment sits on layers like everything else, is saved in the layout (`EQUIP` lines) and is part of undo. Drag it to move it, and drag its corner to resize it.

### Sequence / Delays

The Sequence box runs the start-up and shut-down of a page:
- **Steps:** give each motor, valve or heater a **Seq. step** (1-9) and a **Delay** in seconds (in Properties). Pieces with the same step start together.
- **AUTO, request ON (AUTO START):** the steps start one after another. Each waits its delay (`Start step 2/4 [Screw01] 1.6/4.0 s`), and the pieces about to start show `delay: step 2 starts in 2.4s` in orange.
- **AUTO, request OFF (AUTO STOP):** the steps stop in reverse order, with the same delays.
- **MANUAL:** the sequence does nothing; start and stop by hand.
- **E-STOP:** everything in the sequence stops at once.
- **The External Request** is set with **Request ON / OFF**, or it is ON while a linked part has flow.
- Only pieces in an auto state are started or stopped; manual, disabled and faulted ones are left alone. The first Sequence box on a page runs it.

### Valves, heaters, rain and fire

- **Shutter valve / slide valve:**
  - linked to a 2-way valve: open when running, shut when stopped;
  - linked to a feeder, hopper, silo or outlet: shutting it stops that part.
- **Diverter valve:** linked to a 3-way valve, position 1 (running) and position 2 (stopped) each shut one branch. **Pos 1 shuts / Pos 2 shuts** in Properties choose which; `none` keeps every branch open.
- **Heater (duct heater):** linked to a pipe, it boils the water flowing through that cell into steam (rising air dots). Unlinked, it heats its own box. **Power** sets how strongly.
- **IR heater:** boils off water drops falling through the area below the panel.
- **Rain:** while it rains, the cloud drops real water particles; they fill buckets and hoppers. **Rain %** sets how hard.
- **Fire:**
  - fluff and oil that fall into it burn and make it stronger;
  - water puts it out (`OUT`);
  - motors, valves and heaters caught in the flames go to **Fault**;
  - **Ignite** starts it again, and **Size %** sets how big it grows.

### Well, pool, pond and water pumps

- **Holding water:** a pond, pool or well holds water as a level (**Water %**, shown above it).
  - Water drops that reach it (rain, a drop outlet, a nozzle) are taken in and raise the level.
  - When it is full (`FULL`), the water stays outside and overflows onto the floor.
  - A well refills slowly from the ground water, up to 80%.
- **Water pump:** link it to the pipe it pumps into (**Link: click a part**, or place it on the pipe). While it runs, it draws water from the nearest pond, pool or well and puts it into that pipe.
  - Below the pump you see where it draws from, e.g. `from Well01 (77%)`, or `DRY` when the source is empty.
  - **Flow %** sets how fast it pumps.
  - If its pipe cell is a blower, the pump also drives that blower, so stopping the pump stops the push.
  - It has the six states, a place in the start sequence and double-click run / stop, like a motor.
- **Undo:** the water levels are contents, like feeder stock, so they are not undo steps.

### Roller and belt conveyors

- Material that falls onto a conveyor lands on its deck. While the conveyor runs, the material rides along and falls off the end.
- **Speed %** sets how fast it goes, and **Flip** reverses it.
- A conveyor has the six states and a sequence step, and an electrical motor or drive can run it.

## Electrical circuits

The **Electric** tab of the Tool panel draws real control circuits.

**Where circuits live:** on a wiring grid of their own, over the process. A cell can hold a pipe and a wire at the same time.

**Drawing a circuit:**
- **Wire:** drag to route wires; they join where they meet.
- **Placing a part:** click with a part's tool. On a wire, the part takes its place and keeps the wiring. Its two terminals face W / E (or N / S after **R**).
- **Tags:** a new part gets a tag of its own (K1, KM1, T1, H1, Q1, SB1 ...). A new NO / NC contact takes the tag of the last coil placed. Change a tag in Properties.

**Working the circuit** (Select tool):
- **Push buttons:** hold the mouse button on a Push NO / NC to press it.
- **Other parts:** click a switch, breaker, selector, E-Stop or push on / off button to work it.
- **Ctrl+click** selects a part instead of working it.

**Colours:** wires on the live net (L / +) are **red**, on the neutral net (N / -) **blue**, and dead ones grey. A closed contact and an energized coil, lamp or motor are green.

| Part | What it does |
|---|---|
| Wire, Cross, Terminal | wiring; Cross lets two wires pass without joining |
| AC supply / DC supply | the source: W = L (or +), E = N (or -); a short shuts it down |
| Fuse | conducts until a short blows it (**Replace fuse**) |
| Breaker | ON / OFF; trips on a short (**Reset**) |
| Switch | on / off switch |
| 2-way sw. | changeover (SPDT): common W, position 1 to E, position 2 to S |
| 3-way sw. | intermediate switch: two inputs W / N, two outputs E / S, straight or crossed |
| Push NO | closed only while it is held (start button, "push on, release off") |
| Push NC | open while it is held (stop button) |
| Push on/off | push on, push again off (latching) |
| Selector | a selector contact: SA1 has 2 or 3 positions, each contact closes in its own position |
| E-Stop | NC mushroom button: press latches it open, click again to release |
| NO / NC contact | follows the coil, contactor, timer or overload with the same tag |
| Relay / Contactor | coils K / KM: energized when wired across a supply |
| Timer | timer T: on-delay, off-delay, pulse or flasher (see **Timers and counters**) |
| Overload | NC overload relay OL: trips when its equipment goes to fault; its tag's NO contact then closes |
| Lamp / Buzzer | pilot lamp (5 colours) and buzzer |
| Motor M | runs the equipment named in it (pump, conveyor, blower ...) while energized |
| Drive VFD | like Motor, and sets the equipment's speed / flow % |
| Float sw. | closes on the water level of a pond / pool / well or silo bin: Fill (on when low, off when high) or Empty |
| CT | current transformer: passes the current on and measures it (A) |
| Pot | potentiometer RV: a knob 0-100 % (mouse wheel or Properties); a drive can take its speed from it |

**How the circuit is worked out:**
- A load is energized when one terminal is on a supply's L net and the other on its N net.
- Contacts follow their coils until nothing changes, so seal-in contacts and interlocks work.
- A short from L to N blows the fuse or trips the breaker on its path.
- Motor and drive loads start and stop their equipment, as long as it is in an auto state (not manual, disabled or faulted).
- The wiring is saved (`ECELL` lines) and is part of undo. Working switches is not an undo step.

### Analog values: potentiometers, current transformers, gauges and displays

- **Current:** every energized load draws a current.
  - A motor draws its **Rated A** (5 A by default). At a direct start it draws an **inrush** of about 6x that, settling in about a second; in **Star** it draws a third.
  - A drive draws in proportion to its speed. Coils, lamps and buzzers draw a little.
- **Current transformer (CT):** measures the current of every load it feeds.
- **Overload:** measures its current the same way. With a **Trip A** set, it trips after 2 s over that current; a short start inrush does not trip it.
- **Potentiometer:** turn it with the mouse wheel. A **Drive** can take its speed from it (**Speed from: pot RV1** in Properties).
- **Gauge and Display:** pick what one shows with **Shows < >**, and set its **Min / Max** range. It can show:
  - a CT, overload or motor current (A);
  - a potentiometer or drive (%);
  - a supply voltage (230 V / 24 V);
  - a timer (s), a counter (pcs), a sensor or a controller;
  - the level or speed of any equipment (%).

### Timers and counters

- **Timer** (Electric tab): pick its mode in Properties.
  - **On-delay:** its contacts close the set time after it gets power, and open when the power goes.
  - **Off-delay:** its contacts close at once and open the set time after the power goes.
  - **Pulse:** power on gives one pulse of the set time, however long the power stays.
  - **Flasher:** while it has power its contacts blink: **On s** closed, then **Off s** open.
- **Counter** (Control tab, tag CNT): every time its coil gets power it counts one. Its contacts (NO / NC with its tag) switch when the count reaches its **Preset**.
  - **Reset by:** a push button, switch, coil, timer or photo sensor tag sets it back to 0; **Reset to 0** or a click with the Select tool does it by hand.
  - A gauge or display can show its count (pcs).

## Sensors and controllers

The **Ctrl** tab of the Tool panel holds the counter, nine sensors and the controller. Sensors and controllers are parts of the electrical grid. A sensor does not need wiring; a controller is a load and works while it has power.

| Sensor | Tag | What it reads |
|---|---|---|
| Level LT | LT | the level of a pond / pool / well / silo bin (%) |
| Pressure PT | PT | the air pressure of the pipe under it (kPa), or a pneumatic / hydraulic part by its tag (bar) |
| Flow FT | FT | the air speed in the pipe under it (m/s) |
| Temp. TT | TT | the temperature of a heater, IR heater, fire, the shell outlet of a heat exchanger, or the water leaving a cooling tower or chiller (C). A heater warms up toward 20 + 2.3 x its power % while it runs and cools back to 20 C |
| Speed ST | ST | the speed of a piece of equipment (rpm; 1450 at 100 %) |
| Weight WT | WT | what lies in the bucket above or below it (kg) |
| Humidity MT | MT | **Air RH:** the relative humidity of the air around it (about 45 % in dry air, more with water, steam, ponds, pools or rain near it, less near hot equipment). **Material:** the moisture (water share by mass) of what is in the store or pipe under it, or in the bucket above or below it (%) |
| pH sensor | PH | the pH of what is in the store or pipe under it, or in the bucket above or below it: each material's own pH (set in the Physics lab: water 7.0, oil 6.5, fluff 5.5, sand 8.8) mixed by mass; 7 when empty |
| Photo eye | PE | closes while material passes its cell, and opens 1 s after the last of it; its tag works NO / NC contacts, so it can count batches |

**Controller** (tag IC, for example LIC1 or TIC1):
- **Input:** any analog value: a sensor, a meter, a level, even a value from another page. This is its actual value, **PV**.
- **Set point (SP)** and the mode:
  - **On<SP:** on / off, on below the set point (heating, filling), with a **Hysteresis** band around it.
  - **On>SP:** on / off, on above the set point (cooling, emptying).
  - **PID / PID rev:** a PI controller with a proportional **Band** (in the input's units) and an **Integral s** time; its output runs 0..100 %.
- **Output:** its contacts (NO / NC with its tag) close while the output is on (50 % and more); a **Drive** can take its speed from it (**Speed from**).
- By name, a gauge or display can show `LIC1` (output %), `LIC1.PV` and `LIC1.SP`.
- **Faceplate** (Equip tab): a panel controller face with the actual value large in red, the set point in green and the output as a bar. Select it to change its controller's set point.

## Heat exchanger

The **Heat exch.** tool (Equip tab) puts a shell-and-tube heat exchanger on a pipe and links it to that pipe.

- **Shell side:** the process stream through the linked pipe, coming in at **Shell in C** (20 C by default). Its flow is the air speed in that pipe.
- **Tube side:** **Tube flow** % while it runs (its six states, like a motor), coming in at **Tube in C**, or from the piece picked in **Tube from**: a heater, IR heater or fire (its temperature), a cooling tower or chiller (the water it sends), or another heat exchanger. A **Drive** can set its tube flow, so a controller can run it. The tube side can be hotter (it heats the stream) or colder (it cools it; the duty is then negative).
- **The model:** counterflow, effectiveness-NTU: duty Q = effectiveness x Cmin x (hot in - cold in); the outlets follow in about 3 s. A larger heat exchanger has more area and passes more heat. If one side stops flowing, the still side takes the other side's temperature.
- **Water** leaving the shell hotter than 100 C boils off as steam.
- **Values by name:** `HX01` is its shell outlet in C, `HX01.HOT` its tube outlet, `HX01.IN` its tube inlet and `HX01.KW` its duty in kW. A **Temp. TT** sensor on it reads the shell outlet.
- **On the canvas:** the shell and the tubes take the colour of their temperatures (blue cold, red hot); below it, shell in > out, tube in > out and the duty.

## Cooling tower and chiller

They cool water. Each takes its water **from** another piece (**Water from** / **Return from**): a heat exchanger gives its tube outlet, so a heat exchanger and a tower (or a chiller) can feed each other in a loop.

- **Cooling tower:** the water leaves toward the wet-bulb temperature (**Wet bulb C**, 21 C): out = in - effectiveness x (in - wet bulb). The effectiveness is 0.15 with the fan off (natural draft) and rises to 0.75 with the fan (**Fan %**) at full speed; a **Drive** can set the fan, so a controller can hold a temperature. The warm, moist air rises from the fan stack as a plume of vapour that a humidity sensor near it sees. Without a source, the water comes in at **Water in C**.
- **Chiller:** while it runs it chills the return water to its **Set point C** (7 C), by at most 20 C at its **Capacity** %; it shows the chilled water temperature on its panel, the cooling and the power it takes (cooling / 4). Its condenser water leaves at 30 C + 0.6 x the cooling, and a cooling tower can take its water from the chiller's condenser. Without a source, the water comes back at **Return C**.
- **Values by name:** `Tower01` / `Chiller01` is the water it sends (C), `.IN` the water it gets, `.KW` its duty; `Chiller01.HOT` its condenser water.

## Every page at once (the plant bus)

All pages run at the same time, every frame, not only the page on screen. A pump on page 3 keeps pumping while you look at page 1, and all pages run on the same clock.

Pages work together through the **plant bus**. After its frame, every page tells the others:
- the tags that are on (coils, timers, counters, controllers, photo sensors, limit and pressure switches);
- its analog values by name (sensors, controllers, meters, pressures, levels);
- its equipment (state, level, speed, temperature);
- run / stop commands from its motors and drives to equipment that is on another page.

So the same tag or name links two pages:
- a **NO contact** follows a coil on another page when its own page has no part with that tag;
- a **Motor** or **Drive** runs equipment on another page;
- a **float switch**, **sensor**, **gauge**, **display** or **faceplate** shows a value from another page;
- the Properties pickers (**< >**) list what the other pages have, too.

A value a page publishes reaches the pages after it in the same frame and the pages before it in the next one (1/60 s later). Example 24 shows a control room, a pump house and a monitor on three pages.

## Pneumatic and hydraulic circuits

The **Fluid** tab of the Tool panel draws ISO-style fluid power circuits on their own grid, over the plant like the electrical wiring. Lines take the colour of what they carry: blue for air, orange for oil, brighter the higher the pressure.

| Group | Parts |
|---|---|
| Supply | Compressor, Hydraulic pump, Air receiver, Accumulator, FRL unit, Pressure regulator, Filter, Tank |
| Valves | 3/2, 5/2, 5/3, 4/2 and 4/3 directional valves; Check valve, Flow control (throttle), Shuttle valve (OR), Two-pressure valve (AND), Relief valve |
| Actuators | Single-acting cylinder, Double-acting cylinder, Air motor, Hydraulic motor |
| Others | Line, Line crossing, Silencer / exhaust, Pressure gauge, Pressure switch |

- **Drawing:** drag with **Line** to run lines; drop parts onto them. **R** turns the selected part.
- **Ports of a directional valve:** P (supply) at the bottom, A on the left, B on the right, R (exhaust) on top. A double-acting cylinder takes A on the left and B underneath.
- **Actuation** (Properties): Manual, Push button, Solenoid + spring, or Double solenoid. A solenoid valve follows the electrical solenoid with the same tag (**Y1**, **Y2** ...), so relays, timers and limit switches can run it.
- **Working it** (Select tool): click a manual valve to switch it, hold a push-button valve, click a compressor or pump to start or stop it. The mouse wheel turns a pressure setting, a flow control or a regulator.
- **Cylinders:** a cylinder's speed is set by its **Stroke s** and by any flow control in its lines. Its end positions close limit switches `<tag>0` (in) and `<tag>1` (out), which the electrical circuit can use. Link it to a piece of equipment (**Equipment** in Properties) and the equipment follows: a gate opens, a lift rises.
- **Motors:** an air or hydraulic motor runs its linked equipment at the speed its flow allows.
- **Pressure:** a compressor or pump delivers up to its **bar** setting, and can be made to run only while a contactor or relay is on (**Runs while**). The FRL or regulator sets the working pressure (**Out bar**); a relief valve **Opens** at its setting and sends the excess to the tank. A pressure switch has an **Upper** and a **Lower** setting and is **On when low** or **On when high**, so it can run a compressor between the two. Gauges, and the panel gauges and displays, can show any pressure in bar.
- **Saved and undone** like everything else (`FCELL` lines).
## Menus

The menu bar runs across the top of the window: **File**, **Edit**, **View**, **Panels**, **Examples** and **Theme**. The program starts with a new, empty layout; pick a ready-made one from **Examples**. There is no fixed side panel. The window is the canvas plus a panel column on the right and/or left, and a column is there only while a panel is embedded in it. While one menu is open, moving the mouse over another one switches to it.

### Edit

| Item | Key | What it does |
|---|---|---|
| Undo | Ctrl+Z | Steps back one edit. Up to 100 steps. |
| Redo | Ctrl+Y (or Ctrl+Shift+Z) | Steps forward again. A new edit clears the redo list. |
| Cut | Ctrl+X | Removes the selection (one part, a bucket, or a box of parts) and keeps it on the clipboard. |
| Copy | Ctrl+C | Copies the selection to the clipboard. |
| Paste | Ctrl+V | From the menu: click on the canvas to place it, or press Esc or right-click to cancel. Ctrl+V over the canvas pastes under the mouse. |
| Delete | Del | Removes the selected part or bucket. |
| Rotate right / left | R / Shift+R | Turns the selection a quarter turn (see Rotating). |

Undo records every finished action as one step: a whole pipe drag, a slider drag, a burst of mouse-wheel turns, a menu command, or loading a layout. It covers the pipe layout, part settings, buckets and gravity. Feeder contents and material already flowing aren't rolled back, because the simulation drains feeders all the time. Undo covers the page on screen; page, layer and popup settings are not part of it.

### Selecting several parts

With the **Select** tool, left-drag on empty space to draw a box. When you release the mouse, the box disappears and the selected parts and buckets stay outlined. Every part inside it is selected, plus every bucket whose centre is inside it. The box then shrinks to fit what it caught. A box that catches a single part or a single bucket becomes a normal single selection. The Properties panel shows the count, with Cut, Copy and Delete buttons.

Copying stores the selection as one block. Pasting puts the block's top-left corner on the cell you choose:
- Joints between parts inside the block are kept.
- A part whose joint led outside the block connects to whatever pipe is next to it at the new spot.
- Parts already in the way are replaced.
- Buckets keep their position relative to the parts.
- After pasting, the new block is selected, so you can cut it again straight away to move it.

### Moving parts

With the **Select** tool, press on a part and drag it. If the part is in a box selection, the whole selection moves, buckets included. Otherwise just that part moves.
- A cyan outline shows where it will land. The move snaps to grid cells and the block can't leave the grid.
- A move is a cut and paste in one step: joints inside the moved group are kept, and its edges rejoin whatever pipe they land next to.
- A single part dropped onto an existing pipe is inserted into it, the same way pasting works.
- A click without dragging, inside a box selection, selects just that one part.
- Each move is one undo step.
- Buckets on their own still drag smoothly by the pixel. Buckets inside a box selection move with the group, cell by cell.

### Rotating

**R** turns the selection a quarter turn clockwise and **Shift+R** turns it counter-clockwise. The same commands are in **Edit > Rotate right / Rotate left**, the right-click menu and the box-selection Properties.
- **Box selection:** the whole group turns about its centre. Pipes, joints, pipe sizes and device directions (blower flow, nozzle and suction mouths, drop outlets, 1-way arrows, the closed branch of a 3-way valve) all turn with it. Its edges rejoin whatever pipe they now face. Buckets inside it move with the group but stay upright.
- **A single device:** R turns its direction in place, as before. A blower reverses and a 2-way valve opens or closes.
- **A single plain pipe:** R turns its joints, so you can turn an elbow or a tee.
- Each turn is one undo step.

### Hopper and silo

- **Hopper** (Hopper tool): an open funnel drawn above its outlet cell. Material that falls into the funnel is caught (it holds up to 300 units) and passed on through its pipe. It leaves by gravity when a pipe goes down, or carried by air when a blower or suction pulls on it. Its **Gate %** sets the discharge rate.
- **Silo** (Silo tool): a tall bin drawn above its outlet cell, so leave about 3 cells free above it. It fills through its open roof from a falling stream, or from any pipe joined to its outlet cell, and stores up to 4000 units in layers. Its walls are solid. When it is full it takes no more: material in a feeding pipe waits, and falling material bounces off. Its **Gate %** meters what goes out (0% = storage only).
- Click a hopper's funnel or a silo's body to select it, or drag it to move it. Properties shows the fill level, the contents, the gate and an **Empty it** button. A silo can also be pre-filled per material.
- Like the feeder, both count as open to the air for the pressure solver, and a blower can draw from them.

### Labels

A label is a text box on the canvas for describing part of a layout. The demo and every example come with labels.
- With the **Label** tool, click an empty spot and type. **Enter** starts a new line. **Esc** or clicking elsewhere finishes. The first line is shown as the title.
- Double-click a label (Select tool), or use **Edit label** in its right-click menu, to edit it again. A label left empty is removed.
- Drag a label with the Select tool to move it. Labels can be box-selected, cut, copied, pasted, moved and deleted with the parts around them. A rotate moves a label with its group, but the text stays upright.
- Labels are saved in layout files and are part of undo. Typing into a label becomes one undo step when you finish.
- The built-in font has plain ASCII characters only.

### Frames

A frame is a titled rectangle drawn behind part of the layout. Use it to group parts and give the group a name, for example "SAND LINE" or "Pump room".
- With the **Frame** tool, drag out a rectangle; it snaps to the cells. A plain click gives an 8 x 6 cell frame. Type its title straight away, and press Enter when done.
- A frame is grabbed by its **title tab** or its **outline**; clicks inside it still reach the parts. Drag the title to move the frame. By default everything inside moves with it (parts, buckets, labels), keeping their joints. Drag the **corner square** of a selected frame to resize it. Double-click the title to rename it.
- **Properties:**
  - **Edit title.**
  - **Select contents** box-selects everything inside, ready to cut, copy, rotate or delete.
  - **Colour** (Theme, Blue, Green, Amber, Red, White).
  - **Solid** or **Dashed** outline.
  - **Tint** on or off.
  - **Moving it moves its contents** on or off.
  - The frame's size and how many parts, buckets and labels it holds.
- Frames can sit inside other frames. They are saved in layout files as `FRAME` lines and are part of undo. Examples 5 and 6 use them.

### Date and time labels

The **Date label** and **Time label** tools place a label showing the computer's date or time. It updates live.
- Select it to format it in Properties:
  - **Presets.** Date: `yyyy-mm-dd`, `dd/mm/yyyy`, `mm/dd/yyyy`, `d mmm yyyy`, `dddd, d mmmm yyyy`, `dd.mm.yy`, `ddd d mmm`. Time: `hh:nn:ss`, `hh:nn`, `h:nn:ss am/pm`, `h:nn am/pm`, `hh:nn:ss.zzz`, `hh"h"nn`.
  - **Type a format** of your own; Enter or Esc finishes.
  - Date codes: `d dd ddd dddd` (day), `m mm mmm mmmm` (month), `yy yyyy` (year).
  - Time codes: `h hh` (hour), `n nn` (minutes), `s ss` (seconds), `z zzz` (milliseconds), `am/pm`.
  - Text in double quotes is shown as typed, for example `dd/mm "of" yyyy`. Month and day names follow Windows' language settings.
- **Edit caption** adds a line above the value (for example *Shift start*). Leave it empty for just the value.
- **Colour** (Theme, Blue, Green, Amber, Red, White) and **Box** on/off work for every label, plain text labels too.
- Date and time labels move, copy, paste, undo and save like other labels. In the layout file they're `LABEL2` lines.

### Two kinds of properties

- **The Properties panel (F4)** follows the selection: it shows whatever you select with the mouse. There is one per page.
- **Focus Properties windows** stay with one item.
  - **Opening one:** right-click an item (a part, bucket, label, frame, link, piece of equipment or electrical part) and choose **Focus properties**. A floating window, framed in the selection colour and titled `FOCUS: name`, keeps showing that item whatever you select.
  - **How many:** as many as you like; opening one for an item that already has a window brings that window to the front.
  - **Using one:** its buttons, sliders and typing work on its own item. Drag a window by its title, and **x** closes it.
  - **Pages:** each window belongs to the page it was opened on.
  - **When the item goes:** the window says so if the item is deleted or moved to another cell. A new layout, or deleting or moving a page, closes them all.
  - **Saved with the layout:** the open windows, their places and their items are saved in the layout file (`PIN` lines) and come back when it is opened.

### Right-click menu

Right-clicking the canvas without moving the mouse opens a popup with **Cut, Copy, Paste here, Delete, Rotate, Edit text, Focus properties**. **Edit text** renames a frame or edits a label.
- Right-clicking inside a box selection keeps that selection.
- Right-clicking any other part or bucket selects it first.
- **Paste here** puts the clipboard at the cell you right-clicked.
- Right-drag still erases. A right-click on its own no longer erases; use **Delete** from the popup instead.

When you paste a single part onto an empty cell, it reconnects on the sides it was joined on before. Pasting onto an existing pipe swaps the part in and keeps that pipe's joints. Cutting a blower and pasting it back in the same place restores it exactly.

### View

| Item | Key | What it does |
|---|---|---|
| Zoom in / Zoom out | Ctrl+= / Ctrl+- | Zooms the canvas in or out, 50% to 400%. |
| Zoom 100% | Ctrl+0 | Back to the normal size. |
| Pressure colours | P | Colours pipe bores by pressure. |
| Air dots | A | Shows the air tracer dots. |
| Grid > | | Opens the grid sub-menu (see below). |

### Grid (View > Grid >)

Hovering over **Grid** opens its sub-menu. Every choice is saved in `materialflow.ini`.
- **Show grid** (key **G**) turns the grid on or off.
- **Style:** lines, dots or crosses at the cell corners.
- **Major:** none, or a stronger line (or a bigger dot or cross) every 4, 5 or 10 cells.
- **Strength:** faint, normal or strong.
- **Colour:** follow the theme, or blue, green, amber or white.
- **Cell numbers on edges** numbers the cells along the top and left edges of the canvas, every major step (or every 5 cells). The numbers follow zoom and pan.
- **Reset grid to default.**

The grid size itself is fixed: one cell is one pipe segment.

### Panels menu

| Item | Key | What it does |
|---|---|---|
| Tool | F2 | Shows or hides the Tool panel. |
| Simulation | F3 | Shows or hides the Simulation panel. |
| Properties | F4 | Shows or hides the Properties panel. |
| Status | F5 | Shows or hides the Status panel. |
| Help | F1 | Shows or hides the Help panel. |
| Page & Layer | F6 | Shows or hides the Page & Layer panel. |
| Frame popup | F7 | Shows or hides the Frame popup panel. |
| Physics lab | F8 | Shows or hides the Physics Lab (see below). |
| Shape editor | F9 | Shows or hides the Shape Editor (see below). |
| Dock all panels | | Shows the seven main panels and embeds each one back in its column (left or right). The Physics lab and Shape editor stay floating. |

**Larger panels:** drag the corner grip (bottom right) of the floating Physics lab or Shape editor to make it larger or smaller (80 % to 300 %). Its text, buttons and drawings grow with it and keep working; the size is saved in `materialflow.ini`. When the content is taller than the panel, a scrollbar appears on its right: drag it, click above or below it, or turn the mouse wheel over the panel. Docking a panel puts it back to its normal size.

### Panels

**Tool**, **Simulation**, **Properties**, **Status**, **Help**, **Page & Layer** and **Frame popup** are separate windows. The first five start embedded one above the other in a column to the right of the canvas. Page & Layer and Frame popup start in a column on the left.
- Drag a title bar to float that panel anywhere, including over the canvas.
- Drop it near its slot to embed it again, or close it with **x**.
- Floating panels can overlap; clicking one brings it to the front.
- A hidden, floating or left-embedded panel leaves its place in the column empty. Bring a hidden panel back with its key (F1 to F9) or the Panels menu. Use the panel's right-click menu (**Right embed**) or **View > Dock all panels** to embed it again.
- When no panel is embedded on a side, that column disappears and the window gets narrower. Hide or float every panel and the window is just the menu bar and the canvas.

**Right-click a panel** for its popup:
- **Right embed** puts the panel in the right-hand column.
- **Left embed** opens a column on the left of the canvas and puts the panel there. The canvas moves right and keeps its size; the window gets wider. The left column closes again when no panel is left in it.
- **Float** detaches the panel.
- **Hide** hides it; its key (F1 to F9) brings it back.
- The panel's current place is ticked.

**Saved between runs:** the theme and each panel's state (shown or hidden, left or right, embedded or floating, and its floating position) are written to `materialflow.ini` next to the exe. The file is updated whenever a panel moves, and again on exit. Test runs (`--shot`, `--selftest`) never touch it.

**Tool panel:** five tabs: **Pipes** (pipes, parts, buckets, labels, frames and links; the default is **Select**), **Equip** (the plant equipment), **Elec.** (the electrical parts), **Fluid** (the pneumatic and hydraulic parts) and **Ctrl** (counter, sensors, controller), plus the tool hint and the pipe size brush.

**Simulation panel:**
- Run/Pause, Pressure colours and Air dots
- Gravity
- Clear flow, Clear floor, Load demo, New blank, Empty buckets and Fill feeders

**Properties panel:** the settings of whatever is selected:
- **Feeder:** ingredients, Air %, Feed %.
- **Blower, suction head, push nozzle, drop outlet:** strength, plus **E / S / W / N** buttons to set the direction or mouth directly.
- **1-way pipe:** direction buttons.
- **Valves:** valve state. The 4-way valve has **E / S / W / N** buttons, one per branch: lit means open.
- **Label:** a preview of its text, **Edit text**, **Delete**, and left/top position.
- **Link:** caption, target page or frame popup, colour, layer, **Follow it now**, **Delete**.
- **Every part:** pipe size and joint type.
- **Bucket:** width, height, left and top position, fill level and amount overflowed.
- **Box selection:** counts of parts, buckets and labels, plus Cut, Copy, Rotate and Delete.

**Status panel:** particle count, frame rate, run state, zoom, and what is under the mouse (part, size, pressure, air speed, or label).

**Help panel:** eight pages of short tips (Basics, Select & move, Edit, View & panels, Files & labels, Pages & links, Lab & shapes, Control). Use the **<** and **>** buttons to turn the pages.

### Zoom and pan

- **Ctrl+mouse wheel** zooms around the mouse pointer. **Ctrl +** and **Ctrl -** zoom around the centre, and **Ctrl+0** goes back to 100%. The same commands are in the View menu.
- Zoom runs from 50% to 400%. Zoomed out, the layout sits in the middle of the canvas area.
- **Middle-drag** or the **arrow keys** pan the view. Panning stops at the edges of the layout.
- Every tool works the same when zoomed. Label and caption text keeps its normal size.

### Theme

**Default, Dark, Daylight, Warm white, Red, Green, Blue.** The theme recolours the canvas, pipes, buckets, panel and menus. Pale materials (fluff, air dots) get darker colours on the light themes so they stay visible. Your choice is saved in `materialflow.ini` next to the exe.

## Physics Lab (F8)

The **Physics lab** panel (F8, or **Panels > Physics lab**) shows the physics that every layout runs on and lets you change it while the simulation runs.

- **Material:** pick Water, Oil, Fluff, Sand or Air, then set its **pH** (for pH sensors), **Mass**, **Gravity x** (how strongly gravity pulls it; below 0 it rises), **Air couple** (how strongly moving air carries it), **Air drag**, **Friction**, **Density** (what floats on what), **Size**, **Liquid** or grain, and its colour.
- **World:** **Gravity** (px/sÂ²), **Air speed** per unit of flow, **Feed rate** of the feeders, **Grav. feed** (how fast material drops out of a feeder by its own weight) and **Air dots**.
- **Test scenes:** **Drop** (each material falls from the same height into its own bucket), **Mix** (all four into one bucket, where they settle by density) and **Air** (the same blower on four lines, one material each). Each builds on a page of its own, **Physics lab**, fed by virtual feeders, so your plant pages are left alone. **Clear** removes the material in flight.
- **Live readout:** how many particles of each material there are and their mean speed.
- **Reset** goes back to the built-in values. **Open...** and **Save...** read and write a physics file (`.mfphys`). **Default** saves it as `physics.mfphys` next to the exe, which is loaded at every start.

The physics is kept apart from the layouts: a layout file does not change it, and a physics file can be used with any layout. A `.mfphys` file is plain text:

```
MFPHYS 1
WORLD 500 120 40 70 12                      # gravity air-speed feed-rate gravity-feed air-dots
MAT sand 1.6 1 4 0.08 0.55 1.6 3 0 196 158 92 255 8.8
                                            # name mass gravity couple drag friction density size liquid r g b a pH
```

## Shape Editor (F9)

The **Shape editor** panel (F9, or **Panels > Shape editor**) draws your own vector shape for any kind of equipment. A kind with a shape of its own is drawn from it everywhere, instead of the built-in drawing.

- **Kind:** **<** and **>** step through the equipment kinds. The drawing box has the kind's proportions; the built-in drawing shows behind it (**Ref** turns it off).
- **Drawing:** pick **Rect**, **Ellipse**, **Line** or **Tri** and drag in the box; a click without a drag draws one of a usual size. Points snap to a 1/40 grid.
- **Editing:** with **Select**, click a part and drag it, or drag one of its two corner handles. **Up** / **Down** change the drawing order, **Copy** duplicates, **Delete** removes it.
- **Each part:** colour, opacity, line thickness, **Filled**, and **State colour**: the part takes the equipment's state colour (green running, grey stopped, red fault ...) instead of its own. **Run / Stop / Fault** previews the states.
- **New pieces:** a **Width** and **Height** of its own for new pieces of the kind (0 keeps the built-in size).
- Coordinates run 0..1 across the piece, so a shape stretches with the piece and flips with it.
- **Clear** gives the kind its built-in drawing back; **All** does that for every kind. **Open...** / **Save...** read and write a shape file (`.mfshape`), and **Default** saves `shapes.mfshape` next to the exe, which is loaded at every start.

```
MFSHAPE 1
KIND receiver 0 0                           # kind, new width, new height (0 0: built-in size)
PRIM rect 0.2 0.12 0.8 0.9 150 156 166 255 1 1 2
                                            # rect|ellipse|line|tri x1 y1 x2 y2 r g b a filled state-colour thickness
```
## Saving and loading layouts

The **File** menu has:

- **New layout** (Ctrl+N), **Open...** (Ctrl+O), **Save** (Ctrl+S), **Save as...** (Ctrl+Shift+S). Open and Save use the Windows file dialogs.
- **Exit** (Ctrl+Q) closes the program. Closing the window does the same, and both save the panel places and theme first.
- The File menu has **New layout**, **Open...**, **Save**, **Save as...** and **Exit**.

### Examples menu

**Original demo**, then the examples in six sub-menus by subject: **Pipes & air flow** (1-4), **Storage & equipment** (5-9), **Electrical circuits** (10-14), **Pneumatic systems** (15-18), **Hydraulic systems** (19-21) and **Control & sensors** (22-26). Hover over a subject to open its list. The same layouts are also files in `examples\` (the demo is `demo_original.mflow`), and **Load demo** in the Simulation panel loads the demo too.

Every menu and sub-menu is as wide as its longest item, so no text is cut off.

A layout file stores every page with its layers, parts and settings, the feeder contents, the buckets, labels, frames and links, plus the frame popups. Material currently in flight isn't saved. Files are plain text, so you can edit them by hand:

```
MFLOW 2
NAME My layout
POPUP 1 2 2 How it works                         # n, go-to page (0 = none), colour, title
POPUPTEXT 1 First line\nsecond line              # \n = new line
PAGE Plant                                       # a new page starts here
LAYERS 2 1                                       # layer count, active layer
LAYER 1 1 0 Process                              # n visible locked name
LAYER 2 1 0 Notes
GRAVITY 1.00
ON 1                                             # what follows is on layer 1
CELL 14 2 feeder S 4 E 1 0.00                    # x y kind conn size dir open strength
STOCK 14 2 2500.00 0.00 0.00 0.00 10.00 70.00    # water oil fluff sand air% feed%
CELL 14 3 pipe SN 3 E 1 0.00
BUCKET 303.00 730.00 90.00 70.00                 # x y width height (pixels)
ON 2
LABEL 380.00 40.00 Feeder room\nwater and oil    # x y text, \n = new line
LINK 920.00 6.00 1 page 2 About                  # x y colour page|popup n caption
EQUIP blower 744.00 560.00 120.00 112.00 stop 0 33 27 50.00 Blower01
                                   # kind x y w h state flip link-x link-y level% name
EQX 0 1 2.00 -1 -1                 # mode, sequence step, delay s, diverter pos 1 / pos 2 shut branch
                                   # state: stop run fault mstart mstop disable
PAGE About
...
```

`kind` is one of `pipe feeder blower suction nozzle drop check valve2 valve3 valve4 hopper silo`. Hoppers and silos also have a `STOCK` line (contents, air %, gate %). A `valve4` line has a tenth value: its shut branches (for example `EW`, or `-` when all are open). `conn` lists the joined sides using the letters E, S, W, N. Pages, layers, popups and link targets count from 1. Older `MFLOW 1` files still open as a single page with one layer (their `tank` parts and `TANK` lines are read as feeders). If a file is invalid, the app shows the line number and the reason, and the current layout stays loaded.

### Examples

Twenty-six examples are in the **Examples** menu and in `examples\`, along with the original demo (`demo_original.mflow`).

All of them are built the same way:
- **Page 1 "Plant"** is the working process. Layer 1 **Process** holds the pipes, feeders, devices and buckets; layer 2 **Notes** holds the labels, frames and link buttons. Hide Notes to see the bare process, or lock Process to protect it.
- **Page 2 "About"** explains the example and how the layout is built.
- **Frame popup 1 "How it works"** describes the process; its button goes to the About page. **Frame popup 2 "Try this"** suggests changes to try.
- **Links** on both pages (top right of the plant, bottom of the About page) jump between the pages and open the two popups.

The examples:

1. **Gravity merge/overflow**: water falls by gravity through a one-way pipe. Oil and fluff are blown in through a narrowed section and join at a tee, then pass a 2-way valve and drop into a small bucket. The bucket overflows into a wide tray.
2. **Pneumatic conveyor**: a strong blower pushes sand through a widened section and up a tall riser. A 3-way valve at the top splits it into two drop outlets over two buckets; switch the valve with **R** to send everything one way.
3. **Vacuum & push nozzle**: water and fluff drop into a bucket. A suction head sucks them out through a one-way pipe, and a push-out nozzle shoots them sideways into a far bucket.
4. **4-way valve switchyard**: a blower drives water and oil into a 4-way valve on a cross. Its east, south and north branches each lead to a bucket. North starts shut, so its bucket stays dry until you open that branch (select the valve and use its E S W N buttons).
5. **Hopper feed**: sand falls from a feeder into a hopper, and a blower carries the hopper's output across to a bucket. A second hopper catches falling water and drains it straight down by gravity.
6. **Silo storage**: a blower lifts sand up a riser and drops it through a silo's roof. The silo stores it, and its gate (30%) lets it out slowly into a bucket. A second silo is filled through a pipe in its side and has its gate shut, so it only stores.
7. **Fluff silo system**: the system from the drawing. A silo bin with a cyclone on its roof and three paddle agitators (Paddle01 runs, 02 and 03 are stopped), a screw conveyor under it discharging into a funnel, and a centrifugal blower that blows the fluff up the riser back to the cyclone, with a branch to the consumer and an **Ext. Request** lamp. The equipment is on its own **Equipment** layer and is linked to the real process: stopping **Blower01** stops the air, and stopping **Screw01** stops the silo discharge. The real silo sits on the hidden layer **Silo core**, inside the bin. The **Sequence** box starts Blower01, Screw01, Paddle01 and the diverter one after another with their delays. Paddle02 is in Manual Stop and Paddle03 is disabled; the legend shows all six states.
8. **Rain, fire & heaters**:
   - Rain01 rains into a bucket, and IRHeater01 can dry the drops on their way down.
   - Fluff drops through Shutter01 onto Fire01 and keeps it burning; start Rain02 to put the fire out.
   - A water line runs through Slide01 and Heater01, which boils the water to steam.
9. **Well, pool, pond & pumps**:
   - Pump01 lifts ground water from Well01 up and over into Pool01.
   - Double-click Pump02 to pump the pool on into Pond01.
   - Rain01 over the pond can fill it too, and the levels rise and fall for real.
10. **Circuit: well pump**: a cabinet with Q1, F1, an E-Stop and selector SA1 (1 OFF / 2 HAND / 3 AUTO).
    - In AUTO, float LS1 on Pool01 starts the pump below 30% and stops it at 80%.
    - Float LS2 on Well01 protects the pump from running dry.
    - Contactor KM1 drives motor M1 = Pump01, with overload OL1 and run / fault lamps.
11. **Circuit: start / stop (DOL)**: hold SB1 to start. KM1 seals itself in, M1 runs a belt conveyor carrying sand, and SB0 or the E-Stop stops it. There are run / stop / fault lamps and a buzzer.
12. **Circuit: star-delta**: KM1 + KM2 start a big blower in star; after timer T1 (5 s), KM3 switches it to delta. KM2 and KM3 interlock each other.
13. **Circuit: conveyor line**: the belt (KM2) starts first; timer T1 then starts the roller conveyor (KM1) through drive U1 at 70%. Sand rides both conveyors.
14. **Circuit: meters, pot & CT**:
    - Potentiometer RV1 sets the speed of drive U1, which runs Pump01.
    - CT1 measures the pump's current, and the Pump A gauge shows it.
    - Switch S2 starts Motor01 direct on line; the Motor A gauge shows the inrush settling to 5 A.
    - Displays show the pump speed, the pool level and the supply voltage.
    - OL2 is a thermal overload set to 12 A.
15. **Pneumatic: cylinders & valves**: compressor C1, receiver R1 and FRL1 (6 bar) supply a manual 5/2 valve that drives double-acting cylinder A through two flow controls, and a push-button 3/2 valve for single-acting cylinder B.
16. **Electro-pneumatic gate**: a double-solenoid 5/2 valve, limit switches A0 / A1 and timer T1 open a hopper gate batch after batch; SB1 starts the cycle.
17. **Pneumatic logic: AND / OR**: a two-pressure valve moves A only when S1 and S2 both give air; a shuttle valve moves B from S3 or S4.
18. **Compressor control & air motor**: pressure switch PS1 runs the compressor between 6 and 8 bar; an air motor with a flow control drives a belt.
19. **Hydraulic: power unit & 4/3**: pump P1, relief valve RV1 (100 bar) and a tandem-centre 4/3 valve lift and lower a cylinder; in the centre the pump unloads to the tank.
20. **Electro-hydraulic press**: SB1 starts the press; relays, limit switches and two solenoids run it down to A1 and back up to A0.
21. **Hydraulic motor & flow control**: a hydraulic motor turns a conveyor; flow control FC1 sets its speed, and an accumulator stores the pressure.
22. **Timers & counter**: flasher T1 (1 s on, 2.5 s off) opens the slide gate under a sand feeder's pipe through KM1. Photo sensor PE1 sees each batch fall and counter CNT1 counts it. At 5 the counter stops the flasher and lights H1; hold SB1 to reset it. Off-delay T2 keeps H2 on for 3 s after the last pulse, and weight sensor WT1 weighs the bucket.
23. **Sensors & PID control**:
    - Level sensor LT1 reads Pool01; PID controller LIC1 sets the speed of Pump01 (drive U1) to hold 60 % while Pump02 drains the pool.
    - Temperature sensor TT1 reads Heater01; on / off controller TIC1 keeps it near 150 C.
    - Pressure, flow and speed sensors show on displays, and both controllers have a faceplate.
24. **Every page at once**: page 1 "Control room" holds the circuit and controller LIC1, page 3 "Pump house" the well, pumps and pool, page 4 "Monitor" the meters. KM1 on page 1 runs Pump01 on page 3; LT1 on page 1 reads Pool01 on page 3; every meter on page 4 shows a value from another page.
25. **Heat exchanger & humidity**: a blower pushes wet sand through the shell of HX01; hot water at 160 C runs through its tubes. PID controller TIC1 sets the hot flow (drive U1) to hold the shell outlet at 80 C, read by TT1. Humidity sensor MT1 measures the air by the falling stream, MT2 the moisture of the sand in the bucket.
26. **Cooling tower, chiller & pH**: a hot (90 C) stream of wet sand is cooled in HX01 by water from Tower01, which gets HX01's tube water back (a loop); PID controller TIC1 (reverse) sets the tower fan through drive U1 to hold the stream at 40 C. Chiller01 sends 7 C water through HX02 to cool a second stream (30 C). PH1 and PH2 read the pH in the buckets, MT1 the humidity of the tower's plume.

## What it covers

| Requirement | How it's done |
|---|---|
| Water, oil, fluff and sand, mixed with air | Each material behaves differently: weight, how strongly the air carries it, air drag, friction and density. Oil floats on water, fluff floats on top, sand sinks and piles up. Light-blue dots are air. |
| Endless material with a lifetime | A **Virtual feeder** (Pipes tab, **Virtual fd.**) works like a feeder but never runs out. Each particle it lets out lives for its **Life s** (10 s by default, 1 to 120) and then disappears, so a test can run for ever without filling the buckets. |
| Adjustable ingredient quantities | Each **Feeder** has −/+ buttons and a slider for every ingredient (0–3000 units), plus an **Air %** mix and a **Feed %** rate. Material that flows back into a feeder is stored again. |
| Strength of suction, blow, push-out and drop discharge | Select a part (or scroll the mouse wheel over it) to set: **Blower** blow strength, **Suction** head strength (intake pull and pick-up reach), **Push nozzle** jet strength, and **Drop out** gravity gate %. There is also a global **Gravity** slider. |
| Easy pipe routing | Drag with the Pipe tool. Starting a drag on an existing pipe branches it into a tee. Clicking a device tool on a pipe inserts that device inline. Right-drag erases. |
| Material falls into a bucket and overflows | Buckets show a fill %, a level line and a flashing **OVERFLOW!** warning with a count of spilled particles. You can move buckets (Select + drag), resize them, empty them or delete them. |
| Hoppers and silos | A **hopper** catches falling material in its funnel and passes it on. A **silo** stores what falls through its roof or flows in by pipe, and lets it out through a gate. |
| Single-way, 2-way, 3-way and 4-way | **1-way pipe** is a check valve: flow only follows the arrow. **2-way valve** is on/off. **3-way valve** diverts flow at a tee. **4-way valve** sits on a cross; each of its four branches opens or shuts on its own (R cycles: all open, shut one branch, straight E-W, straight N-S). Pipe joints are also recognized automatically: open end, straight or elbow, tee (3-way) and cross (4-way). |
| Pipe size, constricted or expanded along the way | Five pipe sizes. Use the **Pipe size** tool (or the mouse wheel) on individual cells. A narrow section resists flow and speeds the air up; a wide section slows it down. Size changes are drawn as tapered reducers. |

## Controls

- **1–0**: Select, Pipe, Pipe size, Erase, Feeder, Blower, Suction, Push nozzle, Drop out, Bucket. The 1-way pipe, valves, labels, Frame and Link are in the Tool panel.
- **Left-drag**: use the current tool (Select tool on empty space: box selection). **Right-click**: popup menu. **Right-drag**: erase
- **Mouse wheel over a part**: strength, pipe size or feeder feed. Over a valve it switches the valve
- **R / Shift+R**: rotate the selection right or left. On a single device, it flips a blower or switches a valve.
- **Electrical parts** (Select tool): hold a push button, click a switch / breaker / selector / E-Stop to work it, click a counter to reset it, turn a potentiometer with the mouse wheel; Ctrl+click to select it. **R** turns the selected part.
- **F1 / F2 / F3 / F4 / F5 / F6 / F7 / F8 / F9**: show or hide the Help, Tool, Simulation, Properties, Status, Page & Layer, Frame popup, Physics lab and Shape editor panels
- **Fluid parts** (Select tool): click a manual valve, compressor or pump to work it, hold a push-button valve; the mouse wheel turns a pressure or flow setting
- **PgUp / PgDn**: previous / next page. **Click a link** (Select tool): jump to its page or open its frame popup. **Esc** closes a frame popup
- **G**: show or hide the grid
- **Ctrl+wheel**, **Ctrl + / -**: zoom. **Ctrl+0**: 100%. **Middle-drag / arrow keys**: pan
- **Del**: delete the selected part. **Esc**: switch to the Select tool and clear the selection
- **[ ]**: brush pipe size. **P**: pressure view. **A**: air dots. **C**: clear material. **Space**: pause

## How the physics works

- **Air network:** every pipe cell is a node. Each connection lets air through more easily the larger the pipe is; when sizes differ, the smaller one sets the limit. Blowers, suction heads and nozzles add pump pressure. Open ends and feeders are open to the atmosphere. Pressures are solved each frame (SOR Gauss–Seidel), and air speed equals flow divided by pipe width.
- **Material in pipes:** the air drags particles along. They also feel gravity and wall friction, so sand needs enough suction to be lifted up a riser. At tees, particles split in proportion to the flow in each branch.
- **Free material:** gravity, air drag, suction pull and nozzle jets act on it. Particle contacts use position-based dynamics, so piles and liquid levels stay stable. Buckets and the floor are solid.

For a verification run without user input, `MaterialFlow.exe --shot <frames> out.bmp [layout.mflow]` simulates the demo, or the given layout (every page of it), for that many frames. It then saves a screenshot and a stats file (`out.bmp.txt`). `MaterialFlow.exe --export-examples examples` rewrites the example files and `demo_original.mflow` from the built-in versions. `MaterialFlow.exe --selftest report.txt` runs the automated checks (undo/redo, cut/copy/paste, panels, pages, layers, links, frame popups, equipment, the six states, the sequence, valves, heaters, rain, fire, wells, pools, ponds, pumps, electrical circuits, conveyors, potentiometers, current transformers, gauges, Focus Properties windows, pneumatic and hydraulic circuits, the virtual feeder, the menus, the Physics Lab, the Shape Editor, resizable panels, timers, counters, sensors, controllers, every page running at once, humidity sensors, heat exchangers, cooling towers, chillers, pH sensors, scrolling panels, the examples and the themes; 576 checks). Test runs never load `physics.mfphys` or `shapes.mfshape`.
