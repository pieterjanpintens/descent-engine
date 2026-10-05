class_name MonsterAbility
extends Resource

## One custom ability of a monster - used for BOTH its attack abilities and its
## defense abilities (`MonsterTemplate`/`RuntimeMonster.attack_abilities` and
## `defense_abilities`): same underlying structure on purpose, the list a
## MonsterAbility sits in says which kind it is.
##
## Placeholder for now: only a name. Nothing reads these yet - the actual
## effects (what the ability does when the monster attacks / is attacked) are
## not designed; more fields (description, trigger, effects, ...) will follow.

@export var ability_name: String = ""


## Plain-data form for SaveGame (RuntimeMonster.to_dict()).
func to_dict() -> Dictionary:
	return {"name": ability_name}


static func from_dict(d: Dictionary) -> MonsterAbility:
	var ability := MonsterAbility.new()
	ability.ability_name = str(d.get("name", ""))
	return ability


## Independent copies of `list` - a spawned monster must not share (and later
## mutate) the design-time template's resources.
static func copies(list: Array[MonsterAbility]) -> Array[MonsterAbility]:
	var result: Array[MonsterAbility] = []
	for ability in list:
		result.append(from_dict(ability.to_dict()))
	return result
