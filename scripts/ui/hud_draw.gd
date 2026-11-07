class_name HudDraw
extends Control
## Рисует весь HUD одним _draw: здоровье, оружие, миникарта, босс, подсказки.

const MINI := 210.0

var hud: HUD


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	var main: Main = Game.main
	if main == null or main.player == null:
		return
	var vp := size     # область внутри отступов от краёв (UiFit), в единицах слоя
	var p := main.player
	var f := U.font()
	var fb := U.font_bold()

	_draw_hp(p, f, fb)
	_draw_zone_info(main, f, fb)
	_draw_weapons(p, vp, f, fb)
	_draw_minimap(main, vp, f)
	if main.boss != null and is_instance_valid(main.boss) and not main.boss.dead:
		_draw_boss(main.boss, vp, fb)
	if not hud.inv.visible and not hud.dead_screen:
		if main.near_item != null and is_instance_valid(main.near_item):
			var g: Gun = main.near_item.gun
			GunCard.draw_card(self, g, _card_pos(g, main.near_item.position, vp), p.gun())
			if Controls.mode != "touch":   # на сенсоре вместо подсказки — кнопки
				U.draw_text_c(self, fb, Vector2(vp.x * 0.5, vp.y - 170.0), U.t("[%s] Pick up     [%s] Swap with current     [%s] Scrap for ammo") % [
					Controls.label("interact"), Controls.label("swap"), Controls.label("scrap")], 18, Color(1, 1, 1), 4)
		elif main.near_chest != null and is_instance_valid(main.near_chest) and Controls.mode != "touch":
			U.draw_text_c(self, fb, Vector2(vp.x * 0.5, vp.y - 170.0), U.t("[%s] Open chest") % Controls.label("interact"), 18, Color(1.0, 0.9, 0.5), 4)
	_draw_messages(vp, fb)
	_draw_banner(vp, fb, f)
	if hud.help_t > 0.0 and Game.zone_level == 1 and Controls.mode != "touch":
		var a := clampf(hud.help_t / 2.0, 0.0, 1.0)
		U.draw_text_c(self, f, Vector2(vp.x * 0.5, vp.y - 205.0),
			U.t("%s — move · %s — shoot · %s — dodge · %s — reload · %s — loot · %s — inventory · %s — weapons") % [
				Controls.move_label(), Controls.label("shoot"), Controls.label("dodge"), Controls.label("reload"),
				"/".join(PackedStringArray([Controls.label("interact"), Controls.label("swap"), Controls.label("scrap")])),
				InputSetup.action_label("inventory", "pad" if Controls.mode == "pad" else "kb", 1), Controls.weapons_label()],
			15, Color(1, 1, 1, 0.85 * a), 3)
	if Game.debug:
		U.draw_text(self, f, Vector2(12, vp.y - 12), U.t("FPS %d · enemies %d · projectiles %d") % [Engine.get_frames_per_second(),
			main.enemies.size(), main.projectiles.count()], 13, Color(0.7, 1.0, 0.7), 3)
	if hud.fade > 0.0:
		draw_rect(Rect2(-position - Vector2(64, 64), get_viewport_rect().size + Vector2(128, 128)), Color(0, 0, 0, hud.fade))
	if bool(Game.setting("show_fps")) and not Game.debug:
		U.draw_text_r(self, f, Vector2(vp.x - 12, vp.y - 12), "FPS %d" % Engine.get_frames_per_second(), 14, Color(0.7, 1.0, 0.7), 3)
	if hud.dead_screen:
		_draw_death(vp, f, fb)


func _bar(r: Rect2, k: float, col: Color, bg: Color = Color(0, 0, 0, 0.6)) -> void:
	draw_rect(r.grow(2.0), Color(0, 0, 0, 0.7))
	draw_rect(r, bg)
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(k, 0.0, 1.0), r.size.y)), col)


func _draw_hp(p: Player, f: Font, fb: Font) -> void:
	var r := Rect2(24, 24, 320, 22)
	var col := Color(0.9, 0.22, 0.25)
	_bar(r, p.hp / p.max_hp, col)
	U.draw_text_c(self, fb, Vector2(r.position.x + r.size.x * 0.5, r.position.y + 17), "%s / %s" % [U.fmt(ceilf(p.hp)), U.fmt(p.max_hp)], 15, Color.WHITE, 3)
	# Перезарядка переката
	var dk := 1.0 - clampf(p.dodge_cd / Player.DODGE_CD, 0.0, 1.0)
	var dodge_ready := p.dodge_cd <= 0.0
	_bar(Rect2(24, 52, 120, 6), dk, Color(0.4, 0.85, 1.0) if dodge_ready else Color(0.3, 0.5, 0.7))
	var dl := U.t("dodge ready") if dodge_ready else U.t("dodge %.1f s") % p.dodge_cd
	U.draw_text(self, f, Vector2(150, 59), dl, 12, Color(0.7, 0.85, 1.0, 0.9 if dodge_ready else 0.6), 2)


func _draw_zone_info(main: Main, f: Font, fb: Font) -> void:
	var zname := U.t(str(main.zone.biome.get("name", "")))
	U.draw_text(self, fb, Vector2(24, 86), U.t("Zone %d · %s") % [Game.zone_level, zname], 17, Color(1, 1, 1), 3)
	U.draw_text(self, f, Vector2(24, 108), U.t("Kills: %d   Time: %s") % [Game.kills, U.fmt_time(Game.run_time)], 14, Color(0.8, 0.8, 0.85), 3)
	if Game.best_zone > 0:
		U.draw_text(self, f, Vector2(24, 128), U.t("Best: zone %d") % Game.best_zone, 13, Color(0.7, 0.7, 0.75), 3)


func _draw_weapons(p: Player, vp: Vector2, f: Font, fb: Font) -> void:
	var sw := 150.0
	var sh := 64.0
	var gap := 8.0
	var total := sw * 4.0 + gap * 3.0
	var x0 := vp.x * 0.5 - total * 0.5
	var y0 := vp.y - sh - 20.0
	for i in 4:
		var r := Rect2(x0 + float(i) * (sw + gap), y0, sw, sh)
		var g: Gun = p.guns[i]
		var is_active := i == p.active
		draw_rect(r, Color(0.05, 0.05, 0.08, 0.85 if is_active else 0.6))
		if g != null:
			var rc := g.rarity_color()
			draw_rect(r, Color(rc, 1.0 if is_active else 0.45), false, 3.0 if is_active else 1.5)
			var sc := clampf(110.0 / maxf(60.0, float(g.vis.get("len", 80.0))), 0.5, 1.4)
			GunIcon.draw_gun(self, g, r.get_center() + Vector2(0, -4), sc, 0.0, false, true)
			_bar(Rect2(r.position.x + 6, r.end.y - 9, r.size.x - 12, 4), float(g.ammo) / float(g.mag_size), Color(1.0, 0.85, 0.4))
			var rs := p.reserve_of(g.ammo_type())
			U.draw_text_r(self, U.font(), r.position + Vector2(r.size.x - 6, 16), "∞" if g.free_ammo else str(rs), 12,
				GunData.ammo_color(g.ammo_type()) if (rs > 0 or g.free_ammo) else Color(1.0, 0.35, 0.3), 2)
		else:
			draw_rect(r, Color(1, 1, 1, 0.12), false, 1.0)
		U.draw_text(self, fb, r.position + Vector2(6, 16), str(i + 1), 14, Color(1, 1, 1, 0.7), 2)
	# Активная пушка: имя и патроны
	var ag := p.gun()
	if ag != null:
		var cy := y0 - 14.0
		U.draw_text_c(self, fb, Vector2(vp.x * 0.5, cy - 26.0), ag.gun_name, 18, ag.rarity_color(), 4)
		var res := p.reserve_of(ag.ammo_type())
		var ammo_s := U.t("%d / %d   ·   reserve %d/%d %s") % [ag.ammo, ag.mag_size, res, GunData.ammo_cap(ag.ammo_type()), ag.ammo_name()]
		if ag.free_ammo:
			res = 1
			ammo_s = U.t("%d / %d   ·   reserve ∞") % [ag.ammo, ag.mag_size]
		if p.is_reloading():
			ammo_s = U.t("RELOADING")
		elif ag.ammo <= 0:
			if res > 0:
				ammo_s = U.t("EMPTY — [%s]") % Controls.label("reload") if Controls.mode != "touch" else U.t("EMPTY")
			else:
				ammo_s = U.t("NO AMMO: %s") % ag.ammo_name()
		U.draw_text_c(self, fb, Vector2(vp.x * 0.5, cy), ammo_s, 16, Color(1.0, 0.9, 0.6), 3)
		if p.is_reloading():
			_bar(Rect2(vp.x * 0.5 - 90, cy + 6, 180, 5), p.reload_progress(), Color(1, 1, 1))
	U.draw_text_r(self, f, Vector2(x0 - 12, vp.y - 30), U.t("backpack %d/%d") % [p.backpack.size(), Player.BACKPACK_SIZE], 13, Color(0.75, 0.75, 0.8), 2)


func _draw_minimap(main: Main, vp: Vector2, f: Font) -> void:
	var z := main.zone
	if z.minimap_tex == null or z.w == 0:
		return
	var r := Rect2(vp.x - MINI - 20.0, 20.0, MINI, MINI)
	draw_rect(r.grow(3.0), Color(0, 0, 0, 0.6))
	draw_rect(r, Color(0.02, 0.02, 0.03, 0.7))
	draw_texture_rect(z.minimap_tex, r, false)
	var ws := z.world_size()
	var k := Vector2(r.size.x / ws.x, r.size.y / ws.y)
	for o in main.chests:
		var c: Chest = o
		if not c.opened and z.is_explored(c.position):
			draw_rect(Rect2(r.position + c.position * k - Vector2(2.5, 2.5), Vector2(5, 5)), Color(1.0, 0.8, 0.3))
	for o in main.items:
		var it: GroundItem = o
		if it.gun.rarity >= GunData.R_EPIC:
			draw_circle(r.position + it.position * k, 2.5, it.gun.rarity_color())
	for o in main.enemies:
		var e: Enemy = o
		if e.elite >= 1 and e.awake and z.is_explored(e.position):
			draw_circle(r.position + e.position * k, 3.0 if e.elite < 3 else 5.0,
				Color(1.0, 0.85, 0.3) if e.elite == 2 else (Color(0.5, 0.7, 1.0) if e.elite == 1 else Color(1, 0.2, 0.2)))
	if main.portal != null and is_instance_valid(main.portal):
		var pp := r.position + main.portal.position * k
		var pulse := 4.0 + sin(Time.get_ticks_msec() * 0.006) * 1.5
		draw_circle(pp, pulse, Color(0.75, 0.4, 1.0))
		draw_arc(pp, pulse + 3.0, 0.0, TAU, 16, Color(1, 1, 1, 0.8), 1.0)
	var me := r.position + main.player.position * k
	draw_circle(me, 3.5, Color(0.4, 0.9, 1.0))
	draw_line(me, me + main.player.aim * 9.0, Color(0.4, 0.9, 1.0), 1.5)
	U.draw_text_r(self, f, Vector2(r.end.x, r.end.y + 16), U.t("portal — purple"), 12, Color(0.7, 0.7, 0.75, 0.7), 2)


func _draw_boss(b: Boss, vp: Vector2, fb: Font) -> void:
	var w := 620.0
	var r := Rect2(vp.x * 0.5 - w * 0.5, 34, w, 16)
	_bar(r, b.hp / b.max_hp, Color(0.85, 0.15, 0.2) if not b.enraged else Color(1.0, 0.4, 0.1))
	U.draw_text_c(self, fb, Vector2(vp.x * 0.5, r.position.y - 6), b.title, 18, Color(1.0, 0.85, 0.4), 4)


func _draw_messages(vp: Vector2, fb: Font) -> void:
	var y := vp.y - 240.0
	for i in range(hud.messages.size() - 1, -1, -1):
		var m: Array = hud.messages[i]
		var a := clampf(float(m[2]) / 0.6, 0.0, 1.0)
		var c: Color = m[1]
		U.draw_text_c(self, fb, Vector2(vp.x * 0.5, y), str(m[0]), 17, Color(c, a), 4)
		y -= 26.0


func _draw_banner(vp: Vector2, fb: Font, f: Font) -> void:
	if hud.banner_t <= 0.0:
		return
	var a := clampf(hud.banner_t / 0.8, 0.0, 1.0) * clampf((3.2 - hud.banner_t) / 0.3, 0.0, 1.0)
	U.draw_text_c(self, fb, Vector2(vp.x * 0.5, vp.y * 0.28), hud.banner_text, 48, Color(1, 1, 1, a), 6)
	U.draw_text_c(self, f, Vector2(vp.x * 0.5, vp.y * 0.28 + 40.0), hud.banner_sub, 22, Color(0.85, 0.8, 1.0, a), 4)


func _draw_death(vp: Vector2, f: Font, fb: Font) -> void:
	var a := clampf(hud.death_t / 0.8, 0.0, 1.0)
	draw_rect(Rect2(-position - Vector2(64, 64), get_viewport_rect().size + Vector2(128, 128)), Color(0.15, 0.0, 0.0, 0.7 * a))
	U.draw_text_c(self, fb, Vector2(vp.x * 0.5, vp.y * 0.26), U.t(hud.death_title), 60, Color(1.0, 0.3, 0.25, a), 7)
	var y := vp.y * 0.38
	var lines: Array = [
		U.t("Reached zone %d") % Game.zone_level,
		U.t("Kills: %d   ·   Time: %s   ·   Guns found: %d") % [Game.kills, U.fmt_time(Game.run_time), Game.guns_found],
		Menu.run_info(),
		U.t("Rating: %s   (points %s × %.2f)%s") % [U.fmt(float(Game.rating())), U.fmt(float(Game.run_points())), Game.rating_mult(),
			U.t("   — NEW BEST!") if Game.new_rating_record else U.t("   · best: ") + U.fmt(float(Game.best_rating))],
	]
	for l in lines:
		U.draw_text_c(self, f, Vector2(vp.x * 0.5, y), str(l), 22, Color(1, 1, 1, a), 3)
		y += 36.0
	if Game.best_gun != null:
		U.draw_text_c(self, f, Vector2(vp.x * 0.5, y), U.t("Best find:"), 18, Color(0.8, 0.8, 0.8, a), 3)
		y += 30.0
		U.draw_text_c(self, fb, Vector2(vp.x * 0.5, y), Game.best_gun.gun_name, 22, Color(Game.best_gun.rarity_color(), a), 4)
		y += 40.0
	if hud.new_record:
		U.draw_text_c(self, fb, Vector2(vp.x * 0.5, y), U.t("NEW RECORD!"), 28, Color(1.0, 0.85, 0.3, a), 4)
	elif not Game.counts_for_records():
		U.draw_text_c(self, f, Vector2(vp.x * 0.5, y), U.t("Custom start — record not counted"), 18, Color(0.8, 0.8, 0.8, a), 3)
	else:
		U.draw_text_c(self, f, Vector2(vp.x * 0.5, y), U.t("Best: zone %d") % Game.best_zone, 18, Color(0.8, 0.8, 0.8, a), 3)
	y += 60.0
	if hud.death_t > 0.6:
		if Controls.mode != "touch":    # на сенсоре — кнопки (TouchControls)
			var again := InputSetup.action_label("restart", "pad", 1) if Controls.mode == "pad" else Controls.label("reload")
			U.draw_text_c(self, fb, Vector2(vp.x * 0.5, y), U.t("[%s] — one more time") % again, 24, Color(1, 1, 1, a), 4)
			U.draw_text_c(self, f, Vector2(vp.x * 0.5, y + 36.0), U.t("[%s] — main menu") % Controls.label("pause"), 18, Color(0.8, 0.8, 0.8, a), 3)


## Где показать карточку пушки на земле (настройка gun_card): справа, слева или над самой пушкой.
func _card_pos(g: Gun, world: Vector2, vp: Vector2) -> Vector2:
	var card_h := GunCard.height(g)
	var cy := clampf(vp.y * 0.5 - card_h * 0.5, 70.0, vp.y - card_h - 150.0)
	match str(Game.setting("gun_card")):
		"left":
			return Vector2(24.0, maxf(cy, 150.0))
		"above":
			# мир -> экран -> координаты этого Control (он масштабирован и сдвинут UiFit)
			var screen := get_viewport().get_canvas_transform() * world
			var local := get_global_transform_with_canvas().affine_inverse() * screen
			var pos := local - Vector2(GunCard.W * 0.5, card_h + 46.0)
			return Vector2(clampf(pos.x, 8.0, vp.x - GunCard.W - 8.0), clampf(pos.y, 8.0, vp.y - card_h - 8.0))
	return Vector2(vp.x - GunCard.W - 24.0, cy)
