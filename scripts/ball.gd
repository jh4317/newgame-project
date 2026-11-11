extends CharacterBody2D
## 자동으로 계속 튀는 공. 플레이어는 좌우만 조작한다.

signal died

const GRAVITY := 1500.0
const BOUNCE_SPEED := 620.0   # 튀어 오르는 높이 ≈ 128px (블록 약 2.6칸)
const ACCEL := 1400.0
const FRICTION := 1000.0
const MAX_SPEED := 240.0
const RADIUS := 14.0
const FALL_LIMIT_Y := 700.0

var _squash := 0.0  # 착지 순간 찌그러지는 연출용


func _ready() -> void:
	add_to_group("ball")
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)


func _physics_process(delta: float) -> void:
	var dir := Input.get_axis("ui_left", "ui_right")
	if Input.is_physical_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		dir += 1.0
	dir = clampf(dir, -1.0, 1.0)

	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * MAX_SPEED, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	velocity.y += GRAVITY * delta
	move_and_slide()

	if is_on_floor():
		velocity.y = -BOUNCE_SPEED
		_squash = 1.0

	_squash = move_toward(_squash, 0.0, delta * 6.0)
	queue_redraw()

	if position.y > FALL_LIMIT_Y:
		died.emit()


func _draw() -> void:
	var sx := 1.0 + 0.25 * _squash
	var sy := 1.0 - 0.25 * _squash
	draw_set_transform(Vector2(0, RADIUS * (1.0 - sy)), 0.0, Vector2(sx, sy))
	draw_circle(Vector2.ZERO, RADIUS, Color(0.35, 0.85, 1.0))
	draw_circle(Vector2(-4, -5), 4.0, Color(1, 1, 1, 0.8))
