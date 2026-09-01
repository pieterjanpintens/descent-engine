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


## Rotates a footprint to match a GridMap cell orientation index. GridMap
## orientations 0-23 come from Basis.get_orthogonal_index(); for footprint
## purposes we only care about the flat Y-axis quarter turns, which swap
## X/Z at 90 and 270 degrees.
func rotate_footprint(footprint: Vector3i, orientation: int) -> Vector3i:
	var basis := Basis.from_orthogonal_index(orientation)
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


## Registers a placed item's full footprint into a MissionData's occupancy
## index. Call this from the Creator whenever a prop/pillar/stairs is
## painted or moved. Call remove_item() first if repainting the same origin.
func register_item(mission: MissionData, origin: Vector3i, mesh_item_name: String, orientation: int) -> void:
	var base := get_footprint(mesh_item_name)
	var size := rotate_footprint(base, orientation)
	for x in size.x:
		for z in size.z:
			var cell := origin + Vector3i(x, 0, z)
			mission.occupied_cells[cell] = origin


func remove_item(mission: MissionData, origin: Vector3i, mesh_item_name: String, orientation: int) -> void:
	var base := get_footprint(mesh_item_name)
	var size := rotate_footprint(base, orientation)
	for x in size.x:
		for z in size.z:
			var cell := origin + Vector3i(x, 0, z)
			if mission.occupied_cells.get(cell) == origin:
				mission.occupied_cells.erase(cell)
