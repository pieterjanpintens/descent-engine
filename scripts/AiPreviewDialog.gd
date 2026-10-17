class_name AiPreviewDialog
extends AcceptDialog

## Shows what the AI wrote before anything changes: the original next to the result (the result can still be edited), a
## warning when the answer broke a rule (AiAssist.tag_problem()), and Apply / Try again / Discard. Nothing is ever applied
## without the author pressing Apply. Built in code by AiAssist.

signal applied(text: String)
signal retry_requested

var _warning: Label
var _original_box: VBoxContainer
var _original_label: Label
var _original: TextEdit
var _result_label: Label
var _result: TextEdit
var _error_label: Label


func _ready() -> void:
	title = "AI suggestion"
	min_size = Vector2i(560, 360)
	ok_button_text = "Apply"
	add_button("Try again", false, "retry")
	add_cancel_button("Discard")
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	add_child(box)
	_error_label = Label.new()
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.custom_minimum_size.x = 520  # a wrapping label needs a width, or its first layout counts every letter as a line
	_error_label.visible = false
	box.add_child(_error_label)
	_warning = Label.new()
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.custom_minimum_size.x = 520
	_warning.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	_warning.visible = false
	box.add_child(_warning)
	_original_box = VBoxContainer.new()
	box.add_child(_original_box)
	_original_label = Label.new()
	_original_box.add_child(_original_label)
	_original = _text_box(80)
	_original.editable = false
	_original_box.add_child(_original)
	_result_label = Label.new()
	box.add_child(_result_label)
	_result = _text_box(120)
	box.add_child(_result)
	confirmed.connect(func(): applied.emit(_result.text))
	custom_action.connect(func(action: StringName):
		if action == &"retry":
			hide()
			retry_requested.emit()
	)


func _text_box(height: float) -> TextEdit:
	var edit := TextEdit.new()
	edit.custom_minimum_size.y = height  # a small minimum: the boxes grow when there is room, so the buttons always fit on screen
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	return edit


## `append` = the result is new text that goes after the existing text (Continue the story) instead of replacing it.
func show_result(original: String, result: String, warning: String, append: bool) -> void:
	_error_label.visible = false
	_warning.text = warning
	_warning.visible = warning != ""
	_original_box.visible = true
	_original_label.text = "Your text (stays as it is):" if append else "Your text:"
	_result_label.visible = true
	_result_label.text = "The AI wrote (you can edit it before applying), added after your text:" if append else "The AI wrote (you can edit it before applying), replacing your text:"
	_result.visible = true
	get_ok_button().visible = true
	get_ok_button().disabled = false
	# The texts go in AFTER the dialog has its size: a long text set while the boxes are still laid out at no width counts every
	# word as its own line and blows the dialog up to several screens tall (the buttons end up far below the screen).
	_original.text = ""
	_result.text = ""
	popup_centered_clamped(Vector2i(780, 560), 0.9)  # never bigger than 90% of the game window (its units, see NarrativeWindow)
	await get_tree().process_frame
	_original.text = original
	_result.text = result


## Something went wrong - only the message and Try again / Discard.
func show_error(message: String) -> void:
	_warning.visible = false
	_original_box.visible = false
	_result_label.visible = false
	_result.visible = false
	_error_label.text = message
	_error_label.visible = true
	get_ok_button().visible = false
	popup_centered_clamped(Vector2i(560, 200), 0.9)
