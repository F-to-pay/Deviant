class_name Player
extends Actor
## Игрок. Вся сила в пушках, а уровни героя (Game.state.hero_level) дают очки дерева навыков (LevelTree) на один забег.
## 4 слота + рюкзак. Плюс герой (Heroes) с активным навыком.

const BASE_HP := 100.0
const SPEED := 265.0
const DODGE_SPEED := 640.0
const DODGE_TIME := 0.32
const DODGE_CD := 4.0
const PERFECT_DODGE_CD := 0.5   # КД, если перекатом реально увернулся от урона
const BACKPACK_SIZE := 12
const LEECH_CAP := 4.0          # вампиризм лечит не больше N HP/сек
const FLASK_MAX := 3            # фляг переносится в следующую зону (в самой зоне — сколько угодно)
const FIRE_SLOW := 0.85         # стрельба и пауза между выстрелами замедляют героя (кроме «лёгких» пушек)
const FLASK_HEAL := 0.2         # фляга лечит 20% максимума здоровья

var guns: Array = [null, null, null, null]
var backpack: Array = []
var reserve: Dictionary = {}    # тип патронов -> запас
var active: int = 0
var last_active: int = 0
var aim: Vector2 = Vector2.RIGHT
var kick := Vector2.ZERO        # отдача выстрела: скорость, которой пушка отбрасывает героя назад (гаснет, Gun.recoil)
const KICK_DECEL := 1800.0
const KICK_MAX := 2200.0
var dodge_t: float = 0.0
var dodge_cd: float = 0.0
var dodge_dir: Vector2 = Vector2.RIGHT
var invuln: float = 0.0
var perfect_dodge: bool = false
var leech_budget: float = LEECH_CAP
var hazard_tick: float = 0.0
var anim: float = 0.0
var hero := Heroes.DEFAULT
var shooting := Shooting.new(self)   # стрельба и перезарядка (entities/shooting.gd)
var skill := HeroSkill.new(self)   # активный навык героя и его перки (entities/hero_skill.gd)
var hurt_this_zone := false     # получал ли урон в этой зоне (задание «без урона»)
var flasks: int = FLASK_MAX     # фляги лечения (выпить — действие flask)
var flask_cd: float = 0.0
var temp_hp: float = 0.0        # временное здоровье (узел «Осколочный щит»): съедается уроном раньше основного
var temp_t: float = 0.0         # через сколько секунд оно пропадёт
var haste_t: float = 0.0        # сколько ещё длится ускорение после фляги (узел «Быстрый глоток»)


## Здоровье без пушек: база плюс узлы дерева навыков (LevelTree, stat max_hp).
func base_max_hp() -> float:
	return BASE_HP + LevelTree.stat("max_hp")


## Сколько фляг переносится дальше: база плюс узлы дерева.
func flask_max() -> int:
	return FLASK_MAX + int(LevelTree.stat("flask_max"))


## Дерево навыков изменилось (покупка узла): пересчитать здоровье — прибавка сразу и лечит на столько же.
func on_tree_changed() -> void:
	var before := max_hp
	max_hp = base_max_hp()
	if max_hp > before:
		hp += max_hp - before
	hp = minf(hp, max_hp)


func reset() -> void:
	guns = [null, null, null, null]
	backpack = []
	reserve = {}
	active = 0
	last_active = 0
	radius = 14.0
	skill.reset()
	flasks = 0 if bool(Game.run.get("no_heal", false)) else FLASK_MAX
	flask_cd = 0.0
	temp_hp = 0.0
	temp_t = 0.0
	haste_t = 0.0
	LevelTree.recompute()
	max_hp = base_max_hp()
	hp = max_hp
	dead = false
	visible = true
	invuln = 1.0
	shooting.reload_t = 0.0
	kick = Vector2.ZERO
	shooting.burst_left = 0
	shooting.fire_cd = 0.0
	dodge_t = 0.0
	burn_time = 0.0
	acid = 0.0
	cryo = 0.0
	frozen_time = 0.0
	set_hero(Game.profile.hero)


## Сменить героя (в стартовом городе): навык готов сразу.
func set_hero(id: String) -> void:
	hero = id if Heroes.LIST.has(id) else Heroes.DEFAULT
	LevelTree.recompute()   # личные узлы дерева — у своего героя
	skill.on_hero_set()
	queue_redraw()


func dodge_max_cd() -> float:
	return DODGE_CD


func gun() -> Gun:
	return guns[active]


func gun_count() -> int:
	var n := 0
	for g in guns:
		if g != null:
			n += 1
	return n


# --- Инвентарь -------------------------------------------------------------------

## Кладёт пушку в пустой слот, иначе в рюкзак. false — некуда.
func add_gun(g: Gun) -> bool:
	g.sync_level(Game.white_level())   # белая пушка с пола/из лавки сразу в силу текущей зоны
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
	shooting.reload_t = 0.0
	shooting.burst_left = 0
	shooting.fire_cd = maxf(shooting.fire_cd, 0.18)
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
	if shooting.reload_t > 0.0:
		Game.main.sfx.reload_cancel()
	shooting.reload_t = 0.0
	shooting.burst_left = 0
	max_hp = base_max_hp()
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
	hurt_this_zone = true
	amount *= 1.0 - armor()
	amount = _absorb(amount)
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


## Временное здоровье (узел «Осколочный щит») принимает урон первым. Возвращает остаток, который пойдёт в основное.
func _absorb(amount: float) -> float:
	if temp_hp <= 0.0:
		return amount
	var taken := minf(temp_hp, amount)
	temp_hp -= taken
	return amount - taken


## Дали временное здоровье: не больше максимума здоровья, таймер обновляется.
func add_temp_hp(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	temp_hp = minf(max_hp, temp_hp + amount)
	temp_t = maxf(temp_t, LevelTree.stat("temp_hp_time"))


func _on_dodged() -> void:
	if perfect_dodge:
		return
	perfect_dodge = true
	dodge_cd = minf(dodge_cd, PERFECT_DODGE_CD + dodge_t)
	Game.main.fx.text(position + Vector2(0, -34), U.t("DODGED!"), Color(0.5, 0.9, 1.0), 16, 0.6)
	Game.main.fx.ring(position, 40.0, Color(0.5, 0.9, 1.0), 0.3)
	Sfx.at("player/perfect", position, -3.0, 1.0, 0.04, 1, 0.2)


## Урон от жижи — без неуязвимости, чтобы не абузить.
func hurt_dot(amount: float, el: int) -> void:
	if dead:
		return
	hurt_this_zone = true
	amount *= 1.0 - armor()
	amount = _absorb(amount)
	hp -= amount
	Game.main.fx.damage_number(position + Vector2(0, -radius), amount, false, el, true)
	if hp <= 0.0:
		_die()


## Вампиризм: урон нормируется к уровню зоны (иначе на 30-й зоне хил был бы
## бесконечным) и ограничен LEECH_CAP HP в секунду.
func leech(dmg_dealt: float, frac: float) -> void:
	if dead or frac <= 0.0 or dmg_dealt <= 0.0:
		return
	var lvl_mult: float = Balance.gun_dmg_mult(Game.state.zone_level)
	var amt := minf(dmg_dealt / lvl_mult * frac, leech_budget)
	if amt <= 0.0:
		return
	leech_budget -= amt
	heal(amt)


func heal(amount: float, show_fx: bool = false) -> void:
	if dead or amount <= 0.0:
		return
	var before := hp
	hp = minf(max_hp, hp + amount)
	if show_fx and hp > before:
		Game.main.fx.heal_fx(position)
		Sfx.ui("pickup/heal", -5.0)
		Game.main.fx.text(position + Vector2(0, -30), "+" + U.fmt(hp - before), Color(0.4, 1.0, 0.5), 16, 0.8)


func on_dot(amount: float, el: int) -> void:
	hurt_dot(amount, el)


# --- Фляги ---------------------------------------------------------------------------

## Выпить флягу: +20% максимума здоровья.
func drink() -> void:
	if dead or flask_cd > 0.0:
		return
	if flasks <= 0:
		shooting.dry(U.t("NO FLASKS"))
		return
	if hp >= max_hp:
		shooting.dry(U.t("Health is full"))
		return
	flasks -= 1
	flask_cd = 0.5
	heal(max_hp * FLASK_HEAL * (1.0 + LevelTree.stat("flask_heal")), true)
	if LevelTree.stat("flask_haste") > 0.0:
		haste_t = LevelTree.stat("flask_haste_time")   # узел «Быстрый глоток»


## Подобрали флягу с земли: узел «Второе дыхание» снимает долю перезарядки навыка.
func on_flask_pickup() -> void:
	var f := LevelTree.stat("flask_skill_refund")
	if f > 0.0 and skill.charges < skill.max_charges():
		skill.cd -= f * skill.max_cd()


## +n фляг. В зоне их может быть сколько угодно — лишние сгорают при переходе (trim_flasks).
func add_flask(n: int = 1) -> void:
	flasks += maxi(0, n)


## Переход в следующую зону или город: с собой — не больше FLASK_MAX.
func trim_flasks() -> void:
	flasks = mini(flasks, flask_max())


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
	main.rewards.on_player_died()


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
	shooting.tick(delta)
	if flask_cd > 0.0:
		flask_cd -= delta
	if haste_t > 0.0:
		haste_t -= delta
	if temp_t > 0.0:
		temp_t -= delta
		if temp_t <= 0.0:
			temp_hp = 0.0
	skill.tick(delta)

	var mp := Game.controls.aim_world(position)
	if mp.distance_squared_to(position) > 16.0:
		aim = (mp - position).normalized()

	var input := Game.controls.move_vector()
	var g := gun()
	var spd := SPEED
	if g != null:
		spd *= g.move_mult
		if not g.light and (shooting.fire_cd > 0.0 or shooting.burst_left > 0) and shooting.reload_t <= 0.0:
			spd *= FIRE_SLOW
	if chill > 0.0:
		spd *= 0.65
	if haste_t > 0.0:
		spd *= 1.0 + LevelTree.stat("flask_haste")
	if skill.slash_t > 0.0:
		spd *= 1.0 - float(Heroes.get_hero(hero).get("slow", 0.0))
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
			dodge_cd = dodge_max_cd()
			perfect_dodge = false
			invuln = maxf(invuln, DODGE_TIME)
			main.fx.dust(position)
			Sfx.at("player/dodge", position, -7.0, 1.0, 0.08, 1, 0.1)
	position = main.zone.move_circle(position, vel * delta, radius)
	if kick.length_squared() > 1.0:
		position = main.zone.move_circle(position, kick * delta, radius)
		kick = kick.move_toward(Vector2.ZERO, KICK_DECEL * delta)

	# Опасная жижа
	if main.zone.is_hazard_at(position) and dodge_t <= 0.0:
		hazard_tick -= delta
		if hazard_tick <= 0.0:
			hazard_tick = 0.5
			var el: int = main.zone.biome.get("hazard_el", -1)
			var dmgm: float = Balance.enemy_dmg_mult(Game.state.zone_level, float(Game.run["dmg"]))
			hurt_dot(4.0 * dmgm, el)
			if el >= 0:
				apply_element(el, 1.0)
	else:
		hazard_tick = 0.0

	# Пассивного регена нет. Только хилки и (редкий) вампиризм.
	leech_budget = minf(LEECH_CAP, leech_budget + LEECH_CAP * delta)

	var skill_cast: Variant = Game.controls.take_skill()   # навык, прицеленный отдельным стиком на сенсоре
	if not main.transitioning:
		if skill_cast != null and skill.charges > 0 and skill.gap <= 0.0 and not skill.blessed:
			skill.use(skill_cast)
		elif Input.is_action_pressed("skill") and skill.charges > 0 and skill.gap <= 0.0 and not skill.blessed:
			skill.use()
		shooting.update(delta)
	queue_redraw()


# --- Навык героя -------------------------------------------------------------------


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
	elif event.is_action_pressed("flask"):
		if not Game.main.transitioning:
			drink()
	elif event.is_action_pressed("interact"):
		Game.main.interact.use(false)
	elif event.is_action_pressed("swap"):
		Game.main.interact.use(true)
	elif event.is_action_pressed("scrap"):
		Game.main.loot.scrap_near()


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
	var t := g.base_ammo_type()   # у безлимитной пушки — патроны её основы (в магазине энергии запаса нет)
	var n := g.ammo + ceili(float(GunData.base_mag(t)) * (0.75 + 0.25 * float(g.rarity)))
	g.ammo = 0
	Sfx.ui("ui/scrap", -4.0)
	var got := add_ammo(t, n)
	Game.say(U.t("Scrapped: +%d rounds (%s)") % [got, GunData.ammo_label(t)] + ("" if got == n else U.t(" — reserve full")), GunData.ammo_color(t))
	return got


# --- Отрисовка ----------------------------------------------------------------


func _draw() -> void:
	if dead:
		return
	var blink := invuln > 0.0 and dodge_t <= 0.0 and fmod(anim * 20.0, 1.0) < 0.5
	var body := Heroes.color(hero)
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
	skill.draw_effects(self)
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
		if shooting.muzzle > 0.0:
			draw_circle(aim * (radius + 18.0), 7.0, Color(g.proj_color, 0.8))
	shooting.draw_reload(self, bob)
