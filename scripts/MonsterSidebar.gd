class_name MonsterSidebar
extends Control

## The monsters on the board as a column of cards on the right of the Player's map view (MonsterTabCard), like the original game: the figure,
## its colour chip, health and level. At most MAX_VISIBLE cards fit; with more monsters the column turns like the load page's rows - the card in
## the middle is in front, the others lean away above and below it - one step every ROTATE_SECONDS, round and round. The monster view has its
## own display, so the column is hidden there (and while heroes are picked).
##
## `set_monsters(MissionRuntime.monsters)` on every change; cards are kept per monster so a health change does not restart the turning.

const MAX_VISIBLE := 5
const GAP := 6.0
const ROTATE_SECONDS := 3.0
const FOCUS_SECONDS := 0.55
const RIGHT_MARGIN := 18.0
const SIDE_SQUASH := 0.1     ## how much smaller a card next to the middle one looks, as if it were turned away
const FAR_SQUASH := 0.12

var _cards: Dictionary = {}  ## monster id -> MonsterTabCard
var _monsters: Dictionary = {}  ## monster id -> RuntimeMonster (what a card stands for)
var _order: Array[String] = []
var _focus := 0.0
var _focus_tween: Tween
var _timer: Timer
var _map_view_shown := true
var _allowed := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	visible = false
	_timer = Timer.new()
	_timer.wait_time = ROTATE_SECONDS
	_timer.timeout.connect(_turn_one_step)
	add_child(_timer)


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
	_timer_state()
	_layout()
	_apply_visibility()


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


## Turning only when there are more monsters than places.
func _timer_state() -> void:
	var needs := _order.size() > MAX_VISIBLE
	if needs and _timer.is_stopped():
		_timer.start()
	elif not needs:
		_timer.stop()
		_stop_tween()
		_focus = 0.0


func _turn_one_step() -> void:
	if _order.size() <= MAX_VISIBLE or not is_visible_in_tree():
		return
	_stop_tween()
	_focus_tween = create_tween()
	_focus_tween.tween_method(_set_focus, _focus, _focus + 1.0, FOCUS_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _stop_tween() -> void:
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = null


func _set_focus(value: float) -> void:
	_focus = fposmod(value, float(maxi(_order.size(), 1)))
	_layout()


func _layout() -> void:
	var count := _order.size()
	if count == 0:
		return
	var card_size := MonsterTabCard.CARD_SIZE
	var step := card_size.y + GAP
	if count <= MAX_VISIBLE:  # everything fits: a plain column
		for index in count:
			var plain: MonsterTabCard = _cards[_order[index]]
			plain.visible = true
			plain.scale = Vector2.ONE
			plain.modulate = Color.WHITE
			plain.z_index = 0
			plain.position = Vector2(0.0, index * step)
		return
	# more than fit: a turning column. A card's distance from the middle is its place in the circle, so the first one follows the last.
	var middle_y := (MAX_VISIBLE * step - GAP) / 2.0 - card_size.y / 2.0
	var reach := MAX_VISIBLE / 2.0 + 0.05  # beyond this the card is not shown (the cards at the ends fade out before it)
	for index in count:
		var card: MonsterTabCard = _cards[_order[index]]
		var distance := fposmod(float(index) - _focus + count / 2.0, float(count)) - count / 2.0
		var away := absf(distance)
		var near := minf(away, 1.0)
		var beyond := clampf(away - 1.0, 0.0, 2.0)
		card.visible = away < reach
		if not card.visible:
			continue
		card.scale = Vector2.ONE * (1.0 - SIDE_SQUASH * near - FAR_SQUASH * beyond * 0.5)
		var offset := signf(distance) * step * (near + maxf(away - 1.0, 0.0) * 0.9)
		card.position = Vector2(0.0, middle_y + offset)
		var shade := lerpf(1.0, 0.7, near) - 0.08 * beyond
		card.modulate = Color(shade, shade, shade, 1.0 - clampf((away - (reach - 1.0)) / 1.0, 0.0, 1.0))
		card.z_index = 100 - int(roundf(away * 10.0))
