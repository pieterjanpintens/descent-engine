class_name MapPlanValidator
extends RefCounted

## Checks a MAP PLAN - a plain description of a 3D map (floor tiles, hazards, props, where the heroes start and where monsters spawn) -
## against what the game can really hold: only meshes that exist, positions on the grid the pieces snap to, no two floor tiles in the same
## place, props standing on floor, floors above the ground resting on a pillar / stair / gateway that reaches exactly that height, room for
## the figures (2 height units, the Centurion 6), the floor connected through stairs and ladders, no more copies of a physical piece than
## the box has. The fit rules are hard-coded in BuildRules (one table, also readable as text for an AI). It never touches a mission and uses
## no AI; it exists so that whatever produces a plan (later: an AI turning a description or a spoken story into a map) can be checked, and
## told exactly what is wrong, before anything is built. Experimental (branch experiment/ai-map-generation).
##
## THE PLAN (JSON-friendly, everything plain numbers/strings):
##   {
##     "pieces": [ {"mesh": "1a", "x": 0, "z": 0, "rotation": 0, "height": 0, "name": ""}, ... ],
##     "player_start": [ {"x": 1, "z": 1, "height": 0}, ... ],                     (optional; one tile square each)
##     "spawns": [ {"x": 3, "z": 2, "height": 0, "creature": "figure"|"centaur"}, ... ]   (optional)
##   }
## - `mesh`: a name from the mesh library (floor tile faces "1a".."21b", hazards water/acid/lava/spikes, props gate/tree/tall/...).
## - `x`, `z`: the position in GAME UNITS, exactly what the Creator's status bar shows: the first tile square starts at 0, 0 and a piece's
##   position is the near (lowest x/z) corner of the cells it covers, so it does not change when the piece is rotated. Whole numbers for
##   everything except the pillars (tall / medium / mini), which also sit on half units (they stand where tile squares meet).
## - `rotation`: quarter turns 0..3 (90, 180, 270 degrees are accepted too).
## - `height`: height units (see BuildRules). For a floor tile or hazard the height of its walking surface; for any other piece the height of
##   the floor it stands on. Default 0 = ground.
## - `name`: optional reference name.
## - `player_start`: a hero's square (whole numbers). `spawns`: a monster's square; a "centaur" (Centurion) covers 2x2 squares and `x`, `z`
##   is the near corner of that 2x2 area.
##
## validate() returns {ok, errors, warnings, pieces, starts, spawns, usage, bounds, heights}; format_issues() / render_ascii() / render_stack()
## turn that into text.

const MAX_PIECES := 500
const MAX_COORDINATE := 64.0
const MAX_HEIGHT := 9
const MAX_NAME_LENGTH := 60
const MAX_CREATURES := 200
const MESH_LIBRARY_PATH := "res://descent-meshes.tres"

static var _known_meshes: Dictionary = {}


## Every mesh name the game has (the shared mesh library's items). Loaded once.
static func known_meshes() -> Dictionary:
	if _known_meshes.is_empty():
		var library := load(MESH_LIBRARY_PATH) as MeshLibrary
		if library != null:
			for item_id in library.get_item_list():
				_known_meshes[library.get_item_name(item_id)] = true
	return _known_meshes


## Checks `plan` (a Dictionary, see the class doc). Never throws, whatever it is given.
## Returns {
##   "ok": bool                  - no errors (warnings don't count),
##   "errors": Array[Dictionary], "warnings": Array[Dictionary]   - each {severity, code, piece, message}; `piece` = index in plan["pieces"] or -1,
##   "pieces": Array[Dictionary] - the pieces that were readable, normalised: {index, mesh, layer, x, z, height, quarter_turns, name,
##                                 fine_origin (Vector3i), cells (Array[Vector3i], every fine cell it covers), support_cells, solid_cells},
##   "starts" / "spawns": Array[Dictionary] - the readable creature entries, {x, z, height, creature, squares},
##   "usage": Dictionary         - physical group -> copies used,
##   "bounds": Rect2i            - the area covered, in tile squares (empty plan: zero size),
##   "heights": Array[int]       - every height that holds a floor, ascending.
## }
static func validate(plan: Variant) -> Dictionary:
	var result := {"ok": false, "errors": [], "warnings": [], "pieces": [], "starts": [], "spawns": [], "usage": {}, "bounds": Rect2i(), "heights": []}
	if typeof(plan) != TYPE_DICTIONARY:
		_add(result, "error", "bad_format", -1, "The plan must be an object with a \"pieces\" list.")
		return result
	var raw_pieces: Variant = plan.get("pieces", null)
	if typeof(raw_pieces) != TYPE_ARRAY:
		_add(result, "error", "bad_format", -1, "The plan needs a \"pieces\" list.")
		return result
	if raw_pieces.size() > MAX_PIECES:
		_add(result, "error", "too_many_pieces", -1, "The plan has %d pieces; the most allowed is %d." % [raw_pieces.size(), MAX_PIECES])
		return result
	if raw_pieces.is_empty():
		_add(result, "error", "empty", -1, "The plan has no pieces.")
		return result

	var pieces: Array[Dictionary] = []
	for index in raw_pieces.size():
		var piece := _read_piece(raw_pieces[index], index, result)
		if not piece.is_empty():
			pieces.append(piece)
	result["pieces"] = pieces

	var floor_cells := _cells_of(pieces, "floor")
	_check_overlaps(pieces, result)
	var standing := _check_props_on_floor(pieces, floor_cells, result)
	var support := _support_map(pieces, standing)
	_check_floor_support(pieces, support, result)
	_check_creatures(plan, pieces, floor_cells, result)
	_check_connected(pieces, floor_cells, standing, result)
	_check_limits(pieces, result)
	_check_names(pieces, result)
	result["bounds"] = _bounds(pieces)
	var heights: Dictionary = {}
	for key: Vector3i in floor_cells:
		heights[key.y] = true
	var sorted_heights: Array = heights.keys()
	sorted_heights.sort()
	result["heights"] = sorted_heights
	result["ok"] = (result["errors"] as Array).is_empty()
	return result


# ---------------------------------------------------------------- reading one piece

## Turns one entry of the plan into a normalised piece, or an empty Dictionary (with the errors added) when it can't be used.
static func _read_piece(entry: Variant, index: int, result: Dictionary) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		_add(result, "error", "bad_format", index, "Piece %d is not an object." % index)
		return {}
	var mesh_value: Variant = entry.get("mesh", null)
	if typeof(mesh_value) != TYPE_STRING or str(mesh_value) == "":
		_add(result, "error", "bad_format", index, "Piece %d has no \"mesh\" name." % index)
		return {}
	var mesh := str(mesh_value)
	if not known_meshes().has(mesh):
		_add(result, "error", "unknown_mesh", index, "Piece %d: there is no piece called \"%s\"." % [index, mesh])
		return {}
	var x: Variant = entry.get("x", null)
	var z: Variant = entry.get("z", null)
	if not _is_number(x) or not _is_number(z):
		_add(result, "error", "bad_position", index, "Piece %d (\"%s\") needs numeric \"x\" and \"z\"." % [index, mesh])
		return {}
	var fx := float(x)
	var fz := float(z)
	if absf(fx) > MAX_COORDINATE or absf(fz) > MAX_COORDINATE:
		_add(result, "error", "out_of_range", index, "Piece %d (\"%s\"): position %s, %s is outside -%d..%d." % [index, mesh, String.num(fx), String.num(fz), MAX_COORDINATE, MAX_COORDINATE])
		return {}
	# whole numbers, except the pillars which also sit on half units
	var step := 0.5 if FootprintRegistry.allows_fine_placement(mesh) else 1.0
	if not _is_multiple(fx, step) or not _is_multiple(fz, step):
		_add(result, "error", "bad_position", index, "Piece %d (\"%s\"): position %s, %s must be %s." % [index, mesh, String.num(fx), String.num(fz), "a multiple of 0.5" if step == 0.5 else "a whole number"])
		return {}
	var turns := _quarter_turns(entry.get("rotation", 0))
	if turns == -1:
		_add(result, "error", "bad_rotation", index, "Piece %d (\"%s\"): rotation must be 0-3 quarter turns (or 0, 90, 180, 270 degrees)." % [index, mesh])
		return {}
	if entry.has("level"):
		_add(result, "error", "bad_height", index, "Piece %d (\"%s\"): there is no \"level\" any more - use \"height\" in height units." % [index, mesh])
		return {}
	var height := _read_height(entry.get("height", 0))
	if height == -1:
		_add(result, "error", "bad_height", index, "Piece %d (\"%s\"): height must be a whole number from 0 to %d." % [index, mesh, MAX_HEIGHT])
		return {}
	var name_value: Variant = entry.get("name", "")
	var piece_name := str(name_value) if typeof(name_value) == TYPE_STRING else ""
	if piece_name.length() > MAX_NAME_LENGTH:
		_add(result, "error", "bad_format", index, "Piece %d (\"%s\"): the name is longer than %d characters." % [index, mesh, MAX_NAME_LENGTH])
		return {}

	# Exactly the occupancy the Creator/LayeredMap stores: rotate the expanded footprint, anchored by its near corner at the position.
	var basis := Basis(Vector3.UP, deg_to_rad(90.0 * turns))
	var footprint := FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(mesh), basis)
	var min_x: int = footprint[0].x
	var min_z: int = footprint[0].z
	for offset in footprint:
		min_x = mini(min_x, offset.x)
		min_z = mini(min_z, offset.z)
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var origin := Vector3i(roundi(fx * cpt) - min_x, height, roundi(fz * cpt) - min_z)
	var cells: Array[Vector3i] = []
	for offset in footprint:
		cells.append(origin + Vector3i(offset.x, 0, offset.z))
	var support_cells: Array[Vector3i] = []
	if BuildRules.is_support(mesh):
		for offset in FootprintRegistry.rotate_footprint(BuildRules.support_offsets(mesh), basis):
			support_cells.append(origin + Vector3i(offset.x, 0, offset.z))
	var layer := FootprintRegistry.get_layer(mesh)
	var solid_cells: Array[Vector3i] = []
	if layer == "prop":
		for offset in FootprintRegistry.rotate_footprint(BuildRules.solid_offsets(mesh), basis):
			solid_cells.append(origin + Vector3i(offset.x, 0, offset.z))
	return {
		"index": index, "mesh": mesh, "layer": layer,
		"x": fx, "z": fz, "height": height, "quarter_turns": turns, "name": piece_name,
		"fine_origin": origin, "cells": cells, "support_cells": support_cells, "solid_cells": solid_cells,
	}


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _is_multiple(value: float, step: float) -> bool:
	var scaled := value / step
	return absf(scaled - roundf(scaled)) < 0.0001


## A height 0..MAX_HEIGHT as an int; -1 when it is anything else.
static func _read_height(value: Variant) -> int:
	if not _is_number(value) or not _is_multiple(float(value), 1.0):
		return -1
	var whole := roundi(float(value))
	return whole if whole >= 0 and whole <= MAX_HEIGHT else -1


## 0..3 quarter turns from a number of turns or of degrees; -1 when it is neither.
static func _quarter_turns(value: Variant) -> int:
	if not _is_number(value):
		return -1
	var number := float(value)
	if not _is_multiple(number, 1.0):
		return -1
	var whole := roundi(number)
	if whole >= 0 and whole <= 3:
		return whole
	if whole % 90 == 0 and whole >= 0 and whole < 360:
		return whole / 90
	return -1


# ---------------------------------------------------------------- whole-plan checks

## Floor tiles (and hazard cards) never stack in the same spot, so two covering the same cell at the same height is an error (a floor
## ABOVE another one - a bridge - is a different height and is fine). Props may overlap in the game (a gate inside an archway) but that is
## almost never what a generated plan means, so it only warns.
static func _check_overlaps(pieces: Array[Dictionary], result: Dictionary) -> void:
	for layer in ["floor", "underlay", "prop"]:
		var owner_of: Dictionary = {}  # Vector3i fine cell (x, height, z) -> piece
		var reported: Dictionary = {}
		for piece in pieces:
			if piece["layer"] != layer:
				continue
			for cell in piece["cells"]:
				var key := Vector3i(cell.x, piece["height"], cell.z)
				if owner_of.has(key):
					var other: Dictionary = owner_of[key]
					var pair := "%d-%d" % [other["index"], piece["index"]]
					if layer == "prop" and (_inside(piece, other) or _inside(other, piece)):
						continue  # one prop entirely inside another is the legitimate case (a gate in an archway's passage)
					if not reported.has(pair):
						reported[pair] = true
						_add(result, "error" if layer != "prop" else "warning", "%s_overlap" % layer, piece["index"],
							"Piece %d %s overlaps piece %d %s (both %s%s)." % [piece["index"], _describe(piece), other["index"], _describe(other), layer, " pieces" if layer == "prop" else " tiles"])
				else:
					owner_of[key] = piece


## True when every cell of `inner` is also a cell of `outer` (at the same height).
static func _inside(inner: Dictionary, outer: Dictionary) -> bool:
	if inner["height"] != outer["height"]:
		return false
	var cells: Dictionary = {}
	for cell in outer["cells"]:
		cells[cell] = true
	for cell in inner["cells"]:
		if not cells.has(cell):
			return false
	return true


## A prop has to stand on floor: every cell it covers needs floor at its own height. Returns the indices of the props that do (only those
## can hold anything up or help anyone climb).
static func _check_props_on_floor(pieces: Array[Dictionary], floor_cells: Dictionary, result: Dictionary) -> Dictionary:
	var standing: Dictionary = {}
	for piece in pieces:
		if piece["layer"] != "prop":
			continue
		var missing := 0
		for cell in piece["cells"]:
			if not floor_cells.has(Vector3i(cell.x, piece["height"], cell.z)):
				missing += 1
		if missing > 0:
			_add(result, "error", "floating_prop", piece["index"],
				"Piece %d %s is not fully on floor: %d of its %d cells have no floor tile under them at height %d." % [piece["index"], _describe(piece), missing, (piece["cells"] as Array).size(), piece["height"]])
		else:
			standing[piece["index"]] = true
	return standing


## Everything a floor can rest on: fine cell (x, height, z) -> the pieces that hold a floor there. A support stands on a floor at height b and
## holds floor at b + each of its rises (BuildRules.SUPPORT_RISES).
static func _support_map(pieces: Array[Dictionary], standing: Dictionary) -> Dictionary:
	var support: Dictionary = {}
	for piece in pieces:
		if not standing.has(piece["index"]):
			continue
		for rise: int in BuildRules.support_rises(piece["mesh"]):
			for cell in piece["support_cells"]:
				var key := Vector3i(cell.x, piece["height"] + rise, cell.z)
				if not support.has(key):
					support[key] = []
				support[key].append(piece["index"])
	return support


## A floor above the ground needs something under it that reaches exactly its height.
static func _check_floor_support(pieces: Array[Dictionary], support: Dictionary, result: Dictionary) -> void:
	for piece in pieces:
		if piece["layer"] != "floor" or piece["height"] == 0:
			continue
		var held := false
		for cell in piece["cells"]:
			if support.has(Vector3i(cell.x, piece["height"], cell.z)):
				held = true
				break
		if not held:
			_add(result, "error", "unsupported_floor", piece["index"],
				"Piece %d %s is a floor at height %d but nothing holds it up: it needs a pillar, a stair's high end or a gateway top reaching exactly height %d under at least one of its squares (the support must itself stand on floor)." % [piece["index"], _describe(piece), piece["height"], piece["height"]])


## Heroes and monsters: they stand on floor at their height, not inside a blocking prop, with enough free height above them.
static func _check_creatures(plan: Dictionary, pieces: Array[Dictionary], floor_cells: Dictionary, result: Dictionary) -> void:
	var blocked: Dictionary = {}  # (x, height, z) -> piece index that blocks walking there
	var ceilings: Dictionary = {}  # Vector2i fine column -> Array[int] heights of solid things (floors above, gateway tops)
	for key: Vector3i in floor_cells:
		var column := Vector2i(key.x, key.z)
		if not ceilings.has(column):
			ceilings[column] = []
		ceilings[column].append(key.y)
	for piece in pieces:
		if piece["layer"] != "prop":
			continue
		for cell in piece["solid_cells"]:
			blocked[Vector3i(cell.x, piece["height"], cell.z)] = piece["index"]
		if BuildRules.CEILING_RISES.has(piece["mesh"]):
			for cell in piece["cells"]:
				var column := Vector2i(cell.x, cell.z)
				if not ceilings.has(column):
					ceilings[column] = []
				ceilings[column].append(piece["height"] + int(BuildRules.CEILING_RISES[piece["mesh"]]))

	var taken: Dictionary = {}  # (square x, height, square z) -> label, to warn about two creatures on one square
	var starts: Variant = plan.get("player_start", [])
	if typeof(starts) != TYPE_ARRAY:
		_add(result, "error", "bad_format", -1, "\"player_start\" must be a list of {x, z} squares.")
	else:
		for i in starts.size():
			var creature := _read_creature(starts[i], "Player start %d" % i, "figure", result)
			if creature.is_empty():
				continue
			(result["starts"] as Array).append(creature)
			_check_creature(creature, "Player start %d" % i, floor_cells, blocked, ceilings, taken, result)
	var spawns: Variant = plan.get("spawns", [])
	if typeof(spawns) != TYPE_ARRAY:
		_add(result, "error", "bad_format", -1, "\"spawns\" must be a list of {x, z, creature} squares.")
	else:
		if spawns.size() + (starts.size() if typeof(starts) == TYPE_ARRAY else 0) > MAX_CREATURES:
			_add(result, "error", "too_many_pieces", -1, "Too many creatures (the most allowed is %d)." % MAX_CREATURES)
			return
		for i in spawns.size():
			var creature := _read_creature(spawns[i], "Spawn %d" % i, "", result)
			if creature.is_empty():
				continue
			(result["spawns"] as Array).append(creature)
			_check_creature(creature, "Spawn %d" % i, floor_cells, blocked, ceilings, taken, result)


## A creature entry as {x, z, height, creature, squares (side length in squares), need (free height units)}; empty when unusable.
static func _read_creature(entry: Variant, label: String, forced_kind: String, result: Dictionary) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY or not _is_number(entry.get("x", null)) or not _is_number(entry.get("z", null)):
		_add(result, "error", "bad_creature", -1, "%s needs numeric \"x\" and \"z\"." % label)
		return {}
	var fx := float(entry["x"])
	var fz := float(entry["z"])
	if not _is_multiple(fx, 1.0) or not _is_multiple(fz, 1.0) or absf(fx) > MAX_COORDINATE or absf(fz) > MAX_COORDINATE:
		_add(result, "error", "bad_creature", -1, "%s (%s, %s) must be a whole tile square inside -%d..%d." % [label, String.num(fx), String.num(fz), MAX_COORDINATE, MAX_COORDINATE])
		return {}
	var height := _read_height(entry.get("height", 0))
	if height == -1:
		_add(result, "error", "bad_creature", -1, "%s: height must be a whole number from 0 to %d." % [label, MAX_HEIGHT])
		return {}
	var kind := forced_kind
	if kind == "":
		kind = str(entry.get("creature", "figure"))
	if kind != "figure" and kind != "centaur":
		_add(result, "error", "bad_creature", -1, "%s: creature must be \"figure\" or \"centaur\" (the Centurion)." % label)
		return {}
	var big := kind == "centaur"
	return {
		"x": roundi(fx), "z": roundi(fz), "height": height, "creature": kind,
		"squares": BuildRules.CENTAUR_SQUARES if big else 1,
		"need": BuildRules.CENTAUR_HEIGHT if big else BuildRules.FIGURE_HEIGHT,
	}


static func _check_creature(creature: Dictionary, label: String, floor_cells: Dictionary, blocked: Dictionary, ceilings: Dictionary, taken: Dictionary, result: Dictionary) -> void:
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var side: int = creature["squares"]
	var height: int = creature["height"]
	var need: int = creature["need"]
	var off_floor := false
	var blocker := -1
	var room := 1 << 20
	for sx in side:
		for sz in side:
			var square := Vector3i(creature["x"] + sx, height, creature["z"] + sz)
			if taken.has(square):
				_add(result, "warning", "creature_overlap", -1, "%s shares the square %d, %d with %s." % [label, square.x, square.z, taken[square]])
			taken[square] = label
			for dx in cpt:
				for dz in cpt:
					var cell := Vector3i(square.x * cpt + dx, height, square.z * cpt + dz)
					if not floor_cells.has(cell):
						off_floor = true
					if blocked.has(cell):
						blocker = blocked[cell]
					for above: int in ceilings.get(Vector2i(cell.x, cell.z), []):
						if above > height:
							room = mini(room, above - height)
	var where := "(%d, %d, height %d)" % [creature["x"], creature["z"], height]
	if off_floor:
		_add(result, "error", "creature_off_floor", -1, "%s %s is not on floor at height %d." % [label, where, height])
	elif blocker != -1:
		_add(result, "error", "creature_blocked", -1, "%s %s is inside piece %d, which blocks walking." % [label, where, blocker])
	elif room < need:
		_add(result, "error", "no_headroom", -1, "%s %s has only %d height units free above it but a %s needs %d - never put it under a bridge, floor or gateway." % [label, where, room, "Centurion" if creature["creature"] == "centaur" else "figure", need])


## The walkable floor should be one connected area: floors at one height connect by touching, floors at different heights only through a
## stair (its high end touches the upper floor) or a ladder (the upper floor touches the ladder's square). Solid pieces are ignored here
## (see below). Several separate groups is an ERROR - a part of the map nobody can reach is a design flaw.
static func _check_connected(pieces: Array[Dictionary], floor_cells: Dictionary, standing: Dictionary, result: Dictionary) -> void:
	# Walkable = all the floor. Solid pieces are NOT taken out: gates open, barricades get destroyed, and a room walled off for good would be
	# pointless, so only the floor itself (touching tiles, stairs, ladders) decides whether the map hangs together.
	var walkable: Dictionary = floor_cells
	# label every walkable island: touching cells at one height
	var island_of: Dictionary = {}  # Vector3i -> island id
	var island_height: Array[int] = []
	var island_cells: Array[int] = []
	for start: Vector3i in walkable:
		if island_of.has(start):
			continue
		var id := island_height.size()
		island_height.append(start.y)
		island_cells.append(0)
		var stack: Array[Vector3i] = [start]
		island_of[start] = id
		while not stack.is_empty():
			var current: Vector3i = stack.pop_back()
			island_cells[id] += 1
			for step in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				var next: Vector3i = current + step
				if walkable.has(next) and not island_of.has(next):
					island_of[next] = id
					stack.append(next)
	if island_height.is_empty():
		return
	var parent: Array[int] = []
	for i in island_height.size():
		parent.append(i)
	var union := func(a: int, b: int):
		var root_a := a
		while parent[root_a] != root_a:
			root_a = parent[root_a]
		var root_b := b
		while parent[root_b] != root_b:
			root_b = parent[root_b]
		if root_a != root_b:
			parent[root_b] = root_a
	for piece in pieces:
		if piece["layer"] != "prop" or not standing.has(piece["index"]):
			continue
		if piece["mesh"] == "stair":
			# the stair stands in the island of the floor it is on; its high end links to the floor one unit up that it holds or touches
			var base := -1
			for cell in piece["cells"]:
				var key := Vector3i(cell.x, piece["height"], cell.z)
				if island_of.has(key):
					base = island_of[key]
					break
			if base == -1:
				continue
			for rise: int in BuildRules.support_rises("stair"):
				for cell in piece["support_cells"]:
					for offset in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
						var upper := Vector3i(cell.x + offset.x, piece["height"] + rise, cell.z + offset.z)
						if island_of.has(upper):
							union.call(base, island_of[upper])
		var climbs := BuildRules.climb_rises(piece["mesh"])
		if not climbs.is_empty():
			# a ladder is solid: it links every island touching it at its own height with every island touching it `rise` units up
			var covered: Dictionary = {}
			for cell in piece["cells"]:
				covered[Vector2i(cell.x, cell.z)] = true
			var touching: Array[Vector2i] = []
			for column: Vector2i in covered:
				for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next: Vector2i = column + offset
					if not covered.has(next):
						touching.append(next)
			var lower: Array[int] = []
			for column in touching:
				var key := Vector3i(column.x, piece["height"], column.y)
				if island_of.has(key) and not lower.has(island_of[key]):
					lower.append(island_of[key])
			for rise: int in climbs:
				for column in touching:
					var upper := Vector3i(column.x, piece["height"] + rise, column.y)
					if island_of.has(upper):
						for low_island in lower:
							union.call(low_island, island_of[upper])
	# summarise the groups
	var groups: Dictionary = {}  # root -> {heights: {h: true}, cells: n}
	for i in island_height.size():
		var root := i
		while parent[root] != root:
			root = parent[root]
		if not groups.has(root):
			groups[root] = {"heights": {}, "cells": 0}
		groups[root]["heights"][island_height[i]] = true
		groups[root]["cells"] += island_cells[i]
	if groups.size() > 1:
		var parts: Array[String] = []
		var number := 1
		for root: int in groups:
			var heights: Array = groups[root]["heights"].keys()
			heights.sort()
			parts.append("group %d: height%s %s, about %d squares" % [number, "s" if heights.size() > 1 else "", ", ".join(heights.map(func(h): return str(h))), int(round(float(groups[root]["cells"]) / 4.0))])
			number += 1
		_add(result, "error", "disconnected_floor", -1, "The walkable floor is in %d separate groups that do not connect (%s). Floors at different heights connect only through a stair or ladder." % [groups.size(), "; ".join(parts)])


## Copies used per physical piece (the two faces of a tile, or of a hazard card, are ONE piece) against what the box has.
static func _check_limits(pieces: Array[Dictionary], result: Dictionary) -> void:
	var usage: Dictionary = {}
	for piece in pieces:
		var group := ComponentInventory.get_group(piece["mesh"])
		usage[group] = int(usage.get(group, 0)) + 1
	result["usage"] = usage
	for group: String in usage:
		var maximum := ComponentInventory.get_max_count(group)
		if maximum >= 0 and int(usage[group]) > maximum:
			_add(result, "error", "over_limit", -1, "The plan uses %d of \"%s\" but the box only has %d." % [usage[group], group, maximum])


static func _check_names(pieces: Array[Dictionary], result: Dictionary) -> void:
	var seen: Dictionary = {}
	for piece in pieces:
		var piece_name: String = piece["name"]
		if piece_name == "":
			continue
		if seen.has(piece_name):
			_add(result, "warning", "duplicate_name", piece["index"], "Piece %d %s has the same name \"%s\" as piece %d." % [piece["index"], _describe(piece), piece_name, seen[piece_name]])
		else:
			seen[piece_name] = piece["index"]


# ---------------------------------------------------------------- helpers

## Every fine cell of the pieces on `layer`, as (x, height, z).
static func _cells_of(pieces: Array[Dictionary], layer: String) -> Dictionary:
	var cells: Dictionary = {}
	for piece in pieces:
		if piece["layer"] == layer:
			for cell in piece["cells"]:
				cells[Vector3i(cell.x, piece["height"], cell.z)] = true
	return cells


static func _bounds(pieces: Array[Dictionary]) -> Rect2i:
	if pieces.is_empty():
		return Rect2i()
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var low := Vector2i(1 << 30, 1 << 30)
	var high := Vector2i(-(1 << 30), -(1 << 30))
	for piece in pieces:
		for cell in piece["cells"]:
			low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.z))
			high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.z))
	var first := Vector2i(floori(float(low.x) / cpt), floori(float(low.y) / cpt))
	var last := Vector2i(floori(float(high.x) / cpt), floori(float(high.y) / cpt))
	return Rect2i(first, last - first + Vector2i.ONE)


static func _describe(piece: Dictionary) -> String:
	var where := "%s, %s" % [String.num(piece["x"]), String.num(piece["z"])]
	if piece["height"] > 0:
		where += ", height %d" % piece["height"]
	return "(\"%s\" at %s)" % [piece["mesh"], where]


static func _add(result: Dictionary, severity: String, code: String, piece: int, message: String) -> void:
	var bucket: Array = result["errors"] if severity == "error" else result["warnings"]
	bucket.append({"severity": severity, "code": code, "piece": piece, "message": message})


# ---------------------------------------------------------------- text output

## The problems as plain lines, errors first - what gets shown to an author, or handed back to an AI so it can repair its plan.
static func format_issues(result: Dictionary) -> String:
	var lines: Array[String] = []
	for issue: Dictionary in result["errors"]:
		lines.append("ERROR: " + str(issue["message"]))
	for issue: Dictionary in result["warnings"]:
		lines.append("Warning: " + str(issue["message"]))
	if lines.is_empty():
		lines.append("No problems found.")
	return "\n".join(lines)


## A text picture of the pieces at one HEIGHT at tile-square resolution (x to the right, z downwards): '.' floor, '#' solid prop (or an
## archway's end post), 'x' a removable solid (gate, fence, barricade), 'g' an archway's passage, 'o' any other passable prop (stairs, tokens), '~' hazard with no floor over it, 'S' a hero's start, 'M' a monster spawn, 'C' a Centurion
## (2x2), ' ' empty. Creatures win over props, props over floor. Props show at the height of the floor they stand on.
static func render_ascii(result: Dictionary, height: int = 0) -> String:
	var bounds: Rect2i = result["bounds"]
	if bounds.size == Vector2i.ZERO:
		return ""
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var grid: Dictionary = {}  # Vector2i tile square -> char
	var rank := {"~": 1, ".": 2, "o": 3, "g": 4, "x": 5, "#": 5, "S": 6, "M": 6, "C": 7}
	for piece: Dictionary in result["pieces"]:
		if piece["height"] != height:
			continue
		var solid_here: Dictionary = {}
		for cell in piece["solid_cells"]:
			solid_here[cell] = true
		for cell in piece["cells"]:
			var symbol := "."
			if piece["layer"] == "underlay":
				symbol = "~"
			elif piece["layer"] == "prop":
				if BuildRules.REMOVABLE.has(piece["mesh"]):
					symbol = "x"
				elif solid_here.has(cell):
					symbol = "#"
				elif piece["mesh"] == "archway":
					symbol = "g"
				else:
					symbol = "o"
			var square := Vector2i(floori(float(cell.x) / cpt), floori(float(cell.z) / cpt))
			if symbol == "~" and grid.has(square):
				continue  # a hazard only shows where there is no floor over it
			if not grid.has(square) or rank[symbol] >= rank[grid[square]]:
				grid[square] = symbol
	for entry: Dictionary in result["starts"]:
		if entry["height"] == height:
			grid[Vector2i(entry["x"], entry["z"])] = "S"
	for entry: Dictionary in result["spawns"]:
		if entry["height"] != height:
			continue
		for sx in entry["squares"]:
			for sz in entry["squares"]:
				grid[Vector2i(entry["x"] + sx, entry["z"] + sz)] = "C" if entry["creature"] == "centaur" else "M"
	var lines: Array[String] = []
	for z in range(bounds.position.y, bounds.end.y):
		var line := ""
		for x in range(bounds.position.x, bounds.end.x):
			line += str(grid.get(Vector2i(x, z), " "))
		lines.append(line)
	return "\n".join(lines)


## Every height that has anything in it, one picture each, labelled - the "layers" of the map.
static func render_stack(result: Dictionary) -> String:
	var used: Dictionary = {}
	for piece: Dictionary in result["pieces"]:
		used[piece["height"]] = true
	var heights: Array = used.keys()
	heights.sort()
	var parts: Array[String] = []
	for height: int in heights:
		parts.append("height %d:\n%s" % [height, render_ascii(result, height)])
	return "\n\n".join(parts)
