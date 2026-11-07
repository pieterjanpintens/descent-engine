class_name HeroProgress
extends Resource

## One hero's growth in a campaign save (CampaignState.hero_progress): skill points, owned skills and feats. Plain data - the rules (which feat may be
## equipped, what a completed feat pays, what a skill costs) live in CampaignState, which knows the campaign.

## The game's hero id ("HERO_CHANCE", see HeroData).
@export var hero_id: String = ""
## Skill points not spent yet: the campaign's starting points, plus what completed feats paid, minus what bought skills cost.
@export var skill_points: int = 0
## The skill numbers (1-11, HeroData) the hero owns.
@export var skills: Array[int] = []
## The feats being worked on: feat id -> progress (how many times its condition has happened). A feat stays here, with its progress, until it is
## completed or the player changes it - not between quests, not between missions.
@export var active_feats: Dictionary = {}
## Feat ids the hero has completed (never replaced, never done twice).
@export var completed_feats: Array[String] = []
