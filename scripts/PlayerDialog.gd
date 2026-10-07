class_name PlayerDialog
extends Control

## Reusable dialog for the Player scene - pops up centered near the top of
## the screen (matches the original companion app's own prompt style) for
## the interaction patterns Player phase needs: confirming an instruction
## (OK), walking through narrative text (OK/NEXT/BACK), asking a yes/no
## question the table answers honestly (the app never sees real board
## state - see claude.md's Story layer section, "if they lie they ruin
## their own game"), or asking for a rolled/counted number.
##
## Built at runtime in _build_ui() rather than hand-authored in a .tscn -
## same reasoning as CreatorPalette: content and buttons change per call,
## nothing here would be static scene content anyway.
##
## Modal while visible: the root Control covers the full screen (a dim
## scrim, mouse_filter STOP - same STOP-blocks-everything-behind-it
## mechanism CreatorPalette's background bug worked through earlier this
## session, deliberately relied on here instead of worked around) so
## nothing else - camera look/zoom, the End Phase/Back buttons, the world -
## is reachable until the dialog is answered. The actual visible box (text
## + buttons) is a child positioned center-top within that full-rect root,
## not the root itself.
##
## Usage (all async - caller awaits the result):
##   await dialog.ask_ok("Place your figures in the highlighted area.")
##   await dialog.ask_ok("Bandit is hit!", true, true)  # large: fills most of the screen
##   var yes: bool = await dialog.ask_yes_no("Is a player on tile 2a?")
##   var n: int = await dialog.ask_count("How many successes did you roll?")
##   await dialog.ask_narrative(["Page one text...", "Page two text..."])
##   var i: int = await dialog.ask_choice("Do what?", ["Pick fruit", "Climb"])  # -1 = Cancel

const PANEL_WIDTH := 480.0
const LARGE_MARGIN := 80.0  ## ask_ok(..., large = true): gap to every screen edge
const LARGE_FONT_SIZE := 28

signal _closed(result: Variant)

var _label: Label
var _button_row: HBoxContainer
var _count_input: SpinBox
var _attack_preview: CombatMeshPreview
var _image_row: HBoxContainer
var _left_image: TextureRect
var _right_image: TextureRect
const IMAGE_WIDTH := 220.0

var _narrative_pages: Array[String] = []

## Voice control context: what the open dialog is asking ("ok"/"yes_no"/
## "count"/"choice"/"narrative", "" when closed), so speech can answer it - see
## try_voice_answer(). MissionPlayer sets voice_hints_enabled when a microphone
## is actually listening; the hint line under the buttons then tells the table
## what can be said.
var voice_hints_enabled: bool = false
## Quest log recorder (Journal.gd), set by MissionPlayer. ask_ok()/ask_narrative()
## record their text into it when given a non-empty `log_title`.
var journal: Journal
var _voice_kind: String = ""
var _voice_options: Array[String] = []  ## "choice": the option NAMES, in button order
var _hint_label: Label
var _buttons: Array[Button] = []
var _narrative_index: int = 0


func _ready() -> void:
	_build_ui()
	visible = false


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # the modal scrim - blocks everything behind it

	_scrim = ColorRect.new()
	var scrim := _scrim
	scrim.color = Color(0, 0, 0, 0.35)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE  # self (the root) already blocks; this is purely visual
	add_child(scrim)

	_panel = Control.new()
	var panel := _panel
	add_child(panel)
	_apply_panel_layout(false)

	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(background)

	var vbox := VBoxContainer.new()
	background.add_child(vbox)

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_label)

	# Optional image row (combat croptops): left = attacker, right = target.
	_image_row = HBoxContainer.new()
	_image_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_image_row.add_theme_constant_override("separation", 24)
	_image_row.visible = false
	vbox.add_child(_image_row)
	vbox.move_child(_image_row, 0)
	_left_image = TextureRect.new()
	_right_image = TextureRect.new()
	for img in [_left_image, _right_image]:
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.custom_minimum_size = Vector2(IMAGE_WIDTH, 0)
		_image_row.add_child(img)

	# The attacking monster's flat model (ask_monster_attack()) - on top of the box.
	_attack_preview = CombatMeshPreview.new()
	_attack_preview.custom_minimum_size = Vector2(320, 240)
	_attack_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attack_preview.visible = false
	vbox.add_child(_attack_preview)
	vbox.move_child(_attack_preview, 0)

	_count_input = SpinBox.new()
	_count_input.min_value = 0
	_count_input.max_value = 99
	_count_input.visible = false
	_count_input.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_count_input)

	_button_row = HBoxContainer.new()
	_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_button_row)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.modulate = Color(1, 1, 1, 0.65)
	_hint_label.visible = false
	vbox.add_child(_hint_label)


## The dim overlay behind the box - `ask_ok(text, false)` hides it so the
## scene behind stays fully visible (used to show monster miniatures on the
## map while telling the table where to put them). Reset to visible at the
## end of every dimless ask.
var _scrim: ColorRect


## The box holding the text + buttons; re-laid-out by _apply_panel_layout().
var _panel: Control


## Normal: a 480px box centered near the top. Large: fills most of the
## screen (margins on every side), with bigger, vertically centered text -
## used for moments that deserve the table's full attention (a hit).
func _apply_panel_layout(large: bool) -> void:
	if large:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_panel.custom_minimum_size = Vector2.ZERO
		_panel.offset_left = LARGE_MARGIN
		_panel.offset_right = -LARGE_MARGIN
		_panel.offset_top = LARGE_MARGIN
		_panel.offset_bottom = -LARGE_MARGIN
	else:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
		_panel.offset_left = -PANEL_WIDTH / 2.0
		_panel.offset_right = PANEL_WIDTH / 2.0
		_panel.offset_top = 16.0
		_panel.offset_bottom = 0.0
	if _label == null:  # first call, from _build_ui(), before the label exists
		return
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL if large else Control.SIZE_FILL
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if large else VERTICAL_ALIGNMENT_TOP
	if large:
		_label.add_theme_font_size_override("font_size", LARGE_FONT_SIZE)
	else:
		_label.remove_theme_font_size_override("font_size")


func ask_ok(text: String, dim: bool = true, large: bool = false, log_title: String = "", left_image: Texture2D = null, right_image: Texture2D = null) -> void:
	_set_images(left_image, right_image)
	_set_modal(dim)
	if log_title != "" and journal != null:
		journal.add(log_title, [text])
	_apply_panel_layout(large)
	_label.text = text
	_count_input.visible = false
	_set_buttons([{"text": "OK", "result": null}])
	_set_voice_context("ok")
	visible = true
	await _closed
	visible = false
	_set_modal(true)
	_set_images(null, null)
	if large:
		_apply_panel_layout(false)


## dim = false is the "placement" look: no scrim AND the rest of the screen
## stays interactive (only the dialog box itself blocks clicks), so the table
## can still move the camera while being told where to put things.
func _set_images(left: Texture2D, right: Texture2D) -> void:
	_image_row.visible = left != null or right != null
	for pair in [[_left_image, left], [_right_image, right]]:
		var img: TextureRect = pair[0]
		var tex: Texture2D = pair[1]
		img.texture = tex
		img.visible = tex != null
		# Keep the aspect ratio: height follows the texture's proportions.
		img.custom_minimum_size = Vector2(IMAGE_WIDTH, IMAGE_WIDTH * tex.get_height() / tex.get_width()) if tex != null else Vector2.ZERO


func _set_modal(dim: bool) -> void:
	_scrim.visible = dim
	mouse_filter = Control.MOUSE_FILTER_STOP if dim else Control.MOUSE_FILTER_IGNORE


## A MONSTER attacks (new 2026-10-05): the normal dialog box with the monster's flat
## model on top and `cfg["text"]` (who attacks whom, damage, range, abilities), exactly as
## much as the real game shows. Two buttons: "Continue" (0 - the table has resolved the
## attack itself) and "Interrupt" (1 - the players act BEFORE the monster's attack, e.g. an
## ability that lets a hero attack first; the caller hands control back and shows this
## dialog again afterwards if the monster survived). `cfg` also carries
## MonsterDisplay.preview_data() for the model. Answerable by voice ("continue",
## "interrupt").
func ask_monster_attack(cfg: Dictionary) -> int:
	_set_images(null, null)
	_set_modal(true)
	var meshes: Array = cfg.get("monster_flat_meshes", [])
	if not meshes.is_empty():
		var paths: Array[String] = []
		for path in meshes:
			paths.append(str(path))
		var size_units: float = cfg.get("monster_size_units", 1.0)
		_attack_preview.show_meshes(paths, cfg.get("monster_flat_texture"), cfg.get("monster_flat_rotation", Vector3.ZERO), cfg.get("monster_flat_surface_overrides", {}), size_units, size_units, false)
	else:
		_attack_preview.show_quad(cfg.get("monster_image"))
	_attack_preview.visible = true
	_label.text = cfg.get("text", "")
	_count_input.visible = false
	_set_buttons([{"text": "Continue", "result": 0}, {"text": "Interrupt", "result": 1}])
	_set_voice_context("choice", ["Continue", "Interrupt"])
	visible = true
	var result: int = await _closed
	visible = false
	_attack_preview.visible = false
	return result


## The full-screen combat screen (CombatView): asks for the number of
## successes rolled. Returns -1 if cancelled (the view is closed then). `cfg` is
## CombatView.configure()'s dictionary. Voice answers work like ask_count() (the
## number is spoken, then Confirm is pressed).
## The conditions toggled in the view's Conditions dialog are left in
## `attack_conditions` (empty when the successes screen was skipped).
## **On Confirm the view STAYS OPEN** - the caller resolves the attack and then
## MUST call ask_attack_outcome(), which shows the result on this same screen
## and closes it.
func ask_attack(cfg: Dictionary) -> int:
	_ensure_combat()
	attack_conditions = []
	_count_input.min_value = 0
	_count_input.max_value = 99
	_count_input.value = 0
	_combat.configure(cfg)
	_enter_combat_view([_combat.confirm_button, _combat.cancel_button])
	_set_voice_context("count")
	visible = true
	var result: Variant = await _closed
	if typeof(result) == TYPE_INT and result == -1:
		_leave_combat_view()
		return -1
	attack_conditions = _combat.selected_conditions.duplicate()
	return int(_count_input.value)


## The result of an attack, shown on the combat screen itself (CombatView.
## show_outcome(): calculation top-left, health bar dropping, weakness/resistance
## revealed). `pre_cfg` is the combat cfg as it was shown for the successes
## screen (known_* lists as they were BEFORE the attack), `post_cfg` the same
## with the monster's post-attack known_* lists, `outcome` the MissionRuntime.
## resolve_attack() breakdown. A second click
## on Confirm (or saying "ok") closes the view. If ask_attack() wasn't shown for
## this attack (the roll was spoken in the command) the view is opened first.
## `log_text` goes to the quest log under `log_title` when given, like ask_ok().
func ask_attack_outcome(pre_cfg: Dictionary, post_cfg: Dictionary, outcome: Dictionary, log_text: String = "", log_title: String = "") -> void:
	_ensure_combat()
	if log_title != "" and journal != null:
		journal.add(log_title, [log_text])
	if not _combat_open:
		# The PRE-attack cfg goes through configure() so the newly discovered
		# entries still animate in below.
		_combat.configure(pre_cfg)
		_enter_combat_view([_combat.confirm_button])
	_combat.show_outcome(post_cfg, outcome)
	_buttons = [_combat.confirm_button]
	_set_voice_context("ok")
	visible = true
	await _closed
	_leave_combat_view()


## The combat view's weapon-choice stage (CombatView.show_choice(), `cfg` as
## documented there): returns the picked option's index (0/1), or -1 if
## cancelled. Answerable by voice like ask_choice() (the weapon names).
func ask_weapon(cfg: Dictionary) -> int:
	_ensure_combat()
	_combat.show_choice(cfg)
	_enter_combat_view([_combat.choice_buttons[0], _combat.choice_buttons[1], _combat.choice_cancel_button])
	var names: Array[String] = []
	for option: Dictionary in cfg.get("options", []):
		names.append(str(option.get("name", "")))
	_set_voice_context("choice", names)
	visible = true
	var result: Variant = await _closed
	_leave_combat_view()
	return int(result)


func _ensure_combat() -> void:
	if _combat != null:
		return
	_combat = CombatView.new()
	add_child(_combat)
	_combat.step_requested.connect(func(delta: int): _count_input.value = clampi(int(_count_input.value) + delta, int(_count_input.min_value), int(_count_input.max_value)))
	_count_input.value_changed.connect(func(v: float): _combat.show_value(int(v)))
	_combat.confirm_button.pressed.connect(_on_button_pressed.bind(null))
	_combat.cancel_button.pressed.connect(_on_button_pressed.bind(-1))
	_combat.choice_buttons[0].pressed.connect(_on_button_pressed.bind(0))
	_combat.choice_buttons[1].pressed.connect(_on_button_pressed.bind(1))
	_combat.choice_cancel_button.pressed.connect(_on_button_pressed.bind(-1))


## Shows the full-screen view in place of the normal dialog box. Call AFTER the
## CombatView stage method (its hint_label depends on the stage). Safe to call
## again while the view is already open (a stage change) - only the buttons and
## hint label are re-pointed then.
func _enter_combat_view(buttons: Array[Button]) -> void:
	_scrim.visible = false
	_panel.visible = false
	_combat.visible = true
	_buttons = buttons
	if not _combat_open:
		_combat_saved_hint = _hint_label
		_combat_open = true
	_hint_label = _combat.hint_label


func _leave_combat_view() -> void:
	visible = false
	_combat_open = false
	if _combat_saved_hint != null:
		_hint_label = _combat_saved_hint
		_combat_saved_hint = null
	_combat.visible = false
	_panel.visible = true
	_scrim.visible = true


var attack_conditions: Array[int] = []  ## MonsterCondition.Kind values chosen during the last ask_attack()
var _combat_open: bool = false
var _combat_saved_hint: Label


var _combat: CombatView


func ask_yes_no(text: String) -> bool:
	_label.text = text
	_count_input.visible = false
	_set_buttons([{"text": "Yes", "result": true}, {"text": "No", "result": false}])
	_set_voice_context("yes_no")
	visible = true
	var result: bool = await _closed
	visible = false
	return result


func ask_count(text: String, min_value: int = 0, max_value: int = 99, left_image: Texture2D = null, right_image: Texture2D = null) -> int:
	_set_images(left_image, right_image)
	_label.text = text
	_count_input.min_value = min_value
	_count_input.max_value = max_value
	_count_input.value = min_value
	_count_input.visible = true
	_set_buttons([{"text": "OK", "result": null}])  # actual answer is read from _count_input below
	_set_voice_context("count")
	visible = true
	await _closed
	visible = false
	_set_images(null, null)
	return int(_count_input.value)


## Offers `option_labels` as buttons (one per entry, in order - result is
## that entry's index) plus a trailing "Cancel" button (result -1) -
## Cancel is always present, never omitted, so the caller never has to
## build its own "and let them back out" affordance. Used by
## PlayerInteractionController's action picker (new 2026-09-14 - "which
## of this prop's currently-available actions do you mean?").
## `option_disabled` (new 2026-09-14, e.g. an exhausted single_shot
## PropAction - see MissionRuntime.available_actions()/PropAction's own
## doc) greys out that option's button rather than omitting it, so the
## player can see it exists but can no longer be chosen. Defaults to all
## enabled - a shorter (or empty) array than option_labels just leaves the
## remaining ones enabled.
func ask_choice(text: String, option_labels: Array[String], option_disabled: Array[bool] = [], allow_cancel: bool = true) -> int:
	_label.text = text
	_count_input.visible = false
	var specs: Array = []
	for i in option_labels.size():
		var disabled: bool = option_disabled[i] if i < option_disabled.size() else false
		specs.append({"text": option_labels[i], "result": i, "disabled": disabled})
	if allow_cancel:
		specs.append({"text": "Cancel", "result": -1})
	_set_buttons(specs)
	var names: Array[String] = []
	for label in option_labels:
		names.append(VoiceAnswerParser.option_name(label))
	_set_voice_context("choice", names)
	visible = true
	var result: int = await _closed
	visible = false
	return result


## `on_page` (optional) is called with the page index every time a page is
## shown (also when going Back) - lets the caller sync the scene to the page.
func ask_narrative(pages: Array[String], log_title: String = "", dim: bool = true, on_page: Callable = Callable()) -> void:
	_narrative_page_callback = on_page
	_set_modal(dim)
	if log_title != "" and journal != null:
		journal.add(log_title, pages)
	_narrative_pages = pages
	_narrative_index = 0
	_count_input.visible = false
	_show_narrative_page()
	_set_voice_context("narrative")
	visible = true
	await _closed
	visible = false
	_set_modal(true)
	_narrative_page_callback = Callable()


var _narrative_page_callback: Callable


func _show_narrative_page() -> void:
	if _narrative_page_callback.is_valid():
		_narrative_page_callback.call(_narrative_index)
	_label.text = _narrative_pages[_narrative_index]
	var specs: Array = []
	if _narrative_index > 0:
		specs.append({"text": "Back", "result": "_back"})
	if _narrative_index < _narrative_pages.size() - 1:
		specs.append({"text": "Next", "result": "_next"})
	else:
		specs.append({"text": "OK", "result": null})
	_set_buttons(specs)


func _set_buttons(specs: Array) -> void:
	for child in _button_row.get_children():
		child.queue_free()
	_buttons.clear()
	for spec in specs:
		var btn := Button.new()
		btn.text = spec["text"]
		btn.disabled = spec.get("disabled", false)
		btn.pressed.connect(_on_button_pressed.bind(spec["result"]))
		_button_row.add_child(btn)
		_buttons.append(btn)


## "_next"/"_back" are internal sentinels for ask_narrative() - they advance
## the page and rebuild buttons instead of resolving the await, unlike
## every other result value (null/true/false/int - ask_choice()'s option
## indices/-1 for Cancel), which closes the dialog. The typeof() guard is
## required, not just style: GDScript's `==` throws "Invalid operands
## 'int' and 'String'" (a runtime error, not a false result) when compared
## against an incompatible Variant type pair like int vs String - which
## ask_choice()'s int results hit the moment they reached the bare
## `result == "_next"` check below, since every button (regardless of
## which ask_*() call made it) funnels through this one handler.
func _on_button_pressed(result: Variant) -> void:
	if typeof(result) == TYPE_STRING:
		if result == "_next":
			_narrative_index += 1
			_show_narrative_page()
			return
		if result == "_back":
			_narrative_index -= 1
			_show_narrative_page()
			return
	_voice_kind = ""
	_hint_label.visible = false
	_closed.emit(result)


# ---------------------------------------------------------------- voice answers

func _set_voice_context(kind: String, options: Array[String] = []) -> void:
	_voice_kind = kind
	_voice_options = options
	_show_voice_hint("")


## The line under the buttons telling the table what it can say right now
## (only when a microphone is listening). `problem` is prefixed when the last
## spoken answer wasn't understood.
func _show_voice_hint(problem: String) -> void:
	if not voice_hints_enabled or _voice_kind == "":
		_hint_label.visible = false
		return
	var hint := ""
	match _voice_kind:
		"ok":
			hint = "Say \"ok\""
		"yes_no":
			hint = "Say \"yes\" or \"no\""
		"count":
			hint = "Say a sentence with the number, like \"I rolled three\" (%d to %d)" % [int(_count_input.min_value), int(_count_input.max_value)]
		"narrative":
			hint = "Say \"next\" or \"ok\" (or \"back\")"
		"choice":
			var parts: Array[String] = []
			for i in _voice_options.size():
				parts.append("%d: %s" % [i + 1, _voice_options[i]])
			hint = "Say a sentence, like \"use the %s\", or a number - %s - or \"cancel\"" % [_voice_options[0].to_lower() if not _voice_options.is_empty() else "sword", " | ".join(parts)]
	_hint_label.text = (problem + " - " if problem != "" else "") + "Voice - " + hint
	_hint_label.visible = true


## A sample of what can be said to the open dialog, phrased as sentences, for
## the speech recogniser's prompt (single words are hard for it, sentences work
## - "sword" alone was never heard, "attack John with sword" was). "" when no
## dialog is open or nothing useful applies.
func voice_prompt() -> String:
	if not visible:
		return ""
	match _voice_kind:
		"count":
			return "I rolled three."
		"choice":
			var sentences: Array[String] = []
			for i in mini(_voice_options.size(), 3):
				sentences.append("I use the %s." % _voice_options[i].to_lower())
			return " ".join(sentences)
	return ""


## Answers the open dialog from speech (see VoiceAnswerParser): presses the
## button the words pick, entering the number first for a count question.
## Returns true if an answer was applied. Called by PlayerCommandRunner
## instead of treating the speech as a command whenever a dialog is open.
func try_voice_answer(text: String) -> bool:
	if not visible or _voice_kind == "":
		return false
	if _combat_open and _combat.conditions_dialog_open():
		return false  # a spoken answer must not act on the combat view behind the Conditions dialog
	match _voice_kind:
		"ok":
			if VoiceAnswerParser.is_ok(text):
				return _press(0)
			_show_voice_hint("Didn't catch that")
		"yes_no":
			if VoiceAnswerParser.is_no(text):
				return _press(1)
			if VoiceAnswerParser.is_yes(text):
				return _press(0)
			_show_voice_hint("Didn't catch that")
		"count":
			var number := VoiceAnswerParser.parse_number(text)
			if number < int(_count_input.min_value) or number > int(_count_input.max_value):
				_show_voice_hint("Didn't catch a number in range")
				return false
			_count_input.value = number
			return _press(0)
		"narrative":
			if VoiceAnswerParser.is_back(text):
				return _press_text("Back")
			if VoiceAnswerParser.is_ok(text):
				return _press_text("Next") or _press_text("OK")
			_show_voice_hint("Didn't catch that")
		"choice":
			var picked := VoiceAnswerParser.match_choice(text, _voice_options)
			match picked:
				VoiceAnswerParser.CHOICE_CANCEL:
					return _press(_buttons.size() - 1)  # the trailing Cancel button
				VoiceAnswerParser.CHOICE_NONE:
					_show_voice_hint("Didn't catch which option")
				VoiceAnswerParser.CHOICE_AMBIGUOUS:
					_show_voice_hint("More than one matches - say a number")
				_:
					if _press(picked):
						return true
					_show_voice_hint("That option isn't available")
	return false


## Presses the button at `index` unless it's missing or disabled.
func _press(index: int) -> bool:
	if index < 0 or index >= _buttons.size() or _buttons[index].disabled:
		return false
	_buttons[index].pressed.emit()
	return true


func _press_text(button_text: String) -> bool:
	for i in _buttons.size():
		if _buttons[i].text == button_text:
			return _press(i)
	return false
