class_name UpdateDialog
extends ConfirmationDialog

## "A newer version is available": what is new, and a one-click install (AppUpdater). The new version is downloaded, checked
## against the release's checksum list, unpacked next to the app and swapped in by a small helper script once the app has
## closed; the previous files are kept in user data as a backup. An install that can't update itself (a development build,
## a read-only folder) only gets the release page opened.

const MAX_NOTES_CHARS := 1800

var updater: AppUpdater
var _release: Dictionary = {}
var _notes: Label
var _status: Label
var _page_button: Button
var _busy := false
## Test seam: don't quit the app after the helper was started.
var quit_after_apply := true


func _ready() -> void:
	title = "App update"
	ok_button_text = "Install and restart"
	cancel_button_text = "Later"
	min_size = Vector2i(560, 0)
	updater = AppUpdater.new()
	add_child(updater)
	updater.progress.connect(_on_progress)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(520, 0)
	box.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 180)
	box.add_child(scroll)
	_notes = Label.new()
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notes.custom_minimum_size = Vector2(500, 0)
	_notes.modulate = Color(1, 1, 1, 0.8)
	scroll.add_child(_notes)
	_page_button = add_button("Release page", false, "page")
	custom_action.connect(_on_custom_action)
	confirmed.connect(_on_confirmed)


## `release` = a result of AppUpdater.check() that is newer.
func open_for(release: Dictionary) -> void:
	_release = release
	_busy = false
	var blocked := str(release.get("blocked", ""))
	var current := AppUpdater.current_version()
	_status.text = "Version %s is available (you have %s)." % [str(release["tag"]).trim_prefix("v"), current]
	if blocked != "":
		_status.text += "\n\nThe app can't update itself here: %s. Download it from the release page." % blocked
	var notes := str(release.get("notes", "")).strip_edges()
	_notes.text = notes.substr(0, MAX_NOTES_CHARS) + ("…" if notes.length() > MAX_NOTES_CHARS else "")
	get_ok_button().disabled = blocked != ""
	get_ok_button().visible = blocked == ""
	get_cancel_button().disabled = false
	popup_centered()


func _on_progress(text: String) -> void:
	if _busy:
		_status.text = text


func _on_custom_action(action: StringName) -> void:
	if action == &"page" and str(_release.get("page", "")).begins_with("https://"):
		OS.shell_open(str(_release["page"]))


func _on_confirmed() -> void:
	if _busy:
		return
	_busy = true
	# the dialog stays open while it works
	popup_centered()
	get_ok_button().disabled = true
	get_cancel_button().disabled = true
	_status.text = "Downloading the update…"
	var staged := await updater.download_and_stage(_release)
	if not staged["ok"]:
		_finish_failed(str(staged["error"]))
		return
	_status.text = "Installing… the app closes and starts again by itself."
	if not updater.apply(str(staged["staged"])):
		_finish_failed("The update could not be started.")
		return
	if quit_after_apply:
		get_tree().quit()


func _finish_failed(message: String) -> void:
	_busy = false
	_status.text = "%s\n\nNothing was changed. You can try again, or download the update from the release page." % message
	get_ok_button().disabled = false
	get_cancel_button().disabled = false
	popup_centered()
