class_name AppUpdater
extends Downloader

## Updating the app itself. Released builds know their version (the release workflow writes the tag into
## `application/config/version`), ask GitHub once per run whether a newer release exists (check()), and on a click download
## the zip for their platform, verify it against the release's SHA256SUMS.txt (download_and_stage()), and swap the files with a
## small helper script that waits for this process to end, keeps a backup of what it replaces, copies the new files over and
## starts the app again (apply()). Nothing happens without a click, and a build run from the editor, a renamed or read-only
## install only gets the release page opened. The checksum proves the download arrived intact - the builds are not code-signed,
## so TLS to GitHub is what vouches for who made them.
## Add as a child of something in the tree; status text arrives via `progress`.

const REPO := "pieterjanpintens/descent-engine"
const EXPORT_NAME := "Descent-Engine"
const DIR := "user://updates"
const SUMS_FILE := "SHA256SUMS.txt"
const MAX_ZIP_BYTES := 500 * 1048576
const MAX_TEXT_BYTES := 2 * 1048576

## Result of the one check made in this run (so going back to the main menu doesn't ask GitHub again).
static var last_check: Dictionary = {}

var api_url := "https://api.github.com/repos/%s/releases/latest" % REPO
## Test seams: install somewhere else / start something else afterwards / pretend to be a given platform.
var install_dir_override := ""
var launch_name_override := ""
var platform_override := ""


## "0.0.18" for a released build, "" for everything else (editor, a manual workflow run stamped "dev").
static func current_version() -> String:
	var text := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges().trim_prefix("v")
	return text if RegEx.create_from_string("^[0-9]+(\\.[0-9]+){0,3}$").search(text) != null else ""


static func is_newer(tag: String, current: String) -> bool:
	if current == "":
		return false
	return CommunityLibrary.compare_versions(tag.trim_prefix("v"), current) > 0


## Downloads only come from https; the test seam lets a local test server stand in for GitHub.
var allow_http_for_tests := false


func _url_prefix() -> String:
	return "http" if allow_http_for_tests else "https://"


func platform() -> String:
	if platform_override != "":
		return platform_override
	match OS.get_name():
		"Windows":
			return "windows"
		"macOS":
			return "macos"
		_:
			return "linux"


## The release file for this platform.
func asset_name() -> String:
	return "%s-%s.zip" % [EXPORT_NAME, platform()]


## The folder that is replaced: the app's folder (Windows / Linux) or the .app bundle (macOS).
func install_dir() -> String:
	if install_dir_override != "":
		return install_dir_override
	var executable := OS.get_executable_path()
	if platform() == "macos":
		return executable.get_base_dir().get_base_dir().get_base_dir()
	return executable.get_base_dir()


## The file the app is started with after an update.
func launch_name() -> String:
	if launch_name_override != "":
		return launch_name_override
	return "%s.app" % EXPORT_NAME if platform() == "macos" else _main_file()


func _main_file() -> String:
	return "%s.exe" % EXPORT_NAME if platform() == "windows" else "%s.x86_64" % EXPORT_NAME


## Why this install can't be updated by the app itself ("" = it can).
func cannot_install_reason() -> String:
	if install_dir_override == "":
		if OS.has_feature("editor"):
			return "this is a development build"
		var executable := OS.get_executable_path().get_file()
		if platform() != "macos" and executable != _main_file():
			return "the app file was renamed"
		if platform() == "macos" and not install_dir().ends_with(".app"):
			return "it is not running from an app bundle"
	var probe := install_dir().path_join(".update_write_test")
	var file := FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return "the app folder can't be written to"
	file.close()
	DirAccess.remove_absolute(probe)
	return ""


## Asks GitHub for the latest release. {ok, error, tag, notes, page, assets {name: url}, newer, blocked (why it can't self-install or "")}.
## Keeps the answer in `last_check`.
func check() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var file := DIR.path_join("latest.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	if not await _fetch(api_url, file, "", "the release information", MAX_TEXT_BYTES):
		return {"ok": false, "error": "Could not reach GitHub."}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("tag_name"):
		return {"ok": false, "error": "GitHub's answer was not understood."}
	var release: Dictionary = parsed
	var assets := {}
	var listed: Variant = release.get("assets", [])
	if typeof(listed) == TYPE_ARRAY:
		for item: Variant in listed:
			if typeof(item) == TYPE_DICTIONARY and str(item.get("browser_download_url", "")).begins_with(_url_prefix()):
				assets[str(item.get("name", ""))] = str(item["browser_download_url"])
	var tag := str(release["tag_name"])
	var result := {
		"ok": true, "error": "", "tag": tag, "notes": str(release.get("body", "")), "page": str(release.get("html_url", "")),
		"assets": assets, "newer": is_newer(tag, current_version()), "blocked": cannot_install_reason(),
	}
	last_check = result
	return result


## True while some updater is downloading/unpacking an update - only one may run at a time.
static var _staging := false
var _owns_staging := false


## Downloads and verifies the new version for this platform and unpacks it into a staging folder.
## {ok, error, staged (an absolute path)}. Refused while another update download is running.
func download_and_stage(release: Dictionary) -> Dictionary:
	if _staging:
		return {"ok": false, "error": "An update is already being downloaded."}
	_staging = true
	_owns_staging = true
	var result := await _download_and_stage(release)
	_staging = false
	_owns_staging = false
	return result


func _exit_tree() -> void:
	super()
	if _owns_staging:
		_staging = false
		_owns_staging = false


func _download_and_stage(release: Dictionary) -> Dictionary:
	var assets: Dictionary = release.get("assets", {})
	var name := asset_name()
	if not assets.has(name) or not assets.has(SUMS_FILE):
		return {"ok": false, "error": "This release has no %s (or no checksum list)." % name}
	var folder := DIR.path_join(str(release["tag"]).validate_filename())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var sums_path := folder.path_join(SUMS_FILE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sums_path))
	if not await _fetch(str(assets[SUMS_FILE]), sums_path, "", "the checksum list", MAX_TEXT_BYTES):
		return {"ok": false, "error": "The checksum list could not be downloaded."}
	var expected := checksum_for(FileAccess.get_file_as_string(sums_path), name)
	if expected == "":
		return {"ok": false, "error": "The release's checksum list has no entry for %s." % name}
	var archive := folder.path_join(name)
	if not await _fetch(str(assets[name]), archive, expected, "the update", MAX_ZIP_BYTES):
		return {"ok": false, "error": "The update could not be downloaded or did not match its checksum."}
	var staged := folder.path_join("staged")
	_remove_tree(ProjectSettings.globalize_path(staged))
	if not _extract(archive, staged):
		return {"ok": false, "error": "The update could not be unpacked."}
	var main := ProjectSettings.globalize_path(staged).path_join(launch_name())
	if platform() == "macos":
		if not DirAccess.dir_exists_absolute(main):
			return {"ok": false, "error": "The update does not contain %s." % launch_name()}
	elif not FileAccess.file_exists(main):
		return {"ok": false, "error": "The update does not contain %s." % launch_name()}
	return {"ok": true, "error": "", "staged": ProjectSettings.globalize_path(staged)}


## The hash listed for `file_name` in the text of a SHA256SUMS.txt ("<hash>  <name>" per line), "" when it is not there.
static func checksum_for(sums: String, file_name: String) -> String:
	for line in sums.split("\n"):
		var text := line.strip_edges()
		var split := text.find(" ")
		if split < 40:
			continue
		var hash := text.substr(0, split).to_lower()
		var listed := text.substr(split).strip_edges().trim_prefix("*")
		if listed == file_name and RegEx.create_from_string("^[0-9a-f]{64}$").search(hash) != null:
			return hash
	return ""


func _extract(archive: String, staged: String) -> bool:
	var target := ProjectSettings.globalize_path(staged)
	DirAccess.make_dir_recursive_absolute(target)
	if platform() == "macos":
		# ditto keeps the executable bits, the links and the signature of the bundle
		var code := OS.execute("/usr/bin/ditto", ["-x", "-k", ProjectSettings.globalize_path(archive), target], [], true)
		return code == 0
	if not _unzip(archive, staged, "update"):
		return false
	if platform() == "linux":
		OS.execute("chmod", ["+x", target.path_join(_main_file())], [], true)
	return true


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


## Writes the helper script and starts it; the caller must quit the app right after (the script waits for this process to end).
## `staged` = the folder (or on macOS the .app) unpacked by download_and_stage(). False (with a `progress` text) on failure.
func apply(staged: String, process_id := -1) -> bool:
	var pid := process_id if process_id >= 0 else OS.get_process_id()
	var script_dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(script_dir)
	var backup := script_dir.path_join("backup")
	var destination := install_dir()
	var script_path := ""
	var command := ""
	var arguments: PackedStringArray = []
	match platform():
		"windows":
			script_path = script_dir.path_join("update.bat")
			_write(script_path, _windows_script(pid, staged, destination, backup, launch_name()))
			command = "cmd.exe"
			arguments = ["/c", script_path.replace("/", "\\")]
		_:
			script_path = script_dir.path_join("update.sh")
			_write(script_path, _unix_script(pid, staged, destination, backup, launch_name(), platform() == "macos"))
			command = "/bin/sh"
			arguments = [script_path]
	if not FileAccess.file_exists(script_path):
		progress.emit("Couldn't write the update script.")
		return false
	return OS.create_process(command, arguments) > 0


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


static func _windows_script(pid: int, staged: String, destination: String, backup: String, launch: String) -> String:
	var src := staged.replace("/", "\\")
	var dst := destination.replace("/", "\\")
	var bak := backup.replace("/", "\\")
	var lines: PackedStringArray = [
		"@echo off",
		"set \"PID=%d\"" % pid,
		"set \"SRC=%s\"" % src,
		"set \"DST=%s\"" % dst,
		"set \"BAK=%s\"" % bak,
		"set \"EXE=%s\"" % launch,
		"set /a N=0",
		":wait",
		"tasklist /FI \"PID eq %PID%\" 2>nul | find \"%PID%\" >nul",
		"if errorlevel 1 goto swap",
		"set /a N+=1",
		"if %N% GTR 90 exit /b 2",
		"ping -n 2 127.0.0.1 >nul",
		"goto wait",
		":swap",
		"if exist \"%BAK%\" rmdir /S /Q \"%BAK%\"",
		"mkdir \"%BAK%\"",
		"for %%F in (\"%SRC%\\*\") do if exist \"%DST%\\%%~nxF\" copy /Y \"%DST%\\%%~nxF\" \"%BAK%\\\" >nul",
		"xcopy /Y /Q /E \"%SRC%\\*\" \"%DST%\\\" >nul",
		"if errorlevel 1 goto restore",
		"start \"\" \"%DST%\\%EXE%\"",
		"exit /b 0",
		":restore",
		"xcopy /Y /Q /E \"%BAK%\\*\" \"%DST%\\\" >nul",
		"start \"\" \"%DST%\\%EXE%\"",
		"exit /b 1",
	]
	return "\r\n".join(lines) + "\r\n"


static func _unix_script(pid: int, staged: String, destination: String, backup: String, launch: String, bundle: bool) -> String:
	var lines: PackedStringArray = [
		"#!/bin/sh",
		"PID=%d" % pid,
		"SRC='%s'" % staged,
		"DST='%s'" % destination,
		"BAK='%s'" % backup,
		"EXE='%s'" % launch,
		"n=0",
		"while kill -0 \"$PID\" 2>/dev/null; do",
		"  n=$((n+1))",
		"  [ $n -gt 90 ] && exit 2",
		"  sleep 1",
		"done",
		"rm -rf \"$BAK\"",
	]
	if bundle:
		lines.append_array([
			"mv \"$DST\" \"$BAK\" || exit 1",
			"if ! /usr/bin/ditto \"$SRC/$EXE\" \"$DST\"; then",
			"  rm -rf \"$DST\"",
			"  mv \"$BAK\" \"$DST\"",
			"fi",
			"open \"$DST\"",
		])
	else:
		lines.append_array([
			"mkdir -p \"$BAK\"",
			"for f in \"$SRC\"/*; do",
			"  b=$(basename \"$f\")",
			"  [ -e \"$DST/$b\" ] && cp -a \"$DST/$b\" \"$BAK/\"",
			"done",
			"if ! cp -a \"$SRC\"/. \"$DST\"/; then",
			"  cp -a \"$BAK\"/. \"$DST\"/",
			"fi",
			"chmod +x \"$DST/$EXE\" 2>/dev/null",
			"nohup \"$DST/$EXE\" >/dev/null 2>&1 &",
		])
	return "\n".join(lines) + "\n"


## Deletes what earlier updates left in user data (downloads, staging) once the app runs that version or a newer one.
static func clean_up() -> void:
	var current := current_version()
	var root := ProjectSettings.globalize_path(DIR)
	if current == "" or not DirAccess.dir_exists_absolute(root):
		return
	for folder in DirAccess.get_directories_at(root):
		if folder == "backup":
			continue
		if CommunityLibrary.compare_versions(folder.trim_prefix("v"), current) <= 0:
			var path := root.path_join(folder)
			for file in DirAccess.get_files_at(path):
				DirAccess.remove_absolute(path.path_join(file))
			var staged := path.path_join("staged")
			if DirAccess.dir_exists_absolute(staged):
				_remove_static(staged)
			DirAccess.remove_absolute(path)


static func _remove_static(path: String) -> void:
	for sub in DirAccess.get_directories_at(path):
		_remove_static(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
