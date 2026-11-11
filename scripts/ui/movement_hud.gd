extends CanvasLayer
## 이동 프로토타입용 디버그 HUD: 속도, 상태, 벽 점프 횟수, 시점, 조작법.

var player: CharacterBody3D
var mode_name := ""
var kills := 0
var _info: Label
var _crosshair: Label
var _top_speed := 0.0


func _ready() -> void:
	_info = _make_label(18)
	_info.position = Vector2(16, 12)
	add_child(_info)

	_crosshair = _make_label(28)
	_crosshair.text = "+"
	add_child(_crosshair)

	var help := _make_label(15)
	help.text = "WASD 이동 · Space 점프/벽 점프(착지 직후=버니합) · Shift 슬라이드 · E 대시 · 좌클릭 검(근접+검기, 3타 콤보) · F/우클릭 패링 · V 시점 · R 리스폰"
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
	var sword: Node = player.get("sword")
	var combo: int = sword.get("combo") if sword else 0
	_info.text = ("체력 %d / 100\n검 콤보: %d / 3\n패링: %s  (성공 %d · 처치 %d)\n\n속도 %5.1f m/s  (최고 %4.1f)\n상태: %s\n"
		+ "스태미나(벽 점프·대시): %s\n버니합 연속: %d\n높이: %4.1f m\n시점: %s") % [
		int(hp), combo, player.call("parry_status"), player.get("parry_count"), kills,
		speed, _top_speed, player.call("state_name"), dots, chain, player.global_position.y, mode_name]
	_crosshair.visible = mode_name == "숄더뷰"
	_crosshair.position = _crosshair.get_viewport_rect().size * 0.5 - _crosshair.size * 0.5


func reset_top_speed() -> void:
	_top_speed = 0.0


func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	return l
