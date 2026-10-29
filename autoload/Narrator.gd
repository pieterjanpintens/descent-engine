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
## Narration is on but no voice of the language of the text is installed: the story is shown as text only. Emitted on every
## attempt; the small hint on screen appears once per language per session.
signal language_unavailable(lang: String)

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
var _hinted: Array[String] = []  # languages the "no voices" hint was already shown for
var _hint_layer: CanvasLayer


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
	return PlayerSettings.narration_enabled and is_available() and not DebugSession.skipping()


## The language narration reads in now (see NarratorVoices.reading_language()).
func language() -> String:
	return NarratorVoices.reading_language()


## Is there a voice installed for this language (or a test stub)?
func has_voices(lang: String) -> bool:
	return not command_override.is_empty() or not NarratorVoices.installed_for(lang).is_empty()


## `lang_override`: read in the voices of this language instead of the one the game is read in (the campaign setup page's samples,
## before the game's language has been applied).
func speak(text: String, characters: Array[NarratorCharacter] = [], lang_override: String = "") -> void:
	var lang := lang_override if lang_override != "" else language()
	if not has_voices(lang):
		stop()
		if is_enabled():
			_note_missing_voices(lang)
		return
	var jobs: Array[Dictionary] = []
	var storyteller := _storyteller(lang)
	# Voices with an owner: every character's chosen voice ("taken" - throwaways stay away from them) and the heroes'
	# ("hero_ids" - not even another character may use those).
	var taken: Array[String] = []
	var hero_ids: Array[String] = []
	for character in characters:
		if character.voice_id != NarratorVoices.RANDOM_ID:
			taken.append(character.voice_id)
			if character.is_hero:
				hero_ids.append(character.voice_id)
	for segment in NarrationMarkup.segments(text, characters):
		var voice := storyteller
		if segment["speaker"] != null:
			voice = _character_voice(segment["speaker"], storyteller, taken, hero_ids, lang)
		elif segment["name"] != "":
			voice = _random_voice(segment["name"], storyteller, taken, hero_ids, lang)
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


## The player's chosen story teller for a language; when that voice isn't installed the first installed voice of the language
## (for English the base voice).
func _storyteller(lang: String) -> Dictionary:
	var voice := NarratorVoices.find(PlayerSettings.storyteller_for(lang))
	if not voice.is_empty() and NarratorVoices.lang_of(voice) == lang and _voice_available(voice):
		return voice
	for candidate in NarratorVoices.voices_for(lang):
		if _voice_available(candidate):
			return candidate
	return NarratorVoices.BASE


func _character_voice(character: NarratorCharacter, storyteller: Dictionary, taken: Array[String], hero_ids: Array[String], lang: String) -> Dictionary:
	if character.voice_id == NarratorVoices.RANDOM_ID:
		return _random_voice(character.character_name, storyteller, taken, hero_ids, lang)
	var voice := NarratorVoices.find(character.voice_id)
	if not voice.is_empty() and NarratorVoices.lang_of(voice) != lang:
		# A voice chosen for another language (a campaign author picked an English one): here the character gets a voice of this
		# language picked from the name, of the same gender when the chosen voice said which it is.
		return _random_voice(character.character_name, storyteller, taken, hero_ids, lang, NarratorVoices.gender(voice))
	var stolen := not character.is_hero and hero_ids.has(character.voice_id)  # a hero has this voice
	if voice.is_empty() or not _voice_available(voice) or voice["id"] == storyteller["id"] or stolen:
		return _random_voice(character.character_name, storyteller, taken, hero_ids, lang)
	return voice


## A voice for `character_name`, picked by the name's hash: the same name always gets the same voice (while the same
## voices are installed). Never the story teller's; as far as the installed voices allow also none that a character
## has chosen ("taken"), and failing that none a hero has; plain English voices are preferred over accented ones.
func _random_voice(character_name: String, storyteller: Dictionary, taken: Array[String], hero_ids: Array[String], lang: String, gender_hint: String = "") -> Dictionary:
	# A name starting with a capital M wants a male voice, one starting with F a female voice ("MGuard", "FInnkeeper"); without
	# that prefix the hint (the gender of a voice chosen in another language) decides.
	var wanted_gender := gender_hint
	if character_name.begins_with("M"):
		wanted_gender = "m"
	elif character_name.begins_with("F"):
		wanted_gender = "f"
	var genders: Array[String] = [""]  # the wanted gender first, then any
	if wanted_gender != "":
		genders.push_front(wanted_gender)
	for gender in genders:
		for avoid in [taken, hero_ids, [] as Array[String]]:
			for plain_only in [true, false]:  # plain English first, accents only when nothing plain is left
				var pool: Array[Dictionary] = []
				for voice in NarratorVoices.voices_for(lang):
					if voice["id"] != storyteller["id"] and not avoid.has(voice["id"]) and _voice_available(voice) \
							and (voice.get("plain", false) or not plain_only) \
							and (gender == "" or NarratorVoices.gender(voice) == gender):
						pool.append(voice)
				if not pool.is_empty():
					return pool[character_name.hash() % pool.size()]
	return storyteller


## The language has no installed voice: tell the player once (a small hint at the bottom of the screen) and stay silent.
func _note_missing_voices(lang: String) -> void:
	language_unavailable.emit(lang)
	if _hinted.has(lang):
		return
	_hinted.append(lang)
	var hint := tr("No narration voices for %s are installed, so the story is shown as text only. Download them in Options > Voice.") % CampaignInfo.native_name(lang)
	if _hint_layer == null:
		_hint_layer = CanvasLayer.new()
		_hint_layer.layer = 100
		add_child(_hint_layer)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var label := Label.new()
	label.text = hint
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 520
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	_hint_layer.add_child(panel)
	var tween := create_tween()
	tween.tween_interval(6.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.8)
	tween.tween_callback(panel.queue_free)


func _voice_available(voice: Dictionary) -> bool:
	return not command_override.is_empty() or NarratorVoices.model_installed(voice["model"])


## Piper reads one utterance per input line and writes ONE wav file for the run, so each piece goes
## in as a single line.
static func _flatten(text: String) -> String:
	var spoken := _without_asides(text)
	return " ".join(spoken.replace("\r", " ").replace("\n", " ").replace("\t", " ").split(" ", false))


## Anything between round brackets is for the reader only - an acting hint like "(Lie) No, I have not seen him." -
## and is never spoken (nested brackets go innermost first).
static func _without_asides(text: String) -> String:
	var aside := RegEx.create_from_string("\\([^()]*\\)")
	var result := text
	while true:
		var stripped := aside.sub(result, "", true)
		if stripped == result:
			return result
		result = stripped
	return result


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
	return PiperInstaller.command()


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
