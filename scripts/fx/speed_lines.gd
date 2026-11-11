extends CanvasLayer
## 속도선 (GDD 4.1 속도감 연출).
## 화면 가장자리에 방사형 흰 줄이 깜빡이며 흐른다. 빠를수록 진하고 안쪽까지 들어온다.
## 탑뷰에서는 플레이어의 화면 위치를 중심으로, 숄더뷰에서는 화면 중앙을 중심으로 퍼진다.

const SHADER_CODE := """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform float aspect = 1.7778;
uniform float line_count = 110.0;

float hash(float n) { return fract(sin(n) * 43758.5453123); }

void fragment() {
	vec2 uv = SCREEN_UV - center;
	uv.x *= aspect;
	float r = length(uv);
	float a = atan(uv.y, uv.x) / 6.2831853 + 0.5;
	float cell = floor(a * line_count);
	float t = floor(TIME * 20.0);
	float on = step(0.70, hash(cell * 13.17 + t * 7.31));
	float d = abs(fract(a * line_count) - 0.5);
	float line = on * smoothstep(0.22, 0.02, d);
	float inner = mix(0.62, 0.32, intensity) + hash(cell + t * 3.1) * 0.12;
	float mask = smoothstep(inner, inner + 0.3, r);
	COLOR = vec4(1.0, 1.0, 1.0, line * mask * intensity * 0.5);
}
"""

@export var start_speed := 14.0   # 이 속도부터 보이기 시작
@export var full_speed := 26.0    # 이 속도에서 최대

var player: CharacterBody3D
var camera_rig: Node3D
var _rect: ColorRect
var _mat: ShaderMaterial
var _intensity := 0.0
var _center := Vector2(0.5, 0.5)


func _ready() -> void:
	layer = 50
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func _process(delta: float) -> void:
	if player == null:
		return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var target := clampf((speed - start_speed) / (full_speed - start_speed), 0.0, 1.0)
	if player.call("state_name") == "대시":
		target = 1.0
	# 올라갈 땐 빠르게, 내려갈 땐 천천히
	var rate := 12.0 if target > _intensity else 3.0
	_intensity = lerpf(_intensity, target, 1.0 - exp(-rate * delta))

	var view_size := _rect.get_viewport_rect().size
	var desired := Vector2(0.5, 0.5)
	if camera_rig and camera_rig.call("mode_name") == "탑뷰":
		var cam: Camera3D = camera_rig.get("camera")
		var screen := cam.unproject_position(player.global_position + Vector3.UP)
		desired = screen / view_size
	_center = _center.lerp(desired, 1.0 - exp(-10.0 * delta))

	_rect.visible = _intensity > 0.01
	_mat.set_shader_parameter("intensity", _intensity)
	_mat.set_shader_parameter("center", _center)
	_mat.set_shader_parameter("aspect", view_size.x / maxf(view_size.y, 1.0))
