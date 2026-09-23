class_name VoiceListener
extends Label

## Voice control: turns speech into command text for PlayerCommandRunner (via
## command_heard) - exactly like the typed CommandInput. This script is now
## JUST the mic capture/recognition engine + a small status line (a live
## mic-level meter + what it last heard) - centered under the hero portraits,
## above CommandInput. Everything about CONFIGURING it (an Enable checkbox,
## the input-device picker, push-to-talk/hands-free mode, the in-game
## download button) moved out to VoiceSettingsDialog.gd (new 2026-09-23,
## opened from PlayerHud's Gear menu "Options") - see that script's own
## class doc for the split and why: this label should stay put and minimal
## even while its settings live in an occasional dialog elsewhere.
##
## Two modes (checkbox in VoiceSettingsDialog), both on the addon's native SpeechToText node:
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
## res://addons/godot_whisper/models/, or click "Set up voice control" in
## VoiceSettingsDialog (which drives VoiceInstaller). Until either has
## happened is_available() stays false, this label stays hidden, and typed
## commands keep working. Only the addon's native class is used, driven via
## set()/call(), so this script compiles and runs without the addon.

## The recognized text of a command.
signal command_heard(text: String)

## Voice control is usable (true) or not (false) - emitted whenever
## is_enabled() actually changes (start(), VoiceSettingsDialog's Enable
## checkbox, or a successful in-dialog install), so the dialog hints can
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

var _available: bool = false  ## engine + a model confirmed present - see is_available()
var _enabled: bool = false  ## actively listening - see is_enabled()/set_enabled()

var _language_model: Resource
var _vad_model: Resource
var _stt: Node  ## the speech engine (native SpeechToText)
var _mic_player: AudioStreamPlayer
var _effect_capture: AudioEffectCapture

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
	# Centered under the hero portraits (see PlayerInteractionController's
	# own BOTTOM_MARGIN), above CommandInput.
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -260.0
	offset_right = 260.0
	offset_top = -96.0
	offset_bottom = -68.0
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_theme_constant_override("outline_size", 4)
	visible = false  # only shown once actually enabled - see set_enabled()
	push_to_talk = PlayerSettings.push_to_talk  # a saved preference now, not always the hardcoded default


## True once the engine + a language model have been confirmed present
## (regardless of whether voice is currently ENABLED - see is_enabled()) -
## VoiceSettingsDialog's Enable checkbox is read-only/forced off unless this
## is true. Checked fresh each call (audio input can't newly appear, but a
## model can, right after an in-dialog install) - cheap, no caching needed.
func is_available() -> bool:
	_available = ProjectSettings.get_setting("audio/driver/enable_input", false) \
		and (ClassDB.class_exists(NATIVE_CLASS) or VoiceInstaller.load_extension())
	if _available:
		_language_model = _load_model(false)
		_vad_model = _load_model(true)
		_available = _language_model != null
	return _available


## Actively capturing/listening right now.
func is_enabled() -> bool:
	return _enabled


## Checks availability and, if available AND PlayerSettings.voice_enabled
## (the saved "Enable voice" preference - defaults true, so voice still
## defaults to ON for anyone who's never touched the checkbox), starts
## listening. Called once by MissionPlayer after construction, and again by
## VoiceSettingsDialog right after a successful in-dialog install (that one
## deliberately ignores a saved `false` - installing IS turning it on).
## Emits voice_ready either way (see that signal's own doc).
func start() -> bool:
	set_enabled(is_available() and PlayerSettings.voice_enabled)
	return _enabled


## The master on/off switch - VoiceSettingsDialog's Enable checkbox drives
## this directly. A no-op turning on when not is_available() (that
## checkbox is read-only then, so this shouldn't normally be reached, but
## nothing here relies on that). Hides this label and stops the engine/mic
## capture entirely when turned off - "stop listening" really means stop,
## not just stop reacting.
func set_enabled(enabled: bool) -> void:
	if enabled and not _available:
		return
	if enabled == _enabled:
		return
	_enabled = enabled
	if enabled:
		if _mic_player == null:
			_setup_microphone()
		else:
			_mic_player.play()
		visible = true
		_start_engine()
	else:
		_finish_thread()
		if _stt != null:
			_stt.queue_free()
			_stt = null
		if _mic_player != null:
			_mic_player.stop()
		visible = false
		_status = ""
		_level_text = ""
		_refresh_text()  # _status/_level_text alone don't touch the Label's own .text - see _set_status()/_refresh_text()
	voice_ready.emit(_enabled)


## VoiceSettingsDialog's mode checkbox.
func set_push_to_talk(value: bool) -> void:
	push_to_talk = value
	if _enabled:
		_start_engine()


## VoiceSettingsDialog's input-device picker.
func set_input_device(device_name: String) -> void:
	AudioServer.input_device = device_name
	if _mic_player != null:
		_mic_player.stop()
		_mic_player.play()
	if _enabled:
		_set_status("Input device: %s" % device_name)


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
