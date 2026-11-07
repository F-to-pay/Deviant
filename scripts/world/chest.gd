class_name Chest
extends Node2D
## Сундук с лутом. Золотой — щедрее.

var golden := false
var opened := false
var t := 0.0


func _process(delta: float) -> void:
	t += delta
	if not opened:
		queue_redraw()


func _draw() -> void:
	var body := Color(0.45, 0.28, 0.14) if not golden else Color(0.85, 0.65, 0.15)
	var trim := Color(0.75, 0.7, 0.6) if not golden else Color(1.0, 0.95, 0.6)
	draw_rect(Rect2(-18, 4, 36, 8), Color(0, 0, 0, 0.3))
	if golden and not opened:
		draw_circle(Vector2.ZERO, 30.0 + sin(t * 3.0) * 3.0, Color(1.0, 0.85, 0.3, 0.15))
	draw_rect(Rect2(-16, -10, 32, 18), body)
	draw_rect(Rect2(-16, -10, 32, 18), trim, false, 2.0)
	if opened:
		draw_colored_polygon(PackedVector2Array([Vector2(-16, -10), Vector2(16, -10), Vector2(12, -22), Vector2(-12, -22)]), body.darkened(0.3))
		draw_rect(Rect2(-13, -9, 26, 5), Color(0.05, 0.03, 0.02))
	else:
		draw_rect(Rect2(-17, -16, 34, 8), body.lightened(0.1))
		draw_rect(Rect2(-17, -16, 34, 8), trim, false, 2.0)
		draw_rect(Rect2(-3, -11, 6, 7), trim)
