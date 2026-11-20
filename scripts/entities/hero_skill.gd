class_name HeroSkill
extends RefCounted
## Активный навык героя и его перки (Мистик): заряды и перезарядка, применение (`use`) — граната Первопроходца, турель Инженера,
## благословенный выстрел Шерифа, удар Ассасина, — урон навыка (`dmg_mult`), перки текущего забега, рисование эффектов.
## Данные героев и перков — `Heroes`, эффекты попаданий — `Skills`. Экземпляр — `Player.skill`.

var player: Player
var cd: float = 0.0              # перезарядка следующего заряда навыка
var charges: int = 1             # готовых зарядов навыка («Дополнительная рука» даёт больше)
var gap: float = 0.0             # пауза между применениями, чтобы зажатая кнопка не тратила все заряды разом
var element: int = -1            # стихия навыка (перк «Стихия»), -1 — нет
var trophy_bonus: float = 0.0    # «Трофеи»: прибавка к урону навыка за убийства навыком
var parry_cd: float = 0.0        # «Парирование»: до готовности
var ready_pending := false       # «Готовность»: этот навык ещё не снимал КД рывка
var blessed := false             # Шериф: следующий выстрел усилен (навык)
var slash_t: float = 0.0         # Ассасин: идёт удар (замедление, дуга на экране)
var slash_dir := Vector2.RIGHT
var run_perks: Dictionary = {}   # перки навыка (Мистик) на этот забег: id -> сколько раз взят (Heroes.PERKS)


func _init(p: Player = null) -> void:
	player = p


## Новый забег: перки и накопленные бонусы сбрасываются.
func reset() -> void:
	run_perks = {}
	element = -1
	trophy_bonus = 0.0


## Герой сменился (стартовый город): навык готов сразу.
func on_hero_set() -> void:
	cd = 0.0
	charges = max_charges()
	parry_cd = 0.0
	blessed = false
	slash_t = 0.0


## Каждый физический кадр: копим следующий заряд, таймеры паузы, парирования и удара.
func tick(delta: float) -> void:
	if charges < max_charges():
		cd -= delta
		if cd <= 0.0:
			charges += 1
			cd = max_cd() if charges < max_charges() else 0.0
	if gap > 0.0:
		gap -= delta
	if parry_cd > 0.0:
		parry_cd -= delta
	if slash_t > 0.0:
		slash_t -= delta


func max_cd() -> float:
	return float(Heroes.get_hero(player.hero)["cd"]) + float(perk("heavy"))   # «Тяжёлый снаряд»: +1 с за взятие


func max_charges() -> int:
	return 1 + perk("hand")


## Сколько раз взят перк навыка (0 — нет; у чужого героя перк не работает).
func perk(id: String) -> int:
	if not Heroes.perk_fits(id, player.hero):
		return 0
	return int(run_perks.get(id, 0))


## Множитель урона навыка от перков: разделение, тяжёлый, яд, точный, трофеи, вандализм и дерево навыков (skill_dmg).
func dmg_mult() -> float:
	var k := (1.0 + 0.2 * perk("split")) * (1.0 + 0.2 * perk("heavy")) * (1.0 + 0.5 * perk("poison")) \
		* (1.0 + 0.1 * perk("precise")) * (1.0 + trophy_bonus) * (1.0 + LevelTree.stat("skill_dmg"))
	if perk("vandal") > 0:
		k *= 0.5
	return k


## Взять перк навыка у Мистика. el — стихия для перка «Стихия».
func add_run_perk(id: String, el: int = -1) -> void:
	run_perks[id] = int(run_perks.get(id, 0)) + 1
	if id == "element":
		element = el
	if id == "hand":
		charges += 1


## Навык нанёс урон: «Готовность» — минус секунда КД рывка (один раз за применение).
func on_damage() -> void:
	if ready_pending and perk("ready") > 0:
		ready_pending = false
		player.dodge_cd = maxf(0.0, player.dodge_cd - 1.0)


## Убийство навыком: «Трофеи» — монета и прибавка к урону навыка.
func on_kill(e: Node2D) -> void:
	var tr := perk("trophies")
	if tr <= 0:
		return
	trophy_bonus += 0.002 + 0.0005 * float(tr - 1)
	Game.state.add_coins(1)
	Quests.progress("coins", 1)
	Game.main.fx.text(e.position + Vector2(0, -30), "+1", Color(1.0, 0.85, 0.3), 14, 0.7)


func run_perk_count() -> int:
	var n := 0
	for id in run_perks:
		n += int(run_perks[id])
	return n


## cast — отдельный стик навыка на сенсоре: {"dir", "len"}; null или dir = ZERO — целимся, как обычно.
func use(cast: Variant = null) -> void:
	var main: Main = Game.main
	var h := Heroes.get_hero(player.hero)
	var col: Color = h["color"] if element < 0 else U.el_color(element)
	# турель: сначала проверки (лимит, патроны) — заряд тратится, только если бросок состоится
	var turret_spec: Dictionary = {}
	if str(h["skill"]) == "turret":
		turret_spec = make_turret_spec()
		if turret_spec.is_empty():
			return
	if charges >= max_charges():
		cd = max_cd()   # заряд пошёл в дело — начинаем копить следующий
	charges -= 1
	gap = 0.3
	ready_pending = true
	var sdmg := float(h["dmg"]) * dmg_mult()
	match str(h["skill"]):
		"grenade":
			# в точку прицела, но не дальше range. «Разделение» — 3×N гранат, урон поровну;
			# ложатся пятном вокруг точки прицела, как мины миномёта (чем дальше бросок, тем шире пятно)
			var cdir := player.aim
			var dist: float
			if cast is Dictionary and (cast["dir"] as Vector2) != Vector2.ZERO:
				# своим стиком: направление — куда потянули, дальность — насколько сильно
				cdir = (cast["dir"] as Vector2).normalized()
				dist = lerpf(60.0, float(h["range"]), clampf(float(cast["len"]), 0.0, 1.0))
			else:
				var to := Game.controls.aim_world(player.position) - player.position
				dist = clampf(to.length(), 40.0, float(h["range"]))
			var target := player.position + cdir * dist
			var n := 3 * perk("split") if perk("split") > 0 else 1
			var dev := (20.0 + dist * 0.14) * sqrt(float(n) / 3.0)
			for i in n:
				var off := Vector2.ZERO
				if n > 1:
					off = Vector2.from_angle(randf() * TAU) * dev * sqrt(randf())
				main.projectiles.throw_grenade(player.position + cdir * (player.radius + 6.0), target + off, sdmg / float(n), float(h["r"]), col)
			Sfx.at("player/dodge", player.position, -6.0, 1.4, 0.06, 1, 0.1)
		"turret":
			var tdir := player.aim
			var tdist: float
			if cast is Dictionary and (cast["dir"] as Vector2) != Vector2.ZERO:
				tdir = (cast["dir"] as Vector2).normalized()
				tdist = lerpf(60.0, float(h["range"]), clampf(float(cast["len"]), 0.0, 1.0))
			else:
				tdist = clampf((Game.controls.aim_world(player.position) - player.position).length(), 40.0, float(h["range"]))
			var tpos := player.position + tdir * tdist
			# в скале или пропасти турель не встанет — ищем свободное место рядом
			if main.zone.circle_blocked(tpos, 18.0):
				tpos = main.zone.random_free_near(tpos, 0.0, 90.0)
				if main.zone.circle_blocked(tpos, 18.0):
					tpos = player.position
			turret_spec["el"] = element
			main.projectiles.throw_turret(player.position + tdir * (player.radius + 6.0), tpos, turret_spec, col)
			Sfx.at("player/dodge", player.position, -6.0, 0.8, 0.06, 1, 0.1)
		"bless":
			blessed = true
			main.fx.ring(player.position, 34.0, Color(1.0, 0.8, 0.3), 0.4)
			Sfx.at("player/perfect", player.position, -6.0, 0.7, 0.04, 1, 0.1)
		"slash":
			slash_t = float(h["time"])
			var sdir := player.aim
			if cast is Dictionary and (cast["dir"] as Vector2) != Vector2.ZERO:
				sdir = (cast["dir"] as Vector2).normalized()   # своим стиком на сенсоре
			slash_dir = sdir
			var r := float(h["r"])
			var half := deg_to_rad(float(h["arc"])) * 0.5
			var hits := 0
			for o in main.grid_hash.query(player.position, r + 60.0):
				var e: Enemy = o
				if e.dead:
					continue
				var to_e := e.position - player.position
				if to_e.length() > r + e.radius:
					continue
				# совсем вплотную — бьём в любом случае, иначе только в дуге
				if to_e.length() > e.radius + player.radius and absf(sdir.angle_to(to_e)) > half:
					continue
				Skills.hit(e, sdmg, to_e.normalized() * 160.0)
				hits += 1
			# «Парирование»: раз в 4 с удар разворачивает вражеские снаряды
			var pr := perk("parry")
			if pr > 0 and parry_cd <= 0.0:
				var refl := main.projectiles.reflect(player.position, sdir, r + 20.0, half, 1.0 + 0.3 * float(pr - 1))
				if refl > 0:
					parry_cd = 4.0
					main.fx.ring(player.position, r, Color(0.85, 0.7, 1.0), 0.3)
					Sfx.at("player/perfect", player.position, -5.0, 1.3, 0.04, 1, 0.1)
			Sfx.at("player/dodge", player.position, -5.0, 1.6, 0.08, 2, 0.05)
			if hits > 0:
				Sfx.at("hit/body", player.position, -6.0, 1.2, 0.08, 2, 0.05)
				main.fx.shake(2.0)


## Что унесёт турель Инженера: {gun, ammo}. Пустой словарь — бросать нельзя (сообщение уже показано).
## Обычная турель — копия активной пушки и ВСЕ патроны из её текущей обоймы; пушка остаётся пустой, герой перезаряжается
## (из запаса, как обычно; у Синергиса перезарядка бесплатная).
## Обойма у турели всегда конечная — расстреляла и сломалась; «Экономия» даёт сверху +40% за взятие.
## «Безумный Учёный» — случайная пушка Синергис на редкость выше: у героя ничего не берётся, обойма — её полная.
func make_turret_spec() -> Dictionary:
	var main: Main = Game.main
	# лимит здесь не проверяем: сверх лимита самая старая турель убирается при посадке новой (Main.spawn_turret)
	var g := player.gun()
	if g == null:
		return {}
	var tg: Gun
	var n: int
	var take := 0
	if perk("scientist") > 0:
		# легендарка может быть привязана к другой марке — тогда free_ammo выставляем сами, а перки с повышенным расходом
		# патронов (Двуствольный) для безлимитной пушки недопустимы: перебрасываем, пока не пропадут
		for attempt in 30:
			tg = GunGen.generate(Game.state.zone_level, main.rng, 0.0, 0, mini(g.rarity + 1, GunData.R_LEGENDARY), "", "synergis")
			var costly := tg.ammo_per_shot > 1
			for m in tg.mods:
				if GunData.perk_costs_ammo(GunData.perk(str(m))):
					costly = true
			if not costly:
				break
		tg.free_ammo = true
		n = tg.mag_size
	else:
		tg = g.copy()
		if player.shooting.reload_t > 0.0:
			player.shooting.dry(U.t("RELOADING"))   # обойма в процессе — брать нечего
			return {}
		take = g.ammo
		if take <= 0:
			player.shooting.dry(U.t("NO AMMO"))
			return {}
		n = take
	n = maxi(1, roundi(float(n) * (1.0 + 0.4 * float(perk("economy")))))
	tg.ammo = n
	if take > 0:
		g.ammo = 0
		player.shooting.burst_left = 0
		player.shooting.start_reload()   # без запаса сообщит «NO AMMO» — турель всё равно получила патроны
	return {"gun": tg, "ammo": n}


## Благословлённый выстрел Шерифа: снаряды помечены как навык (Skills), к урону — бонус навыка
## (делится между дробинами/минами). «Разделение» — 3×N копий каждого снаряда веером, урон поровну;
## «Точный выстрел» — самонаведение и дальность.
func bless_proj(p: Projectiles.Proj, n: int, copies: int) -> void:
	p.skill = true
	p.dmg = (p.dmg + float(Heroes.get_hero(player.hero)["dmg"]) * dmg_mult() / float(maxi(1, n))) / float(copies)
	if element >= 0:
		p.color = U.el_color(element)
	var pc := perk("precise")
	if pc > 0:
		p.homing = maxf(p.homing, 5.0)
		p.eff_range *= 1.0 + 0.2 * float(pc)


## Эффекты навыка вокруг героя (рисуются под телом): аура благословения, превью броска/удара, дуга удара. ci — холст героя.
func draw_effects(ci: CanvasItem) -> void:
	if blessed:
		var pulse := 1.0 + sin(player.anim * 8.0) * 0.15
		ci.draw_circle(Vector2.ZERO, (player.radius + 7.0) * pulse, Color(1.0, 0.8, 0.3, 0.22))
		ci.draw_arc(Vector2.ZERO, (player.radius + 7.0) * pulse, 0.0, TAU, 24, Color(1.0, 0.85, 0.4, 0.8), 2.0)
	if Game.controls.skill_aim != Vector2.ZERO:
		draw_preview(ci)
	if slash_t > 0.0:
		# дуга удара: метёт от одного края к другому
		var hs := Heroes.get_hero(player.hero)
		var half := deg_to_rad(float(hs["arc"])) * 0.5
		var k := 1.0 - clampf(slash_t / float(hs["time"]), 0.0, 1.0)
		var a0 := slash_dir.angle() - half
		var a1 := a0 + half * 2.0 * minf(1.0, k * 1.6)
		var sc: Color = hs["color"]
		ci.draw_arc(Vector2.ZERO, float(hs["r"]) * 0.8, a0, a1, 20, Color(sc.lightened(0.4), 0.9 * (1.0 - k * 0.6)), 10.0)
		ci.draw_arc(Vector2.ZERO, float(hs["r"]) * 0.8 + 8.0, a0, a1, 20, Color(1, 1, 1, 0.5 * (1.0 - k)), 3.0)


## Превью броска, пока тянешь стик навыка: линия, круг взрыва в точке падения и кольцо максимальной дальности.
func draw_preview(ci: CanvasItem) -> void:
	var hd := Heroes.get_hero(player.hero)
	if not bool(hd.get("aimed", false)):
		return
	var col: Color = hd["color"] if element < 0 else U.el_color(element)
	var sd := Game.controls.skill_aim
	var dir := sd.normalized()
	var ready := charges > 0
	var a := 1.0 if ready else 0.4
	if str(hd["skill"]) == "slash":
		# сектор удара: куда и насколько широко ударим
		var sr := float(hd["r"])
		var half := deg_to_rad(float(hd["arc"])) * 0.5
		var pts := PackedVector2Array([Vector2.ZERO])
		for k in 13:
			pts.append(Vector2.from_angle(dir.angle() - half + half * 2.0 * float(k) / 12.0) * sr)
		ci.draw_colored_polygon(pts, Color(col, 0.16 * a))
		ci.draw_arc(Vector2.ZERO, sr, dir.angle() - half, dir.angle() + half, 20, Color(col, 0.85 * a), 2.0)
		ci.draw_line(Vector2.ZERO, Vector2.from_angle(dir.angle() - half) * sr, Color(col, 0.5 * a), 2.0)
		ci.draw_line(Vector2.ZERO, Vector2.from_angle(dir.angle() + half) * sr, Color(col, 0.5 * a), 2.0)
		return
	var d := lerpf(60.0, float(hd["range"]), clampf(sd.length(), 0.0, 1.0))
	ci.draw_arc(Vector2.ZERO, float(hd["range"]), 0.0, TAU, 48, Color(col, 0.12 * a), 2.0)
	ci.draw_line(dir * (player.radius + 6.0), dir * d, Color(col, 0.4 * a), 2.0)
	ci.draw_circle(dir * d, float(hd["r"]), Color(col, 0.14 * a))
	ci.draw_arc(dir * d, float(hd["r"]), 0.0, TAU, 32, Color(col, 0.85 * a), 2.0)
