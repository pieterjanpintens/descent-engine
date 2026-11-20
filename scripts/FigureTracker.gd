class_name FigureTracker
extends RefCounted

## Finds the heroes on photos of the table camera without markers, for one Table and one calibration (CameraCalibration).
##
## 1. What the board looks like empty: `learn(photo, ...)` copies every square nobody stands on (and no figure in front of it hides)
##    into a background picture. The calibration photo (taken before the figures are placed, or with them on known squares) starts it;
##    every confirmed photo adds to it.
## 2. Where something stands: `propose()` compares a new photo with that background, square by square, nearest square to the camera
##    first. A square whose floor looks different is taken as occupied - unless a figure already found in front of it (or a monster,
##    whose squares the app knows) covers it in the picture: a figure is a box of FIGURE_LEVELS high over its square, projected with
##    the calibration. A square never seen empty is compared with the last confirmed photo instead.
## 3. Who is who: the heroes are matched to the occupied squares by how far each would have moved since the last confirmed positions and
##    by how much the figure there looks like the hero (a colour histogram of the box, learned from confirmed photos). The cheapest
##    assignment wins; a hero that would be a guess (not found, a poor look match, or a close second assignment) is marked unsure.
## 4. `learn()` with the confirmed positions teaches the background and every hero's look again.
##
## All work happens on a copy of the photo WORK_WIDTH wide. Kept in memory only (not in saves).

const WORK_WIDTH := 1000
## How tall a figure is, in height levels (about 4 cm with 3.6 cm levels).
const FIGURE_LEVELS := 1.15
## A pixel counts as different when a colour channel differs by more than this.
const PIXEL_CHANGE := 0.16
## A square counts as occupied when at least this part of its floor looks different.
const OCCUPIED := 0.3
## Part of a square's floor that a figure in front must cover in the picture to explain its change.
const COVERED := 0.5
const STEP := 1
const HUE_BINS := 12
const GREY_BINS := 4
## Cost of a hero not found (it keeps its last square), and per square of movement.
const MISSING_COST := 1.2
const MOVE_COST := 0.08
const LOOK_WEIGHT := 1.0
## A hero is unsure when swapping it with another hero (or leaving it out) costs less than this extra.
const SURE_MARGIN := 0.15

var calibration: CameraCalibration
var _factor := 1.0
var _background: Image
var _known: Dictionary = {}  # Vector3i square -> true: its background is a picture of it empty
var _last: Image
var _last_occupied: Dictionary = {}  # square -> true in the last confirmed photo
var _seen: Dictionary = {}  # Vector3i -> true: squares that were on the board when a photo was learned
var _looks: Dictionary = {}  # hero slot -> PackedFloat32Array histogram
var _quads: Dictionary = {}  # Vector3i -> PackedVector2Array (work pixels), cache per calibration
var _boxes: Dictionary = {}


func _init(cal: CameraCalibration) -> void:
	calibration = cal


func is_ready() -> bool:
	return calibration != null and calibration.valid and _last != null


## Teaches the tracker with a photo whose positions are known: `heroes` = {slot: Vector3i}, `monsters` = Array of Vector3i squares
## (a large monster's four squares each). Squares nobody covers go into the background; every hero's look is learned.
func learn(photo: Image, squares: Dictionary, heroes: Dictionary, monsters: Array, learn_looks: bool = true) -> void:
	var work := _work(photo)
	if _background == null or _background.get_size() != work.get_size():
		_background = work.duplicate() as Image
		_known.clear()
	var occupied := {}
	for slot in heroes:
		occupied[heroes[slot]] = true
	for sq in monsters:
		occupied[sq] = true
	var cover := _covered_by(occupied, squares)
	for sq: Vector3i in squares:
		if occupied.has(sq) or cover.has(sq):
			continue
		var quad := _quad(sq, squares)
		if quad.is_empty():
			continue
		_copy_quad(work, _background, quad)
		_known[sq] = true
	for sq: Vector3i in squares:
		_seen[sq] = true
	for slot in heroes:
		if not learn_looks:
			break
		var look := _look(work, heroes[slot], squares)
		if look.is_empty():
			continue
		if _looks.has(slot):
			var old: PackedFloat32Array = _looks[slot]
			for i in look.size():
				look[i] = old[i] * 0.5 + look[i] * 0.5
		_looks[slot] = look
	_last = work
	_last_occupied = occupied


## A stage was just built: learns the background of the squares that were not on the board before, from a photo taken before anybody
## walks in (so nobody is assumed to stand on them). Without this a new room would look "changed" compared with the last photo.
func add_new_squares(photo: Image, squares: Dictionary) -> void:
	if not is_ready():
		return
	var work := _work(photo)
	for sq: Vector3i in squares:
		if _seen.has(sq):
			continue
		var quad := _quad(sq, squares)
		_seen[sq] = true
		if quad.is_empty():
			continue
		_copy_quad(work, _background, quad)
		_copy_quad(work, _last, quad)
		_known[sq] = true


## Where the heroes are on `photo`: {slot: {"square": Vector3i, "sure": bool, "found": bool}} for every hero in `last` ({slot:
## Vector3i}, their last confirmed squares). `monsters` = Array of Vector3i the monsters stand on now (the app placed them).
func propose(photo: Image, squares: Dictionary, last: Dictionary, monsters: Array) -> Dictionary:
	var result := {}
	if not is_ready():
		return result
	var work := _work(photo)
	var monster_squares := {}
	for sq in monsters:
		monster_squares[sq] = true
	# nearest to the camera first (lowest in the picture)
	var order: Array = []
	for sq: Vector3i in squares:
		var quad := _quad(sq, squares)
		if not quad.is_empty():
			order.append([_centre(quad).y, sq])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var accepted := {}
	var blockers: Array = []  # figure boxes that explain changes behind them
	for sq in monster_squares:
		var box := _box(sq, squares)
		if not box.is_empty():
			blockers.append(box)
	for entry in order:
		var sq: Vector3i = entry[1]
		if monster_squares.has(sq) or not _seen.has(sq):
			continue  # a square that came on the board without a photo cannot be judged
		var quad := _quad(sq, squares)
		if _covered_part(quad, blockers) >= COVERED:
			continue
		if _occupied_evidence(work, sq, quad) >= OCCUPIED:
			accepted[sq] = true
			var box := _box(sq, squares)
			if not box.is_empty():
				blockers.append(box)
	# a hero hidden behind another figure in the picture cannot be seen: where one stood last time and its square is now covered by an
	# accepted figure, it is probably still there (marked unsure by _assign()'s look check if it is not)
	var hidden := {}
	for slot in last:
		var was: Vector3i = last[slot]
		if accepted.has(was) or monster_squares.has(was):
			continue
		var quad := _quad(was, squares)
		if not quad.is_empty() and _covered_part(quad, blockers) >= COVERED:
			accepted[was] = true
			hidden[was] = true
	var proposal := _assign(work, accepted.keys(), squares, last)
	for slot in proposal:
		if hidden.has((proposal[slot] as Dictionary)["square"]):
			proposal[slot]["sure"] = false
	return proposal


# ---------------------------------------------------------------- evidence

## How much of the square's floor differs from the empty board (or, never seen empty, how different it is from the last photo - or
## how SIMILAR, when something stood there then).
func _occupied_evidence(work: Image, sq: Vector3i, quad: PackedVector2Array) -> float:
	if _known.has(sq):
		return _changed_part(work, _background, quad)
	var change := _changed_part(work, _last, quad)
	return 1.0 - change if _last_occupied.has(sq) else change


func _changed_part(a: Image, b: Image, quad: PackedVector2Array) -> float:
	var total := 0
	var changed := 0
	for p in _pixels(quad, a.get_size()):
		var ca := a.get_pixelv(p)
		var cb := b.get_pixelv(p)
		total += 1
		if maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))) > PIXEL_CHANGE:
			changed += 1
	return float(changed) / total if total > 0 else 0.0


## Squares hidden in the picture by a figure standing on one of `occupied` (more than COVERED of their floor inside its box).
func _covered_by(occupied: Dictionary, squares: Dictionary) -> Dictionary:
	var boxes: Array = []
	for sq in occupied:
		var box := _box(sq, squares)
		if not box.is_empty():
			boxes.append(box)
	var covered := {}
	for sq: Vector3i in squares:
		if occupied.has(sq):
			continue
		var quad := _quad(sq, squares)
		if not quad.is_empty() and _covered_part(quad, boxes) >= COVERED:
			covered[sq] = true
	return covered


func _covered_part(quad: PackedVector2Array, boxes: Array) -> float:
	if boxes.is_empty() or quad.is_empty():
		return 0.0
	var inside := 0
	var samples := 0
	var low := quad[0]
	var high := quad[0]
	for p in quad:
		low = Vector2(minf(low.x, p.x), minf(low.y, p.y))
		high = Vector2(maxf(high.x, p.x), maxf(high.y, p.y))
	for i in 5:
		for j in 5:
			var p := Vector2(lerpf(low.x, high.x, (i + 0.5) / 5.0), lerpf(low.y, high.y, (j + 0.5) / 5.0))
			if not Geometry2D.is_point_in_polygon(p, quad):
				continue
			samples += 1
			for box: PackedVector2Array in boxes:
				if Geometry2D.is_point_in_polygon(p, box):
					inside += 1
					break
	return float(inside) / samples if samples > 0 else 0.0


# ---------------------------------------------------------------- who is who

func _assign(work: Image, candidates: Array, squares: Dictionary, last: Dictionary) -> Dictionary:
	var slots: Array = last.keys()
	var cost := {}  # slot -> {candidate index: cost}
	for slot in slots:
		var row := {}
		for i in candidates.size():
			var c: Vector3i = candidates[i]
			var from: Vector3i = last[slot]
			var move := maxi(absi(c.x - from.x), absi(c.z - from.z))
			var look_cost := 0.5
			if _looks.has(slot):
				var look := _look(work, c, squares)
				if not look.is_empty():
					look_cost = _look_distance(_looks[slot], look)
			row[i] = move * MOVE_COST + look_cost * LOOK_WEIGHT
		cost[slot] = row
	var best := _search(slots, candidates.size(), cost)
	var result := {}
	for k in slots.size():
		var slot = slots[k]
		var choice: int = best["choice"][k]
		if choice < 0:
			result[slot] = {"square": last[slot], "sure": false, "found": false}
			continue
		# sure when no other choice for this hero is nearly as cheap
		var sure := true
		var mine: float = cost[slot][choice]
		for other in slots:
			if other == slot:
				continue
			var other_k := slots.find(other)
			var theirs: int = best["choice"][other_k]
			if theirs < 0:
				continue
			var swapped: float = float(cost[slot][theirs]) + float(cost[other][choice])
			var now: float = mine + float(cost[other][theirs])
			if swapped - now < SURE_MARGIN:
				sure = false
		if mine >= MISSING_COST - SURE_MARGIN:
			sure = false
		result[slot] = {"square": candidates[choice], "sure": sure, "found": true}
	return result


## The cheapest assignment of heroes to candidate squares (each square once; a hero may be left out at MISSING_COST): {"choice":
## Array of candidate index or -1 per hero, "cost"}. Depth-first with pruning; at most 6 heroes.
func _search(slots: Array, count: int, cost: Dictionary) -> Dictionary:
	var best := {"choice": [], "cost": INF}
	var choice: Array = []
	choice.resize(slots.size())
	var used := {}
	var walk := func(walk_ref: Callable, k: int, total: float) -> void:
		if total >= best["cost"]:
			return
		if k == slots.size():
			best["cost"] = total
			best["choice"] = choice.duplicate()
			return
		var row: Dictionary = cost[slots[k]]
		for i in count:
			if used.has(i):
				continue
			used[i] = true
			choice[k] = i
			walk_ref.call(walk_ref, k + 1, total + float(row[i]))
			used.erase(i)
		choice[k] = -1
		walk_ref.call(walk_ref, k + 1, total + MISSING_COST)
	walk.call(walk, 0, 0.0)
	return best


## A colour histogram of the figure box over a square: HUE_BINS for coloured pixels, GREY_BINS by brightness for the rest; sums to 1.
func _look(work: Image, sq: Vector3i, squares: Dictionary) -> PackedFloat32Array:
	var box := _box(sq, squares)
	var bins := PackedFloat32Array()
	if box.is_empty():
		return bins
	bins.resize(HUE_BINS + GREY_BINS)
	var total := 0.0
	for p in _pixels(box, work.get_size()):
		var c := work.get_pixelv(p)
		if c.s > 0.25 and c.v > 0.15:
			bins[mini(HUE_BINS - 1, int(c.h * HUE_BINS))] += 1.0
		else:
			bins[HUE_BINS + mini(GREY_BINS - 1, int(c.v * GREY_BINS))] += 1.0
		total += 1.0
	if total <= 0.0:
		return PackedFloat32Array()
	for i in bins.size():
		bins[i] /= total
	return bins


## 0 = the same colours, 1 = nothing in common (one minus the histogram intersection).
static func _look_distance(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size():
		return 1.0
	var common := 0.0
	for i in a.size():
		common += minf(a[i], b[i])
	return 1.0 - common


# ---------------------------------------------------------------- geometry

func _work(photo: Image) -> Image:
	var work := photo.duplicate() as Image
	if work.get_format() != Image.FORMAT_RGB8:
		work.convert(Image.FORMAT_RGB8)
	_factor = 1.0
	if work.get_width() > WORK_WIDTH:
		_factor = float(WORK_WIDTH) / work.get_width()
		work.resize(WORK_WIDTH, maxi(1, roundi(work.get_height() * _factor)), Image.INTERPOLATE_BILINEAR)
	return work


func _level(sq: Vector3i, squares: Dictionary) -> float:
	var lowest := 1 << 20
	for other: Vector3i in squares:
		lowest = mini(lowest, other.y)
	return float(sq.y - lowest)


## The square's floor in work pixels; empty when (partly) behind the camera.
func _quad(sq: Vector3i, squares: Dictionary) -> PackedVector2Array:
	if _quads.has(sq):
		return _quads[sq]
	var level := _level(sq, squares)
	var quad := PackedVector2Array()
	for corner in [Vector3(sq.x, level, sq.z), Vector3(sq.x + 1, level, sq.z), Vector3(sq.x + 1, level, sq.z + 1), Vector3(sq.x, level, sq.z + 1)]:
		if not calibration.is_visible(corner):
			quad = PackedVector2Array()
			break
		quad.append(calibration.project(corner) * _factor)
	_quads[sq] = quad
	return quad


## The outline of a figure standing on the square: the convex hull of a box FIGURE_LEVELS high, in work pixels.
func _box(sq: Vector3i, squares: Dictionary) -> PackedVector2Array:
	if _boxes.has(sq):
		return _boxes[sq]
	var level := _level(sq, squares)
	var points := PackedVector2Array()
	for top in [level, level + FIGURE_LEVELS]:
		for corner in [Vector2(sq.x + 0.15, sq.z + 0.15), Vector2(sq.x + 0.85, sq.z + 0.15), Vector2(sq.x + 0.85, sq.z + 0.85), Vector2(sq.x + 0.15, sq.z + 0.85)]:
			var at := Vector3(corner.x, top, corner.y)
			if not calibration.is_visible(at):
				_boxes[sq] = PackedVector2Array()
				return _boxes[sq]
			points.append(calibration.project(at) * _factor)
	var hull := Geometry2D.convex_hull(points)
	_boxes[sq] = hull
	return hull


func _centre(quad: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in quad:
		sum += p
	return sum / quad.size()


## The work pixels inside a polygon (every STEP-th).
func _pixels(polygon: PackedVector2Array, size: Vector2i) -> Array[Vector2i]:
	var pixels: Array[Vector2i] = []
	if polygon.size() < 3:
		return pixels
	var low := polygon[0]
	var high := polygon[0]
	for p in polygon:
		low = Vector2(minf(low.x, p.x), minf(low.y, p.y))
		high = Vector2(maxf(high.x, p.x), maxf(high.y, p.y))
	var y := maxi(0, floori(low.y))
	while y <= mini(size.y - 1, ceili(high.y)):
		var x := maxi(0, floori(low.x))
		while x <= mini(size.x - 1, ceili(high.x)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), polygon):
				pixels.append(Vector2i(x, y))
			x += STEP
		y += STEP
	return pixels


func _copy_quad(from: Image, to: Image, quad: PackedVector2Array) -> void:
	for p in _pixels(quad, from.get_size()):
		to.set_pixelv(p, from.get_pixelv(p))
