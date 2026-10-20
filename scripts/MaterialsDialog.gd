class_name MaterialsDialog
extends AcceptDialog

## Edits a materials dictionary (LootMaterials key -> count) IN PLACE, for what a chapter / side quest gives and what an offer costs.
## Inventory style: every material is a tile with its picture (from the user's own game export; a coloured placeholder without it),
## its name and a counter under it; 0 = none (the key is removed). Built in code, one instance reused by the campaign editor.

const TILE_COUNTER_MAX := 99

var _materials: Dictionary = {}
var _on_change: Callable
var _read_only := false
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


## `materials` is changed directly; `on_change` is called after every edit (the editor marks the campaign dirty and redraws its summary).
func open_for(heading: String, materials: Dictionary, on_change: Callable, read_only: bool = false) -> void:
	_materials = materials
	_on_change = on_change
	_read_only = read_only
	title = heading
	for child in _content.get_children():
		_content.remove_child(child)
		child.free()
	_add_section("Common", LootMaterials.COMMON)
	_add_section("Essences", LootMaterials.ESSENCES)
	popup_centered_clamped(Vector2i(600, 560), 0.9)


func _add_section(heading: String, keys: Array) -> void:
	var label := Label.new()
	label.text = heading
	label.add_theme_font_size_override("font_size", 16)
	label.modulate = Color(0.56, 0.79, 0.9)
	_content.add_child(label)
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
			if _on_change.is_valid():
				_on_change.call()
		)
		var tile_data := ItemTile.data(LootMaterials.display_name(key), ItemData.material_image(key))
		flow.add_child(ItemTile.build(tile_data, spin))
