class_name WeaponCatalog
extends RefCounted

## Never instantiated - the weapon data heroes pick from at embark
## (EmbarkDialog.ask_loadouts()), same shared-namespace pattern as
## HeroCatalog/MonsterChip.


const SLASH: int = Vulnerability.Kind.SLASH
const PIERCE: int = Vulnerability.Kind.PIERCE
const CRUSH: int = Vulnerability.Kind.CRUSH
const LUMOS: int = Vulnerability.Kind.LUMOS
const IGNOS: int = Vulnerability.Kind.IGNOS


static func make(weapon_name: String, damage: int, types: Array[int], weapon_range: int = 0, reach: bool = false) -> Weapon:
	var weapon := Weapon.new()
	weapon.weapon_name = weapon_name
	weapon.damage = damage
	weapon.damage_types = types
	weapon.weapon_range = weapon_range
	weapon.reach = reach
	return weapon


## Real per-hero weapon TYPES (2026-09-27, given directly), index-aligned
## with HeroCatalog.HERO_NAMES - each hero's two weapon slots are FIXED to
## one type each, in order (index 0 = Weapon 1/acti, index 1 = Weapon 2/
## actii, matching HeroCatalog.slot_crop()/flat_mesh_paths()'s own
## weapon_index convention - these are the same two acts the real
## meshes/croptops are for). The TYPE is what's fixed per slot/hero - which
## SPECIFIC named weapon fills it is a free pick from every item of that
## type (see WEAPONS_BY_TYPE below) - "all swords fall under the sword
## dropdown" was the exact request, so a type is shared globally across
## every hero who has a slot of it (Galaden and Brynn both have a "Sword"
## slot, and both pick from the SAME pool, not separate per-hero lists).
const HERO_WEAPON_TYPES: Array = [
	["Gloves", "Throwing Knives"],       # Chance
	["Bow", "Sword"],                    # Galaden - swapped 2026-09-28, acti/actii mismatch confirmed visually
	["Sword", "Warhammer"],              # Brynn - swapped 2026-09-28, acti/actii mismatch confirmed visually
	["Staff", "War Bell"],               # Vaerix - swapped 2026-09-28, acti/actii mismatch confirmed visually
	["Hammer", "Crossbow"],              # Kehli
	["Staff", "Wand"],                   # Syrus
]


## The named weapons available under each type - INVENTED for testing (no
## real per-item list exists yet, only the TYPE names were given directly).
## Add/replace/rename items freely; each type needs at least one entry.
const WEAPONS_BY_TYPE: Dictionary = {
	"Gloves": ["Iron Knuckles", "Spiked Gauntlets", "Shadow Fists"],
	"Throwing Knives": ["Rusty Knives", "Silver Darts", "Assassin's Edge"],
	"Sword": ["Iron Longsword", "Silverblade", "Kingsbane"],
	"Bow": ["Hunter's Bow", "Longshot Bow", "Windwhisper Bow"],
	"Warhammer": ["Stonebreaker", "Skullcrusher", "Dawnhammer"],
	"War Bell": ["Bronze War Bell", "Chiming Doom", "Resonant Toll"],
	"Staff": ["Oaken Staff", "Emberwood Staff", "Moonlit Staff"],
	"Hammer": ["Iron Mallet", "Miner's Hammer", "Thunderhead"],
	"Crossbow": ["True Aim Crossbow", "Rapid Bolt Crossbow", "Deadfall Crossbow"],
	"Wand": ["Spark Wand", "Frostbite Wand", "Whispering Wand"],
}


## The fixed weapon TYPE for hero `slot`'s weapon slot `weapon_index` (0 or 1).
static func type_of(slot: int, weapon_index: int) -> String:
	return HERO_WEAPON_TYPES[slot][weapon_index]


## Every named weapon belonging to `type_name` - fresh Weapon instances each
## call, in WEAPONS_BY_TYPE's own order. Falls back to a single weapon named
## after the type itself if the type has no entry there (keeps this
## resilient to a HERO_WEAPON_TYPES entry with no matching catalog yet).
static func weapons_of_type(type_name: String) -> Array[Weapon]:
	var names: Array = WEAPONS_BY_TYPE.get(type_name, [type_name])
	var weapons: Array[Weapon] = []
	for weapon_name: String in names:
		weapons.append(make(weapon_name, _placeholder_damage(type_name), _placeholder_types(type_name), _placeholder_range(type_name)))
	return weapons


## Crude, invented type/damage/range guesses from the weapon TYPE's own
## name - blunt/bladed/ranged/magic, nothing more - replace with real stats
## whenever they're known.
static func _placeholder_types(type_name: String) -> Array[int]:
	var name := type_name.to_lower()
	if name.contains("wand"):
		return [LUMOS]
	if name.contains("sword"):
		return [SLASH]
	if name.contains("bow") or name.contains("crossbow") or name.contains("knives") or name.contains("knife"):
		return [PIERCE]
	return [CRUSH]  # hammer, warhammer, bell, staff, gloves


static func _placeholder_damage(type_name: String) -> int:
	var name := type_name.to_lower()
	if name.contains("warhammer"):
		return 4
	if name.contains("gloves") or name.contains("staff") or name.contains("knives") or name.contains("wand"):
		return 2
	return 3


static func _placeholder_range(type_name: String) -> int:
	var name := type_name.to_lower()
	if name.contains("bow") or name.contains("crossbow"):
		return 5
	if name.contains("knives") or name.contains("wand"):
		return 3
	return 0


## Fresh Weapon instances each call, in picker order. No longer used by
## EmbarkDialog (each hero's two slots are now type-constrained, see
## type_of()/weapons_of_type() above) - kept as a flat "everything" list for
## anything that still wants one (e.g. Weapon.placeholder()'s own fallback
## construction doesn't use this, but a future generic picker might).
static func all() -> Array[Weapon]:
	var weapons: Array[Weapon] = []
	for type_name: String in WEAPONS_BY_TYPE:
		weapons.append_array(weapons_of_type(type_name))
	return weapons
