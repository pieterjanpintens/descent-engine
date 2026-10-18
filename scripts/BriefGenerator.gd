class_name BriefGenerator
extends Node

## Asks the AI (optional - AiClient.is_configured()) to write the BRIEF of ONE mission chapter (MissionBrief): the goal, objectives,
## variables, monsters, map notes and key moments the story needs, from the chapter's summary, its manuscript section and the
## notes that matter. One chapter at a time, so the author decides what is sent and what it costs. The answer is only read
## through MissionBrief.parse_answer(). Nothing is sent unless the author presses the button.

const MAX_TOKENS := 3000
const NOTES_BUDGET := 10000
const TIMEOUT_SEC := 180.0

## Tests give this a stub that overrides ask().
var client: AiClient

var _busy := false


func is_busy() -> bool:
	return _busy or (client != null and client.is_busy())


func cancel() -> void:
	if client != null:
		client.cancel()


## Returns {ok, brief, dropped, error, cancelled}. `chapter_plan` = the plan chapter (title, summary, manuscript section).
func generate(folder: String, campaign: Campaign, act_plan: Dictionary, chapter_plan: Dictionary) -> Dictionary:
	if _busy:
		return _fail("A brief is already being made.")
	if client == null:
		client = AiClient.new()
		client.timeout_sec = TIMEOUT_SEC
		add_child(client)
	_busy = true
	var answer := await client.ask(system_prompt(), user_prompt(folder, campaign, act_plan, chapter_plan), MAX_TOKENS)
	_busy = false
	if answer.get("cancelled", false):
		var cancelled := _fail("Cancelled.")
		cancelled["cancelled"] = true
		return cancelled
	if not answer["ok"]:
		return _fail(str(answer["error"]))
	var result := MissionBrief.parse_answer(str(answer["text"]))
	result["cancelled"] = false
	return result


static func system_prompt() -> String:
	return "You help the author of a fantasy adventure campaign for a digital tabletop companion app. One chapter of the story is a " \
		+ "tactical MISSION that the players play on a board built from physical tiles. From the chapter's summary, its manuscript text " \
		+ "and the notes, write the mission's brief and answer with ONE JSON object and nothing else (no markdown, no explanation). The shape:\n" \
		+ "{\"goal\": \"one or two sentences: what the players must achieve\", " \
		+ "\"objectives\": [{\"kind\": \"win\" or \"lose\" or \"optional\", \"description\": \"short, clear\"}], " \
		+ "\"variables\": [{\"name\": \"snake_case\", \"type\": \"bool\" or \"int\" or \"float\" or \"string\", \"default\": value, \"purpose\": \"what it tracks\"}], " \
		+ "\"monsters\": [{\"name\": \"monster type\", \"count\": number, \"notes\": \"when/where they appear\"}], " \
		+ "\"map_notes\": \"what the map should be like: rooms, atmosphere, important places and objects - words only, no coordinates\", " \
		+ "\"key_moments\": [\"things that happen during the mission, in order\"]}\n" \
		+ "Rules: 'win' objectives are steps that must be done in the order given, the last one ends the mission with victory; 'lose' " \
		+ "objectives are ways to fail; 'optional' objectives are bonus goals. Use at most a few of each. Variables only for things the " \
		+ "mission has to remember (a door opened, an item found, a count). Stay with what the story says - do not invent plot - and use " \
		+ "names exactly as the manuscript spells them."


static func user_prompt(folder: String, campaign: Campaign, act_plan: Dictionary, chapter_plan: Dictionary) -> String:
	var parts: Array[String] = []
	var excluded: Array[String] = []
	for entry in CampaignNotes.list_files(folder):
		if entry["manuscript"]:
			excluded.append(entry["file"])
	var section := _section_text(folder, chapter_plan)
	var pack := AiContext.build(folder, section + "\n" + str(chapter_plan["summary"]), {"budget": NOTES_BUDGET, "exclude_files": excluded})
	if pack["text"] != "":
		parts.append("The author's notes:\n" + pack["text"])
	parts.append("Campaign: %s\nAct: %s" % [campaign.campaign_name, act_plan["name"]])
	var titles: Array[String] = []
	for sibling in act_plan["chapters"]:
		titles.append(("-> " if sibling["key"] == chapter_plan["key"] else "") + sibling["title"])
	parts.append("The chapters of this act in order (the mission is marked ->): " + ", ".join(titles))
	parts.append("The mission chapter: %s\nSummary: %s" % [chapter_plan["title"], chapter_plan["summary"]])
	if section != "":
		parts.append("Its manuscript text:\n<<<\n%s\n>>>" % section)
	var variables: Array[String] = []
	for variable in campaign.variables:
		variables.append(variable.name)
	if not variables.is_empty():
		parts.append("Campaign variables that exist (the mission may relate to them): " + ", ".join(variables))
	return "\n\n".join(parts)


## The manuscript section a chapter comes from, as it is now.
static func _section_text(folder: String, chapter_plan: Dictionary) -> String:
	if chapter_plan["section_file"] == "":
		return ""
	for section in CampaignNotes.sections(CampaignNotes.read(folder, chapter_plan["section_file"])):
		if section["title"] == chapter_plan["section_title"]:
			return str(section["body"]).left(20000)
	return ""


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "brief": MissionBrief.empty(), "dropped": [], "error": message, "cancelled": false}
