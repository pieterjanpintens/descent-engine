class_name MapPlanValidator
extends RefCounted

## Checks a MAP PLAN - a plain description of a map (floor tiles, hazards and props at coordinates) - against what the game can really
## hold: only meshes that exist, positions on the grid the pieces snap to, no two floor tiles on top of each other, props standing on floor,
## no more copies of a physical piece than the box has, the floor in one piece, a player start that is on floor and not inside a pillar.
## It never touches a mission and uses no AI; it exists so that whatever produces a plan (later: an AI turning a description or a spoken
## story into a map) can be checked, and told exactly what is wrong, before anything is built. Experimental (branch experiment/ai-map-generation).
##
## THE PLAN (JSON-friendly, everything plain numbers/strings):
##   {
##     "pieces": [
##       {"mesh": "1a", "x": 0, "z": 0, "rotation": 0, "level": 0, "name": ""},
##       ...
##     ],
##     "player_start": [{"x": 1, "z": 1}, ...]      (optional; tile squares the heroes start on)
##   }
## - `mesh`: a name from the mesh library (floor tile faces "1a".."21b", hazards water/acid/lava/spikes, props gate/tree/tall/...).
## - `x`, `z`: the position in GAME UNITS, exactly what the Creator's status bar shows: the first tile square starts at 0, 0 and a
##   piece's position is the near (lowest x/z) corner of the cells it covers, so it does not change when the piece is rotated. Whole
##   numbers for everything except the pillars (tall / mini / medium), which also sit on half units (they stand where tile squares meet).
## - `rotation`: quarter turns 0..3 (90, 180, 270 degrees are accepted too). `level`: the height, 0 = ground floor. `name`: optional reference name.
##
## validate() returns {ok, errors, warnings, pieces, usage, bounds}; see its doc. format_issues() / render_ascii() turn that into text.

const MAX_PIECES := 500
const MAX_COORDINATE := 64.0
const MAX_LEVEL := 5
const MAX_NAME_LENGTH := 60
const MESH_LIBRARY_PATH := "res://descent-meshes.tres"
## Props that don't need floor under them: a stair joins two levels.
const NEEDS_NO_FLOOR: Array[String] = ["stair"]

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
##   "pieces": Array[Dictionary] - the pieces that were readable, normalised: {index, mesh, layer, x, z, level, quarter_turns, name,
##                                 fine_origin (Vector3i), cells (Array[Vector3i], every fine cell it covers)},
##   "usage": Dictionary         - physical group -> copies used,
##   "bounds": Rect2i            - the area covered, in tile squares (empty plan: zero size).
## }
static func validate(plan: Variant) -> Dictionary:
	var result := {"ok": false, "errors": [], "warnings": [], "pieces": [], "usage": {}, "bounds": Rect2i()}
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

	_check_overlaps(pieces, result)
	_check_props_on_floor(pieces, result)
	_check_limits(pieces, result)
	_check_floor_connected(pieces, result)
	_check_names(pieces, result)
	_check_player_start(plan.get("player_start", []), pieces, result)
	result["bounds"] = _bounds(pieces)
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
	var level_value: Variant = entry.get("level", 0)
	if not _is_number(level_value) or not _is_multiple(float(level_value), 1.0) or int(level_value) < 0 or int(level_value) > MAX_LEVEL:
		_add(result, "error", "bad_level", index, "Piece %d (\"%s\"): level must be a whole number from 0 to %d." % [index, mesh, MAX_LEVEL])
		return {}
	var level := int(level_value)
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
	var origin := Vector3i(roundi(fx * cpt) - min_x, level, roundi(fz * cpt) - min_z)
	var cells: Array[Vector3i] = []
	for offset in footprint:
		cells.append(origin + Vector3i(offset.x, 0, offset.z))
	return {
		"index": index, "mesh": mesh, "layer": FootprintRegistry.get_layer(mesh),
		"x": fx, "z": fz, "level": level, "quarter_turns": turns, "name": piece_name,
		"fine_origin": origin, "cells": cells,
	}


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _is_multiple(value: float, step: float) -> bool:
	var scaled := value / step
	return absf(scaled - roundf(scaled)) < 0.0001


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

## Floor tiles (and hazard cards) never stack, so two covering the same cell at one level is an error; props may overlap in
## the game (a gate inside an archway) but that is almost never what a generated plan means, so it only warns.
static func _check_overlaps(pieces: Array[Dictionary], result: Dictionary) -> void:
	for layer in ["floor", "underlay", "prop"]:
		var owner_of: Dictionary = {}  # Vector3i fine cell (with level) -> piece
		var reported: Dictionary = {}
		for piece in pieces:
			if piece["layer"] != layer:
				continue
			for cell in piece["cells"]:
				var key := Vector3i(cell.x, piece["level"], cell.z)
				if owner_of.has(key):
					var other: Dictionary = owner_of[key]
					var pair := "%d-%d" % [other["index"], piece["index"]]
					if not reported.has(pair):
						reported[pair] = true
						_add(result, "error" if layer != "prop" else "warning", "%s_overlap" % layer, piece["index"],
							"Piece %d %s overlaps piece %d %s (both %s%s)." % [piece["index"], _describe(piece), other["index"], _describe(other), layer, " pieces" if layer == "prop" else " tiles"])
				else:
					owner_of[key] = piece


## A prop has to stand on floor: every cell it covers needs floor at its own level (stairs excepted).
static func _check_props_on_floor(pieces: Array[Dictionary], result: Dictionary) -> void:
	var floor_cells := _cells_of(pieces, "floor")
	for piece in pieces:
		if piece["layer"] != "prop" or NEEDS_NO_FLOOR.has(piece["mesh"]):
			continue
		var missing := 0
		for cell in piece["cells"]:
			if not floor_cells.has(Vector3i(cell.x, piece["level"], cell.z)):
				missing += 1
		if missing > 0:
			_add(result, "error", "floating_prop", piece["index"],
				"Piece %d %s is not fully on floor: %d of its %d cells have no floor tile under them at level %d." % [piece["index"], _describe(piece), missing, (piece["cells"] as Array).size(), piece["level"]])


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


## The floor of one level should be one connected area (heroes walk between tiles); several separate islands at the same level
## are probably a mistake - a warning, since levels may legitimately be joined by stairs elsewhere.
static func _check_floor_connected(pieces: Array[Dictionary], result: Dictionary) -> void:
	var by_level: Dictionary = {}  # level -> {cell: true}
	for piece in pieces:
		if piece["layer"] != "floor":
			continue
		if not by_level.has(piece["level"]):
			by_level[piece["level"]] = {}
		for cell in piece["cells"]:
			by_level[piece["level"]][Vector2i(cell.x, cell.z)] = true
	for level: int in by_level:
		var cells: Dictionary = by_level[level]
		var seen: Dictionary = {}
		var islands := 0
		for start: Vector2i in cells:
			if seen.has(start):
				continue
			islands += 1
			var stack: Array[Vector2i] = [start]
			seen[start] = true
			while not stack.is_empty():
				var current: Vector2i = stack.pop_back()
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next: Vector2i = current + step
					if cells.has(next) and not seen.has(next):
						seen[next] = true
						stack.append(next)
		if islands > 1:
			_add(result, "warning", "disconnected_floor", -1, "The floor at level %d is in %d separate pieces that do not touch." % [level, islands])


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


## Player start squares: whole tile squares on floor, not under something that blocks walking (pillar, tree).
static func _check_player_start(starts: Variant, pieces: Array[Dictionary], result: Dictionary) -> void:
	if typeof(starts) != TYPE_ARRAY:
		_add(result, "error", "bad_format", -1, "\"player_start\" must be a list of {x, z} squares.")
		return
	var floor_cells := _cells_of(pieces, "floor")
	var blocked: Dictionary = {}
	for piece in pieces:
		if piece["layer"] == "prop" and not FootprintRegistry.get_logical_defaults(piece["mesh"]).get("walkable", true):
			for cell in piece["cells"]:
				blocked[Vector3i(cell.x, piece["level"], cell.z)] = piece["index"]
	var cpt := FootprintRegistry.CELLS_PER_TILE
	for i in starts.size():
		var entry: Variant = starts[i]
		if typeof(entry) != TYPE_DICTIONARY or not _is_number(entry.get("x", null)) or not _is_number(entry.get("z", null)):
			_add(result, "error", "bad_start", -1, "Player start %d needs numeric \"x\" and \"z\"." % i)
			continue
		var fx := float(entry["x"])
		var fz := float(entry["z"])
		if not _is_multiple(fx, 1.0) or not _is_multiple(fz, 1.0):
			_add(result, "error", "bad_start", -1, "Player start %d (%s, %s) must be a whole tile square." % [i, String.num(fx), String.num(fz)])
			continue
		var level_value: Variant = entry.get("level", 0)
		var level := int(level_value) if _is_number(level_value) else 0
		# all four fine cells of the square must be floor, none of them blocked
		var all_floor := true
		var blocker := -1
		for dx in cpt:
			for dz in cpt:
				var cell := Vector3i(roundi(fx) * cpt + dx, level, roundi(fz) * cpt + dz)
				if not floor_cells.has(cell):
					all_floor = false
				if blocked.has(cell):
					blocker = blocked[cell]
		if not all_floor:
			_add(result, "error", "start_off_floor", -1, "Player start %d (%s, %s) is not on floor at level %d." % [i, String.num(fx), String.num(fz), level])
		elif blocker != -1:
			_add(result, "error", "start_blocked", -1, "Player start %d (%s, %s) is inside piece %d, which blocks walking." % [i, String.num(fx), String.num(fz), blocker])


# ---------------------------------------------------------------- helpers

static func _cells_of(pieces: Array[Dictionary], layer: String) -> Dictionary:
	var cells: Dictionary = {}
	for piece in pieces:
		if piece["layer"] == layer:
			for cell in piece["cells"]:
				cells[Vector3i(cell.x, piece["level"], cell.z)] = true
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
	return "(\"%s\" at %s, %s)" % [piece["mesh"], String.num(piece["x"]), String.num(piece["z"])]


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


## A text picture of one level at tile-square resolution (x to the right, z downwards): '.' floor, '#' pillar/tree/other blocking prop,
## 'g' gate/fence/archway, 'o' any other prop, '~' hazard with no floor over it, ' ' empty. Props win over floor.
static func render_ascii(result: Dictionary, level: int = 0) -> String:
	var bounds: Rect2i = result["bounds"]
	if bounds.size == Vector2i.ZERO:
		return ""
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var grid: Dictionary = {}  # Vector2i tile square -> char
	for piece: Dictionary in result["pieces"]:
		if piece["level"] != level:
			continue
		var symbol := "."
		match piece["layer"]:
			"underlay":
				symbol = "~"
			"prop":
				var mesh: String = piece["mesh"]
				if not FootprintRegistry.get_logical_defaults(mesh).get("walkable", true):
					symbol = "#"
				elif mesh in ["gate", "fence", "archway"]:
					symbol = "g"
				else:
					symbol = "o"
		var rank := {"~": 1, ".": 2, "o": 3, "g": 4, "#": 5}
		for cell in piece["cells"]:
			var square := Vector2i(floori(float(cell.x) / cpt), floori(float(cell.z) / cpt))
			if symbol == "~" and grid.has(square):
				continue  # a hazard only shows where there is no floor over it
			if not grid.has(square) or rank[symbol] >= rank[grid[square]]:
				grid[square] = symbol
	var lines: Array[String] = []
	for z in range(bounds.position.y, bounds.end.y):
		var line := ""
		for x in range(bounds.position.x, bounds.end.x):
			line += str(grid.get(Vector2i(x, z), " "))
		lines.append(line)
	return "\n".join(lines)
