class_name MacroParam
extends Resource

## One input of a MissionMacro (see MissionMacro.params()): what the author fills in in the MacroDialog before the macro builds its data.
## The dialog is generated from these, so a new macro needs no UI code.
##
## Kinds and what their value is:
##   INT    a whole number between min_value and max_value
##   BOOL   true / false
##   TEXT   one line of text
##   CHOICE one of `choices` - each entry is [label, value] (the value is what the macro receives, typically an int enum); an optional
##          third entry is a Dictionary of extra texts ({"success": "..."}) that a user-defined macro template reads as {param.success}
##   LOOT   an Effect of type LOOT (gold, materials, cards, recipes, title, text), edited with the normal Loot editor; the macro
##          should .duplicate(true) it into the data it generates
##   MONSTERS a pool of monsters: an Effect of type SPAWN_RANDOM_MONSTERS whose `spawn_monsters` (or `spawn_group_id`) is the list, edited with the
##          Spawn Monsters editor; the macro duplicates it into the effect it generates and sets the target and count itself

enum Kind { INT, BOOL, TEXT, CHOICE, LOOT, MONSTERS }

## (A Resource, not a plain object, so the inputs of a user-defined macro template can be saved - see MacroTemplate.)
@export var id: String = ""
@export var label: String = ""
@export var hint: String = ""
@export var kind: Kind = Kind.INT
@export var default_value: Variant = null
@export var min_value: int = 0
@export var max_value: int = 99
@export var choices: Array = []
## LOOT / MONSTERS only: whether an empty value is allowed (a user macro's problem() refuses an empty one otherwise).
@export var allow_empty: bool = false


static func int_param(p_id: String, p_label: String, p_default: int, p_min: int = 0, p_max: int = 99, p_hint: String = "") -> MacroParam:
	var param := MacroParam.new()
	param.id = p_id
	param.label = p_label
	param.kind = Kind.INT
	param.default_value = p_default
	param.min_value = p_min
	param.max_value = p_max
	param.hint = p_hint
	return param


static func bool_param(p_id: String, p_label: String, p_default: bool, p_hint: String = "") -> MacroParam:
	var param := MacroParam.new()
	param.id = p_id
	param.label = p_label
	param.kind = Kind.BOOL
	param.default_value = p_default
	param.hint = p_hint
	return param


static func text_param(p_id: String, p_label: String, p_default: String = "", p_hint: String = "") -> MacroParam:
	var param := MacroParam.new()
	param.id = p_id
	param.label = p_label
	param.kind = Kind.TEXT
	param.default_value = p_default
	param.hint = p_hint
	return param


## `p_choices` = [[label, value], ...]; `p_default` is one of the values.
static func choice_param(p_id: String, p_label: String, p_choices: Array, p_default: Variant, p_hint: String = "") -> MacroParam:
	var param := MacroParam.new()
	param.id = p_id
	param.label = p_label
	param.kind = Kind.CHOICE
	param.choices = p_choices
	param.default_value = p_default
	param.hint = p_hint
	return param


static func loot_param(p_id: String, p_label: String, p_hint: String = "") -> MacroParam:
	var param := MacroParam.new()
	param.id = p_id
	param.label = p_label
	param.kind = Kind.LOOT
	param.hint = p_hint
	return param


static func monsters_param(p_id: String, p_label: String, p_hint: String = "") -> MacroParam:
	var param := MacroParam.new()
	param.id = p_id
	param.label = p_label
	param.kind = Kind.MONSTERS
	param.hint = p_hint
	return param


## A fresh default value (a LOOT param starts as an empty Loot effect, a MONSTERS param as an empty random-spawn effect).
func make_default() -> Variant:
	if kind == Kind.LOOT:
		var loot := Effect.new()
		loot.type = Effect.Type.LOOT
		return loot
	if kind == Kind.MONSTERS:
		var pool := Effect.new()
		pool.type = Effect.Type.SPAWN_RANDOM_MONSTERS
		return pool
	return default_value
