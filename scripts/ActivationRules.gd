class_name ActivationRules
extends RefCounted

## What the APP does by itself for the game's activation abilities (MonsterAbility.game_key of an attack ability; the
## texts stay in the user's export). Everything else is text for the table. Applied once at the start of the monster's
## activation (MissionPlayer._monster_attack()).
##
##   heal_per_level        recovers N x the monster's level health (Mend; the number is the user's choice, the game text has none)
##   heal_pct_per_level    recovers (N x level) percent of its maximum health, rounded down, at least 1 (Undeath)
##   clear_statuses        all its conditions are removed (Stitched)
##   damage_permanent      its attack damage goes up for good (Furious Sentinel)
##   second_attack         after the attack it may attack a second hero (Bloodlust) - the table says if one is possible

const RULES := {
	"ENEMY_ACTIVATION_ZEALOT_BASIC": {"heal_per_level": 3},
	"ENEMY_ACTIVATION_ZEALOT_DREAD_BASIC": {"heal_per_level": 3, "clear_statuses": true},
	"ENEMY_ACTIVATION_WIGHT_BASIC_2": {"heal_pct_per_level": 5},
	"ENEMY_ACTIVATION_GOLEM_RAGESTONE_1": {"damage_permanent": 1},
	"ENEMY_ACTIVATION_BERSERKER_BASIC": {"second_attack": true},
}


static func rules_of(monster: RuntimeMonster) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for ability in monster.attack_abilities:
		if RULES.has(ability.game_key):
			found.append(RULES[ability.game_key])
	return found


## True if one of its abilities lets it attack a second hero (Bloodlust).
static func has_second_attack(monster: RuntimeMonster) -> bool:
	for rule in rules_of(monster):
		if rule.get("second_attack", false):
			return true
	return false


## Applies the start-of-activation rules; returns the lines to tell the table ("recovers 12 health (now 30 / 40)").
static func start_of_activation(runtime: MissionRuntime, monster: RuntimeMonster) -> Array[String]:
	var lines: Array[String] = []
	for rule in rules_of(monster):
		if rule.has("heal_per_level") or rule.has("heal_pct_per_level"):
			var amount := 0
			if rule.has("heal_per_level"):
				amount = int(rule["heal_per_level"]) * monster.level
			else:
				amount = maxi(floori(monster.max_hitpoints * int(rule["heal_pct_per_level"]) * monster.level / 100.0), 1)
			var healed := runtime.heal_monster(monster, amount)
			lines.append(TranslationServer.translate("recovers %d health (now %d / %d)") % [healed, monster.hitpoints, monster.max_hitpoints])
		if rule.get("clear_statuses", false) and not monster.conditions.is_empty():
			monster.conditions.clear()
			runtime.monsters_changed.emit()
			lines.append(TranslationServer.translate("all its statuses are removed"))
		if rule.has("damage_permanent"):
			monster.attack_power += int(rule["damage_permanent"])
			runtime.monsters_changed.emit()
			lines.append(TranslationServer.translate("damage +%d for good (now %d)") % [int(rule["damage_permanent"]), monster.attack_power])
	return lines
