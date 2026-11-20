class_name TableSetup
extends RefCounted

## The plan behind the setup sheet (TableSetupSheet): where the whole map of the Table being set up goes on the player's real table,
## where to start building, and - with a table camera - where the camera stands and what it sees. Pure data, no scene nodes.
##
## Sheet coordinates, in cm, as seen from above with the player's side at the bottom: X from the table's left edge to the right,
## Y from the table's far edge towards the player (so the near edge is Y = depth). The map is drawn like the editor's top view
## (board x to the right, board z down) when its long side matches the table's long side; otherwise it is turned a quarter.
##
## `plan(mission, table_cm, square_cm, camera)` returns {map_squares, start_squares, rotated, map_cm, fits, offset, start_rect,
## start_side (cm to the nearer short side), start_from_right, start_near (cm to the player's edge), camera} where camera = {} without a camera, else {side ("left" / "right"), position (Vector2 sheet,
## outside the table), height, back, sees_all, needed_height (-1 = none up to MAX_HEIGHT), coverage (PackedVector2Array, the
## part of the table in the picture)}.

## The camera's half field of view (tangents) of a phone held upright: about the user's phone's main lens. A calibration of the real
## camera replaces them.
const DEFAULT_TAN_ACROSS := 0.433
const DEFAULT_TAN_ALONG := 0.578
const MAX_HEIGHT := 200.0
const MIN_HEIGHT := 15.0
## How much of the photo's edge stays free around the map (as a fraction of the half picture).
const MARGIN := 0.04
const FAR_CLIP := 400.0


static func plan(mission: MissionData, table_cm: Vector2, square_cm: float, camera: Dictionary = {}) -> Dictionary:
	var map_squares := table_squares(mission)
	var start_squares := start_area(mission, map_squares)
	var result := {"map_squares": map_squares, "start_squares": start_squares, "rotated": false, "map_cm": Vector2.ZERO,
		"fits": true, "offset": Vector2.ZERO, "start_rect": Rect2(), "start_side": 0.0, "start_from_right": false, "start_near": 0.0, "camera": {},
		"low": Vector2i.ZERO, "span": Vector2i.ZERO}
	if map_squares.is_empty() or square_cm <= 0.0:
		return result
	var low := Vector2i(1 << 20, 1 << 20)
	var high := Vector2i(-(1 << 20), -(1 << 20))
	for sq: Vector2i in map_squares:
		low = Vector2i(mini(low.x, sq.x), mini(low.y, sq.y))
		high = Vector2i(maxi(high.x, sq.x), maxi(high.y, sq.y))
	var span := high - low + Vector2i.ONE
	var table := Vector2(maxf(table_cm.x, table_cm.y), minf(table_cm.x, table_cm.y))  # long side across the sheet
	var rotated := span.y > span.x
	var map_cm := Vector2(span.y, span.x) * square_cm if rotated else Vector2(span) * square_cm
	result["rotated"] = rotated
	result["low"] = low
	result["span"] = span
	result["map_cm"] = map_cm
	result["fits"] = map_cm.x <= table.x + 0.01 and map_cm.y <= table.y + 0.01
	result["table"] = table
	result["offset"] = (table - map_cm) * 0.5
	result["square_cm"] = square_cm
	if not start_squares.is_empty():
		var start := Rect2()
		var first := true
		for sq: Vector2i in start_squares:
			var box := square_rect(result, sq)
			start = box if first else start.merge(box)
			first = false
		result["start_rect"] = start
		# measured from the nearer short side, so the number stays small
		var from_right := start.get_center().x > table.x * 0.5
		result["start_from_right"] = from_right
		result["start_side"] = table.x - start.end.x if from_right else start.position.x
		result["start_near"] = table.y - start.end.y
	if camera.get("on", false):
		result["camera"] = _camera_plan(result, camera)
	return result


## Sheet position (cm) of a board point (in squares; a square's near corner is its own coordinates).
static func to_sheet(p: Dictionary, board: Vector2) -> Vector2:
	var low: Vector2i = p["low"]
	var span: Vector2i = p["span"]
	var sq: float = p["square_cm"]
	var local := board - Vector2(low)
	var turned := Vector2(span.y - local.y, local.x) if p["rotated"] else local
	return (p["offset"] as Vector2) + turned * sq


## The sheet rectangle a board square covers.
static func square_rect(p: Dictionary, sq: Vector2i) -> Rect2:
	var a := to_sheet(p, Vector2(sq))
	var b := to_sheet(p, Vector2(sq) + Vector2.ONE)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs())


## Every square of the Table on the table (floor and hazard cards, all stages - also those not revealed yet): {Vector2i (x, z): true}.
static func table_squares(mission: MissionData) -> Dictionary:
	var squares := {}
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var pairs := [[mission.floor_placements, mission.floor_occupied_cells], [mission.underlay_placements, mission.underlay_occupied_cells]]
	for pair in pairs:
		var origins := {}
		for placement: TilePlacement in pair[0]:
			if mission.table_of(placement) == mission.active_table_id:
				origins[placement.origin_cell] = true
		var occupied: Dictionary = pair[1]
		for fine: Vector3i in occupied:
			if origins.has(occupied[fine]):
				squares[Vector2i(floori(float(fine.x) / cpt), floori(float(fine.z) / cpt))] = true
	return squares


## The squares of the stage(s) the heroes start in (MissionData.find_starting_group_ids()); for a mission without stages, the floor
## that is shown at the start (everything visible).
static func start_area(mission: MissionData, map_squares: Dictionary) -> Dictionary:
	var start_ids := mission.find_starting_group_ids()
	var parent_of := {}
	for group in mission.groups:
		parent_of[group.id] = group.parent_id
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var origins := {}
	for placement in mission.floor_placements:
		if mission.table_of(placement) != mission.active_table_id:
			continue
		var take := false
		if start_ids.is_empty():
			take = mission.is_effectively_visible(placement)
		else:
			var walk := placement.parent_id
			var guard := mission.groups.size() + 1
			while walk != "" and guard > 0:
				if start_ids.has(walk):
					take = true
					break
				walk = str(parent_of.get(walk, ""))
				guard -= 1
		if take:
			origins[placement.origin_cell] = true
	var squares := {}
	for fine: Vector3i in mission.floor_occupied_cells:
		if origins.has(mission.floor_occupied_cells[fine]):
			var sq := Vector2i(floori(float(fine.x) / cpt), floori(float(fine.z) / cpt))
			if map_squares.has(sq):
				squares[sq] = true
	return squares


# ---------------------------------------------------------------- the camera

## The camera stands in the middle of the short side nearest the start area, `back` cm behind the edge, `height` cm above the
## table, looking along the table and tilted so the map's nearest and farthest points are equally far from the picture's middle.
static func _camera_plan(p: Dictionary, camera: Dictionary) -> Dictionary:
	var table: Vector2 = p["table"]
	var height: float = camera.get("height", 60.0)
	var back: float = camera.get("back", 10.0)
	var tan_across: float = camera.get("tan_across", DEFAULT_TAN_ACROSS)
	var tan_along: float = camera.get("tan_along", DEFAULT_TAN_ALONG)
	var start: Rect2 = p["start_rect"]
	var centre_x: float = start.get_center().x if start.size != Vector2.ZERO else table.x * 0.5
	var side := "left" if centre_x <= table.x * 0.5 else "right"
	var corners := _map_corners(p)
	var plan := {"side": side, "height": height, "back": back}
	plan["position"] = Vector2(-back if side == "left" else table.x + back, table.y * 0.5)
	plan["sees_all"] = _sees(corners, plan["position"], side, height, tan_across, tan_along)
	plan["coverage"] = _coverage(plan["position"], side, height, tan_across, tan_along, corners)
	var needed := -1.0
	var h := MIN_HEIGHT
	while h <= MAX_HEIGHT:
		if _sees(corners, plan["position"], side, h, tan_across, tan_along):
			needed = h
			break
		h += 1.0
	plan["needed_height"] = needed
	return plan


## The map's outline on the sheet: the convex hull of every square's corners (the empty corners of the map's bounding box need not
## be in the picture).
static func _map_corners(p: Dictionary) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for sq: Vector2i in p["map_squares"]:
		var box := square_rect(p, sq)
		points.append_array([box.position, box.position + Vector2(box.size.x, 0), box.end, box.position + Vector2(0, box.size.y)])
	var hull := Geometry2D.convex_hull(PackedVector2Array(points))
	var corners: Array[Vector2] = []
	for point in hull:
		corners.append(point)
	return corners


## The camera's frame for a given height: forward, right and up vectors in (sheet X, sheet Y, height) space.
static func _frame(points: Array[Vector2], from: Vector2, side: String, height: float) -> Array[Vector3]:
	var direction := 1.0 if side == "left" else -1.0
	var nearest := INF
	var farthest := 0.0
	for point in points:
		var along := (point.x - from.x) * direction
		nearest = minf(nearest, along)
		farthest = maxf(farthest, along)
	nearest = maxf(nearest, 1.0)
	var pitch := (atan2(height, nearest) + atan2(height, farthest)) * 0.5
	var forward := Vector3(direction * cos(pitch), 0.0, -sin(pitch))
	var right := Vector3(0.0, direction, 0.0)
	var up := right.cross(forward).normalized()
	if up.z < 0.0:
		up = -up
	return [forward, right, up]


static func _sees(points: Array[Vector2], from: Vector2, side: String, height: float, tan_across: float, tan_along: float) -> bool:
	var frame := _frame(points, from, side, height)
	var eye := Vector3(from.x, from.y, height)
	for point in points:
		var d := Vector3(point.x, point.y, 0.0) - eye
		var depth := d.dot(frame[0])
		if depth <= 0.0:
			return false
		if absf(d.dot(frame[1]) / depth) > tan_across * (1.0 - MARGIN) or absf(d.dot(frame[2]) / depth) > tan_along * (1.0 - MARGIN):
			return false
	return true


## The part of the table the picture shows: where the rays through the picture's corners hit the table (cut off FAR_CLIP away).
static func _coverage(from: Vector2, side: String, height: float, tan_across: float, tan_along: float, points: Array[Vector2]) -> PackedVector2Array:
	var frame := _frame(points, from, side, height)
	var eye := Vector3(from.x, from.y, height)
	var outline := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var ray: Vector3 = frame[0] + frame[1] * corner.x * tan_across + frame[2] * corner.y * tan_along
		var t := FAR_CLIP
		if ray.z < -1e-6:
			t = minf(-height / ray.z, FAR_CLIP)
		var hit := eye + ray * t
		outline.append(Vector2(hit.x, hit.y))
	return outline
