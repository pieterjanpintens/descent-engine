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

const BUILTIN_TYPES := {
	"round_number": MissionVariable.Type.INT,
	"player_count": MissionVariable.Type.INT,
}

var mission: MissionData
var _variables: Dictionary = {}  # String -> Variant

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
		if coerced == null:
			push_warning("MissionVariable '%s' default_value doesn't match its declared type - using a zero value" % variable.name)
			coerced = _zero_value(variable.type)
		_variables[variable.name] = coerced

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
	var declared: Variant = _declared_type(condition.variable_name)
	if declared == null:
		push_warning("Condition references unknown variable '%s'" % condition.variable_name)
		return false
	var target: Variant = _coerce(condition.value, declared)
	if target == null:
		push_warning("Condition value for '%s' doesn't match its declared type" % condition.variable_name)
		return false
	var current: Variant = _variables.get(condition.variable_name)
	match condition.operator:
		Condition.Operator.EQUALS:
			return current == target
		Condition.Operator.NOT_EQUALS:
			return current != target
		Condition.Operator.GREATER:
			return current > target
		Condition.Operator.GREATER_EQUAL:
			return current >= target
		Condition.Operator.LESS:
			return current < target
		Condition.Operator.LESS_EQUAL:
			return current <= target
	return false


## Implicit AND across every entry - an empty array is vacuously true.
func evaluate_conditions(conditions: Array[Condition]) -> bool:
	for condition in conditions:
		if not evaluate_condition(condition):
			return false
	return true


func apply_effect(effect: Effect) -> void:
	if BUILTIN_TYPES.has(effect.variable_name):
		push_warning("Effect cannot write built-in variable '%s' - skipped" % effect.variable_name)
		return
	var declared: Variant = _declared_type(effect.variable_name)
	if declared == null:
		push_warning("Effect references unknown variable '%s' - skipped" % effect.variable_name)
		return
	var coerced: Variant = _coerce(effect.value, declared)
	if coerced == null:
		push_warning("Effect value for '%s' doesn't match its declared type - skipped" % effect.variable_name)
		return
	_variables[effect.variable_name] = coerced


func apply_effects(effects: Array[Effect]) -> void:
	for effect in effects:
		apply_effect(effect)


## Fires every checkpoint-driven trigger due at `checkpoint`, then checks
## the currently-active objective node(s) - returns the first that just
## resolved as a leaf (or null). Triggers fire before objectives are
## checked so an objective can depend on a variable a trigger just wrote.
func evaluate_checkpoint(checkpoint: RoundCheckpoint.Checkpoint) -> MissionObjective:
	var due: Array[MissionTrigger] = []
	for trigger in mission.triggers:
		if trigger.checkpoint == checkpoint:
			due.append(trigger)
	_fire_triggers(due)
	return _check_current_objectives()


## Fires every event-driven trigger watching `event_id`, then checks the
## currently-active objective node(s) - returns the first that just
## resolved as a leaf (or null). Objectives are re-checked on events too
## (not just checkpoints) since something like "found the item" is
## reported live via a PropAction, not observable only at the next
## checkpoint boundary.
func fire_event(event_id: String) -> MissionObjective:
	var due: Array[MissionTrigger] = []
	for trigger in mission.triggers:
		if trigger.event_id == event_id:
			due.append(trigger)
	_fire_triggers(due)
	return _check_current_objectives()


## Applies a PropAction's own effects, then fires the event-driven half -
## both halves fire per PropAction's own doc ("firing one applies its
## effects immediately - the event-driven half of the trigger system").
## Returns the same nullable MissionObjective fire_event() does.
func fire_prop_action(action: PropAction) -> MissionObjective:
	apply_effects(action.effects)
	return fire_event(action.action_id)


## Sorted by priority ascending, then fired SEQUENTIALLY rather than as a
## pre-filtered batch: each trigger's conditions are re-evaluated against
## the CURRENT live variable state right before it fires, not a snapshot
## taken before the loop. This is what MissionTrigger.priority's own doc
## comment is for - "matters when one trigger's effect writes a variable
## another trigger's condition depends on" only makes sense if effects from
## an earlier trigger in this same batch are visible to a later one.
func _fire_triggers(candidates: Array[MissionTrigger]) -> void:
	var sorted: Array[MissionTrigger] = candidates.duplicate()
	sorted.sort_custom(func(a, b): return a.priority < b.priority)
	for trigger in sorted:
		if trigger.one_shot and trigger.already_fired:
			continue
		if not evaluate_conditions(trigger.conditions):
			continue
		apply_effects(trigger.effects)
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
func _check_current_objectives() -> MissionObjective:
	for group_index in _current_groups.size():
		var group: Array = _current_groups[group_index]
		var sorted: Array = group.duplicate()
		sorted.sort_custom(func(a, b): return a.priority < b.priority)

		for node in sorted:
			for optional in node.optional_objectives:
				if not optional.already_achieved and evaluate_conditions(optional.conditions):
					apply_effects(optional.effects)
					optional.already_achieved = true

		for node in sorted:
			if node.already_achieved or not evaluate_conditions(node.conditions):
				continue
			node.already_achieved = true
			apply_effects(node.effects)
			if node.children.is_empty():
				return node
			_current_groups[group_index] = node.children.duplicate()
			break
	return null


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


## MissionVariable.Type, or null if `name` isn't a declared custom variable
## or a runtime built-in.
func _declared_type(name: String) -> Variant:
	if BUILTIN_TYPES.has(name):
		return BUILTIN_TYPES[name]
	for variable in mission.custom_variables:
		if variable.name == name:
			return variable.type
	return null


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
