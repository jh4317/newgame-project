extends Node3D
## 첫 무기: 검기 검.
## 공격 버튼(좌클릭/RT)을 누르면 조준 방향으로 검을 휘두른다. 한 번 휘두를 때마다:
##   1) 근접 베기: 앞쪽 부채꼴 안의 적에게 큰 대미지. 근접으로 처치하면 체력 회복 (GDD 5.1)
##   2) 검기: 초승달 파동이 앞으로 날아가 원거리 적을 벤다 (관통, 대미지는 근접보다 낮음)
## 3타 콤보: 세 번째는 마무리 베기로 범위·대미지·검기가 커진다. 누르고 있으면 계속 휘두른다.
## 대미지 단위: 20 = 적 체력 1칸 (적의 탄 1발과 같음)
##
## 플레이어의 _visual 아래에 붙어서 플레이어가 바라보는 방향(-Z)을 따라 돈다.

signal swung(combo_index: int)
## kind: "melee" / "finisher"(3타 근접) / "wave" / "wave_big"(3타 검기)
signal hit_enemy(enemy: Node, killed: bool, melee: bool, kind: String)
## 먹 폭발: 먹이 기준치 이상 쌓인 적을 근접으로 베어 추가 피해를 줬다
signal ink_burst(enemy: Node, bonus: float, killed: bool)

const SwordWave := preload("res://scripts/combat/sword_wave.gd")

@export var swing_interval := 0.28
@export var combo_window := 0.6
@export var melee_range := 2.8
@export var melee_angle_deg := 120.0
@export var melee_damage := 40.0        # 체력 2칸
@export var finisher_damage := 60.0     # 체력 3칸
@export var wave_damage := 20.0         # 체력 1칸 (마무리는 1.5배)
@export var wave_speed := 35.0
@export var wave_range := 25.0
@export var aim_assist_deg := 15.0      # 이 각도 안의 적(높이 차 포함)을 검기가 향한다
@export var melee_kill_heal := 20.0

@export_group("Ink")  ## 공격마다 적에게 쌓이는 먹 (ink_stack.gd)
@export var ink_melee := 25.0
@export var ink_finisher := 35.0
@export var ink_wave := 20.0
@export var ink_wave_big := 30.0

var player: CharacterBody3D
var combo := 0
var _cooldown := 0.0
var _since_swing := 10.0
var _pivot: Node3D
var _blade_mat: StandardMaterial3D
var _blade_glow := 0.0
var _trail_core_mat: StandardMaterial3D
var _trail_ink_mat: StandardMaterial3D
var _swing_dir := 1.0

const SWING_TIME := 0.09   # 칼날이 휘둘러지는 시간 (궤적도 이 시간 동안 그려진다)
const TRAIL_FADE := 0.2    # 궤적이 사라지는 시간
const TRAIL_INNER := 0.45  # 궤적 안쪽 반지름 (손 근처)


func _ready() -> void:
	# 검: 오른쪽 어깨 높이의 회전축 + 앞으로 뻗은 칼날
	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, 1.15, 0.0)
	add_child(_pivot)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.04, 1.3)
	blade.mesh = bm
	blade.position = Vector3(0.45, 0.0, -0.75)
	_blade_mat = StandardMaterial3D.new()
	_blade_mat.albedo_color = Color(0.85, 0.87, 0.9)
	_blade_mat.metallic = 0.8
	_blade_mat.roughness = 0.3
	_blade_mat.emission_enabled = true
	_blade_mat.emission = Color(1, 1, 1)
	_blade_mat.emission_energy_multiplier = 0.0  # 휘두를 때만 번쩍인다
	blade.material_override = _blade_mat
	_pivot.add_child(blade)
	_pivot.rotation.y = deg_to_rad(-35.0)  # 평소엔 살짝 비스듬히 든다

	# 궤적 잔상용 재질 (모든 휘두르기가 공유)
	_trail_core_mat = StandardMaterial3D.new()
	_trail_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_core_mat.vertex_color_use_as_albedo = true
	_trail_core_mat.emission_enabled = true
	_trail_core_mat.emission = Color(1, 1, 1)
	_trail_core_mat.emission_energy_multiplier = 3.5
	_trail_core_mat.render_priority = 2
	_trail_ink_mat = StandardMaterial3D.new()
	_trail_ink_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_ink_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_ink_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_ink_mat.vertex_color_use_as_albedo = true
	_trail_ink_mat.render_priority = 1


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_cooldown -= delta
	_since_swing += delta
	if _since_swing > combo_window:
		combo = 0
	if Input.is_action_pressed("attack") and _cooldown <= 0.0:
		_swing()
	_blade_glow = move_toward(_blade_glow, 0.0, 30.0 * delta)
	_blade_mat.emission_energy_multiplier = _blade_glow


func _swing() -> void:
	combo = combo % 3 + 1
	var finisher := combo == 3
	_cooldown = swing_interval * (1.4 if finisher else 1.0)
	_since_swing = 0.0

	# 칼날 휘두르기: 콤보마다 방향을 번갈아
	_swing_dir = -_swing_dir
	var from := deg_to_rad(75.0) * _swing_dir
	_pivot.rotation.y = from
	var tw := _pivot.create_tween()
	tw.tween_property(_pivot, "rotation:y", -from, SWING_TIME)
	tw.tween_property(_pivot, "rotation:y", deg_to_rad(-35.0), 0.18).set_delay(0.06)

	var reach_mul := 1.25 if finisher else 1.0
	_blade_glow = 8.0 if finisher else 5.0
	# 궤적 잔상: 실제 근접 범위만큼 큰 붓터치 호. 마무리는 바깥에 한 줄 더
	_spawn_trail(from, -from, TRAIL_INNER, melee_range * reach_mul, finisher)
	if finisher:
		_spawn_trail(from * 1.1, -from * 1.1, melee_range * reach_mul + 0.25, melee_range * reach_mul + 0.6, true)
	_tip_glints(-from, melee_range * reach_mul, finisher)

	var hit := _melee_hits(finisher, reach_mul)
	_launch_wave(finisher, hit)
	swung.emit(combo)


func _melee_hits(finisher: bool, reach_mul: float) -> Array:
	var hit := []
	var origin := player.global_position + Vector3.UP
	var aim := _aim()
	var half := deg_to_rad(melee_angle_deg) * 0.5
	var dmg := finisher_damage if finisher else melee_damage
	for e in get_tree().get_nodes_in_group("enemy"):
		var to: Vector3 = e.call("aim_point") - origin
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() > melee_range * reach_mul + 0.8 or absf(to.y) > 2.5:
			continue  # 0.8 = 적 몸통 반폭 여유
		if flat.length() > 0.5 and aim.angle_to(flat.normalized()) > half:
			continue
		hit.append(e)
		# 먹이 기준치 이상이면 먼저 전부 터뜨려 추가 피해, 그 뒤 이번 베기의 먹을 새로 묻힌다
		var ink: Node = e.get("ink")
		var bonus := 0.0
		if ink and bool(ink.call("is_ready")):
			bonus = ink.call("consume")
		var killed: bool = e.call("take_damage", dmg + bonus)
		if killed:
			player.set("health", minf(float(player.get("max_health")), float(player.get("health")) + melee_kill_heal))
		elif ink:
			ink.call("add", ink_finisher if finisher else ink_melee)
		if bonus > 0.0:
			ink_burst.emit(e, bonus, killed)
		hit_enemy.emit(e, killed, true, "finisher" if finisher else "melee")
	return hit


func _launch_wave(finisher: bool, already_hit: Array) -> void:
	var origin := player.global_position + Vector3.UP * 1.0 + _aim() * 0.8
	var w := SwordWave.new()
	w.setup(origin, _assisted_direction(origin), wave_speed, wave_range,
		wave_damage * (1.5 if finisher else 1.0), finisher, player, already_hit)
	var kind := "wave_big" if finisher else "wave"
	var ink_amount := ink_wave_big if finisher else ink_wave
	w.hit_enemy.connect(_on_wave_hit.bind(kind, ink_amount))
	player.get_parent().add_child(w)


func _on_wave_hit(e: Node, killed: bool, kind: String, ink_amount: float) -> void:
	var ink: Node = e.get("ink")
	if ink and not killed:
		ink.call("add", ink_amount)  # 검기는 먹을 묻히기만 한다 (터뜨리는 건 근접)
	hit_enemy.emit(e, killed, false, kind)


func _aim() -> Vector3:
	var f: Vector3 = player.get("facing")
	return Vector3(f.x, 0.0, f.z).normalized()


## 조준 방향 근처(보정 각도 안)에 적이 있으면 가장 가까운 적의 몸통을 향한다 (높이 차 포함)
func _assisted_direction(from: Vector3) -> Vector3:
	var aim := _aim()
	var best := aim
	var best_dist := wave_range
	for e in get_tree().get_nodes_in_group("enemy"):
		var to: Vector3 = e.call("aim_point") - from
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() < 0.5 or rad_to_deg(aim.angle_to(flat.normalized())) > aim_assist_deg:
			continue
		if to.length() < best_dist:
			best_dist = to.length()
			best = to.normalized()
	return best


# ---------------------------------------------------------------- 휘두르기 잔상

## 칼날이 지나간 자리를 따라 자라나는 붓터치 궤적 (흰 심 + 검은 외곽선).
## 앞쪽(칼날이 있는 쪽)이 진하고 꼬리로 갈수록 옅고 가늘어진다.
## 칼날과 같은 시간(SWING_TIME) 동안 그려지고, 그 뒤 TRAIL_FADE 동안 사라진다.
func _spawn_trail(from_angle: float, to_angle: float, r_in: float, r_out: float, thin: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.position = Vector3(0.0, 1.15, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var width := (0.35 if thin else 1.0)
	var tw := mi.create_tween()
	tw.tween_method(_draw_trail.bind(mi, from_angle, to_angle, r_in, r_out, width, 1.0), 0.0, 1.0, SWING_TIME)
	tw.tween_method(_draw_trail_fade.bind(mi, from_angle, to_angle, r_in, r_out, width), 1.0, 0.0, TRAIL_FADE)
	tw.tween_callback(mi.queue_free)


func _draw_trail_fade(fade: float, mi: MeshInstance3D, from_angle: float, to_angle: float,
		r_in: float, r_out: float, width: float) -> void:
	_draw_trail(1.0, mi, from_angle, to_angle, r_in, r_out, width, fade)


func _draw_trail(p: float, mi: MeshInstance3D, from_angle: float, to_angle: float,
		r_in: float, r_out: float, width: float, fade: float) -> void:
	if not is_instance_valid(mi):
		return
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	var cur := lerpf(from_angle, to_angle, p)
	if absf(cur - from_angle) < 0.01:
		return
	var steps := 18
	# 외곽선(검정)은 살짝 더 넓게 먼저, 그 위에 흰 심
	for layer in 2:
		var ink := layer == 0
		var pad := 0.12 if ink else 0.0
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_ink_mat if ink else _trail_core_mat)
		for i in steps + 1:
			var u := float(i) / steps                 # 0 = 꼬리, 1 = 칼날 쪽
			var a := lerpf(from_angle, cur, u)
			var d := Vector3(-sin(a), 0.0, -cos(a))
			var band := (r_out - r_in) * width * (0.25 + 0.75 * pow(u, 0.7))  # 꼬리로 갈수록 가늘게
			var outer := r_out + pad
			var inner := maxf(0.0, r_out - band - pad)
			var alpha := fade * pow(u, 1.4)
			var c := Color(0.02, 0.02, 0.02, alpha * 0.85) if ink else Color(1, 1, 1, alpha)
			var y := -0.01 if ink else 0.0
			im.surface_set_color(c)
			im.surface_add_vertex(d * inner + Vector3(0, y, 0))
			im.surface_set_color(c)
			im.surface_add_vertex(d * outer + Vector3(0, y, 0))
		im.surface_end()


## 칼끝이 멈추는 자리에서 흰 불꽃이 튄다
func _tip_glints(end_angle: float, radius: float, big: bool) -> void:
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.35, 0.04)
	p.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = Color(1, 1, 1)
	m.emission_energy_multiplier = 5.0
	p.material_override = m
	p.particle_flag_align_y = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 14 if big else 7
	p.lifetime = 0.25
	var d := Vector3(-sin(end_angle), 0.0, -cos(end_angle))
	var tangent := Vector3.UP.cross(d) * signf(end_angle)  # 칼이 움직이던 방향
	p.direction = (tangent + Vector3.UP * 0.3).normalized()
	p.spread = 35.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector3(0, -14, 0)
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = c
	add_child(p)
	p.position = Vector3(0.0, 1.15, 0.0) + d * radius
	p.emitting = true
	get_tree().create_timer(0.5).timeout.connect(p.queue_free)
