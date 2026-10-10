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
	size = Vector2i(620, 720)
	min_size = Vector2i(420, 320)
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
	popup_centered()


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
	for type_name: String in WeaponData.TYPE_TO_GAME_WEAPON:
		_content.add_child(HSeparator.new())
		var heading := Label.new()
		heading.text = type_name
		heading.add_theme_font_size_override("font_size", 16)
		_content.add_child(heading)
		for weapon in WeaponData.weapons_for_type(type_name):
			_content.add_child(_check("%s  (damage %d)" % [weapon.weapon_name, weapon.damage], _campaign.starting_weapons, weapon.part_id, weapon.ability_text))
		for attachment in WeaponData.attachments_for_type(type_name):
			_content.add_child(_check("Part %s: %s" % [attachment.part_slot, attachment.attachment_name], _campaign.starting_attachments, attachment.part_id, attachment.ability_text))
	_content.add_child(HSeparator.new())
	var runes_heading := Label.new()
	runes_heading.text = "Runes"
	runes_heading.add_theme_font_size_override("font_size", 16)
	_content.add_child(runes_heading)
	for rune in WeaponData.runes():
		_content.add_child(_check(rune.weapon_name, _campaign.starting_runes, rune.part_id, rune.ability_text))


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
