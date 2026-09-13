class_name CreatorToolbar
extends HBoxContainer

## The Creator's persistent toolbar - sits directly under the MenuBar (see
## MissionMap.tscn's MainLayout), full width, so its controls stay
## reachable regardless of which SidePanel tab (Palette/Outline) is
## currently active. Requested 2026-09-14 to fix exactly that friction:
## "Working group" used to live inside the Outline tab (had to switch away
## from Palette - where you're actually drawing - just to change it), and
## "Show unavailable" used to live inside the Palette's own mesh grid
## (invisible while browsing the Outline tab).
##
## Built entirely in code in _ready(), same pattern as every other
## dynamic Creator UI piece (CreatorPalette, PropertiesDialog, ...).
## `_rebuild_working_group_option()` duplicates the same small "Root +
## groups" list-building loop CreatorOutline.gd's own three near-identical
## builders (the "Move to..." submenu, and CreatorPropertiesPanel.gd's
## batch-move dropdown) already use, rather than sharing it - matches this
## project's established convention of each UI piece owning its own
## near-identical widget-building code.
##
## Talks to CreatorController ONLY through its public API/signals -
## working_group_id/set_working_group()/working_group_changed and
## show_unavailable_meshes/set_show_unavailable_meshes()/
## show_unavailable_meshes_changed - same "controller emits, UI listens"
## convention as CreatorPalette.

@export var creator_controller: CreatorController
@export var layered_map: LayeredMap

var _working_group_option: OptionButton
var _working_group_ids: Array[String] = []  # parallel to _working_group_option's items, same pattern as CreatorOutline's own _move_to_target_ids

var _rebuild_queued: bool = false


func _ready() -> void:
	# Let CreatorController's/LayeredMap's own @onready/_ready finish first -
	# same order-independence trick used throughout this project, see
	# CLAUDE.md's "Hard-won lessons".
	await get_tree().process_frame

	_build_ui()

	creator_controller.working_group_changed.connect(_on_working_group_changed)
	layered_map.mission_objects_changed.connect(_queue_working_group_option_rebuild)
	_rebuild_working_group_option()


func _build_ui() -> void:
	var group_label := Label.new()
	group_label.text = "Working group:"
	add_child(group_label)

	_working_group_option = OptionButton.new()
	_working_group_option.item_selected.connect(_on_working_group_option_selected)
	add_child(_working_group_option)

	# Pushes "Show unavailable" to the right - a plain expand-filling
	# spacer, same trick used for centering rows elsewhere in this project.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer)

	var show_unavailable_check := CheckBox.new()
	show_unavailable_check.text = "Show unavailable (click to locate)"
	show_unavailable_check.button_pressed = creator_controller.show_unavailable_meshes
	show_unavailable_check.toggled.connect(creator_controller.set_show_unavailable_meshes)
	add_child(show_unavailable_check)


## Coalesces rapid repeated triggers (mission_objects_changed can fire once
## per painted cell during a fast drag stroke) into a single deferred
## rebuild - same pattern as CreatorOutline.gd's refresh()/_do_refresh().
func _queue_working_group_option_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild_working_group_option.call_deferred()


## "(none - root)" + every mission.groups entry, flat (no nesting
## indentation - matches CreatorOutline's own "Root + groups" list
## builders' precedent). Re-selects whatever creator_controller.
## working_group_id currently is; resets it if that id no longer exists
## (shouldn't normally happen outside CreatorOutline._delete_group()'s own
## reset, but stays consistent rather than silently keeping a dangling id).
func _rebuild_working_group_option() -> void:
	_rebuild_queued = false
	_working_group_option.clear()
	_working_group_ids.clear()

	_working_group_option.add_item("(none - root)")
	_working_group_ids.append("")

	var mission := layered_map.mission
	if mission != null:
		for group in mission.groups:
			_working_group_option.add_item(group.reference_name if group.reference_name != "" else "(unnamed group)")
			_working_group_ids.append(group.id)

	var current_index := _working_group_ids.find(creator_controller.working_group_id)
	if current_index == -1:
		creator_controller.set_working_group("")
		current_index = 0
	_working_group_option.select(current_index)


func _on_working_group_option_selected(index: int) -> void:
	if index < 0 or index >= _working_group_ids.size():
		return
	creator_controller.set_working_group(_working_group_ids[index])


## Keeps the dropdown's own selection in sync regardless of what triggered
## the change (a pick here, or a reset from CreatorOutline._delete_group()) -
## cheap enough to just re-select rather than rely on
## mission_objects_changed's own refresh pipeline to happen to cover every
## path that could call set_working_group().
func _on_working_group_changed(group_id: String) -> void:
	var index := _working_group_ids.find(group_id)
	_working_group_option.select(index if index != -1 else 0)
