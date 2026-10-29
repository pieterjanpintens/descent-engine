class_name LanguagesDialog
extends Window

## The languages of one campaign or mission (anything with `default_language` and `languages`): how complete each language is, add one, remove one (with its
## texts), choose the default, move the texts of a language to another code (content that was filed under the wrong language), fill the empty texts of a
## language with the default's as a starting point, and export / import every text as a CSV file for translators who work outside the game.
## The owner (an editor) supplies `root_provider` (the CURRENT campaign / mission - undo swaps them) and `commit(label, mutate)`, which runs `mutate` as one
## undo step and refreshes the editor. `language_requested(code)` asks the editor to switch its editing language.

signal language_requested(code: String)

const SIZE := Vector2i(700, 600)

var root_provider: Callable
var commit: Callable
var read_only := false

var _rows: VBoxContainer
var _add_picker: OptionButton
var _status: Label
var _confirm: ConfirmationDialog
var _confirm_action: Callable
var _file_dialog: FileDialog
var _file_mode := ""


func _init() -> void:
	visible = false  # a Window is shown as soon as it is added to the tree


func _ready() -> void:
	title = "Languages"
	unresizable = true
	exclusive = false
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	margin.add_child(page)
	var hint := Label.new()
	hint.text = "Texts can exist in several languages. A player reads the first of their preferred languages that has a text; what is missing falls back to the default language."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = SIZE.x - 40
	page.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)

	var add_row := HBoxContainer.new()
	page.add_child(add_row)
	add_row.add_child(_label("Add a language:"))
	_add_picker = OptionButton.new()
	_add_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_add_picker)
	add_row.add_child(_button("Add", _on_add_pressed))
	var file_row := HBoxContainer.new()
	page.add_child(file_row)
	file_row.add_child(_button("Export all texts (CSV)…", func(): _ask_file("export")))
	file_row.add_child(_button("Import texts (CSV)…", func(): _ask_file("import")))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = SIZE.x - 40
	page.add_child(_status)
	var close := _button("Close", hide)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	page.add_child(close)

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func(): _confirm_action.call())
	add_child(_confirm)
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.add_filter("*.csv", "CSV files")
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)


func open() -> void:
	_status.text = ""
	_rebuild()
	popup_centered(SIZE)


# ---------------------------------------------------------------- rows

func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.free()
	var root: Resource = root_provider.call()
	if root == null:
		return
	var entries := TextWalker.collect(root)
	var codes := TextWalker.content_languages(root, entries)
	var default_language := str(root.get("default_language"))
	var total := TextWalker.with_text(entries).size()
	for code in codes:
		_rows.add_child(_language_row(code, code == default_language, TextWalker.completeness(entries, code), total, codes))
	_add_picker.clear()
	for language in CampaignInfo.LANGUAGES:
		if not codes.has(language["code"]):
			_add_picker.add_item(language["name"])
			_add_picker.set_item_metadata(_add_picker.item_count - 1, language["code"])


func _language_row(code: String, is_default: bool, done: Dictionary, total: int, codes: Array[String]) -> Control:
	var row := PanelContainer.new()
	var box := VBoxContainer.new()
	row.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var name_label := Label.new()
	name_label.text = "%s (%s)%s" % [CampaignInfo.language_name(code), code, "  - default" if is_default else ""]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var count := Label.new()
	var percent := 100 if total == 0 else int(round(100.0 * float(done["done"]) / float(total)))
	count.text = "%d of %d texts (%d%%)" % [done["done"], total, percent]
	count.modulate = Color(1, 1, 1, 0.8) if percent == 100 else Color(1.0, 0.82, 0.5)
	top.add_child(count)
	var buttons := HFlowContainer.new()
	box.add_child(buttons)
	buttons.add_child(_button("Edit in this language", func(): language_requested.emit(code)))
	if not read_only:
		if not is_default:
			buttons.add_child(_button("Make default", func(): _set_default(code)))
			var fill := _button("Fill empty texts with the default's", func(): _fill_from_default(code))
			fill.tooltip_text = "Copies the default language's text into every text that has none in this language: a starting point to translate from."
			buttons.add_child(fill)
		var move := MenuButton.new()
		move.text = "Move texts to…"
		move.flat = false
		move.tooltip_text = "For content that was filed under the wrong language code: every text of this language moves to the language you pick."
		var popup := move.get_popup()
		var targets: Array[String] = []
		for language in CampaignInfo.LANGUAGES:
			if language["code"] != code:
				targets.append(language["code"])
				popup.add_item(language["name"])
		popup.index_pressed.connect(func(index: int): _confirm_move(code, targets[index]))
		buttons.add_child(move)
		if not is_default:
			buttons.add_child(_button("Remove…", func(): _confirm_remove(code)))
	return row


# ---------------------------------------------------------------- actions

func _on_add_pressed() -> void:
	if read_only or _add_picker.item_count == 0 or _add_picker.selected < 0:
		return
	var code := str(_add_picker.get_item_metadata(_add_picker.selected))
	_run("Add language", func():
		var root: Resource = root_provider.call()
		var declared: Array[String] = root.get("languages")
		if code != str(root.get("default_language")) and not declared.has(code):
			declared.append(code))
	language_requested.emit(code)


func _set_default(code: String) -> void:
	_run("Default language", func():
		var root: Resource = root_provider.call()
		var old := str(root.get("default_language"))
		var declared: Array[String] = root.get("languages")
		if old != code and not declared.has(old):
			declared.append(old)
		declared.erase(code)
		root.set("default_language", code)
		LText.fallback_language = code)


func _fill_from_default(code: String) -> void:
	var stats := {"copied": 0}  # a lambda sees plain variables by value, so the count goes in a dictionary
	_run("Fill texts", func():
		var root: Resource = root_provider.call()
		stats["copied"] = TextWalker.copy_missing(TextWalker.collect(root), str(root.get("default_language")), code))
	_status.text = "%d empty texts filled with the default's." % stats["copied"]


func _confirm_remove(code: String) -> void:
	var root: Resource = root_provider.call()
	var count := 0
	for entry in TextWalker.collect(root):
		if entry["map"].has(code):
			count += 1
	_confirm.dialog_text = "Remove %s? Its %d texts are deleted (undo brings them back)." % [CampaignInfo.language_name(code), count]
	_confirm_action = func():
		_run("Remove language", func():
			var current: Resource = root_provider.call()
			TextWalker.remove_language(TextWalker.collect(current), code)
			var declared: Array[String] = current.get("languages")
			declared.erase(code))
		if LText.edit_language == code:
			language_requested.emit(str(root_provider.call().get("default_language")))
	_confirm.popup_centered()


func _confirm_move(from: String, to: String) -> void:
	_confirm.dialog_text = "Move every %s text to %s? A text that already has a %s version keeps it." % [CampaignInfo.language_name(from), CampaignInfo.language_name(to), CampaignInfo.language_name(to)]
	_confirm_action = func():
		_run("Move texts", func():
			var root: Resource = root_provider.call()
			TextWalker.rename_language(TextWalker.collect(root), from, to)
			var declared: Array[String] = root.get("languages")
			declared.erase(from)
			if str(root.get("default_language")) == from:
				root.set("default_language", to)
				LText.fallback_language = to
			elif to != str(root.get("default_language")) and not declared.has(to):
				declared.append(to))
		language_requested.emit(to)
	_confirm.popup_centered()


func _run(label: String, mutate: Callable) -> void:
	commit.call(label, mutate)
	_rebuild()


# ---------------------------------------------------------------- CSV

func _ask_file(mode: String) -> void:
	_file_mode = mode
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if mode == "export" else FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = "Export all texts" if mode == "export" else "Import texts"
	_file_dialog.popup_centered_ratio(0.6)


func _on_file_selected(path: String) -> void:
	var root: Resource = root_provider.call()
	if _file_mode == "export":
		var entries := TextWalker.collect(root)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_status.text = "Could not write %s." % path
			return
		file.store_string(TextWalker.to_csv(entries, TextWalker.content_languages(root, entries)))
		file.close()
		_status.text = "Exported %d texts to %s. Translate the language columns (keep the key column), then import the file again." % [TextWalker.with_text(entries).size(), path]
	else:
		var text := FileAccess.get_file_as_string(path)
		var result := {}
		_run("Import texts", func():
			var current: Resource = root_provider.call()
			result.merge(TextWalker.from_csv(text, TextWalker.collect(current)), true)
			var declared: Array[String] = current.get("languages")
			for code: String in result["languages"]:
				if code != str(current.get("default_language")) and not declared.has(code):
					declared.append(code))
		_status.text = "Imported: %d texts changed%s." % [result.get("updated", 0), (", %d rows had an unknown key and were skipped" % result["unknown_keys"]) if int(result.get("unknown_keys", 0)) > 0 else ""]


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
