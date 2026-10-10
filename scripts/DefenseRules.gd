class_name DefenseRules
extends RefCounted

## What the APP does for the game's monster defense abilities (MonsterAbility.game_key). The texts themselves come from the
## user's own export (ItemData) and are always shown to the table; this table only holds the rules the app can carry
## out by itself - everything else (shifts, scars, stress, infect, damage to heroes, anything needing positions) stays
## text. Written from the ability texts; keys are the game's own ids (no game text is stored here).
##
## All rules are skipped while the ability is deactivated (Spiral Bolts, Star Metal Offhand+): callers pass `active`.
##
## Rule keys:
##   immune              Array of MonsterCondition names the monster is immune to
##   immune_all          immune to every condition
##   defense_after       added to the defense until the end of the round after EVERY attack on it (negative = lowers it)
##   defense_other       also given to one random other enemy after every attack
##   damage_permanent    attack damage goes up for good after every attack on it
##   random_stat_after   after every attack one of damage / defense / range / speed (random) is +N until the round ends
##   defense_during_unless_weak   defense +N during an attack when none of the attack's damage types is a weakness
##   no_damage_from      Array of Vulnerability names: attacks with that type deal no damage
##   part_chance         factor on the chance of the weapon's B/C parts (0.5 half as likely, 0 cannot occur)
##   retaliate           targets the last hero who attacked it first
##   once                effects that happen ONCE, the first time the monster is attacked (RuntimeMonster.defense_ability_fired):
##                       defense_permanent N, random_enemy / random_other (who), include_self, damage N (adds to that enemy's
##                       next activation), heal_pct N, afflict

const RULES := {
	"ENEMY_DEFEND_BANDIT_SHADOWALK": {"defense_after": 1},
	"ENEMY_DEFEND_GOLEM": {"immune": ["AFFLICTED"], "defense_after": 1},
	"ENEMY_DEFEND_GOLEM_BARONIAL": {"immune": ["AFFLICTED"], "defense_after": 1, "defense_other": 1},
	"ENEMY_DEFEND_GOLEM_RUNEBOUND": {"immune_all": true, "defense_after": 1},
	"ENEMY_DEFEND_BOSS_ANIMUS": {"immune": ["AFFLICTED"], "once": {"defense_permanent": 1}},
	"ENEMY_DEFEND_DOOMCALLER": {"immune": ["DOOMED"], "random_stat_after": 1},
	"ENEMY_DEFEND_HARBINGER_BARONIAL": {"immune": ["DAZED", "DOOMED"]},
	"ENEMY_DEFEND_NAVOTH": {"immune": ["DAZED", "DOOMED"], "defense_after": 2},
	"ENEMY_DEFEND_VAMPIRE": {"immune": ["ENFEEBLED", "SLOWED"], "defense_after": -1},
	"ENEMY_DEFEND_VAMPIRE_NAMED": {"immune": ["AFFLICTED", "ENFEEBLED", "SLOWED"], "defense_after": -1},
	"ENEMY_DEFEND_BERSERKER": {"damage_permanent": 1},
	"ENEMY_DEFEND_SALAMANDER": {"defense_during_unless_weak": 2},
	"ENEMY_DEFEND_ZEALOT_RUNE": {"immune": ["AFFLICTED"], "no_damage_from": ["SLASH"]},
	"ENEMY_DEFEND_SPECTER": {"part_chance": 0.5},
	"ENEMY_DEFEND_SPECTER_DEATHBORN": {"part_chance": 0.5},
	"ENEMY_DEFEND_SPECTER_RUNEMARKED": {"part_chance": 0.0},
	"ENEMY_DEFEND_BOSS_SPECTER": {"part_chance": 0.5},
	"ENEMY_DEFEND_MERCENARY": {"retaliate": true},
	"ENEMY_DEFEND_ZEALOT": {"once": {"random_enemy": true, "include_self": true, "damage": 2}},
	"ENEMY_DEFEND_ZEALOT_CRIMSON": {"once": {"random_other": true, "heal_pct": 10, "damage": 2}},
	"ENEMY_DEFEND_BOSS_ZEALOT": {"once": {"random_enemy": true, "include_self": true, "afflict": true, "damage": 3}},
}

const RANDOM_STATS: Array[String] = ["damage", "defense", "range", "speed"]


## The rules of the monster's defense abilities that are on the table above.
static func rules_of(monster: RuntimeMonster) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for ability in monster.defense_abilities:
		if RULES.has(ability.game_key):
			found.append(RULES[ability.game_key])
	return found


## True if the monster is immune to condition `kind` through a defense ability.
static func immune_to(monster: RuntimeMonster, kind: int) -> bool:
	for rule in rules_of(monster):
		if rule.get("immune_all", false):
			return true
		for condition_name: String in rule.get("immune", []):
			if MonsterCondition.Kind[condition_name] == kind:
				return true
	return false


## Factor on the chance of the weapon's B/C parts (1.0 = unchanged).
static func part_chance_factor(monster: RuntimeMonster) -> float:
	var factor := 1.0
	for rule in rules_of(monster):
		factor = minf(factor, float(rule.get("part_chance", 1.0)))
	return factor


## Duelist: the monster targets the last hero who attacked it first.
static func retaliates(monster: RuntimeMonster) -> bool:
	for rule in rules_of(monster):
		if rule.get("retaliate", false):
			return true
	return false


## Extra defense during this attack (Hardened Scales): `attack_types` is every damage type of the attack.
static func defense_during(monster: RuntimeMonster, attack_types: Array[int]) -> int:
	var extra := 0
	for rule in rules_of(monster):
		if rule.has("defense_during_unless_weak"):
			var weak := false
			for kind in attack_types:
				if monster.weaknesses.has(kind):
					weak = true
			if not weak:
				extra += int(rule["defense_during_unless_weak"])
	return extra


## True if this attack deals no damage to the monster at all (Scars Upon Scars: slash).
static func blocks_damage(monster: RuntimeMonster, attack_types: Array[int]) -> bool:
	for rule in rules_of(monster):
		for type_name: String in rule.get("no_damage_from", []):
			if attack_types.has(Vulnerability.Kind[type_name]):
				return true
	return false


## What happens right AFTER an attack on `monster` (it may already be defeated and out of `runtime.monsters`). Returns
## the lines for the outcome, e.g. "Resilience: defense +1 until the end of the round".
static func after_attack(runtime: MissionRuntime, monster: RuntimeMonster) -> Array[String]:
	var lines: Array[String] = []
	var alive := runtime.monsters.has(monster)
	for rule in rules_of(monster):
		if alive:
			if rule.has("defense_after"):
				monster.defense_round_bonus += int(rule["defense_after"])
				lines.append("defense %+d until the end of the round (now %d)" % [int(rule["defense_after"]), monster.effective_defense()])
			if rule.has("defense_other"):
				var others := _others(runtime, monster)
				if not others.is_empty():
					var chosen: RuntimeMonster = others.pick_random()
					chosen.defense_round_bonus += int(rule["defense_other"])
					lines.append("%s: defense +%d until the end of the round" % [chosen.display_name(), int(rule["defense_other"])])
			if rule.has("damage_permanent"):
				monster.attack_power += int(rule["damage_permanent"])
				lines.append("damage +%d for good (now %d)" % [int(rule["damage_permanent"]), monster.attack_power])
			if rule.has("random_stat_after"):
				var n := int(rule["random_stat_after"])
				var stat: String = RANDOM_STATS.pick_random()
				match stat:
					"damage":
						monster.damage_round_bonus += n
					"defense":
						monster.defense_round_bonus += n
					"range":
						monster.range_round_bonus += n
					"speed":
						monster.speed_round_bonus += n
				lines.append("%s +%d until the end of the round" % [stat, n])
		if rule.has("once") and not monster.defense_ability_fired:
			monster.defense_ability_fired = true
			lines.append_array(_once(runtime, monster, rule["once"]))
	if not lines.is_empty():
		runtime.monsters_changed.emit()
	return lines


static func _once(runtime: MissionRuntime, monster: RuntimeMonster, once: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if once.has("defense_permanent") and runtime.monsters.has(monster):
		monster.defense += int(once["defense_permanent"])
		lines.append("defense +%d for good (now %d)" % [int(once["defense_permanent"]), monster.defense])
	if once.get("random_enemy", false) or once.get("random_other", false):
		var pool := _others(runtime, monster)
		if once.get("include_self", false) and runtime.monsters.has(monster):
			pool.append(monster)
		if pool.is_empty():
			return lines
		var target: RuntimeMonster = pool.pick_random()
		var parts: Array[String] = []
		if once.has("heal_pct"):
			var amount := maxi(floori(target.max_hitpoints * float(once["heal_pct"]) / 100.0), 1)
			var healed := runtime.heal_monster(target, amount)
			parts.append("recovers %d health" % healed)
		if once.get("afflict", false) and runtime.add_condition(target, MonsterCondition.Kind.AFFLICTED):
			parts.append("becomes afflicted")
		if once.has("damage"):
			target.next_activation_damage += int(once["damage"])
			parts.append("adds %d damage to its next activation" % int(once["damage"]))
		lines.append("%s %s" % [target.display_name(), ", ".join(parts)])
	return lines


static func _others(runtime: MissionRuntime, monster: RuntimeMonster) -> Array[RuntimeMonster]:
	var others: Array[RuntimeMonster] = []
	for other in runtime.monsters:
		if other != monster:
			others.append(other)
	return others
