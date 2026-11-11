extends Area3D
## 적이 쏘는 탄. 패링하면 되돌아가 적에게 대미지를 준다.
## - 패링 가능 탄: 흰색 발광 (GDD 3.1)
## - 패링 불가 탄: 붉은색 발광. 붉은색은 이 용도로만 쓴다 (GDD 8.3)

const RADIUS := 0.3

var velocity := Vector3.ZERO
var damage := 20.0
var parryable := true
var reflected := false
var shooter: Node = null
var life := 6.0

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D


## add_child 전에 호출한다 (부모가 원점에 있다고 가정해 position = 월드 좌표)
func setup(pos: Vector3, vel: Vector3, dmg: float, can_parry: bool, from: Node) -> void:
	position = pos
	velocity = vel
	damage = dmg
	parryable = can_parry
	shooter = from


func _ready() -> void:
	add_to_group("projectile")
	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)

	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	_mesh.mesh = sm
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.emission_enabled = true
	_mesh.material_override = _mat
	add_child(_mesh)
	_apply_color()


## 패링 성공 시 플레이어가 호출한다
func reflect(dir: Vector3, speed_mul: float, damage_mul: float) -> void:
	velocity = dir.normalized() * velocity.length() * speed_mul
	damage *= damage_mul
	reflected = true
	life = 4.0
	_mesh.scale = Vector3.ONE * 1.4
	_apply_color()


func _apply_color() -> void:
	var c := Color(1.0, 1.0, 1.0) if parryable else Color(1.0, 0.12, 0.1)
	_mat.albedo_color = c
	_mat.emission = c
	_mat.emission_energy_multiplier = 6.0 if reflected else 3.0  # 블룸으로 번지게


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	life -= delta
	if life <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body == shooter and not reflected:
		return
	if body.is_in_group("player"):
		if reflected:
			return
		body.call("take_damage", damage)
		queue_free()
	elif body.is_in_group("enemy"):
		if not reflected:
			return  # 적끼리는 맞지 않는다
		get_tree().call_group("hit_fx", "reflect_hit", global_position, velocity.normalized(), damage)
		body.call("take_damage", damage)
		queue_free()
	else:
		queue_free()  # 벽·바닥
