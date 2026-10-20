class_name SpeechDictation
extends Node

## A "Dictate" button in the corner of a story text box: click it, speak, click again, and what you said is typed into the box at the
## caret (replacing a selection). It uses the same Whisper setup as the Player's voice control (Options > Voice) through the shared
## DictationEngine; the button is only there when that is set up. Attached with `SpeechDictation.attach()` next to AiAssist.attach();
## the node is a child of the text box, so it lives and dies with it.

const IDLE_TEXT := "Dictate"
const RECORDING_TEXT := "● Stop"
const THINKING_TEXT := "Thinking…"

var edit: TextEdit
## Names that Whisper should be able to spell (a campaign's characters), optional.
var characters: Array[NarratorCharacter] = []

var _button: Button
var _status: Label
var _hide_status: Timer


static func attach(target: TextEdit, speakers: Array[NarratorCharacter] = []) -> SpeechDictation:
	var dictation := SpeechDictation.new()
	dictation.edit = target
	dictation.characters = speakers
	target.add_child(dictation)
	return dictation


func _ready() -> void:
	var row := TextBoxCorner.row(edit)
	_status = Label.new()
	_status.visible = false
	_status.add_theme_font_size_override("font_size", 12)
	_status.modulate = Color(1.0, 0.75, 0.55)
	row.add_child(_status)
	_button = Button.new()
	_button.text = IDLE_TEXT
	_button.flat = true
	_button.tooltip_text = "Dictate: click, speak, click again - the text is typed in at the cursor. Needs voice set up (Options > Voice)."
	_button.pressed.connect(_on_pressed)
	row.add_child(_button)
	row.move_child(_status, 0)
	row.move_child(_button, 1)  # leftmost of the helper buttons
	_hide_status = Timer.new()
	_hide_status.one_shot = true
	_hide_status.wait_time = 6.0
	_hide_status.timeout.connect(func(): _status.visible = false)
	add_child(_hide_status)
	var engine := DictationEngine.instance()
	engine.finished.connect(_on_finished)
	engine.state_changed.connect(_refresh)
	edit.visibility_changed.connect(_refresh)
	edit.focus_entered.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	var engine := DictationEngine.instance()
	if engine.current_owner == self and engine.state == DictationEngine.State.RECORDING:
		engine.cancel()


## Text for Whisper's initial prompt: a sentence (never a bare list - Whisper echoes lists back) that names the characters.
func whisper_prompt() -> String:
	var prompt := "A fantasy adventure story, with dialogue."
	var names: Array[String] = []
	for character in characters:
		if character.name != "":
			names.append(character.name)
	if not names.is_empty():
		prompt += " The characters are %s." % ", ".join(names.slice(0, 12))
	return prompt


func _refresh() -> void:
	var engine := DictationEngine.instance()
	_button.visible = engine.is_available() and edit.editable
	var mine := engine.current_owner == self
	match engine.state:
		DictationEngine.State.RECORDING:
			_button.text = RECORDING_TEXT if mine else IDLE_TEXT
			_button.disabled = not mine
			_button.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35) if mine else Color.WHITE)
		DictationEngine.State.THINKING:
			_button.text = THINKING_TEXT if mine else IDLE_TEXT
			_button.disabled = true
			_button.remove_theme_color_override("font_color")
		_:
			_button.text = IDLE_TEXT
			_button.disabled = false
			_button.remove_theme_color_override("font_color")


func _on_pressed() -> void:
	var engine := DictationEngine.instance()
	if engine.state == DictationEngine.State.RECORDING and engine.current_owner == self:
		engine.stop(whisper_prompt())
		return
	var result := engine.start(self)
	if not result["ok"]:
		_show_status(str(result["reason"]))
		return
	edit.grab_focus()
	_status.visible = false


func _on_finished(requester: Object, text: String, error: String) -> void:
	if requester != self:
		return
	if text == "":
		if error != "":
			_show_status(error)
		return
	_insert(text)


## Types `text` at the caret (over a selection) as ONE undo step, with a space before it when the words would otherwise run together.
func _insert(text: String) -> void:
	if not edit.editable:
		return
	edit.begin_complex_operation()
	if edit.has_selection():
		edit.delete_selection()
	var line := edit.get_caret_line()
	var column := edit.get_caret_column()
	var piece := text.strip_edges()
	if column > 0:
		var before := edit.get_line(line).substr(column - 1, 1)
		if before != " " and before != "	":
			piece = " " + piece  # don't glue the new words to the one before
	edit.insert_text_at_caret(piece)
	edit.end_complex_operation()
	_show_status("Added %d words" % piece.split(" ", false).size())


func _show_status(message: String) -> void:
	_status.text = message
	_status.visible = true
	_hide_status.start()
