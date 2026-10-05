class_name MonsterAbility
extends Resource

## One custom ability of a monster - used for BOTH its attack abilities and its
## defense abilities (`MonsterArchetype`/`RuntimeMonster.attack_abilities` and
## `defense_abilities`): same underlying structure on purpose, the list a
## MonsterAbility sits in says which kind it is.
##
## A name plus an optional `behavior` the engine actually acts on. Behaviors build
## on the FEEDBACK the table reports after a monster's attack (see
## MissionPlayer._monster_attack()); only attack abilities use them so far, and
## only one exists - more will follow.

enum Behavior {
	NONE,                  ## flavour only - shown to the table, nothing happens
	ATTACK_AGAIN_ON_DAMAGE, ## after an attack that dealt damage, the monster attacks again
}

@export var ability_name: String = ""
@export var behavior: Behavior = Behavior.NONE


static func behavior_name(behavior: int) -> String:
	match behavior:
		Behavior.NONE:
			return "Flavour only"
		Behavior.ATTACK_AGAIN_ON_DAMAGE:
			return "Attacks again after dealing damage"
	return ""


## Plain-data form for SaveGame (RuntimeMonster.to_dict()).
func to_dict() -> Dictionary:
	return {"name": ability_name, "behavior": behavior}


static func from_dict(d: Dictionary) -> MonsterAbility:
	var ability := MonsterAbility.new()
	ability.ability_name = str(d.get("name", ""))
	ability.behavior = int(d.get("behavior", Behavior.NONE)) as Behavior
	return ability


## Independent copies of `list` - a spawned monster must not share (and later
## mutate) the design-time template's resources.
static func copies(list: Array[MonsterAbility]) -> Array[MonsterAbility]:
	var result: Array[MonsterAbility] = []
	for ability in list:
		result.append(from_dict(ability.to_dict()))
	return result
