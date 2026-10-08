class_name NarrationSyntaxHighlighter
extends SyntaxHighlighter

## Colors the parts of a story text that belong to a character - everything between `[Name]` and `[/Name]`,
## the tags included - in that character's color (see NarrationMarkup for the syntax). CodeHighlighter's color
## regions can't do this (their keys must be pure symbols), so the line is scanned here. A tag may span lines,
## so the state at the start of a line is found by scanning the lines before it (story texts are short).
## Only the tags of known characters count; other brackets stay plain.

var characters: Array[NarratorCharacter] = []


func _get_line_syntax_highlighting(line: int) -> Dictionary:
	var edit := get_text_edit()
	var plain: Color = edit.get_theme_color("font_color")
	var open: NarratorCharacter = null
	for i in line:
		open = _scan(edit.get_line(i), open, plain).get("open", open)
	return _scan(edit.get_line(line), open, plain)["colors"]


## Scans one line starting inside `open` (null = outside any tag): the column -> {"color"} map and the state at the end of the line.
func _scan(text: String, open: NarratorCharacter, plain: Color) -> Dictionary:
	var colors := {0: {"color": open.color if open != null else plain}}
	var column := 0
	while column < text.length():
		var bracket := text.find("[", column)
		if bracket == -1:
			break
		var close := text.find("]", bracket)
		if close == -1:
			break
		var tag := text.substr(bracket + 1, close - bracket - 1)
		if open == null:
			var character := _find(tag)
			if character != null:
				open = character
				colors[bracket] = {"color": character.color}
		elif tag == "/" + open.character_name:
			open = null
			colors[close + 1] = {"color": plain}
		column = close + 1
	return {"colors": colors, "open": open}


func _find(character_name: String) -> NarratorCharacter:
	for character in characters:
		if character.character_name == character_name:
			return character
	return null
