class_name Player
extends Actor
## Игрок. Уровней нет — вся сила в пушках. 4 слота + рюкзак. Плюс герой (Heroes) с активным навыком.

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
var hero := Heroes.DEFAULT
var skill_cd: float = 0.0       # перезарядка следующего заряда навыка
var skill_charges: int = 1      # готовых зарядов навыка («Дополнительная рука» даёт больше)
var skill_gap: float = 0.0      # пауза между применениями, чтобы зажатая кнопка не тратила все заряды разом
var skill_element: int = -1     # стихия навыка (перк «Стихия»), -1 — нет
var trophy_bonus: float = 0.0   # «Трофеи»: прибавка к урону навыка за убийства навыком
var parry_cd: float = 0.0       # «Парирование»: до готовности
var _ready_pending := false     # «Готовность»: этот навык ещё не снимал КД рывка
var blessed := false            # Шериф: следующий выстрел усилен (навык)
var slash_t: float = 0.0        # Ассасин: идёт удар (замедление, дуга на экране)
var slash_dir := Vector2.RIGHT
var run_perks: Dictionary = {}  # перки навыка (Мистик) на этот забег: id -> сколько раз взят (Heroes.PERKS)
var reload_total: float = 1.0   # полная длительность текущей перезарядки (с перками)
var hurt_this_zone := false     # получал ли урон в этой зоне (задание «без урона»)
var flasks: int = FLASK_MAX     # фляги лечения (выпить — действие flask)
var flask_cd: float = 0.0


func reset() -> void:
	guns = [null, null, null, null]
	backpack = []
	reserve = {}
	active = 0
	last_active = 0
	radius = 14.0
	run_perks = {}
	flasks = 0 if bool(Game.run.get("no_heal", false)) else FLASK_MAX
	flask_cd = 0.0
	skill_element = -1
	trophy_bonus = 0.0
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
	set_hero(Game.hero)


## Сменить героя (в стартовом городе): навык готов сразу.
func set_hero(id: String) -> void:
	hero = id if Heroes.LIST.has(id) else Heroes.DEFAULT
	skill_cd = 0.0
	skill_charges = max_charges()
	parry_cd = 0.0
	blessed = false
	slash_t = 0.0
	queue_redraw()


func skill_max_cd() -> float:
	return float(Heroes.get_hero(hero)["cd"]) + float(perk("heavy"))   # «Тяжёлый снаряд»: +1 с за взятие


func dodge_max_cd() -> float:
	return DODGE_CD


func max_charges() -> int:
	return 1 + perk("hand")


## Сколько раз взят перк навыка (0 — нет; у чужого героя перк не работает).
func perk(id: String) -> int:
	if not Heroes.perk_fits(id, hero):
		return 0
	return int(run_perks.get(id, 0))


## Множитель урона навыка от перков: разделение, тяжёлый, яд, точный, трофеи, вандализм.
func skill_dmg_mult() -> float:
	var k := (1.0 + 0.2 * perk("split")) * (1.0 + 0.2 * perk("heavy")) * (1.0 + 0.3 * perk("poison")) \
		* (1.0 + 0.1 * perk("precise")) * (1.0 + trophy_bonus)
	if perk("vandal") > 0:
		k *= 0.5
	return k


## Взять перк навыка у Мистика. element — для перка «Стихия».
func add_run_perk(id: String, element: int = -1) -> void:
	run_perks[id] = int(run_perks.get(id, 0)) + 1
	if id == "element":
		skill_element = element
	if id == "hand":
		skill_charges += 1


## Навык нанёс урон: «Готовность» — минус секунда КД рывка (один раз за применение).
func on_skill_damage() -> void:
	if _ready_pending and perk("ready") > 0:
		_ready_pending = false
		dodge_cd = maxf(0.0, dodge_cd - 1.0)


## Убийство навыком: «Трофеи» — монета и прибавка к урону навыка.
func on_skill_kill(e: Node2D) -> void:
	var tr := perk("trophies")
	if tr <= 0:
		return
	trophy_bonus += 0.002 + 0.0005 * float(tr - 1)
	Game.add_coins(1)
	Quests.progress("coins", 1)
	Game.main.fx.text(e.position + Vector2(0, -30), "+1", Color(1.0, 0.85, 0.3), 14, 0.7)


func run_perk_count() -> int:
	var n := 0
	for id in run_perks:
		n += int(run_perks[id])
	return n


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
	return 1.0 - reload_t / maxf(0.01, reload_total)


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
	hurt_this_zone = true
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
	Game.main.fx.text(position + Vector2(0, -34), U.t("DODGED!"), Color(0.5, 0.9, 1.0), 16, 0.6)
	Game.main.fx.ring(position, 40.0, Color(0.5, 0.9, 1.0), 0.3)
	Sfx.at("player/perfect", position, -3.0, 1.0, 0.04, 1, 0.2)


## Урон от жижи — без неуязвимости, чтобы не абузить.
func hurt_dot(amount: float, el: int) -> void:
	if dead:
		return
	hurt_this_zone = true
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
		_dry(U.t("NO FLASKS"))
		return
	if hp >= max_hp:
		_dry(U.t("Health is full"))
		return
	flasks -= 1
	flask_cd = 0.5
	heal(max_hp * FLASK_HEAL, true)


## +n фляг. В зоне их может быть сколько угодно — лишние сгорают при переходе (trim_flasks).
func add_flask(n: int = 1) -> void:
	flasks += maxi(0, n)


## Переход в следующую зону или город: с собой — не больше FLASK_MAX.
func trim_flasks() -> void:
	flasks = mini(flasks, FLASK_MAX)


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
	if flask_cd > 0.0:
		flask_cd -= delta
	if skill_charges < max_charges():
		skill_cd -= delta
		if skill_cd <= 0.0:
			skill_charges += 1
			skill_cd = skill_max_cd() if skill_charges < max_charges() else 0.0
	if skill_gap > 0.0:
		skill_gap -= delta
	if parry_cd > 0.0:
		parry_cd -= delta
	if slash_t > 0.0:
		slash_t -= delta

	var mp := Controls.aim_world(position)
	if mp.distance_squared_to(position) > 16.0:
		aim = (mp - position).normalized()

	var input := Controls.move_vector()
	var g := gun()
	var spd := SPEED
	if g != null:
		spd *= g.move_mult
		if not g.light and (fire_cd > 0.0 or burst_left > 0) and reload_t <= 0.0:
			spd *= FIRE_SLOW
	if chill > 0.0:
		spd *= 0.65
	if slash_t > 0.0:
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

	var skill_cast: Variant = Controls.take_skill()   # навык, прицеленный отдельным стиком на сенсоре
	if not main.transitioning:
		if skill_cast != null and skill_charges > 0 and skill_gap <= 0.0 and not blessed:
			_use_skill(skill_cast)
		elif Input.is_action_pressed("skill") and skill_charges > 0 and skill_gap <= 0.0 and not blessed:
			_use_skill()
		_update_gun(delta)
	queue_redraw()


# --- Навык героя -------------------------------------------------------------------

## cast — отдельный стик навыка на сенсоре: {"dir", "len"}; null или dir = ZERO — целимся, как обычно.
func _use_skill(cast: Variant = null) -> void:
	var main: Main = Game.main
	var h := Heroes.get_hero(hero)
	var col: Color = h["color"] if skill_element < 0 else U.el_color(skill_element)
	if skill_charges >= max_charges():
		skill_cd = skill_max_cd()   # заряд пошёл в дело — начинаем копить следующий
	skill_charges -= 1
	skill_gap = 0.3
	_ready_pending = true
	var sdmg := float(h["dmg"]) * skill_dmg_mult()
	match str(h["skill"]):
		"grenade":
			# в точку прицела, но не дальше range. «Разделение» — 3×N гранат, урон поровну;
			# ложатся пятном вокруг точки прицела, как мины миномёта (чем дальше бросок, тем шире пятно)
			var cdir := aim
			var dist: float
			if cast is Dictionary and (cast["dir"] as Vector2) != Vector2.ZERO:
				# своим стиком: направление — куда потянули, дальность — насколько сильно
				cdir = (cast["dir"] as Vector2).normalized()
				dist = lerpf(60.0, float(h["range"]), clampf(float(cast["len"]), 0.0, 1.0))
			else:
				var to := Controls.aim_world(position) - position
				dist = clampf(to.length(), 40.0, float(h["range"]))
			var target := position + cdir * dist
			var n := 3 * perk("split") if perk("split") > 0 else 1
			var dev := (20.0 + dist * 0.14) * sqrt(float(n) / 3.0)
			for i in n:
				var off := Vector2.ZERO
				if n > 1:
					off = Vector2.from_angle(randf() * TAU) * dev * sqrt(randf())
				main.projectiles.throw_grenade(position + cdir * (radius + 6.0), target + off, sdmg / float(n), float(h["r"]), col)
			Sfx.at("player/dodge", position, -6.0, 1.4, 0.06, 1, 0.1)
		"bless":
			blessed = true
			main.fx.ring(position, 34.0, Color(1.0, 0.8, 0.3), 0.4)
			Sfx.at("player/perfect", position, -6.0, 0.7, 0.04, 1, 0.1)
		"slash":
			slash_t = float(h["time"])
			var sdir := aim
			if cast is Dictionary and (cast["dir"] as Vector2) != Vector2.ZERO:
				sdir = (cast["dir"] as Vector2).normalized()   # своим стиком на сенсоре
			slash_dir = sdir
			var r := float(h["r"])
			var half := deg_to_rad(float(h["arc"])) * 0.5
			var hits := 0
			for o in main.grid_hash.query(position, r + 60.0):
				var e: Enemy = o
				if e.dead:
					continue
				var to_e := e.position - position
				if to_e.length() > r + e.radius:
					continue
				# совсем вплотную — бьём в любом случае, иначе только в дуге
				if to_e.length() > e.radius + radius and absf(sdir.angle_to(to_e)) > half:
					continue
				Skills.hit(e, sdmg, to_e.normalized() * 160.0)
				hits += 1
			# «Парирование»: раз в 4 с удар разворачивает вражеские снаряды
			var pr := perk("parry")
			if pr > 0 and parry_cd <= 0.0:
				var refl := main.projectiles.reflect(position, sdir, r + 20.0, half, 1.0 + 0.3 * float(pr - 1))
				if refl > 0:
					parry_cd = 4.0
					main.fx.ring(position, r, Color(0.85, 0.7, 1.0), 0.3)
					Sfx.at("player/perfect", position, -5.0, 1.3, 0.04, 1, 0.1)
			Sfx.at("player/dodge", position, -5.0, 1.6, 0.08, 2, 0.05)
			if hits > 0:
				Sfx.at("hit/body", position, -6.0, 1.2, 0.08, 2, 0.05)
				main.fx.shake(2.0)


## Благословлённый выстрел Шерифа: снаряды помечены как навык (Skills), к урону — бонус навыка
## (делится между дробинами/минами). «Разделение» — 3×N копий каждого снаряда веером, урон поровну;
## «Точный выстрел» — самонаведение и дальность.
func _bless_proj(p: Projectiles.Proj, n: int, copies: int) -> void:
	p.skill = true
	p.dmg = (p.dmg + float(Heroes.get_hero(hero)["dmg"]) * skill_dmg_mult() / float(maxi(1, n))) / float(copies)
	if skill_element >= 0:
		p.color = U.el_color(skill_element)
	var pc := perk("precise")
	if pc > 0:
		p.homing = maxf(p.homing, 5.0)
		p.eff_range *= 1.0 + 0.2 * float(pc)


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
	Game.say(U.t("Scrapped: +%d rounds (%s)") % [got, g.ammo_name()] + ("" if got == n else U.t(" — reserve full")), GunData.ammo_color(t))
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
			_dry(U.t("NO AMMO"))
		return
	reload_t = g.reload_time
	reload_total = reload_t
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
	# «Стрельба по отпусканию» (сенсор): один выстрел, когда отпустили правый стик
	if Controls.take_shot(fire_cd <= 0.0):
		if g.ammo <= 0:
			start_reload()
			return
		fire_cd = maxf(fire_cd, 0.0)
		_pull_trigger(g)
		return
	if not Controls.firing():
		if g.ammo <= 0 and (g.free_ammo or reserve_of(g.ammo_type()) > 0):
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
	_fire(g)
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
	var to := Controls.aim_world(position) - position
	var dist := clampf(to.length(), 60.0, g.eff_range())
	var aim_pt := position + aim * dist
	var dev := dist * tan(clampf(spr * 0.5, 0.0, 1.2))
	for i in n:
		var off := Vector2.from_angle(randf() * TAU) * dev * sqrt(randf())
		var p := main.projectiles.fire_shell(g, mpos, aim_pt + off)
		if p != null and blessed:
			_bless_proj(p, n, 1)


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
			var copies := 3 * perk("split") if blessed and perk("split") > 0 else 1
			for c in copies:
				var ca := a + (float(c) - float(copies - 1) * 0.5) * 0.07
				var p := main.projectiles.fire_gun(g, mpos, Vector2.from_angle(ca), 0)
				if p != null and blessed:
					_bless_proj(p, n, copies)
	if blessed:
		blessed = false
		_ready_pending = true
		main.fx.ring(mpos, 24.0, Color(1.0, 0.8, 0.3), 0.3)
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
			Game.say(U.t("NUKE!"), Color(1.0, 0.85, 0.3))
	bloom = minf(bloom + g.spread * 0.12 + 0.4, 18.0)
	muzzle = 0.06
	main.fx.muzzle_flash(mpos, aim, g.proj_color)
	main.sfx.gun_shot(g, mpos)
	main.fx.shake(minf(g.shake, 8.0))


# --- Отрисовка ----------------------------------------------------------------

## Превью броска, пока тянешь стик навыка: линия, круг взрыва в точке падения и кольцо максимальной дальности.
func _draw_skill_preview() -> void:
	var hd := Heroes.get_hero(hero)
	if not bool(hd.get("aimed", false)):
		return
	var col: Color = hd["color"] if skill_element < 0 else U.el_color(skill_element)
	var sd := Controls.skill_aim
	var dir := sd.normalized()
	var ready := skill_charges > 0
	var a := 1.0 if ready else 0.4
	if str(hd["skill"]) == "slash":
		# сектор удара: куда и насколько широко ударим
		var sr := float(hd["r"])
		var half := deg_to_rad(float(hd["arc"])) * 0.5
		var pts := PackedVector2Array([Vector2.ZERO])
		for k in 13:
			pts.append(Vector2.from_angle(dir.angle() - half + half * 2.0 * float(k) / 12.0) * sr)
		draw_colored_polygon(pts, Color(col, 0.16 * a))
		draw_arc(Vector2.ZERO, sr, dir.angle() - half, dir.angle() + half, 20, Color(col, 0.85 * a), 2.0)
		draw_line(Vector2.ZERO, Vector2.from_angle(dir.angle() - half) * sr, Color(col, 0.5 * a), 2.0)
		draw_line(Vector2.ZERO, Vector2.from_angle(dir.angle() + half) * sr, Color(col, 0.5 * a), 2.0)
		return
	var d := lerpf(60.0, float(hd["range"]), clampf(sd.length(), 0.0, 1.0))
	draw_arc(Vector2.ZERO, float(hd["range"]), 0.0, TAU, 48, Color(col, 0.12 * a), 2.0)
	draw_line(dir * (radius + 6.0), dir * d, Color(col, 0.4 * a), 2.0)
	draw_circle(dir * d, float(hd["r"]), Color(col, 0.14 * a))
	draw_arc(dir * d, float(hd["r"]), 0.0, TAU, 32, Color(col, 0.85 * a), 2.0)


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
	if blessed:
		var pulse := 1.0 + sin(anim * 8.0) * 0.15
		draw_circle(Vector2.ZERO, (radius + 7.0) * pulse, Color(1.0, 0.8, 0.3, 0.22))
		draw_arc(Vector2.ZERO, (radius + 7.0) * pulse, 0.0, TAU, 24, Color(1.0, 0.85, 0.4, 0.8), 2.0)
	if Controls.skill_aim != Vector2.ZERO:
		_draw_skill_preview()
	if slash_t > 0.0:
		# дуга удара: метёт от одного края к другому
		var hs := Heroes.get_hero(hero)
		var half := deg_to_rad(float(hs["arc"])) * 0.5
		var k := 1.0 - clampf(slash_t / float(hs["time"]), 0.0, 1.0)
		var a0 := slash_dir.angle() - half
		var a1 := a0 + half * 2.0 * minf(1.0, k * 1.6)
		var sc: Color = hs["color"]
		draw_arc(Vector2.ZERO, float(hs["r"]) * 0.8, a0, a1, 20, Color(sc.lightened(0.4), 0.9 * (1.0 - k * 0.6)), 10.0)
		draw_arc(Vector2.ZERO, float(hs["r"]) * 0.8 + 8.0, a0, a1, 20, Color(1, 1, 1, 0.5 * (1.0 - k)), 3.0)
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
