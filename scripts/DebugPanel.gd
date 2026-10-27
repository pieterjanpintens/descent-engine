class_name DebugPanel
extends Control

## The Player's debug tools, only built during a debug session (see DebugSession): a short "toast" line for feedback of the
## hotkeys, and a panel (Gear menu > Debug) with the snapshot slots, the way back to the editor, and a few shortcuts to get
## to the moment you want to test - set a variable, reveal a group. MissionPlayer wires the callables.
##
## Keys (handled by MissionPlayer): F9 = snapshot into "quick", F10 = roll back to "quick", Ctrl+E = back to the editor.

const PANEL_WIDTH := 440.0
const TOAST_SECONDS := 2.6

## (slot: String) -> void
var take_snapshot: Callable
var restore_snapshot: Callable
## () -> void
var back_to_editor: Callable
## (group_id: String) -> void
var reveal_group: Callable
## () -> void - after something changed the game state (objective label etc.)
var state_changed: Callable
var mission: MissionData
var runtime: MissionRuntime
var snapshot_key: String = ""

var _toast: Label
var _toast_tween: Tween
var _panel: PanelContainer
var _slot_labels := {}  ## slot -> Label
var _variable_option: OptionButton
var _variable_edit: LineEdit
var _group_option: OptionButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 14.0
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -PANEL_WIDTH - 12.0
	_panel.offset_right = -12.0
	_panel.offset_top = 56.0
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	_panel.visible = false
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Debug"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var keys := Label.new()
	keys.text = "F9 snapshot (quick)   F10 roll back (quick)   %s+E back to the editor" % ("Cmd" if OS.get_name() == "macOS" else "Ctrl")
	keys.modulate = Color(1, 1, 1, 0.6)
	box.add_child(keys)

	box.add_child(_heading("Snapshots"))
	for slot in DebugSession.SLOTS:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slot_labels[slot] = label
		row.add_child(label)
		var save := Button.new()
		save.text = "Take"
		save.pressed.connect(func(): _call(take_snapshot, slot))
		row.add_child(save)
		var load_button := Button.new()
		load_button.text = "Roll back"
		load_button.pressed.connect(func(): _call(restore_snapshot, slot))
		row.add_child(load_button)
		box.add_child(row)

	box.add_child(_heading("Variables"))
	var variable_row := HBoxContainer.new()
	_variable_option = OptionButton.new()
	_variable_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_variable_option.item_selected.connect(func(_i: int): _show_current_value())
	variable_row.add_child(_variable_option)
	_variable_edit = LineEdit.new()
	_variable_edit.custom_minimum_size.x = 110.0
	_variable_edit.placeholder_text = "value"
	_variable_edit.text_submitted.connect(func(_t: String): _on_set_variable())
	variable_row.add_child(_variable_edit)
	var set_button := Button.new()
	set_button.text = "Set"
	set_button.pressed.connect(_on_set_variable)
	variable_row.add_child(set_button)
	box.add_child(variable_row)

	box.add_child(_heading("Groups"))
	var group_row := HBoxContainer.new()
	_group_option = OptionButton.new()
	_group_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group_row.add_child(_group_option)
	var reveal := Button.new()
	reveal.text = "Reveal"
	reveal.pressed.connect(_on_reveal)
	group_row.add_child(reveal)
	box.add_child(group_row)

	box.add_child(HSeparator.new())
	var fast := CheckBox.new()
	fast.text = "Fast start (skip setup dialogs, banners and narration)"
	fast.button_pressed = DebugSession.fast()
	fast.toggled.connect(DebugSession.set_fast)
	box.add_child(fast)
	var party_row := HBoxContainer.new()
	var forget := Button.new()
	forget.text = "Forget the remembered party"
	forget.tooltip_text = "The next debug start asks for the heroes and weapons again."
	forget.pressed.connect(func():
		DebugSession.forget_party()
		toast("The party will be asked again at the next start.")
	)
	party_row.add_child(forget)
	var editor_button := Button.new()
	editor_button.text = "Back to the editor"
	editor_button.pressed.connect(func(): _call(back_to_editor))
	party_row.add_child(editor_button)
	box.add_child(party_row)


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		refresh()


func refresh() -> void:
	for slot: String in _slot_labels:
		(_slot_labels[slot] as Label).text = DebugSession.slot_label(snapshot_key, slot)
	var previous := _variable_option.get_item_text(_variable_option.selected) if _variable_option.selected >= 0 else ""
	_variable_option.clear()
	if mission != null:
		for variable in mission.custom_variables:
			_variable_option.add_item(variable.name)
	for builtin: String in MissionRuntime.WRITABLE_BUILTINS:
		_variable_option.add_item(builtin)
	for i in _variable_option.item_count:
		if _variable_option.get_item_text(i) == previous:
			_variable_option.select(i)
	_show_current_value()
	_group_option.clear()
	if mission != null:
		for group in mission.groups:
			if not group.visible:
				_group_option.add_item(group.reference_name if group.reference_name != "" else group.id)
				_group_option.set_item_metadata(_group_option.item_count - 1, group.id)


## A line that fades after a moment - the answer to a hotkey.
func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_SECONDS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HeadingLabel"
	label.text = text
	label.add_theme_color_override("font_color", Color(0.56, 0.79, 0.9))
	return label


func _call(callable: Callable, argument: Variant = null) -> void:
	if not callable.is_valid():
		return
	if argument == null:
		callable.call()
	else:
		callable.call(argument)
	refresh()


func _show_current_value() -> void:
	if runtime == null or _variable_option.selected < 0:
		return
	_variable_edit.text = str(runtime.get_variable(_variable_option.get_item_text(_variable_option.selected)))


func _on_set_variable() -> void:
	if runtime == null or _variable_option.selected < 0:
		return
	var variable_name := _variable_option.get_item_text(_variable_option.selected)
	var text := _variable_edit.text.strip_edges()
	var value: Variant = text
	if MissionRuntime.WRITABLE_BUILTINS.has(variable_name):
		value = int(text)
		runtime.set_variable(variable_name, value)
	else:
		for variable in mission.custom_variables:
			if variable.name != variable_name:
				continue
			match variable.type:
				MissionVariable.Type.BOOL:
					value = text.to_lower() in ["true", "1", "yes", "on"]
				MissionVariable.Type.INT:
					value = int(text)
				MissionVariable.Type.FLOAT:
					value = float(text)
		runtime.preset_variable(variable_name, value)
	toast("%s = %s" % [variable_name, str(runtime.get_variable(variable_name))])
	_call(state_changed)


func _on_reveal() -> void:
	if _group_option.selected < 0:
		return
	var group_id: String = _group_option.get_item_metadata(_group_option.selected)
	_panel.visible = false
	_call(reveal_group, group_id)
