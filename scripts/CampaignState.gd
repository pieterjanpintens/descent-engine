class_name CampaignState
extends Resource

## A campaign in progress - the campaign save (CampaignIO.save_state()), separate from a
## mission save: where the party is on the campaign's map, which chapters are done, the heroes'
## progress and what the party owns. One save per campaign, in user://campaign_saves/.

@export var campaign_folder: String = ""
@export var current_act: int = 0
## Ids of the chapters the party has won.
@export var completed_chapters: Array[String] = []
## The chapters of the current act the party can play now (the frontier of its path: the start
## chapter at first, then wherever the links of won/lost chapters lead).
@export var available_chapters: Array[String] = []
@export var campaign_complete: bool = false
@export var heroes: Array[HeroState] = []
@export var gold: int = 0
## Crafting materials: name -> count.
@export var materials: Dictionary = {}
## Names of the weapon attachments (AttachmentCatalog) the party owns.
@export var owned_attachments: Array[String] = []


## The state of hero `slot`, created (level 1, nothing equipped) the first time it is asked for.
func hero(slot: int) -> HeroState:
	for state in heroes:
		if state.hero_slot == slot:
			return state
	var created := HeroState.new()
	created.hero_slot = slot
	heroes.append(created)
	return created


## The party's level for the heroes in `roster` (HeroCatalog slots): their average level,
## rounded down. Missions can use it to scale their monsters up (planned).
func party_level(roster: Array[int], progression: HeroProgression) -> int:
	if roster.is_empty():
		return 1
	var total := 0
	for slot in roster:
		total += hero(slot).level(progression)
	@warning_ignore("integer_division")
	return total / roster.size()


## Puts a brand-new campaign at the start of its first act (does nothing once started).
func ensure_started(campaign: Campaign) -> void:
	if campaign_complete or not available_chapters.is_empty():
		return
	_begin_act(campaign, current_act)


func _begin_act(campaign: Campaign, index: int) -> void:
	current_act = index
	available_chapters.clear()
	if index >= campaign.acts.size():
		campaign_complete = true
		return
	var act := campaign.acts[index]
	if act.find_chapter(act.start_chapter_id) != null:
		available_chapters.append(act.start_chapter_id)


## Applies how a chapter's mission ended. A win: the chapter is completed, every hero in `roster`
## gets its XP, the party its gold, and the way forward opens (the chapter's "on win"/"always"
## links; winning a finale ends the act and starts the next one - or finishes the campaign). A loss:
## an "on lose"/"always" link leads on; without one the chapter is simply played again. Returns
## {won, xp, gold, levels (hero slot -> levels reached), next (titles of the chapters now
## available), story_after, act_complete, campaign_complete} for the screen to tell.
func apply_result(campaign: Campaign, chapter_id: String, won: bool, roster: Array[int]) -> Dictionary:
	var summary := {"won": won, "xp": 0, "gold": 0, "levels": {}, "next": [], "story_after": "", "act_complete": false, "campaign_complete": false}
	if current_act < 0 or current_act >= campaign.acts.size() or not available_chapters.has(chapter_id):
		return summary
	var act := campaign.acts[current_act]
	var chapter := act.find_chapter(chapter_id)
	if chapter == null:
		return summary
	if won:
		mark_completed(chapter_id)
		summary["xp"] = chapter.reward_xp
		summary["gold"] = chapter.reward_gold
		summary["story_after"] = chapter.story_after
		gold += chapter.reward_gold
		for slot in roster:
			var reached := hero(slot).add_experience(chapter.reward_xp, campaign.progression)
			if not reached.is_empty():
				summary["levels"][slot] = reached
	var targets: Array[String] = []
	for link in chapter.links:
		var applies := link.outcome == CampaignLink.Outcome.ANY \
			or (won and link.outcome == CampaignLink.Outcome.WIN) \
			or (not won and link.outcome == CampaignLink.Outcome.LOSE)
		if applies and act.find_chapter(link.target_id) != null and not targets.has(link.target_id):
			targets.append(link.target_id)
	if won or not targets.is_empty():  # a loss with no way on = play the chapter again
		available_chapters.erase(chapter_id)
		for target in targets:
			if not available_chapters.has(target):
				available_chapters.append(target)
	if won and (chapter.is_finale or available_chapters.is_empty()):
		summary["act_complete"] = true
		_begin_act(campaign, current_act + 1)
		summary["campaign_complete"] = campaign_complete
	for next_id in available_chapters:
		var next_chapter := campaign.acts[current_act].find_chapter(next_id) if current_act < campaign.acts.size() else null
		if next_chapter != null:
			summary["next"].append(next_chapter.title)
	return summary


func add_material(material_name: String, amount: int) -> void:
	materials[material_name] = maxi(int(materials.get(material_name, 0)) + amount, 0)


func mark_completed(chapter_id: String) -> void:
	if not completed_chapters.has(chapter_id):
		completed_chapters.append(chapter_id)
