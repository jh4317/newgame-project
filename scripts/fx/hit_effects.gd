extends Node3D
## 적중·처치 이펙트 (GDD 8.3: 로우폴리가 아닌 화려한 흑백 + 블룸, 붉은색은 쓰지 않음)
## 만화풍의 과장된 타격 연출을 목표로 한다: 붓터치 베기 자국(흰 심 + 검은 외곽선),
## 크게 튀어나오는 대미지 숫자, 바닥에 튀는 먹물, 화면 연출(화면 베기·줌 블러)은 combat_fx/screen_slash가 맡는다.
## 플레이어 공격 종류마다 모양이 다르다:
##   근접 베기   : 굵은 붓터치 자국 1줄 + 불꽃 + 충격파 고리 + 숫자
##   3타 마무리  : 큰 X자 붓터치 + 큰 충격파 + 섬광 + 불꽃 많이 + 검은 연기 + 큰 숫자
##   검기        : 얇고 긴 붓터치 + 불꽃 조금 + 작은 숫자
##   반사탄      : 섬광 구 + 방사형 가시 + 불꽃 + 큰 숫자
##   처치        : 로우폴리 파편 + 큰 섬광 + 검은 연기 + 바닥 충격파 + 바닥 먹물
## 이펙트 노드는 스스로 사라진다. 히트스톱 중에는 함께 멈춘다(time_scale 영향).

const WHITE := Color(1, 1, 1)
const INK := Color(0.02, 0.02, 0.02)


func _ready() -> void:
	add_to_group("hit_fx")


# ---------------------------------------------------------------- 공격 종류별

func melee_hit(pos: Vector3, dir: Vector3, damage := 40.0) -> void:
	_brush(pos, dir, 3.6, 0.55, 0.2, 30.0)
	_sparks(pos, dir, 16, 9.0, 18.0, 0.32, 50.0)
	_ring(pos, 2.0, 0.2)
	damage_number(pos, damage, false)


func finisher_hit(pos: Vector3, dir: Vector3, damage := 60.0) -> void:
	_brush(pos, dir, 5.5, 0.8, 0.3, 40.0)
	_brush(pos, dir, 5.5, 0.8, 0.3, -40.0)
	_sparks(pos, dir, 32, 11.0, 24.0, 0.45, 70.0)
	_ring(pos, 4.0, 0.3)
	_flash(pos, 2.0, 0.14)
	_smoke(pos, 8, 0.7)
	damage_number(pos, damage, true)


func wave_hit(pos: Vector3, dir: Vector3, damage := 20.0) -> void:
	_brush(pos, dir, 4.0, 0.22, 0.15, 90.0)  # 진행 방향에 수직인 얇은 자국
	_sparks(pos, dir, 8, 7.0, 13.0, 0.25, 35.0)
	damage_number(pos, damage, false)


func reflect_hit(pos: Vector3, dir: Vector3, damage := 40.0) -> void:
	_flash(pos, 2.0, 0.16)
	for i in 8:
		_brush(pos, dir, 2.0, 0.16, 0.16, i * 45.0, 1.0)  # 방사형 가시
	_sparks(pos, dir, 20, 9.0, 20.0, 0.36, 180.0)
	damage_number(pos, damage, true)


func enemy_killed(pos: Vector3, size: float, elite: bool) -> void:
	var center := pos + Vector3.UP * size * 0.5
	_shards(center, 22 if elite else 14, size)
	_flash(center, 3.2 if elite else 2.4, 0.2)
	_smoke(center, 12 if elite else 8, 1.0)
	_ring(pos + Vector3.UP * 0.1, 6.0 if elite else 4.5, 0.4)
	_ink_splat(pos, 9 if elite else 6, 1.6 if elite else 1.2)


## 먹 폭발: 쌓인 먹이 한꺼번에 터진다. 검은 먹방울이 사방으로 튀고, 바닥에 큰 먹 자국,
## 흰 섬광과 고리, "먹 폭발" 문구와 추가 피해 숫자
func ink_burst(pos: Vector3, base_pos: Vector3, bonus: float) -> void:
	_ink_droplets(pos, 40, 13.0)
	_ink_splat(base_pos, 10, 1.8)
	_flash(pos, 2.6, 0.16)
	_ring(base_pos + Vector3.UP * 0.1, 5.5, 0.35)
	_brush(pos, Vector3(1, 0, 0), 6.0, 0.9, 0.3, 0.0)
	_pop_label(pos + Vector3.UP * 1.6, "먹 폭발", 110, 0.8)
	_pop_label(pos + Vector3(0.0, 0.6, 0.0), "+" + str(int(round(bonus))), 150, 0.8)


## 먹 끌어당김: 중심으로 검은 고리가 오므라들고, 끌려오는 적마다 먹 사슬이 이어졌다 끊긴다
func ink_pull(center: Vector3, from_points: Array) -> void:
	_implode(center + Vector3.UP * 1.2, 9.0, 0.28)
	_flash(center + Vector3.UP * 1.2, 2.2, 0.18)
	for p in from_points:
		_tether(center + Vector3.UP * 1.2, (p as Vector3) + Vector3.UP * 1.2, 0.4)
	_ink_droplets(center + Vector3.UP * 1.2, 24, 9.0)
	_pop_label(center + Vector3.UP * 3.4, "먹 끌어당김", 100, 0.9)


## 회복 표시 (플레이어 머리 위)
func heal_text(pos: Vector3, amount: float) -> void:
	_pop_label(pos + Vector3(0.6, 2.0, 0.0), "+%d 먹" % int(round(amount)), 80, 0.8)


## 패링 성공 문구 (플레이어 머리 위)
func parry_text(pos: Vector3) -> void:
	_pop_label(pos + Vector3.UP * 2.4, "PARRY", 120, 0.7)


## 크게 튀어나왔다가 떠오르며 사라지는 대미지 숫자 (흰 글자 + 두꺼운 검은 외곽선)
func damage_number(pos: Vector3, damage: float, big: bool) -> void:
	var jitter := Vector3(randf_range(-0.6, 0.6), randf_range(0.3, 0.9), randf_range(-0.3, 0.3))
	_pop_label(pos + jitter, str(int(round(damage))), 130 if big else 84, 0.6)


# ---------------------------------------------------------------- 조각들

## 붓터치 베기 자국: 가운데가 두껍고 끝이 뾰족한 초승달. 흰 심 + 검은 외곽선 두 겹.
## 확 그어졌다가 얇아지며 사라진다. 깊이 테스트 없이 항상 위에 그린다.
## angle_deg: 공격 방향 기준 회전, offset: 중심에서 바깥쪽으로 밀어내기(가시용)
func _brush(pos: Vector3, dir: Vector3, length: float, thickness: float, life: float,
		angle_deg: float, offset := 0.0) -> void:
	var root := Node3D.new()
	add_child(root)
	var yaw := atan2(-dir.x, -dir.z) + deg_to_rad(angle_deg)
	root.global_position = pos
	root.rotation = Vector3(deg_to_rad(-30.0), yaw, 0.0)  # 기울여 탑뷰·숄더뷰 모두에서 보이게
	if offset > 0.0:
		root.global_position += root.global_transform.basis.x * offset

	var arc := deg_to_rad(70.0)
	var radius := length / (2.0 * sin(arc * 0.5))
	var outline := MeshInstance3D.new()
	outline.mesh = _make_crescent(radius, arc * 1.06, thickness * 1.9)
	var out_mat := StandardMaterial3D.new()
	out_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	out_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	out_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	out_mat.no_depth_test = true
	out_mat.render_priority = 1
	out_mat.albedo_color = INK
	outline.material_override = out_mat
	outline.position = Vector3(0, 0, -thickness * 0.35)
	root.add_child(outline)

	var core := MeshInstance3D.new()
	core.mesh = _make_crescent(radius, arc, thickness)
	var core_mat := _glow_mat(7.0)
	core_mat.no_depth_test = true
	core_mat.render_priority = 2
	core.material_override = core_mat
	root.add_child(core)
	for m in [outline, core]:
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# 세로로 확 그어진 뒤(0.25) 두께가 얇아지며 사라진다
	root.scale = Vector3(0.1, 1.0, 1.4)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3(1.15, 1.0, 1.0), life * 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector3(1.25, 1.0, 0.05), life * 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(out_mat, "albedo_color:a", 0.0, life * 0.75)
	tw.tween_callback(root.queue_free)


## 바닥 먹물: 납작한 검은 덩어리들이 확 번졌다가 잠시 남은 뒤 옅어진다
func _ink_splat(pos: Vector3, count: int, spread: float) -> void:
	for i in count:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 8
		sm.rings = 4
		m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(INK.r, INK.g, INK.b, 0.92)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		var r := randf_range(0.35, 1.0) * spread * (1.4 if i == 0 else 1.0)
		var off := Vector3.ZERO if i == 0 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(0.8, 2.6) * spread
		m.global_position = pos + off + Vector3.UP * (0.02 + i * 0.002)
		var final_scale := Vector3(r * randf_range(0.8, 1.3), 0.01, r * randf_range(0.6, 1.0))
		m.rotation.y = randf() * TAU
		m.scale = final_scale * 0.2
		var tw := m.create_tween()
		tw.tween_property(m, "scale", final_scale, 0.08).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_interval(1.2)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
		tw.tween_callback(m.queue_free)


## 튀어나오는 글자: 크게 → 원래 크기, 떠오르며 마지막에 사라짐
func _pop_label(pos: Vector3, text: String, size: int, life: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = int(size * 0.22)
	l.modulate = WHITE
	l.outline_modulate = INK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 3
	l.outline_render_priority = 2
	l.pixel_size = 0.01
	add_child(l)
	l.global_position = pos
	l.scale = Vector3.ONE * 1.8
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "global_position", pos + Vector3.UP * 1.2, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, life * 0.35).set_delay(life * 0.65)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, life * 0.35).set_delay(life * 0.65)
	tw.tween_callback(l.queue_free)


## -Z 쪽으로 볼록한 초승달 리본 (가운데 두껍고 끝으로 갈수록 뾰족). 중심을 원점 근처로 맞춘다.
func _make_crescent(radius: float, angle: float, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 20
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	var sag := radius - cos(angle * 0.5) * radius  # 초승달이 원점을 가로지르도록 보정
	for i in steps + 1:
		var u := float(i) / steps
		var th := -angle * 0.5 + angle * u
		var t := thickness * pow(sin(u * PI), 0.8)
		outer.append(Vector3(sin(th) * radius, 0.0, radius - cos(th) * radius - sag * 0.5))
		var r_in := radius - t
		inner.append(Vector3(sin(th) * r_in, 0.0, radius - cos(th) * r_in - sag * 0.5))
	for i in steps:
		st.add_vertex(outer[i])
		st.add_vertex(outer[i + 1])
		st.add_vertex(inner[i])
		st.add_vertex(inner[i])
		st.add_vertex(outer[i + 1])
		st.add_vertex(inner[i + 1])
	return st.commit()


## 충격파 고리: 바닥과 나란한 얇은 고리가 퍼진다
func _ring(pos: Vector3, radius: float, life: float) -> void:
	var m := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 4
	m.mesh = tm
	var mat := _glow_mat(4.0)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = pos
	m.scale = Vector3.ONE * 0.2
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3(radius, 1.0, radius), life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(m.queue_free)


## 섬광: 아주 밝은 구가 부풀었다 사라진다 (블룸으로 크게 번짐)
func _flash(pos: Vector3, radius: float, life: float) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 6
	m.mesh = sm
	var mat := _glow_mat(10.0)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = pos
	m.scale = Vector3.ONE * 0.3
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3.ONE * radius, life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(m.queue_free)


## 불꽃: 속도 방향으로 늘어난 흰 조각들이 튀었다 줄어든다
func _sparks(pos: Vector3, dir: Vector3, count: int, speed: float, max_speed: float,
		life: float, spread_deg: float) -> void:
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.45, 0.05)
	p.mesh = bm
	p.material_override = _glow_mat(5.0)
	p.particle_flag_align_y = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = life
	p.direction = Vector3(dir.x, 0.25, dir.z).normalized() if dir.length() > 0.1 else Vector3.UP
	p.spread = spread_deg
	p.initial_velocity_min = speed
	p.initial_velocity_max = max_speed
	p.gravity = Vector3(0, -18, 0)
	p.scale_amount_curve = _shrink_curve()
	_emit_once(p, pos, life)


## 검은 연기: 흰 이펙트와 대비되는 검은 덩어리가 천천히 퍼지며 옅어진다
func _smoke(pos: Vector3, count: int, life: float) -> void:
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	p.material_override = mat
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.02, 0.02, 0.85))
	g.set_color(1, Color(0.02, 0.02, 0.02, 0.0))
	p.color_ramp = g
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = count
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 90.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, 1.5, 0)
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.8
	_emit_once(p, pos, life)


## 오므라드는 고리: 넓은 검은 고리가 중심으로 확 빨려 든다 (끌어당김)
func _implode(pos: Vector3, radius: float, life: float) -> void:
	for i in 2:
		var m := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.88
		tm.outer_radius = 1.0
		tm.rings = 32
		tm.ring_segments = 4
		m.mesh = tm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(INK.r, INK.g, INK.b, 0.0)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		m.global_position = pos
		var r := radius * (1.0 - 0.3 * i)
		m.scale = Vector3(r, 1.0, r)
		var tw := m.create_tween()
		tw.tween_interval(0.05 * i)
		tw.tween_property(mat, "albedo_color:a", 0.9, 0.04)
		tw.tween_property(m, "scale", Vector3(0.3, 1.0, 0.3), life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		tw.tween_callback(m.queue_free)


## 먹 사슬: 두 점을 잇는 굵은 검은 줄(가운데 흰 심)이 잠깐 이어졌다 가늘어지며 끊긴다
func _tether(a: Vector3, b: Vector3, life: float) -> void:
	var length := a.distance_to(b)
	if length < 0.1:
		return
	var root := Node3D.new()
	add_child(root)
	root.global_position = (a + b) * 0.5
	root.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	for layer in 2:
		var ink := layer == 0
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.22, length) if ink else Vector3(0.06, 0.06, length)
		m.mesh = bm
		var mat := _glow_mat(4.0) if not ink else StandardMaterial3D.new()
		if ink:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = INK
		mat.no_depth_test = true
		mat.render_priority = 1 if ink else 2
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(m)
	var tw := root.create_tween()
	tw.tween_interval(life * 0.4)
	tw.tween_property(root, "scale", Vector3(0.05, 0.05, 1.0), life * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)


## 먹방울: 검은 방울이 사방으로 튀었다가 떨어지며 작아진다
func _ink_droplets(pos: Vector3, count: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = INK
	p.material_override = mat
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = 0.7
	p.direction = Vector3.UP
	p.spread = 100.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -24, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 2.0
	p.scale_amount_curve = _shrink_curve(0.5)
	_emit_once(p, pos, 0.7)


## 처치 파편: 회색·흰색 로우폴리 조각이 사방으로 튀고 떨어진다
func _shards(pos: Vector3, count: int, size: float) -> void:
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.28 * size / 2.2
	p.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.85, 0.88)
	mat.emission_enabled = true
	mat.emission = WHITE
	mat.emission_energy_multiplier = 1.2
	p.material_override = mat
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 13.0
	p.gravity = Vector3(0, -28, 0)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	p.scale_amount_curve = _shrink_curve(0.6)
	_emit_once(p, pos, 0.9)


func _emit_once(p: CPUParticles3D, pos: Vector3, life: float) -> void:
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.2).timeout.connect(p.queue_free)


func _glow_mat(energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = WHITE
	mat.emission_enabled = true
	mat.emission = WHITE
	mat.emission_energy_multiplier = energy
	return mat


## 1 → hold까지 유지 → 0 으로 줄어드는 크기 곡선
func _shrink_curve(hold := 0.2) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(hold, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	return c
