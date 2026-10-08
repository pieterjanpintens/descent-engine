"""One command that runs every official-asset import for YOUR OWN copy of "Descent: Legends of the Dark".

This repo ships none of the game's art. This wrapper only runs the three local import tools in this folder, in order,
against the game install on your own machine, and puts the results in the game's per-user data folder
(%APPDATA%\\Godot\\app_userdata\\Descent-Engine\\), where only you will ever see them:

    1. import_official_assets.py  - textures: floors, hazards, tokens, hero portraits, croptops, icons
    2. import_monster_meshes.py   - the monster figures and flat cards   (needs Godot 4.7.2)
    3. import_hero_meshes.py      - the hero models                      (needs Godot 4.7.2)

Usage (Windows):
    python import_all.py                      # finds the game and Godot by itself if it can
    python import_all.py "<game folder>" "<Godot 4.7.2 exe>"

`<game folder>` can be the game's install folder (the Steam folder, or any folder above the `bundles` folder) or the
`bundles` folder itself. If no Godot is found, only step 1 runs (the textures); the 3D figures need Godot.
See FRIENDS_GUIDE.md for the step-by-step version.
"""

import glob
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUTPUT = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Descent-Engine")

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
        for candidate in glob.glob(os.path.join(root, "*Descent*")):
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
    for pattern in (r"~\godot\**\Godot_v4.7*console.exe", r"~\Downloads\**\Godot_v4.7*console.exe",
                    r"~\Desktop\**\Godot_v4.7*console.exe", r"C:\Godot*\**\Godot_v4.7*console.exe"):
        hits = glob.glob(os.path.expanduser(pattern), recursive=True)
        if hits:
            return hits[0]
    return ""


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
    if os.name != "nt":
        print("These import tools write to the Windows %APPDATA% folder, so this wrapper is Windows-only for now.")
        return 1
    given_game = sys.argv[1] if len(sys.argv) > 1 else ""
    given_godot = sys.argv[2] if len(sys.argv) > 2 else ""

    bundles = find_bundles(given_game) if given_game else autodetect_game()
    if not bundles:
        print("Could not find the game's 'bundles' folder. Run again with the game folder as the first argument:")
        print('    python import_all.py "C:\\...\\Descent Legends of the Dark"')
        return 1
    print("Game assets: %s" % bundles)

    godot = given_godot or find_godot()
    if godot:
        print("Godot: %s" % godot)
    else:
        print("No Godot 4.7.2 found - only the textures will be imported (pass the Godot .exe as the second argument for the 3D figures).")

    if not ensure_unitypy():
        return 1

    results = {"textures": run("1/3 Textures, portraits, icons", "import_official_assets.py", bundles)}
    if godot:
        results["monster figures"] = run("2/3 Monster figures", "import_monster_meshes.py", bundles, godot)
        results["hero models"] = run("3/3 Hero models", "import_hero_meshes.py", bundles, godot)

    print("\n=== Done ===")
    for name, ok in results.items():
        print("  %-16s %s" % (name, "ok" if ok else "FAILED (see the messages above)"))
    print("Files are in: %s" % OUTPUT)
    print("Start the game again to see them.")
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
