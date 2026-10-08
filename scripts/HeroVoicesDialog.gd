class_name HeroVoicesDialog
extends Window

## Asked once when a campaign starts: which narration voice does each hero speak with (`[Chance]...[/Chance]` in a story
## text). A voice goes to one hero only - a voice another hero has is greyed out in the others' lists - and the story
## teller's voice is not offered. Add it to the tree, then `await ask(current)`; the answer is {hero name: voice id}
## ("" = a voice picked from the name, used when there are fewer installed voices than heroes).

signal done

var _voices: Array[Dictionary] = []
var _assigned: Array[String] = []
var _options: Array[OptionButton] = []


func ask(current: Dictionary) -> Dictionary:
	title = "Hero voices"
	exclusive = true
	close_requested.connect(_finish)
	_collect_voices()
	_assign_defaults(current)
	_build()
	popup_centered(Vector2i(520, 440))
	await done
	var answer := {}
	for i in HeroCatalog.HERO_NAMES.size():
		answer[HeroCatalog.HERO_NAMES[i]] = _assigned[i]
	hide()
	return answer


func _finish() -> void:
	done.emit()


## Installed voices except the story teller's.
func _collect_voices() -> void:
	var storyteller: String = PlayerSettings.storyteller_voice
	for voice in NarratorVoices.installed():
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
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_top = 10
	root.offset_right = -10
	root.offset_bottom = -10
	add_child(root)

	var intro := Label.new()
	intro.text = "Pick a voice for each hero. Their lines in the story are read in it, and nobody else will use it."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(intro)

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
				Narrator.speak("[%s]%s[/%s]" % [hero, CharactersDialog.SAMPLE_LINE, hero], as_hero)
			else:
				Narrator.speak_voice(_assigned[i], CharactersDialog.SAMPLE_LINE)
		)
		row.add_child(play)
		root.add_child(row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	var ok := Button.new()
	ok.text = "Done"
	ok.pressed.connect(_finish)
	root.add_child(ok)
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
