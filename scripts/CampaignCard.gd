class_name CampaignCard
extends Control

## One campaign (or mission) in the New Game carousel, drawn like the designer's mockup: a tall hexagon with the cover, a blue title plaque, the
## language flags, the play time and a book / sword icon for campaign / single mission. `item` is what LibraryPage built:
## {title, kind "campaign"|"mission", source "installed"|"draft"|"catalog", languages, minutes, texture (nullable)}.

signal pressed

const CARD_SIZE := Vector2(236, 430)
const PLAQUE_PATH := "res://models/ui/menu_button_wide.png"
const BORDER_COLOR := Color(0.62, 0.64, 0.70)
const BORDER_HOVER := Color(1.0, 0.82, 0.55)
const FLAG_HEIGHT := 18.0

## Textures drawn from _draw() must stay referenced: one loaded there and dropped at the end of the call is freed before the renderer draws it.
static var _textures: Dictionary = {}

var item: Dictionary = {}

var _hover := false
var _plaque: Texture2D


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_plaque = load(PLAQUE_PATH) as Texture2D
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
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()


## The hexagon (pointy top and bottom, vertical sides) shrunk by `inset` pixels.
func _hexagon(inset: float) -> PackedVector2Array:
	var width := size.x - inset * 2.0
	var height := size.y - inset * 2.0
	var shoulder := height * 0.17
	var left := inset
	var top := inset
	return PackedVector2Array([
		Vector2(left + width / 2.0, top),
		Vector2(left + width, top + shoulder),
		Vector2(left + width, top + height - shoulder),
		Vector2(left + width / 2.0, top + height),
		Vector2(left, top + height - shoulder),
		Vector2(left, top + shoulder),
	])


func _draw() -> void:
	var dimmed: bool = item.get("source", "") == "catalog"
	var tint := Color(1, 1, 1, 0.55) if dimmed else Color.WHITE
	var outer := _hexagon(3.0)
	var inner := _hexagon(9.0)
	draw_colored_polygon(outer, Color(0.1, 0.1, 0.13) * tint)
	# the cover, cropped to fill the hexagon
	var texture := item.get("texture") as Texture2D
	if texture != null:
		var box := Rect2(9.0, 9.0, size.x - 18.0, size.y - 18.0)
		var uvs := PackedVector2Array()
		var texture_aspect := float(texture.get_width()) / float(texture.get_height())
		var box_aspect := box.size.x / box.size.y
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
		for point in inner:
			uvs.append(Vector2(lerpf(u0, u1, (point.x - box.position.x) / box.size.x), lerpf(v0, v1, (point.y - box.position.y) / box.size.y)))
		draw_colored_polygon(inner, tint, uvs, texture)
	else:
		var hue := float(str(item.get("title", "")).hash() % 360) / 360.0
		draw_colored_polygon(inner, Color.from_hsv(hue, 0.45, 0.35) * tint)
	# a darkening of the lower part so the plaque and the small print read on any picture
	var top_y := size.y * 0.60
	var shoulder := (size.y - 18.0) * 0.17
	var bottom_shoulder := size.y - 9.0 - shoulder
	draw_colored_polygon(PackedVector2Array([
		Vector2(9.0, top_y), Vector2(size.x - 9.0, top_y), Vector2(size.x - 9.0, bottom_shoulder),
		Vector2(size.x / 2.0, size.y - 9.0), Vector2(9.0, bottom_shoulder),
	]), Color(0, 0, 0, 0.55))
	# the double border
	var border := BORDER_HOVER if _hover else BORDER_COLOR
	draw_polyline(_closed(outer), border * tint, 5.0, true)
	draw_polyline(_closed(inner), Color(border.r * 0.55, border.g * 0.55, border.b * 0.55) * tint, 2.0, true)

	var font := MenuStyle.font()
	# the title plaque
	var plaque_rect := Rect2(14.0, size.y * 0.625, size.x - 28.0, 64.0)
	draw_texture_rect(_plaque, plaque_rect, false, tint)
	var title := str(item.get("title", ""))
	var title_size := 18 if title.length() <= 22 else 15
	var lines := font.get_multiline_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, plaque_rect.size.x - 44.0, title_size, 2)
	draw_multiline_string(font, Vector2(plaque_rect.position.x + 22.0, plaque_rect.position.y + (plaque_rect.size.y - lines.y) / 2.0 + title_size), title, HORIZONTAL_ALIGNMENT_CENTER, plaque_rect.size.x - 44.0, title_size, 2, Color.WHITE * tint)
	if item.get("source", "") == "draft":
		draw_string(font, Vector2(0, 30), "IN DEVELOPMENT", HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(1.0, 0.8, 0.35))

	# flags | clock + play time
	var row_y := plaque_rect.end.y + 12.0
	var languages: Array = item.get("languages", [])
	var flags_width := 0.0
	var flag_textures: Array[Texture2D] = []
	for code: Variant in languages:
		flag_textures.append(_texture("res://models/ui/flag_%s.png" % str(code)))
	var codes: Array = languages
	var widths: Array[float] = []
	for index in flag_textures.size():
		var flag_texture := flag_textures[index]
		var w := FLAG_HEIGHT * (float(flag_texture.get_width()) / float(flag_texture.get_height())) if flag_texture != null else 26.0
		widths.append(w)
		flags_width += w + 5.0
	var minutes := int(item.get("minutes", 0))
	var time_text := CampaignInfo.duration_text(minutes)
	var clock := _texture("res://models/ui/icon_clock.png")
	var time_width := (FLAG_HEIGHT + 6.0 + font.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x) if time_text != "" else 0.0
	var gap := 16.0 if flags_width > 0.0 and time_width > 0.0 else 0.0
	var x := (size.x - (flags_width - 5.0 if flags_width > 0.0 else 0.0) - gap - time_width) / 2.0
	for index in flag_textures.size():
		if flag_textures[index] != null:
			draw_texture_rect(flag_textures[index], Rect2(x, row_y, widths[index], FLAG_HEIGHT), false, tint)
		else:
			draw_string(font, Vector2(x, row_y + FLAG_HEIGHT - 3.0), str(codes[index]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE * tint)
		x += widths[index] + 5.0
	if time_text != "":
		x += gap - (5.0 if flags_width > 0.0 else 0.0)
		draw_texture_rect(clock, Rect2(x, row_y, FLAG_HEIGHT, FLAG_HEIGHT), false, Color(1, 1, 1, 0.85) * tint)
		draw_string(font, Vector2(x + FLAG_HEIGHT + 6.0, row_y + FLAG_HEIGHT - 3.0), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.85) * tint)
	# campaign (book) or single mission (sword)
	var icon_path := "res://models/ui/icon_campaign.png" if item.get("kind", "campaign") == "campaign" else "res://models/ui/icon_mission.png"
	var icon := _texture(icon_path)
	draw_texture_rect(icon, Rect2(size.x / 2.0 - 21.0, size.y - 84.0, 42.0, 42.0), false, Color(1, 1, 1, 0.9) * tint)


static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[path]


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	closed.append(points[0])
	return closed
