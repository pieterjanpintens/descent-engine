class_name AiClient
extends Node

## The one place that talks to an AI (see PlayerSettings.ai_*). Optional by design: nothing here runs unless the author turned
## AI help on and pressed an AI button. Two providers behind `ask()`: the author's own Anthropic API key, or the Claude Code
## program on this PC (`claude -p`, signed in with the author's own Claude account - no key, nothing paid per request). Add as a
## child of something in the tree (it awaits timers).
##
## Requests are not threaded: a threaded HTTPRequest blocks cancel_request() and freeing (see Downloader). One request at a
## time per client; something that wants several at once (the translation window) uses several AiClient nodes.

const API_URL := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2023-06-01"
const DEFAULT_MODEL := "claude-sonnet-5-5"
## The models offered in Options: [id, label].
const MODELS := [
	["claude-sonnet-5-5", "Sonnet 5.5 - balanced (recommended)"],
	["claude-haiku-5-5", "Haiku 5.5 - fast and cheapest"],
	["claude-opus-5-5", "Opus 5.5 - best writing, most expensive"],
]

const CLI_TIMEOUT_SEC := 180.0
const WORK_DIR := "user://ai/work/"

## Replaced by tests (a local mock server).
var api_url := API_URL
## Tests: a stub program (a .bat / .sh script) used instead of the real Claude Code.
var cli_override := ""
## Seconds to wait for the answer in total.
var timeout_sec := 90.0

var _http: HTTPRequest
var _cancelled := false
var _busy := false
var _cli_pid := -1


## Whether AI help is switched on AND can work: a key for the API provider, or the Claude Code program found on this PC.
## Everything AI in the editors is hidden otherwise.
static func is_configured() -> bool:
	if not PlayerSettings.ai_enabled:
		return false
	if PlayerSettings.ai_provider == "claude_code":
		return claude_executable() != ""
	return PlayerSettings.ai_api_key.strip_edges() != ""


func is_busy() -> bool:
	return _busy


## Stops the request that is running; its ask() returns {ok = false, cancelled = true}.
func cancel() -> void:
	_cancelled = true
	if _http != null:
		_http.cancel_request()
	if _cli_pid > 0:
		_kill_cli(_cli_pid)


# ---------------------------------------------------------------- Claude Code on this PC

const INSTALL_COMMAND := "npm install -g @anthropic-ai/claude-code"

## The Claude Code program: the path in the settings if it exists, else `claude` on the PATH. "" when it isn't there - Claude Code
## has to be installed by the author (`npm install -g @anthropic-ai/claude-code`), nothing else is searched for.
static func claude_executable() -> String:
	var chosen := PlayerSettings.ai_claude_path.strip_edges()
	if chosen != "" and FileAccess.file_exists(chosen):
		return chosen
	var is_windows := OS.get_name() == "Windows"
	var names: Array[String] = []
	if is_windows:
		names.append_array(["claude.exe", "claude.cmd"])
	else:
		names.append("claude")
	for folder in OS.get_environment("PATH").split(";" if is_windows else ":", false):
		for exe_name in names:
			var candidate := folder.path_join(exe_name)
			if FileAccess.file_exists(candidate):
				return candidate
	return ""


## Whether Claude Code is installed and signed in, without using any tokens (`claude auth status`):
## {found, logged_in, path, text}. Blocks for about a second.
static func claude_status() -> Dictionary:
	var path := claude_executable()
	if path == "":
		return {"found": false, "logged_in": false, "path": "", "text": "Claude Code isn't installed (or isn't on the PATH). Install it with:  %s" % INSTALL_COMMAND}
	var output: Array = []
	OS.execute(path, ["auth", "status", "--json"], output, true)
	var parsed: Variant = JSON.parse_string("".join(output))
	if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).get("loggedIn", false):
		return {"found": true, "logged_in": true, "path": path, "text": "Claude Code is signed in."}
	return {"found": true, "logged_in": false, "path": path, "text": "Claude Code is not signed in. Run this once in a terminal:  claude auth login"}


## Our model ids -> Claude Code's model aliases.
static func cli_model(model_id: String) -> String:
	if model_id.contains("haiku"):
		return "haiku"
	if model_id.contains("opus"):
		return "opus"
	return "sonnet"


## Runs `claude -p` with no tools (it can only answer with text) from an empty folder, so no project settings or notes are read.
## Prompts go through files (no quoting problems, no length limit); the answer comes back through a file.
func _ask_cli(system_prompt: String, user_prompt: String, model: String) -> Dictionary:
	var exe := cli_override if cli_override != "" else claude_executable()
	if exe == "":
		return _failure("Claude Code isn't installed - install it with:  %s" % INSTALL_COMMAND)
	var work := ProjectSettings.globalize_path(WORK_DIR)
	DirAccess.make_dir_recursive_absolute(work)
	var id := "%d_%d" % [Time.get_ticks_usec(), get_instance_id()]  # unique per client: several run at once
	var is_windows := OS.get_name() == "Windows"
	var base := work.path_join(id)
	var files := {"sys": base + ".sys", "in": base + ".in", "out": base + ".out", "err": base + ".err", "code": base + ".code", "run": base + (".bat" if is_windows else ".sh")}
	_write(files["sys"], system_prompt if system_prompt != "" else "You are a helpful writing assistant. Reply with the text only.")
	_write(files["in"], user_prompt)
	var chosen: String = model if model != "" else PlayerSettings.ai_model
	var invoke := ("call " if is_windows and exe.get_extension().to_lower() in ["bat", "cmd"] else "") + _quote(exe)
	var line := "%s -p --tools \"\" --system-prompt-file %s --model %s --output-format text --no-session-persistence --disable-slash-commands < %s > %s 2> %s" % [
		invoke, _quote(files["sys"]), cli_model(chosen), _quote(files["in"]), _quote(files["out"]), _quote(files["err"])]
	if is_windows:
		_write(files["run"], "@echo off\r\ncd /d %s\r\n%s\r\necho %%errorlevel%%> %s\r\n" % [_quote(work), line, _quote(files["code"])])
	else:
		_write(files["run"], "#!/bin/sh\ncd %s\n%s\necho $? > %s\n" % [_quote(work), line, _quote(files["code"])])
	var process: Dictionary = OS.execute_with_pipe("cmd.exe", ["/c", files["run"]], false) if is_windows else OS.execute_with_pipe("/bin/sh", [files["run"]], false)
	if process.is_empty():
		_remove_all(files.values())
		return _failure("Couldn't start Claude Code.")
	_cli_pid = int(process["pid"])
	var started := Time.get_ticks_msec()
	var timed_out := false
	while OS.is_process_running(_cli_pid) and not _cancelled:
		if Time.get_ticks_msec() - started > CLI_TIMEOUT_SEC * 1000.0:
			timed_out = true
			break
		await get_tree().create_timer(0.1).timeout
	if _cancelled or timed_out:
		_kill_cli(_cli_pid)
	_cli_pid = -1
	var answer := FileAccess.get_file_as_string(files["out"]).strip_edges()
	var problem := FileAccess.get_file_as_string(files["err"]).strip_edges()
	var exit_code := int(FileAccess.get_file_as_string(files["code"]).strip_edges()) if FileAccess.file_exists(files["code"]) else -1
	_remove_all(files.values())
	if _cancelled:
		var cancelled := _failure("Cancelled.")
		cancelled["cancelled"] = true
		return cancelled
	if timed_out:
		return _failure("Claude Code took too long (over %d seconds)." % int(CLI_TIMEOUT_SEC))
	return _read_cli_answer(exit_code, answer, problem)


## Turns Claude Code's output into {ok, text, error, ...}. A sign-in problem gets its own message.
static func _read_cli_answer(exit_code: int, answer: String, problem: String) -> Dictionary:
	var combined := (answer + "\n" + problem).to_lower()
	if combined.contains("not logged in") or combined.contains("/login") or combined.contains("auth login"):
		return _failure("Claude Code is not signed in - run  claude auth login  in a terminal once.")
	if exit_code != 0 or answer == "":
		var detail := (problem if problem != "" else answer).left(240)
		return _failure("Claude Code didn't give an answer%s" % ((": " + detail) if detail != "" else "."))
	return {"ok": true, "text": answer, "error": "", "status": 200, "cancelled": false}


static func _quote(path: String) -> String:
	return "\"%s\"" % (path.replace("/", "\\") if OS.get_name() == "Windows" else path)


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


static func _remove_all(paths: Array) -> void:
	for path in paths:
		if FileAccess.file_exists(str(path)):
			DirAccess.remove_absolute(str(path))


## Ends the run and the Claude Code process under it (on Windows the whole tree).
static func _kill_cli(pid: int) -> void:
	if OS.get_name() == "Windows":
		OS.execute("taskkill", ["/PID", str(pid), "/T", "/F"], [], true)
	elif OS.is_process_running(pid):
		OS.kill(pid)


## One question. Returns {ok, text, error, status, cancelled}. `model` / `api_key` default to the settings. Never throws: a
## problem comes back as ok = false with a readable `error`.
func ask(system_prompt: String, user_prompt: String, max_tokens: int = 1024, model: String = "", api_key: String = "") -> Dictionary:
	if _busy:
		return _failure("Another request is still running.")
	_busy = true
	_cancelled = false
	var answer: Dictionary
	if PlayerSettings.ai_provider == "claude_code" and api_key == "":
		answer = await _ask_cli(system_prompt, user_prompt, model)
	else:
		answer = await _ask_api(system_prompt, user_prompt, max_tokens, model, api_key)
	_busy = false
	return answer


func _ask_api(system_prompt: String, user_prompt: String, max_tokens: int, model: String, api_key: String) -> Dictionary:
	var key: String = (api_key if api_key != "" else PlayerSettings.ai_api_key).strip_edges()
	if key == "":
		return _failure("There is no API key - add one in Options.")
	var chosen: String = model if model != "" else PlayerSettings.ai_model
	var body := {
		"model": chosen if chosen != "" else DEFAULT_MODEL,
		"max_tokens": max_tokens,
		"messages": [{"role": "user", "content": user_prompt}],
	}
	if system_prompt != "":
		body["system"] = system_prompt
	var headers := PackedStringArray([
		"content-type: application/json",
		"x-api-key: " + key,
		"anthropic-version: " + API_VERSION,
	])
	_http = HTTPRequest.new()
	_http.use_threads = false
	_http.timeout = timeout_sec
	add_child(_http)
	_cancelled = false
	var result := {"done": false, "status": 0, "code": 0, "body": PackedByteArray()}
	_http.request_completed.connect(func(status: int, code: int, _headers: PackedStringArray, data: PackedByteArray):
		result["status"] = status
		result["code"] = code
		result["body"] = data
		result["done"] = true
	)
	if _http.request(api_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		_release()
		return _failure("Couldn't start the request.")
	while not result["done"] and not _cancelled:
		await get_tree().create_timer(0.1).timeout
	_release()
	if _cancelled and not result["done"]:
		var cancelled := _failure("Cancelled.")
		cancelled["cancelled"] = true
		return cancelled
	return _read_answer(int(result["status"]), int(result["code"]), result["body"])


func _release() -> void:
	if _http != null:
		_http.queue_free()
		_http = null


func _exit_tree() -> void:
	if _http != null:
		_http.cancel_request()


## Turns the HTTP answer into {ok, text, error, status}.
static func _read_answer(net_status: int, code: int, data: PackedByteArray) -> Dictionary:
	if net_status != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "text": "", "error": "No connection to the AI service (network error %d)." % net_status, "status": 0, "cancelled": false}
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	if code != 200:
		var detail := ""
		if typeof(parsed) == TYPE_DICTIONARY and typeof((parsed as Dictionary).get("error")) == TYPE_DICTIONARY:
			detail = str(((parsed as Dictionary)["error"] as Dictionary).get("message", ""))
		var message := "The AI service refused the request (HTTP %d)." % code
		match code:
			401:
				message = "The API key was not accepted - check it in Options."
			403:
				message = "This API key isn't allowed to do that."
			429:
				message = "Too many requests or no credit left - wait a moment or check your account."
			413:
				message = "The text is too long to send."
			500, 502, 503, 529:
				message = "The AI service is busy or down right now - try again in a minute."
		if detail != "" and code != 401:
			message += " (%s)" % detail
		return {"ok": false, "text": "", "error": message, "status": code, "cancelled": false}
	if typeof(parsed) != TYPE_DICTIONARY or typeof((parsed as Dictionary).get("content")) != TYPE_ARRAY:
		return {"ok": false, "text": "", "error": "The AI service answered something unexpected.", "status": code, "cancelled": false}
	var pieces: Array[String] = []
	for block in (parsed as Dictionary)["content"]:
		if typeof(block) == TYPE_DICTIONARY and (block as Dictionary).get("type", "") == "text":
			pieces.append(str((block as Dictionary).get("text", "")))
	var text := "".join(pieces)
	if text.strip_edges() == "":
		return {"ok": false, "text": "", "error": "The AI service sent an empty answer.", "status": code, "cancelled": false}
	return {"ok": true, "text": text, "error": "", "status": code, "cancelled": false}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "text": "", "error": message, "status": 0, "cancelled": false}
