class_name TriggersDialog
extends Window

## Editor for MissionData.triggers - the story layer's rules that fire when something
## happens, opened via CreatorSaveLoad's "Triggers…" button. A trigger watches EITHER a
## round-loop checkpoint (RoundCheckpoint - e.g. "before the monster phase") OR an event (a
## prop action's action_id - fires the instant a player reports that action) and, when
## all its Conditions hold, applies its Effects. Unlike an objective (reached once, then
## done) a trigger can repeat: untick "One shot" for "every round...". Triggers at the
## same moment fire in priority order (lower first), each re-checking its conditions
## against the state the earlier ones left behind.
##
## A flat scrollable list, one block per trigger (like PropActionsDialog); the conditions
## and effects are edited with the shared EffectEditor widgets. One instance, created in
## code by CreatorSaveLoad and reused via open_for(); every edit goes through
## operation_history.record() then layered_map.notify_objects_changed().

var operation_history: OperationHistory
var layered_map: LayeredMap

const CHECKPOINT_LABELS := {
	RoundCheckpoint.Checkpoint.BEFORE_PLAYER_PHASE: "Before the player phase",
	RoundCheckpoint.Checkpoint.PLAYER_PHASE: "Player phase starts",
	RoundCheckpoint.Checkpoint.AFTER_PLAYER_PHASE: "After the player phase",
	RoundCheckpoint.Checkpoint.BEFORE_DARKNESS_PHASE: "Before the monster phase",
	RoundCheckpoint.Checkpoint.DARKNESS_PHASE: "Monster phase starts",
	RoundCheckpoint.Checkpoint.AFTER_DARKNESS_PHASE: "After the monster phase",
}

var _mission: MissionData
var _editor: EffectEditor
var _rows_container: VBoxContainer
var _empty_label: Label


func _ready() -> void:
	title = "Triggers"
	size = Vector2i(560, 560)
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
	_empty_label.text = "No triggers yet."
	root.add_child(_empty_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_container)

	var add_button := Button.new()
	add_button.text = "Add Trigger"
	add_button.pressed.connect(_on_add_trigger_pressed)
	root.add_child(add_button)

	_editor = EffectEditor.new()
	_editor.setup(self, _commit_field)


## Public - CreatorSaveLoad calls this from its "Triggers…" button.
func open_for(mission: MissionData) -> void:
	_mission = mission
	_editor.mission = mission
	_rebuild_rows()
	popup_centered()


func _commit_field(label: String, mutate: Callable) -> void:
	operation_history.record(label, mutate)
	layered_map.notify_objects_changed()


func _rebuild_rows() -> void:
	# queue_free(): called from a block's own button handler (see PropActionsDialog).
	for child in _rows_container.get_children():
		child.queue_free()
	if _mission == null:
		return
	_empty_label.visible = _mission.triggers.is_empty()
	for trigger in _mission.triggers:
		_rows_container.add_child(_build_trigger_block(trigger))
		_rows_container.add_child(HSeparator.new())


func _build_trigger_block(trigger: MissionTrigger) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)

	# --- when: a checkpoint or an event
	var when_row := HBoxContainer.new()
	box.add_child(when_row)
	when_row.add_child(_label("When:"))
	var kind_option := OptionButton.new()
	kind_option.add_item("Round checkpoint", 0)
	kind_option.add_item("Event (a prop action)", 1)
	var is_event := trigger.checkpoint == RoundCheckpoint.Checkpoint.NONE
	kind_option.select(1 if is_event else 0)
	when_row.add_child(kind_option)

	var checkpoint_option := OptionButton.new()
	var checkpoint_ids: Array[int] = []
	for checkpoint in CHECKPOINT_LABELS:
		checkpoint_option.add_item(CHECKPOINT_LABELS[checkpoint])
		checkpoint_ids.append(checkpoint)
	checkpoint_option.select(checkpoint_ids.find(trigger.checkpoint))
	checkpoint_option.item_selected.connect(func(index: int):
		_commit_field("Edit trigger checkpoint", func(): trigger.checkpoint = checkpoint_ids[index] as RoundCheckpoint.Checkpoint)
	)
	when_row.add_child(checkpoint_option)

	# The event picker lists every action id used by a prop (plus the current one if it
	# matches none - e.g. its prop was since removed - so nothing is silently lost).
	var event_option := OptionButton.new()
	var event_ids := _known_event_ids()
	if trigger.event_id != "" and not event_ids.has(trigger.event_id):
		event_ids.append(trigger.event_id)
	for event_id in event_ids:
		event_option.add_item(event_id)
	event_option.select(event_ids.find(trigger.event_id))
	event_option.item_selected.connect(func(index: int):
		_commit_field("Edit trigger event", func(): trigger.event_id = event_ids[index])
	)
	when_row.add_child(event_option)

	var update_when := func():
		var event_mode: bool = kind_option.selected == 1
		checkpoint_option.visible = not event_mode
		event_option.visible = event_mode
	update_when.call()
	kind_option.item_selected.connect(func(index: int):
		_commit_field("Edit trigger kind", func():
			if index == 1:
				trigger.checkpoint = RoundCheckpoint.Checkpoint.NONE
				trigger.event_id = event_ids[0] if not event_ids.is_empty() else ""
			else:
				trigger.event_id = ""
				trigger.checkpoint = RoundCheckpoint.Checkpoint.BEFORE_PLAYER_PHASE
		)
		if index == 1:
			event_option.select(0 if not event_ids.is_empty() else -1)
		else:
			checkpoint_option.select(checkpoint_ids.find(RoundCheckpoint.Checkpoint.BEFORE_PLAYER_PHASE))
		update_when.call()
	)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	when_row.add_child(spacer)
	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.tooltip_text = "Remove this trigger"
	remove_button.pressed.connect(func():
		_commit_field("Remove trigger", func(): _mission.triggers.erase(trigger))
		_rebuild_rows()
	)
	when_row.add_child(remove_button)

	# --- priority + one shot
	var options_row := HBoxContainer.new()
	box.add_child(options_row)
	options_row.add_child(_label("Priority (lower fires first):"))
	var priority_spin := SpinBox.new()
	priority_spin.min_value = -999
	priority_spin.max_value = 999
	priority_spin.value = trigger.priority
	priority_spin.value_changed.connect(func(value: float):
		_commit_field("Edit trigger priority", func(): trigger.priority = int(value))
	)
	options_row.add_child(priority_spin)
	var one_shot_check := CheckBox.new()
	one_shot_check.text = "One shot (fires only once)"
	one_shot_check.button_pressed = trigger.one_shot
	one_shot_check.toggled.connect(func(pressed: bool):
		_commit_field("Edit trigger one-shot", func(): trigger.one_shot = pressed)
	)
	options_row.add_child(one_shot_check)

	# --- conditions + effects (the shared editor widgets)
	box.add_child(HSeparator.new())
	box.add_child(_label("Conditions (implicit AND - empty = always):"))
	for condition in trigger.conditions:
		box.add_child(_editor.build_condition_row(trigger.conditions, condition, _rebuild_rows))
	var add_condition_button := Button.new()
	add_condition_button.text = "Add Condition"
	add_condition_button.pressed.connect(func():
		var condition := Condition.new()
		_commit_field("Add condition", func(): trigger.conditions.append(condition))
		_rebuild_rows()
	)
	box.add_child(add_condition_button)

	box.add_child(HSeparator.new())
	box.add_child(_label("Effects (applied when it fires):"))
	for effect in trigger.effects:
		box.add_child(_editor.build_effect_row(trigger.effects, effect, _rebuild_rows))
	var add_effect_button := Button.new()
	add_effect_button.text = "Add Effect"
	add_effect_button.pressed.connect(func():
		var effect := Effect.new()
		_commit_field("Add effect", func(): trigger.effects.append(effect))
		_rebuild_rows()
	)
	box.add_child(add_effect_button)

	return panel


func _on_add_trigger_pressed() -> void:
	if _mission == null:
		return
	var trigger := MissionTrigger.new()
	trigger.id = _mission.allocate_object_id()
	trigger.checkpoint = RoundCheckpoint.Checkpoint.BEFORE_PLAYER_PHASE
	_commit_field("Add trigger", func(): _mission.triggers.append(trigger))
	_rebuild_rows()


## Every distinct, non-empty action_id of every prop in the mission - the events a
## trigger can listen for.
func _known_event_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry in _mission.interactables:
		for action in entry.actions:
			if action.action_id != "" and not ids.has(action.action_id):
				ids.append(action.action_id)
	return ids


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
