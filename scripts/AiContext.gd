class_name AiContext
extends RefCounted

## Builds the CONTEXT PACK the AI gets with a request: the part of the author's notes that matters for the text being worked on.
## The app assembles it itself (so it works the same with the API key and with Claude Code) and returns it together with a
## description of every part, so the UI can show "Context used" with a switch per part - nothing is sent unseen.
## Style guide and story bible go in whole; the character and location notes only contribute the `##` sections whose title
## is mentioned in the text; the rest is opt-in. Everything is limited by a character budget. Part of the AI workspace
## (claude.md, open item 26). Never instantiated.

const DEFAULT_BUDGET := 6000
## Notes that go in whole, in this order, when they exist and have something written in them.
const ALWAYS := ["style.md", "bible.md"]
## Notes of which only the sections named in the focus text go in.
const BY_MENTION := ["characters.md", "locations.md", "glossary.md"]


## options: {"disabled": Array[String] of part labels to leave out, "budget": int, "extra_files": Array[String] of note files to add
## in whole, "exclude_files": Array[String] of note files to leave out (e.g. the file being edited - it IS the text)}. `focus` = the text being worked on (plus anything else that names things, e.g. the chapter title).
## Returns {"text": String, "parts": [{label, file, chars, included (bool), reason}]}.
static func build(folder: String, focus: String, options: Dictionary = {}) -> Dictionary:
	var disabled: Array = options.get("disabled", [])
	var budget: int = int(options.get("budget", DEFAULT_BUDGET))
	var candidates: Array[Dictionary] = []  # {label, file, text}
	for file_name: String in ALWAYS:
		var text := _meaningful(CampaignNotes.read(folder, file_name), file_name)
		if text != "":
			candidates.append({"label": _title(file_name), "file": file_name, "text": text})
	for file_name: String in BY_MENTION:
		for section in CampaignNotes.sections(CampaignNotes.read(folder, file_name)):
			var title: String = section["title"]
			if title != "" and section["body"] != "" and _mentions(focus, title):
				candidates.append({"label": "%s: %s" % [_title(file_name), title], "file": file_name, "text": "%s\n%s" % [title, section["body"]]})
	for file_name: String in options.get("extra_files", []):
		var text := _meaningful(CampaignNotes.read(folder, file_name), file_name)
		if text != "" and not _has_file(candidates, file_name):
			candidates.append({"label": _title(file_name), "file": file_name, "text": text})
	var excluded: Array = options.get("exclude_files", [])
	candidates = candidates.filter(func(candidate: Dictionary): return not excluded.has(candidate["file"]))
	var parts: Array[Dictionary] = []
	var pieces: Array[String] = []
	var used := 0
	for candidate in candidates:
		var text: String = candidate["text"]
		var part := {"label": candidate["label"], "file": candidate["file"], "chars": text.length(), "included": false, "reason": ""}
		if disabled.has(candidate["label"]):
			part["reason"] = "switched off"
		elif used + text.length() > budget:
			part["reason"] = "over the size limit"
		else:
			part["included"] = true
			used += text.length()
			pieces.append("[%s]\n%s" % [candidate["label"], text])
		parts.append(part)
	return {"text": "\n\n".join(pieces), "parts": parts}


## A note that is still only its template (headings and the instructions we wrote) counts as empty.
static func _meaningful(text: String, file_name: String) -> String:
	var trimmed := text.strip_edges()
	if trimmed == "":
		return ""
	for note in CampaignNotes.STANDARD:
		if note["file"] == file_name and trimmed == str(note["text"]).strip_edges():
			return ""
	return trimmed


static func _title(file_name: String) -> String:
	for note in CampaignNotes.STANDARD:
		if note["file"] == file_name:
			return note["title"]
	return file_name.get_basename()


static func _has_file(candidates: Array[Dictionary], file_name: String) -> bool:
	for candidate in candidates:
		if candidate["file"] == file_name:
			return true
	return false


## Whether `name` is mentioned in `text` as a whole word (any case), also inside a [Name] tag.
static func _mentions(text: String, name: String) -> bool:
	var regex := RegEx.new()
	regex.compile("(?i)(?<![A-Za-z0-9])%s(?![A-Za-z0-9])" % _escape(name))
	return regex.search(text) != null


static func _escape(text: String) -> String:
	var result := ""
	for character in text:
		result += "\\" + character if "\\^$.|?*+()[]{}-".contains(character) else character
	return result
