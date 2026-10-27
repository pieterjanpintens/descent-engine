class_name CommunityPanel
extends VBoxContainer

## "Community" (a tab of the Options dialog in the main menu): what shared missions and campaigns are installed (Play / Fork to edit / Remove),
## importing a package file or a web address by hand, and the address of the community list. Finding and installing from the list happens on the New
## game screen. Whatever comes in goes through SharePackage.read() first (a package is checked as plain text before anything is loaded) and is installed
## side by side with other versions (CommunityLibrary): nothing is ever updated in place.

signal play_mission(path: String)
signal open_campaigns

var _service: CommunityService
var _pending: Dictionary = {}  ## the checked package waiting for the player's OK
var _pending_source := ""
var _busy := false

var _installed_box: VBoxContainer
var _status_label: Label
var _url_edit: LineEdit
var _catalog_url_edit: LineEdit
var _action_buttons: Array[Button] = []
var _file_dialog: FileDialog
var _review_dialog: ConfirmationDialog
var _review_label: Label
var _remove_dialog: ConfirmationDialog
var _remove_entry: Dictionary = {}
var _message_dialog: AcceptDialog


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(_small_label("Missions and campaigns made by other players. Everything is checked before it is installed - a package can only contain game data, never code - and every version is installed next to the others, so nothing you made or saved is ever overwritten."))
	add_child(_heading("Installed"))
	_installed_box = VBoxContainer.new()
	_installed_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_installed_box.add_theme_constant_override("separation", 6)
	add_child(_installed_box)
	add_child(HSeparator.new())
	add_child(_heading("Install by hand"))
	_build_import_section()
	add_child(HSeparator.new())
	add_child(_heading("Community list"))
	add_child(_small_label("The list of shared campaigns that the refresh icon on the New game screen shows. By default the one in the descent-engine-community repository on GitHub."))
	_catalog_url_edit = LineEdit.new()
	_catalog_url_edit.text = PlayerSettings.community_catalog_url
	_catalog_url_edit.placeholder_text = CommunityService.DEFAULT_CATALOG_URL
	_catalog_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_url_edit.text_submitted.connect(func(_text: String): _save_catalog_url())
	_catalog_url_edit.focus_exited.connect(_save_catalog_url)
	add_child(_catalog_url_edit)
	_status_label = _small_label("")
	add_child(_status_label)

	_service = CommunityService.new()
	_service.progress.connect(func(text: String): _status_label.text = text)
	add_child(_service)

	_file_dialog = FileDialog.new()
	_file_dialog.title = "Choose a package"
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.add_filter("*.%s" % SharePackage.EXTENSION, "Descent Engine package")
	_file_dialog.file_selected.connect(func(path: String): _review(path, ""))
	add_child(_file_dialog)

	_review_dialog = ConfirmationDialog.new()
	_review_dialog.title = "Install this package?"
	_review_dialog.ok_button_text = "Install"
	_review_dialog.min_size = Vector2i(560, 0)
	_review_label = Label.new()
	_review_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_review_label.custom_minimum_size = Vector2(520, 0)
	_review_dialog.add_child(_review_label)
	_review_dialog.confirmed.connect(_on_install_confirmed)
	_review_dialog.canceled.connect(_forget_pending)
	add_child(_review_dialog)

	_remove_dialog = ConfirmationDialog.new()
	_remove_dialog.title = "Remove"
	_remove_dialog.ok_button_text = "Remove"
	_remove_dialog.confirmed.connect(_on_remove_confirmed)
	add_child(_remove_dialog)

	_message_dialog = AcceptDialog.new()
	_message_dialog.min_size = Vector2i(520, 0)
	add_child(_message_dialog)
	_refresh_installed()


## Call when the Options dialog opens: what is installed may have changed since (the New game screen installs too).
func refresh() -> void:
	if _installed_box != null:
		_status_label.text = ""
		_refresh_installed()


func _heading(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HeadingLabel"
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.56, 0.79, 0.9))
	return label


func _save_catalog_url() -> void:
	var address := _catalog_url_edit.text.strip_edges()
	if address != PlayerSettings.community_catalog_url:
		PlayerSettings.community_catalog_url = address
		PlayerSettings.save_settings()


## A package you were handed (a file, or a link to one).
func _build_import_section() -> void:
	add_child(_small_label("Got a package from someone? Choose the file, or paste the web address of it. You see what is in it, and who made it, before anything is installed."))
	var file_row := HBoxContainer.new()
	file_row.add_child(_action_button("Choose a package file…", func(): _file_dialog.popup_centered_clamped(Vector2i(820, 560), 0.9)))
	add_child(file_row)
	add_child(_small_label("Or a web address (https://…) of a package file:"))
	var url_row := HBoxContainer.new()
	_url_edit = LineEdit.new()
	_url_edit.placeholder_text = "https://…"
	_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_edit.text_submitted.connect(func(_text: String): _on_import_url_pressed())
	url_row.add_child(_url_edit)
	url_row.add_child(_action_button("Import", _on_import_url_pressed))
	add_child(url_row)


func _action_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	_action_buttons.append(button)
	return button


func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(1, 1, 1, 0.8)
	return label


func _set_busy(busy: bool) -> void:
	_busy = busy
	_action_buttons = _action_buttons.filter(func(button: Button): return is_instance_valid(button))
	for button in _action_buttons:
		button.disabled = busy


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.free()


# ------------------------------------------------------------------ installed

func _refresh_installed() -> void:
	_clear(_installed_box)
	var entries := CommunityLibrary.installed()
	if entries.is_empty():
		_installed_box.add_child(_small_label("Nothing installed yet. Use the refresh icon on the New game screen to find shared campaigns, or install a package by hand below."))
		return
	entries.reverse()
	for entry in entries:
		_installed_box.add_child(_installed_row(entry))


func _installed_row(entry: Dictionary) -> Control:
	var is_mission: bool = entry.get("type", "") == SharePackage.TYPE_MISSION
	var row := PanelContainer.new()
	var box := HBoxContainer.new()
	row.add_child(box)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	var title := Label.new()
	title.text = "%s   v%s%s" % [entry.get("name", ""), entry.get("version", ""), "   (your release)" if entry.get("source", "") == "own" else ""]
	text.add_child(title)
	var meta := _small_label("%s%s" % ["Mission" if is_mission else "Campaign", " - by %s" % entry["author"] if str(entry.get("author", "")) != "" else ""])
	text.add_child(meta)
	if str(entry.get("description", "")) != "":
		text.add_child(_small_label(str(entry["description"]).substr(0, 220)))
	var play := Button.new()
	play.text = "Play" if is_mission else "Open campaigns"
	play.pressed.connect(func():
		if is_mission:
			play_mission.emit(str(entry["path"]))
		else:
			open_campaigns.emit()
	)
	box.add_child(play)
	var fork := _action_button("Fork to edit", func(): _fork(entry))
	fork.tooltip_text = "Copies this read-only release into a new draft you can change. The release itself and its save games stay as they are."
	box.add_child(fork)
	var remove := _action_button("Remove", func(): _ask_remove(entry))
	box.add_child(remove)
	return row


func _ask_remove(entry: Dictionary) -> void:
	_remove_entry = entry
	var extra := ""
	if entry.get("type", "") == SharePackage.TYPE_CAMPAIGN:
		var saves := CampaignIO.save_keys(str(entry.get("path", "")).get_file()).size()
		if saves > 0:
			extra = "\n%d save game(s) of it are moved aside (user://campaign_saves/_removed), not deleted." % saves
	_remove_dialog.dialog_text = "Remove \"%s\" version %s from this computer?%s" % [entry.get("name", ""), entry.get("version", ""), extra]
	_remove_dialog.popup_centered()


func _fork(entry: Dictionary) -> void:
	var base_name := CommunityLibrary.strip_version_suffix(str(entry.get("name", "")))
	if base_name == "":
		base_name = "copy"
	var made := ""
	if entry.get("type", "") == SharePackage.TYPE_MISSION:
		made = CommunityLibrary.fork_mission(str(entry["path"]), base_name)
	else:
		made = CampaignIO.fork(str(entry["path"]).get_file(), base_name)
	if made == "":
		_status_label.text = "Could not fork %s." % entry.get("name", "")
	else:
		_status_label.text = "Forked %s into your draft \"%s\" - open it in the %s editor." % [entry.get("name", ""), made.get_file().get_basename(), "mission" if entry.get("type", "") == SharePackage.TYPE_MISSION else "campaign"]


func _on_remove_confirmed() -> void:
	CommunityLibrary.remove(_remove_entry)
	_status_label.text = "Removed %s v%s." % [_remove_entry.get("name", ""), _remove_entry.get("version", "")]
	_refresh_installed()


# ------------------------------------------------------------------ importing

func _on_import_url_pressed() -> void:
	if _busy:
		return
	var address := CommunityService.normalize_url(_url_edit.text)
	if address == "":
		_status_label.text = "That is not a web address (it must start with https://)."
		return
	_set_busy(true)
	var path := await _service.download_package(address, "", "the package")
	_set_busy(false)
	if path == "":
		return
	_review(path, address)


## Reads and checks a package; shows what is in it and asks before installing. `expect` = {id, version} it must be.
func _review(path: String, source: String, expect: Dictionary = {}) -> void:
	var package := SharePackage.read(path)
	if not package["ok"]:
		_message("This package was not imported - it is damaged or contains something that is not allowed:\n\n- %s" % "\n- ".join(package["errors"].slice(0, 8)))
		_remove_download()
		return
	var manifest: Dictionary = package["manifest"]
	if not expect.is_empty() and (manifest["id"] != expect["id"] or manifest["version"] != expect["version"]):
		_message("The downloaded package is not the one the list promised (%s %s instead of %s %s). It was not imported." % [manifest["id"], manifest["version"], expect["id"], expect["version"]])
		_remove_download()
		return
	if not CommunityLibrary.find(manifest["id"], manifest["version"]).is_empty():
		_message("\"%s\" version %s is already installed." % [manifest["name"], manifest["version"]])
		_remove_download()
		return
	_pending = package
	_pending_source = source
	_review_label.text = _summary(package)
	_review_dialog.popup_centered()


func _summary(package: Dictionary) -> String:
	var manifest: Dictionary = package["manifest"]
	var files: Dictionary = package["files"]
	var pictures := 0
	var missions := 0
	var bytes := 0
	for file_name: String in files:
		bytes += (files[file_name] as PackedByteArray).size()
		if file_name.get_extension().to_lower() == "tres":
			missions += 1
		else:
			pictures += 1
	var is_mission: bool = manifest["type"] == SharePackage.TYPE_MISSION
	var lines: Array[String] = []
	lines.append("%s \"%s\" - version %s" % ["Mission" if is_mission else "Campaign", manifest["name"], manifest["version"]])
	lines.append("by %s" % (manifest["author"] if manifest["author"] != "" else "an unknown author"))
	if manifest["description"] != "":
		lines.append("\n" + manifest["description"])
	if is_mission:
		lines.append("\n%.1f MB." % (bytes / 1048576.0))
	else:
		lines.append("\n%d mission(s), %d picture(s), %.1f MB." % [maxi(missions - 1, 0), pictures, bytes / 1048576.0])
	if pictures > 0:
		lines.append("The author %s." % ("confirms they may share the pictures" if manifest["rights_confirmed"] else "did not say whether they may share the pictures"))
	var others := CommunityLibrary.versions_of(manifest["id"])
	if not others.is_empty():
		lines.append("You already have version %s - this one is installed next to it." % ", ".join(others.map(func(e: Dictionary): return str(e["version"]))))
	lines.append("\nThe package was checked: it only contains game data.")
	return "\n".join(lines)


func _on_install_confirmed() -> void:
	if _pending.is_empty():
		return
	var result := CommunityLibrary.install(_pending, _pending_source)
	var manifest: Dictionary = _pending["manifest"]
	_forget_pending()
	if result["ok"]:
		_status_label.text = "Installed \"%s\" v%s." % [manifest["name"], manifest["version"]]
		_refresh_installed()
	else:
		_message(str(result["error"]))


func _forget_pending() -> void:
	_pending = {}
	_pending_source = ""
	_remove_download()


func _remove_download() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CommunityService.DOWNLOAD_FILE))


func _message(text: String) -> void:
	_message_dialog.dialog_text = text
	_message_dialog.popup_centered()
