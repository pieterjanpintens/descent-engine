class_name DictationEngine
extends Node

## Speech to text for the editors: records from the microphone while asked to, then transcribes the whole recording once (Whisper, on a
## worker thread) and reports the text. ONE shared instance (`DictationEngine.instance()`, a child of the scene tree's root so it survives
## scene changes); SpeechDictation is the per-text-box button that drives it.
##
## It uses the same voice setup as the Player's voice control (VoiceInstaller / Options > Voice: the Whisper engine and a model), but not
## the VoiceListener node: dictation is a long, deliberate recording, not a stream of short commands, so the microphone only runs
## while recording (no background capture) and a recording may be a couple of minutes long.

## `requester` is whoever started the recording; `text` is "" with `error` set when nothing came out.
signal finished(requester: Object, text: String, error: String)
signal state_changed

enum State { IDLE, RECORDING, THINKING }

const MAX_RECORD_SEC := 180.0
const MIN_RECORD_SEC := 0.4
## Whisper makes up text ("thank you", an echo of the prompt) when it is fed silence, so a recording that never got this loud is dropped.
const LOUD_PEAK := 0.02

static var _instance: DictationEngine

var state: State = State.IDLE
var current_owner: Object

var _stt: Node
var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _frames: PackedVector2Array = PackedVector2Array()
var _peak := 0.0
var _thread: Thread
var _last_check_msec := -100000
var _last_check := false


static func instance() -> DictationEngine:
	if _instance == null or not is_instance_valid(_instance):
		_instance = DictationEngine.new()
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_instance)  # deferred: the root may be busy setting up the scene
	return _instance


## Whether voice is set up well enough to dictate: microphone input enabled, the speech engine loadable and a model present. Cheap (no model is
## loaded) and remembered for a few seconds, so text boxes can ask whenever they get focus.
func is_available() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_check_msec < 5000:
		return _last_check
	_last_check_msec = now
	_last_check = ProjectSettings.get_setting("audio/driver/enable_input", false) \
		and (ClassDB.class_exists(VoiceListener.NATIVE_CLASS) or VoiceInstaller.load_extension()) \
		and VoiceListener.model_path(false) != ""
	return _last_check


## Forget the remembered answer (after an install, for instance).
func recheck() -> void:
	_last_check_msec = -100000


## The current level of the microphone, 0..1, while recording (for a live indicator).
var level := 0.0


## Starts recording for `requester`. False (with a message in `reason`) when it can't: not set up, or busy.
func start(requester: Object) -> Dictionary:
	if state != State.IDLE:
		return {"ok": false, "reason": "Already busy with another recording."}
	if not is_available():
		return {"ok": false, "reason": "Voice is not set up (Options > Voice)."}
	if _stt == null and not _make_engine():
		return {"ok": false, "reason": "The speech engine could not be started."}
	if _mic_player == null:
		_setup_microphone()
	Narrator.stop()
	_frames = PackedVector2Array()
	_peak = 0.0
	level = 0.0
	_capture.clear_buffer()
	_mic_player.play()
	current_owner = requester
	_set_state(State.RECORDING)
	return {"ok": true, "reason": ""}


## Stops recording and starts transcribing; `prompt` is a hint text for Whisper (character names help it spell them).
func stop(prompt: String = "") -> void:
	if state != State.RECORDING:
		return
	_mic_player.stop()
	var mix_rate: float = ProjectSettings.get_setting("audio/driver/mix_rate")
	if _frames.size() < MIN_RECORD_SEC * mix_rate:
		_finish("", "Too short - nothing was recorded.")
		return
	if _peak < LOUD_PEAK:
		_finish("", "Heard only silence - check the microphone (Options > Voice).")
		return
	_set_state(State.THINKING)
	_finish_thread()
	_thread = Thread.new()
	_thread.start(_transcribe.bind(_frames.duplicate(), prompt))


## Throws a recording away.
func cancel() -> void:
	if state == State.RECORDING:
		if _mic_player != null:
			_mic_player.stop()
		_finish("", "")


func _process(_delta: float) -> void:
	if state != State.RECORDING or _capture == null:
		return
	var available := _capture.get_frames_available()
	if available <= 0:
		return
	var frames := _capture.get_buffer(available)
	var peak := 0.0
	for frame in frames:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	level = peak
	_peak = maxf(_peak, peak)
	_frames.append_array(frames)
	var mix_rate: float = ProjectSettings.get_setting("audio/driver/mix_rate")
	if _frames.size() > MAX_RECORD_SEC * mix_rate:
		stop(_pending_prompt())


## A long recording ends by itself; the box's own prompt is not known here, so it comes from the requester when it has one.
func _pending_prompt() -> String:
	if current_owner != null and current_owner.has_method("whisper_prompt"):
		return str(current_owner.call("whisper_prompt"))
	return ""


func _exit_tree() -> void:
	_finish_thread()


# ---------------------------------------------------------------- internals

func _make_engine() -> bool:
	var language_model := VoiceListener.load_model(false)
	if language_model == null:
		return false
	_stt = ClassDB.instantiate(VoiceListener.NATIVE_CLASS)
	if _stt == null:
		return false
	_stt.set("language_model", language_model)
	add_child(_stt)
	return true


## The same muted "Record" bus + AudioEffectCapture the Player's voice control uses (reused when it exists), fed by the microphone.
func _setup_microphone() -> void:
	if PlayerSettings.input_device != "" and PlayerSettings.input_device in AudioServer.get_input_device_list():
		AudioServer.input_device = PlayerSettings.input_device
	var bus := AudioServer.get_bus_index(VoiceListener.BUS_NAME)
	if bus == -1:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, VoiceListener.BUS_NAME)
		AudioServer.add_bus_effect(bus, AudioEffectCapture.new(), 0)
		AudioServer.set_bus_mute(bus, true)
	_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = VoiceListener.BUS_NAME
	add_child(_mic_player)


## Runs on a worker thread: resample to Whisper's 16 kHz and transcribe the whole recording once.
func _transcribe(frames: PackedVector2Array, prompt: String) -> void:
	var interpolator := ClassDB.class_get_integer_constant(VoiceListener.NATIVE_CLASS, "SRC_SINC_FASTEST")
	var samples: PackedFloat32Array = _stt.call("resample", frames, interpolator)
	var text := ""
	if not samples.is_empty():
		var tokens: Array = _stt.call("transcribe", samples, prompt, 0)
		if not tokens.is_empty():
			text = str(tokens[0])
	call_deferred("_on_transcribed", text)


func _on_transcribed(text: String) -> void:
	_finish_thread()
	var heard := VoiceListener.strip_noise_markers(text)
	if heard == "":
		_finish("", "Didn't catch anything - try again.")
	else:
		_finish(heard, "")


func _finish(text: String, error: String) -> void:
	var requester := current_owner
	current_owner = null
	_set_state(State.IDLE)
	if is_instance_valid(requester):
		finished.emit(requester, text, error)


func _finish_thread() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null


func _set_state(value: State) -> void:
	state = value
	state_changed.emit()
