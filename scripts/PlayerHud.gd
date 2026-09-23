class_name PlayerHud
extends Control

## First pass at reworking the Player's HUD chrome toward a real mockup
## layout (screenshots supplied 2026-09-23): two circular icon buttons
## top-right, and a Gear/Party icon pair bottom-left that each pop a small
## stacked menu of buttons ABOVE themselves. The
## objective text, phase text, and End Phase button stay MissionPlayer's
## own `.tscn` nodes (just repositioned/restyled there) - this script only
## builds the pieces that didn't exist at all before.
##
## Per the user's own framing ("we can make mocks for all menu items, we
## will implement them one by one"): every menu item started as a pure
## mock - click it and it just tells the table it isn't built yet, via
## PlayerDialog. Several are real now, added one at a time the same day:
##  - "Back to Menu" (Gear menu) - MissionPlayer's pre-existing "leave the
##    mission" action, relocated out of its own standalone always-visible
##    button (the mockup's "the back to main menu is in the menu").
##  - The two top-right icons - "Quest" switches to the map/world view,
##    "Threat" switches to the monster view, both via `show_map`/
##    `show_monsters` - the same swap the M key and the "show map"/"show
##    monsters" voice commands already drive (MissionPlayer.
##    _set_monster_display_visible()).
##  - "Options" (Gear menu) opens `open_voice_settings` - VoiceSettingsDialog,
##    the new home for everything about CONFIGURING voice control (see that
##    script's own class doc).
##  - "Rules Reference" (Gear menu) just opens the official rulebook PDF in
##    the system browser (`OS.shell_open()`) - a link to Fantasy Flight's
##    own hosted copy, nothing of theirs bundled or reproduced here.
## Everything else in GEAR_ITEMS/PARTY_ITEMS is still a pure mock.
##
## Built entirely in code (same "dynamic content, no reason for static
## .tscn nodes" convention as CreatorToolbar/EmbarkDialog/PlayerDialog/...)
## and added as a plain child by MissionPlayer._ready() - not a scene-file
## node, since it needs `dialog`/`back_to_menu` wired in right after
## construction anyway (same "runtime-constructed object, plain var, no
## @export/NodePath" pattern PropertiesDialog/ObjectivesDialog use).
##
## No real icon art (this project ships zero copyrighted game assets, see
## claude.md's "Official asset overrides") - each icon button is a flat
## coloured circle with a short text label, same "generated placeholder,
## not a real asset" approach HeroCatalog's own dummy portraits use.

## Assigned by MissionPlayer._ready() - both the mock-item "not implemented"
## dialog and (implicitly, since PlayerDialog is modal) what keeps a mock
## click from fighting an already-open real dialog.
var dialog: PlayerDialog
## MissionPlayer._on_back_button_pressed - the one non-mock menu item.
var back_to_menu: Callable
## MissionPlayer._set_monster_display_visible.bind(false)/(true) - the top-
## right "Quest" icon switches back to the map/world view, "Threat" switches
## to the monster view (the same swap the M key and the "show map"/"show
## monsters" voice commands already trigger). Unlike everything else in this
## script these two are real, not mocks - see the class doc above.
var show_map: Callable
var show_monsters: Callable
## VoiceSettingsDialog.open - the Gear menu's "Options" item.
var open_voice_settings: Callable

## The official rulebook PDF, hosted by Fantasy Flight Games themselves -
## opened in the system browser (OS.shell_open()) by "Rules Reference", not
## fetched/embedded/redistributed by this project in any way.
const RULES_REFERENCE_URL := "https://images-cdn.fantasyflightgames.com/filer_public/fb/fa/fbfa5691-0f11-4ef5-8a51-69cdcfe0ac7c/dle01_rulebook_web.pdf"

## The "Threat"/"Quest" icons' dummy placeholders (a user's own official
## "Button_EnemyView"/"Button_MapView" art replaces them if present - see
## OfficialAssetMap.MAP).
const THREAT_ICON_PATH := "res://models/hud_threat.png"
const QUEST_ICON_PATH := "res://models/hud_quest.png"

const GEAR_ITEMS: Array[String] = ["Line of Sight", "Options", "Rules Reference", "Save"]
const PARTY_ITEMS: Array[String] = ["Quest Log", "Campaign Log", "Feats", "Heroes", "Inventory"]

const ICON_SIZE := 64.0
const TOGGLE_SIZE := 48.0
const MARGIN := 12.0

var _gear_button: Button
var _party_button: Button
var _gear_menu: VBoxContainer
var _party_menu: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # only the actual buttons below should catch clicks
	_build_top_right()
	_build_bottom_left()


# ---------------------------------------------------------------- top-right

func _build_top_right() -> void:
	var icons := HBoxContainer.new()
	icons.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	icons.offset_left = -(MARGIN + ICON_SIZE * 2 + 8.0)
	icons.offset_top = MARGIN
	icons.offset_right = -MARGIN
	icons.offset_bottom = MARGIN + ICON_SIZE
	icons.add_theme_constant_override("separation", 8)
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icons)
	icons.add_child(_round_icon_button("Quest", Color(0.2, 0.4, 0.65), _on_quest_pressed, QUEST_ICON_PATH))
	icons.add_child(_round_icon_button("Threat", Color(0.55, 0.22, 0.08), _on_threat_pressed, THREAT_ICON_PATH))


## `icon_path` (new 2026-09-23, "Threat", then "Quest" the same day) swaps
## the plain text label for a real texture - the shipped dummy placeholder,
## or a user's own official art if present (OfficialAssetOverrides.
## texture_for(), same override mechanism HeroCatalog.slot_portrait()
## already uses - see that class's own doc). Left "" (nothing currently
## does), a button keeps the flat-colour-circle-plus-text look every icon
## here started with.
func _round_icon_button(label_text: String, color: Color, on_pressed: Callable, icon_path: String = "") -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(ICON_SIZE / 2.0))  # square button, round corners -> reads as a circle
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", style)
	if icon_path != "":
		btn.icon = OfficialAssetOverrides.texture_for(icon_path)
		btn.expand_icon = true
	else:
		btn.text = label_text
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(on_pressed)
	return btn


func _on_quest_pressed() -> void:
	if show_map.is_valid():
		show_map.call()


func _on_threat_pressed() -> void:
	if show_monsters.is_valid():
		show_monsters.call()


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

	_gear_button = _toggle_button("⚙")  # gear glyph
	_gear_button.pressed.connect(_on_gear_pressed)
	toggles.add_child(_gear_button)

	_party_button = _toggle_button("☲")  # generic "group" glyph stand-in
	_party_button.pressed.connect(_on_party_pressed)
	toggles.add_child(_party_button)

	# "Back to Menu" first (the one real item, see class doc), then the mocks.
	# "+" between an untyped literal and a typed Array[String] produces a
	# plain untyped Array, not Array[String] - _build_popup_menu() takes a
	# typed one, so this builds it explicitly instead of via "+".
	var gear_items: Array[String] = ["Back to Menu"]
	gear_items.append_array(GEAR_ITEMS)
	_gear_menu = _build_popup_menu(gear_items)
	_party_menu = _build_popup_menu(PARTY_ITEMS)


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


## A `VBoxContainer` pinned by its BOTTOM-left corner, just above the toggle
## row, starting hidden and empty of height - `grow_vertical =
## GROW_DIRECTION_BEGIN` makes it grow UPWARD as its buttons give it a
## larger minimum size, instead of Godot's default (grow down/both), which
## is what actually produces the "stacks above the icon" look the mockup
## shows, with no manual height math needed.
func _build_popup_menu(items: Array[String]) -> VBoxContainer:
	var menu := VBoxContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	menu.offset_left = MARGIN
	menu.offset_bottom = -(MARGIN + TOGGLE_SIZE + 8.0)
	menu.offset_top = menu.offset_bottom
	menu.offset_right = MARGIN + 180.0
	menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	menu.add_theme_constant_override("separation", 4)
	menu.visible = false
	add_child(menu)
	for item in items:
		var btn := Button.new()
		btn.text = item
		btn.custom_minimum_size = Vector2(180, 36)
		match item:
			"Back to Menu":
				btn.pressed.connect(_on_back_to_menu_pressed)
			"Options":
				btn.pressed.connect(_on_options_pressed)
			"Rules Reference":
				btn.pressed.connect(_on_rules_reference_pressed)
			_:
				btn.pressed.connect(_on_mock_item_pressed.bind(item))
		menu.add_child(btn)
	return menu


func _on_gear_pressed() -> void:
	_party_menu.visible = false
	_gear_menu.visible = not _gear_menu.visible


func _on_party_pressed() -> void:
	_gear_menu.visible = false
	_party_menu.visible = not _party_menu.visible


func _on_back_to_menu_pressed() -> void:
	_gear_menu.visible = false
	if back_to_menu.is_valid():
		back_to_menu.call()


func _on_mock_item_pressed(item_name: String) -> void:
	_gear_menu.visible = false
	_party_menu.visible = false
	if dialog != null:
		await dialog.ask_ok("%s - not yet implemented." % item_name)


func _on_options_pressed() -> void:
	_gear_menu.visible = false
	if open_voice_settings.is_valid():
		open_voice_settings.call()


func _on_rules_reference_pressed() -> void:
	_gear_menu.visible = false
	OS.shell_open(RULES_REFERENCE_URL)
