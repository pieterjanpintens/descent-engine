class_name QuestCard
extends Control

## The campaign map's card for a chapter or side quest, in the game's style (StoryCard): title, orange subtitle ("Main Quest"), the story
## before the mission (scrolls when long), a few extra lines (reward, warnings, playtest buttons) and one orange button at the bottom
## ("Prepare"). A fixed size, centred over the map; clicking outside it or Esc closes it. CampaignPlayer fills it (fill()) and opens it.

signal closed

const CARD_WIDTH := 360.0
const CARD_HEIGHT := 440.0  ## at most; never more than CARD_SCREEN_SHARE of the window
const CARD_SCREEN_SHARE := 0.88

var has_content := false
var _card: Control
var _content: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.35)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var built := StoryCard.build(8)
	_card = built["root"]
	_content = built["content"]
	add_child(_card)
	get_viewport().size_changed.connect(_place)


func _gui_input(event: InputEvent) -> void:
	# a click on the scrim (outside the card - the card itself stops its own clicks) closes it
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Fills the card. `extras`: controls shown between the story and the button. `action_text` "" = no button.
func fill(title: String, subtitle: String, story: String, extras: Array[Control], action_text: String, action_enabled: bool, on_action: Callable) -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_content.add_child(StoryCard.title(title))
	if subtitle != "":
		_content.add_child(StoryCard.subtitle(subtitle))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var story_label := StoryCard.text(story)
	story_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(story_label)
	_content.add_child(scroll)
	for extra in extras:
		_content.add_child(extra)
	if action_text != "":
		var holder := CenterContainer.new()
		var action := StoryCard.button(action_text, Vector2(110, StoryCard.BUTTON_HEIGHT + 2), StoryCard.BUTTON_FONT + 1, StoryCard.BUTTON_ART_SCALE)
		action.disabled = not action_enabled
		action.pressed.connect(on_action)
		holder.add_child(action)
		_content.add_child(holder)
	has_content = true
	_place()


func clear() -> void:
	has_content = false


func open() -> void:
	if not has_content:
		return
	_place()
	visible = true
	move_to_front()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _place() -> void:
	if _card == null:
		return
	var screen := get_viewport_rect().size
	var card_size := Vector2(CARD_WIDTH, minf(CARD_HEIGHT, screen.y * CARD_SCREEN_SHARE))
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.custom_minimum_size = card_size
	_card.size = card_size
	_card.position = (screen - card_size) / 2.0
