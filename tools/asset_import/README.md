# Official asset import

Lets this project use art from the real "Descent: Legends of the Dark" companion
app for personal/local use, without ever shipping or redistributing any of it -
same pattern [OpenMW](https://openmw.org/) uses for Morrowind: the tool ships zero
copyrighted assets, and only an individual user who already owns the original game
can point it at their own install to unlock the real look, on their own machine.

## How it fits together

- `autoload/OfficialAssetMap.gd` — maps a shipped PLACEHOLDER texture's path (e.g.
  `"res://models/underlays_acid.png"`) to the official game's asset name (e.g.
  `"W1_Underlay_FetidPool"`). Hand-maintained; the names don't follow any convention
  that could derive one from the other. Keyed by texture path rather than mesh
  name deliberately - several floor tile faces share the exact same placeholder
  texture (that's the point of the flagstone/grass/dirt/wood-planks material
  system), so one map entry covers every tile face using that look.
- `autoload/OfficialAssetOverrides.gd` — at startup, scans every MeshLibrary item's
  CURRENT texture and looks it up in the map above; if
  `user://official_assets/<OfficialName>.png` exists, swaps it onto that item's
  material. No file there = shipped placeholder stays untouched. This is the *only*
  place official art can ever enter the running game, and it never gets baked into
  an export.
- `import_official_assets.py` (this folder) — a one-time local tool **you** run,
  pointed at **your own** legal install of the game, to populate that folder.

## Usage

Requires `pip install UnityPy`.

```
python import_official_assets.py "<path to game>\<Game>_Data\StreamingAssets\bundles"
```

Reads the list of what to look for directly from `OfficialAssetMap.gd` (so it can
never drift out of sync with what Godot actually looks for), searches the game's
AssetBundle files for matching asset names - both `Texture2D` (the floor/underlay
materials) and `Sprite` (icon-atlas assets, like the token textures - Unity packs
these as a sub-rect of a shared atlas rather than a standalone `Texture2D`, but
UnityPy's `.image` resolves either the same way) - and saves them into Godot's
`user://official_assets/` folder for this project - on Windows, that's:

```
%APPDATA%\Godot\app_userdata\Descent-Engine\official_assets\
```

Re-run any time `OfficialAssetMap.gd` gains new entries. No Godot rebuild/export
needed - it picks up new override files the next time the app starts.

Loads the entire bundles folder into one UnityPy environment (rather than one
file at a time) so cross-bundle references resolve - some assets' material,
texture, or (for Sprites) atlas lives in a different bundle file than the
object itself. Slower and more memory-hungry than per-file loading, but this
is a one-off local tool, not something run often.

## Exploring everything (`dump_all_assets.py`)

`import_official_assets.py` only ever pulls the handful of textures
`OfficialAssetMap.gd` already has exact names for - useless for finding
something nobody's named yet, like monster meshes for the in-progress
combat work (see `claude.md`'s Open item #3). `dump_all_assets.py` is a
broader, exploratory companion: point it at the same bundles folder and it
dumps EVERYTHING it can - every `Mesh` as a `.obj` (confirmed against the
actually-installed UnityPy's own `Mesh.export()` API, not guessed), every
`Texture2D`/`Sprite` as a `.png`, and a full `manifest.tsv` (type, name,
container path, id) covering every object of every type, exported or not -
grep that first for anything monster-shaped before digging through meshes
one file at a time.

```
python dump_all_assets.py "<path to game>\<Game>_Data\StreamingAssets\bundles"
```

Writes to `%APPDATA%\Godot\app_userdata\Descent-Engine\asset_dump\` by
default (same outside-the-repo, never-committed location as
`official_assets\` above) - pass a second argument to write somewhere else.
Same one-environment-for-the-whole-folder loading as the importer above,
for the same cross-bundle-reference reason - this one's slower still, since
it processes every object instead of stopping once a short wanted-list is
found.

## Extending the map

Adding a new placeholder-texture-path entry to `OfficialAssetMap.gd`'s `MAP` dict
is enough for the importer and the runtime swap to both pick it up automatically -
nothing else to touch, *except*: `OfficialAssetOverrides._apply_to_item()`
currently only handles single-surface meshes (verified true for everything matched
so far). Some meshes in `descent-meshes.tres` (the "medium"/"mini" pillars) do have
multiple surfaces/materials - if a future entry needs one of those, that function
needs extending to loop surfaces rather than just touching surface 0.

## Monster meshes (`import_monster_meshes.py`)

A third tool, for `MonsterDisplay.gd`'s real monster figures (see
`claude.md`'s **Mesh conversion: Godot's own native importer, not a
hand-rolled parser** section for the full backstory) - **this one is
different from the two above: it also needs a real Godot 4.7.2 executable
on your machine, not just Python.** A hand-rolled runtime `.obj` parser was
tried first for monster meshes and consistently produced wrong
orientation/shading no matter what coordinate-math theory got thrown at
it, while Godot's own native `res://` OBJ importer gets it right on the
first try - so this tool leans on that importer directly (by shelling out
to it, headless, twice) instead of re-deriving its behavior by hand.

```
python import_monster_meshes.py "<path to game>\<Game>_Data\StreamingAssets\bundles" "<path to Godot 4.7.2 executable>"
```

Reads which monsters to extract straight from `MonsterDisplay.REAL_MONSTERS`
(same "read the source of truth" convention as `import_official_assets.py`
reading `OfficialAssetMap.gd`'s `MAP` dict) - re-run any time that array
gains a new monster. For each one, finds its "`<folder>` plastic pool.prefab"
Mesh + diffuse Texture2D by **container path** rather than internal object
name (mesh/texture names aren't consistent across monsters - e.g. Zealot's
own mesh is literally named `"default"` - but every plastic-pool asset's
container path follows
`assets/d3/enemies/<folder>/prefabs/"<folder> plastic pool.prefab"`,
confirmed against the 4 monsters already wired in), stages each `.obj` into
a temporary, already-gitignored folder inside the actual Godot project
(`models/original/monster_staging/`), saves each texture straight to its
final `user://monster_assets/<folder>/diffuse.png` (no Godot needed for
textures - loaded via `Image.load_from_file()` at runtime, same as the
floor/underlay override textures above), then runs the given Godot
executable headless twice: once with `--import` (so the staged `.obj`
files go through Godot's own native import pipeline), then once running
`convert_staged_meshes.gd` (this same folder - a checked-in, permanent
tool script, unlike the earlier one-off `convert.gd` this replaces) which
loads each natively-imported mesh and re-saves it as a portable
`user://monster_assets/<folder>/mesh.tres` - the ONLY thing
`MonsterDisplay.gd` actually reads at runtime. The staging folder is
deleted again once conversion finishes.

On Windows, the final output lands at:

```
%APPDATA%\Godot\app_userdata\Descent-Engine\monster_assets\<folder>\{mesh.tres,diffuse.png}
```
