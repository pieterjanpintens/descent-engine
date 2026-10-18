class_name PlanSync
extends RefCounted

## Step 4 of the AI workspace (claude.md, open item 26): keeps the MANUSCRIPT and the CHAPTERS built from it honest about each
## other. Every built chapter of the plan remembers what the manuscript section and the chapter's story text looked like when
## they were last in step (`section_fp` + `synced_text`, `built_fp` + `built_text`, fingerprints that ignore layout). `check()`
## compares those with how things are now and tells which side changed; the author decides what to do (SyncWindow) - nothing
## is ever overwritten by itself. No AI is involved. Never instantiated.
##
## States of an entry: "in_sync", "manuscript_changed", "chapter_changed", "both_changed", "section_missing" (the heading is
## gone or renamed), "chapter_missing" (the chapter was deleted). A mission chapter has no story text to compare, so only its
## manuscript side is tracked; a chapter built before this step has no chapter baseline until it is marked reviewed once.

const MAX_TEXT := 40000


## The text of a chapter's story pages (what a manuscript section turns into): the steps' texts, a blank line between.
static func chapter_text(chapter: CampaignChapter) -> String:
	var pieces: Array[String] = []
	for step in chapter.steps:
		if step.text.strip_edges() != "":
			pieces.append(step.text.strip_edges())
	return "\n\n".join(pieces)


## Remembers the current state of a plan chapter and its section as the state they are "in sync" at.
static func remember(chapter_plan: Dictionary, section_body: String, chapter: CampaignChapter) -> void:
	chapter_plan["section_fp"] = CampaignNotes.fingerprint(section_body) if section_body != "" else chapter_plan.get("section_fp", "")
	chapter_plan["synced_text"] = section_body.left(MAX_TEXT)
	if chapter != null and chapter.is_narrative:
		var text := chapter_text(chapter)
		chapter_plan["built_fp"] = CampaignNotes.fingerprint(text)
		chapter_plan["built_text"] = text.left(MAX_TEXT)
	else:
		chapter_plan["built_fp"] = ""
		chapter_plan["built_text"] = ""


## One entry per built chapter of the plan: {act_index, chapter_plan, chapter (null when deleted), state, section_found (bool),
## section_now (the manuscript section's text now - the sections of a combined chapter one after the other - "" if missing), refs
## (the manuscript sections it comes from), single_section (just one, so the chapter text can be written back into it), chapter_now (the chapter's story text now),
## plain_pages (the chapter only has plain pages, so it can be rewritten from the manuscript without losing anything)}.
static func check(plan: Dictionary, campaign: Campaign, folder: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var sections_by_file := {}
	for act_index in plan.get("acts", []).size():
		for chapter_plan in plan["acts"][act_index]["chapters"]:
			if chapter_plan["built"] == "":
				continue
			var chapter := _find_chapter(campaign, chapter_plan["built"])
			var entry := {"act_index": act_index, "chapter_plan": chapter_plan, "chapter": chapter, "state": "in_sync",
				"section_found": false, "section_now": "", "chapter_now": "", "plain_pages": false, "refs": CampaignPlan.section_refs(chapter_plan), "single_section": true}
			result.append(entry)
			if chapter == null:
				entry["state"] = "chapter_missing"
				continue
			entry["chapter_now"] = chapter_text(chapter) if chapter.is_narrative else ""
			entry["plain_pages"] = chapter.is_narrative and _plain_pages(chapter)
			var manuscript_changed := false
			var refs := CampaignPlan.section_refs(chapter_plan)
			entry["refs"] = refs
			entry["single_section"] = refs.size() == 1
			if refs.is_empty():
				continue  # not linked to a manuscript section: nothing to compare
			var bodies: Array[String] = []
			var all_found := true
			for ref in refs:
				if not sections_by_file.has(ref["file"]):
					sections_by_file[ref["file"]] = CampaignNotes.sections(CampaignNotes.read(folder, ref["file"]))
				var found_body := ""
				var found := false
				for section in sections_by_file[ref["file"]]:
					if section["title"] == ref["title"]:
						found = true
						found_body = str(section["body"]).strip_edges()
						break
				if not found:
					all_found = false
					break
				if found_body != "":
					bodies.append(found_body)
			if not all_found:
				entry["state"] = "section_missing"
				continue
			entry["section_found"] = true
			entry["section_now"] = "\n\n".join(bodies)  # a combined chapter has several sections: they count as one text
			manuscript_changed = chapter_plan["section_fp"] != "" and CampaignNotes.fingerprint(entry["section_now"]) != chapter_plan["section_fp"]
			var chapter_changed: bool = chapter.is_narrative and chapter_plan.get("built_fp", "") != "" \
				and CampaignNotes.fingerprint(entry["chapter_now"]) != chapter_plan["built_fp"]
			if manuscript_changed and chapter_changed:
				entry["state"] = "both_changed"
			elif manuscript_changed:
				entry["state"] = "manuscript_changed"
			elif chapter_changed:
				entry["state"] = "chapter_changed"
	return result


## How many built chapters are out of step (every state but in_sync).
static func drift_count(entries: Array[Dictionary]) -> int:
	var count := 0
	for entry in entries:
		if entry["state"] != "in_sync":
			count += 1
	return count


static func state_text(state: String) -> String:
	match state:
		"manuscript_changed":
			return "The manuscript changed since this chapter was made from it."
		"chapter_changed":
			return "The chapter was edited since it was made from the manuscript."
		"both_changed":
			return "Both the manuscript and the chapter changed since they were last in step."
		"section_missing":
			return "The manuscript section this chapter came from is gone (deleted or renamed)."
		"chapter_missing":
			return "The chapter made from the plan was deleted from the campaign."
	return "In step."


## Replaces the chapter's story pages by the pages of the manuscript section as it is now. Only for a chapter with plain pages
## (no questions, answers or conditions - those would be lost). Returns false when not allowed.
static func update_chapter_from_manuscript(entry: Dictionary) -> bool:
	var chapter: CampaignChapter = entry["chapter"]
	if chapter == null or not chapter.is_narrative or not entry["plain_pages"] or not entry["section_found"] or entry["section_now"] == "":
		return false
	chapter.steps.clear()
	for text in PlanBuilder.paginate(entry["section_now"]):
		var step := NarrativeStep.new()
		step.id = chapter.new_step_id()
		step.text = text
		chapter.steps.append(step)
	remember(entry["chapter_plan"], entry["section_now"], chapter)
	return true


## Writes the chapter's story text into its manuscript section (the heading stays). Returns false when not possible. The caller
## has asked the author first.
static func update_manuscript_from_chapter(entry: Dictionary, folder: String) -> bool:
	var chapter: CampaignChapter = entry["chapter"]
	var chapter_plan: Dictionary = entry["chapter_plan"]
	if chapter == null or not chapter.is_narrative or not entry["section_found"] or entry["chapter_now"] == "" or not entry["single_section"]:
		return false  # a combined chapter comes from several sections - there is no one place to write its text back
	var text := CampaignNotes.read(folder, chapter_plan["section_file"])
	var replaced := CampaignNotes.replace_section(text, chapter_plan["section_title"], entry["chapter_now"])
	if replaced == "" or not CampaignNotes.write(folder, chapter_plan["section_file"], replaced):
		return false
	var body := ""
	for section in CampaignNotes.sections(replaced):
		if section["title"] == chapter_plan["section_title"]:
			body = section["body"]
			break
	remember(chapter_plan, body, chapter)
	return true


## Accepts how both sides are now as the new "in step" state, without changing either.
static func mark_reviewed(entry: Dictionary) -> void:
	remember(entry["chapter_plan"], entry["section_now"], entry["chapter"])


## Stops tracking: the chapter forgets its manuscript section (a chapter that was deleted also forgets its built id, so the plan
## item can be built again).
static func forget(entry: Dictionary) -> void:
	var chapter_plan: Dictionary = entry["chapter_plan"]
	if entry["chapter"] == null:
		chapter_plan["built"] = ""
	for field in ["section_file", "section_title", "section_fp", "synced_text", "built_fp", "built_text"]:
		chapter_plan[field] = ""
	chapter_plan["extra_sections"] = []


static func _find_chapter(campaign: Campaign, chapter_id: String) -> CampaignChapter:
	for act in campaign.acts:
		var chapter := act.find_chapter(chapter_id)
		if chapter != null:
			return chapter
	return null


static func _plain_pages(chapter: CampaignChapter) -> bool:
	for step in chapter.steps:
		if step.question != "" or not step.answers.is_empty() or not step.conditions.is_empty():
			return false
	return true
