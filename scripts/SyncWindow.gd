class_name SyncWindow
extends Window

## The manuscript sync check (PlanSync), opened from the writing workspace ("Sync…"): lists the chapters built from the
## manuscript and says which are out of step - the manuscript section changed, the chapter was edited, both, or one side is
## gone. For the selected chapter it shows what changed (a word-level comparison against the last time they were in step) and
## offers the safe choices: update the chapter from the manuscript (only when the chapter has plain pages), update the
## manuscript from the chapter (asks first), accept both as they are ("mark as reviewed"), or stop tracking. Nothing changes
## by itself. A campaign change goes through `on_changed` (the campaign editor's undo step + refresh); a changed manuscript file
## through `on_manuscript_changed`.

## Something was resolved (the plan's baselines changed).
signal resolved

const HINT_COLOR := Color(0.65, 0.65, 0.7)
const WARN_COLOR := Color(1.0, 0.7, 0.3)
const SELECTED_COLOR := Color(0.95, 0.80, 0.45)

var campaign: Campaign
var folder := ""
var read_only := false
var on_changed: Callable
var on_manuscript_changed: Callable

var _plan: Dictionary = {}
var _entries: Array[Dictionary] = []
var _selected_key := ""
var _list_box: VBoxContainer
var _title_label: Label
var _state_label: Label
var _detail: VBoxContainer
var _buttons: HFlowContainer
var _confirm: ConfirmationDialog
var _pending: Callable
var _message_label: Label


func _ready() -> void:
	close_requested.connect(hide)
	title = "Manuscript sync"
	visible = false
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var split := HSplitContainer.new()
	margin.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 260
	split.add_child(left)
	var heading := Label.new()
	heading.text = "CHAPTERS MADE FROM THE MANUSCRIPT"
	heading.add_theme_color_override("font_color", SELECTED_COLOR)
	left.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)
	left.add_child(_button("Close", hide))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	right.add_child(_title_label)
	_state_label = Label.new()
	_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state_label.custom_minimum_size.x = 400
	right.add_child(_state_label)
	_buttons = HFlowContainer.new()
	right.add_child(_buttons)
	_message_label = Label.new()
	_message_label.add_theme_color_override("font_color", WARN_COLOR)
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.custom_minimum_size.x = 400
	_message_label.visible = false
	right.add_child(_message_label)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(detail_scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(_detail)

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func():
		if _pending.is_valid():
			_pending.call()
	)
	add_child(_confirm)


func open_for(p_campaign: Campaign, p_folder: String, p_read_only: bool, p_on_changed: Callable, p_on_manuscript_changed: Callable) -> void:
	campaign = p_campaign
	folder = p_folder
	read_only = p_read_only
	on_changed = p_on_changed
	on_manuscript_changed = p_on_manuscript_changed
	_selected_key = ""
	_message_label.visible = false
	_refresh()
	popup_centered_clamped(Vector2i(1100, 680), 0.92)


## Reads the plan and the files again and shows the result.
func _refresh() -> void:
	_plan = CampaignPlan.load_plan(folder)
	_entries = PlanSync.check(_plan, campaign, folder)
	# Out-of-step chapters first.
	_entries.sort_custom(func(a: Dictionary, b: Dictionary): return (a["state"] == "in_sync") < (b["state"] == "in_sync"))
	var keys: Array[String] = []
	for entry in _entries:
		keys.append(entry["chapter_plan"]["built"])
	if not keys.has(_selected_key):
		_selected_key = keys[0] if not keys.is_empty() else ""
	_rebuild_list()
	_show_selected()


func _rebuild_list() -> void:
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	if _entries.is_empty():
		var hint := Label.new()
		hint.text = "No chapters were built from the manuscript yet (make a plan and build it first)."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = 220
		hint.add_theme_color_override("font_color", HINT_COLOR)
		_list_box.add_child(hint)
		return
	for entry in _entries:
		var key: String = entry["chapter_plan"]["built"]
		var drifted: bool = entry["state"] != "in_sync"
		var button := Button.new()
		button.text = "%s%s" % ["● " if drifted else "", entry["chapter_plan"]["title"]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.tooltip_text = PlanSync.state_text(entry["state"])
		var color := SELECTED_COLOR if key == _selected_key else (WARN_COLOR if drifted else Color(1, 1, 1))
		button.add_theme_color_override("font_color", color)
		button.add_theme_color_override("font_hover_color", color)
		button.pressed.connect(func():
			_selected_key = key
			_message_label.visible = false
			_rebuild_list()
			_show_selected()
		)
		_list_box.add_child(button)


func _selected_entry() -> Dictionary:
	for entry in _entries:
		if entry["chapter_plan"]["built"] == _selected_key:
			return entry
	return {}


func _show_selected() -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	var entry := _selected_entry()
	if entry.is_empty():
		_title_label.text = ""
		_state_label.text = ""
		return
	var plan_chapter: Dictionary = entry["chapter_plan"]
	var state: String = entry["state"]
	_title_label.text = plan_chapter["title"]
	_state_label.text = PlanSync.state_text(state)
	if plan_chapter["section_title"] != "":
		_state_label.text += "  (manuscript: act %d › %s%s)" % [plan_chapter["section_file"].get_basename().trim_prefix(CampaignNotes.MANUSCRIPT_PREFIX).to_int(), plan_chapter["section_title"], "" if entry["single_section"] else " + %d more" % plan_chapter["extra_sections"].size()]
	if state == "manuscript_changed" or state == "both_changed":
		_detail.add_child(_comparison("The manuscript section - what changed since the chapter was made", plan_chapter.get("synced_text", ""), entry["section_now"]))
	if state == "chapter_changed" or state == "both_changed":
		_detail.add_child(_comparison("The chapter's story - what changed since it was made", plan_chapter.get("built_text", ""), entry["chapter_now"]))
	if state == "in_sync":
		var text := "Nothing to do." if plan_chapter["section_title"] != "" else "This chapter is not linked to a manuscript section, so there is nothing to compare."
		_detail.add_child(_note(text))
	if read_only:
		_detail.add_child(_note("This is a release - nothing can be changed."))
		return
	match state:
		"manuscript_changed":
			var update := _button("Update the chapter from the manuscript", func(): _ask("Replace the chapter's story pages with the pages of the manuscript section as it is now? The chapter's own edits to those pages are lost (undo works in the campaign editor).", _do_update_chapter))
			update.disabled = not entry["plain_pages"]
			update.tooltip_text = "" if entry["plain_pages"] else "The chapter has questions, answers or conditions, which would be lost. Update the pages by hand, then mark as reviewed."
			_buttons.add_child(update)
			_buttons.add_child(_button("Mark as reviewed (keep both as they are)", _do_review))
		"chapter_changed":
			if not entry["single_section"]:
				_detail.add_child(_note("This chapter combines several manuscript sections, so its text cannot be written back into one place. Change the manuscript by hand, then mark as reviewed."))
			else:
				_buttons.add_child(_button("Update the manuscript from the chapter…", func(): _ask("Replace the text of the manuscript section '%s' with the chapter's story text? Your manuscript text of that section is overwritten." % plan_chapter["section_title"], _do_update_manuscript)))
			_buttons.add_child(_button("Mark as reviewed (keep both as they are)", _do_review))
		"both_changed":
			_buttons.add_child(_button("Mark as reviewed (I combined them by hand)", _do_review))
			_detail.add_child(_note("Both sides changed, so nothing is offered that could overwrite one of them. Bring them together by hand, then mark as reviewed."))
		"section_missing":
			_buttons.add_child(_button("Stop tracking this chapter", _do_forget))
		"chapter_missing":
			_buttons.add_child(_button("Forget this chapter (it can be built again)", _do_forget))


func _comparison(heading: String, old_text: String, new_text: String) -> Control:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = heading
	label.add_theme_color_override("font_color", SELECTED_COLOR)
	box.add_child(label)
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.custom_minimum_size = Vector2(400, 40)
	rich.selection_enabled = true
	var ops := TextDiff.diff(old_text, new_text)
	if old_text == "" and new_text != "":
		rich.text = "[i](the earlier text was not kept - this is the text now)[/i]\n" + TextDiff.escape(new_text)
	elif ops.is_empty():
		rich.text = "[i](too long to compare - the text now:)[/i]\n" + TextDiff.escape(new_text)
	else:
		rich.text = "[i]red = removed, green = added[/i]\n" + TextDiff.to_bbcode(ops)
	box.add_child(rich)
	return box


# ---------------------------------------------------------------- actions

func _ask(text: String, action: Callable) -> void:
	_confirm.dialog_text = text
	_pending = action
	_confirm.popup_centered()


func _do_update_chapter() -> void:
	var entry := _selected_entry()
	if entry.is_empty() or not PlanSync.update_chapter_from_manuscript(entry):
		_tell("The chapter could not be updated.")
		return
	_finish(true, false, "The chapter now has the pages of the manuscript section.")


func _do_update_manuscript() -> void:
	var entry := _selected_entry()
	if entry.is_empty() or not PlanSync.update_manuscript_from_chapter(entry, folder):
		_tell("The manuscript could not be updated.")
		return
	_finish(false, true, "The manuscript section now has the chapter's text.")


func _do_review() -> void:
	var entry := _selected_entry()
	if entry.is_empty():
		return
	PlanSync.mark_reviewed(entry)
	_finish(false, false, "Marked as reviewed - both sides count as in step now.")


func _do_forget() -> void:
	var entry := _selected_entry()
	if entry.is_empty():
		return
	PlanSync.forget(entry)
	_finish(false, false, "Not tracked any more.")


## Saves the plan (its baselines changed), tells whoever needs to know, and shows the check again.
func _finish(campaign_changed: bool, manuscript_changed: bool, message: String) -> void:
	CampaignPlan.save_plan(folder, _plan)
	if campaign_changed and on_changed.is_valid():
		on_changed.call()
	if manuscript_changed and on_manuscript_changed.is_valid():
		on_manuscript_changed.call()
	_refresh()
	_tell(message)
	resolved.emit()


func _tell(message: String) -> void:
	_message_label.text = message
	_message_label.visible = true


# ---------------------------------------------------------------- small builders

func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 400
	label.add_theme_color_override("font_color", HINT_COLOR)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button
