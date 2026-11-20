class_name Main
extends Node2D
## Корень игры: собирает мир, спавнит зоны и города, раздаёт лут и монеты, двигает камеру.


var zone: Zone
var player: Player
var projectiles: Projectiles
var fx: FX
var hud: HUD
var music: Music
var sfx: Sfx
var menu: Menu
var touch: TouchControls
var camera: Camera2D
var item_layer: Node2D
var enemy_layer: Node2D
var grid_hash := SpatialHash.new()
var rng := RandomNumberGenerator.new()

var enemies: Array = []
var turrets: Array = []          # турели Инженера (Turret): враги отвлекаются на ближайшую цель — героя или турель
var turret_layer: Node2D
var loot := Loot.new(self)             # лут на земле (systems/loot.gd)
var interact := Interact.new(self)     # что рядом с героем и E/F (systems/interaction.gd)
var rewards := Rewards.new(self)       # награды за убийства и смерть героя (systems/rewards.gd)
var loader := ZoneLoader.new(self)     # загрузка зон и городов (world/zone_loader.gd)
var director := Director.new()   # судья: бюджет XP зоны (1,5 уровня), любовь к элиткам, xp_scale (systems/director.gd)
var stalls: Array = []
var portal: Portal = null
var boss: Boss = null
var near_item: GroundItem = null
var near_chest: Chest = null
var near_stall: Stall = null
var reset_stone: ResetStone = null   # камень перезапуска (только в стартовом городе)
var near_reset := false
var transitioning := false
var _next_level := 1
var town: Dictionary = {}       # товар текущего города (Shops.make_town), пусто — не в городе
var _next_town := false
var zone_time := 0.0

var _warmup: Warmup = null
var _wake_t := 0.0
var _explore_t := 0.0


func _ready() -> void:
	Game.main = self
	rng.randomize()
	zone = Zone.new()
	zone.z_index = -10
	add_child(zone)
	item_layer = Node2D.new()
	item_layer.z_index = -2
	add_child(item_layer)
	enemy_layer = Node2D.new()
	add_child(enemy_layer)
	turret_layer = Node2D.new()
	turret_layer.z_index = 1   # под героем (он тоже z 1, но добавлен позже)
	add_child(turret_layer)
	player = Player.new()
	player.z_index = 1
	add_child(player)
	projectiles = Projectiles.new()
	projectiles.z_index = 5
	add_child(projectiles)
	fx = FX.new()
	fx.z_index = 6
	add_child(fx)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	hud = HUD.new()
	add_child(hud)
	music = Music.new()
	add_child(music)
	sfx = Sfx.new()
	add_child(sfx)
	menu = Menu.new()
	add_child(menu)
	touch = TouchControls.new()
	add_child(touch)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	# сначала прогрев под экраном загрузки (шрифты, шейдеры, музыка, скрипты и пушки модов), потом меню
	hud.visible = false
	get_tree().paused = true
	warmup(to_menu)


## Прогрев под экраном загрузки: при запуске и после каждого перескана модов (Game.reload_content).
## done — что сделать, когда экран загрузки начнёт гаснуть.
func warmup(done: Callable = Callable()) -> void:
	if _warmup != null and is_instance_valid(_warmup):
		return
	_warmup = Warmup.new()
	if done.is_valid():
		_warmup.finished.connect(done)
	add_child(_warmup)


## Главное меню: мир выгружен и стоит на паузе, HUD спрятан.
func to_menu() -> void:
	hud.dead_screen = false
	hud.paused = false
	hud.inv.visible = false
	hud.visible = false
	sfx.reload_cancel()
	loader.clear_zone()
	get_tree().paused = true
	music.on_menu()
	menu.open_main()


## cfg — параметры забега (см. RunConfig.DEFAULTS); пустой — обычная игра.
func start_game(cfg: Dictionary = {}) -> void:
	Game.run = RunConfig.DEFAULTS.duplicate()
	Game.run.merge(cfg, true)
	menu.close()
	hud.visible = true
	start_run()


## Рестарт (R на экране смерти) — с теми же параметрами; заданный сид повторяет забег.
func start_run() -> void:
	get_tree().paused = false
	Game.state.seed_value = RunConfig.seed_from(str(Game.run["seed"]))
	rng.seed = Game.state.seed_value
	Game.new_run()
	player.reset()
	# По умолчанию стартовый пистолет — Синергис: бесконечные патроны, чтобы было чем стрелять
	var arch := str(Game.run["arch"])
	var maker := str(Game.run["maker"])
	arch = "pistol" if arch == "" else ("" if arch == "random" else arch)
	maker = "synergis" if maker == "" else ("" if maker == "random" else maker)
	var starter := GunGen.generate(1, rng, 0.0, 0, GunData.R_COMMON, arch, maker)
	player.add_gun(starter)
	for o in player.guns:
		if o != null:
			Game.state.note_gun(o)
			var sg: Gun = o
			if not sg.free_ammo:
				player.add_ammo(sg.ammo_type(), GunData.ammo_cap(sg.ammo_type()))
	if RunConfig.town_before(Game.run, 1):
		loader.load_town(1)
	else:
		loader.load_zone(1)
	hud.on_run_start()


# --- Зоны -------------------------------------------------------------------------


## Ближайшая к точке цель врага: герой или одна из его турелей (мёртвого героя не выбираем, если есть живая турель).
func target_for(pos: Vector2) -> Actor:
	if turrets.is_empty():
		return player
	var best: Actor = player
	var bd := INF if player.dead else pos.distance_squared_to(player.position)
	for o in turrets:
		var t: Turret = o
		if t.dead:
			continue
		var d := pos.distance_squared_to(t.position)
		if d < bd:
			bd = d
			best = t
	return best


## Турель Инженера приземлилась (Projectiles: мина-турель долетела). spec — {gun, ammo, el}.
## Лимит — число зарядов навыка: если все места заняты, самая старая турель убирается, новая встаёт на её место.
func spawn_turret(spec: Dictionary, pos: Vector2) -> void:
	var alive: Array = []
	for o in turrets:
		if is_instance_valid(o) and not (o as Turret).dead:
			alive.append(o)
	turrets = alive
	while turrets.size() >= maxi(1, player.max_charges()):
		(turrets[0] as Turret).dismantle()
	var t := Turret.new()
	t.position = pos
	t.setup(spec)
	turret_layer.add_child(t)
	turrets.append(t)


## Портал: в зону level или (to_town) сначала в город перед ней.
func next_zone(level: int = -1, to_town: bool = false) -> void:
	if transitioning:
		return
	_next_level = level if level > 0 else Game.state.zone_level + 1
	_next_town = to_town
	transitioning = true
	if not Game.state.in_town and not player.dead:
		Quests.progress("zones")
		if not player.hurt_this_zone:
			Quests.progress("flawless")
	player.invuln = 99.0
	Sfx.ui("world/portal", -4.0)
	var tw := create_tween()
	tw.tween_property(hud, "fade", 1.0, 0.35)
	tw.tween_callback(_do_next_zone)
	tw.tween_property(hud, "fade", 0.0, 0.45)
	tw.tween_callback(_end_transition)


## Отладка (команда skip [n] [--boss]): убить всех врагов текущей зоны без лута на земле и перейти дальше.
## n зон вперёд (по умолчанию 1) или to_boss — до ближайшей боссовой зоны. Опыт, убийства и монеты начисляются сразу
## (текущая зона — по реальным врагам, пропущенные — по средним значениям зоны; призванные ничего не дают).
## В городе текущей зоны нет: считается, что пройдено на одну зону меньше номера города.
## Древние монеты и предметы не выдаются.
func skip_zone(n: int = 1, to_boss: bool = false) -> void:
	if transitioning or player.dead:
		return
	var base: int = (zone.level - 1) if Game.state.in_town else Game.state.zone_level
	var target := (base / 5 + 1) * 5 if to_boss else base + maxi(1, n)
	var kills := 0
	var xp := 0.0
	var gold := 0.0
	if not Game.state.in_town:
		var lvl: int = Game.state.zone_level
		for o in enemies.duplicate():
			var e: Enemy = o
			if not is_instance_valid(e) or e.dead:
				continue
			if not e.summoned:
				kills += 1
				xp += director.kill_xp(e.level, e.elite)
				gold += Balance.kill_coin_value(lvl, e.elite, Game.rng)
				if e.elite == 3:
					Game.state.bosses += 1
			e.dead = true
			e.queue_free()
		enemies.clear()
		boss = null
	var ups := Game.add_xp(xp)   # опыт за врагов этой зоны
	# пропущенные зоны между текущей и целевой платят как зачищенные целиком: монеты по средним, опыт — бюджет судьи
	var rm := maxf(0.05, RunConfig.rating_mult(Game.run))
	for l in range(base + 1, target):
		var cnt := 1 if RunConfig.is_boss_zone(l) else roundi(Balance.expected_enemies(l))
		var elite := 3 if RunConfig.is_boss_zone(l) else 0
		for i in cnt:
			gold += Balance.kill_coin_value(l, elite, Game.rng)
		kills += cnt
		if elite == 3:
			Game.state.bosses += 1
		var zone_xp := Director.zone_xp(Game.state.hero_level)
		xp += zone_xp
		ups += Game.add_xp(zone_xp / rm)   # add_xp умножает на рейтинг: делим, чтобы выплата была ровно бюджетом
	Game.state.kills += kills
	Quests.progress("kills", kills)
	Game.state.add_coins(gold)
	Game.say("skip → zone %d: %d kills, +%.0f XP%s, +%s coins" % [target, kills, xp, (" (level up ×%d)" % ups) if ups > 0 else "", U.money(gold)],
		Color(0.7, 1.0, 0.7))
	next_zone(target, RunConfig.town_before(Game.run, target))


## Камень перезапуска: новый забег с нуля в новом стартовом городе (с затемнением, как портал).
func restart_from_stone() -> void:
	if transitioning:
		return
	transitioning = true
	player.invuln = 99.0
	Sfx.ui("world/portal", -4.0, 1.3)
	var tw := create_tween()
	tw.tween_property(hud, "fade", 1.0, 0.3)
	tw.tween_callback(start_run)
	tw.tween_property(hud, "fade", 0.0, 0.4)
	tw.tween_callback(_end_transition)


func _do_next_zone() -> void:
	if _next_town:
		loader.load_town(_next_level)
	else:
		loader.load_zone(_next_level)


func _end_transition() -> void:
	transitioning = false
	player.invuln = 1.0


# --- Лут ------------------------------------------------------------------------


# --- События ---------------------------------------------------------------------


# --- Цикл ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	zone_time += delta
	if not player.dead:
		Game.state.run_time += delta
	grid_hash.clear()
	for o in enemies:
		var e: Enemy = o
		if e.awake and not e.dead:
			grid_hash.insert(e)
	_wake_t -= delta
	if _wake_t <= 0.0:
		_wake_t = 0.3
		update_wake()
	_explore_t -= delta
	if _explore_t <= 0.0:
		_explore_t = 0.2
		if not player.dead:
			zone.explore(player.position, 11)
	interact.update_near()


func update_wake() -> void:
	var pp := player.position
	var need_boss := boss == null or not is_instance_valid(boss) or boss.dead
	for o in enemies:
		var e: Enemy = o
		var d2 := e.position.distance_squared_to(pp)
		# полоска здоровья — первому проснувшемуся боссу (в хаосе их много)
		if need_boss and e.elite == 3 and e.awake and not e.dead:
			boss = e as Boss
			need_boss = false
		if not e.awake and d2 < 1350.0 * 1350.0:
			e.awake = true
			e.set_physics_process(true)
		elif e.awake and d2 > 1850.0 * 1850.0 and e.elite != 3:
			e.awake = false
			e.set_physics_process(false)


func _process(delta: float) -> void:
	if player == null:
		return
	var mp := Game.controls.aim_world(player.position)
	var look := (mp - player.position).limit_length(500.0) * 0.22
	var target := player.position + look
	camera.position = camera.position.lerp(target, 1.0 - exp(-delta * 10.0))
	camera.offset = fx.shake_offset()
