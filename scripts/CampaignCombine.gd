class_name CampaignCombine
extends RefCounted

## Combines chapters that are ALREADY in the campaign into one (the plan window's "Combine selected" on built chapters): the chapters
## of one act become a single chapter - texts merged, links kept, start/finale/rewards/effects taken along, and everything that
## pointed at one of them (links, the act's start chapter, places, side quests) pointed at the combined chapter.
##
## Narrative chapters: their steps follow each other (new step ids; "go to step" answers are re-pointed). Mission chapters:
## maps cannot be merged, so at most ONE of them may have a mission with a drawn map or events; if several have a mission file they
## must all be empty skeletons (BriefBuilder) and are replaced by ONE new skeleton made from the merged brief - the old skeleton
## files are moved to a `_combined` folder inside the campaign folder, not deleted. The caller records the undo step (the campaign
## editor swaps the campaign for a snapshot; the moved files are the one thing an undo does not bring back by itself).
## Never instantiated.

const MOVED_DIR := "_combined"


## The act that holds `chapter`, null when none does.
static func act_of(campaign: Campaign, chapter: CampaignChapter) -> CampaignAct:
	for act in campaign.acts:
		if act.chapters.has(chapter):
			return act
	return null


## Whether a mission has anything beyond objectives and variables (a map, events, spawn areas).
static func has_content(mission: MissionData) -> bool:
	return not mission.floor_placements.is_empty() or not mission.underlay_placements.is_empty() or not mission.interactables.is_empty() \
		or not mission.monster_spawns.is_empty() or not mission.triggers.is_empty() or not mission.player_spawn_cells.is_empty() \
		or not mission.los_blockers.is_empty()


## Why these chapters cannot be combined ("" = they can).
static func problem(campaign: Campaign, folder: String, chapters: Array) -> String:
	if chapters.size() < 2:
		return "Select at least two chapters."
	var act := act_of(campaign, chapters[0])
	if act == null:
		return "A selected chapter is not in the campaign."
	var narrative := 0
	var files: Array[String] = []
	for chapter in chapters:
		if act_of(campaign, chapter) != act:
			return "The chapters must all be in the same act."
		if chapter.is_narrative:
			narrative += 1
		elif chapter.mission_file != "":
			files.append(chapter.mission_file)
	if narrative != 0 and narrative != chapters.size():
		return "Combine missions with missions and narrative chapters with narrative chapters, not both."
	if CampaignIO.is_release(folder):
		return "A release cannot be changed."
	if files.size() >= 2:
		for file_name in files:
			var mission := MissionIO.load_mission("%s/%s" % [CampaignIO.folder_path(folder), file_name])
			if mission == null:
				return "The mission file %s could not be read." % file_name
			if has_content(mission):
				return "%s has a drawn map or events, and maps cannot be merged. Combine only missions that are still empty, or keep one mission with a map and delete the other chapters' missions first." % file_name
	return ""


## Combines `chapters` (CampaignChapters of one act) into the first of them in the act, called `title`. `merged_brief` = the merged brief of
## the chapters (needed when several of them have a mission file: the new skeleton mission is made from it). Returns
## {ok, error, chapter, mission_file}. Nothing is changed when it fails.
static func combine(campaign: Campaign, folder: String, chapters: Array, title: String, merged_brief: Dictionary = {}) -> Dictionary:
	var blocked := problem(campaign, folder, chapters)
	var clean_title := title.strip_edges().left(100)
	if blocked == "" and clean_title == "":
		blocked = "The combined chapter needs a title."
	var files: Array[String] = []
	for chapter in chapters:
		if not chapter.is_narrative and chapter.mission_file != "":
			files.append(chapter.mission_file)
	if blocked == "" and files.size() >= 2 and not _has_win(merged_brief):
		blocked = "The merged brief needs a win objective to make one mission of several."
	if blocked != "":
		return {"ok": false, "error": blocked, "chapter": null, "mission_file": ""}
	var act := act_of(campaign, chapters[0])
	var ordered: Array[CampaignChapter] = []
	for chapter in act.chapters:
		if chapters.has(chapter):
			ordered.append(chapter)
	var first := ordered[0]
	var group := {}
	for chapter in ordered:
		group[chapter.id] = true
	var others: Array[CampaignChapter] = ordered.slice(1)

	# the new mission first, so a failure leaves everything as it was
	var mission_file := ""
	if files.size() == 1:
		mission_file = files[0]
	elif files.size() >= 2:
		var mission := BriefBuilder.skeleton(clean_title, merged_brief)
		mission_file = BriefBuilder._free_file_name(folder, clean_title)
		if not MissionIO.save_mission(mission, "%s/%s" % [CampaignIO.folder_path(folder), mission_file]):
			return {"ok": false, "error": "The combined mission file could not be saved.", "chapter": null, "mission_file": ""}
		DirAccess.make_dir_recursive_absolute("%s/%s" % [CampaignIO.folder_path(folder), MOVED_DIR])
		for old_file in files:
			DirAccess.rename_absolute("%s/%s" % [CampaignIO.folder_path(folder), old_file], "%s/%s/%s" % [CampaignIO.folder_path(folder), MOVED_DIR, old_file])

	# texts, steps and what a win gives
	first.title = clean_title
	first.mission_file = mission_file
	if first.is_narrative:
		first.ensure_step_ids()
	var before: Array[String] = []
	var after: Array[String] = []
	for chapter in ordered:
		if chapter.story_before.strip_edges() != "":
			before.append(chapter.story_before.strip_edges())
		if chapter.story_after.strip_edges() != "":
			after.append(chapter.story_after.strip_edges())
	first.story_before = "\n\n".join(before)
	first.story_after = "\n\n".join(after)
	for chapter in others:
		if chapter.is_narrative:
			chapter.ensure_step_ids()
			var renamed := {}
			for step in chapter.steps:
				var new_id := first.new_step_id()
				renamed[step.id] = new_id
				step.id = new_id
			for step in chapter.steps:
				for answer in step.answers:
					if renamed.has(answer.goto_step_id):
						answer.goto_step_id = renamed[answer.goto_step_id]
				first.steps.append(step)
		first.reward_xp += chapter.reward_xp
		first.reward_gold += chapter.reward_gold
		for material in chapter.reward_materials:
			first.reward_materials[material] = int(first.reward_materials.get(material, 0)) + int(chapter.reward_materials[material])
		first.win_effects.append_array(chapter.win_effects)
		first.lose_effects.append_array(chapter.lose_effects)
		for mapping in chapter.mission_outputs:
			if not _has_mapping(first.mission_outputs, mapping):
				first.mission_outputs.append(mapping)
		for mapping in chapter.mission_inputs:
			if not _has_mapping(first.mission_inputs, mapping):
				first.mission_inputs.append(mapping)
		first.is_finale = first.is_finale or chapter.is_finale
		first.wait_for_all = first.wait_for_all or chapter.wait_for_all
		first.exclusive_links = first.exclusive_links or chapter.exclusive_links

	# links: the group's outgoing links stay (those inside the group vanish), and links into the group go to the combined chapter
	var outgoing: Array[CampaignLink] = []
	var seen := {}
	for chapter in ordered:
		for link in chapter.links:
			if group.has(link.target_id):
				continue
			var key := "%s>%d" % [link.target_id, link.outcome]
			if not seen.has(key):
				seen[key] = true
				outgoing.append(link)
	first.links = outgoing
	var remaining: Array[CampaignChapter] = []
	for chapter in act.chapters:
		if chapter == first or not group.has(chapter.id):
			remaining.append(chapter)
	act.chapters = remaining
	for chapter in act.chapters:
		if chapter == first:
			continue
		var retargeted: Array[CampaignLink] = []
		var seen_here := {}
		for link in chapter.links:
			if group.has(link.target_id):
				link.target_id = first.id
			var key := "%s>%d" % [link.target_id, link.outcome]
			if not seen_here.has(key):
				seen_here[key] = true
				retargeted.append(link)
		chapter.links = retargeted
	if group.has(act.start_chapter_id):
		act.start_chapter_id = first.id
	for place in act.places:
		if group.has(place.unlocked_by_chapter):
			place.unlocked_by_chapter = first.id
		if group.has(place.closes_after_chapter):
			place.closes_after_chapter = first.id
		if group.has(place.reopens_after_chapter):
			place.reopens_after_chapter = first.id
	for quest in campaign.side_quests:
		var ids: Array[String] = []
		for chapter_id in quest.chapter_ids:
			var mapped: String = first.id if group.has(chapter_id) else chapter_id
			if not ids.has(mapped):
				ids.append(mapped)
		quest.chapter_ids = ids
	return {"ok": true, "error": "", "chapter": first, "mission_file": mission_file}


static func _has_win(brief: Dictionary) -> bool:
	for objective in brief.get("objectives", []):
		if objective["kind"] == "win":
			return true
	return false


static func _has_mapping(list: Array[MissionVariableMap], mapping: MissionVariableMap) -> bool:
	for existing in list:
		if existing.mission_variable == mapping.mission_variable and existing.campaign_variable == mapping.campaign_variable:
			return true
	return false
