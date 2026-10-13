class_name GitHubClient
extends Node

## Talking to GitHub for contributors (never for players, who only read public files): signing in with the "device flow" -
## the app shows a short code, the player types it on github.com, no password ever passes through the app - and plain JSON
## calls to GitHub's API with the token that gives. Used by CommunityPublisher to open a pull request on the community
## repository. Add as a child of something in the tree (it awaits timers and requests).
##
## The token is kept in user://community/github.json (plain text, like every other setting of the app); `sign_out()` deletes it.
## It can be withdrawn at any time on github.com > Settings > Applications > Authorized OAuth Apps.

## The OAuth App of this project on GitHub (github.com > Settings > Developer settings > OAuth Apps, with "Enable Device Flow"
## ticked). A client id is public by design - the device flow has no secret. "" = publishing from the app is switched off.
const CLIENT_ID := "Ov23likoWngVahiWxbg2"
## What the app asks for. GitHub has no narrower permission for "open a pull request from a fork": this one allows writing to
## the player's PUBLIC repositories. The app only ever touches their fork of the community repository.
const SCOPE := "public_repo"
const TOKEN_FILE := "user://community/github.json"

## Overridable (tests point these at a local server).
var api_base := "https://api.github.com"
var login_base := "https://github.com"
var client_id := CLIENT_ID

var _cancelled := false


static func is_configured() -> bool:
	return CLIENT_ID != ""


## {token, login} of the signed-in player, {} when nobody is signed in.
static func saved_account() -> Dictionary:
	if not FileAccess.file_exists(TOKEN_FILE):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TOKEN_FILE))
	if typeof(parsed) != TYPE_DICTIONARY or str((parsed as Dictionary).get("token", "")) == "":
		return {}
	return parsed


static func sign_out() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TOKEN_FILE))


static func _save_account(token: String, login: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TOKEN_FILE.get_base_dir()))
	var file := FileAccess.open(TOKEN_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"token": token, "login": login}))
		file.close()


## Stops a sign-in that is waiting for the player.
func cancel() -> void:
	_cancelled = true


## Step 1 of signing in: asks GitHub for a code. {ok, error, user_code, verification_uri, device_code, interval, expires_in}.
func begin_sign_in() -> Dictionary:
	_cancelled = false
	var answer := await call_json(HTTPClient.METHOD_POST, login_base + "/login/device/code", "", {"client_id": client_id, "scope": SCOPE}, true)
	var data: Dictionary = answer["data"] if typeof(answer["data"]) == TYPE_DICTIONARY else {}
	if answer["status"] != 200 or str(data.get("device_code", "")) == "":
		return {"ok": false, "error": "GitHub did not start the sign-in (%s)." % _problem(answer)}
	return {
		"ok": true, "error": "",
		"user_code": str(data.get("user_code", "")),
		"verification_uri": str(data.get("verification_uri", "https://github.com/login/device")),
		"device_code": str(data["device_code"]),
		"interval": maxi(int(data.get("interval", 5)), 1),
		"expires_in": int(data.get("expires_in", 900)),
	}


## Step 2: waits until the player has typed the code on github.com (or it expires / is refused / cancel()).
## {ok, error, login}; on success the account is saved.
func finish_sign_in(started: Dictionary) -> Dictionary:
	var interval := float(started["interval"])
	var deadline := Time.get_ticks_msec() + int(started["expires_in"]) * 1000
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(interval).timeout
		if _cancelled:
			return {"ok": false, "error": "Cancelled.", "login": ""}
		var answer := await call_json(HTTPClient.METHOD_POST, login_base + "/login/oauth/access_token", "", {
			"client_id": client_id, "device_code": started["device_code"], "grant_type": "urn:ietf:params:oauth:grant-type:device_code"}, true)
		var data: Dictionary = answer["data"] if typeof(answer["data"]) == TYPE_DICTIONARY else {}
		var token := str(data.get("access_token", ""))
		if token != "":
			var me := await call_json(HTTPClient.METHOD_GET, api_base + "/user", token)
			var login := str((me["data"] as Dictionary).get("login", "")) if typeof(me["data"]) == TYPE_DICTIONARY else ""
			if me["status"] != 200 or login == "":
				return {"ok": false, "error": "Signed in, but GitHub did not say who you are (%s)." % _problem(me), "login": ""}
			_save_account(token, login)
			return {"ok": true, "error": "", "login": login}
		match str(data.get("error", "")):
			"authorization_pending":
				pass
			"slow_down":
				interval += 5.0
			"expired_token":
				break
			"access_denied":
				return {"ok": false, "error": "The sign-in was refused on github.com.", "login": ""}
			_:
				return {"ok": false, "error": "GitHub refused the sign-in (%s)." % _problem(answer), "login": ""}
	return {"ok": false, "error": "The code expired before it was entered - try again.", "login": ""}


## One call with a JSON answer. {status (0 = no connection), data (the parsed answer, or null)}. `body` is sent as JSON, or
## - `as_form`, what GitHub's sign-in pages expect - as a web form.
func call_json(method: HTTPClient.Method, url: String, token: String, body: Variant = null, as_form := false) -> Dictionary:
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = 120.0
	add_child(http)
	var headers := PackedStringArray(["Accept: application/json", "User-Agent: Descent-Engine", "X-GitHub-Api-Version: 2022-11-28"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var text := ""
	if body != null and as_form:
		headers.append("Content-Type: application/x-www-form-urlencoded")
		var pairs: PackedStringArray = []
		for key: String in (body as Dictionary):
			pairs.append("%s=%s" % [key.uri_encode(), str((body as Dictionary)[key]).uri_encode()])
		text = "&".join(pairs)
	elif body != null:
		headers.append("Content-Type: application/json")
		text = JSON.stringify(body)
	if http.request(url, headers, method, text) != OK:
		http.queue_free()
		return {"status": 0, "data": null}
	var answer: Array = await http.request_completed
	http.queue_free()
	if answer[0] != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "data": null}
	var parsed: Variant = JSON.parse_string((answer[3] as PackedByteArray).get_string_from_utf8())
	return {"status": int(answer[1]), "data": parsed}


## A short reason for a failed call, for messages.
static func _problem(answer: Dictionary) -> String:
	if int(answer["status"]) == 0:
		return "no connection"
	var data: Variant = answer["data"]
	if typeof(data) == TYPE_DICTIONARY:
		for key in ["message", "error_description", "error"]:
			if str((data as Dictionary).get(key, "")) != "":
				return "%d: %s" % [answer["status"], str((data as Dictionary)[key])]
	return "error %d" % int(answer["status"])
