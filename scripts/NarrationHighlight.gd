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
	_add_spelling_menu(edit, characters)
	SpellUnderline.new().setup(edit, characters)


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


# ---------------------------------------------------------------- spelling

const MENU_SUGGESTION := 1000
const MENU_ADD_WORD := 1100


## Misspelled words are red (NarrationSyntaxHighlighter); the text box's right-click menu gets the word under the
## caret's corrections and "Add to dictionary".
static func _add_spelling_menu(edit: TextEdit, characters: Array[NarratorCharacter]) -> void:
	var menu := edit.get_menu()
	var state := {"added": 0, "word": {}, "suggestions": [] as Array[String]}
	menu.about_to_popup.connect(func():
		for _i in state["added"]:
			if menu.item_count > 0:
				menu.remove_item(menu.item_count - 1)
		state["added"] = 0
		var found := SpellChecker.misspelled_at(edit.get_line(edit.get_caret_line()), edit.get_caret_column(), SpellChecker.names_set(characters))
		state["word"] = found
		if found.is_empty():
			return
		var options := SpellChecker.suggestions(found["word"])
		state["suggestions"] = options
		menu.add_separator()
		state["added"] += 1
		for i in options.size():
			menu.add_item(options[i], MENU_SUGGESTION + i)
			state["added"] += 1
		if options.is_empty():
			menu.add_item("(no suggestions)", MENU_SUGGESTION + 99)
			menu.set_item_disabled(menu.item_count - 1, true)
			state["added"] += 1
		menu.add_item("Add \"%s\" to the dictionary" % found["word"], MENU_ADD_WORD)
		state["added"] += 1
	)
	menu.id_pressed.connect(func(id: int):
		var found: Dictionary = state["word"]
		if found.is_empty():
			return
		var line := edit.get_caret_line()
		if id >= MENU_SUGGESTION and id < MENU_SUGGESTION + 99:
			var options: Array[String] = state["suggestions"]
			edit.begin_complex_operation()
			edit.select(line, found["start"], line, found["end"])
			edit.insert_text_at_caret(options[id - MENU_SUGGESTION])
			edit.end_complex_operation()
		elif id == MENU_ADD_WORD:
			SpellChecker.add_word(found["word"])
			if edit.has_meta("spell_underline"):
				edit.get_meta("spell_underline").queue_redraw()
		state["word"] = {}
	)
