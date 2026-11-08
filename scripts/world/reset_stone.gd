class_name ResetStone
extends Node2D
## Камень перезапуска у входа в стартовый город: [interact] — новый забег с нуля, а значит и новый
## стартовый город (другой товар у торговцев, другие дары Мистика и контракты Гильдии).
## С заданным сидом город будет тем же — на то он и сид.

const TALK_DIST := 60.0

var t := 0.0
var highlight := false


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var col := Color(0.55, 0.9, 1.0)
	var stone := Color(0.32, 0.33, 0.38)
	draw_rect(Rect2(-16, 6, 32, 7), Color(0, 0, 0, 0.3))
	var pts := PackedVector2Array([Vector2(-14, 8), Vector2(14, 8), Vector2(10, -34), Vector2(0, -42), Vector2(-10, -34)])
	draw_colored_polygon(pts, stone)
	pts.append(pts[0])
	draw_polyline(pts, stone.lightened(0.3), 2.0)
	# руна: круговая стрелка — «заново»
	var glow := 0.6 + sin(t * 3.0) * 0.25
	var c := Vector2(0, -16)
	draw_arc(c, 8.0, -PI * 0.2, PI * 1.5, 18, Color(col, glow), 3.0)
	var tip := c + Vector2.from_angle(-PI * 0.2) * 8.0
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-5, -3), tip + Vector2(4, -4), tip + Vector2(1, 5)]), Color(col, glow))
	if highlight:
		draw_arc(Vector2(0, -2), 26.0 + sin(t * 5.0) * 2.0, 0.0, TAU, 24, Color(col, 0.7), 2.0)
	U.draw_text_c(self, U.font_bold(), Vector2(0, -52), U.t("Restart"), 16, col)
