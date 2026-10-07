class_name HeroProgression
extends Resource

## How heroes level in a campaign: the experience points needed for each level and how many
## abilities a hero can have equipped at that level. Stored on the Campaign (so each campaign
## can tune its own curve; edited in CampaignEditor). Level 1 needs 0 XP; the last entry is
## the maximum level.

## `xp_thresholds[level - 1]` = total XP needed to be that level (ascending, first is 0).
@export var xp_thresholds: Array[int] = [0, 10, 25, 45, 70, 100]
## `slots_by_level[level - 1]` = ability slots at that level (same length as the thresholds).
@export var slots_by_level: Array[int] = [1, 2, 2, 3, 3, 4]


func max_level() -> int:
	return maxi(xp_thresholds.size(), 1)


## The level a hero with `experience` points has.
func level_for(experience: int) -> int:
	var level := 1
	for i in xp_thresholds.size():
		if experience >= xp_thresholds[i]:
			level = i + 1
	return level


## Equipped-ability slots at `level` (the last entry carries on past the table's end).
func slots_for(level: int) -> int:
	if slots_by_level.is_empty():
		return 1
	return slots_by_level[clampi(level - 1, 0, slots_by_level.size() - 1)]


## Total XP needed for the level after `level`, or -1 at the maximum level.
func xp_for_next(level: int) -> int:
	if level >= xp_thresholds.size():
		return -1
	return xp_thresholds[level]
