class_name TutorialHighlight
extends Control

## A pulsing frame around the controls the current tutorial step is about. Never takes the mouse: everything under it stays usable.
## `rects_provider` returns the screen rectangles to frame, asked every frame (controls move, tabs switch, windows resize).

const COLOR := Color(1.0, 0.78, 0.25)

var rects_provider: Callable
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if not rects_provider.is_valid():
		return
	var pulse := 0.55 + 0.45 * sin(_time * 4.5)
	for rect: Rect2 in rects_provider.call():
		var frame := rect.grow(3.0)
		draw_rect(frame, Color(COLOR.r, COLOR.g, COLOR.b, 0.10 * pulse), true)
		draw_rect(frame, Color(COLOR.r, COLOR.g, COLOR.b, 0.35 + 0.65 * pulse), false, 3.0)
