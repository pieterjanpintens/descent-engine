class_name MissionProgress
extends RefCounted

## What a play has changed in a mission - and how to put that onto a (possibly edited) mission again. Debug snapshots store
## this instead of a copy of the mission (see DebugSession), so loading one shows the mission as it is NOW in the editor,
## with the progress of the snapshot on it.
##
## Progress is everything the Player changes IN the mission resource, keyed by stable ids so it survives edits:
##  - which triggers fired (MissionTrigger.id), which prop actions were used (prop id + action id), which objectives were
##    achieved (MissionObjective.id) - read from the flags the runtime sets, nothing extra is logged for these;
##  - the "world log": groups revealed, pieces removed, pieces moved, in order (MissionRuntime.world_log - written where
##    those happen; a diff against a baseline would go stale once a snapshot was itself started from a snapshot).
## The runtime's own state (variables, monsters, wounds...) is not here, it is in the SaveGame next to this.
##
## Applying never fails as a whole: whatever the edited mission no longer has (a deleted trigger, a removed piece) is
## skipped and described in the report, anything the snapshot doesn't know about keeps its authored default.


## {triggers: {key: label}, actions: {key: label}, objectives: {id: label}, world: [{op, id, ...}]}
static func capture(mission: MissionData, world_log: Array[Dictionary]) -> Dictionary:
	var triggers := {}
	for i in mission.triggers.size():
		var trigger: MissionTrigger = mission.triggers[i]
		if trigger.already_fired:
			triggers[_trigger_key(trigger, i)] = _trigger_label(trigger)
	var actions := {}
	for entry in mission.interactables:
		for action in entry.actions:
			if action.already_used:
				actions[_action_key(entry, action)] = "action '%s' of %s" % [action.action_id, _node_label(entry)]
	var objectives := {}
	for objective in all_objectives(mission):
		if objective.already_achieved and objective.id != "":
			objectives[objective.id] = _objective_label(objective)
	return {"triggers": triggers, "actions": actions, "objectives": objectives, "world": world_log.duplicate(true)}


## A fresh outcome: {report: Array[String], world: Array[Dictionary]} - the apply functions fill it with what could not be
## matched and with the world entries that really applied (those continue as the new world log).
static func new_outcome() -> Dictionary:
	var report: Array[String] = []
	var world: Array[Dictionary] = []
	return {"report": report, "world": world}


## The flags and group reveals - before the mission is painted.
static func apply_before_paint(mission: MissionData, progress: Dictionary, outcome: Dictionary) -> void:
	var by_trigger := {}
	for i in mission.triggers.size():
		by_trigger[_trigger_key(mission.triggers[i], i)] = mission.triggers[i]
	for key: String in progress.get("triggers", {}):
		if by_trigger.has(key):
			(by_trigger[key] as MissionTrigger).already_fired = true
		else:
			_note(outcome, "%s fired before, but it no longer exists." % progress["triggers"][key])
	var by_action := {}
	for entry in mission.interactables:
		for action in entry.actions:
			by_action[_action_key(entry, action)] = action
	for key: String in progress.get("actions", {}):
		if by_action.has(key):
			(by_action[key] as PropAction).already_used = true
		else:
			_note(outcome, "The %s was used before, but it no longer exists." % progress["actions"][key])
	var by_objective := {}
	for objective in all_objectives(mission):
		by_objective[objective.id] = objective
	for id: String in progress.get("objectives", {}):
		if by_objective.has(id):
			(by_objective[id] as MissionObjective).already_achieved = true
		else:
			_note(outcome, "Objective '%s' was achieved before, but it no longer exists." % progress["objectives"][id])
	for op: Dictionary in progress.get("world", []):
		var visibility_op := str(op.get("op", ""))
		if visibility_op == "show" or visibility_op == "hide":
			var changed_node := mission.find_node_by_id(str(op["id"]))
			if changed_node == null:
				_note(outcome, "'%s' was %s before, but it no longer exists." % [str(op.get("name", op["id"])), "shown" if visibility_op == "show" else "hidden"])
			else:
				changed_node.visible = visibility_op == "show"
				outcome["world"].append(op)
			continue
		if str(op.get("op", "")) != "reveal":
			continue
		var group := _find_group(mission, str(op["id"]))
		if group == null:
			_note(outcome, "Group '%s' was revealed before, but it no longer exists." % str(op.get("name", op["id"])))
			continue
		group.visible = true
		outcome["world"].append(op)


## Removed and moved pieces - after the mission is painted (they go through the map, which keeps grid and data together).
static func apply_after_paint(mission: MissionData, layered_map: LayeredMap, progress: Dictionary, outcome: Dictionary) -> void:
	for op: Dictionary in progress.get("world", []):
		var kind := str(op.get("op", ""))
		if kind != "remove" and kind != "move":
			continue
		var label := str(op.get("name", op["id"]))
		if mission.find_node_by_id(str(op["id"])) == null:
			_note(outcome, "'%s' was %s before, but it no longer exists." % [label, "removed" if kind == "remove" else "moved"])
			continue
		if kind == "remove":
			layered_map.remove_node(str(op["id"]))
			outcome["world"].append(op)
		elif layered_map.move_node(str(op["id"]), op["cell"]):
			outcome["world"].append(op)
		else:
			_note(outcome, "'%s' could not be moved to where it was (the place is taken now)." % label)


static func all_objectives(mission: MissionData) -> Array[MissionObjective]:
	var result: Array[MissionObjective] = []
	var visited := {}
	var queue: Array[MissionObjective] = mission.objectives.duplicate()
	while not queue.is_empty():
		var node: MissionObjective = queue.pop_front()
		if visited.has(node):
			continue
		visited[node] = true
		result.append(node)
		queue.append_array(node.children)
		queue.append_array(node.optional_objectives)
	return result


## Entries for MissionRuntime.world_log (written by MissionPlayer where a group is revealed, a piece removed or moved).
static func reveal_entry(group: MissionGroup) -> Dictionary:
	return {"op": "reveal", "id": group.id, "name": group.reference_name if group.reference_name != "" else "a group"}


static func show_entry(node: OutlineNode) -> Dictionary:
	return {"op": "show", "id": node.id, "name": _node_label(node)}


static func hide_entry(node: OutlineNode) -> Dictionary:
	return {"op": "hide", "id": node.id, "name": _node_label(node)}


static func remove_entry(node: OutlineNode) -> Dictionary:
	return {"op": "remove", "id": node.id, "name": _node_label(node)}


static func move_entry(node: OutlineNode) -> Dictionary:
	return {"op": "move", "id": node.id, "name": _node_label(node), "cell": node.get("origin_cell")}


## A trigger's key: its id, or - for a mission whose triggers never got one - its position in the list.
static func _trigger_key(trigger: MissionTrigger, index: int) -> String:
	return trigger.id if trigger.id != "" else "#%d" % index


static func _action_key(entry: InteractableEntry, action: PropAction) -> String:
	var owner_key := entry.id if entry.id != "" else "cell:%s" % str(entry.origin_cell)
	return "%s/%s" % [owner_key, action.action_id]


static func _trigger_label(trigger: MissionTrigger) -> String:
	if trigger.event_id != "":
		return "The trigger on event '%s'" % trigger.event_id
	return "A checkpoint trigger"


static func _objective_label(objective: MissionObjective) -> String:
	return objective.description if objective.description != "" else objective.id


static func _node_label(node: OutlineNode) -> String:
	var shown := node.reference_name
	if shown == "":
		shown = str(node.get("mesh_item_name"))
	return shown


static func _find_group(mission: MissionData, group_id: String) -> MissionGroup:
	for group in mission.groups:
		if group.id == group_id:
			return group
	return null


static func _note(outcome: Dictionary, text: String) -> void:
	(outcome["report"] as Array[String]).append(text)
