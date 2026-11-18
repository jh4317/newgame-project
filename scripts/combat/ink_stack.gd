extends Node3D
## 먹 수치: 플레이어의 공격이 적에게 먹을 쌓는다 (주인공 = 먹을 다루는 검사).
## - 공격 종류마다 먹이 쌓이고, 한동안 공격받지 않으면 서서히 마른다
## - 기준치(threshold) 이상일 때 근접 공격을 맞히면 먹을 전부 터뜨려 추가 피해 (먹 폭발)
## - 표시: 머리 위 먹방울 5칸, 쌓일수록 몸이 먹빛으로 물들고 먹물이 뚝뚝 떨어진다.
##         기준치를 넘으면 발밑에 흰 고리가 맥동해 "지금 베라"고 알려 준다.
## - 잔향: 먹이 묻을 때마다 적의 검은 실루엣이 메아리처럼 몇 겹 퍼지고, 주변의 먹방울이
##         몸으로 빨려 들어가며, 새로 찬 먹방울 칸이 톡 튄다. 기준치를 넘는 순간은 흰 잔향이 더해진다.
## - 그림자 괴물: 먹이 쌓일수록 발밑 먹 웅덩이에서 촉수·눈·뿔 달린 머리가 차례로 드러난다 (ink_shadow_beast.gd)
## 적 스크립트가 add_child 전에 body_size(와 body_height)를 알려 준다.

signal changed(ink: float)

@export var max_ink := 100.0
@export var threshold := 60.0          # 이 이상에서 근접 공격 시 먹 폭발
@export var decay_delay := 3.0         # 마지막으로 먹이 묻은 뒤 이 시간이 지나면
@export var decay_rate := 20.0         # 초당 이만큼 마른다
@export var burst_min_damage := 40.0   # 기준치에서 터뜨릴 때 추가 피해 (적 체력 2칸)
@export var burst_max_damage := 80.0   # 가득(max_ink)일 때 추가 피해 (하급 100 → 체력 4칸)

const PIP_SIZE := 20.0  ## 먹방울 1칸 = 먹 20. 칸 수는 max_ink에 따라 정해진다 (하급 5칸, 중급 8칸)
const INK := Color(0.02, 0.02, 0.02)
const ShadowBeast := preload("res://scripts/combat/ink_shadow_beast.gd")

var ink := 0.0
var body_height := 2.2
var body_size := Vector3(1.2, 2.2, 1.2)
var _filled_prev := 0
var _since_add := 99.0
var _pips: Array[MeshInstance3D] = []
var _pip_full_mat: StandardMaterial3D
var _pip_empty_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _drips: CPUParticles3D
var _aura: CPUParticles3D    ## 먹이 쌓일수록 몸 주변에서 피어오르는 검은 기운
var _embers: CPUParticles3D  ## 기준치 이상에서 검은 기운 사이로 흩날리는 흰 불티
var _t := 0.0
var _beast: Node3D


func _ready() -> void:
	_build_visuals()
	_refresh()


func ratio() -> float:
	return ink / max_ink


func is_ready() -> bool:
	return ink >= threshold


func add(amount: float) -> void:
	var was_ready := is_ready()
	ink = minf(max_ink, ink + amount)
	_since_add = 0.0
	_refresh()
	_echo(amount, not was_ready and is_ready())
	changed.emit(ink)


## 먹을 전부 터뜨리고 추가 피해량을 돌려준다 (기준치 미만이면 0)
func consume() -> float:
	if not is_ready():
		return 0.0
	var t := (ink - threshold) / maxf(max_ink - threshold, 0.001)
	var bonus := lerpf(burst_min_damage, burst_max_damage, t)
	if _beast:
		_beast.call("roar")  # 터지는 순간 포효하고, 먹이 빠지며 가라앉는다
	ink = 0.0
	_refresh()
	changed.emit(ink)
	return bonus


func reset() -> void:
	ink = 0.0
	_since_add = 99.0
	_refresh()


func _process(delta: float) -> void:
	_since_add += delta
	if ink > 0.0 and _since_add > decay_delay:
		ink = maxf(0.0, ink - decay_rate * delta)
		_refresh()
	# 머리 위 먹방울은 적의 회전과 상관없이 화면 가로로 늘어선다
	var base := get_parent() as Node3D
	if base:
		for i in _pips.size():
			_pips[i].global_position = base.global_position + Vector3((i - (_pips.size() - 1) * 0.5) * 0.34, body_height + 0.75, 0.0)
		_ring.global_position = base.global_position + Vector3.UP * 0.05
		if _beast:
			# 적 몸 크기에 맞춘다 (플레이어 그림자 기준 반지름 0.5 → 적 반폭)
			var size := maxf(body_size.x, body_size.z) / 1.0
			_beast.call("follow", delta, base.global_position, size, ratio(), base.global_rotation.y)
	if is_ready():
		_t += delta
		var pulse := 0.5 + 0.5 * sin(_t * 14.0)
		_ring.scale = Vector3.ONE * lerpf(1.0, 1.25, pulse)
		_ring_mat.emission_energy_multiplier = lerpf(2.0, 6.0, pulse)


func _refresh() -> void:
	if _pips.is_empty():
		return
	var filled := int(floor(ink / PIP_SIZE + 0.001))
	for i in _pips.size():
		var full := i < filled
		_pips[i].material_override = _pip_full_mat if full else _pip_empty_mat
		_pips[i].visible = ink > 0.0
		if full and i >= _filled_prev:
			# 새로 찬 칸은 톡 튀어 오른다
			_pips[i].scale = Vector3.ONE * 1.9
			var tw := _pips[i].create_tween()
			tw.tween_property(_pips[i], "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		elif not full:
			_pips[i].scale = Vector3.ONE * 0.55
	_filled_prev = filled
	_ring.visible = is_ready()
	var r := clampf(ratio(), 0.0, 1.0)
	_drips.speed_scale = lerpf(0.35, 1.6, r)  # 많이 쌓일수록 자주 떨어진다
	_drips.emitting = ink > 0.0
	# 검은 기운: 먹이 쌓일수록 더 빠르고 크고 높게 피어오른다
	_aura.emitting = ink > 0.0
	_aura.speed_scale = lerpf(0.5, 1.5, r)
	_aura.scale_amount_min = lerpf(0.35, 1.1, r)
	_aura.scale_amount_max = lerpf(0.6, 1.9, r)
	_aura.initial_velocity_min = lerpf(0.8, 2.2, r)
	_aura.initial_velocity_max = lerpf(1.4, 3.6, r)
	_embers.emitting = is_ready()


# ---------------------------------------------------------------- 잔향

## 먹이 묻는 순간의 잔향: 검은 실루엣 메아리 + 퍼지는 먹 고리 + 빨려 드는 먹방울.
## 많이 묻을수록 겹이 많고 크다. crossed = 이번에 기준치를 넘었으면 흰 잔향을 더한다.
func _echo(amount: float, crossed: bool) -> void:
	var base := get_parent() as Node3D
	if base == null or not base.is_visible_in_tree():
		return
	var strength := clampf(amount / 30.0, 0.5, 2.0)   # 검기 20 ≈ 0.67, 패링 100 = 2
	var echoes := 2 if strength < 1.2 else 3
	for i in echoes:
		_ghost(base, INK, 0.5, 1.0 + 0.18 * (i + 1) * strength, 0.28 + 0.06 * i, 0.07 * i)
		_ring_echo(base, INK, 0.6, 1.2 + 0.5 * (i + 1) * strength, 0.3 + 0.05 * i, 0.07 * i)
	_absorb(base, int(6 + 8 * strength))
	if crossed:
		if _beast:
			_beast.call("roar")
		_ghost(base, Color(1, 1, 1), 0.8, 1.7, 0.35, 0.05, true)
		_ring_echo(base, Color(1, 1, 1), 0.9, 3.2, 0.4, 0.0, true)


## 적 몸통 모양의 실루엣이 커지며 옅어진다 (메아리)
func _ghost(base: Node3D, color: Color, alpha: float, to_scale: float, life: float, delay: float, glow := false) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = body_size
	m.mesh = bm
	var mat := _echo_mat(color, alpha, glow)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.top_level = true
	add_child(m)
	m.global_transform = base.global_transform
	m.global_position += Vector3.UP * body_size.y * 0.5
	m.visible = delay <= 0.0
	var tw := m.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(m.show)
	tw.tween_property(m, "scale", Vector3(to_scale, 1.0 + (to_scale - 1.0) * 0.5, to_scale), life) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(m.queue_free)


## 몸통 중간 높이에서 수평으로 퍼지는 고리
func _ring_echo(base: Node3D, color: Color, alpha: float, radius: float, life: float, delay: float, glow := false) -> void:
	var m := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 4
	m.mesh = tm
	var mat := _echo_mat(color, alpha, glow)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.top_level = true
	add_child(m)
	m.global_position = base.global_position + Vector3.UP * body_size.y * 0.5
	m.scale = Vector3.ONE * 0.6
	m.visible = delay <= 0.0
	var tw := m.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(m.show)
	tw.tween_property(m, "scale", Vector3(radius, 1.0, radius), life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(m.queue_free)


## 주변의 먹방울이 몸 쪽으로 빨려 들어간다
func _absorb(base: Node3D, count: int) -> void:
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = INK
	p.material_override = mat
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = count
	p.lifetime = 0.25
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = maxf(body_size.x, body_size.y * 0.6) * 1.2
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.radial_accel_min = -90.0
	p.radial_accel_max = -70.0
	p.gravity = Vector3.ZERO
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.4))
	c.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = c
	p.top_level = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # 먹 입자는 그림자를 드리우지 않는다 (그리기 호출 절약)
	add_child(p)
	p.global_position = base.global_position + Vector3.UP * body_size.y * 0.5
	p.emitting = true
	get_tree().create_timer(0.5).timeout.connect(p.queue_free)


func _echo_mat(color: Color, alpha: float, glow: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 4.0
	return mat


func _build_visuals() -> void:
	_beast = ShadowBeast.new()
	add_child(_beast)
	_pip_full_mat = StandardMaterial3D.new()
	_pip_full_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pip_full_mat.albedo_color = INK
	_pip_full_mat.no_depth_test = true
	_pip_full_mat.render_priority = 2
	_pip_empty_mat = StandardMaterial3D.new()
	_pip_empty_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pip_empty_mat.albedo_color = Color(1, 1, 1, 0.7)
	_pip_empty_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pip_empty_mat.no_depth_test = true
	_pip_empty_mat.render_priority = 2
	for i in maxi(1, roundi(max_ink / PIP_SIZE)):
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.14
		sm.height = 0.28
		sm.radial_segments = 8
		sm.rings = 4
		m.mesh = sm
		m.top_level = true
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_pips.append(m)

	# 기준치 이상: 발밑 흰 고리가 맥동
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.25
	tm.outer_radius = 1.4
	tm.rings = 24
	tm.ring_segments = 4
	_ring.mesh = tm
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(1, 1, 1)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(1, 1, 1)
	_ring.material_override = _ring_mat
	_ring.top_level = true
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	# 몸에서 떨어지는 먹물 방울 (쌓인 양에 비례)
	_drips = CPUParticles3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.06
	dm.height = 0.16
	dm.radial_segments = 6
	dm.rings = 3
	_drips.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = INK
	_drips.material_override = dmat
	_drips.amount = 12
	_drips.lifetime = 0.6
	_drips.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drips.emission_box_extents = Vector3(0.5, body_height * 0.4, 0.5)
	_drips.direction = Vector3.DOWN
	_drips.spread = 10.0
	_drips.initial_velocity_min = 0.5
	_drips.initial_velocity_max = 1.5
	_drips.gravity = Vector3(0, -12, 0)
	_drips.position = Vector3.UP * body_height * 0.5
	_drips.emitting = false
	_drips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # 먹 입자는 그림자를 드리우지 않는다 (그리기 호출 절약)
	add_child(_drips)

	# 검은 기운: 발밑 고리 모양으로 생겨나 소용돌이치며 위로 피어오르는 먹빛 불길
	var foot_r := maxf(body_size.x, body_size.z) * 0.75
	_aura = CPUParticles3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.14, 0.7, 0.14)
	_aura.mesh = am
	var amat := StandardMaterial3D.new()
	amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	amat.vertex_color_use_as_albedo = true
	amat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_aura.material_override = amat
	var ag := Gradient.new()
	ag.offsets = PackedFloat32Array([0.0, 0.15, 1.0])  # 확 짙어졌다가 천천히 흩어진다
	ag.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0.01, 0.01, 0.01, 0.85), Color(0.02, 0.02, 0.02, 0)])
	_aura.color_ramp = ag
	_aura.particle_flag_align_y = true
	_aura.amount = 28
	_aura.lifetime = 0.9
	_aura.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_aura.emission_ring_axis = Vector3.UP
	_aura.emission_ring_radius = foot_r
	_aura.emission_ring_inner_radius = foot_r * 0.6
	_aura.emission_ring_height = body_height * 0.5
	_aura.direction = Vector3.UP
	_aura.spread = 12.0
	_aura.gravity = Vector3(0, 1.5, 0)          # 연기처럼 위로 떠오름
	_aura.tangential_accel_min = 2.0            # 몸을 감싸며 소용돌이
	_aura.tangential_accel_max = 4.0
	_aura.radial_accel_min = -0.8               # 살짝 몸 쪽으로 모임
	_aura.radial_accel_max = -0.2
	var ac := Curve.new()
	ac.add_point(Vector2(0.0, 0.3))
	ac.add_point(Vector2(0.3, 1.0))
	ac.add_point(Vector2(1.0, 0.0))
	_aura.scale_amount_curve = ac
	_aura.position = Vector3.UP * body_height * 0.25
	_aura.emitting = false
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # 먹 입자는 그림자를 드리우지 않는다 (그리기 호출 절약)
	add_child(_aura)

	# 흰 불티: 기준치 이상일 때만, 검은 기운 사이로 드문드문 빛난다 (블룸)
	_embers = CPUParticles3D.new()
	var em := SphereMesh.new()
	em.radius = 0.05
	em.height = 0.1
	em.radial_segments = 4
	em.rings = 2
	_embers.mesh = em
	var emat := StandardMaterial3D.new()
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emat.emission_enabled = true
	emat.emission = Color(1, 1, 1)
	emat.emission_energy_multiplier = 5.0
	_embers.material_override = emat
	_embers.amount = 10
	_embers.lifetime = 0.8
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_embers.emission_ring_axis = Vector3.UP
	_embers.emission_ring_radius = foot_r
	_embers.emission_ring_inner_radius = foot_r * 0.5
	_embers.emission_ring_height = body_height * 0.6
	_embers.direction = Vector3.UP
	_embers.spread = 25.0
	_embers.initial_velocity_min = 1.5
	_embers.initial_velocity_max = 3.0
	_embers.gravity = Vector3(0, 1.0, 0)
	_embers.tangential_accel_min = 3.0
	_embers.tangential_accel_max = 5.0
	var ec := Curve.new()
	ec.add_point(Vector2(0.0, 1.0))
	ec.add_point(Vector2(1.0, 0.0))
	_embers.scale_amount_curve = ec
	_embers.position = Vector3.UP * body_height * 0.3
	_embers.emitting = false
	_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # 먹 입자는 그림자를 드리우지 않는다 (그리기 호출 절약)
	add_child(_embers)
