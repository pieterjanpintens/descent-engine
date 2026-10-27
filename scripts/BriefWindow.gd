class_name BriefWindow
extends Window

## The brief of ONE mission chapter of the plan (MissionBrief), opened from the plan window ("Brief…" on a mission chapter): the
## goal, the objectives (win / lose / optional), the variables, the monsters, notes on the map and the key moments. "Write the
## brief with AI" (optional, AiClient.is_configured()) fills it in from the chapter's summary, its manuscript section and the notes
## - the author edits everything. "Create the mission file" then makes an EMPTY skeleton mission with the objectives and variables
## (BriefBuilder, no AI) and gives the chapter that file; the map is drawn in the mission editor. Edits go straight into the plan
## chapter's `brief` (`on_edit` saves the plan); making the mission changes the campaign (`on_changed`).

const HINT_COLOR := Color(0.65, 0.65, 0.7)
const SECTION_COLOR := Color(0.95, 0.80, 0.45)
const WARN_COLOR := Color(1.0, 0.7, 0.3)
const KIND_LABELS := ["Win", "Lose", "Optional"]

var campaign: Campaign
var folder := ""
var read_only := false
var act_plan: Dictionary = {}
var chapter_plan: Dictionary = {}
## Called after the brief changed (the plan window saves the plan).
var on_edit: Callable
## Called after the campaign changed (the campaign editor records an undo step and refreshes).
var on_changed: Callable
## Tests give the generator a stub client.
var generator: BriefGenerator

var _body: VBoxContainer
var _title_label: Label
var _status_label: Label
var _generate_button: Button
var _cancel_button: Button
var _create_button: Button
var _confirm: ConfirmationDialog
var _rebuilding := false


func _ready() -> void:
	close_requested.connect(hide)
	visible = false
	generator = BriefGenerator.new()
	add_child(generator)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.clip_text = true
	top.add_child(_title_label)
	_generate_button = _button("Write the brief with AI", _on_generate_pressed)
	top.add_child(_generate_button)
	_cancel_button = _button("Cancel", func(): generator.cancel())
	_cancel_button.visible = false
	top.add_child(_cancel_button)
	_create_button = _button("Create the mission file", _on_create_pressed)
	top.add_child(_create_button)
	top.add_child(_button("Close", hide))
	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", HINT_COLOR)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.x = 500
	column.add_child(_status_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Create the mission file?"
	_confirm.ok_button_text = "Create"
	_confirm.confirmed.connect(_create_mission)
	add_child(_confirm)


func open_for(p_campaign: Campaign, p_folder: String, p_read_only: bool, p_act_plan: Dictionary, p_chapter_plan: Dictionary, p_on_edit: Callable, p_on_changed: Callable) -> void:
	campaign = p_campaign
	folder = p_folder
	read_only = p_read_only
	act_plan = p_act_plan
	chapter_plan = p_chapter_plan
	on_edit = p_on_edit
	on_changed = p_on_changed
	if typeof(chapter_plan.get("brief")) != TYPE_DICTIONARY:
		chapter_plan["brief"] = MissionBrief.empty()
	title = "Mission brief - %s" % chapter_plan["title"]
	_title_label.text = "Mission brief: %s" % chapter_plan["title"]
	_status_label.text = "Summary: %s" % chapter_plan["summary"] if chapter_plan["summary"] != "" else ""
	_refresh_buttons()
	_rebuild()
	popup_centered_clamped(Vector2i(1000, 700), 0.92)


func _brief() -> Dictionary:
	return chapter_plan["brief"]


func _chapter() -> CampaignChapter:
	if chapter_plan["built"] == "":
		return null
	for act in campaign.acts:
		var found := act.find_chapter(chapter_plan["built"])
		if found != null:
			return found
	return null


func _refresh_buttons() -> void:
	_generate_button.disabled = read_only or not AiClient.is_configured()
	_generate_button.tooltip_text = "Sends the chapter's summary, its manuscript section and your notes to your AI account." if AiClient.is_configured() \
		else "Switch AI help on in Options (AI tab) to let the AI write a brief. You can fill it in by hand."
	var blocked := BriefBuilder.problem(_chapter(), _brief(), folder)
	_create_button.disabled = read_only or blocked != ""
	_create_button.tooltip_text = blocked if blocked != "" else "Makes an empty mission with these objectives and variables (no map) and gives the chapter that file."


# ---------------------------------------------------------------- generating

func _on_generate_pressed() -> void:
	if generator.is_busy():
		return
	_generate_button.disabled = true
	_cancel_button.visible = true
	_status_label.text = "Asking the AI..."
	var result := await generator.generate(folder, campaign, act_plan, chapter_plan)
	if not is_instance_valid(self):
		return
	_cancel_button.visible = false
	if result.get("cancelled", false):
		_status_label.text = "Cancelled."
	elif not result["ok"]:
		_status_label.text = str(result["error"])
	else:
		var keep: String = _brief().get("built_file", "")
		chapter_plan["brief"] = result["brief"]
		_brief()["built_file"] = keep
		_status_label.text = "The AI wrote this brief - check and edit it." + ("" if result["dropped"].is_empty() else " (%d unusable part(s) were left out.)" % result["dropped"].size())
		_edited()
		_rebuild()
	_refresh_buttons()


# ---------------------------------------------------------------- creating the mission

func _on_create_pressed() -> void:
	var blocked := BriefBuilder.problem(_chapter(), _brief(), folder)
	if blocked != "":
		_status_label.text = blocked
		return
	var objectives: Array = _brief()["objectives"]
	_confirm.dialog_text = "This makes an EMPTY mission file (no map) for '%s' with %d objective(s) and %d variable(s). Every objective waits on its own variable (for example objective_1_done) that you wire up in the mission editor, where you also draw the map. Undo works in the campaign editor. Continue?" % [chapter_plan["title"], objectives.size(), _brief()["variables"].size() + objectives.size()]
	_confirm.popup_centered()


func _create_mission() -> void:
	var result := BriefBuilder.create_mission(_chapter(), _brief(), campaign, folder)
	if not result["ok"]:
		_status_label.text = str(result["error"])
		return
	_edited()
	if on_changed.is_valid():
		on_changed.call()
	_status_label.text = "Created %s in the campaign folder. Open it in the mission editor to draw the map and wire up the objective variables." % result["file"]
	_refresh_buttons()
	_rebuild()


# ---------------------------------------------------------------- the fields

func _rebuild() -> void:
	_rebuilding = true
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var brief := _brief()
	if brief["built_file"] != "":
		_body.add_child(_hint("Mission file made from this brief: %s" % brief["built_file"]))
	_body.add_child(_heading("GOAL"))
	_body.add_child(_text_edit(brief["goal"], 56, "What the players must achieve", func(text: String): brief["goal"] = text))
	_body.add_child(_heading("OBJECTIVES  (win = steps in this order, the last ends the mission; lose = ways to fail; optional = bonus)"))
	for objective in brief["objectives"]:
		_body.add_child(_objective_row(objective))
	_body.add_child(_add_button("+ Add objective", func():
		brief["objectives"].append({"kind": "win", "description": ""})
		_edited()
		_rebuild()
	))
	_body.add_child(_heading("VARIABLES  (the mission is made with these, plus one per objective)"))
	for variable in brief["variables"]:
		_body.add_child(_variable_row(variable))
	_body.add_child(_add_button("+ Add variable", func():
		brief["variables"].append({"name": "new_variable", "type": "bool", "default": false, "purpose": ""})
		_edited()
		_rebuild()
	))
	_body.add_child(_heading("MONSTERS"))
	for monster in brief["monsters"]:
		_body.add_child(_monster_row(monster))
	_body.add_child(_add_button("+ Add monster", func():
		brief["monsters"].append({"name": "", "count": 1, "notes": ""})
		_edited()
		_rebuild()
	))
	_body.add_child(_heading("KEY MOMENTS  (one per line)"))
	_body.add_child(_text_edit("\n".join(PackedStringArray(brief["key_moments"])), 90, "What happens during the mission", func(text: String):
		var lines: Array = []
		for line in text.split("\n", false):
			if line.strip_edges() != "":
				lines.append(line.strip_edges())
		brief["key_moments"] = lines
	))
	_body.add_child(_heading("MAP NOTES  (words only - you draw the map in the mission editor)"))
	_body.add_child(_text_edit(brief["map_notes"], 90, "Rooms, atmosphere, important places and objects", func(text: String): brief["map_notes"] = text))
	_rebuilding = false


func _objective_row(objective: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var kind := OptionButton.new()
	for label in KIND_LABELS:
		kind.add_item(label)
	kind.select(MissionBrief.KINDS.find(objective["kind"]))
	kind.disabled = read_only
	kind.item_selected.connect(func(index: int):
		objective["kind"] = MissionBrief.KINDS[index]
		_edited()
		_refresh_buttons()
	)
	row.add_child(kind)
	row.add_child(_line(objective["description"], func(text: String): objective["description"] = text))
	row.add_child(_remove_button(func():
		_brief()["objectives"].erase(objective)
		_edited()
		_rebuild()
		_refresh_buttons()
	))
	return row


func _variable_row(variable: Dictionary) -> Control:
	var row := HFlowContainer.new()
	var name_edit := _line(variable["name"], func(text: String): variable["name"] = text.strip_edges().to_lower().replace(" ", "_"))
	name_edit.custom_minimum_size.x = 170
	name_edit.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(name_edit)
	var type := OptionButton.new()
	for type_name in CampaignPlan.TYPES:
		type.add_item(type_name)
	type.select(CampaignPlan.TYPES.find(variable["type"]))
	type.disabled = read_only
	row.add_child(type)
	var default_edit := _line(str(variable["default"]), func(_text: String): pass)
	default_edit.custom_minimum_size.x = 90
	default_edit.size_flags_horizontal = Control.SIZE_FILL
	var commit_default := func(text: String):
		variable["default"] = CampaignPlan.coerce_default(variable["type"], text)
		default_edit.text = str(variable["default"])
		_edited()
	default_edit.text_submitted.connect(commit_default)
	default_edit.focus_exited.connect(func(): commit_default.call(default_edit.text))
	type.item_selected.connect(func(index: int):
		variable["type"] = CampaignPlan.TYPES[index]
		variable["default"] = CampaignPlan.coerce_default(variable["type"], variable["default"])
		default_edit.text = str(variable["default"])
		_edited()
	)
	row.add_child(default_edit)
	var purpose := _line(variable["purpose"], func(text: String): variable["purpose"] = text)
	purpose.custom_minimum_size.x = 260
	row.add_child(purpose)
	row.add_child(_remove_button(func():
		_brief()["variables"].erase(variable)
		_edited()
		_rebuild()
	))
	return row


func _monster_row(monster: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var name_edit := _line(monster["name"], func(text: String): monster["name"] = text)
	name_edit.custom_minimum_size.x = 160
	name_edit.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(name_edit)
	var count := SpinBox.new()
	count.min_value = 1
	count.max_value = 99
	count.value = monster["count"]
	count.editable = not read_only
	count.value_changed.connect(func(value: float):
		monster["count"] = int(value)
		_edited()
	)
	row.add_child(count)
	row.add_child(_line(monster["notes"], func(text: String): monster["notes"] = text))
	row.add_child(_remove_button(func():
		_brief()["monsters"].erase(monster)
		_edited()
		_rebuild()
	))
	return row


func _edited() -> void:
	if _rebuilding or read_only:
		return
	if on_edit.is_valid():
		on_edit.call()
	_refresh_buttons()


# ---------------------------------------------------------------- small builders

func _line(text: String, on_change: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.editable = not read_only
	edit.text_changed.connect(func(value: String):
		on_change.call(value)
		_edited()
	)
	return edit


func _text_edit(text: String, height: float, placeholder: String, on_change: Callable) -> TextEdit:
	var edit := TextEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.custom_minimum_size.y = height
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.editable = not read_only
	edit.text_changed.connect(func():
		on_change.call(edit.text)
		_edited()
	)
	return edit


func _remove_button(on_pressed: Callable) -> Button:
	var button := _button("×", on_pressed)
	button.disabled = read_only
	button.tooltip_text = "Remove"
	return button


func _add_button(text: String, on_pressed: Callable) -> Button:
	var button := _button(text, on_pressed)
	button.disabled = read_only
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return button


func _heading(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HeadingLabel"
	label.text = text
	label.add_theme_color_override("font_color", SECTION_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 400
	return label


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HINT_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 400
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button
