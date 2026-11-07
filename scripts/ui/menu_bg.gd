class_name MenuBg
extends Control
## Фон главного меню: парад случайных пушек из настоящего генератора — дрейфуют,
## крутятся и иногда постреливают.
## ЗАГЛУШКА: потом сюда встанет демо-режим — ИИ-игрок рубится с мобами, вид
## переключается каждые ~10 с. Меню знает только, что это Control на весь экран
## с visible, так что замена — новый класс с тем же интерфейсом.

const COUNT := 11
const MARGIN := 220.0

class Fly:
	var g: Gun
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var rot := 0.0
	var spin := 0.0
	var sc := 1.0
	var shot_t := 1.0

class Streak:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var col := Color.WHITE
	var life := 0.5

var rng := RandomNumberGenerator.new()
var flies: Array[Fly] = []
var streaks: Array[Streak] = []
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rng.randomize()
	for i in COUNT:
		var f := Fly.new()
		_respawn(f, true)
		flies.append(f)


func _respawn(f: Fly, anywhere: bool) -> void:
	var vp := get_viewport_rect().size
	# уровень и бонус пошире — чтобы мелькали и серые, и абсурдные
	f.g = GunGen.generate(rng.randi_range(1, 40), rng, rng.randf_range(0.0, 3.5))
	f.sc = rng.randf_range(1.3, 2.6)
	f.rot = rng.randf_range(-0.6, 0.6) + (PI if rng.randf() < 0.5 else 0.0)
	f.spin = rng.randf_range(-0.15, 0.15)
	var dir := Vector2.from_angle(rng.randf() * TAU)
	f.vel = dir * rng.randf_range(18.0, 55.0)
	f.shot_t = rng.randf_range(0.5, 3.0)
	if anywhere:
		f.pos = Vector2(rng.randf() * vp.x, rng.randf() * vp.y)
	else:
		# заходим с края, противоположного направлению полёта
		f.pos = vp * 0.5 - dir * (vp.length() * 0.5 + MARGIN * 0.5) \
			+ dir.orthogonal() * rng.randf_range(-vp.y * 0.5, vp.y * 0.5)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var vp := get_viewport_rect().size
	var area := Rect2(Vector2.ZERO, vp).grow(MARGIN)
	for f in flies:
		f.pos += f.vel * delta
		f.rot += f.spin * delta
		if not area.has_point(f.pos):
			_respawn(f, false)
			continue
		f.shot_t -= delta
		if f.shot_t <= 0.0:
			f.shot_t = rng.randf_range(0.8, 3.5) / clampf(f.g.fire_rate / 3.0, 0.5, 3.0)
			_shoot(f)
	var alive: Array[Streak] = []
	for s in streaks:
		s.life -= delta
		s.pos += s.vel * delta
		if s.life > 0.0:
			alive.append(s)
	streaks = alive
	queue_redraw()


func _shoot(f: Fly) -> void:
	var dir := Vector2.from_angle(f.rot)
	var muzzle := f.pos + dir * float(f.g.vis.get("len", 40.0)) * 0.5 * f.sc
	var n := clampi(f.g.pellets, 1, 7)
	for i in n:
		var s := Streak.new()
		var a := f.rot + (rng.randf_range(-0.25, 0.25) if n > 1 else rng.randf_range(-0.03, 0.03))
		s.pos = muzzle
		s.vel = Vector2.from_angle(a) * rng.randf_range(700.0, 1000.0)
		s.col = f.g.proj_color
		s.life = rng.randf_range(0.4, 0.8)
		streaks.append(s)


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.025, 0.022, 0.04))
	# медленная диагональная сетка
	var step := 80.0
	var off := fmod(_t * 12.0, step)
	var gc := Color(1, 1, 1, 0.035)
	var x := -vp.y + off
	while x < vp.x:
		draw_line(Vector2(x, 0), Vector2(x + vp.y, vp.y), gc, 1.0)
		x += step
	for s in streaks:
		var a := clampf(s.life / 0.3, 0.0, 1.0)
		draw_line(s.pos, s.pos - s.vel.normalized() * 22.0, Color(s.col, 0.7 * a), 3.0)
	var f0 := U.font()
	for f in flies:
		GunIcon.draw_gun(self, f.g, f.pos, f.sc, f.rot, absf(wrapf(f.rot, -PI, PI)) > PI * 0.5, true)
		U.draw_text_c(self, f0, f.pos + Vector2(0, 30.0 * f.sc), f.g.gun_name, 14, Color(f.g.rarity_color(), 0.45), 3)
	# затемнение к центру, чтобы кнопки читались
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.35))
