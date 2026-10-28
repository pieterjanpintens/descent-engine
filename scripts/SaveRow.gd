class_name SaveRow
extends Control

## One save game on the Load game page, in the designer's mockup: the campaign's art behind a dark gradient, the group (save game) name small above the
## campaign name, a play and a delete button on the right (his frame art; play is the same arrow as the New game page's, pointing forward).
## `setup(entry)` with {folder, key, group, campaign, progress, tag, texture, newer}; `apply_height(h)` sizes the text and buttons to the row.

signal pressed  ## released on the row itself (not on a button) - the page brings a row on the side to the middle
signal resume_pressed
signal delete_pressed
signal update_pressed

const NAV_ARROW := "res://models/ui/nav_arrow.png"
const DELETE_BUTTON := "res://models/ui/button_delete.png"

var _group: Label
var _campaign: Label
var _progress: Label
var _play: TextureButton
var _delete: TextureButton
var _update: Button


func setup(entry: Dictionary) -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	var texture := entry.get("texture") as Texture2D
	if texture != null:
		var picture := TextureRect.new()
		picture.texture = texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(picture)
	else:
		var fill := ColorRect.new()
		fill.color = Color.from_hsv(float(str(entry.get("campaign", "")).hash() % 360) / 360.0, 0.4, 0.28)
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)
	# dark on the left where the text is, letting the art show through towards the buttons
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0.85), Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.12)])
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = gradient
	shade_texture.fill_from = Vector2(0, 0)
	shade_texture.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = shade_texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var texts := VBoxContainer.new()
	texts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texts.offset_left = 40
	texts.offset_right = -260  # room for the buttons
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 2)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(texts)
	_group = MenuStyle.shadow_label(str(entry.get("group", "")), 26, Color(0.78, 0.78, 0.8), MenuStyle.SHADOW_COLOR, true)
	_campaign = MenuStyle.shadow_label(str(entry.get("campaign", "")) + str(entry.get("tag", "")), 36, MenuStyle.TEXT_COLOR)
	_progress = Label.new()
	_progress.text = str(entry.get("progress", ""))
	_progress.modulate = Color(1, 1, 1, 0.65)
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for label in [_group, _campaign, _progress]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		texts.add_child(label)

	var buttons := HBoxContainer.new()
	buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buttons.grow_vertical = Control.GROW_DIRECTION_BOTH
	buttons.offset_right = -34
	buttons.add_theme_constant_override("separation", 30)
	add_child(buttons)
	var newer := str(entry.get("newer", ""))
	if newer != "":
		_update = Button.new()
		_update.text = "Update to v%s…" % newer
		_update.tooltip_text = "Makes an updated COPY of this save game on the newer version. The original stays as it is."
		_update.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_update.pressed.connect(func(): update_pressed.emit())
		buttons.add_child(_update)
	_play = MenuStyle.texture_button(NAV_ARROW, Vector2(70, 70), func(): resume_pressed.emit(), true)
	_play.tooltip_text = "Continue this game"
	_delete = MenuStyle.texture_button(DELETE_BUTTON, Vector2(70, 70), func(): delete_pressed.emit())
	_delete.tooltip_text = "Delete this save game"
	buttons.add_child(_play)
	buttons.add_child(_delete)


## The row is `height` tall: text and buttons follow (the mockup's proportions).
func apply_height(height: float) -> void:
	_group.add_theme_font_size_override("font_size", roundi(height * 0.17))
	_campaign.add_theme_font_size_override("font_size", roundi(height * 0.24))
	_progress.add_theme_font_size_override("font_size", maxi(11, roundi(height * 0.09)))
	var button := Vector2(height * 0.48, height * 0.48)
	_play.custom_minimum_size = button
	_delete.custom_minimum_size = button


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT and not click.pressed:
		if Rect2(Vector2.ZERO, size).has_point(click.position):
			pressed.emit()
