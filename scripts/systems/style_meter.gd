extends CanvasLayer
## 먹 스타일 게이지 (GDD 5.2): 화려하게 싸울수록 플레이어의 먹 게이지가 차고 등급이 오른다.
## - 행동마다 점수. 같은 행동을 연달아 반복하면 점수가 줄어든다 (다양한 기술을 섞도록)
## - 시간이 지나면 서서히 줄고(높은 등급일수록 빨리), 피격당하면 한 등급만큼 크게 깎인다
## - 등급 6단계 (먹·붓 테마의 오리지널 이름): 점 → 획 → 필 → 묵 → 농묵 → 일필휘지
## - 화면 오른쪽 위: 큰 등급 글자 + 게이지 + 최근 행동 목록(+점수)
## 다른 스크립트는 그룹 "style_meter"를 통해 add()를 부른다.

signal rank_changed(rank: int)

const RANKS := ["점", "획", "필", "묵", "농묵", "일필휘지"]
const RANK_SIZE := 300.0       # 등급 하나를 채우는 점수
const REPEAT_WINDOW := 4       # 최근 몇 개의 행동으로 반복을 판단할지
const FEED_LIFE := 2.5

@export var decay_base := 20.0     # 초당 감소 (가장 낮은 등급)
@export var decay_per_rank := 14.0 # 등급마다 추가 감소
@export var damage_penalty := 300.0

var points := 0.0
var best_rank := -1
var _recent: Array[String] = []
var _rank := -1

var _root: Control
var _rank_label: Label
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _feed: VBoxContainer


func _ready() -> void:
	layer = 20
	add_to_group("style_meter")
	_build_ui()
	_update_ui()


## 현재 등급 (-1 = 아직 없음)
func rank() -> int:
	if points <= 0.0:
		return -1
	return mini(RANKS.size() - 1, int(points / RANK_SIZE))


func rank_name() -> String:
	var r := rank()
	return "-" if r < 0 else RANKS[r]


## 행동 점수 추가. id: 반복 판단용, label: 화면 표시
func add(id: String, label: String, base_points: float) -> float:
	var repeats := _recent.count(id)
	var mul := 1.0 / (1.0 + repeats)  # 1, 1/2, 1/3 ...
	var gained := base_points * mul
	points = minf(points + gained, RANK_SIZE * RANKS.size() - 0.01)
	_recent.append(id)
	if _recent.size() > REPEAT_WINDOW:
		_recent.pop_front()
	_push_feed("+%d %s" % [int(round(gained)), label] + ("" if repeats == 0 else "  (반복 ×%.1f)" % mul))
	_update_ui()
	return gained


func on_damaged() -> void:
	points = maxf(0.0, points - damage_penalty)
	_push_feed("피격  -%d" % int(damage_penalty))
	_update_ui()


func _process(delta: float) -> void:
	if points > 0.0:
		var r := maxi(rank(), 0)
		points = maxf(0.0, points - (decay_base + decay_per_rank * r) * delta)
		_update_ui()


func _update_ui() -> void:
	var r := rank()
	if r != _rank:
		var up := r > _rank
		_rank = r
		best_rank = maxi(best_rank, r)
		rank_changed.emit(r)
		if up and r >= 0:
			# 등급이 오르면 글자가 크게 튀어나온다
			_rank_label.pivot_offset = _rank_label.size * 0.5
			_rank_label.scale = Vector2.ONE * 1.6
			var tw := _rank_label.create_tween()
			tw.set_ignore_time_scale(true)
			tw.tween_property(_rank_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_root.visible = points > 0.0
	_rank_label.text = rank_name()
	var frac := 1.0 if r >= RANKS.size() - 1 else fmod(points, RANK_SIZE) / RANK_SIZE
	_bar_fill.size.x = (_bar_bg.size.x - 4.0) * clampf(frac, 0.0, 1.0)  # 테두리 2px 안쪽


func _push_feed(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	_feed.add_child(l)
	_feed.move_child(l, 0)
	while _feed.get_child_count() > 6:
		var old := _feed.get_child(_feed.get_child_count() - 1)
		_feed.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_interval(FEED_LIFE)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_root.offset_left = -320
	_root.offset_right = -20
	_root.offset_top = 16
	_root.offset_bottom = 360
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var caption := Label.new()
	caption.text = "먹 스타일"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.size = Vector2(300, 24)
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	caption.add_theme_constant_override("outline_size", 5)
	_root.add_child(caption)

	_rank_label = Label.new()
	_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rank_label.position = Vector2(0, 20)
	_rank_label.size = Vector2(300, 80)
	_rank_label.add_theme_font_size_override("font_size", 64)
	_rank_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_rank_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_rank_label.add_theme_constant_override("outline_size", 14)
	_root.add_child(_rank_label)

	# 게이지: 검은 테두리 + 흰 채움
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0, 0, 0, 0.85)
	_bar_bg.position = Vector2(60, 108)
	_bar_bg.size = Vector2(240, 12)
	_root.add_child(_bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(1, 1, 1)
	_bar_fill.position = Vector2(62, 110)
	_bar_fill.size = Vector2(0, 8)
	_root.add_child(_bar_fill)

	_feed = VBoxContainer.new()
	_feed.position = Vector2(0, 130)
	_feed.size = Vector2(300, 200)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.add_theme_constant_override("separation", 2)
	_root.add_child(_feed)
