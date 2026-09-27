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


## The weapons hero `slot` may pick from at embark. Today everyone gets the
## whole catalog; this is the seam for a predefined, per-hero set later. A
## hero always picks TWO: the first pick is "Weapon 1", the second "Weapon 2" -
## that position (not which weapon it is) decides the combat croptop shown, see
## HeroCatalog.slot_crop().
static func for_hero(_slot: int) -> Array[Weapon]:
	return all()


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
