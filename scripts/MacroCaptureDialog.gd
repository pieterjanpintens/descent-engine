class_name MacroCaptureDialog
extends Window

## "Save as macro…": the form around MacroCapture. The author names the macro, chooses which prop actions, triggers and variables belong to
## it and which fields become inputs; Save writes a MacroTemplate to the user's macro folder (MacroTemplateLibrary), after which the macro is
## offered on every prop it fits. Nothing in the mission is changed.
##
## Same code-built, one-instance-reused pattern as the other editor dialogs: add it as a child, call open_for(). A fixed size, not
## resizable; the form scrolls inside (the dialog rules of this project).

signal saved(template: MacroTemplate)

const BODY_SIZE := Vector2i(660, 640)
const WRAP_WIDTH := 600

var _mission: MissionData
var _target: InteractableEntry
var _capture: MacroCapture
var _id_edited := false

var _title_edit: LineEdit
var _id_edit: LineEdit
var _description_edit: LineEdit
var _applies_option: OptionButton
var _sections: VBoxContainer
var _status_label: Label
var _save_button: Button


func _ready() -> void:
	title = "Save as macro"
	size = BODY_SIZE
	unresizable = true
	close_requested.connect(hide)
	visible = false

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_top = 10
	root.offset_right = -10
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var intro := _wrapping_label(tr("Turns this prop's actions into a macro you can apply to other props. Choose what belongs to it and which values you want to fill in each time."))
	root.add_child(intro)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)

	_title_edit = _labelled_line(body, tr("Name of the macro"))
	_title_edit.text_changed.connect(_on_title_changed)
	_id_edit = _labelled_line(body, tr("Id (letters, digits, '_', '-', '.'; saved in every mission that uses it)"))
	_id_edit.text_changed.connect(func(_text: String):
		_id_edited = true
		_refresh_status()
	)
	_description_edit = _labelled_line(body, tr("What it does (shown when you apply it)"))
	var applies_label := Label.new()
	applies_label.text = tr("Can be applied to")
	body.add_child(applies_label)
	_applies_option = OptionButton.new()
	_applies_option.item_selected.connect(func(_index: int): _refresh_status())
	body.add_child(_applies_option)

	_sections = VBoxContainer.new()
	_sections.add_theme_constant_override("separation", 6)
	body.add_child(_sections)

	_status_label = _wrapping_label("")
	root.add_child(_status_label)
	var buttons := HBoxContainer.new()
	root.add_child(buttons)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var cancel := Button.new()
	cancel.text = tr("Cancel")
	cancel.pressed.connect(hide)
	buttons.add_child(cancel)
	_save_button = Button.new()
	_save_button.text = tr("Save macro")
	_save_button.pressed.connect(_on_save_pressed)
	buttons.add_child(_save_button)


func open_for(mission: MissionData, target: InteractableEntry) -> void:
	_mission = mission
	_target = target
	_capture = MacroCapture.new(mission, target)
	_id_edited = false
	var default_title := tr("My %s macro") % (target.reference_name if target.reference_name != "" else target.mesh_item_name)
	_title_edit.text = default_title
	_id_edit.text = _id_for(default_title)
	_description_edit.text = ""
	_applies_option.clear()
	_applies_option.add_item(tr("Props of this kind only (%s)") % target.mesh_item_name)
	_applies_option.add_item(tr("Any prop"))
	_applies_option.select(0)
	_rebuild_sections()
	_refresh_status()
	if not visible:
		popup_centered()


func _wrapping_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size.x = WRAP_WIDTH
	return label


func _labelled_line(parent: Control, caption: String) -> LineEdit:
	var label := _wrapping_label(caption)
	parent.add_child(label)
	var line := LineEdit.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(line)
	return line


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HeadingLabel"
	return label


func _id_for(title_text: String) -> String:
	return "user." + MacroContext.identifier(title_text)


func _on_title_changed(text: String) -> void:
	if not _id_edited:
		_id_edit.text = _id_for(text)
	_refresh_status()


# --- the choices -------------------------------------------------------------

func _rebuild_sections() -> void:
	for child in _sections.get_children():
		_sections.remove_child(child)
		child.free()
	_capture.refresh()

	_sections.add_child(_heading(tr("Actions in the macro")))
	for action in _target.actions:
		var check := CheckBox.new()
		var shown := action.action_name if action.action_name != "" else action.description
		check.text = "%s  (%s)" % [shown if shown != "" else tr("(no name)"), action.action_id]
		check.button_pressed = _capture.action_choice.get(action.action_id, true)
		check.toggled.connect(func(pressed: bool):
			_capture.action_choice[action.action_id] = pressed
			_rebuild_sections.call_deferred()
			_refresh_status()
		)
		_sections.add_child(check)

	if not _capture.triggers.is_empty():
		_sections.add_child(_heading(tr("Triggers that belong to it")))
		for entry in _capture.triggers:
			var trigger: MissionTrigger = entry["trigger"]
			var check := CheckBox.new()
			check.text = "%s - %s" % [_trigger_summary(trigger), entry["reason"]]
			check.button_pressed = entry["selected"]
			check.toggled.connect(func(pressed: bool):
				_capture.trigger_choice[trigger.id] = pressed
				_rebuild_sections.call_deferred()
				_refresh_status()
			)
			_sections.add_child(check)

	if not _capture.variables.is_empty():
		_sections.add_child(_heading(tr("Variables")))
		for variable in _capture.variables:
			_sections.add_child(_variable_row(variable))

	var shown_fields := 0
	for field in _capture.fields:
		if shown_fields == 0:
			_sections.add_child(_heading(tr("Values to fill in each time (inputs)")))
		shown_fields += 1
		_sections.add_child(_field_row(field))

	for warning in _capture.warnings:
		var label := _wrapping_label("⚠ " + warning)
		label.modulate = Color(1.0, 0.8, 0.45)
		_sections.add_child(label)


func _trigger_summary(trigger: MissionTrigger) -> String:
	if trigger.event_id != "":
		return tr("when '%s' happens") % trigger.event_id
	return tr("a round trigger")


func _variable_row(variable: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = variable["name"]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.add_item(tr("Created by the macro"))
	option.add_item(tr("Chosen when applied"))
	option.select(0 if variable["owned"] else 1)
	if variable["elsewhere"]:
		option.tooltip_text = tr("Other parts of the mission use this variable too.")
	option.item_selected.connect(func(index: int):
		_capture.variable_choice[variable["name"]] = index == 0
		_rebuild_sections.call_deferred()
		_refresh_status()
	)
	row.add_child(option)
	return row


func _field_row(field: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var check := CheckBox.new()
	check.button_pressed = field["selected"]
	check.toggled.connect(func(pressed: bool):
		_capture.field_choice[field["key"]] = pressed
		_refresh_status()
	)
	row.add_child(check)
	var line := LineEdit.new()
	line.text = field["label"]
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.tooltip_text = tr("The label of this input in the macro form")
	line.text_changed.connect(func(text: String):
		_capture.field_label[field["key"]] = text
		_refresh_status()
	)
	row.add_child(line)
	var value := Label.new()
	value.text = "= " + _value_text(field)
	value.modulate = Color(1, 1, 1, 0.6)
	value.custom_minimum_size.x = 140
	value.clip_text = true
	row.add_child(value)
	return row


func _value_text(field: Dictionary) -> String:
	if field["kind"] == MacroCapture.FieldKind.LOOT:
		var loot := field["value"] as Effect
		var gold := int(loot.loot_materials.get(LootMaterials.GOLD, 0))
		return tr("%d gold, %d other") % [gold, loot.loot_materials.size() - (1 if gold > 0 else 0) + loot.loot_cards.size() + loot.loot_recipes.size()]
	if field["kind"] == MacroCapture.FieldKind.ATTRIBUTE:
		return PlayerAttribute.attribute_name(int(field["value"]))
	return str(field["value"])


# --- saving --------------------------------------------------------------------

func _current_template() -> MacroTemplate:
	return _capture.build(_title_edit.text.strip_edges(), _description_edit.text.strip_edges(), _id_edit.text.strip_edges(), _applies_option.selected == 1)


func _refresh_status() -> void:
	var issue := ""
	if _capture.actions.is_empty():
		issue = tr("Choose at least one action.")
	else:
		var template := _current_template()
		var problems := template.problems()
		if not problems.is_empty():
			issue = problems[0]
		else:
			var existing := MacroTemplateLibrary.load_file(MacroTemplateLibrary.file_for(template.macro_id))
			if existing != null:
				_status_label.text = tr("This replaces your macro '%s' (version %d). Props that already use it keep what they have until you regenerate them.") % [existing.title, existing.version]
				_status_label.modulate = Color(1.0, 0.85, 0.5)
				_save_button.disabled = false
				return
	_save_button.disabled = issue != ""
	_status_label.text = issue
	_status_label.modulate = Color(1.0, 0.55, 0.45)


func _on_save_pressed() -> void:
	var template := _current_template()
	var existing := MacroTemplateLibrary.load_file(MacroTemplateLibrary.file_for(template.macro_id))
	if existing != null:
		template.version = existing.version + 1
	var error := MacroTemplateLibrary.save_template(template)
	if error != "":
		_status_label.text = error
		_status_label.modulate = Color(1.0, 0.55, 0.45)
		return
	hide()
	saved.emit(template)
