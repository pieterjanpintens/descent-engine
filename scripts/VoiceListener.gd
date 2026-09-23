class_name VoiceListener
extends Label

## Voice control: turns speech into command text for PlayerCommandRunner (via
## command_heard) - exactly like the typed CommandInput. Doubles as its own
## small status line, shown bottom-left above the command box, with an
## input-device picker, a live mic-level meter and a mode checkbox.
##
## Two modes (checkbox), both on the addon's native SpeechToText node:
##  - PUSH TO TALK (default): hold PTT_KEY, speak, release. Audio is collected
##    only while the key is held and transcribed ONCE on release, so there is no
##    wake word and no hallucinated text from silence.
##  - HANDS-FREE: our own simple listener - the microphone is watched for
##    loudness, an utterance is cut out (a little pre-roll, ends after
##    HANDS_FREE_SILENCE_SEC of quiet) and transcribed once, exactly like a
##    push-to-talk recording. A sentence containing the wake phrase ("hey DM
##    ...") is a command, a sentence that is ONLY the wake phrase opens a short
##    window in which the next sentence is one, everything else is table
##    chatter and is ignored. (Written instead of using the addon's streaming
##    CaptureStreamToText GDScript, which isn't part of the user-data install.)
## PlayerCommandRunner runs the command straight away (no confirmation).
##
## The speech engine is the third-party Godot Whisper addon (MIT,
## github.com/appsinacup/godot-whisper; whisper.cpp + Silero VAD). It is NOT
## part of this repo: install it and download a Whisper model (+ the Silero VAD
## model) via the editor's "Project -> Tools -> Whisper Models" into
## res://addons/godot_whisper/models/ (or use the in-game setup, see
## VoiceInstaller). Until then this node offers the setup and typed commands keep
## working. Only the addon's native class is used, driven via set()/call(), so
## this script compiles and runs without the addon.

## The recognized text of a command.
signal command_heard(text: String)

## Voice control is usable (true) or not (false) - emitted at the end of
## start(), and again after the in-game setup finishes, so the dialog hints can
## follow it (MissionPlayer connects this).
signal voice_ready(is_ready: bool)

const NATIVE_CLASS := "SpeechToText"  ## from the addon's GDExtension
const BUS_NAME := "Record"
## Where models are looked for, first match wins per file name: user data (the
## in-game setup, see VoiceInstaller) before a dev copy in the project.
const MODEL_DIRS: Array[String] = ["user://whisper/models/", "res://addons/godot_whisper/models/"]
## Language-model preference, best first (substring of the file name). Small
## and fast beats big and accurate here: commands are a few words, and without
## GPU support (the addon only ships OpenCL) the large model takes seconds.
const PREFERRED_MODELS: Array[String] = ["small.en", "base.en", "small", "base"]

## Push to talk: hold this key.
const PTT_KEY := KEY_V
## Shorter recordings are discarded; longer ones are cut off and sent.
const PTT_MIN_SEC := 0.4
const PTT_MAX_SEC := 20.0

## Hands-free: after a bare "hey DM", how long the next sentence is the command.
const COMMAND_WINDOW_SEC := 8.0
## Hands-free utterance cutting: quiet this long ends an utterance; audio kept
## from just before the first loud moment (so the first word isn't clipped).
const HANDS_FREE_SILENCE_SEC := 0.8
const HANDS_FREE_PRE_ROLL_SEC := 0.3
## Microphone peak (0..1) that counts as "someone made a sound".
const LOUD_PEAK := 0.02

## Optional Callable returning Array[String] of object names currently on the
## board; they are worked into Whisper's prompt so words like "pile of dirt"
## are recognised.
var vocabulary_provider: Callable
## Same for custom MONSTER names ("Mieke") - recognition can't guess how an
## unusual name is spelled unless the prompt shows it.
var monster_name_provider: Callable
## The hero weapons' names (Array[String]) and a context sentence for whatever
## dialog is open (String) - both go into the recogniser's prompt, the latter
## last so it weighs most ("I rolled three." while the successes are asked).
var weapon_name_provider: Callable
var context_prompt_provider: Callable
## Optional Callable -> bool: true while a PlayerDialog is open and waiting for
## an answer. While it's open, hands-free skips the "hey DM" wake check
## entirely (see _on_hands_free_sentence) - the modal already makes it obvious
## the table is expected to reply, so saying "yes"/"three"/a name straight
## away shouldn't need the wake phrase first, unlike an unprompted command.
var dialog_open_provider: Callable

var push_to_talk: bool = true
var wake_word_required: bool = true  ## hands-free only

var _language_model: Resource
var _vad_model: Resource
var _stt: Node  ## the speech engine (native SpeechToText)
var _mic_player: AudioStreamPlayer
var _effect_capture: AudioEffectCapture
var _device_picker: OptionButton
var _setup_button: Button
var _mode_check: CheckBox

var _command_window_until_msec: int = 0
var _status: String = ""
var _level_text: String = ""

var _talking: bool = false  ## push to talk: key held
var _hf_speaking: bool = false  ## hands-free: inside an utterance
var _hf_last_loud_msec: int = 0
var _hf_pre_roll: PackedVector2Array = PackedVector2Array()
var _ptt_frames: PackedVector2Array = PackedVector2Array()
var _ptt_peak: float = 0.0  ## loudest sample of the current recording
var _thread: Thread


func _ready() -> void:
	# Just above CommandInput (bottom-left).
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 12.0
	offset_right = 12.0 + 520.0
	offset_top = -76.0
	offset_bottom = -48.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_theme_constant_override("outline_size", 4)


## Sets up the mic + the speech engine. Safe when nothing is installed: it then
## offers the in-game setup (a download button, see VoiceInstaller) and returns
## false. Emits voice_ready with the outcome.
func start() -> bool:
	var ok := _start()
	voice_ready.emit(ok)
	return ok


func _start() -> bool:
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		_set_status("Voice off - enable Project Settings > Audio > Driver > Enable Input")
		return false
	# The native engine: registered at startup from res://addons if a dev copy
	# exists, otherwise loaded from user data if the in-game setup ran.
	if not ClassDB.class_exists(NATIVE_CLASS) and not VoiceInstaller.load_extension():
		_offer_setup("Voice control isn't set up yet")
		return false
	_language_model = _load_model(false)
	_vad_model = _load_model(true)
	if _language_model == null:
		_offer_setup("The speech model is missing")
		return false

	_setup_microphone()
	_build_controls()
	_start_engine()
	return true


## Shows a "Set up voice control" button (a click is the consent for the
## download) plus why it is needed. No-op on platforms the installer can't serve.
func _offer_setup(reason: String) -> void:
	if not VoiceInstaller.is_supported_platform():
		_set_status("Voice off - %s (setup isn't available on %s; typed commands still work)" % [reason, OS.get_name()])
		return
	_set_status("%s - typed commands still work" % reason)
	if _setup_button != null:
		return
	_setup_button = Button.new()
	_setup_button.text = "Set up voice control (downloads %s)" % VoiceInstaller.DOWNLOAD_SIZE_TEXT
	_setup_button.position = Vector2(0, -34)
	_setup_button.pressed.connect(_run_setup)
	add_child(_setup_button)


func _run_setup() -> void:
	_setup_button.disabled = true
	var installer := VoiceInstaller.new()
	add_child(installer)
	installer.progress.connect(_set_status)
	var installed: bool = await installer.install()
	installer.queue_free()
	if installed:
		_setup_button.queue_free()
		_setup_button = null
		start()
	else:
		_setup_button.text = "Retry voice setup"
		_setup_button.disabled = false


func _exit_tree() -> void:
	_finish_thread()


## (Re)builds the speech engine for the current mode.
func _start_engine() -> void:
	_finish_thread()
	if _stt != null:
		_stt.queue_free()
	_talking = false
	_hf_speaking = false
	_hf_pre_roll = PackedVector2Array()
	_command_window_until_msec = 0
	_stt = ClassDB.instantiate(NATIVE_CLASS)
	_stt.set("language_model", _language_model)
	if _vad_model != null:
		_stt.set("vad_model", _vad_model)
	add_child(_stt)
	_effect_capture.clear_buffer()
	if push_to_talk:
		_set_status("Hold %s to talk" % OS.get_keycode_string(PTT_KEY))
	else:
		_set_status("Listening - say \"hey DM, ...\"")


# ---------------------------------------------------------------- push to talk

func _unhandled_input(event: InputEvent) -> void:
	if _stt == null or not push_to_talk:
		return
	if event is InputEventKey and event.keycode == PTT_KEY and not event.echo:
		if event.pressed:
			_start_talking()
		else:
			_stop_talking()
		get_viewport().set_input_as_handled()


## Drains the capture buffer every frame: into the recording while the key is
## held (push to talk) or while an utterance is going on (hands-free), otherwise
## just to feed the level meter and keep the buffer from overflowing.
func _process(_delta: float) -> void:
	if _stt == null or _effect_capture == null:
		return
	var available := _effect_capture.get_frames_available()
	if available <= 0:
		return
	var frames := _effect_capture.get_buffer(available)
	var peak := 0.0
	for frame in frames:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	_on_input_level(peak, 0.0)
	var mix_rate: float = ProjectSettings.get_setting("audio/driver/mix_rate")
	if push_to_talk:
		if _talking:
			_ptt_peak = maxf(_ptt_peak, peak)
			_ptt_frames.append_array(frames)
			if _ptt_frames.size() > PTT_MAX_SEC * mix_rate:
				_stop_talking()
	else:
		_hands_free_step(frames, peak, mix_rate)


## Hands-free utterance cutting, see the class doc.
func _hands_free_step(frames: PackedVector2Array, peak: float, mix_rate: float) -> void:
	var now := Time.get_ticks_msec()
	if not _hf_speaking:
		_hf_pre_roll.append_array(frames)
		var keep := int(HANDS_FREE_PRE_ROLL_SEC * mix_rate)
		if _hf_pre_roll.size() > keep:
			_hf_pre_roll = _hf_pre_roll.slice(_hf_pre_roll.size() - keep)
		if peak > LOUD_PEAK and not (_thread != null and _thread.is_alive()):
			_hf_speaking = true
			_hf_last_loud_msec = now
			_ptt_frames = _hf_pre_roll.duplicate()
			_ptt_peak = peak
			_hf_pre_roll = PackedVector2Array()
		return
	_ptt_frames.append_array(frames)
	_ptt_peak = maxf(_ptt_peak, peak)
	if peak > LOUD_PEAK:
		_hf_last_loud_msec = now
	var quiet_sec := (now - _hf_last_loud_msec) / 1000.0
	if quiet_sec >= HANDS_FREE_SILENCE_SEC or _ptt_frames.size() > PTT_MAX_SEC * mix_rate:
		_hf_speaking = false
		_send_recording(false)


func _start_talking() -> void:
	if _talking:
		return
	if _thread != null and _thread.is_alive():
		_set_status("Still processing the last command...")
		return
	_effect_capture.clear_buffer()
	_ptt_frames = PackedVector2Array()
	_ptt_peak = 0.0
	_talking = true
	_set_status("Listening... release %s to send" % OS.get_keycode_string(PTT_KEY))


func _stop_talking() -> void:
	if not _talking:
		return
	_talking = false
	_send_recording(true)


## Sends the collected frames to Whisper (worker thread). `announce` = push to
## talk, where the player wants feedback on a too-short/silent press; hands-free
## silently drops noises.
func _send_recording(announce: bool) -> void:
	var mix_rate: float = ProjectSettings.get_setting("audio/driver/mix_rate")
	if _ptt_frames.size() < PTT_MIN_SEC * mix_rate:
		if announce:
			_set_status("Too short - hold %s while you speak" % OS.get_keycode_string(PTT_KEY))
		return
	if _ptt_peak < LOUD_PEAK:
		# Whisper echoes its prompt back when fed silence - don't even ask it.
		if announce:
			_set_status("Heard only silence - check the input device / mic level")
		return
	_set_status("Thinking...")
	_finish_thread()
	_thread = Thread.new()
	_thread.start(_transcribe_recording.bind(_ptt_frames.duplicate(), _vocabulary_prompt()))


## Runs on a worker thread (the large model takes a while) - resamples the
## recording to Whisper's 16 kHz and transcribes it once, then hands the text
## back to the main thread.
func _transcribe_recording(frames: PackedVector2Array, prompt: String) -> void:
	var interpolator := ClassDB.class_get_integer_constant(NATIVE_CLASS, "SRC_SINC_FASTEST")
	var samples: PackedFloat32Array = _stt.call("resample", frames, interpolator)
	var text := ""
	if not samples.is_empty():
		var tokens: Array = _stt.call("transcribe", samples, prompt, 0)
		if not tokens.is_empty():
			text = str(tokens[0])
	call_deferred("_on_recording_transcribed", text)


func _on_recording_transcribed(text: String) -> void:
	var heard := _strip_noise_markers(text)
	if push_to_talk:
		if heard == "":
			_set_status("Didn't catch anything - hold %s and try again" % OS.get_keycode_string(PTT_KEY))
			return
		_set_status("Heard: %s" % heard)
		command_heard.emit(heard)
		return
	_on_hands_free_sentence(heard)


func _finish_thread() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null


## Whisper writes "[BLANK_AUDIO]", "<|...|>", "♪ ... ♪" for silence/noise/music.
func _strip_noise_markers(message: String) -> String:
	for pair in [["[", "]"], ["<", ">"], ["♪", "♪"], ["(", ")"]]:
		var begin := message.find(pair[0])
		while begin != -1:
			var end := message.find(pair[1], begin + 1)
			if end == -1:
				break
			message = message.substr(0, begin) + message.substr(end + 1)
			begin = message.find(pair[0])
	return message.strip_edges()


# ---------------------------------------------------------------- shared setup

## Live microphone level next to the status ("mic [|||.......]"). If this stays empty while you
## talk, the selected input device (see the dropdown) or the OS mic permission
## is the problem, not the game.
func _on_input_level(peak: float, _rms: float) -> void:
	var bars := clampi(int(sqrt(peak) * 10.0), 0, 10)
	_level_text = "  mic [%s%s]" % ["|".repeat(bars), ".".repeat(10 - bars)]
	_refresh_text()


## The input-device dropdown (the "Default" device is often silent or the wrong
## microphone; picking one switches the microphone live) and the mode checkbox.
func _build_controls() -> void:
	var devices: PackedStringArray = AudioServer.get_input_device_list()
	print("Voice: input devices = ", devices, ", current = ", AudioServer.input_device)
	_device_picker = OptionButton.new()
	_device_picker.position = Vector2(0, -34)
	_device_picker.custom_minimum_size = Vector2(300, 0)
	for device in devices:
		_device_picker.add_item(device)
	var current := devices.find(AudioServer.input_device)
	if current != -1:
		_device_picker.select(current)
	_device_picker.item_selected.connect(_on_device_selected)
	add_child(_device_picker)

	_mode_check = CheckBox.new()
	_mode_check.text = "Push to talk (hold %s)" % OS.get_keycode_string(PTT_KEY)
	_mode_check.button_pressed = push_to_talk
	_mode_check.position = Vector2(308, -34)
	_mode_check.toggled.connect(_on_mode_toggled)
	add_child(_mode_check)


func _on_mode_toggled(pressed: bool) -> void:
	push_to_talk = pressed
	_start_engine()


func _on_device_selected(index: int) -> void:
	var device := _device_picker.get_item_text(index)
	AudioServer.input_device = device
	if _mic_player != null:
		_mic_player.stop()
		_mic_player.play()
	_set_status("Input device: %s" % device)


## A muted "Record" bus with an AudioEffectCapture (what the speech engines
## read) fed by the microphone. Muted so the mic isn't played back (verified: a
## muted bus still feeds the capture effect at full level). Reuses a bus named
## "Record" if the project already has one.
func _setup_microphone() -> void:
	var bus := AudioServer.get_bus_index(BUS_NAME)
	if bus == -1:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, BUS_NAME)
		AudioServer.add_bus_effect(bus, AudioEffectCapture.new(), 0)
		AudioServer.set_bus_mute(bus, true)
	_effect_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = BUS_NAME
	add_child(_mic_player)
	_mic_player.play()


## Models are looked for in MODEL_DIRS (imported as WhisperResource). The Silero
## VAD one has "silero" in its name; every other .bin is a language model, and of
## those the one matching the EARLIEST entry of PREFERRED_MODELS wins (then any
## other, alphabetically) - so a small fast model is used even while a big one
## is also present. Returns null if none found.
func _load_model(vad: bool) -> Resource:
	var paths: Dictionary = {}  # file name -> directory it was found in (first dir wins)
	for model_dir in MODEL_DIRS:
		var dir := DirAccess.open(model_dir)
		if dir == null:
			continue
		for file in dir.get_files():
			# Imported/exported builds list "x.bin.import"/"x.bin.remap" too.
			var name := file.trim_suffix(".import").trim_suffix(".remap")
			if name.ends_with(".bin") and name.containsn("silero") == vad and not paths.has(name):
				paths[name] = model_dir
	if paths.is_empty():
		return null
	var names: Array[String] = []
	names.assign(paths.keys())
	names.sort()
	var best := names[0]
	if not vad:
		var best_rank := PREFERRED_MODELS.size()
		for name in names:
			for rank in PREFERRED_MODELS.size():
				if rank < best_rank and name.containsn(PREFERRED_MODELS[rank]):
					best_rank = rank
					best = name
		print("Voice: language model = ", best, " (of ", names, ")")
	return load(paths[best] + best)


## Hint text for Whisper: the wake phrase and example commands, which helps
## it recognise words like "Bandit" and "Zealot". Plain sentences, not a
## "Colours: ..." list - Whisper echoes list-shaped prompts back on silence.
func _vocabulary_prompt() -> String:
	var prompt := "Hey DM, attack the green bandit with the sword. Hero two attacks the yellow zealot, I rolled three. Attack the purple wolf. End phase. Show monsters."
	if vocabulary_provider.is_valid():
		# Up to three object names, phrased as commands (see the note above).
		var openers: Array[String] = ["Use the %s.", "Interact with the %s.", "Trigger the %s."]
		var names: Array = vocabulary_provider.call()
		for i in mini(names.size(), openers.size()):
			prompt += " " + openers[i] % str(names[i]).to_lower()
	if monster_name_provider.is_valid():
		var monster_names: Array = monster_name_provider.call()
		for i in mini(monster_names.size(), 3):
			prompt += " Attack %s." % str(monster_names[i])
	if weapon_name_provider.is_valid():
		var weapon_names: Array = weapon_name_provider.call()
		for i in mini(weapon_names.size(), 3):
			prompt += " Attack with the %s." % str(weapon_names[i]).to_lower()
	if context_prompt_provider.is_valid():
		prompt += " " + str(context_prompt_provider.call())
	return prompt


# ---------------------------------------------------------------- hands-free

## One transcribed utterance in hands-free mode: only wake-phrase sentences (or
## the sentence right after a bare "hey DM", or ANY sentence while a dialog is
## open and dialog_open_provider says so) become commands.
func _on_hands_free_sentence(heard: String) -> void:
	if heard == "":
		_set_status("Listening - say \"hey DM, ...\"")
		return
	var dialog_open: bool = dialog_open_provider.is_valid() and dialog_open_provider.call()
	var now := Time.get_ticks_msec()
	if VoiceCommandParser.is_wake_only(heard) and not dialog_open:
		_command_window_until_msec = now + int(COMMAND_WINDOW_SEC * 1000.0)
		_set_status("Yes? (listening for a command)")
		return
	var in_window := now < _command_window_until_msec
	if wake_word_required and not dialog_open and not in_window and not VoiceCommandParser.has_wake_phrase(heard):
		_set_status("(ignored) %s" % heard)
		return
	_command_window_until_msec = 0
	_set_status("Heard: %s" % heard)
	command_heard.emit(heard)


func _set_status(status: String) -> void:
	_status = status
	_refresh_text()


func _refresh_text() -> void:
	text = _status + _level_text
