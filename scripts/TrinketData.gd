class_name TrinketData
extends RefCounted

## The game's trinket cards (20, each with a "+" side), read from the user's own export (ItemData, user://item_data/items.json). Never
## instantiated; without the export there are none. Like armor, a trinket is a card a hero WEARS: the app tracks who owns it, whether it is
## upgraded ("+" side up, CampaignState.upgraded_cards) and - at embark - which hero has it equipped. Its effect is resolved at the table
## for now (nothing applies a trinket yet). A trinket is identified by its BASE id ("TRINKET10_ID"); the "+" side is TRINKET10_ID_PLUS.

static var _loaded := false
static var _stamp := ""  ## the game text language the cached data was built for (ItemData.text_stamp())
static var _base: Array[Dictionary] = []  # {id, name, text, plus_text, price, xp, act, image}
static var _by_id: Dictionary = {}


## The Tarnished Brooch: a campaign gets it only when it defines the monster that goes with it (Campaign.brooch_monster).
const BROOCH_ID := "TRINKET21_ID"
## Defeats of the brooch's monster (by the wearer) it takes to unlock the "+" side.
const BROOCH_DEFEATS_NEEDED := 3


static func is_trinket(card_id: String) -> bool:
	return card_id.begins_with("TRINKET")


static func available() -> bool:
	_load()
	return not _base.is_empty()


## Every base trinket, in the game's order.
static func all() -> Array[Dictionary]:
	_load()
	return _base


static func find(trinket_id: String) -> Dictionary:
	_load()
	return _by_id.get(trinket_id, {})


static func reload() -> void:
	_loaded = false
	_base = []
	_by_id = {}


static func image(trinket_id: String) -> Texture2D:
	var trinket := find(trinket_id)
	return ItemData.image_for(str(trinket.get("image", ""))) if not trinket.is_empty() else null


## "Undying Skull"; the id itself when unknown.
static func label(trinket_id: String) -> String:
	var trinket := find(trinket_id)
	return str(trinket["name"]) if not trinket.is_empty() else trinket_id


## The rule text; the "+" side's text when `upgraded`.
static func rule_text(trinket_id: String, upgraded: bool = false) -> String:
	var trinket := find(trinket_id)
	if trinket.is_empty():
		return ""
	return str(trinket["plus_text"] if upgraded else trinket["text"])


static func _load() -> void:
	var stamp := ItemData.text_stamp()
	if stamp != _stamp:
		_stamp = stamp
		reload()
	if _loaded:
		return
	_loaded = true
	var items := ItemData.trinket_entries()
	var plus_text := {}
	for raw: Dictionary in items:
		if int(raw.get("IsUpgrade", 0)) == 1:
			plus_text[str(raw.get("BaseItemId", ""))] = _text_of(raw)
	for raw: Dictionary in items:
		if int(raw.get("IsUpgrade", 0)) == 1:
			continue
		var id := str(raw.get("_id", ""))
		var shown := ItemData.text(str(raw.get("KeyName", "")))
		var text := _text_of(raw)
		var trinket := {
			"id": id,
			"name": shown if shown != "" else str(raw.get("m_Name", id)),
			"text": text,
			"plus_text": str(plus_text.get(id, text)),
			"price": int(raw.get("Value", 0)),
			"xp": int(raw.get("XPRequiredForDrop", 99)),
			"act": int(raw.get("_act", 0)),
			"image": str(raw.get("TextureAssetPath", "")),
		}
		_base.append(trinket)
		_by_id[id] = trinket


static func _text_of(raw: Dictionary) -> String:
	var text := ItemData.text(str(raw.get("KeyDescription", "")))
	return text if text != "" else ItemData.text(str(raw.get("AbilityKey", "")))
