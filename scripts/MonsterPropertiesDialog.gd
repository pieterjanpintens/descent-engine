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
var _defense_spin: SpinBox
## template property name -> CheckBox per Vulnerability.Kind (index = kind)
var _vuln_boxes: Dictionary = {}


func _ready() -> void:
	title = "Monster Properties"
	size = Vector2i(400, 600)
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

	_defense_spin = _make_spin()
	_defense_spin.value_changed.connect(func(v: float):
		if _suppress or _template == null:
			return
		var template := _template
		commit_field.call("Edit monster defense", func(): template.defense = int(v))
		on_changed.call()
	)
	vbox.add_child(_row("Defense:", _defense_spin))

	_add_vulnerability_group(vbox, "Weaknesses", "weaknesses")
	_add_vulnerability_group(vbox, "Resistances", "resistances")
	_add_vulnerability_group(vbox, "Immunities", "immunities")


func open_for(template: MonsterTemplate) -> void:
	_template = template
	_suppress = true
	_title_label.text = "Type: %s" % MonsterDisplay.find_monster(template.folder).get("name", template.folder)
	_name_edit.text = template.custom_name
	_hp_spin.value = template.hitpoints
	_level_spin.value = template.level
	_defense_spin.value = template.defense
	for prop in _vuln_boxes:
		var selected: Array = template.get(prop)
		for kind in Vulnerability.all():
			(_vuln_boxes[prop][kind] as CheckBox).button_pressed = selected.has(kind)
	_suppress = false
	popup_centered()


## A titled grid of one CheckBox per Vulnerability.Kind, editing the
## template's `prop` list (weaknesses/resistances/immunities).
func _add_vulnerability_group(parent: VBoxContainer, title_text: String, prop: String) -> void:
	var title_label := Label.new()
	title_label.text = title_text + ":"
	parent.add_child(title_label)
	var grid := GridContainer.new()
	grid.columns = 3
	parent.add_child(grid)
	var boxes: Array[CheckBox] = []
	for kind in Vulnerability.all():
		var box := CheckBox.new()
		box.text = Vulnerability.display_name(kind)
		box.toggled.connect(func(_on: bool): _commit_vulnerabilities(prop))
		grid.add_child(box)
		boxes.append(box)
	_vuln_boxes[prop] = boxes


## Writes the ticked boxes of list `prop` back to the template as a NEW
## array, inside the opener's undo-tracked commit.
func _commit_vulnerabilities(prop: String) -> void:
	if _suppress or _template == null:
		return
	var chosen: Array[int] = []
	for kind in Vulnerability.all():
		if (_vuln_boxes[prop][kind] as CheckBox).button_pressed:
			chosen.append(kind)
	var template := _template
	commit_field.call("Edit monster " + prop, func(): template.set(prop, chosen))
	on_changed.call()


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
