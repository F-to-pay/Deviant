class_name FX
extends Node2D
## Частицы, вспышки, молнии, цифры урона и тряска камеры. Всё рисуется одним _draw.

const MAX_PARTS := 1800
const MAX_NUMS := 140

const P_DOT := 0
const P_RING := 1
const P_SPARK := 2
const P_FLASH := 3
const P_BOLT := 4


class Part:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.5
	var max_life := 0.5
	var size := 3.0
	var color := Color.WHITE
	var kind := 0
	var drag := 3.0


class Num:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var text := ""
	var color := Color.WHITE
	var life := 0.7
	var size := 14


var parts: Array[Part] = []
var nums: Array[Num] = []
var shake_amt := 0.0


func clear() -> void:
	parts.clear()
	nums.clear()
	shake_amt = 0.0


func _process(delta: float) -> void:
	var alive: Array[Part] = []
	for p in parts:
		p.life -= delta
		if p.life <= 0.0:
			continue
		if p.kind != P_BOLT:
			p.pos += p.vel * delta
			p.vel *= maxf(0.0, 1.0 - p.drag * delta)
		alive.append(p)
	parts = alive
	var alive_n: Array[Num] = []
	for n in nums:
		n.life -= delta
		if n.life <= 0.0:
			continue
		n.pos += n.vel * delta
		n.vel *= maxf(0.0, 1.0 - 3.0 * delta)
		alive_n.append(n)
	nums = alive_n
	shake_amt *= exp(-delta * 9.0)
	if shake_amt < 0.05:
		shake_amt = 0.0
	queue_redraw()


func shake(amount: float) -> void:
	var k := float(Game.setting("shake"))
	shake_amt = minf(maxf(shake_amt, amount * k), 18.0 * k)


func shake_offset() -> Vector2:
	if shake_amt <= 0.0:
		return Vector2.ZERO
	return Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_amt


func _part(pos: Vector2, vel: Vector2, life: float, size: float, color: Color, kind: int, drag: float = 3.0) -> void:
	if parts.size() >= MAX_PARTS:
		return
	var p := Part.new()
	p.pos = pos
	p.vel = vel
	p.life = life
	p.max_life = life
	p.size = size
	p.color = color
	p.kind = kind
	p.drag = drag
	parts.append(p)


# --- Публичные эффекты --------------------------------------------------------

func spark(pos: Vector2, dir: Vector2, color: Color, n: int, speed: float) -> void:
	for i in n:
		var v := dir.rotated(randf_range(-0.8, 0.8)) * speed * randf_range(0.5, 1.2)
		_part(pos, v, randf_range(0.12, 0.25), randf_range(1.5, 2.5), color, P_SPARK, 6.0)


func muzzle_flash(pos: Vector2, dir: Vector2, color: Color) -> void:
	_part(pos, Vector2.ZERO, 0.05, 9.0, color.lightened(0.5), P_FLASH)
	spark(pos, dir, color, 2, 260.0)


func explosion(pos: Vector2, r: float, color: Color, big: bool = false) -> void:
	_part(pos, Vector2.ZERO, 0.12 if not big else 0.3, r * 0.75, Color(1.0, 0.95, 0.8), P_FLASH)
	_part(pos, Vector2.ZERO, 0.3 if not big else 0.6, r, color, P_RING)
	var n := clampi(int(r / 7.0), 6, 40 if big else 18)
	for i in n:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(r * 1.5, r * 4.0)
		_part(pos, v, randf_range(0.2, 0.45), randf_range(2.0, 4.0), color, P_DOT, 5.0)
	for i in n / 2:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(20.0, 80.0)
		_part(pos + v * 0.3, v, randf_range(0.4, 0.8), randf_range(r * 0.15, r * 0.3), Color(0.15, 0.13, 0.12, 0.6), P_DOT, 2.0)


func death_burst(pos: Vector2, color: Color, r: float) -> void:
	_part(pos, Vector2.ZERO, 0.25, r * 2.2, color, P_RING)
	for i in 12:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(80.0, 260.0)
		_part(pos, v, randf_range(0.25, 0.5), randf_range(2.0, 4.5), color, P_DOT, 4.0)


func lightning(a: Vector2, b: Vector2, color: Color) -> void:
	# у молнии vel хранит конечную точку
	_part(a, b, 0.14, 2.0, color, P_BOLT)


func blink(a: Vector2, b: Vector2, color: Color) -> void:
	_part(a, Vector2.ZERO, 0.2, 14.0, color, P_RING)
	_part(b, Vector2.ZERO, 0.2, 14.0, color, P_RING)


func dust(pos: Vector2) -> void:
	for i in 6:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(30.0, 90.0)
		_part(pos, v, randf_range(0.25, 0.45), randf_range(3.0, 6.0), Color(0.8, 0.8, 0.8, 0.35), P_DOT, 3.0)


func ring(pos: Vector2, r: float, color: Color, life: float = 0.35) -> void:
	_part(pos, Vector2.ZERO, life, r, color, P_RING)


func heal_fx(pos: Vector2) -> void:
	for i in 8:
		var v := Vector2(randf_range(-30.0, 30.0), randf_range(-120.0, -60.0))
		_part(pos + Vector2(randf_range(-12.0, 12.0), 0.0), v, 0.5, 3.0, Color(0.4, 1.0, 0.5), P_DOT, 1.5)


func damage_number(pos: Vector2, amount: float, crit: bool, el: int, on_player: bool = false) -> void:
	if not on_player and not bool(Game.setting("damage_numbers")):
		return
	if nums.size() >= MAX_NUMS:
		nums.remove_at(0)
	var n := Num.new()
	n.pos = pos + Vector2(randf_range(-10.0, 10.0), randf_range(-6.0, 0.0))
	n.vel = Vector2(randf_range(-30.0, 30.0), randf_range(-110.0, -70.0))
	n.text = U.fmt(amount) + ("!" if crit else "")
	n.size = 22 if crit else 15
	n.life = 0.9 if crit else 0.65
	if on_player:
		n.color = Color(1.0, 0.25, 0.25)
		n.size = 18
	elif crit:
		n.color = Color(1.0, 0.88, 0.2)
	elif el >= 0:
		n.color = U.el_color(el)
	else:
		n.color = Color(1, 1, 1)
	nums.append(n)


func text(pos: Vector2, s: String, color: Color, fsize: int = 16, life: float = 1.0) -> void:
	if nums.size() >= MAX_NUMS:
		nums.remove_at(0)
	var n := Num.new()
	n.pos = pos
	n.vel = Vector2(0.0, -60.0)
	n.text = s
	n.size = fsize
	n.life = life
	n.color = color
	nums.append(n)


# --- Отрисовка ---------------------------------------------------------------------

func _draw() -> void:
	for p in parts:
		var k := p.life / p.max_life
		match p.kind:
			P_DOT:
				draw_circle(p.pos, maxf(0.5, p.size * k), Color(p.color, p.color.a * k))
			P_RING:
				draw_arc(p.pos, p.size * (1.0 - k) + 2.0, 0.0, TAU, 32, Color(p.color, k), 3.0)
			P_SPARK:
				draw_line(p.pos, p.pos - p.vel * 0.035, Color(p.color, k), p.size)
			P_FLASH:
				draw_circle(p.pos, p.size * (0.6 + 0.4 * k), Color(p.color, k * 0.75))
			P_BOLT:
				_draw_bolt(p.pos, p.vel, Color(p.color, k), p.size)
	var f := U.font_bold()
	for n in nums:
		var a := clampf(n.life / 0.25, 0.0, 1.0)
		U.draw_text_c(self, f, n.pos, n.text, n.size, Color(n.color, a), 4)


func _draw_bolt(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	var segs := 7
	var perp := (b - a).normalized().orthogonal()
	pts.append(a)
	for i in range(1, segs):
		var t := float(i) / float(segs)
		pts.append(a.lerp(b, t) + perp * randf_range(-12.0, 12.0))
	pts.append(b)
	draw_polyline(pts, Color(col, col.a * 0.4), w * 3.0)
	draw_polyline(pts, col.lightened(0.5), w)
