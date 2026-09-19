class_name MonsterChip
extends RefCounted

## The four physical clip-on colour chips that mark a monster's base notch
## (see ComponentInventory.COLOR_INDICATOR_COUNTS - 4 of each colour). Never
## instantiated, same shared-namespace pattern as PlayerAttribute.

enum Chip { YELLOW, GREEN, ORANGE, PURPLE }

const COLORS := {
	Chip.YELLOW: Color(0.95, 0.85, 0.15),
	Chip.GREEN: Color(0.25, 0.75, 0.25),
	Chip.ORANGE: Color(0.95, 0.55, 0.1),
	Chip.PURPLE: Color(0.55, 0.25, 0.75),
}


## Lowercase key, matching ComponentInventory.COLOR_INDICATOR_COUNTS.
static func key(chip: int) -> String:
	return Chip.keys()[chip].to_lower()


static func display_name(chip: int) -> String:
	return Chip.keys()[chip].capitalize()


static func color(chip: int) -> Color:
	return COLORS[chip]
