class_name MonsterTemplate
extends Resource

## Design-time definition of ONE monster an Effect.Type.SPAWN_MONSTERS
## effect spawns (Effect.spawn_monsters). Its properties are copied onto the
## RuntimeMonster registered at play time (MissionRuntime.register_monster()).
##
## Monsters are managed CENTRALLY through reusable monster templates
## (MonsterArchetype): exactly one BASE template (`base_archetype`, required - the
## Player does not spawn a monster without one, see
## MissionRuntime.register_monster()) defines what the monster is - its
## level-scaled hitpoints/attack/defense, attack range/reach, abilities, target
## rules - and any number of ADDITIVE templates (`archetypes`) add to it ("Tough":
## +hitpoints). The monster itself only has a type, a name and a level (the scaling
## input) - everything else comes from its templates. See resolve().

## MonsterDisplay.REAL_MONSTERS `folder`, e.g. "bandit", "blood sister".
@export var folder: String = "bandit"
## Optional; empty = use the monster type's generic name ("Bandit").
@export var custom_name: String = ""
## Picks the rows of the base/additive templates' scaling tables.
@export_range(0, 9999) var level: int = 1
## The monster's BASE template (an embedded COPY of the library entry, so the
## mission is self-contained). Required.
@export var base_archetype: MonsterArchetype
## ADDITIVE templates attached to this monster (embedded copies, in order).
@export var archetypes: Array[MonsterArchetype] = []

## A new monster definition with the first BASE template in the library attached
## (every monster needs a base), or null if the library has none yet.
static func create_with_default_base() -> MonsterTemplate:
	var keys := MonsterArchetypeLibrary.names_of_kind(MonsterArchetype.Kind.BASE)
	if keys.is_empty():
		return null
	var created := MonsterTemplate.new()
	created.base_archetype = MonsterArchetypeLibrary.load_template(keys[0])
	return created


## resolve()'s stat names -> the MonsterArchetype scaling table that feeds each.
const STAT_TABLES := {
	"hitpoints": "hitpoints_scaling",
	"attack_power": "attack_scaling",
	"defense": "defense_scaling",
}


## The monster's EFFECTIVE properties - its base template combined with every
## additive template (`archetypes`, in order):
## - name prefixes/postfixes are added (base, then additives);
## - weakness/resistance/immunity/condition-immunity lists are merged (union - an
##   additive can add but never remove);
## - attack/defense abilities, target rules and attack range/reach come from the
##   BASE template; additives do not touch them (for now);
## - hitpoints/attack power/defense = the base template's value for the monster's
##   level PLUS each additive's value for that level (may be negative); a table
##   with no rows contributes 0. A level outside a table's rows uses the closest
##   row (LevelValue.pick()). Hitpoints end up >= 1, attack/defense >= 0.
## Returns {name_prefix, name_postfix, weaknesses, resistances, immunities,
## condition_immunities, attack_abilities, defense_abilities, target_rules,
## attack_range, attack_reach, hitpoints, attack_power, defense, sources}
## (`sources`: stat -> [[template name, value], ...], the
## breakdown the totals were summed from). Used by MissionRuntime.register_monster()
## and the properties dialog's preview.
func resolve() -> Dictionary:
	var prefix := ""
	var postfix := ""
	var weak: Array[int] = []
	var resist: Array[int] = []
	var immune: Array[int] = []
	var condition_immune: Array[int] = []
	var attack_abils: Array[MonsterAbility] = []
	var defense_abils: Array[MonsterAbility] = []
	var rules: Array[TargetRule] = []
	var range_value := 0
	var reach_value := false
	var sources := {}
	for stat in STAT_TABLES:
		sources[stat] = []

	if base_archetype != null:
		prefix += base_archetype.name_prefix
		postfix += base_archetype.name_postfix
		_merge_ints(weak, base_archetype.weaknesses)
		_merge_ints(resist, base_archetype.resistances)
		_merge_ints(immune, base_archetype.immunities)
		_merge_ints(condition_immune, base_archetype.condition_immunities)
		_merge_abilities(attack_abils, base_archetype.attack_abilities)
		_merge_abilities(defense_abils, base_archetype.defense_abilities)
		_merge_rules(rules, base_archetype.target_rules)
		range_value = base_archetype.attack_range
		reach_value = base_archetype.attack_reach
		for stat in STAT_TABLES:
			var table: Array[LevelValue] = base_archetype.get(STAT_TABLES[stat])
			if LevelValue.has_rows(table):
				sources[stat].append([base_archetype.template_name, LevelValue.pick(table, level)])

	for additive in archetypes:
		prefix += additive.name_prefix
		postfix += additive.name_postfix
		_merge_ints(weak, additive.weaknesses)
		_merge_ints(resist, additive.resistances)
		_merge_ints(immune, additive.immunities)
		_merge_ints(condition_immune, additive.condition_immunities)
		for stat in STAT_TABLES:
			var table: Array[LevelValue] = additive.get(STAT_TABLES[stat])
			if LevelValue.has_rows(table):
				sources[stat].append([additive.template_name, LevelValue.pick(table, level)])

	var totals := {}
	for stat in STAT_TABLES:
		var total := 0
		for entry: Array in sources[stat]:
			total += int(entry[1])
		totals[stat] = maxi(total, 1 if stat == "hitpoints" else 0)
	return {
		"name_prefix": prefix, "name_postfix": postfix,
		"weaknesses": weak, "resistances": resist, "immunities": immune,
		"condition_immunities": condition_immune,
		"attack_abilities": attack_abils, "defense_abilities": defense_abils,
		"target_rules": rules, "attack_range": range_value, "attack_reach": reach_value,
		"hitpoints": totals["hitpoints"], "attack_power": totals["attack_power"], "defense": totals["defense"],
		"sources": sources,
	}


## The final display name with every prefix/postfix applied.
func full_name() -> String:
	var resolved := resolve()
	var base := custom_name if custom_name != "" else str(MonsterDisplay.find_monster(folder).get("name", folder))
	return "%s%s%s" % [resolved["name_prefix"], base, resolved["name_postfix"]]


## Multi-line readable form of resolve() for the properties dialog's preview,
## with each stat's breakdown ("HP 24 = 18 (Wolf Pack) + 6 (Tough)").
func resolved_summary() -> String:
	var r := resolve()
	var lines: Array[String] = []
	lines.append("%s - level %d" % [full_name(), level])
	if base_archetype == null:
		lines.append("No base template - choose one.")
	lines.append(_breakdown("HP", r["hitpoints"], r["sources"]["hitpoints"]))
	lines.append(_breakdown("Attack", r["attack_power"], r["sources"]["attack_power"]))
	lines.append(_breakdown("Defense", r["defense"], r["sources"]["defense"]))
	lines.append("Range %d%s" % [r["attack_range"], ", reach" if r["attack_reach"] else ""])
	lines.append("Weak: %s" % _names(r["weaknesses"], false))
	lines.append("Resistant: %s" % _names(r["resistances"], false))
	lines.append("Immune: %s" % _names(r["immunities"], false))
	lines.append("Immune to conditions: %s" % _names(r["condition_immunities"], true))
	lines.append("Attack abilities: %s" % _ability_names(r["attack_abilities"]))
	lines.append("Defense abilities: %s" % _ability_names(r["defense_abilities"]))
	var rule_names: Array[String] = []
	for rule: TargetRule in r["target_rules"]:
		rule_names.append(rule.display_name())
	lines.append("Preferred targets: %s" % (", ".join(rule_names) if not rule_names.is_empty() else "-"))
	return "\n".join(lines)


static func _breakdown(label: String, total: int, parts: Array) -> String:
	if parts.is_empty():
		return "%s %d (no table rows)" % [label, total]
	var text := ""
	for i in parts.size():
		var value := int(parts[i][1])
		if i == 0:
			text += "%d (%s)" % [value, parts[i][0]]
		else:
			text += " %s %d (%s)" % ["+" if value >= 0 else "-", absi(value), parts[i][0]]
	return "%s %d = %s" % [label, total, text] if parts.size() > 1 else "%s %d (%s)" % [label, total, parts[0][0]]


static func _ability_names(list: Array) -> String:
	var names: Array[String] = []
	for ability: MonsterAbility in list:
		names.append(ability.ability_name)
	return ", ".join(names) if not names.is_empty() else "-"


static func _names(kinds: Array, is_condition: bool) -> String:
	if kinds.is_empty():
		return "-"
	var names: Array[String] = []
	for kind in kinds:
		names.append(MonsterCondition.display_name(kind) if is_condition else Vulnerability.display_name(kind))
	return ", ".join(names)


static func _merge_ints(into: Array[int], extra: Array[int]) -> void:
	for value in extra:
		if not into.has(value):
			into.append(value)


static func _merge_abilities(into: Array[MonsterAbility], extra: Array[MonsterAbility]) -> void:
	for ability in extra:
		var present := false
		for existing in into:
			if existing.ability_name == ability.ability_name:
				present = true
				break
		if not present:
			into.append(MonsterAbility.from_dict(ability.to_dict()))


static func _merge_rules(into: Array[TargetRule], extra: Array[TargetRule]) -> void:
	for rule in extra:
		var present := false
		for existing in into:
			if existing.kind == rule.kind and existing.hero_slot == rule.hero_slot:
				present = true
				break
		if not present:
			into.append(TargetRule.from_dict(rule.to_dict()))


## One-line description for lists, e.g. "Rex - HP 20, Lv 1" (generic type
## name when no custom name is set).
func summary() -> String:
	var r := resolve()
	return "%s - HP %d, Lv %d, Def %d, Atk %d" % [full_name(), r["hitpoints"], level, r["defense"], r["attack_power"]]
