class_name MissionBrief
extends RefCounted

## Step 5 of the AI workspace (claude.md, open item 26): the BRIEF of a mission chapter - what the author's story needs the mission
## to be, worked out from the manuscript and notes: the goal, the objectives (win / lose / optional), the variables the mission
## has to track, the monsters, notes on the map, and the key moments. It is plain data kept on the plan chapter
## (`chapter_plan["brief"]`, so in `notes/plan.json`, private), edited by the author in BriefWindow. A brief never contains map
## geometry - the author draws the map in the mission editor. `BriefBuilder` can turn a brief into an empty skeleton mission
## (objectives + variables, no map).
## Everything the AI answers goes through `parse_answer()`: read as JSON, every field checked and cleaned, sizes limited, anything
## unusable dropped and counted. A brief is a Dictionary:
##   {goal, objectives: [{kind "win"|"lose"|"optional", description}], variables: [{name, type, default, purpose}],
##    monsters: [{name, count, notes}], map_notes, key_moments: [String], built_file}
## `built_file` = the mission file made from it ("" = none yet). Never instantiated.

const MAX_OBJECTIVES := 10
const MAX_VARIABLES := 20
const MAX_MONSTERS := 20
const MAX_MOMENTS := 12
const KINDS := ["win", "lose", "optional"]
## Variable names the skeleton mission makes for its objectives - a brief's own variables may not use them.
const RESERVED_PREFIXES := ["objective_", "failure_", "optional_"]


static func empty() -> Dictionary:
	return {"goal": "", "objectives": [], "variables": [], "monsters": [], "map_notes": "", "key_moments": [], "built_file": ""}


## Whether the brief says anything at all.
static func has_content(brief: Dictionary) -> bool:
	return brief.get("goal", "") != "" or not brief.get("objectives", []).is_empty() or not brief.get("variables", []).is_empty() \
		or not brief.get("monsters", []).is_empty() or brief.get("map_notes", "") != "" or not brief.get("key_moments", []).is_empty()


## Reads the AI's answer: {ok, brief, dropped (Array[String]), error}.
static func parse_answer(answer: String) -> Dictionary:
	var text := answer.strip_edges()
	var first := text.find("{")
	var last := text.rfind("}")
	var parsed: Variant = JSON.parse_string(text.substr(first, last - first + 1)) if first != -1 and last > first else null
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "brief": empty(), "dropped": [], "error": "The AI's answer was not a brief (no JSON found). Try again."}
	var result := normalize(parsed)
	if not has_content(result["brief"]):
		return {"ok": false, "brief": result["brief"], "dropped": result["dropped"], "error": "The brief came back empty. Try again."}
	result["ok"] = true
	result["error"] = ""
	return result


## Cleans a raw dictionary into a brief: {brief, dropped}.
static func normalize(raw: Dictionary) -> Dictionary:
	var dropped: Array[String] = []
	var brief := empty()
	brief["goal"] = CampaignPlan._text(raw.get("goal", ""), 1500)
	brief["map_notes"] = CampaignPlan._text(raw.get("map_notes", ""), 2500)
	brief["built_file"] = CampaignPlan._text(raw.get("built_file", ""), 120)
	for objective in _array(raw, "objectives").slice(0, MAX_OBJECTIVES):
		var description := CampaignPlan._text(objective.get("description", ""), 300) if typeof(objective) == TYPE_DICTIONARY else ""
		if description == "":
			dropped.append("an objective without a description")
			continue
		var kind := str(objective.get("kind", "win")).to_lower()
		brief["objectives"].append({"kind": kind if KINDS.has(kind) else "win", "description": description})
	var seen := {}
	for variable_raw in _array(raw, "variables").slice(0, MAX_VARIABLES):
		var variable := CampaignPlan.clean_variable(variable_raw)
		if variable.is_empty() or seen.has(variable["name"]) or _reserved(variable["name"]):
			dropped.append("a variable with an unusable, repeated or reserved name")
			continue
		seen[variable["name"]] = true
		brief["variables"].append(variable)
	for monster in _array(raw, "monsters").slice(0, MAX_MONSTERS):
		var monster_name := CampaignPlan._text(monster.get("name", ""), 60) if typeof(monster) == TYPE_DICTIONARY else ""
		if monster_name == "":
			dropped.append("a monster without a name")
			continue
		var count := int(monster["count"]) if typeof(monster.get("count")) in [TYPE_INT, TYPE_FLOAT] else 1
		brief["monsters"].append({"name": monster_name, "count": clampi(count, 1, 99), "notes": CampaignPlan._text(monster.get("notes", ""), 300)})
	for moment in _array(raw, "key_moments").slice(0, MAX_MOMENTS):
		var line := CampaignPlan._text(moment, 300)
		if line != "":
			brief["key_moments"].append(line)
	# A mission needs a way to be won: the goal becomes the win objective when the AI gave none.
	var has_win := false
	for objective in brief["objectives"]:
		if objective["kind"] == "win":
			has_win = true
	if not has_win and brief["goal"] != "":
		brief["objectives"].insert(0, {"kind": "win", "description": brief["goal"].left(300)})
	return {"brief": brief, "dropped": dropped}


static func _reserved(variable_name: String) -> bool:
	for prefix in RESERVED_PREFIXES:
		if variable_name.begins_with(prefix):
			return true
	return false


static func _array(raw: Dictionary, field: String) -> Array:
	return raw[field] if typeof(raw.get(field)) == TYPE_ARRAY else []
