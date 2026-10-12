"""Exports the game's monster data - per enemy its name, family, size, the three tiers (health / defense / base attack), its
activations (speed, damage, range...), weaknesses and resistance, defense ability and loot - from YOUR OWN copy of
"Descent: Legends of the Dark" to Godot's user:// data folder as plain JSON. Same rule as every other tool in this folder:
nothing here ships, redistributes or commits any game content; it only reads the Unity AssetBundles on your machine and
writes to %APPDATA%\\Godot\\app_userdata\\Descent-Engine\\monster_data\\monsters.json.

The Creator's monster template editor ("Import the game's monsters...") builds base templates from this file.

Requires: pip install UnityPy

Usage:
    python import_monster_data.py <path to game's bundles folder>
"""

import csv
import io
import json
import os
import re
import sys

from user_data import user_data_dir

OUTPUT = user_data_dir("monster_data")
DROPPED = {"m_GameObject", "m_Enabled", "m_Script"}


def is_pptr(value) -> bool:
    return isinstance(value, dict) and set(value.keys()) == {"m_FileID", "m_PathID"}


def plain(text: str) -> str:
    text = re.sub(r"<[^>]*>", "", text or "")
    return re.sub(r"\s+", " ", text).strip()


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

    trees = {}
    loc = {}
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
                        loc[row["Key"]] = row["English"]
            elif obj.type.name == "MonoBehaviour":
                try:
                    trees[obj.path_id] = obj.read_typetree()
                except Exception:
                    continue

    def follow(ref):
        return trees.get(ref["m_PathID"]) if is_pptr(ref) and ref["m_PathID"] != 0 else None

    def material(ref) -> str:
        target = follow(ref)
        return str(target.get("_id", "")) if target else ""

    def ability_key(activation_id: str) -> str:
        """The text key of an activation's ability: the activation id itself, or without its trailing _N."""
        for candidate in (activation_id, re.sub(r"_\d+$", "", activation_id)):
            if candidate in loc:
                return candidate
        return ""

    def tactic_record(tactic_id: str, numbers: dict) -> dict:
        """A manual activation (a "tactic"): its numbers and the keys of its texts, found by the usual name patterns."""
        candidates = [tactic_id + "_ACTIVATION"]
        name = tactic_id
        if "_TACTIC_" in tactic_id:
            family, name = tactic_id.split("_TACTIC_", 1)
            candidates.append("ENEMY_ACTIVATION_%s_%s" % (family, name))
        if tactic_id.startswith("ENEMY_TACTIC_"):
            name = tactic_id[len("ENEMY_TACTIC_"):]
            candidates.append("ENEMY_ACTIVATION_" + name)
        if tactic_id.startswith("ENEMY_ACTIVATION_"):
            name = tactic_id[len("ENEMY_ACTIVATION_"):]
            candidates.append(tactic_id)
        activation_key = next((c for c in candidates if c in loc), "")

        def first(options):
            return next((o for o in options if o in loc), "")
        return {
            "id": tactic_id, "name": name.replace("_", " ").title(),
            "speed": numbers.get("Speed"), "damage": numbers.get("Damage"), "range": numbers.get("Range"), "range_type": numbers.get("RangeType"),
            "hint_key": first([tactic_id + "_HINT"]), "activation_key": activation_key,
            "pass_key": first([activation_key + "_PASS", tactic_id + "_TEST_PASS"]) if activation_key else first([tactic_id + "_TEST_PASS"]),
            "fail_key": first([activation_key + "_FAIL", tactic_id + "_TEST_FAIL"]) if activation_key else first([tactic_id + "_TEST_FAIL"]),
            "reaction_key": first([tactic_id + "_PREEMPTIVE_DEFENSE"]),
            "time_passes_key": first(["TACTIC_PHASE_DESCRIPTION_" + name.replace("TACTIC_", "")]),
        }

    enemies = []
    for tree in trees.values():
        identifier = str(tree.get("_id", ""))
        if not identifier.startswith("ENEMY_") or "Tiers" not in tree:
            continue
        activations = []
        for ref in tree.get("Activations", []):
            a = follow(ref)
            if a is None:
                continue
            activations.append({
                "id": a.get("_id"), "speed": a.get("Speed"), "damage": a.get("Damage"), "attack": a.get("Attack"),
                "range": a.get("Range"), "range_type": a.get("RangeType"), "healing": a.get("Healing"), "shield": a.get("Shield"),
                "ability_key": ability_key(str(a.get("_id", ""))),
            })
        tactics = []
        for ref in tree.get("ManualActivations", []):
            m = follow(ref)
            if m is not None and m.get("_id"):
                tactics.append(tactic_record(str(m["_id"]), m))
        loot = []
        for ref in tree.get("DefaultLoot", []):
            table = follow(ref)
            if table is None:
                continue
            common = [material(table.get(k)) for k in ("CommonMat1", "CommonMat2") if material(table.get(k))]
            essences = [material(table.get(k)) for k in ("UncommonMat1", "UncommonMat2") if material(table.get(k))]
            loot.append({"name": plain(loc.get(str(table.get("KeyName", "")), "")), "common": common, "essences": essences})
        weak, resist = [], []
        for entry in tree.get("WeaknessesAndResistances", []):
            if entry["TraitType"] == 1 and entry["TraitIs"] == 0:
                weak.append(entry["TraitValue"])
            elif entry["TraitType"] == -1 and entry["TraitIs"] == 2:
                resist.append(entry["TraitValue"])
        enemies.append({
            "id": identifier, "name": plain(loc.get(str(tree.get("KeyNameSingular", "")), "")),
            "type": tree.get("Type"), "size": tree.get("Size"), "named": bool(tree.get("IsNamed")), "villain": bool(tree.get("IsVillain")),
            "tiers": [{"tier": t["Tier"], "hp": t["StartingHealth"], "defense": t["Defense"], "attack": t["BaseAttack"]} for t in tree.get("Tiers", [])],
            "activations": activations, "tactics": tactics, "weaknesses": weak, "resistances": resist, "immune_mask": tree.get("ImmuneTo"),
            "defensive_key": tree.get("DefensiveKey", ""), "loot": loot,
        })
    enemies.sort(key=lambda e: e["id"])
    os.makedirs(OUTPUT, exist_ok=True)
    with open(os.path.join(OUTPUT, "monsters.json"), "w", encoding="utf-8") as handle:
        json.dump({"enemies": enemies}, handle, indent=1, ensure_ascii=False)
    print("%d enemies -> %s" % (len(enemies), OUTPUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
