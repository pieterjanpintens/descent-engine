class_name InventoryDialog
extends Control

## The party's inventory in a campaign: gold always visible on top, then tabs for weapons (weapon cards, runes and the B / C
## parts), armor, trinkets, consumables, recipes and materials. Read-only - buying, selling and forging happen at the places on the map.
## Built in code, modal scrim like LogDialog; open() rebuilds the tabs from the state the owner hands over.
##
## Every item is a tile in a wrapping grid: its picture (from the user's own game export; a coloured tile with the first letter
## when the picture is not there), the name under it, a "+" badge when upgraded and a count for materials.
##
## Consumables are potions the party brewed: a tile with a count each (a potion and its "+" version are separate tiles).

## Assigned by the owner: returns the CampaignState to show.
var state_provider: Callable

var _gold_label: Label
var _tabs: TabContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var background := PanelContainer.new()
	margin.add_child(background)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	background.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Inventory"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)
	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 20)
	_gold_label.modulate = Color(1.0, 0.85, 0.35)
	header.add_child(_gold_label)
	vbox.add_child(HSeparator.new())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tabs)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func(): visible = false)
	vbox.add_child(close_button)

	visible = false


func open() -> void:
	var state: CampaignState = state_provider.call() if state_provider.is_valid() else null
	var keep_tab := _tabs.current_tab
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.free()
	if state == null:
		_gold_label.text = ""
		visible = true
		return
	_gold_label.text = "Gold: %d" % state.gold
	_add_tab("Weapons", _weapon_items(state))
	_add_tab("Armor", _armor_items(state))
	_add_tab("Trinkets", _trinket_items(state), "The party owns no trinkets yet - they are bought in a recipe shop or found.")
	_add_tab("Consumables", _consumable_items(state), "The party carries no consumables - brew them at an alchemist from potion recipes.")
	_add_tab("Recipes", _recipe_items(state), "No recipes yet - they are bought at a recipe shop.")
	_add_tab("Materials", _material_items(state))
	if keep_tab >= 0 and keep_tab < _tabs.get_tab_count():
		_tabs.current_tab = keep_tab
	visible = true


## A tab with a wrapping grid of tiles. `items` holds {"heading": text} section headings and tile dictionaries
## {title, texture, badge, count, tooltip}.
func _add_tab(tab_name: String, items: Array, empty_text: String = "Nothing yet.") -> void:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	if items.is_empty():
		var empty := Label.new()
		empty.text = empty_text
		empty.modulate = Color(1, 1, 1, 0.6)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.x = 300.0  # a wrapping label needs a width to start from
		list.add_child(empty)
	var flow: HFlowContainer = null
	for item: Dictionary in items:
		if item.has("heading"):
			var heading := Label.new()
			heading.text = str(item["heading"])
			heading.add_theme_font_size_override("font_size", 16)
			heading.modulate = Color(0.56, 0.79, 0.9)
			list.add_child(heading)
			flow = null
			continue
		if flow == null:
			flow = HFlowContainer.new()
			flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			flow.add_theme_constant_override("h_separation", 8)
			flow.add_theme_constant_override("v_separation", 8)
			list.add_child(flow)
		flow.add_child(ItemTile.build(item))
	_tabs.add_child(scroll)


func _tile_data(title: String, texture: Texture2D, upgraded: bool = false, count: int = -1, tooltip: String = "") -> Dictionary:
	return ItemTile.data(title, texture, upgraded, count, tooltip)


func _consumable_items(state: CampaignState) -> Array:
	var items: Array = []
	for id: String in state.consumables:
		var count := state.consumable_count(id)
		if count > 0:
			items.append(_tile_data(ConsumableData.label(id).trim_suffix(" +"), ConsumableData.image(id), ConsumableData.is_upgraded(id), count, ConsumableData.label(id) + "\n" + ConsumableData.rule_text(id)))
	return items


func _weapon_items(state: CampaignState) -> Array:
	var items: Array = []
	if not state.owned_weapons.is_empty():
		items.append({"heading": "Weapons"})
		for weapon_id in state.owned_weapons:
			items.append(_tile_data(WeaponData.part_name(weapon_id), WeaponData.part_icon(weapon_id), state.upgraded_cards.has(weapon_id), -1, WeaponData.weapon_label(weapon_id)))
	if not state.owned_runes.is_empty():
		items.append({"heading": "Runes"})
		for rune_id in state.owned_runes:
			items.append(_tile_data(WeaponData.part_name(rune_id), WeaponData.part_icon(rune_id), state.upgraded_cards.has(rune_id), -1, WeaponData.rune_label(rune_id)))
	if not state.owned_attachments.is_empty():
		items.append({"heading": "Parts (B and C)"})
		for part_id in state.owned_attachments:
			items.append(_tile_data(WeaponData.part_name(part_id), WeaponData.part_icon(part_id), state.upgraded_cards.has(part_id), -1, AttachmentCatalog.label(part_id)))
	return items


func _armor_items(state: CampaignState) -> Array:
	var items: Array = []
	for armor_id in state.owned_armors:
		var armor := ArmorData.find(armor_id)
		items.append(_tile_data(str(armor.get("name", armor_id)), ArmorData.image(armor_id), state.upgraded_cards.has(armor_id), -1, ArmorData.label(armor_id)))
	return items


func _trinket_items(state: CampaignState) -> Array:
	var items: Array = []
	for trinket_id in state.owned_trinkets:
		var upgraded := state.upgraded_cards.has(trinket_id)
		items.append(_tile_data(TrinketData.label(trinket_id), TrinketData.image(trinket_id), upgraded, -1, TrinketData.label(trinket_id) + "\n" + TrinketData.rule_text(trinket_id, upgraded)))
	return items


func _recipe_items(state: CampaignState) -> Array:
	var items: Array = []
	for recipe_id in state.owned_recipes:
		var recipe := RecipeData.find(recipe_id)
		if recipe.is_empty():
			items.append(_tile_data(str(recipe_id), null))
			continue
		var card := str(recipe["card"])
		items.append(_tile_data(RecipeData.card_label(card), RecipeData.card_image(card), bool(recipe["upgrade"]), -1, RecipeData.label(recipe)))
	return items


## Every material with how many the party has (also the ones it has none of, shown dimmed, so the grid does not jump around).
func _material_items(state: CampaignState) -> Array:
	var items: Array = [{"heading": "Common"}]
	for key in LootMaterials.COMMON:
		items.append(_tile_data(LootMaterials.display_name(key), ItemData.material_image(key), false, int(state.materials.get(key, 0))))
	items.append({"heading": "Essences"})
	for key in LootMaterials.ESSENCES:
		items.append(_tile_data(LootMaterials.display_name(key), ItemData.material_image(key), false, int(state.materials.get(key, 0))))
	return items
