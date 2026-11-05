class_name AiSettingsPanel
extends VBoxContainer

## The optional AI writing help settings (AiAssist): either the author's own Anthropic API key, or the Claude Code program on this PC
## (signed in with the author's own Claude account). Off by default. Shared by the Options dialog (AI tab) and the Setup Assistant.


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "AI writing help (optional)"
	title.theme_type_variation = &"HeadingLabel"
	add_child(title)
	var note := Label.new()
	note.text = "Adds an AI menu to the story text boxes in the campaign editor. Text is only sent when you choose an AI action; nothing is sent otherwise."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 380
	add_child(note)
	var enable := CheckBox.new()
	enable.text = "Enable AI writing help"
	enable.button_pressed = PlayerSettings.ai_enabled
	enable.toggled.connect(func(pressed: bool):
		PlayerSettings.ai_enabled = pressed
		PlayerSettings.save_settings())
	add_child(enable)
	var provider_option := OptionButton.new()
	provider_option.add_item("Use my Anthropic API key (pay per use)")
	provider_option.add_item("Use Claude Code on this PC (my Claude account)")
	provider_option.select(1 if PlayerSettings.ai_provider == "claude_code" else 0)
	add_child(provider_option)

	# --- API key provider
	var api_box := VBoxContainer.new()
	add_child(api_box)
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
	add_child(cli_box)
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
	add_child(model_option)

	var test_row := HBoxContainer.new()
	add_child(test_row)
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
