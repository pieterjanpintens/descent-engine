class_name RuntimeMonster
extends RefCounted

## One spawned monster, registered in MissionRuntime.monsters. Pure runtime
## state (never saved), initialised from the MonsterTemplate the spawn effect
## specified. Position is deliberately NOT tracked - the original game
## doesn't track monster movement either; can be added later.

var id: String = ""
var folder: String = ""  ## MonsterDisplay.REAL_MONSTERS `folder`, e.g. "wolf"
var chip: int = MonsterChip.Chip.YELLOW  ## which colour chip is on its base
var custom_name: String = ""  ## empty = generic type name
## Added around the name (already combined from the monster's own and its
## templates', see MonsterTemplate.resolve()): "Shady " + name + " of the Shadowguild".
var name_prefix: String = ""
var name_postfix: String = ""
var hitpoints: int = 20
var max_hitpoints: int = 20  ## the starting hitpoints, for a health-bar "progress" fraction - hitpoints alone loses this once damage is taken
var level: int = 1
var weaknesses: Array[int] = []  ## Vulnerability.Kind values
var resistances: Array[int] = []
var immunities: Array[int] = []
## Discovered by hitting the monster with a matching damage type (see
## MissionRuntime.resolve_attack()); the combat screen shows "?" until then.
var known_weaknesses: Array[int] = []
var known_resistances: Array[int] = []
var known_immunities: Array[int] = []
var defense: int = 0  ## max of the random 0..defense roll subtracted from each hit
var speed: int = 0  ## how far it can walk (tiles); nothing uses it yet - monsters don't move in the app
## The predefined conditions (MonsterCondition.Kind values) currently affecting
## this monster - applied by heroes during an attack (MissionRuntime.resolve_attack()).
## Scripted, game-applied conditions are not modelled yet.
var conditions: Array[int] = []
## MonsterCondition.Kind values it cannot be affected by (see MonsterTemplate).
var condition_immunities: Array[int] = []
## Attack side (inherited from the MonsterTemplate by MissionRuntime.register_monster()) -
## data only, nothing uses it yet: the damage it deals, its range (0 = melee)/
## reach, custom attack + defense abilities (names for now) and ordered
## preferred-target rules (names for now).
## The hero slot that most recently attacked this monster (-1 = none yet) - what the
## Retaliate target rule follows.
var last_attacker: int = -1
var attack_power: int = 3
var attack_range: int = 0
var attack_reach: bool = false
var attack_abilities: Array[MonsterAbility] = []
var defense_abilities: Array[MonsterAbility] = []
var target_rules: Array[TargetRule] = []
## Labels from its templates ("Large", "Uthuk", ...) that weapon part abilities ask about, see MonsterArchetype.tags.
var tags: Array[String] = []
## Defense taken off until the end of this round by weapon part abilities (cleared when the monster phase ends,
## MissionRuntime.end_monster_phase_conditions()); permanent reductions change `defense` itself.
var defense_round_penalty: int = 0
## Attacked by a hero earlier this round (Eastrider Guard); cleared when the monster phase ends.
var attacked_this_round: bool = false
## Spiral Bolts: 0 = the defense ability works, 1 = deactivated for the next attack, 2 = deactivated until the round ends.
var defense_ability_off: int = 0
## Defense ability effects (DefenseRules): signed bonuses until the monster phase ends, and what carries on.
var defense_round_bonus: int = 0
var damage_round_bonus: int = 0
var range_round_bonus: int = 0
var speed_round_bonus: int = 0
## Damage added to this monster's NEXT activation (Martyr / Sacrifice); used up by that activation.
var next_activation_damage: int = 0
## A once-only defense ability effect (Martyr, Sacrifice, Voltaic Guard) has already happened.
var defense_ability_fired: bool = false
## Hero slots this monster is less likely to target until the end of the round (Shadowstone Bracers).
var shadowed_heroes: Array[int] = []
## What it does when Confused instead of attacking (empty = MonsterAction.defaults()).
var confused_actions: Array[MonsterAction] = []
## What it drops (LootItem list from its templates); nothing hands it out yet.
var loot: Array[LootItem] = []
## Shown to the table when this monster is defeated (from its base template).
var defeat_text: String = ""


## The defense as it is NOW: `defense` minus this round's reduction, never below 0.
func effective_defense() -> int:
	return maxi(defense + defense_round_bonus - defense_round_penalty, 0)


## True if it carries `tag` (ignoring case).
## "Dragonkind" also matches a "Dragon" (a dragon is dragonkind); "Dragon" matches only a dragon.
func has_tag(tag: String) -> bool:
	var wanted := tag.to_lower()
	for existing in tags:
		var held := existing.to_lower()
		if held == wanted or (wanted == "dragonkind" and held == "dragon"):
			return true
	return false


## Attack damage as it is NOW: an Enfeebled monster deals ENFEEBLED_DAMAGE_PERCENT% less,
## the reduction rounded up (3 -> 2, 10 -> 8).
func effective_attack_power() -> int:
	var total := attack_power + damage_round_bonus + next_activation_damage
	if conditions.has(MonsterCondition.Kind.ENFEEBLED):
		return maxi(total - ceili(total * MonsterCondition.ENFEEBLED_DAMAGE_PERCENT / 100.0), 0)
	return total


## Attack range as it is NOW (a defense ability can add to it until the round ends).
func effective_attack_range() -> int:
	return attack_range + range_round_bonus


## Speed as it is NOW: a Slowed monster's speed is SET to MonsterCondition.SLOWED_SPEED.
func effective_speed() -> int:
	if conditions.has(MonsterCondition.Kind.SLOWED):
		return MonsterCondition.SLOWED_SPEED + speed_round_bonus
	return speed + speed_round_bonus


## True if the monster cannot get condition `kind`: its own immunities, or one its defense ability gives. `ability_on`:
## -1 = as the ability is now, 0 = deactivated, 1 = working (an attack that is being resolved knows better).
func is_condition_immune(kind: int, ability_on: int = -1) -> bool:
	if condition_immunities.has(kind):
		return true
	var on := defense_ability_off == 0 if ability_on < 0 else ability_on == 1
	return on and DefenseRules.immune_to(self, kind)


## Every condition the monster is immune to right now (for the combat view's conditions dialog).
func all_condition_immunities() -> Array[int]:
	var result: Array[int] = []
	for kind in MonsterCondition.all():
		if is_condition_immune(kind):
			result.append(kind)
	return result


## The custom name if one was set, else the type's generic name ("Bandit").
## True if one of its attack abilities has `behavior` (MonsterAbility.Behavior).
func has_attack_behavior(behavior: int) -> bool:
	for ability in attack_abilities:
		if ability.behavior == behavior:
			return true
	return false


func display_name() -> String:
	var base: String = custom_name if custom_name != "" else str(MonsterDisplay.find_monster(folder).get("name", folder))
	return name_prefix + base + name_postfix


## What the table is told about this monster's defense abilities when it is attacked: the game's text of every ability
## with one (`after` picks the ones shown after the attack roll). "" when none, or nothing for the moment.
func defense_ability_text(after: bool) -> String:
	var lines: Array[String] = []
	for ability in defense_abilities:
		if ability.game_key != "" and ability.shows_after_attack() == after:
			lines.append(ability.shown_text())
	return "\n".join(lines)


## Plain-data round trip for SaveGame - this class is RefCounted, not a
## Resource, so it can't be embedded directly in a Resource's exported
## field; a save just carries a Dictionary of these fields instead.
func to_dict() -> Dictionary:
	return {
		"id": id, "folder": folder, "chip": chip, "custom_name": custom_name, "name_prefix": name_prefix, "name_postfix": name_postfix,
		"hitpoints": hitpoints, "max_hitpoints": max_hitpoints, "level": level, "defense": defense, "speed": speed,
		"weaknesses": weaknesses.duplicate(), "resistances": resistances.duplicate(), "immunities": immunities.duplicate(),
		"known_weaknesses": known_weaknesses.duplicate(), "known_resistances": known_resistances.duplicate(), "known_immunities": known_immunities.duplicate(),
		"conditions": conditions.duplicate(), "condition_immunities": condition_immunities.duplicate(),
		"last_attacker": last_attacker, "tags": tags.duplicate(), "defense_round_penalty": defense_round_penalty,
		"attacked_this_round": attacked_this_round, "defense_ability_off": defense_ability_off,
		"defense_round_bonus": defense_round_bonus, "damage_round_bonus": damage_round_bonus, "range_round_bonus": range_round_bonus,
		"speed_round_bonus": speed_round_bonus, "next_activation_damage": next_activation_damage, "defense_ability_fired": defense_ability_fired, "shadowed_heroes": shadowed_heroes.duplicate(),
		"attack_power": attack_power, "attack_range": attack_range, "attack_reach": attack_reach,
		"attack_abilities": _to_dicts(attack_abilities), "defense_abilities": _to_dicts(defense_abilities),
		"target_rules": _to_dicts(target_rules), "confused_actions": _to_dicts(confused_actions), "loot": _to_dicts(loot), "defeat_text": defeat_text,
	}


static func from_dict(d: Dictionary) -> RuntimeMonster:
	var m := RuntimeMonster.new()
	m.id = d.get("id", "")
	m.folder = d.get("folder", "")
	m.chip = d.get("chip", MonsterChip.Chip.YELLOW)
	m.custom_name = d.get("custom_name", "")
	m.name_prefix = d.get("name_prefix", "")
	m.name_postfix = d.get("name_postfix", "")
	m.hitpoints = d.get("hitpoints", 20)
	# Older saves have no max_hitpoints - fall back to current hitpoints
	# (better than a flat 20, which would be wrong for anything already
	# damaged or with a non-default template hitpoints at save time).
	m.max_hitpoints = d.get("max_hitpoints", m.hitpoints)
	m.level = d.get("level", 1)
	m.defense = d.get("defense", 0)
	m.speed = d.get("speed", 0)
	m.weaknesses = _int_array(d.get("weaknesses", []))
	m.resistances = _int_array(d.get("resistances", []))
	m.immunities = _int_array(d.get("immunities", []))
	m.known_weaknesses = _int_array(d.get("known_weaknesses", []))
	m.known_resistances = _int_array(d.get("known_resistances", []))
	m.known_immunities = _int_array(d.get("known_immunities", []))
	m.conditions = _int_array(d.get("conditions", []))
	m.last_attacker = d.get("last_attacker", -1)
	for tag in d.get("tags", []):
		m.tags.append(str(tag))
	m.defense_round_penalty = d.get("defense_round_penalty", 0)
	m.attacked_this_round = d.get("attacked_this_round", false)
	m.defense_ability_off = d.get("defense_ability_off", 0)
	m.defense_round_bonus = d.get("defense_round_bonus", 0)
	m.damage_round_bonus = d.get("damage_round_bonus", 0)
	m.range_round_bonus = d.get("range_round_bonus", 0)
	m.speed_round_bonus = d.get("speed_round_bonus", 0)
	m.next_activation_damage = d.get("next_activation_damage", 0)
	m.defense_ability_fired = d.get("defense_ability_fired", false)
	m.shadowed_heroes = _int_array(d.get("shadowed_heroes", []))
	m.condition_immunities = _int_array(d.get("condition_immunities", []))
	m.attack_power = d.get("attack_power", 3)
	m.attack_range = d.get("attack_range", 0)
	m.attack_reach = d.get("attack_reach", false)
	for entry in d.get("attack_abilities", []):
		m.attack_abilities.append(MonsterAbility.from_dict(entry))
	for entry in d.get("defense_abilities", []):
		m.defense_abilities.append(MonsterAbility.from_dict(entry))
	for entry in d.get("target_rules", []):
		m.target_rules.append(TargetRule.from_dict(entry))
	for entry in d.get("confused_actions", []):
		m.confused_actions.append(MonsterAction.from_dict(entry))
	for entry in d.get("loot", []):
		m.loot.append(LootItem.from_dict(entry))
	m.defeat_text = str(d.get("defeat_text", ""))
	return m


## `to_dict()` of every Resource in `list` (MonsterAbility/TargetRule).
static func _to_dicts(list: Array) -> Array:
	var result: Array = []
	for item in list:
		result.append(item.to_dict())
	return result


## A save's Dictionary values come back from disk as plain untyped Arrays -
## copy element-by-element into a real Array[int] rather than relying on
## implicit conversion.
static func _int_array(values: Array) -> Array[int]:
	var result: Array[int] = []
	for v in values:
		result.append(int(v))
	return result
