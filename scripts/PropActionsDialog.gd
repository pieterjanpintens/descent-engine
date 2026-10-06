class_name PropActionsDialog
extends Window

## Popup editor for InteractableEntry.actions - what a player can report
## doing to a prop (push a lever, search a bookshelf), see PropAction.gd.
## Opened via CreatorPropertiesPanel.gd's "Actions…" button (OBJECT
## selections only) - one instance, created there in code and reused
## across selections via open_for(), same pattern as PropertiesDialog.gd
## (operation_history/layered_map assigned directly after .new(), not
## @export/NodePath - nothing here needs scene wiring).
##
## Simpler than ObjectivesDialog.gd's DAG editor - a PropAction has no
## children/branching, just an id/description/conditions/effects - so
## this is a flat scrollable list of PropAction "blocks" (one
## PanelContainer per action, grouping its own id/description/conditions/
## effects together) rather than a graph canvas. `conditions` (new
## 2026-09-14) gates whether this action is currently OFFERED to players
## at all - see PropAction.conditions' own doc and MissionRuntime.
## first_available_action(), the runtime consumer. Each block's condition/
## effect rows (and everything nested under them) come from the shared
## EffectEditor, the same widgets ObjectivesDialog and TriggersDialog use.
##
## Every edit goes through operation_history.record() then
## layered_map.notify_objects_changed(), same convention as every other
## Creator dialog.
##
## Unverified in-editor, same caveat as every other Creator dialog built
## this session without the ability to launch Godot and see it rendered.

var operation_history: OperationHistory
var layered_map: LayeredMap

var _entry: InteractableEntry
var _rows_container: VBoxContainer
var _empty_label: Label

## The shared condition/effect editor widgets (EffectEditor).
var _editor: EffectEditor


func _ready() -> void:
	title = "Actions"
	size = Vector2i(420, 480)
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
	_empty_label.text = "No actions yet - this prop is purely decorative."
	root.add_child(_empty_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_container)

	var add_button := Button.new()
	add_button.text = "Add Action"
	add_button.pressed.connect(_on_add_action_pressed)
	root.add_child(add_button)

	_editor = EffectEditor.new()
	_editor.setup(self, _commit_field)


## Public - CreatorPropertiesPanel.gd calls this from its "Actions…" button.
func open_for(entry: InteractableEntry) -> void:
	_entry = entry
	_editor.mission = layered_map.mission
	_rebuild_rows()
	popup_centered()


func _rebuild_rows() -> void:
	# queue_free(), not immediate free() - this is called from a row's own
	# "Remove Action"/"Remove Effect" button pressed handler, i.e. while
	# that button (a descendant of what's being cleared here) is still on
	# the call stack. Immediate free() only became necessary in
	# ObjectivesDialog.gd for a DIFFERENT reason (GraphEdit's internal
	# children plus same-frame add_child() name collisions, see that
	# script's own comment) - neither applies to this plain, unnamed
	# VBoxContainer list, so this follows PropertiesDialog.gd's own
	# (identically-shaped) row list instead.
	for child in _rows_container.get_children():
		child.queue_free()

	if _entry == null:
		return

	_empty_label.visible = _entry.actions.is_empty()
	for action in _entry.actions:
		_rows_container.add_child(_build_action_block(action))
		_rows_container.add_child(HSeparator.new())


func _build_action_block(action: PropAction) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)

	var id_row := HBoxContainer.new()
	box.add_child(id_row)
	var id_label := Label.new()
	id_label.text = "Action id:"
	id_row.add_child(id_label)
	var id_edit := LineEdit.new()
	id_edit.text = action.action_id
	id_edit.placeholder_text = "e.g. push"
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var commit_id := func():
		_commit_field("Edit action id", func(): action.action_id = id_edit.text)
	id_edit.text_submitted.connect(func(_t): commit_id.call())
	id_edit.focus_exited.connect(commit_id)
	id_row.add_child(id_edit)
	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.tooltip_text = "Remove this action"
	remove_button.pressed.connect(func(): _on_remove_action_pressed(action))
	id_row.add_child(remove_button)

	var desc_label := Label.new()
	desc_label.text = "Description (shown to the player):"
	box.add_child(desc_label)
	var desc_edit := LineEdit.new()
	desc_edit.text = action.description
	desc_edit.placeholder_text = "e.g. You can push this lever"
	var commit_desc := func():
		_commit_field("Edit action description", func(): action.description = desc_edit.text)
	desc_edit.text_submitted.connect(func(_t): commit_desc.call())
	desc_edit.focus_exited.connect(commit_desc)
	box.add_child(desc_edit)

	var single_shot_check := CheckBox.new()
	single_shot_check.text = "Single shot (becomes unavailable once used)"
	single_shot_check.button_pressed = action.single_shot
	single_shot_check.toggled.connect(func(pressed: bool):
		_commit_field("Edit action single-shot", func(): action.single_shot = pressed)
	)
	box.add_child(single_shot_check)

	box.add_child(HSeparator.new())
	var conditions_label := Label.new()
	conditions_label.text = "Conditions (implicit AND - when is this action offered to players):"
	box.add_child(conditions_label)
	for condition in action.conditions:
		box.add_child(_editor.build_condition_row(action.conditions, condition, _rebuild_rows))
	var add_condition_button := Button.new()
	add_condition_button.text = "Add Condition"
	add_condition_button.pressed.connect(func():
		var condition := Condition.new()
		_commit_field("Add condition", func(): action.conditions.append(condition))
		_rebuild_rows()
	)
	box.add_child(add_condition_button)

	box.add_child(HSeparator.new())
	var effects_label := Label.new()
	effects_label.text = "Effects (applied immediately when this action fires):"
	box.add_child(effects_label)
	for effect in action.effects:
		box.add_child(_editor.build_effect_row(action.effects, effect, _rebuild_rows))
	var add_effect_button := Button.new()
	add_effect_button.text = "Add Effect"
	add_effect_button.pressed.connect(func():
		var effect := Effect.new()
		_commit_field("Add effect", func(): action.effects.append(effect))
		_rebuild_rows()
	)
	box.add_child(add_effect_button)

	return panel


func _on_add_action_pressed() -> void:
	if _entry == null:
		return
	var action := PropAction.new()
	var entry := _entry
	operation_history.record("Add action", func():
		entry.actions.append(action)
	)
	layered_map.notify_objects_changed()
	_rebuild_rows()


func _on_remove_action_pressed(action: PropAction) -> void:
	if _entry == null:
		return
	var entry := _entry
	operation_history.record("Remove action", func():
		entry.actions.erase(action)
	)
	layered_map.notify_objects_changed()
	_rebuild_rows()


func _commit_field(label: String, mutate: Callable) -> void:
	operation_history.record(label, mutate)
	layered_map.notify_objects_changed()
