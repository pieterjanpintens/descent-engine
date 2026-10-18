class_name CampaignPlan
extends RefCounted

## The PLAN of the AI workspace (claude.md, open item 26): a checklist of what a campaign needs - acts with chapters (narrative
## or mission), characters and variables - worked out from the author's manuscript and notes. It is plain data, kept in
## `notes/plan.json` of the campaign folder (private, never packaged). The author reviews it (PlanWindow), accepts or rejects
## items, edits them; building real campaign objects from the accepted items is a later step. Nothing in the game changes
## because of a plan.
##
## Everything the AI answers goes through `parse_answer()` first: the text is read as JSON, every field is checked and cleaned,
## sizes are limited and anything invalid is dropped (counted in `dropped`) - the AI's answer is never used as it came.
## A plan is a Dictionary:
##   {format, generated, sources: {file: fingerprint},
##    acts: [{name, intro, accepted, chapters: [{key, title, kind "narrative"|"mission", summary,
##            section_file, section_title, section_fp, start, finale, links: [{to, outcome "win"|"lose"|"any"}],
##            accepted, exists, built}]}],
##    characters: [{name, description, accepted, exists, built}],
##    variables: [{name, type "bool"|"int"|"float"|"string", default, purpose, accepted, exists, built}]}
## `exists` = the campaign already has an item with that title/name (shown as such, not accepted by default); `built` = the id of
## the campaign object made from the item ("" = not built yet). Never instantiated.

const FORMAT := 1
const FILE_NAME := "plan.json"
const MAX_ACTS := 12
const MAX_CHAPTERS := 30
const MAX_CHARACTERS := 60
const MAX_VARIABLES := 60
const MAX_LINKS := 6
const KINDS := ["narrative", "mission"]
const OUTCOMES := ["win", "lose", "any"]
const TYPES := ["bool", "int", "float", "string"]


static func plan_path(folder: String) -> String:
	return "%s/%s" % [CampaignNotes.notes_path(folder), FILE_NAME]


static func empty() -> Dictionary:
	return {"format": FORMAT, "generated": "", "sources": {}, "acts": [], "characters": [], "variables": []}


static func is_empty(plan: Dictionary) -> bool:
	return plan.get("acts", []).is_empty() and plan.get("characters", []).is_empty() and plan.get("variables", []).is_empty()


## The saved plan of a campaign (empty() when there is none or it can't be read).
static func load_plan(folder: String) -> Dictionary:
	var handle := FileAccess.open(plan_path(folder), FileAccess.READ)
	if handle == null or handle.get_length() > CampaignNotes.MAX_FILE_BYTES:
		return empty()
	var parsed: Variant = JSON.parse_string(handle.get_as_text())
	handle.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return empty()
	return _normalize(parsed, false)["plan"]


## False for a release or when the file can't be written.
static func save_plan(folder: String, plan: Dictionary) -> bool:
	if CampaignIO.is_release(folder) or DirAccess.make_dir_recursive_absolute(CampaignNotes.notes_path(folder)) != OK:
		return false
	var handle := FileAccess.open(plan_path(folder), FileAccess.WRITE)
	if handle == null:
		return false
	handle.store_string(JSON.stringify(plan, "\t"))
	handle.close()
	return true


## Reads the AI's answer. Returns {ok, plan, dropped (Array[String] of what was left out and why), error}. `manuscripts` = the
## sections of the manuscripts ([{file, title, fingerprint}]) used to link chapters to the text; `campaign` marks what exists.
static func parse_answer(answer: String, manuscripts: Array[Dictionary], campaign: Campaign) -> Dictionary:
	var json := _json_text(answer)
	var parsed: Variant = JSON.parse_string(json) if json != "" else null
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "plan": empty(), "dropped": [], "error": "The AI's answer was not a plan (no JSON found). Try again."}
	var result := _normalize(parsed, true, manuscripts, campaign)
	if is_empty(result["plan"]):
		return {"ok": false, "plan": result["plan"], "dropped": result["dropped"], "error": "The plan came back empty. Is there a manuscript to work from? Try again."}
	result["ok"] = true
	result["error"] = ""
	return result


## The JSON part of an answer: models like to wrap it in a code fence or a sentence.
static func _json_text(answer: String) -> String:
	var text := answer.strip_edges()
	var first := text.find("{")
	var last := text.rfind("}")
	if first == -1 or last <= first:
		return ""
	return text.substr(first, last - first + 1)


## Cleans a raw dictionary into a plan. `fresh` = it comes from the AI (items are accepted by default, links to the manuscript and
## existing campaign items are worked out); false = it is a saved plan, kept as it is (only made safe).
static func _normalize(raw: Dictionary, fresh: bool, manuscripts: Array[Dictionary] = [], campaign: Campaign = null) -> Dictionary:
	var dropped: Array[String] = []
	var plan := empty()
	plan["generated"] = _text(raw.get("generated", Time.get_datetime_string_from_system() if fresh else ""), 40)
	if typeof(raw.get("sources")) == TYPE_DICTIONARY:
		for file_name: String in raw["sources"]:
			plan["sources"][_text(file_name, 80)] = _text(raw["sources"][file_name], 40)
	var existing_chapters: Array[String] = []
	var existing_characters: Array[String] = []
	var existing_variables: Array[String] = []
	if campaign != null:
		for act in campaign.acts:
			for chapter in act.chapters:
				existing_chapters.append(chapter.title.to_lower())
		for character in campaign.characters:
			existing_characters.append(character.character_name.to_lower())
		for variable in campaign.variables:
			existing_variables.append(variable.name.to_lower())

	var acts_raw: Array = raw.get("acts", []) if typeof(raw.get("acts")) == TYPE_ARRAY else []
	for act_raw in acts_raw.slice(0, MAX_ACTS):
		if typeof(act_raw) != TYPE_DICTIONARY:
			dropped.append("an act that was not an object")
			continue
		var act := {"name": _text(act_raw.get("name", ""), 80), "intro": _text(act_raw.get("intro", ""), 1500), "accepted": _flag(act_raw, "accepted", true), "chapters": []}
		var keys: Dictionary = {}
		var chapters_raw: Array = act_raw.get("chapters", []) if typeof(act_raw.get("chapters")) == TYPE_ARRAY else []
		for chapter_raw in chapters_raw.slice(0, MAX_CHAPTERS):
			if typeof(chapter_raw) != TYPE_DICTIONARY or _text(chapter_raw.get("title", ""), 100) == "":
				dropped.append("a chapter without a title in act '%s'" % act["name"])
				continue
			var title := _text(chapter_raw.get("title", ""), 100)
			var key := _key(str(chapter_raw.get("key", "")), keys, act["chapters"].size())
			keys[key] = true
			var kind := str(chapter_raw.get("kind", "narrative")).to_lower()
			var chapter := {
				"key": key, "title": title, "kind": kind if KINDS.has(kind) else "narrative",
				"summary": _text(chapter_raw.get("summary", ""), 1500),
				"section_file": _text(chapter_raw.get("section_file", ""), 80), "section_title": _text(chapter_raw.get("section_title", ""), 120),
				"section_fp": _text(chapter_raw.get("section_fp", ""), 40),
				"start": bool(chapter_raw.get("start", false)), "finale": bool(chapter_raw.get("finale", false)),
				"links": [], "accepted": _flag(chapter_raw, "accepted", true), "exists": _flag(chapter_raw, "exists", false), "built": _text(chapter_raw.get("built", ""), 80),
				"synced_text": _text(chapter_raw.get("synced_text", ""), PlanSync.MAX_TEXT), "built_text": _text(chapter_raw.get("built_text", ""), PlanSync.MAX_TEXT),
				"built_fp": _text(chapter_raw.get("built_fp", ""), 40),
			}
			if fresh:
				chapter["section_file"] = ""
				chapter["section_title"] = ""
				chapter["section_fp"] = ""
				var section := _find_section(str(chapter_raw.get("section", "")), title, manuscripts)
				if not section.is_empty():
					chapter["section_file"] = section["file"]
					chapter["section_title"] = section["title"]
					chapter["section_fp"] = section["fingerprint"]
				chapter["exists"] = existing_chapters.has(title.to_lower())
				chapter["accepted"] = not chapter["exists"]
				chapter["built"] = ""
				chapter["synced_text"] = ""
				chapter["built_text"] = ""
				chapter["built_fp"] = ""
			chapter["links_raw"] = chapter_raw.get("links", [])
			act["chapters"].append(chapter)
		_finish_links(act, dropped)
		_fix_start_and_finale(act)
		if act["chapters"].is_empty():
			dropped.append("act '%s' had no usable chapters" % act["name"])
			continue
		if act["name"] == "":
			act["name"] = "Act %d" % (plan["acts"].size() + 1)
		plan["acts"].append(act)

	var characters_raw: Array = raw.get("characters", []) if typeof(raw.get("characters")) == TYPE_ARRAY else []
	var seen: Dictionary = {}
	for character_raw in characters_raw.slice(0, MAX_CHARACTERS):
		var character_name := _text(character_raw.get("name", ""), 40) if typeof(character_raw) == TYPE_DICTIONARY else ""
		if not _valid_character_name(character_name) or seen.has(character_name.to_lower()):
			dropped.append("a character with an unusable or repeated name ('%s')" % character_name)
			continue
		seen[character_name.to_lower()] = true
		var character := {"name": character_name, "description": _text(character_raw.get("description", ""), 800), "accepted": _flag(character_raw, "accepted", true), "exists": _flag(character_raw, "exists", false), "built": _text(character_raw.get("built", ""), 80)}
		if fresh:
			character["exists"] = existing_characters.has(character_name.to_lower())
			character["accepted"] = not character["exists"]
			character["built"] = ""
		plan["characters"].append(character)

	var variables_raw: Array = raw.get("variables", []) if typeof(raw.get("variables")) == TYPE_ARRAY else []
	seen = {}
	for variable_raw in variables_raw.slice(0, MAX_VARIABLES):
		var variable := _variable(variable_raw)
		if variable.is_empty() or seen.has(variable["name"]):
			dropped.append("a variable with an unusable or repeated name")
			continue
		seen[variable["name"]] = true
		variable["accepted"] = _flag(variable_raw, "accepted", true)
		variable["built"] = _text(variable_raw.get("built", ""), 80)
		variable["exists"] = _flag(variable_raw, "exists", false)
		if fresh:
			variable["exists"] = existing_variables.has(variable["name"]) or Campaign.BUILTIN_VARIABLES.has(variable["name"])
			variable["accepted"] = not variable["exists"]
			variable["built"] = ""
		plan["variables"].append(variable)
	return {"plan": plan, "dropped": dropped}


## Turns each chapter's raw links into {to, outcome} entries that point at another chapter of the same act.
static func _finish_links(act: Dictionary, dropped: Array[String]) -> void:
	var keys: Dictionary = {}
	for chapter in act["chapters"]:
		keys[chapter["key"]] = true
	for chapter in act["chapters"]:
		var raw: Variant = chapter["links_raw"]
		chapter.erase("links_raw")
		if typeof(raw) != TYPE_ARRAY:
			continue
		for link_raw in raw.slice(0, MAX_LINKS):
			if typeof(link_raw) != TYPE_DICTIONARY:
				continue
			var target := str(link_raw.get("to", ""))
			var outcome := str(link_raw.get("outcome", "win")).to_lower()
			if not keys.has(target) or target == chapter["key"]:
				dropped.append("a link from '%s' to a chapter that is not in the act" % chapter["title"])
				continue
			chapter["links"].append({"to": target, "outcome": outcome if OUTCOMES.has(outcome) else "win"})


## Exactly one start chapter, and at least one finale: what the AI left out is filled in (first chapter / last chapter).
static func _fix_start_and_finale(act: Dictionary) -> void:
	var chapters: Array = act["chapters"]
	if chapters.is_empty():
		return
	var start_index := -1
	var has_finale := false
	for i in chapters.size():
		if chapters[i]["start"]:
			if start_index == -1:
				start_index = i
			else:
				chapters[i]["start"] = false
		if chapters[i]["finale"]:
			has_finale = true
	if start_index == -1:
		chapters[0]["start"] = true
	if not has_finale:
		chapters[chapters.size() - 1]["finale"] = true


static func _variable(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var variable_name := str(raw.get("name", "")).strip_edges().to_lower().replace(" ", "_")
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_]{0,40}$")
	if regex.search(variable_name) == null:
		return {}
	var type := str(raw.get("type", "bool")).to_lower()
	if not TYPES.has(type):
		type = "bool"
	return {"name": variable_name, "type": type, "default": coerce_default(type, raw.get("default")), "purpose": _text(raw.get("purpose", ""), 400)}


## A variable's default as the right kind of value for its type (a number typed as text counts; anything else falls back to the
## type's zero value).
static func coerce_default(type: String, value: Variant) -> Variant:
	match type:
		"bool":
			if typeof(value) == TYPE_STRING:
				return str(value).strip_edges().to_lower() in ["true", "yes", "1"]
			return bool(value) if typeof(value) == TYPE_BOOL else false
		"int":
			if typeof(value) == TYPE_STRING:
				return int(str(value)) if str(value).strip_edges().is_valid_int() or str(value).strip_edges().is_valid_float() else 0
			return int(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else 0
		"float":
			if typeof(value) == TYPE_STRING:
				return float(str(value)) if str(value).strip_edges().is_valid_float() else 0.0
			return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else 0.0
	return _text(value, 100) if value != null else ""


## A character name is used as a tag [Name]...[/Name], so no brackets, slashes or line breaks.
static func _valid_character_name(character_name: String) -> bool:
	return character_name != "" and not character_name.contains("[") and not character_name.contains("]") and not character_name.contains("/") \
		and not character_name.contains("\n") and character_name.length() <= 40


## The manuscript section a chapter comes from: the heading the AI named, else one with the chapter's title. {} when none matches.
static func _find_section(heading: String, title: String, manuscripts: Array[Dictionary]) -> Dictionary:
	for wanted in [heading, title]:
		var needle := _plain(str(wanted))
		if needle == "":
			continue
		for section in manuscripts:
			if _plain(section["title"]) == needle:
				return section
		for section in manuscripts:
			var candidate := _plain(section["title"])
			if candidate != "" and (candidate.contains(needle) or needle.contains(candidate)):
				return section
	return {}


static func _plain(text: String) -> String:
	return text.strip_edges().to_lower().lstrip("# ").strip_edges()


static func _key(raw: String, used: Dictionary, index: int) -> String:
	var key := raw.strip_edges().to_lower().replace(" ", "_")
	var regex := RegEx.new()
	regex.compile("[^a-z0-9_]")
	key = regex.sub(key, "", true).left(30)
	if key == "":
		key = "chapter_%d" % (index + 1)
	var unique := key
	var number := 2
	while used.has(unique):
		unique = "%s_%d" % [key, number]
		number += 1
	return unique


static func _flag(source: Variant, field: String, fallback: bool) -> bool:
	if typeof(source) == TYPE_DICTIONARY and typeof(source.get(field)) == TYPE_BOOL:
		return source[field]
	return fallback


## A clean single value: a string with no control characters, limited in length.
static func _text(value: Variant, max_length: int) -> String:
	if value == null:
		return ""
	var text := str(value).strip_edges()
	var cleaned := ""
	for character in text:
		cleaned += character if character == "\n" or character.unicode_at(0) >= 32 else " "
	return cleaned.left(max_length)


## {accepted, total} over the acts' chapters, characters and variables that still have to be decided (items already built are left out).
static func counts(plan: Dictionary) -> Dictionary:
	var accepted := 0
	var total := 0
	for act in plan.get("acts", []):
		for chapter in act["chapters"]:
			if chapter["built"] != "":
				continue
			total += 1
			accepted += 1 if chapter["accepted"] else 0
	for list_name in ["characters", "variables"]:
		for item in plan.get(list_name, []):
			if item["built"] != "":
				continue
			total += 1
			accepted += 1 if item["accepted"] else 0
	return {"accepted": accepted, "total": total}
