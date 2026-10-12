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
| `src/mfexamples.pas` | The three built-in example layouts |
| `examples/*.mflow` | The same three examples as files you can open |

## Menus

The menu bar at the top of the panel has **File**, **Edit**, **View** and **Theme**. While one menu is open, moving the mouse over another one switches to it.

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

Undo records every finished action as one step: a whole pipe drag, a slider drag, a burst of mouse-wheel turns, a menu command, or loading a layout. It covers the pipe layout, part settings, buckets and gravity. Tank contents and material already flowing aren't rolled back, because the simulation drains tanks all the time.

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

### Labels

A label is a text box on the canvas for describing part of a layout. The demo and the three examples come with labels.
- With the **Label** tool, click an empty spot and type. **Enter** starts a new line. **Esc** or clicking elsewhere finishes. The first line is shown as the title.
- Double-click a label (Select tool), or use **Edit label** in its right-click menu, to edit it again. A label left empty is removed.
- Drag a label with the Select tool to move it. Labels can be box-selected, cut, copied, pasted, moved and deleted with the parts around them. A rotate moves a label with its group, but the text stays upright.
- Labels are saved in layout files and are part of undo. Typing into a label becomes one undo step when you finish.
- The built-in font has plain ASCII characters only.

### Right-click menu

Right-clicking the canvas without moving the mouse opens a popup with **Cut, Copy, Paste here, Delete, Rotate, Edit label**.
- Right-clicking inside a box selection keeps that selection.
- Right-clicking any other part or bucket selects it first.
- **Paste here** puts the clipboard at the cell you right-clicked.
- Right-drag still erases. A right-click on its own no longer erases; use **Delete** from the popup instead.

When you paste a single part onto an empty cell, it reconnects on the sides it was joined on before. Pasting onto an existing pipe swaps the part in and keeps that pipe's joints. Cutting a blower and pasting it back in the same place restores it exactly.

### View

| Item | Key | What it does |
|---|---|---|
| Tool | F2 | Shows or hides the Tool panel. |
| Simulation | F3 | Shows or hides the Simulation panel. |
| Properties | F4 | Shows or hides the Properties panel. |
| Status | F5 | Shows or hides the Status panel. |
| Help | F1 | Shows or hides the Help panel. |
| Dock all panels | | Shows all five panels and embeds each one back in its column (left or right). |
| Zoom in / Zoom out | Ctrl+= / Ctrl+- | Zooms the canvas in or out, 50% to 400%. |
| Zoom 100% | Ctrl+0 | Back to the normal size. |
| Pressure colours | P | Colours pipe bores by pressure. |
| Air dots | A | Shows the air tracer dots. |

### Panels

**Tool**, **Simulation**, **Properties**, **Status** and **Help** are separate windows. They start embedded one above the other in the right-hand column.
- Drag a title bar to float that panel anywhere, including over the canvas.
- Drop it near its slot to embed it again, or close it with **x**.
- Floating panels can overlap; clicking one brings it to the front.
- While a panel is hidden, floating or embedded on the left, its right-hand slot shows a **Show** or **Embed it here** button.

**Right-click a panel** for its popup:
- **Right embed** puts the panel in the right-hand column.
- **Left embed** opens a column on the left of the canvas and puts the panel there. The canvas moves right and keeps its size; the window gets wider. The left column closes again when no panel is left in it.
- **Float** detaches the panel.
- **Hide** hides it; its key (F1 to F5) brings it back.
- The panel's current place is ticked.

**Saved between runs:** the theme and each panel's state (shown or hidden, left or right, embedded or floating, and its floating position) are written to `materialflow.ini` next to the exe. The file is updated whenever a panel moves, and again on exit. Test runs (`--shot`, `--selftest`) never touch it.

**Tool panel:** the 15 tools (the default is **Select**), the tool hint and the pipe size brush.

**Simulation panel:**
- Run/Pause, Pressure colours and Air dots
- Gravity
- Clear flow, Clear floor, Load demo, New blank, Empty buckets and Fill tanks

**Properties panel:** the settings of whatever is selected:
- **Tank:** ingredients, Air %, Feed %.
- **Blower, suction head, push nozzle, drop outlet:** strength, plus **E / S / W / N** buttons to set the direction or mouth directly.
- **1-way pipe:** direction buttons.
- **Valves:** valve state. The 4-way valve has **E / S / W / N** buttons, one per branch: lit means open.
- **Label:** a preview of its text, **Edit text**, **Delete**, and left/top position.
- **Every part:** pipe size and joint type.
- **Bucket:** width, height, left and top position, fill level and amount overflowed.
- **Box selection:** counts of parts, buckets and labels, plus Cut, Copy, Rotate and Delete.

**Status panel:** particle count, frame rate, run state, zoom, and what is under the mouse (part, size, pressure, air speed, or label).

**Help panel:** five pages of short tips (Basics, Select & move, Edit, View & panels, Files & labels). Use the **<** and **>** buttons to turn the pages.

### Zoom and pan

- **Ctrl+mouse wheel** zooms around the mouse pointer. **Ctrl +** and **Ctrl -** zoom around the centre, and **Ctrl+0** goes back to 100%. The same commands are in the View menu.
- Zoom runs from 50% to 400%. Zoomed out, the layout sits in the middle of the canvas area.
- **Middle-drag** or the **arrow keys** pan the view. Panning stops at the edges of the layout.
- Every tool works the same when zoomed. Label and caption text keeps its normal size.

### Theme

**Default, Dark, Daylight, Warm white, Red, Green, Blue.** The theme recolours the canvas, pipes, buckets, panel and menus. Pale materials (fluff, air dots) get darker colours on the light themes so they stay visible. Your choice is saved in `materialflow.ini` next to the exe.

## Saving and loading layouts

The **File** menu has:

- **New layout** (Ctrl+N), **Open...** (Ctrl+O), **Save** (Ctrl+S), **Save as...** (Ctrl+Shift+S). Open and Save use the Windows file dialogs.
- **Example 1–3** and **Original demo** load the built-in layouts.

A layout file stores the pipes and devices with their settings, the tank contents, the buckets and the gravity setting. Material currently in flight isn't saved. Files are plain text, so you can edit them by hand:

```
MFLOW 1
NAME My layout
GRAVITY 1.00
CELL 14 2 tank S 4 E 1 0.00                      # x y kind conn size dir open strength
TANK 14 2 2500.00 0.00 0.00 0.00 10.00 70.00     # water oil fluff sand air% feed%
CELL 14 3 pipe SN 3 E 1 0.00
BUCKET 303.00 730.00 90.00 70.00                 # x y width height (pixels)
LABEL 380.00 40.00 Tank room\nwater and oil     # x y text, \n = new line
```

`kind` is one of `pipe tank blower suction nozzle drop check valve2 valve3 valve4`. A `valve4` line has a tenth value: its shut branches (for example `EW`, or `-` when all are open). `conn` lists the joined sides using the letters E, S, W, N. If a file is invalid, the app shows the line number and the reason, and the current layout stays loaded.

### Examples

1. **Gravity merge/overflow**: water falls by gravity through a one-way pipe. Oil and fluff are blown in through a narrowed section and join at a tee, then pass a 2-way valve and drop into a small bucket. The bucket overflows into a wide tray.
2. **Pneumatic conveyor**: a strong blower pushes sand through a widened section and up a tall riser. A 3-way valve at the top splits it into two drop outlets over two buckets; switch the valve with **R** to send everything one way.
3. **Vacuum & push nozzle**: water and fluff drop into a bucket. A suction head sucks them out through a one-way pipe, and a push-out nozzle shoots them sideways into a far bucket.

## What it covers

| Requirement | How it's done |
|---|---|
| Water, oil, fluff and sand, mixed with air | Each material behaves differently: weight, how strongly the air carries it, air drag, friction and density. Oil floats on water, fluff floats on top, sand sinks and piles up. Light-blue dots are air. |
| Adjustable ingredient quantities | Each **Tank** has −/+ buttons and a slider for every ingredient (0–3000 units), plus an **Air %** mix and a **Feed %** rate. Material that flows back into a tank is stored again. |
| Strength of suction, blow, push-out and drop discharge | Select a part (or scroll the mouse wheel over it) to set: **Blower** blow strength, **Suction** head strength (intake pull and pick-up reach), **Push nozzle** jet strength, and **Drop out** gravity gate %. There is also a global **Gravity** slider. |
| Easy pipe routing | Drag with the Pipe tool. Starting a drag on an existing pipe branches it into a tee. Clicking a device tool on a pipe inserts that device inline. Right-drag erases. |
| Material falls into a bucket and overflows | Buckets show a fill %, a level line and a flashing **OVERFLOW!** warning with a count of spilled particles. You can move buckets (Select + drag), resize them, empty them or delete them. |
| Single-way, 2-way, 3-way and 4-way | **1-way pipe** is a check valve: flow only follows the arrow. **2-way valve** is on/off. **3-way valve** diverts flow at a tee. **4-way valve** sits on a cross; each of its four branches opens or shuts on its own (R cycles: all open, shut one branch, straight E-W, straight N-S). Pipe joints are also recognized automatically: open end, straight or elbow, tee (3-way) and cross (4-way). |
| Pipe size, constricted or expanded along the way | Five pipe sizes. Use the **Pipe size** tool (or the mouse wheel) on individual cells. A narrow section resists flow and speeds the air up; a wide section slows it down. Size changes are drawn as tapered reducers. |

## Controls

- **1–0**: Select, Pipe, Pipe size, Erase, Tank, Blower, Suction, Push nozzle, Drop out, Bucket. The 1-way pipe, valves and Label are in the Tool panel.
- **Left-drag**: use the current tool (Select tool on empty space: box selection). **Right-click**: popup menu. **Right-drag**: erase
- **Mouse wheel over a part**: strength, pipe size or tank feed. Over a valve it switches the valve
- **R / Shift+R**: rotate the selection right or left. On a single device, it flips a blower or switches a valve.
- **F1 / F2 / F3 / F4 / F5**: show or hide the Help, Tool, Simulation, Properties and Status panels
- **Ctrl+wheel**, **Ctrl + / -**: zoom. **Ctrl+0**: 100%. **Middle-drag / arrow keys**: pan
- **Del**: delete the selected part. **Esc**: switch to the Select tool and clear the selection
- **[ ]**: brush pipe size. **P**: pressure view. **A**: air dots. **C**: clear material. **Space**: pause

## How the physics works

- **Air network:** every pipe cell is a node. Each connection lets air through more easily the larger the pipe is; when sizes differ, the smaller one sets the limit. Blowers, suction heads and nozzles add pump pressure. Open ends and tanks are open to the atmosphere. Pressures are solved each frame (SOR Gauss–Seidel), and air speed equals flow divided by pipe width.
- **Material in pipes:** the air drags particles along. They also feel gravity and wall friction, so sand needs enough suction to be lifted up a riser. At tees, particles split in proportion to the flow in each branch.
- **Free material:** gravity, air drag, suction pull and nozzle jets act on it. Particle contacts use position-based dynamics, so piles and liquid levels stay stable. Buckets and the floor are solid.

For a verification run without user input, `MaterialFlow.exe --shot <frames> out.bmp [layout.mflow]` simulates the demo, or the given layout, for that many frames. It then saves a screenshot and a stats file (`out.bmp.txt`). `MaterialFlow.exe --export-examples examples` rewrites the example files from the built-in versions. `MaterialFlow.exe --selftest report.txt` runs automated checks of undo/redo, cut/copy/paste and the themes.
