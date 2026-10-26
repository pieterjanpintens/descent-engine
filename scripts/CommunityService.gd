class_name CommunityService
extends Downloader

## Getting shared packages from the web: the catalog (a small index.json kept in this project's GitHub repository, changed by pull
## request so somebody looks at every addition) and the package files it points to - or any https address the player pastes. Every
## download is only a FILE: it is checked by SharePackage before anything is installed (see there). Add as a child of something in
## the tree (it awaits timers); status text arrives via `progress`.
##
## index.json: {"format": 1, "packages": [{id, type, name, author, description, version, url, sha256, size_bytes, languages, duration_minutes}]}

const DEFAULT_CATALOG_URL := "https://raw.githubusercontent.com/pieterjanpintens/descent-engine-community/refs/heads/main/index.json"
## Addresses an earlier version saved as the player's catalog address; they are replaced by the default when settings load.
const OLD_CATALOG_URLS: Array[String] = [
	"https://raw.githubusercontent.com/pieterjanpintens/descent-engine/master/community/index.json",
	"https://raw.githubusercontent.com/pieterjanpintens/descent-engine-community/main/index.json",
]
const CATALOG_FILE := "user://community/index.json"
const DOWNLOAD_FILE := "user://community/download.descentpkg"
const MAX_CATALOG_BYTES := 2 * 1048576


## The address to download from, "" when it is not an https address. A GitHub "blob" page link becomes the raw file.
static func normalize_url(url: String) -> String:
	var text := url.strip_edges()
	if not text.begins_with("https://") or text.contains(" ") or text.length() > 600:
		return ""
	var blob := RegEx.create_from_string("^https://github\\.com/([^/]+)/([^/]+)/blob/(.+)$").search(text)
	if blob != null:
		return "https://raw.githubusercontent.com/%s/%s/%s" % [blob.get_string(1), blob.get_string(2), blob.get_string(3)]
	return text


## Fetches the catalog. {ok, error, entries: Array[Dictionary]} - entries that are not valid are left out.
func fetch_catalog(url: String) -> Dictionary:
	var address := normalize_url(url)
	if address == "":
		return {"ok": false, "error": "The catalog address must start with https://", "entries": []}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CommunityLibrary.ROOT))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CATALOG_FILE))  # _fetch keeps a file that is already there
	if not await _fetch(address, CATALOG_FILE, "", "the community list", MAX_CATALOG_BYTES):
		return {"ok": false, "error": "The community list could not be downloaded.", "entries": []}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CATALOG_FILE))
	if typeof(parsed) != TYPE_DICTIONARY or int((parsed as Dictionary).get("format", 0)) != SharePackage.FORMAT:
		return {"ok": false, "error": "The community list is not in a format this version understands.", "entries": []}
	var entries: Array[Dictionary] = []
	var packages: Variant = (parsed as Dictionary).get("packages", [])
	if typeof(packages) == TYPE_ARRAY:
		for item: Variant in packages:
			var entry := _clean_entry(item)
			if not entry.is_empty():
				entries.append(entry)
	return {"ok": true, "error": "", "entries": entries}


## Downloads a package file (to DOWNLOAD_FILE) - `sha256` "" = not known beforehand (a pasted address). Returns the path, "" on failure.
func download_package(url: String, sha256: String, label: String) -> String:
	var address := normalize_url(url)
	if address == "":
		progress.emit("The address must start with https://")
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CommunityLibrary.ROOT))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DOWNLOAD_FILE))
	if not await _fetch(address, DOWNLOAD_FILE, sha256, label, SharePackage.MAX_PACKAGE_BYTES):
		return ""
	return DOWNLOAD_FILE


static func _clean_entry(item: Variant) -> Dictionary:
	if typeof(item) != TYPE_DICTIONARY:
		return {}
	var raw: Dictionary = item
	var id := str(raw.get("id", ""))
	var version := str(raw.get("version", ""))
	var package_type := str(raw.get("type", ""))
	var url := normalize_url(str(raw.get("url", "")))
	var checksum := str(raw.get("sha256", "")).to_lower()
	if RegEx.create_from_string("^[a-z0-9][a-z0-9._-]{0,79}$").search(id) == null:
		return {}
	if RegEx.create_from_string("^[0-9]+(\\.[0-9]+){0,3}$").search(version) == null:
		return {}
	if package_type != SharePackage.TYPE_MISSION and package_type != SharePackage.TYPE_CAMPAIGN:
		return {}
	if url == "" or RegEx.create_from_string("^[0-9a-f]{64}$").search(checksum) == null:
		return {}
	return {
		"id": id,
		"version": version,
		"type": package_type,
		"name": SharePackage.clean_text(str(raw.get("name", id)), 80),
		"author": SharePackage.clean_text(str(raw.get("author", "")), 60),
		"description": SharePackage.clean_text(str(raw.get("description", "")), 600, true),
		"url": url,
		"sha256": checksum,
		"size_bytes": int(raw.get("size_bytes", 0)),
		"languages": CampaignInfo.clean_languages(raw.get("languages", [])),
		"duration_minutes": CampaignInfo.clean_minutes(raw.get("duration_minutes", 0)),
	}
