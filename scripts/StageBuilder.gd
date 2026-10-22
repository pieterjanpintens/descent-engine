class_name StageBuilder
extends RefCounted

## Puts a checked map plan (MapPlanValidator.validate(), `result`) into a mission as a new STAGE: a MissionGroup holding the floor tiles, hazards
## and props of the plan, painted into the real GridMaps exactly like the Creator paints them (so occupancy, ids and everything else the editor
## keeps are produced by the editor's own sync code). The caller wraps build() in an undo step. Experimental (branch experiment/stage-generation).


## Where a new stage can go without touching what is there: just right of the existing map (a gap of `gap` squares), top aligned with it;
## (0, 0) for an empty mission. In game units - what the plan's x/z and the editor's status bar use.
static func free_spot(mission: MissionData, gap: int = 2) -> Vector2i:
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var found := false
	var max_x := 0
	var min_z := 0
	for occupied in [mission.floor_occupied_cells, mission.underlay_occupied_cells, mission.occupied_cells]:
		for cell: Vector3i in occupied:
			var x := floori(float(cell.x) / cpt)
			var z := floori(float(cell.z) / cpt)
			if not found:
				max_x = x
				min_z = z
				found = true
			max_x = maxi(max_x, x)
			min_z = mini(min_z, z)
	return Vector2i(max_x + 1 + gap, min_z) if found else Vector2i.ZERO


## Paints the plan with its top-left corner (the plan's bounds) at `corner` (game units). `options`: {name: String, heroes_start: bool}.
## Returns {group_id, pieces, starts}. Piece positions come straight from the validator (`fine_origin`, `quarter_turns`, `height`).
static func build(layered_map: LayeredMap, result: Dictionary, corner: Vector2i, options: Dictionary = {}) -> Dictionary:
	var mission := layered_map.mission
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var bounds: Rect2i = result["bounds"]
	var shift := corner - bounds.position  # game units
	var fine_shift := Vector3i(shift.x * cpt, 0, shift.y * cpt)

	var group := MissionGroup.new()
	group.id = mission.allocate_object_id()
	var stage_name := str(options.get("name", "")).strip_edges()
	group.reference_name = stage_name if stage_name != "" else "Generated stage"
	mission.groups.append(group)

	var floor_origins: Dictionary = {}
	var underlay_origins: Dictionary = {}
	var prop_origins: Array[Vector3i] = []
	var names: Dictionary = {}  # origin -> reference name
	for piece: Dictionary in result["pieces"]:
		var mesh: String = piece["mesh"]
		var layer: String = piece["layer"]
		var grid := _grid_for(layered_map, layer)
		var item_id := layered_map.find_item_id(grid, mesh)
		if item_id == -1:
			push_warning("StageBuilder: no mesh item '%s' in the %s layer - skipped" % [mesh, layer])
			continue
		var origin: Vector3i = piece["fine_origin"] + fine_shift
		var basis := Basis(Vector3.UP, deg_to_rad(90.0 * int(piece["quarter_turns"])))
		grid.set_cell_item(origin, item_id, layered_map.floor_grid.get_orthogonal_index_from_basis(basis))
		match layer:
			"floor":
				floor_origins[origin] = true
			"underlay":
				underlay_origins[origin] = true
			_:
				prop_origins.append(origin)
		if str(piece["name"]) != "":
			names[origin] = str(piece["name"])

	layered_map.rebuild_floor_tiles()
	layered_map.rebuild_underlay_tiles()
	for placement in mission.floor_placements:
		if floor_origins.has(placement.origin_cell):
			placement.parent_id = group.id
			placement.reference_name = str(names.get(placement.origin_cell, placement.reference_name))
	for placement in mission.underlay_placements:
		if underlay_origins.has(placement.origin_cell):
			placement.parent_id = group.id
			placement.reference_name = str(names.get(placement.origin_cell, placement.reference_name))
	for origin in prop_origins:
		layered_map.sync_prop_cell(origin, group.id)
	for entry in mission.interactables:
		if prop_origins.has(entry.origin_cell) and names.has(entry.origin_cell):
			entry.reference_name = str(names[entry.origin_cell])

	var starts := 0
	if options.get("heroes_start", false):
		for start: Dictionary in result["starts"]:
			mission.player_spawn_cells.append(Vector3i(int(start["x"]) + shift.x + 1, int(start["height"]), int(start["z"]) + shift.y + 1))
			starts += 1
		layered_map.set_spawn_overlay_cells(mission.player_spawn_cells)
	layered_map.notify_objects_changed()
	return {"group_id": group.id, "pieces": result["pieces"].size(), "starts": starts}


static func _grid_for(layered_map: LayeredMap, layer: String) -> GridMap:
	match layer:
		"floor":
			return layered_map.floor_grid
		"underlay":
			return layered_map.underlay_grid
	return layered_map.prop_grid
