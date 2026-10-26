class_name SharePackage
extends RefCounted

## The shareable package of a mission or a campaign: a .descentpkg file = a zip holding manifest.json plus the files.
##   mission  : mission.tres
##   campaign : campaign.tres, the mission .tres files of its chapters and its pictures (png / jpg / webp) - the campaign folder, flat.
## manifest.json: format, type, id (stable between versions), name, author, description, version, rights_confirmed (the author states they
## may share the pictures), files {name: sha256}.
##
## SAFETY - a package comes from somebody else. A .tres file can load scripts and other resources, so nothing is ever LOADED from a
## package before it has been read as plain text and checked here: only the project's own Resource scripts may be referenced, no other
## files, no embedded scripts, no objects. The zip is checked too (sizes from the central directory so a zip bomb is never unpacked, file
## names, types, counts). read() does all of it and returns the verified files; nothing touches the disk until install (CommunityLibrary).
## Never instantiated.

const FORMAT := 1
const EXTENSION := "descentpkg"
const TYPE_MISSION := "mission"
const TYPE_CAMPAIGN := "campaign"
const MANIFEST_FILE := "manifest.json"
const MISSION_FILE := "mission.tres"
const CAMPAIGN_FILE := "campaign.tres"

const MAX_PACKAGE_BYTES := 64 * 1048576
const MAX_TOTAL_BYTES := 160 * 1048576
const MAX_TEXT_BYTES := 8 * 1048576
const MAX_IMAGE_BYTES := 16 * 1048576
const MAX_IMAGE_SIDE := 8192
const MAX_FILES := 200
const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]

## Constructors a .tres value may use. Anything else (Object(...), Resource("path"), Callable...) could load code or other files.
const ALLOWED_CALLS: Array[String] = [
	"Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i", "Color", "Rect2", "Rect2i", "Transform2D", "Transform3D",
	"Basis", "Quaternion", "Plane", "AABB", "Projection", "NodePath", "ExtResource", "SubResource", "Array", "Dictionary",
	"PackedByteArray", "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array", "PackedFloat64Array", "PackedStringArray",
	"PackedVector2Array", "PackedVector3Array", "PackedVector4Array", "PackedColorArray",
]
## Property names a .tres must not set.
const FORBIDDEN_PROPERTIES: Array[String] = ["resource_path", "script/source"]

static var _script_cache: Dictionary = {}


# ------------------------------------------------------------------ reading

## Reads and verifies a package file. Result: {ok, errors: Array[String], manifest: Dictionary, files: Dictionary (name -> bytes)}.
## Only when ok is true may the files be used.
static func read(path: String) -> Dictionary:
	var result := {"ok": false, "errors": [] as Array[String], "manifest": {}, "files": {}}
	var errors: Array[String] = result["errors"]
	if not FileAccess.file_exists(path):
		errors.append("The file does not exist.")
		return result
	var size := _file_size(path)
	if size <= 0 or size > MAX_PACKAGE_BYTES:
		errors.append("The package is empty or larger than %d MB." % (MAX_PACKAGE_BYTES / 1048576))
		return result
	var bytes := FileAccess.get_file_as_bytes(path)
	var index := _zip_index(bytes, errors)
	if not errors.is_empty():
		return result

	# every name and size is checked BEFORE a single entry is unpacked
	var total := 0
	var seen := {}
	for entry: Dictionary in index:
		var entry_name: String = entry["name"]
		var entry_size: int = entry["size"]
		var name_problem := _file_name_problem(entry_name)
		if name_problem != "":
			errors.append("%s: %s" % [entry_name, name_problem])
			continue
		if seen.has(entry_name.to_lower()):
			errors.append("%s: appears twice." % entry_name)
		seen[entry_name.to_lower()] = true
		var limit := MAX_TEXT_BYTES if _is_text(entry_name) else MAX_IMAGE_BYTES
		if entry_size > limit:
			errors.append("%s: too large (%d MB, at most %d MB)." % [entry_name, entry_size / 1048576, limit / 1048576])
		total += entry_size
	if total > MAX_TOTAL_BYTES:
		errors.append("The package is too large when unpacked (more than %d MB)." % (MAX_TOTAL_BYTES / 1048576))
	if not seen.has(MANIFEST_FILE):
		errors.append("There is no %s in the package." % MANIFEST_FILE)
	if not errors.is_empty():
		return result

	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		errors.append("The file is not a valid zip.")
		return result
	var files := {}
	for entry: Dictionary in index:
		var data := reader.read_file(entry["name"])
		if data.size() != int(entry["size"]):
			errors.append("%s: damaged." % entry["name"])
			continue
		files[entry["name"]] = data
	reader.close()
	if not errors.is_empty():
		return result

	var manifest := _parse_manifest((files[MANIFEST_FILE] as PackedByteArray).get_string_from_utf8(), errors)
	if not errors.is_empty():
		return result
	result["manifest"] = manifest
	files.erase(MANIFEST_FILE)

	# the manifest and the files must agree, byte for byte
	var listed: Dictionary = manifest["files"]
	for file_name: String in listed:
		if not files.has(file_name):
			errors.append("%s is listed in the manifest but missing." % file_name)
		elif _sha256(files[file_name]) != str(listed[file_name]).to_lower():
			errors.append("%s does not match its checksum." % file_name)
	for file_name: String in files:
		if not listed.has(file_name):
			errors.append("%s is in the package but not in the manifest." % file_name)
	if not errors.is_empty():
		return result

	_check_contents(manifest["type"], files, errors)
	if errors.is_empty():
		result["ok"] = true
		result["files"] = files
	return result


static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return int(length)


static func _is_text(file_name: String) -> bool:
	return file_name.get_extension().to_lower() in ["tres", "json"]


## "" when the name is fine. A package is flat: no folders, no odd characters.
static func _file_name_problem(file_name: String) -> String:
	if file_name.length() > 96:
		return "the name is too long."
	var pattern := RegEx.create_from_string("^[A-Za-z0-9][A-Za-z0-9 _.()\\-]*$")
	if pattern.search(file_name) == null or file_name.contains("..") or file_name.ends_with(".") or file_name.ends_with(" "):
		return "an unsupported file name."
	var extension := file_name.get_extension().to_lower()
	if file_name == MANIFEST_FILE or extension == "tres" or IMAGE_EXTENSIONS.has(extension):
		return ""
	return "a file of this kind is not allowed in a package."


## The central directory of the zip: [{name, size}] with the UNPACKED sizes, read straight from the bytes (ZIPReader would
## decompress a zip bomb to find out how big it is). Appends to `errors` when the zip is not one we accept.
static func _zip_index(bytes: PackedByteArray, errors: Array[String]) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var eocd := -1
	var i := bytes.size() - 22
	var lowest := maxi(0, bytes.size() - 22 - 65535)
	while i >= lowest:
		if bytes.decode_u32(i) == 0x06054b50:
			eocd = i
			break
		i -= 1
	if eocd < 0:
		errors.append("The file is not a zip.")
		return entries
	var count := bytes.decode_u16(eocd + 10)
	var directory_size := bytes.decode_u32(eocd + 12)
	var directory_offset := bytes.decode_u32(eocd + 16)
	if count == 0xFFFF or directory_size == 0xFFFFFFFF or directory_offset == 0xFFFFFFFF:
		errors.append("Zip64 files are not supported.")
		return entries
	if count > MAX_FILES + 1:
		errors.append("The package holds too many files.")
		return entries
	var position := directory_offset
	for n in count:
		if position < 0 or position + 46 > bytes.size() or bytes.decode_u32(position) != 0x02014b50:
			errors.append("The zip is damaged.")
			return []
		var flags := bytes.decode_u16(position + 8)
		var method := bytes.decode_u16(position + 10)
		var uncompressed := bytes.decode_u32(position + 24)
		var name_length := bytes.decode_u16(position + 28)
		var extra_length := bytes.decode_u16(position + 30)
		var comment_length := bytes.decode_u16(position + 32)
		if position + 46 + name_length > bytes.size():
			errors.append("The zip is damaged.")
			return []
		var entry_name := bytes.slice(position + 46, position + 46 + name_length).get_string_from_utf8()
		position += 46 + name_length + extra_length + comment_length
		if entry_name.ends_with("/"):
			errors.append("%s: folders are not allowed in a package." % entry_name)
			continue
		if flags & 1 != 0:
			errors.append("%s: encrypted files are not allowed." % entry_name)
			continue
		if method != 0 and method != 8:
			errors.append("%s: an unsupported compression." % entry_name)
			continue
		entries.append({"name": entry_name, "size": uncompressed})
	return entries


static func _parse_manifest(text: String, errors: Array[String]) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("manifest.json is not valid.")
		return {}
	var raw: Dictionary = parsed
	if int(raw.get("format", 0)) != FORMAT:
		errors.append("This package has format %s; this version of the app reads format %d." % [str(raw.get("format", "?")), FORMAT])
		return {}
	var package_type := str(raw.get("type", ""))
	if package_type != TYPE_MISSION and package_type != TYPE_CAMPAIGN:
		errors.append("The package is neither a mission nor a campaign.")
	var id := str(raw.get("id", ""))
	if RegEx.create_from_string("^[a-z0-9][a-z0-9._-]{0,79}$").search(id) == null:
		errors.append("The package has no valid id.")
	var version := str(raw.get("version", ""))
	if RegEx.create_from_string("^[0-9]+(\\.[0-9]+){0,3}$").search(version) == null or version.length() > 20:
		errors.append("The package has no valid version number.")
	var files_value: Variant = raw.get("files", null)
	var files := {}
	if typeof(files_value) != TYPE_DICTIONARY or (files_value as Dictionary).is_empty():
		errors.append("The manifest lists no files.")
	else:
		for key: Variant in files_value:
			var hash_text := str((files_value as Dictionary)[key]).to_lower()
			if RegEx.create_from_string("^[0-9a-f]{64}$").search(hash_text) == null:
				errors.append("%s has no valid checksum in the manifest." % str(key))
			files[str(key)] = hash_text
	if not errors.is_empty():
		return {}
	return {
		"format": FORMAT,
		"type": package_type,
		"id": id,
		"version": version,
		"name": clean_text(str(raw.get("name", "")), 80),
		"author": clean_text(str(raw.get("author", "")), 60),
		"description": clean_text(str(raw.get("description", "")), 2000, true),
		"app_version": clean_text(str(raw.get("app_version", "")), 20),
		"rights_confirmed": bool(raw.get("rights_confirmed", false)),
		"languages": CampaignInfo.clean_languages(raw.get("languages", [])),
		"duration_minutes": CampaignInfo.clean_minutes(raw.get("duration_minutes", 0)),
		"files": files,
	}


## Text that comes from a package and is shown to the player: control characters out, length capped.
static func clean_text(text: String, max_length: int, keep_newlines := false) -> String:
	var result := ""
	for character in text:
		var code := character.unicode_at(0)
		if code == 10 and keep_newlines:
			result += character
		elif code >= 32 and code != 127:
			result += character
	result = result.strip_edges()
	return result.substr(0, max_length)


static func _check_contents(package_type: String, files: Dictionary, errors: Array[String]) -> void:
	var main_file := MISSION_FILE if package_type == TYPE_MISSION else CAMPAIGN_FILE
	if not files.has(main_file):
		errors.append("A %s package must contain %s." % [package_type, main_file])
	if package_type == TYPE_MISSION and files.size() != 1:
		errors.append("A mission package contains exactly one file, %s." % MISSION_FILE)
	for file_name: String in files:
		var data: PackedByteArray = files[file_name]
		var extension := file_name.get_extension().to_lower()
		if extension == "tres":
			var expected := "Campaign" if file_name == CAMPAIGN_FILE else "MissionData"
			for problem in validate_resource_text(data.get_string_from_utf8(), expected):
				errors.append("%s: %s" % [file_name, problem])
		else:
			var problem := _image_problem(data)
			if problem != "":
				errors.append("%s: %s" % [file_name, problem])


static func _image_problem(data: PackedByteArray) -> String:
	if data.size() < 16:
		return "not a picture."
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	if data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47:
		error = image.load_png_from_buffer(data)
	elif data[0] == 0xFF and data[1] == 0xD8 and data[2] == 0xFF:
		error = image.load_jpg_from_buffer(data)
	elif data.slice(0, 4).get_string_from_ascii() == "RIFF" and data.slice(8, 12).get_string_from_ascii() == "WEBP":
		error = image.load_webp_from_buffer(data)
	if error != OK or image.is_empty():
		return "not a valid png, jpg or webp picture."
	if image.get_width() > MAX_IMAGE_SIDE or image.get_height() > MAX_IMAGE_SIDE:
		return "the picture is larger than %d pixels." % MAX_IMAGE_SIDE
	return ""


# ------------------------------------------------------------------ the .tres check

## Checks the TEXT of a .tres before anything is loaded from it. `expected_class` is the script class the file must be
## ("MissionData" / "Campaign"). Returns the problems found; empty = the file only uses the project's own data classes.
static func validate_resource_text(text: String, expected_class: String) -> Array[String]:
	var problems: Array[String] = []
	if text.contains(String.chr(0)):
		problems.append("binary data in a text file.")
		return problems
	var scan := _blank_strings(text)
	if scan.is_empty():
		problems.append("the file is not valid (an unfinished text).")
		return problems
	var code: String = scan["code"]
	var seen_header := false
	var seen_resource := false
	var offset := 0  # the code view has the same length as the text, so a line starts at the same place in both
	for code_line_raw in code.split("\n"):
		var line_length := code_line_raw.length()
		var line_start := offset
		offset += line_length + 1
		if not code_line_raw.begins_with("["):
			continue
		var line_number := text.count("\n", 0, line_start) + 1
		var original := text.substr(line_start, line_length).strip_edges(false, true)
		var kind := RegEx.create_from_string("^\\[([a-z_]+)").search(original)
		if kind == null or not original.ends_with("]"):
			problems.append("an unreadable section header (line %d)." % line_number)
			continue
		var attributes := _header_attributes(original)
		match kind.get_string(1):
			"gd_resource":
				if seen_header:
					problems.append("a second file header (line %d)." % line_number)
				seen_header = true
				if attributes.get("type", "") != "Resource" or attributes.get("script_class", "") != expected_class or attributes.get("format", "") != "3":
					problems.append("this is not a %s file." % expected_class)
			"ext_resource":
				if attributes.get("type", "") != "Script":
					problems.append("it refers to a %s, only the app's own scripts may be referred to (line %d)." % [attributes.get("type", "?"), line_number])
				elif not _script_allowed(str(attributes.get("path", ""))):
					problems.append("it refers to a script that is not part of the app: %s (line %d)." % [attributes.get("path", "?"), line_number])
			"sub_resource":
				if attributes.get("type", "") != "Resource":
					problems.append("it contains a %s, which is not allowed (line %d)." % [attributes.get("type", "?"), line_number])
			"resource":
				seen_resource = true
			_:
				problems.append("a [%s] section is not allowed (line %d)." % [kind.get_string(1), line_number])
	if not seen_header:
		problems.append("there is no file header.")
	if not seen_resource:
		problems.append("there is no resource section.")

	# values: only plain data constructors
	var calls := RegEx.create_from_string("([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	for match_result in calls.search_all(code):
		var call_name := match_result.get_string(1)
		if not ALLOWED_CALLS.has(call_name):
			problems.append("it uses %s(...), which is not allowed." % call_name)
			break
	for forbidden in FORBIDDEN_PROPERTIES:
		if RegEx.create_from_string("(?m)^\\s*" + forbidden + "\\s*=").search(code) != null:
			problems.append("it sets %s, which is not allowed." % forbidden)
	return problems


## `text` with the CONTENT of every string and comment blanked out (same length, same line breaks outside strings), so section
## headers and constructor calls can be looked for without a story text fooling the check. {} when a string never ends.
static func _blank_strings(text: String) -> Dictionary:
	var result := PackedStringArray()
	result.resize(text.length())
	var in_string := false
	var i := 0
	var length := text.length()
	while i < length:
		var character := text[i]
		if in_string:
			if character == "\\" and i + 1 < length:
				result[i] = " "
				result[i + 1] = " "
				i += 2
				continue
			if character == "\"":
				in_string = false
				result[i] = "\""
			else:
				result[i] = " "
		elif character == "\"":
			in_string = true
			result[i] = "\""
		elif character == ";":
			while i < length and text[i] != "\n":
				result[i] = " "
				i += 1
			continue
		else:
			result[i] = character
		i += 1
	if in_string:
		return {}
	return {"code": "".join(result)}


## key="value" pairs of a section header line, as strings (quotes removed).
static func _header_attributes(header: String) -> Dictionary:
	var attributes := {}
	var pattern := RegEx.create_from_string("([a-z_]+)=(\"(?:[^\"\\\\]|\\\\.)*\"|[^\\s\\]]+)")
	for match_result in pattern.search_all(header):
		attributes[match_result.get_string(1)] = match_result.get_string(2).trim_prefix("\"").trim_suffix("\"")
	return attributes


## A script a package may refer to: one of the app's own scripts under res://scripts that is a plain Resource.
static func _script_allowed(path: String) -> bool:
	if _script_cache.has(path):
		return _script_cache[path]
	var allowed := false
	if RegEx.create_from_string("^res://scripts/[A-Za-z0-9_]+\\.gd$").search(path) != null and ResourceLoader.exists(path):
		var script := load(path) as GDScript
		allowed = script != null and script.get_instance_base_type() == "Resource"
	_script_cache[path] = allowed
	return allowed


# ------------------------------------------------------------------ building

## What the author part of an id falls back to when no author was filled in. The release dialog no longer allows that, and the
## community publisher refuses such ids (they would all be one shared namespace).
const ANONYMOUS_AUTHOR := "anonymous"


## A stable id for the things an author shares: <author>.<name>, lower case.
static func make_id(author: String, package_name: String) -> String:
	var author_part := _slug(author)
	if author_part == "":
		author_part = ANONYMOUS_AUTHOR
	var name_part := _slug(package_name)
	if name_part == "":
		name_part = "untitled"
	return "%s.%s" % [author_part.substr(0, 30), name_part.substr(0, 40)]


static func _slug(text: String) -> String:
	var slug := ""
	for character in text.strip_edges().to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			slug += character
		elif slug != "" and not slug.ends_with("-"):
			slug += "-"
	return slug.trim_suffix("-")


## Packs a mission into `out_path`. `meta`: {name, author, description, version, rights_confirmed, languages, duration_minutes}. Returns the problems
## (empty = the package was written and checked).
static func build_mission(mission: MissionData, meta: Dictionary, out_path: String) -> Array[String]:
	var temp := "user://community/export_tmp.tres"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://community"))
	var copy: MissionData = mission.duplicate(true)
	if ResourceSaver.save(copy, temp) != OK:
		return ["The mission could not be prepared."]
	var files := {MISSION_FILE: FileAccess.get_file_as_bytes(temp)}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
	return _write(TYPE_MISSION, files, meta, out_path)


## Packs the campaign in user://campaigns/<folder> (every .tres and picture in it) into `out_path`.
static func build_campaign(folder: String, meta: Dictionary, out_path: String) -> Array[String]:
	var files := {}
	for file_name in DirAccess.get_files_at(CampaignIO.folder_path(folder)):
		var extension := file_name.get_extension().to_lower()
		if extension == "tres" or IMAGE_EXTENSIONS.has(extension):
			files[file_name] = FileAccess.get_file_as_bytes("%s/%s" % [CampaignIO.folder_path(folder), file_name])
	if not files.has(CAMPAIGN_FILE):
		return ["This campaign has not been saved yet."]
	return _write(TYPE_CAMPAIGN, files, meta, out_path)


static func _write(package_type: String, files: Dictionary, meta: Dictionary, out_path: String) -> Array[String]:
	var hashes := {}
	for file_name: String in files:
		hashes[file_name] = _sha256(files[file_name])
	var package_name := clean_text(str(meta.get("name", "")), 80)
	var author := clean_text(str(meta.get("author", "")), 60)
	var manifest := {
		"format": FORMAT,
		"type": package_type,
		"id": str(meta["id"]) if str(meta.get("id", "")) != "" else make_id(author, package_name),
		"name": package_name,
		"author": author,
		"description": clean_text(str(meta.get("description", "")), 2000, true),
		"version": str(meta.get("version", "1.0.0")),
		"app_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"rights_confirmed": bool(meta.get("rights_confirmed", false)),
		"languages": CampaignInfo.clean_languages(meta.get("languages", [])),
		"duration_minutes": CampaignInfo.clean_minutes(meta.get("duration_minutes", 0)),
		"created": Time.get_datetime_string_from_system(true),
		"files": hashes,
	}
	var problems: Array[String] = []
	if package_name == "":
		problems.append("The package needs a name.")
		return problems
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var packer := ZIPPacker.new()
	if packer.open(out_path) != OK:
		problems.append("The file could not be written.")
		return problems
	packer.start_file(MANIFEST_FILE)
	packer.write_file(JSON.stringify(manifest, "\t").to_utf8_buffer())
	packer.close_file()
	for file_name: String in files:
		packer.start_file(file_name)
		packer.write_file(files[file_name])
		packer.close_file()
	packer.close()

	# the same check an importer will do
	var check := read(out_path)
	if not check["ok"]:
		DirAccess.remove_absolute(out_path)
		for error: String in check["errors"]:
			problems.append(error)
	return problems


static func _sha256(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()
