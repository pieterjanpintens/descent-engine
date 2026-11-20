class_name HeroDetector
extends RefCounted

## Finds the heroes on a calibrated photo of the table camera. Each hero stands on a coloured paper square a bit larger than its
## base, so a border of that colour shows around the figure. The player teaches each hero's colour once by clicking the paper on a
## photo (`sample()`); the detector then looks at every square of the board as the camera sees it (CameraCalibration.project(),
## raised floors at their level) and counts the pixels close to each hero's colour. The best-scoring square per hero wins, one hero per
## square, strongest match first; a hero whose best square scores below MIN_SCORE is "not found".
##
## Colours are compared on hue and saturation for coloured papers (so the lamp's brightness matters less) and on brightness and
## saturation for white / grey / black ones. Strongly coloured papers that do not occur on the board (green, blue, magenta) work best;
## pale papers wash out under a lamp.
##
## Pure data; works on a scaled-down copy of the photo (WORK_WIDTH) so a scan takes a second or two.

const WORK_WIDTH := 1000
## A square counts for a hero when at least this part of its pixels matches the hero's colour.
const MIN_SCORE := 0.06
const MATCH_DISTANCE := 0.3
## Only every STEP-th pixel (in both directions) is looked at.
const STEP := 2


## The average colour around a photo pixel (radius in photo pixels): what the player clicked as a hero's paper.
static func sample(image: Image, at: Vector2, radius: int = 6) -> Color:
	var total := Color(0, 0, 0, 0)
	var count := 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := int(at.x) + dx
			var y := int(at.y) + dy
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				total += image.get_pixel(x, y)
				count += 1
	if count == 0:
		return Color.BLACK
	return Color(total.r / count, total.g / count, total.b / count)


## How different two colours are for this purpose (0 = the same); see the class doc.
static func distance(a: Color, b: Color) -> float:
	if a.s > 0.18 and b.s > 0.18:
		var dh := absf(a.h - b.h)
		dh = minf(dh, 1.0 - dh)
		return dh * 4.0 + absf(a.s - b.s) * 1.2 + absf(a.v - b.v) * 0.4
	return absf(a.s - b.s) * 3.0 + absf(a.v - b.v) * 1.2 + (0.25 if (a.s > 0.18) != (b.s > 0.18) else 0.0)


## Finds the heroes. `references` = {hero slot: Color}; `squares` = {Vector3i (x, level, z): true} the board as it is on the table;
## `skip` = squares not to consider (monsters stand there). Returns {"found": {slot: {"square": Vector3i, "score": float}},
## "scores": {slot: {Vector3i: float}}} - the scores per square are there to draw / debug.
static func detect(image: Image, calibration: CameraCalibration, squares: Dictionary, references: Dictionary, skip: Dictionary = {}) -> Dictionary:
	var result := {"found": {}, "scores": {}}
	if image == null or calibration == null or not calibration.valid or references.is_empty():
		return result
	var work := image.duplicate() as Image
	var factor := 1.0
	if work.get_width() > WORK_WIDTH:
		factor = float(WORK_WIDTH) / work.get_width()
		work.resize(WORK_WIDTH, maxi(1, roundi(work.get_height() * factor)), Image.INTERPOLATE_BILINEAR)
	var lowest := 1 << 20
	for sq: Vector3i in squares:
		lowest = mini(lowest, sq.y)
	var slots: Array = references.keys()
	var scores := {}
	for slot in slots:
		scores[slot] = {}
	for sq: Vector3i in squares:
		if skip.has(sq):
			continue
		var level := float(sq.y - lowest)
		var corners: Array[Vector3] = [Vector3(sq.x, level, sq.z), Vector3(sq.x + 1, level, sq.z), Vector3(sq.x + 1, level, sq.z + 1), Vector3(sq.x, level, sq.z + 1)]
		var quad := PackedVector2Array()
		var usable := true
		for corner in corners:
			if not calibration.is_visible(corner):
				usable = false
				break
			quad.append(calibration.project(corner) * factor)
		if not usable:
			continue
		var counts := _count(work, quad, references, slots)
		var total: int = counts.get("total", 0)
		if total < 12:
			continue  # (almost) outside the photo, or too small to judge
		for slot in slots:
			(scores[slot] as Dictionary)[sq] = float(counts.get(slot, 0)) / total
	result["scores"] = scores
	# one hero per square, the strongest match first
	var candidates := []
	for slot in slots:
		for sq: Vector3i in scores[slot]:
			var score: float = scores[slot][sq]
			if score >= MIN_SCORE:
				candidates.append([score, slot, sq])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var taken := {}
	var found := {}
	for candidate in candidates:
		if found.has(candidate[1]) or taken.has(candidate[2]):
			continue
		found[candidate[1]] = {"square": candidate[2], "score": candidate[0]}
		taken[candidate[2]] = true
	result["found"] = found
	return result


## Counts, inside the quadrilateral, the pixels close to each reference colour: {"total": int, slot: int, ...}.
static func _count(work: Image, quad: PackedVector2Array, references: Dictionary, slots: Array) -> Dictionary:
	var low := quad[0]
	var high := quad[0]
	for p in quad:
		low = Vector2(minf(low.x, p.x), minf(low.y, p.y))
		high = Vector2(maxf(high.x, p.x), maxf(high.y, p.y))
	var x0 := maxi(0, floori(low.x))
	var y0 := maxi(0, floori(low.y))
	var x1 := mini(work.get_width() - 1, ceili(high.x))
	var y1 := mini(work.get_height() - 1, ceili(high.y))
	var counts := {"total": 0}
	for slot in slots:
		counts[slot] = 0
	var y := y0
	while y <= y1:
		var x := x0
		while x <= x1:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), quad):
				counts["total"] += 1
				var pixel := work.get_pixel(x, y)
				for slot in slots:
					if distance(pixel, references[slot]) < MATCH_DISTANCE:
						counts[slot] += 1
			x += STEP
		y += STEP
	return counts
