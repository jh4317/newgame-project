extends Node
## 플레이어 절차적 애니메이션: 캐릭터 모델 없이 몸통(캡슐)과 코를 스프링으로 움직인다.
## 게임 판정에는 영향이 없다 — 보이는 몸(pose)만 움직이고, 검·패링 부채꼴·충돌체는 그대로다.
##
##   - 달리기: 속도에 맞춰 통통 튀고 좌우로 살짝 흔들린다
##   - 기울기: 달리는 방향·가속 방향으로 몸이 기운다 (급정지하면 뒤로 젖혀진다)
##   - 늘어남/찌그러짐: 점프·공중 상승은 위로 늘어나고, 착지는 떨어진 속도만큼 납작해진다 (부피 유지)
##   - 벽 붙기: 벽 반대쪽으로 기대고, 슬라이드: 뒤로 젖힌다
##   - 공격: 휘두르는 방향으로 몸을 비틀며 앞으로 내딛는다. 마무리·획 긋기는 더 크게
##   - 차지: 웅크리고 차지가 쌓일수록 떨린다
##   - 패링: 몸이 툭 커졌다 돌아온다 / 피격: 뒤로 젖혀지며 짧게 흔들린다
##
## 히트스톱(Engine.time_scale)이 걸리면 delta가 작아져 자세가 그 순간에 멈춘다 → 임팩트가 또렷해진다.

@export_group("Run")
@export var stride_per_meter := 0.55   # 1 m 달릴 때 진행하는 걸음 위상 (라디안 × 1/π)
@export var bob_height := 0.12
@export var sway_deg := 4.0
@export_group("Lean")
@export var lean_per_speed_deg := 1.1  # 속도 1 m/s당 기울기
@export var lean_per_accel_deg := 0.25 # 가속 1 m/s²당 기울기
@export var lean_max_deg := 24.0
@export_group("Spring")
@export var squash_stiffness := 320.0
@export var squash_damping := 14.0
@export var lean_stiffness := 180.0
@export var lean_damping := 18.0
@export var twist_stiffness := 260.0
@export var twist_damping := 16.0

var player  ## player_controller.gd (신호·속성을 동적으로 쓰므로 타입을 두지 않는다)
var pose: Node3D          ## 모델이 달린 노드 (발밑이 원점)
var model: Node3D         ## player_model.gd: 팔다리·코트 자락·목도리 관절
var visual: Node3D        ## 바라보는 방향으로 도는 노드 (pose의 부모)
var states: Dictionary    ## player.State enum

# 스프링 상태: x = 값, y = 속도
var _squash := Vector2.ZERO   # +면 위로 늘어남, -면 납작
var _lean_x := Vector2.ZERO   # X축 회전 (음수 = 앞으로 숙임)
var _lean_z := Vector2.ZERO   # Z축 회전 (음수 = 오른쪽으로 기움)
var _twist := Vector2.ZERO    # Y축 회전 (상체 비틀기)
var _phase := 0.0
var _prev_hvel := Vector3.ZERO
var _accel := Vector3.ZERO
var _shake := 0.0
var _charge_t := 0.0
var _stretch := 1.0                    # 대시 중 대시 방향으로 늘어나는 배율
var _stretch_dir := Vector3(0, 0, -1)  # 늘어나는 방향 (바라보는 방향 기준)


func _ready() -> void:
	player.jumped.connect(func(): _kick_squash(0.35))
	player.wall_jumped.connect(func():
		_kick_squash(0.4)
		_twist.y += 6.0 * (1.0 if randf() < 0.5 else -1.0))
	player.landed.connect(_on_landed)
	player.dashed.connect(func():
		# 바라보는 쪽이 아니라 대시하는 쪽으로 몸을 던진다
		var d := _local_dash_dir()
		_kick_squash(-0.25)
		_lean_x.y += d.z * 4.0
		_lean_z.y -= d.x * 4.0)
	player.slide_started.connect(func(): _kick_squash(-0.3))
	player.parried.connect(func(_src):
		_kick_squash(0.5)
		_lean_x.y += 5.0)
	player.damaged.connect(func(_amount):
		_kick_squash(-0.35)
		_lean_x.y += 7.0
		_shake = 0.22)
	player.respawned.connect(_reset)
	var sword: Node = player.get("sword")
	sword.swung.connect(_on_swung)
	# 종베기: 몸을 비틀지 않고 앞으로 크게 숙이며 내리꽂는다
	sword.stroke_struck.connect(func(_from, _to, level: int):
		_lean_x.y -= 9.0 + 3.0 * level
		_kick_squash(-0.4 - 0.12 * level))


func _reset() -> void:
	_squash = Vector2.ZERO
	_lean_x = Vector2.ZERO
	_lean_z = Vector2.ZERO
	_twist = Vector2.ZERO
	_prev_hvel = Vector3.ZERO
	_accel = Vector3.ZERO
	_shake = 0.0
	_charge_t = 0.0
	_stretch = 1.0


## 대시 방향을 바라보는 방향 기준 좌표로 (-Z = 앞, +X = 오른쪽)
func _local_dash_dir() -> Vector3:
	var d: Vector3 = visual.global_basis.orthonormalized().inverse() * Vector3(player.get("_dash_dir"))
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3(0, 0, -1)


func _kick_squash(amount: float) -> void:
	_squash.y += amount * 12.0


func _on_landed(fall_speed: float) -> void:
	# 점프 한 번 착지(≈11 m/s)는 가볍게, 높은 곳에서 떨어지면 크게 납작
	_kick_squash(-clampf(fall_speed / 30.0, 0.08, 0.6))


func _on_swung(combo: int) -> void:
	var finisher := combo == 3
	# 칼날은 from → -from(= -_swing_dir 쪽)으로 지나간다. 몸도 그쪽으로 비튼다
	var dir := -float(player.sword.get("_swing_dir"))
	_twist.y += dir * (11.0 if finisher else 7.0)
	_lean_x.y -= 5.0 if finisher else 3.0   # 앞으로 내딛기
	_kick_squash(-0.22 if finisher else -0.1)


## 플레이어 _update_visual에서 매 물리 프레임 호출
func update(delta: float) -> void:
	if pose == null or delta <= 0.0:
		return
	var st: int = player.get("state")
	var on_floor: bool = player.is_on_floor()
	var v: Vector3 = player.velocity
	var hvel := Vector3(v.x, 0.0, v.z)
	var speed := hvel.length()
	var run_speed: float = player.get("run_speed")

	# 가속도 (부드럽게): 출발·급정지·방향 전환에 몸이 반응하도록
	var raw_accel := (hvel - _prev_hvel) / delta
	_prev_hvel = hvel
	_accel = _accel.lerp(raw_accel, 1.0 - exp(-12.0 * delta))

	# 바라보는 방향 기준 좌표로 바꾼다 (-Z = 앞, +X = 오른쪽)
	var inv := visual.global_basis.orthonormalized().inverse()
	var lv := inv * hvel
	var la := inv * _accel

	# ---- 기울기 목표
	var k_v := deg_to_rad(lean_per_speed_deg)
	var k_a := deg_to_rad(lean_per_accel_deg)
	var lean_x_t := lv.z * k_v + la.z * k_a       # 앞으로 달리면(lv.z < 0) 앞으로 숙인다
	var lean_z_t := -lv.x * k_v - la.x * k_a      # 오른쪽으로 달리면 오른쪽으로 기운다
	var lean_max := deg_to_rad(lean_max_deg)
	if st == states.SLIDE:
		lean_x_t = deg_to_rad(16.0)               # 슬라이드: 뒤로 젖혀 미끄러진다
		lean_z_t *= 0.5
	elif st == states.WALL:
		var wn: Vector3 = inv * Vector3(player.get("_wall_normal"))
		lean_x_t = wn.z * deg_to_rad(14.0)        # 벽 반대쪽(법선 방향)으로 기댄다
		lean_z_t = -wn.x * deg_to_rad(14.0)
	elif st == states.DASH:
		_stretch_dir = _local_dash_dir()
		lean_x_t = _stretch_dir.z * deg_to_rad(16.0)
		lean_z_t = -_stretch_dir.x * deg_to_rad(16.0)
	elif not on_floor:
		lean_x_t *= 0.6
		lean_z_t *= 0.6
	lean_x_t = clampf(lean_x_t, -lean_max, lean_max)
	lean_z_t = clampf(lean_z_t, -lean_max, lean_max)

	# ---- 늘어남/찌그러짐 목표
	var squash_t := 0.0
	if not on_floor and st != states.DASH:
		squash_t = clampf(v.y * 0.012, -0.1, 0.16)  # 오를 땐 늘어나고 떨어질 땐 살짝
	var sword: Node = player.get("sword")
	var charging := sword != null and bool(sword.call("is_charging"))
	if charging:
		_charge_t += delta
		squash_t -= minf(_charge_t * 0.25, 0.16)   # 차지할수록 웅크린다
		lean_x_t = minf(lean_x_t, deg_to_rad(-8.0))
	else:
		_charge_t = 0.0

	# ---- 달리기 보빙
	var bob := 0.0
	var sway := 0.0
	var amt := 0.0
	if st == states.GROUND and on_floor and speed > 0.5:
		_phase += speed * stride_per_meter * PI * delta
		amt = clampf(speed / run_speed, 0.0, 1.3)
		bob = absf(sin(_phase)) * bob_height * amt
		sway = sin(_phase) * deg_to_rad(sway_deg) * amt
		squash_t += (absf(sin(_phase)) - 0.5) * 0.06 * amt   # 발 디딜 때 살짝 눌린다
	else:
		_phase = 0.0

	# ---- 스프링 진행
	_squash = _spring(_squash, squash_t, squash_stiffness, squash_damping, delta)
	_lean_x = _spring(_lean_x, lean_x_t, lean_stiffness, lean_damping, delta)
	_lean_z = _spring(_lean_z, lean_z_t, lean_stiffness, lean_damping, delta)
	_twist = _spring(_twist, 0.0, twist_stiffness, twist_damping, delta)

	# ---- 자세 적용
	var sy := clampf(1.0 + _squash.x, 0.45, 1.7)
	var sxz := 1.0 / sqrt(sy)                     # 부피 유지
	var basis := Basis.from_euler(Vector3(_lean_x.x, _twist.x, _lean_z.x + sway)) * Basis.from_scale(Vector3(sxz, sy, sxz))
	# 대시: 대시 방향으로만 늘인다 (옆으로 대시하면 옆으로 늘어난다)
	_stretch = lerpf(_stretch, 1.6 if st == states.DASH else 1.0, 1.0 - exp(-20.0 * delta))
	if _stretch > 1.001:
		var d := _stretch_dir
		var e := _stretch - 1.0
		basis = Basis(Vector3(1.0 + e * d.x * d.x, 0.0, e * d.x * d.z), Vector3.UP,
			Vector3(e * d.x * d.z, 0.0, 1.0 + e * d.z * d.z)) * basis
	pose.basis = basis
	var jitter := Vector3.ZERO
	if _shake > 0.0:
		_shake -= delta
		jitter += Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * 0.12 * (_shake / 0.22)
	if charging:
		var tremble := minf(_charge_t / 0.6, 1.0) * 0.035
		jitter += Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * tremble
	pose.position = Vector3(0.0, bob, 0.0) + jitter

	# ---- 팔다리 (player_model.gd)
	if model:
		var move := Vector2(lv.x, -lv.z)
		move = move.normalized() if move.length() > 0.3 else Vector2(0, 1)
		var grip: Node3D = sword.get("_pivot") if sword else null
		model.call("animate", delta, _phase, amt, move, st, states, v.y, speed, grip)


## 감쇠 스프링 한 걸음 (반암시적 오일러)
func _spring(s: Vector2, target: float, k: float, d: float, dt: float) -> Vector2:
	var vel := s.y + (-(s.x - target) * k - s.y * d) * dt
	return Vector2(s.x + vel * dt, vel)
