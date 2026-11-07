class_name HeroGrowthDialog
extends Control

## The party's heroes in a campaign (Party menu > Heroes): per hero their skill points and skill tree (buy a skill with points) and their feats (work on
## up to `parallel_feats` at once, mark progress by hand, change or drop one - which loses its progress - and see what is completed). The rules are
## CampaignState's (hero progress methods); this only shows them. A skill's rule text is not in the game data, so only names and costs are shown.
## Built in code, modal scrim like InventoryDialog; open() rebuilds from the providers the owner assigns.

## Assigned by the owner: Callables returning the Campaign / CampaignState, and one called after every change (the owner saves the state).
var campaign_provider: Callable
var state_provider: Callable
var on_changed: Callable
## Assigned by the owner: true while playtesting from the campaign editor - only then are the manual progress buttons (+ / -) shown. In real play feat progress
## comes from what happens in the missions.
var manual_marking := false
## Assigned by the owner: true inside a mission - changing or dropping a feat then follows the campaign's feat_change_mode (a cost or a limit).
var in_mission := false

var _hero_id := ""
var _replacing := ""  ## the active feat the next "Replace with this" will take the place of ("" = starting a feat in a free slot)
var _tabs: TabContainer
var _hero_row: HBoxContainer
var _skills_box: VBoxContainer
var _feats_box: VBoxContainer
var _confirm: ConfirmationDialog
var _confirm_action := Callable()
var _notice: AcceptDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var background := PanelContainer.new()
	margin.add_child(background)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	background.add_child(vbox)

	var title := Label.new()
	title.text = "Heroes"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)
	_hero_row = HBoxContainer.new()
	_hero_row.add_theme_constant_override("separation", 6)
	vbox.add_child(_hero_row)
	vbox.add_child(HSeparator.new())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tabs)
	_skills_box = _tab("Skills")
	_feats_box = _tab("Feats")

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func(): visible = false)
	vbox.add_child(close_button)

	_confirm = ConfirmationDialog.new()
	_confirm.min_size = Vector2i(420, 0)
	_confirm.confirmed.connect(func():
		if _confirm_action.is_valid():
			_confirm_action.call()
	)
	add_child(_confirm)
	_notice = AcceptDialog.new()
	_notice.min_size = Vector2i(420, 0)
	add_child(_notice)
	visible = false


func _tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	_tabs.add_child(scroll)
	return box


## `tab`: 0 = Skills, 1 = Feats, -1 = keep the tab that was open.
func open(tab: int = -1) -> void:
	if _hero_id == "":
		_hero_id = CampaignState.hero_ids()[0]
	_replacing = ""
	_refresh()
	if tab >= 0 and tab < _tabs.get_tab_count():
		_tabs.current_tab = tab
	visible = true


# --- data helpers ---------------------------------------------------------------------------------------------------

func _campaign() -> Campaign:
	return campaign_provider.call() if campaign_provider.is_valid() else null


func _state() -> CampaignState:
	return state_provider.call() if state_provider.is_valid() else null


func _changed() -> void:
	if on_changed.is_valid():
		on_changed.call()
	_refresh()


func _hero_label(hero_id: String) -> String:
	return HeroData.hero_name(hero_id) if HeroData.available() else hero_id.trim_prefix("HERO_").capitalize()


func _skill_name(hero_id: String, number: int) -> String:
	return HeroData.skill_name(HeroData.slot_id(hero_id, number)) if HeroData.available() else ""


# --- building -------------------------------------------------------------------------------------------------------

func _refresh() -> void:
	var campaign := _campaign()
	var state := _state()
	# queue_free, not free: the button that asked for this refresh is still inside its own signal
	for child in _hero_row.get_children():
		_hero_row.remove_child(child)
		child.queue_free()
	for box in [_skills_box, _feats_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	if campaign == null or state == null:
		return
	var group := ButtonGroup.new()
	for hero_id in CampaignState.hero_ids():
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.text = _hero_label(hero_id)
		button.icon = HeroCatalog.slot_portrait(HeroData.slot_for_id(hero_id))
		button.expand_icon = true
		button.custom_minimum_size = Vector2(120, 52)
		button.add_theme_constant_override("icon_max_width", 40)
		button.button_pressed = hero_id == _hero_id
		button.pressed.connect(func():
			_hero_id = hero_id
			_replacing = ""
			_refresh()
		)
		_hero_row.add_child(button)
	if not HeroData.available():
		for box in [_skills_box, _feats_box]:
			box.add_child(_wrapped(tr("The hero data is missing - import the game's assets first (Options > Game assets)."), 500.0))
		return
	_build_skills(campaign, state)
	_build_feats(campaign, state)


func _wrapped(text: String, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = width  # a wrapping label needs a width to start from
	return label


func _build_skills(campaign: Campaign, state: CampaignState) -> void:
	var tree := campaign.effective_skill_tree()
	var owned := state.owned_skills(campaign, _hero_id)
	var summary_label := Label.new()
	summary_label.text = tr("Skill points: %d") % state.skill_points(campaign, _hero_id)
	summary_label.add_theme_font_size_override("font_size", 18)
	summary_label.modulate = Color(1.0, 0.85, 0.35)
	_skills_box.add_child(summary_label)
	for row in tree.layers():
		var flow := HFlowContainer.new()
		flow.alignment = FlowContainer.ALIGNMENT_CENTER
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		_skills_box.add_child(flow)
		for number: int in row:
			flow.add_child(_skill_button(campaign, state, tree, number, owned))


func _skill_button(campaign: Campaign, state: CampaignState, tree: SkillTree, number: int, owned: Array[int]) -> Button:
	var slot := tree.node(number)
	var button := Button.new()
	button.custom_minimum_size = Vector2(190, 64)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var skill_name := _skill_name(_hero_id, number)
	var status := tr("Cost %d") % slot.cost
	var tip := ""
	if owned.has(number):
		status = tr("Owned")
		button.disabled = true
		button.modulate = Color(0.6, 1.0, 0.7)
	elif state.can_buy_skill(campaign, _hero_id, number):
		button.modulate = Color(1, 1, 1)
		button.pressed.connect(func(): _ask_buy(campaign, state, number, slot.cost, skill_name))
	else:
		button.disabled = true
		button.modulate = Color(1, 1, 1, 0.55)
		if state.skill_points(campaign, _hero_id) < slot.cost:
			tip = tr("Not enough skill points.")
		elif not slot.parents.is_empty() and slot.parents.filter(func(parent): return owned.has(parent)).is_empty():
			tip = tr("Needs one of: %s") % ", ".join(slot.parents.map(func(parent): return _skill_name(_hero_id, parent)))
		else:
			tip = tr("Locked until a condition is met.")
	button.text = "%s\n%s" % [skill_name if skill_name != "" else "#%d" % number, status]
	button.tooltip_text = tip
	return button


func _ask_buy(campaign: Campaign, state: CampaignState, number: int, cost: int, skill_name: String) -> void:
	_confirm.title = tr("Buy a skill")
	_confirm.dialog_text = tr("Buy %s for %d skill points?") % [skill_name, cost]
	_confirm_action = func():
		if state.buy_skill(campaign, _hero_id, number):
			_changed()
	_confirm.popup_centered()


func _build_feats(campaign: Campaign, state: CampaignState) -> void:
	var active := state.active_feats(campaign, _hero_id)
	var free_slots := state.free_feat_slots(campaign, _hero_id)
	var header := Label.new()
	header.text = tr("Feats active: %d of %d") % [active.size(), maxi(campaign.parallel_feats, 1)]
	header.add_theme_font_size_override("font_size", 18)
	_feats_box.add_child(header)
	if active.is_empty():
		_feats_box.add_child(_wrapped(tr("No feat is active - start one below."), 500.0))
	for feat_id: String in active:
		_feats_box.add_child(_active_feat_row(campaign, state, feat_id, int(active[feat_id])))

	var completed := state.completed_feats(campaign, _hero_id)
	var choices := state.startable_feats(campaign, _hero_id)
	var heading := Label.new()
	heading.text = tr("Replace with which feat?") if _replacing != "" else tr("Available feats")
	heading.add_theme_font_size_override("font_size", 16)
	heading.modulate = Color(0.56, 0.79, 0.9)
	_feats_box.add_child(heading)
	if _replacing != "":
		_feats_box.add_child(_button(tr("Cancel"), func():
			_replacing = ""
			_refresh()
		))
	if choices.is_empty():
		_feats_box.add_child(_wrapped(tr("No other feat is available right now."), 500.0))
	for feat in choices:
		_feats_box.add_child(_feat_card(campaign, state, feat, free_slots))

	var done_label := Label.new()
	done_label.text = tr("Completed feats: %d") % completed.size()
	done_label.add_theme_font_size_override("font_size", 16)
	done_label.modulate = Color(0.56, 0.79, 0.9)
	_feats_box.add_child(done_label)
	for feat_id in completed:
		var feat := HeroData.feat(feat_id)
		var line := Label.new()
		line.text = "✓ %s" % str(feat.get("title", feat_id))
		line.modulate = Color(0.6, 1.0, 0.7)
		line.tooltip_text = str(feat.get("description", ""))
		_feats_box.add_child(line)


func _reward_text(campaign: Campaign, feat: Dictionary) -> String:
	if feat["reward_kind"] == "skill":
		return tr("Skill points: +%d") % campaign.effective_skill_tree().points_per_feat
	var recipe := RecipeData.find(str(feat["reward"]))
	var shown: String = RecipeData.label(recipe) if not recipe.is_empty() else str(feat["reward"])
	return tr("Recipe: ") + shown + "  (" + tr("Skill points: +%d") % campaign.effective_skill_tree().points_per_feat + ")"


func _feat_texts(campaign: Campaign, feat: Dictionary, box: VBoxContainer) -> void:
	var title := Label.new()
	title.text = str(feat["title"])
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)
	box.add_child(_wrapped(str(feat["description"]), 520.0))
	var info := Label.new()
	info.text = tr("Goal: %d") % int(feat["goal"]) + "    " + tr("Reward: %s") % _reward_text(campaign, feat)
	info.modulate = Color(1, 1, 1, 0.7)
	box.add_child(info)


func _active_feat_row(campaign: Campaign, state: CampaignState, feat_id: String, progress: int) -> Control:
	var feat := HeroData.feat(feat_id)
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	_feat_texts(campaign, feat, box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxi(int(feat["goal"]), 1)
	bar.value = progress
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(160, 22)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.12, 0.13, 0.17)
	track.border_color = Color(0.45, 0.5, 0.6)
	track.set_border_width_all(1)
	bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.9, 0.62, 0.2)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var count := Label.new()
	count.text = "%d / %d" % [progress, int(feat["goal"])]
	row.add_child(count)
	if manual_marking:
		row.add_child(_manual_buttons(campaign, state, feat_id, progress))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var blocked := state.feat_change_problem(campaign, _hero_id, in_mission)
	var change_button := _button(tr("Change…"), func():
		_replacing = feat_id
		_refresh()
	)
	var drop_button := _button(tr("Drop"), func(): _ask_drop(campaign, state, feat_id, progress))
	for button in [change_button, drop_button]:
		button.disabled = blocked != ""
		button.tooltip_text = blocked if blocked != "" else state.feat_change_note(campaign, _hero_id, in_mission)
		row.add_child(button)
	return panel


## The hand-marking buttons of an active feat: take one back / it happened once more. Only shown while playtesting (manual_marking).
func _manual_buttons(campaign: Campaign, state: CampaignState, feat_id: String, progress: int) -> Control:
	var box := HBoxContainer.new()
	var minus := _button("−", func():
		state.add_feat_progress(campaign, _hero_id, feat_id, -1)
		_changed()
	)
	minus.tooltip_text = tr("Take one back")
	minus.disabled = progress <= 0
	box.add_child(minus)
	var plus := _button("+", func(): _mark_progress(campaign, state, feat_id))
	plus.tooltip_text = tr("It happened once more (marked by hand)")
	box.add_child(plus)
	return box


func _mark_progress(campaign: Campaign, state: CampaignState, feat_id: String) -> void:
	var result := state.add_feat_progress(campaign, _hero_id, feat_id, 1)
	if not result.is_empty() and result["completed"]:
		var text := tr("%s completed the feat \"%s\"!") % [_hero_label(_hero_id), result["title"]]
		text += "\n" + tr("Skill points: +%d") % int(result["points"])
		if str(result["recipe"]) != "":
			var recipe := RecipeData.find(str(result["recipe"]))
			text += "\n" + tr("Recipe: ") + (RecipeData.label(recipe) if not recipe.is_empty() else str(result["recipe"]))
		_notice.title = tr("Feat completed")
		_notice.dialog_text = text
		_notice.popup_centered()
	_changed()


## Starting a feat: free on the campaign map; during a mission it follows the campaign's setting for a change, so a cost is confirmed first.
func _ask_start(campaign: Campaign, state: CampaignState, feat_id: String, note: String) -> void:
	var begin := func():
		if state.start_feat(campaign, _hero_id, feat_id, in_mission):
			_changed()
	if note == "":
		begin.call()
		return
	_confirm.title = tr("Start a feat")
	_confirm.dialog_text = tr("Start \"%s\"?") % str(HeroData.feat(feat_id).get("title", feat_id)) + "
" + note
	_confirm_action = begin
	_confirm.popup_centered()


func _ask_drop(campaign: Campaign, state: CampaignState, feat_id: String, progress: int) -> void:
	_confirm.title = tr("Drop a feat")
	_confirm.dialog_text = tr("Drop \"%s\"? Its progress (%d) is lost.") % [str(HeroData.feat(feat_id).get("title", feat_id)), progress]
	var note := state.feat_change_note(campaign, _hero_id, in_mission)
	if note != "":
		_confirm.dialog_text += "\n" + note
	_confirm_action = func():
		state.unequip_feat(campaign, _hero_id, feat_id, in_mission)
		_changed()
	_confirm.popup_centered()


func _feat_card(campaign: Campaign, state: CampaignState, feat: Dictionary, free_slots: int) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	_feat_texts(campaign, feat, box)
	var feat_id: String = feat["id"]
	if _replacing != "":
		box.add_child(_button(tr("Replace with this"), func(): _ask_replace(campaign, state, feat_id)))
	else:
		var blocked := state.feat_change_problem(campaign, _hero_id, true) if in_mission else ""
		var note := state.feat_change_note(campaign, _hero_id, true) if in_mission else ""
		var start := _button(tr("Start"), func(): _ask_start(campaign, state, feat_id, note))
		start.disabled = free_slots <= 0 or blocked != ""
		if free_slots <= 0:
			start.tooltip_text = tr("No free feat slot - change or drop an active feat first.")
		elif blocked != "":
			start.tooltip_text = blocked
		else:
			start.tooltip_text = note
		box.add_child(start)
	return panel


func _ask_replace(campaign: Campaign, state: CampaignState, new_feat_id: String) -> void:
	var old_id := _replacing
	var progress := int(state.active_feats(campaign, _hero_id).get(old_id, 0))
	_confirm.title = tr("Change a feat")
	_confirm.dialog_text = tr("Replace \"%s\" with \"%s\"? The old feat's progress (%d) is lost.") % [
		str(HeroData.feat(old_id).get("title", old_id)), str(HeroData.feat(new_feat_id).get("title", new_feat_id)), progress]
	var note := state.feat_change_note(campaign, _hero_id, in_mission)
	if note != "":
		_confirm.dialog_text += "\n" + note
	_confirm_action = func():
		if state.replace_feat(campaign, _hero_id, old_id, new_feat_id, in_mission):
			_replacing = ""
			_changed()
	_confirm.popup_centered()


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button
