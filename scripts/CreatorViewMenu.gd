extends PopupMenu

## "View" menu - attached to `MenuBar/View`, sibling of `MenuBar/File`
## (`CreatorSaveLoad.gd`) and `MenuBar/Edit` (`OperationHistory.gd`).
## Requested 2026-09-10: `O`/`N` were keyboard-only "magic" toggles with
## no visible UI anywhere. The hotkeys still work exactly as before -
## `CreatorController._unhandled_input()` still handles them directly -
## this menu is just a second, discoverable way to reach the SAME
## `set_occupancy_overlay()`/`set_tile_labels()` methods, kept in sync via
## `CreatorController.occupancy_overlay_changed`/`tile_labels_changed` so
## whichever path toggles a setting, the checkmark here always matches -
## same "controller emits, UI listens" convention as every other Creator
## UI piece.

@export var creator_controller: CreatorController

enum _ViewAction { OCCUPANCY_OVERLAY, TILE_LABELS }

var _occupancy_item_index: int
var _tile_labels_item_index: int


func _ready() -> void:
	add_check_item("Occupancy Overlay (O)", _ViewAction.OCCUPANCY_OVERLAY)
	_occupancy_item_index = get_item_index(_ViewAction.OCCUPANCY_OVERLAY)
	add_check_item("Tile Name Labels (N)", _ViewAction.TILE_LABELS)
	_tile_labels_item_index = get_item_index(_ViewAction.TILE_LABELS)

	id_pressed.connect(_on_id_pressed)
	creator_controller.occupancy_overlay_changed.connect(_on_occupancy_overlay_changed)
	creator_controller.tile_labels_changed.connect(_on_tile_labels_changed)

	set_item_checked(_occupancy_item_index, creator_controller.show_occupancy_overlay)
	set_item_checked(_tile_labels_item_index, creator_controller.show_tile_labels)


func _on_id_pressed(id: int) -> void:
	match id:
		_ViewAction.OCCUPANCY_OVERLAY:
			creator_controller.set_occupancy_overlay(not creator_controller.show_occupancy_overlay)
		_ViewAction.TILE_LABELS:
			creator_controller.set_tile_labels(not creator_controller.show_tile_labels)


func _on_occupancy_overlay_changed(enabled: bool) -> void:
	set_item_checked(_occupancy_item_index, enabled)


func _on_tile_labels_changed(enabled: bool) -> void:
	set_item_checked(_tile_labels_item_index, enabled)
