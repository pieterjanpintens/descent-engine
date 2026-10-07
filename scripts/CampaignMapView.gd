class_name CampaignMapView
extends Control

## The map of one act: the act's map image (a plain grid when it has none) with a round pin per
## chapter and a diamond per place (point of interest), and an arrow for every link between
## chapters (green = on win, red = on lose, grey = always). In the editor pins/diamonds can be
## dragged (they edit `map_position` and tell the owner through the *_moved signals; saving and undo
## are the editor's business) and clicked to select. With `read_only` (the campaign player) nothing
## can be moved; chapters are coloured by `statuses` (chapter id -> "available" / "done" / "locked")
## instead of start/finale; only "available" chapters are shown (the story unfolds as it is played, and
## what was passed through is in the campaign log) - neither a pin nor an arrow for the others -, and
## places listed in `hidden_place_ids` are not shown.

signal chapter_selected(chapter_id: String)
signal chapter_moved(chapter_id: String)
signal place_selected(place_id: String)
signal place_moved(place_id: String)

const PIN_RADIUS := 14.0
const START_COLOR := Color(0.95, 0.8, 0.25)
const FINALE_COLOR := Color(0.7, 0.4, 0.9)
const PIN_COLOR := Color(0.3, 0.6, 0.95)
const PLACE_COLOR := Color(0.25, 0.75, 0.7)
const LINK_COLORS := {
	CampaignLink.Outcome.WIN: Color(0.4, 0.85, 0.4),
	CampaignLink.Outcome.LOSE: Color(0.9, 0.35, 0.35),
	CampaignLink.Outcome.ANY: Color(0.7, 0.7, 0.7),
}
const AVAILABLE_COLOR := Color(0.4, 0.85, 0.4)

var act: CampaignAct
var texture: Texture2D
var selected_id: String = ""
var read_only: bool = false
var statuses: Dictionary = {}
var hidden_place_ids: Array[String] = []

var _dragging: Resource  ## the CampaignChapter or CampaignPlace being dragged


func _ready() -> void:
	clip_contents = true
	resized.connect(queue_redraw)


## Shows `new_act` with `new_texture` as its map (either may be null).
func show_act(new_act: CampaignAct, new_texture: Texture2D, new_selected_id: String = "") -> void:
	act = new_act
	texture = new_texture
	selected_id = new_selected_id
	queue_redraw()


## Where the map is drawn: the image fitted and centred in the control (the whole control
## for the grid shown when there is no image).
func map_rect() -> Rect2:
	if texture == null:
		return Rect2(Vector2.ZERO, size)
	var image_size := texture.get_size()
	var scale_factor := minf(size.x / image_size.x, size.y / image_size.y)
	var drawn := image_size * scale_factor
	return Rect2((size - drawn) / 2.0, drawn)


## Screen position of a chapter or a place (anything with a `map_position`).
func pin_position(item: Resource) -> Vector2:
	var rect := map_rect()
	return rect.position + (item.get("map_position") as Vector2) * rect.size


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.12))
	var rect := map_rect()
	if texture != null:
		draw_texture_rect(texture, rect, false)
	else:
		var step := 50.0
		var x := 0.0
		while x <= size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.06))
			x += step
		var y := 0.0
		while y <= size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.06))
			y += step
		if not read_only:
			draw_string(ThemeDB.fallback_font, Vector2(12, 24), "No map image - choose one for this act", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.4))
	if act == null:
		return
	for chapter in act.chapters:
		if _is_hidden(chapter):
			continue
		for link in chapter.links:
			var target := act.find_chapter(link.target_id)
			if target != null and target != chapter and not _is_hidden(target):
				_draw_arrow(pin_position(chapter), pin_position(target), LINK_COLORS[link.outcome] if not read_only else Color(0.75, 0.75, 0.75, 0.6))
	for place in act.places:
		if not hidden_place_ids.has(place.id):
			_draw_place(place)
	for chapter in act.chapters:
		if not _is_hidden(chapter):
			_draw_pin(chapter)


func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	var direction := (to - from).normalized()
	var start := from + direction * PIN_RADIUS
	var end := to - direction * (PIN_RADIUS + 2.0)
	draw_line(start, end, color, 2.5, true)
	var side := direction.orthogonal()
	draw_colored_polygon(PackedVector2Array([end, end - direction * 12.0 + side * 6.0, end - direction * 12.0 - side * 6.0]), color)


## Whether `chapter` is kept off the map: in the player, every chapter that can't be played right now.
func _is_hidden(chapter: CampaignChapter) -> bool:
	return read_only and statuses.get(chapter.id, "locked") != "available"


func _draw_pin(chapter: CampaignChapter) -> void:
	var center := pin_position(chapter)
	var fill := PIN_COLOR
	if read_only:
		fill = AVAILABLE_COLOR
	elif chapter.id == act.start_chapter_id:
		fill = START_COLOR
	elif chapter.is_finale:
		fill = FINALE_COLOR
	draw_circle(center, PIN_RADIUS, fill)
	draw_arc(center, PIN_RADIUS, 0.0, TAU, 32, Color.WHITE if chapter.id == selected_id else Color(0, 0, 0, 0.7), 3.0 if chapter.id == selected_id else 2.0, true)
	_draw_label(center, chapter.title if chapter.title != "" else "(untitled)")


func _draw_place(place: CampaignPlace) -> void:
	var center := pin_position(place)
	var radius := PIN_RADIUS - 1.0
	var diamond := PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, 0), center + Vector2(0, radius), center + Vector2(-radius, 0)])
	draw_colored_polygon(diamond, PLACE_COLOR)
	var outline := diamond.duplicate()
	outline.append(diamond[0])
	draw_polyline(outline, Color.WHITE if place.id == selected_id else Color(0, 0, 0, 0.7), 3.0 if place.id == selected_id else 2.0, true)
	_draw_label(center, place.title if place.title != "" else "(unnamed place)")


func _draw_label(center: Vector2, label: String) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string_outline(font, center + Vector2(-width / 2.0, PIN_RADIUS + 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.85))
	draw_string(font, center + Vector2(-width / 2.0, PIN_RADIUS + 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _gui_input(event: InputEvent) -> void:
	if act == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _item_at(event.position)
			if hit != null:
				_dragging = hit if not read_only else null
				selected_id = hit.get("id")
				if hit is CampaignPlace:
					place_selected.emit(selected_id)
				else:
					chapter_selected.emit(selected_id)
				queue_redraw()
		else:
			if _dragging != null:
				if _dragging is CampaignPlace:
					place_moved.emit(_dragging.id)
				else:
					chapter_moved.emit(_dragging.get("id"))
			_dragging = null
	elif event is InputEventMouseMotion and _dragging != null:
		var rect := map_rect()
		var relative: Vector2 = (event.position - rect.position) / rect.size
		_dragging.set("map_position", Vector2(clampf(relative.x, 0.0, 1.0), clampf(relative.y, 0.0, 1.0)))
		queue_redraw()


## The chapter or place whose pin is under `position` (chapters on top), or null.
func _item_at(position: Vector2) -> Resource:
	for i in range(act.chapters.size() - 1, -1, -1):
		if not _is_hidden(act.chapters[i]) and pin_position(act.chapters[i]).distance_to(position) <= PIN_RADIUS + 4.0:
			return act.chapters[i]
	for i in range(act.places.size() - 1, -1, -1):
		if not hidden_place_ids.has(act.places[i].id) and pin_position(act.places[i]).distance_to(position) <= PIN_RADIUS + 4.0:
			return act.places[i]
	return null
