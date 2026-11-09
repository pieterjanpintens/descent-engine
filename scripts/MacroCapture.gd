class_name MacroCapture
extends RefCounted

## "Save as macro": turns what is on a prop - its prop actions, the variables they use and the triggers that belong to them - into a
## MacroTemplate (see MacroTemplate / UserMacro), so the same recipe can be applied to other props later.
##
## An instance analyses one prop and holds the author's choices; refresh() recomputes the candidate lists, build() makes the template.
## What it decides, and what the author can override:
##   - which prop actions are part of the macro (default: all of them);
##   - which triggers belong to it: those fired by one of the chosen actions (an event trigger on the action's id) are in by default; those that
##     only read one of the macro's variables are in when that variable is created by the macro;
##   - for each variable the pieces mention: CREATED BY THE MACRO (declared again, with a unique name, wherever the macro is applied - the
##     default when nothing outside the chosen pieces mentions it) or CHOSEN WHEN APPLIED (an input: a variable picker - the default when other
##     parts of the mission use it too, e.g. a flag another door reads);
##   - which fields become INPUTS (what the author fills in when applying): loot, the test attribute and the successes needed are offered by
##     default; message texts, action names / descriptions and the numbers in conditions, Set Variable and Math effects can be ticked.
## Things a template cannot carry are reported as warnings (an effect that points at another prop, a stage or a monster group of THIS mission).

enum FieldKind { INT, BOOL, TEXT, ATTRIBUTE, LOOT }

var mission: MissionData
var target: InteractableEntry

## The author's choices; a key that is missing means "the default".
var action_choice: Dictionary = {}    # action id -> bool
var trigger_choice: Dictionary = {}   # trigger id -> bool
var variable_choice: Dictionary = {}  # variable name -> bool (true = created by the macro)
var field_choice: Dictionary = {}     # field key -> bool
var field_label: Dictionary = {}      # field key -> the input's label

## Filled by refresh().
var actions: Array[PropAction] = []          # the chosen actions
var triggers: Array[Dictionary] = []          # {trigger: MissionTrigger, selected: bool, reason: String}
var variables: Array[Dictionary] = []         # {name: String, type: int, owned: bool, elsewhere: bool}
var fields: Array[Dictionary] = []            # {key, part, path, kind, value, label, selected}
var warnings: Array[String] = []

var _base := ""
var _mission_counts: Dictionary = {}


func _init(p_mission: MissionData, p_target: InteractableEntry) -> void:
	mission = p_mission
	target = p_target
	_base = MacroContext.new(mission, target, AppliedMacro.new()).base_name()
	var names := {}
	for variable in mission.custom_variables:
		names[variable.name] = true
	# how often each variable is mentioned in the whole mission (the declarations and the macro records are not mentions)
	_mission_counts = MacroWalker.count_texts([mission], names, PackedStringArray(["macros", "custom_variables"]))
	refresh()


func base_name() -> String:
	return _base


# --- analysis ---------------------------------------------------------------

func refresh() -> void:
	actions.clear()
	for action in target.actions:
		if action_choice.get(action.action_id, true):
			actions.append(action)
	var action_ids := {}
	for action in actions:
		action_ids[action.action_id] = true
	var action_variables := _variables_in(actions)

	# candidate triggers: fired by a chosen action, or reading a variable the chosen actions use
	var candidates: Array[Dictionary] = []
	for trigger in mission.triggers:
		var by_event := false
		for event in trigger.event_list():
			if action_ids.has(event):
				by_event = true
		var by_variable := not _variables_in([trigger], action_variables).is_empty()
		if by_event or by_variable:
			candidates.append({"trigger": trigger, "by_event": by_event})

	# is a variable mentioned anywhere else? (the chosen actions and the candidate triggers count as "inside")
	var inside: Array = []
	inside.append_array(actions)
	for candidate in candidates:
		inside.append(candidate["trigger"])
	var inside_counts := MacroWalker.count_texts(inside, _variable_names())
	var owned_by_default := {}
	for name in _variable_names():
		owned_by_default[name] = int(_mission_counts.get(name, 0)) - int(inside_counts.get(name, 0)) <= 0

	triggers.clear()
	var chosen_triggers: Array = []
	for candidate in candidates:
		var trigger: MissionTrigger = candidate["trigger"]
		var used := _variables_in([trigger], action_variables)
		var default_in: bool = candidate["by_event"]
		var reason := "fired by one of the actions" if default_in else "uses a variable of the macro"
		if not default_in:
			for name in used:
				if owned_by_default.get(name, false):
					default_in = true
		var selected: bool = trigger_choice.get(trigger.id, default_in)
		triggers.append({"trigger": trigger, "selected": selected, "reason": reason})
		if selected:
			chosen_triggers.append(trigger)

	var pieces: Array = []
	pieces.append_array(actions)
	pieces.append_array(chosen_triggers)
	variables.clear()
	var used_names := _variables_in(pieces)
	for variable in mission.custom_variables:
		if used_names.has(variable.name):
			var elsewhere: bool = not owned_by_default.get(variable.name, true)
			variables.append({
				"name": variable.name,
				"type": int(variable.type),
				"owned": variable_choice.get(variable.name, not elsewhere),
				"elsewhere": elsewhere,
			})

	fields.clear()
	warnings.clear()
	for action in actions:
		_discover(action, "a:" + action.action_id)
		_warn_references(action, "Action '%s'" % action.action_id)
	for trigger in chosen_triggers:
		_discover(trigger, "t:" + trigger.id)
		_warn_references(trigger, "A trigger")


func _variable_names() -> Dictionary:
	var names := {}
	for variable in mission.custom_variables:
		names[variable.name] = true
	return names


## The custom variables mentioned by `roots` (limited to `only` when given: a set).
func _variables_in(roots: Array, only: Variant = null) -> Dictionary:
	var wanted: Dictionary = only if only != null else _variable_names()
	return MacroWalker.count_texts(roots, wanted)


# --- fields that can become inputs ------------------------------------------

func _add_field(part: String, path: String, kind: FieldKind, value: Variant, label: String, default_selected: bool) -> void:
	var key := "%s/%s" % [part, path]
	fields.append({
		"key": key, "part": part, "path": path, "kind": kind, "value": value,
		"label": field_label.get(key, label),
		"selected": field_choice.get(key, default_selected),
	})


func _discover(root: Resource, part: String) -> void:
	if root is PropAction:
		var action := root as PropAction
		_add_field(part, "action_name", FieldKind.TEXT, action.action_name, "Action name", false)
		_add_field(part, "description", FieldKind.TEXT, action.description, "Action description", false)
	_discover_conditions(part, (root.get("conditions") as Array), "conditions")
	_discover_effects(part, (root.get("effects") as Array), "effects")


func _discover_conditions(part: String, list: Array, path: String) -> void:
	for index in list.size():
		var condition := list[index] as Condition
		if typeof(condition.value) == TYPE_INT:
			_add_field(part, "%s/%d/value" % [path, index], FieldKind.INT, condition.value, "Condition: %s" % condition.variable_name, false)
		elif typeof(condition.value) == TYPE_BOOL:
			_add_field(part, "%s/%d/value" % [path, index], FieldKind.BOOL, condition.value, "Condition: %s" % condition.variable_name, false)


func _discover_effects(part: String, list: Array, path: String) -> void:
	for index in list.size():
		var effect := list[index] as Effect
		var at := "%s/%d" % [path, index]
		_discover_conditions(part, effect.conditions, at + "/conditions")
		match effect.type:
			Effect.Type.SET_VARIABLE:
				var label := "Value for %s" % effect.variable_name
				if typeof(effect.value) == TYPE_INT:
					_add_field(part, at + "/value", FieldKind.INT, effect.value, label, false)
				elif typeof(effect.value) == TYPE_BOOL:
					_add_field(part, at + "/value", FieldKind.BOOL, effect.value, label, false)
				elif typeof(effect.value) == TYPE_STRING:
					_add_field(part, at + "/value", FieldKind.TEXT, effect.value, label, false)
			Effect.Type.SHOW_MESSAGE, Effect.Type.ASK_QUESTION:
				var text := effect.message
				var preview := text.substr(0, 28) + ("…" if text.length() > 28 else "")
				_add_field(part, at + "/message", FieldKind.TEXT, text, "Message: %s" % preview, false)
			Effect.Type.RUN_TEST:
				_add_field(part, at + "/test_attribute", FieldKind.ATTRIBUTE, effect.test_attribute, "Test", true)
				_add_field(part, at + "/required_successes", FieldKind.INT, effect.required_successes, "Successes needed", true)
			Effect.Type.MATH:
				if not effect.math_operand_a_is_variable:
					_add_field(part, at + "/math_operand_a_literal", FieldKind.INT, effect.math_operand_a_literal, "First number (%s)" % effect.variable_name, false)
				if not effect.math_operand_b_is_variable:
					_add_field(part, at + "/math_operand_b_literal", FieldKind.INT, effect.math_operand_b_literal, "Second number (%s)" % effect.variable_name, false)
			Effect.Type.LOOT:
				_add_field(part, at, FieldKind.LOOT, effect, "Loot", true)
		if not effect.pass_effects.is_empty() or not effect.fail_effects.is_empty():
			_discover_effects(part, effect.pass_effects, at + "/pass_effects")
			_discover_effects(part, effect.fail_effects, at + "/fail_effects")


## Warnings for effects that point at things of THIS mission, which another mission does not have.
func _warn_references(root: Resource, who: String) -> void:
	var pointers := {}
	_collect_pointers(root.get("effects") as Array, pointers)
	for pointer in pointers:
		var what: String = pointers[pointer]
		if what == "object":
			if pointer == target.id:
				continue  # the prop itself: becomes "this prop" in the template
			var other := mission.find_node_by_id(pointer)
			warnings.append("%s points at the object '%s'. A template cannot choose another object when applied: every use would point at this one." % [who, other.reference_name if other != null and other.reference_name != "" else pointer])
		elif what == "group":
			warnings.append("%s points at a stage or monster group of this mission ('%s'); that will not exist elsewhere." % [who, pointer])


func _collect_pointers(list: Array, into: Dictionary) -> void:
	for effect in list:
		var e := effect as Effect
		if e.target_object_id != "" and e.target_object_id != Effect.SELF_ID and e.target_object_id != Effect.MAIN_TABLE:
			into[e.target_object_id] = "object"
		if e.target_group_id != "" and e.target_group_id != Effect.MAIN_TABLE:
			into[e.target_group_id] = "group"
		if e.spawn_group_id != "":
			into[e.spawn_group_id] = "group"
		_collect_pointers(e.pass_effects, into)
		_collect_pointers(e.fail_effects, into)


# --- the template -------------------------------------------------------------

## The macro as a template. `any_prop` = it may be applied to any prop, else only to props of this prop's mesh.
func build(title: String, description: String, macro_id: String, any_prop: bool) -> MacroTemplate:
	refresh()
	var template := MacroTemplate.new()
	template.macro_id = macro_id
	template.title = title
	template.description = description
	template.target_type = MacroTemplate.TargetType.PROP
	if not any_prop:
		template.meshes = [target.mesh_item_name] as Array[String]

	var keys := {}
	var param_ids := {}
	var mapping := {target.id: Effect.SELF_ID}  # exact text -> the token or constant that replaces it in the copies
	var params: Array[MacroParam] = []
	var parts: Array[MacroTemplatePart] = []

	for variable in variables:
		var name: String = variable["name"]
		var declared := _declared(name)
		if declared == null:
			continue
		if variable["owned"]:
			var key := _unique(MacroContext.identifier(name), keys)
			var part := MacroTemplatePart.new()
			part.kind = MacroTemplatePart.Kind.VARIABLE
			part.key = key
			part.wanted = _wanted_name(name)
			var copy := declared.duplicate(true) as MissionVariable
			copy.name = ""
			part.data = copy
			parts.append(part)
			mapping[name] = "{var:%s}" % key
		else:
			var param_id := _unique(MacroContext.identifier(name), param_ids)
			params.append(MacroParam.variable_param(param_id, "Variable: %s" % name, int(declared.type), name))
			mapping[name] = "{%s}" % param_id

	var action_parts: Array[MacroTemplatePart] = []
	for action in actions:
		var part := MacroTemplatePart.new()
		part.kind = MacroTemplatePart.Kind.ACTION
		# an action without an id (only a name was typed) gets one from its name, so the template still has a usable key
		var wanted_id := action.action_id
		if wanted_id == "":
			wanted_id = MacroContext.identifier(action.action_name) if action.action_name.strip_edges() != "" else "action"
		part.key = _unique(MacroContext.identifier(wanted_id), keys)
		part.wanted = wanted_id
		var copy := action.duplicate(true) as PropAction
		copy.already_used = false
		part.data = copy
		parts.append(part)
		action_parts.append(part)
		if action.action_id != "":  # an empty text must never be replaced everywhere
			mapping[action.action_id] = "{action:%s}" % part.key
	var trigger_parts: Array[MacroTemplatePart] = []
	for entry in triggers:
		if not entry["selected"]:
			continue
		var trigger := entry["trigger"] as MissionTrigger
		var part := MacroTemplatePart.new()
		part.kind = MacroTemplatePart.Kind.TRIGGER
		part.key = _unique("trigger", keys)
		var copy := trigger.duplicate(true) as MissionTrigger
		copy.already_fired = false
		part.data = copy
		parts.append(part)
		trigger_parts.append(part)

	# inputs from the ticked fields
	var key_of_part := {}
	for index in actions.size():
		key_of_part["a:" + actions[index].action_id] = action_parts[index].key
	var trigger_index := 0
	for entry in triggers:
		if entry["selected"]:
			key_of_part["t:" + (entry["trigger"] as MissionTrigger).id] = trigger_parts[trigger_index].key
			trigger_index += 1
	var bindings: Array[MacroBinding] = []
	for field in fields:
		if not field["selected"] or not key_of_part.has(field["part"]):
			continue
		var label: String = str(field["label"]).strip_edges()
		var param := _param_for_field(field, _unique(MacroContext.identifier(label if label != "" else "value"), param_ids), label if label != "" else "Value")
		params.append(param)
		var binding := MacroBinding.new()
		binding.path = "%s/%s" % [key_of_part[field["part"]], field["path"]]
		binding.param_id = param.id
		bindings.append(binding)

	# names of variables, actions and the prop itself become tokens in the copies
	var rewrite := func(text: String) -> String: return mapping.get(text, text)
	for part in parts:
		MacroWalker.map_strings(part.data, rewrite)

	template.params = params
	template.parts = parts
	template.bindings = bindings
	return template


func _param_for_field(field: Dictionary, param_id: String, label: String) -> MacroParam:
	var value: Variant = field["value"]
	match field["kind"]:
		FieldKind.INT:
			var number := int(value)
			return MacroParam.int_param(param_id, label, number, mini(0, number * 2), maxi(99, number * 2))
		FieldKind.BOOL:
			return MacroParam.bool_param(param_id, label, bool(value))
		FieldKind.ATTRIBUTE:
			var choices := []
			for attribute in [PlayerAttribute.Attribute.STRENGTH, PlayerAttribute.Attribute.AGILITY, PlayerAttribute.Attribute.INTELLIGENCE, PlayerAttribute.Attribute.WILL]:
				choices.append([PlayerAttribute.attribute_name(attribute), attribute])
			return MacroParam.choice_param(param_id, label, choices, int(value))
		FieldKind.LOOT:
			var param := MacroParam.loot_param(param_id, label)
			param.default_value = (value as Effect).duplicate(true)
			param.allow_empty = loot_is_empty(value as Effect)
			return param
	return MacroParam.text_param(param_id, label, str(value))


static func loot_is_empty(loot: Effect) -> bool:
	return loot.loot_materials.is_empty() and loot.loot_cards.is_empty() and loot.loot_recipes.is_empty() and loot.loot_usable.is_empty()


func _declared(name: String) -> MissionVariable:
	for variable in mission.custom_variables:
		if variable.name == name:
			return variable
	return null


## A variable called "chest_progress" on a prop whose base name is "chest" is wanted as "{base}_progress" - so on another prop it is named
## after that prop.
func _wanted_name(name: String) -> String:
	if name == _base:
		return "{base}"
	if name.begins_with(_base + "_"):
		return "{base}" + name.substr(_base.length())
	return name


static func _unique(wanted: String, used: Dictionary) -> String:
	var result := wanted
	var suffix := 2
	while used.has(result):
		result = "%s_%d" % [wanted, suffix]
		suffix += 1
	used[result] = true
	return result
