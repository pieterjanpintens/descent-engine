class_name MacroParam
extends RefCounted

## One input of a MissionMacro (see MissionMacro.params()): what the author fills in in the MacroDialog before the macro builds its data.
## The dialog is generated from these, so a new macro needs no UI code.
##
## Kinds and what their value is:
##   INT    a whole number between min_value and max_value
##   BOOL   true / false
##   TEXT   one line of text
##   CHOICE one of `choices` - each entry is [label, value] (the value is what the macro receives, typically an int enum)
##   LOOT   an Effect of type LOOT (gold, materials, cards, recipes, title, text), edited with the normal Loot editor; the macro
##          should .duplicate(true) it into the data it generates

enum Kind { INT, BOOL, TEXT, CHOICE, LOOT }

var id: String = ""
var label: String = ""
var hint: String = ""
var kind: Kind = Kind.INT
var default_value: Variant = null
var min_value: int = 0
var max_value: int = 99
var choices: Array = []


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


## A fresh default value (a LOOT param starts as an empty Loot effect).
func make_default() -> Variant:
	if kind == Kind.LOOT:
		var loot := Effect.new()
		loot.type = Effect.Type.LOOT
		return loot
	return default_value
