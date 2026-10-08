extends Node

## Reads text aloud with Piper (neural text-to-speech, installed on demand by PiperInstaller into
## user data - see that script). Autoload, so the campaign player and the mission player share one
## narrator.
##
## `speak(text, characters)`: the text is cut at the character tags (NarrationMarkup) into pieces; the
## story teller reads the untagged parts - the player's own choice of voice, PlayerSettings.storyteller_voice
## - and each character its own voice (NarratorVoices). A character whose voice IS the story teller's gets
## another installed voice instead, and so does one whose voice isn't installed (the extra voices are an
## optional download): characters never sound like the story teller. A throwaway character (a tag whose name
## no character defines) and a character set to "random" get a voice picked from their NAME among the installed
## ones - random, but always the same voice for the same name, so a guard sounds like himself all story long.
##
## A worker thread makes one wav file per piece (a piper process fed the text on stdin) in order while the
## main thread plays the pieces as they arrive. A new `speak()` or `stop()` cancels what is still being
## made or played. Nothing happens - silently - unless narration is enabled in the options
## (PlayerSettings.narration_enabled) AND installed. `speaking` is true from the call until the last audio
## has finished, so the microphone can ignore the narrator (VoiceListener checks it).

signal speaking_changed(is_speaking: bool)

const TEMP_DIR := "user://piper/"

## Test seam: when non-empty this command (executable, then extra arguments) replaces the
## installed Piper and every voice counts as installed - tests point it at a stub that writes a WAV file.
var command_override: PackedStringArray = PackedStringArray()

var speaking: bool = false

var _player: AudioStreamPlayer
var _thread: Thread
var _mutex := Mutex.new()
var _pid: int = -1
var _generation: int = 0
var _pending: Array[String] = []  # wav files made but not played yet
var _synth_done: bool = true
var _current_wav: String = ""


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_on_finished)


func _exit_tree() -> void:
	stop()  # joins the worker thread


## Installed (or overridden for a test), whether or not the player switched it on.
func is_available() -> bool:
	return not command_override.is_empty() or PiperInstaller.is_installed()


func is_enabled() -> bool:
	return PlayerSettings.narration_enabled and is_available()


func speak(text: String, characters: Array[NarratorCharacter] = []) -> void:
	var jobs: Array[Dictionary] = []
	var storyteller := _storyteller()
	for segment in NarrationMarkup.segments(text, characters):
		var voice := storyteller
		if segment["speaker"] != null:
			voice = _character_voice(segment["speaker"], storyteller)
		elif segment["name"] != "":
			voice = _random_voice(segment["name"], storyteller)
		var clean := _flatten(segment["text"])
		if clean != "":
			jobs.append({"text": clean, "model": voice["model"], "speaker": voice["speaker"]})
	_start(jobs)


## Reads `text` in one particular voice (a voice picker's "play a sample"), whether or not it is the story
## teller's.
func speak_voice(voice_id: String, text: String) -> void:
	var voice := NarratorVoices.find(voice_id)
	var clean := _flatten(text)
	if voice.is_empty() or clean == "":
		stop()
		return
	_start([{"text": clean, "model": voice["model"], "speaker": voice["speaker"]}] as Array[Dictionary])


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
	for wav in _pending:
		DirAccess.remove_absolute(wav)
	_pending.clear()
	_remove_current()
	_synth_done = true
	_set_speaking(false)


func _start(jobs: Array[Dictionary]) -> void:
	stop()
	if not is_enabled() or jobs.is_empty():
		return
	_generation += 1
	_synth_done = false
	_set_speaking(true)
	_thread = Thread.new()
	_thread.start(_synthesize.bind(jobs, _generation))


## The player's chosen story teller, the base voice when that isn't installed.
func _storyteller() -> Dictionary:
	var voice := NarratorVoices.find(PlayerSettings.storyteller_voice)
	if voice.is_empty() or not _voice_available(voice):
		return NarratorVoices.BASE
	return voice


func _character_voice(character: NarratorCharacter, storyteller: Dictionary) -> Dictionary:
	if character.voice_id == NarratorVoices.RANDOM_ID:
		return _random_voice(character.character_name, storyteller)
	var voice := NarratorVoices.find(character.voice_id)
	if voice.is_empty() or not _voice_available(voice) or voice["id"] == storyteller["id"]:
		return _other_voice(storyteller)
	return voice


## A voice for `character_name` among the available ones except the story teller's, picked by the name's hash:
## the same name always gets the same voice (while the same voices are installed).
func _random_voice(character_name: String, storyteller: Dictionary) -> Dictionary:
	var pool: Array[Dictionary] = []
	for voice in NarratorVoices.all():
		if voice["id"] != storyteller["id"] and _voice_available(voice):
			pool.append(voice)
	if pool.is_empty():
		return storyteller
	return pool[character_name.hash() % pool.size()]


## Another voice than the story teller's: the first available one in catalogue order.
func _other_voice(storyteller: Dictionary) -> Dictionary:
	for voice in NarratorVoices.all():
		if voice["id"] != storyteller["id"] and _voice_available(voice):
			return voice
	return storyteller


func _voice_available(voice: Dictionary) -> bool:
	return not command_override.is_empty() or NarratorVoices.model_installed(voice["model"])


## Piper reads one utterance per input line and writes ONE wav file for the run, so each piece goes
## in as a single line.
static func _flatten(text: String) -> String:
	return " ".join(text.replace("\r", " ").replace("\n", " ").replace("\t", " ").split(" ", false))


## Worker thread: run the engine once per piece, handing each wav file to the main thread as it is done.
func _synthesize(jobs: Array[Dictionary], generation: int) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_DIR))
	for i in jobs.size():
		if generation != _generation:
			return
		var wav := ProjectSettings.globalize_path(TEMP_DIR + "narration_%d_%d.wav" % [generation, i])
		var made := _run_engine(jobs[i], wav, generation)
		call_deferred("_on_piece", generation, wav if made else "", i == jobs.size() - 1)


func _run_engine(job: Dictionary, wav: String, generation: int) -> bool:
	var command := _command()
	var arguments: PackedStringArray = command.slice(1)
	arguments.append_array(["--model", NarratorVoices.model_path(job["model"]), "--output_file", wav])
	if int(job["speaker"]) >= 0:
		arguments.append_array(["--speaker", str(job["speaker"])])
	var process := OS.execute_with_pipe(command[0], arguments, false)
	if process.is_empty():
		push_warning("Narrator: couldn't start '%s'" % command[0])
		return false
	var pid: int = process["pid"]
	_mutex.lock()
	_pid = pid
	_mutex.unlock()
	var stdio: FileAccess = process["stdio"]
	var stderr: FileAccess = process["stderr"]
	stdio.store_string(job["text"] + "\n")
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
	return code == 0


func _command() -> PackedStringArray:
	if not command_override.is_empty():
		return command_override
	return PackedStringArray([PiperInstaller.engine_path()])


## Main thread: a piece is ready (wav == "" = it failed and is skipped).
func _on_piece(generation: int, wav: String, last: bool) -> void:
	if generation != _generation:
		if wav != "":
			DirAccess.remove_absolute(wav)
		return
	if wav != "" and FileAccess.file_exists(wav):
		_pending.append(wav)
	if last:
		_synth_done = true
	_play_next()


func _play_next() -> void:
	if _player.playing:
		return
	while not _pending.is_empty():
		var wav: String = _pending.pop_front()
		var stream := AudioStreamWAV.load_from_file(wav)
		if stream == null:
			push_warning("Narrator: couldn't read the narration audio")
			DirAccess.remove_absolute(wav)
			continue
		_current_wav = wav
		_player.stream = stream
		_player.play()
		return
	if _synth_done:
		_set_speaking(false)


func _on_finished() -> void:
	_remove_current()
	_play_next()


func _remove_current() -> void:
	if _current_wav != "":
		DirAccess.remove_absolute(_current_wav)
		_current_wav = ""


func _set_speaking(value: bool) -> void:
	if speaking == value:
		return
	speaking = value
	speaking_changed.emit(value)
