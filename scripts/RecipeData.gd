class_name RecipeData
extends RefCounted

## The game's weapon recipes, read from the user's own export (tools/asset_import/import_item_data.py ->
## user://item_data/items.json). Never instantiated. A recipe either makes a NEW card (a weapon, or a part B / C) or is an
## UPGRADE of a card the party owns (flips it to its "+" side). Nothing ships with the project: without the export there
## are no recipes. Weapon parts and armor for now (potions and trinkets come later).
##
## A normalised recipe is {id, card (the base part id it is about), upgrade, direct, price (gold, in the recipe shop), xp
## (XPRequiredForDrop; 99 = story only), act (0 = act I), ingredients (material key -> count)}.
##
## Armor: the 27 armor upgrades are recipes like the weapon ones. Base armors have no recipe in the game's data (they are
## bought for their `Value`), so each one is a DIRECT entry ("BUY_ARMOR_10"): it sits in the shop's rotating stock like a
## recipe but buying it gives the armor card at once - nothing to forge.

const ITEMS_PATH := "user://item_data/items.json"

static var _loaded := false
static var _recipes: Array[Dictionary] = []
static var _by_id: Dictionary = {}
static var _rune_ids: Dictionary = {}


static func available() -> bool:
	_load()
	return not _recipes.is_empty()


static func all() -> Array[Dictionary]:
	_load()
	return _recipes


static func find(recipe_id: String) -> Dictionary:
	_load()
	return _by_id.get(recipe_id, {})


## Forget what was read (a fresh export, or a test).
static func reload() -> void:
	_loaded = false
	_recipes = []
	_by_id = {}
	_rune_ids = {}


## "armor", "rune", "weapon" (an A part), "B" or "C" for the card a recipe is about.
static func card_kind(card_id: String) -> String:
	_load()
	if ArmorData.is_armor(card_id):
		return "armor"
	if _rune_ids.has(card_id):
		return "rune"
	var slot := WeaponData.part_slot(card_id)
	return "weapon" if slot == "A" else slot


## "Warden's Blade (Sword)", "Northrider Guard (Sword, part B)", "Rune: Ice Storm" - what the recipe is for.
static func card_label(card_id: String) -> String:
	match card_kind(card_id):
		"armor":
			return "Armor: " + ArmorData.label(card_id)
		"rune":
			return "Rune: " + WeaponData.part_name(card_id)
		"B", "C":
			return "%s (%s, part %s)" % [WeaponData.part_name(card_id), WeaponData.weapon_type_of_part(card_id), WeaponData.part_slot(card_id)]
		_:
			return WeaponData.weapon_label(card_id)


static func label(recipe: Dictionary) -> String:
	var card := str(recipe["card"])
	if recipe["upgrade"] and card_kind(card) == "armor":
		return "Armor upgrade: " + ArmorData.label(card)
	return ("Upgrade: " if recipe["upgrade"] else "") + card_label(card)


## A deliberately vague description of a recipe ("a sword recipe", "a rune upgrade") for the shop's rumour.
static func hint(recipe: Dictionary) -> String:
	var card := str(recipe["card"])
	var kind := card_kind(card)
	if kind == "armor":
		var armor_class := str(ArmorData.find(card).get("armor_class", "")).to_lower()
		if recipe["direct"]:
			return "a shipment of %s armor" % armor_class if armor_class != "" else "a shipment of armor"
		return "a %s armor upgrade" % armor_class if armor_class != "" else "an armor upgrade"
	var type_name := WeaponData.weapon_type_of_part(card).to_lower()
	var thing := "a rune" if kind == "rune" else ("a %s" % type_name if type_name != "" else "a weapon")
	if kind == "B" or kind == "C":
		thing += " part"
	return "%s %s" % [thing, "upgrade" if recipe["upgrade"] else "recipe"]


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(ITEMS_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_PATH))
	if not data is Dictionary:
		return
	for rune in WeaponData.runes():
		_rune_ids[rune.part_id] = true
	for raw: Dictionary in data.get("recipes", []):
		var crafted := str(raw.get("CraftedItemId", ""))
		if not (crafted.begins_with("WEAPON_PART_") or crafted.begins_with("ARMOR_")):
			continue
		var upgrade := int(raw.get("IsUpgrade", 0)) == 1
		var ingredients := {}
		for part: Dictionary in raw.get("Ingredients", []):
			var key := str(part.get("material", "")).trim_prefix("MAT_").to_lower()
			if LootMaterials.VALUES.has(key):
				ingredients[key] = int(ingredients.get(key, 0)) + int(part.get("qty", 0))
		var recipe := {
			"id": str(raw["_id"]),
			"card": str(raw.get("BaseItemId", "")) if upgrade else crafted,
			"upgrade": upgrade,
			"direct": false,
			"price": int(raw.get("Value", 0)),
			"xp": int(raw.get("XPRequiredForDrop", 99)),
			"act": int(raw.get("_act", 0)),
			"ingredients": ingredients,
		}
		_recipes.append(recipe)
		_by_id[recipe["id"]] = recipe
	for armor in ArmorData.all():
		var direct := {
			"id": "BUY_" + str(armor["id"]),
			"card": str(armor["id"]),
			"upgrade": false,
			"direct": true,
			"price": int(armor["price"]),
			"xp": int(armor["xp"]),
			"act": int(armor["act"]),
			"ingredients": {},
		}
		_recipes.append(direct)
		_by_id[direct["id"]] = direct
