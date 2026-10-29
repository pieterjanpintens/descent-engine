class_name HeroVoicesDialog
extends Window

## For a save game that never got hero voices (it was started before narration was installed): which narration voice does each hero speak with.
## New games choose the voices on the campaign setup page (CampaignSetupPage) instead; both use HeroVoicesPicker for the rows.
## Add it to the tree, then `await ask(current)`; the answer is {hero name: voice id}.

signal done

var _picker: HeroVoicesPicker


func ask(current: Dictionary, lang: String = "") -> Dictionary:
	title = "Hero voices"
	exclusive = true
	unresizable = true
	close_requested.connect(_finish)
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
	_picker = HeroVoicesPicker.new()
	root.add_child(_picker)
	_picker.setup(current, lang)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)
	var ok := Button.new()
	ok.text = "Done"
	ok.pressed.connect(_finish)
	root.add_child(ok)
	popup_centered(Vector2i(520, 440))
	await done
	var answer := _picker.answer()
	hide()
	return answer


func _finish() -> void:
	done.emit()
