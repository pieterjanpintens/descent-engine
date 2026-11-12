class_name GroundFloor
extends RefCounted

## The huge concrete ground plane shared by the world map (MissionPlayer) and
## the monster view (MonsterDisplay). Texture: ambientCG "Concrete036" (CC0,
## https://ambientcg.com/a/Concrete036), brightened in the file.

## Side of the plane (world units) - "really big", so no edge is ever visible.
const SIZE := 2000.0
## Tiles of the texture across the plane (~4 units each).
const TEXTURE_REPEAT := 500.0
## The map floor repeats its texture less often than the monster view's (the original game's looks larger): this many tiles across the
## plane = SIZE / this world units per repeat (200 -> 10 units, about three tile squares). Tune after a look.
const MAP_TEXTURE_REPEAT := 200.0


const MAP_TEXTURE := "res://models/floor_concrete.jpg"      ## official: GroundStone_Diffuse
const MONSTER_TEXTURE := "res://models/floor_enemy.jpg"      ## official: EnemyGround


## The original game's ground texture is very dark (average ~15% brightness; the game lights it much more than we do), so it is lifted
## with a gamma curve in the shader: 1 = as it is, lower = brighter (it keeps the pattern, brightens the dark parts most).
## The shipped placeholders were already brightened in their files and are never touched. Tune these two after a look.
const OFFICIAL_GAMMA_MAP := 0.6
const OFFICIAL_GAMMA_MONSTER := 1.0

## The play area is lit, the ground around it falls into shadow: outside the rectangle the floor fades to this fraction of its
## brightness (1 = no shadow) over PLAY_FADE world units (a tile square is 3.2). Tune after a look.
const PLAY_OUTSIDE_LIGHT := 0.0  # linear light: even 0.05 still shows as ~20% grey on screen, so it fades out completely
const PLAY_FADE := 18.0
## The lit stage reaches this far past the edge of the board (the original game leaves a good strip of lit table around the map; a tile
## square is 3.2 units), so the shadow only starts out there. Both the ground and the fog use the area grown by this.
const PLAY_MARGIN := 9.0
## How much of its own colour the map floor gives off on top of the scene light (0 = only lit by the scene, which is very dark with the
## game's own ground texture). Fades with the shadow like the rest. Tune after a look.
const PLAY_GLOW := 1.0
## How far (world units) slow noise pushes the edge of the shadow in and out, so it creeps around the play area. 0 = a still edge.
const PLAY_WOBBLE := 3.5
## Inside the play area the floor gets a slight lift (1 = none), so the area reads as the lit stage.
const PLAY_INSIDE_BOOST := 1.12

const _LIFT_SHADER := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float repeat = 500.0;
uniform float gamma = 0.5;
uniform vec4 area = vec4(0.0);            // play area: min x, min z, max x, max z (ground-local); an empty area switches the effect off
uniform float outside_light = 0.25;
uniform float fade = 8.0;
uniform float inside_boost = 1.12;
uniform float wobble = 5.0;               // how far (world units) the edge of the shadow drifts in and out
uniform float glow = 1.0;                 // how much of its own colour the floor gives off, whatever the lighting
varying vec2 lpos;
float hash(vec2 p) {
	// no sin(): its precision differs between GPUs and showed up as hard-edged blocks in the noise
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	lpos = VERTEX.xz;
}
void fragment() {
	vec3 c = texture(albedo_tex, UV * repeat).rgb;
	c = pow(c, vec3(gamma));
	float spec = 0.5;
	if (area.z > area.x) {
		vec2 d = max(area.xy - lpos, lpos - area.zw);
		float sd = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);   // distance to the edge, negative inside
		// slow noise that drifts over the ground pushes the edge of the shadow in and out, so it creeps and breathes
		// each layer is turned a different way so the noise grid never lines up with the board's edges
		vec2 p1 = mat2(vec2(0.825, 0.565), vec2(-0.565, 0.825)) * lpos * 0.11 + vec2(TIME * 0.045, -TIME * 0.035);
		vec2 p2 = mat2(vec2(0.62, -0.785), vec2(0.785, 0.62)) * lpos * 0.29 + vec2(-TIME * 0.07, TIME * 0.05);
		float n = vnoise(p1) * 0.65 + vnoise(p2) * 0.35;
		float k = smoothstep(0.0, fade, sd + (n - 0.5) * 2.0 * wobble);
		c *= mix(inside_boost, outside_light, k);
		spec = mix(0.5, 0.0, k);  // no sheen on the dark ground either, or the far floor keeps a grey glow
	}
	ALBEDO = c;
	EMISSION = c * glow;   // the floor is lit by little more than ambient light, so it also glows a bit by itself
	ROUGHNESS = 1.0;
	SPECULAR = spec;
}
"""
static var _lift_shader: Shader


## Lights the play area (ground-local XZ rectangle, the same space the ground's parent uses) and lets the rest of the ground fall into
## shadow. Only the map ground made with `create()` understands this; an empty rect switches it off.
static func set_play_area(ground: MeshInstance3D, area: Rect2) -> void:
	if ground == null or not ground.mesh is PlaneMesh:
		return
	var mat := (ground.mesh as PlaneMesh).material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("area", Vector4(area.position.x, area.position.y, area.end.x, area.end.y))


## `placeholder` is one of the two constants above; the original game's texture is used when it was imported.
static func create(y: float, placeholder: String = MAP_TEXTURE) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	var texture := OfficialAssetOverrides.texture_for(placeholder)
	var gamma := OFFICIAL_GAMMA_MAP if placeholder == MAP_TEXTURE else OFFICIAL_GAMMA_MONSTER
	# A texture loaded from the user's imported files has no resource path; the shipped placeholder has one.
	var imported: bool = texture != null and texture.resource_path == ""
	if placeholder == MAP_TEXTURE or (imported and gamma < 1.0):
		if _lift_shader == null:
			_lift_shader = Shader.new()
			_lift_shader.code = _LIFT_SHADER
		var lifted := ShaderMaterial.new()
		lifted.shader = _lift_shader
		lifted.set_shader_parameter("albedo_tex", texture)
		lifted.set_shader_parameter("repeat", MAP_TEXTURE_REPEAT if placeholder == MAP_TEXTURE else TEXTURE_REPEAT)
		lifted.set_shader_parameter("gamma", gamma if imported else 1.0)
		lifted.set_shader_parameter("outside_light", PLAY_OUTSIDE_LIGHT)
		lifted.set_shader_parameter("fade", PLAY_FADE)
		lifted.set_shader_parameter("inside_boost", PLAY_INSIDE_BOOST)
		lifted.set_shader_parameter("wobble", PLAY_WOBBLE)
		lifted.set_shader_parameter("glow", PLAY_GLOW if placeholder == MAP_TEXTURE else 0.0)
		plane.material = lifted
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = texture
		var repeat := MAP_TEXTURE_REPEAT if placeholder == MAP_TEXTURE else TEXTURE_REPEAT
		mat.uv1_scale = Vector3(repeat, repeat, 1.0)
		mat.texture_repeat = true
		mat.roughness = 1.0
		plane.material = mat
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.position.y = y
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ground
