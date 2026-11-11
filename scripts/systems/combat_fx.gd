extends CanvasLayer
## 전투 연출: 히트스톱과 임팩트 프레임 (GDD 3.5, 9.1)
## - 히트스톱: 짧은 시간 Engine.time_scale을 0에 가깝게 둔다 (실제 시간 기준으로 복구)
## - 임팩트 프레임: 화면 전체를 밝기 임계값으로 흑/백 두 색 실루엣으로 바꾼다 (반전 가능)
## 같은 종류의 임팩트 프레임은 1초에 한 번만 (GDD 3.5 남발 방지)

const SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float threshold = 0.42;
uniform bool invert = false;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float v = step(threshold, l);
	if (invert) { v = 1.0 - v; }
	COLOR = vec4(vec3(v), 1.0);
}
"""

@export var enabled := true          # 접근성 설정에서 끌 수 있게 (GDD 8.2)
@export var same_kind_cooldown_ms := 1000

var impact_count := 0
var _rect: ColorRect
var _mat: ShaderMaterial
var _frames_left := 0
var _hitstop_until_ms := 0
var _last_kind_ms := {}


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("combat_fx")
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.visible = false
	add_child(_rect)


## kind: 같은 종류끼리 1초 쿨타임을 공유하는 이름 ("parry", "kill" 등)
func impact_frame(kind: String, frames: int, invert := false) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_kind_ms.get(kind, -100000)) < same_kind_cooldown_ms:
		return
	_last_kind_ms[kind] = now
	impact_count += 1
	_frames_left = maxi(_frames_left, frames)
	_mat.set_shader_parameter("invert", invert)
	_rect.visible = true


func hitstop(duration: float) -> void:
	_hitstop_until_ms = maxi(_hitstop_until_ms, Time.get_ticks_msec() + int(duration * 1000.0))
	Engine.time_scale = 0.02


func _process(_delta: float) -> void:
	# 렌더된 프레임 수로 센다: frames=2면 정확히 2프레임 보인다
	if _frames_left > 0:
		_frames_left -= 1
	elif _rect.visible:
		_rect.visible = false
	if _hitstop_until_ms > 0 and Time.get_ticks_msec() >= _hitstop_until_ms:
		_hitstop_until_ms = 0
		Engine.time_scale = 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0
