"""Exports the game's item data - crafting materials, recipes (what a craftable item costs), consumables (potions and
the like), armor, trinkets and what each enemy drops - from YOUR OWN copy of "Descent: Legends of the Dark" to Godot's
user:// data folder, as plain JSON. Same rule as every other tool in this folder: nothing here ships, redistributes or
commits any game content; it only reads the Unity AssetBundles on your machine and writes to
%APPDATA%\\Godot\\app_userdata\\Descent-Engine\\item_data\\.

Writes:
    items.json              {"materials": [...], "recipes": [...], "consumables": [...], "armors": [...],
                             "trinkets": [...], "enemy_loot": [...]} - the game's own fields, references resolved to ids
                             (a recipe's ingredients become {"material": "MAT_METAL", "qty": 4}).
    localization_en.json    the English names / descriptions of those items (keys MAT_*, ARMOR_*, CSM_*, TRINKET*...).

Requires: pip install UnityPy

Usage:
    python import_item_data.py <path to game's bundles folder>
"""

import csv
import io
import json
import os
import sys

OUTPUT = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Descent-Engine\item_data")
DROPPED = {"m_GameObject", "m_Enabled", "m_Script"}
LOC_PREFIXES = ("MAT_", "ARMOR_", "CSM_", "TRINKET", "ITEM_", "LOOT", "ENEMY_ACTIVATION_")


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

    trees = {}  # path id -> compact typetree of every MonoBehaviour (so references can be resolved across bundles)
    localization = {}
    for name in sorted(os.listdir(bundles)):
        path = os.path.join(bundles, name)
        if not os.path.isfile(path):
            continue
        try:
            env = UnityPy.load(path)
        except Exception:
            continue
        for obj in env.objects:
            if obj.type.name == "TextAsset":
                data = obj.read()
                text = data.m_Script if isinstance(data.m_Script, str) else bytes(data.m_Script).decode("utf-8", "ignore")
                if text.startswith("Key,Type,Desc,English"):
                    for row in csv.DictReader(io.StringIO(text)):
                        if (row["Key"].startswith(LOC_PREFIXES) or "DEFEN" in row["Key"].upper()) and row["English"]:
                            localization[row["Key"]] = row["English"]
            elif obj.type.name == "MonoBehaviour":
                try:
                    tree = obj.read_typetree()
                except Exception:
                    continue
                trees[obj.path_id] = {k: v for k, v in tree.items() if k not in DROPPED}

    def ref(value):
        """A reference -> the id (or name) of what it points at, "" when it cannot be resolved."""
        target = trees.get(value["m_PathID"]) if value["m_PathID"] != 0 else None
        if target is None:
            return ""
        return target.get("_id") or target.get("m_Name") or ""

    def clean(tree: dict) -> dict:
        entry = {}
        for key, value in tree.items():
            if is_pptr(value):
                value = ref(value)
            elif isinstance(value, list) and value and all(is_pptr(v) for v in value):
                value = [ref(v) for v in value]
            entry[key] = value
        return entry

    result = {"materials": [], "recipes": [], "consumables": [], "armors": [], "trinkets": [], "enemy_loot": []}
    for tree in trees.values():
        identifier = str(tree.get("_id", ""))
        if identifier.startswith("MAT_"):
            result["materials"].append(clean(tree))
        elif identifier.startswith("RECIPE_"):
            entry = clean({k: v for k, v in tree.items() if k != "Ingredients"})
            entry["Ingredients"] = [
                {"material": ref(i["Material"]), "qty": int(i["Qty"])} for i in tree.get("Ingredients", [])
            ]
            result["recipes"].append(entry)
        elif identifier.startswith("CSM_"):
            result["consumables"].append(clean(tree))
        elif identifier.startswith("ARMOR_"):
            result["armors"].append(clean(tree))
        elif identifier.startswith("TRINKET") and identifier.endswith(("_ID", "_ID_PLUS")):
            result["trinkets"].append(clean(tree))
        elif identifier.startswith("ENEMY_") and "DefaultLoot" in tree:
            loot = []
            for entry in tree["DefaultLoot"]:
                target = trees.get(entry["m_PathID"]) if is_pptr(entry) else None
                loot.append(clean(target) if target is not None else {})
            result["enemy_loot"].append({"id": identifier, "name": tree.get("m_Name", ""), "loot": loot,
                                         "defensive_key": tree.get("DefensiveKey", ""), "show_defense_after_attack": bool(tree.get("ShowDefenseAfterAttack", 0))})

    for entries in result.values():
        if entries and "_id" in entries[0]:
            entries.sort(key=lambda e: str(e["_id"]))
    result["enemy_loot"].sort(key=lambda e: e["id"])
    os.makedirs(OUTPUT, exist_ok=True)
    with open(os.path.join(OUTPUT, "items.json"), "w", encoding="utf-8") as handle:
        json.dump(result, handle, indent=1, ensure_ascii=False)
    with open(os.path.join(OUTPUT, "localization_en.json"), "w", encoding="utf-8") as handle:
        json.dump(dict(sorted(localization.items())), handle, indent=1, ensure_ascii=False)
    print("materials %d, recipes %d, consumables %d, armors %d, trinkets %d, enemies with loot %d, texts %d -> %s" % (
        len(result["materials"]), len(result["recipes"]), len(result["consumables"]), len(result["armors"]),
        len(result["trinkets"]), len(result["enemy_loot"]), len(localization), OUTPUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
