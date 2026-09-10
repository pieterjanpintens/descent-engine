extends Control

## Save/Load/New/Back UI for the Mission Creator. Expected scene layout:
##   CreatorSaveLoad (Control, this script)
##    |- ...Back/New/Save/Load buttons...
##    |- ObjectiveLineEdit (LineEdit, marked as Unique Name %ObjectiveLineEdit)
##    |- MinPlayersSpinBox / MaxPlayersSpinBox (SpinBox, marked as Unique
##        Names %MinPlayersSpinBox / %MaxPlayersSpinBox)
##    |- MissionFileDialog (FileDialog, Access=Resources, marked as
##        Unique Name %MissionFileDialog)
##
## Loading a mission for EDITING and loading it for PLAYING turn out to be
## the exact same operation - both just call LayeredMap.apply_mission(),
## which repaints the GridMaps and swaps in the new MissionData. Editing
## then continues normally: CreatorController already keeps whatever
## mission is currently assigned in sync after every paint/erase action.

@export var layered_map: LayeredMap
@export var missions_dir: String = "res://missions"
@export var menu_scene_path: String = "res://ui/MainMenu.tscn"  ## same default MissionPlayer.gd uses

@onready var file_dialog: FileDialog = %MissionFileDialog
@onready var objective_line_edit: LineEdit = %ObjectiveLineEdit
@onready var min_players_spin_box: SpinBox = %MinPlayersSpinBox
@onready var max_players_spin_box: SpinBox = %MaxPlayersSpinBox


## The .tscn had this row's width hardcoded (offset_right = 1144) from
## before the objective/player-count fields existed - once those got added
## the row's actual content outgrew that fixed box and started overlapping
## CreatorPalette's right-anchored panel. Quick fix, not the real one: pin
## the right edge to CreatorPalette.PANEL_WIDTH from the screen's own right
## edge (not a duplicated magic number) so this row can never overlap the
## palette regardless of window size or how many more fields get added
## here later - doesn't fix the row itself potentially getting cramped
## with too many fields, that's a real redesign, not today's problem.
func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_right = -CreatorPalette.PANEL_WIDTH


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
	layered_map.apply_mission(MissionData.new())
	_refresh_objective_field()
	_refresh_player_count_fields()


func _on_mission_file_dialog_file_selected(path: String) -> void:
	if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		_save_to(path)
	else:
		_load_from(path)


func _save_to(path: String) -> void:
	if layered_map.mission.mission_name == "":
		layered_map.mission.mission_name = path.get_file().get_basename()
	_apply_objective_field()
	_apply_player_count_fields()
	MissionIO.save_mission(layered_map.mission, path)


func _load_from(path: String) -> void:
	var loaded := MissionIO.load_mission(path)
	if loaded == null:
		return
	layered_map.apply_mission(loaded)
	_refresh_objective_field()
	_refresh_player_count_fields()


## Only ONE objective field for now (the final win objective's
## description) - just enough to show something in the Player, not a real
## objectives/conditions editor yet (see claude.md's Story layer section).
## Deliberately only reads the field at save time rather than live-syncing
## on every keystroke - simpler, and the mission doesn't need to be correct
## until it's actually saved.
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


## Same "only read at save time" reasoning as the objective field above.
## min_value/max_value on the fields already clamp to SpinBox's own 1-6
## range in the editor, but min<=max isn't something a SpinBox can enforce
## against ANOTHER SpinBox on its own, so that's checked here too.
func _apply_player_count_fields() -> void:
	var min_players := int(min_players_spin_box.value)
	var max_players := int(max_players_spin_box.value)
	if min_players > max_players:
		max_players = min_players
		max_players_spin_box.value = max_players
	layered_map.mission.min_players = min_players
	layered_map.mission.max_players = max_players


func _refresh_player_count_fields() -> void:
	min_players_spin_box.value = layered_map.mission.min_players
	max_players_spin_box.value = layered_map.mission.max_players
