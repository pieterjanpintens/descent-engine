class_name MacroManagerDialog
extends Window

## Mission > "Macros…": the author's own macros (MacroTemplateLibrary). Pick one to rename it, change its description, the pieces it applies
## to, and its inputs (labels, hints, defaults, order); delete it; export it as a file or import one somebody sent. What a macro GENERATES
## (its actions, triggers, variables) is made by "Save as macro…" on a prop - to change that, capture it again under the same id.
## Nothing here touches the mission: props that already use a macro keep what it generated.
##
## Code-built, fixed size (the dialog rules of this project); the form scrolls inside.

signal changed

const BODY_SIZE := Vector2i(820, 600)
const FORM_WIDTH := 560

var _templates: Array[MacroTemplate] = []
var _working: MacroTemplate
var _dirty := false
var _editor: EffectEditor

var _list: ItemList
var _form: VBoxContainer
var _status_label: Label
var _save_button: Button
var _revert_button: Button
var _export_button: Button
var _delete_button: Button
var _confirm: ConfirmationDialog
var _confirm_action: Callable = func(): pass
var _file_dialog: FileDialog
var _exporting := false


func _ready() -> void:
	title = "My macros"
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

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 10)
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 200
	split.add_child(left)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_macro_selected)
	left.add_child(_list)
	var import_button := Button.new()
	import_button.text = tr("Import…")
	import_button.tooltip_text = tr("Adds a macro from a file somebody sent you.")
	import_button.pressed.connect(_on_import_pressed)
	left.add_child(import_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	split.add_child(scroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_theme_constant_override("separation", 8)
	scroll.add_child(_form)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.custom_minimum_size.x = BODY_SIZE.x - 40
	root.add_child(_status_label)

	var buttons := HBoxContainer.new()
	root.add_child(buttons)
	_delete_button = Button.new()
	_delete_button.text = tr("Delete macro")
	_delete_button.pressed.connect(_on_delete_pressed)
	buttons.add_child(_delete_button)
	_export_button = Button.new()
	_export_button.text = tr("Export…")
	_export_button.pressed.connect(_on_export_pressed)
	buttons.add_child(_export_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_revert_button = Button.new()
	_revert_button.text = tr("Revert")
	_revert_button.pressed.connect(func(): _select_working(_working.macro_id if _working != null else ""))
	buttons.add_child(_revert_button)
	_save_button = Button.new()
	_save_button.text = tr("Save changes")
	_save_button.pressed.connect(_on_save_pressed)
	buttons.add_child(_save_button)
	var close := Button.new()
	close.text = tr("Close")
	close.pressed.connect(hide)
	buttons.add_child(close)

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func(): _confirm_action.call())
	add_child(_confirm)
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.add_filter("*.tres", "Macro files")
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)

	# default values of Loot inputs are edited with the normal Loot editor
	_editor = EffectEditor.new()
	_editor.setup(self, func(_label: String, mutate: Callable): mutate.call())


func open() -> void:
	_status_label.text = ""
	_reload_list("")
	if not visible:
		popup_centered_clamped(BODY_SIZE, 0.9)


# --- the list ----------------------------------------------------------------

func _reload_list(select_id: String) -> void:
	MacroCatalog.reload_user_macros()
	_templates.clear()
	for macro in MacroCatalog.user_macros():
		_templates.append((macro as UserMacro).template)
	_list.clear()
	var selected := -1
	for index in _templates.size():
		_list.add_item("%s  (v%d)" % [_templates[index].title, _templates[index].version])
		_list.set_item_tooltip(index, _templates[index].macro_id)
		if _templates[index].macro_id == select_id:
			selected = index
	if selected == -1 and not _templates.is_empty():
		selected = 0
	if selected >= 0:
		_list.select(selected)
		_select_working(_templates[selected].macro_id)
	else:
		_working = null
		_rebuild_form()


func _on_macro_selected(index: int) -> void:
	_select_working(_templates[index].macro_id)


func _select_working(macro_id: String) -> void:
	_working = null
	for template in _templates:
		if template.macro_id == macro_id:
			_working = template.duplicate(true) as MacroTemplate  # edited as a copy: Revert / switching drops it
	_dirty = false
	_rebuild_form()


# --- the form ----------------------------------------------------------------

func _rebuild_form() -> void:
	for child in _form.get_children():
		_form.remove_child(child)
		child.free()
	var has := _working != null
	_delete_button.disabled = not has
	_export_button.disabled = not has
	if not has:
		var empty := Label.new()
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty.custom_minimum_size.x = FORM_WIDTH
		empty.text = tr("You have no macros yet. Put actions on a prop and choose \"Save as macro…\" in its properties, or import a macro file.")
		_form.add_child(empty)
		_refresh_status()
		return
	_editor.mission = null

	_form.add_child(_caption(tr("Id: %s   Version: %d") % [_working.macro_id, _working.version], true))
	_form.add_child(_caption(tr("Name")))
	var title_edit := LineEdit.new()
	title_edit.text = _working.title
	title_edit.text_changed.connect(func(text: String):
		_working.title = text
		_touch()
	)
	_form.add_child(title_edit)
	_form.add_child(_caption(tr("What it does (shown when you apply it)")))
	var description_edit := TextEdit.new()
	description_edit.text = _working.description
	description_edit.custom_minimum_size = Vector2(FORM_WIDTH, 70)
	description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	description_edit.text_changed.connect(func():
		_working.description = description_edit.text
		_touch()
	)
	_form.add_child(description_edit)

	if _working.target_type == MacroTemplate.TargetType.PROP:
		_form.add_child(_caption(tr("Applies to props with these piece names (comma separated; empty = any prop)")))
		var meshes_edit := LineEdit.new()
		meshes_edit.text = ", ".join(_working.meshes)
		meshes_edit.text_changed.connect(func(text: String):
			var names: Array[String] = []
			for part in text.split(","):
				if part.strip_edges() != "":
					names.append(part.strip_edges())
			_working.meshes = names
			_touch()
		)
		_form.add_child(meshes_edit)
	var repeat := CheckBox.new()
	repeat.text = tr("May be applied to the same prop more than once")
	repeat.button_pressed = _working.repeatable
	repeat.toggled.connect(func(pressed: bool):
		_working.repeatable = pressed
		_touch()
	)
	_form.add_child(repeat)
	_form.add_child(_caption(_generates_text(), true))

	_form.add_child(_caption(tr("Inputs (what you fill in when applying)")))
	for index in _working.params.size():
		_form.add_child(_param_block(index))
	_refresh_status()


func _caption(text: String, dim: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size.x = FORM_WIDTH
	if dim:
		label.modulate = Color(1, 1, 1, 0.65)
	return label


func _generates_text() -> String:
	var variables := 0
	var actions := 0
	var triggers := 0
	for part in _working.parts:
		match part.kind:
			MacroTemplatePart.Kind.VARIABLE:
				variables += 1
			MacroTemplatePart.Kind.ACTION:
				actions += 1
			MacroTemplatePart.Kind.TRIGGER:
				triggers += 1
	return tr("It generates %d variable(s), %d prop action(s) and %d trigger(s). To change that, capture the macro again with \"Save as macro…\" under the same id.") % [variables, actions, triggers]


## One input: label, hint, default, and up / down to reorder.
func _param_block(index: int) -> Control:
	var param := _working.params[index]
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var top := HBoxContainer.new()
	box.add_child(top)
	var up := Button.new()
	up.text = "↑"
	up.disabled = index == 0
	up.pressed.connect(func(): _move_param(index, -1))
	top.add_child(up)
	var down := Button.new()
	down.text = "↓"
	down.disabled = index == _working.params.size() - 1
	down.pressed.connect(func(): _move_param(index, 1))
	top.add_child(down)
	var label_edit := LineEdit.new()
	label_edit.text = param.label
	label_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_edit.text_changed.connect(func(text: String):
		param.label = text
		_touch()
	)
	top.add_child(label_edit)
	var kind := Label.new()
	kind.text = _kind_name(param)
	kind.modulate = Color(1, 1, 1, 0.6)
	top.add_child(kind)

	var hint_edit := LineEdit.new()
	hint_edit.placeholder_text = tr("Hint shown under the input (optional)")
	hint_edit.text = param.hint
	hint_edit.text_changed.connect(func(text: String):
		param.hint = text
		_touch()
	)
	box.add_child(hint_edit)
	var default_row := _default_editor(param)
	if default_row != null:
		box.add_child(default_row)
	return panel


func _kind_name(param: MacroParam) -> String:
	match param.kind:
		MacroParam.Kind.INT:
			return tr("number")
		MacroParam.Kind.BOOL:
			return tr("yes / no")
		MacroParam.Kind.TEXT:
			return tr("text")
		MacroParam.Kind.CHOICE:
			return tr("choice")
		MacroParam.Kind.LOOT:
			return tr("loot")
		MacroParam.Kind.MONSTERS:
			return tr("monsters")
		MacroParam.Kind.VARIABLE:
			return tr("variable")
	return ""


## The editor for the input's default value; null for kinds without a simple one.
func _default_editor(param: MacroParam) -> Control:
	var row := HBoxContainer.new()
	var caption := Label.new()
	caption.text = tr("Default:")
	row.add_child(caption)
	match param.kind:
		MacroParam.Kind.INT:
			var spin := SpinBox.new()
			spin.min_value = param.min_value
			spin.max_value = param.max_value
			spin.value = int(param.default_value) if param.default_value != null else param.min_value
			spin.value_changed.connect(func(value: float):
				param.default_value = int(value)
				_touch()
			)
			row.add_child(spin)
			var range_label := Label.new()
			range_label.text = tr("range %d to %d") % [param.min_value, param.max_value]
			range_label.modulate = Color(1, 1, 1, 0.6)
			row.add_child(range_label)
		MacroParam.Kind.BOOL:
			var check := CheckBox.new()
			check.button_pressed = bool(param.default_value)
			check.toggled.connect(func(pressed: bool):
				param.default_value = pressed
				_touch()
			)
			row.add_child(check)
		MacroParam.Kind.TEXT, MacroParam.Kind.VARIABLE:
			var line := LineEdit.new()
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.text = str(param.default_value) if param.default_value != null else ""
			line.text_changed.connect(func(text: String):
				param.default_value = text
				_touch()
			)
			row.add_child(line)
		MacroParam.Kind.CHOICE:
			var option := OptionButton.new()
			var selected := 0
			for index in param.choices.size():
				option.add_item(str(param.choices[index][0]))
				if typeof(param.choices[index][1]) == typeof(param.default_value) and param.choices[index][1] == param.default_value:
					selected = index
			option.select(selected)
			option.item_selected.connect(func(index: int):
				param.default_value = param.choices[index][1]
				_touch()
			)
			row.add_child(option)
		MacroParam.Kind.LOOT, MacroParam.Kind.MONSTERS:
			if not param.default_value is Resource:
				param.default_value = param.make_default()
			var effect := param.default_value as Effect
			var button := Button.new()
			var refresh := func():
				var summary: String = _editor.loot_summary(effect) if param.kind == MacroParam.Kind.LOOT else _editor.monsters_summary(effect)
				button.text = tr("Edit…") if summary == "" else summary
			refresh.call()
			button.pressed.connect(func():
				var done := func():
					refresh.call()
					_touch()
				if param.kind == MacroParam.Kind.LOOT:
					_editor.open_loot_editor(effect, done)
				else:
					_editor.open_monsters_editor(effect, done)
			)
			row.add_child(button)
		_:
			return null
	return row


func _move_param(index: int, delta: int) -> void:
	var target := index + delta
	if target < 0 or target >= _working.params.size():
		return
	var moved := _working.params[index]
	_working.params.remove_at(index)
	_working.params.insert(target, moved)
	_touch()
	_rebuild_form.call_deferred()


func _touch() -> void:
	_dirty = true
	_refresh_status()


func _refresh_status() -> void:
	var issue := ""
	if _working != null:
		var problems := _working.problems()
		if not problems.is_empty():
			issue = problems[0]
	_save_button.disabled = _working == null or not _dirty or issue != ""
	_revert_button.disabled = _working == null or not _dirty
	if issue != "":
		_status_label.text = issue
		_status_label.modulate = Color(1.0, 0.55, 0.45)
	elif _dirty:
		_status_label.text = tr("Unsaved changes. Props that already use this macro keep what it generated until you regenerate them.")
		_status_label.modulate = Color(1.0, 0.85, 0.5)
	# otherwise keep a message a command left (saved, imported...)


# --- commands ----------------------------------------------------------------

func _say(text: String, good: bool = true) -> void:
	_status_label.text = text
	_status_label.modulate = Color(0.6, 0.9, 0.6) if good else Color(1.0, 0.55, 0.45)


func _on_save_pressed() -> void:
	if _working == null:
		return
	_working.version += 1
	var error := MacroTemplateLibrary.save_template(_working)
	if error != "":
		_working.version -= 1
		_say(error, false)
		return
	var saved_id := _working.macro_id
	_reload_list(saved_id)
	_say(tr("Saved."))
	changed.emit()


func _on_delete_pressed() -> void:
	if _working == null:
		return
	var macro_id := _working.macro_id
	_confirm.title = tr("Delete macro")
	_confirm.dialog_text = tr("Delete the macro '%s'?\n\nProps that already use it keep the data it generated, but it can no longer be regenerated or removed as a macro.") % _working.title
	_confirm_action = func():
		MacroTemplateLibrary.delete_template(macro_id)
		_reload_list("")
		_say(tr("Deleted."))
		changed.emit()
	_confirm.popup_centered()


func _on_export_pressed() -> void:
	if _working == null:
		return
	_exporting = true
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.title = tr("Export macro")
	_file_dialog.current_file = MacroTemplateLibrary.file_for(_working.macro_id).get_file()
	_file_dialog.popup_centered_ratio(0.7)


func _on_import_pressed() -> void:
	_exporting = false
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = tr("Import macro")
	_file_dialog.popup_centered_ratio(0.7)


func _on_file_selected(path: String) -> void:
	if _exporting:
		_export_to(path)
	else:
		_import_from(path)


func _export_to(path: String) -> void:
	var source := MacroTemplateLibrary.file_for(_working.macro_id)
	var bytes := FileAccess.get_file_as_bytes(source)
	if bytes.is_empty():
		_say(tr("The macro has to be saved before it can be exported."), false)
		return
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		_say(tr("Could not write the file."), false)
		return
	out.store_buffer(bytes)
	out.close()
	_say(tr("Exported."))


func _import_from(path: String) -> void:
	var found := MacroTemplateLibrary.read_importable(path)
	if found["error"] != "":
		_say(tr("Not imported: %s") % found["error"], false)
		return
	var template: MacroTemplate = found["template"]
	var existing := MacroTemplateLibrary.load_file(MacroTemplateLibrary.file_for(template.macro_id))
	var finish := func():
		var error := MacroTemplateLibrary.save_template(template)
		if error != "":
			_say(tr("Not imported: %s") % error, false)
			return
		_reload_list(template.macro_id)
		_say(tr("Imported '%s'.") % template.title)
		changed.emit()
	if existing == null:
		finish.call()
		return
	_confirm.title = tr("Replace macro")
	_confirm.dialog_text = tr("You already have a macro with the id '%s' ('%s'). Replace it with the imported one?") % [template.macro_id, existing.title]
	_confirm_action = finish
	_confirm.popup_centered()
