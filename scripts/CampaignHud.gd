class_name CampaignHud
extends Control

## The chrome over the full-screen campaign map, in the same style as the mission player's HUD (PlayerHud): a Gear and a Party
## toggle bottom-left that each pop a stacked menu above themselves, the campaign / act name top-left, XP and gold top-right,
## and - for a playtest of a draft only - a small bar with the Auto-win switch on top (a playtest from the editor has "Back to Editor" in the Gear menu instead of "Back to Menu").
##
## It only builds the pieces and sends signals; CampaignPlayer owns what they do. Built in code, added as a plain child of the
## play page (mouse_filter IGNORE, so the map below still gets every click that does not hit one of the pieces).

signal back_to_menu_pressed
signal back_to_editor_pressed
signal options_pressed
signal rules_pressed
signal log_pressed
signal inventory_pressed

const MARGIN := 12.0
const TOGGLE_SIZE := 48.0
const MENU_WIDTH := 180.0

## The pieces CampaignPlayer switches on and off.
var back_to_menu_button: Button
var back_to_editor_button: Button
var auto_win_check: CheckBox

var _heading_panel: PanelContainer
var _title_label: Label
var _act_label: Label
var _status_label: Label
var _playtest_bar: HBoxContainer
var _gear_menu: VBoxContainer
var _party_menu: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_left()
	_build_top_right()
	_build_playtest_bar()
	_build_bottom_left()


## "Campaign name" large, "Act name (save game)" smaller underneath. Empty texts hide the panel.
func set_heading(title: String, act_line: String) -> void:
	_title_label.text = title
	_act_label.text = act_line
	_act_label.visible = act_line != ""
	_heading_panel.visible = title != ""


func set_status(text: String) -> void:
	_status_label.text = text


## Shows the playtest tools (a draft opened from the editor): `from_editor` = the "Back to Editor" menu item (replacing "Back to Menu"), `cheats` = the Auto-win bar.
func set_playtest_tools(from_editor: bool, cheats: bool) -> void:
	back_to_editor_button.visible = from_editor
	auto_win_check.visible = cheats
	_playtest_bar.visible = cheats
	# a playtest leaves through Back to editor, not through the main menu
	back_to_menu_button.visible = not from_editor


func close_menus() -> void:
	_gear_menu.visible = false
	_party_menu.visible = false


# ---------------------------------------------------------------- top

func _dark_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.72)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _build_top_left() -> void:
	_heading_panel = _dark_panel()
	_heading_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_heading_panel.offset_left = MARGIN
	_heading_panel.offset_top = MARGIN
	add_child(_heading_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heading_panel.add_child(box)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_title_label)
	_act_label = Label.new()
	_act_label.modulate = Color(0.56, 0.79, 0.9)
	box.add_child(_act_label)


func _build_top_right() -> void:
	var panel := _dark_panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN  # the panel grows to the left as its text needs room
	panel.offset_right = -MARGIN
	panel.offset_left = -MARGIN
	panel.offset_top = MARGIN
	add_child(panel)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(_status_label)


## The playtest tools, centred on top, only for a campaign being edited.
func _build_playtest_bar() -> void:
	_playtest_bar = HBoxContainer.new()
	_playtest_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_playtest_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_playtest_bar.offset_top = MARGIN
	_playtest_bar.add_theme_constant_override("separation", 12)
	_playtest_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_playtest_bar.visible = false
	add_child(_playtest_bar)
	auto_win_check = CheckBox.new()
	auto_win_check.text = "Auto-win missions"
	auto_win_check.tooltip_text = "Playtest: pressing Play on a mission counts it as won at once, without playing it. Narrative chapters are still read. Use 'count as lost' on a chapter to test a lost mission."
	_playtest_bar.add_child(auto_win_check)


# ---------------------------------------------------------------- bottom-left

func _build_bottom_left() -> void:
	var toggles := HBoxContainer.new()
	toggles.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	toggles.offset_left = MARGIN
	toggles.offset_top = -(MARGIN + TOGGLE_SIZE)
	toggles.offset_right = MARGIN + TOGGLE_SIZE * 2 + 8.0
	toggles.offset_bottom = -MARGIN
	toggles.add_theme_constant_override("separation", 8)
	toggles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toggles)
	var gear := _toggle_button("⚙")
	gear.pressed.connect(func():
		_party_menu.visible = false
		_gear_menu.visible = not _gear_menu.visible
	)
	toggles.add_child(gear)
	var party := _toggle_button("☲")
	party.pressed.connect(func():
		_gear_menu.visible = false
		_party_menu.visible = not _party_menu.visible
	)
	toggles.add_child(party)

	_gear_menu = _popup_menu()
	# a playtest started from the editor leaves through "Back to editor" instead of "Back to Menu" (the same place in the menu)
	back_to_editor_button = _menu_item(_gear_menu, "Back to Editor", func(): back_to_editor_pressed.emit())
	back_to_editor_button.visible = false
	back_to_menu_button = _menu_item(_gear_menu, "Back to Menu", func(): back_to_menu_pressed.emit())
	_menu_item(_gear_menu, "Options", func(): options_pressed.emit())
	_menu_item(_gear_menu, "Rules Reference", func(): rules_pressed.emit())
	_party_menu = _popup_menu()
	_menu_item(_party_menu, "Campaign Log", func(): log_pressed.emit())
	_menu_item(_party_menu, "Inventory", func(): inventory_pressed.emit())


func _toggle_button(glyph: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(TOGGLE_SIZE, TOGGLE_SIZE)
	btn.text = glyph
	btn.add_theme_font_size_override("font_size", 22)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.85)
	style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	return btn


## A stacked menu that grows UPWARD from just above the toggle row (same trick as PlayerHud._build_popup_menu()).
func _popup_menu() -> VBoxContainer:
	var menu := VBoxContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	menu.offset_left = MARGIN
	menu.offset_bottom = -(MARGIN + TOGGLE_SIZE + 8.0)
	menu.offset_top = menu.offset_bottom
	menu.offset_right = MARGIN + MENU_WIDTH
	menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	menu.add_theme_constant_override("separation", 4)
	menu.visible = false
	add_child(menu)
	return menu


func _menu_item(menu: VBoxContainer, text: String, action: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(MENU_WIDTH, 36)
	btn.pressed.connect(func():
		close_menus()
		action.call()
	)
	menu.add_child(btn)
	return btn
