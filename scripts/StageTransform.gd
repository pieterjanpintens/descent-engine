class_name StageTransform
extends RefCounted

## Moves or turns a SELECTION in the mission editor as one rigid body: a stage (a MissionGroup, subgroups included), several pieces, or one piece.
## Every piece keeps its place relative to the others. Used by the arrow keys (move) and R (turn) in CreatorController.
##
## Two steps so a blocked move can be refused before anything changes: plan() works out where everything goes (and returns {} when something
## would land on a piece that is not part of the selection), apply() puts it there. apply() is wrapped in an undo step by the caller.
## What moves: floor tiles, hazards and props (the same GridMap cells the editor paints), the tiles of monster spawns and LOS blockers inside the
## selection, and - when a whole stage is selected - the hero start squares that lie on the stage's floor.

const FLOOR := "floor"
const UNDERLAY := "underlay"
const PROP := "prop"


## What the ids stand for: {floors, underlays, props, spawns, blockers, has_group}. A group stands for everything in it, subgroups included.
static func collect(mission: MissionData, ids: Array[String]) -> Dictionary:
	var group_ids: Dictionary = {}
	var direct: Dictionary = {}
	var has_group := false
	for id in ids:
		var is_group := false
		for group in mission.groups:
			if group.id == id:
				is_group = true
				break
		if is_group:
			group_ids[id] = true
			has_group = true
		else:
			direct[id] = true
	var grew := true
	while grew:
		grew = false
		for group in mission.groups:
			if not group_ids.has(group.id) and group_ids.has(group.parent_id):
				group_ids[group.id] = true
				grew = true
	var floors: Array[TilePlacement] = []
	var underlays: Array[TilePlacement] = []
	var props: Array[InteractableEntry] = []
	var spawns: Array[MonsterSpawn] = []
	var blockers: Array[LosBlocker] = []
	for placement in mission.floor_placements:
		if direct.has(placement.id) or group_ids.has(placement.parent_id):
			floors.append(placement)
	for placement in mission.underlay_placements:
		if direct.has(placement.id) or group_ids.has(placement.parent_id):
			underlays.append(placement)
	for entry in mission.interactables:
		if direct.has(entry.id) or group_ids.has(entry.parent_id):
			props.append(entry)
	for spawn in mission.monster_spawns:
		if direct.has(spawn.id) or group_ids.has(spawn.parent_id):
			spawns.append(spawn)
	for blocker in mission.los_blockers:
		if direct.has(blocker.id) or group_ids.has(blocker.parent_id):
			blockers.append(blocker)
	return {"floors": floors, "underlays": underlays, "props": props, "spawns": spawns, "blockers": blockers, "has_group": has_group}


## The fine cells of the floor tiles and hazards of a group (subgroups included), or of its props when it has no floor - for the selection outline.
static func outline_cells(layered_map: LayeredMap, group_id: String) -> Array[Vector3i]:
	var members := collect(layered_map.mission, [group_id] as Array[String])
	var cells: Array[Vector3i] = []
	for placement: TilePlacement in members["floors"]:
		cells.append_array(_cells_of(layered_map, layered_map.floor_grid, placement.origin_cell, placement.mesh_item_name))
	for placement: TilePlacement in members["underlays"]:
		cells.append_array(_cells_of(layered_map, layered_map.underlay_grid, placement.origin_cell, placement.mesh_item_name))
	if cells.is_empty():
		for entry: InteractableEntry in members["props"]:
			cells.append_array(_cells_of(layered_map, layered_map.prop_grid, entry.origin_cell, entry.mesh_item_name))
	return cells


## Works out a move by `delta` tile squares (x, z) or, when `turn` is true, one quarter turn around the middle of the
## selection. Returns {} when there is nothing to do or the result would land on a piece that does not belong to the selection.
static func plan(layered_map: LayeredMap, ids: Array[String], turn: bool, delta: Vector2i = Vector2i.ZERO) -> Dictionary:
	var mission := layered_map.mission
	if mission == null or ids.is_empty():
		return {}
	var members := collect(mission, ids)
	var cpt := FootprintRegistry.CELLS_PER_TILE

	var pieces: Array[Dictionary] = []
	for placement: TilePlacement in members["floors"]:
		_add_piece(pieces, layered_map, layered_map.floor_grid, FLOOR, placement)
	for placement: TilePlacement in members["underlays"]:
		_add_piece(pieces, layered_map, layered_map.underlay_grid, UNDERLAY, placement)
	for entry: InteractableEntry in members["props"]:
		_add_piece(pieces, layered_map, layered_map.prop_grid, PROP, entry)
	var spawns: Array[MonsterSpawn] = members["spawns"]
	var blockers: Array[LosBlocker] = members["blockers"]
	if pieces.is_empty() and spawns.is_empty() and blockers.is_empty():
		return {}

	# the box around everything that moves, in fine cells: [min_x, max_x, min_z, max_z] (empty until something is added)
	var box: Array[int] = []
	for piece in pieces:
		for cell: Vector3i in piece["old_cells"]:
			_grow(box, cell.x, cell.x, cell.z, cell.z)
	for spawn in spawns:
		for cell in spawn.cells:
			_grow(box, (cell.x - 1) * cpt, cell.x * cpt - 1, (cell.z - 1) * cpt, cell.z * cpt - 1)
	for blocker in blockers:
		for cell in blocker.cells:
			_grow(box, (cell.x - 1) * cpt, cell.x * cpt - 1, (cell.z - 1) * cpt, cell.z * cpt - 1)
	var min_x := box[0]
	var max_x := box[1]
	var min_z := box[2]
	var max_z := box[3]

	# the pivot of a turn: the middle of the box, rounded to a tile-square corner (so everything stays on the tile grid), in tile units
	var pivot := Vector2i.ZERO
	if turn:
		pivot = Vector2i(floori((floori(float(min_x) / cpt) + floori(float(max_x) / cpt) + 2) / 2.0), floori((floori(float(min_z) / cpt) + floori(float(max_z) / cpt) + 2) / 2.0))
	var pivot_fine := pivot * cpt

	for piece in pieces:
		var old_origin: Vector3i = piece["old_origin"]
		if not turn:
			piece["new_origin"] = old_origin + Vector3i(delta.x * cpt, 0, delta.y * cpt)
			piece["new_index"] = piece["old_index"]
			piece["new_footprint"] = piece["old_footprint"]
		else:
			var new_index: int = (int(piece["old_index"]) + 1) % 4
			var new_footprint := FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(piece["mesh"]), Basis(Vector3.UP, deg_to_rad(90.0 * new_index)))
			var rotated_min := Vector2i(1 << 30, 1 << 30)
			for cell: Vector3i in piece["old_cells"]:
				rotated_min.x = mini(rotated_min.x, pivot_fine.x + (cell.z - pivot_fine.y))
				rotated_min.y = mini(rotated_min.y, pivot_fine.y - (cell.x - pivot_fine.x) - 1)
			var footprint_min := Vector2i(1 << 30, 1 << 30)
			for offset in new_footprint:
				footprint_min.x = mini(footprint_min.x, offset.x)
				footprint_min.y = mini(footprint_min.y, offset.z)
			piece["new_origin"] = Vector3i(rotated_min.x - footprint_min.x, old_origin.y, rotated_min.y - footprint_min.y)
			piece["new_index"] = new_index
			piece["new_footprint"] = new_footprint

	# a piece may not land on a piece that stays where it is (the grid holds one item per origin cell)
	var moving: Dictionary = {}
	for piece in pieces:
		moving["%s:%s" % [piece["kind"], piece["old_origin"]]] = true
	for piece in pieces:
		var grid: GridMap = piece["grid"]
		if grid.get_cell_item(piece["new_origin"]) != GridMap.INVALID_CELL_ITEM and not moving.has("%s:%s" % [piece["kind"], piece["new_origin"]]):
			return {}

	# the hero start squares on the stage's floor go along with a whole stage
	var starts: Array[int] = []
	if members["has_group"]:
		var on_floor: Dictionary = {}
		for piece in pieces:
			if piece["kind"] == FLOOR:
				for cell: Vector3i in piece["old_cells"]:
					on_floor[Vector3i(floori(float(cell.x) / cpt), cell.y, floori(float(cell.z) / cpt))] = true
		for index in layered_map.mission.player_spawn_cells.size():
			var square: Vector3i = layered_map.mission.player_spawn_cells[index]
			if on_floor.has(Vector3i(square.x - 1, square.y, square.z - 1)):
				starts.append(index)

	if not turn and delta == Vector2i.ZERO:
		return {}
	return {"pieces": pieces, "spawns": spawns, "blockers": blockers, "starts": starts, "turn": turn, "delta": delta, "pivot": pivot}


## Puts a plan() in place. The caller wraps this in an undo step.
static func apply(layered_map: LayeredMap, plan: Dictionary) -> void:
	var mission := layered_map.mission
	var pieces: Array = plan["pieces"]
	var orientations := _orientations(layered_map)

	for piece: Dictionary in pieces:
		var grid: GridMap = piece["grid"]
		grid.set_cell_item(piece["old_origin"], GridMap.INVALID_CELL_ITEM)
		if piece["kind"] == PROP:
			var entry: InteractableEntry = piece["node"]
			FootprintRegistry.clear_occupied(mission, entry.origin_cell, entry.footprint)
	var floors_moved := false
	var underlays_moved := false
	for piece: Dictionary in pieces:
		var grid: GridMap = piece["grid"]
		var orientation: int = orientations[piece["new_index"]]
		grid.set_cell_item(piece["new_origin"], piece["item_id"], orientation)
		match piece["kind"]:
			PROP:
				var entry: InteractableEntry = piece["node"]
				entry.origin_cell = piece["new_origin"]
				entry.orientation = orientation
				entry.footprint = piece["new_footprint"]
				FootprintRegistry.mark_occupied(mission, entry.origin_cell, entry.footprint)
			_:
				# pointing the placement at its new cell BEFORE the rebuild lets the rebuild's own identity carry-over (keyed by origin) re-adopt it
				var placement: TilePlacement = piece["node"]
				placement.origin_cell = piece["new_origin"]
				placement.orientation = orientation
				if piece["kind"] == FLOOR:
					floors_moved = true
				else:
					underlays_moved = true
	if floors_moved:
		layered_map.rebuild_floor_tiles()
	if underlays_moved:
		layered_map.rebuild_underlay_tiles()

	var turn: bool = plan["turn"]
	var delta: Vector2i = plan["delta"]
	var pivot: Vector2i = plan["pivot"]
	for spawn: MonsterSpawn in plan["spawns"]:
		for index in spawn.cells.size():
			spawn.cells[index] = _move_square(spawn.cells[index], turn, delta, pivot)
	for blocker: LosBlocker in plan["blockers"]:
		for index in blocker.cells.size():
			blocker.cells[index] = _move_square(blocker.cells[index], turn, delta, pivot)
	var starts: Array = plan["starts"]
	for index: int in starts:
		mission.player_spawn_cells[index] = _move_square(mission.player_spawn_cells[index], turn, delta, pivot)

	if not starts.is_empty():
		layered_map.set_spawn_overlay_cells(mission.player_spawn_cells)
	if not (plan["spawns"] as Array).is_empty():
		layered_map.refresh_monster_spawn_overlay()
	if not (plan["blockers"] as Array).is_empty():
		layered_map.refresh_blocker_overlay()
		layered_map.refresh_blocker_lines()
	layered_map.notify_objects_changed()


## A tile square (1-based x, z) after the move: shifted, or turned a quarter around the tile-corner `pivot`.
static func _move_square(square: Vector3i, turn: bool, delta: Vector2i, pivot: Vector2i) -> Vector3i:
	if not turn:
		return Vector3i(square.x + delta.x, square.y, square.z + delta.y)
	var cx := square.x - 1
	var cz := square.z - 1
	return Vector3i(pivot.x + (cz - pivot.y) + 1, square.y, pivot.y - (cx - pivot.x))


static func _grow(box: Array[int], x0: int, x1: int, z0: int, z1: int) -> void:
	if box.is_empty():
		box.assign([x0, x1, z0, z1])
		return
	box[0] = mini(box[0], x0)
	box[1] = maxi(box[1], x1)
	box[2] = mini(box[2], z0)
	box[3] = maxi(box[3], z1)


static func _add_piece(pieces: Array[Dictionary], layered_map: LayeredMap, grid: GridMap, kind: String, node: OutlineNode) -> void:
	var origin: Vector3i = node.get("origin_cell")
	var item_id := grid.get_cell_item(origin)
	if item_id == GridMap.INVALID_CELL_ITEM:
		return
	var mesh := grid.mesh_library.get_item_name(item_id)
	var old_index := _index_of(layered_map, grid.get_cell_item_orientation(origin))
	var footprint := FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(mesh), grid.get_cell_item_basis(origin))
	var cells: Array[Vector3i] = []
	for offset in footprint:
		cells.append(origin + offset)
	pieces.append({
		"node": node, "grid": grid, "kind": kind, "mesh": mesh, "item_id": item_id,
		"old_origin": origin, "old_index": old_index, "old_footprint": footprint, "old_cells": cells,
	})


static func _cells_of(layered_map: LayeredMap, grid: GridMap, origin: Vector3i, mesh: String) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if grid.get_cell_item(origin) == GridMap.INVALID_CELL_ITEM:
		return cells
	for offset in FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(mesh), grid.get_cell_item_basis(origin)):
		cells.append(origin + offset)
	return cells


## GridMap orientation values for 0..3 quarter turns about the vertical axis.
static func _orientations(layered_map: LayeredMap) -> Array[int]:
	var result: Array[int] = []
	for i in 4:
		result.append(layered_map.floor_grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, deg_to_rad(90.0 * i))))
	return result


static func _index_of(layered_map: LayeredMap, orientation: int) -> int:
	var index := _orientations(layered_map).find(orientation)
	return maxi(index, 0)
