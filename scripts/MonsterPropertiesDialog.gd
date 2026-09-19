class_name MonsterPropertiesDialog
extends Window

## Edits ONE MonsterTemplate's properties (name, hitpoints, level - more will
## follow, which is why this is its own dialog rather than inline widgets in
## the spawn-monsters list). Opened from the "Properties…" button on a row of
## the SPAWN_MONSTERS effect's monster list (ObjectivesDialog/
## PropActionsDialog). One instance is built by the opener and reused via
## open_for().
##
## Every edit is applied through `commit_field`, the opener's own undo-tracked
## `_commit_field(label, mutate)`, then `on_changed` is called so the opener
## can refresh whatever summary it shows.

var commit_field: Callable  ## (label: String, mutate: Callable) -> void
var on_changed: Callable  ## () -> void

var _template: MonsterTemplate
var _suppress: bool = false
var _title_label: Label
var _name_edit: LineEdit
var _hp_spin: SpinBox
var _level_spin: SpinBox


func _ready() -> void:
	title = "Monster Properties"
	size = Vector2i(320, 220)
	close_requested.connect(hide)
	visible = false

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	_title_label = Label.new()
	vbox.add_child(_title_label)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name (blank = generic type name)"
	_name_edit.text_submitted.connect(func(_t: String): _commit_name())
	_name_edit.focus_exited.connect(_commit_name)
	vbox.add_child(_row("Name:", _name_edit))

	_hp_spin = _make_spin()
	_hp_spin.value_changed.connect(func(v: float):
		if _suppress or _template == null:
			return
		var template := _template
		commit_field.call("Edit monster hitpoints", func(): template.hitpoints = int(v))
		on_changed.call()
	)
	vbox.add_child(_row("Hitpoints:", _hp_spin))

	_level_spin = _make_spin()
	_level_spin.value_changed.connect(func(v: float):
		if _suppress or _template == null:
			return
		var template := _template
		commit_field.call("Edit monster level", func(): template.level = int(v))
		on_changed.call()
	)
	vbox.add_child(_row("Level:", _level_spin))


func open_for(template: MonsterTemplate) -> void:
	_template = template
	_suppress = true
	_title_label.text = "Type: %s" % MonsterDisplay.find_monster(template.folder).get("name", template.folder)
	_name_edit.text = template.custom_name
	_hp_spin.value = template.hitpoints
	_level_spin.value = template.level
	_suppress = false
	popup_centered()


func _commit_name() -> void:
	if _suppress or _template == null:
		return
	var new_name := _name_edit.text.strip_edges()
	if new_name == _template.custom_name:
		return
	var template := _template
	commit_field.call("Edit monster name", func(): template.custom_name = new_name)
	on_changed.call()


func _make_spin() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 9999
	spin.step = 1
	return spin


func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(80, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row
