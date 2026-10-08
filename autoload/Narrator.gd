extends Node

## Reads text aloud with Piper (neural text-to-speech, installed on demand by PiperInstaller
## into user data - see that script). Autoload, so the campaign player and the mission player
## share one narrator.
##
## `speak(text)` starts the engine in a worker thread (a piper process fed the text on stdin,
## writing a WAV file), then plays that file; a new `speak()` or `stop()` cancels whatever is
## still being made or played. Nothing happens - silently - unless narration is enabled in the
## options (PlayerSettings.narration_enabled) AND installed. `speaking` is true from the call
## until the audio has finished, so the microphone can ignore the narrator
## (VoiceListener checks it).
##
## Piper synthesises a whole text before the first sound (about a second or two for a
## paragraph on a normal PC); cutting the text into sentences and playing the first while the
## next is made is the obvious refinement, not done yet.

signal speaking_changed(is_speaking: bool)

const TEMP_DIR := "user://piper/"

## Test seam: when non-empty this command (executable, then extra arguments) replaces the
## installed Piper - tests point it at a stub that writes a WAV file.
var command_override: PackedStringArray = PackedStringArray()

var speaking: bool = false

var _player: AudioStreamPlayer
var _thread: Thread
var _mutex := Mutex.new()
var _pid: int = -1
var _generation: int = 0
var _current_wav: String = ""


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_on_finished)


## Installed (or overridden for a test), whether or not the player switched it on.
func is_available() -> bool:
	return not command_override.is_empty() or PiperInstaller.is_installed()


func is_enabled() -> bool:
	return PlayerSettings.narration_enabled and is_available()


func speak(text: String) -> void:
	stop()
	if not is_enabled():
		return
	var clean := _flatten(text)
	if clean == "":
		return
	_generation += 1
	_set_speaking(true)
	_thread = Thread.new()
	_thread.start(_synthesize.bind(clean, _generation))


## Cuts off the current narration (and a synthesis still running).
func stop() -> void:
	_generation += 1
	_mutex.lock()
	var pid := _pid
	_mutex.unlock()
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_player.stop()
	_remove_wav()
	_set_speaking(false)


## Piper reads one utterance per input line and writes ONE wav file for the run, so the text goes in
## as a single line.
static func _flatten(text: String) -> String:
	return " ".join(text.replace("\r", " ").replace("\n", " ").replace("\t", " ").split(" ", false))


## Worker thread: run the engine, then hand the wav file to the main thread.
func _synthesize(text: String, generation: int) -> void:
	var wav := ProjectSettings.globalize_path(TEMP_DIR + "narration_%d.wav" % generation)
	DirAccess.make_dir_recursive_absolute(wav.get_base_dir())
	var command := _command()
	var arguments: PackedStringArray = command.slice(1)
	arguments.append_array(["--model", PiperInstaller.voice_path(), "--output_file", wav])
	var process := OS.execute_with_pipe(command[0], arguments, false)
	if process.is_empty():
		push_warning("Narrator: couldn't start '%s'" % command[0])
		call_deferred("_on_synthesized", generation, "")
		return
	var pid: int = process["pid"]
	_mutex.lock()
	_pid = pid
	_mutex.unlock()
	var stdio: FileAccess = process["stdio"]
	var stderr: FileAccess = process["stderr"]
	stdio.store_string(text + "\n")
	stdio.flush()
	stdio.close()  # end of input: piper finishes the line and exits
	while OS.is_process_running(pid):
		OS.delay_msec(20)
	var code := OS.get_process_exit_code(pid)
	stderr.close()
	_mutex.lock()
	_pid = -1
	_mutex.unlock()
	if code != 0 and generation == _generation:  # a cancelled run is killed on purpose
		push_warning("Narrator: the engine exited with code %d" % code)
	call_deferred("_on_synthesized", generation, wav if code == 0 else "")


func _command() -> PackedStringArray:
	if not command_override.is_empty():
		return command_override
	return PackedStringArray([PiperInstaller.engine_path()])


func _on_synthesized(generation: int, wav: String) -> void:
	if generation != _generation:
		if wav != "":
			DirAccess.remove_absolute(wav)
		return
	if wav == "" or not FileAccess.file_exists(wav):
		_set_speaking(false)
		return
	var stream := AudioStreamWAV.load_from_file(wav)
	if stream == null:
		push_warning("Narrator: couldn't read the narration audio")
		_set_speaking(false)
		return
	_current_wav = wav
	_player.stream = stream
	_player.play()


func _on_finished() -> void:
	_remove_wav()
	_set_speaking(false)


func _remove_wav() -> void:
	if _current_wav != "":
		DirAccess.remove_absolute(_current_wav)
		_current_wav = ""


func _set_speaking(value: bool) -> void:
	if speaking == value:
		return
	speaking = value
	speaking_changed.emit(value)
