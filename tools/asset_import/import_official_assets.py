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

Matches both Texture2D assets (the floor/underlay materials) and Sprite
assets (icon-atlas assets like the token textures - Unity packs these as a
Sprite referencing a sub-rect of a shared atlas rather than a standalone
Texture2D, but UnityPy's `.image` resolves either one the same way).

Hero portraits (see HeroCatalog.gd) are matched by NAME + CONTAINER PATH,
unlike everything else here, which is matched by name alone - fixed after
confirming (by dumping the full manifest and comparing against portrait
files the user had already picked by eye) that EVERY hero has at least two
same-named Texture2D/Sprite objects sharing its bare name ("Chance"), one
under an "acti/" container and one under "actii/" (the two acts each have
their own portrait), so name-only matching could silently grab either
act's art depending on Unity's own object iteration order - a real bug,
not a hypothetical: Chance/Galaden's picked portraits are their Act II
art, Brynn/Vaerix/Kehli/Syrus's are Act I (mixed, not "always act N" -
whichever one the user actually looked at and preferred). See
HERO_PORTRAIT_CONTAINERS below for the exact container path recorded per
hero. A Texture2D and a Sprite sharing the identical container path render
identical pixels (confirmed directly: Syrus's picked file IS the Sprite,
not the Texture2D, at the same container - both exported to the same
256x256 image) - so once the container path is pinned down, which of the
two object TYPES actually matches first no longer matters.

Loads the ENTIRE bundles folder into one UnityPy environment rather than
one file at a time - required for assets whose material/texture (or, for
Sprites, atlas) lives in a different bundle file than the object itself
(seen with the token meshes' cross-bundle material references). Slower and
more memory-hungry than per-file loading, but this is a one-off local tool,
not something run often.

On Windows, Godot 4's default user:// folder for this project is:
    %APPDATA%\\Godot\\app_userdata\\Descent-Engine\\official_assets\\
(matches project.godot's config/name - if that ever changes, this path
needs to change too. Other OSes use a different base folder - see
https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)
"""
import sys
import os
import re
import UnityPy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ASSET_MAP_GD = os.path.join(SCRIPT_DIR, "..", "..", "autoload", "OfficialAssetMap.gd")
OVERRIDE_DIR = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Descent-Engine\official_assets")

## Container path per hero portrait (see the class doc above for why this is
## needed at all: the bare name alone is ambiguous between a hero's two
## acts). Recorded by hand, once, from the actual dumped manifest - not
## derivable from HeroCatalog.gd, which has no reason to know Unity's own
## folder layout.
HERO_PORTRAIT_CONTAINERS = {
    "Chance": "assets/d3/heroes/chance/actii/chance.png",
    "Galaden": "assets/d3/heroes/galaden/actii/galaden.png",
    "Brynn": "assets/d3/heroes/brynn/acti/brynn.png",
    "Vaerix": "assets/d3/heroes/vaerix/acti/vaerix.png",
    "Kehli": "assets/d3/heroes/kehli/acti/kehli.png",
    "Syrus": "assets/d3/heroes/syrus/actii/syrus.png",
}


def source_for(official_name):
    """(unity_name, container path or None, object type or None) for one
    official name from OfficialAssetMap.MAP. Most map 1:1 to a Unity asset of
    the same name; the "croptops" (added 2026-09-26) need a bit more:
      - "<Hero>_Weapon1_Crop" / "<Hero>_Weapon2_Crop" -> the Unity texture
        "<Hero>_Crop" in that hero's acti / actii folder (the game keeps one
        crop per act; Weapon 1 = acti, Weapon 2 = actii - assumed, by what the
        two images show), Texture2D (uniform 256x85, unlike the trimmed Sprite).
      - "Icons_<Kind>" (damage-type icons, plus "Icons_Unknown") are Sprites
        with unique names - no special handling, matched by name.
      - "<Monster>_Tab" -> the monster's tab image (the game has no
        monster "_CROP"; this is the equivalent), pinned to
        assets/d3/enemies/<monster>/<monster>_tab.png, Texture2D (256x121).
    """
    m = re.fullmatch(r"(\w+)_Weapon([12])_Crop", official_name)
    if m:
        hero = m.group(1).lower()
        act = "acti" if m.group(2) == "1" else "actii"
        return f"{m.group(1)}_Crop", f"assets/d3/heroes/{hero}/{act}/{hero}_crop.png", "Texture2D"
    m = re.fullmatch(r"(.+)_Tab", official_name)
    if m:
        folder = m.group(1).lower()
        return official_name, f"assets/d3/enemies/{folder}/{folder}_tab.png", "Texture2D"
    return official_name, HERO_PORTRAIT_CONTAINERS.get(official_name), None


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
    sources = {o: source_for(o) for o in wanted}
    print(f"Looking for {len(wanted)} official asset(s): {sorted(wanted)}")

    os.makedirs(OVERRIDE_DIR, exist_ok=True)
    found = set()

    print("Loading bundles folder (this can take a while)...")
    env = UnityPy.load(bundles_dir)

    for obj in env.objects:
        if obj.type.name not in ("Texture2D", "Sprite"):
            continue
        if not (wanted - found):
            break
        try:
            data = obj.read()
        except Exception:
            continue
        name = getattr(data, "m_Name", "")
        # An official name can be served by an object with a DIFFERENT Unity
        # name / need a container+type pin - see source_for().
        for official in [o for o in wanted - found if sources[o][0] == name]:
            _, wanted_container, wanted_type = sources[official]
            if wanted_container is not None and (getattr(obj, "container", "") or "") != wanted_container:
                continue
            if wanted_type is not None and obj.type.name != wanted_type:
                continue
            try:
                image = data.image
            except Exception:
                continue
            out_path = os.path.join(OVERRIDE_DIR, f"{official}.png")
            image.save(out_path)
            print(f"saved {out_path}")
            found.add(official)

    missing = wanted - found
    if missing:
        print(f"\nNot found in {bundles_dir}: {sorted(missing)}")
    print(f"\nDone. {len(found)}/{len(wanted)} official textures now in {OVERRIDE_DIR}")
    print("Godot will pick these up automatically next run - no export/rebuild needed.")


if __name__ == "__main__":
    main()
