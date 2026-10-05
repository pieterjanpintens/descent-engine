class_name MonsterPropertiesDialog
extends Window

## Edits ONE MonsterTemplate (a monster a spawn effect creates). Deliberately
## small: its name, its level (the input of the templates' scaling tables), the
## required BASE template and the ADDITIVE templates - everything else about the
## monster comes from those (see MonsterArchetype), shown in a read-only preview
## of the effective values. Opened from the "Properties…" button on a row of the
## SPAWN_MONSTERS effect's monster list (ObjectivesDialog/PropActionsDialog); one
## instance is built by the opener and reused via open_for().
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
var _level_spin: SpinBox
var _base_picker: OptionButton
var _base_warning: Label
var _template_rows: VBoxContainer
var _template_picker: OptionButton
var _resolved_label: Label


func _ready() -> void:
	title = "Monster Properties"
	min_size = Vector2i(380, 300)
	close_requested.connect(hide)
	visible = false

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	_title_label = Label.new()
	vbox.add_child(_title_label)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name (blank = generic type name)"
	_name_edit.text_submitted.connect(func(_t: String): _commit_name())
	_name_edit.focus_exited.connect(_commit_name)
	vbox.add_child(_row("Name:", _name_edit))

	_level_spin = SpinBox.new()
	_level_spin.min_value = 0
	_level_spin.max_value = 9999
	_level_spin.step = 1
	_level_spin.value_changed.connect(func(v: float):
		if _suppress or _template == null:
			return
		var template := _template
		commit_field.call("Edit monster level", func(): template.level = int(v))
		_notify_changed()
	)
	vbox.add_child(_row("Level:", _level_spin))

	# The BASE template (File > Monster Templates…): every monster needs one. Attaching
	# embeds a COPY of the library entry (see MonsterArchetype).
	_base_picker = OptionButton.new()
	_base_picker.item_selected.connect(_on_base_selected)
	vbox.add_child(_row("Base template:", _base_picker))
	_base_warning = Label.new()
	_base_warning.text = "Every monster needs a base template - choose one."
	_base_warning.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	vbox.add_child(_base_warning)

	# ADDITIVE templates add to the base (extra weaknesses/immunities, +hitpoints...).
	var templates_title := Label.new()
	templates_title.text = "Additive templates:"
	vbox.add_child(templates_title)
	_template_rows = VBoxContainer.new()
	vbox.add_child(_template_rows)
	var template_add_row := HBoxContainer.new()
	_template_picker = OptionButton.new()
	_template_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	template_add_row.add_child(_template_picker)
	var template_add := Button.new()
	template_add.text = "Add template"
	template_add.pressed.connect(_on_add_template_pressed)
	template_add_row.add_child(template_add)
	vbox.add_child(template_add_row)

	# What the monster will actually be once its templates are applied (read-only).
	var resolved_title := Label.new()
	resolved_title.text = "Effective (with templates)"
	resolved_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(resolved_title)
	_resolved_label = Label.new()
	_resolved_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_resolved_label)


func open_for(template: MonsterTemplate) -> void:
	_template = template
	_suppress = true
	_title_label.text = "Type: %s" % MonsterDisplay.find_monster(template.folder).get("name", template.folder)
	_name_edit.text = template.custom_name
	_level_spin.value = template.level
	_refresh_base_picker()
	_refresh_template_picker()
	_rebuild_template_rows()
	_refresh_resolved()
	_suppress = false
	popup_centered_clamped(Vector2i(440, 560), 0.9)  # never taller than the game window (the form scrolls)


func _notify_changed() -> void:
	on_changed.call()
	_refresh_resolved()


func _refresh_resolved() -> void:
	if _template != null and _resolved_label != null:
		_resolved_label.text = _template.resolved_summary()


func _commit_name() -> void:
	if _suppress or _template == null:
		return
	var new_name := _name_edit.text.strip_edges()
	if new_name == _template.custom_name:
		return
	var template := _template
	commit_field.call("Edit monster name", func(): template.custom_name = new_name)
	_notify_changed()


## Item 0 only shows "no base yet" - it is disabled, so a base can be swapped but
## never removed. Then every BASE template in the library.
func _refresh_base_picker() -> void:
	_base_picker.clear()
	_base_picker.add_item("(choose a base template)")
	_base_picker.set_item_disabled(0, true)
	var selected := 0
	var current_key := ""
	if _template != null and _template.base_archetype != null:
		current_key = MonsterArchetypeLibrary.key_for(_template.base_archetype.template_name)
	for key in MonsterArchetypeLibrary.names_of_kind(MonsterArchetype.Kind.BASE):
		_base_picker.add_item(key)
		if key == current_key:
			selected = _base_picker.item_count - 1
	_base_picker.select(selected)
	_base_warning.visible = selected == 0


func _on_base_selected(index: int) -> void:
	if _suppress or _template == null or index == 0:
		return
	var loaded := MonsterArchetypeLibrary.load_template(_base_picker.get_item_text(index))
	if loaded == null:
		return
	var template := _template
	commit_field.call("Set monster base template", func(): template.base_archetype = loaded)
	_base_warning.visible = false
	_notify_changed()


func _refresh_template_picker() -> void:
	_template_picker.clear()
	var keys := MonsterArchetypeLibrary.names_of_kind(MonsterArchetype.Kind.ADDITIVE)
	for key in keys:
		_template_picker.add_item(key)
	if keys.is_empty():
		_template_picker.add_item("(no additive templates yet - File > Monster Templates…)")
		_template_picker.set_item_disabled(0, true)


func _on_add_template_pressed() -> void:
	if _template == null or _template_picker.item_count == 0 or _template_picker.is_item_disabled(_template_picker.selected):
		return
	var loaded := MonsterArchetypeLibrary.load_template(_template_picker.get_item_text(_template_picker.selected))
	if loaded == null:
		return
	for existing in _template.archetypes:
		if existing.template_name == loaded.template_name:
			return  # already attached
	var template := _template
	commit_field.call("Add monster template", func(): template.archetypes.append(loaded))
	_rebuild_template_rows()
	_notify_changed()


func _rebuild_template_rows() -> void:
	for child in _template_rows.get_children():
		_template_rows.remove_child(child)
		child.queue_free()
	if _template == null:
		return
	var template := _template
	for archetype in template.archetypes:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = archetype.template_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var remove := Button.new()
		remove.text = "×"
		remove.pressed.connect(func():
			commit_field.call("Remove monster template", func(): template.archetypes.erase(archetype))
			_rebuild_template_rows()
			_notify_changed()
		)
		row.add_child(remove)
		_template_rows.add_child(row)


func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(100, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row
