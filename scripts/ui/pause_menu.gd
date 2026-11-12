extends CanvasLayer
## 일시정지·설정 메뉴 (GDD 8.2 설정, 접근성)
## Esc(패드 Start)로 열고 닫는다. 열려 있는 동안 게임이 멈춘다.
##   - 효과음 음량 (0이면 끔)
##   - 임팩트 프레임(흑백 번쩍임) 켜기/끄기 — 번쩍임에 민감한 사람을 위한 접근성 설정
##   - 계속하기 / 다시 시작 / 게임 종료
## 설정은 user://settings.cfg에 저장돼 다음 실행에도 유지된다.
## 효과음(그룹 "sfx")·연출(그룹 "combat_fx")·플레이어(그룹 "player")를 그룹으로 찾아 쓴다.

const SAVE_PATH := "user://settings.cfg"

var sfx_volume := 100.0      # 0~100
var impact_frames := true

var _root: Control
var _resume: Button
var _volume: HSlider
var _volume_label: Label
var _impact: CheckButton
var _mouse_before := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	layer = 110  # 임팩트 프레임(100)보다 위
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_build()
	_root.visible = false
	_apply.call_deferred()  # 다른 노드가 그룹에 들어간 뒤에 적용


func _unhandled_input(event: InputEvent) -> void:
	var esc: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE
	var start: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START
	if esc or start:
		set_open(not _root.visible)
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _root.visible


func set_open(open: bool) -> void:
	if open == _root.visible:
		return
	_root.visible = open
	get_tree().paused = open
	if open:
		_mouse_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_resume.grab_focus()
	else:
		Input.mouse_mode = _mouse_before
		_save()


func _exit_tree() -> void:
	get_tree().paused = false


# ---------------------------------------------------------------- 설정 적용·저장

func _apply() -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx:
		sfx.set("enabled", sfx_volume > 0.5)
		sfx.set("master_db", linear_to_db(maxf(sfx_volume, 1.0) / 100.0))
	var fx := get_tree().get_first_node_in_group("combat_fx")
	if fx:
		fx.set("enabled", impact_frames)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 100.0)
	impact_frames = bool(cfg.get_value("accessibility", "impact_frames", impact_frames))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("accessibility", "impact_frames", impact_frames)
	cfg.save(SAVE_PATH)


# ---------------------------------------------------------------- 화면

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.91, 0.84)  # 흰 종이
	style.border_color = Color(0.07, 0.07, 0.1)
	style.set_border_width_all(4)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var ink := Color(0.07, 0.07, 0.1)
	var title := Label.new()
	title.text = "일시정지"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", ink)
	box.add_child(title)

	_resume = _button("계속하기", func(): set_open(false))
	box.add_child(_resume)

	box.add_child(HSeparator.new())

	_volume_label = Label.new()
	_volume_label.add_theme_color_override("font_color", ink)
	box.add_child(_volume_label)
	_volume = HSlider.new()
	_volume.min_value = 0
	_volume.max_value = 100
	_volume.step = 5
	_volume.value = sfx_volume
	_volume.value_changed.connect(_on_volume_changed)
	# 손을 뗄 때 들어 보라고 소리를 낸다
	_volume.drag_ended.connect(func(_changed): get_tree().call_group("sfx", "play", "parry"))
	box.add_child(_volume)
	_on_volume_changed(sfx_volume)

	_impact = CheckButton.new()
	_impact.text = "임팩트 프레임 (흑백 번쩍임)"
	_impact.button_pressed = impact_frames
	_impact.add_theme_color_override("font_color", ink)
	_impact.add_theme_color_override("font_pressed_color", ink)
	_impact.add_theme_color_override("font_hover_color", ink)
	_impact.add_theme_color_override("font_hover_pressed_color", ink)
	_impact.add_theme_color_override("font_focus_color", ink)
	_impact.toggled.connect(func(on: bool):
		impact_frames = on
		_apply())
	box.add_child(_impact)

	box.add_child(HSeparator.new())

	box.add_child(_button("다시 시작", func():
		set_open(false)
		var p := get_tree().get_first_node_in_group("player")
		if p:
			p.call("respawn")))
	box.add_child(_button("게임 종료", func():
		_save()
		get_tree().quit()))

	var hint := Label.new()
	hint.text = "Esc: 닫기"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.07, 0.07, 0.1, 0.6))
	box.add_child(hint)


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 42
	b.pressed.connect(on_pressed)
	return b


func _on_volume_changed(v: float) -> void:
	sfx_volume = v
	_volume_label.text = "효과음 음량  %d" % int(v) if v > 0.5 else "효과음 음량  끔"
	_apply()
