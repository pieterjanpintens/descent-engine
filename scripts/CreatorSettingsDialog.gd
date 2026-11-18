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
var _table_check: CheckBox
var _preset_option: OptionButton
var _width_spin: SpinBox
var _depth_spin: SpinBox
var _square_spin: SpinBox


func _ready() -> void:
	title = "Editor Settings"
	size = Vector2i(440, 540)
	unresizable = true
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

	root.add_child(HSeparator.new())

	# the real table (TableAreaOverlay): how big the table you play on is, and one tile square on it
	var table_label := Label.new()
	table_label.text = "Table size (shown around the map in the editor):"
	root.add_child(table_label)
	_table_check = CheckBox.new()
	_table_check.text = "Show the table area (View > Table Area)"
	root.add_child(_table_check)
	var preset_row := HBoxContainer.new()
	root.add_child(preset_row)
	var preset_label := Label.new()
	preset_label.text = "Table:"
	preset_row.add_child(preset_label)
	_preset_option = OptionButton.new()
	for preset: Array in CreatorSettings.TABLE_PRESETS:
		_preset_option.add_item("%s (%d x %d cm)" % [preset[0], preset[1], preset[2]])
	_preset_option.add_item("Custom")
	_preset_option.item_selected.connect(_on_preset_selected)
	preset_row.add_child(_preset_option)
	_width_spin = _add_spin_row(root, "Width (cm):")
	_depth_spin = _add_spin_row(root, "Depth (cm):")
	for spin: SpinBox in [_width_spin, _depth_spin]:
		spin.max_value = 1000
		spin.value_changed.connect(func(_v: float): _sync_preset())
	_square_spin = _add_spin_row(root, "One tile square on the table (cm):")
	_square_spin.min_value = 0.5
	_square_spin.max_value = 20
	_square_spin.step = 0.1

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
	_table_check.button_pressed = CreatorSettings.table_overlay
	_width_spin.set_value_no_signal(CreatorSettings.table_width_cm)
	_depth_spin.set_value_no_signal(CreatorSettings.table_depth_cm)
	_square_spin.value = CreatorSettings.square_cm
	_sync_preset()
	popup_centered_clamped(size, 0.9)


## Picking a preset fills in its width and depth.
func _on_preset_selected(index: int) -> void:
	if index < CreatorSettings.TABLE_PRESETS.size():
		_width_spin.set_value_no_signal(CreatorSettings.TABLE_PRESETS[index][1])
		_depth_spin.set_value_no_signal(CreatorSettings.TABLE_PRESETS[index][2])


## The preset picker shows the preset the width and depth match, else Custom.
func _sync_preset() -> void:
	var index := CreatorSettings.TABLE_PRESETS.size()
	for i in CreatorSettings.TABLE_PRESETS.size():
		var preset: Array = CreatorSettings.TABLE_PRESETS[i]
		if is_equal_approx(_width_spin.value, preset[1]) and is_equal_approx(_depth_spin.value, preset[2]):
			index = i
	_preset_option.select(index)


func _on_save_pressed() -> void:
	CreatorSettings.enabled = _enabled_check.button_pressed
	CreatorSettings.backup_location = _location_edit.text.strip_edges()
	CreatorSettings.copies = int(_copies_spin.value)
	CreatorSettings.save_interval_minutes = int(_interval_spin.value)
	CreatorSettings.checkpoint_copies = int(_checkpoint_copies_spin.value)
	CreatorSettings.checkpoint_interval_minutes = int(_checkpoint_interval_spin.value)
	CreatorSettings.table_overlay = _table_check.button_pressed
	CreatorSettings.table_width_cm = _width_spin.value
	CreatorSettings.table_depth_cm = _depth_spin.value
	CreatorSettings.square_cm = _square_spin.value
	CreatorSettings.save_settings()
	hide()
