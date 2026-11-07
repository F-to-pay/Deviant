class_name Portal
extends Node2D
## Разлом в следующую зону. Наступил — провалился глубже.

var t := 0.0
var target_level := 2


func _physics_process(delta: float) -> void:
	t += delta
	var main: Main = Game.main
	if main == null or main.player == null or main.player.dead or main.transitioning:
		return
	if position.distance_to(main.player.position) < 42.0:
		main.next_zone()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var base := Color(0.7, 0.35, 1.0)
	draw_circle(Vector2.ZERO, 46.0, Color(0.05, 0.0, 0.1, 0.85))
	for i in 5:
		var r := 14.0 + float(i) * 8.0
		var a := t * (2.5 - float(i) * 0.35) * (1.0 if i % 2 == 0 else -1.0)
		draw_arc(Vector2.ZERO, r, a, a + PI * 1.3, 24, Color(base.lightened(float(i) * 0.08), 0.85 - float(i) * 0.12), 3.0)
	draw_circle(Vector2.ZERO, 8.0 + sin(t * 4.0) * 2.0, Color(1, 0.9, 1, 0.9))
	U.draw_text_c(self, U.font_bold(), Vector2(0, -60), U.t("Зона %d") % target_level, 16, Color(0.9, 0.75, 1.0))
