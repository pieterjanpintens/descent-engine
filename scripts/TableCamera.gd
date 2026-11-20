class_name TableCamera
extends Node

## The table camera: an Android phone in a holder behind the table, running the Ascent Camera app (its own repository,
## github.com/pieterjanpintens/ascent-camera). The phone keeps its screen off and its camera closed; when we ask, it takes
## ONE photo and sends it back. Plain HTTP on the local network (port 8765), protected by the pairing code the app shows:
##   GET /status -> {"app":"ascent-camera","protocol":1,"version":"...","device":"..."}
##   GET /photo  -> image/jpeg, header X-Rotation (degrees clockwise to turn it upright for a phone held in portrait)
## Both need the header X-Key: <pairing code>. The address and code live in PlayerSettings (Options > Table camera).
##
## Add it to the tree, then `await check()` or `await take_photo()`. One request at a time.

const DEFAULT_PORT := 8765
const PROTOCOL := 1
const STATUS_TIMEOUT := 6.0
const PHOTO_TIMEOUT := 45.0
const MAX_PHOTO_BYTES := 40 * 1024 * 1024
const MAX_STATUS_BYTES := 64 * 1024

var _busy := false


## "http://host:port" for what the player typed ("192.168.0.19", "192.168.0.19:8765", "http://..."), or "" when it is
## not a usable address. Only a plain host name or IPv4 address is accepted.
static func base_url(address: String) -> String:
	var text := address.strip_edges()
	for prefix in ["http://", "https://"]:
		if text.begins_with(prefix):
			text = text.substr(prefix.length())
	text = text.trim_suffix("/")
	if text == "":
		return ""
	var host := text
	var port := DEFAULT_PORT
	var colon := text.rfind(":")
	if colon > 0:
		host = text.substr(0, colon)
		var port_text := text.substr(colon + 1)
		if not port_text.is_valid_int():
			return ""
		port = int(port_text)
	if port < 1 or port > 65535:
		return ""
	if RegEx.create_from_string("^[A-Za-z0-9.-]+$").search(host) == null:
		return ""
	return "http://%s:%d" % [host, port]


## True when the feature is switched on (FeatureFlags.TABLE_CAMERA) and an address and a pairing code have been filled in (says
## nothing about whether the phone answers). Off = every camera step of a mission is skipped.
static func is_configured() -> bool:
	return FeatureFlags.enabled(FeatureFlags.TABLE_CAMERA) and base_url(PlayerSettings.table_camera_address) != "" and PlayerSettings.table_camera_code.strip_edges() != ""


func is_busy() -> bool:
	return _busy


## Asks the phone who it is: {ok, device, version} or {ok = false, error}.
func check() -> Dictionary:
	var answer := await _request("/status", STATUS_TIMEOUT, MAX_STATUS_BYTES)
	if not answer["ok"]:
		return answer
	var data: Variant = JSON.parse_string((answer["body"] as PackedByteArray).get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or str(data.get("app", "")) != "ascent-camera":
		return _fail(tr("Something answered at that address, but it is not the Ascent Camera app."))
	if int(data.get("protocol", 0)) != PROTOCOL:
		return _fail(tr("This version of the Ascent Camera app does not fit this version of Ascent. Update both."))
	return {"ok": true, "device": str(data.get("device", "")), "version": str(data.get("version", ""))}


## Takes one photo: {ok, image (upright), seconds} or {ok = false, error}.
func take_photo() -> Dictionary:
	var started := Time.get_ticks_msec()
	var answer := await _request("/photo", PHOTO_TIMEOUT, MAX_PHOTO_BYTES)
	if not answer["ok"]:
		return answer
	var image := Image.new()
	if image.load_jpg_from_buffer(answer["body"]) != OK or image.is_empty():
		return _fail(tr("The camera sent something that is not a photo."))
	var turns := posmod(int(str((answer["headers"] as Dictionary).get("x-rotation", "0"))) / 90, 4)
	for i in turns:
		image.rotate_90(CLOCKWISE)
	return {"ok": true, "image": image, "seconds": (Time.get_ticks_msec() - started) / 1000.0}


## One GET with the pairing code: {ok, body, headers (lower-case names)} or {ok = false, error}.
func _request(path: String, timeout: float, max_bytes: int) -> Dictionary:
	if _busy:
		return _fail(tr("The camera is still busy with the previous request."))
	var base := base_url(PlayerSettings.table_camera_address)
	if base == "":
		return _fail(tr("Fill in the address the app shows, for example 192.168.0.19:8765."))
	var code := PlayerSettings.table_camera_code.strip_edges()
	if code == "":
		return _fail(tr("Fill in the pairing code the app shows."))
	_busy = true
	var request := HTTPRequest.new()
	request.use_threads = false  # a threaded request on a dead connection cannot be cancelled (see Downloader)
	request.timeout = timeout
	request.body_size_limit = max_bytes
	request.download_chunk_size = 1 << 20
	add_child(request)
	if request.request(base + path, ["X-Key: " + code]) != OK:
		request.queue_free()
		_busy = false
		return _fail(tr("Could not send the request to the camera."))
	var result: Array = await request.request_completed
	request.queue_free()
	_busy = false
	var status: int = result[0]
	var http_code: int = result[1]
	var body: PackedByteArray = result[3]
	match status:
		HTTPRequest.RESULT_SUCCESS:
			pass
		HTTPRequest.RESULT_TIMEOUT:
			return _fail(tr("The camera did not answer in time. Is the camera started in the app, and is the phone on the same network as this computer?"))
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR:
			return _fail(tr("Could not reach the camera at %s. Is the camera started in the app, and is the phone on the same network as this computer?") % base.trim_prefix("http://"))
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return _fail(tr("The camera sent a photo that is too big."))
		_:
			return _fail(tr("The connection to the camera failed."))
	match http_code:
		200:
			pass
		401:
			return _fail(tr("The camera refused the pairing code. Type the code the app shows."))
		503:
			return _fail(tr("The camera is still taking another photo. Try again in a moment."))
		_:
			var reason := body.get_string_from_utf8().left(200) if body.size() < 4096 else ""
			return _fail((tr("The camera answered with an error (%d).") % http_code) + ((" " + reason) if reason != "" else ""))
	var headers := {}
	for line in result[2] as PackedStringArray:
		var colon := line.find(":")
		if colon > 0:
			headers[line.substr(0, colon).strip_edges().to_lower()] = line.substr(colon + 1).strip_edges()
	return {"ok": true, "body": body, "headers": headers}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
