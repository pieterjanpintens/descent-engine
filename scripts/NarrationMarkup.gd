class_name NarrationMarkup
extends RefCounted

## Story text can hand parts of itself to characters: `He said [Donal]"Take the key."[/Donal] and left.`
## The tag name is a NarratorCharacter's name (exact spelling and case); only the tags of KNOWN characters count,
## any other square bracket stays plain text. Untagged text belongs to the story teller. Never instantiated.

## Pieces in reading order: {"speaker": NarratorCharacter (null = the story teller), "text": String}.
static func segments(text: String, characters: Array[NarratorCharacter]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var regex := RegEx.new()
	regex.compile("(?s)\\[([^\\[\\]/]+)\\](.*?)\\[/\\1\\]")
	var cursor := 0
	for match in regex.search_all(text):
		var speaker := _find(match.get_string(1), characters)
		if speaker == null:
			continue
		_add(found, null, text.substr(cursor, match.get_start() - cursor))
		_add(found, speaker, match.get_string(2))
		cursor = match.get_end()
	_add(found, null, text.substr(cursor))
	return found


## The text without the tags of known characters - what is shown.
static func plain(text: String, characters: Array[NarratorCharacter]) -> String:
	if not text.contains("["):
		return text
	var parts := PackedStringArray()
	var cursor := 0
	var regex := RegEx.new()
	regex.compile("(?s)\\[([^\\[\\]/]+)\\](.*?)\\[/\\1\\]")
	for match in regex.search_all(text):
		if _find(match.get_string(1), characters) == null:
			continue
		parts.append(text.substr(cursor, match.get_start() - cursor))
		parts.append(match.get_string(2))
		cursor = match.get_end()
	parts.append(text.substr(cursor))
	return "".join(parts)


static func _find(character_name: String, characters: Array[NarratorCharacter]) -> NarratorCharacter:
	for character in characters:
		if character.character_name == character_name:
			return character
	return null


static func _add(into: Array[Dictionary], speaker: NarratorCharacter, text: String) -> void:
	if text.strip_edges() != "":
		into.append({"speaker": speaker, "text": text})
