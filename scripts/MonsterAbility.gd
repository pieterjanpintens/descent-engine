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
## A defense ability of the game (ItemData.defense_abilities(), e.g. "ENEMY_DEFEND_GOLEM"): its text comes from the user's
## own export of the game data and is shown to the table when the monster is attacked. Empty = only the name.
@export var game_key: String = ""


## The text shown to the table: the game's text for `game_key` (when the export has it), else the name.
func shown_text() -> String:
	var info := ItemData.defense_ability(game_key) if game_key != "" else {}
	return str(info["text"]) if not info.is_empty() else ability_name


## True when the game shows this ability's text after the attack roll instead of while attacking.
func shows_after_attack() -> bool:
	var info := ItemData.defense_ability(game_key) if game_key != "" else {}
	return not info.is_empty() and bool(info["after"])


static func behavior_name(behavior: int) -> String:
	match behavior:
		Behavior.NONE:
			return "Flavour only"
		Behavior.ATTACK_AGAIN_ON_DAMAGE:
			return "Attacks again after dealing damage"
	return ""


## Plain-data form for SaveGame (RuntimeMonster.to_dict()).
func to_dict() -> Dictionary:
	return {"name": ability_name, "behavior": behavior, "game_key": game_key}


static func from_dict(d: Dictionary) -> MonsterAbility:
	var ability := MonsterAbility.new()
	ability.ability_name = str(d.get("name", ""))
	ability.behavior = int(d.get("behavior", Behavior.NONE)) as Behavior
	ability.game_key = str(d.get("game_key", ""))
	return ability


## Independent copies of `list` - a spawned monster must not share (and later
## mutate) the design-time template's resources.
static func copies(list: Array[MonsterAbility]) -> Array[MonsterAbility]:
	var result: Array[MonsterAbility] = []
	for ability in list:
		result.append(from_dict(ability.to_dict()))
	return result
