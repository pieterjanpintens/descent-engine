class_name LayeredMap
extends Node3D

## Attach to a scene containing four GridMap children named FloorGridMap,
## WallGridMap, PropGridMap, and UnderlayGridMap - all sharing the same
## MeshLibrary and cell_size. This node keeps the layers visually stacked and
## exposes helpers to sync painted cells into a MissionData resource.
##
## Scene layout expected:
## LayeredMap (this script)
##  |- FloorGridMap     (GridMap)
##  |- WallGridMap      (GridMap)
##  |- PropGridMap      (GridMap)
##  |- UnderlayGridMap  (GridMap)

@export var mission: MissionData
@export var floor_thickness: float = 0.2

@onready var floor_grid: GridMap = $FloorGridMap
@onready var wall_grid: GridMap = $WallGridMap
@onready var prop_grid: GridMap = $PropGridMap
@onready var underlay_grid: GridMap = $UnderlayGridMap


func _ready() -> void:
	# Only position differs between layers - cell_size and XZ cell
	# coordinates must stay identical across all four or occupancy lookups
	# (and the footprint registry) will target the wrong cells. Underlay
	# stays at the SAME Y as floor (not offset below it) - it's meant to be
	# visible exactly where the floor doesn't cover it, not hidden beneath.
	wall_grid.position = Vector3.ZERO
	prop_grid.position = Vector3(0, floor_thickness, 0)
	underlay_grid.position = Vector3.ZERO

	# All four grids share one MeshLibrary, so this only needs to run once -
	# swaps in the user's own official-game textures (if they've run the
	# importer tool against their own install) in place of the shipped
	# placeholders. A no-op if no override files are present.
	OfficialAssetOverrides.apply_overrides(floor_grid.mesh_library)


## Call after painting/moving/erasing a cell in PropGridMap (in-editor or
## from an in-game Creator tool) to keep MissionData's occupancy index and
## interactables list in sync with what's actually painted.
func sync_prop_cell(origin: Vector3i) -> void:
	# Clear any existing entry at this origin first, using ITS stored
	# footprint - never guess from the new state.
	var existing := _find_interactable(origin)
	if existing != null:
		FootprintRegistry.clear_occupied(mission, origin, existing.footprint)
		mission.interactables.erase(existing)

	var item_id := prop_grid.get_cell_item(origin)
	if item_id == GridMap.INVALID_CELL_ITEM:
		return  # cell was erased, nothing further to register

	var mesh_name := prop_grid.mesh_library.get_item_name(item_id)
	var orientation := prop_grid.get_cell_item_orientation(origin)
	var basis := prop_grid.get_cell_item_basis(origin)
	var defaults := FootprintRegistry.get_logical_defaults(mesh_name)
	var footprint := FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(mesh_name), basis)

	FootprintRegistry.mark_occupied(mission, origin, footprint)

	var entry := InteractableEntry.new()
	entry.mesh_item_name = mesh_name
	entry.origin_cell = origin
	entry.footprint = footprint
	entry.orientation = orientation
	entry.blocks_movement = not defaults.walkable
	entry.blocks_los = defaults.blocks_los
	mission.interactables.append(entry)


func _find_interactable(origin: Vector3i) -> InteractableEntry:
	for entry in mission.interactables:
		if entry.origin_cell == origin:
			return entry
	return null


## Rebuilds TileEntry data for every cell covered by a painted floor/wall
## piece, using naming-convention defaults. Floor tiles are irregular
## multi-cell shapes just like props - GridMap only tracks the origin cell
## each was painted at, so we expand each origin through its registered
## footprint to find every cell it actually covers. Run after a painting
## pass, or whenever you want to regenerate logical data from the visual
## layers.
func rebuild_floor_tiles() -> void:
	mission.tiles.clear()
	mission.floor_placements.clear()
	mission.floor_occupied_cells.clear()

	for origin in floor_grid.get_used_cells():
		_write_tile_footprint(origin, floor_grid, TilePlacement.Layer.FLOOR)

	# Wall layer cells override floor defaults where both are present.
	for origin in wall_grid.get_used_cells():
		_write_tile_footprint(origin, wall_grid, TilePlacement.Layer.WALL)


func _write_tile_footprint(origin: Vector3i, grid: GridMap, layer: TilePlacement.Layer) -> void:
	var item_id := grid.get_cell_item(origin)
	var mesh_name := grid.mesh_library.get_item_name(item_id)
	var orientation := grid.get_cell_item_orientation(origin)
	var basis := grid.get_cell_item_basis(origin)
	var defaults := FootprintRegistry.get_logical_defaults(mesh_name)
	var footprint := FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(mesh_name), basis)

	var placement := TilePlacement.new()
	placement.layer = layer
	placement.origin_cell = origin
	placement.mesh_item_name = mesh_name
	placement.orientation = orientation
	mission.floor_placements.append(placement)

	for offset in footprint:
		var cell: Vector3i = origin + offset
		mission.floor_occupied_cells[cell] = origin
		var entry: TileEntry = mission.tiles.get(cell)
		if entry == null:
			entry = TileEntry.new()
		entry.mesh_item_name = mesh_name
		entry.walkable = defaults.walkable
		entry.blocks_los = defaults.blocks_los
		mission.tiles[cell] = entry


## Underlay equivalent of rebuild_floor_tiles() - kept as a SEPARATE pass
## rather than folded into it, because underlay tiles physically coexist
## with whatever floor tile sits on the same cells (they're meant to peek
## through, not replace it). Writing them into mission.tiles the same way
## floor/wall do would have one silently clobber the other's walkable/
## blocks_los data depending on iteration order. Underlay currently carries
## no logical (walkable/blocks_los) data of its own - it's visual/hazard
## marker data only, tracked purely via underlay_placements/
## underlay_occupied_cells.
func rebuild_underlay_tiles() -> void:
	mission.underlay_placements.clear()
	mission.underlay_occupied_cells.clear()

	for origin in underlay_grid.get_used_cells():
		var item_id := underlay_grid.get_cell_item(origin)
		var mesh_name := underlay_grid.mesh_library.get_item_name(item_id)
		var orientation := underlay_grid.get_cell_item_orientation(origin)
		var basis := underlay_grid.get_cell_item_basis(origin)
		var footprint := FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(mesh_name), basis)

		var placement := TilePlacement.new()
		placement.layer = TilePlacement.Layer.UNDERLAY
		placement.origin_cell = origin
		placement.mesh_item_name = mesh_name
		placement.orientation = orientation
		mission.underlay_placements.append(placement)

		for offset in footprint:
			var cell: Vector3i = origin + offset
			mission.underlay_occupied_cells[cell] = origin


## Reverse of sync_prop_cell()/rebuild_floor_tiles()/rebuild_underlay_tiles():
## given a loaded MissionData, clears all four GridMaps and repaints them to
## match. Used by the Player to render a loaded mission, and reusable by the
## Creator later for "open an existing mission to keep editing."
func apply_mission(mission_to_apply: MissionData) -> void:
	floor_grid.clear()
	wall_grid.clear()
	prop_grid.clear()
	underlay_grid.clear()

	mission = mission_to_apply

	for placement in mission.floor_placements:
		var grid := floor_grid if placement.layer == TilePlacement.Layer.FLOOR else wall_grid
		var item_id := find_item_id(grid, placement.mesh_item_name)
		if item_id == -1:
			push_warning("No MeshLibrary item named '%s' - skipping floor placement at %s" % [placement.mesh_item_name, placement.origin_cell])
			continue
		grid.set_cell_item(placement.origin_cell, item_id, placement.orientation)

	for placement in mission.underlay_placements:
		var item_id := find_item_id(underlay_grid, placement.mesh_item_name)
		if item_id == -1:
			push_warning("No MeshLibrary item named '%s' - skipping underlay placement at %s" % [placement.mesh_item_name, placement.origin_cell])
			continue
		underlay_grid.set_cell_item(placement.origin_cell, item_id, placement.orientation)

	for entry in mission.interactables:
		var item_id := find_item_id(prop_grid, entry.mesh_item_name)
		if item_id == -1:
			push_warning("No MeshLibrary item named '%s' - skipping prop at %s" % [entry.mesh_item_name, entry.origin_cell])
			continue
		prop_grid.set_cell_item(entry.origin_cell, item_id, entry.orientation)


## MeshLibrary only looks up items by numeric id, not name - this does the
## name -> id search once per call. Fine for occasional use (mission load,
## interactive painting); would be worth caching if this ever runs
## somewhere hot (e.g. every frame).
func find_item_id(grid: GridMap, mesh_name: String) -> int:
	if grid.mesh_library == null:
		return -1
	for id in grid.mesh_library.get_item_list():
		if grid.mesh_library.get_item_name(id) == mesh_name:
			return id
	return -1
