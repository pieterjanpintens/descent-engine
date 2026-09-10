class_name HeroCatalog
extends RefCounted

## Never instantiated - just a shared namespace, same pattern as
## RoundCheckpoint. Placeholder-only roster of the SLOT_COUNT (6) playable
## characters - no real names/art. Descent's own hero names/portraits are
## the original game's copyrighted content (see claude.md's "Official asset
## overrides" section for why this project never ships that kind of thing),
## and there's no equivalent "override" mechanism for hero identity yet
## anyway - just generic "Hero N" labels + a distinct color per slot.
##
## Shared between EmbarkDialog (party roster selection) and
## PlayerInteractionController (the portrait dock), so both always agree on
## what slot N looks like without duplicating the name/color logic.

const SLOT_COUNT := 6


static func slot_name(index: int) -> String:
	return "Hero %d" % (index + 1)


static func slot_color(index: int) -> Color:
	return Color.from_hsv(float(index) / SLOT_COUNT, 0.55, 0.85)
