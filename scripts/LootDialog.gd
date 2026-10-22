class_name LootDialog
extends AcceptDialog

## The one dialog for "what is found / given": a materials dictionary (LootMaterials key -> count) edited IN PLACE, and optionally gold and lists of
## cards (weapons, parts, runes, armor) and recipes. Used for a chapter's / side quest's reward, a Loot effect, a monster's drops and (materials only)
## what an offer costs. Inventory style: every material is a tile with its picture (from the user's own game export; a coloured placeholder
## without it), its name and a counter under it; 0 = none (the key is removed). Built in code, one instance reused by each editor.

const TILE_COUNTER_MAX := 99

var _materials: Dictionary = {}
var _on_change: Callable
var _read_only := false
var _with_gold := false
var _lists: Dictionary = {}  # "cards" / "recipes" -> Array[String] edited in place; a missing key = that list is not offered
var _heading := ""
var _content: VBoxContainer


func _ready() -> void:
	ok_button_text = "Done"
	min_size = Vector2i(560, 420)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(540, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_content)


## `materials` is changed directly; `on_change` is called after every edit (the editor marks things dirty and redraws its summary).
## `with_gold` adds a Gold counter (kept under LootMaterials.GOLD in `materials`). `lists` may hold "cards" and/or "recipes" (Array[String],
## changed in place) to offer those pickers too; "usable" (consumable ids) is only for mission loot (the Loot effect and monster drops): the
## consumable can be used during that mission and is never added to the inventory.
func open_for(heading: String, materials: Dictionary, on_change: Callable, read_only: bool = false, with_gold: bool = false, lists: Dictionary = {}) -> void:
	_materials = materials
	_on_change = on_change
	_read_only = read_only
	_with_gold = with_gold
	_lists = lists
	_heading = heading
	title = heading
	_build()
	popup_centered_clamped(Vector2i(600, 560), 0.9)


func _build() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.free()
	if _with_gold:
		_add_gold_row()
	_add_section("Common", LootMaterials.COMMON)
	_add_section("Essences", LootMaterials.ESSENCES)
	if _lists.has("cards"):
		_add_id_list("Cards (weapons, parts, runes, armor)", _lists["cards"], card_choices())
	if _lists.has("recipes"):
		_add_id_list("Recipes", _lists["recipes"], recipe_choices())
	if _lists.has("usable"):
		_add_id_list("Usable in this mission only (consumables; not added to the inventory - the table puts them in their play area)", _lists["usable"], ConsumableData.choices())


func _changed() -> void:
	if _on_change.is_valid():
		_on_change.call()


func _add_gold_row() -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Gold:"
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 9999
	spin.value = int(_materials.get(LootMaterials.GOLD, 0))
	spin.editable = not _read_only
	spin.value_changed.connect(func(value: float):
		if int(value) > 0:
			_materials[LootMaterials.GOLD] = int(value)
		else:
			_materials.erase(LootMaterials.GOLD)
		_changed()
	)
	row.add_child(spin)
	_content.add_child(row)


func _heading_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.modulate = Color(0.56, 0.79, 0.9)
	_content.add_child(label)


func _add_section(heading: String, keys: Array) -> void:
	_heading_label(heading)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	_content.add_child(flow)
	for key: String in keys:
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = TILE_COUNTER_MAX
		spin.value = int(_materials.get(key, 0))
		spin.editable = not _read_only
		spin.value_changed.connect(func(value: float):
			if int(value) > 0:
				_materials[key] = int(value)
			else:
				_materials.erase(key)
			_changed()
		)
		var tile_data := ItemTile.data(LootMaterials.display_name(key), ItemData.material_image(key))
		flow.add_child(ItemTile.build(tile_data, spin))


## A list of picked ids (cards / recipes): one row each with a remove button, and a picker to add one. `choices` = id -> label.
func _add_id_list(heading: String, ids: Array, choices: Dictionary) -> void:
	_heading_label(heading)
	for i in ids.size():
		var index := i
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = str(choices.get(ids[index], str(ids[index]) + " (unknown)"))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)
		var remove := Button.new()
		remove.text = "×"
		remove.disabled = _read_only
		remove.pressed.connect(func():
			ids.remove_at(index)
			_changed()
			_build()
		)
		row.add_child(remove)
		_content.add_child(row)
	var picker := OptionButton.new()
	picker.disabled = _read_only
	picker.add_item("(add…)")
	var keys: Array = choices.keys()
	for key in keys:
		picker.add_item(str(choices[key]))
	picker.item_selected.connect(func(selected: int):
		if selected <= 0:
			return
		ids.append(str(keys[selected - 1]))
		_changed()
		_build()
	)
	_content.add_child(picker)


## Every weapon card, B/C part, rune and armor the game data knows (needs the user's own game export): id -> label.
static func card_choices() -> Dictionary:
	var choices := {}
	for type_name: String in WeaponData.TYPE_TO_GAME_WEAPON:
		for weapon in WeaponData.weapons_for_type(type_name):
			choices[weapon.part_id] = "%s (%s)" % [weapon.weapon_name, type_name]
	for attachment in AttachmentCatalog.all():
		choices[attachment.part_id] = AttachmentCatalog.label(attachment.part_id)
	for rune in WeaponData.runes():
		choices[rune.part_id] = "Rune: " + rune.weapon_name
	for armor in ArmorData.all():
		choices[str(armor["id"])] = "Armor: " + ArmorData.label(str(armor["id"]))
	for trinket in TrinketData.all():
		choices[str(trinket["id"])] = "Trinket: " + str(trinket["name"])
	return choices


static func recipe_choices() -> Dictionary:
	var choices := {}
	for recipe in RecipeData.all():
		choices[str(recipe["id"])] = RecipeData.label(recipe)
	return choices
