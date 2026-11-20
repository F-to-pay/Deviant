class_name Turret
extends Actor
## Турель Инженера (Heroes: skill "turret"). Прилетает миной (Projectiles.throw_turret), встаёт в точку падения
## и стреляет в ближайшего видимого врага копией пушки героя. Враги видят в ней цель наравне с героем
## (Main.target_for — кто ближе). Здоровье — как у героя; стоит, пока её не разбили, но с последним патроном
## обоймы ломается сразу. Бесконечных турелей нет: обойма конечна всегда (у пушки Синергис тоже).
## Урон по ней — через take_damage (вражеские пули, взрывы, касание, таран).

const BASH_R := 150.0        # удар при попадании по турели: враги в этом радиусе отлетают
const MIN_RANGE := 400.0    # 10 м: у пушки с короткой дальностью турель всё равно достаёт хотя бы до сюда
const MAX_RANGE := 1600.0   # 40 м: потолок, даже у револьвера (дальность 1000 м)
const BASH_KNOCK := 650.0    # скорость отбрасывания (Enemy.knock); тормозится 1800/с²
const BASH_STUN := 1.0       # стан отброшенных, с
const BURST_GAP := 0.065
const DMG_MULT := 0.5        # турель бьёт вполсилы: урон пули — 50% от урона пушки
const INVULN := 0.25        # пауза после попадания: дробь и кольца пуль не должны убивать за кадр

var gun: Gun = null
var ammo: int = 0
var max_ammo: int = 1
var element: int = -1        # стихия навыка героя (перк «Стихия»)
var target: Enemy = null
var aim: Vector2 = Vector2.RIGHT
var aim_dist: float = 300.0
var fire_cd: float = 0.35    # после посадки — короткая пауза
var burst_left: int = 0
var burst_t: float = 0.0
var invuln: float = 0.0
var anim: float = 0.0
var age: float = 0.0
var recoil: float = 0.0
var _scan_t: float = 0.0
var _col: Color = Color(0.95, 0.8, 0.25)


## spec: {gun: Gun, ammo: int, el: int} — собирает Player._make_turret_spec.
func setup(spec: Dictionary) -> void:
	gun = spec["gun"]
	ammo = int(spec["ammo"])
	max_ammo = maxi(1, ammo)
	element = int(spec.get("el", -1))
	radius = 15.0
	max_hp = Game.main.player.max_hp
	hp = max_hp
	_col = Heroes.color("engineer") if element < 0 else U.el_color(element)
	scale = Vector2.ONE * 0.4


func _ready() -> void:
	var main: Main = Game.main
	main.fx.dust(position)
	main.fx.ring(position, 36.0, _col, 0.3)
	Sfx.at("hit/wall", position, -8.0, 0.7, 0.05, 2, 0.05)


## Турель стреляет на эффективную дальность своей пушки, но не короче 10 м и не дальше 40 м (1 м = 40 px).
func _range() -> float:
	return clampf(gun.eff_range(), MIN_RANGE, MAX_RANGE)


func _physics_process(delta: float) -> void:
	if dead:
		return
	var main: Main = Game.main
	anim += delta
	age += delta
	if age < 0.25:
		scale = Vector2.ONE * lerpf(0.4, 1.0, clampf(age / 0.2, 0.0, 1.0))
	elif scale != Vector2.ONE:
		scale = Vector2.ONE
	if flash > 0.0:
		flash -= delta
	if invuln > 0.0:
		invuln -= delta
	if recoil > 0.0:
		recoil = maxf(0.0, recoil - delta * 40.0)
	if fire_cd > 0.0:
		fire_cd -= delta
	_scan_t -= delta
	if _scan_t <= 0.0 or (target != null and (not is_instance_valid(target) or target.dead)):
		_scan_t = 0.12
		target = _find_target(main)
	if burst_left > 0:
		burst_t -= delta
		if burst_t <= 0.0:
			_fire(main)
			burst_left -= 1
			burst_t = BURST_GAP
		queue_redraw()
		return
	if target != null and is_instance_valid(target):
		var to := target.position - position
		aim_dist = to.length()
		if aim_dist > 1.0:
			aim = to / aim_dist
		var guard := 0
		while fire_cd <= 0.0 and guard < 3 and not dead:
			guard += 1
			_pull_trigger(main)
			if burst_left > 0:
				break
	queue_redraw()


## Ближайший видимый (по прямой, без скал) враг в пределах дальности.
func _find_target(main: Main) -> Enemy:
	var rng := _range()
	var best: Enemy = null
	var bd := INF
	for o in main.grid_hash.query(position, rng + 60.0):
		var e: Enemy = o
		if e.dead:
			continue
		var d := position.distance_to(e.position)
		if d > rng + e.radius or d >= bd:
			continue
		if not main.zone.ray_clear(position, e.position):
			continue
		bd = d
		best = e
	return best


## Нажатие на спуск: выстрел (или первая пуля очереди) и пауза до следующего.
func _pull_trigger(main: Main) -> void:
	_fire(main)
	if dead:
		return
	if gun.burst > 1:
		burst_left = gun.burst - 1
		burst_t = BURST_GAP
		fire_cd += float(gun.burst) / gun.fire_rate
	else:
		fire_cd += 1.0 / gun.fire_rate


func _fire(main: Main) -> void:
	var g := gun
	if randf() >= LevelTree.free_shot_chance():   # узел «Экономный стрелок» работает и на турели
		ammo = maxi(0, ammo - g.ammo_per_shot)
	g.shot_count += 1
	var base := aim.angle()
	var spr := deg_to_rad(g.spread * LevelTree.spread_mult())
	var mpos := position + aim * (radius + 10.0)
	var n := g.pellets
	if g.proj_kind == GunData.K_SHELL:
		# миномёт: мины ложатся вокруг цели, а не летят по полу
		var dist := clampf(aim_dist, 60.0, _range())
		var aim_pt := position + aim * dist
		var dev := dist * tan(clampf(spr * 0.5, 0.0, 1.2))
		for i in n:
			var off := Vector2.from_angle(randf() * TAU) * dev * sqrt(randf())
			_tint(main.projectiles.fire_shell(g, mpos, aim_pt + off))
	else:
		for i in n:
			var a := base
			if n > 1:
				a += lerpf(-spr * 0.5, spr * 0.5, (float(i) + 0.5) / float(n)) + randf_range(-0.08, 0.08) * spr
			else:
				a += randf_range(-spr * 0.5, spr * 0.5)
			_tint(main.projectiles.fire_gun(g, mpos, Vector2.from_angle(a), 0))
	if g.special == "ring" and randf() < GunGen.proc_keep_chance(g):
		for k in 8:
			var dir := Vector2.from_angle(base + TAU * float(k) / 8.0)
			_tint(main.projectiles.fire_gun(g, position + dir * 18.0, dir, 0, 1.0))
	if g.special == "nuke10":
		g.nuke_charge += g.norm_damage() * float(n) / Gun.NUKE_COST
		if g.nuke_charge >= 1.0:
			g.nuke_charge -= 1.0
			var nk: Projectiles.Proj = main.projectiles.fire_nuke(g, mpos, aim, DMG_MULT)
			if nk != null:
				nk.leech = 0.0   # и ядерка турели не лечит героя
	recoil = 4.0
	main.fx.muzzle_flash(mpos, aim, g.proj_color)
	main.sfx.gun_shot(g, mpos)
	if ammo <= 0:
		burst_left = 0
		_destroy(true)


## Стихия навыка (перк «Стихия»): как у пушек — шанс 35% на попадание, кислота/холод/проклятие копятся от каждого.
func _tint(p: Projectiles.Proj) -> void:
	if p == null:
		return
	p.dmg *= DMG_MULT
	p.home = self   # бумеранг возвращается к турели, а не к герою
	p.home_pos = position
	p.leech = 0.0   # вампиризм пушки не лечит героя за пули турели (деления/кассеты копируют это поле уже нулём)
	if element < 0:
		return
	p.element = element
	p.elem_chance = Skills.SKILL_ELEM_CHANCE / maxf(0.08, p.proc)
	p.color = U.el_color(element)


func take_damage(amount: float) -> bool:
	if dead or invuln > 0.0:
		return false
	hp -= amount
	invuln = INVULN
	flash = 0.1
	var main: Main = Game.main
	main.fx.damage_number(position + Vector2(0, -radius), amount, false, -1, true)
	Sfx.at("hit/body", position, -7.0, 1.0, 0.08, 2, 0.1)
	_bash(main)
	if hp <= 0.0:
		_destroy(false)
	return true


## Ответ на попадание: ближайшие враги отлетают от турели и оглушены на секунду (боссы не отбрасываются, но стан получают).
func _bash(main: Main) -> void:
	main.fx.ring(position, BASH_R, _col, 0.25)
	for o in main.grid_hash.query(position, BASH_R + 40.0):
		var e: Enemy = o
		if e.dead or position.distance_to(e.position) > BASH_R + e.radius:
			continue
		var away := e.position - position
		away = away.normalized() if away.length_squared() > 1.0 else Vector2.from_angle(randf() * TAU)
		if e.elite != 3:
			e.knock += away * BASH_KNOCK
		e.stun_time = maxf(e.stun_time, BASH_STUN / e.status_resist)


## Убрать турель без взрыва: её место заняла новая (лимит по зарядам навыка).
func dismantle() -> void:
	_destroy(true)


## spent — расстреляла обойму (тихо), иначе её разбили (взрыв).
func _destroy(spent: bool) -> void:
	if dead:
		return
	dead = true
	var main: Main = Game.main
	main.turrets.erase(self)
	if spent:
		main.fx.ring(position, 30.0, _col, 0.3)
		main.fx.dust(position)
	else:
		main.fx.death_burst(position, _col, 18.0)
		main.fx.explosion(position, 34.0, _col)
		main.sfx.explosion(position, 34.0, false)
	queue_free()


func _draw() -> void:
	if dead or gun == null:
		return
	var body := _col
	if flash > 0.0:
		body = Color(1, 0.4, 0.4)
	draw_circle(Vector2(0, 9), 13.0, Color(0, 0, 0, 0.3))
	# опорная плита: восьмигранник с кольцом цвета Инженера
	var pts := U.ngon(8, radius, PI / 8.0, false)
	draw_colored_polygon(pts, body.darkened(0.6))
	draw_polyline(U.closed(pts), body.lightened(0.1), 2.5)
	draw_circle(Vector2.ZERO, radius * 0.45, body.darkened(0.35))
	var flip := aim.x < 0.0
	GunIcon.draw_gun(self, gun, aim * (8.0 - recoil) + Vector2(0, 1), 0.4, aim.angle(), flip, false)
	if recoil > 2.0:
		draw_circle(aim * (radius + 14.0), 6.0, Color(gun.proj_color, 0.8))
	# здоровье — только когда побита
	if hp < max_hp:
		var bw := 34.0
		var y := -radius - 14.0
		draw_rect(Rect2(-bw * 0.5, y, bw, 4.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-bw * 0.5, y, bw * clampf(hp / max_hp, 0.0, 1.0), 4.0), Color(0.95, 0.25, 0.25))
	# обойма: полоска под турелью
	var by := radius + 7.0
	var f := clampf(float(ammo) / float(max_ammo), 0.0, 1.0)
	var ac := Color(0.35, 0.9, 0.45).lerp(Color(1.0, 0.3, 0.25), 1.0 - f)
	draw_rect(Rect2(-17.0, by, 34.0, 4.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-17.0, by, 34.0 * f, 4.0), ac)
