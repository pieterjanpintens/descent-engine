class_name MonsterTurnView
extends Control

## A monster's turn, built after the original game's activation screen: the monster's flat model big on the left, and on the right
## its name over the game's ornamental line, and a panel in the colour of its chip (like the game: the colour tells the table
## which figure acts) with "Target: <hero>", what it does (its activation ability, tactic or confused action), the rules text and the
## speed / range / damage icons, then the Interrupt / Continue buttons. Shown by
## PlayerDialog.ask_monster_attack(). With `dim` off (the app moves the monster and its path is drawn on the map) the model is left out,
## the panel sits on the right and only that side is darkened: the camera puts the path in the free left part of the screen
## (MissionPlayer._frame_path(), PATH_SCREEN_X / Y).
## The art goes through the official-asset overrides: dummy placeholders ship, the game's pieces come with the asset import.

const ICON_SPEED := "res://models/ui/turn_speed.png"          ## official: Icon_Movement
const ICON_RANGE := "res://models/ui/turn_range.png"          ## Icon_Range
const ICON_DAMAGE := "res://models/ui/turn_damage.png"        ## Icon_Damage
const BUTTON_ART := "res://models/ui/turn_button.png"         ## Button1_Small (white, 9-slice)
const FRAME_ART := "res://models/ui/turn_frame.png"           ## 9Slice_2 (white, 9-slice)
const UNDERLINE_ART := "res://models/ui/turn_underline.png"   ## Underline

const ORANGE := Color(0.86, 0.4, 0.07)
const FRAME_COLOR := Color(0.78, 0.33, 0.07)  ## no chip colour given
const GOLD := Color(1.0, 0.72, 0.25)
const UP_COLOR := Color(0.35, 0.95, 0.4)    ## a stat above the monster's normal value
const DOWN_COLOR := Color(1.0, 0.4, 0.35)   ## ...below it
const PANEL_TOP := Color(0.1, 0.045, 0.03)
const PANEL_BOTTOM := Color(0.36, 0.13, 0.04)

## Backdrop darkness: full view / with the path on the map.
const BACKDROP_ALPHA := 0.86
const BACKDROP_ALPHA_PATH := 0.75  ## the right side, behind the panel; it fades out towards the left, where the path is
## Path mode: the turn screen takes the screen from here to the right edge (fraction of the width).
const PATH_PANEL_LEFT := 0.45

var continue_button: Button
var interrupt_button: Button
var hint_label: Label

var _backdrop: ColorRect
var _side_shade: TextureRect  ## path mode: dark on the right, clear on the left
var _art: CombatMeshPreview
var _column: VBoxContainer
var _title: Label
var _action: Label
var _frame: NinePatchRect
var _gradient: Gradient
var _underline: TextureRect
var _panel: Control
var _target_row: HBoxContainer
var _target_name: Label
var _body: Label
var _stats_row: HBoxContainer
var _path_mode := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	var shade := Gradient.new()
	shade.set_color(0, Color(0.05, 0.02, 0.015, 0.0))
	shade.set_color(1, Color(0.05, 0.02, 0.015, BACKDROP_ALPHA_PATH))
	shade.add_point(0.45, Color(0.05, 0.02, 0.015, BACKDROP_ALPHA_PATH))
	shade.set_offset(0, 0.0)
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = shade
	shade_texture.fill_from = Vector2(0, 0)
	shade_texture.fill_to = Vector2(1, 0)
	_side_shade = TextureRect.new()
	_side_shade.texture = shade_texture
	_side_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_side_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_side_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side_shade.anchor_left = PATH_PANEL_LEFT - 0.12
	_side_shade.anchor_right = 1.0
	_side_shade.anchor_bottom = 1.0
	add_child(_side_shade)

	_art = CombatMeshPreview.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)

	_column = VBoxContainer.new()
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_theme_constant_override("separation", 6)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)

	_title = MenuStyle.shadow_label("", 30, Color.WHITE)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = 300.0
	_column.add_child(_title)
	_underline = TextureRect.new()
	_underline.texture = OfficialAssetOverrides.texture_for(UNDERLINE_ART)
	_underline.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_underline.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_underline.custom_minimum_size = Vector2(220, 32)
	_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_underline)

	# the panel and the buttons under it share one width: Interrupt under its left edge, Continue under its right edge
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	block.add_theme_constant_override("separation", 10)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(block)
	block.add_child(_build_panel())
	var buttons := HBoxContainer.new()
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(buttons)
	interrupt_button = _button(tr("Interrupt"))
	buttons.add_child(interrupt_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_child(spacer)
	continue_button = _button(tr("Continue"))
	buttons.add_child(continue_button)

	hint_label = Label.new()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size.x = 300.0
	hint_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	hint_label.visible = false
	_column.add_child(hint_label)
	visible = false


func _build_panel() -> Control:
	# The frame (the game's 9-slice with corner ornaments, tinted) with a dark, warm gradient inside it.
	var holder := MarginContainer.new()
	holder.custom_minimum_size.x = 420.0
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := NinePatchRect.new()
	frame.texture = OfficialAssetOverrides.texture_for(FRAME_ART)
	var margin := 23
	frame.patch_margin_left = margin
	frame.patch_margin_right = margin
	frame.patch_margin_top = margin
	frame.patch_margin_bottom = margin
	frame.modulate = FRAME_COLOR
	_frame = frame
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	var fill_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		fill_margin.add_theme_constant_override("margin_" + side, 8)  # the frame art's body starts ~6 px in: a thin border stays visible
	fill_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill_margin)
	var gradient := Gradient.new()
	gradient.set_color(0, PANEL_TOP)
	gradient.set_color(1, PANEL_BOTTOM)
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	_gradient = gradient
	gradient_texture.fill_from = Vector2(0, 0)
	gradient_texture.fill_to = Vector2(0, 1)
	var fill := TextureRect.new()
	fill.texture = gradient_texture
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_margin.add_child(fill)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 28)
	content_margin.add_theme_constant_override("margin_right", 28)
	content_margin.add_theme_constant_override("margin_top", 20)
	content_margin.add_theme_constant_override("margin_bottom", 16)
	content_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(content_margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_margin.add_child(content)

	_target_row = HBoxContainer.new()
	_target_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_target_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_row.add_child(MenuStyle.shadow_label(tr("Target:") + " ", 22, Color.WHITE))
	_target_name = MenuStyle.shadow_label("", 22, GOLD)
	_target_row.add_child(_target_name)
	content.add_child(_target_row)

	_action = MenuStyle.shadow_label("", 18, GOLD)
	_action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action.custom_minimum_size.x = 350.0
	content.add_child(_action)

	_body = Label.new()
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 350.0  # a wrapping label needs a width to start from
	_body.add_theme_font_size_override("font_size", 16)
	_body.add_theme_color_override("font_color", Color(0.96, 0.93, 0.88))
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_body)

	_stats_row = HBoxContainer.new()
	_stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_stats_row.add_theme_constant_override("separation", 40)
	_stats_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_stats_row)
	_panel = holder
	return holder


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(150, 46)
	button.add_theme_font_override("font", MenuStyle.font())
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_constant_override("outline_size", 6)
	button.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.0, 0.9))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color.WHITE)
	var art := OfficialAssetOverrides.texture_for(BUTTON_ART)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxTexture.new()
		box.texture = art
		box.texture_margin_left = 29
		box.texture_margin_right = 29
		box.texture_margin_top = 22
		box.texture_margin_bottom = 23
		match state:
			"hover":
				box.modulate_color = ORANGE.lightened(0.18)
			"pressed":
				box.modulate_color = ORANGE.darkened(0.2)
			"focus":
				box.modulate_color = Color(0, 0, 0, 0)
			_:
				box.modulate_color = ORANGE
		button.add_theme_stylebox_override(state, box)
	return button


## `cfg`: MonsterDisplay.preview_data() for the model, plus
##   title (big heading: the monster's name), chip (its chip colour: the panel's colour), target (hero name, "" = no target line),
##   action (what it does: the activation ability / tactic / confused action name, "" = none),
##   text (the rules text), stats ({speed, speed_base, range, reach, damage, damage_base}, any may be missing), dim (false = path mode).
func configure(cfg: Dictionary) -> void:
	_path_mode = not cfg.get("dim", true)
	_backdrop.color = Color(0.05, 0.02, 0.015, 0.0 if _path_mode else BACKDROP_ALPHA)
	_side_shade.visible = _path_mode
	_art.visible = not _path_mode  # the path on the map is the picture in this mode
	# the right edge stays clear of the monster cards along the right side of the map (MonsterSidebar)
	var clear_right := -(MonsterSidebar.RIGHT_MARGIN + MonsterTabCard.CARD_SIZE.x + 12.0)
	if _path_mode:
		_place(_column, PATH_PANEL_LEFT, 1.0, 0.04, 0.96, clear_right)
	else:
		_place(_art, 0.0, 0.52, 0.0, 1.0)
		_place(_column, 0.38, 1.0, 0.04, 0.96, clear_right)
	_title.add_theme_font_size_override("font_size", 26 if _path_mode else 30)
	_title.text = str(cfg.get("title", ""))
	_action.text = str(cfg.get("action", ""))
	_action.visible = _action.text != ""
	# the panel in the colour of the monster's chip
	var chip: Color = cfg.get("chip", Color(0, 0, 0, 0))
	if chip.a > 0.0:
		_frame.modulate = chip.lerp(Color.WHITE, 0.1)
		_gradient.set_color(0, chip.darkened(0.9))
		_gradient.set_color(1, chip.darkened(0.6))
	else:
		_frame.modulate = FRAME_COLOR
		_gradient.set_color(0, PANEL_TOP)
		_gradient.set_color(1, PANEL_BOTTOM)
	var target := str(cfg.get("target", ""))
	_target_row.visible = target != ""
	_target_name.text = target
	_body.text = GameIcons.apply(str(cfg.get("text", "")))  # [damage], [success]... as the game's icons
	_body.visible = _body.text != ""
	_build_stats(cfg.get("stats", {}))
	var meshes: Array = cfg.get("monster_flat_meshes", [])
	if not meshes.is_empty():
		var paths: Array[String] = []
		for path in meshes:
			paths.append(str(path))
		var size_units: float = cfg.get("monster_size_units", 1.0)
		_art.show_meshes(paths, cfg.get("monster_flat_texture"), cfg.get("monster_flat_rotation", Vector3.ZERO), cfg.get("monster_flat_surface_overrides", {}), size_units, size_units, cfg.get("monster_flat_write_depth", false))
	else:
		_art.show_quad(cfg.get("monster_image"))


func _place(control: Control, left: float, right: float, top: float, bottom: float, right_offset: float = 0.0) -> void:
	control.anchor_left = left
	control.anchor_right = right
	control.anchor_top = top
	control.anchor_bottom = bottom
	control.offset_left = 0
	control.offset_right = right_offset
	control.offset_top = 0
	control.offset_bottom = 0


func _build_stats(stats: Dictionary) -> void:
	for child in _stats_row.get_children():
		child.free()
	_stats_row.visible = not stats.is_empty()
	if stats.has("speed"):
		_stats_row.add_child(_stat(ICON_SPEED, str(int(stats["speed"])), _delta_color(int(stats["speed"]), int(stats.get("speed_base", stats["speed"])))))
	if stats.has("range") and (int(stats["range"]) > 0 or stats.get("reach", false)):  # melee: no range shown, like the game
		var range_value := int(stats["range"])
		var shown := str(range_value) if range_value > 0 else tr("Reach")
		_stats_row.add_child(_stat(ICON_RANGE, shown, Color.WHITE, range_value <= 0))
	if stats.has("damage"):
		_stats_row.add_child(_stat(ICON_DAMAGE, str(int(stats["damage"])), _delta_color(int(stats["damage"]), int(stats.get("damage_base", stats["damage"])))))


func _delta_color(value: int, base: int) -> Color:
	if value > base:
		return UP_COLOR
	if value < base:
		return DOWN_COLOR
	return Color.WHITE


func _stat(icon_path: String, value: String, color: Color, small_text: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = OfficialAssetOverrides.texture_for(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(46, 46)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var label := MenuStyle.shadow_label(value, 20 if small_text else 34, color)
	row.add_child(label)
	return row


## Lets clicks through to the map (path mode) or blocks them (full view); the panel's buttons always take clicks.
func set_blocking(blocking: bool) -> void:
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP if blocking else Control.MOUSE_FILTER_IGNORE
