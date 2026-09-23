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
static func slot_portrait(index: int) -> Texture2D:
	return OfficialAssetOverrides.texture_for(PORTRAIT_PATHS[index])
