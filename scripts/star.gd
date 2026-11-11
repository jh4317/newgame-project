extends Area2D
## 공이 닿으면 사라지는 수집용 별.

signal collected

const RADIUS := 14.0

var _taken := false


func _ready() -> void:
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _taken or not body.is_in_group("ball"):
		return
	_taken = true
	collected.emit()
	queue_free()


func _process(delta: float) -> void:
	rotation += delta * 1.5


func _draw() -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var r := RADIUS if i % 2 == 0 else RADIUS * 0.45
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, Color(1.0, 0.85, 0.2))
