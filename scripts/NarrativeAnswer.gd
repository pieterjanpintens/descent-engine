class_name NarrativeAnswer
extends Resource

## One possible answer to the question of a narrative step. Choosing it applies `effects` to the campaign's
## variables (Set Variable / Math - that is how an answer ends up in the campaign) and shows `reply` if there is one.

@export var text: String = "New answer"
@export_multiline var reply: String = ""
@export var effects: Array[Effect] = []
## The answer is only offered while all of these hold (empty = always).
@export var conditions: Array[Condition] = []
## Choosing it ends the story: every step after it is skipped.
@export var ends_narrative: bool = false
