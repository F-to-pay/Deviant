class_name Shooting
extends RefCounted
## Стрельба героя: спуск и очереди (`update`, `fire`), разброс («цветение» bloom), перезарядка из запаса, ритм-перезарядка арбалета
## (такты, попадания, промахи), щелчок «пусто» (`dry`), рисование кольца перезарядки. Пушки, патроны и запас — на `Player`
## (`guns`, `reserve`), навык и благословенный выстрел — `HeroSkill`. Экземпляр — `Player.shooting`.

var player: Player
var fire_cd: float = 0.0
var reload_t: float = 0.0
var reload_total: float = 1.0   # полная длительность текущей перезарядки (с перками)
var burst_left: int = 0
var burst_t: float = 0.0
var bloom: float = 0.0
var muzzle: float = 0.0
var _dry_cd: float = 0.0
var rhythm_phase := 0.0         # ритм-перезарядка: фаза такта 0..1 (такт — когда фаза переходит через 1)
var rhythm_lock := 0.0          # после промаха сокращать перезарядку нельзя ещё столько секунд
var rhythm_hit_beat := false    # в этом такте уже попал
var rhythm_hits := 0            # попаданий и промахов в текущей перезарядке — по ним решается, удачная ли она
var rhythm_fails := 0
var _touch_fire_prev := false    # ритм-перезарядка засчитывает и нажатие кнопки огня: фронт экранной кнопки
var rhythm_flash := 0.0         # вспышка кольца после нажатия
var rhythm_flash_col := Color.WHITE


func _init(p: Player = null) -> void:
	player = p


## Каждый физический кадр: гаснет дульная вспышка.
func tick(delta: float) -> void:
	if muzzle > 0.0:
		muzzle -= delta


func is_reloading() -> bool:
	return reload_t > 0.0


func reload_progress() -> float:
	var g := player.gun()
	if g == null or reload_t <= 0.0:
		return 0.0
	return 1.0 - reload_t / maxf(0.01, reload_total)


func dry(msg: String) -> void:
	if _dry_cd > 0.0:
		return
	_dry_cd = 1.2
	Game.main.sfx.empty_click()
	Game.main.fx.text(player.position + Vector2(0, -34), msg, Color(1.0, 0.5, 0.4), 15, 0.8)


## Ритм-перезарядка: такт — раз в секунду (RHYTHM_PERIOD), окно попадания ±RHYTHM_WINDOW около него. Нажатие R в окне сокращает
## перезарядку на RHYTHM_CUT с (один раз за такт). Нажатие мимо окна или лишнее — промах: сокращать нельзя RHYTHM_LOCK секунд.
func _rhythm_update(g: Gun, delta: float) -> void:
	rhythm_phase += delta / Gun.RHYTHM_PERIOD
	if rhythm_phase >= 1.0:
		rhythm_phase -= 1.0
	rhythm_lock = maxf(0.0, rhythm_lock - delta)
	rhythm_flash = maxf(0.0, rhythm_flash - delta)
	var in_window := _rhythm_in_window()
	if not in_window:
		rhythm_hit_beat = false
	# в такт можно жать и R, и огонь (ЛКМ / курок / экранная кнопка): стрелять во время перезарядки всё равно нельзя
	var tf := Game.controls.touch_fire
	var pressed := Input.is_action_just_pressed("reload") or Input.is_action_just_pressed("shoot") or (tf and not _touch_fire_prev)
	_touch_fire_prev = tf
	if not pressed:
		return
	var main: Main = Game.main
	if rhythm_lock > 0.0:
		Sfx.ui("ui/error", -14.0)
		return
	if in_window and not rhythm_hit_beat:
		rhythm_hit_beat = true
		rhythm_hits += 1
		reload_t -= Gun.RHYTHM_CUT
		rhythm_flash = 0.25
		rhythm_flash_col = Color(0.5, 1.0, 0.6)
		main.fx.text(player.position + Vector2(0, -34), "−%d s" % roundi(Gun.RHYTHM_CUT), Color(0.6, 1.0, 0.7), 15, 0.6)
		Sfx.ui("ui/click", -6.0, 1.5)
	else:
		rhythm_fails += 1
		rhythm_lock = Gun.RHYTHM_LOCK
		rhythm_flash = 0.35
		rhythm_flash_col = Color(1.0, 0.35, 0.3)
		main.fx.text(player.position + Vector2(0, -34), U.t("MISS"), Color(1.0, 0.45, 0.4), 15, 0.8)
		Sfx.ui("ui/error", -6.0)


func rhythm_active() -> bool:
	var g := player.gun()
	return g != null and g.rhythm and reload_t > 0.0


func _rhythm_in_window() -> bool:
	return rhythm_phase >= 1.0 - Gun.RHYTHM_WINDOW or rhythm_phase <= Gun.RHYTHM_WINDOW


## Перезарядка кончилась: каждое попадание в такт дало +RHYTHM_BONUS к урону новой обоймы (бонусы складываются; промахи их не отнимают).
func _rhythm_finish(g: Gun) -> void:
	g.rhythm_bonus = float(rhythm_hits) * Gun.RHYTHM_BONUS
	if rhythm_hits > 0:
		Game.main.fx.text(player.position + Vector2(0, -52), U.t("On the beat ×%d: +%d%% damage") % [rhythm_hits, roundi(g.rhythm_bonus * 100.0)], Color(0.6, 1.0, 0.7), 15, 1.2)


func start_reload(manual: bool = false) -> void:
	var g := player.gun()
	if g == null or reload_t > 0.0 or g.ammo >= g.mag_size:
		return
	if player.reserve_of(g.ammo_type()) <= 0 and not g.free_ammo:
		if manual or g.ammo <= 0:
			dry(U.t("NO AMMO"))
		return
	reload_t = g.reload_time
	reload_total = reload_t
	_touch_fire_prev = Game.controls.touch_fire   # огонь, зажатый до перезарядки, нажатием не считается
	rhythm_phase = 0.2   # первый такт — примерно через 0.8 с после старта
	rhythm_lock = 0.0
	rhythm_hit_beat = false
	rhythm_hits = 0
	rhythm_fails = 0
	burst_left = 0
	Game.main.sfx.reload_start(g)


func update(delta: float) -> void:
	var g := player.gun()
	bloom = maxf(0.0, bloom - delta * 25.0)
	if fire_cd > 0.0:
		fire_cd -= delta
	if g == null:
		return
	if reload_t > 0.0:
		if g.rhythm:
			_rhythm_update(g, delta)
		reload_t -= delta
		if reload_t <= 0.0:
			reload_t = 0.0
			if g.rhythm:
				_rhythm_finish(g)
			if g.free_ammo:
				g.ammo = g.mag_size
			else:
				var t := g.ammo_type()
				var take := mini(g.mag_size - g.ammo, player.reserve_of(t))
				g.ammo += take
				player.reserve[t] = player.reserve_of(t) - take
			Game.main.sfx.reload_done(g)
		return
	if burst_left > 0:
		burst_t -= delta
		if burst_t <= 0.0:
			if g.ammo >= 1:
				fire(g)
				burst_left -= 1
				burst_t = 0.065
			else:
				burst_left = 0
		return
	if _dry_cd > 0.0:
		_dry_cd -= delta
	if Input.is_action_just_pressed("reload"):
		start_reload(true)
		return
	# «Стрельба по отпусканию» (сенсор): один выстрел, когда отпустили правый стик
	if Game.controls.take_shot(fire_cd <= 0.0):
		if g.ammo <= 0:
			start_reload()
			return
		fire_cd = maxf(fire_cd, 0.0)
		_pull_trigger(g)
		return
	if not Game.controls.firing():
		if g.ammo <= 0 and (g.free_ammo or player.reserve_of(g.ammo_type()) > 0):
			start_reload()
		return
	var guard := 0
	while fire_cd <= 0.0 and guard < 4:
		if g.ammo <= 0:
			start_reload()
			return
		guard += 1
		if _pull_trigger(g):
			return


## Одно нажатие на спуск: выстрел (или первая пуля очереди) и пауза до следующего. true — началась очередь.
func _pull_trigger(g: Gun) -> bool:
	fire(g)
	if g.burst > 1:
		burst_left = g.burst - 1
		burst_t = 0.065
		fire_cd += float(g.burst) / g.fire_rate
		return true
	fire_cd += 1.0 / g.fire_rate
	return false


## Миномёт: точка падения = курсор (не дальше дальности), разброс сдвигает её
## пропорционально дистанции. Несколько мин (дробь) ложатся пятном.
func _fire_shells(g: Gun, mpos: Vector2, spr: float, n: int) -> void:
	var main: Main = Game.main
	var to := Game.controls.aim_world(player.position) - player.position
	var dist := clampf(to.length(), 60.0, g.eff_range())
	var aim_pt := player.position + player.aim * dist
	var dev := dist * tan(clampf(spr * 0.5, 0.0, 1.2))
	for i in n:
		var off := Vector2.from_angle(randf() * TAU) * dev * sqrt(randf())
		var p := main.projectiles.fire_shell(g, mpos, aim_pt + off)
		if p != null and player.skill.blessed:
			player.skill.bless_proj(p, n, 1)


func fire(g: Gun) -> void:
	var main: Main = Game.main
	if randf() >= LevelTree.free_shot_chance():   # узел «Экономный стрелок»: выстрел без траты патрона
		g.ammo = maxi(0, g.ammo - g.ammo_per_shot)
	g.shot_count += 1
	var base := player.aim.angle()
	var spr := deg_to_rad((g.spread + bloom) * LevelTree.spread_mult())
	var mpos := player.position + player.aim * (player.radius + 16.0)
	var n := g.pellets
	if g.proj_kind == GunData.K_SHELL:
		_fire_shells(g, mpos, spr, n)
	else:
		for i in n:
			var a := base
			if n > 1:
				a += lerpf(-spr * 0.5, spr * 0.5, (float(i) + 0.5) / float(n)) + randf_range(-0.08, 0.08) * spr
			else:
				a += randf_range(-spr * 0.5, spr * 0.5)
			var copies := 3 * player.skill.perk("split") if player.skill.blessed and player.skill.perk("split") > 0 else 1
			for c in copies:
				var ca := a + (float(c) - float(copies - 1) * 0.5) * 0.07
				var p := main.projectiles.fire_gun(g, mpos, Vector2.from_angle(ca), 0)
				if p != null and player.skill.blessed:
					player.skill.bless_proj(p, n, copies)
	if player.skill.blessed:
		player.skill.blessed = false
		player.skill.ready_pending = true
		main.fx.ring(mpos, 24.0, Color(1.0, 0.8, 0.3), 0.3)
	if g.special == "ring" and randf() < GunGen.proc_keep_chance(g):
		for k in 8:
			var dir := Vector2.from_angle(base + TAU * float(k) / 8.0)
			main.projectiles.fire_gun(g, player.position + dir * 18.0, dir, 0, 1.0)
	if g.special == "nuke10":
		# заряд копится от «веса» выстрела, а не от их количества
		g.nuke_charge += g.norm_damage() * float(n) / Gun.NUKE_COST
		if g.nuke_charge >= 1.0:
			g.nuke_charge -= 1.0
			main.projectiles.fire_nuke(g, mpos, player.aim)
			Game.say(U.t("NUKE!"), Color(1.0, 0.85, 0.3))
	bloom = minf(bloom + g.spread * 0.12 + 0.4, 18.0)
	muzzle = 0.06
	main.fx.muzzle_flash(mpos, player.aim, g.proj_color)
	main.sfx.gun_shot(g, mpos)
	main.fx.shake(minf(g.shake, 8.0))
	if g.recoil > 0.0:
		player.kick = (player.kick - player.aim * g.recoil).limit_length(Player.KICK_MAX)   # отдача корабельной пушки бросает героя назад
		main.fx.dust(player.position)


## Кольцо перезарядки вокруг героя и (для ритм-перезарядки) сжимающееся кольцо такта. ci — холст героя, bob — покачивание тела.
func draw_reload(ci: CanvasItem, bob: float) -> void:
	if reload_t > 0.0:
		ci.draw_arc(Vector2(0, bob), player.radius + 8.0, -PI * 0.5, -PI * 0.5 + TAU * reload_progress(), 24, Color(1, 1, 1, 0.8), 3.0)
		if rhythm_active():
			var ring_r := player.radius + 14.0
			var col := Color(0.55, 0.55, 0.6, 0.7) if rhythm_lock > 0.0 else (Color(0.5, 1.0, 0.6, 0.95) if _rhythm_in_window() else Color(1, 1, 1, 0.55))
			if rhythm_flash > 0.0:
				col = Color(rhythm_flash_col, 0.95)
			ci.draw_arc(Vector2(0, bob), ring_r, 0.0, TAU, 28, Color(col, 0.5), 2.0)   # цель
			ci.draw_arc(Vector2(0, bob), ring_r + (1.0 - rhythm_phase) * 36.0, 0.0, TAU, 32, col, 3.0)   # сжимающееся кольцо: жми, когда оно сошлось с целью
			if rhythm_lock > 0.0:
				ci.draw_arc(Vector2(0, bob), ring_r + 8.0, -PI * 0.5, -PI * 0.5 + TAU * rhythm_lock / Gun.RHYTHM_LOCK, 20, Color(1.0, 0.4, 0.35, 0.9), 2.0)
