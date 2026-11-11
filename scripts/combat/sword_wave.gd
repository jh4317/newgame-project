extends Area3D
## 검기: 검을 휘두를 때 앞으로 날아가는 초승달 모양의 베기 파동.
## 적을 관통하며(적마다 한 번씩), 벽에 닿으면 사라진다. 흰색 발광 + 블룸 (GDD 8.3)

signal hit_enemy(enemy: Node, killed: bool)

var velocity := Vector3.ZERO
var damage := 20.0
var big := false
var life := 0.7
var owner_body: Node = null
var _hit := {}
var _max_life := 0.7
var _mat: StandardMaterial3D
var _mesh: MeshInstance3D


## add_child 전에 호출 (부모가 원점에 있다고 가정)
## already_hit: 같은 휘두르기의 근접 판정에 이미 맞은 적은 검기로 또 맞지 않게 한다
func setup(pos: Vector3, dir: Vector3, speed: float, distance: float, dmg: float,
		is_big: bool, from: Node, already_hit: Array) -> void:
	position = pos
	velocity = dir.normalized() * speed
	life = distance / speed
	_max_life = life
	damage = dmg
	big = is_big
	owner_body = from
	for e in already_hit:
		_hit[e.get_instance_id()] = true
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.01:
		basis = Basis.looking_at(dir.normalized(), Vector3.UP)


func _ready() -> void:
	add_to_group("player_wave")
	var s := 1.3 if big else 1.0
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.6 * s, 1.4, 0.8)
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)

	_mesh = MeshInstance3D.new()
	_mesh.mesh = _make_crescent(1.6 * s, deg_to_rad(110.0), 0.45 * s)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(1, 1, 1, 0.9)
	_mat.emission_enabled = true
	_mat.emission = Color(1, 1, 1)
	_mat.emission_energy_multiplier = 5.0 if big else 3.5
	_mesh.material_override = _mat
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	life -= delta
	_mat.albedo_color.a = clampf(life / (_max_life * 0.35), 0.0, 0.9)  # 끝에서 서서히 사라짐
	if life <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body == owner_body or body.is_in_group("player"):
		return
	if body.is_in_group("enemy"):
		var id := body.get_instance_id()
		if _hit.has(id):
			return
		_hit[id] = true
		var killed: bool = body.call("take_damage", damage)
		hit_enemy.emit(body, killed)
		return
	queue_free()  # 벽·바닥·기둥


## -Z 쪽으로 볼록한 초승달 리본 (가운데 두껍고 끝으로 갈수록 얇다)
func _make_crescent(radius: float, angle: float, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 16
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for i in steps + 1:
		var u := float(i) / steps            # 0..1
		var th := -angle * 0.5 + angle * u
		var t := thickness * sin(u * PI)       # 끝은 0, 가운데 최대
		outer.append(Vector3(sin(th) * radius, 0.0, radius - cos(th) * radius))
		var r_in := radius - t
		inner.append(Vector3(sin(th) * r_in, 0.0, radius - cos(th) * r_in))
	for i in steps:
		st.add_vertex(outer[i])
		st.add_vertex(outer[i + 1])
		st.add_vertex(inner[i])
		st.add_vertex(inner[i])
		st.add_vertex(outer[i + 1])
		st.add_vertex(inner[i + 1])
	return st.commit()
