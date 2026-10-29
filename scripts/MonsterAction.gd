class_name MonsterAction
extends Resource

## An ALTERNATIVE ACTIVATION of a monster: what it does instead of attacking, e.g. when
## it is Confused (MissionPlayer._monster_action()). The table is shown the action
## instead of the attack dialog and carries it out itself - the app doesn't track
## positions, so it only tells what to do ("Move as far from the heroes as you can").
##
## A base template (MonsterArchetype.confused_actions) holds a list of them; the monster
## picks one at random among those that are possible right now (weighted by `weight`).
## An empty list means the built-in defaults() are used.
##
## `text` may contain {speed} (the monster's effective speed) and {damage} (its attack
## damage), filled in by shown_text().

@export var action_name_texts: Dictionary = {}
var action_name: String:
	get:
		return LText.pick(action_name_texts)
	set(value):
		LText.put(action_name_texts, value)
@export var text_texts: Dictionary = {}
var text: String:
	get:
		return LText.pick(text_texts)
	set(value):
		LText.put(text_texts, value)
## Possible only while a prop with this reference name or mesh name is on the board and
## visible ("gate", "tree"); several alternatives separated by commas ("tall,mini,medium").
## Empty = no requirement.
@export var required_object: String = ""
## Possible only while at least this many monsters are alive (0 = no requirement).
@export_range(0, 99) var min_monsters: int = 0
## Relative chance among the possible actions (1 = normal).
@export_range(1, 99) var weight: int = 1


func _init(p_name: String = "", p_text: String = "", p_required_object: String = "", p_min_monsters: int = 0) -> void:
	action_name = p_name
	text = p_text
	required_object = p_required_object
	min_monsters = p_min_monsters


## The text as shown to the table, for `monster`.
func shown_text(monster: RuntimeMonster) -> String:
	return text.replace("{speed}", str(monster.effective_speed())).replace("{damage}", str(monster.effective_attack_power()))


## Plain-data form for SaveGame (RuntimeMonster.to_dict()).
func to_dict() -> Dictionary:
	return {"name": action_name, "text": text, "required_object": required_object, "min_monsters": min_monsters, "weight": weight}


static func from_dict(d: Dictionary) -> MonsterAction:
	var action := MonsterAction.new(str(d.get("name", "")), str(d.get("text", "")), str(d.get("required_object", "")), int(d.get("min_monsters", 0)))
	action.weight = int(d.get("weight", 1))
	return action


## An independent copy that keeps the text in every language (to_dict() carries only the language being read).
func copy_full() -> MonsterAction:
	var copy := from_dict(to_dict())
	copy.action_name_texts = action_name_texts.duplicate()
	copy.text_texts = text_texts.duplicate()
	return copy


## Independent copies of `list` (a spawned monster must not share the template's resources).
static func copies(list: Array[MonsterAction]) -> Array[MonsterAction]:
	var result: Array[MonsterAction] = []
	for action in list:
		result.append(action.copy_full())
	return result


## The nothing-happens action: also the last resort when no action of a monster is possible.
static func stand_and_stare() -> MonsterAction:
	return MonsterAction.new("What was I doing?", "The monster just stands and stares... It does nothing at all.")


## The built-in set used when a base template has no actions of its own (also what the
## template editor's "Fill with defaults" copies in to edit).
static func defaults() -> Array[MonsterAction]:
	var list: Array[MonsterAction] = [
		MonsterAction.new(TranslationServer.translate("Retreat"), TranslationServer.translate("Did I hear retreat? Move up to {speed} tiles, as far away from the heroes as you can.")),
		stand_and_stare(),
		MonsterAction.new(TranslationServer.translate("Guard the gate"), TranslationServer.translate("Move up to {speed} tiles to the closest gate and guard it."), "gate"),
		MonsterAction.new(TranslationServer.translate("Towards the tree"), TranslationServer.translate("Move up to {speed} tiles towards the closest tree."), "tree"),
		MonsterAction.new(TranslationServer.translate("Wander"), TranslationServer.translate("Move up to {speed} tiles in a random direction.")),
		MonsterAction.new(TranslationServer.translate("Friendly fire"), TranslationServer.translate("Lash out at the nearest other monster: it takes {damage} damage. (Press Interrupt, click that monster in the monster view and apply the damage.)"), "", 2),
		MonsterAction.new(TranslationServer.translate("Lunge, no bite"), TranslationServer.translate("Move up to {speed} tiles towards the nearest hero - but do not attack.")),
		MonsterAction.new(TranslationServer.translate("Take cover"), TranslationServer.translate("Move up to {speed} tiles to the nearest pillar and hide behind it."), "tall,mini,medium"),
	]
	return list
