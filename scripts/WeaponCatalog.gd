class_name WeaponCatalog
extends RefCounted

## Never instantiated - the list of weapons heroes can pick at embark
## (EmbarkDialog.ask_loadouts()), same shared-namespace pattern as
## HeroCatalog/MonsterChip. These are generic, invented placeholders (the
## real weapon list isn't known yet - add/replace entries freely), the first
## being the original placeholder "Sword" (damage 3, slash).


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


## Real per-hero weapon NAMES (2026-09-27, given directly), index-aligned
## with HeroCatalog.HERO_NAMES - each hero's two real weapons, in order
## (index 0 = Weapon 1/acti, index 1 = Weapon 2/actii, matching
## HeroCatalog.slot_crop()/flat_mesh_paths()'s own weapon_index convention -
## these are also the actual pair the game's own two real meshes/croptops
## are for). Damage/type/range are STILL invented placeholders (no real
## stat data exists yet) - only the NAMES are real.
const HERO_WEAPONS: Array = [
	["Gloves", "Throwing Knives"],       # Chance
	["Swords", "Bow"],                   # Galaden
	["Warhammer", "Sword"],              # Brynn
	["War Bell", "Staff"],               # Vaerix
	["Hammer", "Crossbow"],              # Kehli
	["Staff", "Wand"],                   # Syrus
]


## The weapons hero `slot` may pick from at embark - their own real pair
## (see HERO_WEAPONS above), not the generic catalog. A hero always picks
## TWO: the first pick is "Weapon 1", the second "Weapon 2" - that position
## (not which weapon it is) decides the combat croptop/mesh shown, see
## HeroCatalog.slot_crop()/flat_mesh_paths().
static func for_hero(slot: int) -> Array[Weapon]:
	var weapons: Array[Weapon] = []
	for weapon_name: String in HERO_WEAPONS[slot]:
		weapons.append(make(weapon_name, _placeholder_damage(weapon_name), _placeholder_types(weapon_name), _placeholder_range(weapon_name)))
	return weapons


## Crude, invented type/damage/range guesses from the weapon's own name -
## blunt/bladed/ranged/magic, nothing more - replace with real stats
## whenever they're known.
static func _placeholder_types(weapon_name: String) -> Array[int]:
	var name := weapon_name.to_lower()
	if name.contains("wand"):
		return [LUMOS]
	if name.contains("sword"):
		return [SLASH]
	if name.contains("bow") or name.contains("crossbow") or name.contains("knives") or name.contains("knife"):
		return [PIERCE]
	return [CRUSH]  # hammer, warhammer, bell, staff, gloves


static func _placeholder_damage(weapon_name: String) -> int:
	var name := weapon_name.to_lower()
	if name.contains("warhammer"):
		return 4
	if name.contains("gloves") or name.contains("staff") or name.contains("knives") or name.contains("wand"):
		return 2
	return 3


static func _placeholder_range(weapon_name: String) -> int:
	var name := weapon_name.to_lower()
	if name.contains("bow") or name.contains("crossbow"):
		return 5
	if name.contains("knives") or name.contains("wand"):
		return 3
	return 0


## Fresh Weapon instances each call, in picker order.
static func all() -> Array[Weapon]:
	var weapons: Array[Weapon] = [
		make("Sword", 3, [SLASH]),
		make("Dagger", 2, [PIERCE]),
		make("Mace", 3, [CRUSH]),
		make("Warhammer", 4, [CRUSH]),
		make("Spear", 3, [PIERCE], 0, true),
		make("Bow", 3, [PIERCE], 5),
		make("Sword of Light", 3, [SLASH, LUMOS]),
		make("Flame Staff", 2, [IGNOS], 4),
	]
	return weapons
