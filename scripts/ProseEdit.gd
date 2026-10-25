class_name ProseEdit
extends RefCounted

## A roomy, wrapping multi-line text box for text the table READS (a prop action's description, a
## Show Message effect) instead of a one-line field: spell check + [Character] colours, the optional AI help
## and dictation, like the story boxes of the campaign editor. Static builder, nothing to keep.
##
## `on_commit(new_text)` is called half a second after typing stops (also after an AI or dictation edit)
## and straight away when the box loses focus - the caller wraps it in its undo step. Enter makes a new line.

const COMMIT_DELAY_SEC := 0.5


static func build(text: String, placeholder: String, min_size: Vector2, characters: Array[NarratorCharacter], context: Callable, on_commit: Callable) -> TextEdit:
	var edit := TextEdit.new()
	edit.custom_minimum_size = min_size
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.text = text
	edit.placeholder_text = placeholder
	NarrationHighlight.apply(edit, characters)
	AiAssist.attach(edit, context, characters)  # only visible when AI help is switched on in Options
	SpeechDictation.attach(edit, characters)  # only visible when voice is set up (Options > Voice)

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = COMMIT_DELAY_SEC
	edit.add_child(timer)
	var committed := [text]
	var flush := func():
		timer.stop()
		if edit.text != committed[0]:
			committed[0] = edit.text
			on_commit.call(edit.text)
	timer.timeout.connect(flush)
	edit.text_changed.connect(func(): timer.start())
	edit.focus_exited.connect(flush)
	return edit
