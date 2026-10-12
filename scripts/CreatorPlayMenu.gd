class_name CreatorPlayMenu
extends PopupMenu

## "Play" menu of the Creator (MenuBar/Play): test the mission you are editing without saving it first.
##  - Play: starts the Player on the editor's mission as it is now (unsaved tweaks included; the file is not touched).
##  - Play from snapshot: starts the Player and loads a snapshot onto the mission as it is now - the progress of the
##    snapshot (what was revealed, fired, used, the variables, the monsters...) on your edited definition.
## In the Player: F9 takes a snapshot, F10 rolls back to it, Ctrl+E returns here with everything as you left it.
## See DebugSession / MissionProgress for the mechanism.

@export var layered_map: LayeredMap
@export var save_load: CreatorSaveLoad  ## the File menu - it owns the mission's file path and starts the Player

enum Action { PLAY, FAST_START, FORGET_PARTY }

var _snapshots: PopupMenu


func _ready() -> void:
	add_item("Play", Action.PLAY, (KEY_MASK_CMD_OR_CTRL | KEY_ENTER) as Key)
	_snapshots = PopupMenu.new()
	_snapshots.name = "Snapshots"
	add_child(_snapshots)
	add_submenu_node_item("Play from snapshot", _snapshots)
	add_separator()
	add_check_item("Fast start (skip setup dialogs and banners)", Action.FAST_START)
	add_item("Forget the remembered party", Action.FORGET_PARTY)
	id_pressed.connect(_on_id_pressed)
	_snapshots.index_pressed.connect(_on_snapshot_chosen)
	about_to_popup.connect(_refresh)


func _refresh() -> void:
	set_item_checked(get_item_index(Action.FAST_START), DebugSession.fast())
	_snapshots.clear()
	var key := _key()
	for slot in DebugSession.SLOTS:
		_snapshots.add_item(DebugSession.slot_label(key, slot))
		_snapshots.set_item_disabled(_snapshots.item_count - 1, not DebugSession.slot_exists(key, slot))


func _key() -> String:
	return DebugSession.mission_key(layered_map.mission, save_load.current_path)


func _on_id_pressed(id: int) -> void:
	match id:
		Action.PLAY:
			save_load.start_play("")
		Action.FAST_START:
			DebugSession.set_fast(not DebugSession.fast())
		Action.FORGET_PARTY:
			DebugSession.forget_party()


func _on_snapshot_chosen(index: int) -> void:
	save_load.start_play(DebugSession.SLOTS[index])
