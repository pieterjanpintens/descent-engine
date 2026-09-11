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
##    |- ObjectiveLineEdit (LineEdit, marked as Unique Name %ObjectiveLineEdit)
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
@onready var objective_line_edit: LineEdit = %ObjectiveLineEdit
@onready var min_players_spin_box: SpinBox = %MinPlayersSpinBox
@onready var max_players_spin_box: SpinBox = %MaxPlayersSpinBox

enum FileAction { NEW, SAVE, LOAD, SETTINGS, BACK }

var _settings_dialog: CreatorSettingsDialog

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
	add_item("New", FileAction.NEW, KEY_MASK_CTRL | KEY_N)
	add_item("Save", FileAction.SAVE, KEY_MASK_CTRL | KEY_S)
	add_item("Load", FileAction.LOAD, KEY_MASK_CTRL | KEY_O)
	add_separator()
	add_item("Settings…", FileAction.SETTINGS)
	add_separator()
	add_item("Back to Menu", FileAction.BACK)
	id_pressed.connect(_on_id_pressed)

	# Autosave settings (requested 2026-09-10) - built once here and
	# reused across opens, same pattern CreatorPropertiesPanel.gd uses for
	# PropertiesDialog.
	_settings_dialog = CreatorSettingsDialog.new()
	add_child(_settings_dialog)

	min_players_spin_box.value_changed.connect(_on_min_players_changed)
	max_players_spin_box.value_changed.connect(_on_max_players_changed)
	objective_line_edit.text_submitted.connect(_on_objective_committed)
	objective_line_edit.focus_exited.connect(_on_objective_committed)

	# apply_mission() (Load/New, and undo/redo via OperationHistory) swaps
	# in a whole different MissionData and emits this - these fields need
	# to catch up to whatever THAT mission's values are, same as
	# CreatorOutline's tree and CreatorPalette's availability grid already
	# do off this same signal.
	layered_map.mission_objects_changed.connect(_on_mission_objects_changed)


func _on_mission_objects_changed() -> void:
	_refresh_objective_field()
	_refresh_player_count_fields()


func _on_id_pressed(id: int) -> void:
	match id:
		FileAction.NEW:
			_on_new_button_pressed()
		FileAction.SAVE:
			_on_save_button_pressed()
		FileAction.LOAD:
			_on_load_button_pressed()
		FileAction.SETTINGS:
			_settings_dialog.open()
		FileAction.BACK:
			_on_back_button_pressed()


func _on_back_button_pressed() -> void:
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
	layered_map.apply_mission(MissionData.new())


func _on_mission_file_dialog_file_selected(path: String) -> void:
	if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		_save_to(path)
	else:
		_load_from(path)


func _save_to(path: String) -> void:
	if layered_map.mission.mission_name == "":
		layered_map.mission.mission_name = path.get_file().get_basename()
	# The objective/player-count fields are live-synced now (see
	# _on_min_players_changed() etc. below) - by the time Save runs, the
	# mission should already reflect whatever's in these widgets. Calling
	# these again is a redundant but harmless safety net for the one edge
	# case where it isn't: text typed into the objective field that never
	# got committed (Enter / losing focus) before Save was clicked.
	_apply_objective_field()
	_apply_player_count_fields()
	MissionIO.save_mission(layered_map.mission, path)


func _load_from(path: String) -> void:
	var loaded := MissionIO.load_mission(path)
	if loaded == null:
		return
	# apply_mission() emits mission_objects_changed, which
	# _on_mission_objects_changed() above already turns into a field
	# refresh - no need to call it explicitly here too.
	layered_map.apply_mission(loaded)


## Fires on Enter (text_submitted) or losing focus (focus_exited) -
## committing per-KEYSTROKE would flood the undo stack with one operation
## per character, so this waits for the user to actually finish an edit.
## Doesn't check whether the text actually changed before recording - a
## submit/focus-loss with no real change just records a no-op Operation,
## harmless (it'll just meld with or get skipped by undo like any other).
func _on_objective_committed() -> void:
	operation_history.record("Edit objective", _apply_objective_field)


## Only ONE objective field for now (the final win objective's
## description) - just enough to show something in the Player, not a real
## objectives/conditions editor yet (see claude.md's Story layer section).
func _apply_objective_field() -> void:
	var description := objective_line_edit.text
	var win_objective := _find_win_objective()
	if win_objective != null:
		win_objective.description = description
		return
	if description == "":
		return  # nothing typed, nothing to create
	var objective := MissionObjective.new()
	objective.id = "final_objective"
	objective.outcome = MissionObjective.Outcome.WIN
	objective.checkpoint = RoundCheckpoint.Checkpoint.AFTER_DARKNESS_PHASE
	objective.description = description
	layered_map.mission.objectives.append(objective)


func _refresh_objective_field() -> void:
	var win_objective := _find_win_objective()
	objective_line_edit.text = win_objective.description if win_objective != null else ""


func _find_win_objective() -> MissionObjective:
	for objective in layered_map.mission.objectives:
		if objective.outcome == MissionObjective.Outcome.WIN:
			return objective
	return null


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
