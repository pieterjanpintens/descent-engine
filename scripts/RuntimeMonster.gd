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
var attack_power: int = 3
var attack_range: int = 0
var attack_reach: bool = false
var attack_abilities: Array[MonsterAbility] = []
var defense_abilities: Array[MonsterAbility] = []
var target_rules: Array[TargetRule] = []


## The custom name if one was set, else the type's generic name ("Bandit").
func display_name() -> String:
	var base: String = custom_name if custom_name != "" else str(MonsterDisplay.find_monster(folder).get("name", folder))
	return name_prefix + base + name_postfix


## Plain-data round trip for SaveGame - this class is RefCounted, not a
## Resource, so it can't be embedded directly in a Resource's exported
## field; a save just carries a Dictionary of these fields instead.
func to_dict() -> Dictionary:
	return {
		"id": id, "folder": folder, "chip": chip, "custom_name": custom_name, "name_prefix": name_prefix, "name_postfix": name_postfix,
		"hitpoints": hitpoints, "max_hitpoints": max_hitpoints, "level": level, "defense": defense,
		"weaknesses": weaknesses.duplicate(), "resistances": resistances.duplicate(), "immunities": immunities.duplicate(),
		"known_weaknesses": known_weaknesses.duplicate(), "known_resistances": known_resistances.duplicate(), "known_immunities": known_immunities.duplicate(),
		"conditions": conditions.duplicate(), "condition_immunities": condition_immunities.duplicate(),
		"attack_power": attack_power, "attack_range": attack_range, "attack_reach": attack_reach,
		"attack_abilities": _to_dicts(attack_abilities), "defense_abilities": _to_dicts(defense_abilities),
		"target_rules": _to_dicts(target_rules),
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
	m.weaknesses = _int_array(d.get("weaknesses", []))
	m.resistances = _int_array(d.get("resistances", []))
	m.immunities = _int_array(d.get("immunities", []))
	m.known_weaknesses = _int_array(d.get("known_weaknesses", []))
	m.known_resistances = _int_array(d.get("known_resistances", []))
	m.known_immunities = _int_array(d.get("known_immunities", []))
	m.conditions = _int_array(d.get("conditions", []))
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
