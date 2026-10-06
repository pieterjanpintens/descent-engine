class_name MonsterCondition
extends RefCounted

## The seven PREDEFINED conditions a monster can be affected by - the ones
## heroes apply with attacks or abilities (typically during an attack, see
## CombatView's "Conditions" dialog and MissionRuntime.resolve_attack()).
## Never instantiated - a shared enum namespace, same pattern as
## Vulnerability / MonsterChip.
##
## A monster holds them in `RuntimeMonster.conditions` (Array[int] of Kind).
## Other conditions are "scripted" (they vary per mission/game and are applied
## by the game itself) - not built yet; they will need their own storage
## alongside this list rather than extending this enum.
## Implemented so far: Afflicted, Doomed, Exposed, Enfeebled, Slowed, Confused, Dazed (see claude.md).

## Dazed: every weapon attachment's chance to trigger against a Dazed monster is raised by
## this many percentage points (WeaponAttachment.roll()).
const DAZED_ATTACHMENT_BONUS_PERCENT := 10

## Slowed: the monster's speed is set to this (see RuntimeMonster.effective_speed()).
const SLOWED_SPEED := 1

## Enfeebled: the monster's attack damage is lowered by this many percent (the
## reduction is rounded UP; see RuntimeMonster.effective_attack_power()).
const ENFEEBLED_DAMAGE_PERCENT := 20

enum Kind {
	AFFLICTED,
	CONFUSED,
	DAZED,
	DOOMED,
	ENFEEBLED,
	EXPOSED,
	SLOWED,
}


## Every kind, in declaration order (also the order the dialog lists them).
static func all() -> Array[int]:
	var kinds: Array[int] = []
	for kind in Kind.values():
		kinds.append(kind)
	return kinds


static func display_name(kind: int) -> String:
	return str(Kind.keys()[kind]).capitalize()
