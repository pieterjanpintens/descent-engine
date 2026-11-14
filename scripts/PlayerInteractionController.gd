class_name PlayerInteractionController
extends Control

## Drag-to-interact UI for the Player scene, matching the original
## companion app's own gesture: drag a hero's portrait out onto the world
## to indicate that hero is interacting with something. The game's own
## rule ("only interact with what you're physically adjacent to") isn't
## enforced here - that needs real player-position tracking, which doesn't
## exist (see claude.md's Story layer section).
##
## Scope for this first pass (see claude.md's Open items):
##   1. UI + drag detection - the party set during EmbarkDialog (see
##      set_roster()) shown as a row of placeholder portraits, dragging one
##      draws a line toward the cursor.
##   2. Interactable props (InteractableEntry with props["interactible"]
##      not explicitly false, AND at least one action whose own
##      `conditions` currently hold - see MissionRuntime.
##      first_available_action(), new 2026-09-14) highlight while a drag
##      hovers over them.
##   3. Releasing a drag over an interactable presents every CURRENTLY-
##      AVAILABLE action (MissionRuntime.available_actions() - conditions
##      gate which ones are even offered) as a choice via a
##      PlayerDialog.ask_choice() picker (new 2026-09-14, see
##      _offer_actions()) - Cancel is always included alongside them.
##      Picking one fires it via MissionRuntime.fire_prop_action().
##
## Deliberately NOT using Godot's built-in Control drag-and-drop system
## (_get_drag_data/_drop_data) - the drop target here is a 3D world
## position found by raycasting, not another Control, so manual mouse
## tracking is more direct than fighting that system to reach underneath it.

## Fired when firing a PropAction resolves an objective node (see
## MissionRuntime.fire_prop_action()) - MissionPlayer._ready() connects
## this to its own _on_game_over_requested(), which shows the outcome and
## returns to the menu. A genuine signal (unlike MissionPlayer._advance_to()'s
## deliberate avoidance of one for the checkpoint-driven path) is safe here
## specifically because nothing below continues an internal loop after
## _end_drag() that would need to wait on the connected handler finishing.
signal game_over_requested(objective: MissionObjective)

## Fired every time firing a PropAction runs the objectives evaluator,
## regardless of outcome - a DAG group can be replaced by its children
## (advancing which objective is "active") without that resolving all the
## way to a leaf, so MissionPlayer needs to know to refresh its objective
## label even when game_over_requested above doesn't fire. See
## MissionRuntime.get_current_objective_descriptions().
signal objectives_progressed

@export var layered_map: LayeredMap
@export var camera: Camera3D  ## leave unset to auto-grab the viewport's active camera
@export var dialog: PlayerDialog  ## %Dialog - the action picker (see _offer_actions()) shows through this
@export var highlight_color: Color = Color(0.3, 1.0, 1.0, 0.5)

## Assigned by MissionPlayer._ready() right after construction - a plain
## var, not @export/NodePath, since MissionRuntime is built at runtime via
## .new() and never placed in a .tscn (same pattern
## CreatorPropertiesPanel._build_object_fields() uses for
## PropertiesDialog.operation_history/.layered_map).
var mission_runtime: MissionRuntime
## Counts attacks and interactions towards the heroes' feats (a campaign mission only; null otherwise).
var feat_tracker: FeatTracker

## Assigned by MissionPlayer._ready() (same plain-var reasoning as above).
## While it's visible (the M view) a drag targets its monsters, not the world.
var monster_display: MonsterDisplay
## The monster cards on the side of the map view (PlayerHud.monster_sidebar): dropping a hero on one attacks that monster, like in the monster view.
var monster_sidebar: MonsterSidebar

## {hero slot index: Array[Weapon]}, set by MissionPlayer after embark.
var hero_weapons: Dictionary = {}

const PORTRAIT_SIZE := 96.0  ## was 56 - too small to read once these became real portrait images rather than a flat colour swatch; matches EmbarkDialog's own portrait cell size
## Space reserved below the portrait row for the mic status line + CommandInput,
## now stacked centered directly underneath it (see VoiceListener.gd's/
## CommandInput.gd's own offsets, which occupy this same margin).
const BOTTOM_MARGIN := 12.0

var _row: HBoxContainer
var _portraits: Array[Control] = []
## Parallel to _portraits - _roster[dock_position] is the HeroCatalog slot
## index that portrait represents (see set_roster()). Dock position and
## catalog slot aren't the same thing once the party doesn't happen to be
## slots 0..N-1 in order (e.g. roster [0, 2, 5]).
var _roster: Array[int] = []

var _drag_line: MeshInstance2D  ## the strip of the arrow (see _set_strip())
var _drag_arrow: Sprite2D  ## the arrow head at the end of the line
## The arrow's pictures (placeholders; OfficialAssetMap swaps in the game's TargetingArcBody / Arrow_Tip when imported) and its width in pixels.
const ARROW_BODY_TEXTURE := "res://models/arrow_body.png"
const ARROW_TIP_TEXTURE := "res://models/arrow_tip.png"
const ARROW_WIDTH := 30.0  ## the arrow head's width; the strip is ARROW_STRIP_WIDTH wide
## Which rows (V0..V1 of its height) of the game's strip picture are used - all of it, as in the game.
const ARROW_BODY_V0 := 0.0
const ARROW_BODY_V1 := 1.0
const ARROW_STRIP_WIDTH := 34.0
const ARROW_TINT := Color(0.66, 0.85, 0.62)  ## the arrow's colour before a hero is chosen; while dragging it is HeroCatalog.arrow_color() (the pictures are grey, the colour is multiplied over them)
const ARROW_SLIDE_SPEED := 0.25  ## picture repeats per second the chevrons slide along the strip
const ARROW_WIDTH_AT_HEAD := 0.6  ## the strip's width where the arrow head begins, as a fraction of its width at the base (the game: 0.5 / 0.79 to 0.58)
const ARROW_REPEATS := 3.0  ## repeats of the strip picture along the whole strip (the game's material tiling), whatever its length
const ARROW_HEAD_WIDEN := 1.45  ## the arrow head is this much wider than the strip, so it covers the strip's end
var _dragging: bool = false
var _drag_dock_position: int = -1

var _highlight_overlay: MeshInstance3D
var _highlight_overlay_mesh: ImmediateMesh
var _hovered_entry: InteractableEntry = null


## How far the arrow's picture has slid, in picture repeats (0..1).
var _slide: float = 0.0
var _strip_curve: PackedVector2Array = PackedVector2Array()  ## the curve the strip was last built along


func _process(delta: float) -> void:
	if _drag_line == null or not _drag_line.visible:
		return
	_slide = fposmod(_slide + delta * ARROW_SLIDE_SPEED, 1.0)
	_set_strip(_strip_curve)


func _ready() -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()
	_build_ui()
	_setup_highlight_overlay()


func _build_ui() -> void:
	# Full-rect, not just a bottom strip - so the drag line (a direct
	# child, added below) shares the same coordinate space as raw mouse
	# positions instead of needing an offset correction for wherever a
	# smaller anchored rect would place its own local origin.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_row = HBoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	# Confirmed bug, 2026-09-23: PRESET_CENTER_BOTTOM leaves grow_horizontal
	# at its own default of GROW_DIRECTION_END, not BOTH - with offset_left/
	# offset_right left at the preset's own 0/0 (a zero-width rect at the
	# anchor point) and no explicit width set here, the row only grew
	# RIGHTWARD as portraits were added, pinning its LEFT edge to screen
	# centre instead of actually centering - confirmed with a headless test
	# reading the row's real global rect (500px left margin vs. 80px right,
	# not the ~renders-symmetric result the anchor math alone suggested).
	# Forcing BOTH is what actually centers a content-sized (not explicitly
	# offset) Control under a CENTER anchor.
	_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# Lifted clear of the mic status line + CommandInput, now stacked
	# centered directly underneath (see VoiceListener.gd/CommandInput.gd's
	# own offsets, which start right where this row's own bottom margin -
	# BOTTOM_MARGIN below - ends).
	_row.offset_top = -PORTRAIT_SIZE - BOTTOM_MARGIN
	_row.offset_bottom = -BOTTOM_MARGIN
	_row.add_theme_constant_override("separation", 12)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	# Empty until set_roster() is called (after EmbarkDialog resolves) -
	# there's nothing to show a portrait row FOR until the party is chosen.

	# The game's own arrow: a strip of chevrons tiled along the curve and sliding toward the tip as a whole (the strip is a mesh
	# built in _set_strip(), its texture coordinates shifted a little every frame), ending in an arrow head.
	_drag_line = MeshInstance2D.new()
	_drag_line.texture = _mipmapped(OfficialAssetOverrides.texture_for(ARROW_BODY_TEXTURE))  # the picture is shown much smaller than it is: mipmaps keep it from shimmering while it slides
	_drag_line.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_drag_line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# Like the game: the strip picture is grey and the game tints it green (a plain multiply: white arrows become light green,
	# the grey ground mid green, the dark outline dark green). The picture slides because the strip's texture coordinates are
	# shifted a little every frame (see _process()); no shader is involved.
	_drag_line.self_modulate = ARROW_TINT
	_drag_line.visible = false
	add_child(_drag_line)
	move_child(_drag_line, 0)  # drawn before the portrait row, so the arrow comes out from behind the portrait
	_drag_arrow = Sprite2D.new()
	_drag_arrow.texture = OfficialAssetOverrides.texture_for(ARROW_TIP_TEXTURE)
	_drag_arrow.flip_h = true  # the game's tip texture points left; the arrow points along the drag
	_drag_arrow.centered = false
	var tip_size := _drag_arrow.texture.get_size()
	_drag_arrow.offset = Vector2(-tip_size.x, -tip_size.y / 2.0)  # the tip of the flipped picture at the origin
	_drag_arrow.scale = Vector2(ARROW_WIDTH / tip_size.y, ARROW_WIDTH / tip_size.y * ARROW_HEAD_WIDEN)
	_drag_arrow.self_modulate = ARROW_TINT  # the head gets the strip's colour too
	_drag_arrow.visible = false
	add_child(_drag_arrow)
	move_child(_drag_arrow, 0)  # both are drawn before the portrait row; the head over the strip, so the head hides the end of the strip
	move_child(_drag_line, 0)


## Rebuilds the portrait row from the party EmbarkDialog.ask_roster()
## returned - one portrait per HeroCatalog slot index in `roster`, in that
## order. Safe to call again later if the party ever needs to change
## mid-session (not currently done anywhere, but nothing here assumes
## it's only called once).
func set_roster(roster: Array[int]) -> void:
	for child in _row.get_children():
		child.queue_free()
	_portraits.clear()
	_wound_labels.clear()
	_roster = roster.duplicate()

	for dock_position in _roster.size():
		var portrait := _make_portrait(_roster[dock_position], dock_position)
		_row.add_child(portrait)
		_portraits.append(portrait)


## HeroCatalog.slot_portrait() - the shipped dummy placeholder art, or a
## user's own official portrait if OfficialAssetOverrides finds one locally
## (see HeroCatalog.gd's own class doc). A name caption still overlays the
## bottom (readable with an outline, same convention InteractionLabels/
## CreatorController's own overlay labels use), since the REAL art has no
## text baked in the way the dummy placeholders do. Uses HeroCatalog so this
## always matches whatever EmbarkDialog showed for the same slot.
func _make_portrait(hero_slot: int, dock_position: int) -> Control:
	var portrait := Panel.new()
	portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	portrait.clip_contents = true  # a non-square portrait shouldn't spill past the panel's own rect
	portrait.add_theme_stylebox_override("panel", StyleBoxEmpty.new())  # the portrait texture (below) covers the whole panel now - no flat colour needed/visible behind it

	var texture_rect := TextureRect.new()
	texture_rect.texture = HeroCatalog.slot_portrait(hero_slot)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(texture_rect)

	var label := Label.new()
	label.text = HeroCatalog.slot_name(hero_slot)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait.add_child(label)

	# Wound marker (top-right): one cross per wound, hidden while healthy.
	var wound_label := Label.new()
	wound_label.add_theme_font_size_override("font_size", 18)
	wound_label.add_theme_color_override("font_outline_color", Color.BLACK)
	wound_label.add_theme_constant_override("outline_size", 6)
	wound_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	wound_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wound_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(wound_label)
	_wound_labels[hero_slot] = wound_label
	_apply_wound_label(hero_slot)

	portrait.gui_input.connect(_on_portrait_gui_input.bind(dock_position))
	return portrait


## hero slot -> wound count, as last reported by MissionRuntime.hero_wounds.
var _wounds: Dictionary = {}
var _wound_labels: Dictionary = {}  # hero slot -> the portrait's wound Label


## Updates the wound markers on the portraits (call after every wound).
func refresh_wounds(wounds: Dictionary) -> void:
	_wounds = wounds.duplicate()
	for slot in _wound_labels:
		_apply_wound_label(slot)


func _apply_wound_label(hero_slot: int) -> void:
	var label: Label = _wound_labels[hero_slot]
	var count := int(_wounds.get(hero_slot, 0))
	label.visible = count > 0
	label.text = "✚".repeat(count)
	label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.25) if count == 1 else Color(1.0, 0.3, 0.25))


func _on_portrait_gui_input(event: InputEvent, dock_position: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if dialog != null and dialog.visible:
			return  # a placement dialog leaves the screen clickable - no interacting yet
		_dragging = true
		_drag_dock_position = dock_position
		var tint := HeroCatalog.arrow_color(_roster[dock_position])  # the arrow takes the colour of the hero's portrait background
		_drag_line.self_modulate = tint
		_drag_arrow.self_modulate = tint
		_drag_line.visible = true
		_update_drag_line(get_viewport().get_mouse_position())  # visible from the first moment, before the mouse moves
		get_viewport().set_input_as_handled()


## Drag motion/release can land anywhere on screen, not just back over the
## originating portrait - a global handler (rather than relying on
## gui_input, which only fires while the mouse stays over one Control) is
## the only reliable way to track it.
func _input(event: InputEvent) -> void:
	if not _dragging:
		# Not dragging: light up the prop under the mouse when a hero could interact with it.
		if event is InputEventMouseMotion:
			var over_ui := get_viewport().gui_get_hovered_control() != null
			if over_ui or (dialog != null and dialog.visible):
				if _hovered_entry != null:
					_hovered_entry = null
					_rebuild_highlight()
			else:
				_update_hover_highlight(event.position)
		return
	if event is InputEventMouseMotion:
		_update_drag_line(event.position)
		_update_hover_highlight(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_drag(event.position)


func _update_drag_line(mouse_pos: Vector2) -> void:
	var portrait := _portraits[_drag_dock_position]
	var start := portrait.global_position + portrait.size / 2.0  # the line starts in the middle of the portrait (drawn behind it)
	# A gentle arch: a quadratic curve whose middle is pulled up, more the longer the line, ending in an arrow head on the mouse.
	var distance := start.distance_to(mouse_pos)
	var tip_length := ARROW_WIDTH * 2.0  # the tip texture is twice as long as it is wide
	if distance < 6.0:
		_set_strip(PackedVector2Array())
		_drag_arrow.visible = false
		return
	if distance < tip_length + 12.0:
		# Closer than the arrow head is long: just the head, pointing from the portrait toward the mouse.
		_set_strip(PackedVector2Array())
		_drag_arrow.visible = true
		_drag_arrow.position = mouse_pos
		_drag_arrow.rotation = (mouse_pos - start).angle()
		return
	# The arrow head's tip sits on the mouse and the strip aims for the MIDDLE of the head, so the head always continues the
	# strip in its own direction: the end point depends on the direction the curve arrives with, which depends on the end
	# point - a few rounds settle it.
	var middle := mouse_pos
	var curve := PackedVector2Array()
	var direction := (mouse_pos - start).normalized()
	const STEPS := 40
	for _round in 4:
		var reach := start.distance_to(middle)
		var control := (start + middle) / 2.0 + Vector2(0.0, -minf(reach * 0.3, 160.0))
		curve.clear()
		for i in STEPS + 1:
			var t := float(i) / STEPS
			curve.append(start.lerp(control, t).lerp(control.lerp(middle, t), t))
		direction = (curve[STEPS] - curve[STEPS - 2]).normalized()  # where the curve is heading at its end
		middle = mouse_pos - direction * (tip_length / 2.0)
	curve.append(mouse_pos)  # like the game's line, the strip runs on to the arrow's tip, under the arrow head, which hides its narrowest part
	_set_strip(curve)
	_drag_arrow.visible = true
	_drag_arrow.position = mouse_pos
	_drag_arrow.rotation = direction.angle()


static func _mipmapped(texture: Texture2D) -> Texture2D:
	var image := texture.get_image()
	if image == null:
		return texture
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## The strip's width, as a fraction of its base width, at `from_tip` pixels before the arrow's tip: like the game it is about
## 60% wide where the arrow head begins (ARROW_WIDTH * 2 from the tip), widening evenly to the full width at the base; under the
## head it narrows to a point (hidden). `total` = the strip's whole length.
static func _strip_width_at(from_tip: float, total: float) -> float:
	var head := ARROW_WIDTH * 2.0
	if from_tip < head:
		return ARROW_WIDTH_AT_HEAD * from_tip / head
	return lerpf(ARROW_WIDTH_AT_HEAD, 1.0, clampf((from_tip - head) / maxf(total - head, 1.0), 0.0, 1.0))


## Builds the arrow's strip along `curve`: a ribbon that narrows evenly from ARROW_STRIP_WIDTH to 60% of it where the head begins,
## textured like the game's line: a fixed number of repeats stretched over the whole length.
func _set_strip(curve: PackedVector2Array) -> void:
	_strip_curve = curve
	if curve.size() < 2:
		_drag_line.mesh = null
		return
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	# As in the game (its ArcRenderer line: texture mode Stretch, material tiling 3): the picture is stretched over the WHOLE strip and
	# repeated ARROW_REPEATS times, so a longer strip has longer arrows, never more of them. The width follows the game's width
	# curve: full at the base, a bit narrower at 75% of the length, a point at the end (which is hidden under the arrow head).
	var lengths := PackedFloat32Array([0.0])
	for i in range(1, curve.size()):
		lengths.append(lengths[i - 1] + curve[i].distance_to(curve[i - 1]))
	var total := maxf(lengths[lengths.size() - 1], 0.001)
	for i in curve.size():
		var ahead := curve[mini(i + 1, curve.size() - 1)] - curve[maxi(i - 1, 0)]
		var side := ahead.normalized().orthogonal() if ahead.length() > 0.001 else Vector2.DOWN
		var along := lengths[i] / total
		var half := ARROW_STRIP_WIDTH / 2.0 * _strip_width_at(total - lengths[i], total)
		vertices.append(curve[i] - side * half)
		vertices.append(curve[i] + side * half)
		var u := along * ARROW_REPEATS - _slide
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	_drag_line.mesh = mesh


## True while the M monster view is what's on screen - drags then target
## monsters (attack) instead of world props.
func _monster_view_active() -> bool:
	return monster_display != null and monster_display.visible


func _update_hover_highlight(screen_pos: Vector2) -> void:
	if _monster_view_active():
		return
	if monster_sidebar != null:
		# while a hero is dragged over a monster card that card is the target (and nothing under it lights up)
		var over_card: RuntimeMonster = monster_sidebar.monster_at(screen_pos) if _dragging else null
		monster_sidebar.set_hovered(over_card)
		if over_card != null:
			if _hovered_entry != null:
				_hovered_entry = null
				_rebuild_highlight()
			return
	var entry := _interactable_at(screen_pos)
	if entry == _hovered_entry:
		return
	_hovered_entry = entry
	_rebuild_highlight()


## Async now (new 2026-09-14) - releasing over an interactable no longer
## fires immediately, it awaits _offer_actions()'s picker dialog first
## (see that function). Drag visuals reset FIRST, before that await, so
## the drag line/highlight don't sit around while the modal dialog is up -
## the drag gesture itself is complete the moment the mouse is released,
## the picker is a separate follow-up interaction. hero_name is captured
## before _drag_dock_position resets. Called un-awaited from _input()
## (an ordinary, non-async function) - a fine GDScript pattern, this just
## runs as a background coroutine, nothing needs to wait on it.
func _end_drag(screen_pos: Vector2) -> void:
	var hero_slot: int = _roster[_drag_dock_position]
	var hero_name := HeroCatalog.slot_name(hero_slot)
	var monster_view := _monster_view_active()
	var card_monster: RuntimeMonster = null if monster_view or monster_sidebar == null else monster_sidebar.monster_at(screen_pos)
	var entry: InteractableEntry = null if monster_view or card_monster != null else _interactable_at(screen_pos)
	var monster: RuntimeMonster = monster_display.monster_at(screen_pos) if monster_view else card_monster
	if monster_sidebar != null:
		monster_sidebar.set_hovered(null)

	_dragging = false
	_drag_dock_position = -1
	_drag_line.visible = false
	_drag_arrow.visible = false
	_hovered_entry = null
	_rebuild_highlight()

	if monster_view or card_monster != null:
		if monster == null:
			print("%s: drag released on no monster" % hero_name)
			return
		await attack(hero_slot, monster)
		return
	if entry == null:
		print("%s: drag released on nothing interactable" % hero_name)
		return
	await _offer_actions(hero_name, entry)


## Public: a hero interacts with a prop - the same picker-then-fire flow a
## portrait drag onto it ends in (_offer_actions()). Used by voice/typed
## commands ("use the pile of dirt").
func interact(hero_slot: int, entry: InteractableEntry) -> void:
	await _offer_actions(HeroCatalog.slot_name(hero_slot), entry)


## Combat: dragging a hero portrait onto a monster in the M view attacks it.
## The table rolls its dice (and applies abilities/potions) outside the engine
## and reports the final number of successes; MissionRuntime.resolve_attack()
## does the rest (successes x weapon damage - random 0..defense, taken off
## the monster's hitpoints) and a large dialog shows the breakdown.
## Public: a portrait drag ends here, and so does a typed/spoken command
## (PlayerCommandRunner) - both attack through this one call.
## `weapon_text` / `successes` are answers already given by voice ("attack John
## with the sword, I rolled three"): a weapon phrase that names one of the
## hero's weapons skips the "Which weapon?" question, a number >= 0 skips the
## "How many successes?" question. Anything not (clearly) given is asked as usual.
func attack(hero_slot: int, monster: RuntimeMonster, weapon_text: String = "", preset_successes: int = -1) -> void:
	if mission_runtime == null:
		return
	visible = false  # hero bar out of the way of the full-screen combat views
	await _attack(hero_slot, monster, weapon_text, preset_successes)
	visible = true


func _attack(hero_slot: int, monster: RuntimeMonster, weapon_text: String, preset_successes: int) -> void:
	var hero_name := HeroCatalog.slot_name(hero_slot)
	var target := tr("%s (%s chip)") % [monster.display_name(), MonsterChip.display_name(monster.chip)]
	var target_chip: int = monster.chip  # (the chip is freed when the monster is defeated; the quest log text is built afterwards)
	# One of the hero's two embark weapons (asked only when there is a choice).
	var weapons: Array = hero_weapons.get(hero_slot, [])
	var weapon: Weapon = null
	var weapon_index := 0
	if weapons.size() == 1:
		weapon = weapons[0]
	elif weapons.size() > 1:
		var spoken := -1
		if weapon_text != "":
			var weapon_names: Array[String] = []
			for w: Weapon in weapons:
				weapon_names.append(w.weapon_name)
			spoken = VoiceAnswerParser.match_choice(weapon_text, weapon_names)
		if spoken >= 0:
			weapon = weapons[spoken]
			weapon_index = spoken
		elif weapons.size() == 2:
			# The full-screen weapon choice: the hero's flat mesh for each weapon
			# side by side, click one (new 2026-10-04).
			var options: Array = []
			for i in 2:
				var w: Weapon = weapons[i]
				var option := {
					"name": w.weapon_name,
					"subtitle": _weapon_subtitle(hero_slot, i, w),
					"damage_types": w.damage_types,
				}
				option.merge(_hero_art(hero_slot, i))
				options.append(option)
			var picked: int = await dialog.ask_weapon({
				"title": tr("%s attacks %s - choose a weapon") % [hero_name, target],
				"hero_size_units": HeroCatalog.size_units(hero_slot),
				"known_weaknesses": monster.known_weaknesses,
				"known_resistances": monster.known_resistances,
				"known_immunities": monster.known_immunities,
				"options": options,
			})
			if picked < 0:
				return
			weapon = weapons[picked]
			weapon_index = picked
		else:
			var labels: Array[String] = []
			for w: Weapon in weapons:
				labels.append(w.summary())
			var picked: int = await dialog.ask_choice(tr("%s attacks %s.\nWhich weapon?") % [hero_name, target], labels)
			if picked < 0:
				return
			weapon = weapons[picked]
			weapon_index = picked

	# The combat view's data - used by the successes screen AND (as the
	# pre-attack snapshot) the outcome. The known_* lists are COPIES: the
	# monster's own arrays are mutated by resolve_attack(), and the outcome
	# animation needs to know what was already discovered before it.
	var damage_types: Array = [] if weapon == null else weapon.damage_types
	# The monster's defense abilities (the game's texts): shown while attacking, or after the roll when the game says so.
	# A deactivated one (Spiral Bolts) is shown as such instead.
	var ability_deactivated := monster.defense_ability_off > 0
	var consume_deactivation := monster.defense_ability_off == 1
	var ability_before := monster.defense_ability_text(false)
	var ability_after := monster.defense_ability_text(true)
	if ability_deactivated:
		ability_before = tr("Defense ability deactivated.") if (ability_before != "" or ability_after != "") else ""
		ability_after = ""
	var reaction := monster.tactic_reaction_text(hero_name)
	if reaction != "":
		ability_before = (ability_before + "\n" if ability_before != "" else "") + reaction
	var cfg := {
		"ability_text": ability_before,
		"monster_name": monster.display_name(),
		"hitpoints": monster.hitpoints,
		"max_hitpoints": monster.max_hitpoints,
		"defense": monster.effective_defense(),
		"damage_types": damage_types,
		"weaknesses": monster.weaknesses,
		"known_weaknesses": monster.known_weaknesses.duplicate(),
		"resistances": monster.resistances,
		"known_resistances": monster.known_resistances.duplicate(),
		"immunities": monster.immunities,
		"known_immunities": monster.known_immunities.duplicate(),
		"hero_size_units": HeroCatalog.size_units(hero_slot),
		"monster_size_units": MonsterDisplay.size_units(monster.folder),
		"monster_conditions": monster.conditions.duplicate(),
		"monster_condition_immunities": monster.all_condition_immunities(),
	}
	var hero_art := _hero_art(hero_slot, weapon_index)
	for key in hero_art:
		cfg["hero_" + key] = hero_art[key]
	if MonsterDisplay.has_flat_card(monster.folder):
		cfg["monster_flat_meshes"] = MonsterDisplay.flat_mesh_paths(monster.folder)
		cfg["monster_flat_texture"] = MonsterDisplay.flat_diffuse_texture(monster.folder)
		cfg["monster_flat_rotation"] = MonsterDisplay.flat_card_rotation(monster.folder)
		cfg["monster_flat_surface_overrides"] = MonsterDisplay.flat_surface_texture_overrides(monster.folder)
		cfg["monster_flat_write_depth"] = MonsterDisplay.flat_write_depth(monster.folder)
	else:
		cfg["monster_image"] = MonsterDisplay.crop_texture(monster.folder)

	# The successes screen - skipped when they were already spoken in the command.
	var successes: int = preset_successes
	var conditions: Array[int] = []
	var debug_kill := false  # the debug "Defeat" button of the successes screen
	if successes < 0:
		successes = await dialog.ask_attack(cfg)
		if successes < 0:
			return
		conditions = dialog.attack_conditions.duplicate()
		debug_kill = dialog.debug_defeat and DebugSession.active()
	# What the table entered is what weapon part A did (successes, conditions). The weapon's parts B and C now roll
	# their chance and apply what they can (PartEffectRunner), the damage is worked out, and what comes after the
	# damage is applied.
	if weapon == null:
		weapon = Weapon.placeholder()
	var runner := PartEffectRunner.new()
	runner.runtime = mission_runtime
	runner.dialog = dialog
	runner.hero_name = hero_name
	runner.hero_slot = hero_slot
	var plan: PartEffectRunner.Plan = await runner.plan(weapon, monster, conditions)
	for kind in plan.conditions:
		if not conditions.has(kind):
			conditions.append(kind)
	var feat_pre := feat_tracker.snapshot(monster, hero_slot) if feat_tracker != null else {}
	if feat_tracker != null:
		feat_tracker.begin_action(hero_slot, "attack")
	var attack_modifiers := plan.modifiers()
	if debug_kill:
		attack_modifiers["debug_damage"] = 10000  # a normal attack (feats, loot, defeat effects, part effects...) that cannot fail to kill
	var r := mission_runtime.resolve_attack(monster, successes, weapon, conditions, hero_slot, attack_modifiers)
	await runner.finish(plan, r)
	if feat_tracker != null:
		feat_tracker.end_action()
		feat_tracker.on_attack(hero_slot, weapon_index, weapon, monster, feat_pre, r)
	if consume_deactivation and not plan.defense_off_set:
		monster.defense_ability_off = 0  # "the next attack" was this one
	# The same cfg with what the monster now has discovered.
	var post_cfg := cfg.duplicate()
	if ability_after != "":
		post_cfg["ability_text"] = ability_after
	post_cfg["damage_types"] = plan.attack_types
	post_cfg["max_hitpoints"] = monster.max_hitpoints
	post_cfg["known_weaknesses"] = monster.known_weaknesses.duplicate()
	post_cfg["known_resistances"] = monster.known_resistances.duplicate()
	post_cfg["known_immunities"] = monster.known_immunities.duplicate()

	var make_text := func() -> String:  # built once per language for the quest log (LogText)
		var target_text := tr("%s (%s chip)") % [monster.display_name(), MonsterChip.display_name(target_chip)]
		var text := tr("%s attacks %s\nwith the %s (damage %d)\n") % [hero_name, target_text, r["weapon_name"], r["base_damage"]]
		if r["weakness_bonus"] > 0:
			text += tr("\nWeakness: +%d damage") % r["weakness_bonus"]
		if r["resistance_penalty"] > 0:
			text += tr("\nResistance: -%d damage") % r["resistance_penalty"]
		if r["immune"]:
			text += tr("\nImmune! The attack does no damage.\n\n0 damage dealt")
		else:
			text += tr("\n%d successes x %d weapon damage") % [r["successes"], r["weapon_damage"]]
			if r["exposed_bonus"] > 0:
				text += tr("\nExposed: +%d damage") % r["exposed_bonus"]
			text += tr(" = %d damage\nDefense roll: -%d\n\n%d damage dealt") % [r["damage"], r["defense_roll"], r["dealt"]]
		if r["defeated"]:
			text += tr("\n\n%s is defeated! Remove it from the board.") % monster.display_name()
			if MissionRuntime.loot_text(monster) != "":
				text += tr("\nLoot for the party: %s.") % MissionRuntime.loot_text(monster)
		else:
			text += tr("\n\n%s has %d hitpoints left.") % [monster.display_name(), r["hitpoints"]]
		var part_lines: Array = r.get("part_lines", [])
		if not part_lines.is_empty():
			text += tr("\nWeapon parts and trinket: ") + "; ".join(part_lines)
		var part_notes: Array = r.get("part_notes", [])
		if not part_notes.is_empty():
			text += tr("\nAt the table: ") + " | ".join(part_notes)
		var applied: Array[int] = r["conditions_applied"]
		if not applied.is_empty():
			var applied_names: Array[String] = []
			for condition in applied:
				applied_names.append(MonsterCondition.display_name(condition))
			text += tr("\nConditions applied: %s") % ", ".join(applied_names)
		var resisted: Array[int] = r["conditions_resisted"]
		if not resisted.is_empty():
			var resisted_names: Array[String] = []
			for condition in resisted:
				resisted_names.append(MonsterCondition.display_name(condition))
			text += tr("\nImmune to: %s") % ", ".join(resisted_names)
		return text
	# The result is shown on the combat screen itself (calculation, health bar,
	# revealed weaknesses); the text below is what the quest log keeps.
	await dialog.ask_attack_outcome(cfg, post_cfg, r, make_text, "Attack")


## The hero's art for weapon slot `weapon_index` in CombatView's key naming
## (`flat_meshes`/`flat_texture`/`flat_rotation`, else the crop `image`) -
## the combat cfg prefixes these with "hero_", a weapon-choice option uses
## them as they are.
func _hero_art(hero_slot: int, weapon_index: int) -> Dictionary:
	if HeroCatalog.has_flat_mesh(hero_slot, weapon_index):
		return {
			"flat_meshes": HeroCatalog.flat_mesh_paths(hero_slot, weapon_index),
			"flat_texture": HeroCatalog.flat_diffuse_texture(hero_slot, weapon_index),
			"flat_rotation": HeroCatalog.flat_mesh_rotation(hero_slot, weapon_index),
		}
	return {"image": HeroCatalog.slot_crop(hero_slot, weapon_index)}


## e.g. "Warhammer - damage 3, range 2, reach" under a weapon's name in the
## weapon-choice screen.
func _weapon_subtitle(hero_slot: int, weapon_index: int, weapon: Weapon) -> String:
	var parts: Array[String] = [tr("damage %d") % weapon.damage]
	if weapon.weapon_range > 0:
		parts.append(tr("range %d") % weapon.weapon_range)
	if weapon.reach:
		parts.append("reach")
	var text := "%s - %s" % ["Rune" if weapon.is_rune else WeaponCatalog.type_of(hero_slot, weapon_index), ", ".join(parts)]
	for attachment in weapon.attachments:
		text += "\n+ " + attachment.attachment_name
	return text


## Presents every CURRENTLY-AVAILABLE action on `entry` (see
## MissionRuntime.available_actions() - re-resolved here rather than
## trusting whatever _interactable_at()'s last hover check found,
## conditions could in principle have changed between then and release)
## as a choice via dialog.ask_choice(), Cancel always included alongside
## them (PlayerDialog.ask_choice()'s own doc - never omitted). Picking
## Cancel (or dropping on a prop with zero available actions right now,
## which _interactable_at() already excludes from being a valid drop
## target in the first place) does nothing. Otherwise fires the chosen
## action exactly like the old single-action _end_drag() body did.
## Fires a prop action and tells the feat tracker about the interaction (after the effects ran, before the caller drains what they queued - the tracker reads
## whether the object is removed or monsters spawn from those queues).
func _fire_tracked(action: PropAction, hero_name: String, entry: InteractableEntry) -> MissionObjective:
	var slot := HeroCatalog.HERO_NAMES.find(hero_name)
	if feat_tracker != null:
		feat_tracker.begin_action(slot, "interaction")
	var objective := await mission_runtime.fire_prop_action(action, hero_name, entry)
	if feat_tracker != null:
		feat_tracker.end_action()
		feat_tracker.on_interaction(slot, entry)
	return objective


func _offer_actions(hero_name: String, entry: InteractableEntry) -> void:
	if mission_runtime == null:
		return
	var actions := mission_runtime.available_actions(entry)
	if actions.is_empty():
		return
	var label := entry.player_name()

	# Actions marked "apply automatically" just happen - no dialog. Only the others are offered as a choice.
	var chosen_actions: Array[PropAction] = []
	var offered: Array[PropAction] = []
	for candidate in actions:
		if candidate.auto_apply:
			if not (candidate.single_shot and candidate.already_used):
				chosen_actions.append(candidate)
		else:
			offered.append(candidate)
	if not chosen_actions.is_empty():
		for auto_action in chosen_actions:
			var auto_objective := await _fire_tracked(auto_action, hero_name, entry)
			objectives_progressed.emit()
			if auto_objective != null:
				game_over_requested.emit(auto_objective)
				return
			print("%s triggered '%s' on '%s'" % [hero_name, auto_action.description, label])
		await mission_runtime.interaction_boon(hero_name)  # Mage-Sight Goggles
		if offered.is_empty():
			return
	actions = offered
	if actions.is_empty():
		return

	# The action's NAME is what is activated (and what voice control listens for); its description sits below it.
	# An action without a name keeps the old look: the description (or, failing that, the id) is the choice.
	var option_labels: Array[String] = []
	var option_details: Array[String] = []
	var option_disabled: Array[bool] = []
	for action in actions:
		if action.action_name != "":
			option_labels.append(action.action_name)
			option_details.append(action.description)
		else:
			option_labels.append(action.description if action.description != "" else action.action_id)
			option_details.append("")
		option_disabled.append(action.single_shot and action.already_used)
	var choice: int = await dialog.ask_choice(tr("%s: interact with '%s'") % [hero_name, label], option_labels, option_disabled, true, false, option_details)

	if choice < 0 or choice >= actions.size():
		print("%s: cancelled interacting with '%s'" % [hero_name, label])
		return

	var action := actions[choice]
	if action.single_shot and action.already_used:
		# Shouldn't be reachable through a correctly-disabled button, but
		# a used-up single-shot action must never actually fire again -
		# cheap insurance rather than trusting the UI's disabled state alone.
		print("%s: '%s' has already been used on '%s'" % [hero_name, action.description, label])
		return
	var objective := await _fire_tracked(action, hero_name, entry)
	objectives_progressed.emit()
	if objective != null:
		game_over_requested.emit(objective)
	else:
		await mission_runtime.interaction_boon(hero_name)  # Mage-Sight Goggles
	print("%s used '%s' on '%s' (%s)" % [hero_name, action.description, label, entry.mesh_item_name])


## Real physics raycast against the actual GridMap collision (same
## technique CreatorController.erase_at_cursor() uses, not the flat-plane
## approximation _update_hover() uses for painting - that assumes a fixed
## editing level, which doesn't make sense here; we want whatever's
## actually there at whatever height it renders). Only the prop layer is
## interactable right now (InteractableEntry only covers props) - a mesh
## needs props["interactible"] not explicitly false (purely decorative
## props, and props temporarily toggled off via that well-known key,
## aren't valid drag targets) AND at least one action whose own
## `conditions` currently hold (see _resolve_action()) - an entry whose
## every action is conditionally unavailable right now reads the same as
## having no actions at all.
func _interactable_at(screen_pos: Vector2) -> InteractableEntry:
	var entry := _prop_at(screen_pos)
	if entry == null or not entry.props.get("interactible", true):
		return null
	if _resolve_action(entry) == null:
		return null
	return entry


## Clicking a prop that has a description shows it to the table (a sign, a statue...). Called by MissionPlayer for a
## plain left click on the world; returns true when it showed something.
func show_description_at(screen_pos: Vector2) -> bool:
	var entry := _prop_at(screen_pos)
	if entry == null or entry.description.strip_edges() == "" or dialog == null or dialog.visible:
		return false
	var label := entry.player_name()
	await dialog.ask_ok(func() -> String: return entry.description, true, false, func() -> String: return label, null, null, true)
	return true


## The visible prop under the cursor (any prop - whether it has actions is the caller's question).
func _prop_at(screen_pos: Vector2) -> InteractableEntry:
	if camera == null or layered_map == null or layered_map.mission == null:
		return null

	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var ray_end := ray_origin + ray_dir * 1000.0

	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return null

	var hit_grid = result.collider
	if not (hit_grid is GridMap) or hit_grid != layered_map.prop_grid:
		return null

	var interior_point: Vector3 = result.position - result.normal * 0.01
	var local_pos: Vector3 = hit_grid.to_local(interior_point)
	var hit_cell: Vector3i = hit_grid.local_to_map(local_pos)

	return layered_map.mission.get_interactable_at(hit_cell, true)


## Cheap existence check for _interactable_at() above - is THERE an
## action here right now, not WHICH one (see _offer_actions() for the
## full picker that actually fires one). The first (by declared order,
## see MissionRuntime.first_available_action()'s own doc) whose
## `conditions` currently hold. Falls back to the plain first/only action
## if mission_runtime isn't set yet (shouldn't normally happen once the
## game has actually started - see mission_runtime's own doc) rather than
## conditions silently gating nothing. Returns null for a null entry so
## _interactable_at() doesn't need to null-check separately first.
func _resolve_action(entry: InteractableEntry) -> PropAction:
	if entry == null or entry.actions.is_empty():
		return null
	if mission_runtime != null:
		return mission_runtime.first_available_action(entry)
	return entry.actions[0]


func _setup_highlight_overlay() -> void:
	_highlight_overlay_mesh = ImmediateMesh.new()
	_highlight_overlay = MeshInstance3D.new()
	_highlight_overlay.mesh = _highlight_overlay_mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_ambient_light = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_highlight_overlay.material_override = material
	_highlight_overlay.visible = false
	# Owned by layered_map (a real Node3D), not self (a Control) - keeps 3D
	# overlay nodes under a 3D parent, matching LayeredMap's own spawn
	# overlay, rather than relying on Node3D-under-Control working (it
	# probably would, World3D resolution isn't blocked by 2D ancestors, but
	# there's no reason to rely on that when a proper parent is right here).
	layered_map.add_child(_highlight_overlay)


func _rebuild_highlight() -> void:
	_highlight_overlay_mesh.clear_surfaces()
	if _hovered_entry == null:
		_highlight_overlay.visible = false
		return

	_highlight_overlay_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for offset in _hovered_entry.footprint:
		_add_highlight_quad(_hovered_entry.origin_cell + offset)
	_highlight_overlay_mesh.surface_end()
	_highlight_overlay.global_transform = Transform3D.IDENTITY  # vertices already computed in world space
	_highlight_overlay.visible = true


## Same corner-based box-building approach used throughout this project's
## overlays (GridMap's Center X/Y/Z are OFF, so map_to_local() returns a
## cell's CORNER) - a filled quad per footprint cell, lifted a hair above
## the prop surface to avoid z-fighting.
func _add_highlight_quad(cell: Vector3i) -> void:
	var grid := layered_map.prop_grid
	var corner_local: Vector3 = grid.map_to_local(cell)
	var size := grid.cell_size
	var lift := Vector3(0, 0.05, 0)
	var a := grid.to_global(corner_local + lift)
	var b := grid.to_global(corner_local + Vector3(size.x, 0, 0) + lift)
	var c := grid.to_global(corner_local + Vector3(size.x, 0, size.z) + lift)
	var d := grid.to_global(corner_local + Vector3(0, 0, size.z) + lift)
	for v in [a, b, c, a, c, d]:
		_highlight_overlay_mesh.surface_set_color(highlight_color)
		_highlight_overlay_mesh.surface_add_vertex(v)
