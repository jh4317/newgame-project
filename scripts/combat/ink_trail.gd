extends Node3D
## 슬라이드 먹 자국과 '먹 도형'.
## - 슬라이드하는 동안(이어지는 점프의 공중 구간 포함) 바닥에 먹 자국을 찍어 획(stroke)을 이어 간다.
## - 자국은 보통 life초 뒤 옅어진다. 버니합을 이어 가는 동안(hold)에는 나이를 먹지 않아 획 전체가 유지된다.
## - 슬라이드를 멈추면 획이 끊긴다(break_stroke). 끊긴 획끼리는 이어지지 않는다.
## - 획이 자기 자신과 교차해 닫힌 도형이 되면, 도형 안의 적에게 피해를 주고
##   안에 있는 적 수만큼 먹방울(1칸 = 먹 20)을 쌓는다. 도형을 이룬 자국은 번쩍이며 소모된다.

##
## 먹 스타일 등급에 따라 강화된다 (TIERS, 소모 없음). 아레나가 매 프레임 rank를 정한다:
##   점   기본
##   획   도형 최소 넓이가 줄어 작은 원도 인정
##   필   자기 획 위를 지나면 슬라이드 속도 +2 m/s (player가 trail_speed_bonus()를 묻는다)
##   묵   적이 먹 획을 밟으면 먹이 초당 10씩 묻는다
##   농묵 도형이 닫힐 때 안의 적을 중심으로 모은다
##   일필휘지 버니합 없이도 획이 유지되고 흰빛이 된다. 도형 먹 폭발 피해 ×1.5
## 모든 등급: 도형이 닫힐 때 안의 적 먹이 기준치(60)를 넘으면 그 자리에서 먹 스택이 터진다.
## 자국은 플레이어 주변 MAX_RANGE 안에만 남는다.

## enemies: 도형 안에 있던 적들, killed: 그중 이번 피해로 죽은 적 수
signal shape_closed(center: Vector3, enemies: Array, killed: int)
## 도형이 먹 스택을 터뜨렸다 (sword.ink_burst와 같은 모양: 아레나가 같은 연출을 쓴다)
signal ink_burst(enemy: Node, bonus: float, killed: bool)

const INK := Color(0.02, 0.02, 0.02)
const MAX_STAMPS := 400          # 너무 길어지면 오래된 자국부터 옅어진다
## 획의 시작·끝 굵기 (끝에서부터 1번째, 2번째, ... 자국): 붓처럼 뾰족하게
const TIP_TAPER := [0.15, 0.35, 0.6, 0.85]
const MAX_RANGE := 20.0          # 플레이어에게서 이보다 먼 자국은 사라진다: 도형은 캐릭터 주변에서만 (m)
const HEIGHT_RANGE := 3.0        # 획의 가장 높은 곳보다 이만큼 위의 적까지 포함
const AIR_REACH := 6.0           # 획의 가장 낮은 곳보다 이만큼 아래의 적까지 포함 (공중 도형이 아래 적을 가둔다)
const TRAIL_TOUCH := 1.0         # 이 거리 안이면 획 '위'에 있다 (m)
const SPEED_SKIP := 6            # 가장 최근 자국 몇 개는 가속 판정에서 뺀다 (방금 찍은 자국 위 = 항상 획 위)

## 등급별 강화: life(초, INF = 버니합 없이도 유지), width(굵기 배율), damage, ink(적 1마리당), min_area(m²)
const TIERS := [
	{"life": 2.5, "width": 1.0,  "damage": 20.0, "ink": 20.0, "min_area": 6.0},  # 점
	{"life": 3.0, "width": 1.1,  "damage": 20.0, "ink": 20.0, "min_area": 5.0},  # 획
	{"life": 3.5, "width": 1.2,  "damage": 30.0, "ink": 20.0, "min_area": 5.0},  # 필
	{"life": 4.0, "width": 1.35, "damage": 30.0, "ink": 25.0, "min_area": 5.0},  # 묵
	{"life": 5.0, "width": 1.5,  "damage": 40.0, "ink": 30.0, "min_area": 5.0},  # 농묵
	{"life": INF, "width": 1.7,  "damage": 40.0, "ink": 40.0, "min_area": 5.0},  # 일필휘지
]
const RANK_SPEED := 2      # 필부터: 자기 획 위 가속
const RANK_CONTACT := 3    # 묵부터: 획을 밟은 적에게 먹
const RANK_PULL := 4       # 농묵부터: 도형 끌어당김
const RANK_WHITE := 5      # 일필휘지: 흰 획 + 도형 먹 폭발 강화
const WHITE_BURST_MUL := 1.5

@export var trail_speed_bonus_amount := 2.0   # 필: 자기 획 위 슬라이드 가속 (m/s)
@export var contact_ink_rate := 10.0          # 묵: 획을 밟은 적에게 초당 묻는 먹
@export var pull_strength := 0.55             # 농묵: 도형 중심 쪽으로 이 비율만큼 당긴다

## true인 동안(버니합 연속 중) 자국이 나이를 먹지 않는다. 플레이어가 매 프레임 정한다
var hold := false
## 현재 먹 스타일 등급 (0~5, 없음 = 0). 아레나가 매 프레임 정한다
var rank := 0
## 획을 긋는 플레이어 (MAX_RANGE 기준점)
var player: Node3D
var _contact_acc := {}  # 적 → 아직 묻히지 않은 먹 (잔향 연출이 매 프레임 터지지 않게 모아서 묻힌다)


func tier() -> Dictionary:
	return TIERS[clampi(rank, 0, TIERS.size() - 1)]


## 도형 피해 (아레나 표시용)
func shape_damage() -> float:
	return float(tier()["damage"])


## 필 이상에서 pos가 자기 획 위면 슬라이드 가속량, 아니면 0
func trail_speed_bonus(pos: Vector3) -> float:
	if rank < RANK_SPEED:
		return 0.0
	var p := Vector2(pos.x, pos.z)
	for i in maxi(_stamps.size() - SPEED_SKIP, 0):
		var s: Dictionary = _stamps[i]
		if absf(float(s["y"]) - pos.y) < 1.0 and p.distance_to(s["p"]) < TRAIL_TOUCH:
			return trail_speed_bonus_amount
	return 0.0

## 자국들(오래된 순): {p: Vector2(x, z), y, age, start: 새 획의 첫 자국인가, nodes}
var _stamps: Array = []
var _blob_mesh: SphereMesh
var _next_is_start := true
var _stroke_count := 0  ## 지금 획에서 찍은 자국 수 (시작 가늘기용)
var _line_counter := 0  ## 차지 획 번호
var _line_entry := {}   ## 슬라이드 획이 차지 획을 처음 가로지른 곳 {line, hit, stamp}


func _ready() -> void:
	_blob_mesh = SphereMesh.new()
	_blob_mesh.radius = 1.0
	_blob_mesh.height = 2.0
	_blob_mesh.radial_segments = 8
	_blob_mesh.rings = 4


func stroke_length() -> int:
	return _stamps.size()


## 바닥 ground에 dir 방향으로 먹 자국을 찍고, 닫힌 도형이 생겼는지 확인한다
## line_id: 차지 획 긋기로 그은 자국이면 그 획의 번호 (0 = 슬라이드 획)
func stamp(ground: Vector3, dir: Vector3, width_mul := 1.0, line_id := 0) -> void:
	var p := Vector2(ground.x, ground.z)
	var start := _next_is_start or _stamps.is_empty()
	_next_is_start = false
	if start:
		_stroke_count = 0
	# 붓을 대는 순간: 획의 첫 자국 몇 개는 가늘게 시작해 점점 굵어진다 (뾰족한 시작)
	var taper: float = TIP_TAPER[_stroke_count] if _stroke_count < TIP_TAPER.size() else 1.0
	_stroke_count += 1
	var prev = null if start else _stamps.back()["pos"]
	var nodes := _spawn_blobs(ground, dir, prev, width_mul * taper)
	if start:
		_line_entry = {}  # 새 획: 차지 획 교차 기록을 지운다
	var closed := false
	if not start:
		closed = _check_loop(p, ground.y)
		if not closed and line_id == 0:
			closed = _check_line_cross(p, ground.y)
	var s := {"p": p, "y": ground.y, "pos": ground, "age": 0.0, "start": start or closed,
		"line": line_id, "nodes": nodes}
	_stamps.append(s)
	if not _line_entry.is_empty() and _line_entry["stamp"] == null:
		_line_entry["stamp"] = s  # 첫 교차 직후의 자국부터 도형에 들어간다
	if _stamps.size() > MAX_STAMPS:
		_fade(_stamps.pop_front(), 0.8)


## 차지 획 긋기(sword.gd): from에서 to까지 바닥에 굵은 직선 획을 한 번에 긋는다.
## 지금 획(슬라이드)에 이어 그어서 도형을 닫을 수 있다. 다 그은 뒤에는 획을 끊는다
## (다음 슬라이드 자국이 획 끝에서 캐릭터까지 이어지지 않게)
func draw_line(from: Vector3, to: Vector3, width_mul: float) -> void:
	var floor_y := _floor_below(from)
	var a := Vector3(from.x, floor_y, from.z)
	var b := Vector3(to.x, floor_y, to.z)
	if not _stamps.is_empty() and Vector2(a.x, a.z).distance_to(_stamps.back()["p"]) > 3.0:
		_next_is_start = true  # 지금 획과 멀면 새 획으로
	var dir := (b - a).normalized()
	var n := maxi(1, int(a.distance_to(b) / 0.7))
	_line_counter += 1
	for i in n + 1:
		stamp(a.lerp(b, float(i) / n), dir, width_mul, _line_counter)
	_taper_end()
	_next_is_start = true


func _floor_below(pos: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 30.0)
	var ex: Array[RID] = []
	for e in get_tree().get_nodes_in_group("enemy"):
		ex.append((e as CollisionObject3D).get_rid())
	if player is CollisionObject3D:
		ex.append((player as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return pos.y if hit.is_empty() else float((hit["position"] as Vector3).y)


## 슬라이드를 멈췄다: 다음 자국부터 새 획이 된다 (이미 찍힌 자국은 평소대로 옅어진다)
func break_stroke() -> void:
	if not _next_is_start:
		_taper_end()
	_next_is_start = true


## 붓을 떼는 순간: 획의 마지막 자국 몇 개를 가늘게 줄여 끝을 뾰족하게 뺀다
func _taper_end() -> void:
	var k := 0
	for i in range(_stamps.size() - 1, -1, -1):
		if k >= TIP_TAPER.size():
			break
		var s: Dictionary = _stamps[i]
		var f: float = TIP_TAPER[k]
		for m in s["nodes"]:
			var mi := m as MeshInstance3D
			if not is_instance_valid(mi) or not mi.has_meta("size"):
				continue
			var size: Vector3 = mi.get_meta("size")
			var joint: bool = mi.get_meta("joint")
			var target := size * Vector3(f, 1.0, f if joint else 1.0)
			mi.set_meta("size", target)
			mi.create_tween().tween_property(mi, "scale", target, 0.1)
		k += 1
		if s["start"]:
			break


## 모든 자국을 바로 지운다 (리스폰)
func end_stroke() -> void:
	for s in _stamps:
		_fade(s, 0.8)
	_stamps.clear()
	_next_is_start = true


func _process(delta: float) -> void:
	_cull_far()
	if rank >= RANK_CONTACT:
		_contact_ink(delta)
	var life: float = tier()["life"]
	if hold or is_inf(life):
		return
	for s in _stamps:
		s["age"] += delta
	while not _stamps.is_empty() and float(_stamps[0]["age"]) >= life:
		_fade(_stamps.pop_front(), 0.8)


## 플레이어에게서 MAX_RANGE보다 먼 자국을 지운다. 획 중간이 지워지면 그 뒤는 새 획으로 끊는다
func _cull_far() -> void:
	if player == null or _stamps.is_empty():
		return
	var me := Vector2(player.global_position.x, player.global_position.z)
	var kept: Array = []
	var cut := false
	for s in _stamps:
		if me.distance_to(s["p"]) > MAX_RANGE:
			_fade(s, 0.4)
			cut = true
			continue
		if cut:
			s["start"] = true
			cut = false
		kept.append(s)
	if cut:
		_next_is_start = true  # 가장 최근 자국까지 지워졌다
	_stamps = kept


## 묵 이상: 먹 획을 밟고 있는 적에게 먹이 조금씩 묻는다 (5씩 모아서 묻힌다)
func _contact_ink(delta: float) -> void:
	if _stamps.is_empty():
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		var n := e as Node3D
		var p := Vector2(n.global_position.x, n.global_position.z)
		var touching := false
		for s in _stamps:
			if absf(float(s["y"]) - n.global_position.y) < 1.5 and p.distance_to(s["p"]) < TRAIL_TOUCH + 0.6:
				touching = true
				break
		if not touching:
			continue
		var acc: float = _contact_acc.get(e, 0.0) + contact_ink_rate * delta
		if acc >= 5.0:
			var ink: Node = e.get("ink")
			if ink:
				ink.call("add", acc)
			acc = 0.0
		_contact_acc[e] = acc


func _check_loop(p: Vector2, y: float) -> bool:
	var n := _stamps.size()
	if n < 3:
		return false
	var a: Vector2 = _stamps[n - 1]["p"]
	# 새 선분 a→p 와 이전 선분들(바로 앞 선분 제외)의 교차를 찾는다. 가장 최근 것부터.
	# 같은 획 안에서만 찾는다: 획이 끊긴 곳(start)을 지나면 멈춘다
	for i in range(n - 3, -1, -1):
		if _stamps[i + 2]["start"]:
			return false
		if _stamps[i + 1]["start"]:
			return false
		var c: Vector2 = _stamps[i]["p"]
		var d: Vector2 = _stamps[i + 1]["p"]
		var hit = Geometry2D.segment_intersects_segment(a, p, c, d)
		if hit == null:
			continue
		var poly := PackedVector2Array([hit])
		for j in range(i + 1, n):
			poly.append(_stamps[j]["p"])
		var area := absf(_area(poly))
		if area < float(tier()["min_area"]):
			return false  # 너무 작은 고리(제자리 흔들림)는 무시
		var used := _stamps.slice(i + 1, n)
		_stamps = _stamps.slice(0, i + 1)
		# 공중에서 그린 획도 도형이 된다. 채우기는 가장 낮은 높이에,
		# 판정은 획 높이 범위 아래쪽(AIR_REACH)까지: 공중 도형이 아래의 적도 가둔다
		var low_y := y
		var high_y := y
		for s in used:
			low_y = minf(low_y, float(s["y"]))
			high_y = maxf(high_y, float(s["y"]))
		_close_shape(poly, low_y, high_y, used)
		return true
	return false


## 슬라이드 획이 차지 획(일필휘지 획 긋기)을 두 번 가로지르면 도형이 닫힌다.
## 첫 번째로 가로지른 곳을 기억해 두고, 같은 차지 획을 다시 가로지르면
## [첫 교차점 → 그 사이 슬라이드 자국 → 두 번째 교차점]을 도형으로 닫는다 (닫는 변은 차지 획 위).
## 차지 획은 소모되지 않아 여러 번 쓸 수 있다. 닫혔으면 true
func _check_line_cross(p: Vector2, y: float) -> bool:
	var n := _stamps.size()
	if n < 1:
		return false
	var a: Vector2 = _stamps[n - 1]["p"]
	for i in n - 1:
		var line_id: int = _stamps[i]["line"]
		if line_id == 0 or int(_stamps[i + 1]["line"]) != line_id or _stamps[i + 1]["start"]:
			continue
		var hit = Geometry2D.segment_intersects_segment(a, p, _stamps[i]["p"], _stamps[i + 1]["p"])
		if hit == null:
			continue
		var entry_idx := -1
		if not _line_entry.is_empty() and int(_line_entry["line"]) == line_id and _line_entry["stamp"] != null:
			entry_idx = _stamps.find(_line_entry["stamp"])
		if entry_idx < 0:
			_line_entry = {"line": line_id, "hit": hit, "stamp": null}  # 첫 교차: 다음 자국부터 기억
			return false
		var poly := PackedVector2Array([_line_entry["hit"]])
		for j in range(entry_idx, n):
			poly.append(_stamps[j]["p"])
		poly.append(hit)
		if absf(_area(poly)) < float(tier()["min_area"]):
			_line_entry = {"line": line_id, "hit": hit, "stamp": null}
			return false
		var used := _stamps.slice(entry_idx, n)
		_stamps = _stamps.slice(0, entry_idx)
		var low_y := y
		var high_y := y
		for s in used:
			low_y = minf(low_y, float(s["y"]))
			high_y = maxf(high_y, float(s["y"]))
		_line_entry = {}
		_close_shape(poly, low_y, high_y, used)
		return true
	return false


func _close_shape(poly: PackedVector2Array, y: float, high_y: float, used: Array) -> void:
	var inside: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		var n := e as Node3D
		var ey := n.global_position.y
		if ey < y - AIR_REACH or ey > high_y + HEIGHT_RANGE:
			continue
		if Geometry2D.is_point_in_polygon(Vector2(n.global_position.x, n.global_position.z), poly):
			inside.append(e)
	var t := tier()
	var center := Vector2.ZERO
	for v in poly:
		center += v
	center /= poly.size()
	var killed := 0
	for e in inside:
		var ink: Node = e.get("ink")
		var died: bool = e.call("take_damage", float(t["damage"]))
		if died:
			killed += 1
			continue
		if ink:
			ink.call("add", float(t["ink"]) * inside.size())
		# 도형 안에서 먹이 기준치를 넘었으면 그 자리에서 먹 스택을 터뜨린다 (일필휘지는 ×1.5)
		if ink and bool(ink.call("is_ready")):
			var bonus: float = float(ink.call("consume")) * (WHITE_BURST_MUL if rank >= RANK_WHITE else 1.0)
			var burst_killed: bool = e.call("take_damage", bonus)
			if burst_killed:
				killed += 1
			ink_burst.emit(e, bonus, burst_killed)
			if burst_killed:
				continue
		# 농묵 이상: 도형 중심 쪽으로 모은다 (근접으로 한꺼번에 터뜨리기 쉽게)
		if rank >= RANK_PULL and inside.size() > 1:
			var n := e as Node3D
			var from := Vector2(n.global_position.x, n.global_position.z)
			var to := from.lerp(center, pull_strength)
			e.call("pull_to", Vector3(to.x, n.global_position.y, to.y), 0.3)
	_fill_flash(poly, y, not inside.is_empty())
	for s in used:
		_flash_and_fade(s)
	shape_closed.emit(Vector3(center.x, y, center.y), inside, killed)


func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


# ---------------------------------------------------------------- 표현

## 한 획처럼 이어 그린다: 앞 자국(prev)에서 이번 자국까지 납작한 먹 띠 + 이음매를 메우는 둥근 점.
## 획의 첫 자국(prev 없음)은 둥근 점만. 가끔 옆으로 작은 먹방울이 튄다.
func _spawn_blobs(ground: Vector3, dir: Vector3, prev, width_mul := 1.0) -> Array:
	var w: float = float(tier()["width"]) * width_mul
	var white := rank >= RANK_WHITE
	var half_w := 0.38 * w  # 획 반폭 (m)
	var lift := Vector3.UP * 0.015
	var nodes: Array = []
	# 이음매(둥근 점): 띠끼리 꺾이는 곳의 틈을 메운다
	var joint := _ink_piece(ground + lift, Basis.IDENTITY, Vector3(half_w, 0.01, half_w), white)
	joint.set_meta("joint", true)
	nodes.append(joint)
	# 띠: 앞 자국에서 이번 자국까지. 양 끝을 반폭만큼 늘려 이음매와 겹치게 한다
	if prev != null:
		var a: Vector3 = prev
		var seg := ground - a
		if seg.length() > 0.05:
			var fwd := seg.normalized()
			var up := Vector3.UP if absf(fwd.y) < 0.95 else Vector3.FORWARD
			var seg_basis := Basis.looking_at(fwd, up)
			var half_len := seg.length() * 0.5 + half_w * 0.6
			var band := _ink_piece(a.lerp(ground, 0.5) + lift, seg_basis, Vector3(half_w, 0.01, half_len), white)
			band.set_meta("joint", false)
			nodes.append(band)
	# 붓 느낌: 가끔 옆으로 튄 작은 먹방울
	if randf() < 0.25:
		var side := dir.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
		var r := randf_range(0.06, 0.12) * w
		var drop := _ink_piece(ground + side * half_w * randf_range(1.4, 2.2) + lift,
			Basis(Vector3.UP, randf() * TAU), Vector3(r, 0.01, r * randf_range(1.0, 1.5)), white)
		drop.remove_meta("size")  # 먹방울은 끝 가늘기에서 뺀다
		nodes.append(drop)
	return nodes


func _ink_piece(pos: Vector3, rot: Basis, size: Vector3, white: bool) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _blob_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # 겹쳐도 진하기가 같도록 불투명(알파 1)에서 시작
	if white:
		mat.albedo_color = Color(1, 1, 1, 1)
		mat.emission_enabled = true
		mat.emission = Color(1, 1, 1)
		mat.emission_energy_multiplier = 1.6
	else:
		mat.albedo_color = Color(INK.r, INK.g, INK.b, 1.0)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_transform = Transform3D(rot, pos)
	m.set_meta("size", size)
	m.scale = size * Vector3(0.5, 1.0, 0.5)
	m.create_tween().tween_property(m, "scale", size, 0.06) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	return m


func _fade(s: Dictionary, time: float) -> void:
	for m in s["nodes"]:
		var mi := m as MeshInstance3D
		if not is_instance_valid(mi):
			continue
		var tw := mi.create_tween()
		tw.tween_property(mi.material_override, "albedo_color:a", 0.0, time)
		tw.tween_callback(mi.queue_free)


## 도형을 이룬 자국: 하얗게 번쩍인 뒤 빠르게 사라진다
func _flash_and_fade(s: Dictionary) -> void:
	for m in s["nodes"]:
		var mi := m as MeshInstance3D
		if not is_instance_valid(mi):
			continue
		var mat := mi.material_override as StandardMaterial3D
		mat.emission_enabled = true
		mat.emission = Color(1, 1, 1)
		mat.emission_energy_multiplier = 4.0
		mat.albedo_color = Color(1, 1, 1, 1)
		var tw := mi.create_tween()
		tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.25)
		tw.parallel().tween_property(mat, "albedo_color", Color(INK.r, INK.g, INK.b, 0.0), 0.5)
		tw.tween_callback(mi.queue_free)


## 도형 안쪽을 채우는 섬광: 흰빛(적이 있으면 더 밝게)으로 번쩍였다가 먹빛으로 가라앉으며 사라진다
func _fill_flash(poly: PackedVector2Array, y: float, hit: bool) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in idx:
		var v := poly[k]
		st.add_vertex(Vector3(v.x, y + 0.03, v.y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 3.0 if hit else 1.2
	mat.albedo_color = Color(1, 1, 1, 0.7 if hit else 0.4)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.2)
	tw.parallel().tween_property(mat, "albedo_color", Color(INK.r, INK.g, INK.b, 0.6), 0.2)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.tween_callback(mi.queue_free)
