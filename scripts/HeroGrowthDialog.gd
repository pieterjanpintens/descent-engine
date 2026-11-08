class_name HeroGrowthDialog
extends Control

## The party's heroes in a campaign (Party menu > Heroes): per hero their skill points and skill tree (buy a skill with points) and their feats (work on
## the first `parallel_feats` of their ordered feat list at once, rearrange the list on the campaign map, and see what is completed). The rules are
## CampaignState's (hero progress methods); this only shows them. A skill's rule text is not in the game data, so only names and costs are shown.
## Built in code, modal scrim like InventoryDialog; open() rebuilds from the providers the owner assigns.

## Assigned by the owner: Callables returning the Campaign / CampaignState, and one called after every change (the owner saves the state).
var campaign_provider: Callable
var state_provider: Callable
var on_changed: Callable
## Assigned by the owner: true while playtesting from the campaign editor - only then are the manual progress buttons (+ / -) shown. In real play feat progress
## comes from what happens in the missions.
var manual_marking := false
## Assigned by the owner: true inside a mission - the feat list is then read-only (it can only be rearranged on the campaign map).
var in_mission := false

var _hero_id := ""
const ACTIVE_COLOR := Color(0.95, 0.65, 0.2)
var _draft: Array[String] = []  ## the feat order being edited (not saved until "Apply the new order")
var _drafting := false
var _tabs: TabContainer
var _hero_row: HBoxContainer
var _skills_box: VBoxContainer
var _feats_box: VBoxContainer
var _apply_holder: HBoxContainer
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

	# The bottom row never scrolls away: the cost of a changed feat order with "Apply" / "Revert" (only while the order has been changed) next to Close.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	vbox.add_child(footer)
	_apply_holder = HBoxContainer.new()
	_apply_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_holder.add_theme_constant_override("separation", 8)
	footer.add_child(_apply_holder)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func(): visible = false)
	footer.add_child(close_button)

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
	_drafting = false
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
	for box in [_skills_box, _feats_box, _apply_holder]:
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
			_drafting = false
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
	var committed := state.feat_queue(campaign, _hero_id)
	var queue: Array[String] = _draft if _drafting else committed
	var limit := maxi(campaign.parallel_feats, 1)
	var live := state.active_feats(campaign, _hero_id)
	var editable := not in_mission
	var window := state.feat_window(campaign, _hero_id, queue)  # the feats this order would work on
	var costly := _drafting and CampaignState.feat_list_change_costs(committed, queue)
	var lost := state.feats_lost_by(campaign, _hero_id, queue) if costly else {}

	var header := Label.new()
	header.text = tr("Feat list - the first %d are active") % limit
	header.add_theme_font_size_override("font_size", 18)
	_feats_box.add_child(header)
	if in_mission:
		_feats_box.add_child(_wrapped(tr("The order can only be changed on the campaign map. When a feat is completed, the next one in the list starts by itself."), 520.0))
	else:
		_feats_box.add_child(_wrapped(tr("Feats at the top are worked on. When one is completed, the next unlocked one in the list starts by itself. Changing the order may cost something."), 520.0))
	if queue.is_empty():
		_feats_box.add_child(_wrapped(tr("The list is empty."), 520.0))
	for index in queue.size():
		_feats_box.add_child(_queue_row(campaign, state, queue, index, window, lost, live, editable))
	if _drafting and queue != committed:
		_apply_holder.add_child(_apply_bar(campaign, state, committed, queue))

	var completed := state.completed_feats(campaign, _hero_id)
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
	box.add_child(_wrapped(str(feat["description"]), 460.0))
	var info := Label.new()
	info.text = tr("Goal: %d") % int(feat["goal"]) + "    " + tr("Reward: %s") % _reward_text(campaign, feat)
	info.modulate = Color(1, 1, 1, 0.7)
	box.add_child(info)


## A framed row: orange and brighter for a feat that is being worked on, dim for one that is waiting in the list.
func _row_panel(active: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.30, 0.20, 0.08, 0.6) if active else Color(0.12, 0.13, 0.17, 0.5)
	style.border_color = ACTIVE_COLOR if active else Color(0.35, 0.38, 0.45)
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	return panel


## One feat of the list: its place, whether it is active, waiting or locked, its text and progress, and (on the map) the buttons that move or remove it in the draft order.
func _queue_row(campaign: Campaign, state: CampaignState, queue: Array[String], index: int, window: Array[String], lost: Dictionary, live: Dictionary, editable: bool) -> Control:
	var feat_id := queue[index]
	var feat := HeroData.feat(feat_id)
	var is_live := live.has(feat_id)
	var unlocked := state.feat_unlocked(campaign, _hero_id, feat_id)
	var highlighted := is_live or (_drafting and window.has(feat_id))
	var panel := _row_panel(highlighted)
	panel.modulate = Color.WHITE if highlighted else (Color(1, 1, 1, 0.75) if unlocked else Color(1, 1, 1, 0.55))
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	var number := Label.new()
	number.text = "%d" % (index + 1)
	number.add_theme_font_size_override("font_size", 22)
	number.modulate = ACTIVE_COLOR if highlighted else Color(1, 1, 1, 0.5)
	number.custom_minimum_size.x = 26
	number.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	outer.add_child(number)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(box)
	var status := Label.new()
	if is_live:
		status.text = "● " + tr("ACTIVE")
		status.modulate = ACTIVE_COLOR
	elif highlighted:
		status.text = "● " + tr("Starts when the new order is applied")
		status.modulate = ACTIVE_COLOR
	elif not unlocked:
		status.text = "🔒 " + _lock_text(campaign, state, feat)
		status.modulate = Color(1, 1, 1, 0.55)
	else:
		status.text = "○ " + tr("Waiting")
		status.modulate = Color(1, 1, 1, 0.55)
	status.add_theme_font_size_override("font_size", 13)
	box.add_child(status)
	_feat_texts(campaign, feat, box)
	if is_live:
		var progress := int(live[feat_id])
		box.add_child(_progress_row(feat, progress, not _drafting and manual_marking, campaign, state, feat_id))
		if lost.has(feat_id):
			var warning := Label.new()
			warning.text = tr("Its progress (%d) is lost when this order is applied.") % progress
			warning.modulate = Color(1.0, 0.55, 0.45)
			box.add_child(warning)

	if editable:
		var buttons := HBoxContainer.new()
		buttons.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var up := _button("▲", func(): _move_in_draft(campaign, state, index, -1))
		up.disabled = index == 0
		up.tooltip_text = tr("Move up")
		buttons.add_child(up)
		var down := _button("▼", func(): _move_in_draft(campaign, state, index, 1))
		down.disabled = index >= queue.size() - 1
		down.tooltip_text = tr("Move down")
		buttons.add_child(down)
		outer.add_child(buttons)
	return panel


## What a locked feat is waiting for: other feats of the hero that have to be completed first.
func _lock_text(campaign: Campaign, state: CampaignState, feat: Dictionary) -> String:
	var done := state.completed_feats(campaign, _hero_id)
	var parts: Array[String] = []
	if done.size() < int(feat["completed_required"]):
		parts.append(tr("%d completed feats") % int(feat["completed_required"]))
	for needed: String in feat["prerequisites"]:
		if not done.has(needed):
			parts.append(str(HeroData.feat(needed).get("title", needed)))
	return tr("Locked - needs: %s") % ", ".join(parts)


func _progress_row(feat: Dictionary, progress: int, with_marking: bool, campaign: Campaign, state: CampaignState, feat_id: String) -> Control:
	var row := HBoxContainer.new()
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
	fill.bg_color = ACTIVE_COLOR
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var count := Label.new()
	count.text = "%d / %d" % [progress, int(feat["goal"])]
	row.add_child(count)
	if with_marking:
		row.add_child(_manual_buttons(campaign, state, feat_id, progress))
	return row


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
		if not result["started"].is_empty():
			text += "\n" + tr("Next feat: %s") % ", ".join(result["started"])
		_notice.title = tr("Feat completed")
		_notice.dialog_text = text
		_notice.popup_centered()
	_drafting = false
	_changed()


# --- editing the order: a draft that is applied (and paid for) once --------------------------------------------------

## The draft order the buttons edit: made from the saved list the first time something changes.
func _edit_draft(campaign: Campaign, state: CampaignState) -> Array[String]:
	if not _drafting:
		_draft.clear()
		_draft.append_array(state.feat_queue(campaign, _hero_id))
		_drafting = true
	return _draft


func _move_in_draft(campaign: Campaign, state: CampaignState, index: int, delta: int) -> void:
	var draft := _edit_draft(campaign, state)
	var target := index + delta
	if target < 0 or target >= draft.size():
		return
	var moved := draft[index]
	draft[index] = draft[target]
	draft[target] = moved
	_refresh()


## The bar in the dialog's bottom row (next to Close, so it never scrolls away) while the order differs from the saved one: what applying costs, Apply and Revert.
func _apply_bar(campaign: Campaign, state: CampaignState, committed: Array[String], draft: Array[String]) -> Control:
	var costly := CampaignState.feat_list_change_costs(committed, draft)
	var problem := state.feat_change_problem(campaign, _hero_id) if costly else ""
	var note := state.feat_change_note(campaign, _hero_id) if costly else ""
	var bar := HBoxContainer.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 160.0
	if problem != "":
		label.text = problem
		label.modulate = Color(1.0, 0.55, 0.45)
	elif note != "":
		label.text = note
	else:
		label.text = tr("This change is free.")
	bar.add_child(label)
	var apply := _button(tr("Apply the new order"), func(): _ask_apply(campaign, state, committed, draft))
	apply.disabled = problem != ""
	bar.add_child(apply)
	bar.add_child(_button(tr("Revert"), func():
		_drafting = false
		_refresh()
	))
	return bar


func _ask_apply(campaign: Campaign, state: CampaignState, committed: Array[String], draft: Array[String]) -> void:
	var costly := CampaignState.feat_list_change_costs(committed, draft)
	var lost := state.feats_lost_by(campaign, _hero_id, draft) if costly else {}
	var note := state.feat_change_note(campaign, _hero_id) if costly else ""
	var apply := func():
		var wanted: Array[String] = []
		wanted.append_array(draft)
		if not state.set_feat_list(campaign, _hero_id, wanted, in_mission).is_empty():
			_drafting = false
			_changed()
	if lost.is_empty() and note == "":
		apply.call()
		return
	var text := tr("Apply the new feat order?")
	for feat_id in lost:
		text += "\n" + tr("Progress lost on \"%s\": %d") % [str(HeroData.feat(str(feat_id)).get("title", feat_id)), int(lost[feat_id])]
	if note != "":
		text += "\n" + note
	_confirm.title = tr("Change the feat order")
	_confirm.dialog_text = text
	_confirm_action = apply
	_confirm.popup_centered()


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button
