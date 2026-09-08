extends Node

## Maps a MeshLibrary item name to the corresponding asset name from the
## official "Descent: Legends of the Dark" companion app. A user who owns
## that game can run the importer (see tools/asset_import/) against their
## own install to populate OfficialAssetOverrides' override folder with
## files named after these - this project never ships or redistributes
## that art itself, only placeholders (see CLAUDE.md).
##
## Names don't reliably match ours (our "acid" is their
## "W1_Underlay_FetidPool", not something derivable from either name), so
## this has to be hand-maintained, not computed.
##
## >>> Only covers items where we've actually confirmed the official name
## >>> by inspecting the game's asset bundles. Floor tile faces (1a-21b)
## >>> aren't here yet - the official game uses a handful of shared
## >>> materials (flagstone/grass/dirt/wood planks) across many physical
## >>> tile shapes rather than one texture per tile number, and which
## >>> shape should use which material is a design decision that hasn't
## >>> been made yet, not something this map can guess.
const MAP: Dictionary = {
	"water": "W1_Underlay_Water",
	"acid": "W1_Underlay_FetidPool",
	"lava": "W1_Underlay_EmberPit",
	"spikes": "W1_Underlay_Spikes",
}


## Returns "" if this mesh has no known official-asset equivalent.
func get_official_name(mesh_item_name: String) -> String:
	return MAP.get(mesh_item_name, "")
