extends Node3D
## 적중·처치 이펙트 (GDD 8.3: 로우폴리가 아닌 화려한 흑백 + 블룸, 붉은색은 쓰지 않음)
## 만화풍의 과장된 타격 연출을 목표로 한다: 붓터치 베기 자국(흰 심 + 검은 외곽선),
## 바닥에 튀는 먹물, 화면 연출(화면 베기·줌 블러)은 combat_fx/screen_slash가 맡는다.
## 플레이어 공격 종류마다 모양이 다르다:
##   근접 베기   : 굵은 붓터치 자국 1줄 + 불꽃 + 충격파 고리
##   3타 마무리  : 큰 X자 붓터치 + 큰 충격파 + 섬광 + 불꽃 많이 + 검은 연기
##   검기        : 얇고 긴 붓터치 + 불꽃 조금
##   반사탄      : 섬광 구 + 방사형 가시 + 불꽃
##   처치        : 로우폴리 파편 + 큰 섬광 + 검은 연기 + 바닥 충격파 + 바닥 먹물
## 적중마다 '먹 관통'이 함께 나온다: 먹 창이 적의 반대편으로 뚫고 나가며 먹방울을 뿜고 뒤쪽 바닥에 먹을 뿌린다.
## 이펙트 노드는 스스로 사라진다. 히트스톱 중에는 함께 멈춘다(time_scale 영향).
## 대미지 숫자와 먹 회복 숫자는 기본으로 끈다 (show_damage_numbers, show_ink_numbers). 패링·먹 폭발 같은 문구는 그대로 뜬다.

const WHITE := Color(1, 1, 1)
const INK := Color(0.02, 0.02, 0.02)

## 공격 피해 숫자(먹 폭발 추가 피해 포함)를 띄울지
@export var show_damage_numbers := false
## 먹(체력)을 되찾을 때 머리 위에 "+N 먹"을 띄울지
@export var show_ink_numbers := false


func _ready() -> void:
	add_to_group("hit_fx")


# ---------------------------------------------------------------- 공격 종류별

func melee_hit(pos: Vector3, dir: Vector3, damage := 40.0) -> void:
	_brush(pos, dir, 3.6, 0.55, 0.2, 30.0)
	_sparks(pos, dir, 16, 9.0, 18.0, 0.32, 50.0)
	_ring(pos, 2.0, 0.2)
	_ink_pierce(pos, dir, 3.2, 0.42, 18)
	damage_number(pos, damage, false)


func finisher_hit(pos: Vector3, dir: Vector3, damage := 60.0) -> void:
	_brush(pos, dir, 5.5, 0.8, 0.3, 40.0)
	_brush(pos, dir, 5.5, 0.8, 0.3, -40.0)
	_sparks(pos, dir, 32, 11.0, 24.0, 0.45, 70.0)
	_ring(pos, 4.0, 0.3)
	_flash(pos, 2.0, 0.14)
	_smoke(pos, 8, 0.7)
	# X자 붓터치에 맞춰 두 갈래로 크게 뚫고 나간다
	_ink_pierce(pos, dir.rotated(Vector3.UP, deg_to_rad(14.0)), 4.6, 0.6, 22)
	_ink_pierce(pos, dir.rotated(Vector3.UP, deg_to_rad(-14.0)), 4.6, 0.6, 22, false)
	damage_number(pos, damage, true)


func wave_hit(pos: Vector3, dir: Vector3, damage := 20.0) -> void:
	_brush(pos, dir, 4.0, 0.22, 0.15, 90.0)  # 진행 방향에 수직인 얇은 자국
	_sparks(pos, dir, 8, 7.0, 13.0, 0.25, 35.0)
	_ink_pierce(pos, dir, 3.6, 0.22, 10, false)  # 가늘고 길게
	damage_number(pos, damage, false)


func reflect_hit(pos: Vector3, dir: Vector3, damage := 40.0) -> void:
	_flash(pos, 2.0, 0.16)
	for i in 8:
		_brush(pos, dir, 2.0, 0.16, 0.16, i * 45.0, 1.0)  # 방사형 가시
	_sparks(pos, dir, 20, 9.0, 20.0, 0.36, 180.0)
	_ink_pierce(pos, dir, 3.4, 0.4, 16)
	damage_number(pos, damage, true)


func enemy_killed(pos: Vector3, size: float, elite: bool) -> void:
	var center := pos + Vector3.UP * size * 0.5
	_shards(center, 22 if elite else 14, size)
	_flash(center, 3.2 if elite else 2.4, 0.2)
	_smoke(center, 12 if elite else 8, 1.0)
	_ring(pos + Vector3.UP * 0.1, 6.0 if elite else 4.5, 0.4)
	_ink_splat(pos, 9 if elite else 6, 1.6 if elite else 1.2)


## 먹 폭발: 쌓인 먹이 한꺼번에 터진다. 검은 먹방울이 사방으로 튀고, 바닥에 큰 먹 자국,
## 흰 섬광과 고리, "먹 폭발" 문구 (추가 피해 숫자는 show_damage_numbers일 때만)
func ink_burst(pos: Vector3, base_pos: Vector3, bonus: float) -> void:
	_ink_droplets(pos, 40, 13.0)
	_ink_splat(base_pos, 10, 1.8)
	_flash(pos, 2.6, 0.16)
	_ring(base_pos + Vector3.UP * 0.1, 5.5, 0.35)
	_brush(pos, Vector3(1, 0, 0), 6.0, 0.9, 0.3, 0.0)
	_pop_label(pos + Vector3.UP * 1.6, "먹 폭발", 110, 0.8)
	if show_damage_numbers:
		_pop_label(pos + Vector3(0.0, 0.6, 0.0), "+" + str(int(round(bonus))), 150, 0.8)


## 먹 끌어당김: 중심으로 검은 고리가 오므라들고, 끌려오는 적마다 먹 사슬이 이어졌다 끊긴다
func ink_pull(center: Vector3, from_points: Array) -> void:
	_implode(center + Vector3.UP * 1.2, 9.0, 0.28)
	_flash(center + Vector3.UP * 1.2, 2.2, 0.18)
	for p in from_points:
		_tether(center + Vector3.UP * 1.2, (p as Vector3) + Vector3.UP * 1.2, 0.4)
	_ink_droplets(center + Vector3.UP * 1.2, 24, 9.0)
	_pop_label(center + Vector3.UP * 3.4, "먹 끌어당김", 100, 0.9)


## 회복 표시 (플레이어 머리 위)
func heal_text(pos: Vector3, amount: float) -> void:
	if not show_ink_numbers:
		return
	_pop_label(pos + Vector3(0.6, 2.0, 0.0), "+%d 먹" % int(round(amount)), 80, 0.8)


## 패링 성공 문구 (플레이어 머리 위)
func parry_text(pos: Vector3) -> void:
	_pop_label(pos + Vector3.UP * 2.4, "PARRY", 120, 0.7)


## 크게 튀어나왔다가 떠오르며 사라지는 대미지 숫자 (흰 글자 + 두꺼운 검은 외곽선)
func damage_number(pos: Vector3, damage: float, big: bool) -> void:
	if not show_damage_numbers:
		return
	var jitter := Vector3(randf_range(-0.6, 0.6), randf_range(0.3, 0.9), randf_range(-0.3, 0.3))
	_pop_label(pos + jitter, str(int(round(damage))), 130 if big else 84, 0.6)


# ---------------------------------------------------------------- 일필휘지 종베기

const SPLIT_SHEET_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float reveal = 0.0;   // 0~1: 플레이어 쪽에서 벽 쪽으로 갈라져 나간다
uniform float fade = 1.0;
uniform float length_m = 10.0;
uniform float ramp_m = 14.0;  // 이 거리(m)에 걸쳐 낮게 시작해 최대 높이까지 치솟는다
uniform float intensity = 1.0;
void fragment() {
	float along = UV.x;          // 0 = 시작(플레이어), 1 = 끝(벽)
	float up = 1.0 - UV.y;       // 0 = 바닥, 1 = 꼭대기
	float shown = 1.0 - smoothstep(reveal - 0.01, reveal + 0.01, along);
	// 바닥에서 가장 밝고 위로 갈수록 옅어지는 빛의 막. 가르는 앞머리는 더 밝게 번쩍인다
	float body = exp(-up * 2.6) * 1.6 + exp(-up * 0.7) * 0.25;
	float head = exp(-abs(along - reveal) * length_m * 0.6) * (1.0 - step(1.0, reveal));
	// 세로 결: 칼바람처럼 위로 솟는 가는 줄무늬
	float streak = 0.75 + 0.25 * sin(along * length_m * 6.0 + TIME * 30.0);
	float ends = smoothstep(0.0, 0.02, along) * (1.0 - smoothstep(0.97, 1.0, along));
	// 칼끝 가까이는 낮고, 멀어질수록 높이 치솟는 쐐기 모양.
	// 숄더뷰에서 막을 옆면으로 볼 때 가까운 부분이 캐릭터를 덮는 기둥이 되지 않고, 먼 곳은 소실점으로 모인다
	float hmax = mix(0.1, 1.0, smoothstep(0.0, clamp(ramp_m / max(length_m, 0.01), 0.01, 1.0), along));
	float top = 1.0 - smoothstep(hmax - 0.06, hmax, up);
	// 쐐기 윗변을 따라 밝은 칼날 선
	float rim_line = exp(-abs(up - hmax) * 40.0) * 0.8;
	float a = shown * fade * ends * intensity * ((body * streak + head * 2.5 * exp(-up * 1.2)) * top + rim_line);
	ALBEDO = vec3(1.0) * (1.0 + a * 2.0);
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

var _split_shader: Shader

## 일필휘지 획 긋기를 '종베기'로: 하늘에서 내려친 칼이 바닥을 따라 벽까지 맵을 가른다.
##   - 빛의 막: 바닥에서 하늘로 치솟는 흰 빛의 벽이 플레이어 쪽에서 벽 쪽으로 순식간에 갈라져 나간다
##   - 갈라진 바닥: 획을 따라 흰 빛을 내는 틈이 남았다가 식는다 (먹 획은 ink_trail이 그린다)
##   - 솟구치는 파편: 갈라진 자리에서 먹방울과 흰 불티가 위로 터져 오른다
## level 2(최대 차지)는 더 높고 굵고 오래 간다.
## 빛의 막과 파편은 칼끝(플레이어 앞 NEAR_SKIP m)부터 시작한다. 숄더뷰처럼 카메라가 가르는 방향 바로 뒤에 있으면
## 막을 옆면으로 보게 되는데, 플레이어 자리부터 막이 서 있으면 캐릭터를 덮는 흰 기둥이 되기 때문이다.
const NEAR_SKIP := 2.5

func map_split(from: Vector3, to: Vector3, level: int) -> void:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length := d.length()
	if length < 0.5:
		return
	var dir := d / length
	var big := level >= 2
	var height := 16.0 if big else 10.0
	# 카메라가 가르는 방향을 따라 보고 있으면(숄더뷰) 막을 거의 옆면으로 보게 된다.
	# 높은 막은 화면을 세로로 덮는 빛기둥이 되므로, 그럴수록 낮고 옅게 깔아 바닥을 따라 지평선까지 달려가는 칼빛으로 보이게 한다
	var intensity := 1.0
	var cam := get_viewport().get_camera_3d()
	if cam:
		var fwd := -cam.global_basis.z
		# 내려다보는 카메라(탑뷰, 55도)에서는 높은 막이 잘 보이므로 줄이지 않는다. 수평에 가까울수록(숄더뷰)만 줄인다
		var level_cam := 1.0 - smoothstep(0.35, 0.6, -fwd.y)
		var cf := Vector3(fwd.x, 0.0, fwd.z)
		if cf.length() > 0.01:
			var along_view := smoothstep(0.55, 0.9, absf(cf.normalized().dot(dir))) * level_cam
			height = lerpf(height, 2.5, along_view)
			intensity = lerpf(1.0, 0.6, along_view)
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(from.x, from.y + 0.02, from.z)
	root.look_at(root.global_position + dir, Vector3.UP)   # 로컬 -Z = 가르는 방향

	# 빛의 막 (가르는 선을 따라 세운 판): 칼끝에서 벽까지
	var skip := minf(NEAR_SKIP, length * 0.5)
	var sheet_len := length - skip
	if _split_shader == null:
		_split_shader = Shader.new()
		_split_shader.code = SPLIT_SHEET_SHADER
	var sheet := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(sheet_len, height)
	sheet.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = _split_shader
	mat.set_shader_parameter("length_m", sheet_len)
	mat.set_shader_parameter("intensity", intensity)
	sheet.material_override = mat
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheet.rotation.y = PI * 0.5            # 판의 +X(UV.x 증가)가 로컬 -Z(가르는 방향)로
	sheet.position = Vector3(0.0, height * 0.5, -skip - sheet_len * 0.5)
	root.add_child(sheet)

	# 갈라진 바닥: 획 가운데의 흰 틈
	var crack := MeshInstance3D.new()
	var cq := QuadMesh.new()
	cq.size = Vector2(0.28 if big else 0.18, length)
	crack.mesh = cq
	var cmat := _glow_mat(8.0)
	cmat.no_depth_test = true
	cmat.render_priority = 3
	crack.material_override = cmat
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crack.rotation.x = -PI * 0.5           # 바닥에 눕힌다 (판의 세로가 가르는 방향)
	crack.position = Vector3(0.0, 0.04, 0.0)
	crack.scale = Vector3(1.0, 0.0001, 1.0)
	root.add_child(crack)

	# 갈라져 나가는 속도: 실제 시간 기준이라 히트스톱 중에도 끝까지 가른다
	var cut_time := 0.12 + length * 0.0012
	var tw := root.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_method(func(v: float):
		mat.set_shader_parameter("reveal", v)
		crack.scale = Vector3(1.0, maxf(v, 0.0001), 1.0)
		crack.position.z = -length * 0.5 * v, 0.0, 1.0, cut_time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.55 if big else 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(cmat, "albedo_color:a", 0.0, 1.4 if big else 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)

	# 솟구치는 먹방울 + 흰 불티 (선을 따라 고르게)
	var drops := clampi(int(length * (2.2 if big else 1.4)), 20, 160)
	for white in [false, true]:
		var p := CPUParticles3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.35, 0.05) if white else Vector3(0.12, 0.12, 0.12)
		p.mesh = bm
		if white:
			p.material_override = _glow_mat(6.0)
			p.particle_flag_align_y = true
		else:
			var im := StandardMaterial3D.new()
			im.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			im.albedo_color = INK
			p.material_override = im
		p.one_shot = true
		p.explosiveness = 0.85
		p.amount = drops if not white else drops / 2
		p.lifetime = 0.9
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(0.2, 0.05, sheet_len * 0.5)
		p.direction = Vector3.UP
		p.spread = 22.0
		p.initial_velocity_min = 10.0 if white else 6.0
		p.initial_velocity_max = (14.0 if big else 10.0) + (8.0 if white else 0.0)
		p.gravity = Vector3(0, -26, 0)
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.6
		p.scale_amount_curve = _shrink_curve(0.5)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(p)
		p.position = Vector3(0.0, 0.1, -skip - sheet_len * 0.5)
		p.emitting = true


# ---------------------------------------------------------------- 조각들

var _spike_mesh: ArrayMesh

## 먹 관통: 적의 몸을 꿰뚫고 반대편으로 먹 창이 튀어나온다.
##   - 검은 먹 창(가운데 흰 심)이 순식간에 뻗었다가 가늘어지며 사라진다. 깊이 테스트 없이 적 위에 그려 '뚫고 지나간' 느낌
##   - 뚫고 나간 쪽으로 먹방울이 원뿔 모양으로 뿜어진다
##   - splat이면 적 뒤쪽 바닥에 진행 방향으로 길게 먹이 뿌려진다
## dir: 공격 방향(플레이어 → 적), length: 창 길이(m), width: 창 굵기, drops: 먹방울 수
func _ink_pierce(pos: Vector3, dir: Vector3, length: float, width: float, drops: int, splat := true) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	if _spike_mesh == null:
		_spike_mesh = _make_spike()

	# 먹 창: 적 몸 안쪽(조금 앞)에서 시작해 뒤로 뚫고 나간다
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos - d * 0.5
	root.look_at(root.global_position + d, Vector3.UP)
	root.rotate_object_local(Vector3.RIGHT, deg_to_rad(randf_range(-6.0, 4.0)))  # 살짝 위아래로 흩어지게
	for layer in 2:
		var ink := layer == 0
		var m := MeshInstance3D.new()
		m.mesh = _spike_mesh
		var mat: StandardMaterial3D
		if ink:
			mat = StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = INK
		else:
			mat = _glow_mat(6.0)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = true
		mat.render_priority = 1 if ink else 2
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 흰 심은 먹보다 가늘고 짧다
		m.scale = Vector3(width, width, length) if ink else Vector3(width * 0.32, width * 0.32, length * 0.8)
		root.add_child(m)
	var life := 0.22 + 0.04 * length
	root.scale = Vector3(1.0, 1.0, 0.05)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3(1.15, 1.15, 1.0), 0.06).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector3(0.0, 0.0, 1.15), life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(root, "global_position", root.global_position + d * 0.6, life)
	tw.tween_callback(root.queue_free)

	# 뚫고 나간 쪽으로 뿜어지는 먹방울
	var exit := pos + d * 0.6
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = INK
	p.material_override = dmat
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = drops
	p.lifetime = 0.55
	p.direction = (d + Vector3.UP * 0.25).normalized()
	p.spread = 16.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 8.0 + length * 4.0
	p.gravity = Vector3(0, -26, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.8 * width / 0.4 + 0.4
	p.scale_amount_curve = _shrink_curve(0.5)
	_emit_once(p, exit, 0.55)

	# 적 뒤쪽 바닥에 진행 방향으로 길게 뿌려진 먹
	if splat:
		var q := PhysicsRayQueryParameters3D.create(exit + Vector3.UP * 0.5, exit + Vector3.DOWN * 6.0)
		var ex: Array[RID] = []
		for n in get_tree().get_nodes_in_group("enemy") + get_tree().get_nodes_in_group("player"):
			if n is CollisionObject3D:
				ex.append((n as CollisionObject3D).get_rid())
		q.exclude = ex
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var ground: Vector3 = hit["position"]
			var blobs := 3 + int(length)
			for i in blobs:
				var t := float(i + 1) / blobs
				var at := ground + d * (0.4 + t * length * 0.7) + d.cross(Vector3.UP) * randf_range(-0.25, 0.25) * t
				_ink_streak(at, d, (1.0 - t * 0.6) * width * 1.4, 0.15 * i)


## 바닥 먹 줄기 하나: 진행 방향으로 길쭉한 납작한 먹. delay만큼 늦게 번져 뿌려지는 순서가 보인다
func _ink_streak(pos: Vector3, d: Vector3, size: float, delay_frac: float) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 8
	sm.rings = 4
	m.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(INK.r, INK.g, INK.b, 0.9)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = pos + Vector3.UP * 0.025
	m.rotation.y = atan2(d.x, d.z)
	var final_scale := Vector3(size * randf_range(0.7, 1.0), 0.01, size * randf_range(1.8, 2.8))
	m.scale = final_scale * 0.1
	var tw := m.create_tween()
	tw.tween_interval(0.04 * delay_frac * 10.0)
	tw.tween_property(m, "scale", final_scale, 0.07).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.tween_callback(m.queue_free)


## 먹 창 메시: -Z로 길이 1, 굵기 1. 뒤(+Z)는 짧고 뭉툭하게, 앞(-Z)은 길고 뾰족한 마름모 단면의 창
func _make_spike() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var back := Vector3(0, 0, 0.08)
	var tip := Vector3(0, 0, -1.0)
	var ring := [Vector3(0.5, 0, -0.12), Vector3(0, 0.5, -0.12), Vector3(-0.5, 0, -0.12), Vector3(0, -0.5, -0.12)]
	for i in 4:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		st.add_vertex(back)
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(a)
		st.add_vertex(tip)
		st.add_vertex(b)
	return st.commit()

## 붓터치 베기 자국: 가운데가 두껍고 끝이 뾰족한 초승달. 흰 심 + 검은 외곽선 두 겹.
## 확 그어졌다가 얇아지며 사라진다. 깊이 테스트 없이 항상 위에 그린다.
## angle_deg: 공격 방향 기준 회전, offset: 중심에서 바깥쪽으로 밀어내기(가시용)
func _brush(pos: Vector3, dir: Vector3, length: float, thickness: float, life: float,
		angle_deg: float, offset := 0.0) -> void:
	var root := Node3D.new()
	add_child(root)
	var yaw := atan2(-dir.x, -dir.z) + deg_to_rad(angle_deg)
	root.global_position = pos
	root.rotation = Vector3(deg_to_rad(-30.0), yaw, 0.0)  # 기울여 탑뷰·숄더뷰 모두에서 보이게
	if offset > 0.0:
		root.global_position += root.global_transform.basis.x * offset

	var arc := deg_to_rad(70.0)
	var radius := length / (2.0 * sin(arc * 0.5))
	var outline := MeshInstance3D.new()
	outline.mesh = _make_crescent(radius, arc * 1.06, thickness * 1.9)
	var out_mat := StandardMaterial3D.new()
	out_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	out_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	out_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	out_mat.no_depth_test = true
	out_mat.render_priority = 1
	out_mat.albedo_color = INK
	outline.material_override = out_mat
	outline.position = Vector3(0, 0, -thickness * 0.35)
	root.add_child(outline)

	var core := MeshInstance3D.new()
	core.mesh = _make_crescent(radius, arc, thickness)
	var core_mat := _glow_mat(7.0)
	core_mat.no_depth_test = true
	core_mat.render_priority = 2
	core.material_override = core_mat
	root.add_child(core)
	for m in [outline, core]:
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# 세로로 확 그어진 뒤(0.25) 두께가 얇아지며 사라진다
	root.scale = Vector3(0.1, 1.0, 1.4)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3(1.15, 1.0, 1.0), life * 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector3(1.25, 1.0, 0.05), life * 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(out_mat, "albedo_color:a", 0.0, life * 0.75)
	tw.tween_callback(root.queue_free)


## 바닥 먹물: 납작한 검은 덩어리들이 확 번졌다가 잠시 남은 뒤 옅어진다
func _ink_splat(pos: Vector3, count: int, spread: float) -> void:
	for i in count:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 8
		sm.rings = 4
		m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(INK.r, INK.g, INK.b, 0.92)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		var r := randf_range(0.35, 1.0) * spread * (1.4 if i == 0 else 1.0)
		var off := Vector3.ZERO if i == 0 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(0.8, 2.6) * spread
		m.global_position = pos + off + Vector3.UP * (0.02 + i * 0.002)
		var final_scale := Vector3(r * randf_range(0.8, 1.3), 0.01, r * randf_range(0.6, 1.0))
		m.rotation.y = randf() * TAU
		m.scale = final_scale * 0.2
		var tw := m.create_tween()
		tw.tween_property(m, "scale", final_scale, 0.08).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_interval(1.2)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
		tw.tween_callback(m.queue_free)


## 튀어나오는 글자: 크게 → 원래 크기, 떠오르며 마지막에 사라짐
func _pop_label(pos: Vector3, text: String, size: int, life: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = int(size * 0.22)
	l.modulate = WHITE
	l.outline_modulate = INK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 3
	l.outline_render_priority = 2
	l.pixel_size = 0.01
	add_child(l)
	l.global_position = pos
	l.scale = Vector3.ONE * 1.8
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "global_position", pos + Vector3.UP * 1.2, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, life * 0.35).set_delay(life * 0.65)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, life * 0.35).set_delay(life * 0.65)
	tw.tween_callback(l.queue_free)


## -Z 쪽으로 볼록한 초승달 리본 (가운데 두껍고 끝으로 갈수록 뾰족). 중심을 원점 근처로 맞춘다.
func _make_crescent(radius: float, angle: float, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 20
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	var sag := radius - cos(angle * 0.5) * radius  # 초승달이 원점을 가로지르도록 보정
	for i in steps + 1:
		var u := float(i) / steps
		var th := -angle * 0.5 + angle * u
		var t := thickness * pow(sin(u * PI), 0.8)
		outer.append(Vector3(sin(th) * radius, 0.0, radius - cos(th) * radius - sag * 0.5))
		var r_in := radius - t
		inner.append(Vector3(sin(th) * r_in, 0.0, radius - cos(th) * r_in - sag * 0.5))
	for i in steps:
		st.add_vertex(outer[i])
		st.add_vertex(outer[i + 1])
		st.add_vertex(inner[i])
		st.add_vertex(inner[i])
		st.add_vertex(outer[i + 1])
		st.add_vertex(inner[i + 1])
	return st.commit()


## 충격파 고리: 바닥과 나란한 얇은 고리가 퍼진다
func _ring(pos: Vector3, radius: float, life: float) -> void:
	var m := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 4
	m.mesh = tm
	var mat := _glow_mat(4.0)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = pos
	m.scale = Vector3.ONE * 0.2
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3(radius, 1.0, radius), life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(m.queue_free)


## 섬광: 아주 밝은 구가 부풀었다 사라진다 (블룸으로 크게 번짐)
func _flash(pos: Vector3, radius: float, life: float) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 6
	m.mesh = sm
	var mat := _glow_mat(10.0)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = pos
	m.scale = Vector3.ONE * 0.3
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3.ONE * radius, life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(m.queue_free)


## 불꽃: 속도 방향으로 늘어난 흰 조각들이 튀었다 줄어든다
func _sparks(pos: Vector3, dir: Vector3, count: int, speed: float, max_speed: float,
		life: float, spread_deg: float) -> void:
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.45, 0.05)
	p.mesh = bm
	p.material_override = _glow_mat(5.0)
	p.particle_flag_align_y = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = life
	p.direction = Vector3(dir.x, 0.25, dir.z).normalized() if dir.length() > 0.1 else Vector3.UP
	p.spread = spread_deg
	p.initial_velocity_min = speed
	p.initial_velocity_max = max_speed
	p.gravity = Vector3(0, -18, 0)
	p.scale_amount_curve = _shrink_curve()
	_emit_once(p, pos, life)


## 검은 연기: 흰 이펙트와 대비되는 검은 덩어리가 천천히 퍼지며 옅어진다
func _smoke(pos: Vector3, count: int, life: float) -> void:
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	p.material_override = mat
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.02, 0.02, 0.85))
	g.set_color(1, Color(0.02, 0.02, 0.02, 0.0))
	p.color_ramp = g
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = count
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 90.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, 1.5, 0)
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.8
	_emit_once(p, pos, life)


## 오므라드는 고리: 넓은 검은 고리가 중심으로 확 빨려 든다 (끌어당김)
func _implode(pos: Vector3, radius: float, life: float) -> void:
	for i in 2:
		var m := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.88
		tm.outer_radius = 1.0
		tm.rings = 32
		tm.ring_segments = 4
		m.mesh = tm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(INK.r, INK.g, INK.b, 0.0)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		m.global_position = pos
		var r := radius * (1.0 - 0.3 * i)
		m.scale = Vector3(r, 1.0, r)
		var tw := m.create_tween()
		tw.tween_interval(0.05 * i)
		tw.tween_property(mat, "albedo_color:a", 0.9, 0.04)
		tw.tween_property(m, "scale", Vector3(0.3, 1.0, 0.3), life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		tw.tween_callback(m.queue_free)


## 먹 사슬: 두 점을 잇는 굵은 검은 줄(가운데 흰 심)이 잠깐 이어졌다 가늘어지며 끊긴다
func _tether(a: Vector3, b: Vector3, life: float) -> void:
	var length := a.distance_to(b)
	if length < 0.1:
		return
	var root := Node3D.new()
	add_child(root)
	root.global_position = (a + b) * 0.5
	root.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	for layer in 2:
		var ink := layer == 0
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.22, length) if ink else Vector3(0.06, 0.06, length)
		m.mesh = bm
		var mat := _glow_mat(4.0) if not ink else StandardMaterial3D.new()
		if ink:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = INK
		mat.no_depth_test = true
		mat.render_priority = 1 if ink else 2
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(m)
	var tw := root.create_tween()
	tw.tween_interval(life * 0.4)
	tw.tween_property(root, "scale", Vector3(0.05, 0.05, 1.0), life * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)


## 먹방울: 검은 방울이 사방으로 튀었다가 떨어지며 작아진다
func _ink_droplets(pos: Vector3, count: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = INK
	p.material_override = mat
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = 0.7
	p.direction = Vector3.UP
	p.spread = 100.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -24, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 2.0
	p.scale_amount_curve = _shrink_curve(0.5)
	_emit_once(p, pos, 0.7)


## 처치 파편: 회색·흰색 로우폴리 조각이 사방으로 튀고 떨어진다
func _shards(pos: Vector3, count: int, size: float) -> void:
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.28 * size / 2.2
	p.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.85, 0.88)
	mat.emission_enabled = true
	mat.emission = WHITE
	mat.emission_energy_multiplier = 1.2
	p.material_override = mat
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 13.0
	p.gravity = Vector3(0, -28, 0)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	p.scale_amount_curve = _shrink_curve(0.6)
	_emit_once(p, pos, 0.9)


func _emit_once(p: CPUParticles3D, pos: Vector3, life: float) -> void:
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.2).timeout.connect(p.queue_free)


func _glow_mat(energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = WHITE
	mat.emission_enabled = true
	mat.emission = WHITE
	mat.emission_energy_multiplier = energy
	return mat


## 1 → hold까지 유지 → 0 으로 줄어드는 크기 곡선
func _shrink_curve(hold := 0.2) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(hold, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	return c
