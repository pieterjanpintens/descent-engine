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

## Extending the map

Adding a new placeholder-texture-path entry to `OfficialAssetMap.gd`'s `MAP` dict
is enough for the importer and the runtime swap to both pick it up automatically -
nothing else to touch, *except*: `OfficialAssetOverrides._apply_to_item()`
currently only handles single-surface meshes (verified true for everything matched
so far). Some meshes in `descent-meshes.tres` (the "medium"/"mini" pillars) do have
multiple surfaces/materials - if a future entry needs one of those, that function
needs extending to loop surfaces rather than just touching surface 0.
