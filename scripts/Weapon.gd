class_name Weapon
extends Resource

## A weapon a hero attacks with: a base damage per success, one or more
## damage types (same Vulnerability.Kind list monsters use for weaknesses/
## resistances/immunities), a range and a reach flag. See
## MissionRuntime.resolve_attack() for how damage and types combine. Weapons
## come from WeaponCatalog and are picked per hero at embark (EmbarkDialog).
## Range and reach are data only - nothing reads them yet (the engine doesn't
## track positions).

@export var weapon_name: String = "Weapon"
@export_range(0, 999) var damage: int = 3
@export var damage_types: Array[int] = []  ## Vulnerability.Kind values
## How far the weapon can attack; 0 = adjacent/melee. (Named weapon_range
## because `range` is a GDScript built-in.)
@export_range(0, 99) var weapon_range: int = 0
## True for weapons with reach (attack past an adjacent square).
@export var reach: bool = false


## One-line description for pickers, e.g. "Spear (damage 3, Pierce, reach)".
func summary() -> String:
	var parts: Array[String] = ["damage %d" % damage]
	for kind in damage_types:
		parts.append(Vulnerability.display_name(kind))
	if weapon_range > 0:
		parts.append("range %d" % weapon_range)
	if reach:
		parts.append("reach")
	return "%s (%s)" % [weapon_name, ", ".join(parts)]


## Fallback when a hero has no weapon picked: damage 3, slashing.
static func placeholder() -> Weapon:
	return WeaponCatalog.make("Sword", 3, [WeaponCatalog.SLASH])
