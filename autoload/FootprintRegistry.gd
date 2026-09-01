extends Node

## Autoload singleton. Add as "FootprintRegistry" in
## Project Settings > Autoload (script path: res://autoload/FootprintRegistry.gd).
##
## Maps a MeshLibrary item name to its footprint size in cells (before
## rotation) so multi-cell props/stairs occupy every cell they visually
## cover, not just their GridMap origin cell.

## Cells are (width_x, height_y, depth_z). height_y is almost always 1 for
## floor-plane footprints; it's here in case you ever need vertical
## multi-cell items later.
##
## >>> Add every multi-cell mesh item name here. Anything not listed
## >>> defaults to Vector3i(1, 1, 1).
const FOOTPRINTS: Dictionary = {
	"stairs_2x3": Vector3i(2, 1, 3),
	"bookshelf_1x2": Vector3i(1, 1, 2),
	"table_1x2": Vector3i(1, 1, 2),
}

## Naming-convention defaults used to auto-fill TileEntry / InteractableEntry
## logical flags from a mesh item's name. Keyed by prefix (checked with
## begins_with), first match wins - order matters.
const LOGICAL_DEFAULTS: Array = [
	{"prefix": "wall_", "walkable": false, "blocks_los": true},
	{"prefix": "pillar_", "walkable": false, "blocks_los": true},
	{"prefix": "door_", "walkable": true, "blocks_los": false},
	{"prefix": "hazard_", "walkable": true, "blocks_los": false},
	{"prefix": "floor_", "walkable": true, "blocks_los": false},
]


func get_footprint(mesh_item_name: String) -> Vector3i:
	return FOOTPRINTS.get(mesh_item_name, Vector3i.ONE)


## Rotates a footprint to match a cell's orientation Basis (get this from
## GridMap.get_cell_item_basis(cell) - GDScript has no way to reconstruct a
## Basis from a raw orientation int on its own, so always pass the real one).
## We only care about the flat Y-axis quarter turns, which swap X/Z.
func rotate_footprint(footprint: Vector3i, basis: Basis) -> Vector3i:
	var forward := basis * Vector3.FORWARD
	var is_quarter_turn := absf(forward.x) > 0.5  # rotated 90 or 270 around Y
	if is_quarter_turn:
		return Vector3i(footprint.z, footprint.y, footprint.x)
	return footprint


func get_logical_defaults(mesh_item_name: String) -> Dictionary:
	for entry in LOGICAL_DEFAULTS:
		if mesh_item_name.begins_with(entry.prefix):
			return entry
	return {"walkable": true, "blocks_los": false}


## Marks every cell of an already-rotated footprint as occupied by origin.
func mark_occupied(mission: MissionData, origin: Vector3i, footprint: Vector3i) -> void:
	for x in footprint.x:
		for z in footprint.z:
			var cell := origin + Vector3i(x, 0, z)
			mission.occupied_cells[cell] = origin


## Clears every cell of an already-rotated footprint, but only if it's
## still owned by origin (avoids clobbering a different item that
## happens to overlap the same cells after edits).
func clear_occupied(mission: MissionData, origin: Vector3i, footprint: Vector3i) -> void:
	for x in footprint.x:
		for z in footprint.z:
			var cell := origin + Vector3i(x, 0, z)
			if mission.occupied_cells.get(cell) == origin:
				mission.occupied_cells.erase(cell)
