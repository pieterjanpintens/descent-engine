class_name NarrativeStep
extends Resource

## One screen of a narrative chapter: some story `text` and, optionally, a `question` the table answers by
## picking one of the `answers`. Without answers it is a plain page to read.

## Stable identity (CampaignChapter.new_step_id()) - what an answer's "go to step" points at, so reordering or deleting steps
## never retargets it.
@export var id: String = ""
@export var text_texts: Dictionary = {}
var text: String:
	get:
		return LText.pick(text_texts)
	set(value):
		LText.put(text_texts, value)
@export var question_texts: Dictionary = {}
var question: String:
	get:
		return LText.pick(question_texts)
	set(value):
		LText.put(question_texts, value)
## The step is only shown while all of these hold (implicit AND, over the campaign's variables, counting the answers
## already given in this story); empty = always.
@export var conditions: Array[Condition] = []
@export var answers: Array[NarrativeAnswer] = []
