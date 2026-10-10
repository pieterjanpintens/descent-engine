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

## In a campaign the loadout page offers only the attachments the party owns (set by
## MissionPlayer from the campaign save); outside one every fitting attachment is offered.
var restrict_to_owned: bool = false
var owned_attachments: Array[String] = []
var owned_runes: Array[String] = []  # part ids of the runes the party owns (campaign only)
var owned_weapons: Array[String] = []  # part ids of the weapon cards the party owns (campaign only)
var upgraded_cards: Array[String] = []  # base ids of the owned cards that are upgraded (campaign only): shown "+", read-only

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


## A transparent (or `color`-bordered, for selected/hover) stylebox for a
## portrait button - a flat bg_color style would just get painted OVER by
## the portrait icon, so selection state instead reads as a border around
## the square portrait (border_width 0 = invisible, just an empty box so
## normal/disabled don't shift the button's size against pressed/hover's).
## Makes a page's title Label bold without needing a bundled bold font file -
## FontVariation.variation_embolden synthesizes bold from the default theme
## font (embolden 1.0 = a normal, clearly-bold weight; Godot 4's own
## documented range is roughly -2..2, negative thins it instead). Same
## instance-per-call approach as every other theme override in this project
## (each Label gets its own, nothing shared/cached - these are only built
## once per dialog anyway).
func _bold_title(label: Label) -> void:
	var bold_font := FontVariation.new()
	bold_font.base_font = label.get_theme_font("font")
	bold_font.variation_embolden = 1.0
	label.add_theme_font_override("font", bold_font)


func _slot_style(color: Color, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.set_corner_radius_all(6)
	style.set_border_width_all(border_width if color.a > 0.0 else 0)
	style.border_color = color
	return style


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
	_bold_title(title)
	vbox.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	# The grid's own natural width (3 portrait cells + separation) is less
	# than `background`'s fixed 360px minimum (sized for the old, wider flat
	# buttons) - left as SIZE_FILL (VBoxContainer's default), the grid still
	# reports that smaller width and sits left-aligned, showing as dead
	# whitespace down the right side. SHRINK_CENTER centers it instead.
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(grid)

	for i in HeroCatalog.SLOT_COUNT:
		# A cell = the portrait (a toggle button, so selection still gets the
		# usual pressed/hover/disabled affordances) + a name caption below it -
		# see _slot_style() for why selection needs its own border stylebox
		# now that the button's face is a portrait image, not a flat colour.
		var cell := VBoxContainer.new()
		var btn := Button.new()
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(96, 96)
		btn.icon = HeroCatalog.slot_portrait(i)
		btn.expand_icon = true
		btn.add_theme_stylebox_override("normal", _slot_style(Color.TRANSPARENT))
		btn.add_theme_stylebox_override("hover", _slot_style(Color(1, 1, 1, 0.6)))
		btn.add_theme_stylebox_override("pressed", _slot_style(HeroCatalog.slot_color(i), 4))
		btn.add_theme_stylebox_override("disabled", _slot_style(Color.TRANSPARENT))
		btn.toggled.connect(_on_slot_toggled)
		cell.add_child(btn)

		var name_label := Label.new()
		name_label.text = HeroCatalog.slot_name(i)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(name_label)

		grid.add_child(cell)
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
	loadout_title.text = "Choose two weapons per hero (and optional attachments)"
	loadout_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bold_title(loadout_title)
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


## Second embark page: each hero in `roster` has TWO weapon slots, each
## FIXED to one weapon TYPE (WeaponCatalog.HERO_WEAPON_TYPES - e.g. Brynn is
## always Warhammer + Sword) - the picker within a slot only offers named
## weapons of THAT type (WeaponCatalog.weapons_of_type()), so "all swords
## fall under the sword dropdown" holds regardless of which hero has a sword
## slot. Returns {hero slot index: Array[Weapon]} (two entries each, in
## Weapon 1/Weapon 2 order - that POSITION, not the type or the specific
## item chosen, is what decides the combat croptop/mesh shown).
func ask_loadouts(roster: Array[int]) -> Dictionary:
	for child in _loadout_rows.get_children():
		child.free()
	var catalogs: Dictionary = {}  # slot -> [Array[Weapon] for slot 0, Array[Weapon] for slot 1]
	var pickers: Dictionary = {}
	var attachment_options: Dictionary = {}  # [slot, weapon_index] -> Array[WeaponAttachment]
	var attachment_pickers_by_weapon: Dictionary = {}  # [slot, weapon_index] -> Array[OptionButton]
	var show_all := not restrict_to_owned
	var weapon_plus_boxes: Dictionary = {}  # [slot, weapon_index] -> CheckBox (the weapon's upgraded side)
	var attachment_plus_boxes: Dictionary = {}  # [slot, weapon_index] -> Array[CheckBox] (the B / C parts' upgraded sides)
	for slot in roster:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = HeroCatalog.slot_name(slot)
		name_label.custom_minimum_size = Vector2(70, 0)
		row.add_child(name_label)
		var per_slot_catalogs: Array = []
		var pair: Array[OptionButton] = []
		for weapon_index in 2:
			var type_name := WeaponCatalog.type_of(slot, weapon_index)
			# In a campaign a weapon and its upgraded "+" side are ONE card (a "+" box flips it); in a plain mission
			# everything is listed, so the table can use whatever it wants.
			var catalog := WeaponCatalog.weapons_of_type(type_name, show_all)
			if restrict_to_owned:
				# Only the weapon cards the party owns (the campaign's starting set plus what it bought); a
				# campaign without any of this type would be unplayable, so then everything stays offered.
				var owned_catalog: Array[Weapon] = []
				for weapon in catalog:
					if owned_weapons.has(weapon.base_part_id):
						owned_catalog.append(weapon)
				if not owned_catalog.is_empty():
					catalog = owned_catalog
			var type_weapon_count := catalog.size()
			for rune in WeaponData.runes(show_all):  # any hero can take a rune in place of their own weapon
				if not restrict_to_owned or owned_runes.has(rune.base_part_id):
					catalog.append(rune)
			per_slot_catalogs.append(catalog)

			var type_label := Label.new()
			type_label.text = type_name
			type_label.add_theme_font_size_override("font_size", 12)
			type_label.modulate = Color(1, 1, 1, 0.7)

			var picker := OptionButton.new()
			picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			picker.tooltip_text = "Weapon %d (%s)" % [weapon_index + 1, type_name]  # the first picker is always Weapon 1, the second Weapon 2 (combat croptops)
			for weapon in catalog:
				picker.add_item(("Rune: " if weapon.is_rune else "") + weapon.summary())
				if weapon.is_rune:
					var fixed_parts: Array[String] = []
					for fixed in weapon.attachments:
						fixed_parts.append("%s (%s)" % [fixed.attachment_name, fixed.ability_text])
					picker.set_item_tooltip(picker.item_count - 1, "%s: %s\nFixed parts: %s" % [weapon.ability_name, weapon.ability_text, ", ".join(fixed_parts)])

			# A weapon and its upgraded "+" side are ONE physical card: in a campaign the picker lists the card and a
			# box flips it; outside one every version is listed and there is nothing to flip.
			var weapon_plus := _plus_box()
			weapon_plus.visible = not show_all
			weapon_plus_boxes[[slot, weapon_index]] = weapon_plus
			weapon_plus.button_pressed = not catalog.is_empty() and upgraded_cards.has(catalog[0].base_part_id)
			picker.item_selected.connect(func(_index: int): weapon_plus.button_pressed = upgraded_cards.has(catalog[picker.selected].base_part_id))

			var column := VBoxContainer.new()
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			column.add_child(type_label)
			column.add_child(_with_plus(picker, weapon_plus))
			# Optional premade attachments (secondary abilities) for this weapon.
			var all_options := _allowed_attachments(slot, weapon_index, type_name, show_all)
			var options: Array = []  # per picker: the attachments it offers (the real B / C parts go to their own picker)
			var attachment_pickers: Array[OptionButton] = []
			var attachment_plus: Array[CheckBox] = []
			for attachment_number in WeaponAttachment.MAX_PER_WEAPON:
				var part_slot := "B" if attachment_number == 0 else "C"
				var picker_options: Array[WeaponAttachment] = []
				for option in all_options:
					if option.part_slot == "" or option.part_slot == part_slot:
						picker_options.append(option)
				options.append(picker_options)
				var attachment_picker := OptionButton.new()
				attachment_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				attachment_picker.add_theme_font_size_override("font_size", 12)
				attachment_picker.add_item("Part %s: none" % part_slot)
				for option in picker_options:
					attachment_picker.add_item(option.summary())
					if option.ability_text != "":
						attachment_picker.set_item_tooltip(attachment_picker.item_count - 1, option.ability_text)
				attachment_picker.disabled = picker_options.is_empty()
				attachment_picker.item_selected.connect(func(_index: int): _keep_attachments_distinct(attachment_pickers, options))
				attachment_picker.set_meta("free_disabled", picker_options.is_empty())
				var part_plus := _plus_box()
				part_plus.visible = not show_all
				attachment_plus.append(part_plus)
				attachment_picker.item_selected.connect(func(_index: int): part_plus.button_pressed = attachment_picker.selected > 0 and upgraded_cards.has(picker_options[attachment_picker.selected - 1].part_id))
				column.add_child(_with_plus(attachment_picker, part_plus))
				attachment_pickers.append(attachment_picker)
			attachment_plus_boxes[[slot, weapon_index]] = attachment_plus
			# A rune has its B and C parts fixed: the part pickers don't apply while one is selected. A rune
			# is one card: while one hero holds it, it is greyed out in every other picker.
			picker.item_selected.connect(func(_index: int):
				var is_rune_selected := picker.selected >= type_weapon_count
				for picker_number in attachment_pickers.size():
					if is_rune_selected:
						attachment_pickers[picker_number].select(0)
						attachment_plus[picker_number].button_pressed = false
					var free: bool = attachment_pickers[picker_number].get_meta("free_disabled")
					attachment_pickers[picker_number].disabled = is_rune_selected or free
				_refresh_rune_availability(pickers, catalogs)
			)
			row.add_child(column)
			pair.append(picker)
			attachment_options[[slot, weapon_index]] = options
			attachment_pickers_by_weapon[[slot, weapon_index]] = attachment_pickers
		_loadout_rows.add_child(row)
		catalogs[slot] = per_slot_catalogs
		pickers[slot] = pair

	_party_panel.visible = false
	_loadout_panel.visible = true
	visible = true
	await _closed
	visible = false

	var loadouts: Dictionary = {}
	for slot in roster:
		var chosen: Array[Weapon] = []
		for weapon_index in pickers[slot].size():
			var picker: OptionButton = pickers[slot][weapon_index]
			var catalog: Array = catalogs[slot][weapon_index]
			var weapon: Weapon = catalog[picker.selected]
			if weapon_plus_boxes[[slot, weapon_index]].button_pressed:
				weapon = WeaponData.upgraded_weapon(weapon)
			var options: Array = attachment_options[[slot, weapon_index]]
			var weapon_pickers: Array = attachment_pickers_by_weapon[[slot, weapon_index]]
			var plus_boxes: Array = attachment_plus_boxes[[slot, weapon_index]]
			for picker_number in weapon_pickers.size():
				var attachment_picker: OptionButton = weapon_pickers[picker_number]
				if attachment_picker.selected > 0 and not weapon.is_rune:
					var attachment: WeaponAttachment = options[picker_number][attachment_picker.selected - 1]
					if plus_boxes[picker_number].button_pressed:
						attachment = WeaponData.upgraded_attachment(attachment)
					weapon.attachments.append(attachment)
			chosen.append(weapon)
		loadouts[slot] = chosen
	return loadouts


## The attachments that may be offered for a weapon: the ones that fit it (AttachmentCatalog),
## and in a campaign (`restrict_to_owned`) only those the party owns. An owned attachment can be
## equipped on more than one weapon - the number of copies is not tracked.
func _allowed_attachments(slot: int, weapon_index: int, type_name: String, include_upgrades: bool = false) -> Array[WeaponAttachment]:
	var allowed: Array[WeaponAttachment] = []
	for attachment in AttachmentCatalog.for_weapon(slot, weapon_index, type_name, include_upgrades):
		if not restrict_to_owned or owned_attachments.has(attachment.part_id):
			allowed.append(attachment)
	return allowed


## A rune is one physical card: while one hero's weapon slot holds it (either side of the card), it is greyed out
## (not selectable) in every other weapon picker; pick something else in that slot first to make it available again.
func _refresh_rune_availability(pickers: Dictionary, catalogs: Dictionary) -> void:
	var holders: Dictionary = {}  # rune card (base part id) -> the picker holding it
	for slot in pickers:
		for weapon_index in pickers[slot].size():
			var picker: OptionButton = pickers[slot][weapon_index]
			var weapon: Weapon = catalogs[slot][weapon_index][picker.selected]
			if weapon.is_rune:
				holders[weapon.base_part_id] = picker
	for slot in pickers:
		for weapon_index in pickers[slot].size():
			var picker: OptionButton = pickers[slot][weapon_index]
			var catalog: Array = catalogs[slot][weapon_index]
			for index in catalog.size():
				var weapon: Weapon = catalog[index]
				if weapon.is_rune:
					picker.set_item_disabled(index, holders.has(weapon.base_part_id) and holders[weapon.base_part_id] != picker)


## The small "+" check box that flips a card to its upgraded side.
func _plus_box() -> CheckBox:
	var box := CheckBox.new()
	box.text = "+"
	box.tooltip_text = "Shows whether this card is upgraded (+). Upgrades are earned in the campaign."
	box.disabled = true  # read-only: the campaign decides which cards are flipped
	return box


func _with_plus(picker: OptionButton, plus: CheckBox) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(plus)  # in FRONT of its picker, so it can't be read as belonging to the weapon in the next column
	row.add_child(picker)
	return row


## The same attachment can't be equipped twice on one weapon: if two pickers show the same
## choice, the later one goes back to "none".
func _keep_attachments_distinct(attachment_pickers: Array[OptionButton], options: Array) -> void:
	var taken: Array[WeaponAttachment] = []
	for picker_number in attachment_pickers.size():
		var attachment_picker := attachment_pickers[picker_number]
		if attachment_picker.selected <= 0:
			continue
		var chosen: WeaponAttachment = options[picker_number][attachment_picker.selected - 1]
		if taken.has(chosen):
			attachment_picker.select(0)
		else:
			taken.append(chosen)
