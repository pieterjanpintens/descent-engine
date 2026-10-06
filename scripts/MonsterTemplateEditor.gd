class_name MonsterTemplateEditor
extends Window

## The editor for the shared library of reusable monster templates
## (MonsterArchetype / MonsterArchetypeLibrary) - opened from the Creator's File
## menu ("Monster Templates…"). Left: the library's templates (New / Delete);
## right: the selected template's pins - its KIND (Base or Additive, see
## MonsterArchetype), name prefix/postfix, weaknesses/resistances/immunities,
## condition immunities, for BASE templates also attack range/reach, abilities and
## target rules, and the level-scaling tables for hitpoints, attack and defense
## (rows of "level min..max -> value", both ends inclusive; for an additive
## template the value is ADDED to the base's and may be negative) with a "preview
## at level" readout.
##
## Not tied to a mission, so it doesn't use the mission's undo history: every edit
## is written to the library file straight away (a rename saves under the new
## name and removes the old file). Templates are attached to spawned monsters in
## MonsterPropertiesDialog, which embeds a COPY; saved edits are pushed to those
## copies (see _sync_open_mission() and "Update all missions…").
##
## Built entirely in code, own copies of the small row/list builders (the project
## convention: each dialog owns its own).

## The Creator's open mission/undo history (assigned by CreatorSaveLoad): every
## saved edit also updates the monster copies in the OPEN mission, as one undo step.
var layered_map: LayeredMap
var operation_history: OperationHistory

var _working: MonsterArchetype
var _key: String = ""  ## library key of the template being edited ("" = none)
var _suppress: bool = false
var _keys: Array[String] = []

var _list: ItemList
var _delete_button: Button
var _form: VBoxContainer  ## the whole right side, disabled when nothing is selected
var _status: Label
var _name_edit: LineEdit
var _prefix_edit: LineEdit
var _postfix_edit: LineEdit
var _kind_option: OptionButton
var _base_only: VBoxContainer  ## the sections only a BASE template has (range/reach, abilities, target rules)
var _range_spin: SpinBox
var _reach_check: CheckBox
var _scaling_hint: Label
var _rule_rows: VBoxContainer
var _action_rows: VBoxContainer
var _action_hint: Label
var _check_boxes: Dictionary = {}  # prop -> Array[CheckBox], index = kind
var _name_rows: Dictionary = {}  # prop -> VBoxContainer
var _scaling_rows: Dictionary = {}  # prop -> VBoxContainer
var _preview_level: SpinBox
var _preview_label: Label
var _delete_confirm: ConfirmationDialog
var _update_all_confirm: ConfirmationDialog
var _notice: AcceptDialog


func _ready() -> void:
	title = "Monster Templates"
	min_size = Vector2i(420, 300)
	close_requested.connect(hide)
	visible = false

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)

	var split := HSplitContainer.new()
	margin.add_child(split)

	# --- left: the library
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(200, 0)
	split.add_child(left)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(index: int): _select_key(_keys[index]))
	left.add_child(_list)
	var buttons := HBoxContainer.new()
	left.add_child(buttons)
	var new_button := Button.new()
	new_button.text = "New"
	new_button.pressed.connect(_on_new_pressed)
	buttons.add_child(new_button)
	_delete_button = Button.new()
	_delete_button.text = "Delete"
	_delete_button.pressed.connect(func(): _delete_confirm.popup_centered())
	buttons.add_child(_delete_button)

	var update_all := Button.new()
	update_all.text = "Update all missions…"
	update_all.tooltip_text = "Apply the library to the monsters in every mission file in your missions folder"
	update_all.pressed.connect(func(): _update_all_confirm.popup_centered())
	left.add_child(update_all)

	_update_all_confirm = ConfirmationDialog.new()
	_update_all_confirm.dialog_text = "Update the monster templates in EVERY mission in your missions folder to the current library versions, and save those missions?"
	_update_all_confirm.confirmed.connect(_on_update_all_confirmed)
	add_child(_update_all_confirm)
	_notice = AcceptDialog.new()
	add_child(_notice)

	_delete_confirm = ConfirmationDialog.new()
	_delete_confirm.dialog_text = "Delete this template from the library? Monsters that already use it keep their copy."
	_delete_confirm.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_confirm)

	# --- right: the form
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_form)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	_form.add_child(_status)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Template name"
	_name_edit.text_submitted.connect(func(_t: String): _commit_name())
	_name_edit.focus_exited.connect(_commit_name)
	_form.add_child(_row("Name:", _name_edit))

	_kind_option = OptionButton.new()
	_kind_option.add_item("Base - defines the monster (one per monster)", MonsterArchetype.Kind.BASE)
	_kind_option.add_item("Additive - adds to the base", MonsterArchetype.Kind.ADDITIVE)
	_kind_option.item_selected.connect(_on_kind_selected)
	_form.add_child(_row("Kind:", _kind_option))

	_prefix_edit = LineEdit.new()
	_prefix_edit.placeholder_text = "e.g. \"Shady \" (include the space)"
	_prefix_edit.text_submitted.connect(func(_t: String): _commit_affix("name_prefix", _prefix_edit))
	_prefix_edit.focus_exited.connect(func(): _commit_affix("name_prefix", _prefix_edit))
	_form.add_child(_row("Prefix:", _prefix_edit))

	_postfix_edit = LineEdit.new()
	_postfix_edit.placeholder_text = "e.g. \" of the Shadowguild\" (include the space)"
	_postfix_edit.text_submitted.connect(func(_t: String): _commit_affix("name_postfix", _postfix_edit))
	_postfix_edit.focus_exited.connect(func(): _commit_affix("name_postfix", _postfix_edit))
	_form.add_child(_row("Postfix:", _postfix_edit))

	_add_check_group("Weaknesses", "weaknesses", Vulnerability.all(), func(k: int) -> String: return Vulnerability.display_name(k))
	_add_check_group("Resistances", "resistances", Vulnerability.all(), func(k: int) -> String: return Vulnerability.display_name(k))
	_add_check_group("Immunities", "immunities", Vulnerability.all(), func(k: int) -> String: return Vulnerability.display_name(k))
	_add_check_group("Condition immunities", "condition_immunities", MonsterCondition.all(), func(k: int) -> String: return MonsterCondition.display_name(k))

	# Sections only a BASE template has (an additive template's are ignored).
	_base_only = VBoxContainer.new()
	_form.add_child(_base_only)
	var attack_row := HBoxContainer.new()
	var range_caption := Label.new()
	range_caption.text = "Attack range:"
	attack_row.add_child(range_caption)
	_range_spin = SpinBox.new()
	_range_spin.min_value = 0
	_range_spin.max_value = 99
	_range_spin.value_changed.connect(func(v: float):
		if _suppress or _working == null:
			return
		_working.attack_range = int(v)
		_save()
	)
	attack_row.add_child(_range_spin)
	_reach_check = CheckBox.new()
	_reach_check.text = "Reach"
	_reach_check.toggled.connect(func(on: bool):
		if _suppress or _working == null:
			return
		_working.attack_reach = on
		_save()
	)
	attack_row.add_child(_reach_check)
	_base_only.add_child(attack_row)
	_add_name_list(_base_only, "Attack abilities", "attack_abilities", "ability_name", func() -> Resource: return MonsterAbility.new())
	_add_name_list(_base_only, "Defense abilities", "defense_abilities", "ability_name", func() -> Resource: return MonsterAbility.new())
	_add_rule_list(_base_only)
	_add_action_list(_base_only)

	var scaling_title := Label.new()
	scaling_title.text = "Level scaling"
	scaling_title.add_theme_font_size_override("font_size", 18)
	_form.add_child(scaling_title)
	_scaling_hint = Label.new()
	_scaling_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_scaling_hint.modulate = Color(1, 1, 1, 0.7)
	_form.add_child(_scaling_hint)
	_add_scaling_list("Hitpoints", "hitpoints_scaling")
	_add_scaling_list("Attack damage", "attack_scaling")
	_add_scaling_list("Defense", "defense_scaling")
	_add_scaling_list("Speed", "speed_scaling")

	var preview_row := HBoxContainer.new()
	var preview_caption := Label.new()
	preview_caption.text = "Preview at level"
	preview_row.add_child(preview_caption)
	_preview_level = SpinBox.new()
	_preview_level.min_value = 0
	_preview_level.max_value = 99
	_preview_level.value = 1
	_preview_level.value_changed.connect(func(_v: float): _refresh_preview())
	preview_row.add_child(_preview_level)
	_preview_label = Label.new()
	preview_row.add_child(_preview_label)
	_form.add_child(preview_row)


## Opens the window on the library's current contents.
func open() -> void:
	_refresh_list("")
	# Clamped to 90% of the game window so it always fits (the form scrolls).
	popup_centered_clamped(Vector2i(820, 720), 0.9)


# ---------------------------------------------------------------- library

## Fills the list with every template, marked "(additive)" where it is one.
func _fill_list() -> void:
	_keys = MonsterArchetypeLibrary.names()
	_list.clear()
	for key in _keys:
		var archetype := MonsterArchetypeLibrary.load_template(key)
		var additive := archetype != null and archetype.kind == MonsterArchetype.Kind.ADDITIVE
		_list.add_item(key + ("  (additive)" if additive else "  (base)"))


func _refresh_list(select_key: String) -> void:
	_fill_list()
	var index := _keys.find(select_key)
	if index < 0 and not _keys.is_empty() and select_key == "":
		index = 0
	if index >= 0:
		_list.select(index)
		_select_key(_keys[index])
	else:
		_working = null
		_key = ""
		_update_form_enabled()


func _select_key(key: String) -> void:
	_working = MonsterArchetypeLibrary.load_template(key)
	_key = key if _working != null else ""
	_status.text = ""
	_populate()


func _on_new_pressed() -> void:
	var base_name := "New template"
	var candidate := base_name
	var n := 2
	while MonsterArchetypeLibrary.names().has(MonsterArchetypeLibrary.key_for(candidate)):
		candidate = "%s %d" % [base_name, n]
		n += 1
	var created := MonsterArchetype.new()
	created.template_name = candidate
	var key := MonsterArchetypeLibrary.save_template(created)
	_refresh_list(key)


func _on_delete_confirmed() -> void:
	if _key == "":
		return
	MonsterArchetypeLibrary.delete_template(_key)
	_refresh_list("")


## Writes the working copy to the library after an edit. A changed name is a
## rename (new file, old one removed) - refused if blank or already taken.
func _save() -> void:
	if _working == null or _suppress:
		return
	var new_key := MonsterArchetypeLibrary.key_for(_working.template_name)
	if new_key == "":
		_status.text = "A template needs a name."
		return
	if new_key != _key and MonsterArchetypeLibrary.names().has(new_key):
		_status.text = "A template called '%s' already exists." % new_key
		return
	_status.text = ""
	var saved := MonsterArchetypeLibrary.save_template(_working)
	if saved == "":
		_status.text = "Could not save the template."
		return
	if _key != "" and saved != _key:
		MonsterArchetypeLibrary.delete_template(_key)
	var renamed := saved != _key
	_key = saved
	if renamed:
		_refresh_keep(saved)
	_refresh_preview()
	_sync_open_mission()


## Re-lists the library after a rename without reloading the working copy.
func _refresh_keep(select_key: String) -> void:
	_fill_list()
	var index := _keys.find(select_key)
	if index >= 0:
		_list.select(index)


# ---------------------------------------------------------------- form

func _update_form_enabled() -> void:
	var has_template := _working != null
	_delete_button.disabled = not has_template
	_form.modulate.a = 1.0 if has_template else 0.4
	for control in _form.find_children("*", "Control", true, false):
		if control is BaseButton:
			(control as BaseButton).disabled = not has_template
		elif control is LineEdit:
			(control as LineEdit).editable = has_template
		elif control is SpinBox:
			(control as SpinBox).editable = has_template


func _populate() -> void:
	_suppress = true
	if _working != null:
		_name_edit.text = _working.template_name
		_prefix_edit.text = _working.name_prefix
		_postfix_edit.text = _working.name_postfix
		_kind_option.select(_kind_option.get_item_index(_working.kind))
		_range_spin.value = _working.attack_range
		_reach_check.button_pressed = _working.attack_reach
		_apply_kind()
		for prop in _check_boxes:
			var chosen: Array = _working.get(prop)
			var boxes: Array = _check_boxes[prop]
			for kind in boxes.size():
				(boxes[kind] as CheckBox).button_pressed = chosen.has(kind)
		_rebuild_rule_rows()
		_rebuild_action_rows()
		for prop in _name_rows:
			_rebuild_name_rows(prop)
		for prop in _scaling_rows:
			_rebuild_scaling_rows(prop)
	_suppress = false
	_update_form_enabled()
	_refresh_preview()


func _commit_name() -> void:
	if _suppress or _working == null:
		return
	var text := _name_edit.text.strip_edges()
	if text == _working.template_name:
		return
	var previous := _working.template_name
	_working.template_name = text
	_save()
	if _status.text != "":
		# Refused (blank / taken) - put the old name back in the working copy and field.
		_working.template_name = previous
		_suppress = true
		_name_edit.text = previous
		_suppress = false


func _commit_affix(prop: String, edit: LineEdit) -> void:
	if _suppress or _working == null or str(_working.get(prop)) == edit.text:
		return
	_working.set(prop, edit.text)  # verbatim - the spaces matter
	_save()


func _add_check_group(title_text: String, prop: String, kinds: Array[int], display: Callable) -> void:
	var title_label := Label.new()
	title_label.text = title_text + ":"
	_form.add_child(title_label)
	var grid := GridContainer.new()
	grid.columns = 3
	_form.add_child(grid)
	var boxes: Array = []
	for kind in kinds:
		var box := CheckBox.new()
		box.text = display.call(kind)
		box.toggled.connect(func(_on: bool): _commit_checks(prop))
		grid.add_child(box)
		boxes.append(box)
	_check_boxes[prop] = boxes


func _commit_checks(prop: String) -> void:
	if _suppress or _working == null:
		return
	var chosen: Array[int] = []
	var boxes: Array = _check_boxes[prop]
	for kind in boxes.size():
		if (boxes[kind] as CheckBox).button_pressed:
			chosen.append(kind)
	_working.set(prop, chosen)
	_save()


func _add_name_list(parent: Control, title_text: String, prop: String, name_prop: String, make_item: Callable) -> void:
	var title_label := Label.new()
	title_label.text = title_text + ":"
	parent.add_child(title_label)
	var rows := VBoxContainer.new()
	rows.set_meta("name_prop", name_prop)
	parent.add_child(rows)
	_name_rows[prop] = rows
	var add := Button.new()
	add.text = "Add"
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(func():
		if _working == null:
			return
		(_working.get(prop) as Array).append(make_item.call())
		_save()
		_rebuild_name_rows(prop)
	)
	parent.add_child(add)


func _rebuild_name_rows(prop: String) -> void:
	var rows: VBoxContainer = _name_rows[prop]
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	if _working == null:
		return
	var name_prop: String = rows.get_meta("name_prop")
	for item: Resource in _working.get(prop):
		var row := HBoxContainer.new()
		var edit := LineEdit.new()
		edit.text = str(item.get(name_prop))
		edit.placeholder_text = "Name"
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var commit := func():
			if _suppress or str(item.get(name_prop)) == edit.text:
				return
			item.set(name_prop, edit.text)
			_save()
		edit.text_submitted.connect(func(_t: String): commit.call())
		edit.focus_exited.connect(commit)
		row.add_child(edit)
		# Attack abilities can have a behavior the engine acts on (MonsterAbility.Behavior).
		if prop == "attack_abilities":
			var behavior_picker := OptionButton.new()
			for behavior in MonsterAbility.Behavior.values():
				behavior_picker.add_item(MonsterAbility.behavior_name(behavior), behavior)
			behavior_picker.select(behavior_picker.get_item_index((item as MonsterAbility).behavior))
			behavior_picker.item_selected.connect(func(index: int):
				if _suppress:
					return
				(item as MonsterAbility).behavior = behavior_picker.get_item_id(index) as MonsterAbility.Behavior
				_save()
			)
			row.add_child(behavior_picker)
		var remove := Button.new()
		remove.text = "×"
		remove.pressed.connect(func():
			(_working.get(prop) as Array).erase(item)
			_save()
			_rebuild_name_rows(prop)
		)
		row.add_child(remove)
		rows.add_child(row)


## The base template's preferred-target rules: an ordered list of rule KINDS (see
## TargetRule) - the monster tries them top to bottom, the first that finds a hero
## wins, else a random hero. Each row: kind picker, move up/down, remove.
func _add_rule_list(parent: Control) -> void:
	var title_label := Label.new()
	title_label.text = "Preferred targets (tried in order, else a random hero):"
	parent.add_child(title_label)
	_rule_rows = VBoxContainer.new()
	parent.add_child(_rule_rows)
	var add := Button.new()
	add.text = "Add rule"
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(func():
		if _working == null:
			return
		_working.target_rules.append(TargetRule.new())
		_save()
		_rebuild_rule_rows()
	)
	parent.add_child(add)


func _rebuild_rule_rows() -> void:
	for child in _rule_rows.get_children():
		_rule_rows.remove_child(child)
		child.queue_free()
	if _working == null:
		return
	var rules := _working.target_rules
	for i in rules.size():
		var rule: TargetRule = rules[i]
		var row := HBoxContainer.new()
		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for kind in TargetRule.Kind.values():
			picker.add_item(TargetRule.kind_name(kind), kind)
			picker.set_item_tooltip(picker.item_count - 1, TargetRule.description(kind))
		picker.select(picker.get_item_index(rule.kind))
		picker.tooltip_text = TargetRule.description(rule.kind)
		row.add_child(picker)
		# Fixed hero: which hero (only shown for that rule kind).
		var hero_picker := OptionButton.new()
		for slot in HeroCatalog.SLOT_COUNT:
			hero_picker.add_item(HeroCatalog.slot_name(slot), slot)
		hero_picker.select(hero_picker.get_item_index(rule.hero_slot))
		hero_picker.visible = rule.kind == TargetRule.Kind.FIXED_HERO
		hero_picker.item_selected.connect(func(index: int):
			if _suppress:
				return
			rule.hero_slot = hero_picker.get_item_id(index)
			_save()
		)
		picker.item_selected.connect(func(index: int):
			if _suppress:
				return
			rule.kind = picker.get_item_id(index) as TargetRule.Kind
			picker.tooltip_text = TargetRule.description(rule.kind)
			hero_picker.visible = rule.kind == TargetRule.Kind.FIXED_HERO
			_save()
		)
		row.add_child(hero_picker)
		var up := Button.new()
		up.text = "↑"
		up.disabled = i == 0
		up.pressed.connect(func(): _move_rule(i, -1))
		row.add_child(up)
		var down := Button.new()
		down.text = "↓"
		down.disabled = i == rules.size() - 1
		down.pressed.connect(func(): _move_rule(i, 1))
		row.add_child(down)
		var remove := Button.new()
		remove.text = "×"
		remove.pressed.connect(func():
			rules.remove_at(i)
			_save()
			_rebuild_rule_rows()
		)
		row.add_child(remove)
		_rule_rows.add_child(row)


## The base template's Confused actions (MonsterAction): what the monster does instead of
## attacking while Confused - one is picked at random among the possible ones. An empty
## list uses the built-in defaults; "Fill with defaults" copies them in to edit.
func _add_action_list(parent: Control) -> void:
	var title_label := Label.new()
	title_label.text = "Confused actions (instead of attacking):"
	parent.add_child(title_label)
	_action_hint = Label.new()
	_action_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_action_hint.modulate = Color(1, 1, 1, 0.7)
	_action_hint.text = "Empty: the built-in default actions are used. {speed} and {damage} in a text are filled in. A required prop is a reference or mesh name (\"gate\"; several with commas)."
	parent.add_child(_action_hint)
	_action_rows = VBoxContainer.new()
	parent.add_child(_action_rows)
	var buttons := HBoxContainer.new()
	parent.add_child(buttons)
	var add := Button.new()
	add.text = "Add action"
	add.pressed.connect(func():
		if _working == null:
			return
		_working.confused_actions.append(MonsterAction.new("New action", "Describe what the monster does."))
		_save()
		_rebuild_action_rows()
	)
	buttons.add_child(add)
	var fill := Button.new()
	fill.text = "Fill with defaults"
	fill.pressed.connect(func():
		if _working == null:
			return
		_working.confused_actions = MonsterAction.defaults()
		_save()
		_rebuild_action_rows()
	)
	buttons.add_child(fill)


func _rebuild_action_rows() -> void:
	for child in _action_rows.get_children():
		_action_rows.remove_child(child)
		child.queue_free()
	if _working == null:
		return
	for action in _working.confused_actions:
		var block := VBoxContainer.new()
		var top := HBoxContainer.new()
		top.add_child(_action_text_field(action, "action_name", "Name", false))
		top.add_child(_caption("Needs prop"))
		var needs := _action_text_field(action, "required_object", "none", false)
		needs.custom_minimum_size.x = 90
		needs.size_flags_horizontal = Control.SIZE_FILL
		top.add_child(needs)
		top.add_child(_caption("Monsters ≥"))
		top.add_child(_level_spin(action, "min_monsters", 0, 99))
		top.add_child(_caption("Weight"))
		top.add_child(_level_spin(action, "weight", 1, 99))
		var remove := Button.new()
		remove.text = "×"
		remove.pressed.connect(func():
			_working.confused_actions.erase(action)
			_save()
			_rebuild_action_rows()
		)
		top.add_child(remove)
		block.add_child(top)
		block.add_child(_action_text_field(action, "text", "What the monster does", true))
		block.add_child(HSeparator.new())
		_action_rows.add_child(block)


## A LineEdit bound to a text property of `action`, committed on Enter / focus lost.
func _action_text_field(action: MonsterAction, prop: String, placeholder: String, expand: bool) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = str(action.get(prop))
	edit.placeholder_text = placeholder
	if expand:
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL if prop == "action_name" else Control.SIZE_FILL
	var commit := func():
		if _suppress or str(action.get(prop)) == edit.text:
			return
		action.set(prop, edit.text)
		_save()
	edit.text_submitted.connect(func(_t: String): commit.call())
	edit.focus_exited.connect(commit)
	return edit


func _move_rule(index: int, delta: int) -> void:
	var rules := _working.target_rules
	var other := index + delta
	if other < 0 or other >= rules.size():
		return
	var moved: TargetRule = rules[index]
	rules[index] = rules[other]
	rules[other] = moved
	_save()
	_rebuild_rule_rows()


func _add_scaling_list(title_text: String, prop: String) -> void:
	var title_label := Label.new()
	title_label.text = title_text + ":"
	_form.add_child(title_label)
	var rows := VBoxContainer.new()
	_form.add_child(rows)
	_scaling_rows[prop] = rows
	var add := Button.new()
	add.text = "Add row"
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(func():
		if _working == null:
			return
		# A new row continues where the table ends (after the highest max level, or
		# from level 1 in an empty table) and spans two levels: 1-2, 3-4, 5-6...
		var row := LevelValue.new()
		var next_level := 1
		for existing: LevelValue in _working.get(prop):
			next_level = maxi(next_level, existing.max_level + 1)
		row.min_level = mini(next_level, 98)
		row.max_level = row.min_level + 1
		(_working.get(prop) as Array).append(row)
		_save()
		_rebuild_scaling_rows(prop)
	)
	_form.add_child(add)


func _rebuild_scaling_rows(prop: String) -> void:
	var rows: VBoxContainer = _scaling_rows[prop]
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	if _working == null:
		return
	for item: LevelValue in _working.get(prop):
		var row := HBoxContainer.new()
		row.add_child(_caption("Level"))
		row.add_child(_level_spin(item, "min_level", 0, 99))
		row.add_child(_caption("to"))
		row.add_child(_level_spin(item, "max_level", 0, 99))
		row.add_child(_caption("→ adds" if _working.kind == MonsterArchetype.Kind.ADDITIVE else "→ value"))
		row.add_child(_level_spin(item, "value", -9999, 9999))
		var remove := Button.new()
		remove.text = "×"
		remove.pressed.connect(func():
			(_working.get(prop) as Array).erase(item)
			_save()
			_rebuild_scaling_rows(prop)
		)
		row.add_child(remove)
		rows.add_child(row)


func _level_spin(item: Resource, field: String, min_value: int, max_value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = 1
	spin.value = item.get(field)
	spin.value_changed.connect(func(v: float):
		if _suppress:
			return
		item.set(field, int(v))
		_save()
	)
	return spin


func _refresh_preview() -> void:
	if _working == null:
		_preview_label.text = ""
		return
	var level := int(_preview_level.value)
	var signed_values := _working.kind == MonsterArchetype.Kind.ADDITIVE
	_preview_label.text = "  hitpoints %s, attack %s, defense %s, speed %s" % [
		_table_value(_working.hitpoints_scaling, level, signed_values),
		_table_value(_working.attack_scaling, level, signed_values),
		_table_value(_working.defense_scaling, level, signed_values),
		_table_value(_working.speed_scaling, level, signed_values),
	]


## The table's value at `level` ("-" for an empty table), "+N" style for additive.
func _table_value(table: Array[LevelValue], level: int, signed_value: bool) -> String:
	if not LevelValue.has_rows(table):
		return "-"
	var value := LevelValue.pick(table, level)
	return ("%+d" % value) if signed_value else str(value)


func _on_kind_selected(index: int) -> void:
	if _suppress or _working == null:
		return
	_working.kind = _kind_option.get_item_id(index) as MonsterArchetype.Kind
	_apply_kind()
	_save()
	_fill_list()
	var list_index := _keys.find(_key)
	if list_index >= 0:
		_list.select(list_index)


## Shows/hides what only a base template has and re-captions the scaling tables.
func _apply_kind() -> void:
	var is_base := _working == null or _working.kind == MonsterArchetype.Kind.BASE
	_base_only.visible = is_base
	_scaling_hint.text = ("A row applies when the monster's level is within min..max (inclusive); a level outside every row uses the closest row. The value is the stat itself." if is_base
		else "A row applies when the monster's level is within min..max (inclusive); a level outside every row uses the closest row. The value is ADDED to the base template's (it may be negative).")
	for prop in _scaling_rows:
		_rebuild_scaling_rows(prop)


## After a library edit: bring the monster copies in the currently open mission
## up to date, as one undo step (nothing happens if none is out of date).
func _sync_open_mission() -> void:
	if layered_map == null or layered_map.mission == null or operation_history == null:
		return
	var mission := layered_map.mission
	if MonsterArchetypeLibrary.sync_mission(mission, false) == 0:
		return
	operation_history.record("Update monster templates", func(): MonsterArchetypeLibrary.sync_mission(mission))


func _on_update_all_confirmed() -> void:
	var result := MonsterArchetypeLibrary.update_missions_in("user://missions")
	_notice.dialog_text = "Updated %d monster(s) in %d mission(s).\nA mission that is open in the Creator right now keeps its current state - reload it to see the update." % [result["monsters"], result["missions"]]
	_notice.popup_centered()


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(80, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row
