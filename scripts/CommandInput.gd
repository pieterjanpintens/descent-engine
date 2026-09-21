class_name CommandInput
extends LineEdit

## A small text box for typing commands ("attack green bandit"). It stands in
## for the microphone while voice control is an experiment: the same text
## will later come from speech-to-text, so everything downstream
## (VoiceCommandParser -> PlayerCommandRunner) is identical. Emits the text on
## Enter and clears itself.

signal command_entered(text: String)


func _ready() -> void:
	placeholder_text = "Command, e.g. attack green bandit"
	custom_minimum_size = Vector2(320, 0)
	# Bottom-left, clear of the portrait dock in the bottom centre.
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 12.0
	offset_right = 12.0 + 320.0
	offset_top = -44.0
	offset_bottom = -12.0
	text_submitted.connect(_on_submitted)


func _on_submitted(submitted: String) -> void:
	clear()
	release_focus()
	command_entered.emit(submitted)
