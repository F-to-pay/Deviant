class_name GunCard
extends RefCounted
## Карточка пушки в стиле лутер-шутера, со сравнением с текущей.

const W := 340.0
const ROW := 19.0
const ICON_H := 84.0


## Сколько строк займёт имя (полные названия марок длинные — до 3 строк).
static func name_lines(g: Gun) -> int:
	return clampi(ceili(U.text_w(U.font_bold(), g.gun_name, 17) * 1.08 / (W - 24.0)), 1, 3)


static func height(g: Gun) -> float:
	var rows := 8 + (1 if g.element >= 0 else 0)
	var perks := g.perk_lines().size()
	var fl_lines := clampi(ceili(U.text_w(U.font(), U.t(g.flavor), 13) / (W - 24.0)), 1, 3)
	return 14.0 + 22.0 * name_lines(g) + 20.0 + 18.0 + 4.0 + ICON_H + 6.0 + ROW * rows + 8.0 + 18.0 * perks + 6.0 + 17.0 * fl_lines + 12.0


static func draw_card(ci: CanvasItem, g: Gun, pos: Vector2, cmp: Gun = null) -> float:
	var f := U.font()
	var fb := U.font_bold()
	var col := g.rarity_color()
	var h := height(g)
	var bg := Rect2(pos, Vector2(W, h))
	ci.draw_rect(bg, Color(0.05, 0.05, 0.07, 0.94))
	ci.draw_rect(Rect2(pos, Vector2(W, 6)), col)
	ci.draw_rect(bg, Color(col, 0.8), false, 2.0)

	var y := pos.y + 14.0
	var nl := name_lines(g)
	ci.draw_multiline_string(fb, Vector2(pos.x + 12.0, y + 17.0), g.gun_name, HORIZONTAL_ALIGNMENT_LEFT,
		W - 24.0, 17, nl, col)
	y += 22.0 * nl
	U.draw_text(ci, f, Vector2(pos.x + 12.0, y + 14.0), U.t("%s · %s · lvl %d") % [g.rarity_name(), g.type_name(), g.level], 13,
		Color(0.78, 0.78, 0.82))
	y += 20.0
	U.draw_text(ci, f, Vector2(pos.x + 12.0, y + 12.0), g.maker_name() + U.t("  ·  ammo: ") + g.ammo_name(), 12, Color(g.body_color.lightened(0.35)))
	y += 18.0

	# Иконка: вписываем и по ширине, и по высоте. Над осью ствола — корпус + прицел/труба
	# (до bh + 10), под осью — рукоять и магазин (~16). Ось ставим так, чтобы всё легло в рамку.
	y += 4.0
	ci.draw_rect(Rect2(pos.x + 10.0, y, W - 20.0, ICON_H), Color(1, 1, 1, 0.04))
	var bh := float(g.vis.get("bh", 10.0))
	var up := bh + 10.0
	var down := 16.0
	var sc := minf(230.0 / maxf(60.0, float(g.vis.get("len", 80.0))), (ICON_H - 10.0) / (up + down))
	sc = clampf(sc, 0.8, 2.2)
	var axis_y := y + (ICON_H - (up + down) * sc) * 0.5 + up * sc
	GunIcon.draw_gun(ci, g, Vector2(pos.x + W * 0.5, axis_y), sc, 0.0, false, true)
	y += ICON_H + 6.0

	# Статы
	var rows: Array = []
	var dmg_s := U.fmt(g.damage) + (" ×%d" % g.pellets if g.pellets > 1 else "")
	rows.append([U.t("Damage"), dmg_s, g.damage * g.pellets, cmp.damage * cmp.pellets if cmp else 0.0, true])
	rows.append([U.t("DPS"), U.fmt(g.dps()), g.dps(), cmp.dps() if cmp else 0.0, true])
	rows.append([U.t("Fire rate"), U.t("%.1f/s") % g.fire_rate, g.fire_rate, cmp.fire_rate if cmp else 0.0, true])
	rows.append([U.t("Accuracy"), "%d%%" % g.accuracy(), float(g.accuracy()), float(cmp.accuracy()) if cmp else 0.0, true])
	rows.append([U.t("Range"), U.t("%d m") % roundi(g.eff_range() / 40.0), g.eff_range(), cmp.eff_range() if cmp else 0.0, true])
	rows.append([U.t("Magazine"), str(g.mag_size), float(g.mag_size), float(cmp.mag_size) if cmp else 0.0, true])
	rows.append([U.t("Reload"), U.t("%.1f s") % g.reload_time, g.reload_time, cmp.reload_time if cmp else 0.0, false])
	rows.append([U.t("Crit"), "%d%% ×%.1f" % [roundi(g.crit_chance * 100.0), g.crit_mult],
		g.crit_chance * g.crit_mult, cmp.crit_chance * cmp.crit_mult if cmp else 0.0, true])
	for r in rows:
		_row(ci, f, pos.x, y, str(r[0]), str(r[1]), float(r[2]), float(r[3]), bool(r[4]), cmp != null and cmp != g)
		y += ROW
	if g.element >= 0:
		var ec := U.el_color(g.element)
		U.draw_text(ci, f, Vector2(pos.x + 12.0, y + 14.0), U.t("Element"), 14, Color(0.7, 0.7, 0.75))
		U.draw_text_r(ci, fb, Vector2(pos.x + W - 30.0, y + 14.0), g.elem_text(), 14, ec)
		y += ROW
	y += 8.0

	# Особенности
	for pl in g.perk_lines():
		U.draw_text(ci, f, Vector2(pos.x + 14.0, y + 13.0), "• " + str(pl[0]), 13, pl[1])
		y += 18.0
	y += 6.0

	# Флейвор
	var fl_col := Color(1.0, 0.45, 0.3) if g.rarity >= GunData.R_LEGENDARY else Color(0.6, 0.6, 0.65)
	ci.draw_multiline_string(f, Vector2(pos.x + 12.0, y + 13.0), U.t(g.flavor), HORIZONTAL_ALIGNMENT_LEFT, W - 24.0, 13, 3, fl_col)
	return h


static func _row(ci: CanvasItem, f: Font, x: float, y: float, label: String, val: String, a: float, b: float,
		higher_better: bool, show_cmp: bool) -> void:
	U.draw_text(ci, f, Vector2(x + 12.0, y + 14.0), label, 14, Color(0.7, 0.7, 0.75))
	U.draw_text_r(ci, U.font_bold(), Vector2(x + W - 30.0, y + 14.0), val, 14, Color(0.95, 0.95, 0.95))
	if not show_cmp or absf(a - b) <= absf(b) * 0.01:
		return
	var better := (a > b) == higher_better
	var c := Color(0.35, 1.0, 0.45) if better else Color(1.0, 0.35, 0.35)
	var cx := x + W - 16.0
	var cy := y + 9.0
	if a > b:
		ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - 5, cy + 4), Vector2(cx + 5, cy + 4), Vector2(cx, cy - 4)]), c)
	else:
		ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - 5, cy - 4), Vector2(cx + 5, cy - 4), Vector2(cx, cy + 4)]), c)
