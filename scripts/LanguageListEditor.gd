class_name LanguageListEditor
extends VBoxContainer

## An ordered list of languages (CampaignInfo.LANGUAGES codes): each row can be moved up or down or removed, and a picker adds one of the others.
## Used for the player's preferred languages (Options > General). `setup(list, on_change)`: `on_change.call(new_list: Array[String])` after every change;
## the caller decides what to keep (the list is never allowed to become empty here).

var _languages: Array[String] = []
var _on_change: Callable
var _rows: VBoxContainer
var _picker: OptionButton


func setup(languages: Array[String], on_change: Callable) -> void:
	_languages = languages.duplicate()
	_on_change = on_change
	add_theme_constant_override("separation", 4)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	add_child(_rows)
	var add_row := HBoxContainer.new()
	add_child(add_row)
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_picker)
	var add := Button.new()
	add.text = "Add language"
	add.pressed.connect(_on_add_pressed)
	add_row.add_child(add)
	_rebuild()


func languages() -> Array[String]:
	return _languages.duplicate()


func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.free()
	for index in _languages.size():
		var code := _languages[index]
		var row := HBoxContainer.new()
		var order := Label.new()
		order.text = "%d." % (index + 1)
		order.custom_minimum_size.x = 26
		row.add_child(order)
		var name_label := Label.new()
		name_label.text = "%s  (%s)" % [CampaignInfo.native_name(code), code]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var up := _small_button("▲", "Read in this language earlier", index > 0, func(): _move(index, -1))
		var down := _small_button("▼", "Read in this language later", index < _languages.size() - 1, func(): _move(index, 1))
		var remove := _small_button("✕", "Remove", _languages.size() > 1, func(): _remove(index))
		for button in [up, down, remove]:
			row.add_child(button)
		_rows.add_child(row)
	_picker.clear()
	for language in CampaignInfo.LANGUAGES:
		if not _languages.has(language["code"]):
			_picker.add_item(language["native"])
			_picker.set_item_metadata(_picker.item_count - 1, language["code"])


func _small_button(text: String, tip: String, enabled: bool, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	return button


func _changed() -> void:
	_rebuild()
	_on_change.call(languages())


func _move(index: int, delta: int) -> void:
	var target := index + delta
	if target < 0 or target >= _languages.size():
		return
	var code := _languages[index]
	_languages.remove_at(index)
	_languages.insert(target, code)
	_changed()


func _remove(index: int) -> void:
	if _languages.size() > 1:
		_languages.remove_at(index)
		_changed()


func _on_add_pressed() -> void:
	if _picker.item_count == 0 or _picker.selected < 0:
		return
	_languages.append(str(_picker.get_item_metadata(_picker.selected)))
	_changed()
