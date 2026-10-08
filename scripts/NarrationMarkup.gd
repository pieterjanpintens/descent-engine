class_name NarrationMarkup
extends RefCounted

## Story text can hand parts of itself to characters: `He said [Donal]"Take the key."[/Donal] and left.`
## The tag name is a NarratorCharacter's name (exact spelling and case). Every matching pair of tags is stripped from
## what is shown; a pair whose name is no character's is a throwaway character - the Narrator gives it a voice of its
## own, chosen from its name.
## A square bracket without a matching closing tag stays plain text. Untagged text belongs to the story teller.
## Never instantiated.

## Pieces in reading order: {"speaker": NarratorCharacter (null = the story teller or an undefined name), "name": the tag name
## ("" for untagged text), "text": String}.
static func segments(text: String, characters: Array[NarratorCharacter]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var regex := RegEx.new()
	regex.compile("(?s)\\[([^\\[\\]/]+)\\](.*?)\\[/\\1\\]")
	var cursor := 0
	for match in regex.search_all(text):
		_add(found, null, "", text.substr(cursor, match.get_start() - cursor))
		_add(found, _find(match.get_string(1), characters), match.get_string(1), match.get_string(2))
		cursor = match.get_end()
	_add(found, null, "", text.substr(cursor))
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
		parts.append(text.substr(cursor, match.get_start() - cursor))
		parts.append(match.get_string(2))
		cursor = match.get_end()
	parts.append(text.substr(cursor))
	return "".join(parts)


## The names used in tags in `text` (each once, in order).
static func tag_names(text: String) -> Array[String]:
	var found: Array[String] = []
	var regex := RegEx.new()
	regex.compile("(?s)\\[([^\\[\\]/]+)\\](.*?)\\[/\\1\\]")
	for match in regex.search_all(text):
		var tag_name := match.get_string(1)
		if not found.has(tag_name):
			found.append(tag_name)
	return found


static func _find(character_name: String, characters: Array[NarratorCharacter]) -> NarratorCharacter:
	for character in characters:
		if character.character_name == character_name:
			return character
	return null


static func _add(into: Array[Dictionary], speaker: NarratorCharacter, tag_name: String, text: String) -> void:
	if text.strip_edges() != "":
		into.append({"speaker": speaker, "name": tag_name, "text": text})
