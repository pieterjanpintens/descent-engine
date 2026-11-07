class_name HeroData
extends RefCounted

## The game's hero cards - skills, legends and feats - read from the user's own export (tools/asset_import/import_hero_data.py ->
## user://hero_data/heroes.json + localization_<code>.json). Never instantiated; nothing of it ships, without the export every
## lookup comes back empty. The texts follow the content language like the other game data (the first language of LText.reading_order()
## that has a file, English otherwise; a key missing in it is filled in from English).
##
## What the data holds: a skill / legend has a NAME (two card sides, "Side A / Side B"), an XP cost and an act - NOT its rule text (that is only
## on the card pictures). A feat is a goal with a reward that is either a skill or a recipe. The game's XP is an equip limit (the total XP cost of the
## cards a hero equips for a quest may not exceed the hero's XP), not a currency; skills come from the story or from a feat.
##
## Heroes are identified by id ("HERO_CHANCE"); HeroCatalog's slots map to them with id_for_slot(). Ids of the cards are the game's:
## "SKILL_CHANCE_3", "LEGEND_CHANCE_1" (a legend CARD has two sides, A and B, in the data "LEGEND_CHANCE_1A" / "...1B"), "FEAT_CHANCE_7".

const FILE := "user://hero_data/heroes.json"
const FOLDER := "user://hero_data/"

static var _loaded := false
static var _language := ""  ## the text language the cached data was built for
static var _texts: Dictionary = {}
static var _heroes: Array[Dictionary] = []  # {id, name, virtues, starting_weapons, starting_feat, color_light, color_dark}
static var _skills: Array[Dictionary] = []  # {id, hero, number, name, name_a, name_b, xp, act, feat}
static var _legends: Array[Dictionary] = []  # {id, hero, number, name, name_a, name_b, xp, act}
static var _feats: Array[Dictionary] = []  # see _build_feat()
static var _by_id: Dictionary = {}  ## every hero / skill / legend / feat id -> its entry


static func available() -> bool:
	_load()
	return not _heroes.is_empty()


static func reload() -> void:
	_loaded = false
	_texts = {}
	_heroes = []
	_skills = []
	_legends = []
	_feats = []
	_by_id = {}


## The hero id of a HeroCatalog slot ("HERO_CHANCE" for slot 0).
static func id_for_slot(slot: int) -> String:
	return "HERO_" + HeroCatalog.HERO_NAMES[slot].to_upper()


## The HeroCatalog slot of a hero id, -1 when it is not one of the six.
static func slot_for_id(hero_id: String) -> int:
	return HeroCatalog.HERO_NAMES.find(hero_id.trim_prefix("HERO_").capitalize())


# --- heroes ---------------------------------------------------------------------------------------------------------

static func heroes() -> Array[Dictionary]:
	_load()
	return _heroes


static func hero(hero_id: String) -> Dictionary:
	_load()
	var entry = _by_id.get(hero_id)
	return entry if entry != null and entry.has("virtues") else {}


## "Chance"; the id itself when unknown.
static func hero_name(hero_id: String) -> String:
	var entry := hero(hero_id)
	return str(entry["name"]) if not entry.is_empty() else hero_id


# --- skills ---------------------------------------------------------------------------------------------------------

## A hero's skill cards in the game's order (1-11).
static func skills_of(hero_id: String) -> Array[Dictionary]:
	_load()
	var result: Array[Dictionary] = []
	for skill in _skills:
		if skill["hero"] == hero_id:
			result.append(skill)
	return result


static func skill(skill_id: String) -> Dictionary:
	_load()
	var entry = _by_id.get(skill_id)
	return entry if entry != null and entry.has("number") and entry["id"].begins_with("SKILL_") else {}


## "Disguise / Careful"; the id itself when unknown.
static func skill_name(skill_id: String) -> String:
	var entry := skill(skill_id)
	return str(entry["name"]) if not entry.is_empty() else skill_id


## The XP cost of a skill (0 when unknown).
static func skill_cost(skill_id: String) -> int:
	return int(skill(skill_id).get("xp", 0))


## What all of a hero's skills cost together (about 18).
static func total_skill_cost(hero_id: String) -> int:
	var total := 0
	for entry in skills_of(hero_id):
		total += int(entry["xp"])
	return total


## The feat whose reward is this skill, "" for a skill the story hands out.
static func skill_feat(skill_id: String) -> String:
	return str(skill(skill_id).get("feat", ""))


# --- legends --------------------------------------------------------------------------------------------------------

## A hero's legend cards (3): {id ("LEGEND_CHANCE_1"), hero, number, name ("Clever-Paw / Clever-Heart"), name_a, name_b, xp, act}.
static func legends_of(hero_id: String) -> Array[Dictionary]:
	_load()
	var result: Array[Dictionary] = []
	for legend in _legends:
		if legend["hero"] == hero_id:
			result.append(legend)
	return result


# --- feats ----------------------------------------------------------------------------------------------------------

## A hero's feats (20) in the game's order: {id, hero, number, title ("Snake Eyes"), description (what to do), goal (how many times),
## timing (raw game number, when it is checked), act, completed_required (feats the hero must have finished before it is offered),
## prerequisites (feat ids that must be finished first), rewards (ids), reward ("SKILL_CHANCE_3" or a recipe id), reward_kind
## ("skill" | "recipe")}.
static func feats_of(hero_id: String) -> Array[Dictionary]:
	_load()
	var result: Array[Dictionary] = []
	for feat in _feats:
		if feat["hero"] == hero_id:
			result.append(feat)
	return result


static func feat(feat_id: String) -> Dictionary:
	_load()
	var entry = _by_id.get(feat_id)
	return entry if entry != null and str(entry.get("id", "")).begins_with("FEAT_") else {}


## Whether a hero is offered this feat: not finished yet, enough other feats finished (`completed_required`) and every prerequisite feat among
## `completed` (feat ids the hero has finished).
static func feat_offered(feat_id: String, completed: Array) -> bool:
	var entry := feat(feat_id)
	if entry.is_empty() or completed.has(feat_id):
		return false
	if completed.size() < int(entry["completed_required"]):
		return false
	for needed: String in entry["prerequisites"]:
		if not completed.has(needed):
			return false
	return true


## The feats a hero is offered right now, given the feat ids they finished.
static func feats_offered(hero_id: String, completed: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in feats_of(hero_id):
		if feat_offered(entry["id"], completed):
			result.append(entry)
	return result


## The game's own wording for a glossary / UI text of these cards (TERM_EXPERIENCE_DESC, TERM_FEATS_DESC_1, UI_FEAT_COMPLETED...).
static func term_text(key: String) -> String:
	_load()
	return ItemData.clean_markup(str(_texts.get(key, "")))


# --- loading --------------------------------------------------------------------------------------------------------

static func _load() -> void:
	var language := ItemData.text_language(FOLDER)
	if language != _language:
		_language = language
		reload()
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(FILE):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if not data is Dictionary:
		return
	_texts = ItemData.load_texts(FOLDER)

	for raw: Dictionary in data.get("heroes", []):
		var entry := {
			"id": str(raw.get("_id", "")),
			"name": _text(str(raw.get("KeyName", "")), str(raw.get("m_Name", ""))),
			"virtues": [_text(str(raw.get("VirtueOneKey", ""))), _text(str(raw.get("VirtueTwoKey", "")))],
			"starting_weapons": raw.get("StartingWeapons", []),
			"starting_feat": str(raw.get("StartingFeat", "")),
			"color_light": _color(raw.get("ColorLight", {})),
			"color_dark": _color(raw.get("ColorDark", {})),
		}
		_heroes.append(entry)
		_by_id[entry["id"]] = entry

	var rewarded: Dictionary = {}  # skill id -> the feat that gives it
	for raw: Dictionary in data.get("feats", []):
		for reward in raw.get("Rewards", []):
			if str(reward).begins_with("SKILL_"):
				rewarded[str(reward)] = str(raw.get("_id", ""))

	for raw: Dictionary in data.get("skills", []):
		var id := str(raw.get("_id", ""))
		var names := _two_sides(_text(str(raw.get("KeyName", "")), id))
		var skill_entry := {
			"id": id, "hero": _hero_of(id), "number": _number_of(id), "name": names[2], "name_a": names[0], "name_b": names[1],
			"xp": int(raw.get("XPCost", 0)), "act": int(raw.get("_act", 0)), "feat": str(rewarded.get(id, "")),
		}
		_skills.append(skill_entry)
		_by_id[id] = skill_entry

	var legend_sides: Dictionary = {}  # "LEGEND_CHANCE_1" -> {"A": name, "B": name}
	var legend_raw: Dictionary = {}
	for raw: Dictionary in data.get("legends", []):
		var id := str(raw.get("_id", ""))
		var card := id.substr(0, id.length() - 1)
		var sides: Dictionary = legend_sides.get(card, {})
		sides[id.right(1)] = _text(str(raw.get("KeyName", "")), id)
		legend_sides[card] = sides
		legend_raw[card] = raw
	for card: String in legend_raw:
		var raw: Dictionary = legend_raw[card]
		var side_a := str(legend_sides[card].get("A", ""))
		var side_b := str(legend_sides[card].get("B", ""))
		var legend_entry := {
			"id": card, "hero": _hero_of(card), "number": _number_of(card), "name": "%s / %s" % [side_a, side_b], "name_a": side_a,
			"name_b": side_b, "xp": int(raw.get("XPCost", 0)), "act": int(raw.get("_act", 0)),
		}
		_legends.append(legend_entry)
		_by_id[card] = legend_entry
	_legends.sort_custom(_by_hero_number)

	for raw: Dictionary in data.get("feats", []):
		var feat_entry := _build_feat(raw)
		_feats.append(feat_entry)
		_by_id[feat_entry["id"]] = feat_entry
	_feats.sort_custom(_by_hero_number)
	_skills.sort_custom(_by_hero_number)


static func _build_feat(raw: Dictionary) -> Dictionary:
	var id := str(raw.get("_id", ""))
	var shown := str(_texts.get(str(raw.get("DescriptionKey", "")), ""))
	var title := ""
	var match_ := RegEx.create_from_string("<b>([^<]*)</b>:?\\s*(.*)").search(shown)
	var description := shown
	if match_ != null:
		title = ItemData.clean_markup(match_.get_string(1))
		description = match_.get_string(2)
	var rewards: Array[String] = []
	for reward in raw.get("Rewards", []):
		rewards.append(str(reward))
	var prerequisites: Array[String] = []
	for needed in raw.get("PrerequisiteFeats", []):
		prerequisites.append(str(needed))
	var first := rewards[0] if not rewards.is_empty() else ""
	return {
		"id": id, "hero": str(raw.get("HeroSource", "")), "number": _number_of(id), "title": title,
		"description": ItemData.clean_markup(description), "goal": int(raw.get("Goal", 1)), "timing": int(raw.get("Timing", 0)),
		"act": int(raw.get("_act", 0)), "completed_required": int(raw.get("AmountCompletedRequired", 0)),
		"prerequisites": prerequisites, "rewards": rewards, "reward": first,
		"reward_kind": "skill" if first.begins_with("SKILL_") else "recipe",
	}


## "SKILL_CHANCE_3" / "LEGEND_CHANCE_1A" / "FEAT_CHANCE_7" -> "HERO_CHANCE".
static func _hero_of(id: String) -> String:
	var parts := id.split("_")
	return "HERO_" + parts[1] if parts.size() > 1 else ""


## "SKILL_CHANCE_3" -> 3, "LEGEND_CHANCE_1" -> 1.
static func _number_of(id: String) -> int:
	return int(id.get_slice("_", id.get_slice_count("_") - 1))


static func _by_hero_number(a: Dictionary, b: Dictionary) -> bool:
	if a["hero"] != b["hero"]:
		return a["hero"] < b["hero"]
	return int(a["number"]) < int(b["number"])


## "Disguise / Careful" -> ["Disguise", "Careful", "Disguise / Careful"] (a name without a slash has both sides the same; some languages
## write the slash without spaces).
static func _two_sides(text: String) -> Array[String]:
	var parts := text.split("/", true, 1)
	var side_a := parts[0].strip_edges()
	var side_b := parts[1].strip_edges() if parts.size() > 1 else side_a
	return [side_a, side_b, text]


static func _text(key: String, fallback: String = "") -> String:
	var shown := ItemData.clean_markup(str(_texts.get(key, "")))
	return shown if shown != "" else fallback


static func _color(raw) -> Color:
	if raw is Dictionary:
		return Color(float(raw.get("r", 0.0)), float(raw.get("g", 0.0)), float(raw.get("b", 0.0)), float(raw.get("a", 1.0)))
	return Color.WHITE
