class_name Campaign
extends Resource

## A campaign: an ordered list of acts (see CampaignAct), stored in its own folder
## (user://campaigns/<name>/campaign.tres) together with the missions and map images it
## uses, so a campaign can be shared as one folder (CampaignIO). Edited in CampaignEditor.
## Progress is CampaignState (the campaign save). Planned next: campaign variables.

@export var campaign_name: String = "New campaign"
@export_multiline var intro: String = ""
## File name (not a path) of the book cover image inside the campaign folder (always the 2:3 ratio,
## see CampaignIO.import_cover_image()); "" = none, the campaign screen shows a plain dummy cover.
@export var cover_image: String = ""
@export var acts: Array[CampaignAct] = []
## Source of unique chapter ids ("ch_1", "ch_2", ...), never reused.
@export var next_chapter_number: int = 1
## The same for places ("place_N") and their offers ("offer_N").
@export var next_place_number: int = 1
@export var next_offer_number: int = 1
## Optional side quests (not part of an act, see CampaignSideQuest) and the counter for their ids ("sq_N").
@export var side_quests: Array[CampaignSideQuest] = []
@export var next_side_quest_number: int = 1


func new_side_quest_id() -> String:
	var quest_id := "sq_%d" % next_side_quest_number
	next_side_quest_number += 1
	return quest_id


func find_side_quest(quest_id: String) -> CampaignSideQuest:
	for quest in side_quests:
		if quest.id == quest_id:
			return quest
	return null


func has_chapter(chapter_id: String) -> bool:
	for act in acts:
		if act.find_chapter(chapter_id) != null:
			return true
	return false


## Human-readable problems with the side quests (`mission_files` = what the campaign folder holds).
func side_quest_problems(mission_files: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for quest in side_quests:
		if quest.mission_file == "":
			found.append("side quest '%s' has no mission" % quest.title)
		elif not mission_files.has(quest.mission_file):
			found.append("side quest '%s': mission file '%s' is missing" % [quest.title, quest.mission_file])
		if quest.chapter_ids.is_empty():
			found.append("side quest '%s' is not linked to a chapter, so it never appears" % quest.title)
		for chapter_id in quest.chapter_ids:
			if not has_chapter(chapter_id):
				found.append("side quest '%s' is linked to a chapter that no longer exists" % quest.title)
	return found


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
