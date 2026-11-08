class_name MacroContext
extends RefCounted

## What a macro's build() works with: the mission, the node the macro is applied to, and the creation helpers. Everything the macro adds
## goes through here so the AppliedMacro record knows exactly what was generated (and the engine can replace or delete it again).

var mission: MissionData
var target: OutlineNode
var applied: AppliedMacro


func _init(p_mission: MissionData, p_target: OutlineNode, p_applied: AppliedMacro) -> void:
	mission = p_mission
	target = p_target
	applied = p_applied


## A readable identifier for names the macro generates: the target's own name when it has one, else its mesh name ("chest"), made safe for
## use in variable names and formulas (lower case letters, digits, underscores, starting with a letter).
func base_name() -> String:
	var raw := target.reference_name
	if raw == "" and target is InteractableEntry:
		raw = (target as InteractableEntry).mesh_item_name
	return MacroContext.identifier(raw if raw != "" else "item")


static func identifier(text: String) -> String:
	var out := ""
	for i in text.length():
		var ch := text[i].to_lower()
		var is_letter := ch >= "a" and ch <= "z"
		var is_digit := ch >= "0" and ch <= "9"
		out += ch if (is_letter or is_digit) else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_")
	if out == "" or not (out[0] >= "a" and out[0] <= "z"):
		out = "m_" + out
	return out


## Declares a mission variable named `wanted` (a number is added when the name is taken, so existing data is never touched) and returns the
## name that was really used.
func variable(wanted: String, type: MissionVariable.Type, default_value: Variant) -> String:
	var name := wanted
	var suffix := 2
	while _variable_taken(name):
		name = "%s_%d" % [wanted, suffix]
		suffix += 1
	var declared := MissionVariable.new()
	declared.name = name
	declared.type = type
	declared.default_value = default_value
	mission.custom_variables.append(declared)
	applied.variable_names.append(name)
	return name


func _variable_taken(name: String) -> bool:
	if MissionRuntime.BUILTIN_TYPES.has(name):
		return true
	for existing in mission.custom_variables:
		if existing.name == name:
			return true
	return false


## Adds a new prop action to `entry` (default: the target, which must be a prop) with a unique action id based on `wanted_id`, and returns it
## for the macro to fill in.
func action(wanted_id: String, entry: InteractableEntry = null) -> PropAction:
	var holder := entry if entry != null else target as InteractableEntry
	if holder == null:
		push_warning("MacroContext.action(): the macro target is not a prop")
		return null
	var action_id := wanted_id
	var suffix := 2
	while _action_id_taken(action_id):
		action_id = "%s_%d" % [wanted_id, suffix]
		suffix += 1
	var created := PropAction.new()
	created.action_id = action_id
	holder.actions.append(created)
	applied.action_ids.append(action_id)
	return created


func _action_id_taken(action_id: String) -> bool:
	for entry in mission.interactables:
		for existing in entry.actions:
			if existing.action_id == action_id:
				return true
	return false


## Adds `created` to the mission's triggers (it gets an id) and remembers it as generated.
func trigger(created: MissionTrigger) -> MissionTrigger:
	created.id = mission.allocate_object_id()
	mission.triggers.append(created)
	applied.trigger_ids.append(created.id)
	return created
