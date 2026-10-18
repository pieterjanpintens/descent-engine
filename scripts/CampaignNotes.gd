class_name CampaignNotes
extends RefCounted

## The author's private writing space for one campaign: plain markdown files in a `notes/` sub-folder of the campaign folder
## (user://campaigns/<folder>/notes/). Story bible, style guide, characters... plus the MANUSCRIPT, one file per act with the
## chapters as `##` headings. Never packaged or released - SharePackage.build_campaign() only takes the campaign folder's own
## top-level files, and a fork copies top-level files only. Part of the AI workspace (claude.md, open item 26); nothing here
## needs AI - the files are just text, editable in the game or in any editor.
## Never instantiated.

const DIR := "notes"
const MAX_FILE_BYTES := 1024 * 1024
const MANUSCRIPT_PREFIX := "manuscript_act_"

## The notes a new workspace starts with. Each has a short template that tells the author (and the AI) what belongs in it.
const STANDARD := [
	{"file": "style.md", "title": "Style guide", "text": "# Style guide\n\nHow the story is told: tone, point of view, tense, language level, things to always or never do.\n\n- Tone:\n- Point of view:\n- Avoid:\n"},
	{"file": "bible.md", "title": "Story bible", "text": "# Story bible\n\nThe world and the premise: setting, history, rules of magic, factions, the central conflict.\n\n## Premise\n\n## The world\n\n## Factions\n"},
	{"file": "characters.md", "title": "Characters", "text": "# Characters\n\nOne `##` section per character, named exactly like the character tag in the story ([Name]...[/Name]).\n\n## Example\nWho they are, how they speak, what they want, what they hide.\n"},
	{"file": "locations.md", "title": "Locations", "text": "# Locations\n\nOne `##` section per place.\n\n## Example\nWhat it looks like, who is there, what happens there.\n"},
	{"file": "outline.md", "title": "Outline", "text": "# Outline\n\nThe plan for the whole campaign: the acts, the big turning points, how it ends.\n\n## Act 1\n\n## Act 2\n"},
	{"file": "glossary.md", "title": "Glossary", "text": "# Glossary\n\nNames, spellings and terms to keep consistent.\n"},
]


static func notes_path(folder: String) -> String:
	return "%s/%s" % [CampaignIO.folder_path(folder), DIR]


static func file_path(folder: String, file_name: String) -> String:
	return "%s/%s" % [notes_path(folder), file_name]


## A note file name is flat, ends in .md and holds only plain characters (nothing that could leave the notes folder).
static func is_valid_file_name(file_name: String) -> bool:
	if file_name.get_extension().to_lower() != "md" or file_name != file_name.get_file() or file_name.begins_with("."):
		return false
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9][A-Za-z0-9 _\\-]*\\.md$")
	return regex.search(file_name) != null and file_name.length() <= 80


static func manuscript_file(act_number: int) -> String:
	return "%s%02d.md" % [MANUSCRIPT_PREFIX, act_number]


static func is_manuscript(file_name: String) -> bool:
	return file_name.begins_with(MANUSCRIPT_PREFIX) and file_name.get_extension().to_lower() == "md"


## Creates the notes folder and any standard note that is missing. Never overwrites a file. Returns false when the campaign
## is a release (read-only) or the folder can't be made.
static func ensure(folder: String) -> bool:
	if CampaignIO.is_release(folder):
		return false
	if DirAccess.make_dir_recursive_absolute(notes_path(folder)) != OK:
		return false
	for note in STANDARD:
		if not FileAccess.file_exists(file_path(folder, note["file"])):
			write(folder, note["file"], note["text"])
	return true


static func exists(folder: String) -> bool:
	return DirAccess.dir_exists_absolute(notes_path(folder))


## Every note file: {file, title, manuscript (bool), size (bytes)}. The standard notes first (in STANDARD order), then the
## manuscript files in act order, then any other note by name.
static func list_files(folder: String) -> Array[Dictionary]:
	var found: Dictionary = {}
	for file_name in DirAccess.get_files_at(notes_path(folder)):
		if is_valid_file_name(file_name):
			found[file_name] = true
	var result: Array[Dictionary] = []
	for note in STANDARD:
		if found.has(note["file"]):
			result.append(_entry(folder, note["file"], note["title"]))
			found.erase(note["file"])
	var manuscripts: Array[String] = []
	var others: Array[String] = []
	for file_name: String in found:
		if is_manuscript(file_name):
			manuscripts.append(file_name)
		else:
			others.append(file_name)
	manuscripts.sort()
	others.sort()
	for file_name in manuscripts:
		result.append(_entry(folder, file_name, "Manuscript - act %s" % file_name.trim_prefix(MANUSCRIPT_PREFIX).get_basename().lstrip("0")))
	for file_name in others:
		result.append(_entry(folder, file_name, file_name.get_basename()))
	return result


static func _entry(folder: String, file_name: String, title: String) -> Dictionary:
	var size := 0
	var handle := FileAccess.open(file_path(folder, file_name), FileAccess.READ)
	if handle != null:
		size = handle.get_length()
		handle.close()
	return {"file": file_name, "title": title, "manuscript": is_manuscript(file_name), "size": size}


## "" when the file doesn't exist, is not a valid note name, or is too big.
static func read(folder: String, file_name: String) -> String:
	if not is_valid_file_name(file_name):
		return ""
	var handle := FileAccess.open(file_path(folder, file_name), FileAccess.READ)
	if handle == null or handle.get_length() > MAX_FILE_BYTES:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


## Writes a note. Refused (false) for a release, an invalid name or an oversized text.
static func write(folder: String, file_name: String, text: String) -> bool:
	if CampaignIO.is_release(folder) or not is_valid_file_name(file_name) or text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return false
	if DirAccess.make_dir_recursive_absolute(notes_path(folder)) != OK:
		return false
	var handle := FileAccess.open(file_path(folder, file_name), FileAccess.WRITE)
	if handle == null:
		return false
	handle.store_string(text)
	handle.close()
	return true


## The text split at `## ` headings: [{title, body, start_line, fingerprint}]. Text before the first heading is the preamble (title
## ""). `#` and `###` lines are ordinary text. The body is without its heading line.
static func sections(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var title := ""
	var body: Array[String] = []
	var start := 0
	var line_number := 0
	var in_heading := false  # false while still in the preamble
	for line in text.split("\n"):
		if line.begins_with("## "):
			if in_heading or "\n".join(body).strip_edges() != "":
				result.append(_section(title, body, start))
			title = line.substr(3).strip_edges()
			body = []
			start = line_number
			in_heading = true
		else:
			body.append(line)
		line_number += 1
	if in_heading or "\n".join(body).strip_edges() != "":
		result.append(_section(title, body, start))
	return result


static func _section(title: String, body: Array[String], start_line: int) -> Dictionary:
	var joined := "\n".join(body).strip_edges()
	return {"title": title, "body": joined, "start_line": start_line, "fingerprint": fingerprint(joined)}


## A short fingerprint of a text that ignores layout (runs of whitespace count as one space), so re-wrapping or trailing spaces
## don't look like a change. Used to notice that a manuscript section changed since a chapter was made from it.
static func fingerprint(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\s+")
	var normalized := regex.sub(text.strip_edges(), " ", true)
	return normalized.sha256_text().substr(0, 16)
