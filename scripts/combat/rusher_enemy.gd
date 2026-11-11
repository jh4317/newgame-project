extends CharacterBody3D
## 돌격형 적 (GDD 6.2): 플레이어를 쫓아와 예고 뒤 직선으로 돌진해 벤다.
## 대응: 근접 패링으로 튕겨 내 경직시키거나, 슬라이드·대시로 돌진 경로에서 빠져나간다.
##
## 상태: 추격 → 예고(멈춰서 조준, 뿔이 점점 밝아짐) → 돌진 → 후딜레이 → 추격
##   - 예고 색: 흰색 = 패링 가능, 붉은색 = 패링 불가 (GDD 3.1, 6.1)
##   - 패링당하면 뒤로 튕겨 나며 경직. 경직 중에는 받는 대미지가 커진다 (GDD 3.1)
## 등급 (GDD 6.1):
##   - 하급: 패링 가능한 돌진만
##   - 중급: 더 크고 단단하며, N번마다 패링 불가(붉은) 돌진을 섞는다. 머리 위 흰 띠로 구분
## 길 찾기는 아직 없다(직선 추격). 적 공통 기반·NavigationAgent3D는 적 종류가 늘 때 정리한다 (GDD 9.2).
## 프로토타입용으로 죽으면 잠시 뒤 다시 살아난다.

signal died(enemy: Node)

enum Tier { BASIC, ELITE }
enum State { CHASE, WINDUP, CHARGE, RECOVER, STAGGER }

const InkStack := preload("res://scripts/combat/ink_stack.gd")
const BODY_COLOR := Color(0.6, 0.6, 0.64)
const INK_TINT := Color(0.03, 0.03, 0.03)
const WARN_RED := Color(1.0, 0.12, 0.1)
const ELITE_MAX_INK := 160.0     # 중급 먹 한계 (하급 100)
const ELITE_BURST_MAX := 120.0   # 중급이 가득(160)일 때 먹 폭발 추가 피해 (체력 6칸)

@export var tier: Tier = Tier.BASIC        # add_child 전에 정한다
@export var max_health := 4.0              # 근접 베기 1번 = 2칸
@export var chase_speed := 9.0             # 달리기(12 m/s)보다 느리다: 달려서 떨칠 수 있다
@export var turn_speed_deg := 360.0
@export var gravity := 24.0
@export var charge_trigger_range := 9.0    # 이 거리 안에서 시야가 트이면 돌진 예고
@export var telegraph_time := 0.5          # GDD 6.1: 예고는 0.3초 이상
@export var charge_speed := 26.0
@export var charge_distance := 11.0        # 돌진 최대 거리
@export var charge_damage := 25.0
@export var hit_radius := 1.3              # 돌진 중 이 거리 안의 플레이어를 벤다
@export var recover_time := 0.7            # 돌진 뒤 빈틈
@export var stagger_time := 1.4            # 패링당한 뒤 경직
@export var stagger_damage_mul := 1.5      # 경직 중 받는 대미지 배율
@export var parry_knockback := 7.0
@export var unparryable_every := 2         # 중급만: N번째 돌진마다 패링 불가
@export var respawn_time := 4.0
@export var respawns := true             # 웨이브 아레나에서는 false (죽으면 그대로 사라진다)
## 예측 돌진: 방향을 고정하는 순간, 플레이어가 돌진이 닿을 때쯤 있을 곳을 겨냥한다.
## 0 = 지금 위치, 1 = 등속 이동을 가정한 정확한 예측. 하급은 덜 정확하다
@export var lead_accuracy := 0.6

var target: Node3D
var health := 4.0
var state: State = State.CHASE
var ink: Node3D  ## 먹 수치 (ink_stack.gd)

var _state_time := 0.0
var _cooldown := 1.0
var _charge_dir := Vector3.FORWARD
var _charge_left := 0.0
var _charge_count := 0
var _unparryable := false
var _hit_done := false
var _pulled := 0.0
var _dead := false
var _spawn := Vector3.ZERO
var _flash := 0.0
var _punch := 0.0
var _size := Vector3(1.5, 1.5, 1.3)
var _col: CollisionShape3D
var _visual: Node3D
var _body_mesh: MeshInstance3D
var _body_mat: StandardMaterial3D
var _horn_mat: StandardMaterial3D
var _stars: Node3D


func body_height() -> float:
	return _size.y


func is_elite() -> bool:
	return tier == Tier.ELITE


func is_dead() -> bool:
	return _dead


func is_staggered() -> bool:
	return state == State.STAGGER


## 플레이어의 근접 패링 판정용: 지금 패링할 수 있는 돌진 중인가
func is_parryable_attack() -> bool:
	return not _dead and state == State.CHARGE and not _unparryable and not _hit_done


## 반사탄·검기 조준 보정에 쓰는 지점
func aim_point() -> Vector3:
	return global_position + Vector3.UP * (_size.y * 0.55)


func _ready() -> void:
	add_to_group("enemy")
	if is_elite():
		_size = Vector3(1.9, 1.9, 1.6)
		max_health = 6.0
		lead_accuracy = 1.0
	else:
		unparryable_every = 0  # 하급은 패링 불가 공격을 쓰지 않는다
	health = max_health
	_spawn = global_position
	_cooldown = randf_range(0.6, 1.4)
	floor_snap_length = 0.3

	var shape := BoxShape3D.new()
	shape.size = _size
	_col = CollisionShape3D.new()
	_col.shape = shape
	_col.position.y = _size.y * 0.5
	add_child(_col)

	_build_visuals()

	ink = InkStack.new()
	if is_elite():
		ink.max_ink = ELITE_MAX_INK            # 먹방울 8칸: 더 쌓아 더 크게 터뜨린다
		ink.burst_max_damage = ELITE_BURST_MAX
	ink.body_height = _size.y
	ink.body_size = _size
	add_child(ink)

	if target is PhysicsBody3D:
		add_collision_exception_with(target)  # 돌진이 플레이어를 밀지 않고 지나가게


## 먹 끌어당김에 붙잡혀 target 위치로 빨려 간다
func pull_to(to: Vector3, duration := 0.3) -> void:
	if _dead:
		return
	_flash = 0.08
	_pulled = duration
	_set_state(State.RECOVER)  # 끌려가면 하던 공격이 끊긴다
	velocity = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(self, "global_position", to, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 이번 공격으로 죽었으면 true
func take_damage(amount: float) -> bool:
	if _dead:
		return false
	if state == State.STAGGER:
		amount *= stagger_damage_mul
	health -= amount / 20.0  # 대미지 20 = 체력 1칸
	_flash = 0.12
	_punch = clampf(amount / 40.0, 0.5, 1.5)
	if health <= 0.0:
		_die()
		return true
	return false


## 플레이어가 돌진을 패링했다: 뒤로 튕겨 나며 경직
func on_parried(from: Vector3) -> void:
	if _dead:
		return
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -_charge_dir
	velocity = away * parry_knockback + Vector3.UP * 4.0
	_hit_done = true
	_flash = 0.15
	_punch = 1.5
	_set_state(State.STAGGER)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_state_time += delta
	if _pulled > 0.0:
		_pulled -= delta
		return

	var vy := velocity.y
	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	var to_target := Vector3.ZERO
	if target:
		to_target = target.global_position - global_position
		to_target.y = 0.0

	match state:
		State.CHASE:
			_cooldown -= delta
			if to_target.length() > 0.1:
				_face(to_target, delta)
				hvel = hvel.move_toward(to_target.normalized() * chase_speed, 40.0 * delta)
			if _cooldown <= 0.0 and to_target.length() <= charge_trigger_range and _can_see_target():
				_begin_windup()
		State.WINDUP:
			hvel = hvel.move_toward(Vector3.ZERO, 60.0 * delta)
			# 예고 초반에는 계속 조준하다가, 마지막 40%는 방향을 고정해 읽고 피할 수 있게 한다
			if _state_time < telegraph_time * 0.6 and to_target.length() > 0.1:
				var to_pred := _predicted_offset()
				_charge_dir = to_pred.normalized() if to_pred.length() > 0.1 else to_target.normalized()
				_face(_charge_dir, delta * 3.0)
			_update_telegraph()
			if _state_time >= telegraph_time:
				_begin_charge()
		State.CHARGE:
			hvel = _charge_dir * charge_speed
			_charge_left -= charge_speed * delta
			_check_charge_hit()
			if _charge_left <= 0.0 or (is_on_wall() and _state_time > 0.05):
				_end_charge()
		State.RECOVER:
			hvel = hvel.move_toward(Vector3.ZERO, 50.0 * delta)
			if _state_time >= recover_time:
				_set_state(State.CHASE)
		State.STAGGER:
			hvel = hvel.move_toward(Vector3.ZERO, 12.0 * delta)
			if _state_time >= stagger_time:
				_set_state(State.CHASE)

	vy = 0.0 if is_on_floor() and vy < 0.0 else vy - gravity * delta
	velocity = Vector3(hvel.x, vy, hvel.z)
	move_and_slide()
	if global_position.y < -20.0:
		global_position = _spawn
		velocity = Vector3.ZERO


func _process(delta: float) -> void:
	if _dead:
		return
	_flash -= delta
	var tint := BODY_COLOR.lerp(INK_TINT, float(ink.call("ratio")) * 0.9)
	_body_mat.albedo_color = Color(1, 1, 1) if _flash > 0.0 else tint
	_punch = move_toward(_punch, 0.0, 8.0 * delta)
	var squash := Vector3(1.0 + 0.15 * _punch, 1.0 - 0.1 * _punch, 1.0 + 0.15 * _punch)
	if state == State.CHARGE:
		squash = Vector3(0.9, 0.85, 1.35)  # 돌진 중 앞뒤로 늘어난다
	_body_mesh.scale = _body_mesh.scale.lerp(squash, 1.0 - exp(-25.0 * delta))
	# 경직: 머리 위에서 흰 별이 돈다
	_stars.visible = state == State.STAGGER
	if _stars.visible:
		_stars.rotation.y += 9.0 * delta


# ---------------------------------------------------------------- 상태 전환

func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0
	if s != State.WINDUP:
		_set_horn(Color(0.5, 0.5, 0.5), 0.3)


func _begin_windup() -> void:
	_charge_count += 1
	_unparryable = unparryable_every > 0 and _charge_count % unparryable_every == 0
	_set_state(State.WINDUP)
	get_tree().call_group("sfx", "play_at", "telegraph_red" if _unparryable else "telegraph", global_position, 0.0, 0.8)


func _begin_charge() -> void:
	_charge_left = charge_distance
	_hit_done = false
	_set_state(State.CHARGE)
	get_tree().call_group("sfx", "play_at", "rush", global_position)
	var c := WARN_RED if _unparryable else Color(1, 1, 1)
	_set_horn(c, 6.0)  # 돌진 중에도 패링 가능 여부를 계속 보여 준다


func _end_charge() -> void:
	_set_state(State.RECOVER)
	_cooldown = randf_range(0.8, 1.6)


func _check_charge_hit() -> void:
	if _hit_done or target == null:
		return
	var to := target.global_position - global_position
	if absf(to.y) > 1.6 or Vector3(to.x, 0.0, to.z).length() > hit_radius + _size.x * 0.5:
		return
	# 플레이어의 패링 판정이 열려 있으면 먼저 확인한다 (같은 프레임 처리 순서와 무관하게)
	if not _unparryable and target.has_method("try_parry_melee") and bool(target.call("try_parry_melee", self)):
		return
	if target.has_method("is_invulnerable") and bool(target.call("is_invulnerable")):
		return  # 대시 무적: 돌진을 뚫고 지나간다 (무적이 끝난 뒤에도 겹쳐 있으면 맞는다)
	_hit_done = true
	target.call("take_damage", charge_damage)
	_end_charge()


## 돌진이 닿을 때쯤 플레이어가 있을 곳까지의 수평 벡터.
## 걸리는 시간 = 남은 예고 시간 + 거리 / 돌진 속도 (두 번 반복해 근사). 돌진 거리 밖은 잘라 낸다
func _predicted_offset() -> Vector3:
	var v: Vector3 = target.get("velocity") if "velocity" in target else Vector3.ZERO
	v.y = 0.0
	var now := target.global_position - global_position
	now.y = 0.0
	var pred := now
	var windup_left := maxf(telegraph_time - _state_time, 0.0)
	for i in 2:
		var t := windup_left + pred.length() / charge_speed
		pred = now + v * t * lead_accuracy
	return pred.limit_length(charge_distance)


func _can_see_target() -> bool:
	var from := global_position + Vector3.UP * (_size.y * 0.6)
	var to := target.global_position + Vector3.UP * 1.0
	if absf(to.y - from.y) > 2.5:
		return false  # 다른 층에 있으면 돌진하지 않는다
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit["collider"] == target


func _face(dir: Vector3, delta: float) -> void:
	var want := atan2(-dir.x, -dir.z)
	rotation.y = rotate_toward(rotation.y, want, deg_to_rad(turn_speed_deg) * delta)


func _die() -> void:
	_dead = true
	ink.call("reset")
	remove_from_group("enemy")
	visible = false
	velocity = Vector3.ZERO
	_col.set_deferred("disabled", true)
	died.emit(self)
	if respawns:
		get_tree().create_timer(respawn_time).timeout.connect(_respawn)


func _respawn() -> void:
	_dead = false
	health = max_health
	global_position = _spawn
	velocity = Vector3.ZERO
	visible = true
	_col.set_deferred("disabled", false)
	add_to_group("enemy")
	_cooldown = 1.0
	_set_state(State.CHASE)


# ---------------------------------------------------------------- 표현

func _build_visuals() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	# 몸통: 사격형(키 큰 상자)과 구분되는 낮고 넓은 덩어리 (GDD 6.1 실루엣)
	_body_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = _size
	_body_mesh.mesh = bm
	_body_mesh.position.y = _size.y * 0.5
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = BODY_COLOR
	_body_mesh.material_override = _body_mat
	_visual.add_child(_body_mesh)

	# 앞으로 뻗은 뿔(칼날): 돌진 방향과 예고 색을 보여 준다
	var horn := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(_size.x * 0.6, 1.2, 0.35)
	horn.mesh = pm
	horn.rotation_degrees = Vector3(-90, 0, 0)  # 꼭짓점이 앞(-Z)을 향하게
	horn.position = Vector3(0, _size.y * 0.55, -_size.z * 0.5 - 0.55)
	_horn_mat = StandardMaterial3D.new()
	_horn_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_horn_mat.emission_enabled = true
	horn.material_override = _horn_mat
	_visual.add_child(horn)
	_set_horn(Color(0.5, 0.5, 0.5), 0.3)

	if is_elite():
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
		_visual.add_child(band)

	# 경직 표시: 머리 위를 도는 흰 점 세 개
	_stars = Node3D.new()
	_stars.position.y = _size.y + 0.6
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.emission_enabled = true
	star_mat.albedo_color = Color(1, 1, 1)
	star_mat.emission = Color(1, 1, 1)
	star_mat.emission_energy_multiplier = 3.0
	for i in 3:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		s.mesh = sm
		s.material_override = star_mat
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * i / 3.0
		s.position = Vector3(cos(a), 0.0, sin(a)) * 0.6
		_stars.add_child(s)
	_stars.visible = false
	_visual.add_child(_stars)


func _update_telegraph() -> void:
	var t := clampf(_state_time / telegraph_time, 0.0, 1.0)
	var c := WARN_RED if _unparryable else Color(1, 1, 1)
	_set_horn(c, lerpf(0.5, 8.0, t))
	# 방향이 고정되면 몸(뿔)이 돌진 방향을 정확히 가리킨다
	if _state_time >= telegraph_time * 0.6:
		rotation.y = atan2(-_charge_dir.x, -_charge_dir.z)


func _set_horn(c: Color, energy: float) -> void:
	_horn_mat.albedo_color = c
	_horn_mat.emission = c
	_horn_mat.emission_energy_multiplier = energy
