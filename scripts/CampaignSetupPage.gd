class_name CampaignSetupPage
extends Control

## The page between "Begin campaign" and the first chapter: everything that is chosen once per game. Full screen, in the style of the begin campaign page
## (the designer's detail background, back arrow, shadowed title, the plaque button). It has a SECTION per setting, so more can be added later
## (more can follow): a section is `_section(column, title, width, hint)` plus its controls, in the left or the right column, and whatever it chooses goes into `confirmed`.
## Now: the language (chosen here and fixed for the whole game), the name of the save game, and - only when narration is installed - the voice of each hero.

signal confirmed(save_name: String, hero_voices: Dictionary, language: String, difficulty: int)
signal cancelled

const BACKGROUND := "res://models/ui/bg_detail.jpg"
const BACK_ARROW := "res://models/ui/back_arrow.png"
const LEFT_WIDTH := 440.0   ## the first column (save game name, later more settings)
const RIGHT_WIDTH := 580.0  ## the second column (hero voices)

var _language: String = "en"
var _difficulty: int = PlayerSettings.mission_difficulty  ## the one the player chose last, in any game
var _name_taken: Callable  ## (name: String) -> bool, supplied by the player: a save game with that name exists
var _name_edit: LineEdit
var _name_message: Label
var _start_button: Button
var _picker: HeroVoicesPicker
var _voices_holder: VBoxContainer  ## the hero voice rows (or a hint) of the chosen language


## `campaign_name` for the title, `suggestion` the prefilled save game name, `name_taken` tells whether a name is already used,
## `languages` the languages the campaign can be played in and `start_language` the one to start with.
func setup(campaign_name: String, suggestion: String, name_taken: Callable, languages: Array[String] = ["en"], start_language: String = "en") -> void:
	_name_taken = name_taken
	_language = start_language if languages.has(start_language) else languages[0]
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := TextureRect.new()
	backdrop.texture = load(BACKGROUND) as Texture2D
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)

	var header := HBoxContainer.new()
	page.add_child(header)
	header.add_child(MenuStyle.texture_button(BACK_ARROW, Vector2(78, 46), func(): cancelled.emit()))
	var title := MenuStyle.shadow_label("Set up your game", 40, MenuStyle.TEXT_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(Control.new())  # keeps the title centred against the back arrow
	header.get_child(2).custom_minimum_size = Vector2(78, 46)
	var subtitle := Label.new()
	subtitle.text = campaign_name
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.7)
	page.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 56)
	center.add_child(columns)
	var column := _new_column(LEFT_WIDTH)
	columns.add_child(column)

	# ---- Language: said clearly here because it cannot be changed once the game has started ----
	_section(column, "Language", LEFT_WIDTH, "The language this game is read, logged and narrated in. You can change it later in Options.")
	if languages.size() > 1:
		var picker := OptionButton.new()
		for code in languages:
			picker.add_item(CampaignInfo.native_name(code))
			picker.set_item_metadata(picker.item_count - 1, code)
			if code == _language:
				picker.select(picker.item_count - 1)
		picker.item_selected.connect(func(index: int):
			_language = str(picker.get_item_metadata(index))
			_fill_voices())
		column.add_child(picker)
	else:
		var only := Label.new()
		only.text = CampaignInfo.native_name(_language)
		column.add_child(only)

	# ---- Difficulty: 1-4 with a name; also a variable (difficulty) the campaign's conditions can read ----
	_section(column, "Difficulty", LEFT_WIDTH, "Tougher monsters and a harder mission at the higher numbers. You can change it before each mission.")
	var difficulty_picker := OptionButton.new()
	for value in Difficulty.all():
		difficulty_picker.add_item(Difficulty.label(value), value)
	difficulty_picker.select(difficulty_picker.get_item_index(_difficulty))
	var difficulty_hint := Label.new()
	difficulty_hint.text = Difficulty.description(_difficulty)
	difficulty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	difficulty_hint.custom_minimum_size.x = LEFT_WIDTH
	difficulty_hint.modulate = Color(1, 1, 1, 0.75)
	difficulty_picker.item_selected.connect(func(index: int):
		_difficulty = difficulty_picker.get_item_id(index)
		difficulty_hint.text = Difficulty.description(_difficulty))
	column.add_child(difficulty_picker)
	column.add_child(difficulty_hint)

	# ---- Save game name ----
	_section(column, "Save game", LEFT_WIDTH, "Your progress is saved automatically under this name, so you can leave and pick up where you stopped (Load game in the main menu). Use a different name for every group or playthrough.")
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "e.g. Friday night group"
	_name_edit.text = suggestion
	_name_edit.text_changed.connect(func(_text: String): _check_name())
	_name_edit.text_submitted.connect(func(_text: String): _on_start_pressed())
	column.add_child(_name_edit)
	_name_message = Label.new()
	_name_message.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	column.add_child(_name_message)

	# ---- Hero voices (only when narration is installed: there would be nothing to hear otherwise) ----
	if Narrator.is_available():
		var voices_column := _new_column(RIGHT_WIDTH)
		columns.add_child(voices_column)
		_section(voices_column, "Hero voices", RIGHT_WIDTH, "Pick a voice for each hero. Their lines in the story are read in it, and nobody else will use it.")
		_voices_holder = VBoxContainer.new()
		voices_column.add_child(_voices_holder)
		_fill_voices()

	var bottom := CenterContainer.new()
	page.add_child(bottom)
	_start_button = MenuStyle.plaque_button("Start game", Vector2(310, 101), _on_start_pressed)
	(_start_button.get_child(0) as Label).add_theme_font_size_override("font_size", 32)
	bottom.add_child(_start_button)
	_check_name()
	_name_edit.grab_focus.call_deferred()
	_name_edit.select_all.call_deferred()


## The hero voice rows for the chosen language - the voices differ per language. A language none of whose voices is installed shows a
## hint instead: that game is shown as text only (the small hint also appears when the story would be read).
func _fill_voices() -> void:
	if _voices_holder == null:
		return
	for child in _voices_holder.get_children():
		_voices_holder.remove_child(child)
		child.free()
	_picker = null
	if NarratorVoices.installed_for(_language).is_empty():
		var hint := Label.new()
		hint.text = tr("No narration voices for %s are installed, so this game is shown as text only. Download them in Options > Voice.") % CampaignInfo.native_name(_language)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = RIGHT_WIDTH
		_voices_holder.add_child(hint)
		return
	_picker = HeroVoicesPicker.new()
	_voices_holder.add_child(_picker)
	_picker.setup({}, _language)


func _new_column(width: float) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = width
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.add_theme_constant_override("separation", 10)
	return column


## A heading with its explanation, the start of a section.
func _section(column: VBoxContainer, heading_text: String, width: float, hint_text: String) -> void:
	if column.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 14
		column.add_child(gap)
	column.add_child(MenuStyle.shadow_label(heading_text, 28, MenuStyle.TEXT_COLOR, MenuStyle.SHADOW_COLOR, true))
	column.get_child(column.get_child_count() - 1).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var hint := Label.new()
	hint.text = hint_text
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = width  # a wrapping label with no width wraps per letter
	hint.modulate = Color(1, 1, 1, 0.75)
	column.add_child(hint)


func _check_name() -> void:
	var entered := _name_edit.text.strip_edges()
	var problem := ""
	if entered == "":
		problem = "A save game needs a name."
	elif _name_taken.call(entered):
		problem = tr("A save game called '%s' already exists.") % entered
	_name_message.text = problem
	_start_button.disabled = problem != ""
	_start_button.modulate = Color(1, 1, 1, 0.5) if problem != "" else Color.WHITE


func _on_start_pressed() -> void:
	_check_name()
	if _start_button.disabled:
		return
	confirmed.emit(_name_edit.text.strip_edges(), _picker.answer() if _picker != null else {}, _language, _difficulty)
