class_name CommandInput
extends LineEdit

## A small text box for typing commands ("attack green bandit"). It stands in
## for the microphone while voice control is an experiment: the same text
## will later come from speech-to-text, so everything downstream
## (VoiceCommandParser -> PlayerCommandRunner) is identical. Emits the text on
## Enter and clears itself.
##
## Hidden by default (new 2026-09-23, "it's more of a debug thing") - Tab
## toggles it, both showing+focusing and hiding+unfocusing. Caught in
## _input(), NOT _unhandled_input() - claude.md's own Hard-won lessons
## already flags Tab as ui_focus_next, consumed by Godot's GUI focus system
## before an _unhandled_input() handler would ever see it once real Controls
## exist in the scene (which this one now shares with plenty). _input() runs
## BEFORE that GUI dispatch, so calling set_input_as_handled() there actually
## pre-empts it - and works regardless of this control's own visibility,
## unlike _gui_input(), which only real Controls that are visible/hit-testable
## ever receive.

signal command_entered(text: String)


func _ready() -> void:
	placeholder_text = "Command, e.g. attack green bandit"
	custom_minimum_size = Vector2(320, 0)
	# Centered under the portrait dock, below the mic status line (see
	# VoiceListener.gd) - moved here from bottom-left 2026-09-23, "for now"
	# (a placeholder spot, not a final call on where this belongs).
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)  # top center, right below the mic status line
	offset_left = -160.0
	offset_right = 160.0
	offset_top = 62.0
	offset_bottom = 94.0
	visible = false
	text_submitted.connect(_on_submitted)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		visible = not visible
		if visible:
			grab_focus()
		else:
			release_focus()
		get_viewport().set_input_as_handled()


func _on_submitted(submitted: String) -> void:
	clear()
	release_focus()
	visible = false  # back out of the way until Tab is pressed again
	command_entered.emit(submitted)
