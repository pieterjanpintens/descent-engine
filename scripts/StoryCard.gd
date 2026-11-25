class_name StoryCard
extends RefCounted

## The look of the game's quest / story cards (never instantiated, static helpers): a near-black panel in the game's ring-cornered
## frame (`9Slice_1`, through OfficialAssetMap; models/ui/card_frame.png is the placeholder) with grey ornament lines, a white Cinzel
## title, an orange subtitle and the orange button of the monster turn screen. Used by PlayerDialog (every in-game text box) and the
## campaign map's chapter / side quest card (QuestCard).
##
## The frame art is ONE white picture (body and ornament lines alike); frame_texture() splits it at run time: the big connected body
## (what survives eroding away the thin lines) becomes the dark fill, everything else the grey lines.

const FRAME_ART := "res://models/ui/card_frame.png"
const BUTTON_ART := "res://models/ui/turn_button.png"  ## Button1_Small (white, 9-slice), the monster turn screen's button
const BODY_COLOR := Color(0.055, 0.05, 0.05, 0.95)
const LINE_COLOR := Color(0.62, 0.62, 0.64)
const ORANGE := Color(0.86, 0.4, 0.07)
const SUBTITLE_COLOR := Color(1.0, 0.62, 0.2)
const TEXT_COLOR := Color(0.95, 0.93, 0.9)
## 9-slice margins of the frame art (256 x 93: two rings in each corner along the long side).
const PATCH_SIDE := 100
const PATCH_TOP := 46
## Room between the frame's edge and the content.
const CONTENT_SIDE := 30
const CONTENT_TOP := 26

static var _frame_cache: Texture2D


## The frame art, recoloured: dark body, grey lines (cached).
static func frame_texture() -> Texture2D:
	if _frame_cache != null:
		return _frame_cache
	var source := OfficialAssetOverrides.texture_for(FRAME_ART)
	if source == null:
		return null
	var image := source.get_image()
	if image == null:
		return source
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var solid := PackedByteArray()
	solid.resize(width * height)
	for y in height:
		for x in width:
			solid[y * width + x] = 1 if image.get_pixel(x, y).a >= 0.5 else 0
	# thin lines vanish when eroded by 2; the body is what is left around the middle, grown back by 3 (its anti-aliased edge included)
	var core := _grow(solid, width, height, 2, false)
	var body := _component(core, width, height, Vector2i(width / 2, height / 2))
	body = _grow(body, width, height, 3, true)
	for y in height:
		for x in width:
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			if body[y * width + x] == 1:
				image.set_pixel(x, y, Color(BODY_COLOR.r, BODY_COLOR.g, BODY_COLOR.b, pixel.a * BODY_COLOR.a))
			else:
				image.set_pixel(x, y, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, pixel.a))
	_frame_cache = ImageTexture.create_from_image(image)
	return _frame_cache


## Erodes (`grow` false) or dilates (true) a 0/1 mask by `radius` (square neighbourhood; done as a row pass then a column pass).
static func _grow(mask: PackedByteArray, width: int, height: int, radius: int, grow: bool) -> PackedByteArray:
	var rows := _pass(mask, width, height, radius, grow, Vector2i(1, 0))
	return _pass(rows, width, height, radius, grow, Vector2i(0, 1))


static func _pass(mask: PackedByteArray, width: int, height: int, radius: int, grow: bool, step: Vector2i) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(mask.size())
	for y in height:
		for x in width:
			var value := 0 if grow else 1
			for offset in range(-radius, radius + 1):
				var nx := x + step.x * offset
				var ny := y + step.y * offset
				var inside := nx >= 0 and ny >= 0 and nx < width and ny < height and mask[ny * width + nx] == 1
				if grow and inside:
					value = 1
					break
				if not grow and not inside:
					value = 0
					break
			result[y * width + x] = value
	return result


## The 4-connected part of `mask` that holds `seed` (empty when the seed is not in the mask).
static func _component(mask: PackedByteArray, width: int, height: int, seed: Vector2i) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(mask.size())
	if mask[seed.y * width + seed.x] == 0:
		return result
	var stack: Array[Vector2i] = [seed]
	while not stack.is_empty():
		var at: Vector2i = stack.pop_back()
		if at.x < 0 or at.y < 0 or at.x >= width or at.y >= height:
			continue
		var index := at.y * width + at.x
		if mask[index] == 0 or result[index] == 1:
			continue
		result[index] = 1
		stack.append(Vector2i(at.x + 1, at.y))
		stack.append(Vector2i(at.x - 1, at.y))
		stack.append(Vector2i(at.x, at.y + 1))
		stack.append(Vector2i(at.x, at.y - 1))
	return result


## A framed card: returns {root, content}. `root` is a MarginContainer sized by its content (add it where it should go); put the card's
## controls in `content` (a VBoxContainer).
static func build(separation: int = 10) -> Dictionary:
	var root := MarginContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var frame := NinePatchRect.new()
	frame.texture = frame_texture()
	frame.patch_margin_left = PATCH_SIDE
	frame.patch_margin_right = PATCH_SIDE
	frame.patch_margin_top = PATCH_TOP
	frame.patch_margin_bottom = PATCH_TOP
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", CONTENT_SIDE)
	margin.add_theme_constant_override("margin_right", CONTENT_SIDE)
	margin.add_theme_constant_override("margin_top", CONTENT_TOP)
	margin.add_theme_constant_override("margin_bottom", CONTENT_TOP)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", separation)
	margin.add_child(content)
	return {"root": root, "content": content, "frame": frame}


## The card's title: white Cinzel with the logo shadow.
static func title(text: String, size: int = 26) -> Label:
	var label := MenuStyle.shadow_label(text, size, Color.WHITE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 120.0
	return label


## The orange line under the title ("Main Quest").
static func subtitle(text: String, size: int = 16) -> Label:
	var label := MenuStyle.shadow_label(text, size, SUBTITLE_COLOR, MenuStyle.SHADOW_COLOR, false)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 120.0
	return label


## Body text (wrapping, light).
static func text(value: String, size: int = 17) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 200.0  # a wrapping label needs a width to start from
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	return label


## A small Cinzel heading inside the card ("The following heroes are required:").
static func heading(value: String, size: int = 15) -> Label:
	var label := MenuStyle.shadow_label(value, size, Color.WHITE, MenuStyle.SHADOW_COLOR, false)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 120.0
	return label


## The orange button (the monster turn screen's).
static func button(label_text: String, min_size: Vector2 = Vector2(150, 46), font_size: int = 19) -> Button:
	var result := Button.new()
	result.text = label_text
	style_button(result, min_size, font_size)
	return result


## Gives an existing button the orange look.
static func style_button(target: Button, min_size: Vector2 = Vector2(150, 46), font_size: int = 19) -> void:
	target.focus_mode = Control.FOCUS_NONE
	target.custom_minimum_size = Vector2(maxf(target.custom_minimum_size.x, min_size.x), maxf(target.custom_minimum_size.y, min_size.y))
	target.add_theme_font_override("font", MenuStyle.font())
	target.add_theme_font_size_override("font_size", font_size)
	target.add_theme_constant_override("outline_size", 6)
	target.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.0, 0.9))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		target.add_theme_color_override(state, Color.WHITE)
	target.add_theme_color_override("font_disabled_color", Color(0.75, 0.72, 0.7))
	var art := OfficialAssetOverrides.texture_for(BUTTON_ART)
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var box := StyleBoxTexture.new()
		box.texture = art
		box.texture_margin_left = 29
		box.texture_margin_right = 29
		box.texture_margin_top = 22
		box.texture_margin_bottom = 23
		box.content_margin_left = 22
		box.content_margin_right = 22
		match state:
			"hover", "hover_pressed":
				box.modulate_color = ORANGE.lightened(0.18)
			"pressed":
				box.modulate_color = ORANGE.darkened(0.2)
			"disabled":
				box.modulate_color = Color(0.42, 0.38, 0.36)
			"focus":
				box.modulate_color = Color(0, 0, 0, 0)
			_:
				box.modulate_color = ORANGE
		target.add_theme_stylebox_override(state, box)
