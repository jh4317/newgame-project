extends CanvasLayer
## HUD: 먹 막대(항상) + 숄더뷰 조준점(항상) + 글자 정보(디버그 모드에서만).
## 글자 정보 = 먹 수치·콤보·패링·속도·상태·스태미나·버니합·높이·시점, 아래쪽 조작 안내.
## 디버그 모드는 F1 (style_meter.gd의 is_debug()).

var player: CharacterBody3D
var mode_name := ""
var kills := 0
var _info: Label
var _help: Label
var _crosshair: Label
var _top_speed := 0.0
## 먹 막대 (체력 = 먹): 검은 먹 = 현재 먹, 회색 = 흘린 먹(회복 가능), 바탕은 흰 종이.
## 붉은색은 경고 전용이라 쓰지 않는다
const BAR_SIZE := Vector2(320, 14)
var _bar_health: ColorRect
var _bar_recover: ColorRect


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.93, 0.92, 0.88, 0.9)  # 종이
	bg.position = Vector2(14, 10)
	bg.size = BAR_SIZE + Vector2(4, 4)
	add_child(bg)
	_bar_recover = ColorRect.new()
	_bar_recover.color = Color(0.55, 0.55, 0.57)
	_bar_recover.position = Vector2(16, 12)
	add_child(_bar_recover)
	_bar_health = ColorRect.new()
	_bar_health.color = Color(0.04, 0.04, 0.05)  # 먹
	_bar_health.position = Vector2(16, 12)
	add_child(_bar_health)

	_info = _make_label(18)
	_info.position = Vector2(16, 32)
	add_child(_info)

	_crosshair = _make_label(28)
	_crosshair.text = "+"
	add_child(_crosshair)

	var help := _make_label(15)
	_help = help
	help.text = "WASD 이동 · Space 점프/벽 점프(착지 직후=버니합) · Ctrl 슬라이드 · Shift 대시 · 좌클릭 검(근접+검기, 3타 콤보) · F/우클릭 패링 · V 시점 · R 리스폰 · Esc 메뉴 · F1 디버그 모드"
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.offset_left = 16
	help.offset_right = 1200
	help.offset_top = -40
	help.offset_bottom = -12
	add_child(help)


func _process(_delta: float) -> void:
	if player == null:
		return
	var speed: float = player.call("horizontal_speed")
	_top_speed = maxf(_top_speed, speed)
	var pips: int = player.call("stamina_pips")
	var stamina: float = player.get("stamina")
	var dots := ""
	for i in 3:
		dots += "● " if i < pips else "○ "
	if stamina < 3.0:
		dots += "(회복 %d%%)" % int((stamina - pips) * 100.0)
	var chain: int = player.get("bhop_chain")
	var hp: float = player.get("health")
	var rec: float = player.get("recoverable")
	var max_hp: float = player.get("max_health")
	_bar_health.size = Vector2(BAR_SIZE.x * clampf(hp / max_hp, 0.0, 1.0), BAR_SIZE.y)
	_bar_recover.size = Vector2(BAR_SIZE.x * clampf((hp + rec) / max_hp, 0.0, 1.0), BAR_SIZE.y)
	var sword: Node = player.get("sword")
	var combo: int = sword.get("combo") if sword else 0
	var dry: bool = player.get("_ink_dry")
	_info.text = ("먹 %d / 100  (흘린 먹 %d)" + ("  · 먹 부족: 획을 못 그림" if dry else "") + "\n검 콤보: %d / 3  · 붓: " + (String(sword.call("ink_stage_name")) if sword else "-") + "\n패링: %s  (성공 %d · 처치 %d)\n\n속도 %5.1f m/s  (최고 %4.1f)\n상태: %s\n"
		+ "스태미나(벽 점프·대시): %s\n버니합 연속: %d\n높이: %4.1f m\n시점: %s") % [
		int(hp), int(rec), combo, player.call("parry_status"), player.get("parry_count"), kills,
		speed, _top_speed, player.call("state_name"), dots, chain, player.global_position.y, mode_name]
	_crosshair.visible = mode_name == "숄더뷰"
	# 글자 정보는 디버그 모드(F1)에서만
	var style := get_tree().get_first_node_in_group("style_meter")
	var debug := style != null and bool(style.call("is_debug"))
	_info.visible = debug
	_help.visible = debug
	_crosshair.position = _crosshair.get_viewport_rect().size * 0.5 - _crosshair.size * 0.5


func reset_top_speed() -> void:
	_top_speed = 0.0


func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	return l
