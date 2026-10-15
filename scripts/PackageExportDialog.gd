class_name PackageExportDialog
extends ConfirmationDialog

## "Release…" of the mission editor and the campaign editor. A RELEASE is a frozen, numbered version of a draft: it is packed
## (SharePackage), checked the way an importer checks it, and installed next to everything else (CommunityLibrary) - from then on it is
## what saves play against and it is never changed again. Afterwards the package file can be saved anywhere or published.
## The name, description and package id are remembered per draft; the version always counts up from the highest release of that id.

const MEMORY_FILE := "user://community/export_memory.json"

var _mode := ""
var _mission: MissionData
var _folder := ""
var _memory_key := ""
var _package_id := ""

var _name_edit: LineEdit
var _author_edit: LineEdit
var _version_edit: LineEdit
var _description_edit: TextEdit
var _rights_box: CheckBox
var _info_label: Label
var _file_dialog: FileDialog
const MESSAGE_WIDTH := 540

var _message_dialog: AcceptDialog
var _message_label: Label
var _publish_dialog: PublishDialog
var _last_package := ""


func _ready() -> void:
	title = "Release"
	ok_button_text = "Release"
	min_size = Vector2i(520, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	_name_edit = _add_row(box, "Name")
	_author_edit = _add_row(box, "Author")
	_version_edit = _add_row(box, "Version")
	var description_label := Label.new()
	description_label.text = "Description"
	box.add_child(description_label)
	_description_edit = TextEdit.new()
	_description_edit.custom_minimum_size = Vector2(0, 90)
	_description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(_description_edit)
	_rights_box = CheckBox.new()
	_rights_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rights_box.custom_minimum_size = Vector2(480, 0)
	_rights_box.text = "I made all the pictures in this package, or I have permission to share them."
	box.add_child(_rights_box)
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(480, 0)
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_info_label)

	confirmed.connect(_on_confirmed)
	_file_dialog = FileDialog.new()
	_file_dialog.title = "Save the package file"
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.add_filter("*.%s" % SharePackage.EXTENSION, "Descent Engine package")
	_file_dialog.file_selected.connect(_on_file_chosen)
	_message_dialog = AcceptDialog.new()
	# The dialog's own label grows as wide as the longest line (and the text got cut off); a label of a fixed width that wraps does not.
	_message_dialog.get_label().visible = false
	_message_label = Label.new()
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.custom_minimum_size = Vector2(MESSAGE_WIDTH, 0)
	_message_dialog.add_child(_message_label)
	_message_dialog.add_button("Publish to the community…", true, "publish")
	_message_dialog.add_button("Save package file…", true, "save_file")
	_message_dialog.custom_action.connect(_on_message_action)
	_publish_dialog = PublishDialog.new()
	# the helper windows hang on the main window, not on this dialog: a window with an exclusive child can't show a second one
	get_tree().root.add_child.call_deferred(_file_dialog)
	get_tree().root.add_child.call_deferred(_message_dialog)
	get_tree().root.add_child.call_deferred(_publish_dialog)


func _exit_tree() -> void:
	for helper in [_file_dialog, _message_dialog, _publish_dialog]:
		if is_instance_valid(helper):
			helper.queue_free()


func _add_row(parent: Container, label_text: String) -> LineEdit:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(90, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	parent.add_child(row)
	return edit


## Release the mission that is open in the editor, as it is now (a draft; `source_path` = the file it was loaded from / saved to).
func open_mission(mission: MissionData, suggested_name: String, memory_key: String, source_path := "") -> void:
	if source_path != "" and not CommunityLibrary.entry_for_path(source_path).is_empty():
		_show_message("This mission is already a release (read-only). Fork it to make a new draft, then release that.")
		return
	_mode = SharePackage.TYPE_MISSION
	_mission = mission
	_folder = ""
	_memory_key = "mission:" + memory_key
	_package_id = str(_load_memory().get(_memory_key, {}).get("package_id", ""))
	_rights_box.visible = false
	_info_label.text = "A release is a frozen version: it is packed as the mission is in the editor right now (you don't have to save first) and can never be changed afterwards. Monster templates it uses are inside the package."
	_fill(suggested_name)


## Release the campaign draft in user://campaigns/<folder> (it must be saved).
func open_campaign(folder: String, suggested_name: String) -> void:
	if CampaignIO.is_release(folder):
		_show_message("This campaign is already a release (read-only). Fork it to make a new draft, then release that.")
		return
	_mode = SharePackage.TYPE_CAMPAIGN
	_mission = null
	_folder = folder
	_memory_key = "campaign:" + folder
	_package_id = str(CampaignIO.draft_info(folder).get("package_id", ""))
	var pictures := 0
	var missions := 0
	for file_name in DirAccess.get_files_at(CampaignIO.folder_path(folder)):
		var extension := file_name.get_extension().to_lower()
		if SharePackage.IMAGE_EXTENSIONS.has(extension):
			pictures += 1
		elif extension == "tres" and file_name != SharePackage.CAMPAIGN_FILE:
			missions += 1
	_rights_box.visible = pictures > 0
	_rights_box.button_pressed = false
	_info_label.text = "A release is a frozen version of the whole campaign folder (%d mission file(s), %d picture(s); save games are not included). Players' save games stay on the version they started with, so a release can never be changed afterwards." % [missions, pictures]
	_fill(suggested_name)


func _fill(suggested_name: String) -> void:
	var memory := _load_memory().get(_memory_key, {}) as Dictionary
	_name_edit.text = CommunityLibrary.strip_version_suffix(str(memory.get("name", suggested_name)))
	_author_edit.text = PlayerSettings.community_author
	_description_edit.text = str(memory.get("description", ""))
	_version_edit.text = _suggested_version()
	_version_edit.tooltip_text = "Numbers separated by dots, like 1.0 or 1.2.1. It always starts one patch above your highest release of this package; a released version is never replaced."
	popup_centered()


func _suggested_version() -> String:
	var id := _package_id if _package_id != "" else SharePackage.make_id(_author_edit.text.strip_edges(), _name_edit.text.strip_edges())
	var newest := CommunityLibrary.newest_version(id)
	return CommunityLibrary.next_version(newest) if newest != "" else "1.0.0"


func _on_confirmed() -> void:
	var package_name := _name_edit.text.strip_edges()
	var version := _version_edit.text.strip_edges()
	var problem := ""
	if package_name == "":
		problem = "Give the package a name."
	elif RegEx.create_from_string("^[0-9]+(\\.[0-9]+){0,3}$").search(version) == null:
		problem = "The version must be numbers separated by dots, like 1.0 or 1.2.1."
	elif _rights_box.visible and not _rights_box.button_pressed:
		problem = "Packages with pictures can only be released when you confirm you may share them."
	if problem != "":
		_show_message(problem, false, true)
		return
	var author := _author_edit.text.strip_edges()
	var id := _package_id if _package_id != "" else SharePackage.make_id(author, package_name)
	var meta := {
		"name": package_name,
		"author": author,
		"description": _description_edit.text.strip_edges(),
		"version": version,
		"rights_confirmed": _rights_box.visible and _rights_box.button_pressed,
		"id": id,
	}
	var result: Dictionary
	if _mode == SharePackage.TYPE_MISSION:
		result = CommunityLibrary.release_mission(_mission, meta)
	else:
		result = CommunityLibrary.release_campaign(_folder, meta)
	if not result["ok"]:
		_show_message(str(result.get("error", "The release could not be made.")), false, true)
		return
	PlayerSettings.community_author = author
	PlayerSettings.save_settings()
	_package_id = id
	var memory := _load_memory()
	memory[_memory_key] = {"name": package_name, "description": meta["description"], "package_id": id}
	_save_memory(memory)
	if _mode == SharePackage.TYPE_CAMPAIGN:
		var info := CampaignIO.draft_info(_folder)
		info["package_id"] = id
		CampaignIO.write_draft_info(_folder, info)
	_last_package = str(result["package_path"])
	_show_message("Released %s v%s.\n\nIt is frozen now: it appears in the campaign / mission lists as a read-only version, and save games stay on it. Keep working on your draft and release the next version when you are ready.\n\nShare the package file with anyone (they import it from the Community page), or publish it so it appears there for everyone once it is approved." % [package_name, version], true)


## `can_share`: the message is about a package that was just released, so the save / publish buttons make sense.
## `retry`: re-open this dialog when the message is closed (a form problem).
func _show_message(text: String, can_share := false, retry := false) -> void:
	_message_label.text = text
	for child in _message_dialog.get_ok_button().get_parent().get_children():
		if child is Button and child != _message_dialog.get_ok_button():
			(child as Button).visible = can_share
	if _message_dialog.confirmed.is_connected(popup_centered):
		_message_dialog.confirmed.disconnect(popup_centered)
	if retry:
		_message_dialog.confirmed.connect(popup_centered, CONNECT_ONE_SHOT)
	# shrink to the wrapped text first, or an earlier longer message leaves the box too big (or too small) for this one
	_message_dialog.size = Vector2i(MESSAGE_WIDTH + 40, 0)
	_message_dialog.popup_centered()
	_message_dialog.reset_size.call_deferred()


func _on_message_action(action: StringName) -> void:
	if _last_package == "":
		return
	if action == &"publish":
		_message_dialog.hide()
		_publish_dialog.open_for(_last_package)
	elif action == &"save_file":
		_file_dialog.current_file = _last_package.get_file()
		_file_dialog.popup_centered_clamped(Vector2i(820, 560), 0.9)


func _on_file_chosen(path: String) -> void:
	var target := path if path.get_extension().to_lower() == SharePackage.EXTENSION else path + "." + SharePackage.EXTENSION
	if DirAccess.copy_absolute(_last_package, target) != OK:
		_show_message("The package file could not be written to %s." % target)
		return
	_show_message("Saved %s" % target, true)


func _load_memory() -> Dictionary:
	if not FileAccess.file_exists(MEMORY_FILE):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MEMORY_FILE))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _save_memory(memory: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CommunityLibrary.ROOT))
	var file := FileAccess.open(MEMORY_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(memory, "\t"))
		file.close()
