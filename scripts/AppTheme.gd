class_name AppTheme
extends RefCounted

## The look of the whole app, in the spirit of the main menu: a dark indigo palette, an orange accent, and Cinzel for headings and buttons only
## (body text - labels, text boxes, check boxes, dropdown values, popup menu items - keeps the normal font so long texts stay readable).
## One Theme (the project theme, filled by the AppThemeSetup autoload), so every Control and every Window (the editors, Options, the dialogs, the
## campaign screens, the mission HUD) picks it up; a hand-made override in a script still wins over it.
## Anything this theme does not mention falls back to Godot's default theme.

const FONT_PATH := "res://fonts/Cinzel.ttf"

const BG_WINDOW := Color(0.085, 0.065, 0.18)
const BG_PANEL := Color(0.12, 0.10, 0.24)
const BG_INPUT := Color(0.06, 0.045, 0.14)
const BG_BUTTON := Color(0.20, 0.15, 0.40)
const BG_BUTTON_HOVER := Color(0.29, 0.22, 0.55)
const BG_BUTTON_PRESSED := Color(0.12, 0.09, 0.26)
const BG_SELECTED := Color(0.27, 0.21, 0.50)
const BORDER := Color(0.42, 0.34, 0.72)
const BORDER_SOFT := Color(0.28, 0.22, 0.50)
const ACCENT := Color(0.95, 0.5, 0.2)
const TEXT := Color(0.92, 0.93, 0.98)
const TEXT_HOVER := Color(1.0, 0.82, 0.55)
const TEXT_DISABLED := Color(1, 1, 1, 0.38)
const HEADING := Color(0.56, 0.79, 0.9)

const BUTTON_FONT_SIZE := 13
const HEADING_FONT_SIZE := 16
const TITLE_FONT_SIZE := 22

static var _fonts: Dictionary = {}


## Cinzel at a weight (400-900), with the normal font behind it for the glyphs Cinzel lacks (arrows, x, warning signs...).
static func font(weight: int = 700) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var base := load(FONT_PATH) as Font
	var result: Font = ThemeDB.fallback_font
	if base != null:
		var variation := FontVariation.new()
		variation.base_font = base
		variation.variation_opentype = {"wght": weight}
		variation.fallbacks = [ThemeDB.fallback_font]
		result = variation
	_fonts[weight] = result
	return result


static func _flat(bg: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0, radius: int = 4, margin_x: float = -1.0, margin_y: float = -1.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	if margin_x >= 0.0:
		style.content_margin_left = margin_x
		style.content_margin_right = margin_x
	if margin_y >= 0.0:
		style.content_margin_top = margin_y
		style.content_margin_bottom = margin_y
	return style


## A copy of Godot's own style for a control part with the colours swapped (keeps its content margins, which the layout of windows and popups relies on).
static func _recolored(theme_type: String, style_name: String, bg: Color, border: Color) -> StyleBox:
	var original := ThemeDB.get_default_theme().get_stylebox(style_name, theme_type)
	var copy := original.duplicate() as StyleBox
	var flat := copy as StyleBoxFlat
	if flat != null:
		flat.bg_color = bg
		flat.border_color = border
	return copy


static func build() -> Theme:
	return populate(Theme.new())


## Fills a theme with the app's look. The project theme (res://theme/app_theme.tres, set in the project settings, an empty stub) is filled at
## startup rather than saved with the content, so the fonts and styles live here in code - and a project theme, unlike a theme set on the
## root window, also reaches controls that sit under a non-Control parent such as a CanvasLayer.
static func populate(theme: Theme) -> Theme:
	var cinzel := font(600)
	var cinzel_light := font(500)

	# ---- Buttons (and everything built on Button) ----
	theme.set_stylebox("normal", "Button", _flat(BG_BUTTON, BORDER_SOFT, 1, 4, 8, 5))
	theme.set_stylebox("hover", "Button", _flat(BG_BUTTON_HOVER, BORDER, 1, 4, 8, 5))
	theme.set_stylebox("pressed", "Button", _flat(BG_BUTTON_PRESSED, ACCENT, 1, 4, 8, 5))
	theme.set_stylebox("hover_pressed", "Button", _flat(BG_BUTTON_PRESSED, ACCENT, 1, 4, 8, 5))
	theme.set_stylebox("disabled", "Button", _flat(Color(BG_BUTTON.r, BG_BUTTON.g, BG_BUTTON.b, 0.45), Color(BORDER_SOFT.r, BORDER_SOFT.g, BORDER_SOFT.b, 0.5), 1, 4, 8, 5))
	var focus := _flat(Color(0, 0, 0, 0), ACCENT, 1, 4, 8, 5)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_font("font", "Button", cinzel)
	theme.set_font_size("font_size", "Button", BUTTON_FONT_SIZE)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT_HOVER)
	theme.set_color("font_hover_pressed_color", "Button", TEXT_HOVER)
	theme.set_color("font_pressed_color", "Button", TEXT_HOVER)
	theme.set_color("font_focus_color", "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", TEXT_DISABLED)

	# Button's children that read as settings or values, not as actions, keep the normal font (and size).
	for type_name in ["CheckBox", "CheckButton", "OptionButton", "MenuButton", "ColorPickerButton"]:
		theme.set_font("font", type_name, ThemeDB.fallback_font)
		theme.set_font_size("font_size", type_name, ThemeDB.fallback_font_size)
	# A check box has no frame of its own: the button boxes would turn it into a framed button.
	for type_name in ["CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			theme.set_stylebox(state, type_name, StyleBoxEmpty.new())
		theme.set_color("font_hover_color", type_name, TEXT_HOVER)
		theme.set_color("font_pressed_color", type_name, TEXT)
		theme.set_color("font_hover_pressed_color", type_name, TEXT_HOVER)

	var unchecked := _check_icon(false)
	var checked := _check_icon(true)
	theme.set_icon("unchecked", "CheckBox", unchecked)
	theme.set_icon("checked", "CheckBox", checked)
	theme.set_icon("unchecked_disabled", "CheckBox", unchecked)
	theme.set_icon("checked_disabled", "CheckBox", checked)

	# ---- Menu bars and tabs ----
	theme.set_font("font", "MenuBar", cinzel)
	theme.set_font_size("font_size", "MenuBar", BUTTON_FONT_SIZE)
	theme.set_color("font_hover_color", "MenuBar", TEXT_HOVER)
	theme.set_color("font_pressed_color", "MenuBar", TEXT_HOVER)
	theme.set_stylebox("normal", "MenuBar", _flat(BG_WINDOW, Color(0, 0, 0, 0), 0, 0, 8, 5))
	theme.set_stylebox("hover", "MenuBar", _flat(BG_BUTTON_HOVER, Color(0, 0, 0, 0), 0, 3, 8, 5))
	theme.set_stylebox("pressed", "MenuBar", _flat(BG_BUTTON_PRESSED, Color(0, 0, 0, 0), 0, 3, 8, 5))

	for tab_type in ["TabContainer", "TabBar"]:
		theme.set_font("font", tab_type, cinzel)
		theme.set_font_size("font_size", tab_type, BUTTON_FONT_SIZE)
		theme.set_color("font_selected_color", tab_type, TEXT_HOVER)
		theme.set_color("font_hovered_color", tab_type, TEXT_HOVER)
		theme.set_color("font_unselected_color", tab_type, TEXT)
		theme.set_color("font_disabled_color", tab_type, TEXT_DISABLED)
		var selected := _flat(BG_PANEL, BORDER, 1, 4, 12, 6)
		selected.border_width_top = 2
		selected.border_color = BORDER
		selected.corner_radius_bottom_left = 0
		selected.corner_radius_bottom_right = 0
		var selected_marked := selected.duplicate() as StyleBoxFlat
		selected_marked.border_color = ACCENT
		selected_marked.border_width_left = 0
		selected_marked.border_width_right = 0
		selected_marked.border_width_bottom = 0
		var unselected := _flat(BG_WINDOW, BORDER_SOFT, 1, 4, 12, 6)
		unselected.corner_radius_bottom_left = 0
		unselected.corner_radius_bottom_right = 0
		var hovered := unselected.duplicate() as StyleBoxFlat
		hovered.bg_color = BG_BUTTON_HOVER
		var disabled := unselected.duplicate() as StyleBoxFlat
		disabled.bg_color = Color(BG_WINDOW.r, BG_WINDOW.g, BG_WINDOW.b, 0.5)
		theme.set_stylebox("tab_selected", tab_type, selected_marked)
		theme.set_stylebox("tab_unselected", tab_type, unselected)
		theme.set_stylebox("tab_hovered", tab_type, hovered)
		theme.set_stylebox("tab_disabled", tab_type, disabled)
		theme.set_stylebox("tab_focus", tab_type, StyleBoxEmpty.new())
	var tab_panel := _flat(BG_PANEL, BORDER, 1, 4)
	tab_panel.corner_radius_top_left = 0
	theme.set_stylebox("panel", "TabContainer", tab_panel)

	# ---- Panels and windows ----
	theme.set_stylebox("panel", "Panel", _flat(BG_PANEL, BORDER_SOFT, 1, 4))
	theme.set_stylebox("panel", "PanelContainer", _flat(BG_PANEL, BORDER_SOFT, 1, 4, 8, 6))
	theme.set_stylebox("panel", "AcceptDialog", _flat(BG_WINDOW, BORDER, 1, 4, 10, 10))
	theme.set_stylebox("panel", "PopupPanel", _flat(BG_WINDOW, BORDER, 1, 4, 6, 6))
	theme.set_font("title_font", "Window", cinzel)
	theme.set_font_size("title_font_size", "Window", HEADING_FONT_SIZE)
	theme.set_color("title_color", "Window", HEADING)
	theme.set_stylebox("embedded_border", "Window", _recolored("Window", "embedded_border", BG_WINDOW, BORDER))
	theme.set_stylebox("embedded_unfocused_border", "Window", _recolored("Window", "embedded_unfocused_border", BG_WINDOW, BORDER_SOFT))

	# ---- Text input ----
	var input := _flat(BG_INPUT, BORDER_SOFT, 1, 3, 6, 4)
	var input_focus := _flat(BG_INPUT, ACCENT, 1, 3, 6, 4)
	var input_read_only := _flat(Color(BG_INPUT.r, BG_INPUT.g, BG_INPUT.b, 0.6), BORDER_SOFT, 1, 3, 6, 4)
	for text_type in ["LineEdit", "TextEdit", "CodeEdit"]:
		theme.set_stylebox("normal", text_type, input)
		theme.set_stylebox("focus", text_type, input_focus)
		theme.set_stylebox("read_only", text_type, input_read_only)
	theme.set_color("caret_color", "LineEdit", TEXT_HOVER)
	theme.set_color("caret_color", "TextEdit", TEXT_HOVER)

	# ---- Lists, trees, popup menus ----
	var list_selected := _flat(BG_SELECTED, Color(0, 0, 0, 0), 0, 2)
	for list_type in ["Tree", "ItemList"]:
		theme.set_stylebox("panel", list_type, _flat(BG_INPUT, BORDER_SOFT, 1, 3))
		theme.set_stylebox("selected", list_type, list_selected)
		theme.set_stylebox("selected_focus", list_type, list_selected)
	theme.set_stylebox("panel", "PopupMenu", _flat(BG_WINDOW, BORDER, 1, 4, 4, 4))
	theme.set_stylebox("hover", "PopupMenu", _flat(BG_SELECTED, Color(0, 0, 0, 0), 0, 3))
	theme.set_color("font_hover_color", "PopupMenu", TEXT_HOVER)

	# ---- Odds and ends ----
	theme.set_stylebox("background", "ProgressBar", _flat(BG_INPUT, BORDER_SOFT, 1, 3))
	theme.set_stylebox("fill", "ProgressBar", _flat(ACCENT, Color(0, 0, 0, 0), 0, 3))
	var line := StyleBoxLine.new()
	line.color = BORDER_SOFT
	line.thickness = 1
	theme.set_stylebox("separator", "HSeparator", line)
	var vline := StyleBoxLine.new()
	vline.color = BORDER_SOFT
	vline.thickness = 1
	vline.vertical = true
	theme.set_stylebox("separator", "VSeparator", vline)

	# ---- Heading labels: apply with `label.theme_type_variation = &"HeadingLabel"` (or "TitleLabel") ----
	theme.set_type_variation("HeadingLabel", "Label")
	theme.set_font("font", "HeadingLabel", cinzel)
	theme.set_font_size("font_size", "HeadingLabel", HEADING_FONT_SIZE)
	theme.set_color("font_color", "HeadingLabel", HEADING)
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", font(800))
	theme.set_font_size("font_size", "TitleLabel", TITLE_FONT_SIZE)
	theme.set_color("font_color", "TitleLabel", TEXT)
	# A lighter weight Cinzel for small captions, for scripts that want it.
	theme.set_type_variation("CaptionLabel", "Label")
	theme.set_font("font", "CaptionLabel", cinzel_light)
	theme.set_font_size("font_size", "CaptionLabel", BUTTON_FONT_SIZE)
	return theme


## The editors (mission Creator, campaign editor and every window they open) keep Godot's normal look: a theme on their root control that gives
## every item the app theme defines back its default value. (Not set on the root window: a theme on a control only reaches its own children.)
static var _classic: Theme


static func classic() -> Theme:
	if _classic != null:
		return _classic
	var app := build()
	var base := ThemeDB.get_default_theme()
	var classic_theme := Theme.new()
	for type_name in app.get_type_list():
		var base_type := app.get_type_variation_base(type_name)
		if base_type != &"":
			classic_theme.set_type_variation(type_name, base_type)
		for item in app.get_stylebox_list(type_name):
			if base.has_stylebox(item, type_name):
				classic_theme.set_stylebox(item, type_name, base.get_stylebox(item, type_name))
		for item in app.get_font_list(type_name):
			classic_theme.set_font(item, type_name, base.get_font(item, type_name) if base.has_font(item, type_name) else ThemeDB.fallback_font)
		for item in app.get_font_size_list(type_name):
			classic_theme.set_font_size(item, type_name, base.get_font_size(item, type_name) if base.has_font_size(item, type_name) else ThemeDB.fallback_font_size)
		for item in app.get_color_list(type_name):
			if base.has_color(item, type_name):
				classic_theme.set_color(item, type_name, base.get_color(item, type_name))
		for item in app.get_icon_list(type_name):
			if base.has_icon(item, type_name):
				classic_theme.set_icon(item, type_name, base.get_icon(item, type_name))
	_classic = classic_theme
	return _classic


static func apply_classic(control: Control) -> void:
	control.theme = classic()


## A check box picture that shows on the dark panels: a light frame, and an orange tick when checked.
static func _check_icon(is_checked: bool) -> Texture2D:
	var size := 18
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var frame := Color(0.62, 0.56, 0.9)
	var fill := Color(0.06, 0.045, 0.14)
	for x in size:
		for y in size:
			var edge := x < 2 or y < 2 or x >= size - 2 or y >= size - 2
			var corner := (x < 2 or x >= size - 2) and (y < 2 or y >= size - 2)
			if corner:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, frame if edge else fill)
	if is_checked:
		var tick := ACCENT
		for i in 4:
			_dot(image, 4 + i, 8 + i, tick)
		for i in 7:
			_dot(image, 7 + i, 11 - i, tick)
	return ImageTexture.create_from_image(image)


static func _dot(image: Image, x: int, y: int, color: Color) -> void:
	for dx in 2:
		for dy in 2:
			if x + dx < image.get_width() and y + dy < image.get_height():
				image.set_pixel(x + dx, y + dy, color)


## Marks a label as a section heading (Cinzel, the heading colour). A colour or size the caller sets on the label itself still wins.
static func heading(label: Label, size: int = 0) -> Label:
	label.theme_type_variation = &"HeadingLabel"
	if size > 0:
		label.add_theme_font_size_override("font_size", size)
	return label
