class_name MenuStyle
extends RefCounted

## The look of the menus (the designer's deliverables in models/ui): Cinzel small-caps entries with the ornamental divider under each, and his
## button art - the cog, arrows, the blue plaque and the gold button (both empty: the captions are drawn so they can be translated).
## Static helpers only - MainMenu and LibraryPage build their pages with them.

const FONT_PATH := "res://fonts/Cinzel.ttf"
const DIVIDER_PATH := "res://models/ui/divider.png"
const PLAQUE_PATH := "res://models/ui/plaque.png"  # the blue title plaque, empty
const GOLD_BUTTON_PATH := "res://models/ui/button_gold.png"  # the gold ornamental button, empty (the caption is drawn, so it can be translated)
const OPTIONS_PATH := "res://models/ui/options.png"
const COLLECTION_PATH := "res://models/ui/collection.png"

const TEXT_COLOR := Color(1, 1, 1)
const HOVER_COLOR := Color(1.0, 0.82, 0.55)
const DISABLED_COLOR := Color(1, 1, 1, 0.38)
const OUTLINE_COLOR := Color(0.07, 0.04, 0.22, 0.95)
const SHADOW_COLOR := Color(0.08, 0.07, 0.1, 1.0)  # near black, like the logo's extruded shadow
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


## A Label with the logo-style shadow (Button has no shadow in its theme, Label does): near black, extruded under the letters.
static func shadow_label(text: String, size: int, color: Color, shadow_color: Color = SHADOW_COLOR, shadow: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if not shadow:
		return label
	# like the logo: a solid shadow extruded under the letters (light from above), none on top
	label.add_theme_color_override("font_shadow_color", shadow_color)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", maxi(3, size / 8))
	label.add_theme_constant_override("shadow_outline_size", 1)
	return label


static func _invisible_button() -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	return button


## One menu entry: the text (a shadowed label with an invisible button on top) with the ornamental divider beneath it.
static func entry(text: String, on_pressed: Callable, size: int = 30) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)  # the divider sits right under the letters
	var holder := MarginContainer.new()  # sizes itself to the label; the button covers all of it
	box.add_child(holder)
	var label := shadow_label(text, size, TEXT_COLOR)
	holder.add_child(label)
	var button := _invisible_button()
	if on_pressed.is_valid():
		button.pressed.connect(on_pressed)
	button.mouse_entered.connect(func(): if not button.disabled: label.add_theme_color_override("font_color", HOVER_COLOR))
	button.mouse_exited.connect(func(): label.add_theme_color_override("font_color", TEXT_COLOR))
	holder.add_child(button)
	var divider := TextureRect.new()
	divider.texture = load(DIVIDER_PATH) as Texture2D
	divider.custom_minimum_size = Vector2(124, 31)
	divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	divider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	divider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(divider)
	return box


static func set_entry_disabled(entry_box: Control, disabled: bool) -> void:
	var holder := entry_box.get_child(0)
	(holder.get_child(1) as Button).disabled = disabled
	(holder.get_child(0) as Label).modulate = Color(1, 1, 1, 0.38) if disabled else Color.WHITE


## A button that is just a picture of the designer's (the lettering is part of the art). Brightens on hover; `flip` mirrors it (previous -> next).
static func texture_button(path: String, size: Vector2, on_pressed: Callable, flip: bool = false) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = load(path) as Texture2D
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.custom_minimum_size = size
	button.flip_h = flip
	button.focus_mode = Control.FOCUS_NONE
	if on_pressed.is_valid():
		button.pressed.connect(on_pressed)
	button.mouse_entered.connect(func(): button.modulate = Color(1.18, 1.18, 1.18))
	button.mouse_exited.connect(func(): button.modulate = Color.WHITE)
	return button


## The biggest font size (at most `max_size`) at which `text` fits in `max_width`: captions differ in length per language.
static func fit_font_size(text: String, max_size: int, max_width: float) -> int:
	var f := font()
	var chosen := max_size
	while chosen > 10 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, chosen).x > max_width:
		chosen -= 1
	return chosen


## The designer's gold button (no lettering on the art) with `text` drawn on it, shrunk to fit.
static func gold_button(text: String, size: Vector2, font_size: int, on_pressed: Callable) -> TextureButton:
	var button := texture_button(GOLD_BUTTON_PATH, size, on_pressed)
	var label := shadow_label(text, fit_font_size(text, font_size, size.x * 0.8), TEXT_COLOR)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(label)
	return button


## A button with text on the designer's blue plaque (the text shrinks to fit, up to `font_size`).
static func plaque_button(text: String, size: Vector2, on_pressed: Callable, font_size: int = 20) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = size
	var texture := load(PLAQUE_PATH) as Texture2D
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxTexture.new()
		style.texture = texture
		match state:
			"hover": style.modulate_color = Color(1.18, 1.18, 1.18)
			"pressed": style.modulate_color = Color(0.8, 0.8, 0.85)
			"disabled": style.modulate_color = Color(1, 1, 1, 0.5)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var label := shadow_label(text, fit_font_size(text, font_size, size.x * 0.8), TEXT_COLOR, SHADOW_COLOR, false)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(label)
	if on_pressed.is_valid():
		button.pressed.connect(on_pressed)
	return button


static func gear_button(size: float, on_pressed: Callable) -> TextureButton:
	return texture_button(OPTIONS_PATH, Vector2(size, size), on_pressed)
