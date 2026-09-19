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
var _party_panel: CenterContainer
var _loadout_panel: CenterContainer
var _loadout_rows: VBoxContainer
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

	# A CenterContainer keeps each page's box truly centred whatever its size
	# (a zero-size Control anchored at the centre grows right/down instead).
	_party_panel = CenterContainer.new()
	var panel := _party_panel
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var background := PanelContainer.new()
	background.custom_minimum_size = Vector2(360, 0)
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

	# Second page (ask_loadouts()): two weapons per chosen hero.
	_loadout_panel = CenterContainer.new()
	_loadout_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loadout_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loadout_panel.visible = false
	add_child(_loadout_panel)

	var loadout_background := PanelContainer.new()
	loadout_background.custom_minimum_size = Vector2(620, 0)
	_loadout_panel.add_child(loadout_background)

	var loadout_vbox := VBoxContainer.new()
	loadout_background.add_child(loadout_vbox)

	var loadout_title := Label.new()
	loadout_title.text = "Choose two weapons per hero"
	loadout_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loadout_vbox.add_child(loadout_title)

	_loadout_rows = VBoxContainer.new()
	loadout_vbox.add_child(_loadout_rows)

	var loadout_start := Button.new()
	loadout_start.text = "Start"
	loadout_start.pressed.connect(_on_start_pressed)
	loadout_vbox.add_child(loadout_start)


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
	_party_panel.visible = true
	_loadout_panel.visible = false

	visible = true
	await _closed
	visible = false

	var roster: Array[int] = []
	for i in _slot_buttons.size():
		if _slot_buttons[i].button_pressed:
			roster.append(i)
	return roster


## Second embark page: each hero in `roster` picks TWO weapons from
## WeaponCatalog (the same weapon twice is allowed). Returns
## {hero slot index: Array[Weapon]} (two entries each).
func ask_loadouts(roster: Array[int]) -> Dictionary:
	for child in _loadout_rows.get_children():
		child.free()
	var catalog := WeaponCatalog.all()
	var pickers: Dictionary = {}
	for slot in roster:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = HeroCatalog.slot_name(slot)
		name_label.custom_minimum_size = Vector2(70, 0)
		row.add_child(name_label)
		var pair: Array[OptionButton] = []
		for n in 2:
			var picker := OptionButton.new()
			picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for weapon in catalog:
				picker.add_item(weapon.summary())
			picker.select(mini(n, catalog.size() - 1))
			row.add_child(picker)
			pair.append(picker)
		_loadout_rows.add_child(row)
		pickers[slot] = pair

	_party_panel.visible = false
	_loadout_panel.visible = true
	visible = true
	await _closed
	visible = false

	var loadouts: Dictionary = {}
	for slot in roster:
		var chosen: Array[Weapon] = []
		for picker in pickers[slot]:
			chosen.append(catalog[picker.selected])
		loadouts[slot] = chosen
	return loadouts
