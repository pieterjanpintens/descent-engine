class_name CharactersDialog
extends Window

## Popup editor for the characters of a campaign (Campaign.characters, opened from the campaign editor's
## "Characters…" button) or a mission (MissionData.characters, the mission editor's "Characters…" button): a name,
## a voice and a color each. Text wrapped in `[Name]...[/Name]` is read in that character's voice and colored in the
## text boxes of the editors (NarrationMarkup / NarrationHighlight). Same shape as MissionVariablesDialog: edits the
## given list in place, every change goes through `commit(label, mutate)`.
##
## Voices that belong to the optional "extra voices" download are listed too, marked "(not installed)" while
## missing - the story still plays then, the character just gets a stand-in voice (see Narrator).

const DEFAULT_COLORS: Array[Color] = [
	Color(0.95, 0.75, 0.3), Color(0.45, 0.8, 0.95), Color(0.95, 0.5, 0.5), Color(0.6, 0.9, 0.5),
	Color(0.8, 0.6, 0.95), Color(0.95, 0.65, 0.85), Color(0.5, 0.9, 0.8), Color(0.9, 0.85, 0.5),
]
const SAMPLE_LINE := "The old road is longer than it looks, friend, and the night is nearly upon us."

var _characters: Array[NarratorCharacter]
## (label: String, mutate: Callable) - applies `mutate` and records/refreshes however the owner wants.
var _commit: Callable
var _rows_container: VBoxContainer
var _empty_label: Label


func _ready() -> void:
	title = "Characters"
	size = Vector2i(520, 480)
	close_requested.connect(hide)
	visible = false

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	add_child(root)

	_empty_label = Label.new()
	_empty_label.text = "No characters yet. Give a character a voice, then wrap their words in [Name]...[/Name] in a text."
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_empty_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_container)

	var add_button := Button.new()
	add_button.text = "Add Character"
	add_button.pressed.connect(_on_add_pressed)
	root.add_child(add_button)


## Edits `characters` in place; every change goes through `commit(label, mutate)`.
func open_for_list(characters: Array[NarratorCharacter], commit: Callable) -> void:
	_characters = characters
	_commit = commit
	_rebuild_rows()
	popup_centered()


func _rebuild_rows() -> void:
	# queue_free(): this can run from a row's own button handler, which is a descendant of what is cleared here.
	for child in _rows_container.get_children():
		child.queue_free()
	if not _commit.is_valid():
		return
	_empty_label.visible = _characters.is_empty()
	for character in _characters:
		_rows_container.add_child(_build_row(character))
		_rows_container.add_child(HSeparator.new())


func _build_row(character: NarratorCharacter) -> Control:
	var row := HBoxContainer.new()

	var name_edit := LineEdit.new()
	name_edit.text = character.character_name
	name_edit.placeholder_text = "Name (case matters)"
	name_edit.custom_minimum_size.x = 110
	var commit_name := func():
		_commit_field("Edit character name", func(): character.character_name = name_edit.text.strip_edges())
	name_edit.text_submitted.connect(func(_t): commit_name.call())
	name_edit.focus_exited.connect(commit_name)
	row.add_child(name_edit)

	var voice_option := OptionButton.new()
	voice_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var voices := NarratorVoices.all()
	for i in voices.size():
		var voice := voices[i]
		voice_option.add_item(voice["label"] if NarratorVoices.model_installed(voice["model"]) else "%s (not installed)" % voice["label"], i)
		if voice["id"] == character.voice_id:
			voice_option.select(i)
	voice_option.item_selected.connect(func(index: int):
		var chosen := voices[voice_option.get_item_id(index)]
		_commit_field("Edit character voice", func(): character.voice_id = chosen["id"])
	)
	row.add_child(voice_option)

	var play := Button.new()
	play.text = "▶"
	play.tooltip_text = "Hear this voice"
	play.pressed.connect(func(): Narrator.speak_voice(character.voice_id, SAMPLE_LINE))
	row.add_child(play)

	var color_button := ColorPickerButton.new()
	color_button.custom_minimum_size = Vector2(36, 0)
	color_button.color = character.color
	color_button.edit_alpha = false
	color_button.color_changed.connect(func(color: Color):
		_commit_field("Edit character color", func(): character.color = color)
	)
	row.add_child(color_button)

	var remove := Button.new()
	remove.text = "×"
	remove.tooltip_text = "Remove this character"
	remove.pressed.connect(func():
		_commit_field("Remove character", func(): _characters.erase(character))
		_rebuild_rows()
	)
	row.add_child(remove)
	return row


func _on_add_pressed() -> void:
	var created := NarratorCharacter.new()
	created.character_name = "Character %d" % (_characters.size() + 1)
	created.color = DEFAULT_COLORS[_characters.size() % DEFAULT_COLORS.size()]
	_commit_field("Add character", func(): _characters.append(created))
	_rebuild_rows()


func _commit_field(label: String, mutate: Callable) -> void:
	if _commit.is_valid():
		_commit.call(label, mutate)
