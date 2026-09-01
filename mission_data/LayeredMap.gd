class_name LayeredMap
extends Node3D

## Attach to a scene containing three GridMap children named FloorGridMap,
## WallGridMap and PropGridMap - all sharing the same MeshLibrary and
## cell_size. This node keeps the layers visually stacked and exposes
## helpers to sync painted cells into a MissionData resource.
##
## Scene layout expected:
## LayeredMap (this script)
##  |- FloorGridMap  (GridMap)
##  |- WallGridMap   (GridMap)
##  |- PropGridMap   (GridMap)

@export var mission: MissionData
@export var floor_thickness: float = 0.1

@onready var floor_grid: GridMap = $FloorGridMap
@onready var wall_grid: GridMap = $WallGridMap
@onready var prop_grid: GridMap = $PropGridMap


func _ready() -> void:
	# Only position differs between layers - cell_size and XZ cell
	# coordinates must stay identical across all three or occupancy lookups
	# (and the footprint registry) will target the wrong cells.
	wall_grid.position = Vector3.ZERO
	prop_grid.position = Vector3(0, floor_thickness, 0)


## Call after painting/moving/erasing a cell in PropGridMap (in-editor or
## from an in-game Creator tool) to keep MissionData's occupancy index and
## interactables list in sync with what's actually painted.
func sync_prop_cell(origin: Vector3i) -> void:
	# Clear any existing entry at this origin first, using ITS stored
	# footprint/orientation - never guess from the new state.
	var existing := _find_interactable(origin)
	if existing != null:
		FootprintRegistry.remove_item(mission, origin, existing.mesh_item_name, existing.orientation)
		mission.interactables.erase(existing)

	var item_id := prop_grid.get_cell_item(origin)
	if item_id == GridMap.INVALID_CELL_ITEM:
		return  # cell was erased, nothing further to register

	var mesh_name := prop_grid.mesh_library.get_item_name(item_id)
	var orientation := prop_grid.get_cell_item_orientation(origin)
	var defaults := FootprintRegistry.get_logical_defaults(mesh_name)
	var footprint := FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(mesh_name), orientation)

	FootprintRegistry.register_item(mission, origin, mesh_name, orientation)

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


## Rebuilds TileEntry data for every painted floor/wall cell using
## naming-convention defaults. Run after a painting pass, or whenever you
## want to regenerate logical data from the visual layers.
func rebuild_floor_tiles() -> void:
	mission.tiles.clear()

	for cell in floor_grid.get_used_cells():
		_write_tile_entry(cell, floor_grid)

	# Wall layer cells override floor defaults where both are present.
	for cell in wall_grid.get_used_cells():
		_write_tile_entry(cell, wall_grid)


func _write_tile_entry(cell: Vector3i, grid: GridMap) -> void:
	var item_id := grid.get_cell_item(cell)
	var mesh_name := grid.mesh_library.get_item_name(item_id)
	var defaults := FootprintRegistry.get_logical_defaults(mesh_name)
	var entry: TileEntry = mission.tiles.get(cell)
	if entry == null:
		entry = TileEntry.new()
	entry.mesh_item_name = mesh_name
	entry.walkable = defaults.walkable
	entry.blocks_los = defaults.blocks_los
	mission.tiles[cell] = entry
