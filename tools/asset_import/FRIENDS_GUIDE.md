# Getting the real game art into the app (for friends)

The app ships with plain placeholder pictures only. If you own **Descent: Legends of the Dark** on your PC, you can
let the app use its real art - floors, tokens, portraits, monsters and heroes - by copying it out of **your own**
install. Nothing is downloaded and nothing leaves your computer; the copies stay in your own user folder and are
never part of the app.

## What you need

1. **The game installed** on this PC (Steam, GOG or Epic).
2. **Python 3** (https://www.python.org/downloads/ - tick "Add python.exe to PATH" in the installer).
3. **The asset tools**: download **`Descent-Engine-asset-tools.zip`** from the same release page as the app and unzip it anywhere
   (it is small - the tools plus the little project around them that they need). Developers can also use the full source zip.
4. *Optional, for the monsters and heroes as 3D models:* **Godot 4.7.2** (https://godotengine.org/download/archive/ -
   the "Standard" Windows build; unzip it anywhere, no install). Without it you still get all the pictures.

## Steps

1. Open the unzipped `Descent-Engine-asset-tools` folder and go into `tools\asset_import\`.
2. Double-click **`import_all.bat`**.
   - It looks for the game in the usual Steam/GOG/Epic folders and for Godot in the usual places.
   - If it asks to install `UnityPy` (a Python package that reads the game's files), type `y` and press Enter.
3. If it says it could not find the game or Godot, open a command prompt in that folder and give it the paths:

   ```
   python import_all.py "C:\Program Files (x86)\Steam\steamapps\common\Descent Legends of the Dark" "C:\Tools\Godot_v4.7.2-stable_win64_console.exe"
   ```

   The first path is the game's folder, the second is the Godot **console** `.exe` (leave it out if you have no Godot).
   **macOS / Linux**: open a terminal in `tools/asset_import/` and run `./import_all.sh` (or `sh import_all.sh`). It makes its
   own Python environment (a `.venv` folder next to it) and installs `UnityPy` there, so you only need Python 3 itself. The
   game and Godot are found by themselves when the game is in the Steam library and `Godot.app` is in Applications; otherwise:

   ```
   ./import_all.sh "<game folder or the game's .app>" "/Applications/Godot.app"
   ```
4. Wait. Reading all the game files takes a few minutes and a lot of memory. When it prints **Done** with every step
   "ok", start the app - the real art is used automatically.

## Where the files go

- Windows: `%APPDATA%\Godot\app_userdata\Descent-Engine\` (paste that into the Explorer address bar)
- macOS: `~/Library/Application Support/Godot/app_userdata/Descent-Engine/` (Finder: Go > Go to Folder)
- Linux: `~/.local/share/godot/app_userdata/Descent-Engine/`

To go back to the
placeholders, delete the `official_assets`, `monster_assets`, `hero_assets`, `weapon_data`, `item_data` and `monster_data` folders in there.

## If something goes wrong

- *"Could not find the game's bundles folder"* - give the game folder as the first argument (step 3).
- *A step says FAILED* - read the lines above it; run the wrapper again, it is safe to repeat. Steps 2 and 3 need Godot
  4.7.2 exactly (other versions can import differently).
- Only the textures appeared, no 3D figures - you ran without Godot; run again with the Godot path.
- Please **don't share the extracted files** with others: they are the game's copyrighted art. Everyone imports from
  their own copy of the game instead - that is what this guide is for.
