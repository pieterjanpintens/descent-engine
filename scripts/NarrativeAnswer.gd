class_name NarrativeAnswer
extends Resource

## One possible answer to the question of a narrative step. Choosing it applies `effects` to the campaign's
## variables (Set Variable / Math - that is how an answer ends up in the campaign) and shows `reply` if there is one.

@export var text: String = "New answer"
@export_multiline var reply: String = ""
@export var effects: Array[Effect] = []
