class_name FeatTracker
extends RefCounted

## Counts what happens in a mission towards the heroes' ACTIVE feats, automatically. A feat is a rule record from the game's data (HeroData.feat(): `timing` = when it
## is checked, `goal` = how often, `filters` = the conditions that are switched on), so one evaluator covers all 120 feats instead of 120 hand-written rules. The mission
## reports events (attacks, defeats, wounds, interactions, items gained, monster activations, the end of a round and of the quest); for every hero in the party the
## tracker checks the events against that hero's active feats and adds progress through CampaignState.add_feat_progress() - saving the campaign state as it goes, so a feat
## keeps its progress between missions. A completed feat is announced with `feat_completed` (the mission shows it and lets the player pick a new feat).
##
## Timing numbers of the game's feats: 1 on an attack, 2 an enemy activation, 3 a hero wounded, 4 an enemy defeated, 5 an interaction, 6 something gained (materials,
## a consumable, a recipe), 7 the end of a round, 8 the end of the quest, 9 the first action of a round (an attack OR an interaction), 10 attacks on the same enemy.
## Only tracked in a campaign mission, and only with the hero data export. State per round (who attacked / interacted, which enemy was attacked by whom) lives in the tracker
## and starts afresh when a saved mission is resumed. Damage numbers are the app's: part A abilities and other table adjustments are not in them.

signal feat_completed(hero_id: String, result: Dictionary)

## Our monster figure folders -> the game's enemy family numbers (the numbers in the feats' EnemyTypes). Dragons (12) have no figure.
const FAMILY_OF_FOLDER := {
	"berserker": 0, "bandit": 1, "zealot": 2, "golem": 3, "fae": 4, "wolf": 5, "specter": 6, "wight": 7, "harbinger": 8, "centurion": 9,
	"blood sister": 10, "doomcaller": 11, "salamander": 13, "vampire": 14, "reanimate": 15, "legionnaire": 16, "mercenary": 17,
}
const FAMILY_ANIMUS := 3  # the golem family; Syrus's "animus" feats list family 3
const FAMILY_DRAGON := 12

## The feats' InteractableType numbers -> the mesh item names of our props (the game's door and gate are our gate and fence; the exploration token is the sight token).
const PROP_MESHES := {
	1: ["chest"], 2: ["bookshelf"], 3: ["altar"], 4: ["well"], 5: ["pot"], 6: ["gate", "fence"], 7: ["exploration"], 8: ["bell"],
	9: ["bloodshrine"], 10: ["fire"], 12: ["statue", "statue2"], 13: ["cart"],
}
## The bits of the feats' EnemyConditions -> MonsterCondition.Kind.
const CONDITION_BITS := {2: MonsterCondition.Kind.ENFEEBLED, 16: MonsterCondition.Kind.EXPOSED, 64: MonsterCondition.Kind.CONFUSED}
## The feats' ItemType numbers.
const ITEM_MATERIAL := 0
const ITEM_CONSUMABLE := 1
const ITEM_RECIPE := 5
const TIMING_KINDS := {1: ["attack"], 2: ["activation"], 3: ["wound"], 4: ["defeat"], 5: ["interaction"], 6: ["item"], 7: ["round_end"], 8: ["quest_end"], 9: ["attack", "interaction"], 10: ["attack"]}
## Every filter this tracker understands; a feat with another one switched on is reported by is_tracked() as not automatic.
const KNOWN_FILTERS: Array[String] = [
	"WeaponClasses", "EnemyTypes", "ItemType", "HeroInjured", "InteractableType", "EnemyConditions", "GoalIsTotalDamage", "WeaknessDamage",
	"ExcessWeaknessDamage", "RequireObjectRemove", "AttackWithBothWeapons", "SameEnemy", "DamagedEnemy", "AnyHero", "AnyHeroInjured", "AnyOtherHeroInjured",
	"EnemyHasTactic", "FirstAttackOfRound", "FirstInteractionOfRound", "FirstTimeInteracted", "FirstTimeAttackedByHero", "HeroAttackedThisRound",
	"EnemyWasAttackedThisRound", "OtherHeroDidDamage", "AllOtherHeroesDidDamageThisRound", "AllHeroesDidDamageThisRound", "DiedFromAffliction",
	"IsVictory", "MinimumDamage", "AmountOfTimeDuringRound", "ForAmountOfRounds", "StatusCount", "EnemiesOnMap",
]

var campaign: Campaign
var state: CampaignState
var runtime: MissionRuntime
var roster: Array[int] = []
var round_number := 1

var _actor_slot := -1  ## the hero whose attack / interaction is being resolved right now (items gained meanwhile are credited to them)
var _actor_kind := ""
var _attack_log: Array[Dictionary] = []  ## this round: {slot, monster_id}
var _interact_log: Array[Dictionary] = []  ## this round: {slot}
var _qualified: Dictionary = {}  ## "slot|feat|round" -> the events of this round that passed a feat's single-event filters (for "N times in a round")
var _pattern_done: Dictionary = {}  ## the same keys -> true once counted this round
var _streaks: Dictionary = {}  ## "slot|feat" -> {round, count, monster} for "in N consecutive rounds"
var _attackers: Dictionary = {}  ## monster id -> hero slots that attacked it (whole mission)
var _damagers: Dictionary = {}  ## monster id -> hero slots that damaged it
var _props_seen: Dictionary = {}  ## prop id -> true once somebody interacted with it
var _round_attacked: Dictionary = {}  ## slot -> true
var _round_damaged: Dictionary = {}  ## slot -> true
var _wounds_total := 0
var _dirty := false


func setup(campaign_in: Campaign, state_in: CampaignState, runtime_in: MissionRuntime, roster_in: Array[int], round_in: int) -> void:
	campaign = campaign_in
	state = state_in
	runtime = runtime_in
	roster = roster_in.duplicate()
	round_number = round_in
	runtime.items_gained.connect(_on_items_gained)


## Whether the app can count this feat by itself: its timing is one we get events for and every filter it uses is known (see KNOWN_FILTERS).
static func is_tracked(feat: Dictionary) -> bool:
	if feat.is_empty() or not TIMING_KINDS.has(int(feat["timing"])):
		return false
	for name: String in feat["filters"]:
		if not KNOWN_FILTERS.has(name):
			return false
	return true


# --- the events the mission reports ----------------------------------------------------------------------------------------------

## What the tracker needs to know about a monster BEFORE an attack on it (call it right before MissionRuntime.resolve_attack()).
func snapshot(monster: RuntimeMonster, slot: int) -> Dictionary:
	return {
		"hp_full": monster.hitpoints >= monster.max_hitpoints, "statuses": monster.conditions.size(), "conditions": monster.conditions.duplicate(),
		"attacked_round": monster.attacked_this_round, "attacked_by_hero": _attackers.get(monster.id, []).has(slot),
		"damaged_by": _damagers.get(monster.id, []).duplicate(), "has_tactic": monster.prepared_tactic >= 0,
	}


## The hero `slot` is about to do something that can gain items (an attack that may defeat a monster, an interaction); items gained until end_action() are theirs.
func begin_action(slot: int, kind: String) -> void:
	_actor_slot = slot
	_actor_kind = kind


func end_action() -> void:
	_actor_slot = -1
	_actor_kind = ""


## An attack was resolved (`result` = MissionRuntime.resolve_attack()'s dictionary, `pre` = snapshot() taken before it).
func on_attack(slot: int, weapon_index: int, weapon: Weapon, monster: RuntimeMonster, pre: Dictionary, result: Dictionary) -> void:
	var dealt := int(result.get("dealt", 0))
	var weakness := mini(int(result.get("weakness_damage", 0)), dealt)
	var ctx := {
		"slot": slot, "weapon_index": weapon_index, "weapon_class": WeaponData.class_of_part(weapon.part_id) if weapon != null else -1,
		"monster": monster, "monster_id": monster.id, "dealt": dealt, "weakness_damage": weakness, "excess_weakness": mini(weakness, int(result.get("overkill", 0))),
		"hp_full": pre["hp_full"], "statuses": pre["statuses"], "conditions": pre["conditions"], "attacked_round": pre["attacked_round"],
		"attacked_by_hero": pre["attacked_by_hero"], "damaged_by": pre["damaged_by"], "has_tactic": pre["has_tactic"], "affliction": false,
	}
	_add_round_flags(ctx, slot)
	_dispatch("attack", ctx)
	if bool(result.get("defeated", false)):
		var defeat := ctx.duplicate()
		defeat["conditions"] = monster.conditions.duplicate()  # what it had when it fell
		defeat["statuses"] = monster.conditions.size()
		_dispatch("defeat", defeat)
	_attack_log.append({"slot": slot, "monster_id": monster.id})
	var attackers: Array = _attackers.get(monster.id, [])
	if not attackers.has(slot):
		attackers.append(slot)
	_attackers[monster.id] = attackers
	if dealt > 0:
		var damagers: Array = _damagers.get(monster.id, [])
		if not damagers.has(slot):
			damagers.append(slot)
		_damagers[monster.id] = damagers
		_round_damaged[slot] = true
	_round_attacked[slot] = true
	_flush()


## Monsters that fell to affliction damage (no hero attacked them).
func on_affliction_defeats(monsters: Array) -> void:
	for monster: RuntimeMonster in monsters:
		_dispatch("defeat", {
			"slot": -1, "monster": monster, "monster_id": monster.id, "conditions": monster.conditions.duplicate(), "statuses": monster.conditions.size(),
			"damaged_by": _damagers.get(monster.id, []).duplicate(), "has_tactic": monster.prepared_tactic >= 0, "affliction": true, "weapon_class": -1,
			"first_attack": true, "first_interaction": true, "first_interaction_other": true,
		})
	_flush()


## Hero `slot` was wounded (`wounds` = how many wounds they have now).
func on_wound(slot: int, wounds: int) -> void:
	_wounds_total += 1
	_dispatch("wound", {"slot": slot, "wounds": wounds, "attacked": _round_attacked.has(slot)})
	_flush()


## A monster activation starts / ends (the marker is what activation_start() returned): feats like "an activation without any hero being wounded".
func activation_start() -> int:
	return _wounds_total


func activation_end(marker: int) -> void:
	_dispatch("activation", {"wound_during": _wounds_total != marker})
	_flush()


## Hero `slot` used a prop (call it after the action's effects ran and before the caller drains what they queued): whether the object was removed or monsters spawn
## is read from the runtime's pending queues.
func on_interaction(slot: int, entry: InteractableEntry) -> void:
	var enemies := runtime.monsters.size() + (1 if runtime.has_pending_spawns() else 0)
	var ctx := {
		"slot": slot, "prop_id": entry.id, "prop_mesh": entry.mesh_item_name, "removed": runtime.pending_removal_ids().has(entry.id),
		"first_time_prop": not _props_seen.has(entry.id), "enemies": enemies,
	}
	_add_round_flags(ctx, slot)
	_dispatch("interaction", ctx)
	_interact_log.append({"slot": slot})
	_props_seen[entry.id] = true
	_flush()


## The end of a round (after the monster phase): "finish a round" feats are checked, then the round's records start afresh.
func on_round_end() -> void:
	_dispatch("round_end", {"enemies": runtime.monsters.size()})
	round_number += 1
	_attack_log.clear()
	_interact_log.clear()
	_qualified.clear()
	_pattern_done.clear()
	_round_attacked.clear()
	_round_damaged.clear()
	_flush()


func on_quest_end(won: bool) -> void:
	_dispatch("quest_end", {"won": won})
	_flush()


func _on_items_gained(materials: int, consumables: int, recipes: Array) -> void:
	if materials > 0:
		_dispatch("item", {"item_kind": ITEM_MATERIAL, "amount": materials, "slot": _actor_slot, "actor_kind": _actor_kind})
	if consumables > 0:
		_dispatch("item", {"item_kind": ITEM_CONSUMABLE, "amount": consumables, "slot": _actor_slot, "actor_kind": _actor_kind})
	if not recipes.is_empty():
		_dispatch("item", {"item_kind": ITEM_RECIPE, "amount": recipes.size(), "slot": _actor_slot, "actor_kind": _actor_kind})


# --- evaluation ------------------------------------------------------------------------------------------------------------------

## Whether nobody has attacked / interacted yet this round (judged before the event itself is logged).
func _add_round_flags(ctx: Dictionary, slot: int) -> void:
	ctx["first_attack"] = _attack_log.is_empty()
	ctx["first_interaction"] = _interact_log.is_empty()
	ctx["first_interaction_other"] = _interact_log.all(func(entry: Dictionary) -> bool: return entry["slot"] == slot)


func _dispatch(kind: String, ctx: Dictionary) -> void:
	for slot in roster:
		var hero_id := HeroData.id_for_slot(slot)
		var active := state.active_feats(campaign, hero_id)
		for feat_id: String in active.keys():
			var feat := HeroData.feat(feat_id)
			if feat.is_empty() or not (TIMING_KINDS.get(int(feat["timing"]), []) as Array).has(kind):
				continue
			var amount := _amount(slot, feat, kind, ctx)
			if amount > 0:
				_progress(hero_id, feat_id, amount)


func _progress(hero_id: String, feat_id: String, amount: int) -> void:
	var result := state.add_feat_progress(campaign, hero_id, feat_id, amount)
	if result.is_empty():
		return
	_dirty = true
	if bool(result["completed"]):
		feat_completed.emit(hero_id, result)


func _flush() -> void:
	if _dirty:
		_dirty = false
		CampaignIO.save_state(state)


## How much progress the event gives hero `slot`'s feat (0 = none).
func _amount(slot: int, feat: Dictionary, kind: String, ctx: Dictionary) -> int:
	var filters: Dictionary = feat["filters"]
	var feat_key := str(feat["id"])
	if not is_tracked(feat):
		return 0
	var any_hero := filters.has("AnyHero")
	# whose action it is: an attack / defeat / interaction / wound counts for the hero themselves (or for any hero when the feat says so)
	if kind in ["attack", "defeat", "interaction", "wound"] and int(ctx.get("slot", -1)) >= 0 and not any_hero and int(ctx["slot"]) != slot:
		return 0
	for filter_name: String in filters:
		if not _filter_ok(filter_name, filters[filter_name], slot, feat, kind, ctx):
			return 0
	var amount := 1
	if kind == "item":
		amount = int(ctx.get("amount", 1))
	if filters.has("GoalIsTotalDamage"):
		amount = int(ctx.get("dealt", 0))
	if filters.has("WeaknessDamage"):
		amount = int(ctx.get("weakness_damage", 0))
	if filters.has("ExcessWeaknessDamage"):
		amount = int(ctx.get("excess_weakness", 0))
	if amount <= 0:
		return 0
	# patterns over a round / several rounds count once the pattern is complete instead of per event
	if filters.has("ForAmountOfRounds"):
		return _consecutive_rounds(slot, feat_key, int(filters["ForAmountOfRounds"]["Value"]), filters, ctx)
	if filters.has("AmountOfTimeDuringRound") or filters.has("AttackWithBothWeapons"):
		return _round_pattern(slot, feat_key, filters, ctx)
	return amount


func _filter_ok(name: String, spec: Dictionary, slot: int, feat: Dictionary, kind: String, ctx: Dictionary) -> bool:
	var value = spec.get("Value", 0)
	match name:
		"WeaponClasses":
			return _has_int(value, int(ctx.get("weapon_class", -1)))
		"EnemyTypes":
			var monster: RuntimeMonster = ctx.get("monster")
			if monster == null:
				return false
			for family in value:
				if _is_family(monster, int(family)):
					return true
			return false
		"EnemyConditions":
			var present: Array = ctx.get("conditions", [])
			for bit in CONDITION_BITS:
				if (int(value) & bit) != 0 and not present.has(CONDITION_BITS[bit]):
					return false
			return true
		"DamagedEnemy":
			return bool(ctx.get("hp_full", false)) if int(value) == 0 else not bool(ctx.get("hp_full", false))
		"StatusCount":
			return int(ctx.get("statuses", 0)) >= int(value)
		"FirstTimeAttackedByHero":
			return not bool(ctx.get("attacked_by_hero", false))
		"EnemyWasAttackedThisRound":
			return not bool(ctx.get("attacked_round", false))  # the feat wants an enemy that has NOT been attacked yet this round
		"EnemyHasTactic":
			return bool(ctx.get("has_tactic", false))
		"OtherHeroDidDamage":
			var others_damaged := (ctx.get("damaged_by", []) as Array).any(func(other): return int(other) != int(ctx.get("slot", -1)) and int(other) != slot)
			return others_damaged if int(value) == 1 else not others_damaged
		"DiedFromAffliction":
			return bool(ctx.get("affliction", false)) == (int(value) == 1)
		"MinimumDamage":
			return int(ctx.get("dealt", 0)) >= int(value)
		"FirstAttackOfRound":
			return bool(ctx.get("first_attack", false))
		"FirstInteractionOfRound":
			# "Clear the Way" only minds interactions of OTHER heroes
			return bool(ctx.get("first_interaction_other", false)) if str(feat["id"]) == "FEAT_KEHLI_8" else bool(ctx.get("first_interaction", false))
		"HeroAttackedThisRound":
			var attacked := _round_attacked.has(slot)
			return attacked if int(value) == 1 else not attacked
		"HeroInjured":
			return _hero_injured_ok(slot, spec, feat)
		"AnyHeroInjured":
			if kind == "activation":
				return not bool(ctx.get("wound_during", false))
			if kind == "wound":
				return _others_uninjured(slot)
			return _all_uninjured()
		"AnyOtherHeroInjured":
			var some_other := roster.any(func(other: int) -> bool: return other != slot and runtime.wound_count(other) > 0)
			return some_other if int(value) == 1 else not some_other
		"AllHeroesDidDamageThisRound":
			return roster.all(func(hero: int) -> bool: return _round_damaged.has(hero))
		"AllOtherHeroesDidDamageThisRound":
			return roster.all(func(hero: int) -> bool: return hero == slot or _round_damaged.has(hero))
		"EnemiesOnMap":
			return int(ctx.get("enemies", runtime.monsters.size())) >= int(value)
		"InteractableType":
			return (PROP_MESHES.get(int(value), []) as Array).has(str(ctx.get("prop_mesh", "")))
		"RequireObjectRemove":
			return bool(ctx.get("removed", false))
		"FirstTimeInteracted":
			return bool(ctx.get("first_time_prop", false)) if int(value) == 1 else not bool(ctx.get("first_time_prop", false))
		"ItemType":
			if not _has_int(value, int(ctx.get("item_kind", -1))):
				return false
			# a recipe "during your interactions" is the interacting hero's
			if int(ctx.get("item_kind", -1)) == ITEM_RECIPE and not feat["filters"].has("AnyHero"):
				return int(ctx.get("slot", -1)) == slot and str(ctx.get("actor_kind", "")) == "interaction"
			return true
		"IsVictory":
			return bool(ctx.get("won", false)) == (int(value) == 1)
		"GoalIsTotalDamage", "WeaknessDamage", "ExcessWeaknessDamage", "AnyHero", "AttackWithBothWeapons", "SameEnemy", "AmountOfTimeDuringRound", "ForAmountOfRounds":
			return true  # not conditions of one event: they decide how much counts (see _amount / the round patterns)
	return false


## Whether a list of numbers from the feat data holds `number` (the numbers come out of JSON as floats, so a plain Array.has(int) would not find them).
static func _has_int(list: Array, number: int) -> bool:
	for entry in list:
		if int(entry) == number:
			return true
	return false


## Hero injury as the feats use it: Value 0 = no injury, 1 = an injury, 2 = a major injury (the wound count). "Escape Notice" (wounded other hero, not you) is the one feat that
## switches the condition around: you are not injured while another hero is.
func _hero_injured_ok(slot: int, spec: Dictionary, feat: Dictionary) -> bool:
	var level := runtime.wound_count(slot)
	if str(feat["id"]) == "FEAT_CHANCE_16":
		return level == 0
	var wanted := int(spec.get("Value", 0))
	return level == 0 if wanted == 0 else level >= wanted


func _all_uninjured() -> bool:
	return roster.all(func(hero: int) -> bool: return runtime.wound_count(hero) == 0)


func _others_uninjured(slot: int) -> bool:
	return roster.all(func(hero: int) -> bool: return hero == slot or runtime.wound_count(hero) == 0)


## Whether the monster is of the game's enemy family `family`: its figure's family, or - for dragons and animus - a template the campaign lists as such.
func _is_family(monster: RuntimeMonster, family: int) -> bool:
	if int(FAMILY_OF_FOLDER.get(monster.folder, -1)) == family:
		return true
	if family == FAMILY_DRAGON and campaign.dragon_templates.has(monster.base_template_name):
		return true
	if family == FAMILY_ANIMUS and campaign.animus_templates.has(monster.base_template_name):
		return true
	return false


# --- round patterns --------------------------------------------------------------------------------------------------------------

## "N times in one round": the events of this round that passed the feat's filters are collected per hero; the pattern counts once (progress 1) when it is complete.
func _round_pattern(slot: int, feat_key: String, filters: Dictionary, ctx: Dictionary) -> int:
	var key := "%d|%s|%d" % [slot, feat_key, round_number]
	if _pattern_done.has(key):
		return 0
	var events: Array = _qualified.get(key, [])
	events.append({"monster_id": str(ctx.get("monster_id", "")), "weapon_index": int(ctx.get("weapon_index", -1))})
	_qualified[key] = events
	var same_enemy := int(filters["SameEnemy"]["Value"]) if filters.has("SameEnemy") else -1  # 1 = the same enemy, 0 = different enemies, -1 = does not matter
	var complete := false
	if filters.has("AttackWithBothWeapons"):
		for first in events:
			for second in events:
				if int(first["weapon_index"]) == 0 and int(second["weapon_index"]) == 1:
					var same: bool = first["monster_id"] == second["monster_id"]
					if same_enemy == -1 or (same_enemy == 1 and same) or (same_enemy == 0 and not same):
						complete = true
	else:
		var needed := int(filters["AmountOfTimeDuringRound"]["Value"])
		var per_enemy: Dictionary = {}
		for entry in events:
			per_enemy[entry["monster_id"]] = int(per_enemy.get(entry["monster_id"], 0)) + 1
		if same_enemy == 1:
			complete = per_enemy.values().any(func(count): return int(count) >= needed)
		elif same_enemy == 0:
			complete = per_enemy.size() >= needed
		else:
			complete = events.size() >= needed
	if not complete:
		return 0
	_pattern_done[key] = true
	return 1


## "In N consecutive rounds": a round with a qualifying event extends the streak (the same enemy each round when the feat says so); N rounds in a row count once.
func _consecutive_rounds(slot: int, feat_key: String, needed: int, filters: Dictionary, ctx: Dictionary) -> int:
	var key := "%d|%s" % [slot, feat_key]
	var streak: Dictionary = _streaks.get(key, {"round": -10, "count": 0, "monster": ""})
	if int(streak["round"]) == round_number:
		return 0  # this round already counted
	var monster_id := str(ctx.get("monster_id", ""))
	var same_enemy := filters.has("SameEnemy") and int(filters["SameEnemy"]["Value"]) == 1
	if int(streak["round"]) == round_number - 1 and (not same_enemy or streak["monster"] == monster_id):
		streak["count"] = int(streak["count"]) + 1
	else:
		streak["count"] = 1
	streak["round"] = round_number
	streak["monster"] = monster_id
	if int(streak["count"]) >= needed:
		_streaks.erase(key)
		return 1
	_streaks[key] = streak
	return 0
