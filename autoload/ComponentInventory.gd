extends Node

## Autoload singleton. Add as "ComponentInventory" in Project Settings >
## Autoload. Tracks how many of each REAL physical piece exists, so the
## Creator can warn/block designs that need more copies than you actually
## own - avoids designing a mission that looks fine on screen but can't
## physically be built on the table.
##
## >>> PLACEHOLDER NUMBERS BELOW. Replace with real counts from your own
## >>> component list - you have the box, I don't.

## Maps a mesh item name to its "physical group" - both faces of a
## double-sided tile share ONE group, since flipping it to show 1b instead
## of 1a doesn't consume a second physical tile. Anything not listed here
## is assumed to be its own group (i.e. mesh_item_name IS the group).
const MESH_TO_GROUP: Dictionary = {
	"1a": "tile_1", "1b": "tile_1",
	"2a": "tile_2", "2b": "tile_2",
	"3a": "tile_3", "3b": "tile_3",
	"4a": "tile_4", "4b": "tile_4",
	"5a": "tile_5", "5b": "tile_5",
	"7a": "tile_7", "7b": "tile_7",
	"6a": "tile_6", "6b": "tile_6",
	"8a": "tile_8", "8b": "tile_8",
	"9a": "tile_9", "9b": "tile_9",
	"10a": "tile_10", "10b": "tile_10",
	"11a": "tile_11", "11b": "tile_11",
	"12a": "tile_12", "12b": "tile_12",
	"13a": "tile_13", "13b": "tile_13",
	"14a": "tile_14", "14b": "tile_14",
	"15a": "tile_15", "15b": "tile_15",
	"16a": "tile_16", "16b": "tile_16",
	"17a": "tile_17", "17b": "tile_17",
	"18a": "tile_18", "18b": "tile_18",
	"20a": "tile_20", "20b": "tile_20",
	"21a": "tile_21", "21b": "tile_21",
	# Underlay hazard cards are double-sided too, just like the tile faces
	# above - water/spikes share one physical card, lava/acid share another.
	"water": "card_water_spikes", "spikes": "card_water_spikes",
	"lava": "card_lava_acid", "acid": "card_lava_acid",
}

## Max physical count per group. -1 or missing = untracked/unlimited (no
## warning given) - useful while you're still filling this table in
## incrementally rather than having everything falsely blocked at 0.
const MAX_COUNTS: Dictionary = {
	"tile_1": 1,
	"tile_2": 1,
	"tile_3": 1,
	"tile_4": 1,
	"tile_5": 1,
	"tile_6": 1,
	"tile_7": 1,
	"tile_8": 1,
	"tile_9": 1,
	"tile_10": 1,
	"tile_11": 1,
	"tile_12": 1,
	"tile_13": 1,
	"tile_14": 1,
	"tile_15": 1,
	"tile_16": 1,
	"tile_17": 1,
	"tile_18": 1,
	"tile_20": 1,
	"tile_21": 1,
	"card_water_spikes": 4,
	"card_lava_acid": 4,
	"tall": 8,
	"mini": 16,
	"medium": 8,
	"stair": 6,
}


func get_group(mesh_item_name: String) -> String:
	return MESH_TO_GROUP.get(mesh_item_name, mesh_item_name)


## Returns -1 if this mesh isn't tracked yet (treated as unlimited).
func get_max_count(mesh_item_name: String) -> int:
	var group := get_group(mesh_item_name)
	return MAX_COUNTS.get(group, -1)
