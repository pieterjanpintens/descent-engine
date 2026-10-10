class_name PartEffectRunner
extends RefCounted

## What the weapon parts B and C do to an attack. The table has already entered what part A did (the successes it rolled
## and the conditions it applied - nothing of A is calculated here); then, per attack:
##   1. plan(): each equipped part rolls its chance (the game's own `Chance` of the ability, +10 points against a Dazed
##      monster - MonsterCondition.DAZED_ATTACHMENT_BONUS_PERCENT; a part flagged `always_if_weak` always triggers when
##      the monster is weak to the attack) and the triggered ones apply their effects that change the attack: extra
##      conditions, damage types, weapon damage, successes, weakness bonus, defense, new weaknesses. Questions about
##      the hero (an injury, fatigue) and choices of another monster are asked here.
##   2. MissionRuntime.resolve_attack() works the damage out with Plan.modifiers().
##   3. finish(): the effects that come after the damage (direct damage, permanent reductions, spreading statuses...).
##   4. The caller shows Plan.lines (what the app did) and Plan.notes (the full ability text of every triggered part:
##      what the app cannot do - heroes' cards, positions, loot... - the table does).
## What each part does is written in data/weapon_part_effects.json (keyed by the base part id; "upgraded_effects" for
## the "+" side when it differs); a part with no entry only shows its text. Parts later in the list see the monster
## as the earlier ones left it (conditions, damage types). A "copy_other" effect repeats the effects of the weapon's
## other part (B copies C and C copies B) without rolling its chance.

const SPEC_PATH := "res://data/weapon_part_effects.json"
const UPGRADED_SUFFIX := "_UPGRADED"

static var _spec: Dictionary = {}
static var _spec_loaded := false

var runtime: MissionRuntime
var dialog: PlayerDialog
var hero_name: String = ""


class Plan:
	extends RefCounted
	var monster: RuntimeMonster
	var attack_types: Array[int] = []  ## the weapon's damage types plus the ones parts added
	var state_conditions: Array[int] = []  ## the monster's conditions as the parts so far leave them
	var extra_types: Array[int] = []
	var damage_delta := 0
	var damage_double := false
	var extra_successes := 0
	var weakness_bonus_extra := 0
	var ignore_defense := false
	var conditions: Array[int] = []  ## conditions the parts add to the target (applied by resolve_attack())
	var post: Array[Dictionary] = []
	var lines: Array[String] = []  ## what the app did, one line per part
	var notes: Array[String] = []  ## the ability text of every triggered part
	var not_triggered: Array[String] = []

	func modifiers() -> Dictionary:
		return {
			"extra_types": extra_types, "damage_delta": damage_delta, "damage_double": damage_double,
			"extra_successes": extra_successes, "weakness_bonus_extra": weakness_bonus_extra, "ignore_defense": ignore_defense,
		}


# ---------------------------------------------------------------- planning (before the damage)

func plan(weapon: Weapon, monster: RuntimeMonster, a_conditions: Array) -> Plan:
	var p := Plan.new()
	p.monster = monster
	p.attack_types = weapon.damage_types.duplicate()
	p.state_conditions = monster.conditions.duplicate()
	for condition in a_conditions:
		if not monster.condition_immunities.has(condition) and not p.state_conditions.has(condition):
			p.state_conditions.append(condition)
	var parts: Array[WeaponAttachment] = weapon.attachments.duplicate()
	parts.sort_custom(func(a: WeaponAttachment, b: WeaponAttachment) -> bool: return a.part_slot < b.part_slot)
	for part in parts:
		var spec := _spec_for(part)
		var chance := part.chance + (MonsterCondition.DAZED_ATTACHMENT_BONUS_PERCENT / 100.0 if p.state_conditions.has(MonsterCondition.Kind.DAZED) else 0.0)
		var forced: bool = spec["always_if_weak"] and _weak_to_attack(p)
		if not forced and randf() >= chance:
			p.not_triggered.append(part.attachment_name)
			continue
		var base_id := _base_id(part.part_id)
		runtime.part_trigger_counts[base_id] = int(runtime.part_trigger_counts.get(base_id, 0)) + 1
		var applied: Array[String] = []
		await _apply(spec["effects"], part, parts, p, applied, 0)
		p.lines.append("%s: %s" % [part.attachment_name, ", ".join(applied)] if not applied.is_empty() else "%s triggered" % part.attachment_name)
		if part.ability_text != "":
			p.notes.append("%s: %s" % [part.attachment_name, part.ability_text])
	return p


func _apply(effects: Array, part: WeaponAttachment, parts: Array[WeaponAttachment], p: Plan, applied: Array[String], depth: int) -> void:
	for e: Dictionary in effects:
		if e.has("to") and not await _holds(e["to"], part, p):
			continue
		match str(e["type"]):
			"conditions":
				for kind_name: String in e["kinds"]:
					_add_condition(p, MonsterCondition.Kind[kind_name], applied)
			"conditions_all":
				var tag := str(e.get("tag", ""))
				if tag == "" or p.monster.has_tag(tag):
					for kind_name: String in e["kinds"]:
						_add_condition(p, MonsterCondition.Kind[kind_name], applied)
				p.post.append({"type": "conditions_others", "kinds": e["kinds"], "tag": tag, "part": part.attachment_name})
			"random_status":
				if e.get("only_if_none", false) and not p.state_conditions.is_empty():
					continue
				for i in int(e["count"]):
					var candidates: Array[int] = []
					for kind in MonsterCondition.all():
						if not p.state_conditions.has(kind) and not p.monster.condition_immunities.has(kind):
							candidates.append(kind)
					if candidates.is_empty():
						break
					_add_condition(p, candidates.pick_random(), applied)
			"damage_types":
				for kind_name: String in e["kinds"]:
					var kind: int = Vulnerability.Kind[kind_name]
					if not p.attack_types.has(kind):
						p.attack_types.append(kind)
						p.extra_types.append(kind)
						applied.append("attack gains %s" % Vulnerability.display_name(kind))
			"damage":
				await _apply_damage(e, part, p, applied)
			"successes":
				var n := 0
				if e.has("per_stronger_enemy"):
					for other in runtime.monsters:
						if other != p.monster and other.hitpoints > p.monster.hitpoints:
							n += int(e["per_stronger_enemy"])
				else:
					n = int(e["n"])
				if n > 0:
					p.extra_successes += n
					applied.append("+%d success%s" % [n, "" if n == 1 else "es"])
			"weakness_bonus":
				p.weakness_bonus_extra += int(e["n"])
				applied.append("weakness damage +%d" % int(e["n"]))
			"ignore_defense":
				p.ignore_defense = true
				applied.append("ignores defense")
			"defense_round":
				p.monster.defense_round_penalty += int(e["n"])
				applied.append("defense -%d this round" % int(e["n"]))
			"become_weak":
				_become_weak(e, p, applied)
			"max_health_to_current":
				p.monster.max_hitpoints = p.monster.hitpoints
				applied.append("max health = current health")
			"affliction_bonus":
				runtime.affliction_bonus_round += int(e["n"])
				applied.append("affliction damage +%d this round" % int(e["n"]))
			"copy_other":
				if depth >= 1:
					continue
				var other: WeaponAttachment = null
				for candidate in parts:
					if candidate != part:
						other = candidate
				if other == null:
					applied.append("no other part to copy")
					continue
				applied.append("copies %s" % other.attachment_name)
				if other.ability_text != "":
					p.notes.append("%s (copied by %s): %s" % [other.attachment_name, part.attachment_name, other.ability_text])
				await _apply(_spec_for(other)["effects"], other, parts, p, applied, depth + 1)
			"direct_ask":
				await _before_ask()
				var amount := await dialog.ask_count("%s - %s\nHow much fatigue is on all of %s's cards?" % [hero_name, part.attachment_name, hero_name], 0, 99)
				p.post.append({"type": "direct_ask", "amount": amount, "part": part.attachment_name})
			"same_damage_other":
				var chosen := await _choose_other(part, p)
				p.post.append({"type": "same_damage_other", "chosen": chosen, "then": e.get("then", []), "part": part.attachment_name})
			_:
				# conditions_after, perm, reveal_weakness, direct, execute_below, strip_statuses, spread_status, counter
				var queued := e.duplicate()
				queued["part"] = part.attachment_name
				queued["base_id"] = _base_id(part.part_id)
				p.post.append(queued)


func _apply_damage(e: Dictionary, part: WeaponAttachment, p: Plan, applied: Array[String]) -> void:
	var n := 0
	if e.has("flat"):
		n = int(e["flat"])
	elif e.has("per_status"):
		n = int(e["per_status"]) * p.state_conditions.size()
	elif e.has("range"):
		n = randi_range(int(e["range"][0]), int(e["range"][1]))
	elif e.get("double", false):
		p.damage_double = true
		applied.append("weapon damage doubled")
		return
	elif e.get("ask_injury", false):
		await _before_ask()
		var level := await dialog.ask_choice("%s - %s\nDoes %s have an injury?" % [hero_name, part.attachment_name, hero_name], ["No injury", "A minor injury", "A major injury"], [], false)
		n = 1 + maxi(level, 0)
	if n > 0:
		p.damage_delta += n
		applied.append("weapon damage +%d" % n)


## An "if" of an effect: `tag`, `already` (a condition the monster has before this effect), `weak_to_attack`, or an
## `ask` the table answers about its hero.
func _holds(cond: Dictionary, part: WeaponAttachment, p: Plan) -> bool:
	if cond.has("tag"):
		return p.monster.has_tag(str(cond["tag"]))
	if cond.has("already"):
		return p.state_conditions.has(MonsterCondition.Kind[str(cond["already"])])
	if cond.get("weak_to_attack", false):
		return _weak_to_attack(p)
	if cond.has("ask"):
		await _before_ask()
		return await dialog.ask_yes_no("%s - %s\nDoes %s have an injury?" % [hero_name, part.attachment_name, hero_name])
	return false


func _weak_to_attack(p: Plan) -> bool:
	for kind in p.attack_types:
		if p.monster.weaknesses.has(kind):
			return true
	return false


## Adds `kind` to the conditions the target gets: nothing if it is immune (said so) or already has it.
func _add_condition(p: Plan, kind: int, applied: Array[String]) -> void:
	if p.monster.condition_immunities.has(kind):
		applied.append("immune to %s" % MonsterCondition.display_name(kind))
	elif not p.state_conditions.has(kind):
		p.state_conditions.append(kind)
		p.conditions.append(kind)
		applied.append(MonsterCondition.display_name(kind))


func _become_weak(e: Dictionary, p: Plan, applied: Array[String]) -> void:
	var kinds: Array[int] = []
	if typeof(e["kinds"]) == TYPE_STRING:
		if e["kinds"] == "attack_types":
			kinds = p.attack_types.duplicate()
		elif e["kinds"] == "random_attack_type" and not p.attack_types.is_empty():
			kinds.append(p.attack_types.pick_random())
	else:
		for kind_name: String in e["kinds"]:
			kinds.append(Vulnerability.Kind[kind_name])
	for kind in kinds:
		if not p.monster.weaknesses.has(kind):
			p.monster.weaknesses.append(kind)
			applied.append("weak to %s" % Vulnerability.display_name(kind))
		if not p.monster.known_weaknesses.has(kind):
			p.monster.known_weaknesses.append(kind)  # the ability text tells the table


func _choose_other(part: WeaponAttachment, p: Plan) -> RuntimeMonster:
	var others: Array[RuntimeMonster] = []
	var labels: Array[String] = []
	for other in runtime.monsters:
		if other != p.monster:
			others.append(other)
			labels.append("%s (%s chip)" % [other.display_name(), MonsterChip.display_name(other.chip)])
	if others.is_empty():
		return null
	await _before_ask()
	var picked := await dialog.ask_choice("%s - %s\nWhich other enemy suffers the same damage? (Cancel: none)" % [hero_name, part.attachment_name], labels)
	return others[picked] if picked >= 0 else null


## The combat view stays open under the successes screen; a question needs the normal dialog box.
func _before_ask() -> void:
	dialog.pause_combat_view()


# ---------------------------------------------------------------- finishing (after the damage)

## Runs the effects that come after the damage. `r` is the MissionRuntime.resolve_attack() result: its hitpoints /
## defeated entries are brought up to date and the lines are added to `plan.lines`.
func finish(p: Plan, r: Dictionary) -> void:
	var target := p.monster
	for e: Dictionary in p.post:
		var part_name := str(e["part"])
		var said := ""
		match str(e["type"]):
			"conditions_after":
				if _alive(target):
					said = _add_to_monster(target, e["kinds"])
			"conditions_others":
				var added: Array[String] = []
				for other in runtime.monsters.duplicate():
					if other == target or (str(e["tag"]) != "" and not other.has_tag(str(e["tag"]))):
						continue
					if _add_to_monster(other, e["kinds"]) != "":
						added.append(other.display_name())
				if not added.is_empty():
					said = "%s: %s" % [", ".join(_kind_names(e["kinds"])), ", ".join(added)]
			"perm":
				if _alive(target):
					target.attack_power = maxi(target.attack_power - int(e["damage"]), 0)
					target.defense = maxi(target.defense - int(e["defense"]), 0)
					var parts: Array[String] = []
					if int(e["damage"]) > 0:
						parts.append("damage -%d" % int(e["damage"]))
					if int(e["defense"]) > 0:
						parts.append("defense -%d" % int(e["defense"]))
					said = "permanently %s" % " and ".join(parts)
					runtime.monsters_changed.emit()
			"reveal_weakness":
				var hidden: Array[int] = []
				for kind in target.weaknesses:
					if not target.known_weaknesses.has(kind):
						hidden.append(kind)
				if hidden.is_empty():
					said = "no weakness left to reveal"
				else:
					var revealed: int = hidden.pick_random()
					target.known_weaknesses.append(revealed)
					said = "reveals weakness to %s" % Vulnerability.display_name(revealed)
			"direct":
				var amount: int = int(r["successes"]) if str(e["amount"]) == "successes" else int(e["amount"])
				var hit: Array[String] = []
				for other in runtime.monsters.duplicate():
					var wanted: bool = (str(e["who"]) == "others" and other != target) or (str(e["who"]) == "exposed" and other.conditions.has(MonsterCondition.Kind.EXPOSED))
					if wanted:
						runtime.damage_monster(other, amount)
						hit.append(other.display_name())
				said = "%d damage to %s" % [amount, ", ".join(hit)] if not hit.is_empty() else "no enemy to damage"
			"direct_ask":
				if _alive(target):
					runtime.damage_monster(target, int(e["amount"]))
					said = "%d damage to the enemy" % int(e["amount"])
			"execute_below":
				if _alive(target) and target.hitpoints < int(e["hp"]):
					runtime.damage_monster(target, target.hitpoints)
					said = "the enemy had less than %d health: defeated" % int(e["hp"])
			"strip_statuses":
				if _alive(target):
					var lost := target.conditions.size()
					target.conditions.clear()
					if lost > 0:
						runtime.damage_monster(target, lost * int(e["damage_per"]))
					said = "lost %d status%s, %d damage" % [lost, "" if lost == 1 else "es", lost * int(e["damage_per"])]
			"spread_status":
				if _alive(target) and not target.conditions.is_empty():
					var others: Array[RuntimeMonster] = []
					for other in runtime.monsters:
						if other != target:
							others.append(other)
					if not others.is_empty():
						var receiver: RuntimeMonster = others.pick_random()
						var given: Array[int] = []
						if e.get("all", false):
							given.append_array(target.conditions)
						else:
							given.append(target.conditions.pick_random())
						var given_names: Array[String] = []
						for kind in given:
							if runtime.add_condition(receiver, kind):
								given_names.append(MonsterCondition.display_name(kind))
						said = "%s gains %s" % [receiver.display_name(), ", ".join(given_names)] if not given_names.is_empty() else "%s is immune" % receiver.display_name()
			"same_damage_other":
				var chosen: RuntimeMonster = e["chosen"]
				if chosen != null and _alive(chosen):
					runtime.damage_monster(chosen, int(r["dealt"]))
					said = "%s suffers %d damage" % [chosen.display_name(), int(r["dealt"])]
					if _alive(chosen) and not e["then"].is_empty():
						said += ", " + _add_to_monster(chosen, e["then"]).to_lower()
			"counter":
				var count := int(runtime.part_trigger_counts.get(str(e["base_id"]), 0))
				if int(e["every"]) > 0 and count % int(e["every"]) == 0:
					for other in runtime.monsters.duplicate():
						runtime.damage_monster(other, int(e["damage_all"]))
					said = "trigger %d: %d damage to every enemy" % [count, int(e["damage_all"])]
				else:
					said = "trigger %d (every %dth: %d damage to every enemy)" % [count, int(e["every"]), int(e["damage_all"])]
		if said != "":
			p.lines.append("%s: %s" % [part_name, said])
	r["hitpoints"] = target.hitpoints
	r["defeated"] = target.hitpoints <= 0
	r["part_lines"] = p.lines
	r["part_notes"] = p.notes
	r["parts_not_triggered"] = p.not_triggered
	r["attack_types"] = p.attack_types


func _alive(monster: RuntimeMonster) -> bool:
	return runtime.monsters.has(monster)


## Adds the named conditions to `monster` (the ones it isn't immune to and doesn't have): the names of those added
## ("Dazed, Exposed"), "" if none.
func _add_to_monster(monster: RuntimeMonster, kind_names: Array) -> String:
	var added: Array[String] = []
	for kind_name: String in kind_names:
		var kind: int = MonsterCondition.Kind[kind_name]
		if runtime.add_condition(monster, kind):
			added.append(MonsterCondition.display_name(kind))
	return ", ".join(added)


func _kind_names(kind_names: Array) -> Array[String]:
	var names: Array[String] = []
	for kind_name: String in kind_names:
		names.append(MonsterCondition.display_name(MonsterCondition.Kind[kind_name]))
	return names


# ---------------------------------------------------------------- the data

static func _base_id(part_id: String) -> String:
	return part_id.trim_suffix(UPGRADED_SUFFIX)


## {"effects": [...], "always_if_weak": bool} of a part - the "+" side uses `upgraded_effects` when the entry has them;
## no entry = no effects (the part only shows its text).
static func _spec_for(part: WeaponAttachment) -> Dictionary:
	if not _spec_loaded:
		_spec_loaded = true
		if FileAccess.file_exists(SPEC_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(SPEC_PATH))
			if parsed is Dictionary:
				_spec = parsed
	var entry: Dictionary = _spec.get(_base_id(part.part_id), {})
	var effects: Array = entry.get("effects", [])
	if part.part_id.ends_with(UPGRADED_SUFFIX) and entry.has("upgraded_effects"):
		effects = entry["upgraded_effects"]
	return {"effects": effects, "always_if_weak": entry.get("always_if_weak", false)}
