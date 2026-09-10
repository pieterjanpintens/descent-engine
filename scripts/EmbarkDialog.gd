class_name EmbarkDialog
extends Control

## Shown once after a mission loads, before round 1 - lets the table pick
## which of HeroCatalog's SLOT_COUNT (6) character slots are actually
## playing this session ("embark" = assembling the party before play
## starts, same idea the original game's own companion app does before a
## mission). This defines both the player COUNT (however many slots get
## selected) and which character maps to which player number - see
## claude.md's Story layer / Open items for what's deliberately not here
## yet: equipment selection ("for now we focus on adding players").
##
## Enforces the mission's own min_players/max_players (see MissionData) -
## once max_players are selected, every remaining UNselected slot greys out
## (disabled, not hidden - a mission allowing e.g. 2-4 players still shows
## all 6 characters, it just won't let you pick a 5th) until one gets
## deselected again; Start stays disabled below min_players.
##
## Built at runtime (same reasoning as CreatorPalette/PlayerDialog -
## content doesn't vary per call here, but the pattern stays consistent
## with every other Player/Creator UI piece in this project).
##
## Modal while visible - see PlayerDialog's class doc for the mechanism
## (full-rect root as a dim scrim, mouse_filter STOP, actual visible box
## is a child positioned within it, not the root itself). Especially
## important here: nothing else in the Player scene should be reachable
## before a party even exists.

signal _closed

var _slot_buttons: Array[Button] = []
var _start_button: Button
var _min_players: int = 1
var _max_players: int = HeroCatalog.SLOT_COUNT


func _ready() -> void:
	_build_ui()
	visible = false


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # the modal scrim - blocks everything behind it

	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.35)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE  # self (the root) already blocks; this is purely visual
	add_child(scrim)

	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360, 0)
	add_child(panel)

	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(background)

	var vbox := VBoxContainer.new()
	background.add_child(vbox)

	var title := Label.new()
	title.text = "Choose your party"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	vbox.add_child(grid)

	for i in HeroCatalog.SLOT_COUNT:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = HeroCatalog.slot_name(i)
		btn.custom_minimum_size = Vector2(100, 60)
		var style := StyleBoxFlat.new()
		style.bg_color = HeroCatalog.slot_color(i)
		style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.toggled.connect(_on_slot_toggled)
		grid.add_child(btn)
		_slot_buttons.append(btn)

	_start_button = Button.new()
	_start_button.text = "Start"
	_start_button.disabled = true
	_start_button.pressed.connect(_on_start_pressed)
	vbox.add_child(_start_button)


func _on_slot_toggled(_pressed: bool) -> void:
	var selected_count := 0
	for btn in _slot_buttons:
		if btn.button_pressed:
			selected_count += 1

	# At the cap: grey out every slot that isn't ALREADY selected (so
	# selected ones stay clickable to deselect, freeing up a slot again).
	var at_cap := selected_count >= _max_players
	for btn in _slot_buttons:
		if not btn.button_pressed:
			btn.disabled = at_cap

	_start_button.disabled = selected_count < _min_players


func _on_start_pressed() -> void:
	_closed.emit()


## Shows the dialog and waits for confirmation - returns the selected slot
## INDICES in slot order (e.g. [0, 2, 5] if slots 1/3/6 got picked), not
## just a count, since which character maps to which player number matters
## just as much as how many are playing (see class doc). Reads
## min_players/max_players from `mission` (null = unrestricted, full
## HeroCatalog range).
func ask_roster(mission: MissionData) -> Array[int]:
	_min_players = clampi(mission.min_players, 1, HeroCatalog.SLOT_COUNT) if mission != null else 1
	_max_players = clampi(mission.max_players, _min_players, HeroCatalog.SLOT_COUNT) if mission != null else HeroCatalog.SLOT_COUNT

	for btn in _slot_buttons:
		btn.button_pressed = false
		btn.disabled = false
	_start_button.disabled = true

	visible = true
	await _closed
	visible = false

	var roster: Array[int] = []
	for i in _slot_buttons.size():
		if _slot_buttons[i].button_pressed:
			roster.append(i)
	return roster
