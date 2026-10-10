class_name LootMaterials
extends RefCounted

## The crafting materials of the game (never instantiated, a shared namespace like Vulnerability): seven COMMON
## materials and ten ESSENCES (one per damage type). Monsters drop them (LootItem) and recipes need them. A
## material is identified by its lower-case key; the keys equal the game's MAT_* ids without the prefix.
## Data only for now - nothing hands the materials out or spends them yet.

## Not a material: a loot item can also carry gold, kept under this key in a mission's collected loot and paid to the
## campaign's gold (CampaignState._take_loot()).
const GOLD := "gold"
const COMMON: Array[String] = ["bone", "cloth", "curios", "herbs", "leather", "metal", "minerals"]
const ESSENCES: Array[String] = ["anemos", "aquos", "fortunos", "ignos", "lumos", "mortos", "terros", "toxos", "umbros", "vigos"]


static func display_name(key: String) -> String:
	return key.capitalize()


static func is_common(key: String) -> bool:
	return COMMON.has(key)
