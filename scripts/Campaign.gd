class_name Campaign
extends Resource

## A campaign: an ordered list of acts (see CampaignAct), stored in its own folder
## (user://campaigns/<name>/campaign.tres) together with the missions and map images it
## uses, so a campaign can be shared as one folder (CampaignIO). Edited in CampaignEditor.
## Progress is CampaignState (the campaign save). Planned next: campaign variables.

@export var campaign_name: String = "New campaign"
@export_multiline var intro: String = ""
@export var acts: Array[CampaignAct] = []
## Source of unique chapter ids ("ch_1", "ch_2", ...), never reused.
@export var next_chapter_number: int = 1
## The same for places ("place_N") and their offers ("offer_N").
@export var next_place_number: int = 1
@export var next_offer_number: int = 1


func new_place_id() -> String:
	var place_id := "place_%d" % next_place_number
	next_place_number += 1
	return place_id


func new_offer_id() -> String:
	var offer_id := "offer_%d" % next_offer_number
	next_offer_number += 1
	return offer_id


func new_chapter_id() -> String:
	var chapter_id := "ch_%d" % next_chapter_number
	next_chapter_number += 1
	return chapter_id
