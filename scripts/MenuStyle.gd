class_name MenuStyle
extends RefCounted

## The look of the main menu (the designer's Illustrator mockup): Cinzel small-caps entries with an ornamental divider under each, and the
## designer's own ornate frames for the buttons (models/ui, extracted from his .ai file at 3x the mockup size; drawn whole, the shapes
## already have the aspect of the buttons: about 1:1 for the cog and 3.1:1 for the wide one). Static helpers only -
## MainMenu builds its pages with them.

const FONT_PATH := "res://fonts/Cinzel.ttf"
const DIVIDER_PATH := "res://models/ui/menu_divider.png"
const SQUARE_FRAME := "res://models/ui/menu_button_square.png"
const WIDE_FRAME := "res://models/ui/menu_button_wide.png"

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
	box.add_theme_constant_override("separation", -12)  # the divider sits right under the letters
	var holder := MarginContainer.new()  # sizes itself to the label; the button covers all of it
	box.add_child(holder)
	var label := shadow_label(text, size, TEXT_COLOR)
	holder.add_child(label)
	var button := _invisible_button()
	button.pressed.connect(on_pressed)
	button.mouse_entered.connect(func(): if not button.disabled: label.add_theme_color_override("font_color", HOVER_COLOR))
	button.mouse_exited.connect(func(): label.add_theme_color_override("font_color", TEXT_COLOR))
	holder.add_child(button)
	var divider := TextureRect.new()
	divider.texture = load(DIVIDER_PATH) as Texture2D
	divider.custom_minimum_size = Vector2(130, 31)
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


## A framed button (the ornate cyan frame). `wide` = the long "Collection" shape, otherwise the square one for an icon.
static func framed_button(text: String, wide: bool, size: Vector2, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = size
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
	if text != "":
		var label := shadow_label(text, 20, TEXT_COLOR, SHADOW_COLOR, false)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(label)
	button.pressed.connect(on_pressed)
	return button


## The cog: the designer's square frame already has the gear in it.
static func gear_button(size: float, on_pressed: Callable) -> Button:
	return framed_button("", false, Vector2(size, size), on_pressed)
