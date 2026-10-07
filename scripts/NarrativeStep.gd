class_name NarrativeStep
extends Resource

## One screen of a narrative chapter: some story `text` and, optionally, a `question` the table answers by
## picking one of the `answers`. Without answers it is a plain page to read.

@export_multiline var text: String = ""
@export var question: String = ""
@export var answers: Array[NarrativeAnswer] = []
