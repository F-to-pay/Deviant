class_name HealthOrb
extends Node2D
## Сфера здоровья (привет, Диабло). Притягивается к игроку.

const HEAL := 10.0

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
		p.heal(HEAL, true)
		main.remove_orb(self)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var pulse := 1.0 + sin(t * 6.0) * 0.12
	draw_circle(Vector2.ZERO, 14.0 * pulse, Color(1.0, 0.2, 0.25, 0.25))
	draw_circle(Vector2.ZERO, 8.0 * pulse, Color(1.0, 0.25, 0.3))
	draw_rect(Rect2(-1.5, -5, 3, 10), Color.WHITE)
	draw_rect(Rect2(-5, -1.5, 10, 3), Color.WHITE)
