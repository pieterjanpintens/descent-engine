class_name NarrativeWindow
extends Window

## The full-screen editor of a narrative chapter's story (opened from the campaign editor's chapter panel,
## "Edit story…"). Left: the list of steps. Right: the selected step, laid out as numbered sections under clear
## headings - Story, Question, "Show only when", Answers - and every answer in its own framed block with its own
## headings (what the players choose, the reply, "offered only when", what choosing it does).
##
## It edits the chapter's `NarrativeStep`s in place; every change calls `mark_dirty` (the campaign editor's undo
## bookkeeping). The condition / effect rows are the campaign editor's own (`build_conditions` / `build_effects`
## callables, `(heading, list, parent, rebuild)`), so they behave exactly like everywhere else in the editor.

const BANNER_STEP := Color(0.18, 0.30, 0.52)
const BANNER_ANSWER := Color(0.17, 0.42, 0.34)
const SECTION_COLOR := Color(0.95, 0.80, 0.45)
const HINT_COLOR := Color(0.65, 0.65, 0.7)

var chapter: CampaignChapter
var campaign: Campaign
var mark_dirty: Callable
var build_conditions: Callable
var build_effects: Callable

var _selected := 0
var _list_box: VBoxContainer
var _detail: VBoxContainer


func _ready() -> void:
	close_requested.connect(hide)
	visible = false
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var split := HSplitContainer.new()
	margin.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	split.add_child(left)
	left.add_child(_banner("STEPS", Color(0.25, 0.25, 0.3), 18))
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_list_box)
	left.add_child(_button("+ Add step", func():
		var created := NarrativeStep.new()
		created.id = chapter.new_step_id()
		chapter.steps.append(created)
		_selected = chapter.steps.size() - 1
		_changed()
		refresh()
	))
	left.add_child(_button("Close", hide))

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(detail_scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(_detail)


func open_for(p_chapter: CampaignChapter, p_campaign: Campaign, p_mark_dirty: Callable, p_build_conditions: Callable, p_build_effects: Callable) -> void:
	chapter = p_chapter
	campaign = p_campaign
	mark_dirty = p_mark_dirty
	build_conditions = p_build_conditions
	build_effects = p_build_effects
	_selected = 0
	chapter.ensure_step_ids()
	refresh()
	popup_centered_ratio(0.97)


## Rebuilds the step list and the selected step (after a structural change, or when the campaign editor changed
## something this window shows - e.g. the characters).
func refresh() -> void:
	if chapter == null:
		return
	title = "Story - %s" % chapter.title
	_selected = clampi(_selected, 0, maxi(chapter.steps.size() - 1, 0))
	_rebuild_list()
	_rebuild_detail()


func _changed() -> void:
	if mark_dirty.is_valid():
		mark_dirty.call()


# ---------------------------------------------------------------- the step list

func _rebuild_list() -> void:
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	if chapter.steps.is_empty():
		_list_box.add_child(_hint("No steps yet - add one."))
	for i in chapter.steps.size():
		var step := chapter.steps[i]
		var summary := NarrationMarkup.plain(step.text, campaign.characters).replace("\n", " ").strip_edges()
		if summary.length() > 34:
			summary = summary.substr(0, 34) + "…"
		if summary == "":
			summary = "(empty)"
		var extra := ""
		if not step.answers.is_empty():
			extra = "  ?%d" % step.answers.size()
		var button := Button.new()
		button.text = "%s%d. %s%s" % ["▶ " if i == _selected else "", i + 1, summary, extra]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.toggle_mode = true
		button.button_pressed = i == _selected
		var index := i
		button.pressed.connect(func():
			_selected = index
			refresh()
		)
		_list_box.add_child(button)


# ---------------------------------------------------------------- the selected step

func _rebuild_detail() -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	if chapter.steps.is_empty():
		_detail.add_child(_hint("Add a step on the left to start the story."))
		return
	var index := _selected
	var step := chapter.steps[index]

	# --- banner with the step's own actions
	var banner_row := HBoxContainer.new()
	banner_row.add_child(_banner("STEP %d of %d" % [index + 1, chapter.steps.size()], BANNER_STEP, 22, true))
	var up := _button("↑ Move up", func(): _move_step(index, -1))
	up.disabled = index == 0
	banner_row.add_child(up)
	var down := _button("↓ Move down", func(): _move_step(index, 1))
	down.disabled = index == chapter.steps.size() - 1
	banner_row.add_child(down)
	banner_row.add_child(_button("✕ Delete step", func():
		_forget_goto_to(step.id)
		chapter.steps.remove_at(index)
		_changed()
		refresh()
	))
	_detail.add_child(banner_row)

	# --- 1 story
	_detail.add_child(_section("1 · Story", "What the party reads. Put words in [Name]...[/Name] to give them to a character's voice; text in (round brackets) is shown but never spoken."))
	var text_edit := _text_edit(190, step.text, "The story the party reads...")
	text_edit.text_changed.connect(func():
		step.text = text_edit.text
		_changed()
		_rebuild_list()
	)
	_detail.add_child(text_edit)

	# --- 2 question
	_detail.add_child(_section("2 · Question (optional)", "Shown under the story when the step has answers."))
	var question_edit := _text_edit(80, step.question, "e.g. What do you tell the guards?")
	question_edit.text_changed.connect(func():
		step.question = question_edit.text
		_changed()
	)
	_detail.add_child(question_edit)
	var story_targets: Array[TextEdit] = [text_edit, question_edit]
	_detail.add_child(NarrationHighlight.legend(story_targets, campaign.characters))

	# --- 3 conditions
	_detail.add_child(_section("3 · Show this step only when…", "Empty = always shown. Counts what was answered earlier in this story."))
	build_conditions.call("", step.conditions, _detail, refresh)

	# --- 4 answers
	_detail.add_child(_section("4 · Answers", "Without answers the step is a plain page to read. With answers the table must pick one."))
	for k in step.answers.size():
		_detail.add_child(_build_answer(step, step.answers[k], k))
	_detail.add_child(_button("+ Add answer", func():
		step.answers.append(NarrativeAnswer.new())
		_changed()
		refresh()
	))


func _build_answer(step: NarrativeStep, answer: NarrativeAnswer, k: int) -> Control:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.16, 0.15)
	style.border_color = BANNER_ANSWER
	style.set_border_width_all(2)
	style.set_content_margin_all(8)
	frame.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	frame.add_child(box)

	var head := HBoxContainer.new()
	head.add_child(_banner("ANSWER %d" % (k + 1), BANNER_ANSWER, 18, true))
	head.add_child(_button("✕ Delete answer", func():
		step.answers.erase(answer)
		_changed()
		refresh()
	))
	box.add_child(head)

	box.add_child(_sub("What the players choose", "Voice tags make the chosen answer be spoken, e.g. [Chance](Lie) No, I have not seen that man.[/Chance]"))
	var text_edit := _text_edit(64, answer.text, "The answer as the players read it...")
	text_edit.text_changed.connect(func():
		answer.text = text_edit.text
		_changed()
	)
	box.add_child(text_edit)

	box.add_child(_sub("Reply (optional)", "Shown after this answer is chosen."))
	var reply_edit := _text_edit(90, answer.reply, "What happens / is said next...")
	reply_edit.text_changed.connect(func():
		answer.reply = reply_edit.text
		_changed()
	)
	box.add_child(reply_edit)
	var targets: Array[TextEdit] = [text_edit, reply_edit]
	box.add_child(NarrationHighlight.legend(targets, campaign.characters))

	box.add_child(_sub("Offered only when…", "Empty = always offered."))
	build_conditions.call("", answer.conditions, box, refresh)

	box.add_child(_sub("Choosing it…", "Variables it sets, and whether it ends the story."))
	build_effects.call("", answer.effects, box, refresh)
	box.add_child(_sub("After this answer", "Branching: carry on with the next step, jump to another step, or end the story."))
	box.add_child(_build_after_picker(answer))
	return frame


## Next step / Go to step… (+ which) / End the story - stored as goto_step_id and ends_narrative (never both).
func _build_after_picker(answer: NarrativeAnswer) -> Control:
	var row := HBoxContainer.new()
	var mode := OptionButton.new()
	mode.add_item("Continue with the next step", 0)
	mode.add_item("Go to step…", 1)
	mode.add_item("End the story", 2)
	var current := 2 if answer.ends_narrative else (1 if answer.goto_step_id != "" else 0)
	mode.select(current)
	row.add_child(mode)
	var target := OptionButton.new()
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in chapter.steps.size():
		var label := NarrationMarkup.plain(chapter.steps[i].text, campaign.characters).replace("\n", " ").strip_edges()
		if label.length() > 40:
			label = label.substr(0, 40) + "…"
		target.add_item("Step %d: %s" % [i + 1, label if label != "" else "(empty)"], i)
	var target_index := chapter.find_step_index(answer.goto_step_id)
	target.select(target_index)  # -1 (blank) when the step no longer exists
	target.visible = current == 1
	row.add_child(target)
	mode.item_selected.connect(func(index: int):
		answer.ends_narrative = index == 2
		if index == 1:
			if chapter.find_step_index(answer.goto_step_id) == -1 and not chapter.steps.is_empty():
				answer.goto_step_id = chapter.steps[0].id
		else:
			answer.goto_step_id = ""
		_changed()
		refresh()
	)
	target.item_selected.connect(func(index: int):
		answer.goto_step_id = chapter.steps[index].id
		_changed()
	)
	return row


## Answers that jumped to a step that is being deleted go back to "continue with the next step".
func _forget_goto_to(step_id: String) -> void:
	for step in chapter.steps:
		for answer in step.answers:
			if answer.goto_step_id == step_id:
				answer.goto_step_id = ""


func _move_step(index: int, delta: int) -> void:
	var other := index + delta
	if other < 0 or other >= chapter.steps.size():
		return
	var moved := chapter.steps[index]
	chapter.steps[index] = chapter.steps[other]
	chapter.steps[other] = moved
	_selected = other
	_changed()
	refresh()


# ---------------------------------------------------------------- small builders

## A coloured bar with a big title; `inline` = no full-width stretch, to sit in a row next to buttons.
func _banner(text: String, color: Color, font_size: int, inline: bool = false) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_content_margin_all(8)
	style.content_margin_left = 12
	panel.add_theme_stylebox_override("panel", style)
	if inline:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	panel.add_child(label)
	return panel


## A numbered section heading with a rule above it and an optional grey explanation under it.
func _section(text: String, hint: String = "") -> Control:
	var box := VBoxContainer.new()
	box.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", SECTION_COLOR)
	box.add_child(label)
	if hint != "":
		box.add_child(_hint(hint))
	return box


## A smaller heading inside an answer block.
func _sub(text: String, hint: String = "") -> Control:
	var box := VBoxContainer.new()
	box.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", SECTION_COLOR)
	box.add_child(label)
	if hint != "":
		box.add_child(_hint(hint))
	return box


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_color_override("font_color", HINT_COLOR)
	label.add_theme_font_size_override("font_size", 13)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button


func _text_edit(height: float, text: String, placeholder: String) -> TextEdit:
	var edit := TextEdit.new()
	edit.custom_minimum_size.y = height
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.text = text
	edit.placeholder_text = placeholder
	NarrationHighlight.apply(edit, campaign.characters)
	return edit
