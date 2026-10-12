class_name Downloader
extends Node

## Shared download plumbing of the on-demand installers (VoiceInstaller for speech
## recognition, PiperInstaller for narration): files are fetched into user data from
## their upstream sources - nothing is redistributed by this project. Add as a child of
## something in the tree (it awaits timers); status text arrives via `progress`.

signal progress(text: String)


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
