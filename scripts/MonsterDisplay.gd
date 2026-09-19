class_name MonsterDisplay
extends Node3D

## Placeholder mockup for the Player's monster display (new 2026-09-15) -
## "combat" itself isn't designed yet; this exists purely to evaluate what
## switching the Player into a monster-facing view should look like before
## building anything real.
##
## Laid out in a grid (GRID_COLUMNS wide), each stand spaced CELL_SPACING
## apart. Builds its own Camera3D (a fixed, angled "look down at the
## tabletop" framing - no FreeLookCamera navigation needed for a first
## mockup) and the whole grid in _ready(), same "build dynamic content in
## code" convention used throughout this project (CreatorPalette's mesh
## grid, PropActionsDialog's action blocks, ...). Reuses the scene's
## existing DirectionalLight3D for lighting - a directional light isn't
## position-dependent, so it already illuminates this grid the same as it
## does LayeredMap, no dedicated light needed.
##
## Toggled on/off by MissionPlayer.gd (temporary "M" key hotkey for now,
## see that script's own _unhandled_input() - there's no real combat-
## trigger to switch views on yet, this is purely for eyeballing the look).
##
## **Real-asset proof of concept, 2026-09-16**: every stand now uses an
## actual extracted mesh + texture (REAL_MONSTERS below) instead of a cube
## placeholder - started with just Centurion, extended to 4 different
## monsters once that first one confirmed working. Sourced via
## tools/asset_import/dump_all_assets.py from each monster's own
## "<name> plastic pool.prefab" (the 3D-miniature-style mesh, not the
## flat/card one - see that tool's README).
##
## **Mesh loading, reworked 2026-09-16**: a hand-rolled runtime OBJ parser
## (ObjMeshLoader.gd) was tried first and produced consistently wrong
## orientation/shading no matter what coordinate-math theory was applied to
## it (several were, all wrong - see git history), while Godot's OWN native
## res:// OBJ importer rendered the identical file correctly on the first
## try with zero adjustment. Rather than keep chasing the custom parser's
## bug, the mesh is now converted ONCE via a one-off headless pass
## (models/original/monsters_temp/convert.gd - see that file and
## tools/asset_import/README.md) that lets Godot's own importer do the
## real work, then re-saves the result as a portable .tres under user://.
## At runtime this script just `ResourceLoader.load()`s that .tres directly
## - no custom parsing left in the runtime path at all. The raw .obj/texture
## files still live under user://monster_assets/<folder>/ (copied BY HAND,
## never committed, same rule as every other official asset - see
## claude.md's "Official asset overrides" section - this project ships zero
## copyrighted game content); only mesh.tres is actually read now, the
## .obj stays alongside it purely as the conversion's own source input.
## `_build_real_figure()` falls back to the same cube placeholder
## `_build_placeholder_figure()` still provides if a monster's .tres is
## missing (e.g. on a machine that never ran the extraction+conversion
## steps) - never hard-fails the whole grid over one missing asset.

const GRID_COLUMNS := 5  ## 18 monsters at 5 wide -> 4 rows (5/5/5/3), roughly square
const CELL_SPACING := 2.0
const BASE_SIZE := Vector3(1.2, 0.15, 1.2)
const FIGURE_SIZE := Vector3(0.6, 1.0, 0.6)  ## placeholder-cube size; its own diagonal is also the base target real meshes are auto-scaled to, see target_figure_diagonal below

## How deep to extrude the gap marker's flat quad into a real box, as a
## fraction of the panel's OWN height (outer-to-inner distance) rather than
## a fixed world-space number - keeps proportions consistent per-monster
## automatically, same reasoning as BaseGapDetector.GAP_WALL_HEIGHT_PCT.
## Visual tuning knob, not derived from geometry - see _build_gap_marker().
## Doubled 0.5 -> 1.0 2026-09-17 per direct user review in the Player.
const GAP_MARKER_DEPTH_RATIO := 1.0

## The gap marker's wall height, in GAME/WORLD space, applied identically
## to every monster regardless of its own raw mesh proportions - replaces
## an earlier per-mesh PERCENTAGE (BaseGapDetector's old GAP_WALL_HEIGHT_PCT,
## a fraction of each mesh's own height) 2026-09-17, after direct review in
## the Player ("the doomcaller height is fine, make that the height for
## all"): a percentage-of-own-height read inconsistent once monsters of
## different body proportions were compared side-by-side, even though it
## scaled correctly in the abstract. This value is Doomcaller's own
## previous 6%-based result, back-calculated once into world space (not
## eyeballed): (Doomcaller's raw mesh height) * 0.06 * (Doomcaller's own
## scale_factor at the time) = 0.05357. `_build_gap_marker()` converts this
## back into each mesh's own LOCAL units via `/ scale_factor` before
## calling `BaseGapDetector.detect_gap_quad()`, so the RENDERED height ends
## up identical everywhere, not just the percentage.
const GAP_WALL_HEIGHT_WORLD := 0.05357

## A `GAP_WIDTH_WORLD` constant (a shared world-space target for the
## outer_a/outer_b chord width, mirroring GAP_WALL_HEIGHT_WORLD above) was
## added and then REMOVED again 2026-09-17, same day - see
## `_build_gap_marker()`'s own doc comment for why (direct user review
## found it made every monster's marker look worse, not just failing to
## fix the Wight report it was built for). Numeric roster-wide
## verification (16/17 monsters already clustering around the same chord
## width) is NOT kept as justification here, on purpose - it looked like
## solid evidence beforehand and still turned out wrong once rendered.

## Each entry's own folder holds mesh.tres/diffuse.png under
## user://monster_assets/<folder>/ (see class doc above for how mesh.tres
## gets there). `extra_rotation_degrees` defaults to 0 for every monster now
## that Godot's native import path needs no coordinate correction for
## HANDEDNESS/winding - left in place as a real per-monster authoring knob
## (a specific model's own sculpted facing direction, a plain Y-axis yaw)
## rather than removed.
##
## `pitch_correction_degrees` (new 2026-09-16) is a DIFFERENT, X-axis fix -
## confirmed via Mesh.get_aabb() on the converted meshes that Zealot's own
## height genuinely runs along local Y (size.y is its largest dimension,
## as expected for an upright figure), but Centurion/Doomcaller/Fae all
## have Y as their SMALLEST dimension while Z is largest - i.e. those three
## are lying on their front, height running along Z instead of Y. This is
## a per-monster AUTHORING inconsistency in the original game's own Unity
## assets (each monster prefab apparently bakes a different rest-pose
## rotation into its mesh data), not a coordinate-system/handedness bug -
## same category as this project's own pillar-mesh pivot quirk (see
## FootprintRegistry's calibration note), just on a different axis and a
## different asset source. -90 brings a Z-up mesh's height into world Y
## (Rx(-90): y' = z, z' = -y, x' = x - verified by hand against Godot's
## rotation-matrix convention, not guessed) - `_build_real_figure()` below
## also has to read the CORRECT AABB axis (z instead of y) for scale/lift
## math when this is non-zero, since Mesh.get_aabb() reports the mesh's
## own local-space bounds, unaffected by whatever rotation gets applied to
## the MeshInstance3D node afterward. **Confirmed working in-editor** - the
## data-derived -90 sign was correct, no monster came out upside-down.
## Expanded 2026-09-16 from the original 4-monster proof of concept to
## (almost) every monster type `dump_all_assets.py` found under
## assets/d3/enemies/ (18 found; Dragon was extracted too but then dropped
## from this list - "not a model we need" - leaving 17) -
## `import_monster_meshes.py` reads this exact list (see that script's own
## docstring), so this array is the single source of truth for which
## monsters get extracted/converted, not just which ones the grid shows.
## `"folder"` values must match the game's own Unity folder names EXACTLY
## (case-insensitively) - confirmed against the real bundles, not guessed -
## including "blood sister"'s literal space.
##
## `pitch_correction_degrees` was FIRST guessed from a headless
## Mesh.get_aabb() dump of the converted meshes, classified by
## `ratio = size.y / max(size.x, size.z)` (Y vs. the taller horizontal
## axis), `ratio < 0.85` -> -90 - but that heuristic turned out to be
## insufficient on its own, confirmed 2026-09-17: Legionnaire (ratio
## 0.867), Salamander (1.159), and Vampire (1.085) all scored "OK" yet
## were STILL lying face-down in-editor - a large bounding box on the
## horizontal axes doesn't guarantee Y is actually the mesh's real height
## axis, it can just mean the mesh is wide/deep as well as mis-oriented.
## **Every current value below is either visually confirmed in-editor, or
## still unverified (Dragon was dropped from the roster entirely - "not a
## model we need" - so it's no longer a concern either way)**. Wolf is the
## one case where NEITHER sign was right: -90 (the ratio heuristic's
## guess) and +90 (tried next, since the user reported "needs the same
## rotation as Vampire/Salamander/Legionnaire but in the other way
## around") both actively broke it - the user's precise report of WHERE
## "down" ended up after +90 ("bottom part pointing to -Z axis", stated
## coordinate convention X=left/right, Y=up/down, Z=toward viewer) was
## enough to back-derive by hand that the RAW, uncorrected mesh's own
## local down direction is already ~(0,-1,0) - i.e. Wolf was correctly
## oriented from the start, and 0 is the only value that doesn't rotate a
## correct mesh into a wrong one. Exactly the "elongated quadruped body,
## naturally longer than tall even when standing right" case flagged as
## low-confidence in the very first diagnosis pass - the ratio heuristic
## isn't just less reliable for that shape, it was actively wrong here.
## `size_units` (new 2026-09-17) - the monster's real physical footprint in
## the actual board game, "1 unit" (a single tile-square) for every regular
## monster, "2" for Centurion specifically ("centaur is actually 2 times as
## big, so all monsters occupy one game unit, centurion is 4 units square"
## - 2x LINEAR scale, matching a 2x2 = 4-square footprint). This is real,
## intentional size variation, not mesh-scale noise to normalize away - see
## target_figure_diagonal below for how it's actually applied.
const REAL_MONSTERS := [
	{"name": "Bandit", "folder": "bandit", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": -90.0, "size_units": 1.0},
	{"name": "Berserker", "folder": "berserker", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": 0.0, "size_units": 1.0},
	{"name": "Blood Sister", "folder": "blood sister", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": 0.0, "size_units": 1.0},
	{"name": "Centurion", "folder": "centurion", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": -90.0, "size_units": 2.0},
	{"name": "Doomcaller", "folder": "doomcaller", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": -90.0, "size_units": 1.0},
	{"name": "Fae", "folder": "fae", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": -90.0, "size_units": 1.0},
	{"name": "Golem", "folder": "golem", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": 0.0, "size_units": 1.0},
	{"name": "Harbinger", "folder": "harbinger", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": -90.0, "size_units": 1.0},  ## BORDERLINE ratio (0.844), see array's own doc above
	{"name": "Legionnaire", "folder": "legionnaire", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": -90.0, "size_units": 1.0},  ## CONFIRMED in-editor 2026-09-17 - ratio heuristic said OK (0.867), was actually still lying face-down
	{"name": "Mercenary", "folder": "mercenary", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": -90.0, "size_units": 1.0},
	{"name": "Reanimate", "folder": "reanimate", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": -90.0, "size_units": 1.0},
	{"name": "Salamander", "folder": "salamander", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": -90.0, "size_units": 1.0},  ## CONFIRMED in-editor 2026-09-17 - ratio heuristic said OK (1.159), was actually still lying face-down
	{"name": "Specter", "folder": "specter", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": 0.0, "size_units": 1.0},
	{"name": "Vampire", "folder": "vampire", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": -90.0, "size_units": 1.0},  ## CONFIRMED in-editor 2026-09-17 - ratio heuristic said OK (1.085), was actually still lying face-down
	{"name": "Wight", "folder": "wight", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": -90.0, "size_units": 1.0},
	{"name": "Wolf", "folder": "wolf", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": 0.0, "size_units": 1.0},  ## CONFIRMED in-editor 2026-09-17 - was ALREADY correctly oriented; +90 (tried first) put its "down" at world -Z, back-derived by hand from that report to mean the RAW mesh's own local down is already (0,-1,0) - see array's own doc above
	{"name": "Zealot", "folder": "zealot", "extra_rotation_degrees": 0.0, "pitch_correction_degrees": 0.0, "size_units": 1.0},
]

## **Scaling reworked 2026-09-17** ("all these monsters are more or less
## the same size in real live, but they are not scaled like that") - every
## real mesh used to be auto-scaled so its HEIGHT (Y-axis, or the
## orientation-corrected equivalent) matched a fixed target, which
## guarantees identical HEIGHTS but leaves WIDTH/DEPTH completely
## unconstrained - confirmed as the actual root cause via direct
## computation, not guessed: Wolf (a naturally wide/long quadruped) and
## Vampire (a slender humanoid) both land on exactly the same forced
## height by construction, yet Wolf's rendered WIDTH (0.945) and DEPTH
## (1.483) came out meaningfully bigger than Vampire's (0.648/1.084) -
## same height, genuinely different overall bulk, which is exactly what
## the user was seeing ("the wolf is just a lot bigger than the vampire").
## Now scales by the mesh's own OVERALL BOUNDING-BOX DIAGONAL
## (`aabb.size.length()`, `sqrt(x²+y²+z²)`) instead of a single axis -
## rotation-invariant (doesn't care which local axis pitch_correction maps
## to "up", so no per-branch axis selection needed the way height_min
## still needs below) and captures TRUE overall size regardless of
## whether a creature is naturally tall-thin or short-wide, rather than
## forcing every body type into an identical silhouette height while
## bulk drifts freely.
##
## `size_units` (see REAL_MONSTERS' own doc above) is a REAL, intentional
## exception to "same size" - Centurion is canonically 2x bigger in the
## actual game, not mesh-scale noise, so its target diagonal is doubled
## rather than matched to everyone else's.
##
## Replaces an earlier single fixed REAL_MESH_SCALE that made Centurion
## look oddly large next to a placeholder cube ("the centaur is a bit
## different as it is bigger" - turned out, much later, to be a real
## design fact about the game rather than noise to normalize away, see
## REAL_MONSTERS' own `size_units` doc above).
##
## Not a `const` - `Vector3.length()` isn't a constant-foldable expression
## in GDScript (confirmed via a real parse error, not assumed:
## "Assigned value... isn't a constant expression"), so this is computed
## once in `_ready()` instead.
var target_figure_diagonal: float

var camera: FreeLookCamera

## Set BEFORE add_child() to use this node as a plain holder for individual
## stands placed via place_stand() (MissionPlayer's "place the monsters on
## the map" step) instead of the roster-grid mockup: skips building the
## camera/grid and the test-only base-gap markers.
var standalone: bool = false


## Parent of every stand/figure/label, so refresh_monsters() can clear
## them all without touching the camera.
var _stands_root: Node3D


func _ready() -> void:
	target_figure_diagonal = FIGURE_SIZE.length()
	_stands_root = Node3D.new()
	add_child(_stands_root)
	if standalone:
		return
	_build_camera()
	refresh_monsters([])


## Rebuilds the M-key monster view from the live registry
## (MissionRuntime.monsters, new 2026-09-19): one stand per registered
## monster in a grid, each with its real colour chip on the base notch (the
## old roster-of-every-type test grid is gone - this shows only monsters
## that actually spawned). Also re-frames the camera on the grid.
func refresh_monsters(monsters: Array) -> void:
	for child in _stands_root.get_children():
		child.free()
	for i in monsters.size():
		var monster: RuntimeMonster = monsters[i]
		var info := find_monster(monster.folder)
		if info.is_empty():
			continue
		var origin := Vector3((i % GRID_COLUMNS) * CELL_SPACING, 0, (i / GRID_COLUMNS) * CELL_SPACING)
		_build_stand(origin, info, i, MonsterChip.color(monster.chip))
	_frame_camera(monsters.size())


## Builds one monster stand (base + figure + name label) at `origin` in
## this node's local space. `monster` is a MonsterDisplay.REAL_MONSTERS
## entry; `index` only picks the placeholder-cube colour. `chip_color`
## (alpha 0 = none) draws the colour-chip marker on the base notch.
func place_stand(origin: Vector3, monster: Dictionary, index: int = 0, chip_color: Color = Color(0, 0, 0, 0)) -> void:
	_build_stand(origin, monster, index, chip_color)


## The REAL_MONSTERS entry whose `folder` matches, or an empty Dictionary.
static func find_monster(folder: String) -> Dictionary:
	for monster in REAL_MONSTERS:
		if monster["folder"] == folder:
			return monster
	return {}


## TEMPORARY - a plain fixed Camera3D made it hard to tell what was
## actually wrong with a mesh's orientation/scale ("it's hard to tell
## what's wrong" - fair, a static angle can't rotate around a model to
## check). FreeLookCamera (the same right-click-drag/WASD navigation the
## world view already uses) for now - revisit once this stops being a
## "compare test meshes" mockup and becomes a real designed view.
func _build_camera() -> void:
	camera = FreeLookCamera.new()
	add_child(camera)

	# Starts hidden (visible = false in MissionPlayer.tscn), but a node's
	# _input()/_unhandled_input() processing is ON by default regardless of
	# visibility - without this, right-click-dragging in the WORLD view
	# before "M" is ever pressed would ALSO silently rotate this (invisible,
	# not yet current) camera. MissionPlayer._set_monster_display_visible()
	# re-enables this while shown.
	camera.set_process_input(false)
	camera.set_process_unhandled_input(false)


## Frames the camera on a grid of `count` stands (jump_to() rather than a
## manual position, so FreeLookCamera's internal yaw/pitch stay in sync).
## Called from refresh_monsters(), i.e. every time the registry changes.
func _frame_camera(count: int) -> void:
	var columns := mini(maxi(count, 1), GRID_COLUMNS)
	var rows := ceili(float(maxi(count, 1)) / GRID_COLUMNS)
	var grid_width := (columns - 1) * CELL_SPACING
	var grid_depth := (rows - 1) * CELL_SPACING
	var center := Vector3(grid_width * 0.5, 0, grid_depth * 0.5)

	# Distance scales with the grid's own diagonal (not a flat constant) -
	# 8.0 was sized for the original 2x2 proof-of-concept grid and left the
	# 5-wide/4-deep 18-monster grid mostly out of frame. Same "scale to
	# what's actually being framed" idea as MissionPlayer's
	# SPAWN_VIEW_RADIUS_MULTIPLIER, just simpler (a flat multiplier is
	# enough here - this is a static initial framing, not something that
	# needs a min-distance floor for a tiny grid, since FreeLookCamera
	# navigation is right there either way).
	var distance: float = max(grid_width, grid_depth) * 0.9 + 4.0

	# jump_to() (not a manual position + look_at()) specifically because it
	# also updates FreeLookCamera's own internal _yaw/_pitch state - set
	# those directly and the FIRST right-click-drag would compute rotation
	# from stale zeros and snap the camera back to facing however it
	# happened to be oriented at _ready(), same gotcha jump_to()'s own doc
	# comment already warns about.
	camera.jump_to(center, distance)


## One "stand" = a base (the plastic-base stand-in) plus a figure (the real
## extracted mesh, or a placeholder cube if its files are missing) sitting
## on top, plus a floating name label.
func _build_stand(origin: Vector3, monster: Dictionary, index: int, chip_color: Color = Color(0, 0, 0, 0)) -> void:
	var size_units: float = monster.get("size_units", 1.0)

	# Base FOOTPRINT (X/Z) scales with size_units too, not just the figure
	# on top - confirmed as a real follow-on bug, not a math error: after
	# the diagonal-based scaling rework, Centurion's mesh was verified by
	# direct computation to be EXACTLY centered on its stand origin (world
	# X/Z center = (0,0), corner-to-corner), but a size_units=2.0 figure
	# standing on a still-1-unit-sized base visibly dwarfs/overflows a
	# base far too small to contain it, which reads as "off center" even
	# though the underlying math never was. Thickness (Y) stays constant -
	# only the game's own real footprint concept (bigger monster, bigger
	# base) should scale, not how tall the plinth itself is.
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(BASE_SIZE.x * size_units, BASE_SIZE.y, BASE_SIZE.z * size_units)
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = Color(0.15, 0.15, 0.15)
	base_mesh.material = base_material
	base.mesh = base_mesh
	base.position = origin + Vector3(0, BASE_SIZE.y * 0.5, 0)
	_stands_root.add_child(base)

	_build_real_figure(origin, monster, index, chip_color)

	# Label offset scales with size_units too (a rough approximation, not
	# exact geometry - the real per-monster rendered height now varies with
	# body proportions as well as size_units since the diagonal-based scale
	# above no longer forces identical heights) so a genuinely bigger
	# monster's name doesn't end up floating inside its own figure.
	var label := Label3D.new()
	label.text = monster["name"]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = origin + Vector3(0, BASE_SIZE.y + FIGURE_SIZE.y * size_units + 0.3, 0)
	_stands_root.add_child(label)


func _build_placeholder_figure(origin: Vector3, index: int, size_units: float = 1.0) -> void:
	var figure := MeshInstance3D.new()
	var figure_mesh := BoxMesh.new()
	figure_mesh.size = FIGURE_SIZE * size_units
	var figure_material := StandardMaterial3D.new()
	figure_material.albedo_color = Color.from_hsv(float(index) / REAL_MONSTERS.size(), 0.6, 0.85)
	figure_mesh.material = figure_material
	figure.mesh = figure_mesh
	figure.position = origin + Vector3(0, BASE_SIZE.y + FIGURE_SIZE.y * size_units * 0.5, 0)
	_stands_root.add_child(figure)


## Loads `monster`'s pre-converted mesh + texture from
## user://monster_assets/<folder>/ via a plain ResourceLoader.load() (see
## class doc above for how mesh.tres gets there - Godot's own native
## importer already did the real conversion work, this just reads the
## result) and Image.load_from_file()/ImageTexture.create_from_image() (the
## exact same proven pattern OfficialAssetOverrides._load_override_texture()
## already uses for user:// textures). Auto-scales via the loaded mesh's own
## Mesh.get_aabb() so every monster's OVERALL SIZE (bounding-box diagonal,
## not just height - see target_figure_diagonal's own doc above for why)
## matches its `size_units`-scaled target regardless of its source mesh's
## native scale, and lifts it by its own AABB's lowest point (not a flat
## BASE_SIZE.y guess) so its feet sit AT the base's top surface rather than
## floating or sinking in. Falls back to the cube placeholder if the .tres
## is missing or fails to load.
##
## When `pitch_correction_degrees` is non-zero (see REAL_MONSTERS' own doc
## above), the "height" axis in the mesh's own LOCAL space is Z, not Y -
## Mesh.get_aabb() always reports LOCAL bounds, unaffected by whatever
## rotation gets applied to the MeshInstance3D node below, so the
## vertical-lift math (height_min below - the SCALE factor itself no
## longer needs this axis selection, see target_figure_diagonal's own doc)
## has to read aabb.position.z instead of aabb.position.y for those
## meshes, or feet/head would swap places.
func _build_real_figure(origin: Vector3, monster: Dictionary, index: int, chip_color: Color = Color(0, 0, 0, 0)) -> void:
	var mesh_path := "user://monster_assets/%s/mesh.tres" % monster["folder"]
	var texture_path := "user://monster_assets/%s/diffuse.png" % monster["folder"]

	if not ResourceLoader.exists(mesh_path):
		_build_placeholder_figure(origin, index, monster.get("size_units", 1.0))
		return
	var mesh: Mesh = ResourceLoader.load(mesh_path)
	if mesh == null:
		_build_placeholder_figure(origin, index, monster.get("size_units", 1.0))
		return

	var aabb := mesh.get_aabb()
	var pitch_correction: float = monster["pitch_correction_degrees"]

	# Which local-Z extreme counts as "feet" flips with the SIGN of the
	# pitch correction, not just whether it's applied - Rx(-90) maps
	# world_y = +local_z (so the local Z MINIMUM is the lowest point,
	# "feet"), but Rx(+90) maps world_y = -local_z (NEGATED - so the local
	## Z MAXIMUM becomes the lowest point instead). Using the min
	# unconditionally here was a real bug caught before Wolf's own
	# pitch_correction_degrees became the first (and, so far, only) +90 in
	# this roster ("needs the same rotation as Vampire/Salamander/
	# Legionnaire but the other way around") - without this, Wolf's feet
	# and head swap places, floating the figure off its base instead of
	# standing on it.
	var height_min: float
	if pitch_correction < 0.0:
		height_min = aabb.position.z
	elif pitch_correction > 0.0:
		height_min = aabb.position.z + aabb.size.z
	else:
		height_min = aabb.position.y

	# Diagonal-based, not height-based (see target_figure_diagonal's own doc
	# above for why) - rotation-invariant (sqrt(x²+y²+z²) doesn't care which
	# local axis pitch_correction maps to "up"), so no axis-selection branch
	# needed here the way height_min still needs one below for POSITIONING.
	var size_units: float = monster.get("size_units", 1.0)
	var raw_diagonal := aabb.size.length()
	var scale_factor := (target_figure_diagonal * size_units) / raw_diagonal if raw_diagonal > 0.0 else 1.0

	var figure := MeshInstance3D.new()
	figure.mesh = mesh
	figure.scale = Vector3.ONE * scale_factor
	figure.rotation_degrees = Vector3(pitch_correction, monster["extra_rotation_degrees"], 0.0)

	# Centers the figure horizontally on its stand (X/Z only - vertical
	# placement stays governed by height_min above, "feet on the base");
	# a mesh whose own local origin isn't centered under its geometry
	# otherwise sits visibly off to one side (confirmed real, e.g.
	# "model 2 is off center"). pivot_local is the local-space POINT that
	# should map onto the stand's origin: the AABB's CENTER on the two
	# horizontal axes, but its MIN on the height axis (same height_min as
	# above - swap which local axis is "up" under pitch_correction, don't
	# swap min-vs-center). figure.basis, read AFTER scale/rotation are
	# both set, already composes rotation+scale (confirmed via a headless
	# check, not assumed - Node3D.basis correctly reflects both), so
	# multiplying it through pivot_local gives the correctly rotated AND
	# scaled world-space offset with no separate hand-derived per-axis
	# formula needed.
	var pivot_local: Vector3
	if pitch_correction != 0.0:
		pivot_local = Vector3(
			aabb.position.x + aabb.size.x * 0.5,
			aabb.position.y + aabb.size.y * 0.5,
			height_min,
		)
	else:
		pivot_local = Vector3(
			aabb.position.x + aabb.size.x * 0.5,
			height_min,
			aabb.position.z + aabb.size.z * 0.5,
		)
	figure.position = origin + Vector3(0, BASE_SIZE.y, 0) - figure.basis * pivot_local

	var material := StandardMaterial3D.new()
	if FileAccess.file_exists(texture_path):
		var image := Image.load_from_file(texture_path)
		if image != null:
			material.albedo_texture = ImageTexture.create_from_image(image)
	figure.material_override = material
	_stands_root.add_child(figure)

	# TEST ONLY - see BaseGapDetector.gd's own class doc for the full
	# feasibility investigation this is built from, including the
	# annulus-related known limitation logged as an open TODO rather than
	# re-guessed at again. figure.basis already has scale+rotation baked
	# in at this point (needed for the centering math above) - reused
	# as-is here too, since uniform scale doesn't change which vertices
	# are lowest/highest or their angular order, so it works equally well
	# for BaseGapDetector's own internal floor/angle analysis. scale_factor
	# is threaded through separately (not re-derived from figure.basis) so
	# _build_gap_marker() can convert GAP_WALL_HEIGHT_WORLD back into this
	# specific mesh's own local units - see that constant's own doc.
	# The chip marker: the REAL colour when one was given (registered
	# monsters), else - only in the old non-standalone mockup path - the
	# per-index test colour. Standalone placement without a chip has none.
	if chip_color.a > 0.0:
		_build_gap_marker(figure, mesh, chip_color, scale_factor)


## TEST ONLY - visually verifies BaseGapDetector.gd actually finds the
## right spot on every monster in the roster at once, without needing to
## launch the editor and eyeball each one individually (which isn't
## possible in this environment anyway - see this project's own
## "Unverified in-editor" convention). Builds a small flat 2-triangle quad
## covering the detected gap and parents it directly to `figure` - a plain
## child with NO extra local transform needed, since BaseGapDetector
## returns its 4 corners in the mesh's own untouched local space (the same
## space `figure.mesh`'s own vertex data already lives in), so it
## automatically inherits `figure`'s full position/rotation/scale chain
## for free. Cycles through GAP_MARKER_TEST_COLORS by grid index purely so
## every stand's coverage is visible at a glance, NOT a real per-monster
## color assignment (see that const's own doc). Silently does nothing if
## detection fails for this particular mesh - same "never hard-fail over
## one thing" convention as the real-mesh/placeholder fallback above.
##
## **`BaseGapDetector` SYNTHESIZES the inner two corners (outer_a/outer_b
## nudged straight up) instead of searching the mesh for a "real" higher
## vertex** - see that script's own class doc for why (the search-based
## approach's annulus bug and the two abandoned attempts at fixing the
## search itself, both tried and reverted after making the rendered result
## worse per direct user feedback).
##
## **Extruded into a real solid box, 2026-09-17** ("can we make it a mesh
## by extruding it backward a bit?") - the flat 2-triangle quad from before
## had zero thickness, relying entirely on UNSHADED + CULL_DISABLED to stay
## visible at all; this instead builds a genuine 6-face prism (front face +
## back face + 4 side walls) by pushing a second copy of the same 4 corners
## along the front face's own normal. `GAP_MARKER_DEPTH_RATIO` sizes that
## push as a fraction of the panel's OWN height (the outer-to-inner
## distance) rather than a fixed world-space number, so the marker's
## proportions stay consistent per-monster the same way GAP_WALL_HEIGHT_WORLD
## does. The extrude direction is just "whichever side the existing
## front-triangle winding faces, or its opposite" - `BaseGapDetector`
## never promised a specific outward/inward winding (see its own doc), so
## this was never derived from which way is physically "into the model,"
## it only needed SOME consistent direction to extrude into, and the sign
## is whatever reads correctly once actually seen rendered - currently
## `-normal` (see this function's own `back_offset` line for the full
## history: flipped to `+normal` once per direct feedback, then flipped
## BACK to `-normal` after `BaseGapDetector`'s own outer_a/outer_b
## labeling swapped under it during an unrelated rewrite, which silently
## reversed what `+normal` meant without this file's own sign changing -
## confirmed by direct computation, not guessed, that the swap exactly
## negates the cross product this normal comes from).
##
## `scale_factor` (the same value `_build_real_figure()` already computed
## for this monster's own scale) is what lets `GAP_WALL_HEIGHT_WORLD` - one
## fixed height in GAME space, shared by every monster - become the right
## LOCAL-space bump amount for THIS specific mesh (`/ scale_factor`, see
## that constant's own doc for why a shared world height replaced the
## earlier per-mesh percentage).
##
## **Width normalization (a `GAP_WIDTH_WORLD` re-centering step, matching
## the wall-height fix) was tried and REVERTED 2026-09-17** - direct
## review in the Player found it made every monster look WORSE, not just
## failing to fix Wight ("its still bad and all others look worse now").
## Numeric verification (16/17 monsters clustering tightly around the same
## world chord width before the change) looked like solid justification
## going in, but the rendered result said otherwise - the same lesson
## `BaseGapDetector.gd`'s own class doc already records from the annulus
## saga: don't trust numeric "looks consistent" checks over an actual look
## at the rendered output. Reverted back to using `detect_gap_quad()`'s
## own raw `outer_a`/`outer_b` directly - Wight's real problem (whatever it
## actually is) is still open, and needs a real look at its base mesh
## rather than another guess from this environment.
func _build_gap_marker(figure: MeshInstance3D, mesh: Mesh, marker_color: Color, scale_factor: float) -> void:
	var wall_height_local: float = GAP_WALL_HEIGHT_WORLD / scale_factor if scale_factor > 0.0 else GAP_WALL_HEIGHT_WORLD
	var quad := BaseGapDetector.detect_gap_quad(mesh, figure.basis, wall_height_local)
	if quad.is_empty():
		return

	var outer_a: Vector3 = quad["outer_a"]
	var outer_b: Vector3 = quad["outer_b"]
	var inner_a: Vector3 = quad["inner_a"]
	var inner_b: Vector3 = quad["inner_b"]

	var normal: Vector3 = (outer_b - outer_a).cross(inner_a - outer_a).normalized()
	var panel_height: float = (inner_a - outer_a).length()
	# Negated - 2026-09-17, after `BaseGapDetector.detect_gap_quad()` was
	# rewritten and its outer_a/outer_b labeling came out SWAPPED relative
	# to before (confirmed by direct computation: Zealot's new outer_a/
	# outer_b are the old outer_b/outer_a, and (outer_b - outer_a).cross(...)
	# is linear in its first argument, so swapping the two operands exactly
	# negates the result - verified numerically, dot product -1.0, not
	# assumed). That silently flipped the extrude direction back to the
	# one already rejected once ("extrude in the other direction") without
	# this file's own `+normal` sign actually changing - the fix belongs
	# here, not in BaseGapDetector (which never promised a specific
	# outer_a/outer_b handedness to begin with, see its own doc).
	var back_offset: Vector3 = -normal * panel_height * GAP_MARKER_DEPTH_RATIO

	var back_outer_a: Vector3 = outer_a + back_offset
	var back_outer_b: Vector3 = outer_b + back_offset
	var back_inner_a: Vector3 = inner_a + back_offset
	var back_inner_b: Vector3 = inner_b + back_offset

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad_face(st, outer_a, outer_b, inner_b, inner_a)  # front
	_add_quad_face(st, back_inner_a, back_inner_b, back_outer_b, back_outer_a)  # back (reversed)
	_add_quad_face(st, outer_a, outer_b, back_outer_b, back_outer_a)  # side: outer edge
	_add_quad_face(st, outer_b, inner_b, back_inner_b, back_outer_b)  # side: inner_b edge
	_add_quad_face(st, inner_b, inner_a, back_inner_a, back_inner_b)  # side: inner edge
	_add_quad_face(st, inner_a, outer_a, back_outer_a, back_inner_a)  # side: outer_a edge
	var marker_mesh := st.commit()

	var marker := MeshInstance3D.new()
	marker.mesh = marker_mesh
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = marker_color
	# Unshaded (flat, ignores DirectionalLight3D) so the test color always
	# reads the same regardless of lighting angle - a real solid box now
	# has correct outward-facing normals on every face (see
	# _add_quad_face()), so CULL_DISABLED is no longer load-bearing the way
	# it was for the old zero-thickness quad, but it's kept anyway as cheap
	# insurance against a degenerate/inverted face on some mesh's geometry.
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = marker_material
	figure.add_child(marker)


## Adds one flat-shaded quad face (as two triangles, `a-b-c` and `a-c-d`)
## to `st`, all four vertices sharing the SAME computed normal - correct
## for a hard-edged box like the gap marker's, where each face should read
## as a distinct flat plane rather than smoothly blending into its
## neighbors. `a, b, c, d` must be wound consistently (CCW when viewed from
## the direction the face should point) same as every other quad-from-4-
## points helper in this project.
func _add_quad_face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_normal(normal)
	st.add_vertex(b)
	st.set_normal(normal)
	st.add_vertex(c)
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_normal(normal)
	st.add_vertex(c)
	st.set_normal(normal)
	st.add_vertex(d)
