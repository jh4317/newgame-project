extends Node3D
## 대안 시점: 숄더뷰 3인칭 카메라 (GDD 4.4).
## 마우스로 카메라를 돌리고, 이동은 카메라 기준, 조준은 화면 중앙 방향.
## SpringArm3D로 벽에 카메라가 박히지 않게 한다.

@export var mouse_sensitivity := 0.0025
@export var arm_length := 4.5
@export var shoulder_offset := 0.7
@export var pivot_height := 1.7
@export var base_fov := 70.0
@export var fov_boost := 12.0
@export var shake_strength := 1.0
@export var shake_max_offset := 0.25
@export var shake_max_roll_deg := 2.0

var target: CharacterBody3D
var camera: Camera3D
var active := false
var _fov_smoothed := 70.0
var _fov_kick := 0.0
var _trauma := 0.0
var _noise := FastNoiseLite.new()
var _t := 0.0
var _yaw := 0.0
var _pitch := -0.3
var _pivot: Node3D
var _arm: SpringArm3D


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.spring_length = arm_length
	_arm.margin = 0.2
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	_arm.shape = probe
	_pivot.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = base_fov
	camera.far = 300.0
	_arm.add_child(camera)
	_fov_smoothed = base_fov
	_noise.frequency = 2.0


func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func fov_kick(amount: float) -> void:
	_fov_kick = maxf(_fov_kick, amount)


func activate(on: bool) -> void:
	active = on
	camera.current = on
	if on:
		if target:
			_arm.add_excluded_object(target.get_rid())
			_yaw = _yaw_from_facing()  # 전환 순간 캐릭터가 보던 방향을 이어받는다
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func mode_name() -> String:
	return "숄더뷰"


func get_move_basis() -> Basis:
	return Basis(Vector3.UP, _yaw)


func get_aim_direction(_from: Vector3) -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _yaw_from_facing() -> float:
	var f: Vector3 = target.get("facing")
	return atan2(-f.x, -f.z)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.2, 0.5)
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if target == null:
		return
	global_position = target.global_position + Vector3(0.0, pivot_height, 0.0)
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_arm.position = Vector3(shoulder_offset, 0.0, 0.0)
	var speed := Vector2(target.velocity.x, target.velocity.z).length()
	var speed_t := clampf((speed - 12.0) / 8.0, 0.0, 1.0)
	_fov_smoothed = lerpf(_fov_smoothed, base_fov + fov_boost * speed_t, 1.0 - exp(-5.0 * delta))
	_fov_kick = move_toward(_fov_kick, 0.0, 30.0 * delta)
	camera.fov = _fov_smoothed + _fov_kick

	_t += delta
	_trauma = maxf(0.0, _trauma - 1.6 * delta)
	var s := _trauma * _trauma * shake_strength
	camera.h_offset = _noise.get_noise_2d(_t * 40.0, 0.0) * shake_max_offset * s
	camera.v_offset = _noise.get_noise_2d(0.0, _t * 40.0) * shake_max_offset * s
	camera.rotation.z = deg_to_rad(shake_max_roll_deg) * _noise.get_noise_2d(_t * 30.0, 50.0) * s
