class_name SetupAssistant
extends Control

## The Setup Assistant: a short wizard for the things a player sets up once - the language, the game's art (Game assets), narration,
## voice commands and the optional AI writing help. Opens by itself the first time the main menu is shown (PlayerSettings.
## setup_assistant_shown) and from the "Setup Assistant" button at the bottom right of the main menu.
##
## Plain dialog rules: a fixed size (the body never changes size from page to page, each page scrolls inside), no moving, one button row.
## Every page uses the same installers and settings as the Options dialog; nothing is required - each page can be skipped with Next.
## Built entirely in code; the pages are built when shown (and again when the app language changes, since texts are put in widgets by tr()).

signal closed

const BODY_SIZE := Vector2(720, 430)

enum Page { LANGUAGE, ASSETS, NARRATION, VOICE, AI, DONE }

var _page: int = Page.LANGUAGE
var _busy := false

var _title_label: Label
var _step_label: Label
var _page_box: VBoxContainer
var _back_button: Button
var _next_button: Button
var _close_button: Button

# narration page
var _narration_lang := "en"
var _narration_status: Label
var _narration_install: Button
var _narration_check: CheckBox
var _teller_row: HBoxContainer
var _teller_picker: OptionButton
var _voice_ids: Array[String] = []

# voice commands page
var _voice_listener: VoiceListener
var _voice_status: Label
var _voice_install: Button
var _voice_check: CheckBox
var _voice_device_row: HBoxContainer
var _voice_device_picker: OptionButton
var _voice_ptt_check: CheckBox


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # modal scrim
	theme = AppTheme.build()
	PlayerSettings.ui_language_changed.connect(func(): call_deferred("_rebuild"))
	_voice_listener = VoiceListener.new()  # never started: it is only asked what is installed
	add_child(_voice_listener)
	_build()
	visible = false


## Opens the wizard at its first page. Counts as "shown once" from this moment, even if it is closed early.
func open() -> void:
	PlayerSettings.setup_assistant_shown = true
	PlayerSettings.save_settings()
	_page = Page.LANGUAGE
	_busy = false
	var reading := NarratorVoices.reading_language()
	_narration_lang = reading if NarratorVoices.LANGUAGES.has(reading) else "en"
	_show_page()
	visible = true


func _rebuild() -> void:
	for child in get_children():
		if child != _voice_listener:
			remove_child(child)
			child.free()
	_build()
	_show_page()


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var background := PanelContainer.new()
	center.add_child(background)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	background.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	_title_label = Label.new()
	_title_label.theme_type_variation = &"TitleLabel"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)
	_step_label = Label.new()
	_step_label.modulate = Color(1, 1, 1, 0.65)
	header.add_child(_step_label)

	var body := Control.new()
	body.custom_minimum_size = BODY_SIZE
	body.clip_contents = true
	vbox.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_page_box = VBoxContainer.new()
	_page_box.add_theme_constant_override("separation", 8)
	_page_box.custom_minimum_size.x = BODY_SIZE.x - 24.0
	scroll.add_child(_page_box)

	vbox.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	vbox.add_child(buttons)
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(_close)
	buttons.add_child(_close_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.pressed.connect(func(): _go(-1))
	buttons.add_child(_back_button)
	_next_button = Button.new()
	_next_button.pressed.connect(func(): _go(1))
	buttons.add_child(_next_button)


func _close() -> void:
	if _busy:
		return
	visible = false
	closed.emit()


func _go(step: int) -> void:
	if _busy:
		return
	var target := _page + step
	if target > Page.DONE:
		_close()
		return
	_page = clampi(target, Page.LANGUAGE, Page.DONE)
	_show_page()


func _set_busy(busy: bool) -> void:
	_busy = busy
	_back_button.disabled = busy or _page == Page.LANGUAGE
	_next_button.disabled = busy
	_close_button.disabled = busy


# ---------------------------------------------------------------- pages

func _show_page() -> void:
	for child in _page_box.get_children():
		_page_box.remove_child(child)
		child.free()
	_title_label.text = [tr("Language"), tr("Game assets"), tr("Narration"), tr("Voice commands"), tr("AI writing help"), tr("All set")][_page]
	_step_label.text = tr("Step %d of %d") % [_page + 1, Page.DONE + 1]
	_next_button.text = tr("Finish") if _page == Page.DONE else (tr("Next") if _page == Page.LANGUAGE else tr("Next (or skip)"))
	_close_button.visible = _page != Page.DONE
	match _page:
		Page.LANGUAGE:
			_build_language_page()
		Page.ASSETS:
			_build_assets_page()
		Page.NARRATION:
			_build_narration_page()
		Page.VOICE:
			_build_voice_page()
		Page.AI:
			_build_ai_page()
		Page.DONE:
			_build_done_page()
	_set_busy(false)


func _text(text: String, dim := false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = BODY_SIZE.x - 40.0  # a wrapping label with no width wraps per letter
	if dim:
		label.add_theme_font_size_override("font_size", 13)
		label.modulate = Color(1, 1, 1, 0.75)
	return label


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HeadingLabel"
	return label


func _build_language_page() -> void:
	_page_box.add_child(_text(tr("Welcome! This assistant helps you set up the app: the language, the game's art, narration, voice commands and the optional AI writing help. Every step can be skipped, and you can open it again with \"Setup Assistant\" at the bottom right of the main menu.")))
	_page_box.add_child(HSeparator.new())
	_page_box.add_child(_heading(tr("Languages you want to read")))
	_page_box.add_child(_text(tr("Campaigns and missions are shown in the first language of this list that they have. The app itself (menus and dialogs) is shown in the first language that it is translated into - %s so far.") % ", ".join(PlayerSettings.UI_LANGUAGES.map(func(code: String) -> String: return CampaignInfo.native_name(code))), true))
	var editor := LanguageListEditor.new()
	_page_box.add_child(editor)
	editor.setup(PlayerSettings.preferred_languages, func(list: Array[String]): PlayerSettings.set_preferred_languages(list))


func _build_assets_page() -> void:
	_page_box.add_child(_text(tr("Optional: if you own \"Descent: Legends of the Dark\", the app can use the game's real pictures, figures and data from your own install. Without it the app shows placeholders. Skip this if you don't own the game.")))
	var panel := AssetImportPanel.new()
	panel.busy_changed.connect(func(busy: bool): _set_busy(busy))
	_page_box.add_child(panel)
	panel.refresh()


func _build_narration_page() -> void:
	_page_box.add_child(_text(tr("The app can read the story aloud with a voice installed on your computer. Nothing is sent anywhere. The voices are a download.")))
	var lang_row := HBoxContainer.new()
	_page_box.add_child(lang_row)
	var lang_label := Label.new()
	lang_label.text = "Voices for:"
	lang_row.add_child(lang_label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for code in NarratorVoices.LANGUAGES:
		picker.add_item(CampaignInfo.native_name(code))
		picker.set_item_metadata(picker.item_count - 1, code)
		if code == _narration_lang:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int):
		_narration_lang = str(picker.get_item_metadata(index))
		_refresh_narration())
	lang_row.add_child(picker)
	_narration_install = Button.new()
	_narration_install.pressed.connect(_on_narration_install_pressed)
	_page_box.add_child(_narration_install)
	_narration_check = CheckBox.new()
	_narration_check.text = "Read the story aloud"
	_narration_check.toggled.connect(func(pressed: bool):
		PlayerSettings.narration_enabled = pressed
		PlayerSettings.save_settings()
		if not pressed:
			Narrator.stop())
	_page_box.add_child(_narration_check)
	_teller_row = HBoxContainer.new()
	_page_box.add_child(_teller_row)
	var teller_label := Label.new()
	teller_label.text = "Story teller:"
	_teller_row.add_child(teller_label)
	_teller_picker = OptionButton.new()
	_teller_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_teller_picker.item_selected.connect(func(index: int):
		PlayerSettings.set_storyteller_for(_narration_lang, _voice_ids[index])
		PlayerSettings.save_settings())
	_teller_row.add_child(_teller_picker)
	var play := Button.new()
	play.text = "▶"
	play.tooltip_text = "Hear the story teller"
	play.pressed.connect(func(): Narrator.speak_voice(PlayerSettings.storyteller_for(_narration_lang), NarratorVoices.teller_sample_line(_narration_lang)))
	_teller_row.add_child(play)
	_narration_status = _text("", true)
	_page_box.add_child(_narration_status)
	_page_box.add_child(_text(tr("More voices (plain English, accents) can be downloaded later in Options > Voice."), true))
	_refresh_narration()


func _refresh_narration() -> void:
	var available := Narrator.is_available()
	_narration_check.set_pressed_no_signal(PlayerSettings.narration_enabled)
	_narration_check.disabled = not available
	var voices := NarratorVoices.installed_for(_narration_lang)
	_teller_row.visible = available and not voices.is_empty()
	_teller_picker.clear()
	_voice_ids.clear()
	for voice in voices:
		_teller_picker.add_item(voice["label"])
		_voice_ids.append(voice["id"])
		if voice["id"] == PlayerSettings.storyteller_for(_narration_lang):
			_teller_picker.select(_teller_picker.item_count - 1)
	var needs_pack := NarratorVoices.has_pack(_narration_lang) and not NarratorVoices.pack_installed(_narration_lang)
	if not PiperInstaller.is_supported_platform():
		_narration_install.visible = false
		_narration_status.text = tr("Narration isn't available on %s.") % OS.get_name()
	elif not available or (voices.is_empty() and needs_pack):
		_narration_install.visible = true
		_narration_install.disabled = false
		if NarratorVoices.has_pack(_narration_lang):
			_narration_install.text = tr("Set up narration - %s voices (downloads about %d MB)") % [CampaignInfo.native_name(_narration_lang), NarratorVoices.PACKS[_narration_lang]["size_mb"] + (0 if available else 25)]
		else:
			_narration_install.text = tr("Set up narration (downloads %s)") % PiperInstaller.DOWNLOAD_SIZE_TEXT
		_narration_status.text = "Narration isn't set up yet - the story is shown as text only."
	else:
		_narration_install.visible = false
		_narration_status.text = "Narration is set up." if not voices.is_empty() else tr("No narration voices for %s are installed, so the story is shown as text only.") % CampaignInfo.native_name(_narration_lang)


func _on_narration_install_pressed() -> void:
	_narration_install.disabled = true
	_set_busy(true)
	var installer := PiperInstaller.new()
	add_child(installer)
	installer.progress.connect(func(text: String): _narration_status.text = text)
	var installed: bool
	if NarratorVoices.has_pack(_narration_lang):
		installed = await installer.install_pack(_narration_lang)
	else:
		installed = await installer.install()
	installer.queue_free()
	if installed:
		PlayerSettings.narration_enabled = true
		PlayerSettings.save_settings()
	_set_busy(false)
	if _page == Page.NARRATION:
		_refresh_narration()


func _build_voice_page() -> void:
	_page_box.add_child(_text(tr("Voice commands let you play by speaking (\"hey DM, hero two attack the green bandit\") and answer dialogs out loud. It runs on your computer with a speech model that is a download; you need a microphone. Typed commands always work.")))
	_voice_install = Button.new()
	_voice_install.pressed.connect(_on_voice_install_pressed)
	_page_box.add_child(_voice_install)
	_voice_check = CheckBox.new()
	_voice_check.text = "Enable voice"
	_voice_check.toggled.connect(func(pressed: bool):
		PlayerSettings.voice_enabled = pressed
		PlayerSettings.save_settings())
	_page_box.add_child(_voice_check)
	_voice_device_row = HBoxContainer.new()
	_page_box.add_child(_voice_device_row)
	var device_label := Label.new()
	device_label.text = tr("Microphone:")
	_voice_device_row.add_child(device_label)
	_voice_device_picker = OptionButton.new()
	_voice_device_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voice_device_picker.item_selected.connect(func(index: int):
		PlayerSettings.input_device = _voice_device_picker.get_item_text(index)
		PlayerSettings.save_settings())
	_voice_device_row.add_child(_voice_device_picker)
	_voice_ptt_check = CheckBox.new()
	_voice_ptt_check.text = tr("Push to talk (hold %s)") % OS.get_keycode_string(VoiceListener.PTT_KEY)
	_voice_ptt_check.tooltip_text = "Off = hands-free: say \"hey DM\" before a command."
	_voice_ptt_check.toggled.connect(func(pressed: bool):
		PlayerSettings.push_to_talk = pressed
		PlayerSettings.save_settings())
	_page_box.add_child(_voice_ptt_check)
	_voice_status = _text("", true)
	_page_box.add_child(_voice_status)
	_refresh_voice()


func _refresh_voice() -> void:
	var available := _voice_listener.is_available()
	_voice_check.set_pressed_no_signal(available and PlayerSettings.voice_enabled)
	_voice_check.disabled = not available
	_voice_ptt_check.set_pressed_no_signal(PlayerSettings.push_to_talk)
	_voice_device_picker.clear()
	var devices := AudioServer.get_input_device_list()
	for device in devices:
		_voice_device_picker.add_item(device)
	var current := devices.find(AudioServer.input_device)
	if current != -1:
		_voice_device_picker.select(current)
	_voice_device_row.visible = available
	_voice_ptt_check.visible = available
	if available:
		_voice_install.visible = false
		_voice_status.text = "Voice control is set up."
	elif not VoiceInstaller.is_supported_platform():
		_voice_install.visible = false
		_voice_status.text = tr("Voice setup isn't available on %s - typed commands still work.") % OS.get_name()
	else:
		_voice_install.visible = true
		_voice_install.disabled = false
		_voice_install.text = tr("Set up voice control (downloads %s)") % VoiceInstaller.DOWNLOAD_SIZE_TEXT
		_voice_status.text = "Voice isn't set up yet - typed commands still work."


func _on_voice_install_pressed() -> void:
	_voice_install.disabled = true
	_set_busy(true)
	var installer := VoiceInstaller.new()
	add_child(installer)
	installer.progress.connect(func(text: String): _voice_status.text = text)
	var installed: bool = await installer.install()
	installer.queue_free()
	if installed:
		PlayerSettings.voice_enabled = true
		PlayerSettings.save_settings()
	_set_busy(false)
	if _page == Page.VOICE:
		_refresh_voice()


func _build_ai_page() -> void:
	_page_box.add_child(_text(tr("Only for people who make campaigns and missions: an AI helper in the story text boxes of the editors (fix spelling, improve, continue the story). It needs either your own Anthropic API key or the Claude Code program on this PC. Skip this if you only play.")))
	_page_box.add_child(AiSettingsPanel.new())


func _build_done_page() -> void:
	_page_box.add_child(_text(tr("That's it! You can change all of this later in Options (the cog at the bottom left) and run this assistant again from \"Setup Assistant\" at the bottom right of the main menu.")))
