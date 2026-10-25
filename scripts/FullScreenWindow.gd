class_name FullScreenWindow
extends RefCounted

## Makes a big editor Window cover the whole game window, like NarrativeWindow does: no title bar (so it
## cannot be dragged around - give it its own Close button), not resizable, and it follows the game window
## when that changes size. Used by the Objectives, Actions and Triggers editors.


static func show(window: Window) -> void:
	window.borderless = true
	window.unresizable = true
	var root := window.get_tree().root
	if not window.has_meta("full_screen_hooked"):
		window.set_meta("full_screen_hooked", true)
		root.size_changed.connect(func():
			if is_instance_valid(window) and window.visible:
				window.position = Vector2i.ZERO
				window.size = screen_size(window)
		)
	window.popup(Rect2i(Vector2i.ZERO, screen_size(window)))


## The game window's size in the units embedded windows use (with the canvas_items stretch mode this is NOT the pixel size).
static func screen_size(window: Window) -> Vector2i:
	return Vector2i(window.get_tree().root.get_visible_rect().size)


## Ctrl/Cmd+Z and Ctrl/Cmd+Shift+Z while an editor window has the keyboard (the Creator's own shortcut never sees keys
## that go to another window). Call from the window's _unhandled_key_input(); text boxes keep their own undo because
## they consume the key first. Returns true when it undid/redid something.
static func handle_undo_key(event: InputEvent, history: OperationHistory) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or history == null:
		return false
	if key.keycode != KEY_Z or not key.is_command_or_control_pressed():
		return false
	if key.shift_pressed:
		history.redo()
	else:
		history.undo()
	return true


## A top row with the editor's title on the left and a Close button on the right.
static func header(title_text: String, on_close: Callable) -> Control:
	var row := HBoxContainer.new()
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(on_close)
	row.add_child(close)
	return row
