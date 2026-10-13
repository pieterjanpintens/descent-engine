class_name CommunityDialog
extends Control

## "Community" (main menu): missions and campaigns shared by other people - what is installed (with Play and Remove), importing a
## package file or a web address, and browsing the catalog kept on GitHub. Built in code, modal like the Options dialog; `open()` shows it.
## Whatever comes in goes through SharePackage.read() first (a package is checked as plain text before anything is loaded) and is installed
## side by side with other versions (CommunityLibrary): nothing is ever updated in place.

signal play_mission(path: String)
signal open_campaigns

var _service: CommunityService
var _pending: Dictionary = {}  ## the checked package waiting for the player's OK
var _pending_source := ""
var _catalog: Array[Dictionary] = []
var _busy := false

var _tabs: TabContainer
var _installed_box: VBoxContainer
var _browse_box: VBoxContainer
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
var _publish_file_dialog: FileDialog
var _publish_dialog: PublishDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # the modal scrim - blocks everything behind it

	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var background := PanelContainer.new()
	background.custom_minimum_size = Vector2(700, 560)
	center.add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	background.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Community"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	var intro := _small_label("Missions and campaigns made by other players. Everything is checked before it is installed - a package can only contain game data, never code - and every version is installed next to the others, so nothing you made or saved is ever overwritten.")
	vbox.add_child(intro)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tabs)
	_tabs.add_child(_build_installed_tab())
	_tabs.add_child(_build_browse_tab())
	_tabs.set_tab_title(0, "Installed")
	_tabs.set_tab_title(1, "Browse online")

	_status_label = _small_label("")
	vbox.add_child(_status_label)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): visible = false)
	vbox.add_child(close)

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

	_publish_dialog = PublishDialog.new()
	add_child(_publish_dialog)
	_publish_file_dialog = FileDialog.new()
	_publish_file_dialog.title = "Choose the package to publish"
	_publish_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_publish_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_publish_file_dialog.use_native_dialog = true
	_publish_file_dialog.add_filter("*.%s" % SharePackage.EXTENSION, "Descent Engine package")
	_publish_file_dialog.file_selected.connect(func(path: String): _publish_dialog.open_for(path))
	add_child(_publish_file_dialog)

	visible = false


func open() -> void:
	_status_label.text = ""
	_refresh_installed()
	_tabs.current_tab = 0
	visible = true


# ------------------------------------------------------------------ the tabs

func _build_installed_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Installed"
	tab.add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	_installed_box = VBoxContainer.new()
	_installed_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_installed_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_installed_box)

	tab.add_child(HSeparator.new())
	var file_row := HBoxContainer.new()
	var import_file := _action_button("Import a package file…", func(): _file_dialog.popup_centered_clamped(Vector2i(820, 560), 0.9))
	file_row.add_child(import_file)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_row.add_child(spacer)
	var publish_file := _action_button("Publish a package file…", func(): _publish_file_dialog.popup_centered_clamped(Vector2i(820, 560), 0.9))
	publish_file.tooltip_text = "Submit a package you exported to the community list (needs a GitHub account)."
	file_row.add_child(publish_file)
	tab.add_child(file_row)
	var url_row := HBoxContainer.new()
	_url_edit = LineEdit.new()
	_url_edit.placeholder_text = "…or paste a web address (https://…) of a package file"
	_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_edit.text_submitted.connect(func(_text: String): _on_import_url_pressed())
	url_row.add_child(_url_edit)
	url_row.add_child(_action_button("Import", _on_import_url_pressed))
	tab.add_child(url_row)
	return tab


func _build_browse_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Browse"
	tab.add_theme_constant_override("separation", 6)
	var url_row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Catalog:"
	url_row.add_child(label)
	_catalog_url_edit = LineEdit.new()
	_catalog_url_edit.text = PlayerSettings.community_catalog_url
	_catalog_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_url_edit.tooltip_text = "The list of shared packages. By default the one in the descent-engine-community repository on GitHub."
	url_row.add_child(_catalog_url_edit)
	url_row.add_child(_action_button("Refresh", _on_refresh_catalog_pressed))
	tab.add_child(url_row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	_browse_box = VBoxContainer.new()
	_browse_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browse_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_browse_box)
	_browse_box.add_child(_small_label("Press Refresh to see what has been shared."))
	return tab


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
		_installed_box.add_child(_small_label("Nothing installed yet. Import a package file, paste a web address, or browse online."))
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
	title.text = "%s   v%s" % [entry.get("name", ""), entry.get("version", "")]
	text.add_child(title)
	var meta := _small_label("%s%s" % ["Mission" if is_mission else "Campaign", " - by %s" % entry["author"] if str(entry.get("author", "")) != "" else ""])
	text.add_child(meta)
	if str(entry.get("description", "")) != "":
		text.add_child(_small_label(str(entry["description"]).substr(0, 220)))
	var play := Button.new()
	play.text = "Play" if is_mission else "Open campaigns"
	play.pressed.connect(func():
		visible = false
		if is_mission:
			play_mission.emit(str(entry["path"]))
		else:
			open_campaigns.emit()
	)
	box.add_child(play)
	var remove := _action_button("Remove", func(): _ask_remove(entry))
	box.add_child(remove)
	return row


func _ask_remove(entry: Dictionary) -> void:
	_remove_entry = entry
	var extra := "\nIts save games are removed too." if entry.get("type", "") == SharePackage.TYPE_CAMPAIGN else ""
	_remove_dialog.dialog_text = "Remove \"%s\" version %s from this computer?%s" % [entry.get("name", ""), entry.get("version", ""), extra]
	_remove_dialog.popup_centered()


func _on_remove_confirmed() -> void:
	CommunityLibrary.remove(_remove_entry)
	_status_label.text = "Removed %s v%s." % [_remove_entry.get("name", ""), _remove_entry.get("version", "")]
	_refresh_installed()
	_render_catalog()


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


## Reads and checks a package; shows what is in it and asks before installing. `expect` (from the catalog) = {id, version} it must be.
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
		_tabs.current_tab = 0
		_refresh_installed()
		_render_catalog()
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


# ------------------------------------------------------------------ catalog

func _on_refresh_catalog_pressed() -> void:
	if _busy:
		return
	_set_busy(true)
	_status_label.text = "Downloading the list…"
	var result := await _service.fetch_catalog(_catalog_url_edit.text)
	_set_busy(false)
	if not result["ok"]:
		_status_label.text = str(result["error"])
		return
	PlayerSettings.community_catalog_url = _catalog_url_edit.text.strip_edges()
	PlayerSettings.save_settings()
	_catalog.assign(result["entries"])
	_status_label.text = "%d shared package(s)." % _catalog.size()
	_render_catalog()


func _render_catalog() -> void:
	if _browse_box == null:
		return
	_clear(_browse_box)
	if _catalog.is_empty():
		_browse_box.add_child(_small_label("Press Refresh to see what has been shared." if _status_label.text == "" else "Nothing has been shared yet."))
		return
	for entry in _catalog:
		_browse_box.add_child(_catalog_row(entry))


func _catalog_row(entry: Dictionary) -> Control:
	var is_mission: bool = entry["type"] == SharePackage.TYPE_MISSION
	var row := PanelContainer.new()
	var box := HBoxContainer.new()
	row.add_child(box)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	var title := Label.new()
	title.text = "%s   v%s" % [entry["name"], entry["version"]]
	text.add_child(title)
	var size_text := " - %.1f MB" % (int(entry["size_bytes"]) / 1048576.0) if int(entry["size_bytes"]) > 0 else ""
	text.add_child(_small_label("%s%s%s" % ["Mission" if is_mission else "Campaign", " - by %s" % entry["author"] if entry["author"] != "" else "", size_text]))
	if entry["description"] != "":
		text.add_child(_small_label(str(entry["description"]).substr(0, 220)))
	var have := CommunityLibrary.newest_version(entry["id"])
	var installed_this := not CommunityLibrary.find(entry["id"], entry["version"]).is_empty()
	if installed_this:
		var label := Label.new()
		label.text = "Installed"
		label.modulate = Color(0.6, 0.9, 0.6)
		box.add_child(label)
	else:
		var button_text := "Install"
		if have != "":
			button_text = "Install this version (you have v%s)" % have if CommunityLibrary.compare_versions(entry["version"], have) > 0 else "Install (you have v%s)" % have
		box.add_child(_action_button(button_text, func(): _install_from_catalog(entry)))
	return row


func _install_from_catalog(entry: Dictionary) -> void:
	if _busy:
		return
	_set_busy(true)
	var path := await _service.download_package(entry["url"], entry["sha256"], entry["name"])
	_set_busy(false)
	if path == "":
		return
	_review(path, entry["url"], {"id": entry["id"], "version": entry["version"]})
