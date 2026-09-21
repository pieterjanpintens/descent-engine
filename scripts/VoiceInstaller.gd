class_name VoiceInstaller
extends Node

## Sets up voice control WITHOUT it being part of the release: downloads the
## speech engine (the Godot Whisper GDExtension, MIT, from its GitHub release)
## and the speech models (Whisper small.en + the Silero VAD, from Hugging Face)
## into user data - `user://whisper/` - and loads the extension at RUNTIME
## (GDExtensionManager.load_extension(), no restart). Releases stay small; each
## player fetches the ~265 MB once, straight from the upstream sources, so
## nothing is redistributed by this project. user:// survives game updates.
##
## Verified with the project's Godot 4.7.2: an extension AND a model loaded
## from user:// work (the model then transcribes). Not yet verified in an
## EXPORTED build. Windows and Linux only (the macOS library is a .framework
## directory - not handled).
##
## Add as a child of something in the tree (it awaits timers), then
## `await install()`; status text arrives via `progress`.

signal progress(text: String)

const INSTALL_DIR := "user://whisper/"
const MODEL_DIR := "user://whisper/models/"
const GDEXTENSION := "user://whisper/godot_whisper.gdextension"

const MODEL_FILE := "ggml-small.en-q5_1.bin"
const VAD_FILE := "ggml-silero-v6.2.0.bin"
## SHA-256 of the exact files (computed from known-good copies) - a corrupt or
## swapped download is rejected.
const MODEL_SHA256 := "bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30"
const VAD_SHA256 := "2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987"
## What the button tells the player.
const DOWNLOAD_SIZE_TEXT := "about 265 MB"

## Overridable (tests point these at a local server).
var addon_url := "https://github.com/appsinacup/godot-whisper/releases/download/v2.0.3/Godot_Whisper.zip"
var model_url := "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/" + MODEL_FILE
var vad_url := "https://huggingface.co/ggml-org/whisper-vad/resolve/main/" + VAD_FILE


static func is_supported_platform() -> bool:
	return OS.get_name() == "Windows" or OS.get_name() == "Linux"


## True if everything needed is already in user data.
static func is_installed() -> bool:
	return FileAccess.file_exists(GDEXTENSION) and FileAccess.file_exists(MODEL_DIR + MODEL_FILE)


## Makes the native `SpeechToText` class available from user data if it isn't
## already (a copy in res://addons registers itself at startup). Cheap when
## nothing is installed. True if the class exists afterwards.
static func load_extension() -> bool:
	if ClassDB.class_exists("SpeechToText"):
		return true
	if not FileAccess.file_exists(GDEXTENSION):
		return false
	GDExtensionManager.load_extension(GDEXTENSION)
	return ClassDB.class_exists("SpeechToText")


## Downloads and installs everything, then loads the extension. Smallest files
## first so a broken link fails fast. Returns true when voice can start.
func install() -> bool:
	if not is_supported_platform():
		progress.emit("Voice setup isn't supported on %s yet." % OS.get_name())
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MODEL_DIR))
	if not await _fetch(vad_url, MODEL_DIR + VAD_FILE, VAD_SHA256, "voice-activity model"):
		return false
	if not await _install_addon():
		return false
	if not await _fetch(model_url, MODEL_DIR + MODEL_FILE, MODEL_SHA256, "speech model"):
		return false
	if not load_extension():
		progress.emit("The speech engine was installed but could not be loaded - try restarting the game.")
		return false
	progress.emit("Voice control installed.")
	return true


## Downloads `url` to `dest` (through a .part file, so an interrupted download
## never looks installed), verifying `sha256` when given. Skips the download if
## the file is already there and matches.
func _fetch(url: String, dest: String, sha256: String, label: String) -> bool:
	if FileAccess.file_exists(dest) and (sha256 == "" or FileAccess.get_sha256(dest) == sha256):
		return true
	var part := dest + ".part"
	var http := HTTPRequest.new()
	http.use_threads = true
	http.download_file = part
	add_child(http)

	var result := {"done": false, "code": 0, "status": 0}
	http.request_completed.connect(func(status: int, code: int, _headers: PackedStringArray, _body: PackedByteArray):
		result["status"] = status
		result["code"] = code
		result["done"] = true
	)
	var error := http.request(url)
	if error != OK:
		http.queue_free()
		progress.emit("Couldn't start the %s download (error %d)." % [label, error])
		return false
	while not result["done"]:
		progress.emit(_progress_text(label, http))
		await get_tree().create_timer(0.25).timeout
	http.queue_free()

	if result["status"] != HTTPRequest.RESULT_SUCCESS or result["code"] != 200:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(part))
		progress.emit("The %s download failed (network %d, HTTP %d)." % [label, result["status"], result["code"]])
		return false
	if sha256 != "" and FileAccess.get_sha256(part) != sha256:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(part))
		progress.emit("The %s download was corrupt (checksum mismatch)." % label)
		return false
	DirAccess.rename_absolute(ProjectSettings.globalize_path(part), ProjectSettings.globalize_path(dest))
	return true


func _progress_text(label: String, http: HTTPRequest) -> String:
	var done_mb := http.get_downloaded_bytes() / 1048576.0
	var total := http.get_body_size()
	if total > 0:
		return "Downloading %s... %d%% (%d / %d MB)" % [label, int(100.0 * http.get_downloaded_bytes() / total), int(done_mb), int(total / 1048576.0)]
	return "Downloading %s... %d MB" % [label, int(done_mb)]


## The addon zip -> only the .gdextension and THIS platform's single-precision
## library, placed as the .gdextension expects them (bin/...). Entries are
## matched by name, whatever folder the zip nests them in.
func _install_addon() -> bool:
	var zip_path := INSTALL_DIR + "addon.zip"
	if not await _fetch(addon_url, zip_path, "", "speech engine"):
		return false
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		progress.emit("The speech engine download isn't a valid zip.")
		return false

	var prefix := ""
	var found := false
	for entry in reader.get_files():
		if entry.get_file() == "godot_whisper.gdextension":
			prefix = entry.get_base_dir() + "/" if entry.get_base_dir() != "" else ""
			found = true
			break
	if not found:
		reader.close()
		progress.emit("The speech engine download doesn't contain godot_whisper.gdextension.")
		return false

	var extracted := 0
	for entry in reader.get_files():
		if entry.ends_with("/"):
			continue
		var relative := entry.trim_prefix(prefix)
		if relative != "godot_whisper.gdextension" and not (relative.begins_with("bin/") and _wanted_library(relative.get_file())):
			continue
		var target := ProjectSettings.globalize_path(INSTALL_DIR + relative)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			reader.close()
			progress.emit("Couldn't write %s (error %d)." % [relative, FileAccess.get_open_error()])
			return false
		file.store_buffer(reader.read_file(entry))
		file.close()
		extracted += 1
	reader.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(zip_path))
	if extracted < 2:
		progress.emit("The speech engine download had no library for %s." % OS.get_name())
		return false
	return true


## This platform's normal (single-precision) library, e.g.
## libgodot_whisper.windows.template_release.x86_64.dll.
static func _wanted_library(file_name: String) -> bool:
	if file_name.contains(".double."):
		return false
	match OS.get_name():
		"Windows":
			return file_name.contains(".windows.") and file_name.ends_with(".x86_64.dll")
		"Linux":
			return file_name.contains(".linux.") and file_name.ends_with(".x86_64.so")
	return false
