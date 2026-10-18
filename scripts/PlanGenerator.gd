class_name PlanGenerator
extends Node

## Asks the AI (optional - AiClient.is_configured()) for a campaign PLAN (CampaignPlan) from the author's manuscript and notes.
## The prompt is assembled here: the rules and the JSON shape, the notes that matter (AiContext), the manuscripts in full, and what
## the campaign already contains (so the plan doesn't repeat it). The answer is only read through CampaignPlan.parse_answer(),
## never used as it came. Nothing is sent unless the author presses Generate.

const MAX_TOKENS := 8000
const MAX_MANUSCRIPT_CHARS := 60000
const NOTES_BUDGET := 14000
const TIMEOUT_SEC := 300.0

## Tests give this a stub that overrides ask().
var client: AiClient

var _busy := false


func is_busy() -> bool:
	return _busy or (client != null and client.is_busy())


func cancel() -> void:
	if client != null:
		client.cancel()


## Returns {ok, plan, dropped, error, cancelled}.
func generate(folder: String, campaign: Campaign) -> Dictionary:
	if _busy:
		return _fail("A plan is already being made.")
	var manuscripts := manuscript_text(folder)
	if manuscripts["text"] == "":
		return _fail("There is no manuscript yet. Write something in a manuscript file first (Writing workspace).")
	if manuscripts["text"].length() > MAX_MANUSCRIPT_CHARS:
		return _fail("The manuscript is too long to send in one go (%d characters; the limit is %d). Shorten it or split the work over acts." % [manuscripts["text"].length(), MAX_MANUSCRIPT_CHARS])
	if client == null:
		client = AiClient.new()
		client.timeout_sec = TIMEOUT_SEC
		add_child(client)
	_busy = true
	var answer := await client.ask(system_prompt(), user_prompt(folder, campaign, manuscripts["text"]), MAX_TOKENS)
	_busy = false
	if answer.get("cancelled", false):
		var cancelled := _fail("Cancelled.")
		cancelled["cancelled"] = true
		return cancelled
	if not answer["ok"]:
		return _fail(str(answer["error"]))
	var result := CampaignPlan.parse_answer(str(answer["text"]), manuscripts["sections"], campaign)
	if result["ok"]:
		result["plan"]["sources"] = manuscripts["sources"]
	result["cancelled"] = false
	return result


## The manuscripts of the campaign, all acts in order: {text, sources: {file: fingerprint}, sections: [{file, title, fingerprint}]}.
static func manuscript_text(folder: String) -> Dictionary:
	var pieces: Array[String] = []
	var sources := {}
	var sections: Array[Dictionary] = []
	for entry in CampaignNotes.list_files(folder):
		if not entry["manuscript"]:
			continue
		var text := CampaignNotes.read(folder, entry["file"]).strip_edges()
		if text == "":
			continue
		pieces.append("=== %s ===\n%s" % [entry["title"], text])
		sources[entry["file"]] = CampaignNotes.fingerprint(text)
		for section in CampaignNotes.sections(text):
			if section["title"] != "":
				sections.append({"file": entry["file"], "title": section["title"], "fingerprint": section["fingerprint"]})
	return {"text": "\n\n".join(pieces), "sources": sources, "sections": sections}


static func system_prompt() -> String:
	return "You help the author of a fantasy adventure campaign for a digital tabletop companion app. The author wrote a manuscript " \
		+ "(and notes). Work out how it should be structured as a playable campaign and answer with ONE JSON object and nothing else " \
		+ "(no markdown, no explanation). The shape:\n" \
		+ "{\"acts\": [{\"name\": \"\", \"intro\": \"a short introduction read to the players\", \"chapters\": [" \
		+ "{\"key\": \"short_unique_id\", \"title\": \"\", \"kind\": \"narrative\" or \"mission\", " \
		+ "\"summary\": \"1-3 sentences: what happens; for a mission also its objective and key moments\", " \
		+ "\"section\": \"the exact ## heading of the manuscript section this chapter comes from, or empty\", " \
		+ "\"start\": true for the first chapter of the act only, \"finale\": true for the chapter that ends the act, " \
		+ "\"links\": [{\"to\": \"key of the next chapter in the SAME act\", \"outcome\": \"win\" or \"lose\" or \"any\"}]}]}], " \
		+ "\"characters\": [{\"name\": \"\", \"description\": \"who they are, how they speak\"}], " \
		+ "\"variables\": [{\"name\": \"snake_case_name\", \"type\": \"bool\" or \"int\" or \"float\" or \"string\", \"default\": value, \"purpose\": \"what it remembers\"}]}\n" \
		+ "Rules: a chapter is 'narrative' when it is story, conversation and decisions with no tactical battle, and 'mission' when the " \
		+ "players play a tactical scenario on the board. Every act has one start chapter and ends in a finale; chapters are linked in the " \
		+ "order the story goes ('win' = followed when the chapter is won; add a 'lose' link only when the story says that failing leads " \
		+ "somewhere else - otherwise the players simply retry). Branches are allowed when the manuscript has them. Use character names " \
		+ "exactly as the manuscript spells them. Add variables only for things the story must remember between chapters (a decision, a " \
		+ "gift, who survived). Stay with what the manuscript says - do not invent plot. Skip things the campaign already has."


static func user_prompt(folder: String, campaign: Campaign, manuscript: String) -> String:
	var parts: Array[String] = []
	var excluded: Array[String] = []
	for entry in CampaignNotes.list_files(folder):
		if entry["manuscript"]:
			excluded.append(entry["file"])
	var extra: Array[String] = ["outline.md"]
	var pack := AiContext.build(folder, manuscript, {"budget": NOTES_BUDGET, "exclude_files": excluded, "extra_files": extra})
	if pack["text"] != "":
		parts.append("The author's notes:\n" + pack["text"])
	var existing := existing_summary(campaign)
	if existing != "":
		parts.append("The campaign already contains (do not repeat these):\n" + existing)
	parts.append("The manuscript:\n<<<\n%s\n>>>" % manuscript)
	return "\n\n".join(parts)


## What the campaign has: chapter titles per act, character names, variable names.
static func existing_summary(campaign: Campaign) -> String:
	var lines: Array[String] = []
	for i in campaign.acts.size():
		var act: CampaignAct = campaign.acts[i]
		if act.chapters.is_empty():
			continue
		var titles: Array[String] = []
		for chapter in act.chapters:
			titles.append(chapter.title)
		lines.append("Act %d (%s): %s" % [i + 1, act.act_name, "; ".join(titles)])
	var names: Array[String] = []
	for character in campaign.characters:
		names.append(character.character_name)
	if not names.is_empty():
		lines.append("Characters: " + ", ".join(names))
	var variables: Array[String] = []
	for variable in campaign.variables:
		variables.append(variable.name)
	if not variables.is_empty():
		lines.append("Variables: " + ", ".join(variables))
	return "\n".join(lines)


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "plan": CampaignPlan.empty(), "dropped": [], "error": message, "cancelled": false}
