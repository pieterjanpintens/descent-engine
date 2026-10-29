class_name TextWalker
extends RefCounted

## Finds every authored text of a campaign or mission - every `<name>_texts` language map (see LText) on the resource and on everything it holds -
## by reflection, so a new text field needs no change here. An entry is {map (the Dictionary itself, edited in place), owner, property, path (a stable
## key like "acts/0/chapters/2/title", used by the CSV files), label (what a person reads: "Act: The road > Chapter: Arrival > Story before"), multiline}.
## The functions below work on such a list: which languages exist, how complete one is, adding / removing / renaming / copying a language.

const SUFFIX := "_texts"
const DESCRIBING := ["title", "act_name", "campaign_name", "mission_name", "text", "description", "question", "message"]
const MAX_SEGMENT := 38
const NICE_NAMES := {"MissionData": "Mission", "InteractableEntry": "Prop", "PropAction": "Action", "CampaignSideQuest": "Side quest", "MissionObjective": "Objective", "MonsterTemplate": "Monster"}
const MULTILINE_FIELDS := ["intro", "story_before", "story_after", "text", "reply", "description", "defeat_text", "message", "loot_text", "own_hint", "own_activation", "question"]


static func collect(root: Resource) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if root != null:
		_walk(root, "", [], {}, entries)
	return entries


static func _walk(resource: Resource, path: String, segments: Array, visited: Dictionary, entries: Array[Dictionary]) -> void:
	if visited.has(resource.get_instance_id()):
		return
	visited[resource.get_instance_id()] = true
	if _is_library_data(resource):
		return
	var own_segments := segments + [_describe(resource)]
	for property in resource.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var name: String = property["name"]
		var value: Variant = resource.get(name)
		match typeof(value):
			TYPE_DICTIONARY:
				if name.ends_with(SUFFIX):
					var field := name.trim_suffix(SUFFIX)
					entries.append({
						"map": value, "owner": resource, "property": name, "path": _join(path, field),
						"label": " › ".join(own_segments + [field.capitalize().replace("_", " ")]),
						"multiline": MULTILINE_FIELDS.has(field),
					})
			TYPE_OBJECT:
				if value is Resource and not (value is Script):
					_walk(value, _join(path, name), own_segments, visited, entries)
			TYPE_ARRAY:
				var items: Array = value
				if items.is_empty() or not (items[0] is Resource):
					continue
				for index in items.size():
					if items[index] is Resource:
						_walk(items[index], _join(path, "%s/%d" % [name, index]), own_segments, visited, entries)


## Monster templates (MonsterArchetype) are copies from the shared template library and are translated there, once, not per mission.
static func _is_library_data(resource: Resource) -> bool:
	var script := resource.get_script() as Script
	return script != null and str(script.get_global_name()) == "MonsterArchetype"


static func _join(path: String, part: String) -> String:
	return part if path == "" else path + "/" + part


## A short name of a resource for the label ("Chapter: Arrival", "Step", "Answer").
static func _describe(resource: Resource) -> String:
	var script := resource.get_script() as Script
	var kind: String = str(script.get_global_name()) if script != null else resource.get_class()
	var shown := ""
	for property in DESCRIBING:
		var maybe: Variant = resource.get(property + SUFFIX)
		if typeof(maybe) == TYPE_DICTIONARY:
			shown = LText.pick(maybe).strip_edges().replace("\n", " ")
			if shown != "":
				break
	if shown == "":
		for property in ["reference_name", "mesh_item_name", "id"]:
			var plain: Variant = resource.get(property)
			if typeof(plain) == TYPE_STRING and str(plain) != "":
				shown = str(plain)
				break
	if shown.length() > MAX_SEGMENT:
		shown = shown.substr(0, MAX_SEGMENT - 1) + "…"
	var nice: String = NICE_NAMES.get(kind, kind.replace("Campaign", "").replace("Narrative", "").capitalize())
	if nice == "":
		nice = "Campaign"
	return "%s: %s" % [nice, shown] if shown != "" else nice


## The languages a campaign or mission has: its default first, then the ones it declares, then any that have texts, in the order of CampaignInfo.LANGUAGES.
static func content_languages(root: Resource, entries: Array[Dictionary]) -> Array[String]:
	var wanted: Array[String] = [str(root.get("default_language"))]
	var declared: Variant = root.get("languages")
	if typeof(declared) == TYPE_ARRAY:
		for code: Variant in declared:
			wanted.append(str(code))
	wanted.append_array(languages_used(entries))
	var result: Array[String] = []
	var rest: Array[String] = []
	for code in wanted:
		if not result.has(code) and not rest.has(code):
			rest.append(code)
	result.append(wanted[0])
	for language in CampaignInfo.LANGUAGES:
		if language["code"] != wanted[0] and rest.has(language["code"]):
			result.append(language["code"])
	for code in rest:
		if not result.has(code):
			result.append(code)
	return result


## Only the entries that have any text in any language: an empty map is a field nobody filled in, nothing to translate.
static func with_text(entries: Array[Dictionary]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry in entries:
		if not LText.languages_in(entry["map"]).is_empty() or _has_other_text(entry["map"]):
			found.append(entry)
	return found


static func _has_other_text(map: Dictionary) -> bool:
	for code in map:
		if str(map[code]) != "":
			return true
	return false


## Every language code that has a text somewhere, in the order of CampaignInfo.LANGUAGES (unknown codes last).
static func languages_used(entries: Array[Dictionary]) -> Array[String]:
	var seen := {}
	for entry in entries:
		for code in entry["map"]:
			if str(entry["map"][code]) != "":
				seen[str(code)] = true
	var ordered: Array[String] = []
	for language in CampaignInfo.LANGUAGES:
		if seen.has(language["code"]):
			ordered.append(language["code"])
			seen.erase(language["code"])
	for code in seen:
		ordered.append(code)
	return ordered


## {done, total}: of the entries that have a text at all, how many have one in `language`.
static func completeness(entries: Array[Dictionary], language: String) -> Dictionary:
	var done := 0
	var total := 0
	for entry in with_text(entries):
		total += 1
		if str(entry["map"].get(language, "")) != "":
			done += 1
	return {"done": done, "total": total}


## The entries that have a text but none in `language`.
static func missing(entries: Array[Dictionary], language: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry in with_text(entries):
		if str(entry["map"].get(language, "")) == "":
			found.append(entry)
	return found


static func remove_language(entries: Array[Dictionary], code: String) -> int:
	var removed := 0
	for entry in entries:
		if entry["map"].has(code):
			entry["map"].erase(code)
			removed += 1
	return removed


## Moves the texts of `from` to `to` (an entry that already has a `to` text keeps it); for content that was filed under the wrong language.
static func rename_language(entries: Array[Dictionary], from: String, to: String) -> int:
	var moved := 0
	for entry in entries:
		var map: Dictionary = entry["map"]
		if not map.has(from):
			continue
		if str(map.get(to, "")) == "":
			map[to] = map[from]
		map.erase(from)
		moved += 1
	return moved


## Fills the entries that have no `to` text with the `from` text (a starting point to translate from); returns how many.
static func copy_missing(entries: Array[Dictionary], from: String, to: String) -> int:
	var copied := 0
	for entry in entries:
		var map: Dictionary = entry["map"]
		if str(map.get(to, "")) == "" and str(map.get(from, "")) != "":
			map[to] = map[from]
			copied += 1
	return copied


# ---------------------------------------------------------------- CSV (for translators working outside the game)

## One row per text: key, label, then a column per language in `languages`. Quoted per RFC 4180; texts keep their line breaks and spaces.
static func to_csv(entries: Array[Dictionary], languages: Array[String]) -> String:
	var lines: Array[String] = []
	var header: Array = ["key", "label"]
	header.append_array(languages)
	lines.append(_csv_line(header))
	for entry in with_text(entries):
		var row: Array = [entry["path"], entry["label"]]
		for code in languages:
			row.append(str(entry["map"].get(code, "")))
		lines.append(_csv_line(row))
	return "\r\n".join(lines) + "\r\n"


static func _csv_line(cells: Array) -> String:
	var parts: Array[String] = []
	for cell in cells:
		parts.append("\"" + str(cell).replace("\"", "\"\"") + "\"")
	return ",".join(parts)


## Reads CSV text made by to_csv() (any column order after key and label; extra columns for languages are added) and puts the texts of the
## listed language columns into the entries with the same key. Empty cells change nothing. Returns {updated, unknown_keys, languages}.
static func from_csv(text: String, entries: Array[Dictionary]) -> Dictionary:
	var rows := _parse_csv(text)
	var result := {"updated": 0, "unknown_keys": 0, "languages": [] as Array[String]}
	if rows.size() < 2:
		return result
	var header: Array = rows[0]
	var by_key := {}
	for entry in entries:
		by_key[entry["path"]] = entry
	var columns := {}
	for index in range(2, header.size()):
		var code := str(header[index]).strip_edges().to_lower()
		if CampaignInfo.is_known(code):
			columns[index] = code
			if not result["languages"].has(code):
				result["languages"].append(code)
	for r in range(1, rows.size()):
		var row: Array = rows[r]
		if row.is_empty() or not by_key.has(str(row[0])):
			if not row.is_empty() and str(row[0]) != "":
				result["unknown_keys"] += 1
			continue
		var map: Dictionary = by_key[str(row[0])]["map"]
		for index in columns:
			if index < row.size() and str(row[index]) != "" and str(map.get(columns[index], "")) != str(row[index]):
				map[columns[index]] = str(row[index])
				result["updated"] += 1
	return result


static func _parse_csv(text: String) -> Array:
	var rows: Array = []
	var row: Array = []
	var cell := ""
	var quoted := false
	var i := 0
	var n := text.length()
	while i < n:
		var c := text[i]
		if quoted:
			if c == "\"":
				if i + 1 < n and text[i + 1] == "\"":
					cell += "\""
					i += 1
				else:
					quoted = false
			else:
				cell += c
		elif c == "\"":
			quoted = true
		elif c == ",":
			row.append(cell)
			cell = ""
		elif c == "\n" or c == "\r":
			if c == "\r" and i + 1 < n and text[i + 1] == "\n":
				i += 1
			row.append(cell)
			cell = ""
			if not (row.size() == 1 and str(row[0]) == ""):
				rows.append(row)
			row = []
		else:
			cell += c
		i += 1
	if cell != "" or not row.is_empty():
		row.append(cell)
		rows.append(row)
	return rows
