extends Control

## Root script for the main menu scene. Expected scene layout (see
## accompanying setup instructions):
##   MainMenu (Control, this script)
##    |- ...buttons for Play / Editor / Exit...
##    |- MissionFileDialog (FileDialog, marked as Unique Name %MissionFileDialog)

@export var editor_scene_path: String = "res://map/MissionMap.tscn"   ## <<< set to your actual Creator/editor scene
@export var player_scene_path: String = "res://player/MissionPlayer.tscn"  ## <<< set to your actual Player scene

@onready var mission_dialog: FileDialog = %MissionFileDialog
@onready var save_dialog: FileDialog = %SaveFileDialog


## FileDialog.root_subfolder errors ("must be an existing sub-directory") if
## the folder doesn't exist yet - true on a genuinely fresh install (no
## mission ever saved, no game ever saved), confirmed the hard way when
## user://saves/ was added and this menu's own scene failed to even load
## headlessly. Neither folder had ever been guaranteed to exist before this.
## The .tscn's own root_subfolder is set at DESERIALIZATION time (before any
## _ready() runs, or a directory this script could create), so the folders
## are made first and root_subfolder is then re-applied from here - a no-op
## when it already took, the actual fix on a fresh install where it didn't.
func _ready() -> void:
	for dir in ["user://missions", "user://saves"]:
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_recursive_absolute(dir)
	mission_dialog.root_subfolder = "user://missions/"
	save_dialog.root_subfolder = "user://saves/"


func _on_play_button_pressed() -> void:
	mission_dialog.popup_centered()


## Resumes a session saved via the Player's Gear menu "Save" - see
## SaveGame.gd/MissionPlayer.save_game(). A separate button/dialog from
## "Play Mission" since it opens a save file (user://saves/), not a mission
## definition (user://missions/) - the two folders hold different Resource
## types.
func _on_load_game_button_pressed() -> void:
	save_dialog.popup_centered()


func _on_save_file_dialog_file_selected(path: String) -> void:
	GameState.load_save_path = path
	get_tree().change_scene_to_file(player_scene_path)


func _on_editor_button_pressed() -> void:
	get_tree().change_scene_to_file(editor_scene_path)


func _on_exit_button_pressed() -> void:
	get_tree().quit()


func _on_mission_file_dialog_file_selected(path: String) -> void:
	GameState.current_mission_path = path
	get_tree().change_scene_to_file(player_scene_path)
