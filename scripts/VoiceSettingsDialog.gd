class_name VoiceSettingsDialog
extends Control

## Configuration dialog for voice control, opened from PlayerHud's Gear menu
## ("Options" - new 2026-09-23, real now, not a mock). Owns everything
## about SETTING UP voice: an Enable checkbox, the input-device picker,
## push-to-talk/hands-free mode, and the in-game download button
## (VoiceInstaller) - all previously lived directly on VoiceListener's own
## status line. VoiceListener itself is now just the mic capture/
## recognition engine and its small status line (moved to sit centered
## under the hero portraits, see MissionPlayer.gd/PlayerInteractionController.gd)
## - see that script's own class doc for the split and why.
##
## Built entirely in code (same pattern as EmbarkDialog/PlayerDialog/...),
## added as a plain child by MissionPlayer._ready() and opened via
## PlayerHud's Gear menu. Modal while open - same full-screen dim-scrim
## mechanism as PlayerDialog/EmbarkDialog (see PlayerDialog.gd's own class
## doc for the mechanism itself) - deliberately NOT `await`-based like those
## two, since nothing needs to block on it closing; it's just settings.

## Assigned by MissionPlayer right after construction.
var voice_listener: VoiceListener
## false in the main menu: there is no running Player to drive, so the settings are only saved (and take effect
## when a mission starts); the listener is then only asked what is installed.
var live := true
## Also assigned by MissionPlayer - this dialog now owns every write to
## dialog.voice_hints_enabled (see "Show voice hints" below), instead of
## MissionPlayer wiring voice_listener.voice_ready straight to it.
var dialog: PlayerDialog

var _enabled_check: CheckBox
var _hints_check: CheckBox
var _device_picker: OptionButton
var _mode_check: CheckBox
var _setup_button: Button
var _setup_status_label: Label
var _narration_check: CheckBox
var _narration_setup_button: Button
var _narration_status_label: Label
var _storyteller_picker: OptionButton
var _voice_ids: Array[String] = []
var _extras_button: Button
var _standard_button: Button
var _assets_panel: AssetImportPanel
var _close_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # the modal scrim - blocks everything behind it

	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.45)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var panel := CenterContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var background := PanelContainer.new()
	background.custom_minimum_size = Vector2(380, 0)
	panel.add_child(background)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	background.add_child(vbox)

	var title := Label.new()
	title.text = "Options"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bold(title)
	vbox.add_child(title)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(440, 400)
	vbox.add_child(tabs)
	var general := _tab(tabs, "General")
	var voice := _tab(tabs, "Voice")
	var ai := _tab(tabs, "AI")
	var assets := _tab(tabs, "Game assets")
	_assets_panel = AssetImportPanel.new()
	_assets_panel.busy_changed.connect(func(busy: bool): _close_button.disabled = busy)
	assets.add_child(_assets_panel)

	var gameplay_title := Label.new()
	gameplay_title.text = "Gameplay"
	_bold(gameplay_title)
	general.add_child(gameplay_title)

	var camera_check := CheckBox.new()
	camera_check.text = "Move camera to player and monster spawns"
	camera_check.button_pressed = PlayerSettings.auto_camera_to_spawns
	camera_check.toggled.connect(func(pressed: bool):
		PlayerSettings.auto_camera_to_spawns = pressed
		PlayerSettings.save_settings())
	general.add_child(camera_check)

	var sight_label := Label.new()
	sight_label.text = "Line of sight rule"
	general.add_child(sight_label)
	var sight_option := OptionButton.new()
	sight_option.add_item("Centre to corner (recommended)", SightLine.Mode.CENTER_TO_CORNER)
	sight_option.add_item("Corner to corner (loose, Descent 2)", SightLine.Mode.CORNER_TO_CORNER)
	sight_option.add_item("Centre to centre (strict)", SightLine.Mode.CENTER_TO_CENTER)
	sight_option.select(sight_option.get_item_index(PlayerSettings.sight_rule))
	sight_option.tooltip_text = "How the line of sight tool decides whether two squares see each other. Centre to corner: a line from the middle of the viewer's square to any corner of the target."
	sight_option.item_selected.connect(func(index: int):
		PlayerSettings.sight_rule = sight_option.get_item_id(index)
		PlayerSettings.save_settings())
	general.add_child(sight_option)

	if AppUpdater.current_version() != "":
		var update_check := CheckBox.new()
		update_check.text = "Check for a newer version of the app at the main menu"
		update_check.tooltip_text = "Only asks GitHub which version is the latest. Nothing is downloaded or installed without your click."
		update_check.button_pressed = PlayerSettings.check_updates
		update_check.toggled.connect(func(pressed: bool):
			PlayerSettings.check_updates = pressed
			PlayerSettings.save_settings())
		general.add_child(update_check)

	_build_ai_section(ai)

	var voice_title := Label.new()
	voice_title.text = "Voice"
	_bold(voice_title)
	voice.add_child(voice_title)

	_enabled_check = CheckBox.new()
	_enabled_check.text = "Enable voice"
	_enabled_check.toggled.connect(_on_enabled_toggled)
	voice.add_child(_enabled_check)

	_hints_check = CheckBox.new()
	_hints_check.text = "Show voice hints"
	_hints_check.button_pressed = PlayerSettings.show_voice_hints  # default on - "once people understand how it works they can remove the clutter"
	_hints_check.toggled.connect(_on_hints_toggled)
	voice.add_child(_hints_check)

	_device_picker = OptionButton.new()
	_device_picker.item_selected.connect(_on_device_selected)
	voice.add_child(_device_picker)

	_mode_check = CheckBox.new()
	_mode_check.toggled.connect(_on_mode_toggled)
	voice.add_child(_mode_check)

	_setup_button = Button.new()
	_setup_button.pressed.connect(_on_setup_pressed)
	voice.add_child(_setup_button)

	_setup_status_label = Label.new()
	_setup_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_setup_status_label.add_theme_font_size_override("font_size", 13)
	_setup_status_label.modulate = Color(1, 1, 1, 0.75)
	voice.add_child(_setup_status_label)

	voice.add_child(HSeparator.new())

	var narration_title := Label.new()
	narration_title.text = "Narration"
	_bold(narration_title)
	voice.add_child(narration_title)

	_narration_check = CheckBox.new()
	_narration_check.text = "Read the story aloud"
	_narration_check.toggled.connect(_on_narration_toggled)
	voice.add_child(_narration_check)

	_narration_setup_button = Button.new()
	_narration_setup_button.pressed.connect(_on_narration_setup_pressed)
	voice.add_child(_narration_setup_button)

	var teller_row := HBoxContainer.new()
	voice.add_child(teller_row)
	var teller_label := Label.new()
	teller_label.text = "Story teller:"
	teller_row.add_child(teller_label)
	_storyteller_picker = OptionButton.new()
	_storyteller_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storyteller_picker.item_selected.connect(_on_storyteller_selected)
	teller_row.add_child(_storyteller_picker)
	var teller_play := Button.new()
	teller_play.text = "▶"
	teller_play.tooltip_text = "Hear the story teller"
	teller_play.pressed.connect(func(): Narrator.speak_voice(PlayerSettings.storyteller_voice, "The old door creaks open, and a cold wind carries the smell of smoke."))
	teller_row.add_child(teller_play)

	_standard_button = Button.new()
	_standard_button.pressed.connect(_on_standard_pressed)
	voice.add_child(_standard_button)

	_extras_button = Button.new()
	_extras_button.pressed.connect(_on_extras_pressed)
	voice.add_child(_extras_button)

	_narration_status_label = Label.new()
	_narration_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_narration_status_label.add_theme_font_size_override("font_size", 13)
	_narration_status_label.modulate = Color(1, 1, 1, 0.75)
	voice.add_child(_narration_status_label)

	vbox.add_child(HSeparator.new())

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func(): visible = false)
	vbox.add_child(_close_button)

	visible = false


## One page of the tab container: a scroll area (so a long page never makes the dialog taller than the screen) with a column inside.
func _tab(tabs: TabContainer, tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	return column


func open() -> void:
	_assets_panel.refresh()
	_refresh()
	visible = true


## Read fresh every time the dialog opens - device list/availability can
## change between opens (a device plugged in, a download finished).
func _refresh() -> void:
	_refresh_narration()
	var available := voice_listener.is_available()
	# *_no_signal: refreshing the widgets must not run the handlers below,
	# which persist - an unavailable engine would otherwise overwrite the
	# saved voice_enabled with false.
	_enabled_check.set_pressed_no_signal(available and (voice_listener.is_enabled() if live else PlayerSettings.voice_enabled))
	_enabled_check.disabled = not available

	_device_picker.clear()
	var devices := AudioServer.get_input_device_list()
	for device in devices:
		_device_picker.add_item(device)
	var current := devices.find(AudioServer.input_device)
	if current != -1:
		_device_picker.select(current)

	_mode_check.text = "Push to talk (hold %s)" % OS.get_keycode_string(VoiceListener.PTT_KEY)
	_mode_check.set_pressed_no_signal(voice_listener.push_to_talk if live else PlayerSettings.push_to_talk)

	if available:
		_setup_button.visible = false
		_setup_status_label.text = "Voice control is set up."
	elif not VoiceInstaller.is_supported_platform():
		_setup_button.visible = false
		_setup_status_label.text = "Voice setup isn't available on %s - typed commands still work." % OS.get_name()
	else:
		_setup_button.visible = true
		_setup_button.disabled = false
		_setup_button.text = "Set up voice control (downloads %s)" % VoiceInstaller.DOWNLOAD_SIZE_TEXT
		_setup_status_label.text = "Voice isn't set up yet - typed commands still work."


func _refresh_narration() -> void:
	var available := Narrator.is_available()
	_narration_check.set_pressed_no_signal(PlayerSettings.narration_enabled)
	_narration_check.disabled = not available
	if available:
		_narration_setup_button.visible = false
		_narration_status_label.text = "Narration is set up."
	elif not PiperInstaller.is_supported_platform():
		_narration_setup_button.visible = false
		_narration_status_label.text = "Narration isn't available on %s." % OS.get_name()
	else:
		_narration_setup_button.visible = true
		_narration_setup_button.disabled = false
		_narration_setup_button.text = "Set up narration (downloads %s)" % PiperInstaller.DOWNLOAD_SIZE_TEXT
		_narration_status_label.text = "Narration isn't set up yet - the story is shown as text only."
	_refresh_voices(available)


## The story-teller picker lists the installed voices; the "extra voices" download is offered once narration works.
func _refresh_voices(available: bool) -> void:
	_storyteller_picker.get_parent().visible = available
	_standard_button.visible = available and not NarratorVoices.standard_installed()
	_standard_button.disabled = false
	_standard_button.text = "Download more voices - plain English (%s)" % NarratorVoices.STANDARD_SIZE_TEXT
	_extras_button.visible = available and not NarratorVoices.extras_installed()
	_extras_button.disabled = false
	_extras_button.text = "Download extra voices - accents (%s)" % NarratorVoices.EXTRAS_SIZE_TEXT
	_storyteller_picker.clear()
	_voice_ids.clear()
	for voice in NarratorVoices.installed():
		_storyteller_picker.add_item(voice["label"])
		_voice_ids.append(voice["id"])
		if voice["id"] == PlayerSettings.storyteller_voice:
			_storyteller_picker.select(_storyteller_picker.item_count - 1)


func _on_storyteller_selected(index: int) -> void:
	PlayerSettings.storyteller_voice = _voice_ids[index]
	PlayerSettings.save_settings()


func _on_standard_pressed() -> void:
	_standard_button.disabled = true
	var installer := PiperInstaller.new()
	add_child(installer)
	installer.progress.connect(func(text: String): _narration_status_label.text = text)
	await installer.install_standard()
	installer.queue_free()
	_refresh_narration()


func _on_extras_pressed() -> void:
	_extras_button.disabled = true
	var installer := PiperInstaller.new()
	add_child(installer)
	installer.progress.connect(func(text: String): _narration_status_label.text = text)
	await installer.install_extras()
	installer.queue_free()
	_refresh_narration()


func _on_narration_toggled(pressed: bool) -> void:
	PlayerSettings.narration_enabled = pressed
	PlayerSettings.save_settings()
	if not pressed:
		Narrator.stop()


func _on_narration_setup_pressed() -> void:
	_narration_setup_button.disabled = true
	var installer := PiperInstaller.new()
	add_child(installer)
	installer.progress.connect(func(text: String): _narration_status_label.text = text)
	var installed: bool = await installer.install()
	installer.queue_free()
	if installed:
		PlayerSettings.narration_enabled = true  # a fresh install means the player wants it on
		PlayerSettings.save_settings()
	_refresh_narration()


func _on_enabled_toggled(pressed: bool) -> void:
	PlayerSettings.voice_enabled = pressed
	PlayerSettings.save_settings()
	if live:
		voice_listener.set_enabled(pressed)
	# set_enabled() emits voice_ready, which _update_dialog_hints() (below,
	# connected in _ready()) already reacts to - no separate call needed here.


## "Show voice hints" - independent of "Enable voice": lets someone who
## already knows the commands hide PlayerDialog's own "Voice - say X or
## Y" caption line without turning voice control itself off.
func _on_hints_toggled(pressed: bool) -> void:
	PlayerSettings.show_voice_hints = pressed
	PlayerSettings.save_settings()
	_update_dialog_hints()


## The single place that writes dialog.voice_hints_enabled - ANDs together
## whether voice is actually listening right now (is_enabled(), which can
## change independently via voice_ready - a fresh install, the Enable
## checkbox) and whether the table wants to see the hint at all
## (_hints_check). Connected to voice_listener.voice_ready in _ready().
func _update_dialog_hints() -> void:
	if dialog != null and live:
		dialog.voice_hints_enabled = voice_listener.is_enabled() and _hints_check.button_pressed


func _on_mode_toggled(pressed: bool) -> void:
	PlayerSettings.push_to_talk = pressed
	PlayerSettings.save_settings()
	if live:
		voice_listener.set_push_to_talk(pressed)


func _on_device_selected(index: int) -> void:
	var device := _device_picker.get_item_text(index)
	PlayerSettings.input_device = device
	PlayerSettings.save_settings()
	if live:
		voice_listener.set_input_device(device)


func _on_setup_pressed() -> void:
	_setup_button.disabled = true
	var installer := VoiceInstaller.new()
	add_child(installer)
	installer.progress.connect(func(text: String): _setup_status_label.text = text)
	var installed: bool = await installer.install()
	installer.queue_free()
	if installed:
		PlayerSettings.voice_enabled = true  # a fresh install means the player wants it on
		PlayerSettings.save_settings()
		if live:
			voice_listener.start()  # re-checks availability and enables
	else:
		_setup_button.disabled = false
	_refresh()


## Same synthetic-bold trick EmbarkDialog's own page titles use (no bundled
## bold font file - see that script's own _bold_title()).
func _bold(label: Label) -> void:
	var bold_font := FontVariation.new()
	bold_font.base_font = label.get_theme_font("font")
	bold_font.variation_embolden = 1.0
	label.add_theme_font_override("font", bold_font)


## Optional AI writing help for the editors (AiAssist): either the author's own Anthropic API key, or the Claude Code program on
## this PC (signed in with the author's own Claude account). Off by default.
func _build_ai_section(vbox: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "AI writing help (optional)"
	_bold(title)
	vbox.add_child(title)
	var note := Label.new()
	note.text = "Adds an AI menu to the story text boxes in the campaign editor. Text is only sent when you choose an AI action; nothing is sent otherwise."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 380
	vbox.add_child(note)
	var enable := CheckBox.new()
	enable.text = "Enable AI writing help"
	enable.button_pressed = PlayerSettings.ai_enabled
	enable.toggled.connect(func(pressed: bool):
		PlayerSettings.ai_enabled = pressed
		PlayerSettings.save_settings())
	vbox.add_child(enable)
	var provider_option := OptionButton.new()
	provider_option.add_item("Use my Anthropic API key (pay per use)")
	provider_option.add_item("Use Claude Code on this PC (my Claude account)")
	provider_option.select(1 if PlayerSettings.ai_provider == "claude_code" else 0)
	vbox.add_child(provider_option)

	# --- API key provider
	var api_box := VBoxContainer.new()
	vbox.add_child(api_box)
	var key_edit := LineEdit.new()
	key_edit.secret = true
	key_edit.placeholder_text = "API key (sk-ant-...)"
	key_edit.text = PlayerSettings.ai_api_key
	var save_key := func():
		PlayerSettings.ai_api_key = key_edit.text.strip_edges()
		PlayerSettings.save_settings()
	key_edit.text_submitted.connect(func(_text: String): save_key.call())
	key_edit.focus_exited.connect(func(): save_key.call())
	api_box.add_child(key_edit)

	# --- Claude Code provider
	var cli_box := VBoxContainer.new()
	vbox.add_child(cli_box)
	var cli_note := Label.new()
	cli_note.text = "Uses the Claude Code program on this PC with your own Claude sign-in (nothing is paid per request here; it counts towards your Claude plan's usage). It can only return text.\n\nSetup, once: install it with  npm install -g @anthropic-ai/claude-code  then run  claude auth login  in a terminal."
	cli_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cli_note.custom_minimum_size.x = 380
	cli_box.add_child(cli_note)
	var path_edit := LineEdit.new()
	path_edit.placeholder_text = "Path to claude (only if it is not on the PATH)"
	path_edit.text = PlayerSettings.ai_claude_path
	var save_path := func():
		PlayerSettings.ai_claude_path = path_edit.text.strip_edges()
		PlayerSettings.save_settings()
	path_edit.text_submitted.connect(func(_text: String): save_path.call())
	path_edit.focus_exited.connect(func(): save_path.call())
	cli_box.add_child(path_edit)

	var model_option := OptionButton.new()
	var selected_model := 0
	for i in AiClient.MODELS.size():
		model_option.add_item(AiClient.MODELS[i][1])
		model_option.set_item_metadata(i, AiClient.MODELS[i][0])
		if AiClient.MODELS[i][0] == PlayerSettings.ai_model:
			selected_model = i
	model_option.select(selected_model)
	model_option.item_selected.connect(func(index: int):
		PlayerSettings.ai_model = str(model_option.get_item_metadata(index))
		PlayerSettings.save_settings())
	vbox.add_child(model_option)

	var test_row := HBoxContainer.new()
	vbox.add_child(test_row)
	var test_button := Button.new()
	test_row.add_child(test_button)
	var test_label := Label.new()
	test_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	test_label.custom_minimum_size.x = 260
	test_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test_row.add_child(test_label)
	var client := AiClient.new()
	add_child(client)
	var refresh_provider := func():
		var cli: bool = PlayerSettings.ai_provider == "claude_code"
		api_box.visible = not cli
		cli_box.visible = cli
		test_button.text = "Check Claude Code" if cli else "Test the key"
		test_label.text = ""
	refresh_provider.call()
	provider_option.item_selected.connect(func(index: int):
		PlayerSettings.ai_provider = "claude_code" if index == 1 else "api"
		PlayerSettings.save_settings()
		refresh_provider.call())
	test_button.pressed.connect(func():
		save_key.call()
		save_path.call()
		test_button.disabled = true
		if PlayerSettings.ai_provider == "claude_code":
			var status := AiClient.claude_status()
			test_label.text = str(status["text"])
			if status["logged_in"]:
				test_label.text = "Claude Code is signed in. Asking it something..."
				var answer := await client.ask("", "Reply with the single word OK.", 16)
				test_label.text = "Claude Code works." if answer["ok"] else str(answer["error"])
		else:
			test_label.text = "Asking..."
			var answer := await client.ask("", "Reply with the single word OK.", 16)
			test_label.text = "The key works." if answer["ok"] else str(answer["error"])
		test_button.disabled = false)
