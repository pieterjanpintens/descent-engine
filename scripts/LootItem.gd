class_name LootItem
extends Resource

## ONE thing a monster can drop (the game's loot table entry, e.g. "a Corroded Blade"): a name for the table and the
## materials it is made of - up to two common materials and up to two essences (LootMaterials keys).
## The game's real drop rules (which of a monster's loot items drops, how many materials come from it, whether the
## two essences are alternatives or both given) are not known/decided yet, so this is only data.

@export var item_name: String = ""
@export var common_materials: Array[String] = []
@export var essences: Array[String] = []
## Gold it is worth to the party (paid to the campaign when the mission is won).
@export_range(0, 9999) var gold: int = 0
## Optional: cards (weapon / part / rune / armor ids) and recipes (RecipeData ids) the party gets when this drops.
@export var cards: Array[String] = []
@export var recipes: Array[String] = []
## Consumable ids the party can use in this mission only when this drops (not added to the inventory).
@export var usable: Array[String] = []


func _init(p_name: String = "") -> void:
	item_name = p_name


func to_dict() -> Dictionary:
	return {"name": item_name, "common": common_materials.duplicate(), "essences": essences.duplicate(), "gold": gold, "cards": cards.duplicate(), "recipes": recipes.duplicate(), "usable": usable.duplicate()}


static func from_dict(d: Dictionary) -> LootItem:
	var item := LootItem.new(str(d.get("name", "")))
	for key in d.get("common", []):
		item.common_materials.append(str(key))
	for key in d.get("essences", []):
		item.essences.append(str(key))
	item.gold = int(d.get("gold", 0))
	for card_id in d.get("cards", []):
		item.cards.append(str(card_id))
	for recipe_id in d.get("recipes", []):
		item.recipes.append(str(recipe_id))
	for usable_id in d.get("usable", []):
		item.usable.append(str(usable_id))
	return item


## Independent copies of `list`.
static func copies(list: Array[LootItem]) -> Array[LootItem]:
	var result: Array[LootItem] = []
	for item in list:
		result.append(from_dict(item.to_dict()))
	return result
