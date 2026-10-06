class_name MonsterManageDialog
extends Control

## Opened by clicking a monster in the monster (M) view: change a monster's state
## directly, without combat - damage or heal it by an amount, switch conditions on/off.
## For everything that happens outside an attack: a hero ability that deals damage or
## applies a condition without a fight, a confused monster's friendly fire (use the
## monster attack dialog's Interrupt, then click the victim here), a correction when the
## table made a mistake. Condition immunities are shown disabled ("(immune)", they are
## not secret). A monster brought to 0 hitpoints is defeated and released, as in combat.
##
## Built in code, modal scrim like HeroesDialog; open() rebuilds fresh. `logged(text)`
## is emitted for each change so MissionPlayer can write it to the quest log.

signal logged(text: String)

var _runtime: MissionRuntime
var _monster: RuntimeMonster

var _title: Label
var _hp_label: Label
var _amount: SpinBox
var _condition_boxes: Dictionary = {}  # MonsterCondition.Kind -> CheckBox
var _suppress: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var background := PanelContainer.new()
	center.add_child(background)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 8)
	background.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_title)

	_hp_label = Label.new()
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_hp_label)

	var amount_row := HBoxContainer.new()
	amount_row.alignment = BoxContainer.ALIGNMENT_CENTER
	amount_row.add_theme_constant_override("separation", 8)
	vbox.add_child(amount_row)
	_amount = SpinBox.new()
	_amount.min_value = 1
	_amount.max_value = 999
	_amount.value = 1
	amount_row.add_child(_amount)
	var damage_button := Button.new()
	damage_button.text = "Damage"
	damage_button.pressed.connect(_on_damage_pressed)
	amount_row.add_child(damage_button)
	var heal_button := Button.new()
	heal_button.text = "Heal"
	heal_button.pressed.connect(_on_heal_pressed)
	amount_row.add_child(heal_button)

	var conditions_title := Label.new()
	conditions_title.text = "Conditions"
	vbox.add_child(conditions_title)
	var grid := GridContainer.new()
	grid.columns = 2
	vbox.add_child(grid)
	for kind in MonsterCondition.all():
		var box := CheckBox.new()
		box.text = MonsterCondition.display_name(kind)
		box.toggled.connect(func(on: bool): _on_condition_toggled(kind, on))
		grid.add_child(box)
		_condition_boxes[kind] = box

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func(): visible = false)
	vbox.add_child(close_button)

	visible = false


func open(monster: RuntimeMonster, runtime: MissionRuntime) -> void:
	_monster = monster
	_runtime = runtime
	_amount.value = 1
	_refresh()
	visible = true


func _refresh() -> void:
	_title.text = "%s (%s chip)" % [_monster.display_name(), MonsterChip.display_name(_monster.chip)]
	_hp_label.text = "Hitpoints %d / %d" % [_monster.hitpoints, _monster.max_hitpoints]
	_suppress = true
	for kind in _condition_boxes:
		var box: CheckBox = _condition_boxes[kind]
		var immune := _monster.condition_immunities.has(kind)
		box.button_pressed = _monster.conditions.has(kind)
		box.disabled = immune
		box.text = MonsterCondition.display_name(kind) + ("  (immune)" if immune else "")
	_suppress = false


func _on_damage_pressed() -> void:
	var amount := int(_amount.value)
	var monster_name := _monster.display_name()
	var result := _runtime.damage_monster(_monster, amount)
	if result["defeated"]:
		logged.emit("%s took %d damage and was defeated." % [monster_name, amount])
		visible = false
		return
	logged.emit("%s took %d damage (%d hitpoints left)." % [monster_name, amount, result["hitpoints"]])
	_refresh()


func _on_heal_pressed() -> void:
	var amount := int(_amount.value)
	var healed := _runtime.heal_monster(_monster, amount)
	logged.emit("%s healed %d (%d hitpoints)." % [_monster.display_name(), healed, _monster.hitpoints])
	_refresh()


func _on_condition_toggled(kind: int, on: bool) -> void:
	if _suppress:
		return
	if on:
		if not _runtime.add_condition(_monster, kind):
			_refresh()
			return
	else:
		_runtime.remove_condition(_monster, kind)
	logged.emit("%s is %s%s." % [_monster.display_name(), "" if on else "no longer ", MonsterCondition.display_name(kind)])
	_refresh()
