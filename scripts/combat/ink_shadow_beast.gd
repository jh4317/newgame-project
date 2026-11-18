extends Node3D
## 그림자 속 먹 괴물: 적 발밑에 사는 먹 짐승. 그 적에게 먹이 쌓일수록(ink_stack.gd) 깨어나 드러난다.
## 순전히 연출이고 게임 판정은 없다. 수묵화처럼 그린다 — 먹(검정)·섬광(흰색) 이펙트 규칙을 따른다.
##
##   먹 조금   : 적 발밑에 먹이 번진다 (젖은 먹이 종이에 스미듯 가장자리가 갈라지고, 테두리에 먹이 고인다)
##   먹 ~35%   : 붓 획 같은 촉수가 웅덩이 밖으로 휘감기며 뻗고, 웅덩이에서 먹 연기가 피어오른다
##   먹 ~60%   : 웅덩이에서 흰 눈 두 개가 떠오른다 (먹 폭발 기준치: 지금 베라)
##   먹 ~85%+  : 뿔 달린 머리가 적의 등 뒤로 솟아오르고, 붓으로 그린 갈기가 바람에 날린다
##
## 반응: 기준치를 넘는 순간과 먹이 터지는 순간 턱을 크게 벌린다(포효). 먹이 빠지면 다시 가라앉는다.
## InkStack이 매 프레임 follow()로 적의 발 위치와 먹 비율을 넘겨준다.

const TENDRILS := 7
const TENDRIL_STEPS := 14
const MANE := 6
const MANE_STEPS := 10

## 먹 비율이 이 값 아래면 괴물이 잠든다
@export var wake_ratio := 0.03
## 머리가 항상 카메라 쪽을 보며 몸(적) 뒤에서 비스듬히 고개를 내민다 → 눈·이빨이 늘 보인다
@export var face_camera := true

# ---------------------------------------------------------------- 셰이더

const NOISE := """
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
"""

## 먹 웅덩이: 젖은 먹이 번지는 수묵 번짐. 가장자리는 섬유결로 갈라지고, 테두리에 먹이 고여 더 짙다
const POOL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float seed = 0.0;
uniform float amount = 1.0;
%s
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float t = TIME * 0.12 + seed;
	// 울퉁불퉁 번지는 가장자리
	float edge = 0.6 + 0.2 * fbm(vec2(ang * 1.7 + seed, t)) + 0.05 * sin(ang * 6.0 + t * 2.0);
	float d = r / edge;
	// 바깥으로 스며 나가는 섬유결 (종이에 먹이 번질 때의 잔털)
	float fibers = fbm(vec2(ang * 30.0 + seed * 7.0, r * 2.5 - t * 0.5));
	float core = 1.0 - smoothstep(0.82, 1.0, d);
	float bleed = (1.0 - smoothstep(0.92, 1.45, d)) * smoothstep(0.45, 0.75, fibers) * 0.75;
	float a = max(core, bleed);
	// 농담: 안쪽은 묽게 일렁이고, 테두리에 먹이 고여 짙다
	float wash = fbm(p * 2.6 + vec2(t, -t * 0.7) + seed);
	float rim = smoothstep(0.7, 0.95, d) * (1.0 - smoothstep(0.98, 1.1, d));
	// 색은 선형 공간 값이다 (0.01이면 화면에서 꽤 어둡지만 0.07이면 회색으로 보인다)
	float shade = mix(0.006, 0.001, smoothstep(0.3, 0.75, wash)) * (1.0 - rim * 0.8);
	ALBEDO = vec3(shade * 0.92, shade * 0.94, shade);
	ALPHA = a * clamp(amount * 4.0, 0.0, 1.0) * mix(1.0, 0.9, wash * (1.0 - rim) * smoothstep(0.4, 0.9, d));
}
"""

## 붓 획 띠: UV.x = 폭 방향(0~1), UV.y = 길이 방향(0 뿌리 ~ 1 끝). 끝으로 갈수록 마른 붓처럼 갈라진다
const BRUSH_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float alpha_mul = 1.0;
%s
void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float s = UV2.x;  // 획마다 다른 씨앗
	// 붓털 결: 길이 방향으로 길게 늘어진 줄무늬
	float bristle = fbm(vec2(UV.x * 16.0 + s * 11.0, UV.y * 2.2 + s));
	float a = 1.0 - smoothstep(0.7, 1.0, across);
	// 끝으로 갈수록 마른 붓: 털 사이가 비며 갈라진다
	float dry = smoothstep(0.25 + 0.55 * UV.y, 0.4 + 0.55 * UV.y, bristle + 0.25 * (1.0 - UV.y));
	a *= mix(1.0, dry, smoothstep(0.15, 0.8, UV.y));
	a *= 1.0 - smoothstep(0.88, 1.0, UV.y);
	// 농담: 뿌리는 진하고, 끝과 가장자리는 살짝 묽다
	float shade = 0.0015 + 0.012 * UV.y * bristle + 0.004 * across;
	ALBEDO = vec3(shade * 0.92, shade * 0.94, shade);
	ALPHA = a * alpha_mul;
}
"""

var _ink := 0.0          # 부드럽게 따라가는 먹 비율 0~1
var _t := 0.0            # 깨어난 정도 0~1
var _time := 0.0
var _flinch := 0.0
var _roar := 0.0
var _seed := 0.0
## 붓 획(촉수·갈기) 다시 그리기 주기: 화면 밖이거나 멀면 드물게 (적이 30마리일 때 프레임 유지)
var _stroke_timer := 0.0
const STROKE_NEAR_DIST := 30.0   # 이보다 가까우면 매 프레임
const STROKE_FAR_INTERVAL := 1.0 / 20.0
const STROKE_OFFSCREEN_INTERVAL := 0.5

var _pool: MeshInstance3D
var _pool_mat: ShaderMaterial
var _tendril_mesh: ImmediateMesh
var _brush_mat: ShaderMaterial
var _tendril_angle: Array[float] = []
var _tendril_len: Array[float] = []
var _wisps: CPUParticles3D
var _motes: CPUParticles3D

var _head: Node3D
var _jaw: Node3D
var _mane_mesh: ImmediateMesh
var _mane_node: MeshInstance3D
var _eyes: Array[Node3D] = []
var _halos: Array[MeshInstance3D] = []
var _halo_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _body_mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	_seed = randf() * 100.0
	for i in TENDRILS:
		_tendril_angle.append(i * TAU / TENDRILS + randf_range(-0.25, 0.25))
		_tendril_len.append(randf_range(0.7, 1.25))
	_build()


func flinch() -> void:
	_flinch = 1.0


func roar() -> void:
	_roar = 1.0


## 매 프레임: 발 위치(바닥), 크기, 먹 비율, 바라보는 방향(yaw)
func follow(delta: float, ground: Vector3, size_scale: float, ink_ratio: float, yaw: float) -> void:
	_time += delta
	_ink = lerpf(_ink, clampf(ink_ratio, 0.0, 1.0), 1.0 - exp(-4.0 * delta))
	_t = clampf((_ink - wake_ratio) / (1.0 - wake_ratio), 0.0, 1.0)
	_flinch = maxf(0.0, _flinch - delta * 2.5)
	_roar = maxf(0.0, _roar - delta * 1.6)
	visible = _t > 0.01
	_wisps.emitting = visible and _t > 0.25
	_motes.emitting = visible and _t > 0.5
	if not visible:
		return
	global_position = ground + Vector3.UP * 0.03
	var cam := get_viewport().get_camera_3d()
	if face_camera and cam:
		# 로컬 -Z(머리가 보는 쪽)가 카메라를 향하게: 머리는 +Z(카메라 반대편 = 몸 뒤)에 있다
		var f := -cam.global_basis.z
		f.y = 0.0
		if f.length() > 0.01:
			f = f.normalized()
			yaw = atan2(f.x, f.z)
	rotation = Vector3(0.0, yaw, 0.0)
	scale = Vector3.ONE * size_scale

	var wake := _t * (1.0 - 0.6 * _flinch)

	# ---- 먹 웅덩이
	var pool_r := lerpf(0.6, 1.55, wake) * (1.0 + 0.04 * sin(_time * 2.2))
	_pool.scale = Vector3.ONE * pool_r / 0.72
	_pool_mat.set_shader_parameter("amount", wake)

	# ---- 먹 연기: 깰수록 짙고 높이
	_wisps.speed_scale = lerpf(0.6, 1.3, wake)
	_wisps.emission_sphere_radius = pool_r * 0.7 * size_scale

	# ---- 붓 획을 이번 프레임에 다시 그릴까: 가까우면 매 프레임, 멀면 초당 20번, 화면 밖이면 초당 2번
	_stroke_timer -= delta
	var redraw := true
	if cam:
		var interval := 0.0
		if not cam.is_position_in_frustum(global_position + Vector3.UP):
			interval = STROKE_OFFSCREEN_INTERVAL
		elif cam.global_position.distance_to(global_position) > STROKE_NEAR_DIST:
			interval = STROKE_FAR_INTERVAL
		redraw = _stroke_timer <= 0.0
		if redraw:
			_stroke_timer = interval

	# ---- 촉수: 바닥을 휘감는 붓 획
	var reach := smoothstep(0.15, 1.0, wake)
	if redraw:
		_tendril_mesh.clear_surfaces()
		if reach > 0.02:
			_tendril_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _brush_mat)
			for i in TENDRILS:
				_ground_stroke(i, pool_r, reach)
			_tendril_mesh.surface_end()

	# ---- 머리: 두 단계로 솟는다 (먹 ~60%에서 눈만, ~85%부터 전체)
	var rise := lerpf(-1.0, -0.15, smoothstep(0.35, 0.6, wake)) + lerpf(0.0, 0.7, smoothstep(0.65, 1.0, wake)) - 0.5 * _flinch
	var breathe := sin(_time * 1.8) * 0.05 * wake
	_head.position = Vector3(1.0 + sin(_time * 0.8) * 0.08, rise + breathe, 0.7)
	_head.rotation = Vector3(-0.12 + 0.1 * sin(_time * 1.1) - 0.4 * _roar, 0.35 + 0.08 * sin(_time * 0.6), 0.06 * sin(_time * 0.9))
	_head.visible = rise > -0.95
	var jaw_open := 0.1 + 0.08 * maxf(0.0, sin(_time * 1.5)) + 0.7 * _roar - 0.08 * _flinch
	_jaw.rotation.x = clampf(jaw_open, 0.0, 0.9)
	# 눈: 숨 쉬듯 맥동하고, 포효하면 크게 번쩍, 맞으면 가늘게
	var glow := 0.8 + 0.2 * sin(_time * 3.0) + 1.2 * _roar
	_eye_mat.emission_energy_multiplier = 5.0 * glow
	_halo_mat.albedo_color.a = clampf(0.14 * glow * smoothstep(-0.5, -0.1, rise), 0.0, 1.0)
	for eye in _eyes:
		eye.scale = Vector3(1.0, maxf(0.15, 1.0 - 0.85 * _flinch + 0.5 * _roar), 1.0)
	for h in _halos:
		h.scale = Vector3.ONE * (0.9 + 0.5 * _roar + 0.08 * sin(_time * 3.0))

	# ---- 갈기: 머리 뒤로 날리는 붓 획 (카메라를 향하는 띠)
	if not redraw:
		return
	_mane_mesh.clear_surfaces()
	var mane_amt := smoothstep(0.55, 1.0, wake)
	if _head.visible and mane_amt > 0.02 and cam:
		var cam_local := _mane_node.global_transform.affine_inverse() * cam.global_position
		_mane_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _brush_mat)
		for i in MANE:
			_mane_stroke(i, mane_amt, cam_local)
		_mane_mesh.surface_end()


# ---------------------------------------------------------------- 붓 획 만들기

## 바닥 촉수 하나: 웅덩이 안쪽에서 시작해 바깥으로 휘감기며 뻗는다. 끝은 소용돌이처럼 말린다
func _ground_stroke(i: int, pool_r: float, reach: float) -> void:
	var a0: float = _tendril_angle[i]
	var length: float = (0.4 + 1.6 * reach) * _tendril_len[i]
	var start_r := pool_r * 0.55
	var pts := PackedVector3Array()
	var widths := PackedFloat32Array()
	var phase := _time * (1.6 + 0.2 * i) + i * 1.9
	for k in TENDRIL_STEPS + 1:
		var s := float(k) / TENDRIL_STEPS
		var r := start_r + length * s
		var curl := sin(phase - s * 3.2) * 0.35 * s + s * s * 0.9 * sin(i * 2.7 + _time * 0.5)
		var ang := a0 + curl / maxf(r, 0.3)
		pts.append(Vector3(cos(ang) * r, 0.02 + 0.03 * s + 0.002 * i, sin(ang) * r))
		widths.append(0.44 * pow(1.0 - s, 0.7) * (0.8 + 0.4 * _tendril_len[i]) + 0.02)
	_ribbon(_tendril_mesh, pts, widths, Vector3.UP, float(i) * 3.7 + _seed, true)


## 갈기 한 가닥: 머리 뒤에서 뒤·위로 흘러 바람에 물결친다
func _mane_stroke(i: int, amt: float, cam_local: Vector3) -> void:
	var side := (float(i) / (MANE - 1)) * 2.0 - 1.0
	var length := (0.9 + 0.6 * (1.0 - absf(side))) * amt * 1.5
	var pts := PackedVector3Array()
	var widths := PackedFloat32Array()
	var phase := _time * 3.2 + i * 0.9
	for k in MANE_STEPS + 1:
		var s := float(k) / MANE_STEPS
		var wave := sin(phase - s * 4.0) * 0.18 * s
		pts.append(Vector3(side * (0.18 + 0.35 * s) + wave * 0.6, 0.2 + s * (0.12 + 0.08 * absf(side)) + wave * 0.4 + 0.45 * _roar * s, 0.2 + s * length))
		widths.append(0.2 * pow(1.0 - s, 0.8) + 0.015)
	_ribbon(_mane_mesh, pts, widths, Vector3.ZERO, float(i) * 5.3 + _seed + 40.0, false, cam_local)


## 점들을 따라 폭이 변하는 띠를 그린다. flat이면 normal(위) 기준으로 바닥에 눕히고,
## 아니면 cam_local 쪽을 보도록 세운다 (어느 각도에서도 붓 획이 보이게)
func _ribbon(im: ImmediateMesh, pts: PackedVector3Array, widths: PackedFloat32Array, normal: Vector3,
		stroke_seed: float, flat: bool, cam_local := Vector3.ZERO) -> void:
	var n := pts.size()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for k in n:
		var tangent := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var facing := normal if flat else (cam_local - pts[k]).normalized()
		var side := tangent.cross(facing)
		side = side.normalized() if side.length() > 0.001 else Vector3.RIGHT
		left.append(pts[k] - side * widths[k] * 0.5)
		right.append(pts[k] + side * widths[k] * 0.5)
	# 삼각형 두 개씩 바로 쓴다 (임시 배열을 만들지 않는다: 적이 많을 때 프레임 유지)
	var uv2 := Vector2(stroke_seed, 0.0)
	var inv := 1.0 / (n - 1)
	for k in n - 1:
		var v0 := k * inv
		var v1 := (k + 1) * inv
		_vtx(im, left[k], Vector2(0, v0), uv2)
		_vtx(im, right[k], Vector2(1, v0), uv2)
		_vtx(im, right[k + 1], Vector2(1, v1), uv2)
		_vtx(im, left[k], Vector2(0, v0), uv2)
		_vtx(im, right[k + 1], Vector2(1, v1), uv2)
		_vtx(im, left[k + 1], Vector2(0, v1), uv2)


func _vtx(im: ImmediateMesh, p: Vector3, uv: Vector2, uv2: Vector2) -> void:
	im.surface_set_uv(uv)
	im.surface_set_uv2(uv2)
	im.surface_add_vertex(p)


# ---------------------------------------------------------------- 조립

func _build() -> void:
	# 먹 웅덩이
	_pool = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2, 2)
	_pool.mesh = plane
	_pool_mat = _shader_mat(POOL_SHADER % NOISE)
	_pool_mat.set_shader_parameter("seed", _seed)
	_pool_mat.render_priority = -1
	_pool.material_override = _pool_mat
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pool)

	# 촉수 (매 프레임 다시 그린다)
	_brush_mat = _shader_mat(BRUSH_SHADER % NOISE)
	var tn := MeshInstance3D.new()
	_tendril_mesh = ImmediateMesh.new()
	tn.mesh = _tendril_mesh
	tn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tn)

	# 먹 연기: 웅덩이에서 느리게 피어올라 퍼지며 옅어진다
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	wm.vertex_color_use_as_albedo = true
	wm.vertex_color_is_srgb = true  # 파티클 색을 화면에 보이는 그대로(sRGB) 쓴다 → 먹이 회색으로 뜨지 않는다
	wm.albedo_texture = _soft_dot()
	wm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_wisps = _particles(Vector2(0.9, 0.9), wm, 14, 2.2, [Color(0.0, 0.0, 0.01, 0.0), Color(0.0, 0.0, 0.01, 0.45), Color(0.0, 0.0, 0.01, 0.0)], 0.25)
	_wisps.spread = 20.0
	_wisps.initial_velocity_min = 0.3
	_wisps.initial_velocity_max = 0.8
	_wisps.gravity = Vector3(0, 0.25, 0)
	_wisps.angle_min = -180.0
	_wisps.angle_max = 180.0
	_wisps.angular_velocity_min = -25.0
	_wisps.angular_velocity_max = 25.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.8))
	_wisps.scale_amount_curve = grow

	# 먹 티끌: 거꾸로 내리는 비처럼 작은 먹방울이 위로 떠오른다
	_motes = _particles(Vector2(0.08, 0.08), wm.duplicate(), 16, 1.6, [Color(0.02, 0.02, 0.03, 0.0), Color(0.02, 0.02, 0.03, 0.95), Color(0.02, 0.02, 0.03, 0.0)], 0.15)
	_motes.emission_sphere_radius = 0.9
	_motes.spread = 15.0
	_motes.initial_velocity_min = 0.6
	_motes.initial_velocity_max = 1.6
	_motes.gravity = Vector3(0, 0.6, 0)
	_motes.scale_amount_min = 0.6
	_motes.scale_amount_max = 1.6

	_build_head()


func _particles(size: Vector2, mat: Material, amount: int, life: float, colors: Array, peak: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = size
	p.mesh = q
	p.material_override = mat
	var g := Gradient.new()
	g.set_color(0, colors[0])
	g.add_point(peak, colors[1])
	g.set_color(g.get_point_count() - 1, colors[2])
	p.color_ramp = g
	p.amount = amount
	p.lifetime = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.0
	p.direction = Vector3.UP
	p.emitting = false
	p.local_coords = false
	add_child(p)
	return p


## 뿔 달린 늑대·용 머리. 앞(-Z)을 본다. 윤이 나는 먹 + 흰 눈·이빨
func _build_head() -> void:
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.035, 0.035, 0.05)
	_body_mat.metallic = 0.75
	_body_mat.roughness = 0.2
	_body_mat.rim_enabled = true
	_body_mat.rim = 1.0
	_body_mat.rim_tint = 0.15
	_body_mat.clearcoat_enabled = true
	_body_mat.clearcoat = 0.6
	_body_mat.clearcoat_roughness = 0.15
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color(1, 1, 1)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(1, 1, 1)
	_eye_mat.emission_energy_multiplier = 5.0
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.albedo_texture = _soft_dot()
	_halo_mat.albedo_color = Color(1, 1, 1, 0.35)
	_halo_mat.no_depth_test = true
	_halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	_head = Node3D.new()
	add_child(_head)
	var hs := Node3D.new()
	hs.scale = Vector3.ONE * 1.45
	_head.add_child(hs)

	# 두개골: 뒤가 넓고 주둥이로 갈수록 좁아지는 사각뿔대들
	_add(hs, _taper(Vector2(0.46, 0.36), Vector2(0.36, 0.3), 0.42), _body_mat, Vector3(0, 0.0, 0.2))
	_add(hs, _taper(Vector2(0.34, 0.24), Vector2(0.15, 0.12), 0.5), _body_mat, Vector3(0, -0.02, -0.2), Vector3(0.12, 0, 0))
	# 눈두덩: 날카롭게 앞으로 튀어나온 이마 능선
	for side in [-1.0, 1.0]:
		_add(hs, _taper(Vector2(0.14, 0.06), Vector2(0.02, 0.02), 0.32), _body_mat, Vector3(0.13 * side, 0.15, -0.12), Vector3(-0.15, 0.25 * side, 0))
	# 위턱 이빨 (바깥 송곳니가 길다)
	for k in 6:
		var x := -0.11 + k * 0.044
		var tooth_len := 0.12 if k == 0 or k == 5 else 0.07
		_add(hs, _spike(0.035, tooth_len), _eye_mat, Vector3(x, -0.1 - tooth_len * 0.4, -0.34 + absf(k - 2.5) * 0.035), Vector3(PI, 0, 0))
	# 아래턱
	_jaw = Node3D.new()
	_jaw.position = Vector3(0, -0.12, 0.05)
	hs.add_child(_jaw)
	_add(_jaw, _taper(Vector2(0.3, 0.07), Vector2(0.12, 0.05), 0.55), _body_mat, Vector3(0, -0.02, -0.02))
	for k in 5:
		_add(_jaw, _spike(0.03, 0.08), _eye_mat, Vector3(-0.08 + k * 0.04, 0.03, -0.38 + absf(k - 2) * 0.04))
	# 뿔: 세 마디로 뒤로 길게 휘어진다
	for side in [-1.0, 1.0]:
		var base := Node3D.new()
		base.position = Vector3(0.17 * side, 0.17, 0.15)
		base.rotation = Vector3(-0.5, 0.0, -0.35 * side)
		hs.add_child(base)
		var parent := base
		var w := 0.1
		for seg in 3:
			_add(parent, _taper(Vector2(w, w), Vector2(w * 0.7, w * 0.7), 0.26), _body_mat, Vector3.ZERO, Vector3(-PI * 0.5, 0, 0))
			var nxt := Node3D.new()
			nxt.position = Vector3(0, 0.26, 0)
			nxt.rotation = Vector3(-0.45, 0.0, 0.05 * side)
			parent.add_child(nxt)
			parent = nxt
			w *= 0.7
		_add(parent, _spike(w, 0.22), _body_mat, Vector3(0, 0.1, 0))
	# 눈: 위로 째진 흰 눈 + 부드러운 빛무리
	for side in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(0.12 * side, 0.1, -0.17)
		eye.rotation = Vector3(-0.3, 0.2 * side, -0.4 * side)
		hs.add_child(eye)
		_add(eye, _taper(Vector2(0.06, 0.03), Vector2(0.015, 0.01), 0.22), _eye_mat, Vector3(-0.05 * side, 0, 0.05), Vector3(0, -PI * 0.5 * side, 0))
		_eyes.append(eye)
		var halo := MeshInstance3D.new()
		var hq := QuadMesh.new()
		hq.size = Vector2(0.3, 0.3)
		halo.mesh = hq
		halo.material_override = _halo_mat
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		halo.position = Vector3(0.12 * side, 0.1, -0.22)
		hs.add_child(halo)
		_halos.append(halo)

	# 갈기 (매 프레임 다시 그린다)
	_mane_node = MeshInstance3D.new()
	_mane_mesh = ImmediateMesh.new()
	_mane_node.mesh = _mane_mesh
	_mane_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hs.add_child(_mane_node)


func _add(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


func _shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## 가운데가 하얗고 가장자리로 갈수록 투명한 둥근 점 (빛무리·연기용)
static var _dot_tex: Texture2D
static func _soft_dot() -> Texture2D:
	if _dot_tex:
		return _dot_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.4, Color(1, 1, 1, 0.45))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_dot_tex = t
	return t


func _spike(w: float, h: float) -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = w * 0.5
	c.height = h
	c.radial_segments = 4
	c.rings = 1
	return c


## 사각뿔대: 뒤(z=0)에서 back 크기 → 앞(z=-length)에서 front 크기. 면마다 각진 법선
func _taper(back: Vector2, front: Vector2, length: float) -> ArrayMesh:
	var b := [Vector3(-back.x, -back.y, 0) * 0.5, Vector3(back.x, -back.y, 0) * 0.5,
		Vector3(back.x, back.y, 0) * 0.5, Vector3(-back.x, back.y, 0) * 0.5]
	var f := [Vector3(-front.x * 0.5, -front.y * 0.5, -length), Vector3(front.x * 0.5, -front.y * 0.5, -length),
		Vector3(front.x * 0.5, front.y * 0.5, -length), Vector3(-front.x * 0.5, front.y * 0.5, -length)]
	var center := Vector3(0, 0, -length * 0.5)
	var quads := [[b[0], b[1], b[2], b[3]], [f[0], f[1], f[2], f[3]], [b[0], b[1], f[1], f[0]],
		[b[1], b[2], f[2], f[1]], [b[2], b[3], f[3], f[2]], [b[3], b[0], f[0], f[3]]]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for qd in quads:
		var qc: Vector3 = (qd[0] + qd[1] + qd[2] + qd[3]) * 0.25
		for tri in [[qd[0], qd[1], qd[2]], [qd[0], qd[2], qd[3]]]:
			var a: Vector3 = tri[0]
			var c1: Vector3 = tri[1]
			var c2: Vector3 = tri[2]
			var nn := (c1 - a).cross(c2 - a)
			if nn.length() < 1e-8:
				continue
			nn = nn.normalized()
			if nn.dot(qc - center) < 0.0:
				nn = -nn
			else:
				var tmp := c1  # Godot 앞면은 바깥에서 볼 때 시계 방향
				c1 = c2
				c2 = tmp
			verts.append_array([a, c1, c2])
			norms.append_array([nn, nn, nn])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
