class_name ItemData
extends RefCounted

## The game's item data (potions/consumables, ...) from the user's own export (tools/asset_import/import_item_data.py ->
## user://item_data/). Nothing of it ships with the project; without the export every lookup comes back empty.

static var _loaded := false
static var _consumables: Array = []
static var _texts: Dictionary = {}


## The display name of a random consumable: a base one, or an upgraded ("+") one when `upgraded`. Any of them can come
## up (hero limits are ignored). "" when the export isn't there.
static func random_consumable(upgraded: bool) -> String:
	_load()
	var pool: Array[String] = []
	for entry: Dictionary in _consumables:
		if bool(int(entry.get("IsUpgrade", 0))) == upgraded:
			var shown := _clean(str(_texts.get(entry.get("KeyName", ""), "")))
			if shown != "":
				pool.append(shown)
	if pool.is_empty():
		return ""
	return pool.pick_random() + (" +" if upgraded else "")


static func _clean(text: String) -> String:
	var markup := RegEx.create_from_string("<[^>]*>")
	var shown := markup.sub(text, "", true)
	var cleaned := ""
	for i in shown.length():
		var code := shown.unicode_at(i)
		if code < 0xE000 or code > 0xF8FF:  # private-use icon glyphs of the game's texts
			cleaned += shown[i]
	return cleaned.strip_edges()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var items = _read("user://item_data/items.json")
	if items is Dictionary:
		_consumables = items.get("consumables", [])
	var texts = _read("user://item_data/localization_en.json")
	if texts is Dictionary:
		_texts = texts


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
