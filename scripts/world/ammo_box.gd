class_name AmmoBox
extends Node2D
## Коробка патронов одного типа. Подбирается касанием, если в запасе есть место;
## что не влезло — остаётся лежать.

var ammo_type: String = "pistol"
var amount: int = 10
var vel := Vector2.ZERO
var t := 0.0


func _physics_process(delta: float) -> void:
	t += delta
	var main: Main = Game.main
	var p: Player = main.player
	if vel.length_squared() > 1.0:
		position = main.zone.move_circle(position, vel * delta, 6.0)
		vel = vel.move_toward(Vector2.ZERO, 500.0 * delta)
	if p == null or p.dead or p.reserve_full(ammo_type):
		return
	var d := p.position - position
	var l := d.length()
	if l < 110.0 and t > 0.35:
		position += d.normalized() * minf(l, (200.0 + (110.0 - l) * 5.0) * delta)
	if l < p.radius + 10.0:
		var got := p.add_ammo(ammo_type, amount)
		if got > 0:
			Sfx.at("pickup/ammo", position, -8.0, 1.0, 0.06, 2, 0.08)
			main.fx.text(position + Vector2(0, -20), "+%d %s" % [got, GunData.ammo_label(ammo_type)],
				GunData.ammo_color(ammo_type), 14, 0.8)
		amount -= got
		if amount <= 0:
			main.remove_ammo(self)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var col: Color = GunData.ammo_color(ammo_type)
	var bob := sin(t * 4.0) * 2.0
	draw_rect(Rect2(-9, 4, 18, 4), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(-8, -8 + bob, 16, 12), col.darkened(0.45))
	draw_rect(Rect2(-8, -8 + bob, 16, 12), col, false, 2.0)
	for i in 3:
		draw_rect(Rect2(-5.0 + float(i) * 4.0, -12 + bob, 2.0, 5.0), col.lightened(0.3))
