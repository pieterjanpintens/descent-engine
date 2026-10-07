class_name EffectEditor
extends RefCounted

## The shared editor widgets for the story layer's Conditions and Effects (the rows,
## the value-type picker, the MATH operand editor, and the nested editor windows for a
## Test, an effect's own conditions, a message's variables and a spawn's monsters).
## ObjectivesDialog (objectives), PropActionsDialog (prop actions) and TriggersDialog
## (triggers) each own one instance, so every place that edits conditions/effects
## looks and behaves the same - there used to be a copy per dialog.
##
## Usage: `setup(host, commit)` once (host = the dialog Window the nested windows are
## added to; commit = the dialog's `_commit_field(label, mutate)`, which runs the change
## through the undo history), set `mission` whenever the dialog opens for a mission,
## then add `build_condition_row()` / `build_effect_row()` rows to the dialog's lists.
## `on_changed` of a row is what the dialog calls to rebuild its list after a
## remove/reorder.

enum _ValueType { STRING, BOOL, INT, FLOAT }

var mission: MissionData
## When not empty, the variables the dropdowns offer INSTEAD of the mission's (the campaign editor uses
## this editor for conditions/effects over the campaign's own variables - Campaign.all_variables()).
var campaign_variables: Array[MissionVariable] = []
## When not empty, the only effect types the type dropdown offers (the campaign editor: set variable / math).
var allowed_effect_types: Array[int] = []
var host: Node
var _commit: Callable

var _test_editor: Window
var _test_editor_container: VBoxContainer
var _effect_conditions_editor: Window
var _effect_conditions_editor_container: VBoxContainer
var _message_variables_editor: Window
var _message_variables_editor_container: VBoxContainer


func setup(p_host: Node, p_commit: Callable) -> void:
	host = p_host
	_commit = p_commit
	_build_test_editor()
	_build_effect_conditions_editor()
	_build_message_variables_editor()


func _commit_field(label: String, mutate: Callable) -> void:
	_commit.call(label, mutate)


## Swaps `item` with its neighbor `delta` slots away (-1 = up/earlier,
## +1 = down/later) - a no-op if `item` is already at that end of the
## array. Added 2026-09-17 so reordering a condition/effect doesn't mean
## deleting everything just to re-add it in the right order ("its kinda
## shitty having to delete all because you want to add something in the
## beginning"). Takes a plain `Array` rather than a typed one - a typed
## `Array[Condition]`/`Array[Effect]` is still a real Array object
## underneath in GDScript, so passing it in untyped and mutating it in
## place still affects the original caller's array.
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


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


## Built-in variable names (MissionRuntime.BUILTIN_TYPES) plus every
## declared MissionData.custom_variables name - the full set a Condition/
## Effect's variable_name can validly reference right now.
func _known_variable_names() -> Array[String]:
	if not campaign_variables.is_empty():
		var campaign_names: Array[String] = []
		for variable in campaign_variables:
			campaign_names.append(variable.name)
		return campaign_names
	var names: Array[String] = ["round_number", "player_count", "affliction_damage"]
	for variable in mission.custom_variables:
		names.append(variable.name)
	return names


## A dropdown of _known_variable_names() (new 2026-09-14, replacing a
## free-text LineEdit - "can we provide them in a dropdown... instead of
## requiring a string") - shared by build_condition_row()/
## build_effect_row() below.
## Selects nothing (blank) if `current_name` isn't among them - e.g.
## authored before the variable was declared, or a since-renamed/deleted
## one - rather than silently picking the first entry and corrupting the
## data; the underlying value stays whatever it was until the user
## actively picks something from the dropdown.
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


## Same as _known_variable_names() but filtered to variables actually
## declared INT (built-ins round_number/player_count are both INT, plus
## any custom_variables entry with type == MissionVariable.Type.INT) -
## Effect.Type.MATH's own operand pickers use this instead of the
## unfiltered list, since a math result and both its operands are always
## plain GDScript ints, not the general Variant every other Condition/
## Effect value has to support - requested directly ("allow the operands
## be value (int) or a other variable... filtered to the ones of type
## int").
func _known_int_variable_names() -> Array[String]:
	if not campaign_variables.is_empty():
		var campaign_names: Array[String] = []
		for variable in campaign_variables:
			if variable.type == MissionVariable.Type.INT:
				campaign_names.append(variable.name)
		return campaign_names
	var names: Array[String] = ["round_number", "player_count", "affliction_damage"]
	for variable in mission.custom_variables:
		if variable.type == MissionVariable.Type.INT:
			names.append(variable.name)
	return names


## Builds one MATH operand's mini-editor: a "Var" CheckBox toggling
## literal-vs-variable, plus whichever ONE widget matches (a SpinBox for a
## literal int, or an OptionButton of _known_int_variable_names() for a
## variable reference) - same "build both, toggle .visible" trick
## _build_value_editor() already uses for its own type picker. `prefix` is
## "math_operand_a_" or "math_operand_b_" - reads/writes the three
## matching Effect fields (`<prefix>is_variable`/`<prefix>literal`/
## `<prefix>variable`) via Object.get()/set() (dynamic property access by
## name) rather than two near-identical copies of this function, since
## that's the only thing that differs between operand A and B.
func _build_math_operand_editor(effect: Effect, prefix: String) -> Control:
	var box := HBoxContainer.new()

	var is_variable_check := CheckBox.new()
	is_variable_check.text = "Var"
	is_variable_check.button_pressed = effect.get(prefix + "is_variable")
	box.add_child(is_variable_check)

	var literal_spin := SpinBox.new()
	literal_spin.min_value = -999999
	literal_spin.max_value = 999999
	literal_spin.step = 1
	literal_spin.value = effect.get(prefix + "literal")
	box.add_child(literal_spin)

	var int_names := _known_int_variable_names()
	var variable_option := OptionButton.new()
	for name in int_names:
		variable_option.add_item(name)
	variable_option.select(int_names.find(effect.get(prefix + "variable")))
	box.add_child(variable_option)

	var update_visibility := func():
		var is_var: bool = is_variable_check.button_pressed
		literal_spin.visible = not is_var
		variable_option.visible = is_var
	update_visibility.call()

	is_variable_check.toggled.connect(func(pressed: bool):
		_commit_field("Edit math operand mode", func(): effect.set(prefix + "is_variable", pressed))
		update_visibility.call()
	)
	literal_spin.value_changed.connect(func(new_value: float):
		_commit_field("Edit math operand value", func(): effect.set(prefix + "literal", int(new_value)))
	)
	variable_option.item_selected.connect(func(index: int):
		if index >= 0 and index < int_names.size():
			_commit_field("Edit math operand variable", func(): effect.set(prefix + "variable", int_names[index]))
	)

	return box


## `conditions_list` (changed 2026-09-18 from a typed `holder: MissionObjective` -
## the ONLY thing holder was ever used for was `holder.conditions.find()`/
## `.erase()` - same refactor `build_effect_row()`'s own `effects_list`
## parameter already went through, for the same reason: a plain array
## reference works identically whether it's an objective's own
## `.conditions`, an optional objective's `.conditions`, or - new the same
## day - an `Effect`'s own `.conditions` (see _open_effect_conditions_editor()
## below), which isn't a `MissionObjective` at all). `on_changed` lets each
## caller decide what to rebuild after a remove/reorder (the outer panel,
## the nested optional-objective editor, or the nested effect-conditions
## editor).
func build_condition_row(conditions_list: Array[Condition], condition: Condition, on_changed: Callable) -> Control:
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
	move_up_button.disabled = conditions_list.find(condition) == 0
	move_up_button.pressed.connect(func():
		_commit_field("Reorder condition", func(): _move_in_array(conditions_list, condition, -1))
		on_changed.call()
	)
	row.add_child(move_up_button)

	var move_down_button := Button.new()
	move_down_button.text = "↓"
	move_down_button.tooltip_text = "Move down"
	move_down_button.disabled = conditions_list.find(condition) == conditions_list.size() - 1
	move_down_button.pressed.connect(func():
		_commit_field("Reorder condition", func(): _move_in_array(conditions_list, condition, 1))
		on_changed.call()
	)
	row.add_child(move_down_button)

	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.pressed.connect(func():
		_commit_field("Remove condition", func(): conditions_list.erase(condition))
		on_changed.call()
	)
	row.add_child(remove_button)

	return row


## `type_option` (Set Variable/Show Stage/Remove Object/Test) picks between
## pre-built widget groups shown one at a time - same "build all, toggle
## .visible" trick _build_value_editor() below already uses for its own
## String/Bool/Int/Float picker. Show Stage's group_option has no "(root)"
## entry - showing a stage for the mission root doesn't mean anything.
## `effects_list` (new 2026-09-14, replacing a typed `holder: MissionObjective` -
## the ONLY thing holder was ever used for was `holder.effects.erase(effect)`)
## is the actual Array[Effect] this row's effect lives in - a plain array
## reference works identically whether that's an objective's own `.effects`
## or a RUN_TEST effect's nested `.pass_effects`/`.fail_effects`, which is
## what lets this same row-builder recurse into a Test's own branches (see
## the RUN_TEST widget group below and _open_test_editor()).
func build_effect_row(effects_list: Array[Effect], effect: Effect, on_changed: Callable) -> Control:
	var row := HBoxContainer.new()

	var type_option := OptionButton.new()
	for entry in [["Set Variable", Effect.Type.SET_VARIABLE], ["Show Stage", Effect.Type.SHOW_STAGE], ["Remove Object", Effect.Type.REMOVE_OBJECT],
			["Test", Effect.Type.RUN_TEST], ["Show Message", Effect.Type.SHOW_MESSAGE], ["Move Object", Effect.Type.MOVE_OBJECT],
			["Math", Effect.Type.MATH], ["Spawn Monsters", Effect.Type.SPAWN_MONSTERS]]:
		if allowed_effect_types.is_empty() or allowed_effect_types.has(entry[1]):
			type_option.add_item(entry[0], entry[1])
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
	for group in mission.groups:
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
	removable_nodes.append_array(mission.interactables)
	removable_nodes.append_array(mission.floor_placements)
	removable_nodes.append_array(mission.underlay_placements)
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
	## dialog" pattern _open_optional_editor() already establishes.
	var test_button := Button.new()
	test_button.text = "Edit Test…"
	test_button.pressed.connect(func(): _open_test_editor(effect))
	row.add_child(test_button)

	## SHOW_MESSAGE - a plain narrative popup (OK button, no branching), see
	## Effect.gd's own doc. The message text stays inline (the common case
	## - most messages reference nothing) - only the ordered
	## message_variables list (new 2026-09-19, $1/$2/... placeholders) gets
	## its own nested editor, same "doesn't fit one row, open a small
	## Window" reasoning as "Edit Test…"/"Conditions…" above.
	var message_edit := LineEdit.new()
	message_edit.placeholder_text = "Message shown to the table, e.g. \"$1 gave you the key.\""
	message_edit.text = effect.message
	message_edit.text_submitted.connect(func(new_text: String):
		_commit_field("Edit effect message", func(): effect.message = new_text)
	)
	message_edit.focus_exited.connect(func():
		_commit_field("Edit effect message", func(): effect.message = message_edit.text)
	)
	row.add_child(message_edit)

	var message_variables_button := Button.new()
	message_variables_button.text = "Variables…"
	message_variables_button.tooltip_text = "The variables $1, $2, ... refer to in the message text"
	message_variables_button.pressed.connect(func(): _open_message_variables_editor(effect))
	row.add_child(message_variables_button)

	## MOVE_OBJECT - a destination cell, authored in TILE-SQUARE ("game
	## unit") coordinates, same unit CreatorStatusBar shows while hovering
	## in the Creator (see Effect.target_cell's own doc for the full
	## reasoning/conversion). Which OBJECT moves reuses the existing
	## object_option picker above (same field, target_object_id, as
	## REMOVE_OBJECT) - only the destination needs its own widgets here.
	var move_cell_box := HBoxContainer.new()
	var move_x_spin := SpinBox.new()
	var move_y_spin := SpinBox.new()
	var move_z_spin := SpinBox.new()
	for spin in [move_x_spin, move_y_spin, move_z_spin]:
		spin.min_value = -999
		spin.max_value = 999
		spin.step = 1
	move_x_spin.value = effect.target_cell.x
	move_y_spin.value = effect.target_cell.y
	move_z_spin.value = effect.target_cell.z
	var move_x_label := Label.new()
	move_x_label.text = "X"
	var move_y_label := Label.new()
	move_y_label.text = "Y"
	var move_z_label := Label.new()
	move_z_label.text = "Z"
	move_cell_box.add_child(move_x_label)
	move_cell_box.add_child(move_x_spin)
	move_cell_box.add_child(move_y_label)
	move_cell_box.add_child(move_y_spin)
	move_cell_box.add_child(move_z_label)
	move_cell_box.add_child(move_z_spin)
	var commit_move_cell := func():
		_commit_field("Edit effect move target", func():
			effect.target_cell = Vector3i(int(move_x_spin.value), int(move_y_spin.value), int(move_z_spin.value))
		)
	move_x_spin.value_changed.connect(func(_v): commit_move_cell.call())
	move_y_spin.value_changed.connect(func(_v): commit_move_cell.call())
	move_z_spin.value_changed.connect(func(_v): commit_move_cell.call())
	row.add_child(move_cell_box)

	## MATH - operand_a OP operand_b, written to variable_name (the SAME
	## var_option picker above, reused - "which variable this writes" is
	## identical to SET_VARIABLE's own target, see Effect.variable_name's
	## own doc). Each operand is its own mini-editor
	## (_build_math_operand_editor()) since either can independently be a
	## literal or a variable reference.
	var math_box := HBoxContainer.new()
	math_box.add_child(_build_math_operand_editor(effect, "math_operand_a_"))
	var math_operator_option := OptionButton.new()
	math_operator_option.add_item("+", Effect.MathOperator.ADD)
	math_operator_option.add_item("−", Effect.MathOperator.SUBTRACT)
	math_operator_option.add_item("×", Effect.MathOperator.MULTIPLY)
	math_operator_option.add_item("÷", Effect.MathOperator.DIVIDE)
	math_operator_option.add_item("mod", Effect.MathOperator.MODULO)
	math_operator_option.select(math_operator_option.get_item_index(effect.math_operator))
	math_operator_option.item_selected.connect(func(_index):
		var new_op: int = math_operator_option.get_selected_id()
		_commit_field("Edit math operator", func(): effect.math_operator = new_op)
	)
	math_box.add_child(math_operator_option)
	math_box.add_child(_build_math_operand_editor(effect, "math_operand_b_"))
	row.add_child(math_box)

	## SPAWN_MONSTERS - which MonsterSpawn (reusing target_object_id, same
	## "which placed thing" field REMOVE_OBJECT/MOVE_OBJECT use - a
	## MonsterSpawn resolves through MissionData.find_node_by_id() too) plus
	## the ordered monster list, edited in its own small nested Window.
	var spawn_option := OptionButton.new()
	var spawn_ids: Array[String] = []
	for spawn_index in mission.monster_spawns.size():
		var candidate: MonsterSpawn = mission.monster_spawns[spawn_index]
		var spawn_label := candidate.reference_name if candidate.reference_name != "" else "Monster Spawn %d" % (spawn_index + 1)
		spawn_option.add_item("%s (%d tiles)" % [spawn_label, candidate.cells.size()])
		spawn_ids.append(candidate.id)
	spawn_option.select(spawn_ids.find(effect.target_object_id))
	spawn_option.item_selected.connect(func(index: int):
		if index >= 0 and index < spawn_ids.size():
			_commit_field("Edit effect monster spawn", func(): effect.target_object_id = spawn_ids[index])
	)
	row.add_child(spawn_option)

	var spawn_monsters_button := Button.new()
	spawn_monsters_button.text = "Monsters…"
	spawn_monsters_button.tooltip_text = "Which monsters spawn, in tile order (first = tile 1)"
	spawn_monsters_button.pressed.connect(func(): _open_spawn_monsters_editor(effect))
	row.add_child(spawn_monsters_button)

	var update_visibility := func():
		var type: int = type_option.get_selected_id()
		spawn_option.visible = type == Effect.Type.SPAWN_MONSTERS
		spawn_monsters_button.visible = type == Effect.Type.SPAWN_MONSTERS
		var_option.visible = type == Effect.Type.SET_VARIABLE or type == Effect.Type.MATH
		value_editor.visible = type == Effect.Type.SET_VARIABLE
		group_option.visible = type == Effect.Type.SHOW_STAGE
		object_option.visible = type == Effect.Type.REMOVE_OBJECT or type == Effect.Type.MOVE_OBJECT
		test_button.visible = type == Effect.Type.RUN_TEST
		message_edit.visible = type == Effect.Type.SHOW_MESSAGE
		message_variables_button.visible = type == Effect.Type.SHOW_MESSAGE
		move_cell_box.visible = type == Effect.Type.MOVE_OBJECT
		math_box.visible = type == Effect.Type.MATH
	update_visibility.call()
	type_option.item_selected.connect(func(_index):
		var new_type: int = type_option.get_selected_id()
		_commit_field("Edit effect type", func(): effect.type = new_type)
		update_visibility.call()
	)

	## Effect.conditions (new 2026-09-18) applies to EVERY type, not just
	## one widget group - so this button is always visible, unlike
	## test_button/message_edit/etc. above which toggle with the type
	## picker. Same "doesn't fit one row, open a small nested Window"
	## reasoning as "Edit Test…" - see _open_effect_conditions_editor().
	var conditions_button := Button.new()
	conditions_button.text = "Conditions…"
	conditions_button.tooltip_text = "Only execute this effect if these hold (empty = always)"
	conditions_button.pressed.connect(func(): _open_effect_conditions_editor(effect))
	row.add_child(conditions_button)

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


## A type picker (String/Bool/Int/Float, defaulted from typeof(current_value)
## when already set) plus the one matching value widget shown at a time -
## same reasoning as PropertiesDialog's own per-type row/add-dialog
## widgets: Condition/Effect.value is a loosely-typed Variant, checked
## against the target variable's declared type only at evaluation time
## (see MissionRuntime._coerce()), not enforced here.
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


## ---- Nested "edit one Test effect" dialog ----
## Same "a dialog opens a smaller dialog" pattern as _optional_editor
## above - Effect.Type.RUN_TEST's attribute/threshold/accumulate-variable/
## two-nested-effect-list editor doesn't fit in one row, see
## build_effect_row()'s own "Edit Test…" button.

func _build_test_editor() -> void:
	_test_editor = Window.new()
	_test_editor.title = "Test"
	_test_editor.size = Vector2i(360, 480)
	_test_editor.close_requested.connect(_test_editor.hide)
	_test_editor.visible = false
	host.add_child(_test_editor)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8
	scroll.offset_top = 8
	scroll.offset_right = -8
	scroll.offset_bottom = -8
	_test_editor.add_child(scroll)

	_test_editor_container = VBoxContainer.new()
	_test_editor_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_test_editor_container)


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
		_test_editor_container.add_child(build_effect_row(effect.pass_effects, pass_effect, func(): _open_test_editor(effect)))
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
		_test_editor_container.add_child(build_effect_row(effect.fail_effects, fail_effect, func(): _open_test_editor(effect)))
	var add_fail_button := Button.new()
	add_fail_button.text = "Add Fail Effect"
	add_fail_button.pressed.connect(func():
		var new_effect := Effect.new()
		_commit_field("Add test fail effect", func(): effect.fail_effects.append(new_effect))
		_open_test_editor(effect)
	)
	_test_editor_container.add_child(add_fail_button)

	_test_editor.popup_centered()


## ---- Nested "edit one Effect's own conditions" dialog ----
## Same "a dialog opens a smaller dialog" pattern as _optional_editor/
## _test_editor above - Effect.conditions (new 2026-09-18, requested
## directly: "can we make effects also conditional... only execute the
## effect if its condition holds") is a universal Effect field, not tied
## to one Type, so a compact "Conditions…" button on EVERY effect row (see
## build_effect_row()) opens this rather than growing every widget group
## with its own copy of the conditions list.

func _build_effect_conditions_editor() -> void:
	_effect_conditions_editor = Window.new()
	_effect_conditions_editor.title = "Effect Conditions"
	_effect_conditions_editor.size = Vector2i(360, 320)
	_effect_conditions_editor.close_requested.connect(_effect_conditions_editor.hide)
	_effect_conditions_editor.visible = false
	host.add_child(_effect_conditions_editor)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8
	scroll.offset_top = 8
	scroll.offset_right = -8
	scroll.offset_bottom = -8
	_effect_conditions_editor.add_child(scroll)

	_effect_conditions_editor_container = VBoxContainer.new()
	_effect_conditions_editor_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_effect_conditions_editor_container)


## `effect` is whichever Effect the "Conditions…" button was clicked on -
## any type, including one nested inside a RUN_TEST's own pass_effects/
## fail_effects, since conditions apply uniformly regardless of type (see
## MissionRuntime.apply_effect()'s own doc).
func _open_effect_conditions_editor(effect: Effect) -> void:
	for child in _effect_conditions_editor_container.get_children():
		child.queue_free()

	_effect_conditions_editor_container.add_child(_label("Implicit AND - empty means this effect always fires:"))
	for condition in effect.conditions:
		_effect_conditions_editor_container.add_child(build_condition_row(effect.conditions, condition, func(): _open_effect_conditions_editor(effect)))
	var add_condition_button := Button.new()
	add_condition_button.text = "Add Condition"
	add_condition_button.pressed.connect(func():
		var condition := Condition.new()
		_commit_field("Add effect condition", func(): effect.conditions.append(condition))
		_open_effect_conditions_editor(effect)
	)
	_effect_conditions_editor_container.add_child(add_condition_button)

	_effect_conditions_editor.popup_centered()


## ---- Nested "edit one SHOW_MESSAGE effect's $1/$2/... list" dialog ----
## Same "a dialog opens a smaller dialog" pattern as the others above -
## message_variables (new 2026-09-19) is an ORDERED Array[String], and
## order IS the data (entry 0 is $1, entry 1 is $2, ...), so this needs
## reorder buttons the same way condition/effect lists do - but
## _move_in_array() (used by every OTHER reorderable list in this file)
## finds its target by VALUE (`array.find(item)`), which is wrong here:
## message_variables can legitimately contain the SAME variable name more
## than once (e.g. "$1 and $1 both need to agree" isn't a realistic
## example, but there's no reason to forbid it), and .find() would always
## resolve to the FIRST matching entry regardless of which row's button
## was actually clicked. Swaps by INDEX directly instead - each row
## captures its own `index` from the loop it's built in.

func _build_message_variables_editor() -> void:
	_message_variables_editor = Window.new()
	_message_variables_editor.title = "Message Variables"
	_message_variables_editor.size = Vector2i(360, 320)
	_message_variables_editor.close_requested.connect(_message_variables_editor.hide)
	_message_variables_editor.visible = false
	host.add_child(_message_variables_editor)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8
	scroll.offset_top = 8
	scroll.offset_right = -8
	scroll.offset_bottom = -8
	_message_variables_editor.add_child(scroll)

	_message_variables_editor_container = VBoxContainer.new()
	_message_variables_editor_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_message_variables_editor_container)


## `effect` is whichever SHOW_MESSAGE Effect the "Variables…" button was
## clicked on. A $N with no corresponding entry here substitutes as
## nothing at runtime (not the literal "$N" text) - see
## MissionRuntime._format_message()'s own doc for the full reasoning.
func _open_message_variables_editor(effect: Effect) -> void:
	for child in _message_variables_editor_container.get_children():
		child.queue_free()

	_message_variables_editor_container.add_child(_label("$1, $2, ... in the message text, in order - any declared variable, any type:"))
	for i in effect.message_variables.size():
		var index := i  # captured by value for this row's own closures below
		var row := HBoxContainer.new()
		row.add_child(_label("$%d:" % (index + 1)))

		var var_option := _build_variable_name_option(effect.message_variables[index], func(new_name: String):
			_commit_field("Edit message variable", func(): effect.message_variables[index] = new_name)
		)
		row.add_child(var_option)

		var move_up_button := Button.new()
		move_up_button.text = "↑"
		move_up_button.tooltip_text = "Move up"
		move_up_button.disabled = index == 0
		move_up_button.pressed.connect(func():
			_commit_field("Reorder message variable", func():
				var tmp: String = effect.message_variables[index]
				effect.message_variables[index] = effect.message_variables[index - 1]
				effect.message_variables[index - 1] = tmp
			)
			_open_message_variables_editor(effect)
		)
		row.add_child(move_up_button)

		var move_down_button := Button.new()
		move_down_button.text = "↓"
		move_down_button.tooltip_text = "Move down"
		move_down_button.disabled = index == effect.message_variables.size() - 1
		move_down_button.pressed.connect(func():
			_commit_field("Reorder message variable", func():
				var tmp: String = effect.message_variables[index]
				effect.message_variables[index] = effect.message_variables[index + 1]
				effect.message_variables[index + 1] = tmp
			)
			_open_message_variables_editor(effect)
		)
		row.add_child(move_down_button)

		var remove_button := Button.new()
		remove_button.text = "×"
		remove_button.pressed.connect(func():
			_commit_field("Remove message variable", func(): effect.message_variables.remove_at(index))
			_open_message_variables_editor(effect)
		)
		row.add_child(remove_button)

		_message_variables_editor_container.add_child(row)

	var add_button := Button.new()
	add_button.text = "Add Variable"
	add_button.pressed.connect(func():
		_commit_field("Add message variable", func(): effect.message_variables.append(""))
		_open_message_variables_editor(effect)
	)
	_message_variables_editor_container.add_child(add_button)

	_message_variables_editor.popup_centered()


## Shared-shape helper for the "Properties…" button on each monster row:
## lazily builds the single MonsterPropertiesDialog and opens it for
## `template`. `refresh` re-renders the row's summary label after an edit.
var _monster_properties_dialog: MonsterPropertiesDialog


func _open_monster_properties(template: MonsterTemplate, refresh: Callable) -> void:
	if _monster_properties_dialog == null:
		_monster_properties_dialog = MonsterPropertiesDialog.new()
		host.add_child(_monster_properties_dialog)
	_monster_properties_dialog.commit_field = _commit_field
	_monster_properties_dialog.on_changed = refresh
	_monster_properties_dialog.open_for(template)


## ---- Nested "edit one SPAWN_MONSTERS effect's monster list" dialog ----
## Built lazily on first use (single instance, reused). The list is ORDERED
## (entry 0 spawns on tile 1) and may repeat a monster, so like
## message_variables it reorders by INDEX, never by value.
var _spawn_monsters_editor: Window
var _spawn_monsters_editor_container: VBoxContainer


func _open_spawn_monsters_editor(effect: Effect) -> void:
	if _spawn_monsters_editor == null:
		_spawn_monsters_editor = Window.new()
		_spawn_monsters_editor.title = "Spawn Monsters"
		_spawn_monsters_editor.size = Vector2i(520, 360)
		_spawn_monsters_editor.close_requested.connect(_spawn_monsters_editor.hide)
		_spawn_monsters_editor.visible = false
		host.add_child(_spawn_monsters_editor)
		var scroll := ScrollContainer.new()
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll.offset_left = 8
		scroll.offset_top = 8
		scroll.offset_right = -8
		scroll.offset_bottom = -8
		_spawn_monsters_editor.add_child(scroll)
		_spawn_monsters_editor_container = VBoxContainer.new()
		_spawn_monsters_editor_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(_spawn_monsters_editor_container)

	for child in _spawn_monsters_editor_container.get_children():
		child.queue_free()

	_spawn_monsters_editor_container.add_child(_label("Monsters in spawn-tile order (1st on tile 1, ...). Name, hitpoints, level: Properties…"))
	for i in effect.spawn_monsters.size():
		var index := i  # captured by value for this row's own closures below
		var template: MonsterTemplate = effect.spawn_monsters[index]
		var row := HBoxContainer.new()
		row.add_child(_label("%d:" % (index + 1)))

		var monster_option := OptionButton.new()
		for monster_index in MonsterDisplay.REAL_MONSTERS.size():
			monster_option.add_item(MonsterDisplay.REAL_MONSTERS[monster_index]["name"], monster_index)
			if MonsterDisplay.REAL_MONSTERS[monster_index]["folder"] == template.folder:
				monster_option.select(monster_index)
		monster_option.item_selected.connect(func(_selected: int):
			var folder: String = MonsterDisplay.REAL_MONSTERS[monster_option.get_selected_id()]["folder"]
			_commit_field("Edit spawned monster", func(): template.folder = folder)
		)
		row.add_child(monster_option)

		var summary := Label.new()
		summary.text = template.summary()
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(summary)

		var properties_button := Button.new()
		properties_button.text = "Properties…"
		properties_button.pressed.connect(func():
			_open_monster_properties(template, func(): summary.text = template.summary())
		)
		row.add_child(properties_button)

		var move_up_button := Button.new()
		move_up_button.text = "↑"
		move_up_button.disabled = index == 0
		move_up_button.pressed.connect(func():
			_commit_field("Reorder spawned monster", func():
				var tmp: MonsterTemplate = effect.spawn_monsters[index]
				effect.spawn_monsters[index] = effect.spawn_monsters[index - 1]
				effect.spawn_monsters[index - 1] = tmp
			)
			_open_spawn_monsters_editor(effect)
		)
		row.add_child(move_up_button)

		var move_down_button := Button.new()
		move_down_button.text = "↓"
		move_down_button.disabled = index == effect.spawn_monsters.size() - 1
		move_down_button.pressed.connect(func():
			_commit_field("Reorder spawned monster", func():
				var tmp: MonsterTemplate = effect.spawn_monsters[index]
				effect.spawn_monsters[index] = effect.spawn_monsters[index + 1]
				effect.spawn_monsters[index + 1] = tmp
			)
			_open_spawn_monsters_editor(effect)
		)
		row.add_child(move_down_button)

		var remove_button := Button.new()
		remove_button.text = "×"
		remove_button.pressed.connect(func():
			_commit_field("Remove spawned monster", func(): effect.spawn_monsters.remove_at(index))
			_open_spawn_monsters_editor(effect)
		)
		row.add_child(remove_button)

		_spawn_monsters_editor_container.add_child(row)

	var add_button := Button.new()
	add_button.text = "Add Monster"
	add_button.pressed.connect(func():
		var created := MonsterTemplate.create_with_default_base()
		if created == null:
			OS.alert("Every monster needs a base template. Create one first (File > Monster Templates…).", "No base template")
			return
		_commit_field("Add spawned monster", func(): effect.spawn_monsters.append(created))
		_open_spawn_monsters_editor(effect)
	)
	_spawn_monsters_editor_container.add_child(add_button)

	_spawn_monsters_editor.popup_centered()
