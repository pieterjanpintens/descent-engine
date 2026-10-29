class_name TranslationWindow
extends Window

## Every text of a campaign or mission next to its original, for translating it: a list of the texts on the left (the missing ones marked), the original
## and the translation of the selected one on the right. With AI help switched on a text - or every missing one - can be translated by the AI (a draft to
## check). Like the other big editor windows it covers the whole game window and has its own Close button.
## The owner supplies `root_provider` (the CURRENT campaign / mission - undo swaps them) and `commit(label, mutate)` (runs `mutate` as one undo step and
## refreshes its panels); it calls `refresh()` after an undo so the list follows.

const MAX_AI_TEXT := 6000
const MAX_AI_TOKENS := 2500
## Texts sent to the AI at the same time by "Translate all missing" (each has its own AiClient: one request per client).
const PARALLEL_REQUESTS := 4

var root_provider: Callable
var commit: Callable
var read_only := false

var _entries: Array[Dictionary] = []   ## every text with something in it, in editor order
var _shown: Array[Dictionary] = []     ## what the list shows (all, or only the missing ones)
var _source: String = "en"
var _target: String = "en"
var _selected_path := ""
var _loading := false
var _batch_running := false
var _batch_cancelled := false

var _source_picker: OptionButton
var _target_picker: OptionButton
var _only_missing: CheckBox
var _progress_label: Label
var _list: ItemList
var _where_label: Label
var _source_edit: TextEdit
var _target_edit: TextEdit
var _status: Label
var _translate_button: Button
var _translate_all_button: Button
var _cancel_button: Button
var _commit_timer: Timer
var _client: AiClient
var _batch_clients: Array[AiClient] = []
## Tests: builds the client a batch worker uses (a client with a mock server / stub program).
var client_factory: Callable


func _init() -> void:
	visible = false  # a Window is shown as soon as it is added to the tree


func _ready() -> void:
	title = "Translate"
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	margin.add_child(page)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	page.add_child(header)
	var heading := Label.new()
	heading.text = "Translate"
	heading.add_theme_font_size_override("font_size", 18)
	header.add_child(heading)
	header.add_child(_label("from"))
	_source_picker = OptionButton.new()
	_source_picker.item_selected.connect(func(index: int): _on_language_changed(str(_source_picker.get_item_metadata(index)), _target))
	header.add_child(_source_picker)
	header.add_child(_label("to"))
	_target_picker = OptionButton.new()
	_target_picker.item_selected.connect(func(index: int): _on_language_changed(_source, str(_target_picker.get_item_metadata(index))))
	header.add_child(_target_picker)
	_only_missing = CheckBox.new()
	_only_missing.text = "Only the missing ones"
	_only_missing.button_pressed = true
	_only_missing.toggled.connect(func(_on: bool): _fill_list())
	header.add_child(_only_missing)
	_progress_label = Label.new()
	_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_progress_label)
	_translate_all_button = _button("Translate all missing with AI…", _on_translate_all_pressed)
	header.add_child(_translate_all_button)
	_cancel_button = _button("Stop", _on_stop_pressed)
	_cancel_button.visible = false
	header.add_child(_cancel_button)
	header.add_child(_button("Close", hide))

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(split)
	_list = ItemList.new()
	_list.custom_minimum_size.x = 380
	_list.item_selected.connect(_on_item_selected)
	split.add_child(_list)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	split.add_child(detail)
	_where_label = Label.new()
	_where_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_where_label.custom_minimum_size.x = 400  # a wrapping label with no width wraps per letter
	_where_label.modulate = Color(1, 1, 1, 0.7)
	detail.add_child(_where_label)
	detail.add_child(_label("Original"))
	_source_edit = TextEdit.new()
	_source_edit.editable = false
	_source_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_source_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(_source_edit)
	detail.add_child(_label("Translation"))
	_target_edit = TextEdit.new()
	_target_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_target_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_target_edit.text_changed.connect(_on_target_changed)
	_target_edit.focus_exited.connect(_commit_current)
	detail.add_child(_target_edit)
	var buttons := HBoxContainer.new()
	detail.add_child(buttons)
	buttons.add_child(_button("Copy the original", _on_copy_pressed))
	_translate_button = _button("Translate with AI", _on_translate_pressed)
	buttons.add_child(_translate_button)
	buttons.add_child(_button("Next missing", _on_next_missing_pressed))
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.8)
	buttons.add_child(_status)

	_commit_timer = Timer.new()
	_commit_timer.one_shot = true
	_commit_timer.wait_time = 0.6
	_commit_timer.timeout.connect(_commit_current)
	add_child(_commit_timer)
	_client = AiClient.new()
	add_child(_client)
	close_requested.connect(hide)


## Opens the window for translating into `target` (the default language is the original).
func open(target: String) -> void:
	var root: Resource = root_provider.call()
	if root == null:
		return
	_source = str(root.get("default_language"))
	_target = target if target != _source else ""
	_selected_path = ""
	_reload(true)
	FullScreenWindow.show(self)


## The campaign / mission was replaced (undo, redo): read everything again, keeping the selected text.
func refresh() -> void:
	if visible:
		_reload(false)


func _reload(rebuild_pickers: bool) -> void:
	var root: Resource = root_provider.call()
	if root == null:
		return
	_entries = TextWalker.with_text(TextWalker.collect(root))
	var codes := TextWalker.content_languages(root, TextWalker.collect(root))
	if rebuild_pickers:
		_fill_picker(_source_picker, codes, _source)
		var targets: Array[String] = []
		for code in codes:
			if code != _source:
				targets.append(code)
		if _target == "" or not targets.has(_target):
			_target = targets[0] if not targets.is_empty() else _source
		_fill_picker(_target_picker, targets if not targets.is_empty() else codes, _target)
	_update_ai_buttons()
	_fill_list()


func _fill_picker(picker: OptionButton, codes: Array[String], current: String) -> void:
	picker.clear()
	for code in codes:
		picker.add_item(CampaignInfo.language_name(code))
		picker.set_item_metadata(picker.item_count - 1, code)
		if code == current:
			picker.select(picker.item_count - 1)


func _on_language_changed(source: String, target: String) -> void:
	_commit_current()
	_source = source
	_target = target
	_reload(false)


func _fill_list() -> void:
	_list.clear()
	_shown.clear()
	var done := 0
	var selected_index := -1
	for entry in _entries:
		var has_translation: bool = str(entry["map"].get(_target, "")) != ""
		if has_translation:
			done += 1
		elif str(entry["map"].get(_source, "")) == "":
			continue  # nothing to translate from in this source language
		if _only_missing.button_pressed and has_translation and entry["path"] != _selected_path:
			continue
		_shown.append(entry)
		_list.add_item(_list_text(entry, has_translation))
		_list.set_item_tooltip(_list.item_count - 1, str(entry["label"]))
		if entry["path"] == _selected_path:
			selected_index = _list.item_count - 1
	_progress_label.text = "%d of %d translated into %s" % [done, _entries.size(), CampaignInfo.language_name(_target)]
	if selected_index >= 0:
		_list.select(selected_index)
		_show_entry(_shown[selected_index])
	else:
		_selected_path = ""
		_show_entry({})


func _list_text(entry: Dictionary, has_translation: bool) -> String:
	var parts: PackedStringArray = str(entry["label"]).split(" › ")
	var short := " › ".join(parts.slice(maxi(0, parts.size() - 2)))
	var first_line := str(entry["map"].get(_source, "")).strip_edges().split("\n")[0]
	if first_line.length() > 40:
		first_line = first_line.substr(0, 39) + "…"
	return "%s  %s  -  %s" % ["●" if has_translation else "○", short, first_line]


func _on_item_selected(index: int) -> void:
	_commit_current()
	if index >= 0 and index < _shown.size():
		_selected_path = _shown[index]["path"]
		_show_entry(_shown[index])


func _show_entry(entry: Dictionary) -> void:
	_loading = true
	var has_entry := not entry.is_empty()
	_where_label.text = str(entry["label"]) if has_entry else "Select a text in the list."
	_source_edit.text = str(entry["map"].get(_source, "")) if has_entry else ""
	_target_edit.text = str(entry["map"].get(_target, "")) if has_entry else ""
	_target_edit.editable = has_entry and not read_only
	_loading = false
	_status.text = ""


# ---------------------------------------------------------------- editing

func _on_target_changed() -> void:
	if not _loading:
		_commit_timer.start()


## Writes the translation box into the selected text (one undo step; typing in bursts melds into one).
func _commit_current() -> void:
	_commit_timer.stop()
	if _selected_path == "" or read_only or _loading:
		return
	var path := _selected_path
	var text := _target_edit.text
	var target := _target
	if text == _text_of(path, target):
		return
	commit.call("Translate", func():
		for entry in TextWalker.collect(root_provider.call()):
			if entry["path"] == path:
				LText.put_in(entry["map"], target, text)
				break)
	_entries = TextWalker.with_text(TextWalker.collect(root_provider.call()))
	_update_marker()


func _text_of(path: String, language: String) -> String:
	for entry in _entries:
		if entry["path"] == path:
			return str(entry["map"].get(language, ""))
	return ""


## The list row and the counter of the text that was just edited (the list is not rebuilt: that would lose the selection and the scroll position).
func _update_marker() -> void:
	var done := 0
	for entry in _entries:
		if str(entry["map"].get(_target, "")) != "":
			done += 1
	_progress_label.text = "%d of %d translated into %s" % [done, _entries.size(), CampaignInfo.language_name(_target)]
	for index in _shown.size():
		if _shown[index]["path"] == _selected_path:
			_list.set_item_text(index, _list_text(_find(_selected_path), str(_find(_selected_path)["map"].get(_target, "")) != ""))


func _find(path: String) -> Dictionary:
	for entry in _entries:
		if entry["path"] == path:
			return entry
	return {}


func _on_copy_pressed() -> void:
	if _selected_path == "" or read_only:
		return
	_loading = true
	_target_edit.text = _source_edit.text
	_loading = false
	_commit_current()


func _on_next_missing_pressed() -> void:
	_commit_current()
	var start := _list.get_selected_items()[0] if not _list.get_selected_items().is_empty() else -1
	for step in range(1, _shown.size() + 1):
		var index := (start + step) % _shown.size() if not _shown.is_empty() else 0
		if not _shown.is_empty() and str(_shown[index]["map"].get(_target, "")) == "":
			_list.select(index)
			_list.ensure_current_is_visible()
			_on_item_selected(index)
			return
	_status.text = "Nothing missing."


# ---------------------------------------------------------------- AI

func _update_ai_buttons() -> void:
	var can_translate := AiClient.is_configured() and not read_only and _source != _target
	_translate_button.disabled = not can_translate
	_translate_all_button.disabled = not can_translate or _batch_running
	var tip := "" if AiClient.is_configured() else "Switch on AI help in Options > AI first."
	_translate_button.tooltip_text = tip
	_translate_all_button.tooltip_text = tip


func _on_translate_pressed() -> void:
	if _selected_path == "" or _client.is_busy():
		return
	var entry := _find(_selected_path)
	var original := str(entry["map"].get(_source, ""))
	_translate_button.disabled = true
	_status.text = "Translating…"
	var result := await _translate(original, str(entry["label"]))
	_update_ai_buttons()
	if not is_instance_valid(self) or _selected_path != str(entry["path"]):
		return
	if result["ok"]:
		_loading = true
		_target_edit.text = result["text"]
		_loading = false
		_commit_current()
		_status.text = "Translated by the AI - check it." + ((" " + str(result["warning"])) if str(result["warning"]) != "" else "")
	else:
		_status.text = str(result["error"])


func _on_stop_pressed() -> void:
	_batch_cancelled = true
	for client in _batch_clients:
		if is_instance_valid(client):
			client.cancel()  # the requests on their way end at once instead of finishing first


## One text through the AI: {ok, text, error, warning}. `client` = the AiClient to ask through (one request at a time per client).
func _translate(original: String, where: String, client: AiClient = null) -> Dictionary:
	if original.length() > MAX_AI_TEXT:
		return {"ok": false, "text": "", "error": "That text is too long to send (%d characters)." % original.length(), "warning": ""}
	if client == null:
		client = _client
	var answer := await client.ask(system_prompt(_source, _target), user_prompt(original, where), MAX_AI_TOKENS)
	if not bool(answer["ok"]):
		return {"ok": false, "text": "", "error": str(answer["error"]), "warning": ""}
	var text := AiAssist.clean_answer(str(answer["text"]))
	return {"ok": text != "", "text": text, "error": "The AI sent an empty answer.", "warning": AiAssist.tag_problem(original, text, false)}


func _on_translate_all_pressed() -> void:
	if _batch_running or _client.is_busy():
		return
	_commit_current()
	var todo: Array[Dictionary] = []
	for entry in _entries:
		if str(entry["map"].get(_target, "")) == "" and str(entry["map"].get(_source, "")) != "":
			todo.append({"path": entry["path"], "label": entry["label"], "text": str(entry["map"][_source])})
	if todo.is_empty():
		_status.text = "Nothing missing."
		return
	_batch_running = true
	_batch_cancelled = false
	_translate_all_button.disabled = true
	_cancel_button.visible = true
	# Several workers, each with its own client, take the next text from the shared queue (a dictionary: lambdas and coroutines see plain variables by value).
	var state := {"next": 0, "finished": 0, "active": 0, "stop": false, "results": {}, "failed": 0, "warned": 0, "error": ""}
	_progress_label.text = "Translating 0 of %d…" % todo.size()
	_batch_clients.clear()
	for worker in mini(PARALLEL_REQUESTS, todo.size()):
		var client: AiClient = client_factory.call() if client_factory.is_valid() else AiClient.new()
		add_child(client)
		_batch_clients.append(client)
		_batch_worker(client, todo, state)
	while int(state["active"]) > 0:
		await get_tree().process_frame
		if not is_instance_valid(self):
			return
	for client in _batch_clients:
		client.queue_free()
	_batch_clients.clear()
	var results: Dictionary = state["results"]
	var failed: int = state["failed"]
	var warned: int = state["warned"]
	_batch_running = false
	_cancel_button.visible = false
	if not results.is_empty():
		var target := _target
		commit.call("Translate with AI", func():
			for entry in TextWalker.collect(root_provider.call()):
				if results.has(entry["path"]) and str(entry["map"].get(target, "")) == "":
					LText.put_in(entry["map"], target, str(results[entry["path"]])))
	_update_ai_buttons()
	_reload(false)  # reselects an item, which clears the status line: say the result after it
	_status.text = "AI translated %d texts (drafts - check them)%s%s." % [results.size(),
		", %d skipped because the character tags changed" % warned if warned > 0 else "", ", %d failed" % failed if failed > 0 else ""]
	if results.is_empty() and str(state["error"]) != "" and not _batch_cancelled:
		_status.text = str(state["error"])


## One batch worker: keeps taking the next text until the queue is empty or the batch is stopped.
func _batch_worker(client: AiClient, todo: Array[Dictionary], state: Dictionary) -> void:
	state["active"] = int(state["active"]) + 1
	while not _batch_cancelled and not bool(state["stop"]):
		var index: int = state["next"]
		if index >= todo.size():
			break
		state["next"] = index + 1
		var answer := await _translate(todo[index]["text"], todo[index]["label"], client)
		if not is_instance_valid(self):
			state["active"] = int(state["active"]) - 1
			return
		state["finished"] = int(state["finished"]) + 1
		_progress_label.text = "Translating %d of %d…" % [state["finished"], todo.size()]
		if _batch_cancelled and not bool(answer["ok"]):
			break
		if not bool(answer["ok"]):
			state["failed"] = int(state["failed"]) + 1
			state["error"] = str(answer["error"])
			if int(state["failed"]) >= 3 and state["results"].is_empty():
				state["stop"] = true  # the same problem every time (no key, no connection): stop early
			continue
		if str(answer["warning"]) != "":
			state["warned"] = int(state["warned"]) + 1  # tags changed: not applied, the author does that one by hand
			continue
		state["results"][todo[index]["path"]] = answer["text"]
	state["active"] = int(state["active"]) - 1


static func system_prompt(source: String, target: String) -> String:
	return "You are a translator for the author of a fantasy adventure campaign for a digital tabletop companion app. " \
		+ "Translate the text you get from %s to %s. Rules: " % [CampaignInfo.language_name(source), CampaignInfo.language_name(target)] \
		+ "keep the meaning, tone and register of the original; " \
		+ "keep every character tag such as [Name]...[/Name] exactly as it is - do not translate the name inside a tag, only the words between the tags; " \
		+ "text in (round brackets) is an acting hint for the reader: translate it and keep the brackets; " \
		+ "keep placeholders such as $1, $2, {name}, {speed}, {damage} and %s exactly as they are; " \
		+ "keep line breaks and paragraphs; names of people and places stay as they are unless they have a well-known translation; " \
		+ "do not add notes, quotation marks around the whole answer or explanations. Reply with the translation only."


static func user_prompt(text: String, where: String) -> String:
	return ("Where this text is used:\n%s\n\n" % where if where.strip_edges() != "" else "") + "The text:\n<<<\n%s\n>>>" % text


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
