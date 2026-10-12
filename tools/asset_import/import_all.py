"""One command that runs every official-asset import for YOUR OWN copy of "Descent: Legends of the Dark".

This repo ships none of the game's art. This wrapper only runs the three local import tools in this folder, in order,
against the game install on your own machine, and puts the results in the app's per-user data folder (see user_data.py),
where only you will ever see them:

    1. import_official_assets.py  - textures: floors, hazards, tokens, hero portraits, croptops, icons
    2. import_monster_meshes.py   - the monster figures and flat cards   (needs Godot 4.7.2)
    3. import_hero_meshes.py      - the hero models                      (needs Godot 4.7.2)
    4. import_weapon_data.py      - weapons, weapon parts, abilities and their texts (JSON)
    5. import_item_data.py        - materials, recipes, potions, armor, trinkets, enemy loot (JSON)
    6. import_monster_data.py     - the game's monsters: tiers, activations, weaknesses, abilities (JSON)

Usage:
    import_all.bat                 (Windows: double-click)
    ./import_all.sh                (macOS / Linux: makes its own Python environment with UnityPy)
    python import_all.py ["<game folder>" ["<Godot 4.7.2 program>"]]     # both are found automatically when possible

`<game folder>` can be the game's install folder (the Steam folder, or any folder above the `bundles` folder) or the
`bundles` folder itself. If no Godot is found, only step 1 runs (the textures); the 3D figures need Godot.
See FRIENDS_GUIDE.md for the step-by-step version.
"""

import glob
import os
import shutil
import subprocess
import sys

from user_data import user_data_dir

HERE = os.path.dirname(os.path.abspath(__file__))
OUTPUT = user_data_dir()

if os.name == "nt":
    GAME_ROOTS = [
        r"C:\Program Files (x86)\Steam\steamapps\common",
        r"C:\Program Files\Steam\steamapps\common",
        r"D:\SteamLibrary\steamapps\common",
        r"E:\SteamLibrary\steamapps\common",
        r"C:\Program Files\Epic Games",
        r"C:\Program Files (x86)\Epic Games",
        r"C:\GOG Games",
        r"C:\Program Files (x86)\GOG Galaxy\Games",
    ]
elif sys.platform == "darwin":
    GAME_ROOTS = [os.path.expanduser("~/Library/Application Support/Steam/steamapps/common"), "/Applications",
                  os.path.expanduser("~/Applications")]
else:
    GAME_ROOTS = [os.path.expanduser("~/.steam/steam/steamapps/common"),
                  os.path.expanduser("~/.local/share/Steam/steamapps/common"),
                  os.path.expanduser("~/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common")]
# The Steam folder is called "Legends of the Dark" on macOS, "Descent Legends of the Dark" elsewhere.
GAME_PATTERNS = ["*Descent*", "*Legends of the Dark*"]


def find_bundles(start: str) -> str:
    """The folder named `bundles` below `start` (or `start` itself if it is one)."""
    if os.path.basename(os.path.normpath(start)).lower() == "bundles":
        return start
    for folder, dirs, _files in os.walk(start):
        if os.path.basename(folder).lower() == "bundles" and "streamingassets" in folder.lower():
            return folder
        if folder.count(os.sep) - start.count(os.sep) > 6:
            dirs[:] = []
    return ""


def autodetect_game() -> str:
    for root in GAME_ROOTS:
        for pattern in GAME_PATTERNS:
            for candidate in glob.glob(os.path.join(root, pattern)):
                found = find_bundles(candidate)
                if found:
                    return found
    return ""


def find_godot() -> str:
    for name in ("GODOT", "GODOT4"):
        if os.environ.get(name) and os.path.isfile(os.environ[name]):
            return os.environ[name]
    for name in ("godot", "godot4", "Godot_v4.7.2-stable_win64_console", "Godot_v4.7.2-stable_win64"):
        found = shutil.which(name)
        if found:
            return found
    if os.name == "nt":
        patterns = [r"~\godot\**\Godot_v4.7*console.exe", r"~\Downloads\**\Godot_v4.7*console.exe",
                    r"~\Desktop\**\Godot_v4.7*console.exe", r"C:\Godot*\**\Godot_v4.7*console.exe"]
    elif sys.platform == "darwin":  # the program inside the .app
        patterns = ["/Applications/Godot*.app/Contents/MacOS/Godot", "~/Applications/Godot*.app/Contents/MacOS/Godot",
                    "~/Downloads/Godot*.app/Contents/MacOS/Godot", "~/Desktop/Godot*.app/Contents/MacOS/Godot"]
    else:
        patterns = ["~/godot/**/Godot_v4.7*linux*", "~/Downloads/**/Godot_v4.7*linux*", "~/Desktop/**/Godot_v4.7*linux*",
                    "~/.local/bin/Godot_v4.7*"]
    for pattern in patterns:
        hits = [hit for hit in glob.glob(os.path.expanduser(pattern), recursive=True) if os.path.isfile(hit)]
        if hits:
            return hits[0]
    return ""


def godot_program(path: str) -> str:
    """A macOS Godot.app is a folder: the program to run is inside it."""
    inside = os.path.join(path, "Contents", "MacOS", "Godot")
    return inside if os.path.isdir(path) and os.path.isfile(inside) else path


def ensure_unitypy() -> bool:
    try:
        import UnityPy  # noqa: F401
        return True
    except ImportError:
        pass
    print("The Python package UnityPy is needed to read the game files.")
    if input("Install it now with 'pip install UnityPy'? [y/N] ").strip().lower() != "y":
        return False
    return subprocess.call([sys.executable, "-m", "pip", "install", "UnityPy"]) == 0


def run(step: str, script: str, *args: str) -> bool:
    print("\n=== %s ===" % step)
    return subprocess.call([sys.executable, os.path.join(HERE, script), *args]) == 0


def main() -> int:
    sys.stdout.reconfigure(line_buffering=True)  # keep our lines in order with the steps' own output
    given_game = sys.argv[1] if len(sys.argv) > 1 else ""
    given_godot = sys.argv[2] if len(sys.argv) > 2 else ""

    bundles = find_bundles(given_game) if given_game else autodetect_game()
    if not bundles:
        print("Could not find the game's 'bundles' folder. Run again with the game folder as the first argument:")
        print('    "%s" "<game folder>"' % ("import_all.bat" if os.name == "nt" else "./import_all.sh"))
        return 1
    print("Game assets: %s" % bundles)

    godot = godot_program(given_godot) if given_godot else find_godot()
    if godot:
        print("Godot: %s" % godot)
    else:
        print("No Godot 4.7.2 found - only the textures will be imported (pass the Godot program as the second argument for the 3D figures).")

    if not ensure_unitypy():
        return 1

    results = {"textures": run("1/6 Textures, portraits, icons", "import_official_assets.py", bundles)}
    if godot:
        results["monster figures"] = run("2/6 Monster figures", "import_monster_meshes.py", bundles, godot)
        results["hero models"] = run("3/6 Hero models", "import_hero_meshes.py", bundles, godot)
    results["weapon data"] = run("4/6 Weapon data", "import_weapon_data.py", bundles)
    results["item data"] = run("5/6 Item data", "import_item_data.py", bundles)
    results["monster data"] = run("6/6 Monster data", "import_monster_data.py", bundles)

    print("\n=== Done ===")
    for name, ok in results.items():
        print("  %-16s %s" % (name, "ok" if ok else "FAILED (see the messages above)"))
    print("Files are in: %s" % OUTPUT)
    print("Start the game again to see them.")
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
