class_name GroundFloor
extends RefCounted

## The huge concrete ground plane shared by the world map (MissionPlayer) and
## the monster view (MonsterDisplay). Texture: ambientCG "Concrete036" (CC0,
## https://ambientcg.com/a/Concrete036), brightened in the file.

## Side of the plane (world units) - "really big", so no edge is ever visible.
const SIZE := 2000.0
## Tiles of the texture across the plane (~4 units each).
const TEXTURE_REPEAT := 500.0


const MAP_TEXTURE := "res://models/floor_concrete.jpg"      ## official: GroundStone_Diffuse
const MONSTER_TEXTURE := "res://models/floor_enemy.jpg"      ## official: EnemyGround


## `placeholder` is one of the two constants above; the original game's texture is used when it was imported.
static func create(y: float, placeholder: String = MAP_TEXTURE) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = OfficialAssetOverrides.texture_for(placeholder)
	mat.uv1_scale = Vector3(TEXTURE_REPEAT, TEXTURE_REPEAT, 1.0)
	mat.texture_repeat = true
	mat.roughness = 1.0
	plane.material = mat
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.position.y = y
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ground
