class_name ItemData
extends RefCounted

## The game's item data (potions/consumables, ...) from the user's own export (tools/asset_import/import_item_data.py ->
## user://item_data/). Nothing of it ships with the project; without the export every lookup comes back empty.

static var _loaded := false
static var _consumables: Array = []
static var _texts: Dictionary = {}
static var _defense: Dictionary = {}  ## game key -> {key, name, text, after, enemies}


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


## The game's rich-text markup as plain text: `<b>..</b>` and other tags go, a term link around words keeps the words, a
## term link around an icon glyph becomes "[success]" (the glyphs show as boxes in a normal font).
static func _clean(text: String) -> String:
	var icon := RegEx.create_from_string("<link=TERM_([A-Z_]+)>([^<]*)</link>")
	var result := ""
	var last := 0
	for found in icon.search_all(text):
		result += text.substr(last, found.get_start() - last)
		var inner := _without_glyphs(found.get_string(2))
		result += inner if inner != "" else "[%s]" % found.get_string(1).to_lower().replace("_", " ")
		last = found.get_end()
	result += text.substr(last)
	result = RegEx.create_from_string("<[^>]*>").sub(result, "", true)
	return _without_glyphs(result).strip_edges()


static func _without_glyphs(text: String) -> String:
	var cleaned := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code < 0xE000 or code > 0xF8FF:  # private-use icon glyphs of the game's texts
			cleaned += text[i]
	return cleaned


## Every defense ability found in the export (what the game's enemies show when they are attacked): [{key, name, text,
## after (the game shows it after the attack roll), enemies}], sorted by name. Empty without the export.
static func defense_abilities() -> Array[Dictionary]:
	_load()
	var result: Array[Dictionary] = []
	for key: String in _defense:
		result.append(_defense[key])
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	return result


## One defense ability by its game key ({} when unknown or there is no export).
static func defense_ability(key: String) -> Dictionary:
	_load()
	return _defense.get(key, {})


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
	if items is Dictionary:
		for enemy: Dictionary in items.get("enemy_loot", []):
			var key := str(enemy.get("defensive_key", ""))
			var text := _clean(str(_texts.get(key, "")))
			if key == "" or text == "":
				continue
			if not _defense.has(key):
				var colon := text.find(":")
				_defense[key] = {"key": key, "name": text.substr(0, colon) if colon > 0 and colon < 40 else key,
					"text": text, "after": bool(enemy.get("show_defense_after_attack", false)), "enemies": []}
			(_defense[key]["enemies"] as Array).append(str(enemy.get("id", "")).trim_prefix("ENEMY_"))


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
