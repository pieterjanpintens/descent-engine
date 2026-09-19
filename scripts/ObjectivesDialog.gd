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

## Same "a dialog opens a smaller dialog" pattern as _optional_editor
## above, new 2026-09-14 for Effect.Type.RUN_TEST's nested editor (attribute
## + threshold + accumulate variable + two nested effect lists - see
## _open_test_editor()).
var _test_editor: Window
var _test_editor_container: VBoxContainer

## Same pattern again, new 2026-09-18 for Effect.conditions (any Effect
## type, not just RUN_TEST) - see _open_effect_conditions_editor().
var _effect_conditions_editor: Window
var _effect_conditions_editor_container: VBoxContainer

## Same pattern again, new 2026-09-19 for Effect.Type.SHOW_MESSAGE's own
## message_variables ($1/$2/... ordered list) - see
## _open_message_variables_editor().
var _message_variables_editor: Window
var _message_variables_editor_container: VBoxContainer


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

	var add_node_button := Button.new()
	add_node_button.text = "Add Node"
	add_node_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_node_button.pressed.connect(_on_add_node_pressed)
	toolbar.add_child(add_node_button)

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
	_build_test_editor()
	_build_effect_conditions_editor()
	_build_message_variables_editor()
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

	# Legacy-mission migration, new 2026-09-18: a node that's reachable as
	# someone's child but was ALSO still sitting in _mission.objectives
	# (possible under the OLD "add as root, never auto-removed once
	# connected" behavior this session replaced - see _reconcile_root()'s
	# own doc) would be evaluated TWICE by MissionRuntime (once as its own
	# independent root group, once via its parent's traversal). Fixed here
	# too, not just for new edits - scanning `visited` directly rather than
	# reusing _reconcile_root() since _node_by_name isn't populated yet at
	# this point in the rebuild. A node can never need the OPPOSITE fix
	# (no incoming edges but missing from _mission.objectives) here - BFS
	# only reaches a node via root-seeding or via node.children, so
	# anything in `visited` with no incoming edge must already be a root.
	for node in visited:
		var has_incoming := false
		for other in visited:
			if other.children.has(node):
				has_incoming = true
				break
		if has_incoming and _mission.objectives.has(node):
			_mission.objectives.erase(node)

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


## `root_prefix` (new 2026-09-18) - "★ Root" whenever this node is
## currently in `_mission.objectives`, so a root reads as one at a glance
## in the graph instead of only being distinguishable by "no arrow points
## into it" (easy to miss, especially with several roots on screen at
## once). Root status is maintained automatically - see
## _reconcile_root()'s own doc - so this always reflects the CURRENT,
## enforced state, never something that can drift out of sync.
func _summary_text(objective: MissionObjective) -> String:
	var root_prefix := "★ Root\n" if _mission.objectives.has(objective) else ""
	if objective.children.is_empty():
		var outcome_text := "WIN" if objective.outcome == MissionObjective.Outcome.WIN else "LOSE"
		return "%sLeaf (%s)\n%d condition(s), %d optional" % [root_prefix, outcome_text, objective.conditions.size(), objective.optional_objectives.size()]
	return "%sBranch\n%d condition(s), %d optional" % [root_prefix, objective.conditions.size(), objective.optional_objectives.size()]


func _refresh_graph_node(objective: MissionObjective) -> void:
	var graph_node: GraphNode = _graph_node_by_objective.get(objective)
	if graph_node == null:
		return
	graph_node.title = objective.description if objective.description != "" else objective.id
	var summary: Label = graph_node.get_child(0)
	summary.text = _summary_text(objective)


## "Add Node", not "Add Root Objective" - renamed 2026-09-18 once
## _on_connection_request()/_on_disconnection_request() started actively
## maintaining "a node is a root iff it has no incoming connections" (see
## _reconcile_root() below): there's no other way to create a node at all
## (this button is it), and a freshly-created one has no incoming
## connections yet, so it always starts as a root regardless of what this
## button is called - the OLD name just exposed an implementation detail
## ("you must add nodes as roots") that isn't actually a designer-facing
## choice. A node stops being a root the moment something connects INTO
## it, automatically - see _reconcile_root()'s own doc for the full
## invariant.
func _on_add_node_pressed() -> void:
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
		# A node that gains its first incoming connection stops being a
		# root - see _reconcile_root()'s own doc. Called INSIDE this same
		# mutate Callable, not after record() returns - record() snapshots
		# its "after" state the instant mutate.call() finishes, so a
		# mutation made afterward would silently fall outside the undo
		# snapshot.
		_reconcile_root(to_obj)
	)
	_graph.connect_node(from_node, from_port, to_node, to_port)
	layered_map.notify_objects_changed()
	_refresh_graph_node(from_obj)  # Leaf -> Branch, now that it has a child
	_refresh_graph_node(to_obj)  # may have just lost its "★ Root" prefix
	if _selected == from_obj:
		_rebuild_properties_panel()


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var from_obj: MissionObjective = _node_by_name.get(from_node)
	var to_obj: MissionObjective = _node_by_name.get(to_node)
	if from_obj == null or to_obj == null:
		return
	operation_history.record("Disconnect objective", func():
		from_obj.children.erase(to_obj)
		# A node that loses its LAST incoming connection becomes a root
		# again, so it doesn't go unreachable - see _reconcile_root()'s own
		# doc for why this needs to run inside the same mutate Callable.
		_reconcile_root(to_obj)
	)
	_graph.disconnect_node(from_node, from_port, to_node, to_port)
	layered_map.notify_objects_changed()
	_refresh_graph_node(from_obj)  # may have just become a Leaf again
	_refresh_graph_node(to_obj)  # may have just regained its "★ Root" prefix
	if _selected == from_obj:
		_rebuild_properties_panel()


## Enforces "a node is a root (present in `_mission.objectives`) if and
## only if it has no incoming connections" - the invariant that replaces
## the old "you must explicitly add nodes as roots, and they silently stay
## roots even once connected as a child too" behavior (a real, latent
## double-counting bug: MissionRuntime seeds one independently-watched
## group per entry in mission.objectives, so a node that was BOTH a root
## AND reachable as someone's child would be evaluated twice). Scans every
## node currently in the graph (_node_by_name.values()) rather than just
## the two endpoints of the edge that just changed, since a DIFFERENT
## node could also still connect into `objective` - it only stops "having
## incoming connections" once EVERY parent is gone, not just the one edge
## that was just touched. Called from inside _on_connection_request()'s/
## _on_disconnection_request()'s own operation_history.record() mutate
## Callables - see those call sites for why the ordering matters.
##
## Deliberately NOT applied on node delete (_on_node_close_requested()) -
## that function's "an orphaned subtree simply disappears rather than
## getting re-rooted" behavior is its own documented, deliberate
## cascade-delete design; reconciling roots there would silently change
## it into "preserve every orphan as its own new root" instead, a bigger
## behavior change than was asked for here.
func _reconcile_root(objective: MissionObjective) -> void:
	var has_incoming := false
	for node in _node_by_name.values():
		if node.children.has(objective):
			has_incoming = true
			break
	var is_root := _mission.objectives.has(objective)
	if has_incoming and is_root:
		_mission.objectives.erase(objective)
	elif not has_incoming and not is_root:
		_mission.objectives.append(objective)


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


## Swaps `item` with its neighbor `delta` slots away (-1 = up/earlier,
## +1 = down/later) - a no-op if `item` is already at that end of the
## array. Added 2026-09-17 so reordering a condition/effect doesn't mean
## deleting everything just to re-add it in the right order ("its kinda
## shitty having to delete all because you want to add something in the
## beginning"). Takes a plain `Array` rather than a typed one - a typed
## `Array[Condition]`/`Array[Effect]` is still a real Array object
## underneath in GDScript, so passing it in untyped and mutating it in
## place still affects the original caller's array. Own copy, not shared
## with PropActionsDialog.gd's identical helper - same "each dialog owns
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
		_props_panel.add_child(_build_condition_row(objective.conditions, condition, _rebuild_properties_panel))
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
		_props_panel.add_child(_build_effect_row(objective.effects, effect, _rebuild_properties_panel))
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


## Built-in variable names (MissionRuntime.BUILTIN_TYPES) plus every
## declared MissionData.custom_variables name - the full set a Condition/
## Effect's variable_name can validly reference right now.
func _known_variable_names() -> Array[String]:
	var names: Array[String] = ["round_number", "player_count"]
	for variable in _mission.custom_variables:
		names.append(variable.name)
	return names


## A dropdown of _known_variable_names() (new 2026-09-14, replacing a
## free-text LineEdit - "can we provide them in a dropdown... instead of
## requiring a string") - shared by _build_condition_row()/
## _build_effect_row() below, both in this same file (unlike the
## cross-DIALOG "each script owns its own near-identical widget code"
## convention elsewhere, sharing a helper within one file is fine).
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
	var names: Array[String] = ["round_number", "player_count"]
	for variable in _mission.custom_variables:
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
## `.erase()` - same refactor `_build_effect_row()`'s own `effects_list`
## parameter already went through, for the same reason: a plain array
## reference works identically whether it's an objective's own
## `.conditions`, an optional objective's `.conditions`, or - new the same
## day - an `Effect`'s own `.conditions` (see _open_effect_conditions_editor()
## below), which isn't a `MissionObjective` at all). `on_changed` lets each
## caller decide what to rebuild after a remove/reorder (the outer panel,
## the nested optional-objective editor, or the nested effect-conditions
## editor).
func _build_condition_row(conditions_list: Array[Condition], condition: Condition, on_changed: Callable) -> Control:
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
func _build_effect_row(effects_list: Array[Effect], effect: Effect, on_changed: Callable) -> Control:
	var row := HBoxContainer.new()

	var type_option := OptionButton.new()
	type_option.add_item("Set Variable", Effect.Type.SET_VARIABLE)
	type_option.add_item("Show Stage", Effect.Type.SHOW_STAGE)
	type_option.add_item("Remove Object", Effect.Type.REMOVE_OBJECT)
	type_option.add_item("Test", Effect.Type.RUN_TEST)
	type_option.add_item("Show Message", Effect.Type.SHOW_MESSAGE)
	type_option.add_item("Move Object", Effect.Type.MOVE_OBJECT)
	type_option.add_item("Math", Effect.Type.MATH)
	type_option.add_item("Spawn Monsters", Effect.Type.SPAWN_MONSTERS)
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

	## Every prop plus every floor/underlay tile - not groups, which have
	## no GridMap presence to remove. The origin-cell suffix disambiguates
	## entries sharing a mesh name (several "gate"s, or every plain "1a"
	## floor tile) - genuinely needed here unlike the group picker above,
	## since groups are already uniquely named.
	var object_option := OptionButton.new()
	var object_ids: Array[String] = []
	var removable_nodes: Array = []
	removable_nodes.append_array(_mission.interactables)
	removable_nodes.append_array(_mission.floor_placements)
	removable_nodes.append_array(_mission.underlay_placements)
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
	for spawn_index in _mission.monster_spawns.size():
		var candidate: MonsterSpawn = _mission.monster_spawns[spawn_index]
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
		_optional_editor_container.add_child(_build_condition_row(optional.conditions, condition, func(): _open_optional_editor(parent_objective, optional)))
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
		_optional_editor_container.add_child(_build_effect_row(optional.effects, effect, func(): _open_optional_editor(parent_objective, optional)))
	var add_effect_button := Button.new()
	add_effect_button.text = "Add Effect"
	add_effect_button.pressed.connect(func():
		var effect := Effect.new()
		_commit_field("Add effect", func(): optional.effects.append(effect))
		_open_optional_editor(parent_objective, optional)
	)
	_optional_editor_container.add_child(add_effect_button)


## ---- Nested "edit one Test effect" dialog ----
## Same "a dialog opens a smaller dialog" pattern as _optional_editor
## above - Effect.Type.RUN_TEST's attribute/threshold/accumulate-variable/
## two-nested-effect-list editor doesn't fit in one row, see
## _build_effect_row()'s own "Edit Test…" button.

func _build_test_editor() -> void:
	_test_editor = Window.new()
	_test_editor.title = "Test"
	_test_editor.size = Vector2i(360, 480)
	_test_editor.close_requested.connect(_test_editor.hide)
	_test_editor.visible = false
	add_child(_test_editor)

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


## ---- Nested "edit one Effect's own conditions" dialog ----
## Same "a dialog opens a smaller dialog" pattern as _optional_editor/
## _test_editor above - Effect.conditions (new 2026-09-18, requested
## directly: "can we make effects also conditional... only execute the
## effect if its condition holds") is a universal Effect field, not tied
## to one Type, so a compact "Conditions…" button on EVERY effect row (see
## _build_effect_row()) opens this rather than growing every widget group
## with its own copy.

func _build_effect_conditions_editor() -> void:
	_effect_conditions_editor = Window.new()
	_effect_conditions_editor.title = "Effect Conditions"
	_effect_conditions_editor.size = Vector2i(360, 320)
	_effect_conditions_editor.close_requested.connect(_effect_conditions_editor.hide)
	_effect_conditions_editor.visible = false
	add_child(_effect_conditions_editor)

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
		_effect_conditions_editor_container.add_child(_build_condition_row(effect.conditions, condition, func(): _open_effect_conditions_editor(effect)))
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
	add_child(_message_variables_editor)

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
		_spawn_monsters_editor.size = Vector2i(360, 360)
		_spawn_monsters_editor.close_requested.connect(_spawn_monsters_editor.hide)
		_spawn_monsters_editor.visible = false
		add_child(_spawn_monsters_editor)
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

	_spawn_monsters_editor_container.add_child(_label("Monsters in spawn-tile order (1st on tile 1, ...):"))
	for i in effect.spawn_monsters.size():
		var index := i  # captured by value for this row's own closures below
		var row := HBoxContainer.new()
		row.add_child(_label("%d:" % (index + 1)))

		var monster_option := OptionButton.new()
		for monster_index in MonsterDisplay.REAL_MONSTERS.size():
			monster_option.add_item(MonsterDisplay.REAL_MONSTERS[monster_index]["name"], monster_index)
			if MonsterDisplay.REAL_MONSTERS[monster_index]["folder"] == effect.spawn_monsters[index]:
				monster_option.select(monster_index)
		monster_option.item_selected.connect(func(_selected: int):
			var folder: String = MonsterDisplay.REAL_MONSTERS[monster_option.get_selected_id()]["folder"]
			_commit_field("Edit spawned monster", func(): effect.spawn_monsters[index] = folder)
		)
		row.add_child(monster_option)

		var move_up_button := Button.new()
		move_up_button.text = "↑"
		move_up_button.disabled = index == 0
		move_up_button.pressed.connect(func():
			_commit_field("Reorder spawned monster", func():
				var tmp: String = effect.spawn_monsters[index]
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
				var tmp: String = effect.spawn_monsters[index]
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
		_commit_field("Add spawned monster", func(): effect.spawn_monsters.append(MonsterDisplay.REAL_MONSTERS[0]["folder"]))
		_open_spawn_monsters_editor(effect)
	)
	_spawn_monsters_editor_container.add_child(add_button)

	_spawn_monsters_editor.popup_centered()
