class_name HeroCatalog
extends RefCounted

## Never instantiated - just a shared namespace, same pattern as
## RoundCheckpoint. The SLOT_COUNT (6) playable characters. Names are the
## real hero names (Chance/Galaden/Brynn/Vaerix/Kehli/Syrus) - these alone
## aren't copyrighted content, just labels - but PORTRAITS are: this ships
## only dummy placeholder art (models/heroes_<name>.png, generated - a flat
## colour + the name, same 256x256 size as the real portraits) and swaps in
## a user's own official art via OfficialAssetOverrides.texture_for(), same
## "override mechanism" every other official asset in this project uses
## (see claude.md's "Official asset overrides"). Never ships/redistributes
## the real art itself.
##
## Shared between EmbarkDialog (party roster selection) and
## PlayerInteractionController (the portrait dock), so both always agree on
## what slot N looks like without duplicating the name/portrait/color logic.

const SLOT_COUNT := 6

const HERO_NAMES: Array[String] = ["Chance", "Galaden", "Brynn", "Vaerix", "Kehli", "Syrus"]

## Index-aligned with HERO_NAMES - see OfficialAssetMap.MAP for the official
## name each one resolves to when a user's own override is present.
const PORTRAIT_PATHS: Array[String] = [
	"res://models/heroes_chance.png",
	"res://models/heroes_galaden.png",
	"res://models/heroes_brynn.png",
	"res://models/heroes_vaerix.png",
	"res://models/heroes_kehli.png",
	"res://models/heroes_syrus.png",
]


static func slot_name(index: int) -> String:
	return HERO_NAMES[index]


static func slot_color(index: int) -> Color:
	return Color.from_hsv(float(index) / SLOT_COUNT, 0.55, 0.85)


## The shipped placeholder portrait, or a user's own official art if
## OfficialAssetOverrides finds one locally (see that autoload's
## texture_for()). Never null - falls back to the placeholder either way.
## The combat dialog "croptop" of hero `index` holding weapon `weapon_index`
## (0 = Weapon 1, 1 = Weapon 2) - dummy placeholder, or the user's own
## official art if present (see OfficialAssetMap).
static func slot_crop(index: int, weapon_index: int) -> Texture2D:
	return OfficialAssetOverrides.texture_for("res://models/crops/hero_%s_weapon%d.png" % [HERO_NAMES[index].to_lower(), weapon_index + 1])


static func slot_portrait(index: int) -> Texture2D:
	return OfficialAssetOverrides.texture_for(PORTRAIT_PATHS[index])


## EXPERIMENTAL (2026-09-27, branch experiment/monster-flat-meshes) - the
## combat view's hero side, real mesh instead of the flat crop image, same
## idea as MonsterDisplay's own flat card (see that class's own doc). Each
## hero has TWO real rigged meshes, one per act - mirroring slot_crop()'s
## own acti=Weapon1/actii=Weapon2 split exactly (see the CORRECTED note
## right below for how this was actually found - a first pass wrongly
## concluded there was only one). The rig's "Weapon" bone carries no
## baked-in weapon geometry (nothing is attached to it) - showing the
## actually-equipped weapon in-hand is explicitly out of scope for this
## pass. `import_hero_meshes.py` (tools/asset_import/) is the fetch script;
## see that script's own doc for how the correct SkinnedMeshRenderer is
## picked out of a hero's other rig meshes (Syrus in particular has 2
## unrelated companion-creature meshes in the same prefab, on BOTH acts).
## CORRECTED 2026-09-27, same day: an earlier version of this class assumed
## heroes had only ONE mesh (shared across both weapon slots) - wrong, found
## by the user directly inspecting the raw dump in Blender: both acti and
## actii have their OWN real mesh + texture, exactly mirroring slot_crop()'s
## own weapon_index convention (0 = acti = Weapon 1, 1 = actii = Weapon 2).
## Filenames are "weapon_<index>.tres"/"weapon_<index>_diffuse.png", NOT
## "flat_N" - unlike MonsterDisplay's flat_mesh_paths() (where N is a PIECE
## of one card), N here is a whole separate weapon-slot mesh, never
## multiple pieces of the same one (not observed for any hero on either
## act) - the Array[String] return type is kept for interface symmetry with
## MonsterDisplay/CombatMeshPreview.show_meshes() even though it only ever
## holds zero or one path.
static func flat_mesh_paths(index: int, weapon_index: int) -> Array[String]:
	var path := "user://hero_assets/%s/weapon_%d.tres" % [HERO_NAMES[index].to_lower(), weapon_index]
	return [path] if ResourceLoader.exists(path) else []


static func flat_diffuse_texture(index: int, weapon_index: int) -> Texture2D:
	var path := "user://hero_assets/%s/weapon_%d_diffuse.png" % [HERO_NAMES[index].to_lower(), weapon_index]
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)  # same idiom as OfficialAssetOverrides._load_override_texture()
	if image == null:
		return null
	return ImageTexture.create_from_image(image)


static func has_flat_mesh(index: int, weapon_index: int) -> bool:
	return not flat_mesh_paths(index, weapon_index).is_empty() and flat_diffuse_texture(index, weapon_index) != null


## Pitch correction for the rigged hero mesh's true "up" axis - DATA-DRIVEN
## first guess, not yet visually confirmed: every hero's raw AABB has its Y
## extent as the SMALLEST of the three axes (e.g. Chance 0.0092 vs 0.0146/
## 0.0135, Galaden 0.0154 vs 0.0221/0.0284) while Z is consistently the
## LARGEST - i.e. a standing figure's real height is baked into local Z, not
## Y, the exact same signature several monster plastic-pool rigs already
## needed a -90-degree X correction for (see MonsterDisplay.REAL_MONSTERS'
## own pitch_correction_degrees history) - confirmed to report as "seeing
## the top or bottom" once actually rendered, matching what a Y/Z swap with
## no correction would look like (the fixed camera looks along world Z, so
## if the model's real front-facing axis is actually world Y once the
## squashed axis is treated as "up", the camera ends up looking down/up the
## true height axis instead of at the front). -90 applied to all 6 heroes
## uniformly (unlike monsters, which needed per-monster values) since every
## hero showed the identical Y/Z pattern - not yet confirmed correct, may
## still need `+90` or another value once actually seen (see
## MonsterDisplay's own saga for how many rounds that sometimes took).
const FLAT_MESH_ROTATION_DEGREES := Vector3(-90, 0, 0)


static func flat_mesh_rotation(_index: int) -> Vector3:
	return FLAT_MESH_ROTATION_DEGREES
