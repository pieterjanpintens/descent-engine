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
## The campaign's own variables (declared here, so conditions and effects pick them from a list - no typos).
## Their values live in the save game (CampaignState.variables); a chapter or side quest sets them when won
## or lost, a side quest's conditions read them.
@export var variables: Array[MissionVariable] = []
## The starting set: what the party owns at mission 0 (base part ids, see WeaponData): weapon cards, B/C parts, runes.
## Every hero type needs at least one starting weapon (starting_set_problems()); StartingSetDialog edits it.
@export var starting_weapons: Array[String] = []
@export var starting_attachments: Array[String] = []
@export var starting_runes: Array[String] = []
## The named speakers of this campaign's stories: `[Name]...[/Name]` in a text is read in the character's voice (NarrationMarkup).
@export var characters: Array[NarratorCharacter] = []

## Always there besides `variables`: the party's counters. `act_number` is 1-based and read-only.
const BUILTIN_VARIABLES: Array[String] = ["experience", "gold", "act_number"]


## The built-in counters (INT) followed by the declared variables - everything a condition can read.
func all_variables() -> Array[MissionVariable]:
	var all: Array[MissionVariable] = []
	for variable_name in BUILTIN_VARIABLES:
		var builtin := MissionVariable.new()
		builtin.name = variable_name
		builtin.type = MissionVariable.Type.INT
		builtin.default_value = 0
		all.append(builtin)
	all.append_array(variables)
	return all


## What an effect may write: all of all_variables() except act_number.
func writable_variables() -> Array[MissionVariable]:
	var writable: Array[MissionVariable] = []
	for variable in all_variables():
		if variable.name != "act_number":
			writable.append(variable)
	return writable


## Every text of the narrative chapters (steps, questions, answers, replies) - what the characters' tags are found in.
func narrative_texts() -> Array[String]:
	var found: Array[String] = []
	for act in acts:
		for chapter in act.chapters:
			for step in chapter.steps:
				found.append_array([step.text, step.question])
				for answer in step.answers:
					found.append_array([answer.text, answer.reply])
	return found


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


## Problems with the starting set: each hero weapon type needs at least one weapon (needs the weapon-data export).
func starting_set_problems() -> Array[String]:
	var found: Array[String] = []
	if not WeaponData.available():
		return found
	var owned_types: Array[String] = []
	for part_id in starting_weapons:
		owned_types.append(WeaponData.weapon_type_of_part(part_id))
	for type_name in WeaponData.hero_types():
		if not owned_types.has(type_name):
			found.append("starting equipment: no %s (a hero needs one for Weapon 1 or 2)" % type_name)
	return found


## Ticks the first weapon of every hero type, nothing else.
func fill_default_starting_set() -> void:
	for part_id in WeaponData.basic_set():
		if not starting_weapons.has(part_id):
			starting_weapons.append(part_id)


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
