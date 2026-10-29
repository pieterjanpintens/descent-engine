class_name PiperInstaller
extends Downloader

## Sets up NARRATION (reading the story aloud) without it being part of the release:
## downloads the Piper text-to-speech engine (MIT, the rhasspy/piper release binary)
## and one neural voice (en_US lessac, medium - from the rhasspy/piper-voices repo on
## Hugging Face) into user data - `user://piper/`. Same on-demand model as the speech
## recognition VoiceInstaller: releases stay small, every player fetches the ~90 MB once
## straight from the upstream sources and nothing is redistributed by this project.
##
## The Windows engine is a zip (extracted with ZIPReader); the Linux and macOS ones are
## tar.gz files, unpacked with the system `tar`.
##
## macOS: the upstream macOS release is incomplete - both its archives hold the same Intel
## (x86_64) program WITHOUT the three libraries it needs. They are in the piper-phonemize
## release, so that archive is downloaded too and its libraries are put next to the program
## (about 45 MB more). The program has no search path for them, so it is started with
## DYLD_LIBRARY_PATH set (see command()). On Apple silicon it runs under Rosetta.
##
## `await install()`; status text arrives via `progress`. Narrator (the autoload) is what
## actually runs the installed engine.

const INSTALL_DIR := "user://piper/"
const VOICE_NAME := NarratorVoices.BASE_MODEL
## What the setup button tells the player.
const DOWNLOAD_SIZE_TEXT := "about 90 MB"
## Arguments: the library folder ("" = none), the program, then the program's own arguments.
const UNIX_LAUNCH := 'lib="$1"; shift; if [ -n "$lib" ]; then export DYLD_LIBRARY_PATH="$lib"; fi; exec "$@" >/dev/null 2>&1'
## macOS: one of the libraries the engine needs, used to tell a complete install.
const MACOS_LIBRARY := "libespeak-ng.1.dylib"

## Overridable (tests point these at a local server).
var engine_url_windows := "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_windows_amd64.zip"
var engine_url_linux := "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_x86_64.tar.gz"
## macOS: the engine (an Intel program, whatever the archive is called) and the libraries it lacks.
var engine_url_macos := "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_macos_x64.tar.gz"
var libraries_url_macos := "https://github.com/rhasspy/piper-phonemize/releases/download/2023.11.14-4/piper-phonemize_macos_x64.tar.gz"
var voice_url := "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/" + VOICE_NAME + ".onnx"
var voice_config_url := "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/" + VOICE_NAME + ".onnx.json"
## The root of the voices repository the optional extra voices come from (NarratorVoices.EXTRA_MODEL_PATHS are below it).
var extras_base_url := "https://huggingface.co/rhasspy/piper-voices/resolve/main/"


static func is_supported_platform() -> bool:
	return OS.get_name() in ["Windows", "Linux", "macOS"]


## macOS on Apple silicon: the engine is an Intel program, so Rosetta must be there.
static func needs_rosetta() -> bool:
	if OS.get_name() != "macOS" or Engine.get_architecture_name() != "arm64":
		return false
	return OS.execute("/usr/bin/arch", ["-x86_64", "/usr/bin/true"]) != 0


## The installed engine executable as an absolute OS path, "" when it isn't installed. The
## release archives nest everything in a `piper/` folder; both layouts are accepted.
static func engine_path() -> String:
	var exe := "piper.exe" if OS.get_name() == "Windows" else "piper"
	for candidate in [INSTALL_DIR + "piper/" + exe, INSTALL_DIR + exe]:
		if FileAccess.file_exists(candidate):
			if OS.get_name() == "macOS" and not FileAccess.file_exists(candidate.get_base_dir() + "/" + MACOS_LIBRARY):
				continue  # the libraries of the second download are not there (yet)
			return ProjectSettings.globalize_path(candidate)
	return ""


## The command line that starts the engine. Linux and macOS go through a small shell line that (1) throws the engine's
## own output away - Narrator closes the pipe after sending the text, and the engine would be killed (SIGPIPE, exit
## code 13) when it then prints the name of the file it wrote - and (2) on macOS points it at its libraries.
static func command() -> PackedStringArray:
	var engine := engine_path()
	if OS.get_name() == "Windows":
		return PackedStringArray([engine])
	var libraries := engine.get_base_dir() if OS.get_name() == "macOS" else ""
	return PackedStringArray(["/bin/sh", "-c", UNIX_LAUNCH, "piper", libraries, engine])


static func is_installed() -> bool:
	return engine_path() != "" and NarratorVoices.model_installed(VOICE_NAME)


## Downloads and installs the engine and the voice. Smallest files first so a broken link
## fails fast. Returns true when narration can start.
func install() -> bool:
	if not is_supported_platform():
		progress.emit(tr("Narration setup isn't supported on %s yet.") % OS.get_name())
		return false
	if needs_rosetta():
		progress.emit("Narration needs Rosetta on this Mac: run 'softwareupdate --install-rosetta' in Terminal, then try again.")
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
	return await _install_models(NarratorVoices.EXTRA_MODEL_PATHS, "Extra voices installed.")


## The optional plain-English voices (NarratorVoices.STANDARD).
func install_standard() -> bool:
	return await _install_models(NarratorVoices.STANDARD_MODEL_PATHS, "Standard voices installed.")


func _install_models(paths: Dictionary, done_text: String) -> bool:
	if not is_supported_platform():
		progress.emit(tr("Narration setup isn't supported on %s yet.") % OS.get_name())
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NarratorVoices.VOICE_DIR))
	for model in paths:
		if NarratorVoices.model_installed(model):
			continue
		var url: String = extras_base_url + paths[model] + "/" + model
		var target: String = NarratorVoices.VOICE_DIR + model
		if not await _fetch(url + ".onnx.json", target + ".onnx.json", "", tr("voice settings (%s)") % model):
			return false
		if not await _fetch(url + ".onnx", target + ".onnx", "", tr("voices (%s)") % model):
			return false
	progress.emit(done_text)
	return true


func _install_engine() -> bool:
	var system := OS.get_name()
	var windows := system == "Windows"
	var archive := INSTALL_DIR + ("engine.zip" if windows else "engine.tar.gz")
	var url := engine_url_windows if windows else (engine_url_macos if system == "macOS" else engine_url_linux)
	if not await _fetch(url, archive, "", "narration engine"):
		return false
	progress.emit("Unpacking the narration engine...")
	var ok := _unpack_zip(archive) if windows else _unpack_tar(archive, INSTALL_DIR)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(archive))
	if not ok:
		return false
	if system == "macOS" and not await _install_macos_libraries():
		return false
	if engine_path() == "":
		progress.emit("The narration engine download doesn't contain a piper executable.")
		return false
	return true


## macOS: the libraries the engine archive lacks - the `lib` folder of the piper-phonemize archive, put next to the program.
func _install_macos_libraries() -> bool:
	var archive := INSTALL_DIR + "libraries.tar.gz"
	if not await _fetch(libraries_url_macos, archive, "", "narration engine libraries"):
		return false
	progress.emit("Unpacking the narration engine libraries...")
	var ok := _unpack_tar(archive, INSTALL_DIR + "piper/", ["--strip-components", "2", "piper-phonemize/lib"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(archive))
	return ok


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
			progress.emit(tr("Couldn't write %s (error %d).") % [entry, FileAccess.get_open_error()])
			return false
		file.store_buffer(reader.read_file(entry))
		file.close()
	reader.close()
	return true


## Linux / macOS: the release is a tar.gz, and Godot has no reader for it - the system `tar` unpacks it
## (and keeps the executable bit and the links between the libraries). `extra` = more tar arguments.
func _unpack_tar(archive: String, into: String, extra: Array = []) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(into))
	var arguments: Array = ["-xzf", ProjectSettings.globalize_path(archive), "-C", ProjectSettings.globalize_path(into)]
	arguments.append_array(extra)
	var output: Array = []
	var code := OS.execute("tar", arguments, output, true)
	if code != 0:
		progress.emit(tr("Couldn't unpack the narration engine (tar exit code %d).") % code)
		return false
	return true
