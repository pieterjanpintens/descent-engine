class_name StageHighlight
extends Node3D

## White outline (and, for floor tiles, a name label) around the pieces a
## stage-setup page is currently telling the table to place - see
## MissionPlayer.show_stage(). The outline follows the true perimeter of each
## piece's occupied cells (an edge is drawn wherever the neighbouring cell
## isn't part of the same piece), so irregular tiles read correctly.
## Child of layered_map, so it hides with the world in the monster view.

const LINE_WIDTH := 0.05
const LIFT := 0.04  ## above the floor surface (floor_thickness is added too)

## Assigned by MissionPlayer.
var layered_map: LayeredMap
var mission: MissionData

var _nodes: Array[Node] = []


func clear() -> void:
	for n in _nodes:
		n.queue_free()
	_nodes.clear()


## `pieces`: MissionPlayer._stage_pieces() entries ({node, bucket, mesh}).
## Labels (the mesh name) are only added for "floor" pieces.
func show_pieces(pieces: Array, with_labels: bool) -> void:
	clear()
	if pieces.is_empty():
		return
	var cells_of := _cells_of(pieces)
	var grid := layered_map.floor_grid
	var cs := grid.cell_size
	var lift := layered_map.floor_thickness + LIFT  # above the surface of the piece's OWN level
	var w := LINE_WIDTH
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for piece in pieces:
		var cells: Array = cells_of.get(piece["node"], [])
		if cells.is_empty():
			continue
		var set := {}
		for c: Vector3i in cells:
			set[c] = true
		var sum := Vector3.ZERO
		for c: Vector3i in cells:
			var o: Vector3 = grid.map_to_local(c)
			sum += o + Vector3(cs.x / 2.0, lift, cs.z / 2.0)
			for side in [Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1)]:
				if set.has(c + side):
					continue
				_add_edge(st, o, cs, side, o.y + lift, w)
		if with_labels and piece["bucket"] == "floor":
			var label := Label3D.new()
			label.text = str(piece["mesh"])
			label.modulate = Color(1, 1, 1)
			label.outline_modulate = Color(0, 0, 0, 0.9)
			label.outline_size = 12
			label.font_size = 64
			label.pixel_size = 0.012
			label.rotation_degrees.x = -90
			add_child(label)
			var center: Vector3 = sum / cells.size()
			label.global_position = grid.to_global(Vector3(center.x, center.y + 0.01, center.z))
			_nodes.append(label)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid.add_child(mesh_instance)
	_nodes.append(mesh_instance)


## One edge of the cell whose local corner is `o`, on the given side.
func _add_edge(st: SurfaceTool, o: Vector3, cs: Vector3, side: Vector3i, y: float, w: float) -> void:
	var h := w / 2.0
	var rect: Rect2  # x/z
	if side.x != 0:
		var x := o.x if side.x < 0 else o.x + cs.x
		rect = Rect2(x - h, o.z - h, w, cs.z + w)
	else:
		var z := o.z if side.z < 0 else o.z + cs.z
		rect = Rect2(o.x - h, z - h, cs.x + w, w)
	var a := Vector3(rect.position.x, y, rect.position.y)
	var b := Vector3(rect.end.x, y, rect.position.y)
	var c := Vector3(rect.end.x, y, rect.end.y)
	var d := Vector3(rect.position.x, y, rect.end.y)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


## node -> Array[Vector3i] of the fine cells it covers, via the mission's
## occupancy dictionaries (cell -> origin).
func _cells_of(pieces: Array) -> Dictionary:
	var by_kind := {"floor": {}, "underlay": {}, "prop": {}}  # kind -> origin -> node
	for piece in pieces:
		var kind: String = "prop" if piece["bucket"] == "pillar" else piece["bucket"]
		by_kind[kind][piece["node"].origin_cell] = piece["node"]
	var result := {}
	_collect(result, by_kind["floor"], mission.floor_occupied_cells)
	_collect(result, by_kind["underlay"], mission.underlay_occupied_cells)
	_collect(result, by_kind["prop"], mission.occupied_cells)
	return result


func _collect(result: Dictionary, wanted: Dictionary, occupied: Dictionary) -> void:
	if wanted.is_empty():
		return
	for cell: Vector3i in occupied:
		var owners: Variant = occupied[cell]
		if not owners is Array:  # old single-owner format
			owners = [owners]
		for origin in owners:
			if wanted.has(origin):
				var node = wanted[origin]
				if not result.has(node):
					result[node] = []
				result[node].append(cell)
