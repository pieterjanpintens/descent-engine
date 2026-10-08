class_name NarrationHighlight
extends RefCounted

## Editor helpers for story text with character tags (NarrationMarkup): colors each character's tagged
## parts in a TextEdit with that character's color, and gives a legend whose buttons wrap the selected
## text (or an empty pair of tags at the caret) in a character's tag. Never instantiated.


## Colors the parts of `edit` that belong to a character (`[Name]...[/Name]`) in that character's color.
static func apply(edit: TextEdit, characters: Array[NarratorCharacter]) -> void:
	var highlighter := NarrationSyntaxHighlighter.new()
	highlighter.characters = characters
	edit.syntax_highlighter = highlighter


## A row of buttons, one per character, in the character's color. They work on whichever of `edits` had the
## focus last (the first one before any).
static func legend(edits: Array[TextEdit], characters: Array[NarratorCharacter]) -> Control:
	var row := HFlowContainer.new()
	var target := [edits[0]]
	for edit in edits:
		edit.focus_entered.connect(func(): target[0] = edit)
	var label := Label.new()
	label.text = "Voices:"
	row.add_child(label)
	var speakers: Array[NarratorCharacter] = characters.duplicate()
	for hero in HeroCatalog.hero_characters():
		speakers.append(hero)
	for character in speakers:
		var button := Button.new()
		button.text = character.character_name
		button.add_theme_color_override("font_color", character.color)
		button.add_theme_color_override("font_hover_color", character.color)
		button.tooltip_text = "Select text and click to give it to %s (or click to insert the tags at the caret)." % character.character_name
		button.pressed.connect(func(): wrap_selection(target[0], character.character_name))
		row.add_child(button)
	return row


static func wrap_selection(edit: TextEdit, character_name: String) -> void:
	var selected := edit.get_selected_text()
	if selected != "":
		edit.delete_selection()
	edit.insert_text_at_caret("[%s]%s[/%s]" % [character_name, selected, character_name])
	if selected == "":
		edit.set_caret_column(edit.get_caret_column() - character_name.length() - 3)
	edit.grab_focus()
