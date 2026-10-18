class_name ManuscriptWindow
extends Window

## The writing workspace of one campaign (opened from the campaign editor, "Writing workspace…"): a full-screen window with the
## campaign's notes and manuscript (CampaignNotes - plain markdown files in the campaign's `notes/` folder). Left: the files
## (story bible, style guide, characters... and one manuscript per act) and, under them, the `##` sections of the open file
## (for a manuscript: its chapters - click one to jump there). Right: a big text box. Everything is saved by itself a moment
## after typing stops, and when the window closes or another file is opened.
##
## This is the CREATIVE half of the AI workspace (claude.md, open item 26): the text is just text, written by the author. The
## optional AI menu (AiAssist, only there when AI help is switched on) works on it like in the story editor, with the notes
## that matter (AiContext) as background; it never touches game data. Notes are private - never part of a package.

const SAVE_DELAY_SEC := 1.5
const CONTEXT_REFRESH_SEC := 1.0
const HINT_COLOR := Color(0.65, 0.65, 0.7)
const SELECTED_COLOR := Color(0.95, 0.80, 0.45)

var campaign: Campaign
var folder := ""
## A release: nothing can be written.
var read_only := false
## Called after the plan builder changed the campaign (the campaign editor records an undo step and refreshes).
var on_changed: Callable

var _file := ""
var _dirty := false
var _loading := false
var _save_timer: Timer
var _context_timer: Timer
var _files_box: VBoxContainer
var _sections_box: VBoxContainer
var _title_label: Label
var _status_label: Label
var _count_label: Label
var _context_label: Label
var _banner: Label
var _edit: TextEdit
var _plan_window: PlanWindow
var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _name_error: Label


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
	_context_timer = Timer.new()
	_context_timer.one_shot = true
	_context_timer.wait_time = CONTEXT_REFRESH_SEC
	_context_timer.timeout.connect(_refresh_side)
	add_child(_context_timer)

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
	left.add_child(_heading("FILES"))
	var files_scroll := ScrollContainer.new()
	files_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	files_scroll.size_flags_stretch_ratio = 2.0  # the file list gets more room than the sections list
	files_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(files_scroll)
	_files_box = VBoxContainer.new()
	_files_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	files_scroll.add_child(_files_box)
	left.add_child(_button("+ Manuscript for the next act", _on_new_manuscript))
	left.add_child(_button("+ New note…", _on_new_note))
	left.add_child(_heading("SECTIONS"))
	var sections_scroll := ScrollContainer.new()
	sections_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sections_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sections_scroll)
	_sections_box = VBoxContainer.new()
	_sections_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections_scroll.add_child(_sections_box)
	left.add_child(_button("Close", hide))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var top := HBoxContainer.new()
	right.add_child(top)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_title_label)
	_count_label = Label.new()
	_count_label.add_theme_color_override("font_color", HINT_COLOR)
	top.add_child(_count_label)
	top.add_child(_button("Plan…", _open_plan))
	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", HINT_COLOR)
	_status_label.custom_minimum_size.x = 90
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_status_label)
	_banner = Label.new()
	_banner.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.custom_minimum_size.x = 400
	_banner.visible = false
	right.add_child(_banner)
	_edit = TextEdit.new()
	_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_edit.placeholder_text = "Write here. Use ## headings for the chapters."
	_edit.text_changed.connect(_on_text_changed)
	right.add_child(_edit)
	_context_label = Label.new()
	_context_label.add_theme_color_override("font_color", HINT_COLOR)
	_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context_label.custom_minimum_size.x = 400
	right.add_child(_context_label)

	_name_dialog = ConfirmationDialog.new()
	_name_dialog.title = "New note"
	_name_dialog.ok_button_text = "Create"
	var name_box := VBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name of the note, e.g. The Guild"
	_name_edit.custom_minimum_size.x = 360
	name_box.add_child(_name_edit)
	_name_error = Label.new()
	_name_error.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	name_box.add_child(_name_error)
	_name_dialog.add_child(name_box)
	_name_dialog.confirmed.connect(_create_note)
	add_child(_name_dialog)


## Opens the workspace of the campaign in `p_folder`. `p_read_only` = a release: nothing can be written (and the notes folder is not
## made).
func open_for(p_campaign: Campaign, p_folder: String, p_read_only: bool = false, p_on_changed: Callable = Callable()) -> void:
	if visible:
		_save_now()
	on_changed = p_on_changed
	campaign = p_campaign
	folder = p_folder
	read_only = p_read_only
	if not read_only:
		CampaignNotes.ensure(folder)
	_edit.editable = not read_only
	_banner.visible = read_only
	_banner.text = "This is a release, so it has no writing workspace and cannot be changed. Fork it to get an editable copy."
	NarrationHighlight.apply(_edit, campaign.characters)
	_attach_ai()
	var files := CampaignNotes.list_files(folder)
	var first := ""
	for entry in files:
		if entry["manuscript"]:
			first = entry["file"]
			break
	if first == "" and not files.is_empty():
		first = files[0]["file"]
	title = "Writing workspace - %s" % campaign.campaign_name
	_show_full_screen()
	_open_file(first)


func _attach_ai() -> void:
	# The AI helper is a child of the text box; replace it when the campaign (so its characters) changed.
	for child in _edit.get_children():
		if child is AiAssist:
			_edit.remove_child(child)
			child.free()
	AiAssist.attach(_edit, _ai_context, campaign.characters)


## Covers the whole game window and cannot be resized (see NarrativeWindow for why the size comes from the visible rect).
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


# ---------------------------------------------------------------- files

## The campaign plan (what the AI proposes from the manuscript). The manuscript is saved first - the plan is made from the files.
func _open_plan() -> void:
	_save_now()
	if _plan_window == null:
		_plan_window = PlanWindow.new()
		add_child(_plan_window)
	_plan_window.open_for(campaign, folder, read_only, on_changed)


func _open_file(file_name: String) -> void:
	_save_now()
	_file = file_name
	_loading = true
	_edit.text = CampaignNotes.read(folder, file_name) if file_name != "" else ""
	_edit.clear_undo_history()
	_loading = false
	_dirty = false
	_edit.set_caret_line(0)
	_edit.set_caret_column(0)
	_title_label.text = _file_title(file_name)
	_status_label.text = ""
	_rebuild_files()
	_refresh_side()


func _file_title(file_name: String) -> String:
	for entry in CampaignNotes.list_files(folder):
		if entry["file"] == file_name:
			return entry["title"]
	return file_name


func _rebuild_files() -> void:
	for child in _files_box.get_children():
		_files_box.remove_child(child)
		child.queue_free()
	var entries := CampaignNotes.list_files(folder)
	if entries.is_empty():
		_files_box.add_child(_hint("No files yet."))
	var shown_manuscripts := false
	for entry in entries:
		if entry["manuscript"] and not shown_manuscripts:
			shown_manuscripts = true
			_files_box.add_child(_hint("Manuscript"))
		var file_name: String = entry["file"]
		var button := Button.new()
		button.text = entry["title"]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.tooltip_text = "%s (%d characters)" % [file_name, entry["size"]]
		if file_name == _file:
			button.add_theme_color_override("font_color", SELECTED_COLOR)
			button.add_theme_color_override("font_hover_color", SELECTED_COLOR)
		button.pressed.connect(func(): _open_file(file_name))
		_files_box.add_child(button)


## A manuscript for the next act number. The chapters of that act (when the campaign has it) become the `##` headings, which is
## what later links the text to the chapters.
func _on_new_manuscript() -> void:
	if read_only or campaign == null:
		return
	var number := 1
	for entry in CampaignNotes.list_files(folder):
		if entry["manuscript"]:
			number = maxi(number, int(entry["file"].trim_prefix(CampaignNotes.MANUSCRIPT_PREFIX).get_basename()) + 1)
	var text := "# Act %d\n" % number
	if number <= campaign.acts.size():
		var act: CampaignAct = campaign.acts[number - 1]
		if act.act_name != "":
			text = "# Act %d - %s\n" % [number, act.act_name]
		for chapter in act.chapters:
			text += "\n## %s\n\n" % chapter.title
	else:
		text += "\n## Chapter 1\n\n"
	var file_name := CampaignNotes.manuscript_file(number)
	if CampaignNotes.write(folder, file_name, text):
		_open_file(file_name)


func _on_new_note() -> void:
	if read_only:
		return
	_name_edit.text = ""
	_name_error.text = ""
	_name_dialog.popup_centered()
	_name_edit.grab_focus()


func _create_note() -> void:
	var note_name := _name_edit.text.strip_edges()
	var file_name := "%s.md" % note_name
	if note_name == "" or not CampaignNotes.is_valid_file_name(file_name):
		_name_error.text = "Use letters, digits, spaces, - and _ only."
		_name_dialog.popup_centered()
		return
	if FileAccess.file_exists(CampaignNotes.file_path(folder, file_name)):
		_name_error.text = "A note called '%s' exists already." % note_name
		_name_dialog.popup_centered()
		return
	if CampaignNotes.write(folder, file_name, "# %s\n\n" % note_name):
		_open_file(file_name)


# ---------------------------------------------------------------- editing and saving

func _on_text_changed() -> void:
	if _loading or read_only:
		return
	_dirty = true
	_status_label.text = "Unsaved"
	_save_timer.start()
	_context_timer.start()
	_count_label.text = _words_text()


func _save_now() -> void:
	if not _dirty or read_only or _file == "" or folder == "":
		return
	_save_timer.stop()
	if CampaignNotes.write(folder, _file, _edit.text):
		_dirty = false
		_status_label.text = "Saved"
	else:
		_status_label.text = "Not saved!"
		push_warning("Could not save the note %s" % _file)


func _words_text() -> String:
	var words := _edit.text.split(" ", false).size() if _edit.text.find("\n") == -1 else _edit.text.replace("\n", " ").split(" ", false).size()
	return "%d words" % words


## The section list of the open file and the "context used" line under the text.
func _refresh_side() -> void:
	_count_label.text = _words_text()
	for child in _sections_box.get_children():
		_sections_box.remove_child(child)
		child.queue_free()
	var found := false
	for section in CampaignNotes.sections(_edit.text):
		if section["title"] == "":
			continue
		found = true
		var line: int = section["start_line"]
		var button := Button.new()
		button.text = section["title"]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.pressed.connect(func():
			_edit.set_caret_line(line)
			_edit.set_caret_column(0)
			_edit.center_viewport_to_caret()
			_edit.grab_focus()
		)
		_sections_box.add_child(button)
	if not found:
		_sections_box.add_child(_hint("No `##` headings in this file."))
	var pack := _context_pack()
	var labels: Array[String] = []
	for part in pack["parts"]:
		if part["included"]:
			labels.append(part["label"])
	_context_label.text = "AI background from your notes: %s" % (", ".join(labels) if not labels.is_empty() else "nothing yet - fill in the style guide, story bible or character notes.")


# ---------------------------------------------------------------- AI background

## The notes that matter for the text in the box (style guide, story bible, the characters mentioned...). The file being edited is
## left out - it is the text itself.
func _context_pack() -> Dictionary:
	var focus := _edit.text.left(AiContext.DEFAULT_BUDGET * 2)
	var excluded: Array[String] = [_file]
	return AiContext.build(folder, focus, {"exclude_files": excluded})


## What the AI is told about where the text sits: the file and the notes that matter.
func _ai_context() -> String:
	var lines: Array[String] = ["Campaign: " + campaign.campaign_name, "Writing in: " + _file_title(_file)]
	var pack := _context_pack()
	if pack["text"] != "":
		lines.append("The author's notes:
" + str(pack["text"]))
	return "
".join(lines)


# ---------------------------------------------------------------- small builders

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", SELECTED_COLOR)
	return label


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HINT_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 200
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button
