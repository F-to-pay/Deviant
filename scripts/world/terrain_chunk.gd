class_name TerrainChunk
extends Node2D
## Кусок карты 16x16 клеток. Рисуется один раз, дальше Godot кэширует
## и сам отсекает чанки за экраном.

var zone: Zone
var x0 := 0
var y0 := 0
var x1 := 0
var y1 := 0


func _hash(cx: int, cy: int) -> int:
	var hh := (cx * 73856093) ^ (cy * 19349663) ^ (zone.level * 83492791)
	return absi(hh)


func _draw() -> void:
	var ts := Zone.T
	var b: Dictionary = zone.biome
	var floor2: Color = b["floor2"]
	var rock: Color = b["rock"]
	var rock_top: Color = b["rock_top"]
	var liq: Color = b["liq"]
	var liq2: Color = b["liq2"]
	var deco: Color = b["deco"]
	var shadow := Color(0, 0, 0, 0.28)

	# Пятна на полу; в городе на улицах — мостовая
	var pave: Color = Color(b["floor"]).lightened(0.07)
	var seam: Color = Color(b["floor"]).darkened(0.18)
	for cy in range(y0, y1):
		for cx in range(x0, x1):
			if zone.get_cell(cx, cy) != Zone.FLOOR:
				continue
			var hh := _hash(cx, cy)
			if zone.is_paved(cx, cy):
				# «булыжники»: два ряда в клетке, швы через ряд со сдвигом на четверть клетки
				draw_rect(Rect2(cx * ts, cy * ts, ts, ts), seam)
				for row in 2:
					var cuts: Array = [0.0, 0.5, 1.0] if (cy * 2 + row) % 2 == 0 else [0.0, 0.25, 0.75, 1.0]
					for k in cuts.size() - 1:
						var xa := cx * ts + float(cuts[k]) * ts
						var xb := cx * ts + float(cuts[k + 1]) * ts
						var shade := float((hh >> (k + row * 3)) % 3) * 0.025
						draw_rect(Rect2(xa + 1.5, cy * ts + float(row) * ts * 0.5 + 1.5, xb - xa - 3.0, ts * 0.5 - 3.0),
							pave.lightened(shade))
				continue
			if hh % 5 == 0:
				var ox := float(hh % 23)
				var oy := float((hh / 23) % 23)
				draw_rect(Rect2(cx * ts + ox * 0.6, cy * ts + oy * 0.6, 14.0 + float(hh % 9), 10.0 + float(hh % 7)), floor2)

	# Декор
	for d in zone.decor:
		var p: Vector2 = d[0]
		var c := zone.cell_at(p)
		if c.x < x0 or c.x >= x1 or c.y < y0 or c.y >= y1:
			continue
		_draw_decor(p, int(d[1]), float(d[2]), deco)

	# Жидкости/пропасти
	for cy in range(y0, y1):
		for cx in range(x0, x1):
			var v := zone.get_cell(cx, cy)
			if v != Zone.PIT and v != Zone.HAZARD:
				continue
			var r := Rect2(cx * ts, cy * ts, ts, ts)
			draw_rect(r.grow(0.5), liq)
			var up := zone.get_cell(cx, cy - 1)
			if up != v:
				# «берег» сверху даёт ощущение глубины
				draw_rect(Rect2(cx * ts, cy * ts, ts, 7.0), liq2 if v == Zone.HAZARD else Color(0, 0, 0, 0.45))
			if v == Zone.HAZARD:
				var hh := _hash(cx, cy)
				if hh % 3 == 0:
					draw_circle(Vector2(cx * ts + float(hh % 31) + 4.0, cy * ts + float((hh / 31) % 31) + 4.0), 3.0 + float(hh % 4), liq2)

	# Скалы: тень, тело, светлая кромка, бугры по краям
	for cy in range(y0, y1):
		for cx in range(x0, x1):
			if zone.get_cell(cx, cy) != Zone.ROCK:
				continue
			if zone.get_cell(cx, cy + 1) != Zone.ROCK:
				draw_rect(Rect2(cx * ts, (cy + 1) * ts, ts, 12.0), shadow)
	for cy in range(y0, y1):
		for cx in range(x0, x1):
			if zone.get_cell(cx, cy) != Zone.ROCK:
				continue
			var r := Rect2(cx * ts, cy * ts, ts, ts)
			draw_rect(r.grow(0.5), rock)
			var hh := _hash(cx, cy)
			if zone.get_cell(cx, cy - 1) != Zone.ROCK:
				draw_rect(Rect2(cx * ts, cy * ts - 4.0, ts, 9.0), rock_top)
				if hh % 2 == 0:
					draw_circle(Vector2(cx * ts + 10.0 + float(hh % 20), cy * ts - 2.0), 6.0, rock_top)
			if zone.get_cell(cx - 1, cy) != Zone.ROCK and hh % 3 == 0:
				draw_circle(Vector2(cx * ts + 2.0, cy * ts + 14.0 + float(hh % 12)), 6.0, rock)
			if zone.get_cell(cx + 1, cy) != Zone.ROCK and hh % 3 == 1:
				draw_circle(Vector2(cx * ts + ts - 2.0, cy * ts + 14.0 + float(hh % 12)), 6.0, rock)
			if hh % 7 == 0:
				draw_rect(Rect2(cx * ts + 8.0, cy * ts + 14.0, 10.0, 3.0), rock.darkened(0.2))


func _draw_decor(p: Vector2, kind: int, s: float, col: Color) -> void:
	match kind:
		0:  # камешки
			draw_circle(p, 3.0 * s, col.darkened(0.2))
			draw_circle(p + Vector2(6, 3) * s, 2.0 * s, col.darkened(0.3))
		1:  # трава/шипы
			for i in 3:
				var a := -PI * 0.5 + (float(i) - 1.0) * 0.45
				draw_line(p, p + Vector2.from_angle(a) * 9.0 * s, col, 2.0)
		2:  # кости/обломки
			draw_line(p - Vector2(7, 2) * s, p + Vector2(7, 2) * s, col.lightened(0.2), 2.5)
			draw_circle(p - Vector2(7, 2) * s, 2.5 * s, col.lightened(0.2))
			draw_circle(p + Vector2(7, 2) * s, 2.5 * s, col.lightened(0.2))
		3:  # кристалл
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -9) * s, p + Vector2(4, 0) * s, p + Vector2(0, 4) * s, p + Vector2(-4, 0) * s]), col.lightened(0.3))
		4:  # трещина
			draw_polyline(PackedVector2Array([p, p + Vector2(8, 4) * s, p + Vector2(13, 1) * s, p + Vector2(20, 6) * s]),
				Color(0, 0, 0, 0.3), 1.5)
