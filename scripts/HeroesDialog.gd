class_name HeroesDialog
extends Control

## The Party menu's "Heroes": every hero in play with their wound state
## (MissionRuntime.hero_wounds) and a "Wound" button - hit points are physical
## and not tracked, so when a hero drops to zero the table reports it here (the
## "wound hero" action). Pressing Wound closes this dialog and emits
## `wound_requested`; MissionPlayer confirms, applies it and handles the third wound
## (game lost). Built in code, modal scrim like QuestLogDialog; open() rebuilds fresh.

signal wound_requested(slot: int)

var _list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var background := PanelContainer.new()
	center.add_child(background)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(460, 0)
	vbox.add_theme_constant_override("separation", 8)
	background.add_child(vbox)

	var title := Label.new()
	title.text = "Heroes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	vbox.add_child(_list)

	var hint := Label.new()
	hint.text = "When a hero has lost all hitpoints, press Wound. The third wound loses the game."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.modulate = Color(1, 1, 1, 0.65)
	vbox.add_child(hint)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func(): visible = false)
	vbox.add_child(close_button)

	visible = false


## `roster`: the hero slots in play; `runtime` supplies each hero's wounds.
func open(roster: Array[int], runtime: MissionRuntime) -> void:
	for child in _list.get_children():
		child.queue_free()
	for slot in roster:
		var wounds := runtime.wound_count(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var portrait := TextureRect.new()
		portrait.texture = HeroCatalog.slot_portrait(slot)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.custom_minimum_size = Vector2(48, 48)
		row.add_child(portrait)
		var name_label := Label.new()
		name_label.text = HeroCatalog.slot_name(slot)
		name_label.custom_minimum_size = Vector2(110, 0)
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name_label)
		var state_label := Label.new()
		state_label.text = MissionRuntime.wound_label(wounds)
		state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		state_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		state_label.add_theme_color_override("font_color", [Color(0.7, 0.9, 0.7), Color(1.0, 0.7, 0.25), Color(1.0, 0.35, 0.3)][mini(wounds, 2)])
		row.add_child(state_label)
		var wound_button := Button.new()
		wound_button.text = "Wound"
		wound_button.pressed.connect(func():
			visible = false
			wound_requested.emit(slot)
		)
		row.add_child(wound_button)
		_list.add_child(row)
	visible = true
