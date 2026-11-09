class_name MacroTemplate
extends Resource

## A user-defined macro, as data: what the author sees (title, description, what it applies to), its inputs, and the recipe - the variables,
## prop actions and triggers it generates (`parts`), with {tokens} in their texts (MacroTokens) and `bindings` that write inputs into their
## number / yes-no / whole-effect fields (MacroBinding). UserMacro turns a template into a MissionMacro, so the editor treats it like a
## built-in one. Saved by MacroTemplateLibrary in the user folder.
##
## Limits on purpose: a template cannot branch ("only when this input is on") - it generates the same pieces every time, with the inputs
## filled in. A recipe that needs a decision is still written as a built-in macro (code).

enum TargetType { PROP, MONSTER_SPAWN, ANY }

## Stable id, saved in every AppliedMacro; never change it once the macro has been applied somewhere. Built-in macro ids are refused.
@export var macro_id: String = ""
@export var title: String = ""
@export var description: String = ""
## Raised by the author when the recipe changes (a record made with an older version can then be regenerated).
@export var version: int = 1
@export var repeatable: bool = false
@export var target_type: TargetType = TargetType.PROP
## For PROP: the piece names it applies to ("chest"); empty = any prop.
@export var meshes: Array[String] = []
## One line telling the AI stage generator how to ask for this macro on a piece ("" = not offered to the AI). See MissionMacro.plan_hint().
@export var plan_hint: String = ""
@export var params: Array[MacroParam] = []
@export var parts: Array[MacroTemplatePart] = []
@export var bindings: Array[MacroBinding] = []


## A fingerprint of the recipe's content: two templates with the same key generate the same data. Used to store one copy per recipe in a mission.
func content_key() -> String:
	return str(MacroEngine.dump(self).hash())


func find_part(key: String) -> MacroTemplatePart:
	for part in parts:
		if part.key == key:
			return part
	return null


func find_param(param_id: String) -> MacroParam:
	for param in params:
		if param.id == param_id:
			return param
	return null


## Everything wrong with the template (empty when it can be used): ids, keys, parts, bindings that point nowhere.
func problems() -> Array[String]:
	var found: Array[String] = []
	if macro_id == "" or not _safe_id(macro_id):
		found.append("The macro needs an id (letters, digits, '_', '-' and '.').")
	elif MacroTemplate.is_builtin_id(macro_id):
		found.append("'%s' is the id of a built-in macro; choose another." % macro_id)
	if title == "":
		found.append("The macro needs a title.")
	var param_ids := {}
	for param in params:
		if param.id == "" or MacroContext.identifier(param.id) != param.id:
			found.append("An input has no usable id ('%s'): letters, digits and underscores only." % param.id)
		elif param_ids.has(param.id):
			found.append("Two inputs are called '%s'." % param.id)
		param_ids[param.id] = true
	var keys := {}
	for part in parts:
		var issue := part.problem()
		if issue != "":
			found.append(issue)
		if keys.has(part.key):
			found.append("Two parts have the key '%s'." % part.key)
		keys[part.key] = true
		if part.kind == MacroTemplatePart.Kind.ACTION and target_type == TargetType.MONSTER_SPAWN:
			found.append("Part '%s' is a prop action, but the macro applies to monster spawn areas." % part.key)
	for binding in bindings:
		var part := find_part(binding.part_key())
		if part == null:
			found.append("A binding points at the part '%s', which does not exist." % binding.part_key())
		elif binding.fields().is_empty():
			found.append("The binding '%s' names no field." % binding.path)
		elif part.data != null and not MacroBinding.can_write(part.data, binding.fields()):
			found.append("The binding '%s' does not lead to a field." % binding.path)
		if find_param(binding.param_id) == null:
			found.append("The binding '%s' uses the input '%s', which does not exist." % [binding.path, binding.param_id])
	return found


static func is_builtin_id(candidate: String) -> bool:
	for macro in MacroCatalog.builtin():
		if macro.id() == candidate:
			return true
	return false


static func _safe_id(candidate: String) -> bool:
	for index in candidate.length():
		var ch := candidate[index].to_lower()
		var ok := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-" or ch == "."
		if not ok:
			return false
	return true
