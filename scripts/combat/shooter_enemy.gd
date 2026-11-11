extends StaticBody3D
## 사격형 적 (GDD 6.2): 제자리에서 플레이어를 향해 탄을 쏜다.
## 쏘기 전에 눈이 밝아지며 예고한다. 흰색 = 패링 가능, 붉은색 = 패링 불가.
## 등급 (GDD 6.1):
##   - 하급: 패링 가능한 탄만 쏜다
##   - 중급: 더 크고 단단하며, N발마다 패링 불가(붉은) 탄을 섞는다. 머리 위 흰 띠로 구분
## 프로토타입용으로 죽으면 잠시 뒤 다시 살아난다.

signal died(enemy: Node)

enum Tier { BASIC, ELITE }

const Projectile := preload("res://scripts/combat/projectile.gd")
const InkStack := preload("res://scripts/combat/ink_stack.gd")
const BODY_COLOR := Color(0.6, 0.6, 0.64)   # 밝은 회색: 먹이 묻으면 검게 물드는 게 보이도록
const INK_TINT := Color(0.03, 0.03, 0.03)

@export var tier: Tier = Tier.BASIC        # add_child 전에 정한다
@export var max_health := 4.0              # 반사탄 1발 = 2 → 하급은 패링 2번, 중급은 3번에 처치
@export var fire_interval := 1.8
@export var telegraph_time := 0.45         # GDD 6.1: 예고는 0.3초 이상
@export var projectile_speed := 16.8       # 12 m/s에서 40% 상향
@export var projectile_damage := 20.0
@export var unparryable_every := 3         # 중급만: N발마다 1발은 패링 불가 탄
@export var attack_range := 35.0
@export var respawn_time := 4.0

var target: Node3D
var health := 4.0
var _timer := 1.0
var _telegraph := 0.0
var _shot_count := 0
var _next_unparryable := false
var _dead := false
var _flash := 0.0
var _col: CollisionShape3D
var _body_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _eye: MeshInstance3D
var _size := Vector3(1.2, 2.2, 1.2)
var _body_mesh: MeshInstance3D
var _punch := 0.0
var ink: Node3D  ## 먹 수치 (ink_stack.gd)


func body_height() -> float:
	return _size.y


func is_elite() -> bool:
	return tier == Tier.ELITE


func _ready() -> void:
	add_to_group("enemy")
	if is_elite():
		_size = Vector3(1.6, 2.8, 1.6)
		max_health = 6.0
	else:
		unparryable_every = 0  # 하급은 패링 불가 공격을 쓰지 않는다
	health = max_health
	_timer = randf_range(0.6, fire_interval)  # 여러 적이 동시에 쏘지 않도록 어긋나게

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
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = BODY_COLOR
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
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() > 0.1:
		rotation.y = atan2(-to.x, -to.z)

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
		else:
			_timer = 0.3


func _process(delta: float) -> void:
	_flash -= delta
	var tint := BODY_COLOR.lerp(INK_TINT, float(ink.call("ratio")) * 0.9)  # 먹이 쌓일수록 검게
	_body_mat.albedo_color = Color(1, 1, 1) if _flash > 0.0 else tint
	# 피격 움찔: 옆으로 부풀고 위아래로 눌렸다 돌아온다
	_punch = move_toward(_punch, 0.0, 8.0 * delta)
	_body_mesh.scale = Vector3(1.0 + 0.15 * _punch, 1.0 - 0.1 * _punch, 1.0 + 0.15 * _punch)


func _fire() -> void:
	_shot_count += 1
	_timer = fire_interval
	_set_eye(Color(0.5, 0.5, 0.5), 0.3)
	_eye.scale = Vector3.ONE
	var muzzle := global_position + Vector3.UP * (_size.y - 0.6) - global_transform.basis.z * (_size.z * 0.5 + 0.4)
	var aim := target.global_position + Vector3.UP * 1.0 - muzzle
	var p := Projectile.new()
	p.setup(muzzle, aim.normalized() * projectile_speed, projectile_damage, not _next_unparryable, self)
	get_parent().add_child(p)


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
	get_tree().create_timer(respawn_time).timeout.connect(_respawn)


func _respawn() -> void:
	_dead = false
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
