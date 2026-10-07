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
## Crafting materials: name -> count.
@export var materials: Dictionary = {}
## Names of the weapon attachments (AttachmentCatalog) the party owns.
@export var owned_attachments: Array[String] = []


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
func apply_result(campaign: Campaign, chapter_id: String, won: bool) -> Dictionary:
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
		gold += chapter.reward_gold
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
		summary["xp"] = experience
	for next_id in available_chapters:
		var next_chapter := campaign.acts[current_act].find_chapter(next_id) if current_act < campaign.acts.size() else null
		if next_chapter != null:
			summary["next"].append(next_chapter.title)
	return summary


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
