class_name CampaignChapter
extends Resource

## One step of an act's path: the players play `mission_file` (a mission inside the
## campaign's folder) and, depending on how it ends, follow a link to the next chapter.
## A finale chapter ends the act when it is won. `map_position` is where its pin sits on
## the act's map, as a fraction of the map image (0..1 on both axes).

@export var id: String = ""
@export var title: String = "New chapter"
## File name (not a path) of the mission inside the campaign folder; "" = none chosen yet.
@export var mission_file: String = ""
@export_multiline var story_before: String = ""
@export_multiline var story_after: String = ""
@export var map_position: Vector2 = Vector2(0.5, 0.5)
@export var is_finale: bool = false
## What winning the chapter gives the party: experience points (the party's counter) and gold.
@export var reward_xp: int = 1
@export var reward_gold: int = 0
## Crafting materials a win gives the party: name -> count.
@export var reward_materials: Dictionary = {}
@export var links: Array[CampaignLink] = []
## Set when the chapter is won / lost (Set Variable and Math effects over the campaign's variables).
## Mission variables copied into campaign variables when the mission ends, before the effects below.
@export var mission_outputs: Array[MissionVariableMap] = []
## Campaign variables handed to the mission when it starts.
@export var mission_inputs: Array[MissionVariableMap] = []
@export var win_effects: Array[Effect] = []
@export var lose_effects: Array[Effect] = []
