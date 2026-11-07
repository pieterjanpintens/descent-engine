class_name SkillTreeNode
extends Resource

## One slot of a campaign's skill tree (see SkillTree). The tree has the same 11 slots for every hero: slot N holds skill N of each hero
## (the game's own skill numbers, HeroData), so a hero's skill N is bought where slot N sits.

## The skill number (1-11) this slot stands for.
@export var number: int = 1
## What buying it costs, in skill points (the game's XP cost of that skill number by default).
@export var cost: int = 1
## Conditions over the campaign's variables that must ALL hold before this slot can be bought (the same Condition rows as a side quest's); empty =
## always. Holding a skill back until an act is one of them: act_number >= 2 (the campaign's own act, not the original game's).
@export var conditions: Array[Condition] = []
## Skill numbers of which owning ANY ONE opens this slot; empty = a starting point.
@export var parents: Array[int] = []
