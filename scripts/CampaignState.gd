class_name CampaignState
extends Resource

## A campaign in progress - the campaign save (CampaignIO.save_state()), separate from a
## mission save: where the party is on the campaign's map, which chapters are done, the experience
## counter and what the party owns. One save per campaign, in user://campaign_saves/.

@export var campaign_folder: String = ""
## The name of this save game (a campaign can have several playthroughs).
@export var save_name: String = ""
@export var current_act: int = 0
## Ids of the chapters the party has won.
@export var completed_chapters: Array[String] = []
## The chapters of the current act the party can play now (the frontier of its path: the start
## chapter at first, then wherever the links of won/lost chapters lead).
@export var available_chapters: Array[String] = []
@export var campaign_complete: bool = false
## Ids of the once-only offers the party has bought.
@export var purchased_offers: Array[String] = []
## The party's experience points - just a counter: a won chapter adds its `reward_xp`, and an
## act can set it to a fixed number when it begins (CampaignAct.start_experience).
@export var experience: int = 0
@export var gold: int = 0
## The values of the campaign's declared variables (Campaign.variables): name -> value.
@export var variables: Dictionary = {}
## Ids of the side quests the party has won.
@export var completed_side_quests: Array[String] = []
## The campaign log: what the party was told and did, oldest first - {title, pages} (see LogDialog).
@export var log_entries: Array[Dictionary] = []
## Crafting materials: name -> count.
@export var materials: Dictionary = {}
## Part ids of the weapon attachments (AttachmentCatalog) the party owns.
@export var owned_attachments: Array[String] = []
## The narration voice of each hero (hero name -> NarratorVoices id, "" = picked from the name). Asked once, when the
## campaign starts; no two heroes share one (HeroVoicesDialog).
@export var hero_voices: Dictionary = {}


## The heroes as speakers, with this save game's voices.
func hero_characters() -> Array[NarratorCharacter]:
	var heroes: Array[NarratorCharacter] = []
	for template in HeroCatalog.hero_characters():
		var hero := NarratorCharacter.new()
		hero.character_name = template.character_name
		hero.color = template.color
		hero.is_hero = true
		hero.voice_id = hero_voices.get(hero.character_name, NarratorVoices.RANDOM_ID)
		heroes.append(hero)
	return heroes


## `characters` (a campaign's or mission's own) plus the heroes - every speaker a text of this playthrough can name.
func speakers(characters: Array[NarratorCharacter]) -> Array[NarratorCharacter]:
	var all: Array[NarratorCharacter] = characters.duplicate()
	all.append_array(hero_characters())
	return all


## A MissionRuntime over the campaign's variables (the built-in counters from this state plus the declared
## ones), used to evaluate conditions and apply effects with the mission rules instead of a second copy of
## them. A declared variable this save game has no value for yet gets its default.
func _runtime(campaign: Campaign) -> MissionRuntime:
	var data := MissionData.new()
	data.custom_variables = campaign.all_variables()
	var runtime := MissionRuntime.new(data)
	runtime.log_evaluations = false
	var values := {"experience": experience, "gold": gold, "act_number": current_act + 1}
	for variable in campaign.variables:
		values[variable.name] = variables.get(variable.name, variable.default_value)
	runtime.load_variables_state(values)
	return runtime


## The current value of every campaign variable (the built-in counters and the declared ones), name -> value.
func variable_values(campaign: Campaign) -> Dictionary:
	return _runtime(campaign).get_variables_state()


func conditions_hold(campaign: Campaign, conditions: Array[Condition]) -> bool:
	return conditions.is_empty() or _runtime(campaign).evaluate_conditions(conditions)


## Copies the mission's final variable values into the campaign variables named by `outputs` (a plain
## Set Variable effect per row, so type checks and the built-in counters behave like any other effect).
func apply_mission_outputs(campaign: Campaign, outputs: Array[MissionVariableMap], mission_values: Dictionary) -> void:
	var copies: Array[Effect] = []
	for output in outputs:
		if mission_values.has(output.mission_variable):
			var copy := Effect.new()
			copy.type = Effect.Type.SET_VARIABLE
			copy.variable_name = output.campaign_variable
			copy.value = mission_values[output.mission_variable]
			copies.append(copy)
	await apply_effects(campaign, copies)


## Applies `effects` (Set Variable / Math) to the campaign's variables and counters.
func apply_effects(campaign: Campaign, effects: Array[Effect]) -> void:
	if effects.is_empty():
		return
	var runtime := _runtime(campaign)
	await runtime.apply_effects(effects)
	var values := runtime.get_variables_state()
	experience = int(values["experience"])
	gold = int(values["gold"])
	for variable in campaign.variables:
		variables[variable.name] = values[variable.name]


## Offered on the map now: not won yet, the party is at one of its chapters and its conditions hold.
func is_side_quest_visible(campaign: Campaign, quest: CampaignSideQuest) -> bool:
	if completed_side_quests.has(quest.id):
		return false
	var at_chapter := false
	for chapter_id in quest.chapter_ids:
		if available_chapters.has(chapter_id):
			at_chapter = true
	return at_chapter and conditions_hold(campaign, quest.conditions)


func visible_side_quests(campaign: Campaign) -> Array[CampaignSideQuest]:
	var visible: Array[CampaignSideQuest] = []
	for quest in campaign.side_quests:
		if is_side_quest_visible(campaign, quest):
			visible.append(quest)
	return visible


## Applies how a side quest's mission ended. A win completes it (never offered again) and gives its XP, gold
## and materials; a loss gives nothing (it can be played again). The quest's win / lose effects are applied.
## Returns the same summary shape as apply_result() so the screen can tell it the same way.
func apply_side_quest_result(campaign: Campaign, quest_id: String, won: bool, mission_values: Dictionary = {}) -> Dictionary:
	var summary := {"won": won, "xp": experience, "xp_gained": 0, "gold": 0, "materials": {}, "next": [], "story_after": "", "act_complete": false, "campaign_complete": false}
	var quest := campaign.find_side_quest(quest_id)
	if quest == null or not is_side_quest_visible(campaign, quest):
		return summary
	if not won:
		await apply_mission_outputs(campaign, quest.mission_outputs, mission_values)
		await apply_effects(campaign, quest.lose_effects)
		summary["xp"] = experience
		return summary
	completed_side_quests.append(quest.id)
	experience += quest.reward_xp
	gold += quest.reward_gold
	for material_name in quest.reward_materials:
		add_material(str(material_name), int(quest.reward_materials[material_name]))
	summary["xp"] = experience
	summary["xp_gained"] = quest.reward_xp
	summary["gold"] = quest.reward_gold
	summary["materials"] = quest.reward_materials.duplicate()
	summary["story_after"] = quest.story_after
	var pages: Array[String] = []
	for story in [quest.story_before, quest.story_after]:
		if story != "":
			pages.append(story)
	pages.append("Side quest won: +%d XP%s." % [quest.reward_xp, (", %d gold" % quest.reward_gold) if quest.reward_gold > 0 else ""])
	add_log("Side quest: %s" % quest.title, pages)
	await apply_mission_outputs(campaign, quest.mission_outputs, mission_values)
	await apply_effects(campaign, quest.win_effects)
	summary["xp"] = experience
	return summary


func add_log(title: String, pages: Array[String]) -> void:
	log_entries.append({"title": title, "pages": pages})


## Puts a brand-new campaign at the start of its first act (does nothing once started).
func ensure_started(campaign: Campaign) -> void:
	if campaign_complete or not available_chapters.is_empty():
		return
	if log_entries.is_empty():
		for variable in campaign.variables:
			variables[variable.name] = variable.default_value
		add_log(campaign.campaign_name, [campaign.intro if campaign.intro != "" else "The story begins."])
	_begin_act(campaign, current_act)


func _begin_act(campaign: Campaign, index: int) -> void:
	current_act = index
	available_chapters.clear()
	if index >= campaign.acts.size():
		campaign_complete = true
		add_log("The end", ["The campaign is complete."])
		return
	var act := campaign.acts[index]
	add_log(act.act_name, [act.intro if act.intro != "" else "A new act begins."])
	if act.start_experience >= 0:
		experience = act.start_experience
	if act.find_chapter(act.start_chapter_id) != null:
		available_chapters.append(act.start_chapter_id)


## Applies how a chapter's mission ended. A win: the chapter is completed, the experience counter
## goes up by the chapter's reward_xp, the party gets its gold, and the way forward opens (the chapter's "on win"/"always"
## links; winning a finale ends the act and starts the next one - or finishes the campaign). A loss:
## an "on lose"/"always" link leads on; without one the chapter is simply played again. Returns
## {won, xp (the counter after the result), gold, next (titles of the chapters now
## available), story_after, act_complete, campaign_complete} for the screen to tell.
func apply_result(campaign: Campaign, chapter_id: String, won: bool, mission_values: Dictionary = {}) -> Dictionary:
	var summary := {"won": won, "xp": experience, "xp_gained": 0, "gold": 0, "materials": {}, "next": [], "story_after": "", "act_complete": false, "campaign_complete": false}
	if current_act < 0 or current_act >= campaign.acts.size() or not available_chapters.has(chapter_id):
		return summary
	var act := campaign.acts[current_act]
	var chapter := act.find_chapter(chapter_id)
	if chapter == null:
		return summary
	if won:
		mark_completed(chapter_id)
		experience += chapter.reward_xp
		summary["xp_gained"] = chapter.reward_xp
		summary["gold"] = chapter.reward_gold
		summary["materials"] = chapter.reward_materials.duplicate()
		for material_name in chapter.reward_materials:
			add_material(str(material_name), int(chapter.reward_materials[material_name]))
		summary["story_after"] = chapter.story_after
		var pages: Array[String] = []
		for story in [chapter.story_before, chapter.story_after]:
			if story != "":
				pages.append(story)
		pages.append("Won: +%d XP%s." % [chapter.reward_xp, (", %d gold" % chapter.reward_gold) if chapter.reward_gold > 0 else ""])
		add_log(chapter.title, pages)
		gold += chapter.reward_gold
	await apply_mission_outputs(campaign, chapter.mission_outputs, mission_values)
	await apply_effects(campaign, chapter.win_effects if won else chapter.lose_effects)
	var targets: Array[String] = []
	for link in chapter.links:
		var applies := link.outcome == CampaignLink.Outcome.ANY \
			or (won and link.outcome == CampaignLink.Outcome.WIN) \
			or (not won and link.outcome == CampaignLink.Outcome.LOSE)
		var target := act.find_chapter(link.target_id)
		if applies and target != null and not targets.has(link.target_id) and _predecessors_done(act, target):
			targets.append(link.target_id)
	if won or not targets.is_empty():  # a loss with no way on = play the chapter again
		available_chapters.erase(chapter_id)
		for target in targets:
			if not available_chapters.has(target):
				available_chapters.append(target)
	if won:
		_close_alternatives(act, chapter)
	if won and (chapter.is_finale or available_chapters.is_empty()):
		summary["act_complete"] = true
		_begin_act(campaign, current_act + 1)
		summary["campaign_complete"] = campaign_complete
	summary["xp"] = experience
	for next_id in available_chapters:
		var next_chapter := campaign.acts[current_act].find_chapter(next_id) if current_act < campaign.acts.size() else null
		if next_chapter != null:
			summary["next"].append(next_chapter.title)
	return summary


## After `chapter` is won: for every chapter before it that offered its links as a choice
## (`exclusive_links`), the other targets it opened close for good unless they are done already.
func _close_alternatives(act: CampaignAct, chapter: CampaignChapter) -> void:
	for before in act.predecessors(chapter.id):
		if not before.exclusive_links or not completed_chapters.has(before.id):
			continue
		for link in before.links:
			if link.target_id != chapter.id and not completed_chapters.has(link.target_id):
				available_chapters.erase(link.target_id)


## A join chapter (`wait_for_all`) opens only when every chapter linking to it has been won.
func _predecessors_done(act: CampaignAct, chapter: CampaignChapter) -> bool:
	if not chapter.wait_for_all:
		return true
	for before in act.predecessors(chapter.id):
		if not completed_chapters.has(before.id) and not _is_closed(act, before):
			return false
	return true


## Whether `chapter` was closed for good by a choice: a chapter before it offered its links as a choice
## (`exclusive_links`) and the party won another of them.
func _is_closed(act: CampaignAct, chapter: CampaignChapter) -> bool:
	for before in act.predecessors(chapter.id):
		if not before.exclusive_links or not completed_chapters.has(before.id):
			continue
		for link in before.links:
			if link.target_id != chapter.id and completed_chapters.has(link.target_id):
				return true
	return false


## Whether `place` can be visited: its unlocking chapter (if any) has been won.
func is_place_unlocked(place: CampaignPlace) -> bool:
	return place.unlocked_by_chapter == "" or completed_chapters.has(place.unlocked_by_chapter)


func has_materials(cost: Dictionary) -> bool:
	for material_name in cost:
		if int(materials.get(material_name, 0)) < int(cost[material_name]):
			return false
	return true


## Can the party buy `offer` now: enough gold and materials, and a once-only offer not bought yet.
func can_buy(offer: CampaignOffer) -> bool:
	if offer.once and purchased_offers.has(offer.id):
		return false
	return gold >= offer.cost_gold and has_materials(offer.cost_materials)


## Buys `offer`: pays its cost and the party owns the attachment it gives. False if it can't be bought.
func buy(offer: CampaignOffer) -> bool:
	if not can_buy(offer):
		return false
	gold -= offer.cost_gold
	for material_name in offer.cost_materials:
		add_material(str(material_name), -int(offer.cost_materials[material_name]))
	if offer.attachment != "":
		owned_attachments.append(offer.attachment)
	if offer.once:
		purchased_offers.append(offer.id)
	return true


## "iron:2, wood:1" -> {"iron": 2, "wood": 1}; entries that are not "name:number" are skipped.
static func parse_materials(text: String) -> Dictionary:
	var parsed := {}
	for part in text.split(","):
		var pieces := part.split(":")
		if pieces.size() == 2 and pieces[0].strip_edges() != "" and pieces[1].strip_edges().is_valid_int():
			parsed[pieces[0].strip_edges()] = maxi(int(pieces[1].strip_edges()), 0)
	return parsed


## {"iron": 2, "wood": 1} -> "iron:2, wood:1" (the text parse_materials() reads back).
static func format_materials(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for material_name in cost:
		parts.append("%s:%d" % [material_name, int(cost[material_name])])
	return ", ".join(parts)


func add_material(material_name: String, amount: int) -> void:
	materials[material_name] = maxi(int(materials.get(material_name, 0)) + amount, 0)


func mark_completed(chapter_id: String) -> void:
	if not completed_chapters.has(chapter_id):
		completed_chapters.append(chapter_id)
