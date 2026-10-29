class_name PublishDialog
extends AcceptDialog

## "Publish to the community" for one package file: signs the player in with GitHub when needed (a code to type on
## github.com - see GitHubClient) and submits the package as a pull request (CommunityPublisher). Opened by the export
## dialog after a package is written, and by the Community page for any package file. `open_for(path)`.

var _path := ""
var _busy := false
var _client: CommunityPublisher

var _summary_label: Label
var _account_label: Label
var _code_label: Label
var _status_label: Label
var _sign_in_button: Button
var _open_site_button: Button
var _publish_button: Button
var _sign_out_button: Button
var _link_button: Button
var _verification_uri := ""
var _result_url := ""


func _ready() -> void:
	title = "Publish to the community"
	ok_button_text = "Close"
	min_size = Vector2i(540, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	_summary_label = _label(box, 15)
	var explanation := _label(box, 13)
	explanation.modulate = Color(1, 1, 1, 0.75)
	explanation.text = "Publishing sends this package to the community list as a request under your GitHub account. It is checked automatically and appears in everyone's Community page once it is approved. Players never need an account - only people who share do."
	box.add_child(HSeparator.new())

	_account_label = _label(box, 14)
	_code_label = _label(box, 30)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_sign_in_button = _button(row, "Sign in with GitHub", _on_sign_in_pressed)
	_open_site_button = _button(row, "Open github.com", func(): OS.shell_open(_verification_uri))
	_publish_button = _button(row, "Publish", _on_publish_pressed)
	_link_button = _button(row, "Open the request", func(): OS.shell_open(_result_url))
	_sign_out_button = _button(row, "Sign out", _on_sign_out_pressed)
	_status_label = _label(box, 13)

	_client = CommunityPublisher.new()
	add_child(_client)
	_client.progress.connect(func(text: String): _status_label.text = text)
	visibility_changed.connect(func():
		if not visible:
			_client.cancel())


func _label(parent: Container, font_size: int) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 0)
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Container, text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	return button


## Shows the dialog for the package file at `path` (it is read and checked first).
func open_for(path: String) -> void:
	_path = path
	_result_url = ""
	_code_label.text = ""
	_status_label.text = ""
	var package := SharePackage.read(path)
	if package["ok"]:
		var manifest: Dictionary = package["manifest"]
		_summary_label.text = "%s %s - a %s%s\n%s" % [str(manifest["name"]), str(manifest["version"]), str(manifest["type"]),
				" by " + str(manifest["author"]) if str(manifest.get("author", "")) != "" else "", path.get_file()]
	else:
		_summary_label.text = tr("%s\nThis file is not a valid package: %s") % [path.get_file(), "; ".join((package["errors"] as Array).slice(0, 3))]
		_path = ""
	_refresh()
	popup_centered()


func _refresh() -> void:
	var account := GitHubClient.saved_account()
	var signed_in := not account.is_empty()
	var waiting_for_code := _code_label.text != ""
	if not GitHubClient.is_configured() and _client.client_id == "":
		_account_label.text = "Publishing from the app is not switched on in this version. Share the package file itself, or see the community repository on GitHub."
	elif signed_in:
		_account_label.text = tr("Signed in to GitHub as %s.") % str(account.get("login", ""))
	elif waiting_for_code:
		_account_label.text = "Type this code on github.com to sign in (it is copied to your clipboard):"
	else:
		_account_label.text = "You are not signed in. Signing in asks GitHub for permission to write to your public repositories - the app only uses it for your copy of the community repository."
	var can_use := _client.client_id != ""
	_sign_in_button.visible = can_use and not signed_in and not waiting_for_code
	_sign_in_button.disabled = _busy
	_open_site_button.visible = waiting_for_code
	_code_label.visible = waiting_for_code
	_publish_button.visible = can_use and signed_in and _result_url == ""
	_publish_button.disabled = _busy or _path == ""
	_link_button.visible = _result_url != ""
	_sign_out_button.visible = signed_in
	_sign_out_button.disabled = _busy
	reset_size()


func _on_sign_in_pressed() -> void:
	_busy = true
	_status_label.text = "Asking GitHub for a code..."
	_refresh()
	var started: Dictionary = await _client.begin_sign_in()
	if not started["ok"]:
		_busy = false
		_status_label.text = str(started["error"])
		_refresh()
		return
	_verification_uri = str(started["verification_uri"])
	_code_label.text = str(started["user_code"])
	DisplayServer.clipboard_set(_code_label.text)
	_status_label.text = "Waiting for you to enter the code on github.com..."
	_refresh()
	OS.shell_open(_verification_uri)
	var finished: Dictionary = await _client.finish_sign_in(started)
	_busy = false
	_code_label.text = ""
	_status_label.text = "Signed in." if finished["ok"] else str(finished["error"])
	_refresh()


func _on_publish_pressed() -> void:
	_busy = true
	_refresh()
	var result: Dictionary = await _client.publish(_path)
	_busy = false
	if result["ok"]:
		_result_url = str(result["url"])
		_status_label.text = tr("Submitted. It shows up in the Community page once it is approved.\n%s") % _result_url
	_refresh()


func _on_sign_out_pressed() -> void:
	GitHubClient.sign_out()
	_status_label.text = "Signed out. To withdraw the permission completely: github.com > Settings > Applications > Authorized OAuth Apps."
	_refresh()
