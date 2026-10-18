class_name PlanBuilder
extends RefCounted

## Step 3 of the AI workspace (claude.md, open item 26): turns the ACCEPTED items of a plan (CampaignPlan) into real campaign
## objects - acts, chapters, narrative steps, characters and variables - from the plan's validated data only. No AI is involved:
## everything here is plain code on what the author reviewed. It changes the in-memory Campaign (the campaign editor records one
## undo step and the author saves as usual) and writes the ids of what it made back into the plan (`built`), so building again
## never makes a second copy and a later step can follow the link from the plan item to the chapter.
## Missions get no geometry: a mission chapter is created without a mission file (the Problems list says so); its summary stays in
## the plan as the brief. Never instantiated.

const STEP_TARGET_CHARS := 500
const MAX_STEPS_PER_CHAPTER := 40
const PALETTE: Array[Color] = [
	Color(0.95, 0.75, 0.3), Color(0.45, 0.8, 0.95), Color(0.9, 0.5, 0.5), Color(0.6, 0.85, 0.5),
	Color(0.8, 0.6, 0.95), Color(0.95, 0.65, 0.4), Color(0.5, 0.85, 0.8), Color(0.9, 0.85, 0.5),
]


## What building would do right now: {acts, chapters, characters, variables} (counts of new objects; acts = acts that would be made).
static func preview(plan: Dictionary, campaign: Campaign) -> Dictionary:
	var result := {"acts": 0, "chapters": 0, "characters": 0, "variables": 0}
	var none: Array[CampaignAct] = []
	for act_plan in plan.get("acts", []):
		var wanted := 0
		for chapter in act_plan["chapters"]:
			if _wanted(chapter):
				wanted += 1
		if wanted == 0:
			continue
		result["chapters"] += wanted
		if _find_act(campaign, act_plan, none).is_empty():
			result["acts"] += 1
	for character in plan.get("characters", []):
		if _wanted(character) and not _is_hero(character["name"]) and _find_character(campaign, character["name"]) == null:
			result["characters"] += 1
	for variable in plan.get("variables", []):
		if _wanted(variable) and _find_variable(campaign, variable["name"]) == null:
			result["variables"] += 1
	return result


## Builds everything accepted. `folder` = the campaign folder (the manuscript sections the narrative steps are made from are read
## from its notes). Changes `campaign` and `plan` (the `built` ids). Returns {made: {acts, chapters, steps, characters, variables},
## skipped: Array[String]}.
static func build(plan: Dictionary, campaign: Campaign, folder: String) -> Dictionary:
	var made := {"acts": 0, "chapters": 0, "steps": 0, "characters": 0, "variables": 0}
	var skipped: Array[String] = []
	# Characters first: the narrative steps use their tags, and the author should see them in the list straight away.
	for character in plan.get("characters", []):
		if not _wanted(character):
			continue
		if _is_hero(character["name"]):
			skipped.append("%s is a hero - heroes already have a voice of their own" % character["name"])
			continue
		var existing := _find_character(campaign, character["name"])
		if existing != null:
			character["built"] = existing.character_name
			continue
		var created := NarratorCharacter.new()
		created.character_name = character["name"]
		created.color = PALETTE[campaign.characters.size() % PALETTE.size()]
		campaign.characters.append(created)
		character["built"] = created.character_name
		made["characters"] += 1
	for variable in plan.get("variables", []):
		if not _wanted(variable):
			continue
		var existing_variable := _find_variable(campaign, variable["name"])
		if existing_variable != null or Campaign.BUILTIN_VARIABLES.has(variable["name"]):
			variable["built"] = variable["name"]
			continue
		var created_variable := MissionVariable.new()
		created_variable.name = variable["name"]
		created_variable.type = _variable_type(variable["type"])
		created_variable.default_value = variable["default"]
		campaign.variables.append(created_variable)
		variable["built"] = created_variable.name
		made["variables"] += 1
	var claimed: Array[CampaignAct] = []
	for act_plan in plan.get("acts", []):
		var wanted_chapters: Array[Dictionary] = []
		for chapter in act_plan["chapters"]:
			if _wanted(chapter):
				wanted_chapters.append(chapter)
		if wanted_chapters.is_empty():
			continue
		var found := _find_act(campaign, act_plan, claimed)
		var act: CampaignAct
		if found.is_empty():
			act = CampaignAct.new()
			act.act_name = act_plan["name"]
			act.intro = act_plan["intro"]
			campaign.acts.append(act)
			made["acts"] += 1
		else:
			act = found["act"]
			if act.chapters.is_empty():
				act.act_name = act_plan["name"]  # the empty act a new campaign starts with takes the plan's name
			if act.intro == "":
				act.intro = act_plan["intro"]
		claimed.append(act)
		_build_chapters(act, act_plan, wanted_chapters, campaign, folder, made, skipped)
	return {"made": made, "skipped": skipped}


static func _build_chapters(act: CampaignAct, act_plan: Dictionary, wanted: Array[Dictionary], campaign: Campaign, folder: String, made: Dictionary, skipped: Array[String]) -> void:
	var ids := {}  # plan key -> chapter id, for the chapters of this act that exist in the campaign (built now or before)
	for chapter_plan in act_plan["chapters"]:
		if chapter_plan["built"] != "" and act.find_chapter(chapter_plan["built"]) != null:
			ids[chapter_plan["key"]] = chapter_plan["built"]
		elif chapter_plan["exists"]:
			for existing in act.chapters:  # a chapter the campaign already had: links can point at it too
				if existing.title.to_lower() == str(chapter_plan["title"]).to_lower():
					ids[chapter_plan["key"]] = existing.id
					break
	var created: Array[CampaignChapter] = []
	var created_plans: Array[Dictionary] = []
	for chapter_plan in wanted:
		var chapter := CampaignChapter.new()
		chapter.id = campaign.new_chapter_id()
		chapter.title = chapter_plan["title"]
		chapter.is_narrative = chapter_plan["kind"] == "narrative"
		chapter.is_finale = chapter_plan["finale"]
		var body := _section_body(chapter_plan, folder)
		if chapter.is_narrative:
			for text in paginate(body if body.strip_edges() != "" else chapter_plan["summary"]):
				var step := NarrativeStep.new()
				step.id = chapter.new_step_id()
				step.text = text
				chapter.steps.append(step)
				made["steps"] += 1
		act.chapters.append(chapter)
		chapter_plan["built"] = chapter.id
		PlanSync.remember(chapter_plan, body, chapter)  # the starting point of the manuscript sync check
		ids[chapter_plan["key"]] = chapter.id
		created.append(chapter)
		created_plans.append(chapter_plan)
		if chapter_plan["start"] and act.start_chapter_id == "":
			act.start_chapter_id = chapter.id
		made["chapters"] += 1
	for i in created.size():
		for link in created_plans[i]["links"]:
			if not ids.has(link["to"]):
				skipped.append("'%s' links to '%s', which was not built" % [created[i].title, _title_of(act_plan, link["to"])])
				continue
			var campaign_link := CampaignLink.new()
			campaign_link.target_id = ids[link["to"]]
			campaign_link.outcome = {"win": CampaignLink.Outcome.WIN, "lose": CampaignLink.Outcome.LOSE}.get(link["outcome"], CampaignLink.Outcome.ANY)
			created[i].links.append(campaign_link)
	# Pins across the map by how far along the story a chapter is, so the arrows run left to right.
	var layout := _layout(act)
	for chapter in created:
		chapter.map_position = layout.get(chapter.id, chapter.map_position)
	if act.start_chapter_id == "" and not act.chapters.is_empty():
		act.start_chapter_id = act.chapters[0].id


## Map positions for the chapters of an act: x by the chapter's layer (the longest way to it from the start along the links that lead
## further into the story - links back to a chapter still being walked, like a retry, are ignored), y spread over the chapters of a layer, with
## a small up and down between neighbouring layers so the titles overlap less. Returns {chapter id: Vector2}.
static func _layout(act: CampaignAct) -> Dictionary:
	var start := act.start_chapter_id if act.find_chapter(act.start_chapter_id) != null else (act.chapters[0].id if not act.chapters.is_empty() else "")
	var back := {}  # "from>to" of every link that leads back to a chapter still being walked (a retry loop)
	_find_back_edges(act, start, {}, back)
	var layer := {start: 0}
	for pass_number in act.chapters.size() + 1:
		for chapter in act.chapters:
			if not layer.has(chapter.id):
				continue
			for link in chapter.links:
				if act.find_chapter(link.target_id) != null and not back.has(chapter.id + ">" + link.target_id):
					layer[link.target_id] = maxi(layer.get(link.target_id, 0), layer[chapter.id] + 1)
	var next_layer := 0
	for chapter in act.chapters:  # chapters the start cannot reach go in a layer of their own at the end
		if not layer.has(chapter.id):
			layer[chapter.id] = -1
		next_layer = maxi(next_layer, layer[chapter.id] + 1)
	for chapter in act.chapters:
		if layer[chapter.id] == -1:
			layer[chapter.id] = next_layer
	var members := {}
	for chapter in act.chapters:
		if not members.has(layer[chapter.id]):
			members[layer[chapter.id]] = []
		members[layer[chapter.id]].append(chapter.id)
	var layers: int = members.size()
	var result := {}
	for layer_index: int in members:
		var ids: Array = members[layer_index]
		for i in ids.size():
			var x := 0.5 if layers == 1 else 0.07 + 0.86 * layer_index / float(maxi(layers - 1, 1))
			var y := 0.5 + (0.0 if ids.size() == 1 else 0.7 * ((i + 0.5) / float(ids.size()) - 0.5))
			if ids.size() == 1:
				y += 0.1 if layer_index % 2 == 0 else -0.1
			result[ids[i]] = Vector2(x, clampf(y, 0.08, 0.92))
	return result


static func _find_back_edges(act: CampaignAct, id: String, state: Dictionary, back: Dictionary) -> void:
	state[id] = 1  # on the walk
	for link in act.find_chapter(id).links:
		if act.find_chapter(link.target_id) == null:
			continue
		if state.get(link.target_id, 0) == 1:
			back[id + ">" + link.target_id] = true
		elif not state.has(link.target_id):
			_find_back_edges(act, link.target_id, state, back)
	state[id] = 2


## The text of the manuscript section a chapter is linked to, as it is now ("" when it has none). A narrative chapter's pages are
## made from it (split into pages of about STEP_TARGET_CHARS, whole paragraphs; the plan's summary when there is no section).
static func _section_body(chapter_plan: Dictionary, folder: String) -> String:
	return CampaignPlan.section_text(folder, chapter_plan)


## Splits a text into pages: consecutive paragraphs are joined until a page reaches the target length.
static func paginate(text: String) -> Array[String]:
	var pages: Array[String] = []
	var current := ""
	for paragraph in text.strip_edges().split("\n\n", false):
		var piece := paragraph.strip_edges()
		if piece == "":
			continue
		if current != "" and current.length() >= STEP_TARGET_CHARS:
			pages.append(current)
			current = ""
		current = piece if current == "" else current + "\n\n" + piece
	if current != "":
		pages.append(current)
	if pages.size() > MAX_STEPS_PER_CHAPTER:
		var merged: Array[String] = pages.slice(0, MAX_STEPS_PER_CHAPTER - 1)
		merged.append("\n\n".join(pages.slice(MAX_STEPS_PER_CHAPTER - 1)))
		return merged
	return pages


## An item is built when it is ticked, not already in the campaign and not built before.
static func _wanted(item: Dictionary) -> bool:
	return item["accepted"] and not item["exists"] and item["built"] == ""


## The campaign act an act of the plan goes into: one with the same name, else the first act without chapters (a new campaign
## starts with one empty act). {} = a new act is needed. `claimed` = acts already used by an earlier act of the plan.
static func _find_act(campaign: Campaign, act_plan: Dictionary, claimed: Array[CampaignAct]) -> Dictionary:
	for act in campaign.acts:
		if not claimed.has(act) and act.act_name.to_lower() == str(act_plan["name"]).to_lower():
			return {"act": act}
	for act in campaign.acts:
		if not claimed.has(act) and act.chapters.is_empty():
			return {"act": act}
	return {}


static func _find_character(campaign: Campaign, character_name: String) -> NarratorCharacter:
	for character in campaign.characters:
		if character.character_name.to_lower() == character_name.to_lower():
			return character
	return null


static func _find_variable(campaign: Campaign, variable_name: String) -> MissionVariable:
	for variable in campaign.variables:
		if variable.name == variable_name:
			return variable
	return null


static func _is_hero(character_name: String) -> bool:
	for hero in HeroCatalog.HERO_NAMES:
		if hero.to_lower() == character_name.to_lower():
			return true
	return false


static func _variable_type(type: String) -> MissionVariable.Type:
	match type:
		"int":
			return MissionVariable.Type.INT
		"float":
			return MissionVariable.Type.FLOAT
		"string":
			return MissionVariable.Type.STRING
	return MissionVariable.Type.BOOL


static func _title_of(act_plan: Dictionary, key: String) -> String:
	for chapter in act_plan["chapters"]:
		if chapter["key"] == key:
			return chapter["title"]
	return key
