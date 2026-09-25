class_name QuestLogDialog
extends Control

## The Party menu's "Quest Log": the current objective(s) on top, then a
## replay of everything the table was told (see Journal.gd), newest first.
## Click an entry to read it again - read-only (going "back" is re-reading,
## not re-deciding: the effects of an answered dialog have already happened).
## Built in code, modal scrim like VoiceSettingsDialog; open() rebuilds fresh.

## Assigned by MissionPlayer.
var journal: Journal
## Returns the current objective descriptions (MissionRuntime.
## get_current_objective_descriptions()).
var objectives_provider: Callable

var _objective_label: Label
var _list: VBoxContainer
var _text: RichTextLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var background := PanelContainer.new()
	margin.add_child(background)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	background.add_child(vbox)

	var title := Label.new()
	title.text = "Quest Log"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bold := FontVariation.new()
	bold.base_font = title.get_theme_font("font")
	bold.variation_embolden = 1.0
	title.add_theme_font_override("font", bold)
	vbox.add_child(title)

	_objective_label = Label.new()
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_objective_label.modulate = Color(0.56, 0.79, 0.9)
	vbox.add_child(_objective_label)
	vbox.add_child(HSeparator.new())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(split)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_text = RichTextLabel.new()
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.bbcode_enabled = false
	_text.selection_enabled = true
	split.add_child(_text)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func(): visible = false)
	vbox.add_child(close_button)

	visible = false


func open() -> void:
	var descriptions: Array = []
	if objectives_provider.is_valid():
		descriptions = objectives_provider.call()
	_objective_label.text = "Current objective: %s" % ", ".join(descriptions) if not descriptions.is_empty() else "No current objective."

	for child in _list.get_children():
		child.queue_free()
	_text.text = ""
	var entries: Array[Dictionary] = journal.entries if journal != null else []
	if entries.is_empty():
		_text.text = "Nothing has happened yet."
	for i in range(entries.size() - 1, -1, -1):
		var entry := entries[i]
		var btn := Button.new()
		btn.text = "Round %d - %s" % [entry["round"], entry["title"]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.pressed.connect(_show_entry.bind(entry))
		_list.add_child(btn)
	if not entries.is_empty():
		_show_entry(entries[entries.size() - 1])
	visible = true


func _show_entry(entry: Dictionary) -> void:
	_text.text = "\n\n- - -\n\n".join(entry["pages"])
