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

## The shared condition/effect editor widgets (EffectEditor).
var _editor: EffectEditor


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
	_editor = EffectEditor.new()
	_editor.setup(self, _commit_field)
	_show_no_selection()


## Public - CreatorSaveLoad.gd calls this from its "Objectives…" button.
func open_for(mission: MissionData) -> void:
	_mission = mission
	_editor.mission = mission
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
		_props_panel.add_child(_editor.build_condition_row(objective.conditions, condition, _rebuild_properties_panel))
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
		_props_panel.add_child(_editor.build_effect_row(objective.effects, effect, _rebuild_properties_panel))
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
		_optional_editor_container.add_child(_editor.build_condition_row(optional.conditions, condition, func(): _open_optional_editor(parent_objective, optional)))
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
		_optional_editor_container.add_child(_editor.build_effect_row(optional.effects, effect, func(): _open_optional_editor(parent_objective, optional)))
	var add_effect_button := Button.new()
	add_effect_button.text = "Add Effect"
	add_effect_button.pressed.connect(func():
		var effect := Effect.new()
		_commit_field("Add effect", func(): optional.effects.append(effect))
		_open_optional_editor(parent_objective, optional)
	)
	_optional_editor_container.add_child(add_effect_button)
