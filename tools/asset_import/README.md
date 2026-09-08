# Official asset import

Lets this project use art from the real "Descent: Legends of the Dark" companion
app for personal/local use, without ever shipping or redistributing any of it -
same pattern [OpenMW](https://openmw.org/) uses for Morrowind: the tool ships zero
copyrighted assets, and only an individual user who already owns the original game
can point it at their own install to unlock the real look, on their own machine.

## How it fits together

- `autoload/OfficialAssetMap.gd` — maps our internal mesh names (e.g. `"acid"`) to
  the official game's asset names (e.g. `"W1_Underlay_FetidPool"`). Hand-maintained;
  the names don't follow any convention that could derive one from the other.
- `autoload/OfficialAssetOverrides.gd` — at startup, for every MeshLibrary item with
  an entry in the map above, checks `user://official_assets/<OfficialName>.png` and
  swaps it onto that item's material if present. No file there = shipped placeholder
  stays untouched. This is the *only* place official art can ever enter the running
  game, and it never gets baked into an export.
- `import_official_assets.py` (this folder) — a one-time local tool **you** run,
  pointed at **your own** legal install of the game, to populate that folder.

## Usage

Requires `pip install UnityPy`.

```
python import_official_assets.py "<path to game>\<Game>_Data\StreamingAssets\bundles"
```

Reads the list of what to look for directly from `OfficialAssetMap.gd` (so it can
never drift out of sync with what Godot actually looks for), searches the game's
AssetBundle files for matching texture names, and saves them into Godot's
`user://official_assets/` folder for this project - on Windows, that's:

```
%APPDATA%\Godot\app_userdata\Descent-Engine\official_assets\
```

Re-run any time `OfficialAssetMap.gd` gains new entries. No Godot rebuild/export
needed - it picks up new override files the next time the app starts.

## Extending the map

Adding a new item to `OfficialAssetMap.gd`'s `MAP` dict is enough for the importer
and the runtime swap to both pick it up automatically - nothing else to touch,
*except*: `OfficialAssetOverrides._apply_texture()` currently only handles
single-surface meshes (verified true for everything in the map so far). Some
meshes in `descent-meshes.tres` (the "medium"/"mini" pillars) do have multiple
surfaces/materials - if a future entry needs one of those, that function needs
extending to loop surfaces rather than just touching surface 0.
