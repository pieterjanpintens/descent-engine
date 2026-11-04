class_name CampaignMapView
extends Control

## The map of one act: the act's map image (a plain grid when it has none) with a round pin per
## chapter and a diamond per place (point of interest), and an arrow for every link between
## chapters (green = on win, red = on lose, grey = always). A narrative chapter (story and questions, no mission) is a speech bubble instead of a round pin. In the editor pins/diamonds can be
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
signal side_quest_selected(quest_id: String)
signal side_quest_moved(quest_id: String)

const PIN_RADIUS := 14.0
const START_COLOR := Color(0.95, 0.8, 0.25)
const FINALE_COLOR := Color(0.7, 0.4, 0.9)
const PIN_COLOR := Color(0.3, 0.6, 0.95)
const PLACE_COLOR := Color(0.25, 0.75, 0.7)
const SIDE_QUEST_COLOR := Color(0.95, 0.55, 0.15)
const LINK_COLORS := {
	CampaignLink.Outcome.WIN: Color(0.4, 0.85, 0.4),
	CampaignLink.Outcome.LOSE: Color(0.9, 0.35, 0.35),
	CampaignLink.Outcome.ANY: Color(0.7, 0.7, 0.7),
}
const AVAILABLE_COLOR := Color(0.4, 0.85, 0.4)
## The map lies on a wooden table: this fills the whole control under the map image (cropped to cover, never stretched).
const TABLE_TEXTURE := "res://models/ui/bg_campaign_table.jpg"
## The pins are the game's own marker art when the user imported it (OfficialAssetMap), else dummy placeholders: a mission chapter, a narrative
## chapter (a short story with questions) and a side quest. Drawn ICON_HEIGHT tall, centred on the pin's position.
const STORY_ICON := "res://models/ui/map_pin_story.png"
const EVENT_ICON := "res://models/ui/map_pin_event.png"
const SIDE_ICON := "res://models/ui/map_pin_side.png"
const ICON_HEIGHT := 58.0
const HIT_RADIUS := 28.0
static var _icon_cache: Dictionary = {}  ## path -> ImageTexture at twice ICON_HEIGHT (shrunk once here: the art is 256 px, a 46 px draw of it would shimmer)

var act: CampaignAct
var texture: Texture2D
var selected_id: String = ""
var read_only: bool = false
## The editor shows a RELEASE: everything is visible and selectable but pins can not be dragged.
var locked: bool = false
var statuses: Dictionary = {}
## The side quests to show (the owner decides which: the editor lists the ones of this act, the player the
## ones on offer), each as an orange star.
var side_quests: Array[CampaignSideQuest] = []
## Ids of the side quests (player only) that are about to go: they get an "ENDING" tag.
var ending_quest_ids: Array[String] = []
var hidden_place_ids: Array[String] = []

var _dragging: Resource  ## the CampaignChapter or CampaignPlace being dragged
var _table: Texture2D  ## held here: a texture that is only loaded inside _draw() can be freed before the renderer draws it


func _ready() -> void:
	_table = load(TABLE_TEXTURE) as Texture2D
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
	_draw_table()
	var rect := map_rect()
	if texture != null:
		draw_rect(Rect2(rect.position + Vector2(3, 6), rect.size), Color(0, 0, 0, 0.4))  # a soft shadow: the map lies on the table
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
	for quest in side_quests:
		_draw_side_quest(quest)
	for chapter in act.chapters:
		if not _is_hidden(chapter):
			_draw_pin(chapter)


func _draw_table() -> void:
	if _table == null:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.12))
		return
	var picture := _table.get_size()
	var cover := maxf(size.x / picture.x, size.y / picture.y)
	var shown := size / cover  # the part of the picture that is visible, in picture pixels
	draw_texture_rect_region(_table, Rect2(Vector2.ZERO, size), Rect2((picture - shown) / 2.0, shown))


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
	# In the editor the start chapter and the finale are told apart by a coloured ring behind the marker.
	var ring := Color(0, 0, 0, 0)
	if not read_only and chapter.id == act.start_chapter_id:
		ring = START_COLOR
	elif not read_only and chapter.is_finale:
		ring = FINALE_COLOR
	_draw_icon(EVENT_ICON if chapter.is_narrative else STORY_ICON, center, chapter.id == selected_id, ring)
	_draw_label(center, chapter.title if chapter.title != "" else "(untitled)", ICON_HEIGHT * 0.5 + 14.0)
	if not read_only:
		if chapter.wait_for_all:
			_draw_badge(center + Vector2(-ICON_HEIGHT * 0.5, -ICON_HEIGHT * 0.5 - 2.0), "ALL")
		if chapter.exclusive_links:
			_draw_badge(center + Vector2(ICON_HEIGHT * 0.5, -ICON_HEIGHT * 0.5 - 2.0), "XOR")


## A small tag next to a pin (editor only): "ALL" = waits for every chapter leading to it, "XOR" = its links are
## a choice. Text, since fonts can't be trusted to have symbols for this.
func _draw_badge(anchor: Vector2, text: String, border: Color = Color(0.95, 0.8, 0.25)) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var box := Rect2(anchor - Vector2(width / 2.0 + 3.0, 11.0), Vector2(width + 6.0, 14.0))
	draw_rect(box, Color(0.1, 0.1, 0.14, 0.9))
	draw_rect(box, border, false, 1.0)
	draw_string(font, anchor + Vector2(-width / 2.0, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


func _draw_place(place: CampaignPlace) -> void:
	var center := pin_position(place)
	var radius := PIN_RADIUS - 1.0
	var diamond := PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, 0), center + Vector2(0, radius), center + Vector2(-radius, 0)])
	draw_colored_polygon(diamond, PLACE_COLOR)
	var outline := diamond.duplicate()
	outline.append(diamond[0])
	draw_polyline(outline, Color.WHITE if place.id == selected_id else Color(0, 0, 0, 0.7), 3.0 if place.id == selected_id else 2.0, true)
	_draw_label(center, place.title if place.title != "" else "(unnamed place)")


func _draw_side_quest(quest: CampaignSideQuest) -> void:
	var center := pin_position(quest)
	_draw_icon(SIDE_ICON, center, quest.id == selected_id, Color(0, 0, 0, 0))
	if ending_quest_ids.has(quest.id):
		_draw_badge(center + Vector2(0, -ICON_HEIGHT * 0.5 - 4.0), "ENDING", Color(0.95, 0.3, 0.25))
	_draw_label(center, quest.title if quest.title != "" else "(unnamed side quest)", ICON_HEIGHT * 0.5 + 14.0)


## A marker picture centred on `center`; a white ring behind it when selected, or `ring` (when it has any colour) for the editor's start / finale.
func _draw_icon(path: String, center: Vector2, selected: bool, ring: Color) -> void:
	if selected:
		draw_arc(center, ICON_HEIGHT * 0.58, 0.0, TAU, 40, Color.WHITE, 3.0, true)
	elif ring.a > 0.0:
		draw_arc(center, ICON_HEIGHT * 0.58, 0.0, TAU, 40, ring, 3.0, true)
	var picture := _icon(path)
	var shown := picture.get_size() / 2.0
	draw_texture_rect(picture, Rect2(center - shown / 2.0, shown), false)


## The marker art shrunk once to twice the height it is drawn at (official art when imported, else the shipped placeholder).
static func _icon(path: String) -> Texture2D:
	if _icon_cache.has(path):
		return _icon_cache[path]
	var source := OfficialAssetOverrides.texture_for(path)
	var image := source.get_image()
	var target_height := int(ICON_HEIGHT * 2.0)
	image.resize(maxi(int(round(image.get_width() * float(target_height) / image.get_height())), 1), target_height, Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	_icon_cache[path] = texture
	return texture


func _draw_label(center: Vector2, label: String, offset: float = PIN_RADIUS + 16.0) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string_outline(font, center + Vector2(-width / 2.0, offset), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.85))
	draw_string(font, center + Vector2(-width / 2.0, offset), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _gui_input(event: InputEvent) -> void:
	if act == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _item_at(event.position)
			if hit != null:
				_dragging = hit if not read_only and not locked else null
				selected_id = hit.get("id")
				if hit is CampaignPlace:
					place_selected.emit(selected_id)
				elif hit is CampaignSideQuest:
					side_quest_selected.emit(selected_id)
				else:
					chapter_selected.emit(selected_id)
				queue_redraw()
		else:
			if _dragging != null:
				if _dragging is CampaignPlace:
					place_moved.emit(_dragging.id)
				elif _dragging is CampaignSideQuest:
					side_quest_moved.emit(_dragging.id)
				else:
					chapter_moved.emit(_dragging.get("id"))
			_dragging = null
	elif event is InputEventMouseMotion and _dragging != null:
		var rect := map_rect()
		var relative: Vector2 = (event.position - rect.position) / rect.size
		_dragging.set("map_position", Vector2(clampf(relative.x, 0.0, 1.0), clampf(relative.y, 0.0, 1.0)))
		queue_redraw()


## The chapter, side quest or place whose pin is under `position` (chapters on top), or null.
func _item_at(position: Vector2) -> Resource:
	for i in range(act.chapters.size() - 1, -1, -1):
		if not _is_hidden(act.chapters[i]) and pin_position(act.chapters[i]).distance_to(position) <= HIT_RADIUS:
			return act.chapters[i]
	for i in range(side_quests.size() - 1, -1, -1):
		if pin_position(side_quests[i]).distance_to(position) <= HIT_RADIUS:
			return side_quests[i]
	for i in range(act.places.size() - 1, -1, -1):
		if not hidden_place_ids.has(act.places[i].id) and pin_position(act.places[i]).distance_to(position) <= PIN_RADIUS + 4.0:
			return act.places[i]
	return null
