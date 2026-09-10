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

## Fires whenever mission.interactables or mission.groups changes shape
## (an object placed/erased/repainted, or a group created/renamed/deleted/
## reparented) - CreatorOutline.gd listens to this to know when to rebuild
## its tree. Deliberately NOT fired for floor/wall/underlay edits - those
## aren't part of the outline tree, see CreatorOutline.gd's own doc
## comment for why.
signal mission_objects_changed

@onready var floor_grid: GridMap = $FloorGridMap
@onready var wall_grid: GridMap = $WallGridMap
@onready var prop_grid: GridMap = $PropGridMap
@onready var underlay_grid: GridMap = $UnderlayGridMap

var _spawn_overlay: MeshInstance3D
var _spawn_overlay_mesh: ImmediateMesh


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

	_setup_spawn_overlay()


func _setup_spawn_overlay() -> void:
	_spawn_overlay_mesh = ImmediateMesh.new()
	_spawn_overlay = MeshInstance3D.new()
	_spawn_overlay.mesh = _spawn_overlay_mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_ambient_light = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_spawn_overlay.material_override = material
	_spawn_overlay.visible = false
	add_child(_spawn_overlay)


## Yellow semi-transparent overlay marking a set of TILE-SQUARE ("game
## unit") cells (mission's player_spawn_cells) - same "start area"
## highlight the original game's own app shows. Cells here are tile-square
## coordinates, not fine GridMap cells - see
## FootprintRegistry.fine_cell_to_tile_square() and _add_spawn_quad() below.
## Shared here (not duplicated in CreatorController/MissionPlayer) since
## both the Creator and Player instance this same scene and both need to
## show it - Creator while drawing it, Player before round 1. Rebuilt from
## scratch each call; pass an empty array to clear it.
func set_spawn_overlay_cells(cells: Array[Vector3i]) -> void:
	_spawn_overlay_mesh.clear_surfaces()
	if cells.is_empty():
		_spawn_overlay.visible = false
		return

	_spawn_overlay_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in cells:
		_add_spawn_quad(cell)
	_spawn_overlay_mesh.surface_end()
	_spawn_overlay.global_transform = Transform3D.IDENTITY  # vertices already computed in world space
	_spawn_overlay.visible = true


func set_spawn_overlay_visible(value: bool) -> void:
	_spawn_overlay.visible = value and _spawn_overlay_mesh.get_surface_count() > 0


func _add_spawn_quad(cell: Vector3i) -> void:
	var corners := get_tile_square_world_corners(cell)
	var color := Color(1.0, 0.9, 0.2, 0.45)
	for v in [corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]]:
		_spawn_overlay_mesh.surface_set_color(color)
		_spawn_overlay_mesh.surface_add_vertex(v)


## `cell` is a TILE-SQUARE ("game unit") coordinate, not a fine GridMap
## cell - see FootprintRegistry.fine_cell_to_tile_square(). Expands it to
## its near fine-cell corner using the same far-corner math
## expand_footprint() uses (base = ts*CELLS_PER_TILE - CELLS_PER_TILE) - bare,
## no manual correction (an earlier attempt at one made things worse, not
## better, and turned out to be chasing a UX problem - hard to tell where a
## click will land with no preview - not an actual math bug; see
## CreatorController's spawn-paint hover ghost, which reuses this exact
## method so preview and placement can never disagree). Returns the four
## WORLD-SPACE corners (in quad winding order) spanning the FULL tile-square
## (CELLS_PER_TILE fine cells per side), lifted just above the floor surface
## (floor_thickness + a small epsilon) so it reads as a decal on top of the
## floor rather than z-fighting with it. Same corner-based box-building
## approach as CreatorController's occupancy overlay (GridMap's Center X/Y/Z
## are OFF, so map_to_local() returns a cell's CORNER, not its center).
func get_tile_square_world_corners(cell: Vector3i) -> Array[Vector3]:
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var near_fine_cell := Vector3i(cell.x * cpt - cpt, cell.y, cell.z * cpt - cpt)
	var corner_local: Vector3 = floor_grid.map_to_local(near_fine_cell)
	var size := Vector3(cpt * floor_grid.cell_size.x, 0, cpt * floor_grid.cell_size.z)
	var lift := Vector3(0, floor_thickness + 0.02, 0)
	return [
		floor_grid.to_global(corner_local + lift),
		floor_grid.to_global(corner_local + Vector3(size.x, 0, 0) + lift),
		floor_grid.to_global(corner_local + Vector3(size.x, 0, size.z) + lift),
		floor_grid.to_global(corner_local + Vector3(0, 0, size.z) + lift),
	]


## Call after painting/moving/erasing a cell in PropGridMap (in-editor or
## from an in-game Creator tool) to keep MissionData's occupancy index and
## interactables list in sync with what's actually painted.
func sync_prop_cell(origin: Vector3i) -> void:
	# Clear any existing entry at this origin first, using ITS stored
	# footprint - never guess from the new state. Keep a reference to it
	# (rather than just erasing) so its identity/authoring survives a
	# repaint of the same cell - see the field-carry-over note below.
	var existing := _find_interactable(origin)
	if existing != null:
		FootprintRegistry.clear_occupied(mission, origin, existing.footprint)
		mission.interactables.erase(existing)

	var item_id := prop_grid.get_cell_item(origin)
	if item_id == GridMap.INVALID_CELL_ITEM:
		mission_objects_changed.emit()
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
	# This function always erases-then-recreates rather than updating in
	# place, so a repaint of an already-placed cell (correcting its mesh
	# or orientation) would otherwise silently orphan its outline-tree
	# identity, group membership, and any authored reference_name/props/
	# actions. Carry those over from the entry that was just here;
	# otherwise mint a fresh id for a genuinely new placement.
	if existing != null:
		entry.id = existing.id
		entry.parent_id = existing.parent_id
		entry.reference_name = existing.reference_name
		entry.props = existing.props
		entry.actions = existing.actions
	else:
		entry.id = mission.allocate_object_id()
	mission.interactables.append(entry)
	mission_objects_changed.emit()


## For callers that mutate mission.groups/mission.interactables' parent_id
## directly (CreatorOutline.gd's group New/Rename/Delete/Move to... - none
## of that touches the GridMap the way sync_prop_cell() does, so there's
## nothing to repaint, just the "something changed, rebuild the tree"
## notification CreatorOutline.gd is listening for).
func notify_objects_changed() -> void:
	mission_objects_changed.emit()


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
	# Keyed by (layer, origin_cell) rather than origin_cell alone - floor
	# and wall are separate GridMaps that can share the same numeric cell
	# coordinate, and this function rebuilds both into one shared array.
	var old_by_key: Dictionary = {}
	for placement in mission.floor_placements:
		old_by_key[_tile_placement_key(placement.layer, placement.origin_cell)] = placement

	mission.tiles.clear()
	mission.floor_placements.clear()
	mission.floor_occupied_cells.clear()

	for origin in floor_grid.get_used_cells():
		_write_tile_footprint(origin, floor_grid, TilePlacement.Layer.FLOOR, old_by_key)

	# Wall layer cells override floor defaults where both are present.
	for origin in wall_grid.get_used_cells():
		_write_tile_footprint(origin, wall_grid, TilePlacement.Layer.WALL, old_by_key)

	mission_objects_changed.emit()


func _tile_placement_key(layer: TilePlacement.Layer, origin_cell: Vector3i) -> String:
	return "%d:%s" % [layer, origin_cell]


func _write_tile_footprint(origin: Vector3i, grid: GridMap, layer: TilePlacement.Layer, old_by_key: Dictionary) -> void:
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

	# This function rebuilds EVERY placement from scratch on every single
	# edit anywhere on the map (see the class doc's "full rebuild" note) -
	# without this, a repainted tile would silently lose its outline-tree
	# id/parent_id every time ANY floor/wall cell gets painted, not just
	# itself. Carry the old entry's identity forward when this origin
	# cell already had something; only mint a fresh id for a genuinely
	# new placement. Mirrors sync_prop_cell()'s own field-carry-over fix.
	var old: TilePlacement = old_by_key.get(_tile_placement_key(layer, origin))
	if old != null:
		placement.id = old.id
		placement.parent_id = old.parent_id
	else:
		placement.id = mission.allocate_object_id()

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
	# Underlay has only one Layer value, so origin_cell alone is an
	# unambiguous key here (unlike rebuild_floor_tiles()'s floor+wall case).
	var old_by_cell: Dictionary = {}
	for placement in mission.underlay_placements:
		old_by_cell[placement.origin_cell] = placement

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

		# Same identity-carry-over reasoning as rebuild_floor_tiles() -
		# this rebuilds every placement from scratch on every edit
		# anywhere in the underlay layer.
		var old: TilePlacement = old_by_cell.get(origin)
		if old != null:
			placement.id = old.id
			placement.parent_id = old.parent_id
		else:
			placement.id = mission.allocate_object_id()

		mission.underlay_placements.append(placement)

		for offset in footprint:
			var cell: Vector3i = origin + offset
			mission.underlay_occupied_cells[cell] = origin

	mission_objects_changed.emit()


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

	# A whole new mission's worth of interactables/groups just got swapped
	# in (New/Load in the Creator) - CreatorOutline.gd needs to rebuild its
	# tree from scratch here too, same as after a single sync_prop_cell()
	# edit. Harmless no-op in the Player (nothing there listens).
	mission_objects_changed.emit()


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
