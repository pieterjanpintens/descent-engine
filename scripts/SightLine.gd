class_name SightLine
extends RefCounted

## Line of sight between two tile squares, by default the Descent 2 rule: corner to corner - if a line can be drawn between ANY corner of one square
## and ANY corner of the other without being stopped, the squares see each other. Pure data and math (no scene, no autoload except the
## BuildRules constants), so the Player's line-of-sight tool can use exactly the same code as the plan validator. Experimental, branch
## experiment/ai-map-generation.
##
## What stops a line (BuildRules decides what blocks sight; this only applies it):
##  - a blocking PIECE (tree, tall / medium pillar, gate, an archway's end posts) when the line passes through it at a height below its top
##    and above the floor it stands on. The line runs at figure height (BuildRules.FIGURE_HEIGHT) above the floors of the two squares, so
##    from a platform you see over low pieces, and a tall piece blocks a view from any height up to its top;
##  - a FLOOR: floors are opaque and there is no limit to how far up or down you can look, but never through a floor - so a figure directly
##    under or over a floor tile is not visible. A line that crosses the height of a floor tile on its way (looking up through a bridge from
##    below, or down through the floor you stand on) is stopped where it meets that tile, edges included.
## A line only touching the edge of a blocker passes (running along the outside of a pillar's edge is fine), but a line running between two
## blockers that touch each other along that edge does not - there is no gap there.

const EYE_HEIGHT := float(BuildRules.FIGURE_HEIGHT)
const EPS := 1e-6

## Which points of the two squares a sight line may start / end at (experiment/los-strictness; the Player's tool cycles it with L):
## CORNER_TO_CORNER = the Descent 2 rule (any corner of one square to any corner of the other, 16 lines - loose),
## CENTER_TO_CORNER = from the middle of the viewer's square to any corner of the target (4 lines),
## CENTER_TO_CENTER = one line from middle to middle (strictest).
enum Mode { CORNER_TO_CORNER, CENTER_TO_CORNER, CENTER_TO_CENTER }
static var mode: int = Mode.CORNER_TO_CORNER


static func mode_name(value: int = -1) -> String:
	match (mode if value < 0 else value):
		Mode.CENTER_TO_CORNER:
			return "centre to corner"
		Mode.CENTER_TO_CENTER:
			return "centre to centre"
	return "corner to corner"


## Everything can_see() needs, from a MapPlanValidator.validate() result: {blockers, floors, squares}. Build it once, ask many times.
static func prepare(result: Dictionary) -> Dictionary:
	var blockers: Dictionary = {}  # Vector2i fine cell -> Array of Vector2(base height, top height)
	var tops := MapPlanValidator.sight_blockers(result)
	for key: Vector3i in tops:
		var cell := Vector2i(key.x, key.z)
		if not blockers.has(cell):
			blockers[cell] = []
		blockers[cell].append(Vector2(float(key.y), float(tops[key])))
	var floors: Dictionary = {}  # height -> {Vector2i fine cell: true}
	for piece: Dictionary in result["pieces"]:
		if piece["layer"] != "floor":
			continue
		var height: int = piece["height"]
		if not floors.has(height):
			floors[height] = {}
		for cell: Vector3i in piece["cells"]:
			floors[height][Vector2i(cell.x, cell.z)] = true
	return context_from(blockers, floors)


## The context from its two raw parts: `blockers` (Vector2i fine cell -> Array of Vector2(base height, top height)) and `floors` (height ->
## {Vector2i fine cell: true}). The squares (x, height, z in game units) are the ones with a complete floor.
static func context_from(blockers: Dictionary, floors: Dictionary) -> Dictionary:
	var counts: Dictionary = {}  # Vector3i (square x, height, square z) -> fine cells with floor
	var cpt := FootprintRegistry.CELLS_PER_TILE
	for height: int in floors:
		for cell: Vector2i in floors[height]:
			var square := Vector3i(floori(float(cell.x) / cpt), height, floori(float(cell.y) / cpt))
			counts[square] = int(counts.get(square, 0)) + 1
	var squares: Array[Vector3i] = []
	for square: Vector3i in counts:
		if counts[square] == cpt * cpt:
			squares.append(square)
	return {"blockers": blockers, "floors": floors, "squares": squares}


## Whether the square `from_square` (x, z in game units) on a floor at `from_height` sees `to_square` on a floor at `to_height`.
static func can_see(context: Dictionary, from_square: Vector2i, from_height: int, to_square: Vector2i, to_height: int) -> bool:
	if from_square == to_square and from_height == to_height:
		return true
	var a := float(from_height) + EYE_HEIGHT
	var b := float(to_height) + EYE_HEIGHT
	for from_corner in _points(from_square, true):
		for to_corner in _points(to_square, false):
			if _clear(context, from_corner, a, to_corner, b):
				return true
	return false


## Every square (x, height, z) with a complete floor that `square` at `height` can see (not including itself).
static func visible_from(context: Dictionary, square: Vector2i, height: int) -> Array[Vector3i]:
	var seen: Array[Vector3i] = []
	for target: Vector3i in context["squares"]:
		if target == Vector3i(square.x, height, square.y):
			continue
		if can_see(context, square, height, Vector2i(target.x, target.z), target.y):
			seen.append(target)
	return seen


## A text picture of what one square sees on its own height: 'V' the viewer, '+' squares it sees, '-' floor squares it can not see,
## '#' a sight-blocking piece, ' ' nothing. (Squares on other heights are not drawn.)
static func render(result: Dictionary, square: Vector2i, height: int) -> String:
	var bounds: Rect2i = result["bounds"]
	if bounds.size == Vector2i.ZERO:
		return ""
	var context := prepare(result)
	var visible := visible_from(context, square, height)
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var grid: Dictionary = {}
	for target: Vector3i in context["squares"]:
		if target.y == height:
			grid[Vector2i(target.x, target.z)] = "+" if visible.has(target) else "-"
	for cell: Vector2i in context["blockers"]:
		for span: Vector2 in context["blockers"][cell]:
			if int(span.x) == height:
				grid[Vector2i(floori(float(cell.x) / cpt), floori(float(cell.y) / cpt))] = "#"
	grid[square] = "V"
	var lines: Array[String] = []
	for z in range(bounds.position.y, bounds.end.y):
		var line := ""
		for x in range(bounds.position.x, bounds.end.x):
			line += str(grid.get(Vector2i(x, z), " "))
		lines.append(line)
	return "\n".join(lines)


# ---------------------------------------------------------------- the line itself

## The points of a square a line may use in the current mode (`viewer` = the square the line starts in).
static func _points(square: Vector2i, viewer: bool) -> Array[Vector2]:
	var centre: Array[Vector2] = [Vector2(square.x + 0.5, square.y + 0.5)]
	if mode == Mode.CENTER_TO_CENTER or (mode == Mode.CENTER_TO_CORNER and viewer):
		return centre
	return _corners(square)


static func _corners(square: Vector2i) -> Array[Vector2]:
	return [
		Vector2(square.x, square.y), Vector2(square.x + 1, square.y),
		Vector2(square.x, square.y + 1), Vector2(square.x + 1, square.y + 1),
	]


## One corner-to-corner line from `p0` (eye height `a`) to `p1` (eye height `b`), points in game units. True when nothing stops it.
static func _clear(context: Dictionary, p0: Vector2, a: float, p1: Vector2, b: float) -> bool:
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var d := p1 - p0
	# 1. opaque floors: the line crosses the plane of a floor at height f (strictly between the two eye heights) at one point
	if absf(b - a) > EPS:
		var lowest := minf(a, b)
		var highest := maxf(a, b)
		for height: int in context["floors"]:
			if float(height) > lowest and float(height) < highest:
				var t := (float(height) - a) / (b - a)
				var point := p0 + d * t
				# floors are CLOSED: a line meeting a floor tile's edge (or corner) is stopped too - unlike a blocking piece, which a line may
				# graze - so nobody sees straight up or down through a floor, whatever corner they look from
				for cx in _cells_at(point.x * cpt):
					for cz in _cells_at(point.y * cpt):
						if context["floors"][height].has(Vector2i(cx, cz)):
							return false
	# 2. blocking pieces: walk the line from grid line to grid line (the grid is the fine cell grid)
	var cuts: Array[float] = [0.0, 1.0]
	if absf(d.x) > EPS:
		for k in range(ceili(minf(p0.x, p1.x) * cpt), floori(maxf(p0.x, p1.x) * cpt) + 1):
			var t := (float(k) / cpt - p0.x) / d.x
			if t > EPS and t < 1.0 - EPS:
				cuts.append(t)
	if absf(d.y) > EPS:
		for k in range(ceili(minf(p0.y, p1.y) * cpt), floori(maxf(p0.y, p1.y) * cpt) + 1):
			var t := (float(k) / cpt - p0.y) / d.y
			if t > EPS and t < 1.0 - EPS:
				cuts.append(t)
	cuts.sort()
	for i in cuts.size() - 1:
		if cuts[i + 1] - cuts[i] < 1e-9:
			continue
		var tm := (cuts[i] + cuts[i + 1]) / 2.0
		var mid := p0 + d * tm
		var line_height := a + (b - a) * tm
		# a piece of the line lying ON a grid line touches the cells on both sides: it is stopped only when both sides block
		var xs := _cells_at(mid.x * cpt)
		var zs := _cells_at(mid.y * cpt)
		var all_block := true
		for cx in xs:
			for cz in zs:
				if not _blocks(context["blockers"], Vector2i(cx, cz), line_height):
					all_block = false
		if all_block:
			return false
	return true


## The fine-cell indices a coordinate (in fine-cell units) touches: one cell, or the two either side of a grid line.
static func _cells_at(value: float) -> Array[int]:
	var nearest := roundi(value)
	if absf(value - float(nearest)) < EPS:
		return [nearest - 1, nearest]
	return [floori(value)]


static func _blocks(blockers: Dictionary, cell: Vector2i, line_height: float) -> bool:
	for span: Vector2 in blockers.get(cell, []):
		if line_height >= span.x and line_height < span.y:
			return true
	return false
