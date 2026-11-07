class_name GroundItem
extends Node2D
## Пушка на земле: луч цвета редкости, как положено в лутер-шутерах.

var gun: Gun
var vel := Vector2.ZERO
var t := 0.0
var highlight := false


func _ready() -> void:
	t = randf() * 3.0


func _physics_process(delta: float) -> void:
	t += delta
	if vel.length_squared() > 1.0:
		position = Game.main.zone.move_circle(position, vel * delta, 8.0)
		vel = vel.move_toward(Vector2.ZERO, 520.0 * delta)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if gun == null:
		return
	var col := gun.rarity_color()
	var bob := sin(t * 3.0) * 3.0
	if gun.rarity >= 1:
		var bh := 40.0 + float(gun.rarity) * 38.0
		var bw := 5.0 + float(gun.rarity) * 1.5
		var pts := PackedVector2Array([Vector2(-bw, 0), Vector2(bw, 0), Vector2(bw * 0.4, -bh), Vector2(-bw * 0.4, -bh)])
		var cols := PackedColorArray([Color(col, 0.55), Color(col, 0.55), Color(col, 0.0), Color(col, 0.0)])
		draw_polygon(pts, cols)
	draw_circle(Vector2.ZERO, 16.0, Color(col, 0.22 if not highlight else 0.45))
	GunIcon.draw_gun(self, gun, Vector2(0, -6 + bob), 0.45, -0.25, false, true)
	if highlight:
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 24, col, 2.0)
	if highlight or gun.rarity >= GunData.R_LEGENDARY:
		U.draw_text_c(self, U.font_bold(), Vector2(0, -34), gun.gun_name, 14, col)
