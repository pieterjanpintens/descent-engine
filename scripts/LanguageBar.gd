class_name LanguageBar
extends HBoxContainer

## The editors' language controls: which language the texts are being edited in, and one menu button with the rest (manage the languages of the
## campaign / mission, the side-by-side translation window). Kept this narrow on purpose: the mission editor's toolbar is crowded.
## The bar only shows and announces; the editor does the work (LText.use_for_editing(), refreshing its panels).
## `show_languages(codes, current, default)` fills the picker (the default language is marked).

signal language_selected(code: String)
signal manage_pressed
signal translate_pressed

const MENU_MANAGE := 0
const MENU_TRANSLATE := 1

var _picker: OptionButton
var _menu: MenuButton
var _suppress := false

## The mission editor puts the Languages menu in its top menu bar instead (see CreatorToolbar): then this bar only shows the picker.
var menu_in_bar := true:
	set(value):
		menu_in_bar = value
		if _menu != null:
			_menu.visible = value


func _init() -> void:
	add_theme_constant_override("separation", 6)
	_picker = OptionButton.new()
	_picker.fit_to_longest_item = false  # as wide as the chosen language, not the longest one
	_picker.tooltip_text = "The language the texts you type are written in. A text that is missing in this language shows the default language's text until you translate it."
	_picker.item_selected.connect(func(index: int):
		if not _suppress:
			language_selected.emit(str(_picker.get_item_metadata(index))))
	add_child(_picker)
	_menu = MenuButton.new()
	_menu.text = "Languages"
	_menu.flat = false
	_menu.tooltip_text = "Add or remove languages, choose the default one, import or export the texts, or translate them side by side with the original."
	var popup := _menu.get_popup()
	popup.add_item("Manage languages…", MENU_MANAGE)
	popup.add_item("Translate…", MENU_TRANSLATE)
	popup.id_pressed.connect(func(id: int):
		if id == MENU_MANAGE:
			manage_pressed.emit()
		elif id == MENU_TRANSLATE:
			translate_pressed.emit())
	_menu.visible = menu_in_bar
	add_child(_menu)


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
	_menu.get_popup().set_item_disabled(MENU_TRANSLATE, codes.size() < 2)
	_suppress = false
