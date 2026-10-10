class_name MonsterTactic
extends Resource

## A TACTIC of a monster (the game's "manual activation"): at the end of a monster phase the app prepares one on a random
## monster and tells the table a hint; in the NEXT monster phase that monster does the tactic instead of its normal
## activation. A BASE template (MonsterArchetype.tactics) holds the list.
##
## Texts: the game's own (keys into the user's export - nothing ships) or the designer's own, which win when filled in.

@export var tactic_name: String = ""
@export var speed: int = 3
## Added to the monster's attack damage at its current level (the tactic's Damage minus the normal activation's).
@export var damage_offset: int = 0
@export var attack_range: int = 0
@export_multiline var own_hint: String = ""
@export_multiline var own_activation: String = ""
## The game's text keys (set by "Import the game's monsters"); empty = none.
@export var hint_key: String = ""
@export var activation_key: String = ""
@export var pass_key: String = ""  ## shown when the hero passes the test the activation asks for
@export var fail_key: String = ""
@export var reaction_key: String = ""  ## what the prepared tactic does in response to a hero's attack
@export var time_passes_key: String = ""  ## replaces the "Time passes" text while it is prepared


func hint_text(monster_name: String, hero_name: String) -> String:
	return _text(own_hint, hint_key, monster_name, hero_name)


func activation_text(monster_name: String, hero_name: String) -> String:
	return _text(own_activation, activation_key, monster_name, hero_name)


func pass_text(monster_name: String, hero_name: String) -> String:
	return _text("", pass_key, monster_name, hero_name)


func fail_text(monster_name: String, hero_name: String) -> String:
	return _text("", fail_key, monster_name, hero_name)


func reaction_text(monster_name: String, hero_name: String) -> String:
	return _text("", reaction_key, monster_name, hero_name)


func time_passes_text() -> String:
	return ItemData.text(time_passes_key) if time_passes_key != "" else ""


## True if the activation asks for a test with a pass and a fail result.
func has_test() -> bool:
	return pass_key != "" or fail_key != ""


func _text(own: String, key: String, monster_name: String, hero_name: String) -> String:
	if own.strip_edges() != "":
		return own.replace("{name}", monster_name).replace("{hero}", hero_name)
	if key == "":
		return ""
	return ItemData.fill_tactic(ItemData.text(key), monster_name, hero_name)


func to_dict() -> Dictionary:
	return {"name": tactic_name, "speed": speed, "damage_offset": damage_offset, "range": attack_range, "own_hint": own_hint,
		"own_activation": own_activation, "hint_key": hint_key, "activation_key": activation_key, "pass_key": pass_key,
		"fail_key": fail_key, "reaction_key": reaction_key, "time_passes_key": time_passes_key}


static func from_dict(d: Dictionary) -> MonsterTactic:
	var tactic := MonsterTactic.new()
	tactic.tactic_name = str(d.get("name", ""))
	tactic.speed = int(d.get("speed", 3))
	tactic.damage_offset = int(d.get("damage_offset", 0))
	tactic.attack_range = int(d.get("range", 0))
	tactic.own_hint = str(d.get("own_hint", ""))
	tactic.own_activation = str(d.get("own_activation", ""))
	tactic.hint_key = str(d.get("hint_key", ""))
	tactic.activation_key = str(d.get("activation_key", ""))
	tactic.pass_key = str(d.get("pass_key", ""))
	tactic.fail_key = str(d.get("fail_key", ""))
	tactic.reaction_key = str(d.get("reaction_key", ""))
	tactic.time_passes_key = str(d.get("time_passes_key", ""))
	return tactic


static func copies(list: Array[MonsterTactic]) -> Array[MonsterTactic]:
	var result: Array[MonsterTactic] = []
	for tactic in list:
		result.append(from_dict(tactic.to_dict()))
	return result
