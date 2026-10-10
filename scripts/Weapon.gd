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
## Premade secondary abilities equipped at embark (at most WeaponAttachment.MAX_PER_WEAPON,
## none by default) - each may trigger when attacking with this weapon.
@export var attachments: Array[WeaponAttachment] = []
## The weapon's own secondary ability from the game's real data (WeaponData): its name and rule text. Information
## for the table only - nothing in the engine applies it. Empty for the placeholder weapons.
@export var ability_name: String = ""
@export_multiline var ability_text: String = ""
## The game's id of the A part ("WEAPON_PART_A_ICE_STORM") for the real weapons, "" for placeholders.
@export var part_id: String = ""
## part_id of the base side of the card: the same as part_id, or the base version's id for an upgraded ("+") weapon.
@export var base_part_id: String = ""
## A rune (WeaponData.runes()): belongs to no hero, any hero can take it as Weapon 1 or Weapon 2 in place of their
## own weapon; its B and C parts are fixed (already in `attachments`).
@export var is_rune: bool = false


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
