extends Control

## Root script for the main menu scene. The main page is about PLAYING campaigns: Continue (the
## most recently played campaign save game), New Campaign (the campaign screen's book library) and
## Load Campaign (its list of save games, where they can also be deleted). Everything for authors and testers - the two editors, playing one single mission,
## loading a mission save - sits on a second page, "Editors & Tools".

@export var editor_scene_path: String = "res://map/MissionMap.tscn"   ## <<< set to your actual Creator/editor scene
@export var player_scene_path: String = "res://player/MissionPlayer.tscn"  ## <<< set to your actual Player scene
@export var campaign_editor_scene_path: String = "res://ui/CampaignEditor.tscn"

@onready var mission_dialog: FileDialog = %MissionFileDialog
@onready var save_dialog: FileDialog = %SaveFileDialog
@onready var main_panel: Control = %MainPanel
@onready var editors_panel: Control = %EditorsPanel
@onready var continue_button: Button = %ContinueButton
@onready var load_campaign_button: Button = %LoadCampaignButton


## Ensures both user:// folders exist before anything tries to browse them -
## true on a genuinely fresh install (no mission ever saved, no game ever
## saved) that neither had ever been guaranteed before this (confirmed the
## hard way when user://saves/ was added and this menu's own scene failed to
## even load headlessly with FileDialog.root_subfolder pointed at it).
func _ready() -> void:
	for dir in ["user://missions", "user://saves"]:
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_recursive_absolute(dir)
	var has_saves := not CampaignIO.latest_save().is_empty()
	continue_button.disabled = not has_saves
	load_campaign_button.disabled = not has_saves


func _on_continue_button_pressed() -> void:
	var latest := CampaignIO.latest_save()
	if latest.is_empty():
		return
	GameState.clear_campaign()
	GameState.campaign_folder = latest["folder"]
	GameState.campaign_save = latest["key"]
	get_tree().change_scene_to_file(GameState.CAMPAIGN_SCENE)


func _on_editors_button_pressed() -> void:
	main_panel.visible = false
	editors_panel.visible = true


func _on_back_button_pressed() -> void:
	editors_panel.visible = false
	main_panel.visible = true


## Each dialog OPENS in its own folder but isn't locked to it - unlike
## root_subfolder (used briefly here, and still what the Creator's own
## mission dialog uses), current_dir just picks the starting folder and
## leaves the rest of `user://` (both access = User Data) reachable by
## navigating up, so the missions folder is browsable from the Load Game
## dialog and vice versa - requested directly, since a save and a mission
## are both just "a .tres file somewhere under user://" from the table's
## point of view even though this project keeps them in separate folders.
## Same current_dir idiom CreatorSaveLoad.gd's own dialog already uses, set
## fresh on every popup rather than once in _ready() for the same reason
## that one does - navigating away in a previous session shouldn't carry
## over as this dialog's new default.
func _on_play_button_pressed() -> void:
	mission_dialog.current_dir = "user://missions"
	mission_dialog.popup_centered()


## Resumes a session saved via the Player's Gear menu "Save" - see
## SaveGame.gd/MissionPlayer.save_game(). A separate button/dialog from
## "Play Mission" since it opens a save file (user://saves/), not a mission
## definition (user://missions/) - the two folders hold different Resource
## types, but see _on_play_button_pressed()'s own doc for why neither
## dialog is locked to just its own folder.
func _on_load_game_button_pressed() -> void:
	save_dialog.current_dir = "user://saves"
	save_dialog.popup_centered()


func _on_save_file_dialog_file_selected(path: String) -> void:
	GameState.clear_campaign()
	GameState.load_save_path = path
	get_tree().change_scene_to_file(player_scene_path)


func _on_editor_button_pressed() -> void:
	get_tree().change_scene_to_file(editor_scene_path)


func _on_new_campaign_button_pressed() -> void:
	_open_campaign_screen("new")


func _on_load_campaign_button_pressed() -> void:
	_open_campaign_screen("load")


func _open_campaign_screen(screen: String) -> void:
	GameState.clear_campaign()
	GameState.campaign_screen = screen
	get_tree().change_scene_to_file(GameState.CAMPAIGN_SCENE)


func _on_campaign_editor_button_pressed() -> void:
	get_tree().change_scene_to_file(campaign_editor_scene_path)


func _on_exit_button_pressed() -> void:
	get_tree().quit()


func _on_mission_file_dialog_file_selected(path: String) -> void:
	GameState.clear_campaign()
	GameState.current_mission_path = path
	get_tree().change_scene_to_file(player_scene_path)
