class_name CampaignState
extends Resource

## A campaign in progress - the campaign save (CampaignIO.save_state()), separate from a
## mission save: where the party is on the campaign's map, which chapters are done, the experience
## counter and what the party owns. One save per campaign, in user://campaign_saves/.

@export var campaign_folder: String = ""
## Which package and version this save was started on ("" for a draft or an older save) - shown in the lists, and what an update starts from.
@export var campaign_id: String = ""
@export var campaign_version: String = ""
## The name of this save game (a campaign can have several playthroughs).
@export var save_name: String = ""
## The language this playthrough is read, logged and narrated in, chosen when it was started and never changed (a log in two languages
## would be confusing). "" = a save game from before the choice existed: the player's preferred languages decide.
@export var language: String = ""
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
## Part ids of the runes the party owns (any hero can take one in place of Weapon 1 or 2).
@export var owned_runes: Array[String] = []
## Part ids of the weapon cards the party owns (base ids; a card and its "+" side are one card).
@export var owned_weapons: Array[String] = []
## Base ids of the armor cards the party owns (ArmorData). Armor effects are resolved at the table; the app only tracks
## ownership (and the "+" side in upgraded_cards).
@export var owned_armors: Array[String] = []
## Base ids of the trinket cards the party owns (TrinketData); the "+" side is in upgraded_cards. Each hero equips one at embark.
@export var owned_trinkets: Array[String] = []
## Progress counters of trinkets: trinket id -> count. The Tarnished Brooch counts the defeats of its monster by the wearer (3 unlock the "+").
@export var trinket_counters: Dictionary = {}
## Chapters / side quests (ids) in which the Brooch monster already spawned: it spawns once per chapter, so retrying a lost mission cannot farm the counter.
@export var brooch_spawned_chapters: Array[String] = []
## Set by the campaign player from the Campaign: false = no Brooch monster is defined, the Brooch is out of the game (not sold, not offered).
var brooch_enabled := true
## The owned cards (weapon, part or rune base ids) that are upgraded: their "+" side is up. Permanent, like flipping
## the physical card; set by the starting set and by shop offers marked "upgraded".
@export var upgraded_cards: Array[String] = []
## The narration voice of each hero (hero name -> NarratorVoices id, "" = picked from the name). Asked once, when the
## campaign starts; no two heroes share one (HeroVoicesDialog).
@export var hero_voices: Dictionary = {}
## Ids of the recipes the party has bought (RecipeData); the smithy forges from these.
@export var owned_recipes: Array[String] = []
## Crafted consumables the party carries: consumable id (a potion and its "+" version are two ids) -> count. Their effect is resolved at the table.
@export var consumables: Dictionary = {}
## Rotation steps so far: one for every won chapter or side quest (see advance_shops()).
@export var shop_steps: int = 0
## Per recipe shop (place id): its rotating stock and its random seed - see ShopRotation. Kept in the save so the stock
## is the same after reloading.
@export var shop_state: Dictionary = {}


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
## What a win gives, in words: "+2 XP, 50 gold", or "no reward" when it gives neither (experience is rare, so most wins give none).
static func reward_text(xp: int, gold: int) -> String:
	var parts: Array[String] = []
	if xp > 0:
		parts.append("+%d XP" % xp)
	if gold > 0:
		parts.append(TranslationServer.translate("%d gold") % gold)
	return ", ".join(parts) if not parts.is_empty() else "no reward"


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


## The title of the chapter whose win would take `quest` off the map, or "" when it is not about to go: the quest is offered at
## exactly one chapter the party can play now and winning that chapter does not lead to another chapter of the quest.
## (A quest offered at several playable chapters stays while one of them is left; its conditions are not looked at.)
func vanishing_chapter(campaign: Campaign, quest: CampaignSideQuest) -> String:
	if not is_side_quest_visible(campaign, quest) or current_act >= campaign.acts.size():
		return ""
	var here: Array[String] = []
	for chapter_id in quest.chapter_ids:
		if available_chapters.has(chapter_id):
			here.append(chapter_id)
	if here.size() != 1:
		return ""
	var chapter := campaign.acts[current_act].find_chapter(here[0])
	if chapter == null:
		return ""
	for link in chapter.links:
		if link.outcome != CampaignLink.Outcome.LOSE and quest.chapter_ids.has(link.target_id):
			return ""
	return chapter.title


func visible_side_quests(campaign: Campaign) -> Array[CampaignSideQuest]:
	var visible: Array[CampaignSideQuest] = []
	for quest in campaign.side_quests:
		if is_side_quest_visible(campaign, quest):
			visible.append(quest)
	return visible


## Applies how a side quest's mission ended. A win completes it (never offered again) and gives its XP, gold
## and materials; a loss gives nothing (it can be played again). The quest's win / lose effects are applied.
## Returns the same summary shape as apply_result() so the screen can tell it the same way.
func apply_side_quest_result(campaign: Campaign, quest_id: String, won: bool, mission_values: Dictionary = {}, loot: Dictionary = {}) -> Dictionary:
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
	_take_loot(summary, loot)
	_take_loot(summary, _reward_items(quest.reward_cards, quest.reward_recipes))
	summary["story_after"] = quest.story_after
	add_log(func() -> String: return tr("Side quest: %s") % quest.title, [
		func() -> String: return quest.story_before,
		func() -> String: return quest.story_after,
		func() -> String: return tr("Side quest won: %s.") % reward_text(quest.reward_xp, quest.reward_gold)])
	await apply_mission_outputs(campaign, quest.mission_outputs, mission_values)
	await apply_effects(campaign, quest.win_effects)
	advance_shops(campaign)
	summary["xp"] = experience
	return summary


## `title` and every page are a Callable (built once per language, see LogText), a language map or a finished String.
func add_log(title: Variant, pages: Array) -> void:
	var recorded: Array = []
	for page in pages:
		recorded.append(LogText.record(page))
	log_entries.append({"title": LogText.record(title), "pages": recorded})


## Puts a brand-new campaign at the start of its first act (does nothing once started).
func ensure_started(campaign: Campaign) -> void:
	if campaign_complete or not available_chapters.is_empty():
		return
	if log_entries.is_empty():
		for variable in campaign.variables:
			variables[variable.name] = variable.default_value
		owned_weapons = campaign.starting_weapons.duplicate()
		owned_attachments = campaign.starting_attachments.duplicate()
		owned_runes = campaign.starting_runes.duplicate()
		owned_armors = campaign.starting_armors.duplicate()
		owned_trinkets = campaign.starting_trinkets.duplicate()
		upgraded_cards = campaign.starting_upgrades.duplicate()
		add_log(func() -> String: return campaign.campaign_name, [func() -> String: return campaign.intro if campaign.intro != "" else tr("The story begins.")])
	_begin_act(campaign, current_act)


func _begin_act(campaign: Campaign, index: int) -> void:
	current_act = index
	available_chapters.clear()
	if index >= campaign.acts.size():
		campaign_complete = true
		add_log(func() -> String: return tr("The end"), [func() -> String: return tr("The campaign is complete.")])
		return
	var act := campaign.acts[index]
	add_log(func() -> String: return act.act_name, [func() -> String: return act.intro if act.intro != "" else tr("A new act begins.")])
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
func apply_result(campaign: Campaign, chapter_id: String, won: bool, mission_values: Dictionary = {}, loot: Dictionary = {}) -> Dictionary:
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
		_take_loot(summary, loot)
		_take_loot(summary, _reward_items(chapter.reward_cards, chapter.reward_recipes))
		summary["story_after"] = chapter.story_after
		add_log(func() -> String: return chapter.title, [
			func() -> String: return chapter.story_before,
			func() -> String: return chapter.story_after,
			func() -> String: return tr("Won: %s.") % reward_text(chapter.reward_xp, chapter.reward_gold)])
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
	if won:
		advance_shops(campaign)
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


## Whether `place` can be visited now: its unlocking chapter (if any) has been won and its closing chapter (if any) has not - or, once closed, its reopening chapter (if any) has been won.
func is_place_open(place: CampaignPlace) -> bool:
	if place.unlocked_by_chapter != "" and not completed_chapters.has(place.unlocked_by_chapter):
		return false
	if place.closes_after_chapter == "" or not completed_chapters.has(place.closes_after_chapter):
		return true
	return place.reopens_after_chapter != "" and completed_chapters.has(place.reopens_after_chapter)


## The materials the party took from defeated monsters during a WON mission go into the stock (and the summary).
## A lost mission gives no loot (it is played again).
func _take_loot(summary: Dictionary, loot: Dictionary) -> void:
	for material_name in loot:
		var count := int(loot[material_name])
		var key := str(material_name)
		if key.begins_with(LootMaterials.CARD_PREFIX):
			var card_id := key.trim_prefix(LootMaterials.CARD_PREFIX)
			if not owns_card(card_id):
				_add_card(card_id)
			_note_item(summary, RecipeData.card_label(card_id))
			continue
		if key.begins_with(LootMaterials.RECIPE_PREFIX):
			var recipe_id := key.trim_prefix(LootMaterials.RECIPE_PREFIX)
			if not owned_recipes.has(recipe_id):
				owned_recipes.append(recipe_id)
			var recipe := RecipeData.find(recipe_id)
			_note_item(summary, tr("Recipe: ") + (RecipeData.label(recipe) if not recipe.is_empty() else recipe_id))
			continue
		if material_name == LootMaterials.GOLD:
			gold += count
			summary["gold"] = int(summary.get("gold", 0)) + count
			continue
		add_material(str(material_name), count)
		summary["materials"][material_name] = int(summary["materials"].get(material_name, 0)) + count


## A reward's cards and recipes in the collected-loot form _take_loot() understands.
static func _reward_items(cards: Array[String], recipes: Array[String]) -> Dictionary:
	var items := {}
	for card_id in cards:
		items[LootMaterials.CARD_PREFIX + card_id] = 1
	for recipe_id in recipes:
		items[LootMaterials.RECIPE_PREFIX + recipe_id] = 1
	return items


## The party owns this weapon / part / rune / armor card from now on.
func _add_card(card_id: String) -> void:
	match RecipeData.card_kind(card_id):
		"armor":
			owned_armors.append(card_id)
		"trinket":
			owned_trinkets.append(card_id)
		"rune":
			owned_runes.append(card_id)
		"weapon":
			owned_weapons.append(card_id)
		_:
			owned_attachments.append(card_id)


func _note_item(summary: Dictionary, text: String) -> void:
	if not summary.has("items"):
		summary["items"] = []
	(summary["items"] as Array).append(text)


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
	if offer.rune != "" and not owned_runes.has(offer.rune):
		owned_runes.append(offer.rune)
	if offer.weapon != "" and not owned_weapons.has(offer.weapon):
		owned_weapons.append(offer.weapon)
	if offer.armor != "" and not owned_armors.has(offer.armor):
		owned_armors.append(offer.armor)
	if offer.trinket != "" and not owned_trinkets.has(offer.trinket):
		owned_trinkets.append(offer.trinket)
	if offer.upgraded:
		for card_id in [offer.attachment, offer.rune, offer.weapon, offer.armor, offer.trinket]:
			if card_id != "" and not upgraded_cards.has(card_id):
				upgraded_cards.append(card_id)
	if offer.once:
		purchased_offers.append(offer.id)
	return true


# ---------------------------------------------------------------- market, recipe shop and smithy

## What the market pays for one `material_key`: the campaign's sell percentage of its value, rounded down.
func sell_price(campaign: Campaign, material_key: String) -> int:
	return floori(LootMaterials.value(material_key) * clampi(campaign.sell_percent, 0, 100) / 100.0)


## Buys `count` of a material at its full value.
func buy_material(material_key: String, count: int = 1) -> bool:
	var price := LootMaterials.value(material_key) * count
	if count <= 0 or price <= 0 or gold < price:
		return false
	gold -= price
	add_material(material_key, count)
	return true


## Sells `count` of a material for the campaign's sell price (false when the party has too few or nothing is paid).
func sell_material(campaign: Campaign, material_key: String, count: int = 1) -> bool:
	var price := sell_price(campaign, material_key) * count
	if count <= 0 or price <= 0 or int(materials.get(material_key, 0)) < count:
		return false
	add_material(material_key, -count)
	gold += price
	return true


## Whether the party already has this card (a weapon card, a part B / C or a rune).
func owns_card(card_id: String) -> bool:
	match RecipeData.card_kind(card_id):
		"armor":
			return owned_armors.has(card_id)
		"trinket":
			return owned_trinkets.has(card_id)
		"rune":
			return owned_runes.has(card_id)
		"weapon":
			return owned_weapons.has(card_id)
		_:
			return owned_attachments.has(card_id)


## Whether the recipe still has something to make: a new card the party lacks, or an upgrade for a card it owns that is not
## upgraded yet.
func recipe_target_open(recipe: Dictionary) -> bool:
	if recipe.get("consumable", false):
		return true  # a potion recipe makes the potion again and again
	var card := str(recipe["card"])
	if recipe["upgrade"]:
		return owns_card(card) and not upgraded_cards.has(card)
	return not owns_card(card)


## The recipe ids that may appear in `place`'s rotating stock now: not owned, not listed by hand, still useful and (if the
## shop asks for it) reached in the game's own terms.
func _recipe_pool(place: CampaignPlace) -> Array[String]:
	var listed: Array[String] = []
	for entry in place.listed_recipes:
		listed.append(entry.recipe_id)
	var pool: Array[String] = []
	for recipe in RecipeData.all():
		var id := str(recipe["id"])
		if owned_recipes.has(id) or listed.has(id) or not recipe_target_open(recipe):
			continue
		if _is_brooch_recipe(recipe):
			continue
		if place.tier_weight(RecipeData.tier(recipe)) <= 0:
			continue
		pool.append(id)
	return pool


## How likely each recipe of `pool` is to be drawn: its tier's weight shared by the recipes of that tier in the pool, so the chance that a
## draw comes from a tier follows the tier weights whatever the number of recipes in it.
func _recipe_weights(place: CampaignPlace, pool: Array[String]) -> Dictionary:
	var per_tier := {}
	for id in pool:
		var tier := RecipeData.tier(RecipeData.find(id))
		per_tier[tier] = int(per_tier.get(tier, 0)) + 1
	var weights := {}
	for id in pool:
		var tier := RecipeData.tier(RecipeData.find(id))
		weights[id] = float(place.tier_weight(tier)) / float(per_tier[tier])
	return weights


## The Brooch's "+" is earned by the counter, never bought or forged; the Brooch itself is only sold when the campaign defines its monster.
func _is_brooch_recipe(recipe: Dictionary) -> bool:
	if str(recipe["card"]) != TrinketData.BROOCH_ID:
		return false
	return recipe["upgrade"] or not brooch_enabled


func _rotate_shop(place: CampaignPlace) -> void:
	var shop: Dictionary = shop_state.get(place.id, {})
	if not shop.has("seed"):
		shop["seed"] = randi()
	var pool := _recipe_pool(place)
	var next := ShopRotation.rotate(shop, shop_steps, pool, maxi(place.stock_size, 0), maxi(place.min_stay, 1), int(shop["seed"]), _recipe_weights(place, pool))
	next["seed"] = shop["seed"]
	shop_state[place.id] = next


## One rotation step - called when the party wins a chapter or a side quest: every recipe shop of the current act the party
## can visit rotates (a shop met for the first time gets its first stock). A lost mission or a replay does not rotate.
func advance_shops(campaign: Campaign) -> void:
	shop_steps += 1
	if current_act < 0 or current_act >= campaign.acts.size():
		return
	for place in campaign.acts[current_act].places:
		if place.kind == CampaignPlace.Kind.RECIPE_SHOP and is_place_open(place):
			_rotate_shop(place)


## What a recipe shop has on sale now: {"entries": [{id, leaving, listed}], "rumour": String}. `leaving` = it goes at the
## next rotation; the rumour is a vague hint of what may arrive then ("" when nothing is announced).
func shop_view(place: CampaignPlace) -> Dictionary:
	if not shop_state.has(place.id):
		_rotate_shop(place)
	var entries: Array[Dictionary] = []
	for listed in place.listed_recipes:
		var recipe := RecipeData.find(listed.recipe_id)
		if recipe.is_empty() or owned_recipes.has(listed.recipe_id) or _is_brooch_recipe(recipe):
			continue
		if listed.unlocked_by_chapter != "" and not completed_chapters.has(listed.unlocked_by_chapter):
			continue
		entries.append({"id": listed.recipe_id, "leaving": false, "listed": true})
	var shop: Dictionary = shop_state[place.id]
	for entry: Dictionary in shop.get("stock", []):
		var recipe := RecipeData.find(str(entry["id"]))
		if not recipe.is_empty() and not owned_recipes.has(entry["id"]) and recipe_target_open(recipe):
			entries.append({"id": entry["id"], "leaving": bool(entry.get("leaving", false)), "listed": false})
	var hints: Array[String] = []
	for id: String in shop.get("incoming", []):
		var recipe := RecipeData.find(id)
		if not recipe.is_empty() and hints.size() < 2:
			hints.append(RecipeData.hint(recipe))
	return {"entries": entries, "rumour": "" if hints.is_empty() else "Rumour: %s may arrive soon." % " and ".join(hints)}


func can_buy_recipe(recipe_id: String) -> bool:
	var recipe := RecipeData.find(recipe_id)
	if recipe.is_empty() or gold < int(recipe["price"]):
		return false
	# a direct entry (a base armor) is bought as the card itself; a recipe is bought once
	return not owns_card(str(recipe["card"])) if recipe["direct"] else not owned_recipes.has(recipe_id)


## Buys a recipe for its price; it leaves every shop (the pool no longer holds it). A direct entry (a base armor) gives the
## card at once instead of a recipe.
func buy_recipe(recipe_id: String) -> bool:
	if not can_buy_recipe(recipe_id):
		return false
	var recipe := RecipeData.find(recipe_id)
	gold -= int(recipe["price"])
	if recipe["direct"]:
		_add_card(str(recipe["card"]))
	else:
		owned_recipes.append(recipe_id)
	_remove_from_shops(recipe_id)
	return true


## A bought recipe is no longer offered anywhere: it leaves the stock and the announced arrivals of every recipe shop (several
## shops may offer the same recipe). The emptied slot is refilled at the next rotation, not at once. A recipe a shop lists by
## hand is hidden by shop_view() as long as it is owned.
func _remove_from_shops(recipe_id: String) -> void:
	for place_id in shop_state:
		var shop: Dictionary = shop_state[place_id]
		var stock: Array[Dictionary] = []
		for entry: Dictionary in shop.get("stock", []):
			if str(entry["id"]) != recipe_id:
				stock.append(entry)
		shop["stock"] = stock
		var incoming: Array[String] = []
		for id: String in shop.get("incoming", []):
			if id != recipe_id:
				incoming.append(id)
		shop["incoming"] = incoming


## The owned recipes that still have something to make.
func forgeable_recipes() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for recipe_id in owned_recipes:
		var recipe := RecipeData.find(recipe_id)
		if not recipe.is_empty() and not recipe.get("consumable", false) and recipe_target_open(recipe):
			list.append(recipe)
	return list


func can_forge(recipe_id: String) -> bool:
	var recipe := RecipeData.find(recipe_id)
	return not recipe.is_empty() and not recipe.get("consumable", false) and owned_recipes.has(recipe_id) and recipe_target_open(recipe) and has_materials(recipe["ingredients"])


## The owned consumable (potion) recipes - what the alchemist can brew.
func brewable_recipes() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for recipe_id in owned_recipes:
		var recipe := RecipeData.find(recipe_id)
		if not recipe.is_empty() and recipe.get("consumable", false):
			list.append(recipe)
	return list


func can_brew(recipe_id: String) -> bool:
	var recipe := RecipeData.find(recipe_id)
	return not recipe.is_empty() and recipe.get("consumable", false) and owned_recipes.has(recipe_id) and has_materials(recipe["ingredients"])


## Brews one consumable of an owned recipe: pays the materials, the party carries one more.
func brew(recipe_id: String) -> bool:
	if not can_brew(recipe_id):
		return false
	var recipe := RecipeData.find(recipe_id)
	for material_name in recipe["ingredients"]:
		add_material(str(material_name), -int(recipe["ingredients"][material_name]))
	add_consumable(str(recipe["card"]), 1)
	return true


func consumable_count(consumable_id: String) -> int:
	return int(consumables.get(consumable_id, 0))


func add_consumable(consumable_id: String, amount: int) -> void:
	consumables[consumable_id] = maxi(consumable_count(consumable_id) + amount, 0)


## Forges the item of an owned recipe: pays the materials, and the party gets the new card or flips the owned one to its "+".
func forge(recipe_id: String) -> bool:
	if not can_forge(recipe_id):
		return false
	var recipe := RecipeData.find(recipe_id)
	for material_name in recipe["ingredients"]:
		add_material(str(material_name), -int(recipe["ingredients"][material_name]))
	var card := str(recipe["card"])
	if recipe["upgrade"]:
		upgraded_cards.append(card)
	else:
		_add_card(card)
	return true


## {"metal": 2, "terros": 1} -> "2x Metal, Terros" - for the screens (the editors use a counter per material).
static func format_materials(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for material_name in cost:
		var count := int(cost[material_name])
		var shown := LootMaterials.display_name(str(material_name))
		parts.append(shown if count == 1 else "%dx %s" % [count, shown])
	return ", ".join(parts)


func add_material(material_name: String, amount: int) -> void:
	materials[material_name] = maxi(int(materials.get(material_name, 0)) + amount, 0)


func bind_campaign(campaign: Campaign) -> void:
	brooch_enabled = campaign.brooch_monster != null


## One more defeat of the Brooch monster by the wearer; the third unlocks the "+" side. Returns the new count.
func add_brooch_defeat() -> int:
	var count := int(trinket_counters.get(TrinketData.BROOCH_ID, 0)) + 1
	trinket_counters[TrinketData.BROOCH_ID] = count
	if count >= TrinketData.BROOCH_DEFEATS_NEEDED and not upgraded_cards.has(TrinketData.BROOCH_ID):
		upgraded_cards.append(TrinketData.BROOCH_ID)
	return count


## Undying Skull: one more defeat of this enemy type (folder) by a wearer; returns the new count (kept for the whole campaign).
func bump_skull_count(folder: String) -> int:
	var key := "TRINKET10_ID:" + folder
	var count := int(trinket_counters.get(key, 0)) + 1
	trinket_counters[key] = count
	return count


## The Undying Skull's "unique recipe": the most expensive recipe (a new weapon / part card or an upgrade, not rune / armor / trinket / potion) for a
## weapon type the hero in `slot` uses that the party can still make use of and does not own yet. "" when there is none.
func pick_skull_recipe(slot: int) -> String:
	var types: Array[String] = [WeaponCatalog.type_of(slot, 0), WeaponCatalog.type_of(slot, 1)]
	var best: Array[String] = []
	var best_price := -1
	for recipe in RecipeData.all():
		if recipe["direct"] or recipe.get("consumable", false) or owned_recipes.has(recipe["id"]):
			continue
		var card := str(recipe["card"])
		var kind := RecipeData.card_kind(card)
		if kind != "weapon" and kind != "B" and kind != "C":
			continue
		if not types.has(WeaponData.weapon_type_of_part(card)) or not recipe_target_open(recipe):
			continue
		var price := int(recipe["price"])
		if price > best_price:
			best_price = price
			best = [str(recipe["id"])]
		elif price == best_price:
			best.append(str(recipe["id"]))
	return "" if best.is_empty() else best.pick_random()


func mark_completed(chapter_id: String) -> void:
	if not completed_chapters.has(chapter_id):
		completed_chapters.append(chapter_id)
