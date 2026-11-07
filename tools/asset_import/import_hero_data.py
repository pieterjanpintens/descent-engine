"""Exports the game's hero data - the six heroes, their skills, legends and feats (with the rewards) and their texts -
from YOUR OWN copy of "Descent: Legends of the Dark" to Godot's user:// data folder, as plain JSON.

Same rule as every other tool in this folder: nothing here ships, redistributes or commits any game content - it only
reads the Unity AssetBundles on your own machine and writes to
%APPDATA%\\Godot\\app_userdata\\Descent-Engine\\hero_data\\ (see user_data.py for macOS / Linux).

Writes:
    heroes.json     {"heroes": [...], "skills": [...], "legends": [...], "feats": [...], "companions": [...]}
                    every field of the game's own data objects, minus pictures/colour noise nothing needs; references
                    to other objects (a hero's starting weapons and feat, a feat's rewards, prerequisite feats and
                    hero) are replaced by the referenced object's `_id` ("" when it cannot be resolved).
    localization_<code>.json   the texts of those objects in every language the game has: hero names and virtues
                    (HERO_/VIRTUE_), skill and legend card names (SKILL_/LEGEND_, "Side A / Side B" for a skill),
                    feat descriptions (FEAT_*_DESC), companions and the glossary / UI texts about experience, skills,
                    legends and feats (TERM_EXPERIENCE*, TERM_FEAT*, UI_FEAT*, ...).

What the data holds (and does not):
    * skills   66 = 11 per hero. `Hero` = hero index (0 Brynn, 1 Chance, 2 Galaden, 3 Kehli, 4 Syrus, 5 Vaerix),
               `XPCost` 1-3, `_act` 0/1. The rule text of a skill is NOT in any text table (only its name) - it is on
               the card picture.
    * legends  36 = 3 per hero, two sides each (`FlipId`), `XPCost`.
    * feats    120 = 20 per hero. `Goal` = how many times the condition must happen, `Timing` = when it is checked
               (raw numbers; seen: 1 on an attack, 2 enemy activation, 3 hero wounded, 4 on a defeat, 5 on an
               interaction, 6 recipe/material gain, 7 end of round, 8 end of quest, 9 / 10 other), the many
               `{"Enable": 0/1, "Value": ...}` fields are filters (weapon class, enemy type, prop type, damage...) that
               only count when Enable is 1. `AmountCompletedRequired` = how many feats the hero must already have
               completed before it can be offered (0, 4, 8, 12, 14), `PrerequisiteFeats` = feats that must be done
               first, `Rewards` = skill or recipe ids (5 skills + 15 recipes per hero).
    * XP       is not a spendable currency in the game: a hero's XP is the maximum total `XPCost` of the cards they may
               equip for a quest (see TERM_EXPERIENCE_DESC_*).

Requires: pip install UnityPy

Usage:
    python import_hero_data.py <path to game's bundles folder>
"""

import csv
import io
import json
import os
import re
import sys

from user_data import LANGUAGE_CODES, user_data_dir

OUTPUT = user_data_dir("hero_data")

DROPPED_FIELDS = {"m_GameObject", "m_Enabled", "m_Script"}

# English-and-other-language text keys worth keeping (prefix match).
TEXT_PREFIXES = ("HERO_", "SKILL_", "LEGEND_", "FEAT_", "VIRTUE_", "COMPANION_", "CARD_SKILL", "UI_FEAT", "UI_NO_NEW_FEAT",
                 "UI_SELECT_NEWFEAT", "TUTORIAL_FEATS", "TERM_EXPERIENCE", "TERM_FEAT", "TERM_SKILL", "TERM_LEGEND",
                 "TERM_COMPANION", "TERM_HERO")


def kind_of(identifier: str, tree: dict) -> str:
    if re.fullmatch(r"HERO_[A-Z]+", identifier) and "VirtueOneKey" in tree:
        return "heroes"
    if re.fullmatch(r"SKILL_[A-Z]+_\d+", identifier):
        return "skills"
    if re.fullmatch(r"LEGEND_[A-Z]+_\d+[AB]", identifier):
        return "legends"
    if re.fullmatch(r"FEAT_[A-Z]+_\d+", identifier):
        return "feats"
    if identifier.startswith("COMPANION_") and "Hero" in tree:
        return "companions"
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

    names = {}  # path id -> _id (or m_Name) of every data object, so references can be resolved across bundles
    found = []  # (kind, tree)
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
            kind = obj.type.name
            if kind == "TextAsset":
                data = obj.read()
                text = data.m_Script if isinstance(data.m_Script, str) else bytes(data.m_Script).decode("utf-8", "ignore")
                if text.startswith("Key,Type,Desc,"):
                    rows = csv.DictReader(io.StringIO(text))
                    column = (rows.fieldnames or ["", "", "", ""])[3]
                    code = LANGUAGE_CODES.get(column)
                    if code is None:
                        continue
                    target = localization.setdefault(code, {})
                    for row in rows:
                        if row["Key"].startswith(TEXT_PREFIXES) and row[column]:
                            target[row["Key"]] = row[column]
            elif kind == "MonoBehaviour":
                try:
                    tree = obj.read_typetree()
                except Exception:
                    continue
                identifier = str(tree.get("_id", "") or "")
                names[obj.path_id] = identifier or str(tree.get("m_Name", "") or "")
                what = kind_of(identifier, tree)
                if what:
                    found.append((what, identifier, tree))

    def ref(value):
        return names.get(value["m_PathID"], "") if value["m_PathID"] != 0 else ""

    result = {"heroes": [], "skills": [], "legends": [], "feats": [], "companions": []}
    seen = set()
    for what, identifier, tree in found:
        if identifier in seen:
            continue
        seen.add(identifier)
        entry = {}
        for key, value in tree.items():
            if key in DROPPED_FIELDS:
                continue
            if is_pptr(value):
                value = ref(value)
            elif isinstance(value, list) and value and all(is_pptr(v) for v in value):
                value = [ref(v) for v in value]
            entry[key] = value
        result[what].append(entry)
    for entries in result.values():
        entries.sort(key=lambda e: str(e.get("_id", "")))

    os.makedirs(OUTPUT, exist_ok=True)
    with open(os.path.join(OUTPUT, "heroes.json"), "w", encoding="utf-8") as handle:
        json.dump(result, handle, indent=1, ensure_ascii=False)
    for code, texts in localization.items():
        with open(os.path.join(OUTPUT, "localization_%s.json" % code), "w", encoding="utf-8") as handle:
            json.dump(dict(sorted(texts.items())), handle, indent=1, ensure_ascii=False)
    unresolved = sum(1 for f in result["feats"] for r in f.get("Rewards", []) if not r)
    print("heroes %d, skills %d, legends %d, feats %d, companions %d, texts %d (%d languages), unresolved feat rewards %d -> %s" % (
        len(result["heroes"]), len(result["skills"]), len(result["legends"]), len(result["feats"]), len(result["companions"]),
        len(localization.get("en", {})), len(localization), unresolved, OUTPUT))
    return 0 if result["heroes"] and result["skills"] and result["feats"] else 1


if __name__ == "__main__":
    sys.exit(main())
