class_name ConsumableData
extends RefCounted

## The game's consumables (potions, grenades...) from the user's own export (ItemData reads user://item_data/). Never instantiated. Nothing ships
## with the project: without the export there are none. Their effect is resolved at the table - the app only knows who owns how many. A
## consumable and its "+" version are two different items (ids "CSM_ANTIDOTE_POTION" / "CSM_ANTIDOTE_POTION_PLUS"), each with its own recipe.
##
## A normalised consumable is {id, name, upgraded, text (the card text), image (TextureAssetPath), limited_heroes}.

static var _loaded := false
static var _all: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func is_consumable(card_id: String) -> bool:
	return card_id.begins_with("CSM_")


static func available() -> bool:
	_load()
	return not _all.is_empty()


static func all() -> Array[Dictionary]:
	_load()
	return _all


static func find(consumable_id: String) -> Dictionary:
	_load()
	return _by_id.get(consumable_id, {})


static func reload() -> void:
	_loaded = false
	_all = []
	_by_id = {}


static func is_upgraded(consumable_id: String) -> bool:
	return bool(find(consumable_id).get("upgraded", false))


## "Antidote Potion" / "Antidote Potion +"; the id itself when unknown.
static func label(consumable_id: String) -> String:
	var entry := find(consumable_id)
	if entry.is_empty():
		return consumable_id
	return str(entry["name"]) + (" +" if entry["upgraded"] else "")


static func rule_text(consumable_id: String) -> String:
	return str(find(consumable_id).get("text", ""))


static func image(consumable_id: String) -> Texture2D:
	return ItemData.image_for(str(find(consumable_id).get("image", "")))


## id -> label for pickers (base potions and their "+" versions).
static func choices() -> Dictionary:
	var result := {}
	for entry in all():
		result[entry["id"]] = label(str(entry["id"]))
	return result


## "Antidote Potion, 2x Fire Grenade +" for a list of ids (repeats are counted).
static func list_text(ids: Array) -> String:
	var counts := {}
	for id in ids:
		counts[str(id)] = int(counts.get(str(id), 0)) + 1
	var parts: Array[String] = []
	for id in counts:
		parts.append(label(id) if counts[id] == 1 else "%dx %s" % [counts[id], label(id)])
	return ", ".join(parts)


## What the table is told when consumables are found for use in THIS mission only (a Loot effect or a monster's drop).
static func usable_notice(ids: Array) -> String:
	if ids.is_empty():
		return ""
	if ids.size() > 1:
		return TranslationServer.translate("Usable in this mission: %s. Put them in your play area to use them. They are not added to the inventory and are gone when the mission ends.") % list_text(ids)
	return TranslationServer.translate("Usable in this mission: %s. Put it in your play area to use it. It is not added to the inventory and is gone when the mission ends.") % list_text(ids)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	for raw: Dictionary in ItemData.consumable_entries():
		var entry := {
			"id": str(raw.get("_id", "")),
			"name": ItemData.text_for(str(raw.get("KeyName", ""))),
			"upgraded": int(raw.get("IsUpgrade", 0)) == 1,
			"text": ItemData.text_for(str(raw.get("KeyDescription", ""))),
			"image": str(raw.get("TextureAssetPath", "")),
			"limited_heroes": raw.get("LimitedHeroesId", []),
		}
		if entry["id"] == "" or entry["name"] == "":
			continue
		_all.append(entry)
		_by_id[entry["id"]] = entry
