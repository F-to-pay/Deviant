class_name Portal
extends Node2D
## Разлом в следующую зону. Наступил — провалился глубже.
## to_town — ведёт сначала в город (конец этапа), из города — уже в зону target_level.

var t := 0.0
var target_level := 2
var to_town := false


func _physics_process(delta: float) -> void:
	t += delta
	var main: Main = Game.main
	if main == null or main.player == null or main.player.dead or main.transitioning:
		return
	if position.distance_to(main.player.position) < 42.0:
		main.next_zone(target_level, to_town)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var base := Color(1.0, 0.75, 0.3) if to_town else Color(0.7, 0.35, 1.0)
	draw_circle(Vector2.ZERO, 46.0, Color(0.05, 0.0, 0.1, 0.85))
	for i in 5:
		var r := 14.0 + float(i) * 8.0
		var a := t * (2.5 - float(i) * 0.35) * (1.0 if i % 2 == 0 else -1.0)
		draw_arc(Vector2.ZERO, r, a, a + PI * 1.3, 24, Color(base.lightened(float(i) * 0.08), 0.85 - float(i) * 0.12), 3.0)
	draw_circle(Vector2.ZERO, 8.0 + sin(t * 4.0) * 2.0, Color(1, 0.9, 1, 0.9))
	var label := U.t("Town") if to_town else U.t("Zone %d") % target_level
	U.draw_text_c(self, U.font_bold(), Vector2(0, -60), label, 16, base.lightened(0.45))
