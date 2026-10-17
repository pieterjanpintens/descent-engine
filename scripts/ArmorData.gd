class_name ArmorData
extends RefCounted

## The game's armor cards, read from the user's own export (tools/asset_import/import_item_data.py ->
## user://item_data/items.json). Never instantiated; without the export there are none. An armor is only a card: its rule
## text is resolved by the table (the engine does not apply armor effects), so the app only tracks WHO OWNS it, whether it
## is upgraded ("+" side up, kept in CampaignState.upgraded_cards like the weapon cards) and what it costs.
##
## An armor is identified by its BASE id ("ARMOR_10"); its "+" side is ARMOR_10_PLUS in the data. Class (Heavy / Medium /
## Light) is the first words of the card text ("Armor Card—Light.").

const ITEMS_PATH := "user://item_data/items.json"

static var _loaded := false
static var _base: Array[Dictionary] = []  # base armors: {id, name, armor_class, text, plus_text, price, xp, act}
static var _by_id: Dictionary = {}


static func available() -> bool:
	_load()
	return not _base.is_empty()


## Every base armor, act I first, in the game's order.
static func all() -> Array[Dictionary]:
	_load()
	return _base


static func find(armor_id: String) -> Dictionary:
	_load()
	return _by_id.get(armor_id, {})


static func is_armor(card_id: String) -> bool:
	return card_id.begins_with("ARMOR_")


static func reload() -> void:
	_loaded = false
	_base = []
	_by_id = {}


## "Duskplate (Heavy)" - the armor's name and class; the id itself when unknown.
static func label(armor_id: String) -> String:
	var armor := find(armor_id)
	if armor.is_empty():
		return armor_id
	return "%s (%s)" % [armor["name"], armor["armor_class"]]


## The rule text without the class prefix; the "+" side's text when `upgraded`.
static func rule_text(armor_id: String, upgraded: bool = false) -> String:
	var armor := find(armor_id)
	if armor.is_empty():
		return ""
	return str(armor["plus_text"] if upgraded else armor["text"])


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(ITEMS_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_PATH))
	if not data is Dictionary:
		return
	var armors: Array = data.get("armors", [])
	var plus_text := {}
	for raw: Dictionary in armors:
		if int(raw.get("IsUpgrade", 0)) == 1:
			plus_text[str(raw.get("BaseItemId", ""))] = ItemData.text(str(raw.get("KeyDescription", "")))
	for raw: Dictionary in armors:
		if int(raw.get("IsUpgrade", 0)) == 1:
			continue
		var full := ItemData.text(str(raw.get("KeyDescription", "")))
		var armor_class := "Armor"
		var body := full
		var found := RegEx.create_from_string("^Armor Card\\W+(\\w+)\\.?\\s*").search(full)
		if found != null:
			armor_class = found.get_string(1)
			body = full.substr(found.get_end()).strip_edges()
		var id := str(raw["_id"])
		var plus_full: String = plus_text.get(id, full)
		var plus_found := RegEx.create_from_string("^Armor Card\\W+(\\w+)\\.?\\s*").search(plus_full)
		var armor := {
			"id": id,
			"name": str(raw.get("m_Name", id)),
			"armor_class": armor_class,
			"text": body,
			"plus_text": plus_full.substr(plus_found.get_end()).strip_edges() if plus_found != null else plus_full,
			"price": int(raw.get("Value", 0)),
			"xp": int(raw.get("XPRequiredForDrop", 99)),
			"act": int(raw.get("_act", 0)),
		}
		_base.append(armor)
		_by_id[id] = armor
