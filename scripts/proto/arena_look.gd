extends RefCounted
## 아레나의 수묵담채 분위기 (GDD 8.3: 세계는 색을 유지한다 → 옅은 채색 + 먹 선·먹 번짐)
##   - 바닥: 화선지. 큰 먹 번짐 얼룩과 종이 섬유결, 4 m마다 붓으로 그은 듯한 격자선(16 m마다 굵게) → 속도감
##   - 벽·발판: 적과 같은 수묵담채 재질(ink_wash_look.gd). 종류마다 색이 다르다
##       벽 = 따뜻한 회색 종이, 탈 수 있는 벽 = 청회색 + 세로 붓결(GDD 3.3: 벽 타기 가능 지형을 색과 결로 구분),
##       발판 = 옅은 담황색
##   - 하늘·안개: 종이빛 하늘과 거리 안개 → 먼 곳이 먹이 번지듯 흐려진다
##   - 먼 산: 외벽 밖에 겹겹이 선 산수화 봉우리 (안개에 묻혀 옅어진다)

const InkWash := preload("res://scripts/combat/ink_wash_look.gd")

## 벽 종류별 담채 색 (선형 공간). 적(황토·비취)·플레이어(남색) 색과 겹치지 않게 고른다
const TINT_WALL := Color(0.36, 0.34, 0.3)
const TINT_CLIMB := Color(0.13, 0.19, 0.28)
const TINT_PLATFORM := Color(0.5, 0.42, 0.28)

const FLOOR_SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform vec3 paper = vec3(0.17, 0.158, 0.13);  // 화선지 (선형). 흰 이펙트(검기·섬광)가 묻히지 않게 중간 밝기로
uniform float grid = 4.0;                      // 격자선 간격 (m)

varying vec3 wp;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	p = rot * p + vec2(3.1, 5.7);
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = rot * p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}

// 붓으로 그은 격자선 하나: 굵기가 출렁이고 마른 붓처럼 군데군데 끊긴다
float brush_line(float d, float along, float width, float seed) {
	float w = width * (0.6 + 0.8 * fbm(vec2(along * 0.15, seed)));
	float l = 1.0 - smoothstep(w * 0.5, w, d);
	l *= smoothstep(0.3, 0.55, fbm(vec2(along * 0.6, seed * 3.0)));
	return l;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	// 화선지: 큰 담묵 얼룩 + 잔 섬유
	float clouds = fbm(p * 0.035);
	float stain = fbm(p * 0.11 + 7.0);
	float fiber = noise(p * 9.0) * 0.5 + noise(p * 23.0) * 0.5;
	vec3 col = paper * (0.93 + 0.07 * fiber);
	col *= 1.0 - 0.18 * smoothstep(0.45, 0.75, clouds);           // 넓게 번진 옅은 먹
	col *= 1.0 - 0.12 * smoothstep(0.55, 0.8, stain);             // 작은 먹 얼룩

	// 격자선: 4 m마다 가늘게, 16 m마다 굵게. 속도감과 거리감을 준다
	vec2 g = abs(fract(p / grid + 0.5) - 0.5) * grid;
	vec2 G = abs(fract(p / (grid * 4.0) + 0.5) - 0.5) * grid * 4.0;
	float lines = max(brush_line(g.x, p.y, 0.07, 1.0), brush_line(g.y, p.x, 0.07, 2.0));
	float big = max(brush_line(G.x, p.y, 0.16, 3.0), brush_line(G.y, p.x, 0.16, 4.0));
	col = mix(col, col * 0.5, lines * 0.55);
	col = mix(col, vec3(0.02, 0.02, 0.025), big * 0.7);

	ALBEDO = col;
	ROUGHNESS = 1.0;
}
"""

static var _floor_shader: Shader


static func floor_material() -> ShaderMaterial:
	if _floor_shader == null:
		_floor_shader = Shader.new()
		_floor_shader.code = FLOOR_SHADER
	var m := ShaderMaterial.new()
	m.shader = _floor_shader
	return m


## 벽·발판 재질. kind: "wall" / "climb" / "platform"
static func block_material(size: Vector3, kind: String) -> ShaderMaterial:
	var tint := TINT_WALL
	match kind:
		"climb":
			tint = TINT_CLIMB
		"platform":
			tint = TINT_PLATFORM
	var m := InkWash.body_material(size, tint, randf() * 100.0)
	m.set_shader_parameter("outline_width", 0.12)          # 큰 블록이라 먹선을 조금 굵게
	m.set_shader_parameter("stripes", 1.0 if kind == "climb" else 0.0)
	m.set_shader_parameter("holes", 0.35)                  # 큰 면에 하얀 얼룩이 생기지 않게 고르게 칠한다
	m.set_shader_parameter("paper", Vector3(0.36, 0.34, 0.29))
	return m


## 종이빛 하늘 + 거리 안개
static func environment() -> Environment:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.72, 0.7, 0.64)
	sky_mat.sky_horizon_color = Color(0.86, 0.83, 0.76)
	sky_mat.ground_horizon_color = Color(0.86, 0.83, 0.76)
	sky_mat.ground_bottom_color = Color(0.7, 0.68, 0.62)
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# 블룸: 밝기 1을 넘는 발광(탄, 적의 눈, 패링 부채꼴)만 번지게 (GDD 9.1)
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 1.0
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# 거리 안개: 먼 곳이 종이색으로 번지며 흐려진다 (산수화의 여백)
	env.fog_enabled = true
	env.fog_light_color = Color(0.84, 0.81, 0.74)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	return env


## 외벽 밖의 먼 산: 겹겹이 선 봉우리. 가까운 줄은 짙고, 먼 줄은 안개에 묻힌다
static func add_mountains(parent: Node3D, arena_half: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2718
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.24, 0.27)
	mat.roughness = 1.0
	for ring in 2:
		var dist := arena_half + 45.0 + ring * 70.0
		var count := 14 + ring * 6
		for i in count:
			var a := TAU * (i + rng.randf_range(-0.3, 0.3)) / count
			var peak := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = rng.randf_range(0.0, 2.0)
			c.bottom_radius = rng.randf_range(22.0, 40.0) * (1.0 + ring * 0.5)
			c.height = rng.randf_range(30.0, 70.0) * (1.0 + ring * 0.6)
			c.radial_segments = rng.randi_range(5, 7)
			c.rings = 1
			peak.mesh = c
			peak.material_override = mat
			peak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			peak.position = Vector3(cos(a) * dist, c.height * 0.5 - 4.0, sin(a) * dist)
			peak.rotation.y = rng.randf() * TAU
			parent.add_child(peak)
