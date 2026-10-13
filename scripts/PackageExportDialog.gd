class_name PackageExportDialog
extends ConfirmationDialog

## "Export package…" of the mission editor and the campaign editor: asks for the details (name, author, version, description, and - when
## there are pictures - the statement that the author may share them), lets the player pick where the .descentpkg goes, and writes it
## (SharePackage). The package is checked the way an importer checks it before the file is kept, so what is written can be installed.
## The author, version and description are remembered per mission / campaign.

const MEMORY_FILE := "user://community/export_memory.json"

var _mode := ""
var _mission: MissionData
var _folder := ""
var _memory_key := ""

var _name_edit: LineEdit
var _author_edit: LineEdit
var _version_edit: LineEdit
var _description_edit: TextEdit
var _rights_box: CheckBox
var _info_label: Label
var _file_dialog: FileDialog
var _message_dialog: AcceptDialog
var _pending_meta: Dictionary = {}


func _ready() -> void:
	title = "Export package"
	ok_button_text = "Choose where to save…"
	min_size = Vector2i(520, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	_name_edit = _add_row(box, "Name")
	_author_edit = _add_row(box, "Author")
	_version_edit = _add_row(box, "Version")
	_version_edit.tooltip_text = "Numbers separated by dots, like 1.0 or 1.2.1. Raise it when you share an update."
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
	_file_dialog.title = "Save the package"
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.add_filter("*.%s" % SharePackage.EXTENSION, "Descent Engine package")
	_file_dialog.file_selected.connect(_on_file_chosen)
	_message_dialog = AcceptDialog.new()
	_message_dialog.min_size = Vector2i(520, 0)
	# the two helper windows hang on the main window, not on this dialog: a window with an exclusive child can't show a second one
	get_tree().root.add_child.call_deferred(_file_dialog)
	get_tree().root.add_child.call_deferred(_message_dialog)


func _exit_tree() -> void:
	for helper in [_file_dialog, _message_dialog]:
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


## Export the mission that is open in the editor, as it is now.
func open_mission(mission: MissionData, suggested_name: String, memory_key: String) -> void:
	_mode = SharePackage.TYPE_MISSION
	_mission = mission
	_folder = ""
	_memory_key = "mission:" + memory_key
	_rights_box.visible = false
	_info_label.text = "The mission is packed as it is in the editor right now (you don't have to save it first). Monster templates it uses are inside the package."
	_fill(suggested_name)


## Export the campaign in user://campaigns/<folder> (it must be saved).
func open_campaign(folder: String, suggested_name: String) -> void:
	_mode = SharePackage.TYPE_CAMPAIGN
	_mission = null
	_folder = folder
	_memory_key = "campaign:" + folder
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
	_info_label.text = "The whole campaign folder is packed: %d mission file(s) and %d picture(s). Save games are not included." % [missions, pictures]
	_fill(suggested_name)


func _fill(suggested_name: String) -> void:
	var memory := _load_memory().get(_memory_key, {}) as Dictionary
	_name_edit.text = str(memory.get("name", suggested_name))
	_author_edit.text = PlayerSettings.community_author
	_version_edit.text = str(memory.get("version", "1.0.0"))
	_description_edit.text = str(memory.get("description", ""))
	popup_centered()


func _on_confirmed() -> void:
	var package_name := _name_edit.text.strip_edges()
	var version := _version_edit.text.strip_edges()
	var problem := ""
	if package_name == "":
		problem = "Give the package a name."
	elif RegEx.create_from_string("^[0-9]+(\\.[0-9]+){0,3}$").search(version) == null:
		problem = "The version must be numbers separated by dots, like 1.0 or 1.2.1."
	elif _rights_box.visible and not _rights_box.button_pressed:
		problem = "Packages with pictures can only be shared when you confirm you may share them."
	if problem != "":
		_message_dialog.dialog_text = problem
		_message_dialog.popup_centered()
		_message_dialog.confirmed.connect(popup_centered, CONNECT_ONE_SHOT)
		return
	_pending_meta = {
		"name": package_name,
		"author": _author_edit.text.strip_edges(),
		"description": _description_edit.text.strip_edges(),
		"version": version,
		"rights_confirmed": _rights_box.visible and _rights_box.button_pressed,
	}
	var id := SharePackage.make_id(_pending_meta["author"], package_name)
	_file_dialog.current_file = "%s-%s.%s" % [id, version, SharePackage.EXTENSION]
	_file_dialog.popup_centered_clamped(Vector2i(820, 560), 0.9)


func _on_file_chosen(path: String) -> void:
	var target := path if path.get_extension().to_lower() == SharePackage.EXTENSION else path + "." + SharePackage.EXTENSION
	var problems: Array[String]
	if _mode == SharePackage.TYPE_MISSION:
		problems = SharePackage.build_mission(_mission, _pending_meta, target)
	else:
		problems = SharePackage.build_campaign(_folder, _pending_meta, target)
	if not problems.is_empty():
		_message_dialog.dialog_text = "The package could not be made:\n\n- %s" % "\n- ".join(problems.slice(0, 8))
		_message_dialog.popup_centered()
		return
	PlayerSettings.community_author = _pending_meta["author"]
	PlayerSettings.save_settings()
	var memory := _load_memory()
	memory[_memory_key] = {"name": _pending_meta["name"], "version": _pending_meta["version"], "description": _pending_meta["description"]}
	_save_memory(memory)
	var entry := {
		"id": SharePackage.make_id(_pending_meta["author"], _pending_meta["name"]),
		"type": _mode,
		"name": _pending_meta["name"],
		"author": _pending_meta["author"],
		"description": _pending_meta["description"],
		"version": _pending_meta["version"],
		"url": "https://… where you uploaded the file",
		"sha256": FileAccess.get_sha256(target),
		"size_bytes": FileAccess.get_file_as_bytes(target).size(),
	}
	var entry_text := JSON.stringify(entry, "  ")
	DisplayServer.clipboard_set(entry_text)
	_message_dialog.dialog_text = "Saved %s\n\nShare this file with anyone - they import it from the Community page in the main menu.\n\nTo list it in the community catalog, upload the file somewhere (a GitHub release works well) and add this entry (copied to your clipboard) to community/index.json in the project - see community/README.md:\n\n%s" % [target, entry_text]
	_message_dialog.popup_centered()


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
