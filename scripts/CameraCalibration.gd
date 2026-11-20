class_name CameraCalibration
extends RefCounted

## Where the board is in a photo of the table camera (TableCamera): made from 4 or more points the player clicked on the photo
## (`image_points`, in photo pixels) that belong to known corners of tile squares on the ground level (`board_points`, in squares:
## x = board x, y = board z, the corner (0, 0) is the near corner of square (0, 0)).
##
## From those it computes
##   - a homography: the ground level of the board -> photo pixels (exact for the clicked plane), and
##   - the camera itself (focal length, rotation, position), derived from that homography with the usual assumptions (square pixels,
##     the lens centre in the middle of the photo), so raised floors - which lie on other planes - can be projected too.
## `project(Vector3(x, level, z))` gives the photo pixel of a point on the board at a height level (LEVEL_IN_SQUARES squares per level).
##
## Pure math, no scene nodes; to_dict() / from_dict() store only the clicked points (everything else is computed again).

## One height level on the table, in tile squares: a level is about 3.6 cm and a square 3.2 cm. Check on photos of raised floors.
const LEVEL_IN_SQUARES := 1.125
## Used when the photo gives no usable focal length (a camera looking straight down): about a 26 mm phone main lens.
const FALLBACK_FOCAL_PER_DIAGONAL := 0.6

var image_size := Vector2.ZERO
var board_points: Array[Vector2] = []
var image_points: Array[Vector2] = []
var valid := false
var error := ""

var _h := PackedFloat64Array()  # 3x3, row-major
var focal := 0.0
var _r1 := Vector3.ZERO
var _r2 := Vector3.ZERO
var _r3 := Vector3.ZERO
var _t := Vector3.ZERO
var _centre := Vector2.ZERO


## Fits the board to the clicked points. Check `valid` / `error` afterwards.
static func solve(board: Array[Vector2], image: Array[Vector2], size: Vector2) -> CameraCalibration:
	var calibration := CameraCalibration.new()
	calibration.image_size = size
	calibration.board_points = board.duplicate()
	calibration.image_points = image.duplicate()
	calibration._compute()
	return calibration


static func from_dict(data: Dictionary) -> CameraCalibration:
	var board: Array[Vector2] = []
	var image: Array[Vector2] = []
	for p in data.get("board", []):
		board.append(Vector2(float(p[0]), float(p[1])))
	for p in data.get("image", []):
		image.append(Vector2(float(p[0]), float(p[1])))
	var size: Array = data.get("size", [0, 0])
	return solve(board, image, Vector2(float(size[0]), float(size[1])))


func to_dict() -> Dictionary:
	var board := []
	for p in board_points:
		board.append([p.x, p.y])
	var image := []
	for p in image_points:
		image.append([p.x, p.y])
	return {"board": board, "image": image, "size": [image_size.x, image_size.y]}


## The photo pixel of a point on the ground level (board coordinates in squares).
func project_ground(board: Vector2) -> Vector2:
	return _apply(_h, board)


## The photo pixel of a board point at a height: Vector3(x, level, z) with x/z in squares and the level in height levels. The ground
## level goes through the homography (exact); other heights add the camera model's difference between that height and the ground.
func project(point: Vector3) -> Vector2:
	var ground := project_ground(Vector2(point.x, point.z))
	if is_zero_approx(point.y):
		return ground
	return ground + _camera_project(point.x, point.z, point.y * LEVEL_IN_SQUARES) - _camera_project(point.x, point.z, 0.0)


## Is the point in front of the camera (a point behind it projects to nonsense)?
func is_visible(point: Vector3) -> bool:
	return _camera_space(point.x, point.z, point.y * LEVEL_IN_SQUARES).z > 0.0


## How far (in photo pixels, the average over the clicked points) the fitted board is from the clicks: near 0 for 4 points, larger
## when more points disagree.
func residual() -> float:
	if not valid or image_points.is_empty():
		return 0.0
	var total := 0.0
	for i in image_points.size():
		total += project_ground(board_points[i]).distance_to(image_points[i])
	return total / image_points.size()


func _compute() -> void:
	valid = false
	if board_points.size() < 4 or board_points.size() != image_points.size():
		error = "Needs at least 4 points."
		return
	if image_size.x <= 0.0 or image_size.y <= 0.0:
		error = "The photo has no size."
		return
	var h := _homography(board_points, image_points)
	if h.is_empty():
		error = "The points do not form a usable shape (three of them on one line?)."
		return
	_h = h
	_centre = image_size * 0.5
	_compute_camera()
	valid = true
	error = ""


# ---------------------------------------------------------------- the camera from the homography

func _compute_camera() -> void:
	# move the lens centre to (0, 0): Hc = T * H with T = translate(-centre)
	var hc := PackedFloat64Array()
	hc.resize(9)
	for col in 3:
		hc[col] = _h[col] - _centre.x * _h[6 + col]
		hc[3 + col] = _h[3 + col] - _centre.y * _h[6 + col]
		hc[6 + col] = _h[6 + col]
	var h1 := Vector3(hc[0], hc[3], hc[6])
	var h2 := Vector3(hc[1], hc[4], hc[7])
	var h3 := Vector3(hc[2], hc[5], hc[8])
	# The two board axes are perpendicular and equally long in the camera's frame: each gives an estimate of f squared.
	var estimates: Array[float] = []
	if absf(h1.z * h2.z) > 1e-12:
		var a := -(h1.x * h2.x + h1.y * h2.y) / (h1.z * h2.z)
		if a > 0.0:
			estimates.append(a)
	if absf(h2.z * h2.z - h1.z * h1.z) > 1e-12:
		var b := (h1.x * h1.x + h1.y * h1.y - h2.x * h2.x - h2.y * h2.y) / (h2.z * h2.z - h1.z * h1.z)
		if b > 0.0:
			estimates.append(b)
	var diagonal := image_size.length()
	focal = FALLBACK_FOCAL_PER_DIAGONAL * diagonal
	if not estimates.is_empty():
		var f := 0.0
		for e in estimates:
			f += sqrt(e)
		f /= estimates.size()
		if f > 0.25 * diagonal and f < 3.0 * diagonal:
			focal = f
	var k1 := Vector3(h1.x / focal, h1.y / focal, h1.z)
	var k2 := Vector3(h2.x / focal, h2.y / focal, h2.z)
	var k3 := Vector3(h3.x / focal, h3.y / focal, h3.z)
	var scale := 2.0 / (k1.length() + k2.length())
	_r1 = k1 * scale
	_r2 = k2 * scale
	_t = k3 * scale
	if _t.z < 0.0:  # the board must be in front of the camera
		_r1 = -_r1
		_r2 = -_r2
		_t = -_t
	_r1 = _r1.normalized()
	_r2 = (_r2 - _r1 * _r1.dot(_r2)).normalized()
	_r3 = _r1.cross(_r2)
	# "up" (away from the table) must point towards the camera: the camera sits on the positive side of the board plane.
	# The camera centre in board coordinates is -R^T t; its height is -(r3 . t).
	if -_r3.dot(_t) < 0.0:
		_r3 = -_r3


func _camera_space(x: float, z: float, up: float) -> Vector3:
	return _r1 * x + _r2 * z + _r3 * up + _t


func _camera_project(x: float, z: float, up: float) -> Vector2:
	var c := _camera_space(x, z, up)
	if c.z <= 1e-9:
		return Vector2(INF, INF)
	return Vector2(focal * c.x / c.z, focal * c.y / c.z) + _centre


# ---------------------------------------------------------------- homography (normalised DLT)

static func _apply(h: PackedFloat64Array, p: Vector2) -> Vector2:
	if h.size() != 9:
		return Vector2(INF, INF)
	var w := h[6] * p.x + h[7] * p.y + h[8]
	if absf(w) < 1e-12:
		return Vector2(INF, INF)
	return Vector2((h[0] * p.x + h[1] * p.y + h[2]) / w, (h[3] * p.x + h[4] * p.y + h[5]) / w)


## The 3x3 homography (row-major, h33 = 1) mapping `src` onto `dst`, least squares for more than 4 points; empty when degenerate.
static func _homography(src: Array[Vector2], dst: Array[Vector2]) -> PackedFloat64Array:
	var ts := _normaliser(src)
	var td := _normaliser(dst)
	var n := src.size()
	# normal equations of the 2n x 8 system
	var ata := []
	for i in 8:
		var row := PackedFloat64Array()
		row.resize(8)
		ata.append(row)
	var atb := PackedFloat64Array()
	atb.resize(8)
	for i in n:
		var s := _apply(ts, src[i])
		var d := _apply(td, dst[i])
		var rows := [
			[s.x, s.y, 1.0, 0.0, 0.0, 0.0, -d.x * s.x, -d.x * s.y, d.x],
			[0.0, 0.0, 0.0, s.x, s.y, 1.0, -d.y * s.x, -d.y * s.y, d.y],
		]
		for r in rows:
			for a in 8:
				atb[a] += r[a] * r[8]
				for b in 8:
					ata[a][b] += r[a] * r[b]
	var x := _solve(ata, atb)
	if x.is_empty():
		return PackedFloat64Array()
	var hn := PackedFloat64Array([x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7], 1.0])
	# H = Td^-1 * Hn * Ts
	var h := _mul(_mul(_inverse_normaliser(td), hn), ts)
	if absf(h[8]) < 1e-15:
		return PackedFloat64Array()
	for i in 9:
		h[i] /= h[8]
	return h


## Moves the points' centre to 0 and scales their mean distance to sqrt(2) (keeps the equations well conditioned).
static func _normaliser(points: Array[Vector2]) -> PackedFloat64Array:
	var centre := Vector2.ZERO
	for p in points:
		centre += p
	centre /= points.size()
	var mean := 0.0
	for p in points:
		mean += p.distance_to(centre)
	mean /= points.size()
	var s := sqrt(2.0) / maxf(mean, 1e-9)
	return PackedFloat64Array([s, 0.0, -s * centre.x, 0.0, s, -s * centre.y, 0.0, 0.0, 1.0])


static func _inverse_normaliser(t: PackedFloat64Array) -> PackedFloat64Array:
	var s := t[0]
	return PackedFloat64Array([1.0 / s, 0.0, -t[2] / s, 0.0, 1.0 / s, -t[5] / s, 0.0, 0.0, 1.0])


static func _mul(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var c := PackedFloat64Array()
	c.resize(9)
	for r in 3:
		for col in 3:
			c[r * 3 + col] = a[r * 3] * b[col] + a[r * 3 + 1] * b[3 + col] + a[r * 3 + 2] * b[6 + col]
	return c


## Gaussian elimination with partial pivoting; empty when the system is singular.
static func _solve(matrix: Array, rhs: PackedFloat64Array) -> PackedFloat64Array:
	var n := rhs.size()
	var m := []
	for i in n:
		var row := PackedFloat64Array(matrix[i])
		row.append(rhs[i])
		m.append(row)
	for col in n:
		var pivot := col
		for r in range(col + 1, n):
			if absf(m[r][col]) > absf(m[pivot][col]):
				pivot = r
		if absf(m[pivot][col]) < 1e-12:
			return PackedFloat64Array()
		var swap: PackedFloat64Array = m[col]
		m[col] = m[pivot]
		m[pivot] = swap
		for r in range(col + 1, n):
			var factor: float = m[r][col] / m[col][col]
			if factor == 0.0:
				continue
			var target: PackedFloat64Array = m[r]
			var source: PackedFloat64Array = m[col]
			for c in range(col, n + 1):
				target[c] -= factor * source[c]
			m[r] = target
	var x := PackedFloat64Array()
	x.resize(n)
	for r in range(n - 1, -1, -1):
		var row: PackedFloat64Array = m[r]
		var total := row[n]
		for c in range(r + 1, n):
			total -= row[c] * x[c]
		x[r] = total / row[r]
	return x


# ---------------------------------------------------------------- choosing what to click

## The rectangle (Rect2i in squares, both sides at least 2) of floor squares (`squares` = {Vector2i: true}, the ground level) whose
## four corners are best to click on a photo: big (the corners far apart in both directions) and with its corners where the floor
## ENDS - a room's corner is easy to find on a photo, a point in the middle of a big floor area can only be found by counting grid
## lines. Score = area x shorter side x (1 + corner points): an outer corner of the floor 2 points, a corner on a straight floor edge
## 1, a corner inside the floor 0. Rect2i() when there is no 2 x 2 area.
static func best_rectangle(squares: Dictionary) -> Rect2i:
	if squares.is_empty():
		return Rect2i()
	var low := Vector2i(1 << 20, 1 << 20)
	var high := Vector2i(-(1 << 20), -(1 << 20))
	for sq: Vector2i in squares:
		low = Vector2i(mini(low.x, sq.x), mini(low.y, sq.y))
		high = Vector2i(maxi(high.x, sq.x), maxi(high.y, sq.y))
	var width := high.x - low.x + 1
	var depth := high.y - low.y + 1
	# prefix[(z) * (width + 1) + x] = floor squares in the area above-left of (x, z)
	var prefix := PackedInt32Array()
	prefix.resize((width + 1) * (depth + 1))
	for z in depth:
		for x in width:
			var here := 1 if squares.has(Vector2i(low.x + x, low.y + z)) else 0
			prefix[(z + 1) * (width + 1) + x + 1] = here + prefix[z * (width + 1) + x + 1] + prefix[(z + 1) * (width + 1) + x] - prefix[z * (width + 1) + x]
	var best := Rect2i()
	var best_score := 0.0
	for z0 in depth:
		for z1 in range(z0 + 1, depth):
			for x0 in width:
				for x1 in range(x0 + 1, width):
					var count := prefix[(z1 + 1) * (width + 1) + x1 + 1] - prefix[z0 * (width + 1) + x1 + 1] - prefix[(z1 + 1) * (width + 1) + x0] + prefix[z0 * (width + 1) + x0]
					if count != (x1 - x0 + 1) * (z1 - z0 + 1):
						break  # a wider rectangle on these rows has the same hole
					var rect := Rect2i(low.x + x0, low.y + z0, x1 - x0 + 1, z1 - z0 + 1)
					var points := 0
					for corner in rectangle_corners(rect):
						points += _corner_points(squares, rect, Vector2i(corner))
					var score := float(rect.size.x * rect.size.y * mini(rect.size.x, rect.size.y)) * (1.0 + points)
					if score > best_score:
						best_score = score
						best = rect
	return best


## How findable a corner of `rect` is: 2 = the floor ends on both sides there (an outer corner), 1 = it lies on a straight edge of the
## floor, 0 = floor all around. `corner` is a grid point; of the four squares around it one is inside the rectangle.
static func _corner_points(squares: Dictionary, rect: Rect2i, corner: Vector2i) -> int:
	var outside := 0
	for offset in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var sq: Vector2i = corner + offset
		if not Rect2(rect).has_point(Vector2(sq) + Vector2(0.5, 0.5)) and not squares.has(sq):
			outside += 1
	return 2 if outside == 3 else (1 if outside == 2 else 0)


## The rectangle's four corner points (board coordinates of square corners), in the order the player clicks them.
static func rectangle_corners(rect: Rect2i) -> Array[Vector2]:
	var corners: Array[Vector2] = [
		Vector2(rect.position.x, rect.position.y),
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x, rect.end.y),
		Vector2(rect.position.x, rect.end.y),
	]
	return corners
