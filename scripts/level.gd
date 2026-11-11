extends Node2D
## ASCII 맵으로 스테이지를 만들고 게임 진행(별 수집, 재시작, 클리어)을 관리한다.
## '#' 블록, '^' 가시, '*' 별, 'P' 시작 위치, '.' 빈칸

const Ball := preload("res://scripts/ball.gd")
const Star := preload("res://scripts/star.gd")

const TILE := 48
const MAP := [
	"....................",
	"....................",
	"....................",
	"..................*.",
	".................###",
	"...............*....",
	"..............###...",
	"..........*.........",
	".........###........",
	"..*.###.............",
	".P......^^^^^^...*..",
	"####################",
]

const BLOCK_COLOR := Color(0.95, 0.55, 0.3)
const BLOCK_EDGE := Color(0.7, 0.35, 0.2)
const SPIKE_COLOR := Color(0.9, 0.25, 0.3)

var _blocks: Array[Vector2i] = []
var _spikes: Array[Vector2i] = []
var _stars_left := 0
var _cleared := false
var _ball: CharacterBody2D
var _info: Label
var _banner: Label


func _ready() -> void:
	var solid := StaticBody2D.new()
	add_child(solid)
	var hazard := Area2D.new()
	add_child(hazard)
	hazard.body_entered.connect(_on_hazard)

	var start := Vector2(TILE * 1.5, TILE * 10.5)
	for y in MAP.size():
		var row: String = MAP[y]
		var run_start := -1
		for x in row.length() + 1:
			var c := row[x] if x < row.length() else "."
			# 이어진 블록은 하나의 충돌 사각형으로 합친다 (이음새에 걸리지 않게)
			if c == "#":
				_blocks.append(Vector2i(x, y))
				if run_start < 0:
					run_start = x
			elif run_start >= 0:
				_add_rect(solid, Rect2(run_start * TILE, y * TILE, (x - run_start) * TILE, TILE))
				run_start = -1
			var center := Vector2(x * TILE + TILE / 2.0, y * TILE + TILE / 2.0)
			match c:
				"^":
					_spikes.append(Vector2i(x, y))
					_add_rect(hazard, Rect2(x * TILE + 6, y * TILE + 26, TILE - 12, TILE - 26))
				"*":
					var star := Star.new()
					star.position = center
					star.collected.connect(_on_star_collected)
					add_child(star)
					_stars_left += 1
				"P":
					start = center

	# 화면 좌우 벽
	var w: int = MAP[0].length() * TILE
	_add_rect(solid, Rect2(-TILE, -TILE * 4, TILE, TILE * 20))
	_add_rect(solid, Rect2(w, -TILE * 4, TILE, TILE * 20))

	_ball = Ball.new()
	_ball.position = start
	_ball.died.connect(_restart)
	add_child(_ball)

	_build_ui()
	queue_redraw()


func _add_rect(body: CollisionObject2D, r: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = r.size
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = r.position + r.size / 2.0
	body.add_child(col)


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	_info = Label.new()
	_info.position = Vector2(16, 10)
	_info.add_theme_font_size_override("font_size", 20)
	ui.add_child(_info)
	_banner = Label.new()
	_banner.position = Vector2(0, 220)
	_banner.size = Vector2(MAP[0].length() * TILE, 120)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 40)
	_banner.visible = false
	ui.add_child(_banner)
	_update_info()


func _update_info() -> void:
	_info.text = "STAGE 1   ★ 남은 별: %d\n←/→ 또는 A/D 이동   R 재시작" % _stars_left


func _on_star_collected() -> void:
	_stars_left -= 1
	_update_info()
	if _stars_left <= 0:
		_cleared = true
		_ball.set_physics_process(false)
		_banner.text = "STAGE CLEAR!\nR 또는 Enter로 다시 하기"
		_banner.visible = true


func _on_hazard(body: Node) -> void:
	if body.is_in_group("ball") and not _cleared:
		_restart()


func _restart() -> void:
	get_tree().reload_current_scene.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			_restart()
		elif _cleared and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_restart()


func _draw() -> void:
	for b in _blocks:
		var r := Rect2(b.x * TILE, b.y * TILE, TILE, TILE)
		draw_rect(r, BLOCK_COLOR)
		draw_rect(r.grow(-1), BLOCK_EDGE, false, 2.0)
	for s in _spikes:
		var x0 := s.x * TILE
		var y1 := (s.y + 1) * TILE
		for i in 3:
			var left := x0 + i * 16
			draw_colored_polygon(PackedVector2Array([
				Vector2(left, y1), Vector2(left + 8, y1 - 22), Vector2(left + 16, y1),
			]), SPIKE_COLOR)
