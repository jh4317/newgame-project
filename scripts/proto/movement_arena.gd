extends Node3D
## 1~2단계 프로토타입: 회색 박스 아레나 + 사격형·돌격형 적과 패링 (GDD 10.2).
## 아레나·플레이어·카메라·HUD를 코드로 만든다. V 키로 탑뷰/숄더뷰를 바꿔 두 시점을 비교한다.
##
## 좌표: +X 동쪽, -Z 북쪽(탑뷰 화면 위쪽). 카메라는 남쪽에서 내려다본다.
## 바닥 120 × 120 m. 구역:
##   - 시작 지점: 남쪽 중앙
##   - 슬라이드 레인: 남서쪽의 긴 통로 (60 m)
##   - 계단 블록: 중앙 북쪽 (1.8 → 3.5 → 5 m)
##   - 벽 점프 굴뚝 A: 북동쪽, 위층 발판 4.5 m
##   - 벽 점프 굴뚝 B: 북서쪽(서쪽 외벽과 짝), 위층 발판 6 m
##   - 기둥 4개: 벽 점프 연습용

const Player := preload("res://scripts/player/player_controller.gd")
const TopDownRig := preload("res://scripts/camera/top_down_camera_rig.gd")
const ShoulderRig := preload("res://scripts/camera/shoulder_camera_rig.gd")
const Hud := preload("res://scripts/ui/movement_hud.gd")
const InputSetup := preload("res://scripts/systems/input_setup.gd")
const ShooterEnemy := preload("res://scripts/combat/shooter_enemy.gd")
const RusherEnemy := preload("res://scripts/combat/rusher_enemy.gd")
const CombatFx := preload("res://scripts/systems/combat_fx.gd")
const SpeedLines := preload("res://scripts/fx/speed_lines.gd")
const HitEffects := preload("res://scripts/fx/hit_effects.gd")
const ScreenFx := preload("res://scripts/fx/screen_fx.gd")
const StyleMeter := preload("res://scripts/systems/style_meter.gd")
const Sfx := preload("res://scripts/systems/sfx.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")

## 먹 끌어당김 (먹이 가득 찬 적에게 반사탄 적중, GDD 3.8)
const PULL_RADIUS := 14.0      # 이 거리 안의 다른 적을 끌어당긴다
const PULL_GAP := 2.6          # 중심 적에게서 이만큼 떨어진 자리로
const PULL_HEAL := 25.0
const PULL_CHAIN_INK := 30.0   # 끌려온 적에게도 먹이 묻는다

## 체력 = 먹: 먹을 터뜨리거나 도형으로 가두면 먹을 다시 얻는다 (먹 획을 그리는 데 쓴 만큼 벌충)
const INK_GAIN_BURST := 10.0         # 먹 폭발 1번 (근접·도형)
const INK_GAIN_SHAPE_PER_ENEMY := 5.0  # 도형 안 적 1마리당

## 적중마다 되찾는 회복 가능 체력 (GDD 5.1). 근접이 원거리보다 많다
const RECOVER_ON_HIT := {
	"melee": 15.0,
	"finisher": 24.0,
	"wave": 3.0,
	"wave_big": 4.0,
	"reflect": 12.0,
	"stroke": 20.0,
}

## 먹 스타일 점수 (GDD 5.2)
const STYLE := {
	"melee": ["베기", 40.0],
	"finisher": ["마무리 베기", 70.0],
	"wave": ["검기", 20.0],
	"wave_big": ["큰 검기", 30.0],
	"parry": ["패링", 120.0],
	"reflect": ["반사탄", 80.0],
	"burst": ["먹 폭발", 200.0],
	"pull": ["먹 끌어당김", 300.0],
	"shape": ["먹 도형", 150.0],
	"stroke": ["획 긋기", 60.0],
	"kill": ["처치", 100.0],
}

const ARENA_HALF := 60.0  ## 바닥 한 변의 절반 (m)
const SPAWN := Vector3(0, 0.1, 33)
## 사격형 적 위치와 등급 (0 = 하급, 1 = 중급)
## 중앙·동쪽·굴뚝 A 위 발판(4.5 m)은 하급, 서쪽은 중급(패링 불가 탄 사용)
const ENEMY_SPOTS := [
	[Vector3(0, 0, 0), 0],
	[Vector3(-37.5, 0, -18), 1],
	[Vector3(39, 0, -9), 0],
	[Vector3(56, 4.5, -39), 0],
]
## 돌격형 적 위치와 등급: 열린 바닥에 배치 (중급은 패링 불가 돌진을 섞는다)
const RUSHER_SPOTS := [
	[Vector3(12, 0.1, 9), 0],
	[Vector3(-9, 0.1, -39), 0],
	[Vector3(42, 0.1, 12), 1],
]

## 웨이브 (GDD 7.1): 적이 웨이브로 나오고, 다 처치하면 다음 웨이브. 마지막 웨이브를 끝내면 클리어 평가.
## 각 항목: [종류, 위치, 등급(0 하급 / 1 중급)]
const WAVES := [
	[
		["shooter", Vector3(0, 0, 0), 0],
		["shooter", Vector3(-20, 0, -10), 0],
		["rusher", Vector3(12, 0.1, 9), 0],
	],
	[
		["rusher", Vector3(-12, 0.1, 6), 0],
		["rusher", Vector3(14, 0.1, -6), 0],
		["shooter", Vector3(-37.5, 0, -18), 1],
		["shooter", Vector3(56, 4.5, -39), 0],
	],
	[
		["rusher", Vector3(0, 0.1, -10), 1],
		["shooter", Vector3(39, 0, -9), 1],
		["rusher", Vector3(-15, 0.1, 5), 0],
		["rusher", Vector3(15, 0.1, 5), 0],
		["shooter", Vector3(-25, 0, -30), 0],
	],
]
const WAVE_DELAY := 1.5  # 웨이브를 끝내고 다음 웨이브가 나오기까지 (초)

## false면 연습 모드(모든 적이 한꺼번에, 죽으면 부활). add_child 전에 정한다
var wave_mode := true
var wave := 0               # 지금 웨이브 번호 (1부터, 0 = 시작 전)
var run_time := 0.0         # 이번 판 경과 시간
var hits_taken := 0
var run_cleared := false
var _wave_alive := 0
var _run_id := 0
var _wave_banner: Label
var _result: Label

var fx: CanvasLayer
var speed_lines: CanvasLayer
var hit_fx: Node3D
var screen_fx: CanvasLayer
var style: CanvasLayer
var sfx: Node
var ink_pulls := 0
var enemies: Array[Node] = []
var kills := 0
var ink_bursts := 0
var _active_rig: Node3D

var player: CharacterBody3D
var top_rig: Node3D
var shoulder_rig: Node3D
var hud: CanvasLayer
var _use_shoulder := false

var _mat_floor: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_climb: StandardMaterial3D
var _mat_platform: StandardMaterial3D


func _ready() -> void:
	add_to_group("combat_events")
	InputSetup.ensure_actions()
	_build_environment()
	_build_materials()
	_build_arena()

	player = Player.new()
	player.position = SPAWN
	add_child(player)

	top_rig = TopDownRig.new()
	add_child(top_rig)
	top_rig.target = player
	shoulder_rig = ShoulderRig.new()
	add_child(shoulder_rig)
	shoulder_rig.target = player

	fx = CombatFx.new()
	add_child(fx)
	speed_lines = SpeedLines.new()
	add_child(speed_lines)
	speed_lines.player = player
	hit_fx = HitEffects.new()
	add_child(hit_fx)
	screen_fx = ScreenFx.new()
	add_child(screen_fx)
	style = StyleMeter.new()
	add_child(style)
	sfx = Sfx.new()
	add_child(sfx)
	sfx.set("listener", player)
	add_child(PauseMenu.new())  # Esc: 일시정지·설정 (음량, 임팩트 프레임)

	if not wave_mode:
		# 연습 모드: 모든 적을 한꺼번에 두고, 죽으면 잠시 뒤 다시 살아난다
		for spot in ENEMY_SPOTS:
			_spawn_enemy("shooter", spot[0], spot[1], true)
		for spot in RUSHER_SPOTS:
			_spawn_enemy("rusher", spot[0], spot[1], true)

	hud = Hud.new()
	add_child(hud)
	hud.player = player
	player.respawned.connect(hud.reset_top_speed)
	player.parried.connect(_on_parried)
	# 속도감 연출: 동작마다 카메라 흔들림·시야 킥 (GDD 4.1)
	player.dashed.connect(func():
		_feedback(0.25, 8.0)
		sfx.call("play", "dash"))
	player.wall_jumped.connect(func():
		_feedback(0.12, 0.0)
		sfx.call("play", "wall_jump"))
	# 버니합을 이어 갈수록 점프 소리가 조금씩 높아진다
	player.jumped.connect(func(): sfx.call("play", "jump", 0.0, 1.0 + 0.06 * mini(int(player.get("bhop_chain")), 6)))
	player.slide_started.connect(func(): sfx.call("play", "slide"))
	player.sword.swung.connect(func(combo: int): sfx.call("play", "swing_big" if combo == 3 else "swing"))
	player.sword.charge_level_up.connect(func(lv: int): sfx.call("play", "charge", 0.0, 1.0 if lv == 1 else 1.5))
	player.landed.connect(_on_landed)
	player.damaged.connect(_on_player_damaged)
	player.sword.hit_enemy.connect(_on_sword_hit)
	player.sword.ink_burst.connect(_on_ink_burst)
	player.ink_trail.shape_closed.connect(_on_ink_shape)
	player.ink_trail.ink_burst.connect(_on_ink_burst)  # 도형 안 먹 스택 폭발
	player.sword.stroke_struck.connect(_on_stroke_struck)

	_set_camera_mode(false)
	_build_run_ui()
	if wave_mode:
		player.respawned.connect(_restart_run)  # 죽거나 R: 1초 안에 판 전체를 처음부터 (GDD 8.2)
		_restart_run()


# ---------------------------------------------------------------- 웨이브·판 (GDD 7.1, 5.2, 8.2)

func _spawn_enemy(kind: String, pos: Vector3, tier: int, respawns: bool) -> Node:
	var e: Node3D = ShooterEnemy.new() if kind == "shooter" else RusherEnemy.new()
	e.position = pos
	e.set("tier", tier)
	e.set("respawns", respawns)
	e.set("target", player)  # 돌격형은 _ready에서 플레이어와의 충돌 예외를 걸기 때문에 add_child 전에 정한다
	add_child(e)
	e.died.connect(_on_enemy_died)
	enemies.append(e)
	return e


## 판 전체를 처음 상태로: 적·탄·검기·먹 획을 지우고 점수·시간·웨이브를 되돌린 뒤 1웨이브부터
func _restart_run() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	_run_id += 1
	for group in ["projectile", "player_wave"]:
		for n in get_tree().get_nodes_in_group(group):
			n.queue_free()
	if player.ink_trail:
		player.ink_trail.call("end_stroke")
	style.set("points", 0.0)
	style.set("best_rank", -1)
	(style.get("_recent") as Array).clear()
	kills = 0
	hud.set("kills", 0)
	hits_taken = 0
	run_time = 0.0
	run_cleared = false
	wave = 0
	_result.visible = false
	sfx.call("play", "wave_start", 0.0, 0.85)  # 재시작
	_next_wave()


func _next_wave() -> void:
	wave += 1
	_wave_alive = 0
	for entry in WAVES[wave - 1]:
		_spawn_enemy(entry[0], entry[1], entry[2], false)
		_wave_alive += 1
	_show_banner("웨이브 %d / %d" % [wave, WAVES.size()])
	if wave > 1:
		sfx.call("play", "wave_start", 0.0, 1.0 + 0.06 * (wave - 1))


func _on_wave_enemy_down() -> void:
	_wave_alive -= 1
	if _wave_alive > 0 or run_cleared:
		return
	if wave >= WAVES.size():
		_clear_run()
		return
	var this_run := _run_id
	get_tree().create_timer(WAVE_DELAY).timeout.connect(func():
		if _run_id == this_run and not run_cleared:  # 그사이 재시작했으면 무시
			_next_wave())


## 클리어 평가 (GDD 5.2): 클리어 시간, 최고 먹 스타일 등급, 피격 횟수
func _clear_run() -> void:
	run_cleared = true
	var best: int = style.get("best_rank")
	var ranks: Array = StyleMeter.RANKS
	var best_name: String = "-" if best < 0 else String(ranks[best])
	_result.text = "아레나 클리어\n\n클리어 시간  %d:%05.2f\n최고 등급  %s\n피격  %d회\n\nR: 다시 시작" % [
		int(run_time / 60.0), fmod(run_time, 60.0), best_name, hits_taken]
	_result.visible = true
	sfx.call("play", "clear")
	fx.call("impact_frame", "clear", 4, true)
	_feedback(0.5, -6.0)


func _show_banner(text: String) -> void:
	_wave_banner.text = text
	_wave_banner.modulate.a = 1.0
	var tw := _wave_banner.create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_wave_banner, "modulate:a", 0.0, 0.6)


func _build_run_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_wave_banner = Label.new()
	_wave_banner.add_theme_font_size_override("font_size", 44)
	_wave_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_wave_banner.add_theme_constant_override("outline_size", 8)
	_wave_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wave_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_banner.offset_left = -300
	_wave_banner.offset_right = 300
	_wave_banner.offset_top = 90
	_wave_banner.modulate.a = 0.0
	layer.add_child(_wave_banner)
	_result = Label.new()
	_result.add_theme_font_size_override("font_size", 34)
	_result.add_theme_color_override("font_outline_color", Color.BLACK)
	_result.add_theme_constant_override("outline_size", 8)
	_result.set_anchors_preset(Control.PRESET_CENTER)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result.offset_left = -320
	_result.offset_right = 320
	_result.offset_top = -170
	_result.offset_bottom = 170
	_result.visible = false
	layer.add_child(_result)


## 먹 획과 검(붓 단계)은 먹 스타일 등급 하나로 강화된다 (ink_trail.gd TIERS, sword.gd INK_STAGES)
func _process(delta: float) -> void:
	if wave_mode and not run_cleared:
		run_time += delta
	if player and player.ink_trail and style:
		var r := int(style.call("rank"))
		player.ink_trail.set("rank", maxi(r, 0))
		player.sword.set("rank", r)


func _feedback(trauma: float, fov: float) -> void:
	if _active_rig == null:
		return
	if trauma > 0.0:
		_active_rig.call("shake", trauma)
	if fov != 0.0:
		_active_rig.call("fov_kick", fov)  # 양수 = 넓게(대시), 음수 = 줌 펀치(큰 타격)


func _on_landed(fall_speed: float) -> void:
	if fall_speed > 3.0:
		sfx.call("play", "land", lerpf(-10.0, 4.0, clampf((fall_speed - 3.0) / 25.0, 0.0, 1.0)))
	# 높은 곳에서 떨어질수록 세게 (점프 한 번 착지 ≈ 11 m/s는 흔들지 않음)
	if fall_speed > 14.0:
		_feedback(clampf((fall_speed - 14.0) / 16.0, 0.1, 0.5), 0.0)


## 검 적중: 공격 종류마다 다른 이펙트. 근접은 묵직하게(히트스톱·흔들림 크게), 검기는 가볍게
func _on_sword_hit(enemy: Node, killed: bool, melee: bool, kind: String) -> void:
	var pos: Vector3 = enemy.call("aim_point")
	var dir := pos - player.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(0, 0, -1)
	_style(kind)
	# 반격으로 회복 가능 체력을 되찾는다: 가까이 붙어 벨수록 많이 (GDD 5.1)
	_recover(float(RECOVER_ON_HIT.get(kind, 0.0)))
	var sword: Node = player.get("sword")
	match kind:
		"finisher", "stroke":
			sfx.call("play", "hit_heavy")
		"melee":
			sfx.call("play", "hit")
		_:
			sfx.call("play", "wave_hit", 2.0 if kind == "wave_big" else 0.0)
	match kind:
		"finisher":
			hit_fx.call("finisher_hit", pos, dir, sword.get("finisher_damage"))
			_big_moment(pos, 0.08, -6.0, 90.0)
		"melee":
			hit_fx.call("melee_hit", pos, dir, sword.get("melee_damage"))
		"wave_big":
			hit_fx.call("wave_hit", pos, dir, float(sword.get("wave_damage")) * 1.5)
		_:
			hit_fx.call("wave_hit", pos, dir, sword.get("wave_damage"))
	if killed:
		return  # 처치 연출(히트스톱·임팩트 프레임·파편)은 _on_enemy_died에서
	if melee:
		fx.call("hitstop", 0.045)
		_feedback(0.18, 0.0)
	else:
		fx.call("hitstop", 0.02)
		_feedback(0.08, 0.0)


## 먹 폭발: 근접으로 쌓인 먹을 터뜨렸다 → 가장 큰 순간 중 하나로 연출
func _on_ink_burst(enemy: Node, bonus: float, _killed: bool) -> void:
	var base := (enemy as Node3D).global_position
	var pos: Vector3 = enemy.call("aim_point")
	hit_fx.call("ink_burst", pos, base, bonus)
	sfx.call("play", "ink_burst")
	ink_bursts += 1
	_style("burst")
	_gain_ink(INK_GAIN_BURST)
	fx.call("hitstop", 0.07)
	fx.call("impact_frame", "ink_burst", 2, false)
	_big_moment(pos, 0.12, -7.0, 140.0)
	_feedback(0.4, 0.0)


## 일필휘지 차지 획 긋기: 바닥을 가르는 한 획. 최대 차지는 가장 큰 순간으로 연출
func _on_stroke_struck(from: Vector3, to: Vector3, level: int) -> void:
	var mid := from.lerp(to, 0.5) + Vector3.UP
	sfx.call("play", "stroke_big" if level >= 2 else "stroke")
	if level >= 2:
		fx.call("hitstop", 0.08)
		fx.call("impact_frame", "stroke", 2, false)
		_big_moment(mid, 0.12, -7.0, 160.0)
		_feedback(0.5, 0.0)
	else:
		fx.call("hitstop", 0.04)
		_big_moment(mid, 0.06, -4.0, 110.0)
		_feedback(0.25, 0.0)


## 먹 도형: 슬라이드 먹 획으로 닫힌 도형을 그렸다. 안에 적이 많을수록 점수가 크다
func _on_ink_shape(center: Vector3, inside: Array, _killed: int) -> void:
	if inside.is_empty():
		_feedback(0.08, 0.0)
		return
	var n := inside.size()
	sfx.call("play", "shape", 0.0, 1.0 + 0.08 * mini(n - 1, 4))
	_style("shape", 1.0 + 0.5 * (n - 1), " ×%d" % n if n > 1 else "")
	_gain_ink(INK_GAIN_SHAPE_PER_ENEMY * n)
	for e in inside:
		if is_instance_valid(e):
			hit_fx.call("damage_number", e.call("aim_point"), player.ink_trail.call("shape_damage"), n > 1)
	fx.call("hitstop", 0.05)
	_big_moment(center + Vector3.UP, 0.1, -5.0, 120.0)
	_feedback(0.3, 0.0)


func _on_player_damaged(_amount: float) -> void:
	hits_taken += 1
	sfx.call("play", "hurt")
	_feedback(0.3, 0.0)
	style.call("on_damaged")  # 피격하면 스타일이 한 등급만큼 깎인다


## 먹 스타일 점수 추가 (STYLE 표 기준). mul: 공중·슬라이드 처치 같은 보너스
func _style(id: String, mul := 1.0, label_suffix := "") -> void:
	if not STYLE.has(id):
		return
	var entry: Array = STYLE[id]
	style.call("add", id, String(entry[0]) + label_suffix, float(entry[1]) * mul)


## 반사탄이 적에게 맞았다 (projectile.gd → 그룹 "combat_events")
func on_reflect_hit(enemy: Node, _killed: bool, ink_full: bool) -> void:
	_style("reflect")
	sfx.call("play_at", "hit", (enemy as Node3D).global_position, 0.0, 1.15)
	_recover(float(RECOVER_ON_HIT["reflect"]))
	if ink_full:
		_ink_pull(enemy)


## 먹 끌어당김: 먹이 가득 찬 적을 중심으로 주변 적을 끌어모으고, 체력을 회복하고, 스타일 점수를 크게 얻는다.
## 끌려온 적에게도 먹이 묻는다 → 모아 놓고 근접으로 한꺼번에 터뜨리는 흐름
func _ink_pull(center_enemy: Node) -> void:
	var center := (center_enemy as Node3D).global_position
	var from_points := []
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == center_enemy:
			continue
		var n := e as Node3D
		var flat := Vector3(n.global_position.x - center.x, 0.0, n.global_position.z - center.z)
		if flat.length() > PULL_RADIUS or flat.length() < 0.1:
			continue
		from_points.append(n.global_position)
		var target := center + flat.normalized() * PULL_GAP
		target.y = _floor_y(target, center.y)
		e.call("pull_to", target, 0.3)
		var ink: Node = e.get("ink")
		if ink:
			ink.call("add", PULL_CHAIN_INK)
	ink_pulls += 1
	player.call("heal", PULL_HEAL)
	hit_fx.call("ink_pull", center, from_points)
	sfx.call("play", "pull")
	hit_fx.call("heal_text", player.global_position, PULL_HEAL)
	_style("pull")
	fx.call("hitstop", 0.06)
	_big_moment(center + Vector3.UP * 1.2, 0.12, -6.0, 130.0)
	_feedback(0.35, 0.0)


func _gain_ink(amount: float) -> void:
	var before: float = player.get("health")
	player.call("heal", amount)
	var got := float(player.get("health")) - before
	if got >= 1.0:
		hit_fx.call("heal_text", player.global_position, got)
		sfx.call("play", "heal")


func _recover(amount: float) -> void:
	var got: float = player.call("recover", amount)
	if got >= 1.0:
		hit_fx.call("heal_text", player.global_position, got)
		sfx.call("play", "heal")


## target 바로 아래 바닥 높이 (없으면 fallback)
func _floor_y(target: Vector3, fallback: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(target + Vector3.UP * 3.0, target + Vector3.DOWN * 20.0)
	var ex: Array[RID] = []
	for e in get_tree().get_nodes_in_group("enemy"):
		ex.append((e as CollisionObject3D).get_rid())
	ex.append(player.get_rid())
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return fallback if hit.is_empty() else float((hit["position"] as Vector3).y)


## 큰 순간 연출: 화면을 가로지르는 붓터치 + 줌 블러 + 줌 펀치(시야를 확 당김)
func _big_moment(world_pos: Vector3, blur: float, zoom: float, slash_width: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var size := get_viewport().get_visible_rect().size
	var px := size * 0.5
	if cam and not cam.is_position_behind(world_pos):
		px = cam.unproject_position(world_pos)
	screen_fx.call("slash", px, randf_range(-35.0, -15.0) if randf() < 0.5 else randf_range(15.0, 35.0), slash_width)
	screen_fx.call("zoom_blur", blur, px / size)
	_feedback(0.0, zoom)


func _on_parried(_projectile: Node) -> void:
	fx.call("hitstop", 0.08)
	fx.call("impact_frame", "parry", 2, true)
	_feedback(0.35, 0.0)
	hit_fx.call("parry_text", player.global_position)
	sfx.call("play", "parry")
	_style("parry")
	var cam := get_viewport().get_camera_3d()
	var size := get_viewport().get_visible_rect().size
	var px := cam.unproject_position(player.global_position + Vector3.UP) if cam else size * 0.5
	screen_fx.call("zoom_blur", 0.06, px / size)
	_feedback(0.0, -4.0)


func _on_enemy_died(enemy: Node) -> void:
	if wave_mode:
		_on_wave_enemy_down()
	kills += 1
	hud.set("kills", kills)
	# 처치 보너스: 공중(벽·대시 포함) 처치 ×1.5, 슬라이드 중 처치 ×1.3
	var st: String = player.call("state_name")
	if st in ["공중", "벽 붙기", "대시"]:
		_style("kill", 1.5, " (공중)")
	elif st == "슬라이드":
		_style("kill", 1.3, " (슬라이드)")
	else:
		_style("kill")
	var epos := (enemy as Node3D).global_position
	var elite: bool = enemy.call("is_elite")
	hit_fx.call("enemy_killed", epos, enemy.call("body_height"), elite)
	sfx.call("play", "kill", 2.0 if elite else 0.0, 0.8 if elite else 1.0)
	_big_moment(epos + Vector3.UP * 1.2, 0.14 if elite else 0.1, -9.0 if elite else -7.0, 150.0 if elite else 120.0)
	fx.call("hitstop", 0.05)
	fx.call("impact_frame", "kill", 3, false)
	_feedback(0.45, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		_set_camera_mode(not _use_shoulder)


func _set_camera_mode(shoulder: bool) -> void:
	_use_shoulder = shoulder
	var rig: Node3D = shoulder_rig if shoulder else top_rig
	top_rig.call("activate", not shoulder)
	shoulder_rig.call("activate", shoulder)
	player.set("camera_rig", rig)
	hud.set("mode_name", rig.call("mode_name"))
	_active_rig = rig
	if speed_lines:
		speed_lines.set("camera_rig", rig)


# ---------------------------------------------------------------- 환경

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.36, 0.45)
	sky_mat.sky_horizon_color = Color(0.6, 0.62, 0.66)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.66)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# 블룸: 밝기 1을 넘는 발광(탄, 적의 눈, 패링 부채꼴)만 번지게 (GDD 9.1)
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 1.0
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 130.0
	add_child(sun)


func _build_materials() -> void:
	_mat_floor = _checker(Color(0.34, 0.34, 0.36), Color(0.29, 0.29, 0.31), 0.25)
	_mat_wall = _checker(Color(0.52, 0.52, 0.55), Color(0.47, 0.47, 0.5), 0.5)
	# 탈 수 있는 벽 표시용 (GDD 3.3): 푸른빛 줄무늬 느낌
	_mat_climb = _checker(Color(0.36, 0.46, 0.62), Color(0.28, 0.36, 0.5), 1.0)
	_mat_platform = _checker(Color(0.58, 0.54, 0.47), Color(0.52, 0.48, 0.42), 0.5)


## 2×2 체커 텍스처를 월드 좌표 기준(트라이플래너)으로 입힌다. 칸 크기 = 0.5 / scale m.
func _checker(c1: Color, c2: Color, scale: float) -> StandardMaterial3D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, c1)
	img.set_pixel(1, 1, c1)
	img.set_pixel(1, 0, c2)
	img.set_pixel(0, 1, c2)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = 0.9
	return m


# ---------------------------------------------------------------- 아레나

func _build_arena() -> void:
	var h := ARENA_HALF
	# 바닥 120 × 120 m (윗면 y = 0)
	_box(Vector3(0, -0.5, 0), Vector3(h * 2.0, 1, h * 2.0), _mat_floor)

	# 외벽: 카메라 쪽(남쪽)은 낮게 해서 시야를 가리지 않는다 (GDD 7.3)
	_block(0, -h - 0.5, h * 2.0 + 2.0, 1, 10, _mat_wall)      # 북
	_block(-h - 0.5, 0, 1, h * 2.0, 10, _mat_climb)           # 서 (굴뚝 B의 한쪽 벽)
	_block(h + 0.5, 0, 1, h * 2.0, 10, _mat_wall)             # 동
	_block(0, h + 0.5, h * 2.0 + 2.0, 1, 1.2, _mat_wall)      # 남 (낮은 벽)

	# 슬라이드 레인: 폭 3 m, 길이 60 m의 낮은 벽 통로
	_block(-24, 49.5, 60, 1, 1.2, _mat_wall)
	_block(-24, 53.5, 60, 1, 1.2, _mat_wall)

	# 계단 블록: 점프 한 번(2.5 m)으로 한 칸씩 오른다
	_block(-4, -30, 4, 4, 1.8, _mat_platform)
	_block(0, -30, 4, 4, 3.5, _mat_platform)
	_block(5, -30, 6, 6, 5.0, _mat_platform)

	# 굴뚝 A (북동): 3.5 m 간격의 두 벽 사이를 벽 점프로 오른 뒤 동쪽 발판(4.5 m)으로
	_block(44, -38, 12, 1, 12, _mat_climb)
	_block(44, -33.5, 12, 1, 12, _mat_climb)
	_block(h - 5.0, -36, 10, 14, 4.5, _mat_platform)

	# 굴뚝 B (북서): 서쪽 외벽과 안쪽 벽 사이 3 m 틈을 올라 북쪽 발판(6 m)으로
	_block(-h + 3.5, -40.5, 1, 13, 12, _mat_climb)
	_block(-h + 5.0, -h + 7.0, 10, 12, 6, _mat_platform)

	# 기둥: 벽 점프·우회 연습
	for p in [Vector2(-22.5, -3), Vector2(22.5, -3), Vector2(-22.5, 18), Vector2(22.5, 18)]:
		_block(p.x, p.y, 2, 2, 9, _mat_climb)

	# 슬라이드 점프 연습: 4 m 간격의 낮은 단상 두 개
	_block(34, 40, 8, 8, 1.0, _mat_platform)
	_block(46, 40, 8, 8, 1.0, _mat_platform)


## 바닥(y=0)에 놓인 블록. (x, z)는 중심, h는 높이.
func _block(x: float, z: float, sx: float, sz: float, h: float, mat: Material) -> void:
	_box(Vector3(x, h * 0.5, z), Vector3(sx, h, sz), mat)


func _box(center: Vector3, size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)
