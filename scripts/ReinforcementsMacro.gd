class_name ReinforcementsMacro
extends MissionMacro

## "Reinforcements": a steady stream of monsters out of a monster spawn area, so the heroes cannot stand still and heal. Applied to a monster
## spawn area; generates ONE repeating trigger (before the monster phase) that spawns random monsters of a pool there:
##   - every Nth round (round_number mod = 0), from a start round on,
##   - only while fewer than a limit of monsters are on the map (monsters_on_the_map),
##   - a Spawn Random Monsters effect: a fixed number each time, or enough to fill the board up to the limit. Monsters that are no longer
##     left in the box are skipped; when the pool runs dry whatever is left spawns.


func id() -> String:
	return "reinforcements"


func title() -> String:
	return "Reinforcements"


func description() -> String:
	return "Every few rounds, while the board has few monsters, random monsters from a pool appear at this spawn area. Keeps the heroes moving."


func fits(target: OutlineNode) -> bool:
	return target is MonsterSpawn


func params() -> Array[MacroParam]:
	return [
		MacroParam.monsters_param("pool", "Monsters to pick from", "Each spawn picks randomly from this list (list a monster twice to make it more likely). Types that are no longer in the box are skipped."),
		MacroParam.int_param("every", "Every Nth round", 3, 1, 20, "1 = every round."),
		MacroParam.int_param("start_round", "Not before round", 1, 1, 50),
		MacroParam.int_param("limit", "Only while fewer than this many monsters are on the map", 3, 1, 16, "The monster limit: nothing spawns while this many are alive."),
		MacroParam.bool_param("fill", "Spawn enough to fill the board up to the limit", false, "Otherwise a fixed number spawns each time."),
		MacroParam.int_param("count", "How many each time", 1, 1, 20, "Not used when filling up to the limit."),
	]


func problem(values: Dictionary) -> String:
	var pool := values.get("pool") as Effect
	if pool == null or (pool.spawn_monsters.is_empty() and pool.spawn_group_id == ""):
		return "Add some monsters to pick from first (Monsters…)."
	return ""


func build(ctx: MacroContext, values: Dictionary) -> void:
	var trigger := MissionTrigger.new()
	trigger.checkpoint = RoundCheckpoint.Checkpoint.BEFORE_DARKNESS_PHASE
	trigger.one_shot = false  # a stream: it fires again whenever its conditions hold

	var start_round := int(values["start_round"])
	if start_round > 1:
		trigger.conditions.append(_condition("round_number", Condition.Operator.GREATER_EQUAL, start_round))
	var every := int(values["every"])
	if every > 1:
		trigger.conditions.append(_condition("round_number", Condition.Operator.MULTIPLE_OF, every))
	var limit := int(values["limit"])
	trigger.conditions.append(_condition("monsters_on_the_map", Condition.Operator.LESS, limit))

	var spawn: Effect = (values["pool"] as Effect).duplicate(true)
	spawn.type = Effect.Type.SPAWN_RANDOM_MONSTERS
	spawn.target_object_id = ctx.target.id
	spawn.random_spawn_count = "%d - monsters_on_the_map" % limit if bool(values.get("fill", false)) else str(int(values["count"]))
	trigger.effects.append(spawn)
	ctx.trigger(trigger)


static func _condition(variable_name: String, operator: Condition.Operator, value: int) -> Condition:
	var condition := Condition.new()
	condition.variable_name = variable_name
	condition.operator = operator
	condition.value = value
	return condition
