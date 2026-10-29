class_name ItemData
extends RefCounted

## The game's item data (potions/consumables, ...) from the user's own export (tools/asset_import/import_item_data.py ->
## user://item_data/). Nothing of it ships with the project; without the export every lookup comes back empty.

static var _loaded := false
static var _consumables: Array = []
static var _trinkets: Array = []
static var _texts: Dictionary = {}
static var _attack: Dictionary = {}  ## game key -> {key, name, text} (activation abilities)
static var _defense: Dictionary = {}  ## game key -> {key, name, text, after, enemies}
static var _images: Dictionary = {}  ## picture path -> Texture2D (or null: not exported)
static var _order_key := ""  ## the reading order the texts were last checked for
static var _loaded_stamp := ""  ## the texts the loaded data was built from
static var _text_language := ""  ## the languages the loaded texts are in (item export | weapon export)


## The game's texts follow the language of the content being played (the reading order of LText): the importers write one
## localization_<code>.json per game language and the first language of the reading order that has a file is used (English otherwise;
## a key missing in that language falls back to English). The classes that build things from the texts (WeaponData, ArmorData, ...) compare
## this stamp in their _load() with the one they were built for and read everything again when it is another (no class reference back
## to them from here: static classes referring to each other in a loop crash the script VM).
static func text_stamp() -> String:
	var order_key := ",".join(LText.reading_order())
	if order_key != _order_key:
		_order_key = order_key
		_text_language = text_language("user://item_data/") + "|" + text_language("user://weapon_data/")
	return _text_language


## The language code the texts of an export folder are read in.
static func text_language(directory: String) -> String:
	for code in LText.reading_order():
		if FileAccess.file_exists("%slocalization_%s.json" % [directory, code]):
			return code
	return "en"


## The texts of an export folder in the current language (missing keys filled in from English).
static func load_texts(directory: String) -> Dictionary:
	var texts: Dictionary = {}
	var english = _read("%slocalization_en.json" % directory)
	if english is Dictionary:
		texts = english.duplicate()
	var code := text_language(directory)
	if code != "en":
		var own = _read("%slocalization_%s.json" % [directory, code])
		if own is Dictionary:
			texts.merge(own, true)
	return texts


## A picture of an armor, material, consumable or trinket from the user's own export (import_item_data.py writes them to
## user://item_data/images/ under the game's path, lower case, without the leading "d3/"); `path` is the item's
## TextureAssetPath. null when it isn't there.
static func image_for(path: String) -> Texture2D:
	if path == "":
		return null
	if _images.has(path):
		return _images[path]
	var relative := path.to_lower()
	if relative.begins_with("d3/"):
		relative = relative.substr(3)
	var file := "user://item_data/images/" + relative
	var texture: Texture2D = null
	if FileAccess.file_exists(file):
		var image := Image.load_from_file(file)
		if image != null:
			texture = ImageTexture.create_from_image(image)
	_images[path] = texture
	return texture


## The picture of a crafting material by its key ("metal").
static func material_image(key: String) -> Texture2D:
	return image_for("d3/crafting materials/%s/%s.png" % [key, key])


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


## The raw consumable entries of the export (ConsumableData normalises them).
static func consumable_entries() -> Array:
	_load()
	return _consumables


## The raw trinket entries of the export (TrinketData normalises them).
static func trinket_entries() -> Array:
	_load()
	return _trinkets


## The cleaned game text of a localization key ("" when unknown).
static func text_for(key: String) -> String:
	_load()
	return _clean(str(_texts.get(key, "")))


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


## Every activation ability of the game (what an enemy does on its own turn: "Sentinel: ...", "Mend: ..."): [{key, name,
## text}], sorted by name. The texts keep their {0}/{1} placeholders - see fill_activation().
static func attack_abilities() -> Array[Dictionary]:
	_load()
	var result: Array[Dictionary] = []
	for key: String in _attack:
		result.append(_attack[key])
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	return result


## Any text of the export by its key, as plain text ("" when unknown).
static func text(key: String) -> String:
	_load()
	return _clean(str(_texts.get(key, "")))


## A tactic's text with its {N} placeholders filled. The game uses them differently from text to text: an index written
## "the {N}" is the monster, the lowest other index is the hero, anything else (a number the data doesn't give) "[number]".
static func fill_tactic(text: String, monster_name: String, hero_name: String) -> String:
	var monster_indices := {}
	for found in RegEx.create_from_string("(?i)\\bthe \\{(\\d)\\}").search_all(text):
		monster_indices[found.get_string(1)] = true
	var others: Array[String] = []
	for found in RegEx.create_from_string("\\{(\\d)\\}").search_all(text):
		var index := found.get_string(1)
		if not monster_indices.has(index) and not others.has(index):
			others.append(index)
	others.sort()
	var result := text
	for index: String in monster_indices:
		result = result.replace("{%s}" % index, monster_name)
	for position in others.size():
		result = result.replace("{%s}" % others[position], hero_name if position == 0 else "[number]")
	return result


## One activation ability by its game key ({} when unknown or there is no export).
static func attack_ability(key: String) -> Dictionary:
	_load()
	return _attack.get(key, {})


## The text with its placeholders filled in. In the game {0} is nearly always the monster and {1} a hero, but a few texts
## use them differently (decided with the user): Mend / Stitched {1} = the amount, 3 x the monster's level; Undeath {0} =
## a percentage, 5 x the level, and {1} = the monster; the Levirax texts {0} = the target hero.
static func fill_activation(key: String, text: String, monster_name: String, hero_name: String, level: int) -> String:
	var first := monster_name
	var second := hero_name
	if key == "ENEMY_ACTIVATION_ZEALOT_BASIC" or key == "ENEMY_ACTIVATION_ZEALOT_DREAD_BASIC":
		second = str(level * 3)
	elif key == "ENEMY_ACTIVATION_WIGHT_BASIC_2":
		first = str(level * 5)
		second = monster_name
	elif key.begins_with("ENEMY_ACTIVATION_BOSS_LEVIRAX_"):
		first = hero_name
	return text.replace("{0}", first).replace("{1}", second)


## One defense ability by its game key ({} when unknown or there is no export).
static func defense_ability(key: String) -> Dictionary:
	_load()
	return _defense.get(key, {})


static func _load() -> void:
	var stamp := text_stamp()
	if stamp != _loaded_stamp:
		_loaded_stamp = stamp
		_loaded = false
		_texts = {}
		_attack = {}
		_defense = {}
	if _loaded:
		return
	_loaded = true
	var items = _read("user://item_data/items.json")
	if items is Dictionary:
		_consumables = items.get("consumables", [])
		_trinkets = items.get("trinkets", [])
	_texts = load_texts("user://item_data/")
	for key: String in _texts:
		if key.begins_with("ENEMY_ACTIVATION_"):
			var shown := _clean(str(_texts[key]))
			var colon := shown.find(":")
			# an ability reads "Name: what it does"; the long story texts of the activations have no short name before a colon
			if colon > 0 and colon < 40 and shown.substr(0, colon).find(".") < 0:
				_attack[key] = {"key": key, "name": shown.substr(0, colon), "text": shown}
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
