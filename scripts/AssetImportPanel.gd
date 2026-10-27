class_name AssetImportPanel
extends VBoxContainer

## The "Game assets" tab of the Options dialog: imports the real art and data from the player's own install of the game with one
## button - see AssetImporter for what happens. Built in code; `refresh()` re-reads what is imported / found (call it when the tab is shown).

signal busy_changed(busy: bool)
signal import_finished  ## an import run ended (whatever its result): other settings that depend on imported files can re-check

const STEP_FOLDERS := {
	"official_assets": "textures and portraits",
	"monster_assets": "monster figures",
	"hero_assets": "hero models",
	"weapon_data": "weapons",
	"item_data": "items",
	"monster_data": "monsters",
}

var _bundles := ""
var _busy := false

var _imported_label: Label
var _game_label: Label
var _choose_button: Button
var _import_button: Button
var _status_label: Label
var _folder_dialog: FileDialog


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var vbox: VBoxContainer = self

	var explanation := _small_label()
	explanation.text = "This app ships without the game's art. If you own \"Descent: Legends of the Dark\", the real pictures, figures and game data can be copied from your own install. Nothing of the game is downloaded and nothing leaves this computer."
	vbox.add_child(explanation)

	_imported_label = _small_label()
	vbox.add_child(_imported_label)
	vbox.add_child(HSeparator.new())

	_game_label = _small_label()
	vbox.add_child(_game_label)

	_choose_button = Button.new()
	_choose_button.text = "Choose the game folder…"
	_choose_button.pressed.connect(func(): _folder_dialog.popup_centered_clamped(Vector2i(820, 560), 0.9))
	vbox.add_child(_choose_button)

	_import_button = Button.new()
	_import_button.custom_minimum_size = Vector2(0, 44)
	_import_button.pressed.connect(_on_import_pressed)
	vbox.add_child(_import_button)

	_status_label = _small_label()
	vbox.add_child(_status_label)
	_folder_dialog = FileDialog.new()
	_folder_dialog.title = "Choose the folder the game is installed in"
	_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_folder_dialog.use_native_dialog = true
	_folder_dialog.dir_selected.connect(_on_folder_chosen)
	add_child(_folder_dialog)


func refresh() -> void:
	if _bundles == "":
		_bundles = AssetImporter.find_game()
	_status_label.text = ""
	_refresh()


func _small_label() -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(400, 0)  # a wrapping label needs a width or it wraps per letter
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(1, 1, 1, 0.8)
	return label


func _refresh() -> void:
	var have: Array[String] = []
	for folder in AssetImporter.imported_folders():
		have.append(STEP_FOLDERS.get(folder, folder))
	_imported_label.text = "Imported so far: %s." % ", ".join(have) if not have.is_empty() else "Nothing has been imported yet - the app shows placeholders."
	_game_label.text = "Game found:\n%s" % _bundles if _bundles != "" else "The game wasn't found in the usual places. Choose the folder it is installed in."

	var importer := AssetImporter.new()
	var needs_download := not importer.tool_ready()
	importer.free()
	_import_button.text = "Import game assets" + (" (downloads the import tool first, %s)" % AssetImporter.DOWNLOAD_SIZE_TEXT if needs_download else "")
	_import_button.disabled = _busy or _bundles == "" or (needs_download and not AssetImporter.is_supported_platform())
	_choose_button.disabled = _busy
	busy_changed.emit(_busy)
	if needs_download and not AssetImporter.is_supported_platform():
		_status_label.text = "Importing from inside the app isn't available on this computer yet - use the asset tools from the release page instead."


func _on_folder_chosen(folder: String) -> void:
	var found := AssetImporter.find_bundles(folder)
	if found == "":
		_status_label.text = "That folder doesn't contain the game (no \"bundles\" folder was found in it)."
	else:
		_bundles = found
		_status_label.text = ""
	_refresh()


func _on_import_pressed() -> void:
	_busy = true
	_refresh()
	var importer := AssetImporter.new()
	add_child(importer)
	importer.progress.connect(func(text: String): _status_label.text = text)
	var ok: bool = await importer.run(_bundles)
	var importer_results: Dictionary = importer.results.duplicate()
	var lines: Array[String] = []
	for label in importer.results:
		lines.append("%s: %s" % [label, "ok" if importer.results[label] else "FAILED"])
	if importer.meshes_converted + importer.meshes_failed > 0:
		lines.append("Models converted: %d%s" % [importer.meshes_converted, " (%d failed)" % importer.meshes_failed if importer.meshes_failed > 0 else ""])
	if not importer.results.is_empty():
		lines.append("")
		lines.append("Done - restart the app to see everything." if ok else "Not everything worked. What did work is in place - restart the app to see it.")
		_status_label.text = "\n".join(lines)
	importer.queue_free()
	_busy = false
	var summary := _status_label.text
	_refresh()
	_status_label.text = summary
	import_finished.emit()
	if _anything_imported(importer_results):
		_offer_restart()


## True when at least one import step worked - then there is something new to load.
func _anything_imported(step_results: Dictionary) -> bool:
	for label in step_results:
		if step_results[label]:
			return true
	return false


## The imported models, pictures and game data are read once and kept by the running app, so a restart is what makes them show up.
func _offer_restart() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Restart needed"
	dialog.dialog_text = "The imported game assets are loaded when the app starts.\n\nRestart now?"
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path.contains("MissionPlayer"):
		dialog.dialog_text += "\n\nThe mission you are playing will be closed - save it first (Options > Save), or choose Later."
	dialog.ok_button_text = "Restart now"
	dialog.cancel_button_text = "Later"
	dialog.confirmed.connect(_restart_app)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _restart_app() -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()
