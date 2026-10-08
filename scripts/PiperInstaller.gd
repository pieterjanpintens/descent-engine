class_name PiperInstaller
extends Downloader

## Sets up NARRATION (reading the story aloud) without it being part of the release:
## downloads the Piper text-to-speech engine (MIT, the rhasspy/piper release binary)
## and one neural voice (en_US lessac, medium - from the rhasspy/piper-voices repo on
## Hugging Face) into user data - `user://piper/`. Same on-demand model as the speech
## recognition VoiceInstaller: releases stay small, every player fetches the ~90 MB once
## straight from the upstream sources and nothing is redistributed by this project.
##
## Windows and Linux only. The Windows engine is a zip (extracted with ZIPReader); the
## Linux one is a tar.gz, unpacked with the system `tar`.
##
## `await install()`; status text arrives via `progress`. Narrator (the autoload) is what
## actually runs the installed engine.

const INSTALL_DIR := "user://piper/"
const VOICE_NAME := NarratorVoices.BASE_MODEL
## What the setup button tells the player.
const DOWNLOAD_SIZE_TEXT := "about 90 MB"

## Overridable (tests point these at a local server).
var engine_url_windows := "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_windows_amd64.zip"
var engine_url_linux := "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_x86_64.tar.gz"
var voice_url := "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/" + VOICE_NAME + ".onnx"
var voice_config_url := "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/" + VOICE_NAME + ".onnx.json"
## The root of the voices repository the optional extra voices come from (NarratorVoices.EXTRA_MODEL_PATHS are below it).
var extras_base_url := "https://huggingface.co/rhasspy/piper-voices/resolve/main/"


static func is_supported_platform() -> bool:
	return OS.get_name() == "Windows" or OS.get_name() == "Linux"


## The installed engine executable as an absolute OS path, "" when it isn't installed. The
## release archives nest everything in a `piper/` folder; both layouts are accepted.
static func engine_path() -> String:
	var exe := "piper.exe" if OS.get_name() == "Windows" else "piper"
	for candidate in [INSTALL_DIR + "piper/" + exe, INSTALL_DIR + exe]:
		if FileAccess.file_exists(candidate):
			return ProjectSettings.globalize_path(candidate)
	return ""


static func is_installed() -> bool:
	return engine_path() != "" and NarratorVoices.model_installed(VOICE_NAME)


## Downloads and installs the engine and the voice. Smallest files first so a broken link
## fails fast. Returns true when narration can start.
func install() -> bool:
	if not is_supported_platform():
		progress.emit("Narration setup isn't supported on %s yet." % OS.get_name())
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NarratorVoices.VOICE_DIR))
	var voice := NarratorVoices.VOICE_DIR + VOICE_NAME + ".onnx"
	if not await _fetch(voice_config_url, voice + ".json", "", "voice settings"):
		return false
	if engine_path() == "" and not await _install_engine():
		return false
	if not await _fetch(voice_url, voice, "", "narrator voice"):
		return false
	if not is_installed():
		progress.emit("Narration was downloaded but the engine could not be found - try again.")
		return false
	progress.emit("Narration installed.")
	return true


## The optional extra voices (accents): every model of NarratorVoices.EXTRA_MODEL_PATHS, skipping
## the ones already there. Needs nothing but the voices repository - the engine comes with install().
func install_extras() -> bool:
	if not is_supported_platform():
		progress.emit("Narration setup isn't supported on %s yet." % OS.get_name())
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NarratorVoices.VOICE_DIR))
	for model in NarratorVoices.EXTRA_MODEL_PATHS:
		if NarratorVoices.model_installed(model):
			continue
		var url: String = extras_base_url + NarratorVoices.EXTRA_MODEL_PATHS[model] + "/" + model
		var target: String = NarratorVoices.VOICE_DIR + model
		if not await _fetch(url + ".onnx.json", target + ".onnx.json", "", "voice settings (%s)" % model):
			return false
		if not await _fetch(url + ".onnx", target + ".onnx", "", "voices (%s)" % model):
			return false
	progress.emit("Extra voices installed.")
	return true


func _install_engine() -> bool:
	var windows := OS.get_name() == "Windows"
	var archive := INSTALL_DIR + ("engine.zip" if windows else "engine.tar.gz")
	if not await _fetch(engine_url_windows if windows else engine_url_linux, archive, "", "narration engine"):
		return false
	progress.emit("Unpacking the narration engine...")
	var ok := _unpack_zip(archive) if windows else _unpack_tar(archive)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(archive))
	if not ok:
		return false
	if engine_path() == "":
		progress.emit("The narration engine download doesn't contain a piper executable.")
		return false
	return true


## Extracts every entry of the zip below INSTALL_DIR, keeping its folder structure.
func _unpack_zip(archive: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(archive) != OK:
		progress.emit("The narration engine download isn't a valid zip.")
		return false
	for entry in reader.get_files():
		if entry.ends_with("/"):
			continue
		var target := ProjectSettings.globalize_path(INSTALL_DIR + entry)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			reader.close()
			progress.emit("Couldn't write %s (error %d)." % [entry, FileAccess.get_open_error()])
			return false
		file.store_buffer(reader.read_file(entry))
		file.close()
	reader.close()
	return true


## Linux: the release is a tar.gz, and Godot has no reader for it - the system `tar` unpacks it
## (and keeps the executable bit).
func _unpack_tar(archive: String) -> bool:
	var output: Array = []
	var code := OS.execute("tar", ["-xzf", ProjectSettings.globalize_path(archive), "-C", ProjectSettings.globalize_path(INSTALL_DIR)], output, true)
	if code != 0:
		progress.emit("Couldn't unpack the narration engine (tar exit code %d)." % code)
		return false
	return true
