class_name TableAreaOverlay
extends Node3D

## The real table in the mission editor (requested 2026-11-18: "it might be sensible to give the mission designer a real scale idea"): an
## outline of a physical table top (CreatorSettings.table_width_cm x table_depth_cm) drawn around the map being built, so you see whether
## the level fits on the table you play on. The size comes from the editor Settings (presets Large 175 x 95, Medium 120 x 90, Small 120 x 75,
## or your own), one tile square is CreatorSettings.square_cm on the table, and View > Table Area switches it on and off.
##
## It frames the pieces of the Table (a mission's "Table" - a separate set-up of the board) you are working in: its long side lies along the
## map's long side and it is centred on the map. Green when the map fits, red when it is bigger than the table in either direction; the label
## says both sizes in cm.

const LINE_WIDTH := 0.35
const FIT_COLOR := Color(0.25, 0.85, 0.35, 0.95)
const TOO_BIG_COLOR := Color(0.95, 0.3, 0.25, 0.95)

var layered_map: LayeredMap
var creator_controller: CreatorController

var _mesh := MeshInstance3D.new()
var _label := Label3D.new()
var _material := StandardMaterial3D.new()
var _queued := false


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = _material
	add_child(_mesh)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0015
	_label.font_size = 28
	_label.outline_size = 8
	_label.outline_modulate = Color(0, 0, 0, 0.85)
	add_child(_label)
	CreatorSettings.settings_changed.connect(refresh)
	layered_map.mission_objects_changed.connect(refresh)
	creator_controller.working_group_changed.connect(func(_id: String): refresh())
	refresh()


## Redraws on the next frame (the map can change many times in one paint stroke).
func refresh() -> void:
	if _queued:
		return
	_queued = true
	_redraw.call_deferred()


func _redraw() -> void:
	_queued = false
	visible = false
	if not CreatorSettings.table_overlay or layered_map.mission == null or CreatorSettings.square_cm <= 0.0:
		return
	var bounds: Variant = _map_bounds()
	if bounds == null:
		return
	var low: Vector3i = bounds[0]  # 1-based tile squares, inclusive
	var high: Vector3i = bounds[1]
	var map_x := high.x - low.x + 1
	var map_z := high.z - low.z + 1
	# the table's long side along the map's long side
	var long_cm := maxf(CreatorSettings.table_width_cm, CreatorSettings.table_depth_cm)
	var short_cm := minf(CreatorSettings.table_width_cm, CreatorSettings.table_depth_cm)
	var table_x_cm := long_cm if map_x >= map_z else short_cm
	var table_z_cm := short_cm if map_x >= map_z else long_cm
	var square := layered_map.get_tile_square_world_corners(Vector3i(1, 0, 1))
	var unit := square[1].x - square[0].x  # world size of one tile square
	var map_min := layered_map.get_tile_square_world_corners(Vector3i(low.x, 0, low.z))[0]
	var map_max := layered_map.get_tile_square_world_corners(Vector3i(high.x, 0, high.z))[2]
	var centre := (map_min + map_max) * 0.5
	var half := Vector2(table_x_cm, table_z_cm) / CreatorSettings.square_cm * unit * 0.5
	var y := map_min.y + 0.05
	var fits := map_x * CreatorSettings.square_cm <= table_x_cm + 0.01 and map_z * CreatorSettings.square_cm <= table_z_cm + 0.01
	_material.albedo_color = FIT_COLOR if fits else TOO_BIG_COLOR
	_mesh.mesh = _frame(Vector3(centre.x - half.x, y, centre.z - half.y), Vector3(centre.x + half.x, y, centre.z + half.y))
	_label.modulate = _material.albedo_color.lightened(0.3)
	_label.position = Vector3(centre.x - half.x, y + 0.5, centre.z - half.y)
	_label.text = "Table %s x %s cm\nMap %s x %s cm (%d x %d squares)%s" % [
		_cm(CreatorSettings.table_width_cm), _cm(CreatorSettings.table_depth_cm),
		_cm(map_x * CreatorSettings.square_cm), _cm(map_z * CreatorSettings.square_cm), map_x, map_z,
		"" if fits else "\ndoes not fit"]
	visible = true


## The rectangle the Table being worked in takes up (MissionData.table_bounds()).
func _map_bounds() -> Variant:
	return layered_map.mission.table_bounds(creator_controller.working_table_id())


## A flat frame of LINE_WIDTH-wide strips along the rectangle from `a` (min corner) to `b` (max corner).
func _frame(a: Vector3, b: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := LINE_WIDTH
	_quad(st, Vector3(a.x - w, a.y, a.z - w), Vector3(b.x + w, a.y, a.z))
	_quad(st, Vector3(a.x - w, a.y, b.z), Vector3(b.x + w, a.y, b.z + w))
	_quad(st, Vector3(a.x - w, a.y, a.z), Vector3(a.x, a.y, b.z))
	_quad(st, Vector3(b.x, a.y, a.z), Vector3(b.x + w, a.y, b.z))
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var p := [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(p[i])


static func _cm(value: float) -> String:
	return String.num(value, 0) if is_equal_approx(value, roundf(value)) else String.num(value, 1)
