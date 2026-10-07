class_name NarrativeStep
extends Resource

## One screen of a narrative chapter: some story `text` and, optionally, a `question` the table answers by
## picking one of the `answers`. Without answers it is a plain page to read.

@export_multiline var text: String = ""
@export var question: String = ""
## The step is only shown while all of these hold (implicit AND, over the campaign's variables, counting the answers
## already given in this story); empty = always.
@export var conditions: Array[Condition] = []
@export var answers: Array[NarrativeAnswer] = []
