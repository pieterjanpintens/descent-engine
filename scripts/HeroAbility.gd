class_name HeroAbility
extends Resource

## An ability a hero can equip once their level allows it (HeroState.equip()). Like the rest
## of the game it is resolved by the table - the app tells which abilities are equipped and
## their text; hooks into the rules can come later. The premade list is AbilityCatalog.

@export var id: String = ""
@export var ability_name: String = ""
@export_multiline var description: String = ""
## HeroCatalog slot this ability belongs to, -1 = any hero.
@export var hero_slot: int = -1
## The hero level from which it can be equipped.
@export var required_level: int = 1


func _init(p_id: String = "", p_name: String = "", p_description: String = "", p_required_level: int = 1, p_hero_slot: int = -1) -> void:
	id = p_id
	ability_name = p_name
	description = p_description
	required_level = p_required_level
	hero_slot = p_hero_slot


## Can hero `slot` at `level` use it?
func fits(slot: int, level: int) -> bool:
	return (hero_slot < 0 or hero_slot == slot) and level >= required_level
