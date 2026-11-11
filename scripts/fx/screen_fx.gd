extends CanvasLayer
## 화면 연출: 큰 순간(3타 마무리·처치·패링)을 만화풍으로 과장한다.
## - 화면 베기: 화면을 가로지르는 거대한 붓터치(흰 심 + 검은 외곽선)가 순식간에 그어졌다 사라진다
## - 줌 블러: 타격 지점을 중심으로 화면이 순간 빨려 들어가듯 번진다
## 둘 다 실제 시간 기준으로 움직여 히트스톱 중에도 재생된다.

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
void fragment() {
	vec2 dir = SCREEN_UV - center;
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		float t = float(i) / 11.0;
		acc += texture(screen_tex, SCREEN_UV - dir * strength * t).rgb;
	}
	COLOR = vec4(acc / 12.0, 1.0);
}
"""

@export var enabled := true  # 접근성: 화면 섬광 줄이기와 함께 끌 수 있게 (GDD 8.2)

var _blur_rect: ColorRect
var _blur_mat: ShaderMaterial
var _blur := 0.0
var _last_us := 0


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = sh
	_blur_rect = ColorRect.new()
	_blur_rect.material = _blur_mat
	_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur_rect.visible = false
	add_child(_blur_rect)
	_last_us = Time.get_ticks_usec()


## center_uv: 0~1 화면 좌표. strength 0.05~0.15 정도
func zoom_blur(strength: float, center_uv: Vector2) -> void:
	if not enabled:
		return
	_blur = maxf(_blur, strength)
	_blur_mat.set_shader_parameter("center", center_uv)


## 화면을 가로지르는 붓터치. center_px: 지나갈 화면 위치(픽셀), angle_deg: 기울기
func slash(center_px: Vector2, angle_deg: float, width: float, life := 0.22) -> void:
	if not enabled:
		return
	var size := _blur_rect.get_viewport_rect().size
	var half := size.length() * 0.65
	var dir := Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
	var a := center_px - dir * half
	var b := center_px + dir * half

	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.0))
	taper.add_point(Vector2(0.45, 1.0))
	taper.add_point(Vector2(1.0, 0.0))

	var outline := Line2D.new()
	outline.width = width * 1.6
	outline.width_curve = taper
	outline.default_color = Color(0.02, 0.02, 0.02, 0.95)
	outline.antialiased = true
	var core := Line2D.new()
	core.width = width
	core.width_curve = taper
	core.default_color = Color(1, 1, 1, 1)
	core.antialiased = true
	for l in [outline, core]:
		var line := l as Line2D
		line.points = PackedVector2Array([a, a])
		add_child(line)

	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_method(_set_slash_progress.bind(outline, core, a, b), 0.0, 1.0, life * 0.3) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(core, "width", 0.0, life * 0.7)
	tw.parallel().tween_property(outline, "width", 0.0, life * 0.7)
	tw.parallel().tween_property(outline, "modulate:a", 0.0, life * 0.7)
	tw.tween_callback(outline.queue_free)
	tw.tween_callback(core.queue_free)


func _set_slash_progress(p: float, outline: Line2D, core: Line2D, a: Vector2, b: Vector2) -> void:
	if is_instance_valid(outline):
		outline.set_point_position(1, a.lerp(b, p))
	if is_instance_valid(core):
		core.set_point_position(1, a.lerp(b, p))


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_dt := float(now - _last_us) / 1000000.0
	_last_us = now
	_blur = move_toward(_blur, 0.0, real_dt * 0.6)
	_blur_rect.visible = _blur > 0.002
	_blur_mat.set_shader_parameter("strength", _blur)
