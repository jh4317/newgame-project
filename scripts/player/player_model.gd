extends Node3D
## 플레이어 로우폴리 모델: '현대적 묵객' — 후드와 마스크, 짧은 코트, 목도리 (GDD 8.3)
## 각진 도형(사각뿔대)을 관절로 이어 붙인다. 발밑이 원점, -Z가 앞, +X가 오른쪽.
## 텍스처: 코드로 만든 32×32 픽셀 텍스처(옷감·먹 얼룩·가죽)를 필터 없이 로컬 트라이플래너로 입힌다 (GDD 8.3)
## 색: 짙은 남색 옷 + 색 바랜 미색 포인트 + 청록 바이저. 흰·검정(이펙트), 빨강(패링 불가 경고)은 피한다.
##
## 관절:
##   hips ─ leg_l/r(허벅지) ─ knee_l/r(정강이·장화)
##        ├ tail_l/r(코트 뒷자락) / flap_l/r(코트 옆자락)
##        └ torso ─ head(후드·마스크·바이저·후드 자락) / scarf(목도리 꼬리) / 등의 큰 붓 / shoulder_l/r ─ elbow_l/r
## animate()가 매 프레임 관절 각도를 정한다. 오른팔은 검 손잡이를 따라간다 (2본 IK).

const NAVY := Color(0.16, 0.22, 0.42)
const NAVY_DARK := Color(0.1, 0.12, 0.23)
const IVORY := Color(0.9, 0.86, 0.74)
const GLOVE := Color(0.14, 0.12, 0.13)
const BOOT := Color(0.1, 0.09, 0.1)
const MASK := Color(0.06, 0.07, 0.09)
const VISOR := Color(0.2, 0.9, 0.82)
const LEATHER := Color(0.32, 0.22, 0.15)
const WOOD := Color(0.36, 0.25, 0.16)
const INK := Color(0.07, 0.07, 0.1)

## 픽셀 텍스처: 32픽셀 한 장이 TEX_TILE m를 덮는다 (1픽셀 = 2.5 cm). 몸보다 크게 잡아 무늬 반복이 눈에 띄지 않게 한다
const TEX_SIZE := 32
const TEX_TILE := 0.8
static var _tex_cache := {}

const HIP_Y := 0.9
const THIGH := 0.42
const SHIN := 0.42
const UPPER_ARM := 0.3
const FOREARM := 0.28
## 검 손잡이: 검 회전축(sword._pivot) 기준 위치
const GRIP := Vector3(0.42, -0.02, -0.14)

var hips: Node3D
var torso: Node3D
var head: Node3D
var scarf: Node3D
var leg := [null, null]     # [왼, 오른]
var knee := [null, null]
var tail := [null, null]
var flap := [null, null]
var shoulder := [null, null]
var elbow := [null, null]
## 메시 목록 (잔상 만들 때 쓴다)
var meshes: Array[MeshInstance3D] = []

var _mats := {}
var _time := 0.0
## 큰 붓: 평소엔 등에 메고, 슬라이드하면 다리 밑으로 내려와 붓끝을 바닥에 대고 탄다 (먹 획을 긋는 모습)
var brush: Node3D
var _brush_back := Transform3D()   # 몸통 기준 등에 멘 자세
var _brush_ride := 0.0             # 0 = 등, 1 = 다리 밑


func _ready() -> void:
	_build()


# ---------------------------------------------------------------- 조립

func _build() -> void:
	hips = _joint(self, Vector3(0, HIP_Y, 0))
	_part(hips, _frustum(Vector2(0.34, 0.2), Vector2(0.32, 0.2), -0.1, 0.06), NAVY_DARK)

	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		# 다리: 허벅지 → 무릎 → 정강이·장화
		leg[i] = _joint(hips, Vector3(0.11 * side, -0.02, 0))
		_part(leg[i], _frustum(Vector2(0.12, 0.13), Vector2(0.16, 0.17), -THIGH, 0.0), NAVY_DARK)
		knee[i] = _joint(leg[i], Vector3(0, -THIGH, 0))
		_part(knee[i], _frustum(Vector2(0.1, 0.11), Vector2(0.12, 0.13), -SHIN + 0.08, 0.0), NAVY_DARK)
		_part(knee[i], _frustum(Vector2(0.13, 0.25), Vector2(0.12, 0.15), -SHIN - 0.02, -SHIN + 0.1), BOOT, Vector3(0, 0, -0.04))
		# 코트 뒷자락: 허리 뒤에서 두 갈래로 늘어진다
		tail[i] = _joint(hips, Vector3(0.1 * side, 0.06, 0.1))
		_part(tail[i], _frustum(Vector2(0.24, 0.03), Vector2(0.18, 0.03), -0.5, 0.0), NAVY, Vector3(0.02 * side, 0, 0))
		_part(tail[i], _frustum(Vector2(0.24, 0.035), Vector2(0.24, 0.035), -0.53, -0.49), IVORY, Vector3(0.02 * side, 0, 0))
		# 코트 옆자락: 앞이 트인 긴 코트처럼 다리 바깥을 덮는다
		flap[i] = _joint(hips, Vector3(0.2 * side, 0.06, -0.02))
		_part(flap[i], _frustum(Vector2(0.03, 0.2), Vector2(0.03, 0.16), -0.46, 0.0), NAVY)
		_part(flap[i], _frustum(Vector2(0.035, 0.2), Vector2(0.035, 0.2), -0.49, -0.45), IVORY)
		# 정강이 감개 (미색)
		_part(knee[i], _frustum(Vector2(0.125, 0.135), Vector2(0.125, 0.135), -0.28, -0.22), IVORY)

	# 몸통: 어깨가 넓은 짧은 코트, 앞섶에 미색 줄, 허리띠
	torso = _joint(hips, Vector3(0, 0.04, 0))
	_part(torso, _frustum(Vector2(0.34, 0.22), Vector2(0.46, 0.26), 0.0, 0.5), NAVY)
	_part(torso, _box(Vector3(0.38, 0.06, 0.24)), IVORY, Vector3(0, 0.04, 0))
	_part(torso, _box(Vector3(0.04, 0.42, 0.02)), IVORY, Vector3(0.05, 0.28, -0.125))
	_part(torso, _box(Vector3(0.08, 0.1, 0.06)), VISOR, Vector3(-0.17, 0.03, -0.09), 0.6)  # 허리의 먹통
	_part(torso, _box(Vector3(0.1, 0.11, 0.08)), LEATHER, Vector3(0.17, -0.01, -0.06))  # 가죽 주머니
	# 등에 멘 큰 붓: 오른쪽 어깨 위로 비스듬히, 먹 묻은 붓끝이 왼쪽 허리 아래로
	# 모델 원점에 붙여 두고 매 프레임 등 ↔ 다리 밑 자세를 섞는다
	brush = _joint(self, Vector3.ZERO)
	_brush_back = Transform3D(Basis.from_euler(Vector3(0, 0, deg_to_rad(-38.0))), Vector3(0.0, 0.28, 0.17))
	_part(brush, _frustum(Vector2(0.045, 0.045), Vector2(0.04, 0.04), -0.2, 0.52), WOOD)
	_part(brush, _frustum(Vector2(0.06, 0.06), Vector2(0.06, 0.06), -0.26, -0.2), IVORY)
	_part(brush, _frustum(Vector2(0.11, 0.11), Vector2(0.07, 0.07), -0.42, -0.26), IVORY)
	_part(brush, _frustum(Vector2(0.02, 0.02), Vector2(0.11, 0.11), -0.56, -0.42), INK)
	_part(torso, _box(Vector3(0.56, 0.045, 0.02)), LEATHER, Vector3(0.01, 0.27, -0.134)).rotation.z = deg_to_rad(49.0)  # 멜빵: 오른쪽 어깨 → 왼쪽 허리
	# 높은 깃 (미색)
	_part(torso, _frustum(Vector2(0.3, 0.24), Vector2(0.26, 0.22), 0.48, 0.62), IVORY)

	# 머리: 후드(남색) + 검은 마스크 + 청록 바이저. 후드 끝이 앞으로 살짝 튀어나온다
	head = _joint(torso, Vector3(0, 0.6, 0))
	_part(head, _frustum(Vector2(0.3, 0.32), Vector2(0.18, 0.22), 0.0, 0.34, Vector3(0, 0, -0.04)), NAVY)
	_part(head, _box(Vector3(0.2, 0.2, 0.05)), MASK, Vector3(0, 0.14, -0.15))
	_part(head, _box(Vector3(0.17, 0.03, 0.03)), VISOR, Vector3(0, 0.17, -0.18), 2.5)
	_part(head, _frustum(Vector2(0.24, 0.06), Vector2(0.16, 0.05), 0.24, 0.34), NAVY, Vector3(0, 0, -0.15))  # 후드 차양
	_part(head, _frustum(Vector2(0.36, 0.08), Vector2(0.26, 0.07), -0.1, 0.2, Vector3(0, 0, -0.03)), NAVY, Vector3(0, 0, 0.14))  # 후드 뒷자락
	_part(head, _frustum(Vector2(0.18, 0.22), Vector2(0.07, 0.09), 0.34, 0.41, Vector3(0, 0, 0.06)), NAVY, Vector3(0, 0, -0.04))  # 후드 윗부분: 끝이 뒤로 넘어간다

	# 목도리 꼬리: 목 뒤에서 뒤로 휘날린다 (탑뷰에서 진행 방향이 보인다)
	scarf = _joint(torso, Vector3(0.06, 0.56, 0.12))
	_part(scarf, _frustum(Vector2(0.14, 0.03), Vector2(0.16, 0.035), -0.6, 0.0), IVORY)

	# 팔: 남색 소매 + 미색 소맷부리 + 장갑
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		shoulder[i] = _joint(torso, Vector3(0.27 * side, 0.44, 0))
		_part(shoulder[i], _frustum(Vector2(0.11, 0.12), Vector2(0.15, 0.16), -UPPER_ARM, 0.04), NAVY)
		_part(shoulder[i], _frustum(Vector2(0.19, 0.2), Vector2(0.15, 0.17), 0.0, 0.07), IVORY)  # 어깨 덧댐: 탑뷰에서 실루엣이 읽힌다
		elbow[i] = _joint(shoulder[i], Vector3(0, -UPPER_ARM, 0))
		_part(elbow[i], _frustum(Vector2(0.1, 0.1), Vector2(0.12, 0.12), -FOREARM + 0.06, 0.0), NAVY)
		_part(elbow[i], _frustum(Vector2(0.12, 0.12), Vector2(0.12, 0.12), -FOREARM + 0.08, -FOREARM + 0.03), IVORY)
		_part(elbow[i], _box(Vector3(0.09, 0.1, 0.1)), GLOVE, Vector3(0, -FOREARM - 0.02, 0))


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j


func _part(parent: Node3D, mesh: Mesh, color: Color, offset := Vector3.ZERO, glow := 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = offset
	m.material_override = _mat(color, glow)
	parent.add_child(m)
	meshes.append(m)
	return m


func _mat(color: Color, glow: float) -> StandardMaterial3D:
	var key := "%s|%s" % [color, glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	else:
		var kind := ""
		if color == NAVY or color == NAVY_DARK:
			kind = "cloth"
		elif color == IVORY:
			kind = "stain"
		elif color in [LEATHER, WOOD, BOOT, GLOVE]:
			kind = "leather"
		if kind != "":
			# 부품마다 로컬 좌표로 트라이플래너: 움직여도 무늬가 몸에 붙어 있다
			m.albedo_texture = _texture(kind)
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE / TEX_TILE
	_mats[key] = m
	return m


## 32×32 밝기 텍스처 (색은 albedo_color가 입힌다). 이음매 없이 반복되도록 모든 무늬를 감싸 그린다
static func _texture(kind: String) -> ImageTexture:
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var n := TEX_SIZE
	var v := PackedFloat32Array()
	v.resize(n * n)
	for y in n:
		for x in n:
			var c := 1.0
			match kind:
				"cloth":   # 옷감: 거친 결 + 4줄마다 박음질
					c = 0.88 + rng.randf() * 0.1
					if y % 4 == 3:
						c *= 0.92
					if (x + y * 3) % 8 == 0:
						c *= 1.06
				"stain":   # 색 바랜 미색 천
					c = 0.9 + rng.randf() * 0.1
				"leather": # 가죽·나무: 얼룩진 결 + 긁힌 자국
					c = 0.78 + rng.randf() * 0.18
					if (x * 2 + y) % 11 == 0:
						c *= 1.15
			v[y * n + x] = c
	# 먹 얼룩: 번진 점 + 아래로 흘러내린 줄기
	var blobs := {"cloth": 3, "stain": 4, "leather": 2}
	var depth := {"cloth": 0.55, "stain": 0.4, "leather": 0.65}
	for b in int(blobs.get(kind, 0)):
		var cx := rng.randi_range(0, n - 1)
		var cy := rng.randi_range(0, n - 1)
		var r := rng.randf_range(1.0, 2.2)
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if Vector2(dx, dy).length() <= r + rng.randf_range(-0.4, 0.4):
					var i := posmod(cy + dy, n) * n + posmod(cx + dx, n)
					v[i] *= float(depth[kind])
		for d in rng.randi_range(2, 5):
			var i := posmod(cy + int(r) + d, n) * n + posmod(cx + (1 if b % 2 == 0 else 0), n)
			v[i] *= lerpf(float(depth[kind]), 1.0, float(d) / 6.0)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var c := clampf(v[y * n + x], 0.0, 1.0)
			img.set_pixel(x, y, Color(c, c, c))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[kind] = tex
	return tex


func _box(size: Vector3) -> Mesh:
	return _frustum(Vector2(size.x, size.z), Vector2(size.x, size.z), -size.y * 0.5, size.y * 0.5)


## 사각뿔대 (면마다 법선이 따로인 각진 메시): 아래 y0에서 bottom 크기, 위 y1에서 top 크기.
## top_shift만큼 윗면을 옮겨 기울어진 모양을 만든다
func _frustum(bottom: Vector2, top: Vector2, y0: float, y1: float, top_shift := Vector3.ZERO) -> ArrayMesh:
	var b := [
		Vector3(-bottom.x, y0, -bottom.y) * Vector3(0.5, 1, 0.5),
		Vector3(bottom.x, y0, -bottom.y) * Vector3(0.5, 1, 0.5),
		Vector3(bottom.x, y0, bottom.y) * Vector3(0.5, 1, 0.5),
		Vector3(-bottom.x, y0, bottom.y) * Vector3(0.5, 1, 0.5),
	]
	var t := [
		Vector3(-top.x, y1, -top.y) * Vector3(0.5, 1, 0.5) + top_shift,
		Vector3(top.x, y1, -top.y) * Vector3(0.5, 1, 0.5) + top_shift,
		Vector3(top.x, y1, top.y) * Vector3(0.5, 1, 0.5) + top_shift,
		Vector3(-top.x, y1, top.y) * Vector3(0.5, 1, 0.5) + top_shift,
	]
	var center := Vector3(0, (y0 + y1) * 0.5, 0) + top_shift * 0.5
	var quads := [
		[b[0], b[1], b[2], b[3]],  # 아래
		[t[0], t[1], t[2], t[3]],  # 위
		[b[0], b[1], t[1], t[0]],  # 앞 (-Z)
		[b[1], b[2], t[2], t[1]],  # 오른쪽
		[b[2], b[3], t[3], t[2]],  # 뒤
		[b[3], b[0], t[0], t[3]],  # 왼쪽
	]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for q in quads:
		var qc: Vector3 = (q[0] + q[1] + q[2] + q[3]) * 0.25
		for tri in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
			var a: Vector3 = tri[0]
			var c1: Vector3 = tri[1]
			var c2: Vector3 = tri[2]
			var n := (c1 - a).cross(c2 - a)
			if n.length() < 1e-8:
				continue
			n = n.normalized()
			var outward := (qc - center)
			if n.dot(outward) < 0.0:
				n = -n
			else:
				var tmp := c1  # Godot 앞면은 시계 방향: 바깥에서 볼 때 시계 방향이 되도록 뒤집는다
				c1 = c2
				c2 = tmp
			verts.append_array([a, c1, c2])
			norms.append_array([n, n, n])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


# ---------------------------------------------------------------- 움직임

## player_animator.gd가 매 프레임 호출한다.
##   phase: 걸음 위상, amt: 달리기 세기(0~1.3), move: 바라보는 방향 기준 이동 방향(x 오른쪽, y 앞)
##   st/states: 플레이어 상태, vy: 수직 속도, speed: 수평 속도, grip_pivot: 검 회전축 (오른손이 따라간다)
func animate(delta: float, phase: float, amt: float, move: Vector2, st: int, states: Dictionary,
		vy: float, speed: float, grip_pivot: Node3D) -> void:
	_time += delta
	var k := 1.0 - exp(-18.0 * delta)
	var lt := [Vector3.ZERO, Vector3.ZERO]  # 허벅지 목표 회전
	var kt := [0.0, 0.0]                     # 무릎 굽힘 (음수 = 뒤로 접힘)
	var arm_l := Vector3(0.0, 0.0, -0.12)    # 왼팔 어깨 회전
	var elbow_l := 0.25                      # 왼팔 팔꿈치 (양수 = 앞으로 접힘)
	var head_x := 0.0

	if st == states.GROUND and amt > 0.05:
		for i in 2:
			var s := sin(phase + PI * i) * 0.75 * amt
			lt[i] = Vector3(move.y * s, 0.0, move.x * s)
			kt[i] = -(0.15 + 0.9 * maxf(0.0, -cos(phase + PI * i))) * minf(amt, 1.0)
		arm_l.x = -sin(phase) * 0.6 * amt * maxf(move.y, 0.3)
		elbow_l = 0.4 + 0.3 * amt
	elif st == states.GROUND:
		kt = [-0.08, -0.08]
	elif st == states.SLIDE:
		lt = [Vector3(1.25, 0, 0), Vector3(0.35, 0, -0.1)]
		kt = [-0.1, -1.5]
		arm_l = Vector3(-0.3, 0, -0.9)
		elbow_l = 0.2
	elif st == states.DASH:
		lt = [Vector3(-0.35, 0, 0), Vector3(-0.6, 0, 0)]
		kt = [-0.7, -0.5]
		arm_l = Vector3(-0.9, 0, -0.2)
		elbow_l = 0.1
	elif st == states.WALL:
		lt = [Vector3(0.9, 0, -0.1), Vector3(0.3, 0, 0.1)]
		kt = [-1.3, -0.5]
		arm_l = Vector3(0.8, 0, -0.5)
		elbow_l = 0.6
	else:
		# 공중: 오를 땐 무릎을 당기고, 떨어질 땐 다리를 펴서 착지를 준비한다
		var rise := clampf(vy / 10.0, -1.0, 1.0)
		var tuck := 0.5 + 0.5 * rise
		lt = [Vector3(0.2 + 0.7 * tuck, 0, -0.05), Vector3(-0.1 + 0.4 * tuck, 0, 0.05)]
		kt = [-0.3 - 1.0 * tuck, -0.5 - 0.6 * tuck]
		arm_l = Vector3(0.2, 0, -0.5 - 0.3 * (1.0 - tuck))
		elbow_l = 0.4
		head_x = -0.1 * rise

	for i in 2:
		var lj: Node3D = leg[i]
		var kj: Node3D = knee[i]
		lj.rotation = lj.rotation.lerp(lt[i], k)
		kj.rotation.x = lerpf(kj.rotation.x, kt[i], k)
	var sl: Node3D = shoulder[0]
	var el: Node3D = elbow[0]
	sl.rotation = sl.rotation.lerp(arm_l, k)
	el.rotation.x = lerpf(el.rotation.x, elbow_l, k)
	head.rotation.x = lerpf(head.rotation.x, head_x, k)

	# 코트 자락·목도리: 빠를수록 뒤로 날리고, 떨어질 땐 위로 펄럭인다
	var blow := clampf(speed / 20.0, 0.0, 1.2)
	var lift := clampf(-vy / 15.0, -0.3, 0.8)
	for i in 2:
		var tj: Node3D = tail[i]
		var flap := sin(_time * (9.0 + 3.0 * i) + i) * 0.12 * (0.3 + blow)
		var target := -(0.12 + 0.9 * blow + 0.6 * lift) + flap
		if st == states.SLIDE:
			target = -1.2
		tj.rotation.x = lerpf(tj.rotation.x, clampf(target, -1.5, 0.2), k)
	for i in 2:
		var fj: Node3D = flap[i]
		var side := -1.0 if i == 0 else 1.0
		var flutter := sin(_time * (10.0 + 2.0 * i) + 2.0 * i) * 0.1 * (0.3 + blow)
		var fx := -(0.08 + 0.7 * blow + 0.5 * lift) + flutter
		var fz := side * (0.06 + 0.25 * blow + 0.3 * maxf(lift, 0.0))   # 바깥으로 벌어진다
		if st == states.SLIDE:
			fx = -1.0
		var ft := Vector3(clampf(fx, -1.3, 0.2), 0.0, fz)
		# 달릴 때 같은 쪽 다리를 따라 조금 밀린다
		ft.x += (leg[i] as Node3D).rotation.x * 0.5
		fj.rotation = fj.rotation.lerp(ft, k)
	var sflap := sin(_time * 11.0) * 0.18 * (0.3 + blow)
	scarf.rotation.x = lerpf(scarf.rotation.x, clampf(-(0.25 + 1.1 * blow + 0.6 * lift) + sflap, -1.6, 0.1), k)
	scarf.rotation.z = lerpf(scarf.rotation.z, sin(_time * 7.0) * 0.15 * blow, k)

	# 큰 붓: 슬라이드하면 다리 밑으로 휙 내려와 눕는다. 자루는 앞, 붓끝은 뒤로 바닥에 닿아 먹 획을 끈다
	_brush_ride = lerpf(_brush_ride, 1.0 if st == states.SLIDE else 0.0, 1.0 - exp(-16.0 * delta))
	var back := hips.transform * torso.transform * _brush_back
	var shake := sin(_time * 38.0) * 0.012 * blow     # 바닥을 긁으며 떨린다
	# 탈 때는 1.5배로 커진다: 탑뷰에서도 '붓을 타고 미끄러지는' 모습이 읽히게
	var ride := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-84.0), 0.0, shake * 4.0)).scaled(Vector3.ONE * 1.5), Vector3(0.0, 0.1 + shake, -0.1))
	if _brush_ride < 0.002:
		brush.transform = back
	elif _brush_ride > 0.998:
		brush.transform = ride
	else:
		# 등에서 다리 밑으로 휘두르듯: 중간에 살짝 옆으로 돌며 내려온다
		var mid := back.interpolate_with(ride, _brush_ride)
		mid.basis = mid.basis * Basis.from_euler(Vector3(0, sin(_brush_ride * PI) * 0.8, 0))
		brush.transform = mid

	if grip_pivot:
		_reach_right(grip_pivot.global_transform * GRIP)


## 오른팔 2본 IK: 어깨에서 손잡이 위치까지 팔을 뻗고 팔꿈치는 바깥 아래로 굽힌다
func _reach_right(target_global: Vector3) -> void:
	var sh: Node3D = shoulder[1]
	var el: Node3D = elbow[1]
	var parent_inv := torso.global_transform.affine_inverse()
	var s := sh.position
	var t := parent_inv * target_global
	var a := UPPER_ARM
	var b := FOREARM + 0.04
	var to := t - s
	var d := clampf(to.length(), 0.05, a + b - 0.001)
	var dir := to.normalized() if to.length() > 0.001 else Vector3.DOWN
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var pole := Vector3(0.3, -0.9, 0.45).normalized()  # 팔꿈치는 아래 뒤로 (살짝 바깥)
	var perp := pole - dir * pole.dot(dir)
	perp = perp.normalized() if perp.length() > 0.001 else Vector3.RIGHT
	var e := s + dir * (cos_a * a) + perp * (sqrt(1.0 - cos_a * cos_a) * a)
	sh.basis = _limb_basis(e - s, dir)
	var to_hand := sh.basis.inverse() * (s + dir * d - e)
	el.basis = _limb_basis(to_hand, Vector3.FORWARD)


## 팔다리 메시는 -Y로 뻗어 있다: -Y가 down_dir을 향하는 회전
func _limb_basis(down_dir: Vector3, hint: Vector3) -> Basis:
	var y := -down_dir.normalized()
	var x := hint.cross(y)
	if x.length() < 0.001:
		x = Vector3.RIGHT.cross(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
