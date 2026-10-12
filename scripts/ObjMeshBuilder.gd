class_name ObjMeshBuilder
extends RefCounted

## Turns a Wavefront .obj file into an ArrayMesh at RUN TIME, for the in-app asset import (AssetImporter): an exported
## game has no editor importers, so Godot's own .obj importer cannot be used there.
##
## It follows what Godot's importer (ResourceImporterOBJ) does with the same file, so a mesh converted here matches
## one converted by the editor through tools/asset_import: positions and normals as written, the texture V flipped
## (1 - v), every triangle's first two corners swapped (the file is counter-clockwise, Godot's front faces are
## clockwise), polygons split as a fan, a new surface at every `usemtl` line, named after the material (`g` and `o`
## lines do NOT start a surface), tangents generated when there are texture coordinates, then indexed.
## Checked against the editor's result for all 49 game meshes: same surfaces, vertex and triangle counts, bounds,
## facing and texture coordinates.
##
## Never instantiated - a namespace for build().


## The mesh of the .obj file at `path` (any path FileAccess opens), or null when it has no faces / cannot be read.
static func build(path: String) -> ArrayMesh:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var mesh := ArrayMesh.new()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pending := 0  # corners added to `tool` since the last surface
	var material := ""

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("v "):
			var parts := line.split(" ", false)
			if parts.size() >= 4:
				vertices.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
		elif line.begins_with("vt "):
			var parts := line.split(" ", false)
			if parts.size() >= 3:
				uvs.append(Vector2(parts[1].to_float(), 1.0 - parts[2].to_float()))
		elif line.begins_with("vn "):
			var parts := line.split(" ", false)
			if parts.size() >= 4:
				normals.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
		elif line.begins_with("f "):
			var corners := line.split(" ", false)
			# A fan over the polygon: (1, i, i+1). The first two corners of each triangle are swapped.
			for i in range(2, corners.size() - 1):
				for corner in [corners[i], corners[1], corners[i + 1]]:
					if _add_corner(tool, corner, vertices, normals, uvs):
						pending += 1
		elif line.begins_with("usemtl "):
			if pending > 0:
				_commit(tool, mesh, material, normals.is_empty(), not uvs.is_empty())
				tool = SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				pending = 0
			material = line.substr(line.find(" ") + 1).strip_edges()
	if pending > 0:
		_commit(tool, mesh, material, normals.is_empty(), not uvs.is_empty())
	return mesh if mesh.get_surface_count() > 0 else null


## One "v", "v/vt", "v//vn" or "v/vt/vn" corner (1-based, negative = counted from the end). False if it is unusable.
static func _add_corner(tool: SurfaceTool, corner: String, vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array) -> bool:
	var parts := corner.split("/")
	var vertex := _index(parts[0], vertices.size())
	if vertex < 0:
		return false
	if parts.size() == 3:
		var normal := _index(parts[2], normals.size())
		if normal >= 0:
			tool.set_normal(normals[normal])
	if parts.size() >= 2 and parts[1] != "":
		var uv := _index(parts[1], uvs.size())
		if uv >= 0:
			tool.set_uv(uvs[uv])
	tool.add_vertex(vertices[vertex])
	return true


static func _index(text: String, count: int) -> int:
	var number := text.to_int()
	var index := number - 1 if number > 0 else count + number
	return index if number != 0 and index >= 0 and index < count else -1


static func _commit(tool: SurfaceTool, mesh: ArrayMesh, material: String, make_normals: bool, make_tangents: bool) -> void:
	if make_normals:
		tool.generate_normals()
	if make_tangents:
		tool.generate_tangents()
	tool.index()
	tool.commit(mesh)
	if material != "":
		mesh.surface_set_name(mesh.get_surface_count() - 1, material.get_basename())
