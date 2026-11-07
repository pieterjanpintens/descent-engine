class_name FeatMonstersDialog
extends Window

## The campaign's "feat monsters": which monster templates count as a DRAGON (dragonkind) and as an ANIMUS for the heroes' feats (Brynn's "deal damage to
## dragonkind", Syrus's "defeat an animus"). Without any setting the game's own families count: the animus is the golem figure, dragonkind is the harbinger,
## centurion, doomcaller and salamander figures. A campaign adds its own monsters here (a dragon has no figure of its own, a custom template may use another
## figure): tick the BASE templates of the monster library that should count too. Built in code; `open_for(campaign, on_changed)` fills it.

var _campaign: Campaign
var _on_changed: Callable
var _content: VBoxContainer


func _ready() -> void:
	title = "Feat monsters"
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
	popup_centered_clamped(Vector2i(560, 560), 0.9)


func _rebuild() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var intro := Label.new()
	intro.text = "Some feats count the enemies of a kind: damage to dragonkind, defeating an animus. By default the game's own families count (animus = the golem figure; dragonkind = harbinger, centurion, doomcaller, salamander). Tick the monster templates of this campaign that should count as well."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	intro.custom_minimum_size.x = 500
	_content.add_child(intro)
	var names := MonsterArchetypeLibrary.names_of_kind(MonsterArchetype.Kind.BASE)
	_section("Counts as a dragon (dragonkind)", names, _campaign.dragon_templates)
	_section("Counts as an animus", names, _campaign.animus_templates)


func _section(heading: String, names: Array[String], chosen: Array[String]) -> void:
	var label := Label.new()
	label.text = heading
	label.add_theme_font_size_override("font_size", 16)
	label.modulate = Color(0.56, 0.79, 0.9)
	_content.add_child(label)
	if names.is_empty():
		var none := Label.new()
		none.text = "The monster library has no base templates yet (File > Monster Templates in the mission editor)."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD
		none.custom_minimum_size.x = 500
		_content.add_child(none)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(grid)
	for template_name in names:
		var box := CheckBox.new()
		box.text = template_name
		box.button_pressed = chosen.has(template_name)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.toggled.connect(func(on: bool):
			if on and not chosen.has(template_name):
				chosen.append(template_name)
			elif not on:
				chosen.erase(template_name)
			if _on_changed.is_valid():
				_on_changed.call()
		)
		grid.add_child(box)
