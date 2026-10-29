class_name AssetImporter
extends Downloader

## The in-app "Import game assets": copies the art and data out of the PLAYER'S OWN install of "Descent: Legends of
## the Dark" into user data, where the app picks them up (see OfficialAssetOverrides and the data readers). Same idea
## as tools/asset_import, without the player needing Python or a Godot editor.
##
## Reading the game's Unity files is done by the Python import tools, packaged as a standalone program
## (tools/asset_import/build_importer.py, built per platform by the release workflow and attached to every release).
## This node downloads that program on demand into `user://importer/` (like the speech and narration engines), runs
## it against the game folder, and converts the meshes it stages into Godot meshes itself (ObjMeshBuilder).
## Nothing of the game is downloaded or redistributed: only the tool is.
##
## Run from the project (the editor) with tools/asset_import/.venv present, the Python source is used directly - no
## download.
##
## Add as a child of something in the tree; `await run(bundles)`; status text arrives via `progress`.

const INSTALL_DIR := "user://importer/"
const STAGING_DIR := "user://importer/staging/"
const TOOL_NAME := "asset_importer"
## Must match asset_importer.PROTOCOL: an installed tool that answers something else is downloaded again.
## Bump it together with the tool whenever the steps change (2: the original props step), or installed older tools are kept.
const PROTOCOL := 3
## What the button tells the player.
const DOWNLOAD_SIZE_TEXT := "about 25 MB"
## The user-data folders an import fills (what "imported" means, and what to delete to go back to the placeholders).
const OUTPUT_FOLDERS: Array[String] = ["official_assets", "monster_assets", "hero_assets", "weapon_data", "item_data", "monster_data"]

## Overridable (tests point this at a local server). The newest release always carries the tool.
var download_base_url := "https://github.com/pieterjanpintens/descent-engine/releases/latest/download/"
## A test seam: the full command that runs the tool (program, then its fixed arguments).
var command_override := PackedStringArray()
## false = behave like an exported app even when run from the project (tests of the download).
var use_project_source := true

## Filled by run(): step label -> true/false as the tool reported it, in order.
var results: Dictionary = {}
## Meshes converted / failed by the last run().
var meshes_converted := 0
var meshes_failed := 0


# ---------------------------------------------------------------- the game

## The usual places the game is installed, per platform.
static func _game_roots() -> Array[String]:
	var home := OS.get_environment("USERPROFILE") if OS.get_name() == "Windows" else OS.get_environment("HOME")
	match OS.get_name():
		"Windows":
			return ["C:/Program Files (x86)/Steam/steamapps/common", "C:/Program Files/Steam/steamapps/common",
					"D:/SteamLibrary/steamapps/common", "E:/SteamLibrary/steamapps/common", "C:/Program Files/Epic Games",
					"C:/Program Files (x86)/Epic Games", "C:/GOG Games", "C:/Program Files (x86)/GOG Galaxy/Games"]
		"macOS":
			return [home + "/Library/Application Support/Steam/steamapps/common", "/Applications", home + "/Applications"]
	return [home + "/.steam/steam/steamapps/common", home + "/.local/share/Steam/steamapps/common",
			home + "/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common"]


## The game's `bundles` folder if the game is installed in a usual place, else "".
static func find_game() -> String:
	for root in _game_roots():
		for folder in DirAccess.get_directories_at(root):
			var lower := folder.to_lower()
			if lower.contains("descent") or lower.contains("legends of the dark"):
				var found := find_bundles(root.path_join(folder))
				if found != "":
					return found
	return ""


## The `bundles` folder at or below `start` (the game folder, the .app, or the bundles folder itself), else "".
static func find_bundles(start: String, depth: int = 0) -> String:
	if start == "" or not DirAccess.dir_exists_absolute(start):
		return ""
	if start.get_file().to_lower() == "bundles" and (depth == 0 or start.to_lower().contains("streamingassets")):
		return start
	if depth >= 8:
		return ""
	for folder in DirAccess.get_directories_at(start):
		var found := find_bundles(start.path_join(folder), depth + 1)
		if found != "":
			return found
	return ""


## Which of OUTPUT_FOLDERS exist (something was imported before).
static func imported_folders() -> Array[String]:
	var found: Array[String] = []
	for folder in OUTPUT_FOLDERS:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://" + folder)):
			found.append(folder)
	return found


# ---------------------------------------------------------------- the tool

static func is_supported_platform() -> bool:
	return archive_name() != ""


## The release file for this platform, "" when there is none.
static func archive_name() -> String:
	var arch := Engine.get_architecture_name()
	match OS.get_name():
		"Windows":
			return "Descent-Engine-importer-windows-x86_64.zip" if arch == "x86_64" else ""
		"Linux":
			return "Descent-Engine-importer-linux-x86_64.tar.gz" if arch == "x86_64" else ""
		"macOS":
			return "Descent-Engine-importer-macos-arm64.tar.gz" if arch == "arm64" else ""
	return ""


## The Python source in the project, with its own environment (tools/asset_import/import_all.sh makes it) - used
## when the app runs from the project instead of an export.
static func _source_command() -> PackedStringArray:
	if not OS.has_feature("editor"):
		return PackedStringArray()
	var folder := ProjectSettings.globalize_path("res://tools/asset_import/")
	var python := folder + (".venv/Scripts/python.exe" if OS.get_name() == "Windows" else ".venv/bin/python")
	if FileAccess.file_exists(python) and FileAccess.file_exists(folder + "asset_importer.py"):
		return PackedStringArray([python, folder + "asset_importer.py"])
	return PackedStringArray()


static func _installed_tool() -> String:
	var exe := TOOL_NAME + (".exe" if OS.get_name() == "Windows" else "")
	var path := INSTALL_DIR + TOOL_NAME + "/" + exe
	return ProjectSettings.globalize_path(path) if FileAccess.file_exists(path) else ""


## True when nothing has to be downloaded before an import.
func tool_ready() -> bool:
	return not _command().is_empty()


func _command() -> PackedStringArray:
	if not command_override.is_empty():
		return command_override
	var source := _source_command() if use_project_source else PackedStringArray()
	if not source.is_empty():
		return source
	var installed := _installed_tool()
	return PackedStringArray([installed]) if installed != "" else PackedStringArray()


## Downloads and unpacks the tool if it is not there (or is an older, incompatible one).
func _ensure_tool() -> bool:
	if not _command().is_empty() and _tool_protocol() == PROTOCOL:
		return true
	if not command_override.is_empty() or (use_project_source and not _source_command().is_empty()):
		progress.emit("The import tool in the project doesn't match this version of the app.")
		return false
	var archive_file := archive_name()
	if archive_file == "":
		progress.emit("Importing isn't available on %s (%s) yet - use tools/asset_import instead." % [OS.get_name(), Engine.get_architecture_name()])
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(INSTALL_DIR))
	_remove_folder(INSTALL_DIR + TOOL_NAME)  # an older tool
	var archive := INSTALL_DIR + archive_file
	if not await _fetch(download_base_url + archive_file, archive, "", "import tool"):
		return false
	progress.emit("Unpacking the import tool...")
	var ok := _unzip(archive, INSTALL_DIR, "import tool") if archive_file.ends_with(".zip") else _untar(archive, INSTALL_DIR, "import tool")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(archive))
	if not ok:
		return false
	if _installed_tool() == "":
		progress.emit("The import tool download doesn't contain the program.")
		return false
	if _tool_protocol() != PROTOCOL:
		progress.emit("The import tool that was downloaded doesn't match this version of the app - update the app.")
		return false
	return true


## What the tool answers to --protocol, -1 when it can't be run.
func _tool_protocol() -> int:
	var command := _command()
	if command.is_empty():
		return -1
	var arguments: PackedStringArray = command.slice(1)
	arguments.append("--protocol")
	var output: Array = []
	if OS.execute(command[0], arguments, output) != 0 or output.is_empty():
		return -1
	var text := str(output[0]).strip_edges()
	return text.to_int() if text.is_valid_int() else -1


# ---------------------------------------------------------------- the import

## Imports everything from the game's `bundles` folder. True when every step and every mesh worked; `results`,
## `meshes_converted` and `meshes_failed` say what happened either way.
func run(bundles: String) -> bool:
	results.clear()
	meshes_converted = 0
	meshes_failed = 0
	if not DirAccess.dir_exists_absolute(bundles):
		progress.emit("The game folder wasn't found.")
		return false
	if not await _ensure_tool():
		return false

	_remove_folder(STAGING_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STAGING_DIR))
	var manifest_path := ProjectSettings.globalize_path(INSTALL_DIR + "manifest.json")
	var manifest := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest == null:
		progress.emit("Couldn't write to the app's user folder.")
		return false
	manifest.store_string(JSON.stringify(_manifest()))
	manifest.close()

	var command := _command()
	var arguments: PackedStringArray = command.slice(1)
	arguments.append_array(["--bundles", bundles, "--out", OS.get_user_data_dir(), "--manifest", manifest_path,
			"--staging", ProjectSettings.globalize_path(STAGING_DIR)])
	progress.emit("Reading the game files... (this takes a few minutes)")
	var process := OS.execute_with_pipe(command[0], arguments)
	if process.is_empty():
		progress.emit("Couldn't start the import tool.")
		return false
	var state := {"done": false, "lines": [], "mutex": Mutex.new()}
	var reader := Thread.new()
	reader.start(_read_output.bind(process["stdio"], state))
	var finished := false
	while not finished:
		await get_tree().create_timer(0.2).timeout
		state["mutex"].lock()
		finished = state["done"]
		var lines: Array = state["lines"].duplicate()
		state["lines"].clear()
		state["mutex"].unlock()
		for line in lines:
			_on_tool_line(str(line))
	reader.wait_to_finish()
	var pid: int = process["pid"]
	while OS.is_process_running(pid):
		await get_tree().create_timer(0.1).timeout
	var code := OS.get_process_exit_code(pid)

	await _convert_staged("monsters", "user://monster_assets/")
	await _convert_staged("heroes", "user://hero_assets/")
	progress.emit("Building the original prop library...")
	await get_tree().process_frame
	await OriginalPropsLibrary.build(STAGING_DIR + "props")
	for line in OriginalPropsLibrary.report:
		print("[import] original prop ", line)
	_remove_folder(STAGING_DIR)
	DirAccess.remove_absolute(manifest_path)

	if results.is_empty():
		progress.emit(tr("The import tool stopped without importing anything (exit code %d).") % code)
		return false
	var all_ok := meshes_failed == 0 and not results.values().has(false)
	progress.emit(tr("Import finished.") if all_ok else tr("Import finished, but not everything worked."))
	return all_ok


## What the app wants: the names the import tools otherwise read from the project's scripts.
func _manifest() -> Dictionary:
	var monster_folders: Array[String] = []
	for monster in MonsterDisplay.REAL_MONSTERS:
		monster_folders.append(str(monster["folder"]))
	return {"protocol": PROTOCOL, "official_assets": OfficialAssetMap.MAP, "monster_folders": monster_folders, "hero_names": HeroCatalog.HERO_NAMES}


## Worker thread: hands the tool's output over line by line until it closes its end.
func _read_output(stdio: FileAccess, state: Dictionary) -> void:
	while true:
		var line := stdio.get_line()
		if stdio.get_error() != OK and line == "":
			break
		state["mutex"].lock()
		state["lines"].append(line)
		state["mutex"].unlock()
	state["mutex"].lock()
	state["done"] = true
	state["mutex"].unlock()


func _on_tool_line(line: String) -> void:
	if line.begins_with("##STEP "):
		var rest := line.trim_prefix("##STEP ")
		progress.emit(tr("Step %s: %s...") % [rest.get_slice(" ", 0), rest.substr(rest.find(" ") + 1)])
	elif line.begins_with("##RESULT "):
		var parts := line.trim_prefix("##RESULT ").split("|")
		if parts.size() == 2:
			results[parts[0]] = parts[1] == "ok"
	elif not line.begins_with("##") and line.strip_edges() != "":
		print("[import] ", line)


## Every staged <kind>/<folder>/<name>.obj becomes <target><folder>/<name>.tres.
func _convert_staged(kind: String, target: String) -> void:
	var root := STAGING_DIR + kind + "/"
	for folder in DirAccess.get_directories_at(root):
		for file_name in DirAccess.get_files_at(root + folder):
			if file_name.get_extension() != "obj":
				continue
			progress.emit(tr("Converting models... %s (%s)") % [folder, file_name.get_basename()])
			await get_tree().process_frame
			var mesh := ObjMeshBuilder.build(root + folder + "/" + file_name)
			var out_dir := target + folder
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
			if mesh != null and ResourceSaver.save(mesh, out_dir + "/" + file_name.get_basename() + ".tres") == OK:
				meshes_converted += 1
			else:
				meshes_failed += 1


static func _remove_folder(path: String) -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(file_name)))
	for folder in DirAccess.get_directories_at(path):
		_remove_folder(path.path_join(folder))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
