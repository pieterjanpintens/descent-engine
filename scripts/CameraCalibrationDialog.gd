class_name CameraCalibrationDialog
extends Control

## Calibrating the table camera: a full-screen page with the camera's photo on the left and a small map of the board on the right.
## The map highlights the biggest rectangle of floor squares on the ground level (CameraCalibration.best_rectangle) with its corners
## numbered 1-4; the player clicks those corners on the photo, in that order. As soon as all four are there, the whole board as the
## engine knows it (every visible floor square, raised ones at their height) is drawn over the photo, so a bad fit shows at once;
## a corner can be dragged to correct it (a magnifier shows the spot under the mouse). "Turn the map" turns the small map a quarter
## so it looks like the table from the camera's side.
##
## `await run(squares, camera, calibration)` -> a CameraCalibration, or null when cancelled. `squares` = {Vector3i (x, level, z): true}
## for the board as it is on the table (MissionSight.build()["squares"]); `cards` = {Vector2i (x, z): Color} hazard cards shown on the
## small map (they help to recognise the board). An existing calibration starts with its points.

signal _done(result: CameraCalibration)

const SIDE_WIDTH := 280.0
const MAP_SIZE := 230.0
const POINT_RADIUS := 9.0
const GRAB_DISTANCE := 18.0
const LOUPE_SIZE := 190.0
const LOUPE_ZOOM := 3.0
const CORNER_COLOR := Color(1.0, 0.55, 0.15)
const GRID_COLOR := Color(0.35, 0.85, 1.0, 0.9)
const RAISED_GRID_COLOR := Color(0.85, 0.55, 1.0, 0.9)

var _camera: TableCamera
var _squares: Dictionary = {}
var _rect := Rect2i()
var _corners: Array[Vector2] = []  # board coordinates, in click order
var _photo: _PhotoView
var _map: _MapView
var _status: Label
var _use_button: Button
var _photo_button: Button
var _result: CameraCalibration


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var background := ColorRect.new()
	background.color = Color(0.05, 0.05, 0.07, 0.97)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		row.set("offset_" + side, 12.0 if side in ["left", "top"] else -12.0)
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	_photo = _PhotoView.new()
	_photo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_photo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_photo.points_changed.connect(_on_points_changed)
	row.add_child(_photo)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = SIDE_WIDTH
	side.add_theme_constant_override("separation", 8)
	row.add_child(side)
	var title := Label.new()
	title.text = "Table camera"
	title.add_theme_font_size_override("font_size", 22)
	side.add_child(title)
	var help := Label.new()
	help.text = "Click the corners of the orange area on the photo, in the order 1 to 4. Drag a corner to correct it."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = SIDE_WIDTH
	side.add_child(help)
	_map = _MapView.new()
	_map.custom_minimum_size = Vector2(SIDE_WIDTH, MAP_SIZE)
	side.add_child(_map)
	var turn := Button.new()
	turn.text = "Turn the map"
	turn.pressed.connect(func():
		_map.turns = (_map.turns + 1) % 4
		_map.queue_redraw())
	side.add_child(turn)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = SIDE_WIDTH
	side.add_child(_status)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	var row1 := HBoxContainer.new()
	side.add_child(row1)
	_photo_button = Button.new()
	_photo_button.text = "New photo"
	_photo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_photo_button.pressed.connect(_take_photo)
	row1.add_child(_photo_button)
	var restart := Button.new()
	restart.text = "Start over"
	restart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restart.pressed.connect(func():
		_photo.points.clear()
		_on_points_changed())
	row1.add_child(restart)
	var row2 := HBoxContainer.new()
	side.add_child(row2)
	_use_button = Button.new()
	_use_button.text = "Use this calibration"
	_use_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_use_button.disabled = true
	_use_button.pressed.connect(func(): _finish(_result))
	row2.add_child(_use_button)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): _finish(null))
	row2.add_child(cancel)


## Shows the page and waits for the player. `photo` = a photo to start with (null = take one now).
func run(squares: Dictionary, camera: TableCamera, existing: CameraCalibration = null, photo: Image = null, cards: Dictionary = {}) -> CameraCalibration:
	_camera = camera
	_squares = squares
	var lowest := 1 << 20
	for sq: Vector3i in squares:
		lowest = mini(lowest, sq.y)
	var ground := {}
	for sq: Vector3i in squares:
		if sq.y == lowest:
			ground[Vector2i(sq.x, sq.z)] = true
	_rect = CameraCalibration.best_rectangle(ground)
	_corners = CameraCalibration.rectangle_corners(_rect)
	_map.squares = squares
	_map.cards = cards
	_map.rect = _rect
	_map.lowest = lowest
	_photo.points.clear()
	if existing != null and existing.valid and existing.board_points == _corners:
		_photo.points = existing.image_points.duplicate()
	_result = null
	visible = true
	move_to_front()
	if _rect.size == Vector2i.ZERO:
		_status.text = tr("There is no area of at least 2 x 2 floor squares on the board to calibrate on yet.")
	elif photo != null:
		_set_photo(photo)
	else:
		_take_photo()
	return await _done


func _finish(result: CameraCalibration) -> void:
	visible = false
	_photo.texture = null
	_done.emit(result)


func _take_photo() -> void:
	_photo_button.disabled = true
	_status.text = tr("Taking a photo...")
	var answer := await _camera.take_photo()
	_photo_button.disabled = false
	if not answer["ok"]:
		_status.text = answer["error"]
		return
	_set_photo(answer["image"])


func _set_photo(image: Image) -> void:
	_photo.image_size = Vector2(image.get_width(), image.get_height())
	_photo.texture = ImageTexture.create_from_image(image)
	_on_points_changed()


func _on_points_changed() -> void:
	_map.next_corner = _photo.points.size()
	_map.queue_redraw()
	_result = null
	_photo.grid.clear()
	if _photo.points.size() == 4 and _photo.texture != null:
		var calibration := CameraCalibration.solve(_corners, _photo.points, _photo.image_size)
		if calibration.valid:
			_result = calibration
			_photo.grid = _grid_lines(calibration)
			_status.text = tr("Check that the drawn grid lies on the tiles everywhere, also on raised floors. Drag a corner to correct it.")
		else:
			_status.text = tr("These corners do not make a usable shape. Start over and click them in the order 1, 2, 3, 4.")
	elif _photo.texture != null:
		_status.text = tr("Click corner %d of the orange area on the photo.") % (_photo.points.size() + 1)
	_use_button.disabled = _result == null
	_photo.queue_redraw()


## Every visible floor square's outline in photo pixels: [PackedVector2Array outline, raised?].
func _grid_lines(calibration: CameraCalibration) -> Array:
	var lines := []
	for sq: Vector3i in _squares:
		var level := float(sq.y - _map.lowest)
		var corners := [Vector3(sq.x, level, sq.z), Vector3(sq.x + 1, level, sq.z), Vector3(sq.x + 1, level, sq.z + 1), Vector3(sq.x, level, sq.z + 1)]
		var outline := PackedVector2Array()
		var ok := true
		for corner: Vector3 in corners:
			if not calibration.is_visible(corner):
				ok = false
				break
			outline.append(calibration.project(corner))
		if ok:
			outline.append(outline[0])
			lines.append([outline, level > 0.0])
	return lines


## The hazard cards on the table ({Vector2i (x, z): Color}) for the small map: water blue, lava red, acid green, spikes brown.
static func hazard_cards(mission: MissionData, held_back: Dictionary = {}) -> Dictionary:
	var colors := {"water": Color(0.2, 0.4, 0.85), "lava": Color(0.85, 0.25, 0.1), "acid": Color(0.3, 0.75, 0.25), "spikes": Color(0.55, 0.45, 0.35)}
	var shown := {}
	for placement in mission.underlay_placements:
		if not held_back.has(placement) and mission.is_effectively_visible(placement):
			shown[placement.origin_cell] = colors.get(placement.mesh_item_name, Color(0.5, 0.5, 0.5))
	var cards := {}
	var cpt := FootprintRegistry.CELLS_PER_TILE
	for fine: Vector3i in mission.underlay_occupied_cells:
		var origin: Vector3i = mission.underlay_occupied_cells[fine]
		if shown.has(origin):
			cards[Vector2i(floori(float(fine.x) / cpt), floori(float(fine.z) / cpt))] = shown[origin]
	return cards


# ---------------------------------------------------------------- the photo

class _PhotoView extends Control:
	signal points_changed

	var texture: Texture2D
	var image_size := Vector2.ZERO
	var points: Array[Vector2] = []  # photo pixels
	var grid: Array = []
	var _dragging := -1
	var _mouse := Vector2(-1, -1)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	## Where the photo is drawn: as large as fits, centred.
	func _photo_rect() -> Rect2:
		if image_size.x <= 0.0:
			return Rect2()
		var scale := minf(size.x / image_size.x, size.y / image_size.y)
		var shown := image_size * scale
		return Rect2((size - shown) * 0.5, shown)

	func _to_screen(p: Vector2) -> Vector2:
		var r := _photo_rect()
		return r.position + p * (r.size.x / image_size.x)

	func _to_photo(p: Vector2) -> Vector2:
		var r := _photo_rect()
		return ((p - r.position) * (image_size.x / r.size.x)).clamp(Vector2.ZERO, image_size)

	func _gui_input(event: InputEvent) -> void:
		if texture == null:
			return
		if event is InputEventMouseMotion:
			_mouse = (event as InputEventMouseMotion).position
			if _dragging >= 0:
				points[_dragging] = _to_photo(_mouse)
				points_changed.emit()
			queue_redraw()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var button := event as InputEventMouseButton
			if button.pressed:
				for i in points.size():
					if _to_screen(points[i]).distance_to(button.position) <= GRAB_DISTANCE:
						_dragging = i
						return
				if points.size() < 4 and _photo_rect().has_point(button.position):
					points.append(_to_photo(button.position))
					points_changed.emit()
			else:
				_dragging = -1

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			_mouse = Vector2(-1, -1)
			queue_redraw()

	func _draw() -> void:
		if texture == null:
			return
		var r := _photo_rect()
		draw_texture_rect(texture, r, false)
		var k := r.size.x / image_size.x
		for line: Array in grid:
			var outline: PackedVector2Array = line[0]
			var screen := PackedVector2Array()
			for p in outline:
				screen.append(r.position + p * k)
			draw_polyline(screen, RAISED_GRID_COLOR if line[1] else GRID_COLOR, 1.5, true)
		if points.size() >= 2:
			var screen_points := PackedVector2Array()
			for p in points:
				screen_points.append(_to_screen(p))
			if points.size() == 4:
				screen_points.append(screen_points[0])
			draw_polyline(screen_points, CORNER_COLOR, 2.0, true)
		var font := get_theme_default_font()
		for i in points.size():
			var at := _to_screen(points[i])
			draw_circle(at, POINT_RADIUS, Color(0, 0, 0, 0.6))
			draw_arc(at, POINT_RADIUS, 0, TAU, 24, CORNER_COLOR, 2.0, true)
			draw_string(font, at + Vector2(-4, 5), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		_draw_loupe(r)

	## A magnifier in the corner furthest from the mouse: the photo around the mouse, LOUPE_ZOOM times bigger, with a cross.
	func _draw_loupe(r: Rect2) -> void:
		if not r.has_point(_mouse):
			return
		var centre := _to_photo(_mouse)
		var region_size := Vector2.ONE * (LOUPE_SIZE / LOUPE_ZOOM) * (image_size.x / r.size.x)
		var region := Rect2(centre - region_size * 0.5, region_size)
		var at := Vector2(8, 8) if _mouse.x > size.x * 0.5 or _mouse.y > size.y * 0.5 else size - Vector2.ONE * (LOUPE_SIZE + 8)
		if _mouse.x > size.x * 0.5 and _mouse.y < size.y * 0.5:
			at = Vector2(8, size.y - LOUPE_SIZE - 8)
		var box := Rect2(at, Vector2.ONE * LOUPE_SIZE)
		draw_rect(box, Color.BLACK)
		draw_texture_rect_region(texture, box, region)
		# the clicked corners and the grid near the mouse, in the loupe too
		var to_loupe := func(p: Vector2) -> Vector2: return at + (p - region.position) * (LOUPE_SIZE / region_size.x)
		for i in points.size():
			var p: Vector2 = to_loupe.call(points[i])
			if box.has_point(p):
				draw_arc(p, POINT_RADIUS, 0, TAU, 24, CORNER_COLOR, 2.0, true)
		var middle := box.get_center()
		draw_line(middle - Vector2(12, 0), middle + Vector2(12, 0), Color.WHITE, 1.0)
		draw_line(middle - Vector2(0, 12), middle + Vector2(0, 12), Color.WHITE, 1.0)
		draw_rect(box, CORNER_COLOR, false, 2.0)


# ---------------------------------------------------------------- the small map

class _MapView extends Control:
	var squares: Dictionary = {}
	var cards: Dictionary = {}
	var rect := Rect2i()
	var lowest := 0
	var next_corner := 0
	var turns := 0  # quarter turns (clockwise) of the drawing

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _turned(p: Vector2) -> Vector2:
		var q := p
		for i in turns:
			q = Vector2(-q.y, q.x)
		return q

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.13))
		if squares.is_empty():
			return
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		var all_cells: Array[Vector2] = []
		for sq: Vector3i in squares:
			all_cells.append(Vector2(sq.x, sq.z))
		for card: Vector2i in cards:
			all_cells.append(Vector2(card))
		for cell in all_cells:
			for corner in [cell, cell + Vector2.ONE]:
				var t := _turned(corner)
				low = Vector2(minf(low.x, t.x), minf(low.y, t.y))
				high = Vector2(maxf(high.x, t.x), maxf(high.y, t.y))
		var span := high - low
		var cell := minf((size.x - 16) / span.x, (size.y - 16) / span.y)
		var offset := (size - span * cell) * 0.5
		var to_screen := func(p: Vector2) -> Vector2: return offset + (_turned(p) - low) * cell
		var in_rect := Rect2(rect)
		for sq: Vector3i in squares:
			var a: Vector2 = to_screen.call(Vector2(sq.x, sq.z))
			var b: Vector2 = to_screen.call(Vector2(sq.x + 1, sq.z + 1))
			var box := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs())
			var shade := 0.35 + 0.12 * (sq.y - lowest)
			var color := Color(shade, shade, shade + 0.05)
			if cards.has(Vector2i(sq.x, sq.z)) and sq.y == lowest:
				color = (cards[Vector2i(sq.x, sq.z)] as Color).darkened(0.2)
			if sq.y == lowest and in_rect.has_point(Vector2(sq.x + 0.5, sq.z + 0.5)):
				color = Color(0.75, 0.42, 0.15)
			draw_rect(box.grow(-0.5), color)
		var font := get_theme_default_font()
		var corners := CameraCalibration.rectangle_corners(rect)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		for i in corners.size():
			var at: Vector2 = to_screen.call(corners[i])
			var fill := Color(1, 1, 1, 0.5 + 0.5 * pulse) if i == next_corner else Color(0, 0, 0, 0.75)
			draw_circle(at, 11, fill)
			draw_arc(at, 11, 0, TAU, 24, CORNER_COLOR, 2.0, true)
			draw_string(font, at + Vector2(-4, 5), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.BLACK if i == next_corner else Color.WHITE)

	func _process(_delta: float) -> void:
		if visible and next_corner < 4:
			queue_redraw()
