extends Node3D
## 고정 사선 탑뷰 카메라 (GDD 4.1).
## - 내려다보는 각도 약 55°, 회전 없음
## - 이동 방향과 조준 방향으로 시점이 앞서 나간다 (고속일수록 더 멀리)
## - 고속에서 시야(FOV)를 살짝 넓혀 속도감을 준다
## 조준은 마우스 커서를 플레이어 높이의 평면에 투영해 구한다(트윈 스틱 방식).

@export var pitch_deg := 55.0
@export var distance := 26.0
@export var lead_from_velocity := 0.3
@export var lead_max := 7.0
@export var aim_lead := 0.2
@export var follow_sharpness := 8.0
@export var base_fov := 45.0
@export var fov_boost := 10.0
@export var shake_strength := 1.0     # 설정에서 줄일 수 있게 (GDD 8.2)
@export var shake_max_offset := 0.6   # 흔들림 최대 이동량 (m)

var target: CharacterBody3D
var camera: Camera3D
var _focus := Vector3.ZERO
var _aim_point := Vector3.ZERO
var _fov_smoothed := 45.0
var _fov_kick := 0.0
var _trauma := 0.0
var _noise := FastNoiseLite.new()
var _t := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = base_fov
	camera.far = 300.0
	add_child(camera)
	_fov_smoothed = base_fov
	_noise.frequency = 2.0


## 카메라 흔들림. amount 0~1을 누적하고 시간이 지나면 줄어든다 (흔들림 = trauma²)
func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


## 순간적으로 시야를 넓혔다가 돌아온다 (대시 등). 음수면 확 당겨 들어가는 줌 펀치 (큰 타격)
func fov_kick(amount: float) -> void:
	if absf(amount) > absf(_fov_kick):
		_fov_kick = amount


func activate(on: bool) -> void:
	camera.current = on
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if target:
			_focus = target.global_position


func mode_name() -> String:
	return "탑뷰"


## 탑뷰는 화면 위쪽 = 월드 -Z(북쪽)로 고정이라 입력을 그대로 쓴다.
func get_move_basis() -> Basis:
	return Basis.IDENTITY


func get_aim_direction(from: Vector3) -> Vector3:
	var d := _aim_point - from
	d.y = 0.0
	return d.normalized() if d.length() > 0.3 else Vector3.ZERO


func _process(delta: float) -> void:
	if target == null:
		return
	var pos := target.global_position

	# 마우스 커서 → 플레이어 허리 높이의 수평면
	var mouse := get_viewport().get_mouse_position()
	var plane := Plane(Vector3.UP, pos.y + 1.0)
	var hit = plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if hit != null:
		_aim_point = hit

	var vel := Vector3(target.velocity.x, 0.0, target.velocity.z)
	var lead := (vel * lead_from_velocity).limit_length(lead_max)
	var aim_offset := _aim_point - pos
	aim_offset.y = 0.0
	aim_offset = aim_offset.limit_length(10.0) * aim_lead

	var k := 1.0 - exp(-follow_sharpness * delta)
	_focus = _focus.lerp(pos + lead + aim_offset, k)

	var pitch := deg_to_rad(pitch_deg)
	camera.global_position = _focus + Vector3(0.0, sin(pitch), cos(pitch)) * distance
	camera.look_at(_focus, Vector3.UP)

	var speed_t := clampf((vel.length() - 12.0) / 8.0, 0.0, 1.0)
	_fov_smoothed = lerpf(_fov_smoothed, base_fov + fov_boost * speed_t, 1.0 - exp(-5.0 * delta))
	_fov_kick = move_toward(_fov_kick, 0.0, 30.0 * delta)
	camera.fov = _fov_smoothed + _fov_kick

	_t += delta
	_trauma = maxf(0.0, _trauma - 1.6 * delta)
	var s := _trauma * _trauma * shake_strength
	camera.h_offset = _noise.get_noise_2d(_t * 40.0, 0.0) * shake_max_offset * s
	camera.v_offset = _noise.get_noise_2d(0.0, _t * 40.0) * shake_max_offset * s
