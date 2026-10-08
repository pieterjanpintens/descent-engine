class_name SpellUnderline
extends Control

## A transparent overlay child of a story TextEdit that draws a red wavy underline under every misspelled word
## (SpellChecker). A Godot syntax highlighter can only colour text, not underline it, so the squiggles are drawn here:
## the word's characters are located with TextEdit.get_rect_at_line_column() (so wrapped words get one squiggle per
## visual line) and the overlay redraws when the text, the scroll position or the size changes.

const COLOR := Color(1.0, 0.3, 0.3)
const WAVE_STEP := 3.0
const WAVE_HEIGHT := 1.5

var _edit: TextEdit
var _characters: Array[NarratorCharacter]


func setup(edit: TextEdit, characters: Array[NarratorCharacter]) -> void:
	_edit = edit
	_characters = characters
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	edit.add_child(self)
	edit.text_changed.connect(queue_redraw)
	edit.resized.connect(queue_redraw)
	edit.get_v_scroll_bar().value_changed.connect(func(_value: float): queue_redraw())
	edit.set_meta("spell_underline", self)


func _draw() -> void:
	if _edit == null:
		return
	var names := SpellChecker.names_set(_characters)
	var last := mini(_edit.get_last_full_visible_line() + 1, _edit.get_line_count() - 1)
	for line in range(_edit.get_first_visible_line(), last + 1):
		var text := _edit.get_line(line)
		for span in SpellChecker.misspelled_ranges(text, names):
			_underline(line, span.x, span.y)


## One squiggle per visual row the word covers.
func _underline(line: int, start: int, end: int) -> void:
	var row_y := -1
	var x0 := 0.0
	var x1 := 0.0
	var bottom := 0.0
	for column in range(start, end):
		var rect := _edit.get_rect_at_line_column(line, column)
		if rect.position.x < 0 or rect.position.y < 0:
			continue  # outside the visible area
		if rect.position.y != row_y:
			if row_y != -1:
				_squiggle(x0, x1, bottom)
			row_y = rect.position.y
			x0 = rect.position.x
			bottom = rect.position.y + rect.size.y - 2.0
		x1 = rect.position.x + rect.size.x
	if row_y != -1:
		_squiggle(x0, x1, bottom)


func _squiggle(x0: float, x1: float, y: float) -> void:
	var points := PackedVector2Array()
	var x := x0
	var up := false
	while x < x1:
		points.append(Vector2(x, y - WAVE_HEIGHT if up else y))
		x += WAVE_STEP
		up = not up
	points.append(Vector2(x1, y))
	if points.size() >= 2:
		draw_polyline(points, COLOR, 1.5)
