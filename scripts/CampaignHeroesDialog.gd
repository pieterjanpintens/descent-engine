class_name CampaignHeroesDialog
extends Window

## The campaign's heroes: for each of the six, their level and experience, the abilities they
## have equipped and a picker to equip another one (only abilities that fit the hero and level,
## while a slot is free). Opened from the campaign player; every change is saved by the owner
## through the `changed` signal.

signal changed

var state: CampaignState
var progression: HeroProgression

var _list: VBoxContainer


func _ready() -> void:
	title = "Heroes"
	size = Vector2i(560, 620)
	close_requested.connect(hide)
	visible = false
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8
	scroll.offset_top = 8
	scroll.offset_right = -8
	scroll.offset_bottom = -8
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func open_for(campaign_state: CampaignState, hero_progression: HeroProgression) -> void:
	state = campaign_state
	progression = hero_progression
	_rebuild()
	popup_centered()


func _rebuild() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for slot in HeroCatalog.SLOT_COUNT:
		_list.add_child(_build_hero(state.hero(slot)))
		_list.add_child(HSeparator.new())


func _build_hero(hero: HeroState) -> Control:
	var box := VBoxContainer.new()
	var header := HBoxContainer.new()
	box.add_child(header)
	var portrait := TextureRect.new()
	portrait.texture = HeroCatalog.slot_portrait(hero.hero_slot)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.custom_minimum_size = Vector2(48, 48)
	header.add_child(portrait)
	var level := hero.level(progression)
	var next_xp := progression.xp_for_next(level)
	var heading := Label.new()
	heading.text = "%s - level %d, %d XP%s" % [HeroCatalog.slot_name(hero.hero_slot), level, hero.experience, " (next level at %d)" % next_xp if next_xp >= 0 else " (maximum level)"]
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(heading)

	var slots := hero.slots(progression)
	var abilities_label := Label.new()
	abilities_label.text = "Abilities (%d of %d slots used):" % [hero.equipped_abilities.size(), slots]
	box.add_child(abilities_label)
	for ability_id in hero.equipped_abilities:
		var ability := AbilityCatalog.find(ability_id)
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = ability.ability_name if ability != null else ability_id
		name_label.tooltip_text = ability.description if ability != null else ""
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var remove := Button.new()
		remove.text = "×"
		remove.tooltip_text = "Unequip"
		remove.pressed.connect(func():
			hero.unequip(ability_id)
			changed.emit()
			_rebuild()
		)
		row.add_child(remove)
		box.add_child(row)

	var choices: Array[HeroAbility] = []
	for ability in hero.available_abilities(progression):
		if not hero.equipped_abilities.has(ability.id):
			choices.append(ability)
	var equip_row := HBoxContainer.new()
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for ability in choices:
		picker.add_item("%s (level %d)" % [ability.ability_name, ability.required_level])
		picker.set_item_tooltip(picker.item_count - 1, ability.description)
	equip_row.add_child(picker)
	var equip := Button.new()
	equip.text = "Equip"
	equip.disabled = choices.is_empty() or hero.equipped_abilities.size() >= slots
	equip.pressed.connect(func():
		if picker.selected >= 0 and hero.equip(choices[picker.selected].id, progression):
			changed.emit()
			_rebuild()
	)
	equip_row.add_child(equip)
	box.add_child(equip_row)
	return box
