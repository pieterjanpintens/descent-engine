class_name CreatorPropertiesPanel
extends Control

## Owns the SidePanel/Outline tab's lower half (the Inspector) - switches
## between the existing mission-level fields (Objective/player count,
## still fully owned/read-written by CreatorSaveLoad.gd at Save/Load/New
## time, completely unchanged - this script only ever toggles their
## visibility, never their values) and a minimal read-only placeholder
## describing whatever object/group is selected in CreatorOutline above
## it. Real property EDITING for objects/groups is a later pass
## (deferred by the user's own words: "modify their properties in a later
## stage") - this is just enough to confirm what's currently selected.
##
## Talks to CreatorOutline ONLY through its public `selected` signal - see
## CreatorPalette.gd's own doc comment for why (keeps this script and
## CreatorOutline from ever drifting out of sync with each other's
## internal state).

@export var creator_outline: CreatorOutline
@export var layered_map: LayeredMap
@export var mission_fields: Control  ## the existing PropertiesFields node

var _placeholder_label: Label


func _ready() -> void:
	_placeholder_label = Label.new()
	_placeholder_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_placeholder_label.offset_left = 8.0
	_placeholder_label.offset_top = 8.0
	_placeholder_label.offset_right = -8.0
	_placeholder_label.offset_bottom = -8.0
	_placeholder_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_placeholder_label.visible = false
	add_child(_placeholder_label)

	creator_outline.selected.connect(_on_outline_selected)


func _on_outline_selected(type: CreatorOutline.SelectionType, id: String) -> void:
	match type:
		CreatorOutline.SelectionType.ROOT:
			mission_fields.visible = true
			_placeholder_label.visible = false
		CreatorOutline.SelectionType.GROUP:
			_show_placeholder(_describe_group(id))
		CreatorOutline.SelectionType.OBJECT:
			_show_placeholder(_describe_object(id))
		CreatorOutline.SelectionType.TILE:
			_show_placeholder(_describe_tile(id))


func _show_placeholder(text: String) -> void:
	mission_fields.visible = false
	_placeholder_label.text = text
	_placeholder_label.visible = true


func _describe_group(id: String) -> String:
	for group in layered_map.mission.groups:
		if group.id == id:
			var display_name := group.reference_name if group.reference_name != "" else "(unnamed group)"
			return "Group: %s\nVisible: %s\n\n(property editing coming later)" % [display_name, group.visible]
	return ""


func _describe_object(id: String) -> String:
	for entry in layered_map.mission.interactables:
		if entry.id == id:
			var display_name := entry.reference_name if entry.reference_name != "" else entry.mesh_item_name
			var type_name: String = InteractableEntry.Type.keys()[entry.type]
			return "Object: %s\nType: %s\nCell: %s\nVisible: %s\n\n(property editing coming later)" % [display_name, type_name, entry.origin_cell, entry.visible]
	return ""


func _describe_tile(id: String) -> String:
	for placement in layered_map.mission.floor_placements:
		if placement.layer == TilePlacement.Layer.FLOOR and placement.id == id:
			return _describe_tile_placement("Floor tile", placement)
	for placement in layered_map.mission.underlay_placements:
		if placement.id == id:
			return _describe_tile_placement("Underlay", placement)
	return ""


func _describe_tile_placement(label: String, placement: TilePlacement) -> String:
	var display_name := placement.reference_name if placement.reference_name != "" else placement.mesh_item_name
	return "%s: %s\nCell: %s\nVisible: %s\n\n(property editing coming later)" % [label, display_name, placement.origin_cell, placement.visible]
