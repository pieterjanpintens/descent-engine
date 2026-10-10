class_name WeaponAttachment
extends Resource

## A weapon part B or C a hero equips on a weapon at embark (EmbarkDialog.ask_loadouts()) - the game's real parts, read
## by WeaponData from the user's own export; a weapon has at most MAX_PER_WEAPON of them (one B, one C). Each attack
## the part rolls its `chance` to trigger and PartEffectRunner applies what it can (the ability's effects are written
## in data/weapon_part_effects.json); whatever the app can't do is shown to the table as the ability's text.

const MAX_PER_WEAPON := 2

@export var attachment_name: String = ""
@export var weapon_type: String = ""
## "B" (guard / haft) or "C" (hilt / pommel) - a weapon has one slot of each.
@export var part_slot: String = ""
## The game's id of the part ("WEAPON_PART_B_SWORD_1") - what campaign offers and the owned list refer to.
@export var part_id: String = ""
## The game's path of the part's icon picture, see Weapon.icon_path.
@export var icon_path: String = ""
@export var ability_name: String = ""
@export_multiline var ability_text: String = ""
## The chance (0..1) that the ability triggers on an attack - the game's own `Chance` of the ability.
@export var chance: float = 0.0


func _init(p_name: String = "", p_weapon_type: String = "") -> void:
	attachment_name = p_name
	weapon_type = p_weapon_type


## "Northrider Guard - Equity".
func summary() -> String:
	return "%s - %s" % [attachment_name, ability_name] if ability_name != "" else attachment_name


## summary() plus what the ability does.
func detail() -> String:
	return "%s: %s" % [summary(), ability_text] if ability_text != "" else summary()
