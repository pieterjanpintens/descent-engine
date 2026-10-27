class_name CampaignCard
extends Control

## One campaign (or mission) in the New Game carousel, built from the designer's pieces: his hexagon frame (models/ui/card_frame.png) over the cover,
## his blue plaque with the title, his language flags, a clock + play time and his book / sword icon for campaign / single mission.
## `item` is what LibraryPage built: {title, kind "campaign"|"mission", source "installed"|"draft"|"catalog", languages, minutes, texture (nullable)}.

signal pressed

## The frame image is 439 x 1138.
const CARD_SIZE := Vector2(176, 456)
const SHOULDER_TOP := 0.145      ## where the frame's top point has widened to the full width (fraction of the height)
const SHOULDER_BOTTOM := 0.832   ## and where it starts narrowing again
const HOVER_TINT := Color(1.0, 0.82, 0.55)
const FLAG_HEIGHT := 17.0

## Textures drawn from _draw() must stay referenced: one loaded there and dropped at the end of the call is freed before the renderer draws it.
static var _textures: Dictionary = {}

var item: Dictionary = {}

var _hover := false
var _down := false


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func():
		_hover = true
		queue_redraw()
	)
	mouse_exited.connect(func():
		_hover = false
		queue_redraw()
	)


func setup(card_item: Dictionary) -> void:
	item = card_item
	tooltip_text = "%s%s" % [str(item.get("title", "")), "\nNot installed yet - open it to install." if item.get("source", "") == "catalog" else ("\nIn development (a draft)" if item.get("source", "") == "draft" else "")]
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# a click counts on release (so a drag that starts on the card is not a click); the event is not accepted, the carousel sees it too
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			_down = true
		elif _down:
			_down = false
			if Rect2(Vector2.ZERO, size).has_point(click.position):
				pressed.emit()


## The hexagon of the frame (pointy top and bottom, vertical sides).
func _hexagon() -> PackedVector2Array:
	var w := size.x
	var h := size.y
	return PackedVector2Array([
		Vector2(w / 2.0, 0.0), Vector2(w, h * SHOULDER_TOP), Vector2(w, h * SHOULDER_BOTTOM),
		Vector2(w / 2.0, h), Vector2(0.0, h * SHOULDER_BOTTOM), Vector2(0.0, h * SHOULDER_TOP),
	])


func _draw() -> void:
	var dimmed: bool = item.get("source", "") == "catalog"
	var tint := Color(1, 1, 1, 0.55) if dimmed else Color.WHITE
	var hexagon := _hexagon()
	var whole := Rect2(Vector2.ZERO, size)
	# the cover, cropped to fill the hexagon (a coloured gradient while there is no picture)
	var texture := item.get("texture") as Texture2D
	if texture != null:
		var uvs := PackedVector2Array()
		var texture_aspect := float(texture.get_width()) / float(texture.get_height())
		var box_aspect := size.x / size.y
		var u0 := 0.0
		var u1 := 1.0
		var v0 := 0.0
		var v1 := 1.0
		if texture_aspect > box_aspect:
			var keep := box_aspect / texture_aspect
			u0 = (1.0 - keep) / 2.0
			u1 = u0 + keep
		else:
			var keep_v := texture_aspect / box_aspect
			v0 = (1.0 - keep_v) / 2.0
			v1 = v0 + keep_v
		for point in hexagon:
			uvs.append(Vector2(lerpf(u0, u1, point.x / size.x), lerpf(v0, v1, point.y / size.y)))
		draw_colored_polygon(hexagon, tint, uvs, texture)
	else:
		var hue := float(str(item.get("title", "")).hash() % 360) / 360.0
		draw_texture_rect(_texture("res://models/ui/card_gradient.png"), whole, false, Color.from_hsv(hue, 0.5, 0.75) * tint)
	# a darkening of the lower part so the plaque and the small print read on any picture
	var top_y := size.y * 0.56
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, top_y), Vector2(size.x, top_y), Vector2(size.x, size.y * SHOULDER_BOTTOM), Vector2(size.x / 2.0, size.y), Vector2(0, size.y * SHOULDER_BOTTOM),
	]), Color(0, 0, 0, 0.5))
	draw_texture_rect(_texture("res://models/ui/card_frame.png"), whole, false, (HOVER_TINT if _hover else Color.WHITE) * tint)

	var font := MenuStyle.font()
	# the title plaque, a little wider than the card like in the mockup
	var plaque_width := size.x + 16.0
	var plaque_rect := Rect2(-8.0, size.y * 0.62, plaque_width, plaque_width / 3.06)
	draw_texture_rect(_texture(MenuStyle.PLAQUE_PATH), plaque_rect, false, tint)
	var title := str(item.get("title", ""))
	var title_size := 16 if title.length() <= 18 else 13
	var text_width := plaque_rect.size.x - 40.0
	var lines := font.get_multiline_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, text_width, title_size, 2)
	draw_multiline_string(font, Vector2(plaque_rect.position.x + 20.0, plaque_rect.position.y + (plaque_rect.size.y - lines.y) / 2.0 + title_size - 1.0), title, HORIZONTAL_ALIGNMENT_CENTER, text_width, title_size, 2, Color.WHITE * tint)
	if item.get("source", "") == "draft":
		draw_string(font, Vector2(0, 26), "IN DEVELOPMENT", HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(1.0, 0.8, 0.35))

	# flags | clock + play time
	var row_y := plaque_rect.end.y + 12.0
	var flag_textures: Array[Texture2D] = []
	var codes: Array = item.get("languages", [])
	var widths: Array[float] = []
	var flags_width := 0.0
	for code: Variant in codes:
		var flag_texture := _texture("res://models/ui/flag_%s.png" % str(code))
		flag_textures.append(flag_texture)
		var w := FLAG_HEIGHT * (float(flag_texture.get_width()) / float(flag_texture.get_height())) if flag_texture != null else 22.0
		widths.append(w)
		flags_width += w + 4.0
	flags_width = maxf(0.0, flags_width - 4.0)
	var time_text := CampaignInfo.duration_text(int(item.get("minutes", 0)))
	var time_size := 13
	var time_width := (FLAG_HEIGHT + 4.0 + font.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, time_size).x) if time_text != "" else 0.0
	var dash_gap := 14.0 if flags_width > 0.0 and time_width > 0.0 else 0.0
	var x := (size.x - flags_width - dash_gap - time_width) / 2.0
	for index in flag_textures.size():
		if flag_textures[index] != null:
			draw_texture_rect(flag_textures[index], Rect2(x, row_y, widths[index], FLAG_HEIGHT), false, tint)
		else:
			draw_string(font, Vector2(x, row_y + FLAG_HEIGHT - 3.0), str(codes[index]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE * tint)
		x += widths[index] + 4.0
	if time_text != "":
		if dash_gap > 0.0:
			x += dash_gap / 2.0 - 4.0
			draw_texture_rect(_texture("res://models/ui/icon_dash.png"), Rect2(x - 1.0, row_y - 1.0, 2.5, FLAG_HEIGHT + 2.0), false, Color(1, 1, 1, 0.8) * tint)
			x += dash_gap / 2.0 + 4.0
		draw_texture_rect(_texture("res://models/ui/icon_clock.png"), Rect2(x, row_y, FLAG_HEIGHT, FLAG_HEIGHT), false, Color(1, 1, 1, 0.85) * tint)
		draw_string(font, Vector2(x + FLAG_HEIGHT + 4.0, row_y + FLAG_HEIGHT - 3.0), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, time_size, Color(1, 1, 1, 0.85) * tint)
	# campaign (book) or single mission (sword)
	var icon := _texture("res://models/ui/icon_campaign.png" if item.get("kind", "campaign") == "campaign" else "res://models/ui/icon_mission.png")
	draw_texture_rect(icon, Rect2(size.x / 2.0 - 20.0, size.y - 82.0, 40.0, 40.0), false, Color(1, 1, 1, 0.9) * tint)


static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[path]
