class_name AiAssist
extends Node

## Optional AI writing help on a story text box: a small "AI" menu in the corner of the TextEdit (only there when AI help is
## switched on and a key is set - see AiClient.is_configured()). An action sends the selected text (or the whole box) to the
## author's own AI account, then shows the answer in AiPreviewDialog; only Apply changes the text, as ONE undo step. Nothing
## is sent unless an action is chosen. Attached with `AiAssist.attach()` next to NarrationHighlight.apply(); the node is a child
## of the text box, so it lives and dies with it.

const ACTIONS := [
	{"id": "fix", "label": "Fix spelling and grammar", "instruction": "Correct the spelling, grammar and punctuation. Change nothing else - keep the words, the style and the meaning."},
	{"id": "improve", "label": "Improve the writing", "instruction": "Improve the writing: clearer, more vivid, with the same meaning, facts and about the same length."},
	{"id": "shorter", "label": "Make it shorter", "instruction": "Make the text shorter. Keep every important fact and the tone."},
	{"id": "dramatic", "label": "Make it more dramatic", "instruction": "Rewrite the text more dramatically and atmospherically, keeping the meaning and every fact."},
	{"id": "continue", "label": "Continue the story", "instruction": "Write the next one or two short paragraphs that continue this text. Reply with ONLY the new text, not the existing text.", "append": true},
	{"id": "custom", "label": "Do something else…"},
]
const MAX_TEXT_LENGTH := 12000
const MAX_TOKENS := 1500

var edit: TextEdit
## Returns a short description of where this text sits (campaign, chapter, the question being answered...). Optional.
var context: Callable
var characters: Array[NarratorCharacter] = []

var _client: AiClient
var _row: HBoxContainer
var _menu_button: MenuButton
var _cancel_button: Button
var _dialog: AiPreviewDialog
var _custom_dialog: ConfirmationDialog
var _custom_edit: LineEdit
## What the running action works on: {instruction, append, original, whole, from_line, from_col, to_line, to_col}.
var _job: Dictionary = {}


## Adds the help to `edit`. Returns the helper (nothing needs it; tests do).
static func attach(target: TextEdit, context_provider: Callable = Callable(), speakers: Array[NarratorCharacter] = []) -> AiAssist:
	var assist := AiAssist.new()
	assist.edit = target
	assist.context = context_provider
	assist.characters = speakers
	target.add_child(assist)
	return assist


func _ready() -> void:
	_client = AiClient.new()
	add_child(_client)
	_row = HBoxContainer.new()
	# Pinned to the top-right corner of the text box. Anchors set by hand (the box has no size yet when this runs), and the row is
	# added deferred: the box may itself still be setting up its children (it is attached before it enters the tree), and a
	# parent that is busy refuses add_child().
	_row.anchor_left = 1.0
	_row.anchor_right = 1.0
	_row.anchor_top = 0.0
	_row.anchor_bottom = 0.0
	_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_row.offset_left = -4.0
	_row.offset_right = -4.0
	_row.offset_top = 2.0
	edit.add_child.call_deferred(_row)
	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.visible = false
	_cancel_button.pressed.connect(func(): _client.cancel())
	_row.add_child(_cancel_button)
	_menu_button = MenuButton.new()
	_menu_button.text = "AI"
	_menu_button.flat = true
	_menu_button.tooltip_text = "AI writing help (optional) - your text is only sent when you choose an action."
	var popup := _menu_button.get_popup()
	for i in ACTIONS.size():
		popup.add_item(ACTIONS[i]["label"], i)
	popup.id_pressed.connect(_on_action_chosen)
	_row.add_child(_menu_button)
	_dialog = AiPreviewDialog.new()
	add_child(_dialog)
	_dialog.applied.connect(_apply)
	_dialog.retry_requested.connect(func():
		if not _job.is_empty():
			_run_job()
		else:
			_unlock()
	)
	_dialog.canceled.connect(_unlock)
	_custom_dialog = ConfirmationDialog.new()
	_custom_dialog.title = "Ask the AI"
	_custom_dialog.ok_button_text = "Go"
	_custom_edit = LineEdit.new()
	_custom_edit.placeholder_text = "e.g. Make the guard sound more suspicious"
	_custom_edit.custom_minimum_size.x = 420
	_custom_dialog.add_child(_custom_edit)
	_custom_dialog.confirmed.connect(func():
		if _custom_edit.text.strip_edges() != "":
			_start(_custom_edit.text.strip_edges(), false)
	)
	add_child(_custom_dialog)
	edit.visibility_changed.connect(_refresh)
	edit.focus_entered.connect(_refresh)
	_refresh()


## The button only exists for authors who switched AI help on.
func _refresh() -> void:
	_row.visible = AiClient.is_configured()


func _on_action_chosen(index: int) -> void:
	var action: Dictionary = ACTIONS[index]
	if action["id"] == "custom":
		_custom_edit.text = ""
		_custom_dialog.popup_centered()
		_custom_edit.grab_focus()
		return
	_start(str(action["instruction"]), bool(action.get("append", false)))


func _start(instruction: String, append: bool) -> void:
	if _client.is_busy() or not AiClient.is_configured():
		return
	var selected := edit.has_selection()
	var original := edit.get_selected_text() if selected else edit.text
	if original.strip_edges() == "" and not append:
		_dialog.show_error("There is no text yet - write something first.")
		return
	if original.length() > MAX_TEXT_LENGTH:
		_dialog.show_error("The text is too long to send (%d characters; the limit is %d). Select a part of it instead." % [original.length(), MAX_TEXT_LENGTH])
		return
	_job = {
		"instruction": instruction, "append": append, "original": original, "whole": not selected,
		"from_line": edit.get_selection_from_line() if selected else 0, "from_col": edit.get_selection_from_column() if selected else 0,
		"to_line": edit.get_selection_to_line() if selected else 0, "to_col": edit.get_selection_to_column() if selected else 0,
	}
	_run_job()


func _run_job() -> void:
	edit.editable = false  # the text must not change while the answer is on its way
	_menu_button.disabled = true
	_cancel_button.visible = true
	var where: String = str(context.call()) if context.is_valid() else ""
	var answer := await _client.ask(system_prompt(), user_prompt(_job["instruction"], _job["original"], where, _character_names()), MAX_TOKENS)
	if not is_instance_valid(edit):
		return
	_cancel_button.visible = false
	_menu_button.disabled = false
	if answer["cancelled"]:
		_unlock()
		return
	if not answer["ok"]:
		_dialog.show_error(str(answer["error"]))
		return
	var result := clean_answer(str(answer["text"]))
	_dialog.show_result(_job["original"], result, tag_problem(_job["original"], result, _job["append"]), _job["append"])


func _unlock() -> void:
	if is_instance_valid(edit):
		edit.editable = true
		_menu_button.disabled = false
		_cancel_button.visible = false


## Puts the (possibly edited) result into the text box as one undo step.
func _apply(result: String) -> void:
	edit.editable = true
	edit.begin_complex_operation()
	if _job["append"]:
		var last := edit.get_line_count() - 1
		edit.set_caret_line(last)
		edit.set_caret_column(edit.get_line(last).length())
		edit.insert_text_at_caret(("\n\n" if edit.text.strip_edges() != "" else "") + result)
	elif _job["whole"]:
		var last_line := edit.get_line_count() - 1
		edit.select(0, 0, last_line, edit.get_line(last_line).length())
		edit.insert_text_at_caret(result)
	else:
		edit.select(_job["from_line"], _job["from_col"], _job["to_line"], _job["to_col"])
		edit.insert_text_at_caret(result)
	edit.end_complex_operation()
	_job = {}


func _character_names() -> Array[String]:
	var names: Array[String] = []
	for character in characters:
		names.append(character.character_name)
	for hero in HeroCatalog.hero_characters():
		names.append(hero.character_name)
	return names


# ---------------------------------------------------------------- prompts and checks

static func system_prompt() -> String:
	return "You are a writing assistant for the author of a fantasy adventure campaign for a digital tabletop companion app. " \
		+ "The text you get is story text shown to the players and sometimes read aloud by a narrator. Rules: " \
		+ "keep the author's meaning, voice and language; " \
		+ "keep every character tag such as [Name]...[/Name] exactly as it is, with the same names - words inside a tag are spoken by that character; " \
		+ "text in (round brackets) is an acting hint for the reader and must be kept; " \
		+ "do not add headings, markdown, quotation marks around the whole answer, notes or explanations. " \
		+ "Reply with the resulting text only."


static func user_prompt(instruction: String, text: String, where: String, character_names: Array[String]) -> String:
	var parts: Array[String] = []
	if where.strip_edges() != "":
		parts.append("Where this text is used:\n" + where.strip_edges())
	if not character_names.is_empty():
		parts.append("Characters that can be tagged: " + ", ".join(character_names))
	parts.append("What to do:\n" + instruction)
	parts.append("The text:\n<<<\n%s\n>>>" % text)
	return "\n\n".join(parts)


## Removes what models like to add around an answer: a code fence, or quotation marks around the whole text.
static func clean_answer(text: String) -> String:
	var cleaned := text.strip_edges()
	if cleaned.begins_with("```"):
		var lines := cleaned.split("\n")
		lines.remove_at(0)
		if lines.size() > 0 and lines[lines.size() - 1].strip_edges() == "```":
			lines.remove_at(lines.size() - 1)
		cleaned = "\n".join(lines).strip_edges()
	if cleaned.length() >= 2 and cleaned.begins_with("\"") and cleaned.ends_with("\"") and cleaned.count("\"") == 2:
		cleaned = cleaned.substr(1, cleaned.length() - 2).strip_edges()
	return cleaned


## "" when the answer is fine; otherwise what is wrong with its character tags. A replacement must use the same tags as the
## original; new text that continues a story may only use tags that exist (checked against the original by name only when it
## had tags - an empty original gives no reference).
static func tag_problem(original: String, result: String, append: bool) -> String:
	var before := NarrationMarkup.tag_names(original)
	var after := NarrationMarkup.tag_names(result)
	if append:
		return ""
	before.sort()
	after.sort()
	if before == after:
		return ""
	return "The character tags changed (before: %s; now: %s). Check who speaks which words before applying." % [
		", ".join(before) if not before.is_empty() else "none", ", ".join(after) if not after.is_empty() else "none"]
