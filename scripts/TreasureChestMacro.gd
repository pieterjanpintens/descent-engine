class_name TreasureChestMacro
extends MissionMacro

## "Treasure chest": makes a chest prop something the heroes have to open with a test, and pays out loot when they succeed.
## Inputs: which attribute test, how many successes in total are needed (repeated attempts add up), and what is inside.
## Generates, on the chest:
##   - a variable `<chest>_progress` (INT, 0) that collects the successes of every attempt,
##   - ONE prop action "Open the chest" whose effect is a Test of that attribute: it adds the rolled successes to the variable and is judged
##     on the running total (the required number is never told to the table), and
##       when the total reaches the goal - the Loot effect (with a default sentence for the test when the author left the text empty),
##                                         then the chest removes itself (Remove Object on "Self");
##       otherwise - a short "it holds" message, and the heroes can try again.

const ATTRIBUTE_TEXTS := {
	PlayerAttribute.Attribute.STRENGTH: {
		"action": "You put your shoulder to the heavy lid.",
		"success": "With a groan of splintering wood, the lid gives way.",
		"fail": "The lid will not budge. It needs more force.",
	},
	PlayerAttribute.Attribute.AGILITY: {
		"action": "You work a thin blade into the lock.",
		"success": "The lock clicks open.",
		"fail": "The lock resists your fingers. Try again.",
	},
	PlayerAttribute.Attribute.INTELLIGENCE: {
		"action": "You study the lock and its mechanism.",
		"success": "You find the trick: the mechanism releases the lid.",
		"fail": "The mechanism is more cunning than it looks.",
	},
	PlayerAttribute.Attribute.WILL: {
		"action": "You focus your will on the seal that binds the chest.",
		"success": "The seal shatters and the lid swings open.",
		"fail": "The seal holds, for now.",
	},
}


func id() -> String:
	return "treasure_chest"


func title() -> String:
	return "Treasure chest"


func description() -> String:
	return "The heroes open the chest with a test; successes add up over several attempts. When the goal is reached they find the loot and the chest is removed."


func fits(target: OutlineNode) -> bool:
	return target is InteractableEntry and fits_mesh((target as InteractableEntry).mesh_item_name)


func fits_mesh(mesh: String) -> bool:
	return mesh == "chest"


func plan_hint() -> String:
	return 'chest: "macro": {"id": "treasure_chest", "attribute": "strength|agility|intelligence|will", "needed": 3, "gold": 30} - the heroes must pass a test to open it (the successes of every attempt add up to "needed") and then find the gold; the chest disappears.'


func params() -> Array[MacroParam]:
	return [
		MacroParam.choice_param("attribute", "Test to open it", [
			["Strength", PlayerAttribute.Attribute.STRENGTH],
			["Agility", PlayerAttribute.Attribute.AGILITY],
			["Intelligence", PlayerAttribute.Attribute.INTELLIGENCE],
			["Will", PlayerAttribute.Attribute.WILL],
		], PlayerAttribute.Attribute.STRENGTH),
		MacroParam.int_param("needed", "Successes needed in total", 3, 1, 99, "Every attempt adds its successes; the chest opens when the total reaches this. The players are never told the number."),
		MacroParam.loot_param("loot", "What is inside", "Leave the text empty to get a default sentence for the test."),
	]


func problem(values: Dictionary) -> String:
	var loot := values.get("loot") as Effect
	if loot == null or (loot.loot_materials.is_empty() and loot.loot_cards.is_empty() and loot.loot_recipes.is_empty() and loot.loot_usable.is_empty()):
		return "Put something in the chest first (Loot…)."
	return ""


func build(ctx: MacroContext, values: Dictionary) -> void:
	var attribute: int = values["attribute"]
	var texts: Dictionary = ATTRIBUTE_TEXTS.get(attribute, ATTRIBUTE_TEXTS[PlayerAttribute.Attribute.STRENGTH])
	var progress := ctx.variable(ctx.base_name() + "_progress", MissionVariable.Type.INT, 0)

	var action := ctx.action("open_chest")
	action.action_name = "Open the chest"
	action.description = "%s (%s test)" % [texts["action"], PlayerAttribute.attribute_name(attribute)]

	var loot: Effect = (values["loot"] as Effect).duplicate(true)
	loot.type = Effect.Type.LOOT
	if loot.loot_title == "":
		loot.loot_title = "Chest"
	if loot.loot_text == "":
		loot.loot_text = texts["success"]

	var remove_chest := Effect.new()
	remove_chest.type = Effect.Type.REMOVE_OBJECT
	remove_chest.target_object_id = Effect.SELF_ID

	var failed := Effect.new()
	failed.type = Effect.Type.SHOW_MESSAGE
	failed.message = texts["fail"]

	var test := Effect.new()
	test.type = Effect.Type.RUN_TEST
	test.test_attribute = attribute
	test.required_successes = int(values["needed"])
	test.accumulate_variable_name = progress
	test.compare_accumulated = true
	test.pass_effects.append(loot)
	test.pass_effects.append(remove_chest)
	test.fail_effects.append(failed)
	action.effects.append(test)
