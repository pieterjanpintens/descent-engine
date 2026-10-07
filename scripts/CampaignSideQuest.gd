class_name CampaignSideQuest
extends Resource

## An optional side quest: much like a chapter it loads one mission, but it belongs to the campaign (not to
## an act), is never part of the path and has no links to other quests. It is offered on the map, with
## its own marking (an orange star), for as long as the party is at one of its `chapter_ids` and its
## `conditions` hold - until it is won (CampaignState.is_side_quest_visible()). A lost side quest can be
## played again. Edited in CampaignEditor.

@export var id: String = ""
@export var title: String = "New side quest"
## File name (not a path) of the mission inside the campaign folder; "" = none chosen yet.
@export var mission_file: String = ""
@export_multiline var story_before: String = ""
@export_multiline var story_after: String = ""
## Fraction 0..1 of the map image of the act it is shown on (the act of the chapter it is linked to).
@export var map_position: Vector2 = Vector2(0.5, 0.5)
@export var reward_xp: int = 1
@export var reward_gold: int = 0
## Crafting materials a win gives the party: name -> count.
@export var reward_materials: Dictionary = {}
## The chapters it is offered at: visible while any of them is one the party can play now.
@export var chapter_ids: Array[String] = []
## Only offered while all of these hold (implicit AND; empty = always). They compare the campaign's
## values - CampaignState.CONDITION_VARIABLES (experience, gold, act_number).
@export var conditions: Array[Condition] = []
