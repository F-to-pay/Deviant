class_name FlaskDrop
extends Node2D
## Фляга лечения на земле. Притягивается и подбирается всегда; лишние сверх Player.FLASK_MAX
## сгорают при переходе в следующую зону (Player.trim_flasks).

var t := 0.0
var vel := Vector2.ZERO


func _physics_process(delta: float) -> void:
	t += delta
	var main: Main = Game.main
	var p: Player = main.player
	if vel.length_squared() > 1.0:
		position = main.zone.move_circle(position, vel * delta, 6.0)
		vel = vel.move_toward(Vector2.ZERO, 500.0 * delta)
	if p == null or p.dead:
		return
	var d := p.position - position
	var l := d.length()
	if l < 150.0 and t > 0.35:
		position += d.normalized() * minf(l, (220.0 + (150.0 - l) * 6.0) * delta)
	if l < p.radius + 10.0:
		p.add_flask()
		Sfx.ui("pickup/heal", -7.0, 1.2)
		main.fx.text(position + Vector2(0, -22), U.t("+1 flask"), Color(1.0, 0.45, 0.5), 14, 0.8)
		main.remove_flask(self)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var bob := sin(t * 4.0) * 2.0
	draw_rect(Rect2(-7, 7, 14, 3), Color(0, 0, 0, 0.3))
	var pulse := 1.0 + sin(t * 5.0) * 0.12
	draw_circle(Vector2(0, bob), 15.0 * pulse, Color(1.0, 0.2, 0.3, 0.16))
	draw_icon(self, Vector2(0, bob), 1.0, 1.0)


## Фляга для интерфейса и земли: fill — насколько полна (0..1), s — масштаб.
static func draw_icon(ci: CanvasItem, at: Vector2, s: float, fill: float) -> void:
	var glass := Color(0.85, 0.9, 1.0, 0.9)
	var red := Color(0.95, 0.15, 0.25)
	var body := Rect2(at + Vector2(-6, -4) * s, Vector2(12, 12) * s)
	ci.draw_rect(body, Color(0.1, 0.05, 0.07, 0.8))
	if fill > 0.0:
		var h := 12.0 * s * clampf(fill, 0.0, 1.0)
		ci.draw_rect(Rect2(body.position.x, body.end.y - h, body.size.x, h), red)
	ci.draw_rect(body, glass, false, 1.5)
	ci.draw_rect(Rect2(at + Vector2(-3, -10) * s, Vector2(6, 6) * s), glass, false, 1.5)
	ci.draw_rect(Rect2(at + Vector2(-4, -12) * s, Vector2(8, 3) * s), Color(0.55, 0.38, 0.22))
