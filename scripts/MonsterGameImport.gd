class_name MonsterGameImport
extends RefCounted

## Builds BASE monster templates from the game's own monster data in the user's export
## (tools/asset_import/import_monster_data.py -> user://monster_data/monsters.json), so the library starts with the
## game's monsters. Nothing of it ships; new templates a designer makes are never prefilled.
##
## One template per ACTIVATION of an enemy (the second one of a Vampire is "Ranged Vampire"). From the data: name; the three
## tiers become the level 1/2/3 rows of the hitpoints / defense / attack tables (attack = the activation's damage + the
## tier's base attack); speed and range from the activation (a range type other than 0 = a ranged attack); weaknesses and
## the resistance; the defense ability (game key); the activation's ability text (game key); loot; the tag "Large" for size 2.
## Only enemies of the families our figures cover are imported - named, villain and story enemies are skipped.

const FILE := "user://monster_data/monsters.json"
const REPORT_FILE := "user://monster_data/import_report.txt"
## The game's family numbers of the monsters we have figures for (12 = dragons are not among them).
const FAMILY_TYPES: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15, 16, 17]
const STORY_ID_PATTERN := "^ENEMY_(Q\\d|S\\d|A\\d|INTRO|EVIL|BOSS|NAMED)"


static func available() -> bool:
	return FileAccess.file_exists(FILE)


## Builds every template without saving: [{archetype, enemy_id, activation_id, ability_text_missing}].
static func build_templates() -> Array[Dictionary]:
	var built: Array[Dictionary] = []
	if not available():
		return built
	var data = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if not (data is Dictionary):
		return built
	var story := RegEx.create_from_string(STORY_ID_PATTERN)
	var used_names := {}
	for enemy: Dictionary in data.get("enemies", []):
		var identifier := str(enemy.get("id", ""))
		if str(enemy.get("name", "")) == "" or bool(enemy.get("named", false)) or bool(enemy.get("villain", false)):
			continue
		if story.search(identifier) != null or identifier.contains("SCULPT") or not FAMILY_TYPES.has(int(enemy.get("type", -1))):
			continue
		var activations: Array = enemy.get("activations", [])
		if activations.is_empty():
			activations = [{}]
		for index in activations.size():
			var activation: Dictionary = activations[index]
			var name := _unique_name(_template_name(enemy, activations, index), identifier, used_names)
			var archetype := _build(enemy, activation, name)
			var missing := str(activation.get("ability_key", "")) == "" and not activation.is_empty()
			built.append({"archetype": archetype, "enemy_id": identifier, "activation_id": str(activation.get("id", "")), "ability_text_missing": missing})
	return built


## Saves the templates that do not exist yet. Returns {created: [names], existing: [names], missing_text: ["Name (activation id)"]}.
static func run() -> Dictionary:
	var report := {"created": [], "existing": [], "missing_text": []}
	var known := MonsterArchetypeLibrary.names()
	for entry in build_templates():
		var archetype: MonsterArchetype = entry["archetype"]
		if known.has(MonsterArchetypeLibrary.key_for(archetype.template_name)):
			report["existing"].append(archetype.template_name)
			continue
		if MonsterArchetypeLibrary.save_template(archetype) != "":
			report["created"].append(archetype.template_name)
			if entry["ability_text_missing"]:
				report["missing_text"].append("%s (%s)" % [archetype.template_name, entry["activation_id"]])
	return report


static func report_text(report: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("Created %d templates." % report["created"].size())
	lines.append("")
	lines.append("Skipped because a template with that name already exists (%d):" % report["existing"].size())
	for name in report["existing"]:
		lines.append("  " + str(name))
	lines.append("")
	lines.append("Created, but no ability text was found for the activation (%d):" % report["missing_text"].size())
	for name in report["missing_text"]:
		lines.append("  " + str(name))
	return "\n".join(lines)


static func _template_name(enemy: Dictionary, activations: Array, index: int) -> String:
	var base := str(enemy["name"])
	if index == 0:
		return base
	var first_range := int(activations[0].get("range", 0)) if activations[0].has("range") else 0
	if int(activations[index].get("range", 0)) > 0 and first_range == 0:
		return "Ranged " + base
	return "%s (%d)" % [base, index + 1]


## Different enemies can share a display name (a Wrathful Specter is called "Specter"): the later one gets its id added.
static func _unique_name(wanted: String, identifier: String, used: Dictionary) -> String:
	var name := wanted
	if used.has(name):
		name = "%s (%s)" % [wanted, identifier.trim_prefix("ENEMY_").replace("_", " ").capitalize()]
	used[name] = true
	return name


static func _build(enemy: Dictionary, activation: Dictionary, name: String) -> MonsterArchetype:
	var archetype := MonsterArchetype.new()
	archetype.template_name = name
	archetype.kind = MonsterArchetype.Kind.BASE
	var damage := int(activation.get("damage", 0))
	for tier: Dictionary in enemy.get("tiers", []):
		var level := int(tier["tier"])
		archetype.hitpoints_scaling.append(_row(level, level, int(tier["hp"])))
		archetype.defense_scaling.append(_row(level, level, int(tier["defense"])))
		archetype.attack_scaling.append(_row(level, level, damage + int(tier["attack"])))
	archetype.speed_scaling.append(_row(1, 99, int(activation.get("speed", 0))))
	archetype.attack_range = int(activation.get("range", 0)) if int(activation.get("range_type", 0)) != 0 else 0
	for number in enemy.get("weaknesses", []):
		if WeaponData.TRAIT_TO_KIND.has(int(number)):
			archetype.weaknesses.append(WeaponData.TRAIT_TO_KIND[int(number)])
	for number in enemy.get("resistances", []):
		if WeaponData.TRAIT_TO_KIND.has(int(number)):
			archetype.resistances.append(WeaponData.TRAIT_TO_KIND[int(number)])
	var defense_key := str(enemy.get("defensive_key", ""))
	var defense := ItemData.defense_ability(defense_key)
	if not defense.is_empty():
		var ability := MonsterAbility.new()
		ability.ability_name = str(defense["name"])
		ability.game_key = defense_key
		archetype.defense_abilities.append(ability)
	var attack_key := str(activation.get("ability_key", ""))
	var attack := ItemData.attack_ability(attack_key) if attack_key != "" else {}
	if not attack.is_empty():
		var ability := MonsterAbility.new()
		ability.ability_name = str(attack["name"])
		ability.game_key = attack_key
		archetype.attack_abilities.append(ability)
	if int(enemy.get("size", 0)) == 2:
		archetype.tags.append("Large")
	for entry: Dictionary in enemy.get("tactics", []):
		var tactic := MonsterTactic.new()
		tactic.tactic_name = str(entry.get("name", ""))
		tactic.speed = int(entry.get("speed", 3))
		tactic.damage_offset = int(entry.get("damage", 0)) - damage
		tactic.attack_range = int(entry.get("range", 0)) if int(entry.get("range_type", 0)) != 0 else 0
		tactic.hint_key = str(entry.get("hint_key", ""))
		tactic.activation_key = str(entry.get("activation_key", ""))
		tactic.pass_key = str(entry.get("pass_key", ""))
		tactic.fail_key = str(entry.get("fail_key", ""))
		tactic.reaction_key = str(entry.get("reaction_key", ""))
		tactic.time_passes_key = str(entry.get("time_passes_key", ""))
		archetype.tactics.append(tactic)
	for table: Dictionary in enemy.get("loot", []):
		var item := LootItem.new(_loot_name(str(table.get("name", ""))))
		for material: String in table.get("common", []):
			item.common_materials.append(material.trim_prefix("MAT_").to_lower())
		for material: String in table.get("essences", []):
			item.essences.append(material.trim_prefix("MAT_").to_lower())
		archetype.loot.append(item)
	return archetype


static func _row(from_level: int, to_level: int, value: int) -> LevelValue:
	var row := LevelValue.new()
	row.min_level = from_level
	row.max_level = to_level
	row.value = value
	return row


## "a Corroded Blade" -> "Corroded Blade", "some Rusty Chains" -> "Rusty Chains".
static func _loot_name(text: String) -> String:
	for article in ["a ", "an ", "some "]:
		if text.begins_with(article):
			return text.substr(article.length()).capitalize()
	return text
