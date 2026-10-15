extends Control

## Root script for the main menu scene. The main page is about PLAYING campaigns: New Campaign (the campaign screen's book library) and
## Load Campaign (its list of save games, where they can also be deleted). Everything for authors and testers - the two editors, playing one single mission,
## loading a mission save - sits on a second page, "Editors & Tools".

@export var editor_scene_path: String = "res://map/MissionMap.tscn"   ## <<< set to your actual Creator/editor scene
@export var player_scene_path: String = "res://player/MissionPlayer.tscn"  ## <<< set to your actual Player scene
@export var campaign_editor_scene_path: String = "res://ui/CampaignEditor.tscn"

@onready var mission_dialog: FileDialog = %MissionFileDialog
@onready var save_dialog: FileDialog = %SaveFileDialog
@onready var main_panel: Control = %MainPanel
@onready var editors_panel: Control = %EditorsPanel
@onready var load_campaign_button: Button = %LoadCampaignButton

## The credits page: [role, names] pairs - add a line here to credit someone.
const CREDITS: Array = [
	["Created by", "Arutha"],
	["Concept art - main menu background", "Ikkante"],
]
const CREDITS_NOTE := "An unofficial fan project, free to use (MIT license).\n*Descent: Legends of the Dark* and everything of the game belong to their owners."

var _options_dialog: VoiceSettingsDialog
var _assets_dialog: AssetImportDialog
var _community_dialog: CommunityDialog
var _credits_panel: VBoxContainer
var _updater: AppUpdater
var _update_button: Button
var _update_dialog: UpdateDialog
var _update_result: Dictionary = {}


## Ensures both user:// folders exist before anything tries to browse them -
## true on a genuinely fresh install (no mission ever saved, no game ever
## saved) that neither had ever been guaranteed before this (confirmed the
## hard way when user://saves/ was added and this menu's own scene failed to
## even load headlessly with FileDialog.root_subfolder pointed at it).
func _ready() -> void:
	for dir in ["user://missions", "user://saves"]:
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_recursive_absolute(dir)
	load_campaign_button.disabled = not CampaignIO.has_saves()
	_build_credits_panel()
	await _build_update_banner()


## Bottom-right: the version of this build and, when a newer release exists, a button that opens the update dialog.
## Development builds have no version and show nothing. The check asks GitHub once per run (and only if the player allows it).
func _build_update_banner() -> void:
	var current := AppUpdater.current_version()
	if current == "":
		return
	AppUpdater.clean_up()
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.alignment = BoxContainer.ALIGNMENT_END
	add_child(box)
	_update_button = Button.new()
	_update_button.visible = false
	_update_button.pressed.connect(_on_update_button_pressed)
	box.add_child(_update_button)
	var version := Label.new()
	version.text = "Version %s" % current
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.modulate = Color(1, 1, 1, 0.55)
	box.add_child(version)
	if not PlayerSettings.check_updates:
		return
	var result := AppUpdater.last_check
	if result.is_empty():
		_updater = AppUpdater.new()
		add_child(_updater)
		result = await _updater.check()
	_show_update(result)


func _show_update(result: Dictionary) -> void:
	if not bool(result.get("ok", false)) or not bool(result.get("newer", false)):
		return
	_update_result = result
	_update_button.text = "Update available: %s" % str(result["tag"])
	_update_button.visible = true


func _on_update_button_pressed() -> void:
	if _update_dialog == null:
		_update_dialog = UpdateDialog.new()
		add_child(_update_dialog)
	_update_dialog.open_for(_update_result)


## The credits page - a third page of the same column as the main and editors pages, built from CREDITS.
func _build_credits_panel() -> void:
	_credits_panel = VBoxContainer.new()
	_credits_panel.add_theme_constant_override("separation", 10)
	_credits_panel.visible = false
	for entry: Array in CREDITS:
		var role := Label.new()
		role.text = str(entry[0])
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role.modulate = Color(0.85, 0.85, 0.85, 0.8)
		_credits_panel.add_child(role)
		var names := Label.new()
		names.text = str(entry[1])
		names.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		names.add_theme_font_size_override("font_size", 26)
		_credits_panel.add_child(names)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		_credits_panel.add_child(gap)
	var note := Label.new()
	note.text = CREDITS_NOTE.replace("*", "")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(440, 0)
	note.modulate = Color(1, 1, 1, 0.85)
	_credits_panel.add_child(note)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_credits_back_pressed)
	_credits_panel.add_child(back)
	main_panel.get_parent().add_child(_credits_panel)


func _on_credits_button_pressed() -> void:
	main_panel.visible = false
	_credits_panel.visible = true


func _on_credits_back_pressed() -> void:
	_credits_panel.visible = false
	main_panel.visible = true


## Shared missions and campaigns: what is installed, importing a package, browsing the catalog.
func _on_community_button_pressed() -> void:
	if _community_dialog == null:
		_community_dialog = CommunityDialog.new()
		_community_dialog.play_mission.connect(_on_mission_file_dialog_file_selected)
		_community_dialog.open_campaigns.connect(_on_new_campaign_button_pressed)
		add_child(_community_dialog)
	_community_dialog.open()


## Importing the real art and data from the player's own install of the game.
func _on_assets_button_pressed() -> void:
	if _assets_dialog == null:
		_assets_dialog = AssetImportDialog.new()
		add_child(_assets_dialog)
	_assets_dialog.open()


## The same Options dialog as the Player's Gear menu (voice control, narration, voices). Nothing is listening in the
## menu, so the dialog (live = false) only saves the settings and lets the player install the voice packs.
func _on_options_button_pressed() -> void:
	if _options_dialog == null:
		var listener := VoiceListener.new()  # never started: it is only asked what is installed
		add_child(listener)
		_options_dialog = VoiceSettingsDialog.new()
		_options_dialog.voice_listener = listener
		_options_dialog.live = false
		add_child(_options_dialog)
	_options_dialog.open()


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
	GameState.clear_debug()
	GameState.load_save_path = path
	get_tree().change_scene_to_file(player_scene_path)


func _on_editor_button_pressed() -> void:
	GameState.clear_debug()
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
	GameState.clear_debug()
	GameState.current_mission_path = path
	get_tree().change_scene_to_file(player_scene_path)
