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
## children/branching, just an id/description/conditions/effects - so
## this is a flat scrollable list of PropAction "blocks" (one
## PanelContainer per action, grouping its own id/description/conditions/
## effects together) rather than a graph canvas. `conditions` (new
## 2026-09-14) gates whether this action is currently OFFERED to players
## at all - see PropAction.conditions' own doc and MissionRuntime.
## first_available_action(), the runtime consumer. Each block's condition/
## effect rows and the value-type editor duplicate ObjectivesDialog's own
## _build_condition_row()/_build_effect_row()/_build_value_editor() rather
## than sharing code with it - those are typed to a MissionObjective
## holder there, and every dialog in this project already owns its
## row-builder helpers independently (PropertiesDialog has its own too)
## rather than factoring a shared base class, so this follows the same
## convention.
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

## The nested "Edit Test…" window - single instance, built once in
## _ready(), rebuilt-and-repopened via _open_test_editor() each time it's
## opened (same "a dialog opens a smaller dialog" pattern ObjectivesDialog.
## _optional_editor already establishes).
var _test_editor: Window
var _test_editor_container: VBoxContainer


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

	_test_editor = Window.new()
	_test_editor.title = "Test"
	_test_editor.size = Vector2i(420, 480)
	_test_editor.close_requested.connect(_test_editor.hide)
	_test_editor.visible = false
	add_child(_test_editor)

	var test_scroll := ScrollContainer.new()
	test_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	test_scroll.offset_left = 8
	test_scroll.offset_top = 8
	test_scroll.offset_right = -8
	test_scroll.offset_bottom = -8
	_test_editor.add_child(test_scroll)

	_test_editor_container = VBoxContainer.new()
	_test_editor_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test_scroll.add_child(_test_editor_container)


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

	var single_shot_check := CheckBox.new()
	single_shot_check.text = "Single shot (becomes unavailable once used)"
	single_shot_check.button_pressed = action.single_shot
	single_shot_check.toggled.connect(func(pressed: bool):
		_commit_field("Edit action single-shot", func(): action.single_shot = pressed)
	)
	box.add_child(single_shot_check)

	box.add_child(HSeparator.new())
	var conditions_label := Label.new()
	conditions_label.text = "Conditions (implicit AND - when is this action offered to players):"
	box.add_child(conditions_label)
	for condition in action.conditions:
		box.add_child(_build_condition_row(action, condition))
	var add_condition_button := Button.new()
	add_condition_button.text = "Add Condition"
	add_condition_button.pressed.connect(func():
		var condition := Condition.new()
		_commit_field("Add condition", func(): action.conditions.append(condition))
		_rebuild_rows()
	)
	box.add_child(add_condition_button)

	box.add_child(HSeparator.new())
	var effects_label := Label.new()
	effects_label.text = "Effects (applied immediately when this action fires):"
	box.add_child(effects_label)
	for effect in action.effects:
		box.add_child(_build_effect_row(action.effects, effect, _rebuild_rows))
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


## Swaps `item` with its neighbor `delta` slots away (-1 = up/earlier,
## +1 = down/later) - a no-op if `item` is already at that end of the
## array. Added 2026-09-17 so reordering a condition/effect doesn't mean
## deleting everything just to re-add it in the right order ("its kinda
## shitty having to delete all because you want to add something in the
## beginning"). Takes a plain `Array` rather than a typed one - a typed
## `Array[Condition]`/`Array[Effect]` is still a real Array object
## underneath in GDScript, so passing it in untyped and mutating it in
## place still affects the original caller's array. Own copy, not shared
## with ObjectivesDialog.gd's identical helper - same "each dialog owns
## its own row-builder helpers" convention as everything else here.
func _move_in_array(array: Array, item, delta: int) -> bool:
	var index := array.find(item)
	if index == -1:
		return false
	var target := index + delta
	if target < 0 or target >= array.size():
		return false
	array[index] = array[target]
	array[target] = item
	return true


## Built-in variable names (MissionRuntime.BUILTIN_TYPES) plus every
## declared MissionData.custom_variables name - own copy of
## ObjectivesDialog's identical helper (same file-local-sharing reasoning
## as _build_condition_row()'s own doc comment below).
func _known_variable_names() -> Array[String]:
	var names: Array[String] = ["round_number", "player_count"]
	for variable in layered_map.mission.custom_variables:
		names.append(variable.name)
	return names


## A dropdown of _known_variable_names() (new 2026-09-14, replacing a
## free-text LineEdit - "can we provide them in a dropdown... instead of
## requiring a string") - shared by _build_condition_row()/
## _build_effect_row() below, both in this same file. Selects nothing
## (blank) if `current_name` isn't among them rather than silently
## picking the first entry and corrupting the data.
func _build_variable_name_option(current_name: String, on_commit: Callable) -> OptionButton:
	var option := OptionButton.new()
	var names := _known_variable_names()
	for name in names:
		option.add_item(name)
	option.select(names.find(current_name))
	option.item_selected.connect(func(index: int):
		if index >= 0 and index < names.size():
			on_commit.call(names[index])
	)
	return option


## Own copy of ObjectivesDialog's _build_condition_row() (typed to a
## MissionObjective holder there) - same "each dialog owns its own
## row-builder helpers" convention as _build_effect_row()/
## _build_value_editor() below. Gates whether this ACTION is currently
## offered to players (see PropAction.conditions' own doc) - distinct
## from InteractableEntry.props["interactible"], a manual whole-prop
## on/off switch that applies regardless of any action's conditions.
func _build_condition_row(holder: PropAction, condition: Condition) -> Control:
	var row := HBoxContainer.new()

	var var_option := _build_variable_name_option(condition.variable_name, func(new_name: String):
		_commit_field("Edit condition variable", func(): condition.variable_name = new_name)
	)
	row.add_child(var_option)

	var operator_option := OptionButton.new()
	operator_option.add_item("=", Condition.Operator.EQUALS)
	operator_option.add_item("!=", Condition.Operator.NOT_EQUALS)
	operator_option.add_item(">", Condition.Operator.GREATER)
	operator_option.add_item(">=", Condition.Operator.GREATER_EQUAL)
	operator_option.add_item("<", Condition.Operator.LESS)
	operator_option.add_item("<=", Condition.Operator.LESS_EQUAL)
	operator_option.select(operator_option.get_item_index(condition.operator))
	operator_option.item_selected.connect(func(_index):
		var value: int = operator_option.get_selected_id()
		_commit_field("Edit condition operator", func(): condition.operator = value)
	)
	row.add_child(operator_option)

	row.add_child(_build_value_editor(condition.value, func(new_value): _commit_field("Edit condition value", func(): condition.value = new_value)))

	var move_up_button := Button.new()
	move_up_button.text = "↑"
	move_up_button.tooltip_text = "Move up"
	move_up_button.disabled = holder.conditions.find(condition) == 0
	move_up_button.pressed.connect(func():
		_commit_field("Reorder condition", func(): _move_in_array(holder.conditions, condition, -1))
		_rebuild_rows()
	)
	row.add_child(move_up_button)

	var move_down_button := Button.new()
	move_down_button.text = "↓"
	move_down_button.tooltip_text = "Move down"
	move_down_button.disabled = holder.conditions.find(condition) == holder.conditions.size() - 1
	move_down_button.pressed.connect(func():
		_commit_field("Reorder condition", func(): _move_in_array(holder.conditions, condition, 1))
		_rebuild_rows()
	)
	row.add_child(move_down_button)

	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.pressed.connect(func():
		_commit_field("Remove condition", func(): holder.conditions.erase(condition))
		_rebuild_rows()
	)
	row.add_child(remove_button)

	return row


## `type_option` (Set Variable/Show Stage/Remove Object/Test) picks between
## pre-built widget groups shown one at a time - same "build all, toggle
## .visible" trick _build_value_editor() below already uses for its own
## String/Bool/Int/Float picker. Show Stage's group_option has no "(root)"
## entry - showing a stage for the mission root doesn't mean anything.
## `effects_list` (new 2026-09-14, replacing a typed `holder: PropAction` -
## the ONLY thing holder was ever used for was `holder.effects.erase(effect)`)
## is the actual Array[Effect] this row's effect lives in - a plain array
## reference works identically whether that's a PropAction's own `.effects`
## or a RUN_TEST effect's nested `.pass_effects`/`.fail_effects`, which is
## what lets this same row-builder recurse into a Test's own branches (see
## the RUN_TEST widget group below and _open_test_editor()). `on_changed`
## (new the same day) replaces a hardcoded _rebuild_rows() call so this
## works identically from the top-level action block and from inside the
## nested test editor - same shape as ObjectivesDialog's own
## _build_effect_row(), which already needed exactly this for its nested
## optional-objective editor.
func _build_effect_row(effects_list: Array[Effect], effect: Effect, on_changed: Callable) -> Control:
	var row := HBoxContainer.new()

	var type_option := OptionButton.new()
	type_option.add_item("Set Variable", Effect.Type.SET_VARIABLE)
	type_option.add_item("Show Stage", Effect.Type.SHOW_STAGE)
	type_option.add_item("Remove Object", Effect.Type.REMOVE_OBJECT)
	type_option.add_item("Test", Effect.Type.RUN_TEST)
	type_option.add_item("Show Message", Effect.Type.SHOW_MESSAGE)
	type_option.select(type_option.get_item_index(effect.type))
	row.add_child(type_option)

	var var_option := _build_variable_name_option(effect.variable_name, func(new_name: String):
		_commit_field("Edit effect variable", func(): effect.variable_name = new_name)
	)
	row.add_child(var_option)

	var value_editor := _build_value_editor(effect.value, func(new_value): _commit_field("Edit effect value", func(): effect.value = new_value))
	row.add_child(value_editor)

	var group_option := OptionButton.new()
	var group_ids: Array[String] = []
	for group in layered_map.mission.groups:
		group_option.add_item(group.reference_name if group.reference_name != "" else "(unnamed group)")
		group_ids.append(group.id)
	var initial_group_index := group_ids.find(effect.target_group_id)
	group_option.select(initial_group_index)
	group_option.item_selected.connect(func(index: int):
		if index >= 0 and index < group_ids.size():
			_commit_field("Edit effect target stage", func(): effect.target_group_id = group_ids[index])
	)
	row.add_child(group_option)

	## Every prop plus every floor/underlay tile - not groups, which have
	## no GridMap presence to remove. The origin-cell suffix disambiguates
	## entries sharing a mesh name (several "gate"s, or every plain "1a"
	## floor tile) - genuinely needed here unlike the group picker above,
	## since groups are already uniquely named.
	var object_option := OptionButton.new()
	var object_ids: Array[String] = []
	var removable_nodes: Array = []
	removable_nodes.append_array(layered_map.mission.interactables)
	removable_nodes.append_array(layered_map.mission.floor_placements)
	removable_nodes.append_array(layered_map.mission.underlay_placements)
	for node in removable_nodes:
		var label: String = node.reference_name if node.reference_name != "" else node.mesh_item_name
		object_option.add_item("%s (%s)" % [label, node.origin_cell])
		object_ids.append(node.id)
	var initial_object_index := object_ids.find(effect.target_object_id)
	object_option.select(initial_object_index)
	object_option.item_selected.connect(func(index: int):
		if index >= 0 and index < object_ids.size():
			_commit_field("Edit effect target object", func(): effect.target_object_id = object_ids[index])
	)
	row.add_child(object_option)

	## RUN_TEST's full editor (attribute + threshold + accumulate variable +
	## two nested effect lists) doesn't fit in one row - a compact button
	## opens a small nested Window instead, same "a dialog opens a smaller
	## dialog" pattern ObjectivesDialog._open_optional_editor() already
	## establishes.
	var test_button := Button.new()
	test_button.text = "Edit Test…"
	test_button.pressed.connect(func(): _open_test_editor(effect))
	row.add_child(test_button)

	## SHOW_MESSAGE - a plain narrative popup (OK button, no branching), see
	## Effect.gd's own doc. Just the message text - no separate editor
	## needed the way RUN_TEST's does.
	var message_edit := LineEdit.new()
	message_edit.placeholder_text = "Message shown to the table, e.g. \"Donal gave you the key.\""
	message_edit.text = effect.message
	message_edit.text_submitted.connect(func(new_text: String):
		_commit_field("Edit effect message", func(): effect.message = new_text)
	)
	message_edit.focus_exited.connect(func():
		_commit_field("Edit effect message", func(): effect.message = message_edit.text)
	)
	row.add_child(message_edit)

	var update_visibility := func():
		var type: int = type_option.get_selected_id()
		var_option.visible = type == Effect.Type.SET_VARIABLE
		value_editor.visible = type == Effect.Type.SET_VARIABLE
		group_option.visible = type == Effect.Type.SHOW_STAGE
		object_option.visible = type == Effect.Type.REMOVE_OBJECT
		test_button.visible = type == Effect.Type.RUN_TEST
		message_edit.visible = type == Effect.Type.SHOW_MESSAGE
	update_visibility.call()
	type_option.item_selected.connect(func(_index):
		var new_type: int = type_option.get_selected_id()
		_commit_field("Edit effect type", func(): effect.type = new_type)
		update_visibility.call()
	)

	var move_up_button := Button.new()
	move_up_button.text = "↑"
	move_up_button.tooltip_text = "Move up"
	move_up_button.disabled = effects_list.find(effect) == 0
	move_up_button.pressed.connect(func():
		_commit_field("Reorder effect", func(): _move_in_array(effects_list, effect, -1))
		on_changed.call()
	)
	row.add_child(move_up_button)

	var move_down_button := Button.new()
	move_down_button.text = "↓"
	move_down_button.tooltip_text = "Move down"
	move_down_button.disabled = effects_list.find(effect) == effects_list.size() - 1
	move_down_button.pressed.connect(func():
		_commit_field("Reorder effect", func(): _move_in_array(effects_list, effect, 1))
		on_changed.call()
	)
	row.add_child(move_down_button)

	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.pressed.connect(func():
		_commit_field("Remove effect", func(): effects_list.erase(effect))
		on_changed.call()
	)
	row.add_child(remove_button)

	return row


## The nested "Edit Test…" window (single instance, built once in
## _ready(), rebuilt-and-repopened on every open - same pattern as
## ObjectivesDialog._open_optional_editor()). Attribute + Required
## Successes + optional Accumulate Variable, then Pass/Fail Effects as two
## nested lists reusing _build_effect_row() recursively - a branch can
## contain any effect type, including another Test.
func _open_test_editor(effect: Effect) -> void:
	for child in _test_editor_container.get_children():
		child.queue_free()

	var attribute_row := HBoxContainer.new()
	_test_editor_container.add_child(attribute_row)
	attribute_row.add_child(_label("Attribute:"))
	var attribute_option := OptionButton.new()
	attribute_option.add_item("Intelligence", PlayerAttribute.Attribute.INTELLIGENCE)
	attribute_option.add_item("Will", PlayerAttribute.Attribute.WILL)
	attribute_option.add_item("Agility", PlayerAttribute.Attribute.AGILITY)
	attribute_option.add_item("Strength", PlayerAttribute.Attribute.STRENGTH)
	attribute_option.select(attribute_option.get_item_index(effect.test_attribute))
	attribute_option.item_selected.connect(func(_index):
		var new_attribute: int = attribute_option.get_selected_id()
		_commit_field("Edit test attribute", func(): effect.test_attribute = new_attribute)
	)
	attribute_row.add_child(attribute_option)

	var required_row := HBoxContainer.new()
	_test_editor_container.add_child(required_row)
	required_row.add_child(_label("Required successes (never shown to the player):"))
	var required_spin := SpinBox.new()
	required_spin.min_value = 0
	required_spin.max_value = 99
	required_spin.step = 1
	required_spin.value = effect.required_successes
	required_spin.value_changed.connect(func(new_value: float):
		_commit_field("Edit test required successes", func(): effect.required_successes = int(new_value))
	)
	required_row.add_child(required_spin)

	_test_editor_container.add_child(HSeparator.new())
	_test_editor_container.add_child(_label("Accumulate raw successes into (optional - for a test repeated toward a larger total, e.g. 20 successes to put out a fire):"))
	var accumulate_option := OptionButton.new()
	accumulate_option.add_item("(none)")
	var accumulate_names := _known_variable_names()
	for name in accumulate_names:
		accumulate_option.add_item(name)
	accumulate_option.select(accumulate_names.find(effect.accumulate_variable_name) + 1 if effect.accumulate_variable_name != "" else 0)
	accumulate_option.item_selected.connect(func(index: int):
		var new_name := accumulate_names[index - 1] if index > 0 else ""
		_commit_field("Edit test accumulate variable", func(): effect.accumulate_variable_name = new_name)
	)
	_test_editor_container.add_child(accumulate_option)

	_test_editor_container.add_child(HSeparator.new())
	_test_editor_container.add_child(_label("Pass Effects (roll met the required successes):"))
	for pass_effect in effect.pass_effects:
		_test_editor_container.add_child(_build_effect_row(effect.pass_effects, pass_effect, func(): _open_test_editor(effect)))
	var add_pass_button := Button.new()
	add_pass_button.text = "Add Pass Effect"
	add_pass_button.pressed.connect(func():
		var new_effect := Effect.new()
		_commit_field("Add test pass effect", func(): effect.pass_effects.append(new_effect))
		_open_test_editor(effect)
	)
	_test_editor_container.add_child(add_pass_button)

	_test_editor_container.add_child(HSeparator.new())
	_test_editor_container.add_child(_label("Fail Effects (roll fell short):"))
	for fail_effect in effect.fail_effects:
		_test_editor_container.add_child(_build_effect_row(effect.fail_effects, fail_effect, func(): _open_test_editor(effect)))
	var add_fail_button := Button.new()
	add_fail_button.text = "Add Fail Effect"
	add_fail_button.pressed.connect(func():
		var new_effect := Effect.new()
		_commit_field("Add test fail effect", func(): effect.fail_effects.append(new_effect))
		_open_test_editor(effect)
	)
	_test_editor_container.add_child(add_fail_button)

	_test_editor.popup_centered()


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


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
