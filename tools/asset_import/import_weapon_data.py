"""Exports the real weapon data (weapons, weapon parts, secondary abilities and their English texts) from YOUR OWN
copy of "Descent: Legends of the Dark" to Godot's user:// data folder, as plain JSON.

Same rule as every other tool in this folder: nothing here ships, redistributes or commits any game content - it only
reads the Unity AssetBundles on your own machine and writes to %APPDATA%\\Godot\\app_userdata\\Descent-Engine\\weapon_data\\.

Writes:
    weapons.json        {"weapons": [...], "parts": [...], "abilities": [...]}   every field of the game's own data
                        objects (WeaponModel / WeaponPartsModel / WeaponAbilityModel), minus the animation curves;
                        references to other objects (a part's ability, a weapon's starting parts) are replaced by
                        the referenced object's `_id`.
    localization_en.json  every English text whose key starts with WEAPON (names and descriptions of weapons, parts
                        and abilities; `<style=...>` markup left as in the game).

The numbers are the game's raw values (enums such as Class, Traits and RangeApproximation are not decoded yet).

Requires: pip install UnityPy

Usage:
    python import_weapon_data.py <path to game's bundles folder>
"""

import csv
import io
import json
import os
import sys

OUTPUT = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Descent-Engine\weapon_data")

DROPPED_FIELDS = {"m_GameObject", "m_Enabled", "m_Script", "DamageCurve", "AttackSound", "SelectSound"}


def kind_of(tree: dict) -> str:
    if "RangeApproximation" in tree:
        return "weapons"
    identifier = str(tree.get("_id", ""))
    if identifier.startswith("WEAPON_PART_") and "Damage" in tree:
        return "parts"
    if identifier.startswith("WEAPON_ABILITY_") and "KeyDesc" in tree:
        return "abilities"
    return ""


def is_pptr(value) -> bool:
    return isinstance(value, dict) and set(value.keys()) == {"m_FileID", "m_PathID"}


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    bundles = sys.argv[1]
    try:
        import UnityPy
    except ImportError:
        print("UnityPy is needed: pip install UnityPy")
        return 1

    result = {"weapons": [], "parts": [], "abilities": []}
    seen = set()
    localization = {}
    for name in sorted(os.listdir(bundles)):
        path = os.path.join(bundles, name)
        if not os.path.isfile(path):
            continue
        try:
            env = UnityPy.load(path)
        except Exception:
            continue
        ids = {}  # path id -> _id, for resolving references inside this file
        found = []  # (kind, tree)
        for obj in env.objects:
            kind = obj.type.name
            if kind == "TextAsset":
                data = obj.read()
                text = data.m_Script if isinstance(data.m_Script, str) else bytes(data.m_Script).decode("utf-8", "ignore")
                if text.startswith("Key,Type,Desc,English"):
                    for row in csv.DictReader(io.StringIO(text)):
                        if row["Key"].startswith("WEAPON") and row["English"]:
                            localization[row["Key"]] = row["English"]
            elif kind == "MonoBehaviour":
                try:
                    tree = obj.read_typetree()
                except Exception:
                    continue
                what = kind_of(tree)
                if what == "":
                    continue
                ids[obj.path_id] = tree["_id"]
                found.append((what, tree))
        for what, tree in found:
            if tree["_id"] in seen:
                continue
            seen.add(tree["_id"])
            entry = {}
            for key, value in tree.items():
                if key in DROPPED_FIELDS:
                    continue
                if is_pptr(value):
                    value = ids.get(value["m_PathID"], "") if value["m_PathID"] != 0 else ""
                elif isinstance(value, list) and value and all(is_pptr(v) for v in value):
                    value = [ids.get(v["m_PathID"], "") for v in value]
                entry[key] = value
            result[what].append(entry)

    for entries in result.values():
        entries.sort(key=lambda e: e["_id"])
    os.makedirs(OUTPUT, exist_ok=True)
    with open(os.path.join(OUTPUT, "weapons.json"), "w", encoding="utf-8") as handle:
        json.dump(result, handle, indent=1, ensure_ascii=False)
    with open(os.path.join(OUTPUT, "localization_en.json"), "w", encoding="utf-8") as handle:
        json.dump(dict(sorted(localization.items())), handle, indent=1, ensure_ascii=False)
    print("weapons %d, parts %d, abilities %d, texts %d -> %s" % (
        len(result["weapons"]), len(result["parts"]), len(result["abilities"]), len(localization), OUTPUT))
    return 0 if result["weapons"] else 1


if __name__ == "__main__":
    sys.exit(main())
