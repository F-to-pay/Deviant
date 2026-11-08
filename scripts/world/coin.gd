class_name Coin
extends Node2D
## Монетка на земле. Обычная — деньги забега (Game.coins), древняя (meta) — мета-прогрессия
## (Game.meta_coins, сохраняется сразу). Подлетает к игроку, как сферы здоровья.

var value := 1
var meta := false
var vel := Vector2.ZERO
var t := 0.0


func _ready() -> void:
	t = randf() * 0.2


func _physics_process(delta: float) -> void:
	t += delta
	var main: Main = Game.main
	var p: Player = main.player
	if vel.length_squared() > 1.0:
		position = main.zone.move_circle(position, vel * delta, 5.0)
		vel = vel.move_toward(Vector2.ZERO, 520.0 * delta)
	if p == null or p.dead:
		return
	var d := p.position - position
	var l := d.length()
	var reach := 200.0 if meta else 150.0
	if l < reach and t > 0.4:
		position += d.normalized() * minf(l, (260.0 + (reach - l) * 6.0) * delta)
	if l < p.radius + 8.0:
		main.pick_coin(self)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var bob := sin(t * 5.0) * 1.5
	draw_rect(Rect2(-6, 5, 12, 3), Color(0, 0, 0, 0.3))
	# «вращение» — монетка сплющивается по ширине
	var sx := maxf(0.25, absf(cos(t * 4.0)))
	draw_set_transform(Vector2(0, bob - 2.0), 0.0, Vector2(sx, 1.0))
	if meta:
		var pulse := 1.0 + sin(t * 4.0) * 0.12
		draw_circle(Vector2.ZERO, 14.0 * pulse, Color(0.45, 0.95, 1.0, 0.18))
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(Vector2.from_angle(TAU * float(i) / 6.0 + PI / 6.0) * 8.0)
		draw_colored_polygon(pts, Color(0.2, 0.6, 0.75))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.7, 1.0, 1.0), 2.0)
		draw_circle(Vector2.ZERO, 2.5, Color(0.9, 1.0, 1.0))
	else:
		draw_circle(Vector2.ZERO, 6.5, Color(0.62, 0.42, 0.08))
		draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.8, 0.25))
		draw_rect(Rect2(-1.0, -3.0, 2.0, 6.0), Color(0.8, 0.55, 0.1))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Иконка монеты для интерфейса (HUD, окно лавки).
static func draw_icon(ci: CanvasItem, at: Vector2, r: float, is_meta: bool) -> void:
	if is_meta:
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(at + Vector2.from_angle(TAU * float(i) / 6.0 + PI / 6.0) * r * 1.15)
		ci.draw_colored_polygon(pts, Color(0.2, 0.6, 0.75))
		pts.append(pts[0])
		ci.draw_polyline(pts, Color(0.7, 1.0, 1.0), 2.0)
	else:
		ci.draw_circle(at, r, Color(0.62, 0.42, 0.08))
		ci.draw_circle(at, r * 0.77, Color(1.0, 0.8, 0.25))
		ci.draw_rect(Rect2(at.x - 1.0, at.y - r * 0.45, 2.0, r * 0.9), Color(0.8, 0.55, 0.1))
