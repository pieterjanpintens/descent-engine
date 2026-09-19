class_name PlayerDialog
extends Control

## Reusable dialog for the Player scene - pops up centered near the top of
## the screen (matches the original companion app's own prompt style) for
## the interaction patterns Player phase needs: confirming an instruction
## (OK), walking through narrative text (OK/NEXT/BACK), asking a yes/no
## question the table answers honestly (the app never sees real board
## state - see claude.md's Story layer section, "if they lie they ruin
## their own game"), or asking for a rolled/counted number.
##
## Built at runtime in _build_ui() rather than hand-authored in a .tscn -
## same reasoning as CreatorPalette: content and buttons change per call,
## nothing here would be static scene content anyway.
##
## Modal while visible: the root Control covers the full screen (a dim
## scrim, mouse_filter STOP - same STOP-blocks-everything-behind-it
## mechanism CreatorPalette's background bug worked through earlier this
## session, deliberately relied on here instead of worked around) so
## nothing else - camera look/zoom, the End Phase/Back buttons, the world -
## is reachable until the dialog is answered. The actual visible box (text
## + buttons) is a child positioned center-top within that full-rect root,
## not the root itself.
##
## Usage (all async - caller awaits the result):
##   await dialog.ask_ok("Place your figures in the highlighted area.")
##   await dialog.ask_ok("Bandit is hit!", true, true)  # large: fills most of the screen
##   var yes: bool = await dialog.ask_yes_no("Is a player on tile 2a?")
##   var n: int = await dialog.ask_count("How many successes did you roll?")
##   await dialog.ask_narrative(["Page one text...", "Page two text..."])
##   var i: int = await dialog.ask_choice("Do what?", ["Pick fruit", "Climb"])  # -1 = Cancel

const PANEL_WIDTH := 480.0
const LARGE_MARGIN := 80.0  ## ask_ok(..., large = true): gap to every screen edge
const LARGE_FONT_SIZE := 28

signal _closed(result: Variant)

var _label: Label
var _button_row: HBoxContainer
var _count_input: SpinBox

var _narrative_pages: Array[String] = []
var _narrative_index: int = 0


func _ready() -> void:
	_build_ui()
	visible = false


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # the modal scrim - blocks everything behind it

	_scrim = ColorRect.new()
	var scrim := _scrim
	scrim.color = Color(0, 0, 0, 0.35)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE  # self (the root) already blocks; this is purely visual
	add_child(scrim)

	_panel = Control.new()
	var panel := _panel
	add_child(panel)
	_apply_panel_layout(false)

	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(background)

	var vbox := VBoxContainer.new()
	background.add_child(vbox)

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_label)

	_count_input = SpinBox.new()
	_count_input.min_value = 0
	_count_input.max_value = 99
	_count_input.visible = false
	_count_input.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_count_input)

	_button_row = HBoxContainer.new()
	_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_button_row)


## The dim overlay behind the box - `ask_ok(text, false)` hides it so the
## scene behind stays fully visible (used to show monster miniatures on the
## map while telling the table where to put them). Reset to visible at the
## end of every dimless ask.
var _scrim: ColorRect


## The box holding the text + buttons; re-laid-out by _apply_panel_layout().
var _panel: Control


## Normal: a 480px box centered near the top. Large: fills most of the
## screen (margins on every side), with bigger, vertically centered text -
## used for moments that deserve the table's full attention (a hit).
func _apply_panel_layout(large: bool) -> void:
	if large:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_panel.custom_minimum_size = Vector2.ZERO
		_panel.offset_left = LARGE_MARGIN
		_panel.offset_right = -LARGE_MARGIN
		_panel.offset_top = LARGE_MARGIN
		_panel.offset_bottom = -LARGE_MARGIN
	else:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
		_panel.offset_left = -PANEL_WIDTH / 2.0
		_panel.offset_right = PANEL_WIDTH / 2.0
		_panel.offset_top = 16.0
		_panel.offset_bottom = 0.0
	if _label == null:  # first call, from _build_ui(), before the label exists
		return
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL if large else Control.SIZE_FILL
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if large else VERTICAL_ALIGNMENT_TOP
	if large:
		_label.add_theme_font_size_override("font_size", LARGE_FONT_SIZE)
	else:
		_label.remove_theme_font_size_override("font_size")


func ask_ok(text: String, dim: bool = true, large: bool = false) -> void:
	_scrim.visible = dim
	_apply_panel_layout(large)
	_label.text = text
	_count_input.visible = false
	_set_buttons([{"text": "OK", "result": null}])
	visible = true
	await _closed
	visible = false
	_scrim.visible = true
	if large:
		_apply_panel_layout(false)


func ask_yes_no(text: String) -> bool:
	_label.text = text
	_count_input.visible = false
	_set_buttons([{"text": "Yes", "result": true}, {"text": "No", "result": false}])
	visible = true
	var result: bool = await _closed
	visible = false
	return result


func ask_count(text: String, min_value: int = 0, max_value: int = 99) -> int:
	_label.text = text
	_count_input.min_value = min_value
	_count_input.max_value = max_value
	_count_input.value = min_value
	_count_input.visible = true
	_set_buttons([{"text": "OK", "result": null}])  # actual answer is read from _count_input below
	visible = true
	await _closed
	visible = false
	return int(_count_input.value)


## Offers `option_labels` as buttons (one per entry, in order - result is
## that entry's index) plus a trailing "Cancel" button (result -1) -
## Cancel is always present, never omitted, so the caller never has to
## build its own "and let them back out" affordance. Used by
## PlayerInteractionController's action picker (new 2026-09-14 - "which
## of this prop's currently-available actions do you mean?").
## `option_disabled` (new 2026-09-14, e.g. an exhausted single_shot
## PropAction - see MissionRuntime.available_actions()/PropAction's own
## doc) greys out that option's button rather than omitting it, so the
## player can see it exists but can no longer be chosen. Defaults to all
## enabled - a shorter (or empty) array than option_labels just leaves the
## remaining ones enabled.
func ask_choice(text: String, option_labels: Array[String], option_disabled: Array[bool] = []) -> int:
	_label.text = text
	_count_input.visible = false
	var specs: Array = []
	for i in option_labels.size():
		var disabled: bool = option_disabled[i] if i < option_disabled.size() else false
		specs.append({"text": option_labels[i], "result": i, "disabled": disabled})
	specs.append({"text": "Cancel", "result": -1})
	_set_buttons(specs)
	visible = true
	var result: int = await _closed
	visible = false
	return result


func ask_narrative(pages: Array[String]) -> void:
	_narrative_pages = pages
	_narrative_index = 0
	_count_input.visible = false
	_show_narrative_page()
	visible = true
	await _closed
	visible = false


func _show_narrative_page() -> void:
	_label.text = _narrative_pages[_narrative_index]
	var specs: Array = []
	if _narrative_index > 0:
		specs.append({"text": "Back", "result": "_back"})
	if _narrative_index < _narrative_pages.size() - 1:
		specs.append({"text": "Next", "result": "_next"})
	else:
		specs.append({"text": "OK", "result": null})
	_set_buttons(specs)


func _set_buttons(specs: Array) -> void:
	for child in _button_row.get_children():
		child.queue_free()
	for spec in specs:
		var btn := Button.new()
		btn.text = spec["text"]
		btn.disabled = spec.get("disabled", false)
		btn.pressed.connect(_on_button_pressed.bind(spec["result"]))
		_button_row.add_child(btn)


## "_next"/"_back" are internal sentinels for ask_narrative() - they advance
## the page and rebuild buttons instead of resolving the await, unlike
## every other result value (null/true/false/int - ask_choice()'s option
## indices/-1 for Cancel), which closes the dialog. The typeof() guard is
## required, not just style: GDScript's `==` throws "Invalid operands
## 'int' and 'String'" (a runtime error, not a false result) when compared
## against an incompatible Variant type pair like int vs String - which
## ask_choice()'s int results hit the moment they reached the bare
## `result == "_next"` check below, since every button (regardless of
## which ask_*() call made it) funnels through this one handler.
func _on_button_pressed(result: Variant) -> void:
	if typeof(result) == TYPE_STRING:
		if result == "_next":
			_narrative_index += 1
			_show_narrative_page()
			return
		if result == "_back":
			_narrative_index -= 1
			_show_narrative_page()
			return
	_closed.emit(result)
