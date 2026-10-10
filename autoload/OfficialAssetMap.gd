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
	# Token props - each token type has its own unique official art (unlike
	# the floor materials, there's no sharing here).
	"res://models/tokens_Exploration.png": "Token_Explore",
	"res://models/tokens_Interact.png": "Token_Interact",
	"res://models/tokens_Umbra.png": "Token_Umbra",
	# Hero portraits (see HeroCatalog.gd) - unlike everything else above,
	# these aren't MeshLibrary materials (OfficialAssetOverrides.apply_overrides()
	# doesn't touch them at all), so HeroCatalog.slot_portrait() calls the new
	# OfficialAssetOverrides.texture_for() directly instead. Official names
	# confirmed by inspecting the game's own bundles (dump_all_assets.py) -
	# these ARE the Unity object's plain m_Name, no prefix/suffix, unlike the
	# floor/underlay names above.
	"res://models/heroes_chance.png": "Chance",
	"res://models/heroes_galaden.png": "Galaden",
	"res://models/heroes_brynn.png": "Brynn",
	"res://models/heroes_vaerix.png": "Vaerix",
	"res://models/heroes_kehli.png": "Kehli",
	"res://models/heroes_syrus.png": "Syrus",
	# PlayerHud's "Threat" (monster-view) icon button - same non-MeshLibrary
	# case as the hero portraits above, resolved via
	# OfficialAssetOverrides.texture_for() directly. Unlike the heroes, this
	# name is genuinely unique in the game's own bundles (confirmed - only
	# one object anywhere is named "Button_EnemyView"), so no container-path
	# disambiguation is needed in the import script for this one.
	"res://models/hud_threat.png": "Button_EnemyView",
	# PlayerHud's "Quest" (map-view) icon button - same case as
	# Button_EnemyView above, also confirmed unique.
	"res://models/hud_quest.png": "Button_MapView",
	# Damage-type icons for the combat view (2026-09-26): dummy placeholders in
	# models/icons/ (same sizes as the real ones), replaced by the user's own art
	# when present. "unknown" is the red ? shown for undiscovered weaknesses.
	"res://models/icons/damage_pierce.png": "Icons_Pierce",
	"res://models/icons/damage_slash.png": "Icons_Slash",
	"res://models/icons/damage_crush.png": "Icons_Crush",
	"res://models/icons/damage_lumos.png": "Icons_Lumos",
	"res://models/icons/damage_aquos.png": "Icons_Aquos",
	"res://models/icons/damage_ignos.png": "Icons_Ignos",
	"res://models/icons/damage_mortos.png": "Icons_Mortos",
	"res://models/icons/damage_terros.png": "Icons_Terros",
	"res://models/icons/damage_anemos.png": "Icons_Anemos",
	"res://models/icons/damage_umbros.png": "Icons_Umbros",
	"res://models/icons/damage_vigos.png": "Icons_Vigos",
	"res://models/icons/damage_unknown.png": "Icons_Unknown",
	# Combat dialog "croptops" (2026-09-26): per hero one per weapon (Weapon 1 =
	# the game's acti crop, Weapon 2 = actii), per monster its tab image (the
	# game has no monster _CROP). See tools/asset_import/import_official_assets.py's
	# source_for() for how these names are resolved.
	"res://models/crops/hero_chance_weapon1.png": "Chance_Weapon1_Crop",
	"res://models/crops/hero_chance_weapon2.png": "Chance_Weapon2_Crop",
	"res://models/crops/hero_galaden_weapon1.png": "Galaden_Weapon1_Crop",
	"res://models/crops/hero_galaden_weapon2.png": "Galaden_Weapon2_Crop",
	"res://models/crops/hero_brynn_weapon1.png": "Brynn_Weapon1_Crop",
	"res://models/crops/hero_brynn_weapon2.png": "Brynn_Weapon2_Crop",
	"res://models/crops/hero_vaerix_weapon1.png": "Vaerix_Weapon1_Crop",
	"res://models/crops/hero_vaerix_weapon2.png": "Vaerix_Weapon2_Crop",
	"res://models/crops/hero_kehli_weapon1.png": "Kehli_Weapon1_Crop",
	"res://models/crops/hero_kehli_weapon2.png": "Kehli_Weapon2_Crop",
	"res://models/crops/hero_syrus_weapon1.png": "Syrus_Weapon1_Crop",
	"res://models/crops/hero_syrus_weapon2.png": "Syrus_Weapon2_Crop",
	"res://models/crops/monster_bandit.png": "Bandit_Tab",
	"res://models/crops/monster_berserker.png": "Berserker_Tab",
	"res://models/crops/monster_blood_sister.png": "Blood Sister_Tab",
	"res://models/crops/monster_centurion.png": "Centurion_Tab",
	"res://models/crops/monster_doomcaller.png": "Doomcaller_Tab",
	"res://models/crops/monster_fae.png": "Fae_Tab",
	"res://models/crops/monster_golem.png": "Golem_Tab",
	"res://models/crops/monster_harbinger.png": "Harbinger_Tab",
	"res://models/crops/monster_legionnaire.png": "Legionnaire_Tab",
	"res://models/crops/monster_mercenary.png": "Mercenary_Tab",
	"res://models/crops/monster_reanimate.png": "Reanimate_Tab",
	"res://models/crops/monster_salamander.png": "Salamander_Tab",
	"res://models/crops/monster_specter.png": "Specter_Tab",
	"res://models/crops/monster_vampire.png": "Vampire_Tab",
	"res://models/crops/monster_wight.png": "Wight_Tab",
	"res://models/crops/monster_wolf.png": "Wolf_Tab",
	"res://models/crops/monster_zealot.png": "Zealot_Tab",
}


## Returns "" if this placeholder texture path has no known official-asset
## equivalent.
func get_official_name(placeholder_texture_path: String) -> String:
	return MAP.get(placeholder_texture_path, "")
