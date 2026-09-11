class_name CreatorSettingsDialog
extends Window

## Settings form for the CreatorSettings autoload (autosave/backup,
## requested 2026-09-10) - opened from CreatorSaveLoad.gd's File menu
## ("Settings…"). Same pattern as PropertiesDialog.gd: built in code, one
## instance, reused via open()/popup_centered(). Reads current
## CreatorSettings values into the form on open, writes them back (and
## calls CreatorSettings.save_settings(), which persists to disk and emits
## settings_changed - CreatorAutosave.gd is the one thing currently
## listening) on Save. Closing via the window's own X button (not Save)
## discards whatever was typed, same as any other unsaved form.

var _enabled_check: CheckBox
var _location_edit: LineEdit
var _copies_spin: SpinBox
var _interval_spin: SpinBox
var _checkpoint_copies_spin: SpinBox
var _checkpoint_interval_spin: SpinBox


func _ready() -> void:
	title = "Autosave Settings"
	size = Vector2i(400, 300)
	close_requested.connect(hide)
	visible = false

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	add_child(root)

	_enabled_check = CheckBox.new()
	_enabled_check.text = "Enable autosave"
	root.add_child(_enabled_check)

	var location_row := HBoxContainer.new()
	root.add_child(location_row)
	var location_label := Label.new()
	location_label.text = "Backup location:"
	location_row.add_child(location_label)
	_location_edit = LineEdit.new()
	_location_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	location_row.add_child(_location_edit)

	root.add_child(HSeparator.new())

	var recent_label := Label.new()
	recent_label.text = "Recent (frequent, shallow history):"
	root.add_child(recent_label)
	_copies_spin = _add_spin_row(root, "Copies to keep:")
	_interval_spin = _add_spin_row(root, "Save every (minutes):")

	root.add_child(HSeparator.new())

	var checkpoint_label := Label.new()
	checkpoint_label.text = "Checkpoints (infrequent, deeper history):"
	root.add_child(checkpoint_label)
	_checkpoint_copies_spin = _add_spin_row(root, "Copies to keep:")
	_checkpoint_interval_spin = _add_spin_row(root, "Save every (minutes):")

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	root.add_child(save_button)


func _add_spin_row(parent: VBoxContainer, label_text: String) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = 1  # matches the request's own "int > 0" constraint on every count/interval field
	spin.max_value = 999
	spin.step = 1
	row.add_child(spin)
	return spin


## Public - CreatorSaveLoad.gd calls this from its "Settings…" menu item.
func open() -> void:
	_enabled_check.button_pressed = CreatorSettings.enabled
	_location_edit.text = CreatorSettings.backup_location
	_copies_spin.value = CreatorSettings.copies
	_interval_spin.value = CreatorSettings.save_interval_minutes
	_checkpoint_copies_spin.value = CreatorSettings.checkpoint_copies
	_checkpoint_interval_spin.value = CreatorSettings.checkpoint_interval_minutes
	popup_centered()


func _on_save_pressed() -> void:
	CreatorSettings.enabled = _enabled_check.button_pressed
	CreatorSettings.backup_location = _location_edit.text.strip_edges()
	CreatorSettings.copies = int(_copies_spin.value)
	CreatorSettings.save_interval_minutes = int(_interval_spin.value)
	CreatorSettings.checkpoint_copies = int(_checkpoint_copies_spin.value)
	CreatorSettings.checkpoint_interval_minutes = int(_checkpoint_interval_spin.value)
	CreatorSettings.save_settings()
	hide()
