"""Populates the local override folder that OfficialAssetOverrides.gd reads
from at runtime, using YOUR OWN legally-purchased copy of the official
"Descent: Legends of the Dark" companion app.

This tool, like the rest of this repo, ships and redistributes NO
copyrighted game art - it only reads Unity AssetBundle files that already
exist on your own machine (from your own game install) and copies the
named textures into Godot's user:// data folder, where only YOU will ever
see them, on YOUR OWN machine. Nothing here gets committed, bundled into
an export, or sent anywhere.

Requires: pip install UnityPy

Usage:
    python import_official_assets.py <path to game's StreamingAssets/bundles folder>

Reads the mapping from ../../autoload/OfficialAssetMap.gd (so it can never
drift out of sync with what the Godot side actually looks for), searches
every bundle file for each mapped official asset name, and saves matches
as PNGs into the Godot project's user:// data folder.

On Windows, Godot 4's default user:// folder for this project is:
    %APPDATA%\\Godot\\app_userdata\\Descent-Engine\\official_assets\\
(matches project.godot's config/name - if that ever changes, this path
needs to change too. Other OSes use a different base folder - see
https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)
"""
import sys
import os
import re
import glob
import UnityPy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ASSET_MAP_GD = os.path.join(SCRIPT_DIR, "..", "..", "autoload", "OfficialAssetMap.gd")
OVERRIDE_DIR = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Descent-Engine\official_assets")


def read_official_names_from_gd():
    """Parses OfficialAssetMap.gd's MAP dict for the official asset names
    (the dict VALUES, e.g. "W1_Underlay_FetidPool") - never hand-duplicate
    this list, it must always match what the Godot side actually reads."""
    with open(ASSET_MAP_GD, "r") as f:
        text = f.read()
    match = re.search(r"const MAP: Dictionary = \{(.*?)\n\}", text, re.DOTALL)
    if not match:
        raise RuntimeError(f"Couldn't find MAP dict in {ASSET_MAP_GD}")
    body = match.group(1)
    # each line looks like: "water": "W1_Underlay_Water",
    pairs = re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', body)
    return dict(pairs)  # our_name -> official_name


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    bundles_dir = sys.argv[1]

    name_map = read_official_names_from_gd()
    wanted = set(name_map.values())
    print(f"Looking for {len(wanted)} official asset(s): {sorted(wanted)}")

    os.makedirs(OVERRIDE_DIR, exist_ok=True)
    found = set()

    for path in sorted(f for f in glob.glob(os.path.join(bundles_dir, "*")) if os.path.isfile(f)):
        if not wanted - found:
            break
        try:
            env = UnityPy.load(path)
        except Exception:
            continue
        for obj in env.objects:
            if obj.type.name != "Texture2D":
                continue
            try:
                data = obj.read()
            except Exception:
                continue
            name = getattr(data, "m_Name", "")
            if name in wanted and name not in found:
                out_path = os.path.join(OVERRIDE_DIR, f"{name}.png")
                data.image.save(out_path)
                print(f"saved {out_path}")
                found.add(name)

    missing = wanted - found
    if missing:
        print(f"\nNot found in {bundles_dir}: {sorted(missing)}")
    print(f"\nDone. {len(found)}/{len(wanted)} official textures now in {OVERRIDE_DIR}")
    print("Godot will pick these up automatically next run - no export/rebuild needed.")


if __name__ == "__main__":
    main()
