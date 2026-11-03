class_name TutorialChecks
extends RefCounted

## The "done when" tests of the tutorial steps (data/tutorials/*.json: "done": {"check": "<name>", ...}). Every check looks at the
## mission as it is NOW (or at what the user did since the step began), never at one particular click - so steps can be done in any
## order, an undo takes a step back, and a step that is already true shows as done at once.

const TOKENS := ["exploration", "interact", "umbra"]


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
			return mission.player_spawn_cells.size() >= int(spec.get("n", 1))
		"players_fit":
			return not mission.player_spawn_cells.is_empty() and mission.max_players <= mission.player_spawn_cells.size()
	push_warning("TutorialChecks: unknown check '%s'" % spec.get("check", ""))
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
