class_name MenuStyle
extends RefCounted

## The look of the main menu (from the designer's mockup): Cinzel small-caps entries with an ornamental divider under each, and
## framed buttons drawn by tools/ui/generate_menu_frames.py. Static helpers only - MainMenu builds its pages with them.

const FONT_PATH := "res://fonts/Cinzel.ttf"
const DIVIDER_PATH := "res://models/ui/menu_divider.png"
const SQUARE_FRAME := "res://models/ui/menu_button_square.png"
const WIDE_FRAME := "res://models/ui/menu_button_wide.png"
const GEAR_ICON := "res://models/ui/menu_gear.png"

const TEXT_COLOR := Color(1, 1, 1)
const HOVER_COLOR := Color(1.0, 0.82, 0.55)
const DISABLED_COLOR := Color(1, 1, 1, 0.38)
const OUTLINE_COLOR := Color(0.07, 0.04, 0.22, 0.95)
const ORANGE := Color(0.95, 0.5, 0.2)


static func font(weight: int = 900) -> Font:
	var base := load(FONT_PATH) as Font
	if base == null:
		return ThemeDB.fallback_font
	var variation := FontVariation.new()
	variation.base_font = base
	variation.variation_opentype = {"wght": weight}
	variation.variation_embolden = 1.1  # on top of the heaviest weight: the mockup's letters are fat
	return variation


## One menu entry: the text as a flat button with the ornamental divider beneath it.
static func entry(text: String, on_pressed: Callable, size: int = 34) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -8)  # the divider sits right under the letters
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_override("font", font())
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", HOVER_COLOR)
	button.add_theme_color_override("font_pressed_color", HOVER_COLOR)
	button.add_theme_color_override("font_disabled_color", DISABLED_COLOR)
	# a bezel look: a hard shadow under the letters only, none around them
	button.add_theme_color_override("font_shadow_color", OUTLINE_COLOR)
	button.add_theme_constant_override("shadow_offset_x", 0)
	button.add_theme_constant_override("shadow_offset_y", maxi(3, size / 9))
	button.add_theme_constant_override("shadow_outline_size", 0)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var empty := StyleBoxEmpty.new()
		empty.content_margin_top = 0
		empty.content_margin_bottom = 0
		button.add_theme_stylebox_override(state, empty)
	button.pressed.connect(on_pressed)
	box.add_child(button)
	var divider := TextureRect.new()
	divider.texture = load(DIVIDER_PATH) as Texture2D
	divider.custom_minimum_size = Vector2(130, 26)
	divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	divider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	divider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(divider)
	return box


## A framed button (the ornate cyan frame). `wide` = the long "Collection" shape, otherwise the square one for an icon.
static func framed_button(text: String, wide: bool, size: Vector2, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = size
	button.add_theme_font_override("font", font())
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", TEXT_COLOR)
	button.add_theme_color_override("font_shadow_color", Color(0.05, 0.2, 0.4, 0.95))
	button.add_theme_constant_override("shadow_offset_y", 2)
	button.add_theme_constant_override("shadow_outline_size", 0)
	var texture := load(WIDE_FRAME if wide else SQUARE_FRAME) as Texture2D
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxTexture.new()
		style.texture = texture
		match state:
			"hover": style.modulate_color = Color(1.18, 1.18, 1.18)
			"pressed": style.modulate_color = Color(0.8, 0.8, 0.85)
			"disabled": style.modulate_color = Color(1, 1, 1, 0.5)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(on_pressed)
	return button


static func gear_button(size: float, on_pressed: Callable) -> Button:
	var button := framed_button("", false, Vector2(size, size), on_pressed)
	button.icon = load(GEAR_ICON) as Texture2D
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", int(size * 0.5))
	return button
