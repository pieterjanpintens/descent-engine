class_name Campaign
extends Resource

## A campaign: an ordered list of acts (see CampaignAct), stored in its own folder
## (user://campaigns/<name>/campaign.tres) together with the missions and map images it
## uses, so a campaign can be shared as one folder (CampaignIO). Edited in CampaignEditor.
## Planned next: hero levels/experience and abilities, campaign variables, points of
## interest on the map (shops that trade gold/materials for weapon parts).

@export var campaign_name: String = "New campaign"
@export_multiline var intro: String = ""
@export var acts: Array[CampaignAct] = []
## Source of unique chapter ids ("ch_1", "ch_2", ...), never reused.
@export var next_chapter_number: int = 1


func new_chapter_id() -> String:
	var chapter_id := "ch_%d" % next_chapter_number
	next_chapter_number += 1
	return chapter_id
