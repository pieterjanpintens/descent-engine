class_name SkillTreeDialog
extends Window

## The campaign's SKILL TREE editor (Campaign.skill_tree, see SkillTree): the same 11 slots for every hero. Per slot: the skill-point cost, which other
## skills it needs (owning ANY ONE of them opens it; none = a starting point) and optional conditions over the campaign's variables that must hold
## (the same rows as a side quest's; act_number >= 2 holds a skill back until the campaign's second act). Plus the skill points a completed feat pays
## and the points every hero starts with. A picture of the tree sits on top. While the dialog is open the campaign has a tree (the default one until
## something changes); closing it drops the tree again when it is still exactly the default, so a campaign only keeps one it actually changed.
## "Reset to the default tree" puts the defaults back. A hero picker only shows that hero's skill names (the shape is the same for all heroes); it
## needs the hero data export (HeroData.available()).
## Built in code; `open_for(campaign, on_changed, build_conditions)` fills it: `on_changed` is called after every edit and `build_conditions` is the
## campaign editor's condition-section builder (heading, conditions, parent container, rebuild callable).

var _campaign: Campaign
var _on_changed: Callable
var _build_conditions: Callable
var _hero_id := ""  ## whose skill names are shown ("" = none)
var _preview: SkillTreePreview
var _problems_label: Label
var _rows: VBoxContainer
var _points_spin: SpinBox
var _starting_spin: SpinBox


func _ready() -> void:
	title = "Skill tree"
	min_size = Vector2i(560, 420)
	visible = false
	close_requested.connect(_close)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var outer := VBoxContainer.new()
	margin.add_child(outer)

	var intro := Label.new()
	intro.text = "Where the heroes' 11 skills sit and what it takes to buy them (the same for every hero). A skill opens as soon as ANY ONE of the skills it needs is owned; a skill that needs none is a starting point. Skill points come from completed feats."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	intro.custom_minimum_size.x = 500
	outer.add_child(intro)

	var top := HBoxContainer.new()
	outer.add_child(top)
	top.add_child(_label("Skill points per completed feat:"))
	_points_spin = SpinBox.new()
	_points_spin.min_value = 0
	_points_spin.max_value = 10
	_points_spin.tooltip_text = "The game has 20 feats per hero and the skills of a hero cost 18 together."
	_points_spin.value_changed.connect(func(value: float):
		if _campaign == null:
			return
		_edit_tree().points_per_feat = int(value)
		_changed()
	)
	top.add_child(_points_spin)
	var starting_row := HBoxContainer.new()
	outer.add_child(starting_row)
	starting_row.add_child(_label("Skill points every hero starts with:"))
	_starting_spin = SpinBox.new()
	_starting_spin.min_value = 0
	_starting_spin.max_value = 30
	_starting_spin.tooltip_text = "Spent on the skills above before any feat is completed (0 = none). All of a hero's skills cost 18 together."
	_starting_spin.value_changed.connect(func(value: float):
		if _campaign == null:
			return
		_edit_tree().starting_points = int(value)
		_changed()
	)
	starting_row.add_child(_starting_spin)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var reset := Button.new()
	reset.text = "Reset to the default tree"
	reset.pressed.connect(func():
		_campaign.skill_tree = SkillTree.default_tree()
		_changed()
		_rebuild()
	)
	top.add_child(reset)

	var names_row := HBoxContainer.new()
	outer.add_child(names_row)
	names_row.add_child(_label("Show skill names of:"))
	var picker := OptionButton.new()
	picker.add_item("(no names)")
	picker.set_item_metadata(0, "")
	if HeroData.available():
		for hero in HeroData.heroes():
			picker.add_item(str(hero["name"]))
			picker.set_item_metadata(picker.item_count - 1, str(hero["id"]))
	else:
		picker.tooltip_text = "No hero data found - run the asset import first."
	picker.item_selected.connect(func(index: int):
		_hero_id = str(picker.get_item_metadata(index))
		_rebuild()
	)
	names_row.add_child(picker)

	var preview_scroll := ScrollContainer.new()
	preview_scroll.custom_minimum_size = Vector2(0, 310)
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer.add_child(preview_scroll)
	_preview = SkillTreePreview.new()
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_scroll.add_child(_preview)

	_problems_label = Label.new()
	_problems_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_problems_label.custom_minimum_size.x = 500
	_problems_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.4))
	outer.add_child(_problems_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)


func open_for(campaign: Campaign, on_changed: Callable, build_conditions: Callable) -> void:
	_campaign = campaign
	_on_changed = on_changed
	_build_conditions = build_conditions
	_edit_tree()  # the condition rows edit the nodes in place, so the campaign needs its tree while this is open
	_rebuild()
	popup_centered_clamped(Vector2i(760, 760), 0.9)  # never bigger than 90% of the game window


## The tree being edited: the campaign gets the default one when it has none.
func _edit_tree() -> SkillTree:
	if _campaign.skill_tree == null:
		_campaign.skill_tree = SkillTree.default_tree()
	return _campaign.skill_tree


## Closing: a tree that is still exactly the default is not kept.
func _close() -> void:
	if _campaign != null and _campaign.skill_tree != null and _campaign.skill_tree.is_default():
		_campaign.skill_tree = null
	hide()


func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()  # not free(): the control that triggered this rebuild is still inside its own signal
	var tree := _edit_tree()
	_points_spin.set_value_no_signal(tree.points_per_feat)
	_starting_spin.set_value_no_signal(tree.starting_points)
	var names := _names()
	for entry in tree.nodes:
		_rows.add_child(_build_row(entry, names))
	_refresh()


## number -> the first-side name of that skill for the chosen hero.
func _names() -> Dictionary:
	var names: Dictionary = {}
	if _hero_id != "" and HeroData.available():
		for skill in HeroData.skills_of(_hero_id):
			names[int(skill["number"])] = str(skill["name_a"])
	return names


func _build_row(entry: SkillTreeNode, names: Dictionary) -> Control:
	var number := entry.number
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var heading := _label("Skill %d%s" % [number, ": " + str(names[number]) if names.has(number) else ""])
	heading.custom_minimum_size.x = 210
	head.add_child(heading)
	head.add_child(_label("Cost:"))
	var cost := SpinBox.new()
	cost.min_value = 0
	cost.max_value = 20
	cost.value = entry.cost
	cost.value_changed.connect(func(value: float):
		_edit_node(number).cost = int(value)
		_changed()
	)
	head.add_child(cost)
	if entry.parents.is_empty():
		var start := _label("  starting point")
		start.add_theme_color_override("font_color", Color(0.55, 0.85, 0.6))
		head.add_child(start)

	var needs := HFlowContainer.new()
	box.add_child(needs)
	needs.add_child(_label("Needs any of:"))
	for other in range(1, SkillTree.SLOTS + 1):
		if other == number:
			continue
		var check := CheckBox.new()
		check.text = str(other)
		check.tooltip_text = str(names[other]) if names.has(other) else "Skill %d" % other
		check.button_pressed = entry.parents.has(other)
		check.toggled.connect(func(on: bool):
			var parents := _edit_node(number).parents
			if on and not parents.has(other):
				parents.append(other)
				parents.sort()
			elif not on:
				parents.erase(other)
			_changed()
			_rebuild()
		)
		needs.add_child(check)
	if not entry.conditions.is_empty():
		var only := _label("Only while all of these hold:")
		only.add_theme_color_override("font_color", Color(0.75, 0.7, 0.95))
		box.add_child(only)
	if _build_conditions.is_valid():
		_build_conditions.call("", entry.conditions, box, func():
			_changed()
			_rebuild()
		)
	return panel


func _edit_node(number: int) -> SkillTreeNode:
	return _edit_tree().node(number)


## Refresh the picture and the problem line after an edit.
func _refresh() -> void:
	var tree := _edit_tree()
	_preview.names = _names()
	_preview.tree = tree
	var found := _campaign.skill_tree_problems()
	_problems_label.text = "\n".join(found) if not found.is_empty() else ""
	_problems_label.visible = not found.is_empty()


func _changed() -> void:
	_refresh()
	if _on_changed.is_valid():
		_on_changed.call()


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
