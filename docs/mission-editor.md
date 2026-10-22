# The mission editor

Open it from the main menu: **Editors & Tools > Mission Editor**. A mission is one map plus the story rules that run on it. Missions are saved as files in your user folder (`missions/`) and can also live inside a campaign folder.

All keys are in [hotkeys.md](hotkeys.md).

## Layout

- **Menu bar**: File, Edit, View, Play.
- **Toolbar** under it: *Working group*, **Generate stage...**, **Problems**, *Show unavailable*.
- **3D view** on the left: where you build.
- **Side panel** on the right with two tabs: **Palette** (what you can place) and **Outline** (everything that is placed, plus the properties of the selection).
- **Status bar** (bottom left of the 3D view): the position of the square under the pointer, in game units (the first square is 0, 0).

## Building the map

The map is made of the physical pieces of the box, so the editor stops you using more copies than exist (a greyed-out piece has none left; tick *Show unavailable* and click it to jump to where it is used).

1. In the **Palette**, pick a layer tab and a piece:
   - **Floor**: the walkable tiles (faces a/b of each tile).
   - **Prop**: pillars, stairs, gates, archways, trees, ladders, furniture, tokens.
   - **Underlay**: hazard cards (water, acid, lava, spikes) that lie under the floor.
   - **Misc**: tools that are not pieces (see below).
2. Click in the 3D view to place; **R** rotates the piece you are about to place; **Shift+click** erases.
3. Pieces snap to whole squares. Pillars are the exception: they can sit on half squares.
4. **Page Up / Page Down** change the level you paint on, for raised floors. Raised floors need something holding them up (pillars, stairs, archways) and a way to reach them (stairs, ladders); the Problems list tells you when they don't.

### The Misc tab
- **Player Start**: click squares to mark where the heroes start. You need at least as many as the most heroes that may play.
- **Monster Spawn**: pick or create a spawn area, then click squares. The order you click is the order the monsters are placed (tile 1, tile 2, ...). A square can belong to one spawn only.
- **LOS Blocker**: squares that block line of sight like an infinitely high wall (for example to stop shots across open space). Put a blocker in a stage group and it only counts once that stage is revealed, so it doesn't give the level away. Blockers may overlap.

### Select, move, rotate
- **D** switches between Draw and Select mode. In Select mode a click selects the piece (it is also selected in the Outline).
- **M** (Move mode): drag a placed piece to another square. The drop is refused if the square is taken.
- **R** on a selected piece turns it in place.
- **Arrow keys** move the selection; see below.

## Stages (groups)

A **group** is a stage: an area of the map that can be revealed later during play (the Show Stage effect). The group containing the hero start squares is revealed automatically at the start.

- Right click in the Outline to make groups and subgroups, rename or delete them, or **Move to...** another group. Deleting a group keeps its contents (they move up one level).
- Set the **Working group** in the toolbar and everything you draw lands in that group.
- Select several pieces (Ctrl/Shift+click) and use *Move to Group* in the panel to group them afterwards.
- **A selected stage can be moved and turned as a whole**: arrow keys (pointer over the 3D view) move it one square, **R** turns it. Everything in it keeps its place relative to the rest: floors, props, monster spawns and LOS blockers inside it, and the hero start squares that lie on its floor. The move is refused if it would land on a piece outside the stage. This is how you line up a stage you generated with the rest of the map.
- The *Visible* box on a group hides everything in it until revealed.

## The Outline and properties

Click anything in the Outline to select it and see its properties underneath:

- **Name**: a reference name, used to point at the piece from effects and conditions (and shown in the Outline).
- **Visible**.
- For props: **Custom Properties...** (free-form values, e.g. whether it can be interacted with) and **Actions...** (see below).
- Nothing selected (the mission root): the mission's own settings, **Objectives...**, **Variables...**, **Characters...**, **Triggers...** and the minimum / maximum number of players.

## Story rules

Everything here is edited with the same condition and effect rows.

### Variables
**Variables...** declares the variables the mission uses (yes/no, number, decimal, text). A variable that is not declared does nothing, so declare first. Anywhere you pick a variable there is a **+ New variable...** entry to make one on the spot. Built in: `round_number`, `player_count`, `affliction_damage`.

### Actions on props
**Actions...** on a prop lists what the players can do with it ("open", "search", "pull the lever"). In the game a hero is dragged onto the prop and the action is chosen. An action has:
- *conditions* (when it is offered at all),
- *single shot* (it can be used once),
- *effects*, which run when it is used.

### Effects
An effect is one thing that happens. Every effect can have its own conditions. The kinds:

| Effect | Does |
|---|---|
| Set Variable | write a value |
| Math | add, subtract, multiply, divide or take the remainder of two numbers or variables |
| Show Stage | reveal a group; the players are told how to build it, piece by piece |
| Remove Object | take a prop or tile off the board (a door that disappears once opened) |
| Move Object | move a prop or tile to given coordinates |
| Test | ask for an attribute roll; branches on pass / fail, or adds the result to a counter. The needed number is never shown to the players. |
| Show Message | tell the table something; `$1`, `$2`... in the text are replaced by variables |
| Spawn Monsters | the players take the listed monsters from the box and place them on a spawn area |
| Loot | add gold, materials, cards or recipes to the party (shown to them) |

Use the arrows on a row to reorder; the order matters when one effect writes what the next one reads.

### Objectives
**Objectives...** is a graph. A node is an objective with *conditions* (when it is reached), *effects*, a *priority*, and optional side objectives. Drag from one node to another to make the second follow the first. A node with no follow-up is a final objective and is a **Win** or a **Loss**. A node nothing leads into is a start node (marked with a star); you can have several. When a node has several follow-ups, the first one (by priority) whose conditions hold wins and the others are dropped.

A mission needs at least one path that ends in a win.

### Triggers
**Triggers...** run effects without a player action: at a **round checkpoint** (before / during / after the player phase and the monster phase) or when a prop **action** is used. Each has conditions, a priority (lower first) and *one shot* (untick to repeat every round).

### Characters
**Characters...** gives named speakers a voice for narration. In any message text, `[Name]words[/Name]` is read in that character's voice. Names you don't define get a voice from their name (start the name with M or F for a male or female voice).

## Monsters

- **File > Monster Templates...** opens the template library; see [other-tools.md](other-tools.md).
- A Spawn Monsters effect lists monsters, each with a **Properties...** button: name, level, one **base** template (required) and any number of **additive** templates. The preview shows the resulting numbers.

## Checking your work

- **Problems** (toolbar): a live list of what is wrong or unfinished: pieces floating or overlapping, floors nobody can reach, missing start squares, no way to win, undeclared variables. **Show** next to a problem selects the piece and moves the camera there. Red means errors, amber warnings, green means all clear.
- **Play** menu (or **Ctrl+Enter**): runs the mission you are editing right now, without saving.
  - *Fast start* skips the setup dialogs and banners.
  - In the test run **F9** takes a snapshot, **F10** rolls back to it, **Ctrl+E** returns to the editor. You can fix the mission, then *Play from snapshot* to continue from that point on the changed mission.
  - The Gear > **Debug** panel in the Player sets variables, reveals a stage and manages the snapshot slots.
- **Occupancy overlay** (O) and **Tile name labels** (N) show what the editor thinks is where, handy when a piece won't select or place.

## Generate stage (experimental, needs AI help)

**Generate stage...** (toolbar): describe an area in words ("a crossroad, on each end a staircase with a door"), optionally tick that the heroes start there, and press **Generate**. The AI designs it from the pieces still free, every answer is checked by the same rules as the Problems list, and it retries (up to 4 times) with the problems as feedback. You see a picture of the result; **Build into the mission** creates a new stage group (one undo step). Place it with the corner fields or *Next free spot*, then use the arrow keys and **R** on the new stage to line it up.

AI help is off until you turn it on in **Options > AI** (your own API key, or Claude Code on this PC). Nothing is sent before you press Generate.

## Saving, settings, sharing

- **Save** writes to the file the mission came from; **Save As** asks for a new one. Missions that belong to an installed release are read-only: use *Fork to edit*.
- **File > Settings...**: automatic backups (a frequent shallow set and a rarer deeper set), off by default.
- **File > Release...** packs the mission as a versioned package you can share (see [other-tools.md](other-tools.md)).
