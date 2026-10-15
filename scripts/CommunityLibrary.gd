class_name CommunityLibrary
extends RefCounted

## The shared missions and campaigns installed on this computer - every package is checked first (SharePackage.read), then
## installed SIDE BY SIDE: each version gets its own copy under its own name, so a saved game stays with the exact version it was
## played on, a copy you edited is never overwritten, and nothing has to be migrated.
##   mission  -> user://missions/community/<key>.tres
##   campaign -> user://campaigns/<key>/   (it shows in the campaign library like any other campaign)
## The list of what is installed (and where from) is user://community/installed.json. The version is added to the name inside the
## file ("The Lost Scroll (v1.1.0)"), so two versions can be told apart in the menus. Never instantiated.

const ROOT := "user://community"
const REGISTRY := "user://community/installed.json"
const MISSIONS_DIR := "user://missions/community"
## The package file of every release made from the player's own drafts - exactly what was installed, so export/publish ship the same bytes.
const RELEASES_DIR := "user://community/releases"


## The folder / file name of one version of a package.
static func key_for(id: String, version: String) -> String:
	return ("%s__v%s" % [id, version]).replace(".", "_")


## Every installed package, newest install last. Entries whose files were deleted by hand are dropped.
static func installed() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not FileAccess.file_exists(REGISTRY):
		return entries
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY))
	if typeof(parsed) != TYPE_ARRAY:
		return entries
	var pruned := false
	for item: Variant in parsed:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var path := str(entry.get("path", ""))
		var exists := FileAccess.file_exists(path) if entry.get("type", "") == SharePackage.TYPE_MISSION else DirAccess.dir_exists_absolute(path)
		if exists:
			entries.append(entry)
		else:
			pruned = true
	if pruned:
		_save(entries)
	return entries


static func find(id: String, version: String) -> Dictionary:
	for entry in installed():
		if entry.get("id", "") == id and entry.get("version", "") == version:
			return entry
	return {}


## The entry whose files are at `path` (a campaign folder path or a mission file path), {} when `path` is not a release.
static func entry_for_path(path: String) -> Dictionary:
	for entry in installed():
		if entry.get("path", "") == path:
			return entry
	return {}


## "Finding the lost Scroll (v1.0.0)" -> "Finding the lost Scroll": installing adds the version to the name of a copy.
static func strip_version_suffix(package_name: String) -> String:
	return RegEx.create_from_string("\\s*\\(v[0-9]+(\\.[0-9]+){0,3}\\)\\s*$").sub(package_name, "").strip_edges()


## "1.0.0" -> "1.0.1", "1.2" -> "1.3": the last number goes up.
static func next_version(version: String) -> String:
	var parts := version.split(".")
	if parts.is_empty() or not parts[-1].is_valid_int():
		return version
	parts[-1] = str(int(parts[-1]) + 1)
	return ".".join(parts)


## The package file of a release made here, "" when there is none (an installed community package has none).
static func package_file_for(entry: Dictionary) -> String:
	var path := "%s/%s.%s" % [RELEASES_DIR, key_for(str(entry.get("id", "")), str(entry.get("version", ""))), SharePackage.EXTENSION]
	return path if FileAccess.file_exists(path) else ""


## Freezes a draft CAMPAIGN as a release: builds the package, checks it the way an importer does and installs it side by side.
## `meta` is SharePackage's (name, author, description, version, rights_confirmed) plus "id". Result {ok, error, entry, package_path}.
static func release_campaign(folder: String, meta: Dictionary) -> Dictionary:
	return _release(meta, func(out: String) -> Array[String]: return SharePackage.build_campaign(folder, meta, out))


## The same for a MISSION (the one open in the editor, as it is now).
static func release_mission(mission: MissionData, meta: Dictionary) -> Dictionary:
	return _release(meta, func(out: String) -> Array[String]: return SharePackage.build_mission(mission, meta, out))


static func _release(meta: Dictionary, build: Callable) -> Dictionary:
	var id := str(meta.get("id", ""))
	var version := str(meta.get("version", ""))
	if id == "" or not find(id, version).is_empty():
		return {"ok": false, "error": "Version %s of this package is already released - a release is never replaced. Use a higher version." % version}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RELEASES_DIR))
	var out := "%s/%s.%s" % [RELEASES_DIR, key_for(id, version), SharePackage.EXTENSION]
	var problems: Array[String] = build.call(out)
	if not problems.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out))
		return {"ok": false, "error": "The release could not be made:\n\n- %s" % "\n- ".join(problems.slice(0, 8))}
	var package := SharePackage.read(out)
	if not package["ok"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out))
		return {"ok": false, "error": "The release did not pass the package check:\n\n- %s" % "\n- ".join(package["errors"].slice(0, 8))}
	var result := install(package, "own")
	if not result["ok"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out))
		return result
	result["package_path"] = out
	return result


## Copies the released mission file `source` into a new draft `user://missions/<name>.tres` and returns its path ("" on failure).
static func fork_mission(source: String, new_name: String) -> String:
	var mission := MissionIO.load_mission(source)
	if mission == null:
		return ""
	var base := CampaignIO.key_for(new_name)
	if base == "":
		base = "mission"
	var path := "user://missions/%s.tres" % base
	var number := 2
	while FileAccess.file_exists(path):
		path = "user://missions/%s_%d.tres" % [base, number]
		number += 1
	mission.mission_name = new_name
	return path if MissionIO.save_mission(mission, path) else ""


## Every installed version of one package id.
static func versions_of(id: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry in installed():
		if entry.get("id", "") == id:
			found.append(entry)
	return found


## The highest installed version of `id`, "" when none.
static func newest_version(id: String) -> String:
	var newest := ""
	for entry in versions_of(id):
		if newest == "" or compare_versions(str(entry["version"]), newest) > 0:
			newest = str(entry["version"])
	return newest


## -1 / 0 / 1 for "1.2" vs "1.10.0" style versions (missing parts count as 0).
static func compare_versions(a: String, b: String) -> int:
	var left := a.split(".")
	var right := b.split(".")
	for i in maxi(left.size(), right.size()):
		var x := int(left[i]) if i < left.size() else 0
		var y := int(right[i]) if i < right.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0


## Installs a package that SharePackage.read() accepted. Result: {ok, error, already, entry}.
static func install(package: Dictionary, source := "") -> Dictionary:
	var manifest: Dictionary = package["manifest"]
	var files: Dictionary = package["files"]
	var id: String = manifest["id"]
	var version: String = manifest["version"]
	if not find(id, version).is_empty():
		return {"ok": false, "already": true, "error": "Version %s is already installed." % version}

	var key := key_for(id, version)
	var is_mission: bool = manifest["type"] == SharePackage.TYPE_MISSION
	var path := "%s/%s.tres" % [MISSIONS_DIR, key] if is_mission else CampaignIO.folder_path(key)
	if (is_mission and FileAccess.file_exists(path)) or (not is_mission and DirAccess.dir_exists_absolute(path)):
		return {"ok": false, "error": "Something with the same name is already in the way: %s." % path}

	DirAccess.make_dir_recursive_absolute(path.get_base_dir() if is_mission else path)
	var written := true
	for file_name: String in files:
		var data: PackedByteArray = files[file_name]
		var target := path if is_mission else "%s/%s" % [path, file_name]
		if file_name == SharePackage.MISSION_FILE:
			data = _with_version_in_name(data, "mission_name", version)
		elif file_name == SharePackage.CAMPAIGN_FILE:
			data = _with_version_in_name(data, "campaign_name", version)
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			written = false
			break
		file.store_buffer(data)
		file.close()
	if not written:
		_delete_files(path, is_mission)
		return {"ok": false, "error": "The files could not be written (error %d)." % FileAccess.get_open_error()}

	var entry := {
		"id": id,
		"version": version,
		"type": manifest["type"],
		"name": manifest["name"],
		"author": manifest["author"],
		"description": manifest["description"],
		"rights_confirmed": manifest["rights_confirmed"],
		"path": path,
		"source": source,
		"installed": Time.get_datetime_string_from_system(true),
	}
	var entries := installed()
	entries.append(entry)
	_save(entries)
	return {"ok": true, "entry": entry}


## Removes one installed version (for a campaign: its folder; its save games are moved to user://campaign_saves/_removed/).
static func remove(entry: Dictionary) -> void:
	var is_mission: bool = entry.get("type", "") == SharePackage.TYPE_MISSION
	var path := str(entry.get("path", ""))
	# only ever delete inside the places this class installs to
	if is_mission and path.begins_with(MISSIONS_DIR + "/"):
		_delete_files(path, true)
	elif not is_mission and path.begins_with(CampaignIO.ROOT + "/"):
		_delete_files(path, false)
		# save games are moved aside, never deleted (CampaignIO.archive_saves)
		CampaignIO.archive_saves(path.get_file())
	var package_file := package_file_for(entry)
	if package_file != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(package_file))
	var remaining: Array[Dictionary] = []
	for other in installed():
		if other.get("path", "") != path:
			remaining.append(other)
	_save(remaining)


static func _delete_files(path: String, is_file: bool) -> void:
	if is_file:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [path, file_name]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _save(entries: Array[Dictionary]) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	var file := FileAccess.open(REGISTRY, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(entries, "\t"))
		file.close()


## Adds " (v<version>)" to the name stored in the file (`property` = "mission_name" / "campaign_name") - a name left at its default is
## not stored at all and stays as it is.
static func _with_version_in_name(data: PackedByteArray, property: String, version: String) -> PackedByteArray:
	var text := data.get_string_from_utf8()
	var found := RegEx.create_from_string("(?m)^" + property + " = \"((?:[^\"\\\\]|\\\\.)*)\"").search(text)
	if found == null:
		return data
	var changed := text.substr(0, found.get_end(1)) + " (v" + version + ")" + text.substr(found.get_end(1))
	return changed.to_utf8_buffer()
