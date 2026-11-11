extends Area3D
## 검기: 검을 휘두를 때 앞으로 날아가는 초승달 모양의 붓질.
## 적을 관통하며(적마다 한 번씩), 벽에 닿으면 사라진다.
## 모양: 거친 붓으로 그은 먹 초승달(갈라진 붓결) + 바깥 가장자리의 가는 흰 빛줄기 (GDD 8.3 흑백 대비).
## 날아가는 동안 뒤로 먹방울이 흩뿌려지고, 지나간 바닥에 먹 자국이 잠시 남는다.

signal hit_enemy(enemy: Node, killed: bool)

const INK := Color(0.02, 0.02, 0.02)
const SPLAT_EVERY := 1.6   # 이 거리마다 바닥에 먹 자국 (m)

var velocity := Vector3.ZERO
var damage := 20.0
var big := false
var size_mul := 1.0
var life := 0.7
var owner_body: Node = null
var _hit := {}
var _max_life := 0.7
var _ink_mat: StandardMaterial3D
var _edge_mat: StandardMaterial3D
var _spray: CPUParticles3D
var _travel := 0.0
var _splat_mesh: SphereMesh


## add_child 전에 호출 (부모가 원점에 있다고 가정)
## already_hit: 같은 휘두르기의 근접 판정에 이미 맞은 적은 검기로 또 맞지 않게 한다
## size: 검기 크기 배율 (붓의 먹 단계, sword.gd)
func setup(pos: Vector3, dir: Vector3, speed: float, distance: float, dmg: float,
		is_big: bool, from: Node, already_hit: Array, size := 1.0) -> void:
	position = pos
	velocity = dir.normalized() * speed
	life = distance / speed
	_max_life = life
	damage = dmg
	big = is_big
	size_mul = size
	owner_body = from
	for e in already_hit:
		_hit[e.get_instance_id()] = true
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.01:
		basis = Basis.looking_at(dir.normalized(), Vector3.UP)


func _ready() -> void:
	add_to_group("player_wave")
	var s := (1.3 if big else 1.0) * size_mul
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.6 * s, 1.4, 0.8)
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)

	var radius := 1.6 * s
	var arc := deg_to_rad(110.0)
	# 먹 몸통: 갈라진 붓결
	var body := MeshInstance3D.new()
	body.mesh = _make_brush(radius, arc, 1.25 * s)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ink_mat = StandardMaterial3D.new()
	_ink_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ink_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ink_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ink_mat.albedo_color = Color(INK.r, INK.g, INK.b, 1.0)
	_ink_mat.render_priority = 1
	body.material_override = _ink_mat
	add_child(body)
	# 바깥 가장자리 흰 빛줄기: 먹 위에 가늘게 (블룸으로 번짐)
	var edge := MeshInstance3D.new()
	edge.mesh = _make_edge(radius + 0.02, arc * 0.9, 0.09 * s)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_edge_mat = StandardMaterial3D.new()
	_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_edge_mat.albedo_color = Color(1, 1, 1, 1)
	_edge_mat.emission_enabled = true
	_edge_mat.emission = Color(1, 1, 1)
	_edge_mat.emission_energy_multiplier = 5.0 if big else 3.5
	_edge_mat.render_priority = 2
	edge.material_override = _edge_mat
	edge.position.y = 0.01
	add_child(edge)

	_spray = _make_spray(s)
	add_child(_spray)
	_splat_mesh = SphereMesh.new()
	_splat_mesh.radius = 1.0
	_splat_mesh.height = 2.0
	_splat_mesh.radial_segments = 8
	_splat_mesh.rings = 4


func _physics_process(delta: float) -> void:
	var step := velocity * delta
	global_position += step
	life -= delta
	var a := clampf(life / (_max_life * 0.35), 0.0, 1.0)  # 끝에서 서서히 사라짐
	_ink_mat.albedo_color.a = a * 0.95
	_edge_mat.albedo_color.a = a
	_travel += step.length()
	if _travel >= SPLAT_EVERY:
		_travel = 0.0
		_floor_splat()
	if life <= 0.0:
		_detach_spray()
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
	_detach_spray()
	queue_free()  # 벽·바닥·기둥


## 사라질 때 이미 흩뿌린 먹방울은 남아서 마저 떨어지게 한다
func _detach_spray() -> void:
	if _spray == null or not is_instance_valid(_spray) or get_parent() == null:
		return
	var xf := _spray.global_transform
	remove_child(_spray)
	get_parent().add_child(_spray)
	_spray.global_transform = xf
	_spray.emitting = false
	get_tree().create_timer(_spray.lifetime + 0.1).timeout.connect(_spray.queue_free)
	_spray = null


## 지나간 바닥에 작은 먹 자국 (아래 3 m 안에 바닥이 있을 때)
func _floor_splat() -> void:
	var from := global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0)
	q.collide_with_areas = false
	var ex: Array[RID] = []
	for e in get_tree().get_nodes_in_group("enemy"):
		ex.append((e as CollisionObject3D).get_rid())
	if owner_body is CollisionObject3D:
		ex.append((owner_body as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or get_parent() == null:
		return
	var m := MeshInstance3D.new()
	m.mesh = _splat_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(INK.r, INK.g, INK.b, 0.85)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(m)
	var r := randf_range(0.18, 0.32) * size_mul
	m.global_position = (hit["position"] as Vector3) + Vector3.UP * 0.02 \
		+ global_transform.basis.x * randf_range(-0.8, 0.8) * size_mul
	m.rotation.y = randf() * TAU
	m.scale = Vector3(r * randf_range(1.0, 1.8), 0.01, r)
	var tw := m.create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.tween_callback(m.queue_free)


## 날아가는 동안 뒤로 흩뿌려지는 먹방울
func _make_spray(s: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = INK
	p.material_override = m
	p.local_coords = false
	p.amount = int(28 * s)
	p.lifetime = 0.45
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1.3 * s, 0.1, 0.2)
	p.direction = Vector3(0, 0.4, 1)  # 뒤쪽(+Z)으로
	p.spread = 35.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -16, 0)
	p.scale_amount_min = 0.6 * s
	p.scale_amount_max = 1.6 * s
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = c
	p.position = Vector3(0, 0, 0.3 * s)
	p.emitting = true
	return p


## -Z 쪽으로 볼록한 거친 붓 초승달. 붓결(band) 여러 가닥으로 나눠, 가닥 사이 틈과
## 가닥마다 다른 길이로 갈라진 마른 붓 자국처럼 보이게 한다. 앞쪽 끝(u = 1)이 굵다.
func _make_brush(radius: float, angle: float, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 20
	var bands := 6
	for b in bands:
		# 가닥 사이 틈: 가닥 폭의 0~22%를 비운다 (바깥 가닥은 틈 없이 꽉 차게)
		var gap := 0.0 if b == 0 else randf_range(0.05, 0.22)
		var v0 := (float(b) + gap) / bands
		var v1 := float(b + 1) / bands
		# 안쪽 가닥일수록 꼬리 쪽에서 일찍 끊긴다 (마른 붓)
		var start_u := clampf(randf_range(0.0, 0.25) + 0.08 * b, 0.0, 0.6)
		for i in steps:
			var u0 := float(i) / steps
			var u1 := float(i + 1) / steps
			if u1 <= start_u:
				continue
			var quad := []
			for corner in [[u0, v0], [u1, v0], [u0, v1], [u1, v1]]:
				var u: float = maxf(corner[0], start_u)
				var v: float = corner[1]
				var th := -angle * 0.5 + angle * u
				var t := thickness * sin(u * PI) * (0.45 + 0.55 * u)  # 앞쪽이 굵다
				var r := radius - t * v
				quad.append(Vector3(sin(th) * r, 0.0, radius - cos(th) * r))
			for k in [0, 1, 2, 2, 1, 3]:
				st.add_vertex(quad[k])
	return st.commit()


## 바깥 가장자리의 가는 빛줄기 (가운데만 두껍다)
func _make_edge(radius: float, angle: float, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 16
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for i in steps + 1:
		var u := float(i) / steps
		var th := -angle * 0.5 + angle * u
		var t := thickness * sin(u * PI)
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
