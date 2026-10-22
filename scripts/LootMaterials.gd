class_name LootMaterials
extends RefCounted

## The crafting materials of the game (never instantiated, a shared namespace like Vulnerability): seven COMMON
## materials and ten ESSENCES (one per damage type). Monsters drop them (LootItem) and recipes need them. A
## material is identified by its lower-case key; the keys equal the game's MAT_* ids without the prefix.
## Data only for now - nothing hands the materials out or spends them yet.

## Not a material: a loot item can also carry gold, kept under this key in a mission's collected loot and paid to the
## campaign's gold (CampaignState._take_loot()).
const GOLD := "gold"
## A found card (weapon, part, rune, armor) / a learned recipe is kept in the collected loot under "card:<id>" / "recipe:<id>" (count 1).
const CARD_PREFIX := "card:"
const RECIPE_PREFIX := "recipe:"
const COMMON: Array[String] = ["bone", "cloth", "curios", "herbs", "leather", "metal", "minerals"]
const ESSENCES: Array[String] = ["anemos", "aquos", "fortunos", "ignos", "lumos", "mortos", "terros", "toxos", "umbros", "vigos"]


## What a material is worth in gold (the game's `Value`): the price the market sells it for; the market buys it back at
## the campaign's sell percentage of this.
const VALUES := {
	"bone": 5, "cloth": 5, "curios": 5, "herbs": 5, "leather": 5, "metal": 5, "minerals": 5,
	"anemos": 25, "aquos": 25, "ignos": 25, "terros": 25,
	"fortunos": 30, "lumos": 30, "mortos": 30, "toxos": 30, "umbros": 30, "vigos": 30,
}


static func value(key: String) -> int:
	return int(VALUES.get(key, 0))


static func display_name(key: String) -> String:
	return key.capitalize()


static func is_common(key: String) -> bool:
	return COMMON.has(key)
