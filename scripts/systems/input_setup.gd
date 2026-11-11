extends RefCounted
## 이동 프로토타입에서 쓰는 입력 액션을 코드로 등록한다.
## (나중에 프로젝트 설정의 Input Map으로 옮겨도 된다)


static func ensure_actions() -> void:
	if InputMap.has_action("jump"):
		return  # 씬을 다시 불러와도 중복 등록하지 않는다
	_add_keys("move_forward", [KEY_W, KEY_UP])
	_add_keys("move_back", [KEY_S, KEY_DOWN])
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("jump", [KEY_SPACE])
	_add_keys("slide", [KEY_CTRL, KEY_C])
	_add_keys("dash", [KEY_SHIFT, KEY_E])
	_add_keys("parry", [KEY_F])
	_add_mouse("parry", MOUSE_BUTTON_RIGHT)
	_add_mouse("attack", MOUSE_BUTTON_LEFT)
	_add_keys("attack", [KEY_J])
	_add_keys("toggle_camera", [KEY_V])
	_add_keys("restart", [KEY_R])

	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_button("jump", JOY_BUTTON_A)
	_add_joy_button("slide", JOY_BUTTON_B)
	_add_joy_button("dash", JOY_BUTTON_X)
	_add_joy_button("parry", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_axis("attack", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_joy_button("toggle_camera", JOY_BUTTON_BACK)
	_add_joy_button("restart", JOY_BUTTON_Y)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


static func _add_keys(action: String, keys: Array) -> void:
	_ensure(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


static func _add_mouse(action: String, button: MouseButton) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


static func _add_joy_button(action: String, button: JoyButton) -> void:
	_ensure(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


static func _add_joy_axis(action: String, axis: JoyAxis, value: float) -> void:
	_ensure(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)
