class_name RecipeData
extends RefCounted

## The game's weapon recipes, read from the user's own export (tools/asset_import/import_item_data.py ->
## user://item_data/items.json). Never instantiated. A recipe either makes a NEW card (a weapon, or a part B / C) or is an
## UPGRADE of a card the party owns (flips it to its "+" side). Nothing ships with the project: without the export there
## are no recipes. Weapon parts, armor, trinkets and consumables (potions).
##
## A normalised recipe is {id, card (the base part id it is about), upgrade, direct, price (gold, in the recipe shop), xp
## (XPRequiredForDrop; 99 = story only), act (0 = act I), ingredients (material key -> count)}.
##
## Armor: the 27 armor upgrades are recipes like the weapon ones. Base armors have no recipe in the game's data (they are
## bought for their `Value`), so each one is a DIRECT entry ("BUY_ARMOR_10"): it sits in the shop's rotating stock like a
## recipe but buying it gives the armor card at once - nothing to forge. Trinkets work the same way: the 20 "+" upgrades are recipes, the base
## trinkets are direct entries ("BUY_TRINKET10_ID").

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


## The game gates its recipes by an XP number (4, 5, 6...); the campaign calls that a TIER: tier 1 = 4 XP, tier 2 = 5 XP, and so on.
## 0 = story only (the game never hands it out by itself).
const TIER_BASE_XP := 3


static func tier(recipe: Dictionary) -> int:
	var xp := int(recipe["xp"])
	return 0 if xp >= 99 else maxi(xp - TIER_BASE_XP, 1)


## The highest tier any recipe has (1 when there is no data).
static func highest_tier() -> int:
	var highest := 1
	for recipe in all():
		highest = maxi(highest, tier(recipe))
	return highest


## "armor", "rune", "weapon" (an A part), "B" or "C" for the card a recipe is about.
static func card_kind(card_id: String) -> String:
	_load()
	if ConsumableData.is_consumable(card_id):
		return "consumable"
	if TrinketData.is_trinket(card_id):
		return "trinket"
	if ArmorData.is_armor(card_id):
		return "armor"
	if _rune_ids.has(card_id):
		return "rune"
	var slot := WeaponData.part_slot(card_id)
	return "weapon" if slot == "A" else slot


## The picture of the card a recipe makes (weapon, part, rune or armor), null when there is none.
static func card_image(card_id: String) -> Texture2D:
	match card_kind(card_id):
		"armor":
			return ArmorData.image(card_id)
		"trinket":
			return TrinketData.image(card_id)
		"consumable":
			return ConsumableData.image(card_id)
	return WeaponData.part_icon(card_id)


## "Warden's Blade (Sword)", "Northrider Guard (Sword, part B)", "Rune: Ice Storm" - what the recipe is for.
static func card_label(card_id: String) -> String:
	match card_kind(card_id):
		"armor":
			return "Armor: " + ArmorData.label(card_id)
		"consumable":
			return ConsumableData.label(card_id)
		"trinket":
			return "Trinket: " + TrinketData.label(card_id)
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
	if recipe["upgrade"] and card_kind(card) == "trinket":
		return "Trinket upgrade: " + TrinketData.label(card)
	return ("Upgrade: " if recipe["upgrade"] else "") + card_label(card)


## A deliberately vague description of a recipe ("a sword recipe", "a rune upgrade") for the shop's rumour.
static func hint(recipe: Dictionary) -> String:
	var card := str(recipe["card"])
	var kind := card_kind(card)
	if kind == "consumable":
		return "a potion recipe"
	if kind == "trinket":
		return "a trinket" if recipe["direct"] else "a trinket upgrade"
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
		var is_potion := crafted.begins_with("CSM_")
		if not (crafted.begins_with("WEAPON_PART_") or crafted.begins_with("ARMOR_") or crafted.begins_with("TRINKET") or is_potion):
			continue
		var unresolved := false
		for part: Dictionary in raw.get("Ingredients", []):
			if not LootMaterials.VALUES.has(str(part.get("material", "")).trim_prefix("MAT_").to_lower()):
				unresolved = true  # the export could not name a material: a recipe with a missing ingredient would be too cheap
		if unresolved:
			continue
		# a potion's "+" recipe makes the "+" potion by itself (a counted item), it does not upgrade anything the party owns
		var upgrade := int(raw.get("IsUpgrade", 0)) == 1 and not is_potion
		var ingredients := {}
		for part: Dictionary in raw.get("Ingredients", []):
			var key := str(part.get("material", "")).trim_prefix("MAT_").to_lower()
			if LootMaterials.VALUES.has(key):
				ingredients[key] = int(ingredients.get(key, 0)) + int(part.get("qty", 0))
		var recipe := {
			"id": str(raw["_id"]),
			"card": str(raw.get("BaseItemId", "")) if upgrade else crafted,
			"upgrade": upgrade,
			"consumable": is_potion,
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
	for trinket in TrinketData.all():
		var direct_trinket := {
			"id": "BUY_" + str(trinket["id"]),
			"card": str(trinket["id"]),
			"upgrade": false,
			"direct": true,
			"price": int(trinket["price"]),
			"xp": int(trinket["xp"]),
			"act": int(trinket["act"]),
			"ingredients": {},
		}
		_recipes.append(direct_trinket)
		_by_id[direct_trinket["id"]] = direct_trinket
