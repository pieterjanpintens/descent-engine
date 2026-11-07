class_name SkillGrant
extends Resource

## A skill a chapter or side quest hands out when it is won (CampaignChapter / CampaignSideQuest `skill_grants`): free, no skill points, no tree rules.

## The hero that learns it (HeroData id, "HERO_CHANCE"); "" = every hero.
@export var hero_id: String = ""
## The skill number (1-11, or 12-14 for the legends; HeroData).
@export var number: int = 1
