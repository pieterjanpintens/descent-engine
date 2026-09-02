extends Node

## Autoload singleton. Add as "FootprintRegistry" in
## Project Settings > Autoload (script path: res://autoload/FootprintRegistry.gd).
##
## Maps a MeshLibrary item name to the exact set of cells it covers, relative
## to its GridMap origin cell. Footprints are NOT assumed to be rectangular -
## Descent's floor tiles and several props are irregular shapes (L-pieces,
## notched rectangles, crosses...), so a footprint is just a flat list of
## Vector3i offsets. The origin cell itself (Vector3i.ZERO) should always be
## included in the list.
##
## This same table is used for BOTH the floor layer and the prop layer -
## floor tiles are multi-cell items exactly like stairs/bookshelves, just
## painted into FloorGridMap instead of PropGridMap.

## >>> Add every mesh item name here with its unrotated cell layout (as if
## >>> painted at orientation 0). Anything not listed defaults to a single
## >>> cell at the origin, i.e. [Vector3i.ZERO].
##
## Example - an L-shaped 3-cell tile occupying its origin, one cell to the
## +X, and one cell to the +Z:
##   "tile_01a": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1)],
const FOOTPRINTS: Dictionary = {
	# Tile 1 - 2x3 solid rectangle. Origin is the BOTTOM-RIGHT cell, so all
	# offsets are <= 0.
	"1a": [
		Vector3i(-2, 0, -1), Vector3i(-1, 0, -1), Vector3i(0, 0, -1),
		Vector3i(-2, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 0),
	],
	"1b": [
		Vector3i(-2, 0, -1), Vector3i(-1, 0, -1), Vector3i(0, 0, -1),
		Vector3i(-2, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 0),
	],
	# Tile 2 - same shape as tile 1
	"2a": [
		Vector3i(-2, 0, -1), Vector3i(-1, 0, -1), Vector3i(0, 0, -1),
		Vector3i(-2, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 0),
	],
	"2b": [
		Vector3i(-2, 0, -1), Vector3i(-1, 0, -1), Vector3i(0, 0, -1),
		Vector3i(-2, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 0),
	],
	# Tile 7 - plus/cross shape, 4 rows x 6 cols:
	#   ..xx..
	#   xxxxxx
	#   xxxxxy   <- origin is the marked cell (row 3, col 6, 1-indexed)
	#   ..xx..
	"7a": [
		Vector3i(-3, 0, -2), Vector3i(-2, 0, -2),
		Vector3i(-5, 0, -1), Vector3i(-4, 0, -1), Vector3i(-3, 0, -1), Vector3i(-2, 0, -1), Vector3i(-1, 0, -1), Vector3i(0, 0, -1),
		Vector3i(-5, 0, 0), Vector3i(-4, 0, 0), Vector3i(-3, 0, 0), Vector3i(-2, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 0),
		Vector3i(-3, 0, 1), Vector3i(-2, 0, 1),
	],
	"7b": [
		Vector3i(-3, 0, -2), Vector3i(-2, 0, -2),
		Vector3i(-5, 0, -1), Vector3i(-4, 0, -1), Vector3i(-3, 0, -1), Vector3i(-2, 0, -1), Vector3i(-1, 0, -1), Vector3i(0, 0, -1),
		Vector3i(-5, 0, 0), Vector3i(-4, 0, 0), Vector3i(-3, 0, 0), Vector3i(-2, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 0),
		Vector3i(-3, 0, 1), Vector3i(-2, 0, 1),
	],
	# Pillars - 1x1 tile-square each. Listed explicitly for clarity even
	# though this matches the no-entry default, since these are exactly
	# the kind of item someone might reasonably expect needs an entry.
	"tall": [Vector3i.ZERO],
	"mini": [Vector3i.ZERO],
	"medium": [Vector3i.ZERO],
	# Stairs - low point (marked Y) is origin, 3 rows x 2 cols, all occupied:
	#   xx   <- high point
	#   xx
	#   xy   <- origin (low point)
	"stair": [
		Vector3i(-1, 0, -2), Vector3i(0, 0, -2),
		Vector3i(-1, 0, -1), Vector3i(0, 0, -1),
		Vector3i(-1, 0, 0), Vector3i(0, 0, 0),
	],
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
	{"prefix": "tile_", "walkable": true, "blocks_los": false},
]

## Exact-name overrides, checked BEFORE the prefix table above. Use this for
## items whose real MeshLibrary name doesn't follow (and you don't want to
## force it into) the prefix convention - e.g. these pillars are literally
## named "tall"/"mini"/"medium" in the palette, not "pillar_tall" etc.
const LOGICAL_OVERRIDES: Dictionary = {
	"tall": {"walkable": false, "blocks_los": true},
	"mini": {"walkable": false, "blocks_los": true},
	"medium": {"walkable": false, "blocks_los": true},
	"stair": {"walkable": true, "blocks_los": false},
}


## How many GridMap cells make up one physical tile-square. FOOTPRINTS below
## is authored in tile-square units (matching the game's own artwork/ASCII
## layout) - get_footprint() expands each square into this many sub-cells
## automatically, since pillars need finer-than-one-tile positioning and so
## the actual GridMap grid runs at this finer resolution.
##
## >>> Set this to match whatever you divided your GridMap cell_size by.
const CELLS_PER_TILE: int = 2

## Returns the fine-grained footprint (list of Vector3i cell offsets from
## origin, in actual GridMap cell units) for a mesh item name. Automatically
## expands FOOTPRINTS' tile-square entries by CELLS_PER_TILE. Defaults to a
## single tile-square (still expanded) if the mesh isn't listed.
func get_footprint(mesh_item_name: String) -> Array[Vector3i]:
	var raw: Array = FOOTPRINTS.get(mesh_item_name, [Vector3i.ZERO])
	var expanded: Array[Vector3i] = []
	for square_offset in raw:
		var base_x: int = square_offset.x * CELLS_PER_TILE
		var base_z: int = square_offset.z * CELLS_PER_TILE
		for dx in CELLS_PER_TILE:
			for dz in CELLS_PER_TILE:
				expanded.append(Vector3i(base_x + dx, square_offset.y, base_z + dz))
	return expanded


## Rotates every offset in a footprint to match a cell's orientation Basis
## (get this from GridMap.get_cell_item_basis(cell) - GDScript can't
## reconstruct a Basis from a raw orientation int on its own, so always
## pass the real one). Only the four flat Y-axis quarter turns are
## supported, which covers everything GridMap's default paint controls do.
func rotate_footprint(footprint: Array[Vector3i], basis: Basis) -> Array[Vector3i]:
	var quarter_turns := _quarter_turns_from_basis(basis)
	var rotated: Array[Vector3i] = footprint.duplicate()
	for i in quarter_turns:
		for j in rotated.size():
			rotated[j] = _rotate_cell_90(rotated[j])
	return rotated


func _quarter_turns_from_basis(basis: Basis) -> int:
	var forward := basis * Vector3.FORWARD
	if forward.z < -0.5:
		return 0
	elif forward.x < -0.5:
		return 1
	elif forward.z > 0.5:
		return 2
	else:
		return 3


func _rotate_cell_90(cell: Vector3i) -> Vector3i:
	# 90 degree rotation around Y. If footprints come out mirrored/rotated
	# the wrong way in testing, flip the sign here (swap which term is
	# negated) - direction (CW vs CCW) depends on convention and is easy
	# to get backwards on the first try.
	return Vector3i(cell.z, cell.y, -cell.x)


func get_logical_defaults(mesh_item_name: String) -> Dictionary:
	if LOGICAL_OVERRIDES.has(mesh_item_name):
		return LOGICAL_OVERRIDES[mesh_item_name]
	for entry in LOGICAL_DEFAULTS:
		if mesh_item_name.begins_with(entry.prefix):
			return entry
	return {"walkable": true, "blocks_los": false}


## Marks every cell of an already-rotated footprint as occupied by origin.
func mark_occupied(mission: MissionData, origin: Vector3i, footprint: Array[Vector3i]) -> void:
	for offset in footprint:
		var cell: Vector3i = origin + offset
		mission.occupied_cells[cell] = origin


## Clears every cell of an already-rotated footprint, but only if it's
## still owned by origin (avoids clobbering a different item that
## happens to overlap the same cells after edits).
func clear_occupied(mission: MissionData, origin: Vector3i, footprint: Array[Vector3i]) -> void:
	for offset in footprint:
		var cell: Vector3i = origin + offset
		if mission.occupied_cells.get(cell) == origin:
			mission.occupied_cells.erase(cell)
