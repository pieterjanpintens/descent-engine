class_name MissionRuntime
extends RefCounted

## The live variable registry + evaluator for one playthrough - the runtime
## container MissionData's own class doc says explicitly doesn't exist yet
## ("the story layer's own runtime ... is deliberately NOT part of this
## resource"). Constructed once by MissionPlayer._ready() from the loaded
## MissionData; not persisted, not saved back.
##
## Holds every variable's live value in one flat Dictionary - both
## MissionData.custom_variables (seeded from their default_value at
## construction) and the runtime's own built-ins (round_number/player_count,
## kept in sync via sync_builtins()) live in the same dictionary, evaluated
## identically by Condition/Effect - matching MissionVariable's own doc
## ("built-ins ... use this same shape but aren't authored here").
##
## apply_effect()/apply_effects() genuinely AWAIT now (new 2026-09-14, for
## Effect.Type.RUN_TEST - see that field group's own doc and _run_test()
## below), which makes them, and everything that calls them, real GDScript
## coroutines: _fire_triggers()/_check_current_objectives() ->
## evaluate_checkpoint()/fire_event() -> fire_prop_action(). Every one of
## those needed `await` added at its own call site once this rippled
## through - Godot's parser hard-errors ("Function is a coroutine, so it
## must be called with 'await'") on any call site that's missed, so this
## is self-checking, not a silent-breakage risk.

const BUILTIN_TYPES := {
	"round_number": MissionVariable.Type.INT,
	"player_count": MissionVariable.Type.INT,
}

var mission: MissionData

## The per-check debug prints (evaluate_condition / first_available_action) were
## added while chasing a real bug; callers that check availability in bulk
## (InteractionLabels, every few frames) switch this off for their pass so the
## console isn't flooded. Everything else keeps the prints.
var log_evaluations: bool = true
var _variables: Dictionary = {}  # String -> Variant

## Assigned externally by MissionPlayer._ready() right after construction
## (same "runtime-constructed object, plain var, no @export/NodePath"
## pattern already used for interaction_dock.mission_runtime), NOT held
## since this class's original construction. A deliberate, narrow
## exception to "MissionRuntime has no scene/UI access" (true for
## everything else here - see Effect.Type.SHOW_STAGE/REMOVE_OBJECT's own
## "queue an id, let the caller act on it" pattern): a RUN_TEST effect
## must ask a question and branch on the answer BEFORE the rest of its
## effects list can be applied, which can't be deferred to "the caller
## sorts it out afterward" the way Show Stage/Remove Object can - see
## _run_test() below and this class's own doc for the full reasoning.
var dialog: PlayerDialog

## Objectives-DAG traversal state - each entry is a set of mutually
## exclusive candidate MissionObjective nodes currently being watched.
## Starts as one singleton group per root in mission.objectives (roots are
## independent of each other, not siblings - see MissionObjective's own
## doc). When a group's winner resolves, the WHOLE group is replaced by
## its winner's children (a fresh group of new candidates) - this is what
## makes "first sibling to satisfy its conditions wins, the rest are
## dropped" correct without needing parent-pointers on MissionObjective:
## losing siblings are never explicitly "closed", they simply stop being
## reachable once their group is replaced.
var _current_groups: Array = []  # Array[Array[MissionObjective]]


func _init(p_mission: MissionData) -> void:
	mission = p_mission
	for variable in mission.custom_variables:
		var coerced: Variant = _coerce(variable.default_value, variable.type)
		if typeof(coerced) == TYPE_NIL:
			push_warning("MissionVariable '%s' default_value doesn't match its declared type - using a zero value" % variable.name)
			coerced = _zero_value(variable.type)
		_variables[variable.name] = coerced
		print("MissionRuntime: seeded '%s' = %s (%s)" % [variable.name, coerced, MissionVariable.Type.keys()[variable.type]])

	for root in mission.objectives:
		_current_groups.append([root])
	_warn_on_cycles()


func sync_builtins(round_number: int, player_count: int) -> void:
	_variables["round_number"] = round_number
	_variables["player_count"] = player_count


func get_variable(name: String) -> Variant:
	return _variables.get(name)


func set_variable(name: String, value: Variant) -> void:
	_variables[name] = value


func evaluate_condition(condition: Condition) -> bool:
	var declared: int = _declared_type(condition.variable_name)
	if declared == -1:
		push_warning("Condition references unknown variable '%s'" % condition.variable_name)
		return false
	var target: Variant = _coerce(condition.value, declared as MissionVariable.Type)
	if typeof(target) == TYPE_NIL:
		push_warning("Condition value for '%s' doesn't match its declared type" % condition.variable_name)
		return false
	var current: Variant = _variables.get(condition.variable_name)
	var result: bool
	match condition.operator:
		Condition.Operator.EQUALS:
			result = current == target
		Condition.Operator.NOT_EQUALS:
			result = current != target
		Condition.Operator.GREATER:
			result = current > target
		Condition.Operator.GREATER_EQUAL:
			result = current >= target
		Condition.Operator.LESS:
			result = current < target
		Condition.Operator.LESS_EQUAL:
			result = current <= target
		_:
			result = false
	if log_evaluations:
		print("MissionRuntime.evaluate_condition: '%s' %s %s -> current=%s (%s) => %s" % [condition.variable_name, Condition.Operator.keys()[condition.operator], target, current, typeof(current), result])
	return result


## Implicit AND across every entry - an empty array is vacuously true.
func evaluate_conditions(conditions: Array[Condition]) -> bool:
	for condition in conditions:
		if not evaluate_condition(condition):
			return false
	return true


## Returns the first PropAction in `entry.actions` whose own `conditions`
## currently hold (implicit AND, empty = always available), or null if
## none do - including an empty `actions` list. "First" by declared
## array order - PropAction has no priority field of its own (unlike
## MissionTrigger/MissionObjective), since a multi-action picker UI
## doesn't exist yet; array order is the only ordering that currently
## means anything. PlayerInteractionController uses this to decide both
## whether a prop is currently interactable at all, and which action
## actually fires on drop.
func first_available_action(entry: InteractableEntry) -> PropAction:
	for action in entry.actions:
		if evaluate_conditions(action.conditions) and not (action.single_shot and action.already_used):
			return action
	if log_evaluations:
		print("MissionRuntime.first_available_action: '%s' (%d action(s) authored) - none currently available" % [entry.reference_name if entry.reference_name != "" else entry.mesh_item_name, entry.actions.size()])
	return null


## Every action in `entry.actions` whose own `conditions` currently hold -
## the full candidate list for a picker UI (see PlayerInteractionController.
## _offer_actions()), unlike first_available_action() above which only
## returns the first (cheaper existence check, used to decide whether a
## prop is interactable at all) AND additionally skips an exhausted
## single-shot action. This list deliberately does NOT filter out an
## exhausted single_shot action (single_shot and already_used) - the
## picker is meant to still SHOW it, just disabled (see PropAction's own
## doc), so the player can see it's been used rather than have it silently
## vanish. Order matches entry.actions' own declared order.
func available_actions(entry: InteractableEntry) -> Array[PropAction]:
	var result: Array[PropAction] = []
	for action in entry.actions:
		if evaluate_conditions(action.conditions):
			result.append(action)
	return result


## Queued Effect.Type.SHOW_STAGE targets from the most recent
## apply_effect()/apply_effects() pass(es), drained by
## drain_pending_stage_reveals() below. A RefCounted with no scene/UI
## access (see this class's own doc) can't itself await a dialog or touch
## LayeredMap when a Show Stage effect fires, so it just collects the
## target group id for the caller (MissionPlayer) to act on afterward -
## same "return a value, let the caller decide" shape
## _check_current_objectives() already uses for ending the game.
var _pending_stage_reveals: Array[String] = []

## Queued Effect.Type.REMOVE_OBJECT targets, same shape/reasoning as
## _pending_stage_reveals above - drained by
## drain_pending_object_removals() below.
var _pending_object_removals: Array[String] = []

## Queued Effect.Type.MOVE_OBJECT targets, same shape/reasoning as
## _pending_object_removals above - a Dictionary (not a bare String) since
## a move needs BOTH the object id AND its destination, drained by
## drain_pending_object_moves() below. Keys: "id" (String), "cell"
## (Vector3i, tile-square units - see Effect.target_cell's own doc).
var _pending_object_moves: Array[Dictionary] = []

## SPAWN_MONSTERS effects waiting for MissionPlayer to act on them (it has
## the dialogs/scene access, this class doesn't) - see
## drain_pending_monster_spawns(). Keys: "spawn_id" (String), "monsters"
## (Array[String] of monster folders, in spawn-tile order).
var _pending_monster_spawns: Array[Dictionary] = []

## Every live spawned monster (new 2026-09-19), registered by
## register_monster(). Emits monsters_changed on any add/remove so the M
## monster view can rebuild.
var monsters: Array[RuntimeMonster] = []
var _next_monster_number: int = 1
signal monsters_changed


## Registers a newly spawned monster from `template` (its properties are
## inherited) with a random colour chip.
## Rules: a chip colour is never shared by two live monsters of the SAME
## type (two bandits can't both be yellow), and at most
## ComponentInventory.get_color_indicator_count() (4) monsters can hold a
## given colour at once, since that's how many physical chips exist.
## Returns null (and push_warning()s) if no valid colour is left, e.g. a
## fifth bandit or all four yellow chips in use.
func register_monster(template: MonsterTemplate) -> RuntimeMonster:
	var folder := template.folder
	var candidates: Array[int] = []
	for chip in MonsterChip.Chip.values():
		var used_total := 0
		var used_by_type := false
		for monster in monsters:
			if monster.chip == chip:
				used_total += 1
				if monster.folder == folder:
					used_by_type = true
		var limit := ComponentInventory.get_color_indicator_count(MonsterChip.key(chip))
		if used_by_type or (limit >= 0 and used_total >= limit):
			continue
		candidates.append(chip)
	if candidates.is_empty():
		push_warning("No colour chip available for a new '%s' - not registered" % folder)
		return null
	var created := RuntimeMonster.new()
	created.id = "monster_%d" % _next_monster_number
	_next_monster_number += 1
	created.folder = folder
	created.custom_name = template.custom_name
	created.hitpoints = template.hitpoints
	created.level = template.level
	created.defense = template.defense
	created.weaknesses = template.weaknesses.duplicate()
	created.resistances = template.resistances.duplicate()
	created.immunities = template.immunities.duplicate()
	created.chip = candidates[randi() % candidates.size()]
	monsters.append(created)
	monsters_changed.emit()
	return created


## Resolves one attack on `monster` with `weapon` (null = Weapon.placeholder()).
## The table reports the final `successes` (dice, abilities and potions all
## happen outside the engine). For each of the weapon's damage types: a
## monster weakness to it adds +1 to the weapon's damage, a resistance
## subtracts 1 (never below 0), and ANY immunity match makes the attack do 0.
## Damage = successes x adjusted weapon damage; unless immune the engine then
## rolls 0..monster.defense and subtracts it (never below 0), and the result
## comes off the monster's hitpoints. A monster at 0 hitpoints or less is
## defeated and released (chip freed, removed from the M view). Returns the
## breakdown for display: {weapon_name, base_damage, weakness_bonus,
## resistance_penalty, immune, weapon_damage, successes, damage, defense_roll,
## dealt, hitpoints, defeated}.
func resolve_attack(monster: RuntimeMonster, successes: int, weapon: Weapon = null) -> Dictionary:
	if weapon == null:
		weapon = Weapon.placeholder()
	var bonus := 0
	var penalty := 0
	var immune := false
	for kind in weapon.damage_types:
		if monster.weaknesses.has(kind):
			bonus += 1
		if monster.resistances.has(kind):
			penalty += 1
		if monster.immunities.has(kind):
			immune = true
	var weapon_damage := maxi(weapon.damage + bonus - penalty, 0)
	var damage := 0 if immune else successes * weapon_damage
	var defense_roll := 0 if immune else randi_range(0, maxi(monster.defense, 0))
	var dealt := maxi(damage - defense_roll, 0)
	monster.hitpoints -= dealt
	var defeated := monster.hitpoints <= 0
	var result := {
		"weapon_name": weapon.weapon_name, "base_damage": weapon.damage,
		"weakness_bonus": bonus, "resistance_penalty": penalty, "immune": immune,
		"weapon_damage": weapon_damage, "successes": successes, "damage": damage,
		"defense_roll": defense_roll, "dealt": dealt, "hitpoints": monster.hitpoints, "defeated": defeated,
	}
	if defeated:
		release_monster(monster.id)
	else:
		monsters_changed.emit()  # the M view shows HP
	return result


## Removes a monster from the registry, freeing its colour chip (called by
## resolve_attack() when a monster is defeated; the release half of
## register_monster()).
func release_monster(monster_id: String) -> void:
	for i in monsters.size():
		if monsters[i].id == monster_id:
			monsters.remove_at(i)
			monsters_changed.emit()
			return


## `hero_name` (new 2026-09-14, optional) is the acting player, threaded
## through purely so a RUN_TEST effect's dialog prompt can address them by
## name - blank when there's no acting player in context (e.g. a
## checkpoint-driven MissionTrigger's effects). See this class's own doc
## for why this function (and everything that calls it) is now a
## coroutine. SHOW_MESSAGE (new 2026-09-17) reuses the same `dialog`
## reference RUN_TEST already established - `await dialog.ask_ok(...)` a
## plain narrative popup with no branching, no variable write of its own.
## The text goes through `_format_message()` first (new 2026-09-19) to
## substitute any `$1`/`$2`/... placeholders against `effect.message_variables`
## - see that method's own doc for the full mechanism.
##
## `effect.conditions` (new 2026-09-18) is checked FIRST, before any
## type branch below - an Effect whose own conditions don't currently
## hold is skipped entirely, same evaluate_conditions() (implicit AND,
## empty = always true) every other conditions list in this class already
## uses. Checked here rather than per-branch so it applies uniformly to
## all seven Effect.Type kinds for free, not just SET_VARIABLE.
func apply_effect(effect: Effect, hero_name: String = "") -> void:
	if not evaluate_conditions(effect.conditions):
		return
	if effect.type == Effect.Type.SHOW_STAGE:
		if effect.target_group_id != "":
			_pending_stage_reveals.append(effect.target_group_id)
		return
	if effect.type == Effect.Type.REMOVE_OBJECT:
		if effect.target_object_id != "":
			_pending_object_removals.append(effect.target_object_id)
		return
	if effect.type == Effect.Type.MOVE_OBJECT:
		if effect.target_object_id != "":
			_pending_object_moves.append({"id": effect.target_object_id, "cell": effect.target_cell})
		return
	if effect.type == Effect.Type.MATH:
		_apply_math(effect)
		return
	if effect.type == Effect.Type.RUN_TEST:
		await _run_test(effect, hero_name)
		return
	if effect.type == Effect.Type.SPAWN_MONSTERS:
		_pending_monster_spawns.append({"spawn_id": effect.target_object_id, "monsters": effect.spawn_monsters.duplicate()})
		return
	if effect.type == Effect.Type.SHOW_MESSAGE:
		if dialog == null:
			push_warning("SHOW_MESSAGE effect fired but MissionRuntime.dialog isn't wired - skipped")
			return
		await dialog.ask_ok(_format_message(effect.message, effect.message_variables))
		return
	if BUILTIN_TYPES.has(effect.variable_name):
		push_warning("Effect cannot write built-in variable '%s' - skipped" % effect.variable_name)
		return
	var declared: int = _declared_type(effect.variable_name)
	if declared == -1:
		push_warning("Effect references unknown variable '%s' - skipped" % effect.variable_name)
		return
	var coerced: Variant = _coerce(effect.value, declared as MissionVariable.Type)
	if typeof(coerced) == TYPE_NIL:
		push_warning("Effect value for '%s' doesn't match its declared type - skipped" % effect.variable_name)
		return
	_variables[effect.variable_name] = coerced
	print("MissionRuntime.apply_effect: '%s' = %s" % [effect.variable_name, coerced])


func apply_effects(effects: Array[Effect], hero_name: String = "") -> void:
	for effect in effects:
		await apply_effect(effect, hero_name)


## Effect.Type.SHOW_MESSAGE's own text-substitution mechanism (new
## 2026-09-19) - requested directly: "in our shown message dialog text we
## might want to reference variables... the text can contain $1, $2 etc
## that represent entries in the list... at runtime these must be
## replaced with the actual value of that variable." `template` is
## `effect.message`, `variable_names` is `effect.message_variables` (1st
## entry = $1, 2nd = $2, ...). Uses a real RegEx (`\$(\d+)`, matching ANY
## run of digits, not just single-digit `$1`-`$9`) rather than naive
## string replacement specifically so `$10`/`$11`/... substitute correctly
## instead of `$1` inside `$10` matching first and corrupting the digit
## that follows it. An index with no corresponding list entry (typo, or an
## entry removed after the text was written) is replaced with NOTHING (an
## empty string - requested directly: "if it references a position
## outside the list, just show nothing") and `push_warning()`s, so the
## authoring mistake is still visible to whoever's testing the mission,
## just not to the table. Each substituted variable's value goes through
## plain `str()` - a bool/int/float/string all read naturally in
## narrative text with no special-casing needed.
func _format_message(template: String, variable_names: Array[String]) -> String:
	var regex := RegEx.new()
	regex.compile("\\$(\\d+)")

	var result := ""
	var last_end := 0
	for found in regex.search_all(template):
		result += template.substr(last_end, found.get_start() - last_end)
		var index: int = int(found.get_string(1)) - 1  # $1 -> list index 0
		if index >= 0 and index < variable_names.size():
			result += str(_variables.get(variable_names[index], "?"))
		else:
			push_warning("SHOW_MESSAGE references %s, but only %d variable(s) are listed - showing nothing" % [found.get_string(), variable_names.size()])
		last_end = found.get_end()
	result += template.substr(last_end)
	return result


## Asks dialog.ask_count() for a raw successes roll - the required number
## is NEVER included in the prompt ("how many successes?", not "do you
## need 6?"), so the table can't game a retry with foreknowledge (see
## Effect.required_successes' own doc). Then, independently: (a) if
## accumulate_variable_name is set, adds the raw count to that declared
## INT variable via _accumulate() below (case 2 - repeated tests toward a
## larger cumulative total); (b) if pass_effects or fail_effects is
## non-empty, compares the roll against required_successes and applies
## whichever branch's effects, recursively through apply_effects() (a
## branch can itself contain another RUN_TEST). A Test with both
## pass_effects and fail_effects empty skips the comparison entirely -
## purely accumulate-only.
func _run_test(effect: Effect, hero_name: String) -> void:
	if dialog == null:
		push_warning("RUN_TEST effect fired but MissionRuntime.dialog isn't wired - skipped")
		return
	var attribute_label := PlayerAttribute.attribute_name(effect.test_attribute)
	var prompt := "%s: perform a %s test - how many successes?" % [hero_name, attribute_label] if hero_name != "" else "Perform a %s test - how many successes?" % attribute_label
	var successes: int = await dialog.ask_count(prompt, 0, 99)
	print("MissionRuntime._run_test: %s -> %d successes" % [attribute_label, successes])

	if effect.accumulate_variable_name != "":
		_accumulate(effect.accumulate_variable_name, successes)

	if not effect.pass_effects.is_empty() or not effect.fail_effects.is_empty():
		if successes >= effect.required_successes:
			await apply_effects(effect.pass_effects, hero_name)
		else:
			await apply_effects(effect.fail_effects, hero_name)


## Adds `delta` to a declared INT variable - the operation a cumulative
## test needs that SET_VARIABLE can't do (it only ever overwrites). Same
## warn-and-skip discipline as apply_effect()'s SET_VARIABLE body: rejects
## a built-in, an undeclared name, or a variable not declared INT.
func _accumulate(variable_name: String, delta: int) -> void:
	if BUILTIN_TYPES.has(variable_name):
		push_warning("Test result cannot accumulate into built-in variable '%s' - skipped" % variable_name)
		return
	var declared: int = _declared_type(variable_name)
	if declared != MissionVariable.Type.INT:
		push_warning("Test result can only accumulate into an INT variable - '%s' isn't one - skipped" % variable_name)
		return
	var current: Variant = _variables.get(variable_name, 0)
	_variables[variable_name] = (current if typeof(current) == TYPE_INT else 0) + delta
	print("MissionRuntime._accumulate: '%s' += %d -> %s" % [variable_name, delta, _variables[variable_name]])


## Effect.Type.MATH's own mechanism - resolves both operands (see
## _resolve_math_operand() below), applies effect.math_operator, and
## writes the result to effect.variable_name through the SAME
## declared-type coercion discipline apply_effect()'s own SET_VARIABLE
## body uses (a plain int result naturally coerces into an INT target
## exactly, or a FLOAT target via _coerce()'s existing int-widening rule -
## see that method's own doc). Bails (push_warning() + skip, never a
## partial write) on either operand failing to resolve, a division/modulo
## by zero, an undeclared/built-in target, or a target whose declared type
## can't accept an int.
func _apply_math(effect: Effect) -> void:
	var a: Variant = _resolve_math_operand(effect.math_operand_a_is_variable, effect.math_operand_a_literal, effect.math_operand_a_variable)
	if typeof(a) == TYPE_NIL:
		return
	var b: Variant = _resolve_math_operand(effect.math_operand_b_is_variable, effect.math_operand_b_literal, effect.math_operand_b_variable)
	if typeof(b) == TYPE_NIL:
		return

	var result: int
	match effect.math_operator:
		Effect.MathOperator.ADD:
			result = a + b
		Effect.MathOperator.SUBTRACT:
			result = a - b
		Effect.MathOperator.MULTIPLY:
			result = a * b
		Effect.MathOperator.DIVIDE:
			if b == 0:
				push_warning("Math effect: division by zero writing '%s' - skipped" % effect.variable_name)
				return
			result = a / b
		Effect.MathOperator.MODULO:
			if b == 0:
				push_warning("Math effect: modulo by zero writing '%s' - skipped" % effect.variable_name)
				return
			result = a % b
		_:
			push_warning("Math effect has an unrecognized operator - skipped")
			return

	if BUILTIN_TYPES.has(effect.variable_name):
		push_warning("Math effect cannot write built-in variable '%s' - skipped" % effect.variable_name)
		return
	var declared: int = _declared_type(effect.variable_name)
	if declared == -1:
		push_warning("Math effect references unknown variable '%s' - skipped" % effect.variable_name)
		return
	var coerced: Variant = _coerce(result, declared as MissionVariable.Type)
	if typeof(coerced) == TYPE_NIL:
		push_warning("Math effect result for '%s' doesn't match its declared type - skipped" % effect.variable_name)
		return
	_variables[effect.variable_name] = coerced
	print("MissionRuntime._apply_math: '%s' = %s" % [effect.variable_name, coerced])


## Resolves one MATH operand - `literal_value` verbatim if `is_variable`
## is false, or (if true) a declared INT variable's CURRENT value from
## `variable_name`. Returns null (TYPE_NIL) on failure - an undeclared
## name, or one declared but not INT - so _apply_math() can bail the whole
## effect the same "skip, never half-apply" way every other invalid-effect
## path in this class already does (same null-means-failure,
## typeof()==TYPE_NIL-checked-by-the-caller convention _coerce() itself
## uses - see that method's own doc for why a genuine 0 result must never
## be confused with failure here). Builtins (round_number/player_count)
## are valid operand sources - only WRITING one is disallowed elsewhere in
## this class, reading is fine.
func _resolve_math_operand(is_variable: bool, literal_value: int, variable_name: String) -> Variant:
	if not is_variable:
		return literal_value
	var declared: int = _declared_type(variable_name)
	if declared != MissionVariable.Type.INT:
		push_warning("Math effect operand '%s' isn't a declared INT variable - skipped" % variable_name)
		return null
	var current: Variant = _variables.get(variable_name, 0)
	return current if typeof(current) == TYPE_INT else 0


## Clears and returns whatever Show Stage targets queued up since the last
## drain - called by MissionPlayer right after anything that can apply
## effects (a checkpoint transition, a fired PropAction), so it can await
## show_stage() for each.
func drain_pending_stage_reveals() -> Array[String]:
	var reveals := _pending_stage_reveals
	_pending_stage_reveals = []
	return reveals


## Clears and returns whatever Remove Object targets queued up since the
## last drain - called by MissionPlayer right alongside
## drain_pending_stage_reveals(), so it can call
## LayeredMap.remove_node() for each.
func drain_pending_object_removals() -> Array[String]:
	var removals := _pending_object_removals
	_pending_object_removals = []
	return removals


## Clears and returns the SPAWN_MONSTERS effects queued since the last drain (new 2026-09-19) - MissionPlayer runs each via _run_monster_spawn().
func drain_pending_monster_spawns() -> Array[Dictionary]:
	var spawns := _pending_monster_spawns
	_pending_monster_spawns = []
	return spawns


## Clears and returns whatever Move Object targets queued up since the
## last drain - same call site/reasoning as the other two drains above.
## Each entry is {"id": String, "cell": Vector3i} - `cell` is still in
## AUTHORED tile-square units at this point (see Effect.target_cell's own
## doc); MissionPlayer converts to a real fine origin_cell via
## FootprintRegistry.tile_square_to_fine_far_corner() right before calling
## LayeredMap.move_node(), so this class never needs to know that
## conversion exists.
func drain_pending_object_moves() -> Array[Dictionary]:
	var moves := _pending_object_moves
	_pending_object_moves = []
	return moves


## Fires every checkpoint-driven trigger due at `checkpoint`, then checks
## the currently-active objective node(s) - returns the first that just
## resolved as a leaf (or null). Triggers fire before objectives are
## checked so an objective can depend on a variable a trigger just wrote.
## No hero_name to thread through - a checkpoint transition has no acting
## player in context (unlike fire_prop_action() below).
func evaluate_checkpoint(checkpoint: RoundCheckpoint.Checkpoint) -> MissionObjective:
	var due: Array[MissionTrigger] = []
	for trigger in mission.triggers:
		if trigger.checkpoint == checkpoint:
			due.append(trigger)
	await _fire_triggers(due)
	return await _check_current_objectives()


## Fires every event-driven trigger watching `event_id`, then checks the
## currently-active objective node(s) - returns the first that just
## resolved as a leaf (or null). Objectives are re-checked on events too
## (not just checkpoints) since something like "found the item" is
## reported live via a PropAction, not observable only at the next
## checkpoint boundary. `hero_name` (new 2026-09-14) just passes through to
## apply_effect() for a RUN_TEST's dialog prompt - see that function's own
## doc.
func fire_event(event_id: String, hero_name: String = "") -> MissionObjective:
	var due: Array[MissionTrigger] = []
	for trigger in mission.triggers:
		if trigger.event_id == event_id:
			due.append(trigger)
	await _fire_triggers(due, hero_name)
	return await _check_current_objectives(hero_name)


## Applies a PropAction's own effects, then fires the event-driven half -
## both halves fire per PropAction's own doc ("firing one applies its
## effects immediately - the event-driven half of the trigger system").
## Returns the same nullable MissionObjective fire_event() does. `hero_name`
## (new 2026-09-14, required - its one caller, PlayerInteractionController.
## _offer_actions(), always has one) is the player who performed the
## action, threaded through purely so a RUN_TEST effect anywhere downstream
## of this action can address them by name in its dialog prompt.
func fire_prop_action(action: PropAction, hero_name: String) -> MissionObjective:
	print("MissionRuntime.fire_prop_action: '%s' (action_id='%s', %d effect(s))" % [action.description, action.action_id, action.effects.size()])
	await apply_effects(action.effects, hero_name)
	if action.single_shot:
		# Mutating the loaded PropAction resource instance directly is
		# safe, same reasoning as MissionTrigger.already_fired -
		# MissionIO.load_mission() already uses CACHE_MODE_IGNORE for a
		# fresh instance never saved back.
		action.already_used = true
	return await fire_event(action.action_id, hero_name)


## Sorted by priority ascending, then fired SEQUENTIALLY rather than as a
## pre-filtered batch: each trigger's conditions are re-evaluated against
## the CURRENT live variable state right before it fires, not a snapshot
## taken before the loop. This is what MissionTrigger.priority's own doc
## comment is for - "matters when one trigger's effect writes a variable
## another trigger's condition depends on" only makes sense if effects from
## an earlier trigger in this same batch are visible to a later one.
func _fire_triggers(candidates: Array[MissionTrigger], hero_name: String = "") -> void:
	var sorted: Array[MissionTrigger] = candidates.duplicate()
	sorted.sort_custom(func(a, b): return a.priority < b.priority)
	for trigger in sorted:
		if trigger.one_shot and trigger.already_fired:
			continue
		if not evaluate_conditions(trigger.conditions):
			continue
		await apply_effects(trigger.effects, hero_name)
		trigger.already_fired = true


## Evaluates every currently-watched objective group. For each group
## (mutually exclusive candidates): every candidate's optional_objectives
## are checked FIRST, each tick, for every candidate still in the group -
## not just the eventual winner - so a side objective stays completable
## for as long as its node is still a live possibility, even if a
## different sibling ends up being the one that actually resolves. THEN
## each candidate's own conditions are checked in priority order; the
## first (lowest-priority-number) one whose conditions hold wins - its
## effects apply, and the WHOLE group is replaced by its children (a
## fresh group of new candidates), discarding the other siblings entirely
## with no per-node "closed" bookkeeping needed. A winning leaf (no
## children) is returned immediately - the caller ends the game with its
## outcome. Deliberately does NOT recurse into a freshly-installed group
## the same tick - new candidates get their first real evaluation on the
## NEXT call, keeping this non-recursive and incidentally making an
## accidentally-authored cycle harmless (see _warn_on_cycles()).
func _check_current_objectives(hero_name: String = "") -> MissionObjective:
	for group_index in _current_groups.size():
		var group: Array = _current_groups[group_index]
		var sorted: Array = group.duplicate()
		sorted.sort_custom(func(a, b): return a.priority < b.priority)

		for node in sorted:
			for optional in node.optional_objectives:
				if not optional.already_achieved and evaluate_conditions(optional.conditions):
					await apply_effects(optional.effects, hero_name)
					optional.already_achieved = true

		for node in sorted:
			if node.already_achieved or not evaluate_conditions(node.conditions):
				continue
			node.already_achieved = true
			await apply_effects(node.effects, hero_name)
			if node.children.is_empty():
				return node
			_current_groups[group_index] = node.children.duplicate()
			break
	return null


## Every currently-active objective node's own description, one per
## candidate across every watched group (see _current_groups above),
## skipping blank ones - what MissionPlayer shows the table so it never
## reveals a DAG branch/leaf that hasn't actually become reachable yet.
## Showing every ROOT's description unconditionally (what MissionPlayer
## used to do, reading mission.objectives directly) spoiled branches
## nobody has reached - this reads the runtime's own traversal frontier
## instead, which is already exactly the "what's live right now" set.
func get_current_objective_descriptions() -> Array[String]:
	var descriptions: Array[String] = []
	for group in _current_groups:
		for node in group:
			if node.description != "":
				descriptions.append(node.description)
	return descriptions


## Load-time safety net for an accidentally-authored cycle - a DFS from
## each root, push_warning() per back-edge found. Purely informational:
## nothing is stripped, because _check_current_objectives()'s "don't
## recurse into a freshly-installed group the same tick" rule already
## means a cycle can't infinite-loop at runtime - at worst it loops the
## player back through an earlier group on some LATER tick, which might
## even be an intentional "retry this chapter" design, not necessarily a
## mistake.
func _warn_on_cycles() -> void:
	for root in mission.objectives:
		_walk_for_cycles(root, [])


func _walk_for_cycles(node: MissionObjective, path: Array[MissionObjective]) -> void:
	if path.has(node):
		push_warning("MissionObjective '%s' is part of a cycle in the objectives DAG" % node.id)
		return
	var extended: Array[MissionObjective] = path.duplicate()
	extended.append(node)
	for child in node.children:
		_walk_for_cycles(child, extended)


## MissionVariable.Type, or -1 if `name` isn't a declared custom variable
## or a runtime built-in. Returns a plain `int` with a sentinel OUTSIDE the
## valid 0-3 enum range, not `Variant`/`null` - `Type.BOOL` is 0, and
## `declared == null` would need `0 == null` to reliably evaluate false
## for a bare "not found" check to be safe. round_number/player_count are
## both Type.INT (1), so this exact ambiguity was never actually exercised
## until a real custom BOOL variable was declared for the first time
## 2026-09-14 - fixed defensively to an unambiguous int sentinel rather
## than confirming whether `0 == null` was ever actually the problem.
func _declared_type(name: String) -> int:
	if BUILTIN_TYPES.has(name):
		return BUILTIN_TYPES[name] as int  # BUILTIN_TYPES is an untyped Dictionary literal - .[] returns Variant, needs an explicit cast to satisfy the -> int return type
	for variable in mission.custom_variables:
		if variable.name == name:
			return variable.type
	return -1


## Returns `value` (coerced if needed) if it matches `type`, else null.
## BOOL/INT/STRING require an exact typeof() match; FLOAT additionally
## accepts TYPE_INT and coerces via float(value) - typing "5" instead of
## "5.0" into a float field's Inspector value is the single most common
## authoring mistake, and would otherwise spuriously warn every time. A
## genuinely null/unset value falls through this same path (typeof(null) ==
## TYPE_NIL never matches any declared type) and is correctly treated as a
## mismatch - no special-casing needed.
func _coerce(value: Variant, type: MissionVariable.Type) -> Variant:
	match type:
		MissionVariable.Type.BOOL:
			return value if typeof(value) == TYPE_BOOL else null
		MissionVariable.Type.INT:
			return value if typeof(value) == TYPE_INT else null
		MissionVariable.Type.FLOAT:
			if typeof(value) == TYPE_FLOAT:
				return value
			if typeof(value) == TYPE_INT:
				return float(value)
			return null
		MissionVariable.Type.STRING:
			return value if typeof(value) == TYPE_STRING else null
	return null


func _zero_value(type: MissionVariable.Type) -> Variant:
	match type:
		MissionVariable.Type.BOOL:
			return false
		MissionVariable.Type.INT:
			return 0
		MissionVariable.Type.FLOAT:
			return 0.0
		MissionVariable.Type.STRING:
			return ""
	return null
