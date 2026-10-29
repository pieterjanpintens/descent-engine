class_name HeroVoicesPicker
extends VBoxContainer

## The hero voice rows: which narration voice does each hero speak with (`[Chance]...[/Chance]` in a story text). A voice goes to one hero only - a voice
## another hero has is greyed out in the others' lists - and the story teller's voice is not offered. `setup(current)` once, then `answer()` gives
## {hero name: voice id} ("" = a voice picked from the name, used when there are fewer installed voices than heroes).
## Used by the campaign setup page and, for a save game that never got voices, by HeroVoicesDialog.

var _lang := "en"  ## the narration language the voices are for
var _voices: Array[Dictionary] = []
var _assigned: Array[String] = []
var _options: Array[OptionButton] = []


## `lang` = the narration language the voices are chosen for ("" = the language the game is read in now).
func setup(current: Dictionary, lang: String = "") -> void:
	_lang = lang if lang != "" else NarratorVoices.reading_language()
	add_theme_constant_override("separation", 8)
	_collect_voices()
	_assign_defaults(current)
	_build()


func answer() -> Dictionary:
	var result := {}
	for i in HeroCatalog.HERO_NAMES.size():
		result[HeroCatalog.HERO_NAMES[i]] = _assigned[i]
	return result


## Installed voices of the language except the story teller's.
func _collect_voices() -> void:
	var storyteller: String = PlayerSettings.storyteller_for(_lang)
	for voice in NarratorVoices.installed_for(_lang):
		if voice["id"] != storyteller:
			_voices.append(voice)


func _assign_defaults(current: Dictionary) -> void:
	_assigned.clear()
	for i in HeroCatalog.HERO_NAMES.size():
		var wanted: String = current.get(HeroCatalog.HERO_NAMES[i], "")
		var usable := false
		for voice in _voices:
			usable = usable or voice["id"] == wanted
		_assigned.append(wanted if usable and not _assigned.has(wanted) else "")
	for i in _assigned.size():
		if _assigned[i] != "":
			continue
		for voice in _voices:
			if not _assigned.has(voice["id"]):
				_assigned[i] = voice["id"]
				break


func _build() -> void:
	for i in HeroCatalog.HERO_NAMES.size():
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = HeroCatalog.HERO_NAMES[i]
		name_label.custom_minimum_size.x = 90
		name_label.add_theme_color_override("font_color", HeroCatalog.slot_color(i))
		row.add_child(name_label)

		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.add_item("Random (from the name)", 0)
		for v in _voices.size():
			option.add_item(_voices[v]["label"], v + 1)
		option.item_selected.connect(func(index: int): _on_selected(i, option.get_item_id(index)))
		row.add_child(option)
		_options.append(option)

		var play := Button.new()
		play.text = "▶"
		play.tooltip_text = "Hear this voice"
		play.pressed.connect(func():
			var hero := HeroCatalog.HERO_NAMES[i]
			if _assigned[i] == "":
				var as_hero: Array[NarratorCharacter] = [NarratorCharacter.new()]
				as_hero[0].character_name = hero
				Narrator.speak("[%s]%s[/%s]" % [hero, NarratorVoices.sample_line(_lang), hero], as_hero, _lang)
			else:
				Narrator.speak_voice(_assigned[i], NarratorVoices.sample_line(_lang))
		)
		row.add_child(play)
		add_child(row)
	_refresh()


func _on_selected(hero_index: int, item_id: int) -> void:
	_assigned[hero_index] = "" if item_id == 0 else _voices[item_id - 1]["id"]
	_refresh()


## Selects each hero's voice and greys out, in every list, the voices another hero has.
func _refresh() -> void:
	for i in _options.size():
		var option := _options[i]
		for index in option.item_count:
			var item_id := option.get_item_id(index)
			if item_id == 0:
				continue
			var voice_id: String = _voices[item_id - 1]["id"]
			option.set_item_disabled(index, voice_id != _assigned[i] and _assigned.has(voice_id))
			if voice_id == _assigned[i]:
				option.select(index)
		if _assigned[i] == "":
			option.select(0)
