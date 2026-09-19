class_name CreatorPropertiesPanel
extends Control

## Owns the SidePanel/Outline tab's lower half (the Inspector) - switches
## between the existing mission-level fields (Objective/player count,
## still fully owned/read-written by CreatorSaveLoad.gd) and an editable
## form for whatever object/tile/group is selected in CreatorOutline
## above it. Expanded 2026-09-10 from a read-only summary to real editing
## of `reference_name`/`visible` - the two fields every selectable node
## shares via OutlineNode (see that script's own doc comment), now that
## the data model has one shared place to read/write them instead of
## three separate per-type implementations. InteractableEntry.props (see
## PropertiesDialog.gd) and .actions (see PropActionsDialog.gd) both have
## full editing UI now too. Still a later pass: LEVEL_LINK's own
## link_from_cell/link_to_cell/link_bidirectional fields.
##
## Talks to CreatorOutline ONLY through its public `selection_changed`
## signal - see CreatorPalette.gd's own doc comment for why (keeps this
## script and CreatorOutline from ever drifting out of sync with each
## other's internal state). Refreshing the form after some OTHER path edits
## the same node (the tree's own inline group rename, an undo/redo, a
## world-click pick) falls out of that same signal for free: CreatorOutline
## re-emits `selection_changed` for whatever's currently selected every
## time it rebuilds (see that script's `_rebuild_tree()`), not just on an
## actual selection change - so this form is never stale for more than one
## rebuild.
##
## **Multi-select** (2026-09-14, CreatorOutline's tree is SELECT_MULTI now)
## adds a THIRD sibling state, `_multi_fields` - shown whenever
## `selection_changed` carries more than one item. Deliberately minimal per
## the request that motivated it ("properties view can be frozen, only the
## add to group action should be visible"): a count label and a single
## batch "Move to Group" action, nothing else - `mission_fields`/
## `_object_fields` both hidden, no per-item editing while multiple things
## are selected.

@export var creator_outline: CreatorOutline
@export var layered_map: LayeredMap
@export var operation_history: OperationHistory  ## records name/visible edits for undo/redo
@export var mission_fields: Control  ## the existing PropertiesFields node

## The single-selection form: a ScrollContainer (toggled visible/hidden like
## the other panels) wrapping `_object_content` - the panel is short and the
## fields (name, buttons, a monster spawn's tile list) overflowed it.
var _object_fields: ScrollContainer
var _object_content: VBoxContainer
var _info_label: Label
var _name_edit: LineEdit
var _visible_check: CheckBox
var _properties_button: Button
var _properties_dialog: PropertiesDialog
var _actions_button: Button

## MonsterSpawn only - the ordered tile list with reorder/remove buttons,
## rebuilt by _rebuild_spawn_tiles() on every selection refresh.
var _spawn_tiles_box: VBoxContainer
var _actions_dialog: PropActionsDialog

## Multi-select batch panel (see class doc) - built once alongside
## _object_fields/mission_fields, shown only while selection_changed
## carries more than one item.
var _multi_fields: VBoxContainer
var _multi_count_label: Label
var _multi_group_option: OptionButton
var _multi_group_ids: Array[String] = []  # parallel to _multi_group_option's items, same pattern as CreatorOutline's own _working_group_ids/_move_to_target_ids

## The current multi-selection's raw metadata dicts (CreatorOutline's own
## per-item {type, id[, grid]} shape) - only meaningful while _multi_fields
## is visible, read by the "Move to Group" button below.
var _current_multi_selection: Array = []

## Whichever OutlineNode is currently shown (InteractableEntry/
## TilePlacement/MissionGroup all extend it) - null while ROOT is
## selected, since MissionData itself isn't one. Editing reference_name/
## visible below writes straight to THIS object regardless of its
## concrete type - the whole point of pulling those fields up to
## OutlineNode was to not need type-specific edit logic here.
var _current_node: OutlineNode

## Guards the field-refresh path (_show_single() setting
## _name_edit.text/_visible_check.button_pressed FROM data) from being
## mistaken for a user edit and looping back into a record() call.
var _suppress_field_signals: bool = false


func _ready() -> void:
	_build_object_fields()
	_build_multi_fields()
	creator_outline.selection_changed.connect(_on_selection_changed)


func _build_object_fields() -> void:
	_object_fields = ScrollContainer.new()
	_object_fields.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_object_fields.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_object_fields.offset_left = 8.0
	_object_fields.offset_top = 8.0
	_object_fields.offset_right = -8.0
	_object_fields.offset_bottom = -8.0
	_object_fields.visible = false
	add_child(_object_fields)

	_object_content = VBoxContainer.new()
	_object_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_object_fields.add_child(_object_content)

	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_object_content.add_child(_info_label)

	var name_row := HBoxContainer.new()
	_object_content.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "Name:"
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Fires on Enter or losing focus, not per keystroke - same reasoning
	# as CreatorSaveLoad's objective field: committing every keystroke
	# would flood the undo stack one entry per character. Zero-arg
	# handler connected to both signals despite text_submitted passing
	# the new text along - reads _name_edit.text directly instead,
	# mirroring CreatorSaveLoad._on_objective_committed() exactly.
	_name_edit.text_submitted.connect(_on_name_committed)
	_name_edit.focus_exited.connect(_on_name_committed)
	name_row.add_child(_name_edit)

	_visible_check = CheckBox.new()
	_visible_check.text = "Visible"
	_visible_check.toggled.connect(_on_visible_toggled)
	_object_content.add_child(_visible_check)

	# Object-only (InteractableEntry.props doesn't exist on TilePlacement/
	# MissionGroup) - a popup rather than inline rows here, requested
	# 2026-09-10: a dynamic add/remove/type-aware list would get cramped
	# in this 260px-wide panel. See PropertiesDialog.gd's own doc comment.
	_properties_button = Button.new()
	_properties_button.text = "Custom Properties…"
	_properties_button.pressed.connect(_on_properties_button_pressed)
	_object_content.add_child(_properties_button)

	_properties_dialog = PropertiesDialog.new()
	_properties_dialog.operation_history = operation_history
	_properties_dialog.layered_map = layered_map
	add_child(_properties_dialog)

	# Object-only, same reasoning as "Custom Properties…" above - what a
	# player can report doing to this prop (InteractableEntry.actions),
	# see PropActionsDialog.gd.
	_actions_button = Button.new()
	_actions_button.text = "Actions…"
	_actions_button.pressed.connect(_on_actions_button_pressed)
	_object_content.add_child(_actions_button)

	_actions_dialog = PropActionsDialog.new()
	_actions_dialog.operation_history = operation_history
	_actions_dialog.layered_map = layered_map
	add_child(_actions_dialog)

	_spawn_tiles_box = VBoxContainer.new()
	_spawn_tiles_box.visible = false
	_object_content.add_child(_spawn_tiles_box)


func _build_multi_fields() -> void:
	_multi_fields = VBoxContainer.new()
	_multi_fields.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_multi_fields.offset_left = 8.0
	_multi_fields.offset_top = 8.0
	_multi_fields.offset_right = -8.0
	_multi_fields.offset_bottom = -8.0
	_multi_fields.visible = false
	add_child(_multi_fields)

	_multi_count_label = Label.new()
	_multi_count_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_multi_fields.add_child(_multi_count_label)

	_multi_group_option = OptionButton.new()
	_multi_fields.add_child(_multi_group_option)

	var move_button := Button.new()
	move_button.text = "Move to Group"
	move_button.pressed.connect(_on_multi_move_button_pressed)
	_multi_fields.add_child(move_button)


func _on_selection_changed(items: Array) -> void:
	if items.size() > 1:
		_show_multi_selection(items)
		return
	if items.is_empty():
		_show_root()
		return
	var meta: Dictionary = items[0]
	if meta["type"] == CreatorOutline.SelectionType.ROOT:
		_show_root()
		return
	_show_single(meta["type"], meta["id"])


func _show_root() -> void:
	_current_node = null
	mission_fields.visible = true
	_object_fields.visible = false
	_multi_fields.visible = false


func _show_single(type: CreatorOutline.SelectionType, id: String) -> void:
	mission_fields.visible = false
	_multi_fields.visible = false
	_object_fields.visible = true
	_current_node = _resolve_node(type, id)

	if _current_node == null:
		# Stale id (shouldn't normally happen - e.g. a rebuild racing this
		# lookup) - show something rather than silently editing nothing.
		_info_label.text = "(not found)"
		_name_edit.editable = false
		_visible_check.disabled = true
		_properties_button.visible = false
		_actions_button.visible = false
		_spawn_tiles_box.visible = false
		return

	_name_edit.editable = true
	_visible_check.disabled = false
	_info_label.text = _describe(type)
	_name_edit.placeholder_text = _fallback_name(type)
	_properties_button.visible = type == CreatorOutline.SelectionType.OBJECT
	_actions_button.visible = type == CreatorOutline.SelectionType.OBJECT
	_rebuild_spawn_tiles(type)

	_suppress_field_signals = true
	_name_edit.text = _current_node.reference_name
	_visible_check.button_pressed = _current_node.visible
	_suppress_field_signals = false


## MonsterSpawn's ordered tile list: "N: (x, y, z)" with up/down (renumbers
## by swapping list positions - the cheap alternative to redrawing tiles to
## insert one in the middle) and remove buttons. Swaps by INDEX, never by
## value.
func _rebuild_spawn_tiles(type: CreatorOutline.SelectionType) -> void:
	for child in _spawn_tiles_box.get_children():
		child.queue_free()
	_spawn_tiles_box.visible = type == CreatorOutline.SelectionType.MONSTER_SPAWN
	if not _spawn_tiles_box.visible:
		return
	var spawn := _current_node as MonsterSpawn
	var header := Label.new()
	header.text = "Tiles (spawn order):"
	_spawn_tiles_box.add_child(header)
	for i in spawn.cells.size():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%d: %s" % [i + 1, FootprintRegistry.format_game_position(FootprintRegistry.tile_square_to_game_position(spawn.cells[i]))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var up := Button.new()
		up.text = "↑"
		up.disabled = i == 0
		up.pressed.connect(_on_spawn_tile_moved.bind(spawn, i, -1))
		row.add_child(up)
		var down := Button.new()
		down.text = "↓"
		down.disabled = i == spawn.cells.size() - 1
		down.pressed.connect(_on_spawn_tile_moved.bind(spawn, i, 1))
		row.add_child(down)
		var remove := Button.new()
		remove.text = "×"
		remove.pressed.connect(_on_spawn_tile_removed.bind(spawn, i))
		row.add_child(remove)
		_spawn_tiles_box.add_child(row)


func _on_spawn_tile_moved(spawn: MonsterSpawn, index: int, delta: int) -> void:
	var target := index + delta
	if target < 0 or target >= spawn.cells.size():
		return
	operation_history.record("Reorder spawn tile", func():
		var tmp := spawn.cells[index]
		spawn.cells[index] = spawn.cells[target]
		spawn.cells[target] = tmp
	)
	layered_map.refresh_monster_spawn_overlay()
	layered_map.notify_objects_changed()


func _on_spawn_tile_removed(spawn: MonsterSpawn, index: int) -> void:
	if index < 0 or index >= spawn.cells.size():
		return
	operation_history.record("Remove spawn tile", func():
		spawn.cells.remove_at(index)
	)
	layered_map.refresh_monster_spawn_overlay()
	layered_map.notify_objects_changed()


## Deliberately minimal - see class doc's "properties view frozen, only the
## add to group action visible" note. `_multi_group_option` doesn't filter
## by is_valid_move_target() the way CreatorOutline's own "Move to..."
## submenu does: with several different source items possibly selected at
## once, a group valid for one might not be for another, and the button
## handler below already skips/warns per-item instead - showing the full
## list here keeps this simple (same "simplest first" tradeoff every other
## per-type widget builder in this project already makes).
func _show_multi_selection(items: Array) -> void:
	mission_fields.visible = false
	_object_fields.visible = false
	_multi_fields.visible = true
	_current_node = null
	_current_multi_selection = items

	_multi_count_label.text = "%d items selected" % items.size()

	_multi_group_option.clear()
	_multi_group_ids.clear()
	_multi_group_option.add_item("(none - root)")
	_multi_group_ids.append("")
	for group in layered_map.mission.groups:
		_multi_group_option.add_item(group.reference_name if group.reference_name != "" else "(unnamed group)")
		_multi_group_ids.append(group.id)


func _on_multi_move_button_pressed() -> void:
	var index := _multi_group_option.get_selected()
	if index < 0 or index >= _multi_group_ids.size():
		return
	var target_group_id: String = _multi_group_ids[index]

	var nodes: Array[OutlineNode] = []
	for item in _current_multi_selection:
		var type: CreatorOutline.SelectionType = item["type"]
		var id: String = item["id"]
		if type == CreatorOutline.SelectionType.ROOT:
			continue
		if not creator_outline.is_valid_move_target(type, id, target_group_id):
			push_warning("Skipping move of '%s' - would create a group cycle" % id)
			continue
		var node := _resolve_node(type, id)
		if node != null:
			nodes.append(node)

	if nodes.is_empty():
		return

	# ONE Operation for the whole batch, not one per item - same "several
	# related edits, one undo step" reasoning CreatorSaveLoad's player-count
	# fields already establish.
	operation_history.record("Move %d item(s) to group" % nodes.size(), func():
		for node in nodes:
			node.parent_id = target_group_id
	)
	layered_map.notify_objects_changed()


func _on_properties_button_pressed() -> void:
	if _current_node is InteractableEntry:
		_properties_dialog.open_for(_current_node as InteractableEntry)


func _on_actions_button_pressed() -> void:
	if _current_node is InteractableEntry:
		_actions_dialog.open_for(_current_node as InteractableEntry)


func _resolve_node(type: CreatorOutline.SelectionType, id: String) -> OutlineNode:
	match type:
		CreatorOutline.SelectionType.OBJECT:
			for entry in layered_map.mission.interactables:
				if entry.id == id:
					return entry
		CreatorOutline.SelectionType.GROUP:
			for group in layered_map.mission.groups:
				if group.id == id:
					return group
		CreatorOutline.SelectionType.TILE:
			for placement in layered_map.mission.floor_placements:
				if placement.layer == TilePlacement.Layer.FLOOR and placement.id == id:
					return placement
			for placement in layered_map.mission.underlay_placements:
				if placement.id == id:
					return placement
		CreatorOutline.SelectionType.MONSTER_SPAWN:
			for spawn in layered_map.mission.monster_spawns:
				if spawn.id == id:
					return spawn
	return null


func _describe(type: CreatorOutline.SelectionType) -> String:
	match type:
		CreatorOutline.SelectionType.OBJECT:
			var entry := _current_node as InteractableEntry
			return "Type: %s\nMesh: %s\nPosition: %s" % [InteractableEntry.Type.keys()[entry.type], entry.mesh_item_name, FootprintRegistry.format_game_position(FootprintRegistry.placed_game_position(entry.origin_cell, entry.footprint))]
		CreatorOutline.SelectionType.TILE:
			var placement := _current_node as TilePlacement
			var label := "Floor tile" if placement.layer == TilePlacement.Layer.FLOOR else "Underlay"
			var grid: GridMap = layered_map.floor_grid if placement.layer == TilePlacement.Layer.FLOOR else layered_map.underlay_grid
			var placement_footprint := FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(placement.mesh_item_name), grid.get_cell_item_basis(placement.origin_cell))
			return "%s\nMesh: %s\nPosition: %s" % [label, placement.mesh_item_name, FootprintRegistry.format_game_position(FootprintRegistry.placed_game_position(placement.origin_cell, placement_footprint))]
		CreatorOutline.SelectionType.MONSTER_SPAWN:
			return "Monster Spawn\n%d tile(s)" % (_current_node as MonsterSpawn).cells.size()
		_:  # GROUP - no mesh/cell/type to show
			return "Group"


## Matches CreatorOutline._add_tile_item()/_create_group_item()'s own
## fallback-when-empty logic exactly, so the placeholder text always shows
## what the tree label would actually read if this field is left blank.
func _fallback_name(type: CreatorOutline.SelectionType) -> String:
	match type:
		CreatorOutline.SelectionType.OBJECT:
			return (_current_node as InteractableEntry).mesh_item_name
		CreatorOutline.SelectionType.TILE:
			return (_current_node as TilePlacement).mesh_item_name
		CreatorOutline.SelectionType.MONSTER_SPAWN:
			return "Monster Spawn"
		_:
			return "(unnamed group)"


func _on_name_committed() -> void:
	if _suppress_field_signals or _current_node == null:
		return
	var new_name := _name_edit.text.strip_edges()
	if new_name == _current_node.reference_name:
		return  # nothing actually changed - don't record a no-op Operation
	var node := _current_node
	operation_history.record("Set name", func():
		node.reference_name = new_name
	)
	layered_map.notify_objects_changed()


func _on_visible_toggled(pressed: bool) -> void:
	if _suppress_field_signals or _current_node == null:
		return
	var node := _current_node
	operation_history.record("Set visible", func():
		node.visible = pressed
	)
	layered_map.notify_objects_changed()
