class_name ObjectivesDialog
extends Window

## DAG editor for MissionData.objectives (reworked 2026-09-12 from a
## single win-objective LineEdit - see claude.md's Story layer section for
## the full design). A GraphEdit canvas on the left - one GraphNode per
## MissionObjective reachable from mission.objectives' roots, walked as a
## DAG so a node reachable from more than one parent only gets ONE
## GraphNode - plus a properties panel on the right showing whichever node
## is currently selected. Opened via CreatorSaveLoad.gd's "Objectives…"
## button - one instance, created there in code and reused via
## open_for(), same pattern as PropertiesDialog.gd (not a .tscn node,
## operation_history/layered_map assigned directly after .new()).
##
## Every edit goes through operation_history.record() then
## layered_map.notify_objects_changed(), same convention as
## PropertiesDialog.gd/CreatorPropertiesPanel.gd. GraphNode canvas
## positions (MissionObjective.editor_position) are NOT undo-tracked -
## pure layout metadata, saved directly whenever the dialog closes.
##
## Unverified in-editor - GraphEdit's connection/selection/close-request
## behavior especially, since none of it can be visually confirmed here.

var operation_history: OperationHistory
var layered_map: LayeredMap

enum _ValueType { STRING, BOOL, INT, FLOAT }

var _mission: MissionData
var _graph: GraphEdit
var _props_panel: VBoxContainer
var _selected: MissionObjective

## GraphNode name (StringName) <-> MissionObjective - GraphEdit's
## connection_request()/node_selected()/close_request signals only give
## us node names or the Node itself, never the resource directly.
var _node_by_name: Dictionary = {}  # StringName -> MissionObjective
var _name_by_node: Dictionary = {}  # MissionObjective -> StringName
var _graph_node_by_objective: Dictionary = {}  # MissionObjective -> GraphNode

var _optional_editor: Window
var _optional_editor_container: VBoxContainer


func _ready() -> void:
	title = "Objectives"
	size = Vector2i(900, 560)
	close_requested.connect(_on_close_requested)
	visible = false

	var root := HSplitContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(left)

	# A real toolbar row, not a bare Button - a lone Button as a direct
	# VBoxContainer child stretches to the container's full width (and
	# looks "fat" as a result). HBoxContainer + SHRINK_BEGIN keeps it
	# sized to its own content and left-aligned, and gives room to add
	# more toolbar actions later without restructuring.
	var toolbar := HBoxContainer.new()
	left.add_child(toolbar)

	var add_root_button := Button.new()
	add_root_button.text = "Add Root Objective"
	add_root_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_root_button.pressed.connect(_on_add_root_pressed)
	toolbar.add_child(add_root_button)

	_graph = GraphEdit.new()
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# GraphEdit only ever emits connection_request for port-type pairs
	# explicitly whitelisted here - type compatibility is checked BEFORE
	# the signal fires, even for two ports of the identical type (0here).
	# Without this, a drag visually snaps to a target port (GraphEdit's
	# own drag-preview feedback) but is silently discarded on release,
	# with no signal ever reaching this script and no error printed -
	# confirmed in-editor 2026-09-12.
	_graph.add_valid_connection_type(0, 0)
	_graph.connection_request.connect(_on_connection_request)
	_graph.disconnection_request.connect(_on_disconnection_request)
	_graph.node_selected.connect(_on_node_selected)
	left.add_child(_graph)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 0)
	root.add_child(scroll)

	_props_panel = VBoxContainer.new()
	_props_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_props_panel)

	_build_optional_editor()
	_show_no_selection()


## Public - CreatorSaveLoad.gd calls this from its "Objectives…" button.
func open_for(mission: MissionData) -> void:
	_mission = mission
	_selected = null
	_rebuild_graph()
	_show_no_selection()
	popup_centered()


## Canvas layout is authoring metadata only (not undo-tracked, see class
## doc) - saved directly to each node's editor_position whenever the
## dialog closes, so a rearrange survives the next open_for() without
## cluttering the undo stack.
func _on_close_requested() -> void:
	for objective in _name_by_node.keys():
		var graph_node: GraphNode = _graph_node_by_objective[objective]
		objective.editor_position = graph_node.position_offset
	hide()


func _rebuild_graph() -> void:
	_graph.clear_connections()
	# GraphEdit.get_children() incorrectly includes its own internal
	# _connection_layer node even though it's meant to be excluded
	# (confirmed Godot engine bug - see godotengine/godot#91857).
	# Freeing every child indiscriminately destroys that layer, which then
	# makes gui_input() hard-error ("connections_layer is missing") on
	# every future click and silently breaks node dragging. Only free
	# actual GraphElement/GraphNode children we added ourselves.
	#
	# IMMEDIATE free() here, not queue_free(): this function re-adds a
	# fresh GraphNode using the SAME computed name for each still-present
	# objective right after this loop. queue_free() only marks a node for
	# removal at the end of the current frame, so a same-frame add_child()
	# with the same name (any objective surviving from before, e.g. a
	# second root added right after the first) collides with the
	# not-yet-actually-removed old node - Godot then silently discards the
	# requested name and falls back to its own auto-generated placeholder
	# ("@GraphNode@642") instead, breaking every later name-based lookup
	# for that node (connection_request, node_selected, ...). Confirmed
	# in-editor 2026-09-13.
	for child in _graph.get_children():
		if child is GraphElement:
			_graph.remove_child(child)
			child.free()
	_node_by_name.clear()
	_name_by_node.clear()
	_graph_node_by_objective.clear()

	if _mission == null:
		return

	# BFS from every root, visiting each unique node once - a DAG, so a
	# node reachable from more than one parent must still only get ONE
	# GraphNode.
	var visited: Array[MissionObjective] = []
	var queue: Array[MissionObjective] = []
	for root in _mission.objectives:
		if not visited.has(root):
			visited.append(root)
			queue.append(root)
	var i := 0
	while i < queue.size():
		var node: MissionObjective = queue[i]
		i += 1
		for child in node.children:
			if not visited.has(child):
				visited.append(child)
				queue.append(child)

	for index in visited.size():
		_add_graph_node(visited[index], index)

	for node in visited:
		for child in node.children:
			_graph.connect_node(_name_by_node[node], 0, _name_by_node[child], 0)


func _add_graph_node(objective: MissionObjective, fallback_index: int) -> void:
	var graph_node := GraphNode.new()
	var node_name := StringName("obj_%s" % objective.id)
	graph_node.name = node_name
	graph_node.title = objective.description if objective.description != "" else objective.id

	# A never-opened-before node (editor_position still at the default
	# ZERO) gets fanned out horizontally by BFS order so freshly-created
	# nodes don't all stack on top of each other - a real position (even
	# a manually-dragged-back-to-origin one) is left alone. The base
	# margin (not just fallback_index > 0) matters: GraphEdit draws its
	# own built-in zoom/minimap controls floating over the canvas's
	# top-left corner, so a node placed at literal (0,0) renders directly
	# underneath/behind them - hard to even see, let alone grab.
	if objective.editor_position == Vector2.ZERO:
		graph_node.position_offset = Vector2(60, 80) + Vector2(fallback_index * 220, 0)
	else:
		graph_node.position_offset = objective.editor_position

	var summary := Label.new()
	summary.text = _summary_text(objective)
	graph_node.add_child(summary)

	# One slot, input and output both enabled - any node can be dragged
	# into a connection either direction (a root's input just stays
	# unused, harmless). Slot index matches the summary Label's child
	# index (0) - GraphNode assigns slots by row/child position.
	graph_node.set_slot(0, true, 0, Color.WHITE, true, 0, Color.WHITE)

	# GraphNode.show_close/close_request don't exist on this Godot
	# version - a plain child Button is a manual close/delete affordance
	# instead, same "×" pattern used for every other remove button in
	# this dialog. Sits at child index 1 (no slot configured for it, so
	# it gets no connection port dots).
	var delete_button := Button.new()
	delete_button.text = "Delete Node"
	delete_button.pressed.connect(_on_node_close_requested.bind(objective))
	graph_node.add_child(delete_button)

	_graph.add_child(graph_node)
	_node_by_name[node_name] = objective
	_name_by_node[objective] = node_name
	_graph_node_by_objective[objective] = graph_node


func _summary_text(objective: MissionObjective) -> String:
	if objective.children.is_empty():
		var outcome_text := "WIN" if objective.outcome == MissionObjective.Outcome.WIN else "LOSE"
		return "Leaf (%s)\n%d condition(s), %d optional" % [outcome_text, objective.conditions.size(), objective.optional_objectives.size()]
	return "Branch\n%d condition(s), %d optional" % [objective.conditions.size(), objective.optional_objectives.size()]


func _refresh_graph_node(objective: MissionObjective) -> void:
	var graph_node: GraphNode = _graph_node_by_objective.get(objective)
	if graph_node == null:
		return
	graph_node.title = objective.description if objective.description != "" else objective.id
	var summary: Label = graph_node.get_child(0)
	summary.text = _summary_text(objective)


func _on_add_root_pressed() -> void:
	if _mission == null:
		return
	var objective := MissionObjective.new()
	objective.id = _mission.allocate_object_id()
	var mission := _mission
	operation_history.record("Add objective", func():
		mission.objectives.append(objective)
	)
	layered_map.notify_objects_changed()
	_rebuild_graph()


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var from_obj: MissionObjective = _node_by_name.get(from_node)
	var to_obj: MissionObjective = _node_by_name.get(to_node)
	if from_obj == null or to_obj == null or from_obj == to_obj or from_obj.children.has(to_obj):
		return
	operation_history.record("Connect objective", func():
		from_obj.children.append(to_obj)
	)
	_graph.connect_node(from_node, from_port, to_node, to_port)
	layered_map.notify_objects_changed()
	_refresh_graph_node(from_obj)
	if _selected == from_obj:
		_rebuild_properties_panel()


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var from_obj: MissionObjective = _node_by_name.get(from_node)
	var to_obj: MissionObjective = _node_by_name.get(to_node)
	if from_obj == null or to_obj == null:
		return
	operation_history.record("Disconnect objective", func():
		from_obj.children.erase(to_obj)
	)
	_graph.disconnect_node(from_node, from_port, to_node, to_port)
	layered_map.notify_objects_changed()
	_refresh_graph_node(from_obj)
	if _selected == from_obj:
		_rebuild_properties_panel()


## A full delete, not a single-edge removal (dragging a connection off
## already covers edge-only removal) - removes this node from EVERY
## parent's children that references it (and from mission.objectives if
## it was a root), then rebuilds the graph. Any subtree that was ONLY
## reachable through the deleted node simply won't appear in the rebuilt
## graph - nothing else references it, so it's freed like any other
## unreferenced Resource, no explicit cascade-delete needed.
func _on_node_close_requested(objective: MissionObjective) -> void:
	var mission := _mission
	var all_nodes: Array = _node_by_name.values()
	operation_history.record("Delete objective", func():
		mission.objectives.erase(objective)
		for node in all_nodes:
			node.children.erase(objective)
	)
	layered_map.notify_objects_changed()
	if _selected == objective:
		_selected = null
	_rebuild_graph()
	_rebuild_properties_panel()


func _on_node_selected(node: Node) -> void:
	var objective: MissionObjective = _node_by_name.get(node.name)
	if objective == null:
		return
	_selected = objective
	_rebuild_properties_panel()


func _commit_field(label: String, mutate: Callable) -> void:
	operation_history.record(label, mutate)
	layered_map.notify_objects_changed()


func _show_no_selection() -> void:
	for child in _props_panel.get_children():
		child.queue_free()
	var label := Label.new()
	label.text = "Select a node to edit it."
	_props_panel.add_child(label)


## ---- Properties panel for whichever node is currently selected ----

func _rebuild_properties_panel() -> void:
	for child in _props_panel.get_children():
		child.queue_free()
	if _selected == null:
		_show_no_selection()
		return

	var objective := _selected

	_props_panel.add_child(_label("Description:"))
	var desc_edit := LineEdit.new()
	desc_edit.text = objective.description
	var commit_desc := func():
		_commit_field("Edit objective description", func(): objective.description = desc_edit.text)
		_refresh_graph_node(objective)
	desc_edit.text_submitted.connect(func(_t): commit_desc.call())
	desc_edit.focus_exited.connect(commit_desc)
	_props_panel.add_child(desc_edit)

	_props_panel.add_child(_label("Outcome (only applies to a leaf - no children):"))
	var outcome_option := OptionButton.new()
	outcome_option.add_item("WIN", MissionObjective.Outcome.WIN)
	outcome_option.add_item("LOSE", MissionObjective.Outcome.LOSE)
	outcome_option.select(outcome_option.get_item_index(objective.outcome))
	outcome_option.disabled = not objective.children.is_empty()
	outcome_option.item_selected.connect(func(_index):
		var value: int = outcome_option.get_selected_id()
		_commit_field("Set objective outcome", func(): objective.outcome = value)
		_refresh_graph_node(objective)
	)
	_props_panel.add_child(outcome_option)

	_props_panel.add_child(_label("Priority (tie-break among siblings, lower first):"))
	var priority_spin := SpinBox.new()
	priority_spin.min_value = -999
	priority_spin.max_value = 999
	priority_spin.step = 1
	priority_spin.value = objective.priority
	priority_spin.value_changed.connect(func(new_value: float):
		_commit_field("Set objective priority", func(): objective.priority = int(new_value))
	)
	_props_panel.add_child(priority_spin)

	_props_panel.add_child(HSeparator.new())
	_props_panel.add_child(_label("Conditions (implicit AND):"))
	for condition in objective.conditions:
		_props_panel.add_child(_build_condition_row(objective, condition, _rebuild_properties_panel))
	var add_condition_button := Button.new()
	add_condition_button.text = "Add Condition"
	add_condition_button.pressed.connect(func():
		var condition := Condition.new()
		_commit_field("Add condition", func(): objective.conditions.append(condition))
		_refresh_graph_node(objective)
		_rebuild_properties_panel()
	)
	_props_panel.add_child(add_condition_button)

	_props_panel.add_child(HSeparator.new())
	_props_panel.add_child(_label("Effects (applied once when achieved):"))
	for effect in objective.effects:
		_props_panel.add_child(_build_effect_row(objective, effect, _rebuild_properties_panel))
	var add_effect_button := Button.new()
	add_effect_button.text = "Add Effect"
	add_effect_button.pressed.connect(func():
		var effect := Effect.new()
		_commit_field("Add effect", func(): objective.effects.append(effect))
		_rebuild_properties_panel()
	)
	_props_panel.add_child(add_effect_button)

	_props_panel.add_child(HSeparator.new())
	_props_panel.add_child(_label("Optional objectives (valid only while this node is active):"))
	for optional in objective.optional_objectives:
		_props_panel.add_child(_build_optional_row(objective, optional))
	var add_optional_button := Button.new()
	add_optional_button.text = "Add Optional Objective"
	add_optional_button.pressed.connect(func():
		var optional := MissionObjective.new()
		optional.id = _mission.allocate_object_id()
		_commit_field("Add optional objective", func(): objective.optional_objectives.append(optional))
		_refresh_graph_node(objective)
		_rebuild_properties_panel()
	)
	_props_panel.add_child(add_optional_button)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


## `holder` is whatever MissionObjective actually owns this condition -
## the real node when called from the main panel, or an optional
## objective when called from _open_optional_editor(). `on_changed` lets
## each caller decide what to rebuild after a remove (the outer panel vs.
## the nested optional-objective editor).
func _build_condition_row(holder: MissionObjective, condition: Condition, on_changed: Callable) -> Control:
	var row := HBoxContainer.new()

	var var_edit := LineEdit.new()
	var_edit.text = condition.variable_name
	var_edit.custom_minimum_size = Vector2(90, 0)
	var commit_var := func():
		_commit_field("Edit condition variable", func(): condition.variable_name = var_edit.text)
	var_edit.text_submitted.connect(func(_t): commit_var.call())
	var_edit.focus_exited.connect(commit_var)
	row.add_child(var_edit)

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

	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.pressed.connect(func():
		_commit_field("Remove condition", func(): holder.conditions.erase(condition))
		on_changed.call()
	)
	row.add_child(remove_button)

	return row


## `type_option` (Set Variable/Show Stage) picks between two pre-built
## widget groups shown one at a time - same "build all, toggle .visible"
## trick _build_value_editor() below already uses for its own String/Bool/
## Int/Float picker. Show Stage's group_option has no "(root)" entry -
## showing a stage for the mission root doesn't mean anything.
func _build_effect_row(holder: MissionObjective, effect: Effect, on_changed: Callable) -> Control:
	var row := HBoxContainer.new()

	var type_option := OptionButton.new()
	type_option.add_item("Set Variable", Effect.Type.SET_VARIABLE)
	type_option.add_item("Show Stage", Effect.Type.SHOW_STAGE)
	type_option.select(type_option.get_item_index(effect.type))
	row.add_child(type_option)

	var var_edit := LineEdit.new()
	var_edit.text = effect.variable_name
	var_edit.placeholder_text = "variable name"
	var_edit.custom_minimum_size = Vector2(90, 0)
	var commit_var := func():
		_commit_field("Edit effect variable", func(): effect.variable_name = var_edit.text)
	var_edit.text_submitted.connect(func(_t): commit_var.call())
	var_edit.focus_exited.connect(commit_var)
	row.add_child(var_edit)

	var value_editor := _build_value_editor(effect.value, func(new_value): _commit_field("Edit effect value", func(): effect.value = new_value))
	row.add_child(value_editor)

	var group_option := OptionButton.new()
	var group_ids: Array[String] = []
	for group in _mission.groups:
		group_option.add_item(group.reference_name if group.reference_name != "" else "(unnamed group)")
		group_ids.append(group.id)
	var initial_group_index := group_ids.find(effect.target_group_id)
	group_option.select(initial_group_index)
	group_option.item_selected.connect(func(index: int):
		if index >= 0 and index < group_ids.size():
			_commit_field("Edit effect target stage", func(): effect.target_group_id = group_ids[index])
	)
	row.add_child(group_option)

	var update_visibility := func():
		var is_show_stage: bool = type_option.get_selected_id() == Effect.Type.SHOW_STAGE
		var_edit.visible = not is_show_stage
		value_editor.visible = not is_show_stage
		group_option.visible = is_show_stage
	update_visibility.call()
	type_option.item_selected.connect(func(_index):
		var new_type: int = type_option.get_selected_id()
		_commit_field("Edit effect type", func(): effect.type = new_type)
		update_visibility.call()
	)

	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.pressed.connect(func():
		_commit_field("Remove effect", func(): holder.effects.erase(effect))
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


func _build_optional_row(objective: MissionObjective, optional: MissionObjective) -> Control:
	var row := HBoxContainer.new()

	var label := Label.new()
	label.text = optional.description if optional.description != "" else "(untitled optional objective)"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var edit_button := Button.new()
	edit_button.text = "Edit…"
	edit_button.pressed.connect(func(): _open_optional_editor(objective, optional))
	row.add_child(edit_button)

	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.pressed.connect(func():
		_commit_field("Remove optional objective", func(): objective.optional_objectives.erase(optional))
		_refresh_graph_node(objective)
		_rebuild_properties_panel()
	)
	row.add_child(remove_button)

	return row


## ---- Nested "edit one optional objective" dialog ----
## Same "a dialog opens a smaller dialog" pattern PropertiesDialog's own
## Add-Property ConfirmationDialog already uses. children/outcome don't
## apply to an optional objective (see MissionObjective's own doc) so
## only description/conditions/effects are editable here.

func _build_optional_editor() -> void:
	_optional_editor = Window.new()
	_optional_editor.size = Vector2i(360, 400)
	_optional_editor.close_requested.connect(_optional_editor.hide)
	_optional_editor.visible = false
	add_child(_optional_editor)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8
	scroll.offset_top = 8
	scroll.offset_right = -8
	scroll.offset_bottom = -8
	_optional_editor.add_child(scroll)

	_optional_editor_container = VBoxContainer.new()
	_optional_editor_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_optional_editor_container)


func _open_optional_editor(parent_objective: MissionObjective, optional: MissionObjective) -> void:
	_optional_editor.title = "Optional Objective (for '%s')" % (parent_objective.description if parent_objective.description != "" else parent_objective.id)

	for child in _optional_editor_container.get_children():
		child.queue_free()

	_optional_editor_container.add_child(_label("Description:"))
	var desc_edit := LineEdit.new()
	desc_edit.text = optional.description
	var commit_desc := func():
		_commit_field("Edit optional objective description", func(): optional.description = desc_edit.text)
		_rebuild_properties_panel()
	desc_edit.text_submitted.connect(func(_t): commit_desc.call())
	desc_edit.focus_exited.connect(commit_desc)
	_optional_editor_container.add_child(desc_edit)

	_optional_editor_container.add_child(HSeparator.new())
	_optional_editor_container.add_child(_label("Conditions (implicit AND):"))
	for condition in optional.conditions:
		_optional_editor_container.add_child(_build_condition_row(optional, condition, func(): _open_optional_editor(parent_objective, optional)))
	var add_condition_button := Button.new()
	add_condition_button.text = "Add Condition"
	add_condition_button.pressed.connect(func():
		var condition := Condition.new()
		_commit_field("Add condition", func(): optional.conditions.append(condition))
		_open_optional_editor(parent_objective, optional)
	)
	_optional_editor_container.add_child(add_condition_button)

	_optional_editor_container.add_child(HSeparator.new())
	_optional_editor_container.add_child(_label("Effects (applied once when achieved):"))
	for effect in optional.effects:
		_optional_editor_container.add_child(_build_effect_row(optional, effect, func(): _open_optional_editor(parent_objective, optional)))
	var add_effect_button := Button.new()
	add_effect_button.text = "Add Effect"
	add_effect_button.pressed.connect(func():
		var effect := Effect.new()
		_commit_field("Add effect", func(): optional.effects.append(effect))
		_open_optional_editor(parent_objective, optional)
	)
	_optional_editor_container.add_child(add_effect_button)

	_optional_editor.popup_centered()
