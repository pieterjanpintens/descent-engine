class_name ConcaveBorderBox
extends Control

## A square badge border whose four edges are circular arcs bulging INWARD
## (toward the badge's own centre) instead of straight lines, so the four
## corners come to a real point instead of a flat or rounded corner - "make
## it arcs pointing inward so that their tips come together on the corners
## making sharp pointy corner" (new 2026-10-01), a decorative alternative
## to the plain `StyleBoxFlat` rounded-rect double border
## `CombatView._bordered_icon_box()`'s icon badges used before this. That
## function nests two of these (an always-gray outer one, a weakness=red/
## resistance=blue/damage-type=gray inner one) where it used to nest two
## `PanelContainer`s - only the SHAPE changed, the fill/border colour
## scheme from that round is untouched.
##
## The first custom `_draw()`-based 2D Control in this project (everything
## else that draws its own geometry here is 3D, via `ImmediateMesh`/
## `SurfaceTool`) - plain `draw_colored_polygon()`/`draw_polyline()` calls
## on a flattened point list, no new mechanism needed.
##
## Geometry: each edge is the classic "sagitta" arc - the circle whose
## centre sits OUTSIDE the square, on the opposite side of that edge from
## the square's own centre, sized exactly so the arc passes through both
## of that edge's corner points while bulging inward by `concavity` (a
## fraction of the square's own side length) at the edge's midpoint. The
## four arcs share their endpoints (each corner belongs to two adjacent
## arcs), so the corners land on a real point.
##
## Two follow-on touches, same day, after a first real look ("it's pretty
## solid, the corners where the arc come together are looking a bit off,
## can we smooth those? also try adding a small dash in the middle of
## each arc pointing outward so it touches the size of the shape bounding
## box"):
## - A small filled dot at each corner (see `_draw()`) - `draw_polyline()`
##   has no round-join option of its own and strokes each segment as an
##   independent rectangle, which leaves a visible notch/gap right at a
##   corner this acute (two arcs meeting at a near-cusp). A plain circle,
##   same colour, radius matched to the stroke's own half-width, caps the
##   join the same way a round line-join would.
## - A short outward "dash" at each edge's own deepest point, reaching
##   back out to touch the shape's own plain bounding-box edge (see
##   `_edge_dash_points()`) - a decorative accent.

@export var fill_color: Color = Color(0, 0, 0, 0.9)
@export var border_color: Color = Color(0.72, 0.74, 0.78, 0.9)
@export var border_width: float = 2.0
@export var concavity: float = 0.09  ## how far each edge's midpoint is pulled inward, as a fraction of the square's own side length - eased back twice the same day (2026-10-01): 0.18 -> 0.12 ("make it arc a little bit less") -> 0.09. **Keep this well under ~0.3** - `_arc_between()`'s sagitta formula only traces the correct INWARD arc while `depth < chord/2` (i.e. concavity < 0.5 for a square); confirmed by direct headless check that 0.5 and 0.9 both flip the arc to bulge OUTWARD instead and miss the requested depth entirely, not just look "more extreme"
@export var arc_segments: int = 14  ## points per edge arc - smooth enough at this badge's small on-screen size without being wasteful


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var pts := _outline_points()
	if pts.is_empty():
		return
	draw_colored_polygon(pts, fill_color)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, border_color, border_width, true)

	# Round off the sharp corner joins (new 2026-10-01, "the corners...
	# are looking a bit off, can we smooth those") - see this script's own
	# class doc for why a plain circle is the fix here.
	for corner in _corners():
		draw_circle(corner, border_width / 2.0, border_color, true, -1.0, true)

	# A small outward dash at each edge's own deepest point, touching the
	# shape's plain bounding-box edge (new 2026-10-01, same round - "adding
	# a small dash in the middle of each arc pointing outward").
	var dashes := _edge_dash_points()
	if not dashes.is_empty():
		draw_multiline(dashes, border_color, border_width, true)


## The square's own 4 corners, in local (0,0)-to-`size` space - shared by
## every method below so there's one single place that defines them.
func _corners() -> Array[Vector2]:
	var s := size
	return [Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(0, s.y)]


## The unit normal of chord `a`-`b` that points toward `center` - shared by
## `_arc_between()` and `_edge_dash_points()` so both ever only flip the
## sign once, in one place.
func _inward_normal(a: Vector2, b: Vector2, center: Vector2) -> Vector2:
	var chord := b - a
	if chord.length() <= 0.0:
		return Vector2.ZERO
	var normal := chord.normalized().rotated(PI / 2.0)
	if normal.dot(center - (a + b) / 2.0) < 0.0:
		normal = -normal
	return normal


## The four corners, each edge replaced by `arc_segments` points along its
## own inward-bulging arc - one continuous closed polygon.
func _outline_points() -> PackedVector2Array:
	var s := size
	var side := minf(s.x, s.y)
	if side <= 0.0:
		return PackedVector2Array()
	var depth := side * concavity
	var corners := _corners()
	var pts := PackedVector2Array()
	for i in 4:
		pts.append_array(_arc_between(corners[i], corners[(i + 1) % 4], depth, s / 2.0))
	return pts


## One line-segment pair (inward arc point, then straight back out to the
## plain bounding-box edge) per edge, for `draw_multiline()` - a circular
## arc's own midpoint (`t = 0.5`) always lands exactly `depth` along the
## chord's inward normal from the chord's own midpoint, by the definition
## of sagitta itself, so no separate arc sampling is needed to find it.
func _edge_dash_points() -> PackedVector2Array:
	var s := size
	var side := minf(s.x, s.y)
	if side <= 0.0:
		return PackedVector2Array()
	var depth := side * concavity
	if depth <= 0.0:
		return PackedVector2Array()
	var center := s / 2.0
	var corners := _corners()
	var pts := PackedVector2Array()
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var straight_mid := (a + b) / 2.0
		var normal := _inward_normal(a, b, center)
		pts.append(straight_mid + normal * depth)
		pts.append(straight_mid)
	return pts


## Points along a circular arc from `a` to `b` that bulges toward
## `center` by sagitta `depth` - the shared edge-arc formula every side
## uses, just handed a different corner pair each time.
func _arc_between(a: Vector2, b: Vector2, depth: float, center: Vector2) -> PackedVector2Array:
	var chord := b - a
	var length := chord.length()
	if depth <= 0.0 or length <= 0.0:
		return PackedVector2Array([a, b])
	var mid := (a + b) / 2.0
	var normal := _inward_normal(a, b, center)
	var radius := (depth * depth + (length / 2.0) * (length / 2.0)) / (2.0 * depth)
	# The circle's own centre sits on the OPPOSITE side of the chord from
	# the bulge direction (`normal`), by (radius - depth) beyond the
	# chord - a huge, far-away circle whose near edge grazes the chord's
	# midpoint by exactly `depth`. Confirmed by direct headless check
	# after an initial sign slip here placed the centre on the WRONG side,
	# which bulged every edge outward instead of inward.
	var arc_center := mid + normal * (depth - radius)
	var from_angle := (a - arc_center).angle()
	var to_angle := (b - arc_center).angle()
	# atan2 wraps at +-PI - the two corner angles are always close together
	# (the arc's own circle is huge relative to the chord, so the corners
	# only subtend a small angle at its centre), so if the raw values land
	# on opposite sides of that seam, nudge one by a full turn so the loop
	# below still sweeps the short way around.
	if absf(to_angle - from_angle) > PI:
		if to_angle > from_angle:
			to_angle -= TAU
		else:
			to_angle += TAU
	var pts := PackedVector2Array()
	for i in arc_segments + 1:
		var t := float(i) / arc_segments
		var ang := lerpf(from_angle, to_angle, t)
		pts.append(arc_center + Vector2(cos(ang), sin(ang)) * radius)
	return pts
