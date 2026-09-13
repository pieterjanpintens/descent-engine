class_name PropActionsDialog
extends Window

## Popup editor for InteractableEntry.actions - what a player can report
## doing to a prop (push a lever, search a bookshelf), see PropAction.gd.
## Opened via CreatorPropertiesPanel.gd's "Actions…" button (OBJECT
## selections only) - one instance, created there in code and reused
## across selections via open_for(), same pattern as PropertiesDialog.gd
## (operation_history/layered_map assigned directly after .new(), not
## @export/NodePath - nothing here needs scene wiring).
##
## Simpler than ObjectivesDialog.gd's DAG editor - a PropAction has no
## children/branching, just an id/description and a flat effects list -
## so this is a flat scrollable list of PropAction "blocks" (one
## PanelContainer per action, grouping its own id/description/effects
## together) rather than a graph canvas. Each block's effect rows and the
## value-type editor duplicate ObjectivesDialog's own _build_effect_row()/
## _build_value_editor() rather than sharing code with it - those are
## typed to a MissionObjective holder there (holder.effects.erase()), and
## every dialog in this project already owns its row-builder helpers
## independently (PropertiesDialog has its own too) rather than factoring
## a shared base class, so this follows the same convention.
##
## Every edit goes through operation_history.record() then
## layered_map.notify_objects_changed(), same convention as every other
## Creator dialog.
##
## Unverified in-editor, same caveat as every other Creator dialog built
## this session without the ability to launch Godot and see it rendered.

var operation_history: OperationHistory
var layered_map: LayeredMap

enum _ValueType { STRING, BOOL, INT, FLOAT }

var _entry: InteractableEntry
var _rows_container: VBoxContainer
var _empty_label: Label


func _ready() -> void:
	title = "Actions"
	size = Vector2i(420, 480)
	close_requested.connect(hide)
	visible = false

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	add_child(root)

	_empty_label = Label.new()
	_empty_label.text = "No actions yet - this prop is purely decorative."
	root.add_child(_empty_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_container)

	var add_button := Button.new()
	add_button.text = "Add Action"
	add_button.pressed.connect(_on_add_action_pressed)
	root.add_child(add_button)


## Public - CreatorPropertiesPanel.gd calls this from its "Actions…" button.
func open_for(entry: InteractableEntry) -> void:
	_entry = entry
	_rebuild_rows()
	popup_centered()


func _rebuild_rows() -> void:
	# queue_free(), not immediate free() - this is called from a row's own
	# "Remove Action"/"Remove Effect" button pressed handler, i.e. while
	# that button (a descendant of what's being cleared here) is still on
	# the call stack. Immediate free() only became necessary in
	# ObjectivesDialog.gd for a DIFFERENT reason (GraphEdit's internal
	# children plus same-frame add_child() name collisions, see that
	# script's own comment) - neither applies to this plain, unnamed
	# VBoxContainer list, so this follows PropertiesDialog.gd's own
	# (identically-shaped) row list instead.
	for child in _rows_container.get_children():
		child.queue_free()

	if _entry == null:
		return

	_empty_label.visible = _entry.actions.is_empty()
	for action in _entry.actions:
		_rows_container.add_child(_build_action_block(action))
		_rows_container.add_child(HSeparator.new())


func _build_action_block(action: PropAction) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)

	var id_row := HBoxContainer.new()
	box.add_child(id_row)
	var id_label := Label.new()
	id_label.text = "Action id:"
	id_row.add_child(id_label)
	var id_edit := LineEdit.new()
	id_edit.text = action.action_id
	id_edit.placeholder_text = "e.g. push"
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var commit_id := func():
		_commit_field("Edit action id", func(): action.action_id = id_edit.text)
	id_edit.text_submitted.connect(func(_t): commit_id.call())
	id_edit.focus_exited.connect(commit_id)
	id_row.add_child(id_edit)
	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.tooltip_text = "Remove this action"
	remove_button.pressed.connect(func(): _on_remove_action_pressed(action))
	id_row.add_child(remove_button)

	var desc_label := Label.new()
	desc_label.text = "Description (shown to the player):"
	box.add_child(desc_label)
	var desc_edit := LineEdit.new()
	desc_edit.text = action.description
	desc_edit.placeholder_text = "e.g. You can push this lever"
	var commit_desc := func():
		_commit_field("Edit action description", func(): action.description = desc_edit.text)
	desc_edit.text_submitted.connect(func(_t): commit_desc.call())
	desc_edit.focus_exited.connect(commit_desc)
	box.add_child(desc_edit)

	box.add_child(HSeparator.new())
	var effects_label := Label.new()
	effects_label.text = "Effects (applied immediately when this action fires):"
	box.add_child(effects_label)
	for effect in action.effects:
		box.add_child(_build_effect_row(action, effect))
	var add_effect_button := Button.new()
	add_effect_button.text = "Add Effect"
	add_effect_button.pressed.connect(func():
		var effect := Effect.new()
		_commit_field("Add effect", func(): action.effects.append(effect))
		_rebuild_rows()
	)
	box.add_child(add_effect_button)

	return panel


func _on_add_action_pressed() -> void:
	if _entry == null:
		return
	var action := PropAction.new()
	var entry := _entry
	operation_history.record("Add action", func():
		entry.actions.append(action)
	)
	layered_map.notify_objects_changed()
	_rebuild_rows()


func _on_remove_action_pressed(action: PropAction) -> void:
	if _entry == null:
		return
	var entry := _entry
	operation_history.record("Remove action", func():
		entry.actions.erase(action)
	)
	layered_map.notify_objects_changed()
	_rebuild_rows()


func _commit_field(label: String, mutate: Callable) -> void:
	operation_history.record(label, mutate)
	layered_map.notify_objects_changed()


func _build_effect_row(holder: PropAction, effect: Effect) -> Control:
	var row := HBoxContainer.new()

	var var_edit := LineEdit.new()
	var_edit.text = effect.variable_name
	var_edit.placeholder_text = "variable name"
	var_edit.custom_minimum_size = Vector2(90, 0)
	var commit_var := func():
		_commit_field("Edit effect variable", func(): effect.variable_name = var_edit.text)
	var_edit.text_submitted.connect(func(_t): commit_var.call())
	var_edit.focus_exited.connect(commit_var)
	row.add_child(var_edit)

	row.add_child(_build_value_editor(effect.value, func(new_value): _commit_field("Edit effect value", func(): effect.value = new_value)))

	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.pressed.connect(func():
		_commit_field("Remove effect", func(): holder.effects.erase(effect))
		_rebuild_rows()
	)
	row.add_child(remove_button)

	return row


## A type picker (String/Bool/Int/Float, defaulted from typeof(current_value)
## when already set) plus the one matching value widget shown at a time -
## same reasoning as PropertiesDialog's/ObjectivesDialog's own per-type
## widgets: Effect.value is a loosely-typed Variant, checked against the
## target variable's declared type only at evaluation time (see
## MissionRuntime._coerce()), not enforced here.
func _build_value_editor(current_value: Variant, on_commit: Callable) -> Control:
	var box := HBoxContainer.new()

	var type_option := OptionButton.new()
	type_option.add_item("String", _ValueType.STRING)
	type_option.add_item("Bool", _ValueType.BOOL)
	type_option.add_item("Int", _ValueType.INT)
	type_option.add_item("Float", _ValueType.FLOAT)
	box.add_child(type_option)

	var string_edit := LineEdit.new()
	var bool_check := CheckBox.new()
	var int_spin := SpinBox.new()
	int_spin.min_value = -999999
	int_spin.max_value = 999999
	int_spin.step = 1
	var float_spin := SpinBox.new()
	float_spin.min_value = -999999
	float_spin.max_value = 999999
	float_spin.step = 0.01
	box.add_child(string_edit)
	box.add_child(bool_check)
	box.add_child(int_spin)
	box.add_child(float_spin)

	var initial_type: int
	match typeof(current_value):
		TYPE_BOOL:
			initial_type = _ValueType.BOOL
			bool_check.button_pressed = current_value
		TYPE_INT:
			initial_type = _ValueType.INT
			int_spin.value = current_value
		TYPE_FLOAT:
			initial_type = _ValueType.FLOAT
			float_spin.value = current_value
		_:
			initial_type = _ValueType.STRING
			string_edit.text = str(current_value) if current_value != null else ""
	type_option.select(type_option.get_item_index(initial_type))

	var update_visibility := func():
		var type: int = type_option.get_selected_id()
		string_edit.visible = type == _ValueType.STRING
		bool_check.visible = type == _ValueType.BOOL
		int_spin.visible = type == _ValueType.INT
		float_spin.visible = type == _ValueType.FLOAT
	update_visibility.call()
	type_option.item_selected.connect(func(_index): update_visibility.call())

	var commit_string := func(): on_commit.call(string_edit.text)
	string_edit.text_submitted.connect(func(_t): commit_string.call())
	string_edit.focus_exited.connect(commit_string)
	bool_check.toggled.connect(func(pressed: bool): on_commit.call(pressed))
	int_spin.value_changed.connect(func(new_value: float): on_commit.call(int(new_value)))
	float_spin.value_changed.connect(func(new_value: float): on_commit.call(new_value))

	return box
