"""Run: python tools/part_effects/gen_part_effects.py (needs the weapon-data export of tools/asset_import/import_weapon_data.py, which
it uses only to turn part NAMES into part ids). Writes data/weapon_part_effects.json: what the app computes for each weapon part (B / C) ability. Keyed by the
base part id; `up` is used for the upgraded ("+") side when it differs. Written from the ability texts - anything the
text doesn't make clear is NOT here (see claude.md "Weapon part abilities")."""
import json, os, re

D = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Descent-Engine\weapon_data")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "weapon_part_effects.json")
d = json.load(open(D + r"\weapons.json", encoding="utf-8"))
loc = json.load(open(D + r"\localization_en.json", encoding="utf-8"))
clean = lambda v: re.sub(r"[\ue000-\uf8ff]", "", v).strip()

CLASS = {"Hammer": 0, "Crossbow": 1, "Sword": 2, "WarHammer": 3, "Warbell": 4, "Spear": 5, "Wand": 6, "Staff": 7,
         "Gauntlet": 8, "Knives": 9, "Blades": 10, "Bow": 11, "Rune": 12}


# ---- effect builders
def conds(kinds, **kw): return dict(type="conditions", kinds=kinds, **kw)
def conds_all(kinds, **kw): return dict(type="conditions_all", kinds=kinds, **kw)
def conds_after(kinds, **kw): return dict(type="conditions_after", kinds=kinds, **kw)
def types(kinds): return dict(type="damage_types", kinds=kinds)
def dmg(**kw): return dict(type="damage", **kw)
def succ(n, **kw): return dict(type="successes", n=n, **kw)
def weak_bonus(n): return dict(type="weakness_bonus", n=n)
def defense_round(n): return dict(type="defense_round", n=n)
def become_weak(kinds): return dict(type="become_weak", kinds=kinds)
def perm(damage, defense): return dict(type="perm", damage=damage, defense=defense)
def direct(who, amount): return dict(type="direct", who=who, amount=amount)
def message(): return dict(type="message")
def drop_loot(n): return dict(type="drop_loot", n=n)
def loot_times(n): return dict(type="loot_times", n=n)

TAG = lambda t: {"tag": t}
ALREADY = lambda k: {"already": k}
WEAK = {"weak_to_attack": True}

# (class, slot, name): (base effects, upgraded effects or None = same, options)
SPEC = {
    ("Hammer", "B", "Forgik Haft"): ([drop_loot(1)], None, {}),
    ("Gauntlet", "B", "Shadow-Weave Gloves"): ([drop_loot(1)], None, {}),
    ("Staff", "C", "Goldbloom Lacing"): ([drop_loot(1)], None, {}),
    ("Hammer", "B", "Salvager Haft"): ([loot_times(2)], [loot_times(3)], {}),
    ("Hammer", "C", "Tinker's Grip"): ([message()], None, {}),
    ("Wand", "C", "Mothwing Ornament"): ([message()], None, {}),
    ("Knives", "C", "Duskstrike Belt"): ([message()], None, {}),
    ("Hammer", "B", "Kehlik Haft"): ([dict(type="copy_other")], None, {}),
    ("Hammer", "C", "Devastator's Grip"): ([weak_bonus(1)], [weak_bonus(2)], {}),
    ("Crossbow", "B", "Mammoth Stock"): ([dmg(flat=1), succ(1, to=TAG("Large"))], [dmg(flat=1), succ(2, to=TAG("Large"))], {}),
    ("Crossbow", "C", "Barbed Bolts"): ([conds(["AFFLICTED", "SLOWED"])], [conds(["AFFLICTED", "SLOWED"]), dmg(flat=1)], {}),
    ("Crossbow", "C", "Screamer Bolts"): ([conds(["ENFEEBLED", "EXPOSED"])], [types(["ANEMOS"]), conds(["ENFEEBLED", "EXPOSED"])], {}),
    ("Crossbow", "C", "Marking Bolts"): ([perm(1, 1)], [perm(2, 2)], {}),
    ("Crossbow", "C", "Splintering Bolts"): ([conds(["DAZED", "DOOMED"])], [conds(["DAZED", "DOOMED"]), defense_round(2)], {}),
    ("Sword", "B", "Northrider Guard"): ([dmg(flat=1, to={"ask": "injured"})], [dmg(flat=2, to={"ask": "injured"})], {}),
    ("Sword", "B", "Breaker Guard"): ([perm(1, 0)], None, {}),
    ("WarHammer", "B", "Dragonscale Haft"): ([conds_all(["DAZED"], tag="Dragon")], None, {}),
    ("WarHammer", "C", "Tenderizer Pommel"): ([become_weak(["PIERCE"])], None, {}),
    ("WarHammer", "C", "Talon Pommel"): ([become_weak(["SLASH"])], None, {}),
    ("WarHammer", "C", "Sahe Pommel"): ([become_weak(["CRUSH"])], None, {}),
    ("WarHammer", "C", "Crown Pommel"): ([dict(type="become_weak", kinds="attack_types")], None, {}),
    ("Warbell", "B", "Talon Grip"): ([conds(["DAZED"])], [succ(1, to=ALREADY("DAZED")), conds(["DAZED"])], {}),
    ("Warbell", "B", "Jeweled Grip"): ([dict(type="copy_other")], None, {}),
    ("Warbell", "B", "Spiked Grip"): ([dmg(per_status=1)], [dmg(per_status=1), dict(type="random_status", count=1, only_if_none=True)], {}),
    ("Warbell", "C", "Reinforced Haft"): ([dmg(flat=2)], [dmg(flat=3)], {}),
    ("Warbell", "C", "Ringing Haft"): ([direct("others", "successes")], None, {}),
    ("Spear", "B", "Twisting Haft"): ([dict(type="same_damage_other")], None, {}),
    ("Spear", "B", "Superior Haft"): ([conds(["ENFEEBLED"])], [conds(["SLOWED"], to=ALREADY("ENFEEBLED")), conds(["ENFEEBLED"])], {}),
    ("Spear", "C", "Radiant Tail"): ([become_weak(["PIERCE", "IGNOS"])], [become_weak(["PIERCE", "IGNOS"]), conds(["AFFLICTED"])], {}),
    ("Spear", "C", "Nightfall Tail"): ([conds(["DOOMED"])], [succ(1, to=ALREADY("DOOMED")), conds(["DOOMED"])], {}),
    ("Spear", "C", "Serpent's Tail"): ([weak_bonus(1)], [weak_bonus(2)], {}),
    ("Spear", "C", "Biting Tail"): ([dmg(flat=1)], [dmg(flat=2)], {"always_if_weak": True}),
    ("Wand", "B", "Nature Wrap"): ([conds(["ENFEEBLED", "SLOWED"])], None, {}),
    ("Wand", "B", "Nightsky Wrap"): ([dict(type="direct_ask", prompt="fatigue")], None, {}),
    ("Wand", "B", "Scholar's Wrap"): ([dict(type="reveal_weakness")], None, {}),
    ("Wand", "C", "Feather Ornament"): ([types(["IGNOS"]), conds(["AFFLICTED"])], [types(["IGNOS", "LUMOS"]), conds(["AFFLICTED"])], {}),
    ("Wand", "C", "Lacerate"): ([conds(["AFFLICTED"], to=WEAK)], None, {}),
    ("Wand", "C", "Eye Ornament"): ([dict(type="become_weak", kinds="random_attack_type")], None, {}),
    ("Wand", "C", "Volcanic Ornament"): ([dict(type="counter", every=5, damage_all=10)], [conds(["AFFLICTED"]), dict(type="counter", every=5, damage_all=15)], {}),
    ("Staff", "B", "Scarlet Wrap"): ([dict(type="same_damage_other", then=["AFFLICTED"])], None, {}),
    ("Staff", "B", "Rider's Wrap"): ([dmg(range=[1, 2])], [dmg(range=[1, 3])], {}),
    ("Staff", "B", "Flamescale Wrap"): ([dict(type="affliction_bonus", n=3)], [conds(["AFFLICTED"]), dict(type="affliction_bonus", n=3)], {}),
    ("Staff", "B", "Banded Wrap"): ([conds_all(["ENFEEBLED"])], None, {}),
    ("Staff", "C", "Blood Vein Lacing"): ([types(["PIERCE", "SLASH"]), conds(["EXPOSED"])], [types(["PIERCE", "SLASH"]), conds(["EXPOSED"]), succ(1)], {}),
    ("Staff", "C", "Stormwind Lacing"): ([types(["ANEMOS"])], [types(["ANEMOS", "UMBROS"])], {}),
    ("Staff", "C", "Ember Lacing"): ([types(["IGNOS"]), dict(type="max_health_to_current")], [types(["IGNOS"]), succ(2), dict(type="max_health_to_current")], {}),
    ("Gauntlet", "B", "Clawed Gloves"): ([types(["PIERCE"]), conds(["EXPOSED"])], None, {}),
    ("Gauntlet", "B", "Drakewing Gloves"): ([types(["IGNOS"])], None, {}),
    ("Gauntlet", "C", "Heavy Bracers"): ([types(["CRUSH"]), conds(["DAZED"])], None, {}),
    ("Gauntlet", "C", "Cruel Bracers"): ([dmg(per_status=1)], [dmg(per_status=1), dict(type="random_status", count=1, only_if_none=True)], {}),
    ("Gauntlet", "C", "Biting Bracers"): ([dmg(flat=3)], [dmg(flat=4)], {}),
    ("Gauntlet", "C", "Grasping Bracers"): ([types(["TOXOS"]), conds(["ENFEEBLED"])], None, {}),
    ("Knives", "B", "Balanced Grip"): ([succ(1, to=WEAK)], None, {}),
    ("Knives", "B", "Spiked Grip"): ([conds(["EXPOSED"], to=WEAK)], None, {}),
    ("Knives", "B", "Lacerate"): ([conds(["AFFLICTED"], to=WEAK)], None, {}),
    ("Knives", "B", "Livewood Grip"): ([conds(["ENFEEBLED", "SLOWED"])], None, {}),
    ("Knives", "B", "Fanged Grip"): ([conds(["EXPOSED"]), direct("exposed", 5)], [conds(["EXPOSED"]), direct("exposed", 8)], {}),
    ("Knives", "C", "Threewishes Sash"): ([dict(type="random_status", count=3)], None, {}),
    ("Blades", "B", "Hooked Offhand"): ([conds(["SLOWED"])], [conds(["SLOWED", "ENFEEBLED"])], {}),
    ("Blades", "B", "Forgotten Offhand"): ([dmg(double=True)], [dmg(double=True), succ(1)], {}),
    ("Blades", "B", "Star Metal Offhand"): ([dict(type="ignore_defense")], None, {}),
    ("Blades", "B", "Leonx Offhand"): ([dict(type="successes", per_stronger_enemy=1)], None, {}),
    ("Blades", "C", "Redstone Pommel"): ([dmg(flat=1, to=TAG("Uthuk"))], [dmg(flat=1, to=TAG("Uthuk")), conds(["DAZED"], to=TAG("Uthuk"))], {}),
    ("Blades", "C", "Bloodscript Pommel"): ([dict(type="damage", ask_injury=True)], None, {}),
    ("Blades", "C", "Braided Pommel"): ([conds(["DAZED"])], None, {}),
    ("Blades", "C", "Gilded Pommel"): ([conds(["CONFUSED"])], None, {}),
    ("Blades", "C", "Clawguard Pommel"): ([conds_after(["SLOWED"])], [conds_after(["DAZED", "SLOWED"])], {}),
    ("Bow", "B", "Silken String"): ([dict(type="execute_below", hp=7)], [dict(type="execute_below", hp=13)], {}),
    ("Bow", "B", "Wildborn String"): ([conds(["DAZED"]), dmg(flat=1)], [conds(["DAZED"]), dmg(flat=2)], {}),
    ("Bow", "B", "Full Moon String"): ([dict(type="strip_statuses", damage_per=3)], [dict(type="strip_statuses", damage_per=5)], {}),
    ("Bow", "B", "Thrumming String"): ([dict(type="spread_status", all=False)], [dict(type="spread_status", all=True)], {}),
    ("Bow", "C", "Marksman's Arrow"): ([conds(["EXPOSED"])], [succ(1, to=ALREADY("EXPOSED")), conds(["EXPOSED"])], {}),
    ("Bow", "C", "Direvine Arrow"): ([conds(["DAZED"])], None, {}),
    ("Bow", "C", "Omen-Touched"): ([conds(["DOOMED"])], [succ(1, to=ALREADY("DOOMED")), conds(["DOOMED"])], {}),
    ("Bow", "C", "Pinpoint Arrow"): ([defense_round(2)], [defense_round(4)], {}),
    ("Rune", "B", "Chosen Foe"): ([dmg(flat=1, to=TAG("Dragonkind")), succ(1, to=TAG("Dragonkind"))], None, {}),
    ("Rune", "B", "Enervation"): ([conds(["AFFLICTED", "ENFEEBLED"])], None, {}),
    ("Rune", "B", "Impede"): ([conds(["SLOWED"])], None, {}),
    ("Rune", "B", "Omen-Touched"): ([conds(["DOOMED"])], None, {}),
    ("Rune", "B", "Lacerate"): ([conds(["AFFLICTED"], to=WEAK)], None, {}),
    ("Rune", "C", "Overwhelm"): ([conds_all(["ENFEEBLED", "EXPOSED"], tag="Dragonkind")], None, {}),
    ("Rune", "C", "Whiteout"): ([conds_all(["ENFEEBLED"])], None, {}),
    ("Rune", "C", "Overcharge"): ([conds_all(["DAZED", "EXPOSED"])], None, {}),
    ("Rune", "C", "Spiral Strike"): ([dict(type="same_damage_other")], None, {}),
}

parts = d["parts"]
by_id = {p["_id"]: p for p in parts}
abil_by_id = {a["_id"]: a for a in d["abilities"]}
out = {}
missing = []
for (cls, slot, name), (base, up, opts) in SPEC.items():
    wanted = {"B": 1, "C": 2}[slot]
    hits = [p for p in parts if p["Class"] == CLASS[cls] and p["Slot"] == wanted and not p["IsUpgrade"]
            and name in (clean(loc.get(p["KeyName"], "")), clean(loc.get(abil_by_id.get(p["Ability"], {}).get("KeyName", ""), "")))]
    if len(hits) != 1:
        missing.append((cls, slot, name, len(hits)))
        continue
    entry = {"name": name, "effects": base}
    if up is not None:
        entry["upgraded_effects"] = up
    entry.update(opts)
    out[hits[0]["_id"]] = entry
if missing:
    print("UNRESOLVED:", missing)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
json.dump(out, open(OUT, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
print(len(out), "parts written;", len(SPEC), "in the table")
