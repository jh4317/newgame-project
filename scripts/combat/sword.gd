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

## 붓 단계: 먹 스타일 등급(5.2)이 오를수록 검기가 강해진다. 먹 획 강화와 같은 등급 하나로 움직인다.
## 맞으면 등급이 깎이므로 붓도 함께 식는다. 아레나가 매 프레임 rank를 정한다 (-1 = 등급 없음)
## [최소 등급, 이름, 검기 크기, 사거리, 검기 피해, 검기 먹, 갈래 수]
const INK_STAGES := [
	[-1, "기본 붓",  1.0,  1.0, 1.0,  1.0,  1],   # 없음·점
	[1,  "젖은 붓",  1.15, 1.1, 1.1,  1.25, 1],   # 획·필
	[3,  "짙은 붓",  1.25, 1.2, 1.25, 1.5,  1],   # 묵·농묵
	[5,  "일필",     1.25, 1.2, 1.25, 1.5,  1],   # 일필휘지: 공격이 차지형 '획 긋기'로 바뀐다 (아래)
]
const SPLIT_ANGLE_DEG := 14.0
const RANK_CHARGE := 5
## 일필휘지에서는 사거리가 무한: 획 긋기와 검기가 벽에 닿을 때까지 뻗는다 (아레나 대각선 170 m보다 길게)
const INFINITE_RANGE := 400.0

## 일필휘지 차지 '획 긋기': 누르고 있다가 떼면 조준 방향으로 직선 먹 획을 한 번에 긋는다.
## 획에 닿은 적을 모두 베고(관통), 획은 바닥에 먹 자국으로 남아 먹 도형(ink_trail.gd)의 일부가 된다.
## 사거리는 무한: 단계와 상관없이 벽에 닿을 때까지 긋는다 (단계는 굵기·피해·먹만 다르다).
## 차지 중에도 이동할 수 있지만 패링은 못 한다. 짧게 누르면 보통 휘두르기.
## [최소 차지 시간, 획 길이, 획 굵기(배율), 피해, 묻는 먹(-1 = 가득)]
const CHARGE_LEVELS := [
	[0.25, 8.0,  1.0, 60.0,  40.0],
	[0.6,  16.0, 1.4, 120.0, -1.0],
]

## 차지 획을 그었다 (아레나 연출용). level: 1 또는 2
signal stroke_struck(from: Vector3, to: Vector3, level: int)
## 차지 단계가 올랐다 (1 또는 2)
signal charge_level_up(level: int)

var player: CharacterBody3D
var combo := 0
var rank := -1
var _cooldown := 0.0
var _since_swing := 10.0
var _pivot: Node3D
var _blade_mat: StandardMaterial3D
var _blade_glow := 0.0
var _trail_core_mat: StandardMaterial3D
var _trail_ink_mat: StandardMaterial3D
var _swing_dir := 1.0
var _charging := false
var _charge_t := 0.0
var _charge_level := 0

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
	if rank >= RANK_CHARGE:
		_update_charge(delta)
	else:
		_charging = false
		if Input.is_action_pressed("attack") and _cooldown <= 0.0:
			_swing()
	_blade_glow = move_toward(_blade_glow, 0.0, 30.0 * delta)
	if _charging:
		# 차지: 칼날에 먹이 모이며 점점 밝아지고, 단계가 오를 때 번쩍인다
		var pulse := 0.5 + 0.5 * sin(_charge_t * 30.0)
		_blade_glow = maxf(_blade_glow, 2.0 + 4.0 * _charge_level + 2.0 * pulse * _charge_level)
	_blade_mat.emission_energy_multiplier = _blade_glow


func is_charging() -> bool:
	return _charging


func _update_charge(delta: float) -> void:
	if Input.is_action_pressed("attack"):
		if not _charging:
			if _cooldown > 0.0:
				return
			_charging = true
			_charge_t = 0.0
			_charge_level = 0
		_charge_t += delta
		var lv := 0
		for i in CHARGE_LEVELS.size():
			if _charge_t >= float(CHARGE_LEVELS[i][0]):
				lv = i + 1
		if lv > _charge_level:
			_charge_level = lv
			_blade_glow = 12.0  # 단계가 오르는 순간 번쩍
			charge_level_up.emit(lv)
		return
	if not _charging:
		return
	_charging = false
	if _charge_level == 0:
		_swing()  # 짧게 눌렀다 떼면 보통 휘두르기
	else:
		_strike(_charge_level)
		_cooldown = swing_interval * 1.5


## 차지 획 긋기
func _strike(level: int) -> void:
	var cfg: Array = CHARGE_LEVELS[level - 1]
	var length: float = INFINITE_RANGE  # 일필휘지: 벽에 닿을 때까지 (cfg[1]은 예전 길이, 참고용)
	var width_mul: float = cfg[2]
	var dmg: float = cfg[3]
	var ink_amount: float = cfg[4]
	var aim := _aim()
	var feet := player.global_position
	# 벽에 막히면 거기까지만 긋는다 (가슴 높이 레이캐스트)
	var chest := feet + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(chest, chest + aim * length)
	var ex: Array[RID] = [player.get_rid()]
	for e in get_tree().get_nodes_in_group("enemy"):
		ex.append((e as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		length = maxf(chest.distance_to(hit["position"]) - 0.3, 1.0)
	var to := feet + aim * length

	# 획에 닿은 적을 모두 벤다
	var half := 0.38 * 1.7 * width_mul + 0.6  # 일필휘지 획 반폭(ink_trail TIERS 굵기 1.7) + 적 몸통 여유
	var a := Vector2(feet.x, feet.z)
	var b := Vector2(to.x, to.z)
	for e in get_tree().get_nodes_in_group("enemy"):
		var n := e as Node3D
		var p := Vector2(n.global_position.x, n.global_position.z)
		if absf(n.global_position.y - feet.y) > 2.5:
			continue
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) > half:
			continue
		var ink: Node = e.get("ink")
		var bonus := 0.0
		if ink and bool(ink.call("is_ready")):
			bonus = ink.call("consume")
		var killed: bool = e.call("take_damage", dmg + bonus)
		if killed:
			player.call("heal", melee_kill_heal)
		elif ink:
			ink.call("add", float(ink.get("max_ink")) if ink_amount < 0.0 else ink_amount)
		if bonus > 0.0:
			ink_burst.emit(e, bonus, killed)
		hit_enemy.emit(e, killed, true, "stroke")

	# 바닥에 먹 획을 남긴다: 슬라이드 획에 이어 그어지므로 도형을 닫을 수 있다
	var trail: Node = player.get("ink_trail")
	if trail:
		trail.call("draw_line", feet, to, width_mul)

	# 칼날: 머리 위로 치켜들었다가 앞으로 내려친다 (종베기). 끝나면 평소 자세로
	_pivot.rotation = Vector3(deg_to_rad(110.0), 0.0, 0.0)
	var tw := _pivot.create_tween()
	tw.tween_property(_pivot, "rotation:x", deg_to_rad(-65.0), SWING_TIME * 0.7).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.12)
	tw.tween_property(_pivot, "rotation", Vector3(0.0, deg_to_rad(-35.0), 0.0), 0.25)
	_blade_glow = 14.0
	_tip_glints(0.0, melee_range, true)
	stroke_struck.emit(feet, to, level)


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
			player.call("heal", melee_kill_heal)
		elif ink:
			ink.call("add", ink_finisher if finisher else ink_melee)
		if bonus > 0.0:
			ink_burst.emit(e, bonus, killed)
		hit_enemy.emit(e, killed, true, "finisher" if finisher else "melee")
	return hit


## 지금 붓 단계 (INK_STAGES의 한 줄)
func ink_stage() -> Array:
	var cur: Array = INK_STAGES[0]
	for s in INK_STAGES:
		if rank >= int(s[0]):
			cur = s
	return cur


func ink_stage_name() -> String:
	return String(ink_stage()[1])


func _launch_wave(finisher: bool, already_hit: Array) -> void:
	var stage := ink_stage()
	var size_mul: float = stage[2]
	var range_mul: float = stage[3]
	var dmg_mul: float = stage[4]
	var ink_mul: float = stage[5]
	var forks: int = stage[6]
	var origin := player.global_position + Vector3.UP * 1.0 + _aim() * 0.8
	var center_dir := _assisted_direction(origin)
	var kind := "wave_big" if finisher else "wave"
	var base_dmg := wave_damage * (1.5 if finisher else 1.0) * dmg_mul
	var base_ink := (ink_wave_big if finisher else ink_wave) * ink_mul
	for k in forks:
		var off := 0.0 if k == 0 else SPLIT_ANGLE_DEG * (1.0 if k == 1 else -1.0)
		var side := k > 0
		var w := SwordWave.new()
		w.vertical = rank >= RANK_CHARGE   # 일필휘지: 세로로 선 초승달 (종베기 검기)
		w.setup(origin, center_dir.rotated(Vector3.UP, deg_to_rad(off)), wave_speed, _wave_reach() * range_mul,
			base_dmg * (0.5 if side else 1.0), finisher, player, already_hit,
			size_mul * (0.7 if side else 1.0))
		w.hit_enemy.connect(_on_wave_hit.bind(kind, base_ink * (0.5 if side else 1.0)))
		player.get_parent().add_child(w)


func _on_wave_hit(e: Node, killed: bool, kind: String, ink_amount: float) -> void:
	var ink: Node = e.get("ink")
	if ink and not killed:
		ink.call("add", ink_amount)  # 검기는 먹을 묻히기만 한다 (터뜨리는 건 근접)
	hit_enemy.emit(e, killed, false, kind)


func _aim() -> Vector3:
	var f: Vector3 = player.get("facing")
	return Vector3(f.x, 0.0, f.z).normalized()


## 검기 사거리: 일필휘지면 무한(벽에 닿을 때까지)
func _wave_reach() -> float:
	return INFINITE_RANGE if rank >= RANK_CHARGE else wave_range


## 조준 방향 근처(보정 각도 안)에 적이 있으면 가장 가까운 적의 몸통을 향한다 (높이 차 포함)
func _assisted_direction(from: Vector3) -> Vector3:
	var aim := _aim()
	var best := aim
	var best_dist := _wave_reach()
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
