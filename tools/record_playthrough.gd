extends SceneTree
## 자동 플레이(봇)로 웨이브 아레나를 플레이하며 영상으로 남긴다 (약 1분 30초).
## 실행 (Godot의 Movie Maker로 녹화):
##   godot --path . --write-movie recordings/playthrough.avi --fixed-fps 30 --resolution 1280x720 -s tools/record_playthrough.gd
## 녹화 없이 봇만 보고 싶으면 --write-movie를 빼면 된다.
##
## 구성:
##   1) 오프닝 쇼케이스 (~15초): 웨이브 1의 적이 다가오는 동안 이동 기술을 차례로 보여 준다
##      슬라이드(먹 획) → 버니합 연속 → 대시 → 기둥 벽 점프 연속 → 전투 돌입
##   2) 전투: 가장 가까운 적에게 다가가 근접 콤보, 탄·돌진 패링, 높은 발판 위 적에게는 검기.
##      일필휘지가 되면 적이 많은 줄로 차지 종베기. 그 사이사이 슬라이드·대시·버니합·벽 점프를 섞는다
## 녹화 중에는 먹(체력)이 30 아래로 떨어지지 않게 붙잡는다 (봇이 끝까지 가도록. 맞는 연출은 그대로 나온다).
## 조준은 진짜 마우스를 움직이지 않도록 가짜 카메라 리그(_BotRig)로 플레이어에게 직접 알려 준다.

const DURATION := 90.0          # 영상 길이 (초)
const HOLD_AFTER_CLEAR := 3.0   # 그 전에 클리어하면 클리어 화면을 이만큼 보여 주고 끝낸다

## 벽 점프에 쓰는 탈 수 있는 기둥·판 (movement_arena.gd의 기둥 원 반경 32 m + 동·서 벽 점프 판)
var _climbables: Array[Vector3] = []

var arena
var player
var bot_rig: Node3D
var t := 0.0
var _frames := 0                # 영상 길이는 프레임 수로 잰다 (히트스톱 중에는 게임 시간이 느려져도 영상은 흘러간다)
var _clear_t := -1.0

# 전투
var _attack_hold := 0.0
var _charging := false
var _charge_t := 0.0
var _slide_t := 0.0
var _slide_cd := 2.0
var _dash_cd := 1.5
var _jump_cd := 1.0
var _stuck_t := 0.0
var _parry_cd := 0.0
var _weave := 0.0
var _bhop := false              # 착지하는 순간 다시 뛴다 (버니합)
var _wj_cd := 6.0               # 다음 벽 점프 묘기까지

# 벽 점프 묘기
var _trick := ""                # "" / "walljump"
var _trick_t := 0.0
var _wj_target := Vector3.ZERO
var _wj_count := 0
var _wj_tap_cd := 0.0

# 오프닝 쇼케이스 단계
var _show := 0                  # 0 슬라이드, 1 버니합, 2 대시, 3 벽 점프, 4 끝
var _show_t := 0.0

# 영상에 무엇이 들어갔는지 센다
var _count := {"slide": 0, "dash": 0, "wall_jump": 0, "jump": 0, "bhop": 0, "parry": 0, "stroke": 0}
var _max_bhop := 0


class _BotRig extends Node3D:
	var aim := Vector3(0, 0, -1)

	func get_aim_direction(_from: Vector3) -> Vector3:
		return aim

	func get_move_basis() -> Basis:
		return Basis.IDENTITY


func _init() -> void:
	arena = load("res://scenes/movement_proto.tscn").instantiate()
	root.add_child(arena)
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		_climbables.append(Vector3(cos(a) * 32.0, 0.0, sin(a) * 32.0))
	_climbables.append(Vector3(60, 0, 25))
	_climbables.append(Vector3(-60, 0, 25))


func _process(delta: float) -> bool:
	t += delta
	_frames += 1
	var video_t := _frames / 30.0   # --fixed-fps 30으로 녹화한다
	if player == null:
		player = arena.get("player")
		if player == null:
			return false
		# 일반 플레이처럼: 디버그 모드(일필휘지 고정·글자 HUD)를 끄고 등급을 처음부터 올린다
		var style = arena.get("style")
		style.set("debug_lock_max", false)
		style.set("points", 0.0)
		bot_rig = _BotRig.new()
		root.add_child(bot_rig)
		player.slide_started.connect(func(): _count["slide"] += 1)
		player.dashed.connect(func(): _count["dash"] += 1)
		player.wall_jumped.connect(func(): _count["wall_jump"] += 1)
		player.parried.connect(func(_s): _count["parry"] += 1)
		player.jumped.connect(func():
			_count["jump"] += 1
			var chain := int(player.get("bhop_chain"))
			if chain > 0:
				_count["bhop"] += 1
			_max_bhop = maxi(_max_bhop, chain))
		player.landed.connect(func(_v):
			if _bhop:
				_tap("jump"))   # 착지 직후 다시 뛰기 = 버니합
		player.sword.stroke_struck.connect(func(_a, _b, _l): _count["stroke"] += 1)
		return false
	player.set("camera_rig", bot_rig)   # 조준·이동 기준을 봇이 정한다 (화면은 탑뷰 카메라가 그대로 찍는다)
	if float(player.get("health")) < 30.0:
		player.set("health", 30.0)

	if bool(arena.get("run_cleared")):
		_release_all()
		if _clear_t < 0.0:
			_clear_t = t
			_report("cleared")
		return t - _clear_t > HOLD_AFTER_CLEAR
	if video_t >= DURATION:
		_report("end")
		_release_all()
		return true

	_parry(delta)
	if _show < 4:
		_showcase(delta)
	elif _trick == "walljump":
		_walljump(delta)
	else:
		_fight(delta)
	return false


func _report(label: String) -> void:
	var style = arena.get("style")
	var best: int = style.get("best_rank")
	print("[playthrough] %s  t=%.1fs  wave %d/3  kills %d  best rank %s" % [
		label, t, int(arena.get("wave")), int(arena.get("kills")), "-" if best < 0 else String(style.RANKS[best])])
	print("[playthrough] moves: %s  longest bunny-hop chain %d" % [str(_count), _max_bhop])


# ---------------------------------------------------------------- 오프닝 쇼케이스

func _showcase(delta: float) -> void:
	_show_t += delta
	var me: Vector3 = player.global_position
	var pillar := _nearest_climbable(me)
	match _show:
		0:
			# 시작하자마자 동쪽으로 달리다 슬라이드: 바닥에 먹 획이 남는다
			_bhop = false
			var dir := Vector3(1, 0, -0.35).normalized()
			bot_rig.aim = dir
			_apply_move(dir)
			if _show_t > 0.5 and _show_t < 1.9:
				Input.action_press("slide")
			else:
				Input.action_release("slide")
			if _show_t > 2.2:
				_next_show()
		1:
			# 기둥 쪽으로 버니합을 이어 가며 속도를 올린다
			var to := pillar - me
			to.y = 0.0
			var dir := to.normalized()
			bot_rig.aim = dir
			_apply_move(dir)
			_bhop = true
			if _show_t < 0.1 and player.is_on_floor():
				_tap("jump")
			if _show_t > 3.2 or to.length() < 14.0:
				_bhop = false
				_next_show()
		2:
			# 대시 한 번으로 기둥 앞까지
			var to := pillar - me
			to.y = 0.0
			bot_rig.aim = to.normalized()
			_apply_move(to.normalized())
			if _show_t > 0.15 and _show_t < 0.25:
				_tap("dash")
			if _show_t > 0.8:
				_next_show()
		3:
			# 기둥 벽 점프 연속
			if _trick == "":
				_start_walljump(pillar)
			_walljump(delta)
			if _trick == "":
				_next_show()


func _next_show() -> void:
	_show += 1
	_show_t = 0.0


# ---------------------------------------------------------------- 벽 점프 묘기

func _start_walljump(pillar: Vector3) -> void:
	_trick = "walljump"
	_trick_t = 0.0
	_wj_target = pillar
	_wj_count = 0
	_wj_tap_cd = 0.0
	Input.action_release("attack")
	Input.action_release("slide")


func _walljump(delta: float) -> void:
	_trick_t += delta
	_wj_tap_cd -= delta
	var me: Vector3 = player.global_position
	var to := _wj_target - me
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.01 else Vector3.FORWARD
	bot_rig.aim = dir
	_apply_move(dir)   # 기둥 쪽으로 계속 민다 → 닿으면 벽에 붙는다
	var on_wall: bool = player.call("state_name") == "벽 붙기"
	if player.is_on_floor():
		if _wj_count > 0 and _trick_t > 0.4:
			_trick = ""   # 벽 점프를 하고 내려왔다
			return
		if to.length() < 3.2 and _wj_tap_cd <= 0.0:
			_tap("jump")
			_wj_tap_cd = 0.3
	elif on_wall and _wj_tap_cd <= 0.0 and int(player.call("stamina_pips")) > 0:
		_tap("jump")   # 벽에 붙은 채 점프 = 벽 점프 (기둥 반대쪽으로 튕긴다)
		_wj_count += 1
		_wj_tap_cd = 0.35
	if _wj_count >= 3 or _trick_t > 4.5:
		_trick = ""


func _nearest_climbable(me: Vector3) -> Vector3:
	var best := _climbables[0]
	for c in _climbables:
		if Vector2(c.x - me.x, c.z - me.z).length() < Vector2(best.x - me.x, best.z - me.z).length():
			best = c
	return best


# ---------------------------------------------------------------- 전투

func _fight(delta: float) -> void:
	_slide_cd -= delta
	_dash_cd -= delta
	_jump_cd -= delta
	_wj_cd -= delta
	_weave += delta
	var me: Vector3 = player.global_position
	var target := _nearest_enemy(me)
	if target == null:
		_release_moves()
		return
	var to: Vector3 = target.global_position - me
	to.y = 0.0
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector3.FORWARD
	if _parry_cd < 0.3:
		bot_rig.aim = dir

	# 가끔 근처 기둥으로 벽 점프 묘기 (적이 바로 옆에 없을 때)
	if _wj_cd <= 0.0 and dist > 5.0 and not _charging:
		var pillar := _nearest_climbable(me)
		if Vector2(pillar.x - me.x, pillar.z - me.z).length() < 12.0:
			_wj_cd = randf_range(9.0, 13.0)
			_start_walljump(pillar)
			return

	var rank := int(arena.get("style").call("rank"))
	var charge_mode := rank >= 5
	# 높은 발판 위 적: 올라갈 수 없으니 8~14 m 떨어져 검기를 쏜다 (조준 보정이 높이 차를 따라 검기를 띄운다)
	var elevated := target.global_position.y - me.y > 1.5

	# ---- 공격
	if elevated:
		if _charging:
			Input.action_release("attack")
			_charging = false
		_attack_hold -= delta
		if dist < 26.0 and _attack_hold < -0.15:
			_attack_hold = 0.08          # 짧게 눌렀다 떼면 보통 휘두르기 = 검기
		if _attack_hold > 0.0:
			Input.action_press("attack")
		else:
			Input.action_release("attack")
	elif charge_mode:
		# 일필휘지: 차지했다가 적이 많은 줄로 종베기
		if not _charging and dist < 30.0:
			_charging = true
			_charge_t = 0.0
			Input.action_press("attack")
		if _charging:
			_charge_t += delta
			bot_rig.aim = _best_line(me, dir)
			if _charge_t > 0.75:
				Input.action_release("attack")
				_charging = false
	else:
		_charging = false
		if dist < 3.4:
			_attack_hold = 0.3
		_attack_hold -= delta
		if _attack_hold > 0.0:
			Input.action_press("attack")
		else:
			Input.action_release("attack")

	# ---- 이동: 좌우로 흔들며 다가가고, 붙으면 살짝 돈다
	var side := dir.cross(Vector3.UP)
	var move := dir
	if elevated:
		if dist < 8.0:
			move = (-dir + side * 0.5).normalized()
		elif dist > 14.0:
			move = (dir + side * 0.3).normalized()
		else:
			move = side * (1.0 if sin(_weave * 0.7) > 0.0 else -1.0)
	elif dist < 2.4:
		move = side * (1.0 if sin(_weave * 1.3) > 0.0 else -1.0) * 0.6
	else:
		move = (dir + side * sin(_weave * 2.1) * 0.35).normalized()
	if _charging:
		move *= 0.5
	_apply_move(move)

	# ---- 버니합: 멀리 있는 적에게 달려갈 때는 착지마다 다시 뛴다
	_bhop = dist > 12.0 and not _charging and _slide_t <= 0.0
	if _bhop and player.is_on_floor() and _jump_cd <= 0.0:
		_tap("jump")
		_jump_cd = 0.6

	# ---- 슬라이드: 6~20 m 거리에서 가끔 파고든다 (먹 획)
	if _slide_t > 0.0:
		_slide_t -= delta
		if _slide_t <= 0.0:
			Input.action_release("slide")
	elif _slide_cd <= 0.0 and not elevated and dist > 6.0 and dist < 20.0 and player.is_on_floor():
		Input.action_press("slide")
		_slide_t = 0.9
		_slide_cd = randf_range(3.0, 5.0)

	# ---- 대시: 적과 거리가 있으면 자주
	if _dash_cd <= 0.0 and dist > 7.0:
		_tap("dash")
		_dash_cd = randf_range(2.0, 3.2)

	# ---- 점프: 막혔으면(낮은 턱·적 무리)
	var speed: float = player.call("horizontal_speed")
	_stuck_t = _stuck_t + delta if speed < 1.0 and dist > 3.5 else 0.0
	if _jump_cd <= 0.0 and _stuck_t > 0.5:
		_tap("jump")
		_jump_cd = 1.0
		_stuck_t = 0.0


## 패링: 가까이 날아오는 패링 가능한 탄, 또는 이쪽으로 돌진하는 돌격형 (쇼케이스·묘기 중에도)
func _parry(delta: float) -> void:
	_parry_cd -= delta
	var threat := _parry_threat(player.global_position)
	if threat != Vector3.ZERO and _parry_cd <= 0.0:
		bot_rig.aim = threat
		_tap("parry")
		_parry_cd = 0.45


func _nearest_enemy(me: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for e in arena.get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.call("is_dead")):
			continue
		var n := e as Node3D
		var d := me.distance_to(n.global_position) + absf(n.global_position.y - me.y) * 3.0  # 높은 발판 위 적은 뒤로
		if d < best_d:
			best_d = d
			best = n
	return best


## 패링할 위협의 방향 (없으면 ZERO)
func _parry_threat(me: Vector3) -> Vector3:
	var chest := me + Vector3.UP
	for p in arena.get_tree().get_nodes_in_group("projectile"):
		var n := p as Node3D
		if n == null or bool(p.get("reflected")) or not bool(p.get("parryable")):
			continue
		var to := chest - n.global_position
		if to.length() > 4.0:
			continue
		var v: Vector3 = p.get("velocity") if "velocity" in p else Vector3.ZERO
		if v.length() > 0.1 and v.normalized().dot(to.normalized()) > 0.6:
			var d := -to
			d.y = 0.0
			return d.normalized()
	for e in arena.get_tree().get_nodes_in_group("enemy"):
		if e.has_method("is_parryable_attack") and bool(e.call("is_parryable_attack")):
			var to := (e as Node3D).global_position - me
			to.y = 0.0
			if to.length() < 4.5:
				return to.normalized()
	return Vector3.ZERO


## 차지 획을 그을 방향: 지금 방향 근처에서 선 위에 적이 가장 많이 걸리는 쪽
func _best_line(me: Vector3, fallback: Vector3) -> Vector3:
	var best := fallback
	var best_n := -1
	for i in 13:
		var d := fallback.rotated(Vector3.UP, deg_to_rad(-60.0 + i * 10.0))
		var n := 0
		for e in arena.get_tree().get_nodes_in_group("enemy"):
			var to: Vector3 = (e as Node3D).global_position - me
			to.y = 0.0
			var along := to.dot(d)
			if along > 0.0 and (to - d * along).length() < 1.6:
				n += 1
		if n > best_n:
			best_n = n
			best = d
	return best


func _apply_move(v: Vector3) -> void:
	v = v.limit_length(1.0)
	_set_axis("move_right", "move_left", v.x)
	_set_axis("move_back", "move_forward", v.z)


func _set_axis(pos_action: String, neg_action: String, value: float) -> void:
	if value > 0.05:
		Input.action_press(pos_action, value)
		Input.action_release(neg_action)
	elif value < -0.05:
		Input.action_press(neg_action, -value)
		Input.action_release(pos_action)
	else:
		Input.action_release(pos_action)
		Input.action_release(neg_action)


## 잠깐 눌렀다 뗀다 (점프·대시·패링: just_pressed로 읽는다)
func _tap(action: String) -> void:
	Input.action_release(action)
	Input.action_press(action)
	create_timer(0.05).timeout.connect(func(): Input.action_release(action))


func _release_moves() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)


func _release_all() -> void:
	_release_moves()
	for a in ["attack", "slide", "dash", "jump", "parry"]:
		Input.action_release(a)
