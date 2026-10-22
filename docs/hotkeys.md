# Hotkeys and mouse controls

On macOS read **Ctrl** as **Cmd**. Keys that are not listed here do nothing.

## Mission editor (3D view)

Most keys only work while no text box has the focus.

### Camera (any time, also in the Player)
| Input | Does |
|---|---|
| Hold **right mouse button** + drag | look around |
| While holding it: **W A S D** | move forward / left / back / right |
| While holding it: **Q / E** | move down / up |
| While holding it: **Shift** | move 3x faster |
| **Mouse wheel** | dolly forward / back |

### Tools and modes
| Key | Does |
|---|---|
| **D** | toggle **Draw** mode (paint pieces) and **Select** mode (click to select). Picking a mesh in the Palette switches Draw on by itself; leaving the Palette tab switches it off. |
| **P** | toggle the **Player Start** tool (click a square to add / remove a hero start square) |
| **M** | toggle **Move** mode (drag a placed piece to a new square) |
| **O** | toggle the occupancy overlay (also View menu) |
| **N** | toggle the tile name labels (also View menu) |
| **,** and **.** | previous / next mesh in the current layer |
| **L** | cycle the layer filter (Floor, Prop, Underlay) |
| **Page Up / Page Down** | painting level up / down (floors higher than the ground) |

The Monster Spawn and LOS Blocker tools have no hotkey; pick them in the Palette's **Misc** tab. Only one tool is active at a time.

### Mouse in the 3D view
| Input | Draw mode | Select mode | Move mode |
|---|---|---|---|
| **Left click** | place the selected piece | select the piece under the pointer (also selects it in the Outline) | pick up the piece, drop it on release |
| **Shift + left click** | erase the piece under the pointer | | |

With the Player Start / Monster Spawn / LOS Blocker tool on, a left click toggles the square under the pointer.

### Editing the selection
| Key | Does |
|---|---|
| **R** (Draw mode) | rotate the piece you are about to place |
| **R** (otherwise) | rotate the selected piece a quarter turn **in place**; for a selected **stage** (group) or several things, turn them as one body |
| **Arrow keys** | move the selection one square, as one body (a selected stage takes everything in it along). Up = away from the camera, right = to the camera's right. Only works while the **pointer is over the 3D view**; over the Outline or a panel the arrows keep their normal job. |
| **Ctrl+Z** | undo |
| **Ctrl+Shift+Z** | redo |

Holding an arrow key or tapping it quickly counts as one undo step.

### Files and menus
| Key | Does |
|---|---|
| **Ctrl+N** | New mission |
| **Ctrl+O** | Load |
| **Ctrl+S** | Save (to the file the mission came from; Save As the first time) |
| **Ctrl+Shift+S** | Save As |
| **Ctrl+Enter** | Play the mission you are editing (no need to save first) |

### Outline tree
| Input | Does |
|---|---|
| **Click** | select one thing |
| **Ctrl+click / Shift+click** | add to / extend the selection |
| **Arrow keys** (pointer over the tree) | walk the tree |
| **Right click** | menu: new group / subgroup, rename, delete, **Move to...** |
| **Double click** a group | rename it |

## Player (playing a mission)

| Key | Does |
|---|---|
| **M** | switch between the map and the monster view |
| **Tab** | show / hide the typed-command box (the text version of voice commands) |
| **V** (hold) | push to talk, if voice control is set up (default mode) |

In a **test run from the editor** (Play menu) there are extra keys:

| Key | Does |
|---|---|
| **F9** | take a snapshot into the "quick" slot |
| **F10** | roll back to the quick snapshot |
| **Ctrl+E** | back to the editor, with everything as you left it |

The Gear menu (bottom left) has Line of Sight, Options, Rules Reference, Save, Debug and Back to Menu. In the line of sight tool, click a floor square to see what it can see and how far away each square is.

## Campaign editor

| Key | Does |
|---|---|
| **Ctrl+N** | New campaign |
| **Ctrl+S** | Save |
| **Ctrl+Enter** | Playtest from the start |
| **Ctrl+Z / Ctrl+Shift+Z** | undo / redo (typing and dragging a pin are grouped into one step) |

On the map: **left click** a pin to select it, **drag** it to move it.

## Text boxes in the story and writing windows

| Input | Does |
|---|---|
| Right click a misspelled word | spelling suggestions, "Add to the dictionary" |
| Select text, click a coloured name under the box | wrap it in that character's voice tag |
| **Dictate** button (top right of the box) | click, speak, click again: the words are typed in (needs voice control set up) |
| **AI** button (top right of the box) | writing help (needs AI help turned on in Options) |
