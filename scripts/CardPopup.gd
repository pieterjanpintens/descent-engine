class_name CardPopup
extends Control

## A modal popup in the story card style (StoryCard), the default dialog of the campaign and mission player in place of Godot's
## AcceptDialog / ConfirmationDialog: an optional title, a body (a text, or any Control) that SCROLLS when it is taller than the room on
## the screen, and a row of orange buttons. Esc or a click outside the card closes it with `dismiss_result` ("" = not dismissable).
##
##   popup.open(tr("Mission won"), text)                                   # OK
##   popup.open("", tr("Delete this save?"), [[tr("Cancel"), "cancel"], [tr("Delete"), "ok"]])
##   var result: String = await popup.closed
##
## A Control body stays a child of the popup until the next open() / clear_body(), so a caller can rebuild its contents while it is
## open (then call refit()).

signal closed(result: String)

const DEFAULT_WIDTH := 460.0
const MAX_HEIGHT_SHARE := 0.86  ## the card never gets taller than this part of the window: the body scrolls instead

var dismiss_result := "ok"
var _card: Control
var _content: VBoxContainer
var _title: Label
var _scroll: ScrollContainer
var _button_row: HBoxContainer
var _body: Control
var _owns_body := false  ## the body is our own text label (freed when replaced), not the caller's Control
var _width := DEFAULT_WIDTH


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.4)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var built := StoryCard.build(8)
	_card = built["root"]
	_content = built["content"]
	center.add_child(_card)
	_title = StoryCard.title("")
	_content.add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(_scroll)
	_button_row = HBoxContainer.new()
	_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_row.add_theme_constant_override("separation", 12)
	_content.add_child(_button_row)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and dismiss_result != "":
		_close(dismiss_result)  # a click outside the card (the card stops its own clicks)
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if visible and dismiss_result != "" and event.is_action_pressed("ui_cancel"):
		_close(dismiss_result)
		get_viewport().set_input_as_handled()


## `body`: a String (shown as wrapping text) or a Control. `buttons`: [[label, result], ...]. `width`: the card's width.
## `own_body`: a Control body is freed when it is replaced (a list built only for this popup).
func open(title: String, body: Variant, buttons: Array = [], width: float = DEFAULT_WIDTH, dismiss: String = "ok", own_body: bool = false) -> void:
	if not is_node_ready():
		await ready
	_width = width
	dismiss_result = dismiss
	_title.text = title
	_title.visible = title != ""
	clear_body()
	if body is Control:
		_body = body
		_owns_body = own_body
		if _body.get_parent() != null:
			_body.get_parent().remove_child(_body)
	else:
		var label := StoryCard.text(str(body), 15)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_body = label
		_owns_body = true
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	for child in _button_row.get_children():
		_button_row.remove_child(child)
		child.queue_free()
	if buttons.is_empty():
		buttons = [[tr("OK"), "ok"]]
	for spec in buttons:
		var button := StoryCard.dialog_button(str(spec[0]))
		var result := str(spec[1])
		button.pressed.connect(func(): _close(result))
		_button_row.add_child(button)
	visible = true
	move_to_front()
	refit()


## Takes the body out (a Control body is not freed: it belongs to the caller).
func clear_body() -> void:
	if _body != null and is_instance_valid(_body) and _body.get_parent() == _scroll:
		_scroll.remove_child(_body)
		if _owns_body:
			_body.queue_free()
	_body = null
	_owns_body = false


## Sizes the card to its body, up to MAX_HEIGHT_SHARE of the window (the body scrolls beyond that). Call again after changing a Control
## body while the popup is open.
func refit() -> void:
	_card.custom_minimum_size = Vector2(_width, 0)
	_scroll.custom_minimum_size = Vector2(0, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	if _body == null or not is_instance_valid(_body):
		return
	var others := _card.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	var room := get_viewport_rect().size.y * MAX_HEIGHT_SHARE - others
	_scroll.custom_minimum_size.y = clampf(_body.get_combined_minimum_size().y, 20.0, maxf(room, 80.0))


## Closes it as if `result` was chosen.
func close(result: String = "") -> void:
	_close(result if result != "" else dismiss_result)


func _close(result: String) -> void:
	if not visible:
		return
	visible = false
	closed.emit(result)
