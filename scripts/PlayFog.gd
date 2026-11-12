class_name PlayFog
extends RefCounted

## Wisps of fog drifting along the edge of the play area, so the lit stage melts into the dark around it. A flat transparent plane just
## above the floor: two layers of the game's own seamless cloud texture ("Clouds_Wrappable") slide past each other at different speeds, and
## a band around the area's edge decides where the fog is (thickest at the edge, thinning towards the inside and the dark outside).
## No game art, no fog: without the imported texture create() gives null and everything else stays as it is.

const CLOUD_NAME := "Clouds_Wrappable"
## Height above the layered map's origin (the floor top is a little above it).
const HEIGHT := 0.7
## How far the plane reaches past the area (world units); the band ends well before it.
const MARGIN := 40.0

## World units per repeat of the texture (one repeat = this many units across), the drift speeds and the look. Tune after a look.
const CLOUD_SIZE := 22.0
const STRENGTH := 0.5
const INNER := 3.0    ## how far the fog reaches into the play area
const OUTER := 16.0   ## how far it reaches out into the dark
const TINT := Color(0.62, 0.68, 0.78)

const _SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform vec4 area = vec4(0.0);      // play area: min x, min z, max x, max z (parent-local)
uniform vec2 centre = vec2(0.0);    // where this plane sits (parent-local x, z)
uniform float cloud_size = 26.0;
uniform float strength = 0.55;
uniform float inner = 3.0;
uniform float outer = 14.0;
uniform vec3 tint : source_color = vec3(0.62, 0.68, 0.78);
varying vec2 lpos;
void vertex() {
	lpos = VERTEX.xz + centre;
}
void fragment() {
	vec2 d = max(area.xy - lpos, lpos - area.zw);
	float sd = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);   // distance to the edge, negative inside
	float band = smoothstep(-inner, 0.0, sd) * (1.0 - smoothstep(0.0, outer, sd));
	vec2 uv = lpos / vec2(cloud_size * 2.0, cloud_size);   // the texture is twice as wide as it is high
	float a = texture(clouds, uv + vec2(TIME * 0.010, TIME * 0.004)).r;
	float b = texture(clouds, uv * 1.6 + vec2(0.37 - TIME * 0.007, TIME * 0.006)).r;
	float density = smoothstep(0.0, 1.0, (a * 0.6 + b * 0.4 - 0.76) / 0.2);   // the texture only spans ~0.72 - 0.97
	ALBEDO = tint;
	ALPHA = band * density * strength;
}
"""
static var _shader: Shader


## The fog plane, or null when the game's cloud texture was not imported.
static func create() -> MeshInstance3D:
	var clouds := OfficialAssetOverrides.official_texture(CLOUD_NAME)
	if clouds == null:
		return null
	if _shader == null:
		_shader = Shader.new()
		_shader.code = _SHADER
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("clouds", clouds)
	material.set_shader_parameter("cloud_size", CLOUD_SIZE)
	material.set_shader_parameter("strength", STRENGTH)
	material.set_shader_parameter("inner", INNER)
	material.set_shader_parameter("outer", OUTER)
	material.set_shader_parameter("tint", Vector3(TINT.r, TINT.g, TINT.b))
	var plane := PlaneMesh.new()
	plane.material = material
	var fog := MeshInstance3D.new()
	fog.mesh = plane
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return fog


## Puts the fog around `area` (a ground-local XZ rectangle, like GroundFloor.set_play_area()). Safe with null.
static func set_area(fog: MeshInstance3D, area: Rect2) -> void:
	if fog == null:
		return
	var plane := fog.mesh as PlaneMesh
	plane.size = area.size + Vector2.ONE * (2.0 * (OUTER + MARGIN))
	var centre := area.get_center()
	fog.position = Vector3(centre.x, HEIGHT, centre.y)
	var material := plane.material as ShaderMaterial
	material.set_shader_parameter("area", Vector4(area.position.x, area.position.y, area.end.x, area.end.y))
	material.set_shader_parameter("centre", centre)
