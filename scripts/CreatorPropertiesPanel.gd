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
## three separate per-type implementations. Deeper per-type property
## editing (InteractableEntry.actions/props, LEVEL_LINK fields, ...) is
## still a later pass.
##
## Talks to CreatorOutline ONLY through its public `selected` signal - see
## CreatorPalette.gd's own doc comment for why (keeps this script and
## CreatorOutline from ever drifting out of sync with each other's
## internal state). Refreshing the form after some OTHER path edits the
## same node (the tree's own inline group rename, an undo/redo, a
## world-click pick) falls out of that same signal for free:
## CreatorOutline re-emits `selected` for whatever's currently selected
## every time it rebuilds (see that script's `_rebuild_tree()`), not just
## on an actual selection change - so this form is never stale for more
## than one rebuild.

@export var creator_outline: CreatorOutline
@export var layered_map: LayeredMap
@export var operation_history: OperationHistory  ## records name/visible edits for undo/redo
@export var mission_fields: Control  ## the existing PropertiesFields node

var _object_fields: VBoxContainer
var _info_label: Label
var _name_edit: LineEdit
var _visible_check: CheckBox
var _properties_button: Button
var _properties_dialog: PropertiesDialog

## Whichever OutlineNode is currently shown (InteractableEntry/
## TilePlacement/MissionGroup all extend it) - null while ROOT is
## selected, since MissionData itself isn't one. Editing reference_name/
## visible below writes straight to THIS object regardless of its
## concrete type - the whole point of pulling those fields up to
## OutlineNode was to not need type-specific edit logic here.
var _current_node: OutlineNode

## Guards the field-refresh path (_on_outline_selected() setting
## _name_edit.text/_visible_check.button_pressed FROM data) from being
## mistaken for a user edit and looping back into a record() call.
var _suppress_field_signals: bool = false


func _ready() -> void:
	_build_object_fields()
	creator_outline.selected.connect(_on_outline_selected)


func _build_object_fields() -> void:
	_object_fields = VBoxContainer.new()
	_object_fields.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_object_fields.offset_left = 8.0
	_object_fields.offset_top = 8.0
	_object_fields.offset_right = -8.0
	_object_fields.offset_bottom = -8.0
	_object_fields.visible = false
	add_child(_object_fields)

	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_object_fields.add_child(_info_label)

	var name_row := HBoxContainer.new()
	_object_fields.add_child(name_row)
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
	_object_fields.add_child(_visible_check)

	# Object-only (InteractableEntry.props doesn't exist on TilePlacement/
	# MissionGroup) - a popup rather than inline rows here, requested
	# 2026-09-10: a dynamic add/remove/type-aware list would get cramped
	# in this 260px-wide panel. See PropertiesDialog.gd's own doc comment.
	_properties_button = Button.new()
	_properties_button.text = "Custom Properties…"
	_properties_button.pressed.connect(_on_properties_button_pressed)
	_object_fields.add_child(_properties_button)

	_properties_dialog = PropertiesDialog.new()
	_properties_dialog.operation_history = operation_history
	_properties_dialog.layered_map = layered_map
	add_child(_properties_dialog)


func _on_outline_selected(type: CreatorOutline.SelectionType, id: String) -> void:
	if type == CreatorOutline.SelectionType.ROOT:
		_current_node = null
		mission_fields.visible = true
		_object_fields.visible = false
		return

	mission_fields.visible = false
	_object_fields.visible = true
	_current_node = _resolve_node(type, id)

	if _current_node == null:
		# Stale id (shouldn't normally happen - e.g. a rebuild racing this
		# lookup) - show something rather than silently editing nothing.
		_info_label.text = "(not found)"
		_name_edit.editable = false
		_visible_check.disabled = true
		_properties_button.visible = false
		return

	_name_edit.editable = true
	_visible_check.disabled = false
	_info_label.text = _describe(type)
	_name_edit.placeholder_text = _fallback_name(type)
	_properties_button.visible = type == CreatorOutline.SelectionType.OBJECT

	_suppress_field_signals = true
	_name_edit.text = _current_node.reference_name
	_visible_check.button_pressed = _current_node.visible
	_suppress_field_signals = false


func _on_properties_button_pressed() -> void:
	if _current_node is InteractableEntry:
		_properties_dialog.open_for(_current_node as InteractableEntry)


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
	return null


func _describe(type: CreatorOutline.SelectionType) -> String:
	match type:
		CreatorOutline.SelectionType.OBJECT:
			var entry := _current_node as InteractableEntry
			return "Type: %s\nMesh: %s\nCell: %s" % [InteractableEntry.Type.keys()[entry.type], entry.mesh_item_name, entry.origin_cell]
		CreatorOutline.SelectionType.TILE:
			var placement := _current_node as TilePlacement
			var label := "Floor tile" if placement.layer == TilePlacement.Layer.FLOOR else "Underlay"
			return "%s\nMesh: %s\nCell: %s" % [label, placement.mesh_item_name, placement.origin_cell]
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
