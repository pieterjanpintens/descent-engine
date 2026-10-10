class_name LootItem
extends Resource

## ONE thing a monster can drop (the game's loot table entry, e.g. "a Corroded Blade"): a name for the table and the
## materials it is made of - up to two common materials and up to two essences (LootMaterials keys).
## The game's real drop rules (which of a monster's loot items drops, how many materials come from it, whether the
## two essences are alternatives or both given) are not known/decided yet, so this is only data.

@export var item_name: String = ""
@export var common_materials: Array[String] = []
@export var essences: Array[String] = []


func _init(p_name: String = "") -> void:
	item_name = p_name


func to_dict() -> Dictionary:
	return {"name": item_name, "common": common_materials.duplicate(), "essences": essences.duplicate()}


static func from_dict(d: Dictionary) -> LootItem:
	var item := LootItem.new(str(d.get("name", "")))
	for key in d.get("common", []):
		item.common_materials.append(str(key))
	for key in d.get("essences", []):
		item.essences.append(str(key))
	return item


## Independent copies of `list`.
static func copies(list: Array[LootItem]) -> Array[LootItem]:
	var result: Array[LootItem] = []
	for item in list:
		result.append(from_dict(item.to_dict()))
	return result
