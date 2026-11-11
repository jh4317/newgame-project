extends CharacterBody3D
## 이동 프로토타입 플레이어: 달리기, 슬라이드, 슬라이드 점프, 벽 붙기, 벽 점프, 대시.
## 수치 초기값은 docs/GDD.md 3.4를 따른다.
## 이동 방향과 바라보는 방향은 camera_rig(탑뷰/숄더뷰)에게 물어본다.
##
## 스태미나: 벽 점프와 대시가 같은 스태미나(3칸)를 나눠 쓴다.
## 바닥에 서 있는 동안에만 회복한다(공중에서는 회복 없음).

const Sword := preload("res://scripts/combat/sword.gd")

signal respawned
signal parried(projectile: Node)
signal damaged(amount: float)
signal dashed
signal wall_jumped
signal landed(fall_speed: float)

enum State { GROUND, SLIDE, AIR, WALL, DASH }

@export_group("Ground")
@export var run_speed := 12.0
@export var ground_accel := 100.0
@export var overspeed_decel := 30.0  # 슬라이드 속도에서 달리기 속도로 줄어드는 정도

@export_group("Slide")
@export var slide_speed := 20.0
@export var slide_turn_deg := 150.0
@export var slide_overspeed_decay := 8.0

@export_group("Air")
@export var gravity := 24.0
@export var jump_height := 2.5
@export var air_accel := 30.0
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12

@export_group("Wall")
@export var wall_slide_speed := 2.0
@export var wall_jump_push := 9.0
@export var wall_coyote_time := 0.15

@export_group("Stamina")
@export var stamina_max := 3
@export var stamina_regen_time := 0.5  # 바닥에서 1칸 회복하는 데 걸리는 시간(초)
@export var wall_jump_cost := 1.0
@export var dash_cost := 1.0

@export_group("Bunny Hop")
@export var bhop_window := 0.12      # 착지 후 이 시간 안에 점프하면 '버니합'
@export var bhop_gain := 1.0         # 버니합 1회당 늘어나는 수평 속도 (m/s)
@export var bhop_max_speed := 28.0   # 버니합으로 올릴 수 있는 최고 속도
@export var bhop_min_speed := 10.0   # 이 속도 이상으로 움직일 때만 가속

@export_group("Dash")
@export var dash_speed := 30.0
@export var dash_time := 0.15  # 30 m/s × 0.15초 = 4.5 m
@export var dash_cooldown := 0.1

@export_group("Combat")
@export var max_health := 100.0
@export var parry_window := 0.15        # GDD 3.4: 판정 시간
@export var parry_radius := 2.0         # 판정 반경 (m)
@export var parry_angle_deg := 90.0     # 조준 방향 기준 부채꼴 각도
@export var parry_whiff_cooldown := 0.35
@export var parry_speed_mul := 1.5
@export var parry_damage_mul := 2.0
@export var parry_heal := 10.0
@export var parry_aim_assist_deg := 25.0  # 이 각도 안의 적에게 반사탄을 보정

@export_group("Speed FX")
@export var afterimage_speed := 17.0     # 이 속도 이상(또는 대시 중)이면 잔상
@export var afterimage_interval := 0.035
@export var afterimage_life := 0.25

const CAPSULE_RADIUS := 0.4
const CAPSULE_HEIGHT := 1.8
const KILL_Y := -20.0

var state: State = State.AIR
var camera_rig: Node3D
var stamina := 3.0
var facing := Vector3(0, 0, -1)

var bhop_chain := 0  # 연속 버니합 횟수 (HUD 표시용)
var health := 100.0
var parry_count := 0
var _parry_left := 0.0
var _parry_cooldown_left := 0.0
var _parry_hit := false
var _parry_fan: MeshInstance3D
var sword: Node3D
var _last_air_vy := 0.0
var _ghost_timer := 0.0
var _body_mesh_node: MeshInstance3D
var _time_on_floor := 0.0
var _dash_left := 0.0
var _dash_cooldown_left := 0.0
var _dash_dir := Vector3(0, 0, -1)
var _dash_exit_speed := 0.0

var _since_floor := 10.0
var _since_jump_pressed := 10.0
var _since_wall := 10.0
var _wall_normal := Vector3.ZERO
var _slide_dir := Vector3(0, 0, -1)
var _spawn_point := Vector3.ZERO
var _visual: Node3D
var _shadow: MeshInstance3D
var _dots: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("player")
	_spawn_point = global_position
	stamina = stamina_max
	health = max_health
	floor_snap_length = 0.3
	_build_collision()
	_build_visual()
	sword = Sword.new()
	sword.player = self
	_visual.add_child(sword)


func jump_velocity() -> float:
	return sqrt(2.0 * gravity * jump_height)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func state_name() -> String:
	match state:
		State.GROUND:
			return "지상"
		State.SLIDE:
			return "슬라이드"
		State.WALL:
			return "벽 붙기"
		State.DASH:
			return "대시"
	return "공중"


func parry_status() -> String:
	if _parry_left > 0.0:
		return "판정 중"
	if _parry_cooldown_left > 0.0:
		return "헛침 (%.2f초)" % _parry_cooldown_left
	return "준비"


func take_damage(amount: float) -> void:
	health -= amount
	damaged.emit(amount)
	if health <= 0.0:
		respawn()


## 지금 바로 쓸 수 있는 스태미나 칸 수
func stamina_pips() -> int:
	return int(floor(stamina + 0.001))


func respawn() -> void:
	global_position = _spawn_point
	velocity = Vector3.ZERO
	stamina = stamina_max
	health = max_health
	_dash_left = 0.0
	_parry_left = 0.0
	_parry_cooldown_left = 0.0
	state = State.AIR
	respawned.emit()


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("restart") or global_position.y < KILL_Y:
		respawn()
		return

	_update_parry(delta)

	var input_dir := _input_direction()
	if Input.is_action_just_pressed("jump"):
		_since_jump_pressed = 0.0
	else:
		_since_jump_pressed += delta

	var on_floor := is_on_floor()
	if on_floor:
		if _since_floor > 0.05:
			landed.emit(-_last_air_vy)
		_time_on_floor = 0.0 if _since_floor > 0.0 else _time_on_floor + delta
		_since_floor = 0.0
		stamina = minf(stamina_max, stamina + delta / stamina_regen_time)
		if _time_on_floor > bhop_window:
			bhop_chain = 0  # 착지 후 너무 오래 머물면 연속 버니합이 끊긴다
	else:
		_since_floor += delta
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)

	var hvel := Vector3(velocity.x, 0.0, velocity.z)

	# 대시: 짧은 순간 고속 직선 이동. 중력 무시. 점프를 누르면 즉시 끊고 점프로 이어진다.
	if Input.is_action_just_pressed("dash") and _dash_left <= 0.0 \
			and _dash_cooldown_left <= 0.0 and stamina >= dash_cost:
		_start_dash(hvel, input_dir)
	if _dash_left > 0.0:
		_dash_left -= delta
		if _dash_left > 0.0 and _since_jump_pressed > jump_buffer_time:
			velocity = _dash_dir * dash_speed
			move_and_slide()
			_track_wall(delta)
			_update_visual(delta, input_dir)
			return
		# 대시 종료: 들어올 때 속도(최소 달리기 속도)로 대시 방향을 유지한다
		_dash_left = 0.0
		_dash_cooldown_left = dash_cooldown
		hvel = _dash_dir * _dash_exit_speed

	_update_state(on_floor, input_dir, hvel)

	match state:
		State.GROUND:
			hvel = _ground_move(hvel, input_dir, delta)
		State.SLIDE:
			hvel = _slide_move(hvel, input_dir, delta)
		_:
			hvel = _air_move(hvel, input_dir, delta)

	var vy := velocity.y
	if not on_floor:
		vy -= gravity * delta
		if state == State.WALL:
			vy = maxf(vy, -wall_slide_speed)
		_last_air_vy = vy

	# 점프: 입력 버퍼 + 코요테 타임. 슬라이드 중 점프하면 속도를 그대로 가져간다.
	if _since_jump_pressed <= jump_buffer_time:
		if _since_floor <= coyote_time:
			# 버니합: 착지 직후 점프하면 속도를 잃지 않고 조금 더 붙는다
			if on_floor and _time_on_floor <= bhop_window and hvel.length() >= bhop_min_speed:
				var hop_speed := minf(hvel.length() + bhop_gain, maxf(bhop_max_speed, hvel.length()))
				var hop_dir := hvel.normalized()
				if input_dir.length() > 0.1:
					hop_dir = hop_dir.slerp(input_dir.normalized(), 0.35).normalized()
				hvel = hop_dir * hop_speed
				bhop_chain += 1
			vy = jump_velocity()
			_consume_jump()
		elif _since_wall <= wall_coyote_time and stamina >= wall_jump_cost:
			hvel -= _wall_normal * minf(hvel.dot(_wall_normal), 0.0)  # 벽 쪽으로 향하던 속도 제거
			hvel += _wall_normal * wall_jump_push
			vy = jump_velocity()
			stamina -= wall_jump_cost
			_since_wall = 10.0
			_consume_jump()
			wall_jumped.emit()

	velocity = Vector3(hvel.x, vy, hvel.z)
	move_and_slide()
	_track_wall(delta)
	_update_visual(delta, input_dir)


# ---------------------------------------------------------------- 패링 (GDD 3.1)

func _update_parry(delta: float) -> void:
	_parry_cooldown_left = maxf(0.0, _parry_cooldown_left - delta)
	if Input.is_action_just_pressed("parry") and _parry_left <= 0.0 and _parry_cooldown_left <= 0.0:
		_parry_left = parry_window
		_parry_hit = false
	if _parry_left <= 0.0:
		_parry_fan.visible = false
		return
	_parry_fan.visible = true
	_try_parry()
	_parry_left -= delta
	if _parry_left <= 0.0 or _parry_hit:
		_parry_left = 0.0
		_parry_fan.visible = false
		if not _parry_hit:
			_parry_cooldown_left = parry_whiff_cooldown  # 헛치면 난발 방지 후딜레이


func _try_parry() -> void:
	var center := global_position + Vector3.UP * 1.0
	var half_angle := deg_to_rad(parry_angle_deg) * 0.5
	for node in get_tree().get_nodes_in_group("projectile"):
		var p := node as Node3D
		if p == null or bool(p.get("reflected")) or not bool(p.get("parryable")):
			continue  # 붉은 탄(패링 불가)은 되받아칠 수 없다
		var to := p.global_position - center
		if to.length() > parry_radius + 0.3:
			continue
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() > 0.2 and facing.angle_to(flat.normalized()) > half_angle:
			continue
		p.call("reflect", _reflect_direction(p.global_position), parry_speed_mul, parry_damage_mul)
		_parry_hit = true
		parry_count += 1
		health = minf(max_health, health + parry_heal)
		parried.emit(p)


## 조준 방향으로 되돌리되, 그 근처(보정 각도 안)에 적이 있으면 가장 가까운 적을 향한다
func _reflect_direction(from: Vector3) -> Vector3:
	var aim := Vector3(facing.x, 0.0, facing.z).normalized()
	var best_dir := aim
	var best_dist := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		var to: Vector3 = e.call("aim_point") - from
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() < 0.5 or rad_to_deg(aim.angle_to(flat.normalized())) > parry_aim_assist_deg:
			continue
		if to.length() < best_dist:
			best_dist = to.length()
			best_dir = to.normalized()
	return best_dir


func _start_dash(hvel: Vector3, input_dir: Vector3) -> void:
	stamina -= dash_cost
	_dash_dir = input_dir.normalized() if input_dir.length() > 0.1 else facing
	_dash_exit_speed = maxf(hvel.length(), run_speed)
	_dash_left = dash_time
	state = State.DASH
	_ghost_timer = 0.0
	dashed.emit()


func _consume_jump() -> void:
	_since_jump_pressed = 10.0
	_since_floor = 10.0


func _update_state(on_floor: bool, input_dir: Vector3, hvel: Vector3) -> void:
	if on_floor:
		if Input.is_action_pressed("slide"):
			if state != State.SLIDE:
				_begin_slide(hvel, input_dir)
			state = State.SLIDE
		else:
			state = State.GROUND
	elif _since_wall <= 0.05 and velocity.y < 0.0 and input_dir.dot(-_wall_normal) > 0.3:
		state = State.WALL
	else:
		state = State.AIR


func _ground_move(hvel: Vector3, input_dir: Vector3, delta: float) -> Vector3:
	if hvel.length() > run_speed + 0.1:
		if _time_on_floor <= bhop_window:
			return hvel  # 버니합 판정 시간 동안은 지면 마찰을 적용하지 않는다
		return hvel.move_toward(input_dir * run_speed, overspeed_decel * delta)
	return hvel.move_toward(input_dir * run_speed, ground_accel * delta)


func _begin_slide(hvel: Vector3, input_dir: Vector3) -> void:
	if hvel.length() > 1.0:
		_slide_dir = hvel.normalized()
	elif input_dir.length() > 0.1:
		_slide_dir = input_dir.normalized()
	else:
		_slide_dir = facing


func _slide_move(hvel: Vector3, input_dir: Vector3, delta: float) -> Vector3:
	if hvel.length() > 1.0:
		_slide_dir = hvel.normalized()
	if input_dir.length() > 0.1:
		var angle := _slide_dir.signed_angle_to(input_dir.normalized(), Vector3.UP)
		var max_step := deg_to_rad(slide_turn_deg) * delta
		_slide_dir = _slide_dir.rotated(Vector3.UP, clampf(angle, -max_step, max_step))
	# 감속 없음: 슬라이드 속도 아래로는 떨어지지 않는다. 그보다 빠르면 천천히 맞춘다.
	var speed := maxf(slide_speed, move_toward(hvel.length(), slide_speed, slide_overspeed_decay * delta))
	return _slide_dir * speed


func _air_move(hvel: Vector3, input_dir: Vector3, delta: float) -> Vector3:
	if input_dir.length() < 0.1:
		return hvel  # 입력이 없으면 관성을 그대로 유지
	var max_speed := maxf(run_speed, hvel.length())
	return hvel.move_toward(input_dir * max_speed, air_accel * delta)


func _track_wall(delta: float) -> void:
	if not is_on_floor() and is_on_wall():
		var n := get_wall_normal()
		n.y = 0.0
		if n.length() > 0.5:
			_wall_normal = n.normalized()
			_since_wall = 0.0
			return
	_since_wall += delta


func _input_direction() -> Vector3:
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_basis := Basis.IDENTITY
	if camera_rig and camera_rig.has_method("get_move_basis"):
		move_basis = camera_rig.get_move_basis()
	var dir := move_basis * Vector3(raw.x, 0.0, raw.y)
	dir.y = 0.0
	return dir.limit_length(1.0)


# ---------------------------------------------------------------- 표현

func _build_collision() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_RADIUS
	shape.height = CAPSULE_HEIGHT
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = CAPSULE_HEIGHT * 0.5
	add_child(col)


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = CAPSULE_RADIUS
	cm.height = CAPSULE_HEIGHT
	body.mesh = cm
	body.position.y = CAPSULE_HEIGHT * 0.5
	body.material_override = _flat(Color(0.92, 0.92, 0.95))
	_visual.add_child(body)
	_body_mesh_node = body

	# 바라보는 방향 표시 (붉은색은 '패링 불가' 경고용이라 쓰지 않는다)
	var nose := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.25, 0.25, 0.5)
	nose.mesh = bm
	nose.position = Vector3(0, 1.4, -0.45)
	nose.material_override = _flat(Color(0.25, 0.8, 1.0))
	_visual.add_child(nose)

	# 패링 판정 부채꼴: 판정이 열려 있는 동안만 보인다
	_parry_fan = MeshInstance3D.new()
	_parry_fan.mesh = _make_fan_mesh(parry_radius, deg_to_rad(parry_angle_deg))
	_parry_fan.position.y = 1.0
	var fan_mat := StandardMaterial3D.new()
	fan_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fan_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fan_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fan_mat.albedo_color = Color(1, 1, 1, 0.35)
	fan_mat.emission_enabled = true
	fan_mat.emission = Color(1, 1, 1)
	fan_mat.emission_energy_multiplier = 2.0
	_parry_fan.material_override = fan_mat
	_parry_fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parry_fan.visible = false
	_visual.add_child(_parry_fan)

	# 발밑 그림자: 탑뷰에서 현재 높이를 읽게 해 준다 (GDD 3.3)
	_shadow = MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.5
	sm.bottom_radius = 0.5
	sm.height = 0.02
	_shadow.mesh = sm
	var shm := StandardMaterial3D.new()
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.albedo_color = Color(0, 0, 0, 0.55)
	_shadow.material_override = shm
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)

	# 스태미나(벽 점프·대시 공용): 발밑의 점 3개 (GDD 8.2)
	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = Color(1, 1, 1)
	for i in stamina_max:
		var dot := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.1
		sp.height = 0.2
		dot.mesh = sp
		dot.material_override = dot_mat
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.top_level = true
		add_child(dot)
		_dots.append(dot)


func _update_visual(delta: float, input_dir: Vector3) -> void:
	var aim := Vector3.ZERO
	if camera_rig and camera_rig.has_method("get_aim_direction"):
		aim = camera_rig.get_aim_direction(global_position)
	if aim.length() > 0.1:
		facing = aim.normalized()
	elif input_dir.length() > 0.1:
		facing = input_dir.normalized()
	_visual.rotation.y = atan2(-facing.x, -facing.z)

	var target_scale_y := 0.55 if state == State.SLIDE else 1.0
	var target_scale_z := 1.6 if state == State.DASH else 1.0  # 대시 중 앞뒤로 늘어나는 표시
	var k := 1.0 - exp(-20.0 * delta)
	_visual.scale.y = lerpf(_visual.scale.y, target_scale_y, k)
	_visual.scale.z = lerpf(_visual.scale.z, target_scale_z, k)

	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.2, global_position + Vector3.DOWN * 60.0)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_shadow.visible = false
	else:
		var ground: Vector3 = hit["position"]
		var height := global_position.y - ground.y
		var s := clampf(1.0 - height / 12.0, 0.4, 1.0)
		_shadow.visible = true
		_shadow.global_position = ground + Vector3.UP * 0.02
		_shadow.scale = Vector3(s, 1.0, s)

	for i in _dots.size():
		var dot := _dots[i]
		dot.visible = i < stamina_pips()
		dot.global_position = global_position + Vector3((i - 1) * 0.3, 0.08, 0.75)

	# 고속 잔상: 흰 반투명 실루엣이 짧게 남았다 사라진다 (블룸으로 살짝 번짐)
	if state == State.DASH or horizontal_speed() >= afterimage_speed:
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = afterimage_interval
			_spawn_afterimage()


func _spawn_afterimage() -> void:
	if get_parent() == null:
		return
	var ghost := MeshInstance3D.new()
	ghost.mesh = _body_mesh_node.mesh
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.35)
	m.emission_enabled = true
	m.emission = Color(1, 1, 1)
	m.emission_energy_multiplier = 1.5
	ghost.material_override = m
	get_parent().add_child(ghost)
	ghost.global_transform = _body_mesh_node.global_transform
	var tw := ghost.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, afterimage_life)
	tw.tween_callback(ghost.queue_free)


## -Z 방향을 중심으로 펼쳐진 수평 부채꼴 메시
func _make_fan_mesh(radius: float, angle: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 12
	for i in steps:
		var a0 := -angle * 0.5 + angle * i / steps
		var a1 := -angle * 0.5 + angle * (i + 1) / steps
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a0), 0.0, -cos(a0)) * radius)
		st.add_vertex(Vector3(sin(a1), 0.0, -cos(a1)) * radius)
	return st.commit()


func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m
