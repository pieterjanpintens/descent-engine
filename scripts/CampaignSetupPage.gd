class_name CampaignSetupPage
extends Control

## The page between "Begin campaign" and the first chapter: everything that is chosen once per game. Full screen, in the style of the begin campaign page
## (the designer's detail background, back arrow, shadowed title, the plaque button). It has a SECTION per setting, so more can be added later
## (difficulty is the obvious next one): a section is `_section(column, title, width, hint)` plus its controls, in the left or the right column, and whatever it chooses goes into `confirmed`.
## Now: the name of the save game, and - only when narration is installed - the voice of each hero.

signal confirmed(save_name: String, hero_voices: Dictionary)
signal cancelled

const BACKGROUND := "res://models/ui/bg_detail.jpg"
const BACK_ARROW := "res://models/ui/back_arrow.png"
const LEFT_WIDTH := 440.0   ## the first column (save game name, later more settings)
const RIGHT_WIDTH := 580.0  ## the second column (hero voices)

var _name_taken: Callable  ## (name: String) -> bool, supplied by the player: a save game with that name exists
var _name_edit: LineEdit
var _name_message: Label
var _start_button: Button
var _picker: HeroVoicesPicker


## `campaign_name` for the title, `suggestion` the prefilled save game name, `name_taken` tells whether a name is already used.
func setup(campaign_name: String, suggestion: String, name_taken: Callable) -> void:
	_name_taken = name_taken
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
		_picker = HeroVoicesPicker.new()
		voices_column.add_child(_picker)
		_picker.setup({})

	var bottom := CenterContainer.new()
	page.add_child(bottom)
	_start_button = MenuStyle.plaque_button("Start game", Vector2(310, 101), _on_start_pressed)
	(_start_button.get_child(0) as Label).add_theme_font_size_override("font_size", 32)
	bottom.add_child(_start_button)
	_check_name()
	_name_edit.grab_focus.call_deferred()
	_name_edit.select_all.call_deferred()


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
		problem = "A save game called '%s' already exists." % entered
	_name_message.text = problem
	_start_button.disabled = problem != ""
	_start_button.modulate = Color(1, 1, 1, 0.5) if problem != "" else Color.WHITE


func _on_start_pressed() -> void:
	_check_name()
	if _start_button.disabled:
		return
	confirmed.emit(_name_edit.text.strip_edges(), _picker.answer() if _picker != null else {})
