class_name MonsterArchetype
extends Resource

## A reusable "monster template" (UI name; the class is called MonsterArchetype
## because MonsterTemplate already means ONE monster a spawn effect creates):
## a bundle of pinned traits that can be attached to any number of spawned
## monsters, in any mission - e.g. "Shadowguild" = prefix "Shady ", postfix " of
## the Shadowguild", resistant to Pierce, immune to Confused, an extra attack
## ability, and an attack/defense that grows with the monster's level.
##
## Stored in the shared library (MonsterArchetypeLibrary, user data, edited with
## MonsterTemplateEditor) so it can be reused across missions; when it is
## attached to a monster (MonsterTemplate.archetypes) the mission gets its own
## embedded COPY, so a mission file stays self-contained.
##
## Two KINDS (`kind`): a BASE template defines what a monster is - every monster
## needs exactly one (MonsterTemplate.base_archetype): its level-scaled stats,
## attack range/reach, abilities, target rules. ADDITIVE templates
## (MonsterTemplate.archetypes, any number) add to it: name affixes, extra
## weaknesses/resistances/immunities/condition immunities, and level-scaled values
## ADDED to the base's hitpoints/attack/defense (may be negative). The range/reach/
## abilities/target rules of an additive template are ignored (for now). See
## MonsterTemplate.resolve().
enum Kind { BASE, ADDITIVE }

@export var kind: Kind = Kind.BASE

@export var template_name: String = ""
## Added in front of / behind the monster's name, verbatim - include the spaces
## yourself ("Shady " + "John" + " of the Shadowguild").
@export var name_prefix: String = ""
@export var name_postfix: String = ""
## Vulnerability.Kind lists (merged into the monster's own).
@export var weaknesses: Array[int] = []
@export var resistances: Array[int] = []
@export var immunities: Array[int] = []
## MonsterCondition.Kind values the monster cannot be affected by.
@export var condition_immunities: Array[int] = []
@export var attack_abilities: Array[MonsterAbility] = []
@export var defense_abilities: Array[MonsterAbility] = []
## Level scaling tables (rows of "level min..max -> value", see LevelValue): for a
## BASE template the value for the monster's level IS the stat (a level outside every
## row uses the closest row); for an ADDITIVE template it is ADDED to the base's (an
## empty table adds nothing).
@export var attack_scaling: Array[LevelValue] = []
@export var defense_scaling: Array[LevelValue] = []
@export var hitpoints_scaling: Array[LevelValue] = []
## BASE templates only: how the monster attacks (range as Weapon.weapon_range, 0 =
## melee; reach) and its ordered preferred-target rules.
@export_range(0, 99) var attack_range: int = 0
@export var attack_reach: bool = false
@export var target_rules: Array[TargetRule] = []


## A fully independent copy (no resource paths anywhere) - used both when
## attaching to a monster (so the mission embeds it instead of referencing the
## library file) and by the editor's working copy.
func deep_copy() -> MonsterArchetype:
	var copy := MonsterArchetype.new()
	copy.template_name = template_name
	copy.kind = kind
	copy.attack_range = attack_range
	copy.attack_reach = attack_reach
	copy.target_rules = TargetRule.copies(target_rules)
	copy.name_prefix = name_prefix
	copy.name_postfix = name_postfix
	copy.weaknesses = weaknesses.duplicate()
	copy.resistances = resistances.duplicate()
	copy.immunities = immunities.duplicate()
	copy.condition_immunities = condition_immunities.duplicate()
	copy.attack_abilities = MonsterAbility.copies(attack_abilities)
	copy.defense_abilities = MonsterAbility.copies(defense_abilities)
	copy.attack_scaling = LevelValue.copies(attack_scaling)
	copy.defense_scaling = LevelValue.copies(defense_scaling)
	copy.hitpoints_scaling = LevelValue.copies(hitpoints_scaling)
	return copy


## A string that is equal for two templates with identical content - how the
## library sync (MonsterArchetypeLibrary.sync_templates()) decides whether an
## attached copy is out of date.
func signature() -> String:
	var abilities := func(list: Array[MonsterAbility]) -> Array:
		var names: Array = []
		for ability in list:
			names.append(ability.ability_name)
		return names
	var scaling := func(list: Array[LevelValue]) -> Array:
		var rows: Array = []
		for row in list:
			rows.append([row.min_level, row.max_level, row.value])
		return rows
	var rules: Array = []
	for rule in target_rules:
		rules.append(rule.rule_name)
	return var_to_str([
		template_name, kind, attack_range, attack_reach, rules, name_prefix, name_postfix,
		weaknesses, resistances, immunities, condition_immunities,
		abilities.call(attack_abilities), abilities.call(defense_abilities),
		scaling.call(attack_scaling), scaling.call(defense_scaling), scaling.call(hitpoints_scaling),
	])
