class_name CursorDraw
extends Control
## Прицел вместо системного курсора: показывает разброс и перезарядку.
## follow_aim (прицел HUD): на геймпаде и сенсоре рисуется в точке прицеливания, а не у мыши.
## Курсоры меню без follow_aim на геймпаде и сенсоре не рисуются — там работает фокус кнопок.

var follow_aim := false


func _draw() -> void:
	if not follow_aim and Controls.mode != "kbm":
		return
	var m := Controls.cursor_screen(self) if follow_aim else get_local_mouse_position()
	var main: Main = Game.main
	var gap := 6.0
	var reload := 0.0
	if main != null and main.player != null and not main.player.dead:
		var p := main.player
		var g := p.gun()
		if g != null and not get_tree().paused:
			gap = 6.0 + (g.spread + p.bloom) * 0.6
		reload = p.reload_progress()
	var col := Color(1, 1, 1, 0.95)
	var sh := Color(0, 0, 0, 0.7)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var dv: Vector2 = d
		draw_line(m + dv * gap, m + dv * (gap + 9.0), sh, 4.0)
		draw_line(m + dv * gap, m + dv * (gap + 9.0), col, 2.0)
	draw_circle(m, 2.0, col)
	if reload > 0.0:
		draw_arc(m, gap + 14.0, -PI * 0.5, -PI * 0.5 + TAU * reload, 24, Color(1.0, 0.85, 0.4), 3.0)
