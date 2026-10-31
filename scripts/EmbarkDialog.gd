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
## The crafted consumables the party carries (consumable id -> count, campaign only) and how many each player may take: shown by the
## "Consumables" shortcut on both pages. They are available again every mission, so nothing is ever used up.
var consumables: Dictionary = {}
var consumables_per_player: int = 3
## The armor cards the party owns (base ids, campaign only): the "Armor…" shortcut lists them (upgraded ones from `upgraded_cards`). Armor effects are resolved at the table.
var owned_armors: Array[String] = []
## The trinket cards the party owns (base ids, campaign only); outside a campaign every trinket can be picked. Each hero wears ONE trinket,
## chosen on the loadout page: `chosen_trinkets` (hero slot -> {"id", "upgraded"}) is read after ask_loadouts().
var owned_trinkets: Array[String] = []
var chosen_trinkets: Dictionary = {}
## Trinket ids that are out of the game here (the Tarnished Brooch when the campaign defines no monster for it, or in a plain mission).
var excluded_trinkets: Array[String] = []
var _armor_button_party: Button
var _armor_button_loadout: Button
var _armor_dialog: AcceptDialog
var _consumables_button_party: Button
var _consumables_button_loadout: Button
var _consumables_dialog: AcceptDialog
var _roster_size: int = 0  # set once the heroes are chosen (the loadout page)
var upgraded_cards: Array[String] = []  # base ids of the owned cards that are upgraded (campaign only): shown "+", read-only

var _slot_buttons: Array[Button] = []
var _start_button: Button
var _party_panel: CenterContainer
var _loadout_panel: CenterContainer
var _loadout_scroll: ScrollContainer
var _loadout_rows: VBoxContainer
## The difficulty (1-4, Difficulty) the party plays at: set before ask_roster(), read back after it.
var difficulty: int = Difficulty.DEFAULT
var _difficulty_picker: OptionButton
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
	label.theme_type_variation = &"TitleLabel"


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

	var party_shortcuts := HBoxContainer.new()
	party_shortcuts.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(party_shortcuts)
	_armor_button_party = _armor_button()
	party_shortcuts.add_child(_armor_button_party)
	_consumables_button_party = _consumables_button()
	party_shortcuts.add_child(_consumables_button_party)

	# The difficulty of this game: the only place to change it, since it cannot change once the mission has started. MissionPlayer sets
	# `difficulty` before ask_roster() and keeps the answer (campaign save or player setting) for the next mission.
	var difficulty_row := HBoxContainer.new()
	difficulty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var difficulty_label := Label.new()
	difficulty_label.text = "Difficulty"
	difficulty_row.add_child(difficulty_label)
	_difficulty_picker = OptionButton.new()
	for value in Difficulty.all():
		_difficulty_picker.add_item(Difficulty.label(value), value)
	_difficulty_picker.item_selected.connect(func(index: int):
		difficulty = _difficulty_picker.get_item_id(index)
		_difficulty_picker.tooltip_text = Difficulty.description(difficulty))
	difficulty_row.add_child(_difficulty_picker)
	vbox.add_child(difficulty_row)

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

	# Six heroes with three pickers per weapon is taller than the window: the list scrolls, Start stays in reach
	# (_fit_loadout_scroll() sizes the scroll area to the window).
	_loadout_scroll = ScrollContainer.new()
	_loadout_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	loadout_vbox.add_child(_loadout_scroll)
	_loadout_rows = VBoxContainer.new()
	_loadout_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loadout_scroll.add_child(_loadout_rows)

	var loadout_shortcuts := HBoxContainer.new()
	loadout_shortcuts.alignment = BoxContainer.ALIGNMENT_CENTER
	loadout_vbox.add_child(loadout_shortcuts)
	_armor_button_loadout = _armor_button()
	loadout_shortcuts.add_child(_armor_button_loadout)
	_consumables_button_loadout = _consumables_button()
	loadout_shortcuts.add_child(_consumables_button_loadout)

	var loadout_start := Button.new()
	loadout_start.text = "Start"
	loadout_start.pressed.connect(_on_start_pressed)
	loadout_vbox.add_child(loadout_start)


## The "Consumables" shortcut: opens a read-only list of what the party can take. Hidden outside a campaign.
func _consumables_button() -> Button:
	var button := Button.new()
	button.text = "Consumables…"
	button.tooltip_text = "The potions the party has crafted - available in every mission"
	button.visible = false
	button.pressed.connect(_open_consumables)
	return button


## The "Armor" shortcut: a read-only list of the armor the party owns. Hidden outside a campaign.
func _armor_button() -> Button:
	var button := Button.new()
	button.text = "Armor…"
	button.tooltip_text = "The armor the party owns"
	button.visible = false
	button.pressed.connect(_open_armor)
	return button


func _open_armor() -> void:
	if _armor_dialog == null:
		_armor_dialog = AcceptDialog.new()
		_armor_dialog.title = "Armor"
		_armor_dialog.ok_button_text = "Close"
		_armor_dialog.min_size = Vector2i(560, 360)
		add_child(_armor_dialog)
	for child in _armor_dialog.get_children():
		if child is ScrollContainer:
			_armor_dialog.remove_child(child)
			child.free()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(540, 320)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	box.add_child(flow)
	for armor_id in owned_armors:
		var upgraded := upgraded_cards.has(armor_id)
		var armor := ArmorData.find(armor_id)
		var shown := str(armor.get("name", ArmorData.label(armor_id)))
		flow.add_child(ItemTile.build(ItemTile.data(shown, ArmorData.image(armor_id), upgraded, -1, ArmorData.label(armor_id) + "
" + ArmorData.rule_text(armor_id, upgraded))))
	if owned_armors.is_empty():
		var none := Label.new()
		none.text = "The party owns no armor yet."
		none.modulate = Color(1, 1, 1, 0.6)
		box.add_child(none)
	else:
		var note := Label.new()
		note.text = "Hover an armor for its rules. Armor is worn and resolved at the table."
		note.modulate = Color(1, 1, 1, 0.6)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 500.0
		box.add_child(note)
	_armor_dialog.add_child(scroll)
	_armor_dialog.popup_centered_clamped(Vector2i(600, 420), 0.9)


func _open_consumables() -> void:
	if _consumables_dialog == null:
		_consumables_dialog = AcceptDialog.new()
		_consumables_dialog.title = "Consumables"
		_consumables_dialog.ok_button_text = "Close"
		_consumables_dialog.min_size = Vector2i(560, 360)
		add_child(_consumables_dialog)
	for child in _consumables_dialog.get_children():
		if child is ScrollContainer:
			_consumables_dialog.remove_child(child)
			child.free()
	var players := _roster_size
	if players <= 0:
		for button in _slot_buttons:
			if button.button_pressed:
				players += 1
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(540, 320)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	var limit := Label.new()
	limit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	limit.custom_minimum_size.x = 500.0
	var total_text := ""
	if players > 0:
		total_text = tr_n(" (%d for %d player)", " (%d for %d players)", players) % [consumables_per_player * players, players]
	limit.text = tr("Each player may take %d into the mission%s. Crafted consumables are available again every mission - none is used up.") % [consumables_per_player, total_text]
	box.add_child(limit)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	box.add_child(flow)
	var any := false
	for id: String in consumables:
		var count := int(consumables[id])
		if count > 0:
			any = true
			flow.add_child(ItemTile.build(ItemTile.data(ConsumableData.label(id).trim_suffix(" +"), ConsumableData.image(id), ConsumableData.is_upgraded(id), count, ConsumableData.label(id) + "\n" + ConsumableData.rule_text(id))))
	if not any:
		var none := Label.new()
		none.text = "The party has no consumables. Brew them at an alchemist from potion recipes."
		none.modulate = Color(1, 1, 1, 0.6)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size.x = 500.0
		box.add_child(none)
	_consumables_dialog.add_child(scroll)
	_consumables_dialog.popup_centered_clamped(Vector2i(600, 420), 0.9)


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
	_roster_size = 0
	_consumables_button_party.visible = restrict_to_owned
	_armor_button_party.visible = restrict_to_owned
	difficulty = Difficulty.clamped(difficulty)
	_difficulty_picker.select(_difficulty_picker.get_item_index(difficulty))
	_difficulty_picker.tooltip_text = Difficulty.description(difficulty)

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
## Makes the list of heroes as tall as it needs, but never taller than the window leaves room for.
func _fit_loadout_scroll() -> void:
	_loadout_scroll.custom_minimum_size.y = 0.0
	await get_tree().process_frame
	var wanted := _loadout_rows.get_combined_minimum_size().y
	var room := get_viewport_rect().size.y - 170.0  # the title, the Start button and some air around the box
	_loadout_scroll.custom_minimum_size.y = minf(wanted, maxf(room, 160.0))


func ask_loadouts(roster: Array[int]) -> Dictionary:
	_roster_size = roster.size()
	_consumables_button_loadout.visible = restrict_to_owned
	_armor_button_loadout.visible = restrict_to_owned
	for child in _loadout_rows.get_children():
		child.free()
	var catalogs: Dictionary = {}  # slot -> [Array[Weapon] for slot 0, Array[Weapon] for slot 1]
	var pickers: Dictionary = {}
	var attachment_options: Dictionary = {}  # [slot, weapon_index] -> Array[WeaponAttachment]
	var attachment_pickers_by_weapon: Dictionary = {}  # [slot, weapon_index] -> Array[OptionButton]
	var show_all := not restrict_to_owned
	var weapon_plus_boxes: Dictionary = {}  # [slot, weapon_index] -> CheckBox (the weapon's upgraded side)
	var attachment_plus_boxes: Dictionary = {}  # [slot, weapon_index] -> Array[CheckBox] (the B / C parts' upgraded sides)
	var trinket_pickers: Dictionary = {}  # slot -> OptionButton (item 0 = none, then trinket_ids in order)
	var trinket_pluses: Dictionary = {}  # slot -> CheckBox
	var trinket_ids: Array[String] = []
	chosen_trinkets = {}
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
			picker.fit_to_longest_item = false  # else the longest weapon text decides the width of the whole page
			picker.clip_text = true
			picker.tooltip_text = tr("Weapon %d (%s)") % [weapon_index + 1, type_name]  # the first picker is always Weapon 1, the second Weapon 2 (combat croptops)
			for weapon in catalog:
				_add_item(picker, ("Rune: " if weapon.is_rune else "") + weapon.summary(), weapon.icon_path)
				if weapon.is_rune:
					var fixed_parts: Array[String] = []
					for fixed in weapon.attachments:
						fixed_parts.append("%s (%s)" % [fixed.attachment_name, fixed.ability_text])
					picker.set_item_tooltip(picker.item_count - 1, tr("%s: %s\nFixed parts: %s") % [weapon.ability_name, weapon.ability_text, ", ".join(fixed_parts)])

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
				attachment_picker.fit_to_longest_item = false
				attachment_picker.clip_text = true
				attachment_picker.add_theme_font_size_override("font_size", 12)
				attachment_picker.add_item(tr("Part %s: none") % part_slot)
				for option in picker_options:
					_add_item(attachment_picker, option.summary(), option.icon_path)
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
		if TrinketData.available():
			var trinket_column := VBoxContainer.new()
			trinket_column.custom_minimum_size = Vector2(150, 0)
			var trinket_caption := Label.new()
			trinket_caption.text = "Trinket"
			trinket_caption.add_theme_font_size_override("font_size", 12)
			trinket_caption.modulate = Color(1, 1, 1, 0.7)
			trinket_column.add_child(trinket_caption)
			var trinket_picker := OptionButton.new()
			trinket_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			trinket_picker.fit_to_longest_item = false
			trinket_picker.clip_text = true
			trinket_picker.tooltip_text = "The trinket this hero wears (one per hero; a trinket can only be worn by one hero)"
			trinket_picker.add_item("(none)")
			var ids: Array[String] = []
			for trinket in TrinketData.all():
				var trinket_id := str(trinket["id"])
				if (restrict_to_owned and not owned_trinkets.has(trinket_id)) or excluded_trinkets.has(trinket_id):
					continue
				ids.append(trinket_id)
				var icon := TrinketData.image(trinket_id)
				if icon != null:
					trinket_picker.add_icon_item(icon, str(trinket["name"]))
					trinket_picker.add_theme_constant_override("icon_max_width", 28)
					trinket_picker.get_popup().add_theme_constant_override("icon_max_width", 48)
				else:
					trinket_picker.add_item(str(trinket["name"]))
				trinket_picker.set_item_tooltip(trinket_picker.item_count - 1, str(trinket["text"]))
			trinket_ids.assign(ids)  # filled in place: the picker callbacks below hold this very array
			var trinket_plus := _plus_box()
			trinket_plus.disabled = restrict_to_owned  # a campaign decides which trinkets are upgraded; a plain mission lets the table choose
			trinket_plus.tooltip_text = "Upgraded (+). In a campaign this follows the party's upgrades." if restrict_to_owned else "Use the upgraded (+) side of this trinket."
			trinket_picker.disabled = ids.is_empty()
			trinket_picker.item_selected.connect(func(index: int):
				if restrict_to_owned:
					trinket_plus.button_pressed = index > 0 and upgraded_cards.has(ids[index - 1])
				_refresh_trinket_availability(trinket_pickers, trinket_ids)
			)
			trinket_column.add_child(_with_plus(trinket_picker, trinket_plus))
			row.add_child(trinket_column)
			trinket_pickers[slot] = trinket_picker
			trinket_pluses[slot] = trinket_plus
		_loadout_rows.add_child(row)
		catalogs[slot] = per_slot_catalogs
		pickers[slot] = pair

	_party_panel.visible = false
	_loadout_panel.visible = true
	visible = true
	_fit_loadout_scroll()
	await _closed
	visible = false

	for slot in trinket_pickers:
		var chosen_picker: OptionButton = trinket_pickers[slot]
		if chosen_picker.selected > 0:
			chosen_trinkets[slot] = {"id": trinket_ids[chosen_picker.selected - 1], "upgraded": (trinket_pluses[slot] as CheckBox).button_pressed}
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


## A trinket is one physical card: while one hero wears it, it is greyed out in every other hero's trinket picker.
func _refresh_trinket_availability(pickers: Dictionary, ids: Array[String]) -> void:
	var worn: Dictionary = {}  # trinket id -> the picker wearing it
	for slot in pickers:
		var picker: OptionButton = pickers[slot]
		if picker.selected > 0:
			worn[ids[picker.selected - 1]] = picker
	for slot in pickers:
		var picker: OptionButton = pickers[slot]
		for index in ids.size():
			picker.set_item_disabled(index + 1, worn.has(ids[index]) and worn[ids[index]] != picker)


## Adds an entry with the part's picture (when the user's weapon-data export has it) to a picker and keeps the pictures small.
func _add_item(picker: OptionButton, text: String, icon_path: String) -> void:
	var icon := WeaponData.icon_for(icon_path)
	if icon == null:
		picker.add_item(text)
		return
	picker.add_icon_item(icon, text)
	picker.add_theme_constant_override("icon_max_width", 28)
	picker.get_popup().add_theme_constant_override("icon_max_width", 48)


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
