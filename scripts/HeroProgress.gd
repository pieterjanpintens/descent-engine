class_name HeroProgress
extends Resource

## One hero's growth in a campaign save (CampaignState.hero_progress): skill points, owned skills and feats. Plain data - the rules (which feat may be
## equipped, what a completed feat pays, what a skill costs) live in CampaignState, which knows the campaign.

## The game's hero id ("HERO_CHANCE", see HeroData).
@export var hero_id: String = ""
## Skill points not spent yet: the campaign's starting points, plus what completed feats paid, minus what bought skills cost.
@export var skill_points: int = 0
## The skill numbers (1-11, and 12-14 for the legends; HeroData) the hero owns.
@export var skills: Array[int] = []
## The hero's feat list, in order: the first `Campaign.parallel_feats` of it are the ones being worked on; when one is completed the next in the list starts by
## itself. Changing the order or removing an entry is a "change" the campaign may charge for (see Campaign.feat_change_mode).
@export var feat_queue: Array[String] = []
## True once the list has been filled with all of the hero's feats in the game's own order (done the first time the hero is looked at, see
## CampaignState._normalize_feats); after that a feat the player takes off the list stays off.
@export var feat_list_ready: bool = false
## The feats being worked on: feat id -> progress (how many times its condition has happened). A feat stays here, with its progress, until it is
## completed or pushed out of the first places of the list - not between quests, not between missions. Always a subset of `feat_queue`.
@export var active_feats: Dictionary = {}
## Feat ids the hero has completed (never replaced, never done twice).
@export var completed_feats: Array[String] = []
