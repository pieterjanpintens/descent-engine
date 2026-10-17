class_name Downloader
extends Node

## Shared download plumbing of the on-demand installers (VoiceInstaller for speech
## recognition, PiperInstaller for narration): files are fetched into user data from
## their upstream sources - nothing is redistributed by this project. Add as a child of
## something in the tree (it awaits timers); status text arrives via `progress`.

signal progress(text: String)

## A download that receives nothing for this long (a dead Wi-Fi connection) is stopped and reported as failed instead of
## waiting forever.
var stall_timeout_sec := 30.0

## Every .part file being written right now, over all downloaders: a second download of the same file is refused, so two
## requests can never write into one file (e.g. a retry while the first, stalled one is still running).
static var _active_parts: Dictionary = {}
var _requests: Array[HTTPRequest] = []


## Stops every download this node has running; each waiting _fetch() returns false. Also done when the node leaves the tree.
func cancel_downloads() -> void:
	for http in _requests.duplicate():
		http.set_meta("cancelled", true)
		http.cancel_request()
		_active_parts.erase(str(http.get_meta("part", "")))


func is_downloading() -> bool:
	return not _requests.is_empty()


func _exit_tree() -> void:
	cancel_downloads()


## Downloads `url` to `dest` (through a .part file, so an interrupted download
## never looks installed), verifying `sha256` when given. Skips the download if
## the file is already there and matches.
## `max_bytes` > 0 caps the size of the body (the download stops with an error beyond it).
func _fetch(url: String, dest: String, sha256: String, label: String, max_bytes: int = -1) -> bool:
	if FileAccess.file_exists(dest) and (sha256 == "" or FileAccess.get_sha256(dest) == sha256):
		return true
	var part := dest + ".part"
	var part_key := ProjectSettings.globalize_path(part)
	if _active_parts.has(part_key):
		progress.emit("The %s is already being downloaded." % label)
		return false
	_active_parts[part_key] = true
	var http := HTTPRequest.new()
	http.set_meta("part", part_key)
	# Not threaded: a threaded request blocks cancel_request() - and freeing it, which also happens when the app quits - until
	# its stuck network read returns, which on a dead connection can be never (that is how an update restart once hung).
	# Polled from the main loop instead, a big chunk per frame keeps it fast.
	http.use_threads = false
	http.download_chunk_size = 1048576
	http.download_file = part
	if max_bytes > 0:
		http.body_size_limit = max_bytes
	add_child(http)
	_requests.append(http)

	var result := {"done": false, "code": 0, "status": 0}
	http.request_completed.connect(func(status: int, code: int, _headers: PackedStringArray, _body: PackedByteArray):
		result["status"] = status
		result["code"] = code
		result["done"] = true
	)
	var error := http.request(url)
	if error != OK:
		_release_request(http)
		progress.emit("Couldn't start the %s download (error %d)." % [label, error])
		return false
	var last_bytes := -1
	var last_change := Time.get_ticks_msec()
	var stopped := ""
	while not result["done"]:
		if http.has_meta("cancelled"):
			stopped = "The %s download was cancelled." % label
			break
		var bytes := http.get_downloaded_bytes()
		if bytes != last_bytes:
			last_bytes = bytes
			last_change = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - last_change > stall_timeout_sec * 1000.0:
			stopped = "The %s download stopped receiving data - check the connection and try again." % label
			break
		progress.emit(_progress_text(label, http))
		await get_tree().create_timer(0.25).timeout
	if stopped != "" or not result["done"]:
		http.cancel_request()
	_release_request(http)
	if stopped != "":
		DirAccess.remove_absolute(part_key)
		progress.emit(stopped)
		return false

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


func _release_request(http: HTTPRequest) -> void:
	_requests.erase(http)
	_active_parts.erase(str(http.get_meta("part", "")))
	http.queue_free()


func _progress_text(label: String, http: HTTPRequest) -> String:
	var done_mb := http.get_downloaded_bytes() / 1048576.0
	var total := http.get_body_size()
	if total > 0:
		return "Downloading %s... %d%% (%d / %d MB)" % [label, int(100.0 * http.get_downloaded_bytes() / total), int(done_mb), int(total / 1048576.0)]
	return "Downloading %s... %d MB" % [label, int(done_mb)]


## Unpacks a .zip below `into` (a user:// folder), keeping its folder structure. False (with a `progress` text) on failure.
func _unzip(archive: String, into: String, label: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(archive) != OK:
		progress.emit("The %s download isn't a valid zip." % label)
		return false
	for entry in reader.get_files():
		if entry.ends_with("/"):
			continue
		var target := ProjectSettings.globalize_path(into.path_join(entry))
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


## Unpacks a .tar.gz below `into` with the system `tar` (Linux / macOS; Godot has no reader for it, and tar keeps the
## executable bits and the links between libraries).
func _untar(archive: String, into: String, label: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(into))
	var output: Array = []
	var code := OS.execute("tar", ["-xzf", ProjectSettings.globalize_path(archive), "-C", ProjectSettings.globalize_path(into)], output, true)
	if code != 0:
		progress.emit("Couldn't unpack the %s (tar exit code %d)." % [label, code])
		return false
	return true
