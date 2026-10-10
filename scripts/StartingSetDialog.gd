class_name StartingSetDialog
extends Window

## The campaign's STARTING SET: the weapon cards, B/C parts and runes the party owns at mission 0 (Campaign.
## starting_weapons / starting_attachments / starting_runes). Every hero needs at least one weapon of each of
## their two weapon types to be playable, so the campaign editor lists a problem until each hero type has one -
## "Fill with the basic set" ticks the first weapon of every type. Ids are the game's base part ids (a card and its
## upgraded "+" side are one card, see WeaponData). Needs the user's own weapon-data export (WeaponData.available()).
## Built in code; `open_for(campaign, on_changed)` fills it, `on_changed` is called after every edit.

var _campaign: Campaign
var _on_changed: Callable
var _content: VBoxContainer


func _ready() -> void:
	title = "Starting equipment"
	min_size = Vector2i(360, 240)
	visible = false
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)


func open_for(campaign: Campaign, on_changed: Callable) -> void:
	_campaign = campaign
	_on_changed = on_changed
	_rebuild()
	popup_centered_clamped(Vector2i(640, 720), 0.9)  # never bigger than 90% of the game window


func _rebuild() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()  # not free(): the button that triggered this rebuild is still inside its own signal
	var intro := Label.new()
	intro.text = "What the party owns when the campaign starts. Every hero needs at least one weapon of each of their two types."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	_content.add_child(intro)
	if not WeaponData.available():
		var missing := Label.new()
		missing.text = "No weapon data found - run the asset import (import_all) first."
		_content.add_child(missing)
		return
	var defaults := Button.new()
	defaults.text = "Fill with the basic set (first weapon of every type)"
	defaults.pressed.connect(func():
		_campaign.fill_default_starting_set()
		_changed()
		_rebuild()
	)
	_content.add_child(defaults)
	# One folded section per weapon type (a long flat list didn't fit the window); a section opens to two columns of
	# check boxes - the weapon cards, then the B and C parts.
	for type_name: String in WeaponData.TYPE_TO_GAME_WEAPON:
		var grid := _section(type_name)
		for weapon in WeaponData.weapons_for_type(type_name):
			grid.add_child(_check("%s (dmg %d)" % [weapon.weapon_name, weapon.damage], _campaign.starting_weapons, weapon.part_id, weapon.ability_text))
		for attachment in WeaponData.attachments_for_type(type_name):
			grid.add_child(_check("%s: %s" % [attachment.part_slot, attachment.attachment_name], _campaign.starting_attachments, attachment.part_id, attachment.ability_text))
	var rune_grid := _section("Runes")
	for rune in WeaponData.runes():
		rune_grid.add_child(_check(rune.weapon_name, _campaign.starting_runes, rune.part_id, rune.ability_text))


## A folded section titled `title_text` holding a two-column grid.
func _section(title_text: String) -> GridContainer:
	var section := FoldableContainer.new()
	section.title = title_text
	section.folded = true
	_content.add_child(section)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(grid)
	return grid


func _check(text: String, owned: Array[String], id: String, tooltip: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.tooltip_text = tooltip
	box.button_pressed = owned.has(id)
	box.toggled.connect(func(on: bool):
		if on and not owned.has(id):
			owned.append(id)
		elif not on:
			owned.erase(id)
		_changed()
	)
	return box


func _changed() -> void:
	if _on_changed.is_valid():
		_on_changed.call()
