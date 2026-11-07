class_name Player
extends Actor
## Игрок. Уровней нет — вся сила в пушках. 4 слота + рюкзак.

const BASE_HP := 100.0
const SPEED := 265.0
const DODGE_SPEED := 640.0
const DODGE_TIME := 0.32
const DODGE_CD := 4.0
const PERFECT_DODGE_CD := 0.5   # КД, если перекатом реально увернулся от урона
const BACKPACK_SIZE := 12
const LEECH_CAP := 4.0          # вампиризм лечит не больше N HP/сек

var guns: Array = [null, null, null, null]
var backpack: Array = []
var reserve: Dictionary = {}    # тип патронов -> запас
var _dry_cd: float = 0.0
var active: int = 0
var last_active: int = 0
var aim: Vector2 = Vector2.RIGHT
var vel: Vector2 = Vector2.ZERO
var fire_cd: float = 0.0
var reload_t: float = 0.0
var burst_left: int = 0
var burst_t: float = 0.0
var bloom: float = 0.0
var dodge_t: float = 0.0
var dodge_cd: float = 0.0
var dodge_dir: Vector2 = Vector2.RIGHT
var invuln: float = 0.0
var perfect_dodge: bool = false
var leech_budget: float = LEECH_CAP
var chill: float = 0.0
var hazard_tick: float = 0.0
var anim: float = 0.0
var muzzle: float = 0.0


func reset() -> void:
	guns = [null, null, null, null]
	backpack = []
	reserve = {}
	active = 0
	last_active = 0
	radius = 14.0
	max_hp = BASE_HP
	hp = max_hp
	dead = false
	visible = true
	invuln = 1.0
	reload_t = 0.0
	burst_left = 0
	fire_cd = 0.0
	dodge_t = 0.0
	burn_time = 0.0
	acid = 0.0
	cryo = 0.0
	frozen_time = 0.0


func gun() -> Gun:
	return guns[active]


func gun_count() -> int:
	var n := 0
	for g in guns:
		if g != null:
			n += 1
	return n


func is_reloading() -> bool:
	return reload_t > 0.0


func reload_progress() -> float:
	var g := gun()
	if g == null or reload_t <= 0.0:
		return 0.0
	return 1.0 - reload_t / g.reload_time


# --- Инвентарь -------------------------------------------------------------------

## Кладёт пушку в пустой слот, иначе в рюкзак. false — некуда.
func add_gun(g: Gun) -> bool:
	for i in 4:
		if guns[i] == null:
			guns[i] = g
			if gun() == null:
				active = i
			on_gun_changed()
			return true
	if backpack.size() < BACKPACK_SIZE:
		backpack.append(g)
		return true
	return false


func switch_to(i: int) -> void:
	if i < 0 or i > 3 or guns[i] == null or i == active:
		return
	last_active = active
	active = i
	reload_t = 0.0
	burst_left = 0
	fire_cd = maxf(fire_cd, 0.18)
	on_gun_changed()
	Sfx.ui("ui/switch", -9.0)


func cycle(dir: int) -> void:
	for k in range(1, 5):
		var i := posmod(active + dir * k, 4)
		if guns[i] != null:
			switch_to(i)
			return


## После любых перестановок: активный слот не пустой, бонус к HP пересчитан.
func on_gun_changed() -> void:
	if guns[active] == null:
		for i in 4:
			if guns[i] != null:
				active = i
				break
	if reload_t > 0.0:
		Game.main.sfx.reload_cancel()
	reload_t = 0.0
	burst_left = 0
	max_hp = BASE_HP
	hp = minf(hp, max_hp)


func armor() -> float:
	var g := gun()
	return g.armor if g != null else 0.0


# --- Урон и лечение --------------------------------------------------------------

## true — урон прошёл. Во время переката урон не проходит, а КД переката
## сбрасывается до PERFECT_DODGE_CD — награда за реальное уклонение.
func take_damage(amount: float) -> bool:
	if dead:
		return false
	if dodge_t > 0.0:
		_on_dodged()
		return false
	if invuln > 0.0:
		return false
	amount *= 1.0 - armor()
	hp -= amount
	invuln = 0.4
	flash = 0.12
	var main: Main = Game.main
	main.fx.shake(6.0)
	main.fx.damage_number(position + Vector2(0, -radius), amount, false, -1, true)
	Sfx.at("player/hurt", position, -5.0, 1.0, 0.05, 1, 0.35)
	Sfx.at("hit/body", position, -7.0, 1.0, 0.08, 2, 0.1)
	if hp <= 0.0:
		_die()
	return true


func _on_dodged() -> void:
	if perfect_dodge:
		return
	perfect_dodge = true
	dodge_cd = minf(dodge_cd, PERFECT_DODGE_CD + dodge_t)
	Game.main.fx.text(position + Vector2(0, -34), U.t("УКЛОН!"), Color(0.5, 0.9, 1.0), 16, 0.6)
	Game.main.fx.ring(position, 40.0, Color(0.5, 0.9, 1.0), 0.3)
	Sfx.at("player/perfect", position, -3.0, 1.0, 0.04, 1, 0.2)


## Урон от жижи — без неуязвимости, чтобы не абузить.
func hurt_dot(amount: float, el: int) -> void:
	if dead:
		return
	amount *= 1.0 - armor()
	hp -= amount
	Game.main.fx.damage_number(position + Vector2(0, -radius), amount, false, el, true)
	if hp <= 0.0:
		_die()


## Вампиризм: урон нормируется к уровню зоны (иначе на 30-й зоне хил был бы
## бесконечным) и ограничен LEECH_CAP HP в секунду.
func leech(dmg_dealt: float, frac: float) -> void:
	if dead or frac <= 0.0 or dmg_dealt <= 0.0:
		return
	var lvl_mult: float = Game.gun_dmg_mult(Game.zone_level)
	var amt := minf(dmg_dealt / lvl_mult * frac, leech_budget)
	if amt <= 0.0:
		return
	leech_budget -= amt
	heal(amt)


func heal(amount: float, show: bool = false) -> void:
	if dead or amount <= 0.0:
		return
	var before := hp
	hp = minf(max_hp, hp + amount)
	if show and hp > before:
		Game.main.fx.heal_fx(position)
		Sfx.ui("pickup/heal", -5.0)
		Game.main.fx.text(position + Vector2(0, -30), "+" + U.fmt(hp - before), Color(0.4, 1.0, 0.5), 16, 0.8)


func on_dot(amount: float, el: int) -> void:
	hurt_dot(amount, el)


func _die() -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	var main: Main = Game.main
	main.fx.death_burst(position, Color(0.4, 0.9, 1.0), 30.0)
	main.fx.explosion(position, 60.0, Color(0.4, 0.9, 1.0))
	visible = false
	Sfx.ui("player/death", -2.0)
	main.on_player_died()


# --- Обновление ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		return
	var main: Main = Game.main
	anim += delta
	tick_status(delta)
	if dead:
		return
	if invuln > 0.0:
		invuln -= delta
	if dodge_cd > 0.0:
		dodge_cd -= delta
	if chill > 0.0:
		chill -= delta
	if muzzle > 0.0:
		muzzle -= delta

	var mp := get_global_mouse_position()
	if mp.distance_squared_to(position) > 16.0:
		aim = (mp - position).normalized()

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var g := gun()
	var spd := SPEED
	if g != null:
		spd *= g.move_mult
	if chill > 0.0:
		spd *= 0.65
	if main.transitioning:
		input = Vector2.ZERO
	if dodge_t > 0.0:
		dodge_t -= delta
		vel = dodge_dir * DODGE_SPEED
	else:
		vel = input * spd
		if Input.is_action_just_pressed("dodge") and dodge_cd <= 0.0 and not main.transitioning:
			dodge_dir = input.normalized() if input.length() > 0.1 else aim
			dodge_t = DODGE_TIME
			dodge_cd = DODGE_CD
			perfect_dodge = false
			invuln = maxf(invuln, DODGE_TIME)
			main.fx.dust(position)
			Sfx.at("player/dodge", position, -7.0, 1.0, 0.08, 1, 0.1)
	position = main.zone.move_circle(position, vel * delta, radius)

	# Опасная жижа
	if main.zone.is_hazard_at(position) and dodge_t <= 0.0:
		hazard_tick -= delta
		if hazard_tick <= 0.0:
			hazard_tick = 0.5
			var el: int = main.zone.biome.get("hazard_el", -1)
			var dmgm: float = Game.enemy_dmg_mult(Game.zone_level)
			hurt_dot(4.0 * dmgm, el)
			if el >= 0:
				apply_element(el, 1.0)
	else:
		hazard_tick = 0.0

	# Пассивного регена нет. Только хилки и (редкий) вампиризм.
	leech_budget = minf(LEECH_CAP, leech_budget + LEECH_CAP * delta)

	if not main.transitioning:
		_update_gun(delta)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	for i in 4:
		if event.is_action_pressed("slot_%d" % (i + 1)):
			switch_to(i)
			return
	if event.is_action_pressed("next_weapon"):
		cycle(1)
	elif event.is_action_pressed("prev_weapon"):
		cycle(-1)
	elif event.is_action_pressed("last_weapon"):
		switch_to(last_active)
	elif event.is_action_pressed("interact"):
		Game.main.player_interact(false)
	elif event.is_action_pressed("swap"):
		Game.main.player_interact(true)
	elif event.is_action_pressed("scrap"):
		Game.main.player_scrap_near()


# --- Патроны ---------------------------------------------------------------------

func reserve_of(t: String) -> int:
	return int(reserve.get(t, 0))


## Добавляет патроны в запас (до лимита). Возвращает, сколько реально влезло.
func add_ammo(t: String, n: int) -> int:
	var cur := reserve_of(t)
	var add := clampi(GunData.ammo_cap(t) - cur, 0, n)
	reserve[t] = cur + add
	return add


func reserve_full(t: String) -> bool:
	return reserve_of(t) >= GunData.ammo_cap(t)


## Разбор пушки: патроны из магазина + сколько-то за саму пушку (больше за редкость).
func scrap(g: Gun) -> int:
	var t := g.ammo_type()
	var n := g.ammo + ceili(float(GunData.base_mag(t)) * (0.75 + 0.25 * float(g.rarity)))
	g.ammo = 0
	Sfx.ui("ui/scrap", -4.0)
	var got := add_ammo(t, n)
	Game.say(U.t("Разобрано: +%d патр. (%s)") % [got, g.ammo_name()] + ("" if got == n else U.t(" — запас полон")), GunData.AMMO_COL[t])
	return got


func _dry(msg: String) -> void:
	if _dry_cd > 0.0:
		return
	_dry_cd = 1.2
	Game.main.sfx.empty_click()
	Game.main.fx.text(position + Vector2(0, -34), msg, Color(1.0, 0.5, 0.4), 15, 0.8)


func start_reload(manual: bool = false) -> void:
	var g := gun()
	if g == null or reload_t > 0.0 or g.ammo >= g.mag_size:
		return
	if reserve_of(g.ammo_type()) <= 0 and not g.free_ammo:
		if manual or g.ammo <= 0:
			_dry(U.t("НЕТ ПАТРОНОВ"))
		return
	reload_t = g.reload_time
	burst_left = 0
	Game.main.sfx.reload_start(g)


func _update_gun(delta: float) -> void:
	var g := gun()
	bloom = maxf(0.0, bloom - delta * 25.0)
	if fire_cd > 0.0:
		fire_cd -= delta
	if g == null:
		return
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			reload_t = 0.0
			if g.free_ammo:
				g.ammo = g.mag_size
			else:
				var t := g.ammo_type()
				var take := mini(g.mag_size - g.ammo, reserve_of(t))
				g.ammo += take
				reserve[t] = reserve_of(t) - take
			Game.main.sfx.reload_done(g)
		return
	if burst_left > 0:
		burst_t -= delta
		if burst_t <= 0.0:
			if g.ammo >= 1:
				_fire(g)
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
	if not Input.is_action_pressed("shoot"):
		if g.ammo <= 0 and (g.free_ammo or reserve_of(g.ammo_type()) > 0):
			start_reload()
		return
	var guard := 0
	while fire_cd <= 0.0 and guard < 4:
		if g.ammo <= 0:
			start_reload()
			return
		_fire(g)
		guard += 1
		if g.burst > 1:
			burst_left = g.burst - 1
			burst_t = 0.065
			fire_cd += float(g.burst) / g.fire_rate
			return
		fire_cd += 1.0 / g.fire_rate


## Миномёт: точка падения = курсор (не дальше дальности), разброс сдвигает её
## пропорционально дистанции. Несколько мин (дробь) ложатся пятном.
func _fire_shells(g: Gun, mpos: Vector2, spr: float, n: int) -> void:
	var main: Main = Game.main
	var to := get_global_mouse_position() - position
	var dist := clampf(to.length(), 60.0, g.eff_range())
	var aim_pt := position + aim * dist
	var dev := dist * tan(clampf(spr * 0.5, 0.0, 1.2))
	for i in n:
		var off := Vector2.from_angle(randf() * TAU) * dev * sqrt(randf())
		main.projectiles.fire_shell(g, mpos, aim_pt + off)


func _fire(g: Gun) -> void:
	var main: Main = Game.main
	g.ammo = maxi(0, g.ammo - g.ammo_per_shot)
	g.shot_count += 1
	var base := aim.angle()
	var spr := deg_to_rad(g.spread + bloom)
	var mpos := position + aim * (radius + 16.0)
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
			main.projectiles.fire_gun(g, mpos, Vector2.from_angle(a), 0)
	if g.special == "ring" and randf() < GunGen.proc_keep_chance(g):
		for k in 8:
			var dir := Vector2.from_angle(base + TAU * float(k) / 8.0)
			main.projectiles.fire_gun(g, position + dir * 18.0, dir, 0, 0.4)
	if g.special == "nuke10":
		# заряд копится от «веса» выстрела, а не от их количества
		g.nuke_charge += g.norm_damage() * float(n) / Gun.NUKE_COST
		if g.nuke_charge >= 1.0:
			g.nuke_charge -= 1.0
			main.projectiles.fire_nuke(g, mpos, aim)
			Game.say(U.t("ЯДЕРКА!"), Color(1.0, 0.85, 0.3))
	bloom = minf(bloom + g.spread * 0.12 + 0.4, 18.0)
	muzzle = 0.06
	main.fx.muzzle_flash(mpos, aim, g.proj_color)
	main.sfx.gun_shot(g, mpos)
	main.fx.shake(minf(g.shake, 8.0))


# --- Отрисовка ----------------------------------------------------------------

func _draw() -> void:
	if dead:
		return
	var blink := invuln > 0.0 and dodge_t <= 0.0 and fmod(anim * 20.0, 1.0) < 0.5
	var body := Color(0.35, 0.85, 1.0)
	if flash > 0.0:
		body = Color(1, 0.4, 0.4)
	if blink:
		body.a = 0.45
	draw_circle(Vector2(0, 9), 13.0, Color(0, 0, 0, 0.3))
	if dodge_t > 0.0:
		for i in 3:
			draw_circle(-dodge_dir * float(i + 1) * 10.0, radius * (0.9 - 0.2 * float(i)), Color(0.35, 0.85, 1.0, 0.25 - 0.07 * float(i)))
	if chill > 0.0:
		draw_circle(Vector2.ZERO, radius + 5.0, Color(0.7, 0.95, 1.0, 0.25))
	var bob := sin(anim * 14.0) * 1.5 if vel.length() > 10.0 else 0.0
	draw_circle(Vector2(0, bob), radius, body.darkened(0.2))
	draw_arc(Vector2(0, bob), radius, 0.0, TAU, 24, body.lightened(0.4), 2.5)
	# «Визор» в сторону прицела
	draw_arc(Vector2(0, bob), radius * 0.6, aim.angle() - 0.7, aim.angle() + 0.7, 10, Color(1, 1, 1, 0.9), 4.0)
	draw_statuses(anim)
	var g := gun()
	if g != null:
		var flip := aim.x < 0.0
		var hand := aim * 12.0 + Vector2(0, bob + 2.0)
		GunIcon.draw_gun(self, g, hand, 0.38, aim.angle(), flip, false)
		if muzzle > 0.0:
			draw_circle(aim * (radius + 18.0), 7.0, Color(g.proj_color, 0.8))
	if reload_t > 0.0:
		draw_arc(Vector2(0, bob), radius + 8.0, -PI * 0.5, -PI * 0.5 + TAU * reload_progress(), 24, Color(1, 1, 1, 0.8), 3.0)
