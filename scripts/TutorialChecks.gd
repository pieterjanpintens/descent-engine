class_name TutorialChecks
extends RefCounted

## The "done when" tests of the tutorial steps (data/tutorials/*.json: "done": {"check": "<name>", ...}). Every check looks at the
## mission as it is NOW (or at what the user did since the step began), never at one particular click - so steps can be done in any
## order, an undo takes a step back, and a step that is already true shows as done at once.

const TOKENS := ["exploration", "interact", "umbra"]
## The two variables the tutorial mission uses: the monster was defeated, the lair was looted.
const MONSTER_DEAD := "monster_dead"
const CHEST_LOOTED := "chest_looted"
## The variable tutorial 2 (the fork) uses: has the Lair encounter been started by either route?
const ENCOUNTER_STARTED := "encounter_started"


static func check(spec: Dictionary, r: TutorialRunner) -> bool:
	var mission := r.layered_map.mission
	if mission == null:
		return false
	match str(spec.get("check", "")):
		"camera_turned":
			return r.camera_turned_degrees() >= 8.0
		"camera_moved":
			return r.camera_moved_distance() >= 3.0
		"stage_ready":
			return not mission.groups.is_empty() and r.controller.working_group_id != ""
		"floors":
			return _floors(spec, mission)
		"event":
			return r.event_count(str(spec["name"])) >= int(spec.get("n", 1))
		"saved":
			return r.save_load.current_path != ""
		"props":
			return placed_props(mission).size() >= int(spec.get("n", 1))
		"named_prop":
			for entry in placed_props(mission):
				if entry.reference_name != "":
					return true
			return false
		"starts":
			return mission.all_start_cells().size() >= int(spec.get("n", 1))
		"players_fit":
			return not mission.all_start_cells().is_empty() and mission.max_players <= mission.all_start_cells().size()
		"template":
			return not MonsterArchetypeLibrary.names_of_kind(MonsterArchetype.Kind.BASE).is_empty()
		"monster_spawn":
			for spawn in mission.monster_spawns:
				if spawn.cells.size() >= int(spec.get("n", 1)):
					return true
			return false
		"los_blocker":
			for blocker in mission.los_blockers:
				if blocker.cells.size() >= int(spec.get("n", 1)):
					return true
			return false
		"variables":
			return _has_bool_variable(mission, MONSTER_DEAD) and _has_bool_variable(mission, CHEST_LOOTED)
		"chest_action":
			return chest_action_sets(mission, CHEST_LOOTED)
		"spawn_trigger":
			return not spawn_effects(mission).is_empty()
		"defeat_effect":
			for effect in spawn_effects(mission):
				for monster in effect.spawn_monsters:
					if sets_variable(monster.defeat_effects, MONSTER_DEAD):
						return true
			return false
		"objectives":
			return objective_chain_ok(mission)
		# ---- tutorial 2: the fork ----
		"ready":
			return mission.all_start_cells().size() >= 1 and _floors({"n": 3, "in_stage": true}, mission)
		"hidden_stage":
			return hidden_stage(mission) != null
		"lair_floor":
			return not stage_floors(mission, hidden_stage(mission)).is_empty()
		"fork_floors":
			return fork_floors_ok(mission)
		"door":
			return door(mission) != null and door(mission).reference_name != ""
		"encounter_variable":
			return _has_bool_variable(mission, ENCOUNTER_STARTED)
		"lair_spawn":
			return lair_spawn(mission) != null
		"door_action":
			return door_action_basics(mission)
		"door_stage_effects":
			return door_stage_effects(mission)
		"door_spawn":
			return door_spawn_ok(mission)
		"spawn_guard":
			return spawn_guard_ok(mission)
		"monster_group":
			return monster_group_ok(mission)
		"token":
			return token(mission) != null and token(mission).reference_name != ""
		"token_action":
			return token_action_ok(mission)
		"token_effects":
			return token_effects_ok(mission)
		"door_wake":
			return has_effect_type(door_effects(mission), Effect.Type.WAKE_MONSTERS)
		"restless":
			return restless_trigger_ok(mission)
		"reinforcements":
			return reinforcements_ok(mission)
		# ---- tutorial 3: macros ----
		"fork_ready":
			return lair_spawn(mission) != null and door_spawn(mission) != null
		"lair_chest":
			return lair_chest(mission) != null
		"chest_macro":
			return has_macro(lair_chest(mission), "treasure_chest")
		"reinforce_macro":
			return cave_spawn_with_macro(mission) != null
		"no_errors":
			return MapPlanValidator.validate_mission(mission)["errors"].is_empty()
	push_warning("TutorialChecks: unknown check '%s'" % spec.get("check", ""))
	return false


static func _has_bool_variable(mission: MissionData, variable_name: String) -> bool:
	for variable in mission.custom_variables:
		if variable.name == variable_name and variable.type == MissionVariable.Type.BOOL:
			return true
	return false


## True when some effect in the list sets `variable_name` to true.
static func sets_variable(effects: Array[Effect], variable_name: String) -> bool:
	for effect in effects:
		if effect.type == Effect.Type.SET_VARIABLE and effect.variable_name == variable_name and effect.value == true:
			return true
	return false


## True when an action of a prop in the mission sets `variable_name` to true (the chest's "Search").
static func chest_action_sets(mission: MissionData, variable_name: String) -> bool:
	for entry in mission.interactables:
		for action in entry.actions:
			if sets_variable(action.effects, variable_name):
				return true
	return false


## Every Spawn Monsters effect (with at least one monster) of the mission's triggers.
static func spawn_effects(mission: MissionData) -> Array[Effect]:
	var found: Array[Effect] = []
	for trigger in mission.triggers:
		for effect in trigger.effects:
			if effect.type == Effect.Type.SPAWN_MONSTERS and effect.target_object_id != "" and not effect.spawn_monsters.is_empty():
				found.append(effect)
	return found


## A root objective that waits for the monster to be dead, leading to a winning objective that waits for the lair to be looted.
static func objective_chain_ok(mission: MissionData) -> bool:
	for root in mission.objectives:
		if not _waits_for(root, MONSTER_DEAD):
			continue
		for child in root.children:
			if child.children.is_empty() and child.outcome == MissionObjective.Outcome.WIN and _waits_for(child, CHEST_LOOTED):
				return true
	return false


static func _waits_for(objective: MissionObjective, variable_name: String) -> bool:
	for condition in objective.conditions:
		if condition.variable_name == variable_name and condition.operator == Condition.Operator.EQUALS and condition.value == true:
			return true
	return false


## The props that are not event tokens.
static func placed_props(mission: MissionData) -> Array[InteractableEntry]:
	var found: Array[InteractableEntry] = []
	for entry in mission.interactables:
		if not TOKENS.has(entry.mesh_item_name):
			found.append(entry)
	return found


static func _floors(spec: Dictionary, mission: MissionData) -> bool:
	var placements: Array[TilePlacement] = []
	for placement in mission.floor_placements:
		if bool(spec.get("in_stage", false)) and placement.parent_id == "":
			continue
		placements.append(placement)
	if placements.size() < int(spec.get("n", 1)):
		return false
	if bool(spec.get("connected", false)):
		return connected_components(mission, placements) == 1
	return true


## How many separate groups the given floor tiles form (tiles that share an edge belong together).
static func connected_components(mission: MissionData, placements: Array[TilePlacement]) -> int:
	var wanted := {}
	for placement in placements:
		wanted[placement.origin_cell] = true
	var parent := {}
	for origin in wanted:
		parent[origin] = origin
	for cell: Vector3i in mission.floor_occupied_cells:
		var origin: Vector3i = mission.floor_occupied_cells[cell]
		if not wanted.has(origin):
			continue
		for step in [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
			var neighbour: Vector3i = cell + step
			if not mission.floor_occupied_cells.has(neighbour):
				continue
			var other: Vector3i = mission.floor_occupied_cells[neighbour]
			if other != origin and wanted.has(other):
				_union(parent, origin, other)
	var roots := {}
	for origin in wanted:
		roots[_find(parent, origin)] = true
	return roots.size()


static func _find(parent: Dictionary, node: Vector3i) -> Vector3i:
	while parent[node] != node:
		parent[node] = parent[parent[node]]
		node = parent[node]
	return node


static func _union(parent: Dictionary, a: Vector3i, b: Vector3i) -> void:
	parent[_find(parent, a)] = _find(parent, b)


# ---- Tutorial 2: the fork (a door and a side passage into a shared, hidden Lair) ----

## The first stage that starts hidden (Visible unticked): the Lair.
static func hidden_stage(mission: MissionData) -> MissionGroup:
	for group in mission.groups:
		if not group.visible:
			return group
	return null


static func stage_floors(mission: MissionData, stage: MissionGroup) -> Array[TilePlacement]:
	var found: Array[TilePlacement] = []
	if stage == null:
		return found
	for placement in mission.floor_placements:
		if placement.parent_id == stage.id:
			found.append(placement)
	return found


## All the floor is one connected piece: the Lair's own tiles, plus at least seven tiles in the stages that are shown from the start.
static func fork_floors_ok(mission: MissionData) -> bool:
	var stage := hidden_stage(mission)
	if stage == null or stage_floors(mission, stage).is_empty():
		return false
	var shown := 0
	for placement in mission.floor_placements:
		if placement.parent_id != stage.id:
			shown += 1
	return shown >= 7 and connected_components(mission, mission.floor_placements) == 1


static func door(mission: MissionData) -> InteractableEntry:
	for entry in mission.interactables:
		if entry.mesh_item_name == "gate":
			return entry
	return null


static func token(mission: MissionData) -> InteractableEntry:
	for entry in mission.interactables:
		if TOKENS.has(entry.mesh_item_name):
			return entry
	return null


static func lair_spawn(mission: MissionData) -> MonsterSpawn:
	var stage := hidden_stage(mission)
	if stage == null:
		return null
	for spawn in mission.monster_spawns:
		if spawn.parent_id == stage.id and spawn.cells.size() >= 2:
			return spawn
	return null


static func door_effects(mission: MissionData) -> Array[Effect]:
	var found: Array[Effect] = []
	var entry := door(mission)
	if entry != null:
		for action in entry.actions:
			found.append_array(action.effects)
	return found


static func token_effects(mission: MissionData) -> Array[Effect]:
	var found: Array[Effect] = []
	var entry := token(mission)
	if entry != null:
		for action in entry.actions:
			found.append_array(action.effects)
	return found


static func has_effect_type(effects: Array[Effect], type: Effect.Type) -> bool:
	for effect in effects:
		if effect.type == type:
			return true
	return false


## True when some condition in the list reads the variable.
static func mentions(conditions: Array[Condition], variable_name: String) -> bool:
	for condition in conditions:
		if condition.variable_name == variable_name:
			return true
	return false


static func door_action_basics(mission: MissionData) -> bool:
	var entry := door(mission)
	if entry == null:
		return false
	for action in entry.actions:
		if action.action_name != "" and action.description != "" and action.single_shot:
			return true
	return false


static func door_stage_effects(mission: MissionData) -> bool:
	var stage := hidden_stage(mission)
	if stage == null:
		return false
	var removes_self := false
	var shows_stage := false
	for effect in door_effects(mission):
		if effect.type == Effect.Type.REMOVE_OBJECT and effect.target_object_id == Effect.SELF_ID:
			removes_self = true
		if effect.type == Effect.Type.SHOW_STAGE and effect.target_group_id == stage.id:
			shows_stage = true
	return removes_self and shows_stage


## The door's Spawn Monsters effect (at the Lair's spawn area).
static func door_spawn(mission: MissionData) -> Effect:
	var spawn := lair_spawn(mission)
	if spawn == null:
		return null
	for effect in door_effects(mission):
		if effect.type == Effect.Type.SPAWN_MONSTERS and effect.target_object_id == spawn.id:
			return effect
	return null


## At least two guards, and one of them only appears for a bigger party (a condition on a built-in variable).
static func door_spawn_ok(mission: MissionData) -> bool:
	var effect := door_spawn(mission)
	if effect == null:
		return false
	var monsters := mission.monsters_for(effect)
	if monsters.size() < 2:
		return false
	for monster in monsters:
		if mentions(monster.conditions, "player_count") or mentions(monster.conditions, "difficulty"):
			return true
	return false


static func spawn_guard_ok(mission: MissionData) -> bool:
	var effect := door_spawn(mission)
	if effect == null or not mentions(effect.conditions, ENCOUNTER_STARTED):
		return false
	return sets_variable(door_effects(mission), ENCOUNTER_STARTED)


static func monster_group_ok(mission: MissionData) -> bool:
	var effect := door_spawn(mission)
	if effect == null or effect.spawn_group_id == "":
		return false
	var group := mission.find_monster_group(effect.spawn_group_id)
	return group != null and group.monsters.size() >= 2


static func token_action_ok(mission: MissionData) -> bool:
	var entry := token(mission)
	if entry == null:
		return false
	for action in entry.actions:
		if action.auto_apply and mentions(action.conditions, ENCOUNTER_STARTED):
			return true
	return false


## The token's action reveals the Lair, spawns the SAME group unaware, and records that the encounter started.
static func token_effects_ok(mission: MissionData) -> bool:
	var stage := hidden_stage(mission)
	var spawn := door_spawn(mission)
	if stage == null or spawn == null or spawn.spawn_group_id == "":
		return false
	var shows := false
	var spawns := false
	for effect in token_effects(mission):
		if effect.type == Effect.Type.SHOW_STAGE and effect.target_group_id == stage.id:
			shows = true
		if effect.type == Effect.Type.SPAWN_MONSTERS and effect.spawn_group_id == spawn.spawn_group_id and effect.spawn_unaware:
			spawns = true
	return shows and spawns and sets_variable(token_effects(mission), ENCOUNTER_STARTED)


## The reinforcement trigger of tutorial 2: it fires on every Nth round (a "mod = 0" condition), only while there are few monsters on the board (a condition on
## monsters_on_the_map), and its effect is a Spawn Random Monsters at the Lair's spawn area that draws from the guards' group.
static func reinforcements_trigger(mission: MissionData) -> MissionTrigger:
	var spawn := lair_spawn(mission)
	if spawn == null:
		return null
	for trigger in mission.triggers:
		var has_mod := false
		for condition in trigger.conditions:
			if condition.variable_name == "round_number" and condition.operator == Condition.Operator.MULTIPLE_OF:
				has_mod = true
		if not has_mod or not mentions(trigger.conditions, "monsters_on_the_map"):
			continue
		for effect in trigger.effects:
			if effect.type == Effect.Type.SPAWN_RANDOM_MONSTERS and effect.target_object_id == spawn.id and not mission.monsters_for(effect).is_empty():
				return trigger
	return null


## A chest prop inside the hidden Lair stage (tutorial 3).
static func lair_chest(mission: MissionData) -> InteractableEntry:
	var stage := hidden_stage(mission)
	if stage == null:
		return null
	for entry in mission.interactables:
		if entry.mesh_item_name == "chest" and entry.parent_id == stage.id:
			return entry
	return null


static func has_macro(node: OutlineNode, macro_id: String) -> bool:
	if node == null:
		return false
	for applied in node.macros:
		if applied.macro_id == macro_id:
			return true
	return false


## A monster spawn area other than the Lair's that has the Reinforcements macro.
static func cave_spawn_with_macro(mission: MissionData) -> MonsterSpawn:
	var lair := lair_spawn(mission)
	for spawn in mission.monster_spawns:
		if (lair == null or spawn.id != lair.id) and has_macro(spawn, "reinforcements"):
			return spawn
	return null


static func reinforcements_ok(mission: MissionData) -> bool:
	return reinforcements_trigger(mission) != null


static func restless_trigger_ok(mission: MissionData) -> bool:
	for trigger in mission.triggers:
		if mentions(trigger.conditions, "round_number") and has_effect_type(trigger.effects, Effect.Type.WAKE_MONSTERS):
			return true
	return false
