class_name LockedDoorMacro
extends MissionMacro

## "Locked door": a gate that stays shut until something sets its variable (a key found in a chest, a lever, a story effect) and then removes
## itself when opened. Optionally the heroes can also force it open with a test.
## Generates, on the gate:
##   - a variable `<door>_unlocked` (BOOL, false): set it to yes from anywhere (Set Variable effect) to unlock the door,
##   - the action "Open the door" (offered only while unlocked): the door removes itself (Remove Object on "Self"),
##   - the action "Try the door" (offered only while locked): shows the "locked" message,
##   - when forcing is allowed: a variable `<door>_force` (INT) and the action "Force the door" (only while locked): a Test of the chosen
##     attribute whose successes add up (judged on the running total), and the door removes itself when the goal is reached.


func id() -> String:
	return "locked_door"


func title() -> String:
	return "Locked door"


func description() -> String:
	return "The door stays shut until the variable <name>_unlocked is set to yes (for example by a key found in a chest). Opening it removes the door. Optionally it can be forced open with a test."


func fits(target: OutlineNode) -> bool:
	return target is InteractableEntry and fits_mesh((target as InteractableEntry).mesh_item_name)


func fits_mesh(mesh: String) -> bool:
	return mesh == "gate"


func plan_hint() -> String:
	return 'gate: "macro": {"id": "locked_door", "locked_message": "The door is locked.", "forceable": true, "attribute": "strength", "needed": 4} - a door that stays shut until the story unlocks it (a key found elsewhere); "forceable" lets the heroes break it open with a test.'


func params() -> Array[MacroParam]:
	return [
		MacroParam.text_param("locked_message", "Message when it is tried while locked", "The door is locked.", "What the table reads when they try the handle."),
		MacroParam.bool_param("forceable", "It can also be forced open with a test", false),
		MacroParam.choice_param("attribute", "Test to force it", [
			["Strength", PlayerAttribute.Attribute.STRENGTH],
			["Agility", PlayerAttribute.Attribute.AGILITY],
			["Intelligence", PlayerAttribute.Attribute.INTELLIGENCE],
			["Will", PlayerAttribute.Attribute.WILL],
		], PlayerAttribute.Attribute.STRENGTH, "Only used when the door can be forced."),
		MacroParam.int_param("needed", "Successes needed to force it", 4, 1, 99, "Only used when the door can be forced. Successes of every attempt add up."),
	]


func problem(values: Dictionary) -> String:
	if str(values.get("locked_message", "")).strip_edges() == "":
		return "Write the message the table reads when the door is tried while locked."
	return ""


static func _remove_self() -> Effect:
	var remove_door := Effect.new()
	remove_door.type = Effect.Type.REMOVE_OBJECT
	remove_door.target_object_id = Effect.SELF_ID
	return remove_door


static func _message(text: String) -> Effect:
	var message := Effect.new()
	message.type = Effect.Type.SHOW_MESSAGE
	message.message = text
	return message


static func _when(variable_name: String, value: bool) -> Condition:
	var condition := Condition.new()
	condition.variable_name = variable_name
	condition.operator = Condition.Operator.EQUALS
	condition.value = value
	return condition


func build(ctx: MacroContext, values: Dictionary) -> void:
	var unlocked := ctx.variable(ctx.base_name() + "_unlocked", MissionVariable.Type.BOOL, false)

	var open := ctx.action("open_door")
	open.action_name = "Open the door"
	open.description = "The door is unlocked."
	open.conditions.append(_when(unlocked, true))
	open.effects.append(_remove_self())

	var attempt := ctx.action("try_door")
	attempt.action_name = "Try the door"
	attempt.description = "You try the handle."
	attempt.conditions.append(_when(unlocked, false))
	attempt.effects.append(_message(str(values["locked_message"])))

	if bool(values.get("forceable", false)):
		var attribute: int = values["attribute"]
		var force_progress := ctx.variable(ctx.base_name() + "_force", MissionVariable.Type.INT, 0)
		var force := ctx.action("force_door")
		force.action_name = "Force the door"
		force.description = "You throw yourself at the door. (%s test)" % PlayerAttribute.attribute_name(attribute)
		force.conditions.append(_when(unlocked, false))
		var test := Effect.new()
		test.type = Effect.Type.RUN_TEST
		test.test_attribute = attribute
		test.required_successes = int(values["needed"])
		test.accumulate_variable_name = force_progress
		test.compare_accumulated = true
		test.pass_effects.append(_message("The door splinters and gives way."))
		test.pass_effects.append(_remove_self())
		test.fail_effects.append(_message("The door shudders, but holds."))
		force.effects.append(test)
