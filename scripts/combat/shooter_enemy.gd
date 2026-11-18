extends CharacterBody3D
## 사격형 적 (GDD 6.2): 거리를 유지하며 움직이다가, 멈춰 서서 플레이어를 향해 탄을 쏜다.
## 쏘기 전에 눈이 밝아지며 예고한다. 흰색 = 패링 가능, 붉은색 = 패링 불가.
## 움직임:
##   - 너무 가까우면(keep_min) 물러나고, 멀거나(keep_max) 플레이어가 안 보이면 다가가고, 그 사이에서는 옆으로 돈다
##   - 목표 지점까지는 내비게이션 메시(아레나가 굽는다)로 길을 찾는다 → 벽·다리·엄폐물을 돌아간다.
##     발판 위 사격형은 그 발판(따로 떨어진 섬) 안에서만 움직인다
##   - 예고하고 쏘는 동안에는 멈춰 선다 → 예고를 읽고 패링하기 좋게
##   - 발 앞에 바닥이 없으면 그쪽으로 가지 않는다 (만약을 위한 안전장치)
##   - 다른 적과 조금씩 떨어진다
## 등급 (GDD 6.1):
##   - 하급: 패링 가능한 탄만 쏜다
##   - 중급: 더 크고 단단하며, N발마다 패링 불가(붉은) 탄을 섞는다. 머리 위 흰 띠로 구분
## 프로토타입용으로 죽으면 잠시 뒤 다시 살아난다.

signal died(enemy: Node)

enum Tier { BASIC, ELITE }

const Projectile := preload("res://scripts/combat/projectile.gd")
const InkStack := preload("res://scripts/combat/ink_stack.gd")
const InkWash := preload("res://scripts/combat/ink_wash_look.gd")
## 몸통은 화선지에 그린 수묵담채 (ink_wash_look.gd). 사격형은 황토색 (붉은색은 패링 불가 경고 전용이라 피한다)
const TINT := Color(0.5, 0.27, 0.06)
const ELITE_MAX_INK := 160.0     # 중급 먹 한계 (하급 100)
const ELITE_BURST_MAX := 120.0   # 중급이 가득(160)일 때 먹 폭발 추가 피해 (체력 6칸)

@export var tier: Tier = Tier.BASIC        # add_child 전에 정한다
@export var max_health := 4.0              # 반사탄 1발 = 2 → 하급은 패링 2번, 중급은 3번에 처치
@export var fire_interval := 1.8
@export var telegraph_time := 0.45         # GDD 6.1: 예고는 0.3초 이상
@export var projectile_speed := 50.4       # 16.8 m/s에서 3배. 반사탄은 ×1.5 = 75.6 m/s
@export var projectile_damage := 20.0
@export var unparryable_every := 3         # 중급만: N발마다 1발은 패링 불가 탄
@export var attack_range := 35.0
@export var respawn_time := 4.0
@export var respawns := true             # 웨이브 아레나에서는 false (죽으면 그대로 사라진다)
## 예측 사격: 플레이어가 이동할 곳을 겨냥한다. 0 = 지금 위치, 1 = 등속 이동을 가정한 정확한 요격점.
## 하급은 덜 정확하게 예측한다. 방향을 바꾸면 빗나간다 → '멈추지 말고 꺾어라'
@export var lead_accuracy := 0.6

@export_group("Movement")
@export var move_speed := 4.5            # 플레이어 달리기(12)보다 훨씬 느리다. 중급은 5.5
@export var accel := 18.0
@export var keep_min := 11.0             # 이보다 가까우면 물러난다
@export var keep_max := 22.0             # 이보다 멀면 다가간다
@export var gravity := 24.0

var target: Node3D
var health := 4.0
var _timer := 1.0
var _telegraph := 0.0
var _shot_count := 0
var _next_unparryable := false
var _dead := false
var _flash := 0.0
var _col: CollisionShape3D
var _body_mat: ShaderMaterial
var _eye_mat: StandardMaterial3D
var _eye: MeshInstance3D
var _size := Vector3(1.2, 2.2, 1.2)
var _body_mesh: MeshInstance3D
var _punch := 0.0
var ink: Node3D  ## 먹 수치 (ink_stack.gd)
var _pulled := 0.0
var _strafe_sign := 1.0
var _strafe_timer := 0.0
var _stuck := 0.0                 # 가려는데 못 가고 있는 시간
var _agent: NavigationAgent3D
var _repath := 0.0                # 목표 지점을 다시 정하기까지 남은 시간
var _safe_vel := Vector3.ZERO     # 무리 회피를 거친 속도 (velocity_computed)
var _unstick := 0.0               # 엄폐벽 모서리 등에 걸렸을 때 벽을 따라 빠져나가는 남은 시간
var _unstick_dir := Vector3.ZERO


func body_height() -> float:
	return _size.y


func is_elite() -> bool:
	return tier == Tier.ELITE


func _ready() -> void:
	add_to_group("enemy")
	if is_elite():
		_size = Vector3(1.6, 2.8, 1.6)
		max_health = 6.0
		lead_accuracy = 1.0
		move_speed = 5.5
	else:
		unparryable_every = 0  # 하급은 패링 불가 공격을 쓰지 않는다
	health = max_health
	_timer = randf_range(0.6, fire_interval)  # 여러 적이 동시에 쏘지 않도록 어긋나게
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0
	_strafe_timer = randf_range(1.2, 3.0)
	floor_snap_length = 0.4
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 1.0
	_agent.target_desired_distance = 1.5
	_agent.path_max_distance = 3.0
	# 무리 회피: 적끼리 서로 비켜 가서 엄폐벽 끝 같은 좁은 길목에 줄지어 막히지 않게
	_agent.avoidance_enabled = true
	_agent.radius = maxf(_size.x, _size.z) * 0.6
	_agent.neighbor_distance = 6.0
	_agent.time_horizon_agents = 0.8
	_agent.velocity_computed.connect(func(v: Vector3): _safe_vel = v)
	add_child(_agent)

	var shape := BoxShape3D.new()
	shape.size = _size
	_col = CollisionShape3D.new()
	_col.shape = shape
	_col.position.y = _size.y * 0.5
	add_child(_col)

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = _size
	body.mesh = bm
	body.position.y = _size.y * 0.5
	_body_mat = InkWash.body_material(_size, TINT, randf() * 100.0)
	body.material_override = _body_mat
	add_child(body)
	_body_mesh = body

	if is_elite():
		# 중급 표시: 머리 위 흰 발광 띠 (붉은색은 경고 전용이라 쓰지 않는다)
		var band := MeshInstance3D.new()
		var bandm := BoxMesh.new()
		bandm.size = Vector3(_size.x + 0.1, 0.18, _size.z + 0.1)
		band.mesh = bandm
		band.position.y = _size.y + 0.25
		var band_mat := StandardMaterial3D.new()
		band_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		band_mat.emission_enabled = true
		band_mat.albedo_color = Color(1, 1, 1)
		band_mat.emission = Color(1, 1, 1)
		band_mat.emission_energy_multiplier = 2.0
		band.material_override = band_mat
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(band)

	ink = InkStack.new()
	if is_elite():
		ink.max_ink = ELITE_MAX_INK            # 먹방울 8칸: 더 쌓아 더 크게 터뜨린다
		ink.burst_max_damage = ELITE_BURST_MAX
	ink.body_height = _size.y
	ink.body_size = _size
	add_child(ink)

	_eye = MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.22
	em.height = 0.44
	_eye.mesh = em
	_eye.position = Vector3(0, _size.y - 0.6, -_size.z * 0.5 - 0.02)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.emission_enabled = true
	_eye.material_override = _eye_mat
	add_child(_eye)
	_set_eye(Color(0.5, 0.5, 0.5), 0.3)


func is_dead() -> bool:
	return _dead


## 플레이어의 반사탄 조준 보정에 쓰는 지점
func aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


## 먹 끌어당김에 붙잡혀 target 위치로 빨려 간다 (살짝 지나쳤다 멈춤)
func pull_to(target: Vector3, duration := 0.3) -> void:
	if _dead:
		return
	_flash = 0.08
	_pulled = duration + 0.1   # 끌려가는 동안 스스로 움직이지 않는다
	velocity = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(self, "global_position", target, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 이번 공격으로 죽었으면 true
func take_damage(amount: float) -> bool:
	if _dead:
		return false
	health -= amount / 20.0  # 대미지 20 = 체력 1칸. 반사탄(×2)은 2칸
	_flash = 0.12
	_punch = clampf(amount / 40.0, 0.5, 1.5)  # 세게 맞을수록 크게 움찔
	if health <= 0.0:
		_die()
		return true
	return false


func _physics_process(delta: float) -> void:
	if _dead or target == null:
		return
	if global_position.y < -10.0:
		_die()  # 어쩌다 맵 밖으로 떨어지면
		return
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() > 0.1:
		rotation.y = atan2(-to.x, -to.z)

	_move(delta, to)

	if _telegraph > 0.0:
		_telegraph -= delta
		var t := 1.0 - _telegraph / telegraph_time
		var c := Color(1.0, 0.12, 0.1) if _next_unparryable else Color(1, 1, 1)
		_set_eye(c, lerpf(0.5, 8.0, t))
		_eye.scale = Vector3.ONE * lerpf(1.0, 1.8, t)
		if _telegraph <= 0.0:
			_fire()
		return

	_timer -= delta
	if _timer <= 0.0:
		if _can_see_target():
			_next_unparryable = unparryable_every > 0 and (_shot_count + 1) % unparryable_every == 0
			_telegraph = telegraph_time
			get_tree().call_group("sfx", "play_at", "telegraph_red" if _next_unparryable else "telegraph", global_position)
		else:
			_timer = 0.3


## 거리 유지 이동: 물러나기 / 다가가기 / 옆으로 돌기. 예고·발사 중에는 멈춘다.
## 어디로 갈지(목표 지점)를 정하고, 거기까지는 내비게이션 메시 길을 따라간다
func _move(delta: float, to: Vector3) -> void:
	var vy := velocity.y
	vy = vy - gravity * delta if not is_on_floor() else -0.5
	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	if _pulled > 0.0:
		_pulled -= delta
		velocity = Vector3(0.0, vy, 0.0)
		return

	var desired := Vector3.ZERO
	if _telegraph > 0.0:
		hvel = Vector3.ZERO   # 예고가 시작되면 그 자리에 딱 멈춘다 (예고를 읽기 좋게)
	elif to.length() > 0.1:
		var dir := to.normalized()
		var dist := to.length()
		var side := dir.cross(Vector3.UP) * _strafe_sign
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_sign = -_strafe_sign
			_strafe_timer = randf_range(1.2, 3.0)
		# 목표 지점: 0.25초마다 다시 정한다 (매 프레임 길을 다시 찾지 않게)
		_repath -= delta
		if _repath <= 0.0:
			_repath = 0.25
			var goal := global_position
			if dist < keep_min:
				goal = global_position - dir * 6.0 + side * 2.5          # 비스듬히 물러난다
			elif dist > keep_max or not _can_see_target():
				# 다가간다. 멀 때는 곧장(도는 방향이 바뀔 때마다 길이 뒤집히지 않게), 가까워지면 비스듬히
				goal = target.global_position + (side * 4.0 if dist < keep_max + 10.0 else Vector3.ZERO)
			else:
				goal = global_position + side * 6.0                      # 옆으로 돈다
			_agent.target_position = goal
		if not _agent.is_navigation_finished():
			var next := _agent.get_next_path_position()
			var step := next - global_position
			step.y = 0.0
			if step.length() > 0.05:
				desired = step.normalized()
		# 다른 적과 떨어지기
		for e in get_tree().get_nodes_in_group("enemy"):
			if e == self:
				continue
			var away: Vector3 = global_position - (e as Node3D).global_position
			away.y = 0.0
			var d := away.length()
			if d > 0.01 and d < 3.5:
				desired += away / d * (3.5 - d) * 0.6
	if desired.length() > 0.01:
		desired = desired.normalized() * move_speed
		# 발 앞에 바닥이 없으면 그쪽으로 가지 않는다 (만약을 위한 안전장치)
		if is_on_floor() and not _floor_ahead(desired.normalized()):
			desired = Vector3.ZERO
			_strafe_sign = -_strafe_sign
			_repath = 0.0

	if _unstick > 0.0 and _telegraph <= 0.0:
		_unstick -= delta
		desired = _unstick_dir * move_speed
	# 무리 회피: 원하는 속도를 알려 주고, 지난 물리 프레임에 받은 '안전한 속도'로 움직인다
	_agent.max_speed = move_speed
	_agent.velocity = desired
	if desired.length() > 0.01:
		var steer := Vector3(_safe_vel.x, 0.0, _safe_vel.z)
		if steer.length() > 0.1 and (not is_on_floor() or _floor_ahead(steer.normalized())):
			desired = steer
	hvel = hvel.move_toward(desired, accel * delta)
	var hop := _try_hop(desired, _size.x * 0.5)
	if hop > 0.0:
		vy = hop
	velocity = Vector3(hvel.x, vy, hvel.z)
	move_and_slide()
	# 그래도 막혀 있으면 도는 방향을 바꾸고 목표를 다시 정한다
	var moved := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	if desired.length() > 0.01 and moved < move_speed * 0.35:
		_stuck += delta
	else:
		_stuck = 0.0
	if _stuck > 0.4:
		_stuck = 0.0
		_strafe_sign = -_strafe_sign
		_strafe_timer = randf_range(1.2, 3.0)
		_repath = 0.0
		if is_on_wall():
			# 벽에 막혔으면: 벽 법선 + 벽을 따르는 방향으로 잠깐 빠져나간다
			var n := get_wall_normal()
			n.y = 0.0
			_unstick_dir = (n * 0.6 + n.cross(Vector3.UP) * _strafe_sign).normalized()
			_unstick = 0.6


## 낮은 턱(MAX_HOP m 이하, 예: 중앙 광장 1 m·점프 단상)에 막히면 뛰어오른다. 내비게이션 메시가 이 높이까지는 길로 잇는다
const MAX_HOP := 1.3

func _try_hop(dir: Vector3, half_width: float) -> float:
	if not is_on_floor() or get_slide_collision_count() == 0 or dir.length() < 0.01:
		return 0.0
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	var probe := global_position + d * (half_width + 0.35) + Vector3.UP * (MAX_HOP + 0.4)
	var q := PhysicsRayQueryParameters3D.create(probe, probe + Vector3.DOWN * (MAX_HOP + 0.6))
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return 0.0
	var h := float((hit["position"] as Vector3).y) - global_position.y
	if h < 0.25 or h > MAX_HOP:
		return 0.0
	return sqrt(2.0 * gravity * (h + 0.35))   # 턱 높이 + 여유만큼 뛰어오르는 속도


## dir 방향으로 몸 반폭 + 여유만큼 앞의 발밑에 (1.4 m 안쪽으로) 바닥이 있는가
func _floor_ahead(dir: Vector3) -> bool:
	var probe := global_position + dir * (_size.x * 0.5 + 0.6) + Vector3.UP * 0.5
	# 1.4 m 이하로 내려가는 턱(중앙 광장 가장자리 1 m)은 내려가도 된다. 높은 발판(3 m 이상)에서는 멈춘다
	var q := PhysicsRayQueryParameters3D.create(probe, probe + Vector3.DOWN * 1.9)
	q.exclude = [get_rid()]
	return not space_state().intersect_ray(q).is_empty()


func space_state() -> PhysicsDirectSpaceState3D:
	return get_world_3d().direct_space_state


func _process(delta: float) -> void:
	_flash -= delta
	InkWash.update(_body_mat, float(ink.call("ratio")), _flash > 0.0)  # 먹이 쌓일수록 아래에서부터 먹이 스며 오른다
	# 피격 움찔: 옆으로 부풀고 위아래로 눌렸다 돌아온다
	_punch = move_toward(_punch, 0.0, 8.0 * delta)
	_body_mesh.scale = Vector3(1.0 + 0.15 * _punch, 1.0 - 0.1 * _punch, 1.0 + 0.15 * _punch)


func _fire() -> void:
	_shot_count += 1
	_timer = fire_interval
	_set_eye(Color(0.5, 0.5, 0.5), 0.3)
	_eye.scale = Vector3.ONE
	var muzzle := global_position + Vector3.UP * (_size.y - 0.6) - global_transform.basis.z * (_size.z * 0.5 + 0.4)
	var aim := predict_target(muzzle) - muzzle
	var p := Projectile.new()
	p.setup(muzzle, aim.normalized() * projectile_speed, projectile_damage, not _next_unparryable, self)
	get_parent().add_child(p)
	get_tree().call_group("sfx", "play_at", "enemy_shoot_red" if _next_unparryable else "enemy_shoot", muzzle)


## 탄이 날아가는 동안 플레이어가 수평으로 등속 이동한다고 보고 요격점을 구한다 (두 번 반복해 근사)
func predict_target(from: Vector3) -> Vector3:
	var aim_at := target.global_position + Vector3.UP * 1.0
	var v: Vector3 = target.get("velocity") if "velocity" in target else Vector3.ZERO
	v.y = 0.0
	var predicted := aim_at
	for i in 2:
		var t := from.distance_to(predicted) / projectile_speed
		predicted = aim_at + v * t * lead_accuracy
	return predicted


func _can_see_target() -> bool:
	var from := global_position + Vector3.UP * (_size.y - 0.6)
	var to := target.global_position + Vector3.UP * 1.0
	if from.distance_to(to) > attack_range:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit["collider"] == target


func _die() -> void:
	_dead = true
	ink.call("reset")
	remove_from_group("enemy")
	visible = false
	_col.set_deferred("disabled", true)
	died.emit(self)
	if respawns:
		get_tree().create_timer(respawn_time).timeout.connect(_respawn)


func _respawn() -> void:
	_dead = false
	velocity = Vector3.ZERO
	_pulled = 0.0
	health = max_health
	visible = true
	_col.set_deferred("disabled", false)
	add_to_group("enemy")
	_timer = fire_interval
	_telegraph = 0.0


func _set_eye(c: Color, energy: float) -> void:
	_eye_mat.albedo_color = c
	_eye_mat.emission = c
	_eye_mat.emission_energy_multiplier = energy
