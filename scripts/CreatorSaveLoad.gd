class_name CreatorSaveLoad
extends PopupMenu

## File menu (New/Save/Load/Back) for the Mission Creator, plus the
## mission-level Objective/player-count fields - those now live in the
## SidePanel's "Outline" tab (see MissionMap.tscn) rather than a
## toolbar row, since the toolbar became this menu bar instead. Attached
## directly to the "File" PopupMenu under the top-spanning MenuBar - items
## are added here in code rather than hand-authored in the .tscn, same
## reasoning as every other runtime-built UI piece in this project
## (CreatorPalette, PlayerDialog, ...): a PopupMenu's item list is fragile
## to hand-write as raw scene text.
##
## Expected scene layout:
##   MenuBar (MenuBar)
##    |- File (PopupMenu, this script)
##        |- MissionFileDialog (FileDialog, Access=User Data, marked as
##            Unique Name %MissionFileDialog)
##   SidePanel/Outline/Split/Inspector/PropertiesFields
##    |- ObjectivesButton (Button, marked as Unique Name %ObjectivesButton) -
##        opens ObjectivesDialog.gd, see that script for the DAG editor
##    |- VariablesButton (Button, marked as Unique Name %VariablesButton) -
##        opens MissionVariablesDialog.gd, see that script for why this
##        exists (without a declared MissionVariable, ANY Condition/Effect
##        referencing that name silently does nothing)
##    |- TriggersButton (Button, marked as Unique Name %TriggersButton) -
##        opens TriggersDialog.gd (the mission's checkpoint/event triggers)
##    |- MinPlayersSpinBox / MaxPlayersSpinBox (SpinBox, marked as Unique
##        Names %MinPlayersSpinBox / %MaxPlayersSpinBox)
##
## Loading a mission for EDITING and loading it for PLAYING turn out to be
## the exact same operation - both just call LayeredMap.apply_mission(),
## which repaints the GridMaps and swaps in the new MissionData. Editing
## then continues normally: CreatorController already keeps whatever
## mission is currently assigned in sync after every paint/erase action.

@export var layered_map: LayeredMap
@export var operation_history: OperationHistory  ## records objective/player-count edits for undo/redo
@export var missions_dir: String = "user://missions"
@export var menu_scene_path: String = "res://ui/MainMenu.tscn"  ## same default MissionPlayer.gd uses

@onready var file_dialog: FileDialog = %MissionFileDialog
@onready var objectives_button: Button = %ObjectivesButton
@onready var variables_button: Button = %VariablesButton
@onready var triggers_button: Button = %TriggersButton
@onready var min_players_spin_box: SpinBox = %MinPlayersSpinBox
@onready var max_players_spin_box: SpinBox = %MaxPlayersSpinBox

const CAMPAIGN_EDITOR_SCENE := "res://ui/CampaignEditor.tscn"

enum FileAction { NEW, SAVE, LOAD, SETTINGS, MONSTER_TEMPLATES, BACK, SAVE_AS, EXPORT_PACKAGE }

## The file the mission in the editor comes from / was last saved to ("" = never saved). Save writes straight to it; Save As asks.
## Also the key of the debug snapshots (see DebugSession) and what a Play hands to the Player.
var current_path: String = ""
## The mission is a RELEASE (frozen, played by saves): it can be looked at and play-tested but not saved - fork it to edit.
var read_only := false
var _leave_dialog: ConfirmationDialog
var _pending_leave: Callable
var _banner: HBoxContainer
var _banner_label: Label

var _settings_dialog: CreatorSettingsDialog
var _monster_template_editor: MonsterTemplateEditor
var _notice_dialog: AcceptDialog
var _export_dialog: PackageExportDialog
var _objectives_dialog: ObjectivesDialog
var _variables_dialog: MissionVariablesDialog
var _characters_dialog: CharactersDialog
var _triggers_dialog: TriggersDialog

## Guards _refresh_player_count_fields() below - setting a SpinBox's
## `value` from code fires `value_changed` exactly like a user click would,
## which would otherwise re-record a (redundant, no-op) Operation every
## time the fields just get refreshed FROM the mission (Load/New/undo/
## redo) rather than actually being edited.
var _suppress_player_count_recording: bool = false


func _ready() -> void:
	# Real accelerators (not just inline text like the View menu's "(O)"/
	# "(N)" hints) - requested 2026-09-10. Safe to bind globally through
	# Godot's own MenuBar-accelerator system here specifically because
	# Ctrl+N/Ctrl+S/Ctrl+O aren't ALSO handled anywhere else (unlike
	# Ctrl+Z or bare O/N, which CreatorController._unhandled_input()
	# already owns - giving those a SECOND, native binding risks firing
	# twice per keypress, so those stay inline-text-only, see
	# CreatorViewMenu.gd/OperationHistory.gd).
	# (KEY_MASK_CMD_OR_CTRL | KEY_N) is a plain int after the bitwise OR - GDScript
	# warns "Integer used when an enum value is expected" for add_item()'s
	# Key-typed accel param without an explicit cast.
	add_item("New", FileAction.NEW, (KEY_MASK_CMD_OR_CTRL | KEY_N) as Key)
	add_item("Save", FileAction.SAVE, (KEY_MASK_CMD_OR_CTRL | KEY_S) as Key)
	add_item("Save As…", FileAction.SAVE_AS, (KEY_MASK_CMD_OR_CTRL | KEY_MASK_SHIFT | KEY_S) as Key)
	add_item("Load", FileAction.LOAD, (KEY_MASK_CMD_OR_CTRL | KEY_O) as Key)
	add_item("Release…", FileAction.EXPORT_PACKAGE)
	add_separator()
	add_item("Monster Templates…", FileAction.MONSTER_TEMPLATES)
	add_item("Settings…", FileAction.SETTINGS)
	add_separator()
	add_item("Back to Menu", FileAction.BACK)
	id_pressed.connect(_on_id_pressed)

	# Autosave settings (requested 2026-09-10) - built once here and
	# reused across opens, same pattern CreatorPropertiesPanel.gd uses for
	# PropertiesDialog.
	_settings_dialog = CreatorSettingsDialog.new()
	add_child(_settings_dialog)

	# The shared library of reusable monster templates (new 2026-10-05) - not
	# part of the mission, so no operation_history/layered_map wiring.
	_monster_template_editor = MonsterTemplateEditor.new()
	_monster_template_editor.layered_map = layered_map
	_monster_template_editor.operation_history = operation_history
	add_child(_monster_template_editor)
	_notice_dialog = AcceptDialog.new()
	add_child(_notice_dialog)
	_export_dialog = PackageExportDialog.new()
	add_child(_export_dialog)

	# Objectives DAG editor (reworked 2026-09-12 from a single LineEdit) -
	# built once here and reused across opens, same pattern as
	# _settings_dialog above and CreatorPropertiesPanel.gd's PropertiesDialog.
	# Edits go straight into layered_map.mission.objectives, so unlike the
	# old LineEdit there's no local widget state to keep synced or flush at
	# Save time - open_for() rebuilds the graph fresh from the mission every
	# time it's opened.
	_objectives_dialog = ObjectivesDialog.new()
	_objectives_dialog.operation_history = operation_history
	_objectives_dialog.layered_map = layered_map
	add_child(_objectives_dialog)
	objectives_button.pressed.connect(_on_objectives_button_pressed)

	# Custom variable declarations (new 2026-09-14) - without one, ANY
	# Condition/Effect referencing that name is silently ignored by
	# MissionRuntime, see MissionVariablesDialog.gd's own doc comment for
	# the real bug report that surfaced this gap. Same built-once-reused
	# pattern as _objectives_dialog above.
	_variables_dialog = MissionVariablesDialog.new()
	_variables_dialog.operation_history = operation_history
	_variables_dialog.layered_map = layered_map
	add_child(_variables_dialog)
	variables_button.pressed.connect(_on_variables_button_pressed)

	# The mission's speakers (voices for [Name]...[/Name] in its texts) - the button is added next to
	# Variables... in code, so the scene file needs no change.
	_characters_dialog = CharactersDialog.new()
	add_child(_characters_dialog)
	var characters_button := Button.new()
	characters_button.text = "Characters…"
	characters_button.tooltip_text = "The named speakers of this mission's messages, with a voice each."
	characters_button.pressed.connect(func():
		_characters_dialog.open_for_list(layered_map.mission.characters, func(label: String, mutate: Callable):
			operation_history.record(label, mutate)
			layered_map.notify_objects_changed()
		)
	)
	variables_button.get_parent().add_child(characters_button)
	variables_button.get_parent().move_child(characters_button, variables_button.get_index() + 1)

	# Triggers (checkpoint/event rules) - same built-once-reused pattern.
	_triggers_dialog = TriggersDialog.new()
	_triggers_dialog.operation_history = operation_history
	_triggers_dialog.layered_map = layered_map
	add_child(_triggers_dialog)
	triggers_button.pressed.connect(func(): _triggers_dialog.open_for(layered_map.mission))

	min_players_spin_box.value_changed.connect(_on_min_players_changed)
	max_players_spin_box.value_changed.connect(_on_max_players_changed)

	# apply_mission() (Load/New, and undo/redo via OperationHistory) swaps
	# in a whole different MissionData and emits this - these fields need
	# to catch up to whatever THAT mission's values are, same as
	# CreatorOutline's tree and CreatorPalette's availability grid already
	# do off this same signal.
	layered_map.mission_objects_changed.connect(_on_mission_objects_changed)

	# Coming back from a debug Play: take the editor's mission (and its undo history and camera) back as it was.
	if GameState.editor_returning:
		_restore_from_play.call_deferred()
	elif GameState.edit_mission_path != "":
		# Opened from the campaign editor's "Edit" button: load that mission, and let Back return there.
		var path := GameState.edit_mission_path
		GameState.edit_mission_path = ""
		_load_from.call_deferred(path)
	if GameState.edit_mission_return_folder != "":
		set_item_text(get_item_index(FileAction.BACK), "Back to Campaign Editor")


func _on_mission_objects_changed() -> void:
	_refresh_player_count_fields()


func _on_objectives_button_pressed() -> void:
	_objectives_dialog.open_for(layered_map.mission)


func _on_variables_button_pressed() -> void:
	_variables_dialog.open_for(layered_map.mission)


func _on_id_pressed(id: int) -> void:
	match id:
		FileAction.NEW:
			_on_new_button_pressed()
		FileAction.SAVE:
			if read_only:
				return
			if current_path != "":
				_save_to(current_path)
			else:
				_on_save_button_pressed()
		FileAction.SAVE_AS:
			_on_save_button_pressed()
		FileAction.LOAD:
			_on_load_button_pressed()
		FileAction.SETTINGS:
			_settings_dialog.open()
		FileAction.EXPORT_PACKAGE:
			if read_only:
				_notice_dialog.dialog_text = "This mission is a release (read-only). Fork it to make a draft, then release that."
				_notice_dialog.popup_centered()
				return
			var mission := layered_map.mission
			var suggested := mission.mission_name if mission.mission_name != "" else current_path.get_file().get_basename()
			_export_dialog.open_mission(mission, suggested, current_path.get_file().get_basename() if current_path != "" else mission.mission_name, current_path)
		FileAction.MONSTER_TEMPLATES:
			_monster_template_editor.open()
		FileAction.BACK:
			_on_back_button_pressed()


func _on_back_button_pressed() -> void:
	_confirm_leave(_leave)


## Runs `go` (leaving the editor) at once when there is nothing to lose; otherwise asks first: save, discard, or stay.
func _confirm_leave(go: Callable) -> void:
	if read_only or not operation_history.is_dirty():
		go.call()
		return
	if _leave_dialog == null:
		_leave_dialog = ConfirmationDialog.new()
		_leave_dialog.title = "Unsaved changes"
		_leave_dialog.add_button("Discard changes", true, "discard")
		_leave_dialog.confirmed.connect(_on_leave_save)
		_leave_dialog.custom_action.connect(func(action: StringName):
			if action == &"discard":
				_leave_dialog.hide()
				_pending_leave.call()
		)
		add_child(_leave_dialog)
	_pending_leave = go
	var file_name := current_path.get_file() if current_path != "" else "This mission"
	_leave_dialog.dialog_text = "%s has changes that are not saved." % file_name
	_leave_dialog.ok_button_text = "Save and leave" if current_path != "" else "Save as…"
	_leave_dialog.cancel_button_text = "Stay"
	_leave_dialog.popup_centered()


func _on_leave_save() -> void:
	if current_path == "":
		_on_save_button_pressed()  # no file yet: choose one, then leave with Back again
		return
	_save_to(current_path)
	if not operation_history.is_dirty():
		_pending_leave.call()


func _leave() -> void:
	if GameState.edit_mission_return_folder != "":
		GameState.campaign_editor_folder = GameState.edit_mission_return_folder
		GameState.edit_mission_return_folder = ""
		get_tree().change_scene_to_file(CAMPAIGN_EDITOR_SCENE)
		return
	get_tree().change_scene_to_file(menu_scene_path)


func _on_save_button_pressed() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_dir = missions_dir
	file_dialog.popup_centered()


func _on_load_button_pressed() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.current_dir = missions_dir
	file_dialog.popup_centered()


func _on_new_button_pressed() -> void:
	# Reuses apply_mission() with a blank MissionData - same repaint-to-
	# empty logic as loading, just with nothing in it. Lets you start a
	# second/third mission without restarting the whole scene.
	# apply_mission() emits mission_objects_changed, which
	# _on_mission_objects_changed() above already turns into a field
	# refresh - no need to call it explicitly here too.
	current_path = ""
	_update_read_only()
	layered_map.reset_editor_view()
	layered_map.apply_mission(MissionData.new())
	operation_history.mark_saved()


func _on_mission_file_dialog_file_selected(path: String) -> void:
	if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		_save_to(path)
	else:
		_load_from(path)


func _save_to(path: String) -> void:
	if not CommunityLibrary.entry_for_path(path).is_empty():
		_notice_dialog.dialog_text = "That file is a release and is never changed. Save under another name, or fork it."
		_notice_dialog.popup_centered()
		return
	if layered_map.mission.mission_name == "":
		layered_map.mission.mission_name = path.get_file().get_basename()
	# Player-count fields are live-synced (see _on_min_players_changed()
	# etc. below) - by the time Save runs, the mission should already
	# reflect whatever's in these widgets. Calling this again is a
	# redundant but harmless safety net for the one edge case where it
	# isn't: a value typed but never committed before Save was clicked.
	# Objectives no longer need an equivalent call - ObjectivesDialog edits
	# layered_map.mission.objectives directly, there's no local widget
	# state that could be sitting uncommitted.
	_apply_player_count_fields()
	if MissionIO.save_mission(layered_map.mission, path):
		operation_history.mark_saved()
	current_path = path
	_update_read_only()


## Read-only mode follows the file: a release (CommunityLibrary registry) is frozen.
func _update_read_only() -> void:
	var entry := CommunityLibrary.entry_for_path(current_path) if current_path != "" else {}
	read_only = not entry.is_empty()
	set_item_disabled(get_item_index(FileAction.SAVE), read_only)
	set_item_disabled(get_item_index(FileAction.EXPORT_PACKAGE), read_only)
	var scene := get_tree().current_scene
	var controller := scene.get_node_or_null("CreatorController") if scene != null else null
	if controller != null:
		controller.set_process_unhandled_input(not read_only)
		if read_only:
			controller.set_draw_mode(false)
	if read_only and _banner == null:
		var toolbar := scene.find_child("Toolbar", true, false) if scene != null else null
		if toolbar != null:
			_banner = HBoxContainer.new()
			_banner_label = Label.new()
			_banner_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
			_banner.add_child(_banner_label)
			var fork_button := Button.new()
			fork_button.text = "Fork to edit"
			fork_button.pressed.connect(_on_fork_pressed)
			_banner.add_child(fork_button)
			toolbar.add_child(_banner)
	if _banner != null:
		_banner.visible = read_only
		if read_only:
			_banner_label.text = "Release v%s - read-only   " % str(entry.get("version", "?"))


func _on_fork_pressed() -> void:
	var new_name := CommunityLibrary.strip_version_suffix(layered_map.mission.mission_name)
	var path := CommunityLibrary.fork_mission(current_path, new_name if new_name != "" else "mission")
	if path == "":
		_notice_dialog.dialog_text = "The mission could not be forked."
		_notice_dialog.popup_centered()
		return
	_load_from(path)
	_notice_dialog.dialog_text = "Forked to %s - this is your own draft now." % path
	_notice_dialog.popup_centered()


## Starts the Player on the mission as it is in the editor now, as a debug session (see DebugSession): the mission is handed
## over in memory (nothing is saved), `snapshot_slot` = a slot to load onto it ("" = a fresh start). The Creator scene is freed
## meanwhile, so everything it needs back - the mission, its path, the undo history, the camera - waits in GameState.
func start_play(snapshot_slot: String) -> void:
	_apply_player_count_fields()
	GameState.clear_campaign()
	GameState.editor_mission = layered_map.mission
	GameState.editor_mission_path = current_path
	GameState.editor_history = operation_history.export_state()
	var camera := layered_map.get_viewport().get_camera_3d() as FreeLookCamera
	GameState.editor_view = camera.export_view() if camera != null else {}
	GameState.editor_returning = false
	GameState.debug_session = true
	GameState.current_mission_path = current_path
	GameState.load_save_path = ""
	if snapshot_slot != "":
		GameState.load_save_path = DebugSession.slot_path(DebugSession.mission_key(layered_map.mission, current_path), snapshot_slot)
	get_tree().change_scene_to_file(GameState.PLAYER_SCENE)


func _restore_from_play() -> void:
	var mission := GameState.editor_mission
	if mission != null:
		layered_map.apply_mission(mission)
		current_path = GameState.editor_mission_path
		_update_read_only()
		operation_history.import_state(GameState.editor_history)
		var camera := layered_map.get_viewport().get_camera_3d() as FreeLookCamera
		if camera != null:
			camera.import_view(GameState.editor_view)
	GameState.clear_debug()


func _load_from(path: String) -> void:
	var loaded := MissionIO.load_mission(path)
	if loaded == null:
		return
	current_path = path
	_update_read_only()
	# Bring the monster templates attached in this mission up to date with the
	# library first (the library is the source of truth while editing; a copy
	# whose library entry is gone is left alone).
	var updated := 0 if read_only else MonsterArchetypeLibrary.sync_mission(loaded)
	# apply_mission() emits mission_objects_changed, which
	# _on_mission_objects_changed() above already turns into a field
	# refresh - no need to call it explicitly here too.
	layered_map.reset_editor_view()
	layered_map.apply_mission(loaded)
	operation_history.mark_saved()
	if updated > 0:
		operation_history.mark_dirty()
		_notice_dialog.dialog_text = "Updated %d monster template(s) in this mission from the library. Save the mission to keep the update." % updated
		_notice_dialog.popup_centered()


## Live-synced (2026-09-10, for undo/redo - see OperationHistory.gd). Each
## SpinBox's own value_changed already fires per click/drag/type, so no
## extra debouncing needed here beyond OperationHistory's own melding
## (repeated clicks on the SAME field within its meld window become one
## Operation, per the user's own "pressing the button 6 times" example).
## min_value/max_value on the fields already clamp to SpinBox's own 1-6
## range in the editor, but min<=max isn't something a SpinBox can enforce
## against ANOTHER SpinBox on its own, so that's checked here too - setting
## max_players_spin_box.value below fires ITS OWN value_changed in turn,
## which OperationHistory.record()'s reentrancy handling folds into this
## same Operation rather than recording a second one.
func _on_min_players_changed(_value: float) -> void:
	if _suppress_player_count_recording:
		return
	operation_history.record("Set min players", _apply_player_count_fields)


func _on_max_players_changed(_value: float) -> void:
	if _suppress_player_count_recording:
		return
	operation_history.record("Set max players", _apply_player_count_fields)


func _apply_player_count_fields() -> void:
	var min_players := int(min_players_spin_box.value)
	var max_players := int(max_players_spin_box.value)
	if min_players > max_players:
		max_players = min_players
		max_players_spin_box.value = max_players
	layered_map.mission.min_players = min_players
	layered_map.mission.max_players = max_players


func _refresh_player_count_fields() -> void:
	_suppress_player_count_recording = true
	min_players_spin_box.value = layered_map.mission.min_players
	max_players_spin_box.value = layered_map.mission.max_players
	_suppress_player_count_recording = false
