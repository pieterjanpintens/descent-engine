class_name PlanWindow
extends Window

## The review list of the campaign PLAN (CampaignPlan): opened from the writing workspace ("Plan…"). "Generate plan" asks the AI
## (optional, AiClient.is_configured()) to work the manuscript and notes out into acts, chapters, characters and variables;
## the author then accepts or rejects every item and edits what is wrong. The plan is saved by itself in the campaign's
## `notes/plan.json` (private). Nothing here changes the campaign - building real chapters from the accepted items is the next
## step (the Build button is a placeholder). Full screen like the other writing windows.

const SAVE_DELAY_SEC := 0.8
const SECTION_COLOR := Color(0.95, 0.80, 0.45)
const HINT_COLOR := Color(0.65, 0.65, 0.7)
const WARN_COLOR := Color(1.0, 0.7, 0.3)
const KIND_LABELS := ["Narrative", "Mission"]

var campaign: Campaign
var folder := ""
var read_only := false
## Tests give the generator a stub client before pressing Generate.
var generator: PlanGenerator

var _plan: Dictionary = CampaignPlan.empty()
var _save_timer: Timer
var _body: VBoxContainer
var _generate_button: Button
var _cancel_button: Button
var _status_label: Label
var _count_label: Label
var _note_label: Label
var _confirm: ConfirmationDialog
var _rebuilding := false


func _ready() -> void:
	close_requested.connect(hide)
	visibility_changed.connect(func():
		if not visible:
			_save_now()
	)
	visible = false
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY_SEC
	_save_timer.timeout.connect(_save_now)
	add_child(_save_timer)
	generator = PlanGenerator.new()
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
	var heading := Label.new()
	heading.text = "Campaign plan"
	heading.add_theme_font_size_override("font_size", 20)
	top.add_child(heading)
	_generate_button = _button("Generate plan from the manuscript", _on_generate_pressed)
	top.add_child(_generate_button)
	_cancel_button = _button("Cancel", func(): generator.cancel())
	_cancel_button.visible = false
	top.add_child(_cancel_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_count_label = Label.new()
	_count_label.add_theme_color_override("font_color", HINT_COLOR)
	top.add_child(_count_label)
	top.add_child(_button("Accept all new", func(): _set_all(true)))
	top.add_child(_button("Reject all", func(): _set_all(false)))
	var build := _button("Build accepted items (next step)", func(): pass)
	build.disabled = true
	build.tooltip_text = "Creating the chapters, characters and variables from the accepted items is the next step of the workspace."
	top.add_child(build)
	top.add_child(_button("Close", hide))

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", HINT_COLOR)
	column.add_child(_status_label)
	_note_label = Label.new()
	_note_label.add_theme_color_override("font_color", WARN_COLOR)
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.custom_minimum_size.x = 500
	_note_label.visible = false
	column.add_child(_note_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Replace the plan?"
	_confirm.dialog_text = "Making a new plan replaces the current one, including what you accepted, rejected or edited. Continue?"
	_confirm.ok_button_text = "Replace"
	_confirm.confirmed.connect(_generate)
	add_child(_confirm)


func open_for(p_campaign: Campaign, p_folder: String, p_read_only: bool = false) -> void:
	campaign = p_campaign
	folder = p_folder
	read_only = p_read_only
	_plan = CampaignPlan.load_plan(folder)
	title = "Plan - %s" % campaign.campaign_name
	_note_label.visible = false
	_status_label.text = ""
	_refresh_generate_button()
	_rebuild()
	_show_full_screen()


func _refresh_generate_button() -> void:
	_generate_button.disabled = read_only or not AiClient.is_configured()
	if read_only:
		_generate_button.tooltip_text = "A release has no writing workspace."
	elif not AiClient.is_configured():
		_generate_button.tooltip_text = "Switch AI help on in Options (AI tab) to make a plan. You can also write a plan by hand later."
	else:
		_generate_button.tooltip_text = "Sends your manuscript and notes to your AI account and shows what it proposes. Nothing is changed until you build."


func _show_full_screen() -> void:
	borderless = true
	unresizable = true
	var root := get_tree().root
	if not root.size_changed.is_connected(_fit_to_screen):
		root.size_changed.connect(_fit_to_screen)
	popup(Rect2i(Vector2i.ZERO, Vector2i(root.get_visible_rect().size)))


func _fit_to_screen() -> void:
	if visible:
		position = Vector2i.ZERO
		size = Vector2i(get_tree().root.get_visible_rect().size)


# ---------------------------------------------------------------- generating

func _on_generate_pressed() -> void:
	if generator.is_busy():
		return
	if CampaignPlan.is_empty(_plan):
		_generate()
	else:
		_confirm.popup_centered()


func _generate() -> void:
	_note_label.visible = false
	_generate_button.disabled = true
	_cancel_button.visible = true
	_status_label.text = "Asking the AI - this can take a minute or two..."
	var result := await generator.generate(folder, campaign)
	if not is_instance_valid(self):
		return
	_cancel_button.visible = false
	_refresh_generate_button()
	if result.get("cancelled", false):
		_status_label.text = "Cancelled."
		return
	if not result["ok"]:
		_status_label.text = ""
		_say(str(result["error"]))
		return
	_plan = result["plan"]
	_status_label.text = "Plan made - review it below."
	var dropped: Array = result["dropped"]
	if not dropped.is_empty():
		_say("%d part(s) of the AI's answer were left out because they were not usable: %s" % [dropped.size(), "; ".join(dropped.slice(0, 5))])
	_changed()
	_rebuild()


func _say(message: String) -> void:
	_note_label.text = message
	_note_label.visible = true


# ---------------------------------------------------------------- the list

func _rebuild() -> void:
	_rebuilding = true
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	if CampaignPlan.is_empty(_plan):
		_body.add_child(_hint("There is no plan yet. Write your story in the writing workspace (a manuscript with a ## heading per chapter, and notes for the characters and style), then press 'Generate plan from the manuscript'."))
		_rebuilding = false
		_update_counts()
		return
	if _plan.get("generated", "") != "":
		_body.add_child(_hint("Made %s. Untick what you do not want; edit anything that is wrong." % _plan["generated"]))
	_body.add_child(_heading("ACTS AND CHAPTERS"))
	for act in _plan["acts"]:
		_body.add_child(_act_block(act))
	if not _plan["characters"].is_empty():
		_body.add_child(_heading("CHARACTERS"))
		for character in _plan["characters"]:
			_body.add_child(_character_row(character))
	if not _plan["variables"].is_empty():
		_body.add_child(_heading("VARIABLES"))
		for variable in _plan["variables"]:
			_body.add_child(_variable_row(variable))
	_rebuilding = false
	_update_counts()


func _act_block(act: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	head.add_child(_label("Act:"))
	head.add_child(_line(act["name"], func(text: String): act["name"] = text))
	var intro := _text_edit(act["intro"], 48, "Introduction read to the players", func(text: String): act["intro"] = text)
	box.add_child(intro)
	var titles := _chapter_titles(act)
	for chapter in act["chapters"]:
		box.add_child(_chapter_block(chapter, titles))
	return panel


func _chapter_titles(act: Dictionary) -> Dictionary:
	var titles := {}
	for chapter in act["chapters"]:
		titles[chapter["key"]] = chapter["title"]
	return titles


func _chapter_block(chapter: Dictionary, titles: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.22, 0.22, 0.26)
	style.set_content_margin_all(6)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(_check(chapter, "accepted", not chapter["exists"] and not read_only))
	var kind := OptionButton.new()
	for label in KIND_LABELS:
		kind.add_item(label)
	kind.select(CampaignPlan.KINDS.find(chapter["kind"]))
	kind.item_selected.connect(func(index: int):
		chapter["kind"] = CampaignPlan.KINDS[index]
		_changed()
	)
	kind.disabled = read_only
	row.add_child(kind)
	row.add_child(_line(chapter["title"], func(text: String): chapter["title"] = text))
	var flags: Array[String] = []
	if chapter["start"]:
		flags.append("start")
	if chapter["finale"]:
		flags.append("finale")
	if chapter["exists"]:
		flags.append("already in the campaign")
	if not flags.is_empty():
		row.add_child(_inline_hint(" · ".join(flags)))
	box.add_child(_text_edit(chapter["summary"], 48, "What happens", func(text: String): chapter["summary"] = text))
	var facts: Array[String] = []
	for link in chapter["links"]:
		facts.append("%s → %s" % [link["outcome"], titles.get(link["to"], "?")])
	if not facts.is_empty():
		box.add_child(_hint("Next: " + ", ".join(facts)))
	if chapter["section_title"] != "":
		var act_number := int(chapter["section_file"].get_basename().trim_prefix(CampaignNotes.MANUSCRIPT_PREFIX))
		box.add_child(_hint("From the manuscript: act %d › %s" % [act_number, chapter["section_title"]]))
	return panel


func _character_row(character: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_check(character, "accepted", not character["exists"] and not read_only))
	var name_edit := _line(character["name"], func(text: String): character["name"] = text)
	name_edit.custom_minimum_size.x = 160
	name_edit.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(name_edit)
	row.add_child(_line(character["description"], func(text: String): character["description"] = text))
	if character["exists"]:
		row.add_child(_inline_hint("already in the campaign"))
	return row


func _variable_row(variable: Dictionary) -> Control:
	var row := HFlowContainer.new()
	row.add_child(_check(variable, "accepted", not variable["exists"] and not read_only))
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
	default_edit.tooltip_text = "Starting value"
	var commit_default := func(text: String):
		variable["default"] = CampaignPlan.coerce_default(variable["type"], text)
		default_edit.text = str(variable["default"])
		_changed()
	default_edit.text_submitted.connect(commit_default)
	default_edit.focus_exited.connect(func(): commit_default.call(default_edit.text))
	type.item_selected.connect(func(index: int):
		variable["type"] = CampaignPlan.TYPES[index]
		variable["default"] = CampaignPlan.coerce_default(variable["type"], variable["default"])
		default_edit.text = str(variable["default"])
		_changed()
	)
	row.add_child(default_edit)
	var purpose := _line(variable["purpose"], func(text: String): variable["purpose"] = text)
	purpose.custom_minimum_size.x = 300
	row.add_child(purpose)
	if variable["exists"]:
		row.add_child(_inline_hint("already in the campaign"))
	return row


# ---------------------------------------------------------------- editing and saving

func _set_all(accepted: bool) -> void:
	if read_only:
		return
	for act in _plan.get("acts", []):
		for chapter in act["chapters"]:
			chapter["accepted"] = accepted and not chapter["exists"]
	for list_name in ["characters", "variables"]:
		for item in _plan.get(list_name, []):
			item["accepted"] = accepted and not item["exists"]
	_changed()
	_rebuild()


func _changed() -> void:
	if _rebuilding or read_only:
		return
	_save_timer.start()
	_update_counts()


func _save_now() -> void:
	if read_only or folder == "" or CampaignPlan.is_empty(_plan):
		return
	_save_timer.stop()
	if not CampaignPlan.save_plan(folder, _plan):
		push_warning("Could not save the plan")


func _update_counts() -> void:
	var counts := CampaignPlan.counts(_plan)
	_count_label.text = "" if counts["total"] == 0 else "%d of %d accepted" % [counts["accepted"], counts["total"]]


# ---------------------------------------------------------------- small builders

func _check(item: Dictionary, field: String, enabled: bool) -> CheckBox:
	var box := CheckBox.new()
	box.button_pressed = item[field] and enabled
	box.disabled = not enabled
	box.tooltip_text = "Build this item" if enabled else "Not available"
	box.toggled.connect(func(pressed: bool):
		item[field] = pressed
		_changed()
	)
	return box


func _line(text: String, on_change: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.editable = not read_only
	edit.text_changed.connect(func(value: String):
		on_change.call(value)
		_changed()
	)
	return edit


func _text_edit(text: String, height: float, placeholder: String, on_change: Callable) -> TextEdit:
	var edit := TextEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.custom_minimum_size.y = height
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.scroll_fit_content_height = true
	edit.editable = not read_only
	edit.text_changed.connect(func():
		on_change.call(edit.text)
		_changed()
	)
	return edit


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", SECTION_COLOR)
	return label


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


## A hint on one line (inside a row; a wrapping label with no width would stack its letters).
func _inline_hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HINT_COLOR)
	return label


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HINT_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 300
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button
