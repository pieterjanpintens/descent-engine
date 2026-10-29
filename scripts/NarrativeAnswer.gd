class_name NarrativeAnswer
extends Resource

## One possible answer to the question of a narrative step. Choosing it applies `effects` to the campaign's
## variables (Set Variable / Math - that is how an answer ends up in the campaign) and shows `reply` if there is one.

@export var text_texts: Dictionary = {"en": "New answer"}
var text: String:
	get:
		return LText.pick(text_texts)
	set(value):
		LText.put(text_texts, value)
@export var reply_texts: Dictionary = {}
var reply: String:
	get:
		return LText.pick(reply_texts)
	set(value):
		LText.put(reply_texts, value)
@export var effects: Array[Effect] = []
## The answer is only offered while all of these hold (empty = always).
@export var conditions: Array[Condition] = []
## Choosing it ends the story: every step after it is skipped.
@export var ends_narrative: bool = false
## Choosing it continues with the step that has this id instead of the next one ("" = the next one) - branching. Ignored
## when `ends_narrative` is set.
@export var goto_step_id: String = ""
