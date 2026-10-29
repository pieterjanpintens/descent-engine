class_name LanguageBar
extends HBoxContainer

## The editors' language controls: which language the texts are being edited in, a button for the languages of the campaign / mission and one for
## the side-by-side translation window. The bar only shows and announces; the editor does the work (LText.use_for_editing(), refreshing its panels).
## `show_languages(codes, current, default)` fills the picker (the default language is marked).

signal language_selected(code: String)
signal manage_pressed
signal translate_pressed

var _picker: OptionButton
var _translate: Button
var _suppress := false


func _init() -> void:
	add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = "Language:"
	add_child(label)
	_picker = OptionButton.new()
	_picker.fit_to_longest_item = false  # as wide as the chosen language, not the longest one
	_picker.tooltip_text = "The language the texts you type are written in. A text that is missing in this language shows the default language's text until you translate it."
	_picker.item_selected.connect(func(index: int):
		if not _suppress:
			language_selected.emit(str(_picker.get_item_metadata(index))))
	add_child(_picker)
	var manage := Button.new()
	manage.text = "Languages…"
	manage.tooltip_text = "Add or remove languages, choose the default one, import or export the texts."
	manage.pressed.connect(func(): manage_pressed.emit())
	add_child(manage)
	_translate = Button.new()
	_translate.text = "Translate…"
	_translate.tooltip_text = "Every text next to its original, with the missing ones first."
	_translate.pressed.connect(func(): translate_pressed.emit())
	add_child(_translate)


func show_languages(codes: Array[String], current: String, default_language: String) -> void:
	_suppress = true
	_picker.clear()
	for code in codes:
		var shown := CampaignInfo.language_name(code)
		if code == default_language:
			shown += " (default)"
		_picker.add_item(shown)
		_picker.set_item_metadata(_picker.item_count - 1, code)
		if code == current:
			_picker.select(_picker.item_count - 1)
	_translate.disabled = codes.size() < 2
	_suppress = false
