extends Node

## Maps a shipped PLACEHOLDER texture's res:// path to the corresponding
## asset name from the official "Descent: Legends of the Dark" companion
## app. A user who owns that game can run the importer (see
## tools/asset_import/) against their own install to populate
## OfficialAssetOverrides' override folder with files named after these -
## this project never ships or redistributes that art itself, only
## placeholders (see CLAUDE.md).
##
## Keyed by TEXTURE PATH, not mesh/item name - deliberately, because
## several floor tile faces (e.g. every tile using the "flagstone" look)
## share the exact same placeholder texture. Matching by mesh name would
## mean one map entry per tile face pointing at the same texture; matching
## by texture path instead means OfficialAssetOverrides can scan every
## MeshLibrary item uniformly and swap whichever ones happen to be using a
## known placeholder, with no per-tile-face bookkeeping needed here. This
## still works identically for the underlay hazards too, since each of
## those already has its own uniquely-named placeholder texture.
##
## Names don't reliably match ours (our "acid" placeholder corresponds to
## their "W1_Underlay_FetidPool", not something derivable from either
## name), so this has to be hand-maintained, not computed.
const MAP: Dictionary = {
	"res://models/underlays_water.png": "W1_Underlay_Water",
	"res://models/underlays_acid.png": "W1_Underlay_FetidPool",
	"res://models/underlays_lava.png": "W1_Underlay_EmberPit",
	"res://models/underlays_spikes.png": "W1_Underlay_Spikes",
	"res://models/floors_flagstone.png": "W1_Tiles_Flagstone",
	"res://models/floors_grass.png": "W1_Tiles_Grass",
	"res://models/floors_dirt.png": "W1_Tiles_Dirt",
	"res://models/floors_wood_planks.png": "W1_Tiles_WoodPlanks",
}


## Returns "" if this placeholder texture path has no known official-asset
## equivalent.
func get_official_name(placeholder_texture_path: String) -> String:
	return MAP.get(placeholder_texture_path, "")
