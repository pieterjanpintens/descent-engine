class_name MonsterSidebar
extends Control

## The monsters on the board as a column of cards on the right of the Player's map view (MonsterTabCard), like the original game: the figure,
## its colour chip, health and level. At most MAX_VISIBLE cards fit; with more monsters the column scrolls with the mouse wheel while the pointer is
## over it (the wheel is then not used for the camera there): the card in the middle is in front, the ones at the ends lean away and fade, which
## also tells there is more above or below. The monster view has its own display, so the column is hidden there (and while heroes are picked).
##
## `set_monsters(MissionRuntime.monsters)` on every change; cards are kept per monster so a health change does not move the scroll position.
## `monster_at()` / `set_hovered()` serve the attack by dropping a hero on a card.

const MAX_VISIBLE := 5
const GAP := 6.0
const SCROLL_SECONDS := 0.25
const RIGHT_MARGIN := 18.0
const SIDE_SQUASH := 0.1     ## how much smaller a card next to the middle one looks, as if it were turned away
const FAR_SQUASH := 0.12

var _cards: Dictionary = {}  ## monster id -> MonsterTabCard
var _monsters: Dictionary = {}  ## monster id -> RuntimeMonster (what a card stands for)
var _order: Array[String] = []
var _scroll := 0.0           ## the card index at the top of the window (fractional while it moves)
var _target := 0             ## where the scroll is heading
var _scroll_tween: Tween
var _up_hint: Label
var _down_hint: Label
var _map_view_shown := true
var _allowed := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # PASS while there is something to scroll, see _update_scrollable()
	clip_contents = false
	visible = false
	_up_hint = _hint("▲")
	_down_hint = _hint("▼")


func _hint(glyph: String) -> Label:
	var label := Label.new()
	label.text = glyph
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	add_child(label)
	return label


## Where the column sits: `top` is the y of its first card (under the Quest / Threat icons).
func place(top: float) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	var height := MAX_VISIBLE * (MonsterTabCard.CARD_SIZE.y + GAP)
	offset_left = -(RIGHT_MARGIN + MonsterTabCard.CARD_SIZE.x)
	offset_right = -RIGHT_MARGIN
	offset_top = top
	offset_bottom = top + height
	_layout()


func set_monsters(monsters: Array) -> void:
	var seen := {}
	_order.clear()
	_monsters.clear()
	for monster: RuntimeMonster in monsters:
		seen[monster.id] = true
		_monsters[monster.id] = monster
		_order.append(monster.id)
		var card: MonsterTabCard = _cards.get(monster.id)
		if card == null:
			card = MonsterTabCard.new()
			add_child(card)
			_cards[monster.id] = card
		card.show_monster(monster)
	for id in _cards.keys():
		if not seen.has(id):
			var gone: MonsterTabCard = _cards[id]
			remove_child(gone)
			gone.queue_free()
			_cards.erase(id)
	_target = clampi(_target, 0, _max_scroll())
	_scroll = clampf(_scroll, 0.0, float(_max_scroll()))
	_update_scrollable()
	_layout()
	_apply_visibility()


## The monster whose card is under this screen position (the one in front when cards overlap), null when none. Only while the column is on screen.
func monster_at(screen_pos: Vector2) -> RuntimeMonster:
	if not is_visible_in_tree():
		return null
	var best: MonsterTabCard = null
	for card: MonsterTabCard in _cards.values():
		if card.visible and card.modulate.a > 0.35 and card.contains_screen_point(screen_pos):
			if best == null or card.z_index > best.z_index:
				best = card
	return _monsters.get(best.monster_id) if best != null else null


## Lights up the card of `monster` (null = none): the target a dragged hero is over.
func set_hovered(monster: RuntimeMonster) -> void:
	var id := monster.id if monster != null else ""
	for card: MonsterTabCard in _cards.values():
		card.set_highlighted(card.monster_id == id and id != "")


## The map view shows the column, the monster view does not.
func set_map_view(shown: bool) -> void:
	_map_view_shown = shown
	_apply_visibility()


## Off during hero selection.
func set_allowed(allowed: bool) -> void:
	_allowed = allowed
	_apply_visibility()


func _apply_visibility() -> void:
	visible = _allowed and _map_view_shown and not _order.is_empty()


func _max_scroll() -> int:
	return maxi(_order.size() - MAX_VISIBLE, 0)


## The wheel is only taken over the column when there is something to scroll (PASS: clicks and drops still reach the game below, but the
## camera - which leaves the wheel alone over a control - does not zoom there).
func _update_scrollable() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS if _max_scroll() > 0 else Control.MOUSE_FILTER_IGNORE


func _gui_input(event: InputEvent) -> void:
	if _max_scroll() <= 0 or not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		scroll_by(1)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		scroll_by(-1)
		accept_event()


## Moves the window by `steps` cards (limited to the ends).
func scroll_by(steps: int) -> void:
	var target := clampi(_target + steps, 0, _max_scroll())
	if target == _target:
		return
	_target = target
	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.tween_method(_set_scroll, _scroll, float(_target), SCROLL_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_scroll(value: float) -> void:
	_scroll = value
	_layout()


func _layout() -> void:
	var count := _order.size()
	var card_size := MonsterTabCard.CARD_SIZE
	var step := card_size.y + GAP
	var hidden_above := 0.0
	var hidden_below := 0.0
	if count > MAX_VISIBLE:
		hidden_above = clampf(_scroll, 0.0, 1.0)
		hidden_below = clampf(float(_max_scroll()) - _scroll, 0.0, 1.0)
	_up_hint.visible = hidden_above > 0.5
	_down_hint.visible = hidden_below > 0.5
	_up_hint.position = Vector2(0.0, -16.0)
	_up_hint.size = Vector2(card_size.x, 14.0)
	_down_hint.position = Vector2(0.0, MAX_VISIBLE * step - GAP + 2.0)
	_down_hint.size = Vector2(card_size.x, 14.0)
	if count == 0:
		return
	# the window's middle, in card indices; a card's distance from it decides its place, size and fade - only on the side where more is hidden
	var middle := _scroll + (MAX_VISIBLE - 1) / 2.0
	var middle_y := (MAX_VISIBLE * step - GAP) / 2.0 - card_size.y / 2.0
	var reach := MAX_VISIBLE / 2.0 + 0.05
	for index in count:
		var card: MonsterTabCard = _cards[_order[index]]
		var distance := float(index) - middle
		var away := absf(distance)
		card.visible = away < reach
		if not card.visible:
			continue
		var lean := hidden_above if distance < 0.0 else hidden_below  # 0 = nothing more in that direction: the card is shown plainly
		var near := minf(away, 1.0) * lean
		var beyond := clampf(away - 1.0, 0.0, 2.0) * lean
		card.scale = Vector2.ONE * (1.0 - SIDE_SQUASH * near - FAR_SQUASH * beyond * 0.5)
		var offset := signf(distance) * step * (minf(away, 1.0) + maxf(away - 1.0, 0.0) * lerpf(1.0, 0.9, lean))
		card.position = Vector2(0.0, middle_y + offset)
		var shade := lerpf(1.0, 0.7, near) - 0.08 * beyond
		var alpha := 1.0 - lean * clampf(away - (reach - 1.0), 0.0, 1.0)
		card.modulate = Color(shade, shade, shade, alpha)
		card.z_index = 100 - int(roundf(away * 10.0))
