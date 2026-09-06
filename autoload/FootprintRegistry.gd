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
	# Tile 3 - notched rectangle, 3 rows x 4 cols. Origin is the marked cell:
	#   xx..   <- 3a
	#   xxxx
	#   xxxy   <- origin (row 3, col 4)
	"3a": [
		Vector3i(-3, 0, -2), Vector3i(-2, 0, -2),
		Vector3i(-3, 0, -1), Vector3i(-2, 0, -1), Vector3i(-1, 0, -1), Vector3i(0, 0, -1),
		Vector3i(-3, 0, 0), Vector3i(-2, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 0),
	],
	# 3b - the other face, same physical piece mirrored left/right:
	#   ..xx
	#   xxxx
	#   yxxx   <- origin (row 3, col 1)
	"3b": [
		Vector3i(2, 0, -2), Vector3i(3, 0, -2),
		Vector3i(0, 0, -1), Vector3i(1, 0, -1), Vector3i(2, 0, -1), Vector3i(3, 0, -1),
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0),
	],
	# Tile 4 - stepped/L-shaped, 4 rows x 4 cols. Origin is the marked cell:
	#   xx..   <- 4a
	#   xx..
	#   xxxx
	#   yxxx   <- origin (row 4, col 1)
	"4a": [
		Vector3i(0, 0, -3), Vector3i(1, 0, -3),
		Vector3i(0, 0, -2), Vector3i(1, 0, -2),
		Vector3i(0, 0, -1), Vector3i(1, 0, -1), Vector3i(2, 0, -1), Vector3i(3, 0, -1),
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0),
	],
	# 4b - the other face, same physical piece mirrored left/right:
	#   ..xx
	#   ..xx
	#   xxxx
	#   xxxy   <- origin (row 4, col 4)
	"4b": [
		Vector3i(-1, 0, -3), Vector3i(0, 0, -3),
		Vector3i(-1, 0, -2), Vector3i(0, 0, -2),
		Vector3i(-3, 0, -1), Vector3i(-2, 0, -1), Vector3i(-1, 0, -1), Vector3i(0, 0, -1),
		Vector3i(-3, 0, 0), Vector3i(-2, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 0),
	],
	# Tile 5 - same shape as tile 4
	"5a": [
		Vector3i(0, 0, -3), Vector3i(1, 0, -3),
		Vector3i(0, 0, -2), Vector3i(1, 0, -2),
		Vector3i(0, 0, -1), Vector3i(1, 0, -1), Vector3i(2, 0, -1), Vector3i(3, 0, -1),
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0),
	],
	"5b": [
		Vector3i(-1, 0, -3), Vector3i(0, 0, -3),
		Vector3i(-1, 0, -2), Vector3i(0, 0, -2),
		Vector3i(-3, 0, -1), Vector3i(-2, 0, -1), Vector3i(-1, 0, -1), Vector3i(0, 0, -1),
		Vector3i(-3, 0, 0), Vector3i(-2, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 0),
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
	# Tile 18 - large irregular octagon-ish shape, 7 rows x 7 cols. Origin is
	# the marked cell:
	#   00xx000
	#   0xxxx00
	#   xxxxxx0
	#   xxxxxxx
	#   xxxxxxx
	#   xxxxxx0
	#   0xxxy00   <- 18a origin (row 7, col 5)
	"18a": [
		Vector3i(-2, 0, -6), Vector3i(-1, 0, -6),
		Vector3i(-3, 0, -5), Vector3i(-2, 0, -5), Vector3i(-1, 0, -5), Vector3i(0, 0, -5),
		Vector3i(-4, 0, -4), Vector3i(-3, 0, -4), Vector3i(-2, 0, -4), Vector3i(-1, 0, -4), Vector3i(0, 0, -4), Vector3i(1, 0, -4),
		Vector3i(-4, 0, -3), Vector3i(-3, 0, -3), Vector3i(-2, 0, -3), Vector3i(-1, 0, -3), Vector3i(0, 0, -3), Vector3i(1, 0, -3), Vector3i(2, 0, -3),
		Vector3i(-4, 0, -2), Vector3i(-3, 0, -2), Vector3i(-2, 0, -2), Vector3i(-1, 0, -2), Vector3i(0, 0, -2), Vector3i(1, 0, -2), Vector3i(2, 0, -2),
		Vector3i(-4, 0, -1), Vector3i(-3, 0, -1), Vector3i(-2, 0, -1), Vector3i(-1, 0, -1), Vector3i(0, 0, -1), Vector3i(1, 0, -1),
		Vector3i(-3, 0, 0), Vector3i(-2, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 0),
	],
	# 18b - the other face:
	#   000xx00
	#   00xxxx0
	#   0xxxxxx
	#   xxxxxxx
	#   xxxxxxx
	#   0xxxxxx
	#   00xxxy0   <- origin (row 7, col 6)
	"18b": [
		Vector3i(-2, 0, -6), Vector3i(-1, 0, -6),
		Vector3i(-3, 0, -5), Vector3i(-2, 0, -5), Vector3i(-1, 0, -5), Vector3i(0, 0, -5),
		Vector3i(-4, 0, -4), Vector3i(-3, 0, -4), Vector3i(-2, 0, -4), Vector3i(-1, 0, -4), Vector3i(0, 0, -4), Vector3i(1, 0, -4),
		Vector3i(-5, 0, -3), Vector3i(-4, 0, -3), Vector3i(-3, 0, -3), Vector3i(-2, 0, -3), Vector3i(-1, 0, -3), Vector3i(0, 0, -3), Vector3i(1, 0, -3),
		Vector3i(-5, 0, -2), Vector3i(-4, 0, -2), Vector3i(-3, 0, -2), Vector3i(-2, 0, -2), Vector3i(-1, 0, -2), Vector3i(0, 0, -2), Vector3i(1, 0, -2),
		Vector3i(-4, 0, -1), Vector3i(-3, 0, -1), Vector3i(-2, 0, -1), Vector3i(-1, 0, -1), Vector3i(0, 0, -1), Vector3i(1, 0, -1),
		Vector3i(-3, 0, 0), Vector3i(-2, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 0),
	],
	# Pillars - 1x1 tile-square each. Asset geometry: pivot at (0,0,0),
	# mesh extends to (1,0,-1) - i.e. +1 tile-square in X, but the pivot
	# is already at the correct Z edge (0, not -1). This offset makes
	# expand_footprint's shared "forward corner is pivot" convention land
	# on the correct cells for this specific asset's actual pivot placement.
	# NOTE: this is a hand-correction, not something _apply_pivot_correction()
	# can derive - a 1x1 footprint has no second offset to read direction
	# from. If the pillar mesh's pivot is ever moved in Blender to the
	# quadrant that extends -X/-Z instead, this should become Vector3i.ZERO.
	"tall": [Vector3i(1, 0, 0)],
	"mini": [Vector3i(1, 0, 0)],
	"medium": [Vector3i(1, 0, 0)],
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

## Returns the RAW, unrotated, unexpanded tile-square offsets for a mesh
## item name - exactly as authored in FOOTPRINTS. Rotate this BEFORE
## expanding (see expand_footprint) - the true physical pivot lives at
## tile-square granularity, not at whatever fine-cell corner CELLS_PER_TILE
## happens to expand it to.
func get_tile_square_footprint(mesh_item_name: String) -> Array[Vector3i]:
	var raw: Array = FOOTPRINTS.get(mesh_item_name, [Vector3i.ZERO])
	var typed: Array[Vector3i] = []
	typed.assign(raw)
	return _apply_pivot_correction(typed)


## The Blender pivot always sits on a physical corner of the tile-square
## containing the origin - so cells adjacent to the origin along a given
## axis only ever extend in ONE direction, never both. expand_footprint()
## assumes that direction is always -X/-Z (the "far corner" convention).
## When a mesh's number/label pivot happens to sit on the opposite edge
## instead, the origin's own row/column will read the opposite sign, and
## every offset in the footprint needs a uniform +1 nudge on that axis to
## land on the correct fine cells - this detects that case automatically
## from the authored data instead of hand-correcting each affected tile's
## offsets (as had to be done for tile 3b/4a/5a).
##
## Only works when there's a second offset to read direction from - a
## single-cell footprint (e.g. a manually pre-corrected pillar, see
## FOOTPRINTS above) has nothing to compare against and is left untouched.
func _apply_pivot_correction(footprint: Array[Vector3i]) -> Array[Vector3i]:
	if footprint.size() <= 1:
		return footprint
	var needs_x := false
	var needs_z := false
	for offset in footprint:
		if offset.z == 0 and offset.x > 0:
			needs_x = true
		if offset.x == 0 and offset.z > 0:
			needs_z = true
	if not needs_x and not needs_z:
		return footprint
	var correction := Vector3i(1 if needs_x else 0, 0, 1 if needs_z else 0)
	var corrected: Array[Vector3i] = []
	for offset in footprint:
		corrected.append(offset + correction)
	return corrected


## Expands a tile-square-unit footprint (already rotated, if rotation is
## needed) into fine-grained GridMap cell offsets. Each offset is treated
## as the square's FAR corner, extending backward toward -X/-Z by a full
## CELLS_PER_TILE - e.g. Vector3i.ZERO with CELLS_PER_TILE=2 expands to
## (-1,-1), (-1,-2), (-2,-1), (-2,-2). Verified against real in-game
## mismatches: an earlier attempt at this correction (shifting by
## CELLS_PER_TILE - 1) closed most but not all of a uniform +1 tile-square
## error seen across every shape - this closes the remaining one-fine-cell
## gap in the same direction.
func expand_footprint(square_footprint: Array[Vector3i]) -> Array[Vector3i]:
	var expanded: Array[Vector3i] = []
	for square_offset in square_footprint:
		var base_x: int = square_offset.x * CELLS_PER_TILE - CELLS_PER_TILE
		var base_z: int = square_offset.z * CELLS_PER_TILE - CELLS_PER_TILE
		for dx in CELLS_PER_TILE:
			for dz in CELLS_PER_TILE:
				expanded.append(Vector3i(base_x + dx, square_offset.y, base_z + dz))
	return expanded


## Full convenience pipeline for the UNROTATED case: raw tile-square
## offsets, expanded to fine cells. Do NOT use this if you also need to
## rotate - call get_tile_square_footprint() -> rotate_footprint() ->
## expand_footprint() in that order instead (see LayeredMap for the actual
## call sites). Rotating an already-expanded footprint rotates around a
## fine-cell CORNER instead of the tile-square's true pivot, which breaks
## anything not perfectly symmetric about that corner - this was the cause
## of pillars visually landing correctly but their registered occupied
## cells jumping to the wrong quadrant after rotation.
func get_footprint(mesh_item_name: String) -> Array[Vector3i]:
	return expand_footprint(get_tile_square_footprint(mesh_item_name))


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


## Rotates a MIN-CORNER tile-square offset by 90 degrees around the origin.
## This is NOT just rotating a point - each offset represents a full unit
## square extending +1 in X and Z from that corner, so rotating the SQUARE
## as a region (not just its corner) requires an extra -1 correction on
## the new axis its extension direction rotated into. Without this, a
## rotated shape's reference corners move but its extent doesn't rotate
## with them, which is what caused rotated pillars/tiles to register the
## wrong occupied cells even though the visual mesh looked fine.
##
## Verified by construction: applying this 4 times returns the original
## offset exactly (correct order-4 rotation group behavior). Rotation
## DIRECTION (this vs. the mirrored alternative) still needs confirming
## against a real asymmetric shape in-game - if a rotated tile/pillar
## lands in the mirror-image quadrant of where it visually should, swap
## which axis gets the "-1" and which gets negated.
func _rotate_cell_90(cell: Vector3i) -> Vector3i:
	return Vector3i(cell.z, cell.y, -cell.x - 1)


func get_logical_defaults(mesh_item_name: String) -> Dictionary:
	if LOGICAL_OVERRIDES.has(mesh_item_name):
		return LOGICAL_OVERRIDES[mesh_item_name]
	for entry in LOGICAL_DEFAULTS:
		if mesh_item_name.begins_with(entry.prefix):
			return entry
	return {"walkable": true, "blocks_los": false}


## Exact-name overrides for which physical layer a mesh belongs to.
## Anything not listed falls through to the automatic rules in get_layer().
const MESH_LAYER: Dictionary = {
	"tall": "prop",
	"mini": "prop",
	"medium": "prop",
	"stair": "prop",
}

## Returns "floor", "wall", or "prop" for a mesh item name - this is the
## SINGLE source of truth for which GridMap a mesh belongs in. All three
## GridMaps share one MeshLibrary, so nothing else distinguishes "this is a
## floor tile" from "this is a pillar" except this classification - callers
## (CreatorController, LayeredMap) should always derive the destination
## grid from this rather than from separately-tracked UI state, so it's
## structurally impossible to paint a prop into the floor layer by mistake.
func get_layer(mesh_item_name: String) -> String:
	if MESH_LAYER.has(mesh_item_name):
		return MESH_LAYER[mesh_item_name]
	if mesh_item_name.begins_with("wall_"):
		return "wall"
	if _looks_like_tile_face(mesh_item_name):
		return "floor"
	# Most physical components in this game (pillars, stairs, tables,
	# bookshelves, chests, doors...) are props, not floor tiles - only 18
	# named tile faces are actually floor pieces. Prop is the safer default
	# for anything unrecognized.
	return "prop"


## Tile faces are named like "7a" / "12b" - one or more digits followed by
## a single a/b letter. Matching that shape means we don't need a manual
## MESH_LAYER entry for every one of the ~22 tiles.
func _looks_like_tile_face(mesh_item_name: String) -> bool:
	if mesh_item_name.length() < 2:
		return false
	var last_char := mesh_item_name[mesh_item_name.length() - 1]
	if last_char != "a" and last_char != "b":
		return false
	var digits := mesh_item_name.substr(0, mesh_item_name.length() - 1)
	return digits.is_valid_int()


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
