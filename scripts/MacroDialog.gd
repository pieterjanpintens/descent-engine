class_name MacroDialog
extends Window

## The form for applying a macro (MissionMacro) to a node, or editing / removing one already applied. The fields are generated from the
## macro's params() - number, yes/no, text, choice, loot - so a new macro needs no UI code. Apply (or Regenerate, when editing) goes
## through MacroEngine inside ONE undo step; Remove macro deletes what the macro generated, also one undo step.
##
## Same code-built, one-instance-reused pattern as the other editor dialogs: the owner assigns `operation_history` and `layered_map` right
## after .new() (both may stay null in a test, then the change is just applied), adds it as a child and calls open_for(). A fixed size,
## not resizable, the form scrolls inside (the dialog rules of this project).

signal macro_changed(target: OutlineNode)

var operation_history: OperationHistory
var layered_map: LayeredMap

const BODY_SIZE := Vector2i(600, 540)
const WRAP_WIDTH := 540

var _mission: MissionData
var _target: OutlineNode
var _macro: MissionMacro
var _existing: AppliedMacro
var _values: Dictionary = {}
var _editor: EffectEditor

var _description_label: Label
var _form: VBoxContainer
var _status_label: Label
var _apply_button: Button
var _remove_button: Button


func _ready() -> void:
	title = "Macro"
	size = BODY_SIZE
	unresizable = true
	close_requested.connect(hide)
	visible = false

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_top = 10
	root.offset_right = -10
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_description_label = Label.new()
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_description_label.custom_minimum_size.x = WRAP_WIDTH
	root.add_child(_description_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_theme_constant_override("separation", 8)
	scroll.add_child(_form)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.custom_minimum_size.x = WRAP_WIDTH
	root.add_child(_status_label)

	var buttons := HBoxContainer.new()
	root.add_child(buttons)
	_remove_button = Button.new()
	_remove_button.text = "Remove macro"
	_remove_button.tooltip_text = "Deletes everything this macro generated (variables, actions, triggers)."
	_remove_button.pressed.connect(_on_remove_pressed)
	buttons.add_child(_remove_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(hide)
	buttons.add_child(cancel_button)
	_apply_button = Button.new()
	_apply_button.pressed.connect(_on_apply_pressed)
	buttons.add_child(_apply_button)

	# The loot input is edited with the normal Loot editor; its changes go straight into the working copy of the value
	# (nothing in the mission changes until Apply, so no undo step is wanted here).
	_editor = EffectEditor.new()
	_editor.setup(self, func(_label: String, mutate: Callable): mutate.call())


## Opens the form for `macro` on `target`: new when `existing` is null, else the inputs of that record (Regenerate / Remove).
func open_for(mission: MissionData, target: OutlineNode, macro: MissionMacro, existing: AppliedMacro = null) -> void:
	_mission = mission
	_target = target
	_macro = macro
	_existing = existing
	_editor.mission = mission
	_editor.hide_nested()
	_values = macro.default_values()
	if existing != null:
		var stored := macro.completed(existing.values)
		for key in stored:
			var value: Variant = stored[key]
			_values[key] = value.duplicate(true) if value is Resource else value  # a working copy: Cancel changes nothing
	title = macro.title() if existing == null else tr("%s (applied)") % macro.title()
	_description_label.text = macro.description()
	_apply_button.text = "Apply" if existing == null else "Regenerate"
	_remove_button.visible = existing != null
	_rebuild_form()
	_refresh_status()
	if not visible:
		popup_centered()


func _rebuild_form() -> void:
	for child in _form.get_children():
		_form.remove_child(child)
		child.free()
	for param in _macro.params():
		_form.add_child(_param_row(param))


func _param_row(param: MacroParam) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = param.label
	box.add_child(label)
	match param.kind:
		MacroParam.Kind.INT:
			var spin := SpinBox.new()
			spin.min_value = param.min_value
			spin.max_value = param.max_value
			spin.step = 1
			spin.value = int(_values.get(param.id, param.default_value))
			spin.value_changed.connect(func(new_value: float):
				_values[param.id] = int(new_value)
				_refresh_status()
			)
			box.add_child(spin)
		MacroParam.Kind.BOOL:
			var check := CheckBox.new()
			check.text = param.label
			label.visible = false
			check.button_pressed = bool(_values.get(param.id, param.default_value))
			check.toggled.connect(func(pressed: bool):
				_values[param.id] = pressed
				_refresh_status()
			)
			box.add_child(check)
		MacroParam.Kind.TEXT:
			var line := LineEdit.new()
			line.text = str(_values.get(param.id, param.default_value))
			line.text_changed.connect(func(new_text: String):
				_values[param.id] = new_text
				_refresh_status()
			)
			box.add_child(line)
		MacroParam.Kind.CHOICE:
			var option := OptionButton.new()
			var selected := 0
			for index in param.choices.size():
				option.add_item(str(param.choices[index][0]))
				if param.choices[index][1] == _values.get(param.id, param.default_value):
					selected = index
			option.select(selected)
			option.item_selected.connect(func(index: int):
				_values[param.id] = param.choices[index][1]
				_refresh_status()
			)
			box.add_child(option)
		MacroParam.Kind.LOOT:
			var loot: Effect = _values.get(param.id)
			var button := Button.new()
			var refresh := func():
				var summary := _editor.loot_summary(loot)
				button.text = "Loot…" if summary == "" else "Loot: " + summary
			refresh.call()
			button.pressed.connect(func(): _editor.open_loot_editor(loot, func():
				refresh.call()
				_refresh_status()
			))
			box.add_child(button)
	if param.hint != "":
		var hint := Label.new()
		hint.text = param.hint
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		hint.custom_minimum_size.x = WRAP_WIDTH
		hint.modulate = Color(1, 1, 1, 0.6)
		box.add_child(hint)
	return box


func _refresh_status() -> void:
	var issue := _macro.problem(_values)
	_apply_button.disabled = issue != ""
	var text := issue
	if issue == "" and _existing != null and MacroEngine.is_modified(_mission, _existing):
		text = tr("What this macro generated was edited by hand (or deleted). Regenerate replaces it with a fresh version.")
	_status_label.text = text
	_status_label.modulate = Color(1.0, 0.55, 0.45) if issue != "" else Color(1.0, 0.85, 0.5)


func _on_apply_pressed() -> void:
	var mission := _mission
	var target := _target
	var macro := _macro
	var existing := _existing
	var values := _values
	_run("Apply macro" if existing == null else "Edit macro", func():
		if existing == null:
			MacroEngine.apply(mission, target, macro, values)
		else:
			MacroEngine.reapply(mission, target, existing, macro, values)
	)


func _on_remove_pressed() -> void:
	var mission := _mission
	var target := _target
	var existing := _existing
	if existing == null:
		return
	_run("Remove macro", func(): MacroEngine.remove(mission, target, existing))


## Runs `mutate` as one undo step (when there is a history), tells the editor the objects changed, and closes.
func _run(label: String, mutate: Callable) -> void:
	_editor.hide_nested()
	if operation_history != null:
		operation_history.record(label, mutate)
	else:
		mutate.call()
	if layered_map != null:
		layered_map.notify_objects_changed()
	hide()
	macro_changed.emit(_target)
