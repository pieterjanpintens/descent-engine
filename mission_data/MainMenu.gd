extends Control

## Root script for the main menu scene. Expected scene layout (see
## accompanying setup instructions):
##   MainMenu (Control, this script)
##    |- ...buttons for Play / Editor / Exit...
##    |- MissionFileDialog (FileDialog, marked as Unique Name %MissionFileDialog)

@export var editor_scene_path: String = "res://map/MissionMap.tscn"   ## <<< set to your actual Creator/editor scene
@export var player_scene_path: String = "res://player/MissionPlayer.tscn"  ## <<< set to your actual Player scene

@onready var mission_dialog: FileDialog = %MissionFileDialog


func _on_play_button_pressed() -> void:
	mission_dialog.popup_centered()


func _on_editor_button_pressed() -> void:
	get_tree().change_scene_to_file(editor_scene_path)


func _on_exit_button_pressed() -> void:
	get_tree().quit()


func _on_mission_file_dialog_file_selected(path: String) -> void:
	GameState.current_mission_path = path
	get_tree().change_scene_to_file(player_scene_path)
