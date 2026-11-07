class_name GunIcon
extends RefCounted
## Процедурная отрисовка пушки из «деталей». Ствол смотрит вправо,
## начало координат — рукоять. Параметры формы лежат в gun.vis (см. GunGen).


static func draw_gun(ci: CanvasItem, g: Gun, at: Vector2, sc: float, rot: float = 0.0,
		flip: bool = false, centered: bool = false) -> void:
	if g == null or g.vis.is_empty():
		return
	var v: Dictionary = g.vis
	var pos := at
	if centered:
		pos -= Vector2(float(v["cx"]) * sc, 0.0).rotated(rot)
	ci.draw_set_transform(pos, rot, Vector2(sc, -sc if flip else sc))

	var body_c: Color = g.body_color
	var dark_c: Color = g.dark_color
	var acc: Color = g.rarity_color()
	var metal := dark_c.lightened(0.25)
	var blen: float = v["body"]
	var bh: float = v["bh"]
	var barrel: float = v["barrel"]
	var bt: float = v["bt"]
	var stock: float = v["stock"]
	var nb: int = v["nb"]
	var x_end := -10.0 + blen

	# Приклад
	if stock > 0.0:
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(-10.0, -bh), Vector2(-10.0 - stock, -bh * 0.7),
			Vector2(-10.0 - stock, 2.0), Vector2(-10.0, -1.0)]), dark_c)
	# Рукоять
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-4.0, -1.0), Vector2(4.0, -1.0), Vector2(1.0, 13.0), Vector2(-7.0, 13.0)]), dark_c)
	# Спусковая скоба
	ci.draw_arc(Vector2(6.0, 1.0), 4.0, 0.0, PI, 8, dark_c, 1.5)
	# Стволы (под корпусом, чтобы стык был аккуратный)
	var by := -bh * 0.82
	for i in nb:
		var yy := by + float(i) * (bt + 1.5)
		ci.draw_rect(Rect2(x_end - 2.0, yy, barrel + 2.0, bt), metal)
		ci.draw_rect(Rect2(x_end + barrel - 3.0, yy - 1.0, 3.0, bt + 2.0), dark_c)
	# Корпус
	ci.draw_rect(Rect2(-10.0, -bh, blen, bh), body_c)
	ci.draw_rect(Rect2(-10.0, -bh, blen, 2.0), body_c.lightened(0.25))
	# Полоса редкости
	ci.draw_rect(Rect2(-8.0, -bh * 0.5, blen - 4.0, 2.5), acc)
	# Рёбра охлаждения
	var fins: int = v["fins"]
	for i in fins + 1:
		ci.draw_rect(Rect2(-6.0 + float(i) * 5.0, -bh + 3.0, 2.0, bh * 0.3), dark_c)
	# Магазин
	var mx := -10.0 + blen * 0.45
	if bool(v["drum"]):
		ci.draw_circle(Vector2(mx + 4.0, 5.0), 7.0, dark_c)
		ci.draw_circle(Vector2(mx + 4.0, 5.0), 3.0, acc.darkened(0.3))
	elif g.mag_size > 1:
		var mh := clampf(4.0 + float(g.mag_size) * 0.25, 5.0, 14.0)
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(mx, -1.0), Vector2(mx + 7.0, -1.0), Vector2(mx + 9.0, mh), Vector2(mx + 2.0, mh)]), dark_c)
	# Прицел
	if bool(v["scope"]):
		ci.draw_rect(Rect2(-4.0, -bh - 6.0, 18.0, 5.0), dark_c)
		ci.draw_circle(Vector2(14.0, -bh - 3.5), 2.5, Color(0.5, 0.85, 1.0))
	# Ракетная труба
	if bool(v["tube"]):
		ci.draw_rect(Rect2(-6.0, -bh - 9.0, blen + barrel * 0.6, 8.0), body_c.darkened(0.2))
		ci.draw_circle(Vector2(-6.0 + blen + barrel * 0.6, -bh - 5.0), 4.0, Color(1.0, 0.3, 0.2))
	# Гранатный барабан
	if bool(v["gl"]):
		ci.draw_circle(Vector2(x_end - 4.0, -bh * 0.5), bh * 0.55, dark_c)
		ci.draw_arc(Vector2(x_end - 4.0, -bh * 0.5), bh * 0.55, 0.0, TAU, 12, acc, 1.5)
	# Шар-излучатель
	if bool(v["orb"]):
		ci.draw_circle(Vector2(x_end + barrel, -bh * 0.6), 6.0, g.proj_color)
		ci.draw_circle(Vector2(x_end + barrel, -bh * 0.6), 3.0, Color.WHITE)
	# Барабан револьвера
	if bool(v.get("cyl", false)):
		ci.draw_circle(Vector2(-10.0 + blen * 0.55, -bh * 0.5), bh * 0.6, dark_c)
		for i in 3:
			ci.draw_circle(Vector2(-10.0 + blen * 0.55 + (float(i) - 1.0) * bh * 0.32, -bh * 0.5), 1.6, metal)
	# Миномётная труба с опорной плитой
	if bool(v.get("mortar", false)):
		ci.draw_rect(Rect2(x_end - 4.0, -bh - 4.0, barrel + 6.0, bt + 4.0), body_c.darkened(0.15))
		ci.draw_rect(Rect2(x_end + barrel - 2.0, -bh - 6.0, 5.0, bt + 8.0), dark_c)
		ci.draw_rect(Rect2(-14.0, 10.0, 22.0, 4.0), dark_c)
	# Стихийные катушки
	if g.element >= 0:
		var ec := U.el_color(g.element)
		for i in 2:
			var cx := x_end + barrel * (0.3 + 0.35 * float(i))
			ci.draw_rect(Rect2(cx, by - 2.0, 3.0, bt + 4.0), ec)
	# Легендарка/абсурд — светящаяся точка
	if g.rarity >= GunData.R_LEGENDARY:
		ci.draw_circle(Vector2(-10.0 + blen * 0.75, -bh * 0.5), 2.5, Color(1, 1, 1, 0.9))

	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
