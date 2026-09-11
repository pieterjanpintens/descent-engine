class_name PropertiesDialog
extends Window

## Popup editor for InteractableEntry.props - the free-form custom
## property dictionary (only "interactible" is a well-known key today,
## see that script's own doc comment; anything else is whatever the
## designer wants - linked_region, locked, loot_table, ...). Requested
## 2026-09-10 as a POPUP rather than embedded inline in the Inspector - a
## dynamic add/remove/type-aware list would get cramped in the
## SidePanel's 260px width otherwise. Opened via
## CreatorPropertiesPanel.gd's "Custom Properties…" button - one instance,
## created there in code (not a .tscn node - nothing here needs NodePath
## wiring, `operation_history`/`layered_map` are just assigned directly
## after `PropertiesDialog.new()`) and reused across selections via
## open_for(), same as how CreatorOutline.gd reuses one PopupMenu for its
## context menu rather than building a fresh one per right-click.
##
## Adding a new key opens a SECOND, nested dialog (_open_add_dialog())
## asking for name/type/default value up front, rather than an inline
## "type a key, pick a type" row in this same window - keeps this main
## list simple (existing rows just show name + a type-appropriate value
## widget + a remove button) and the add flow focused on the one thing it
## actually needs to ask.
##
## Each existing row's value widget is chosen from the property's CURRENT
## Variant type (typeof()) - a CheckBox for bool, SpinBox for int/float,
## LineEdit otherwise - so an already-typed key like "interactible"
## (bool) can't accidentally get flattened into a string by editing it
## here. A brand new key's type is fixed once, at Add time, via the
## nested dialog's type dropdown.

var operation_history: OperationHistory
var layered_map: LayeredMap

enum _PropType { STRING, BOOL, INT, FLOAT }

var _entry: InteractableEntry
var _rows_container: VBoxContainer
var _empty_label: Label

var _add_dialog: ConfirmationDialog
var _add_name_edit: LineEdit
var _add_type_option: OptionButton
var _add_value_string: LineEdit
var _add_value_bool: CheckBox
var _add_value_int: SpinBox
var _add_value_float: SpinBox


func _ready() -> void:
	title = "Properties"
	size = Vector2i(360, 320)
	close_requested.connect(hide)
	visible = false

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	add_child(root)

	_empty_label = Label.new()
	_empty_label.text = "No custom properties yet."
	root.add_child(_empty_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_container)

	var add_button := Button.new()
	add_button.text = "Add Property…"
	add_button.pressed.connect(_open_add_dialog)
	root.add_child(add_button)

	_build_add_dialog()


## Public - CreatorPropertiesPanel.gd calls this from its "Custom
## Properties…" button.
func open_for(entry: InteractableEntry) -> void:
	_entry = entry
	_rebuild_rows()
	popup_centered()


func _rebuild_rows() -> void:
	for child in _rows_container.get_children():
		child.queue_free()

	if _entry == null:
		return

	var keys := _entry.props.keys()
	keys.sort()
	_empty_label.visible = keys.is_empty()
	for key in keys:
		_rows_container.add_child(_build_row(key, _entry.props[key]))


func _build_row(key: String, value: Variant) -> Control:
	var row := HBoxContainer.new()

	var key_label := Label.new()
	key_label.text = key
	key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key_label)

	match typeof(value):
		TYPE_BOOL:
			var check := CheckBox.new()
			check.button_pressed = value
			check.toggled.connect(func(pressed: bool): _set_value(key, pressed))
			row.add_child(check)
		TYPE_INT:
			var spin := SpinBox.new()
			spin.min_value = -999999
			spin.max_value = 999999
			spin.step = 1
			spin.value = value
			spin.value_changed.connect(func(new_value: float): _set_value(key, int(new_value)))
			row.add_child(spin)
		TYPE_FLOAT:
			var spin := SpinBox.new()
			spin.min_value = -999999
			spin.max_value = 999999
			spin.step = 0.01
			spin.value = value
			spin.value_changed.connect(func(new_value: float): _set_value(key, new_value))
			row.add_child(spin)
		_:
			var edit := LineEdit.new()
			edit.text = str(value)
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# Commits on Enter/focus-lost, not per keystroke - same
			# reasoning as every other text field in this Creator. Two
			# separate lambdas (not one .bind()'d callable) since
			# text_submitted and focus_exited pass different argument
			# counts - binding extra args onto one shared callable would
			# shift positionally and land in the wrong parameters.
			var commit := func(): _set_value(key, edit.text)
			edit.text_submitted.connect(func(_new_text): commit.call())
			edit.focus_exited.connect(commit)
			row.add_child(edit)

	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.tooltip_text = "Remove property"
	remove_button.pressed.connect(func(): _remove(key))
	row.add_child(remove_button)

	return row


func _set_value(key: String, value: Variant) -> void:
	if _entry == null or _entry.props.get(key) == value:
		return
	var entry := _entry
	operation_history.record("Set property", func():
		entry.props[key] = value
	)
	layered_map.notify_objects_changed()


func _remove(key: String) -> void:
	if _entry == null:
		return
	var entry := _entry
	operation_history.record("Remove property", func():
		entry.props.erase(key)
	)
	layered_map.notify_objects_changed()
	_rebuild_rows()


## ---- Add Property dialog - name + type + default value ----

func _build_add_dialog() -> void:
	_add_dialog = ConfirmationDialog.new()
	_add_dialog.title = "Add Property"
	_add_dialog.confirmed.connect(_on_add_confirmed)
	add_child(_add_dialog)

	var form := VBoxContainer.new()
	form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	form.offset_left = 8
	form.offset_top = 8
	form.offset_right = -8
	form.offset_bottom = -40  # leave room for the dialog's own OK/Cancel row
	_add_dialog.add_child(form)

	var name_row := HBoxContainer.new()
	form.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "Name:"
	name_row.add_child(name_label)
	_add_name_edit = LineEdit.new()
	_add_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_add_name_edit)

	var type_row := HBoxContainer.new()
	form.add_child(type_row)
	var type_label := Label.new()
	type_label.text = "Type:"
	type_row.add_child(type_label)
	_add_type_option = OptionButton.new()
	_add_type_option.add_item("String", _PropType.STRING)
	_add_type_option.add_item("Bool", _PropType.BOOL)
	_add_type_option.add_item("Int", _PropType.INT)
	_add_type_option.add_item("Float", _PropType.FLOAT)
	_add_type_option.item_selected.connect(_on_add_type_selected)
	type_row.add_child(_add_type_option)

	var value_row := HBoxContainer.new()
	form.add_child(value_row)
	var value_label := Label.new()
	value_label.text = "Default:"
	value_row.add_child(value_label)

	_add_value_string = LineEdit.new()
	_add_value_string.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_row.add_child(_add_value_string)

	_add_value_bool = CheckBox.new()
	value_row.add_child(_add_value_bool)

	_add_value_int = SpinBox.new()
	_add_value_int.min_value = -999999
	_add_value_int.max_value = 999999
	_add_value_int.step = 1
	value_row.add_child(_add_value_int)

	_add_value_float = SpinBox.new()
	_add_value_float.min_value = -999999
	_add_value_float.max_value = 999999
	_add_value_float.step = 0.01
	value_row.add_child(_add_value_float)


func _open_add_dialog() -> void:
	_add_name_edit.text = ""
	_add_type_option.select(0)
	_add_value_string.text = ""
	_add_value_bool.button_pressed = false
	_add_value_int.value = 0
	_add_value_float.value = 0.0
	_on_add_type_selected(0)
	_add_dialog.popup_centered()


func _on_add_type_selected(_index: int) -> void:
	var type: int = _add_type_option.get_selected_id()
	_add_value_string.visible = type == _PropType.STRING
	_add_value_bool.visible = type == _PropType.BOOL
	_add_value_int.visible = type == _PropType.INT
	_add_value_float.visible = type == _PropType.FLOAT


## Silently no-ops on a blank or already-used key rather than raising a
## popup-on-a-popup warning dialog - the ConfirmationDialog already closed
## by the time this fires (OK always hides it first), so the failure mode
## is just "nothing got added, try Add Property… again", not data loss.
func _on_add_confirmed() -> void:
	if _entry == null:
		return
	var key := _add_name_edit.text.strip_edges()
	if key == "" or _entry.props.has(key):
		push_warning("PropertiesDialog: '%s' is blank or already exists - not added" % key)
		return

	var value: Variant
	match _add_type_option.get_selected_id():
		_PropType.BOOL:
			value = _add_value_bool.button_pressed
		_PropType.INT:
			value = int(_add_value_int.value)
		_PropType.FLOAT:
			value = _add_value_float.value
		_:
			value = _add_value_string.text

	var entry := _entry
	operation_history.record("Add property", func():
		entry.props[key] = value
	)
	layered_map.notify_objects_changed()
	_rebuild_rows()
