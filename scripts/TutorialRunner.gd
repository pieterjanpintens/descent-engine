class_name TutorialRunner
extends Node

## The in-editor tutorials (Help menu in the Creator). A tutorial is a list of steps in data/tutorials/<id>.json; the runner shows the
## current step in a small panel at the bottom left, frames the controls it is about, and tells when the step is done.
##
## DESIGN: a step is done when the MISSION reaches a state (TutorialChecks), not when one particular click happened - so people can do
## things in another order, undo, or already have it. Every step can have a "Do it for me" (TutorialAssists) that does it through the
## editor's own code, which also lets a test run a whole tutorial. Nothing here takes the mouse except the panel itself.
##
## Controls are found through `tutorial_target(id)` on the palette / toolbar / properties panel (stable ids, not node paths), so a
## rearranged UI does not silently break a tutorial.

## `finished` = the mission the tutorial builds (Peek plays it); `start` = the mission "Load the example" puts in the editor (a tutorial
## that continues another one starts from the other one's result).
const TUTORIALS: Array[Dictionary] = [
	{"id": "build_a_mission", "title": "Build a mission", "file": "res://data/tutorials/build_a_mission.json",
		"finished": "res://data/tutorials/finished_mission.tres", "start": ""},
	{"id": "fork", "title": "The fork: conditions, groups and surprises", "file": "res://data/tutorials/fork.json",
		"finished": "res://data/tutorials/finished_fork.tres", "start": "res://data/tutorials/finished_mission.tres"},
	{"id": "macros", "title": "Macros: shortcuts for common things", "file": "res://data/tutorials/macros.json",
		"finished": "res://data/tutorials/finished_macros.tres", "start": "res://data/tutorials/finished_fork.tres"},
	{"id": "own_macro", "title": "Your own macro: capture, reuse, manage", "file": "res://data/tutorials/own_macro.json",
		"finished": "res://data/tutorials/finished_own_macro.tres", "start": "res://data/tutorials/finished_macros.tres"},
]
const PROGRESS_FILE := "user://configuration/tutorial.cfg"
const PANEL_WIDTH := 410.0
const CHECK_SECONDS := 0.25
const MARGIN := Vector2(12.0, 44.0)  ## the default distance of the panel from the bottom left corner (44: above the status bar)
const ICON_SIZE := Vector2(104.0, 34.0)
const DRAG_SLOP := 4.0  ## the mouse may move this far on the little icon and it still counts as a click

var controller: CreatorController
var layered_map: LayeredMap
var history: OperationHistory
var save_load: CreatorSaveLoad
var camera: FreeLookCamera
var menu_bar: MenuBar
var side_panel: TabContainer
var palette: Control
var outline_tree: Control
var inspector: Control
var toolbar: Control
var viewport_spacer: Control

var _tutorial: Dictionary = {}
var _steps: Array = []
var _index := -1

var _events: Dictionary = {}  ## "op:Rotate" / "undo" / "redo" -> how often since the step began
var _camera_origin := Vector3.ZERO
var _camera_rotation := Quaternion.IDENTITY
var _done := false

var _canvas: CanvasLayer
var _highlight: TutorialHighlight
var _panel: PanelContainer
var _icon: Button  ## the small stand-in the panel shrinks to
var _running := false
var _collapsed := false
var _drag_offset := Vector2.ZERO  ## how far the user moved the panel from its default place (right, down)
var _dragging := false
var _drag_distance := 0.0
var _chapter_label: Label
var _title_label: Label
var _body: RichTextLabel
var _note_label: Label
var _status_label: Label
var _back_button: Button
var _next_button: Button
var _assist_button: Button
var _skip_button: Button
var _peek_button: Button
var _confirm: ConfirmationDialog
var _confirmed_action: Callable


func _ready() -> void:
	# The palette and the other panels build their UI one frame after they start - wait for them.
	await get_tree().process_frame
	await get_tree().process_frame
	_resolve()
	_build_ui()
	_load_ui()
	_apply_visibility()
	history.recorded.connect(func(label: String): _bump("op:" + label))
	history.undone.connect(func(): _bump("undo"))
	history.redone.connect(func(): _bump("redo"))
	var timer := Timer.new()
	timer.wait_time = CHECK_SECONDS
	timer.autostart = true
	timer.timeout.connect(_refresh_state)
	add_child(timer)
	_add_help_menu.call_deferred()
	if GameState.resume_tutorial != "":  # back from a peek at the finished mission: carry on where the user was
		var id := GameState.resume_tutorial
		GameState.resume_tutorial = ""
		start(id)


func _resolve() -> void:
	var root := get_parent()
	controller = root.get_node("CreatorController")
	layered_map = root.get_node("LayeredMap")
	camera = root.get_node("Camera3D")
	var main := root.get_node("CanvasLayer/MainLayout")
	menu_bar = main.get_node("MenuBar")
	history = menu_bar.get_node("Edit")
	save_load = menu_bar.get_node("File")
	toolbar = main.get_node("Toolbar")
	viewport_spacer = main.get_node("EditorArea/ViewportSpacer")
	side_panel = main.get_node("EditorArea/SidePanel")
	palette = side_panel.get_node("Palette")
	outline_tree = side_panel.get_node("Outline/Split/OutlineTree")
	inspector = side_panel.get_node("Outline/Split/Inspector")


# ---- Starting and stopping ----

func is_running() -> bool:
	return _running


## Starts the tutorial `id`: where the user stopped last time, or from the first step when `restart` (or nothing was stored).
func start(id: String = "build_a_mission", restart: bool = false) -> void:
	_tutorial = {}
	for tutorial in TUTORIALS:
		if tutorial["id"] == id:
			_tutorial = tutorial
	if _tutorial.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_tutorial["file"]))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("steps"):
		push_warning("TutorialRunner: %s could not be read" % _tutorial["file"])
		return
	_steps = parsed["steps"]
	var stored := 0 if restart else _stored_step(id)
	_running = true
	_apply_visibility()
	_go_to(clampi(stored, 0, _steps.size() - 1))


func stop() -> void:
	_running = false
	_apply_visibility()
	_highlight.visible = false


## The panel, or - shrunk - the small icon; neither when the tutorial is closed.
func _apply_visibility() -> void:
	_panel.visible = _running and not _collapsed
	_icon.visible = _running and _collapsed
	_update_icon()
	_place_controls()


func _set_collapsed(collapsed: bool) -> void:
	_collapsed = collapsed
	_apply_visibility()
	_store_ui()


func _update_icon() -> void:
	if _index >= 0 and not _steps.is_empty():
		_icon.text = "Tutorial %d/%d" % [_index + 1, _steps.size()]


## Panel and icon sit at the bottom left, moved by what the user dragged, and never leave the window (it can be smaller than last time,
## and each step has a different height).
func _place_controls() -> void:
	if _panel == null:
		return
	var view := _canvas.get_viewport().get_visible_rect().size
	var size := ICON_SIZE if _collapsed else Vector2(PANEL_WIDTH, _panel.size.y)
	_drag_offset.x = clampf(_drag_offset.x, -MARGIN.x, view.x - MARGIN.x - size.x)
	_drag_offset.y = clampf(_drag_offset.y, size.y + MARGIN.y - view.y, MARGIN.y)
	var left := MARGIN.x + _drag_offset.x
	var bottom := -MARGIN.y + _drag_offset.y
	_panel.offset_left = left
	_panel.offset_right = left + PANEL_WIDTH
	_panel.offset_bottom = bottom
	_icon.offset_left = left
	_icon.offset_right = left + ICON_SIZE.x
	_icon.offset_bottom = bottom
	_icon.offset_top = bottom - ICON_SIZE.y


## Dragging by the header of the panel or by the icon.
func _on_drag_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		if button.pressed:
			_drag_distance = 0.0
		else:
			_store_ui()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_drag_distance += motion.relative.length()
		_drag_offset += motion.relative
		_place_controls()


func _store_ui() -> void:
	var config := ConfigFile.new()
	config.load(PROGRESS_FILE)
	config.set_value("ui", "collapsed", _collapsed)
	config.set_value("ui", "offset_x", _drag_offset.x)
	config.set_value("ui", "offset_y", _drag_offset.y)
	DirAccess.make_dir_recursive_absolute(PROGRESS_FILE.get_base_dir())
	config.save(PROGRESS_FILE)


func _load_ui() -> void:
	var config := ConfigFile.new()
	if config.load(PROGRESS_FILE) != OK:
		return
	_collapsed = bool(config.get_value("ui", "collapsed", false))
	_drag_offset = Vector2(float(config.get_value("ui", "offset_x", 0.0)), float(config.get_value("ui", "offset_y", 0.0)))


func _finish() -> void:
	_store_step(_tutorial["id"], 0)
	stop()


func _stored_step(id: String) -> int:
	var config := ConfigFile.new()
	if config.load(PROGRESS_FILE) != OK:
		return 0
	return int(config.get_value("progress", id, 0))


func _store_step(id: String, index: int) -> void:
	var config := ConfigFile.new()
	config.load(PROGRESS_FILE)
	config.set_value("progress", id, index)
	DirAccess.make_dir_recursive_absolute(PROGRESS_FILE.get_base_dir())
	config.save(PROGRESS_FILE)


# ---- Steps ----

func _go_to(index: int) -> void:
	_index = index
	_update_icon()
	var step: Dictionary = _steps[index]
	_store_step(_tutorial["id"], index)
	_events.clear()
	_camera_origin = camera.global_position
	_camera_rotation = camera.global_transform.basis.get_rotation_quaternion()
	var tab: String = step.get("tab", "")
	if tab != "" and side_panel.has_node(tab):
		side_panel.current_tab = side_panel.get_tab_idx_from_control(side_panel.get_node(tab))

	_chapter_label.text = "%s  -  step %d of %d" % [step.get("chapter", ""), index + 1, _steps.size()]
	_title_label.text = step.get("title", "")
	_body.text = step.get("text", "")
	_note_label.text = ""
	_peek_button.visible = _tutorial.get("finished", "") != ""
	_assist_button.visible = step.has("assist")
	_assist_button.text = step.get("assist_label", "Do it for me")
	_back_button.disabled = index == 0
	_next_button.text = "Finish" if index == _steps.size() - 1 else "Next"
	_skip_button.visible = step.has("done") and index < _steps.size() - 1
	_highlight.visible = true
	_refresh_state()


func _refresh_state() -> void:
	if _panel == null or not _running or _index < 0:
		return
	_follow_window()
	_place_controls()
	var step: Dictionary = _steps[_index]
	var has_check := step.has("done")
	_done = has_check and TutorialChecks.check(step["done"], self)
	_status_label.text = "Done - click Next" if _done else ""
	_next_button.disabled = has_check and not _done


func _on_next() -> void:
	if _index >= _steps.size() - 1:
		_finish()
	else:
		_go_to(_index + 1)


func _on_assist() -> void:
	var step: Dictionary = _steps[_index]
	var message := TutorialAssists.run(step["assist"], self)
	_note_label.text = message
	_refresh_state.call_deferred()


# ---- What the checks look at ----

func _bump(event: String) -> void:
	_events[event] = int(_events.get(event, 0)) + 1


func event_count(event: String) -> int:
	return int(_events.get(event, 0))


func camera_turned_degrees() -> float:
	return rad_to_deg(_camera_rotation.angle_to(camera.global_transform.basis.get_rotation_quaternion()))


func camera_moved_distance() -> float:
	return camera.global_position.distance_to(_camera_origin)


# ---- Things the assists need ----

## File > New, asking first when there is unsaved work.
func start_empty_mission() -> void:
	if history.is_dirty():
		_ask("This replaces the mission you have open, and its unsaved changes are lost. Start a new, empty one?", save_load._on_new_button_pressed)
	else:
		save_load._on_new_button_pressed()


func _ask(text: String, action: Callable) -> void:
	_confirmed_action = action
	_confirm.dialog_text = text
	_confirm.popup_centered()


## Plays the mission being built, as it is now (the Play menu's Play).
func play() -> void:
	save_load.start_play("")


## Plays the finished mission of the running tutorial (or of tutorial `id`) in the Player (the editor's own mission is kept; Ctrl+E comes back).
func peek(id: String = "") -> void:
	var tutorial := _tutorial
	if id != "":
		for candidate in TUTORIALS:
			if candidate["id"] == id:
				tutorial = candidate
	var path: String = tutorial.get("finished", "")
	if path == "":
		return
	GameState.resume_tutorial = str(tutorial.get("id", "")) if is_running() else ""
	save_load.start_peek(path)


## Puts the running tutorial's example start mission in the editor (as an untitled mission), asking first when there is unsaved work.
func load_start_mission() -> void:
	var path: String = _tutorial.get("start", "")
	if path == "":
		return
	if history.is_dirty():
		_ask("This replaces the mission you have open, and its unsaved changes are lost. Load the example mission?", func(): save_load.load_example(path))
	else:
		save_load.load_example(path)


# ---- Highlights ----

func target_control(id: String) -> Control:
	if id.begins_with("button:"):
		return _find_button(id.substr(7))
	match id:
		"menu_bar":
			return menu_bar
		"viewport":
			return viewport_spacer
		"side_tabs":
			return side_panel.get_tab_bar()
		"outline_tree":
			return outline_tree
	for owner: Control in [palette, toolbar, inspector]:
		if owner.has_method("tutorial_target"):
			var found: Control = owner.tutorial_target(id)
			if found != null:
				return found
	return null


## A visible button anywhere in the editor (its windows included) by its text: how steps point into the editors' dialogs.
func _find_button(text: String) -> Button:
	for node in get_parent().find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == text and button.is_visible_in_tree():
			return button
	return null


## The panel and the frames live in the main window, or - while one of the big editor windows (Objectives, Actions, Triggers, templates)
## covers the whole game window - inside that window, so they stay visible on top of it.
func _follow_window() -> void:
	var screen := Vector2(get_tree().root.get_visible_rect().size)
	var host: Node = self
	for node in get_parent().find_children("*", "Window", true, false):
		var window := node as Window
		if window.visible and not window is Popup and Vector2(window.size).x >= screen.x * 0.9 and Vector2(window.size).y >= screen.y * 0.9:
			host = window
	if _canvas.get_parent() != host:
		_canvas.reparent(host, false)


func _highlight_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if _index < 0 or _index >= _steps.size():
		return rects
	for id: String in _steps[_index].get("highlight", []):
		var control := target_control(id)
		if control != null and control.is_visible_in_tree() and control.get_window() == _canvas.get_window():
			rects.append(control.get_global_rect())
	return rects


# ---- UI ----

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 20
	_canvas.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # the editors stay in English
	add_child(_canvas)

	_highlight = TutorialHighlight.new()
	_highlight.rects_provider = _highlight_rects
	_highlight.visible = false
	_canvas.add_child(_highlight)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.custom_minimum_size.x = PANEL_WIDTH
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 12.0
	_panel.offset_right = 12.0 + PANEL_WIDTH
	_panel.offset_bottom = -44.0  # above the status bar
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.17, 0.97)
	style.border_color = Color(1.0, 0.78, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	_canvas.add_child(_panel)

	_icon = Button.new()
	_icon.visible = false
	_icon.focus_mode = Control.FOCUS_NONE
	_icon.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_icon.tooltip_text = "Click to open the tutorial. Drag to move it."
	_icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var icon_style := style.duplicate() as StyleBoxFlat
	icon_style.set_content_margin_all(6)
	for state in ["normal", "hover", "pressed", "focus"]:
		_icon.add_theme_stylebox_override(state, icon_style)
	_icon.add_theme_color_override("font_color", Color(1.0, 0.78, 0.25))
	_icon.add_theme_font_size_override("font_size", 13)
	_icon.gui_input.connect(_on_drag_input)
	_icon.pressed.connect(func():
		if _drag_distance <= DRAG_SLOP:  # a drag ends with a release too, and is not a click
			_set_collapsed(false)
	)
	_canvas.add_child(_icon)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	_chapter_label = Label.new()
	_chapter_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chapter_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.25))
	_chapter_label.add_theme_font_size_override("font_size", 13)
	_chapter_label.mouse_filter = Control.MOUSE_FILTER_STOP  # the handle the panel is dragged by
	_chapter_label.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_chapter_label.tooltip_text = "Drag to move the tutorial."
	_chapter_label.gui_input.connect(_on_drag_input)
	header.add_child(_chapter_label)
	var shrink := _button("Shrink")
	shrink.tooltip_text = "Shrink the tutorial to a small icon (click the icon to open it again)."
	shrink.pressed.connect(func(): _set_collapsed(true))
	header.add_child(shrink)
	var close := _button("Close")
	close.tooltip_text = "Hide the tutorial. Help > Tutorial continues where you stopped."
	close.pressed.connect(stop)
	header.add_child(close)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 19)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.custom_minimum_size.x = PANEL_WIDTH - 24.0
	box.add_child(_title_label)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size.x = PANEL_WIDTH - 24.0
	box.add_child(_body)

	_note_label = Label.new()
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.custom_minimum_size.x = PANEL_WIDTH - 24.0
	_note_label.add_theme_color_override("font_color", Color(0.65, 0.8, 1.0))
	box.add_child(_note_label)
	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
	box.add_child(_status_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	_back_button = _button("Back")
	_back_button.pressed.connect(func(): _go_to(_index - 1))
	row.add_child(_back_button)
	_assist_button = _button("Do it for me")
	_assist_button.tooltip_text = "Does this step for you, the way you would have done it."
	_assist_button.pressed.connect(_on_assist)
	row.add_child(_assist_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_next_button = _button("Next")
	_next_button.pressed.connect(_on_next)
	row.add_child(_next_button)

	var row2 := HBoxContainer.new()
	box.add_child(row2)
	_skip_button = _button("Skip step")
	_skip_button.flat = true
	_skip_button.pressed.connect(func(): _go_to(_index + 1))
	row2.add_child(_skip_button)
	_peek_button = _button("Peek at the finished mission")
	_peek_button.flat = true
	_peek_button.tooltip_text = "Plays the finished tutorial mission. Your own mission is kept; Ctrl+E in the Player brings you back."
	_peek_button.pressed.connect(peek)
	row2.add_child(_peek_button)

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func(): _confirmed_action.call())
	add_child(_confirm)


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE  # keys like R, D and M still belong to the editor after a click here
	return button


## The "Help" menu in the menu bar: per tutorial the tutorial itself (continues where you stopped), starting it over, and a peek at what it builds.
func _add_help_menu() -> void:
	var menu := PopupMenu.new()
	menu.name = "Help"
	for i in TUTORIALS.size():
		var tutorial: Dictionary = TUTORIALS[i]
		if i > 0:
			menu.add_separator()
		menu.add_item("Tutorial %d: %s…" % [i + 1, tutorial["title"]], i * 3)
		menu.add_item("Start tutorial %d from the beginning" % (i + 1), i * 3 + 1)
		if tutorial.get("finished", "") != "":
			menu.add_item("Peek at the finished mission of tutorial %d" % (i + 1), i * 3 + 2)
	menu.id_pressed.connect(func(id: int):
		var tutorial: Dictionary = TUTORIALS[floori(id / 3.0)]
		match id % 3:
			0:
				start(tutorial["id"])
			1:
				start(tutorial["id"], true)
			2:
				peek(tutorial["id"])
	)
	menu_bar.add_child(menu)
