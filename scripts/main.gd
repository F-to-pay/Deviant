class_name Main
extends Node2D
## Корень игры: собирает мир, спавнит зоны, раздаёт лут, двигает камеру.

const MAX_ORBS_PER_ZONE := 2   # хилок за зону, не больше
const ZONE_HEAL := 0.0         # хил при входе в новую зону (0 = хардкор). Крути, если станет нереально.

var zone: Zone
var player: Player
var projectiles: Projectiles
var fx: FX
var hud: HUD
var music: Music
var sfx: Sfx
var menu: Menu
var camera: Camera2D
var item_layer: Node2D
var enemy_layer: Node2D
var grid_hash := SpatialHash.new()
var rng := RandomNumberGenerator.new()

var enemies: Array = []
var items: Array = []
var orbs: Array = []
var ammo_boxes: Array = []
var chests: Array = []
var portal: Portal = null
var boss: Boss = null
var near_item: GroundItem = null
var near_chest: Chest = null
var transitioning := false
var zone_time := 0.0
var orbs_spawned := 0

var _flow_t := 0.0
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
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	to_menu()


## Главное меню: мир выгружен и стоит на паузе, HUD спрятан.
func to_menu() -> void:
	hud.dead_screen = false
	hud.paused = false
	hud.inv.visible = false
	hud.visible = false
	sfx.reload_cancel()
	_clear_zone()
	get_tree().paused = true
	music.on_menu()
	menu.open_main()


## cfg — параметры забега (см. Game.RUN_DEFAULTS); пустой — обычная игра.
func start_game(cfg: Dictionary = {}) -> void:
	Game.run = Game.RUN_DEFAULTS.duplicate()
	Game.run.merge(cfg, true)
	menu.close()
	hud.visible = true
	start_run()


## Рестарт (R на экране смерти) — с теми же параметрами; заданный сид повторяет забег.
func start_run() -> void:
	get_tree().paused = false
	Game.seed_value = Game.seed_from(str(Game.run["seed"]))
	rng.seed = Game.seed_value
	Game.new_run()
	player.reset()
	# По умолчанию стартовый пистолет — Синергис: бесконечные патроны, чтобы было чем стрелять
	var arch := str(Game.run["arch"])
	var maker := str(Game.run["maker"])
	arch = "pistol" if arch == "" else ("" if arch == "random" else arch)
	maker = "synergis" if maker == "" else ("" if maker == "random" else maker)
	var starter := GunGen.generate(1, rng, 0.0, 0, GunData.R_COMMON, arch, maker)
	player.add_gun(starter)
	player.add_gun(GunGen.generate(1, rng, 0.0, 0, GunData.R_UNCOMMON))
	for o in player.guns:
		if o != null:
			Game.note_gun(o)
			var sg: Gun = o
			player.add_ammo(sg.ammo_type(), GunData.ammo_cap(sg.ammo_type()))
	load_zone(1)
	hud.on_run_start()


# --- Зоны -------------------------------------------------------------------------

func _clear_zone() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	for it in items:
		if is_instance_valid(it):
			it.queue_free()
	items.clear()
	for o in orbs:
		if is_instance_valid(o):
			o.queue_free()
	orbs.clear()
	for a in ammo_boxes:
		if is_instance_valid(a):
			a.queue_free()
	ammo_boxes.clear()
	for c in chests:
		if is_instance_valid(c):
			c.queue_free()
	chests.clear()
	if portal != null and is_instance_valid(portal):
		portal.queue_free()
	portal = null
	boss = null
	near_item = null
	near_chest = null
	projectiles.clear_all()
	fx.clear()
	grid_hash.clear()


func load_zone(level: int) -> void:
	Game.zone_level = level
	zone_time = 0.0
	orbs_spawned = 0
	if level > 1:
		if bool(Game.run["zone_heal"]):
			player.heal(player.max_hp, true)
		elif ZONE_HEAL > 0.0:
			player.heal(ZONE_HEAL)
	_clear_zone()
	var data: Dictionary = ZoneGen.generate(level, rng)
	zone.setup(data)
	player.position = zone.cell_center(data["spawn"])
	var ws := zone.world_size()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(ws.x)
	camera.limit_bottom = int(ws.y)
	camera.position = player.position
	camera.reset_smoothing()
	var boss_title := ""
	if bool(data["boss"]):
		var b := Boss.new()
		b.position = zone.cell_center(data["boss_cell"])
		b.setup_boss(level, rng)
		enemy_layer.add_child(b)
		enemies.append(b)
		boss = b
		boss_title = b.title
	else:
		for pk in data["packs"]:
			_spawn_pack(level, zone.cell_center(pk))
		for c in (data["chests"] if bool(Game.run["chests"]) else []):
			_spawn_chest(zone.cell_center(c), rng.randf() < 0.12 + float(level) * 0.004)
		_spawn_portal(zone.cell_center(data["portal"]), level + 1)
	zone.update_flow(player.position)
	zone.explore(player.position, 11)
	_update_wake()
	music.on_zone(boss != null)
	if boss != null:
		Sfx.ui("boss/appear", -3.0)
	elif level > 1:
		Sfx.ui("world/zone", -8.0)
	hud.zone_banner(level, U.t(str(data["biome"]["name"])), boss_title)


func next_zone() -> void:
	if transitioning:
		return
	transitioning = true
	player.invuln = 99.0
	Sfx.ui("world/portal", -4.0)
	var tw := create_tween()
	tw.tween_property(hud, "fade", 1.0, 0.35)
	tw.tween_callback(_do_next_zone)
	tw.tween_property(hud, "fade", 0.0, 0.45)
	tw.tween_callback(_end_transition)


func _do_next_zone() -> void:
	load_zone(Game.zone_level + 1)


func _end_transition() -> void:
	transitioning = false
	player.invuln = 1.0


func _spawn_pack(level: int, center: Vector2) -> void:
	var pk: Dictionary = EnemyData.roll_pack(level, rng)
	if bool(pk.get("boss", false)):
		_spawn_wander_boss(level, center)
		return
	var members: Array = pk["members"]
	var elite: int = pk["elite"]
	var n_aff := int(pk["affixes"])
	var no_normals := bool(Game.run["no_normals"])
	# «Нет обычных врагов»: обычный пак становится чемпионским, свита вожака — тоже чемпионы
	if no_normals and elite == 0:
		elite = 1
		n_aff = 1 + (1 if level >= 10 else 0)
		members = members.slice(0, 5)
	var affs: Array = EnemyData.roll_affixes(n_aff, rng)
	var champ_affs: Array = EnemyData.roll_affixes(1, rng) if no_normals and elite == 2 else []
	var pid := rng.randi() % 1000000
	for i in members.size():
		var pos := zone.random_free_near(center, 0.0, 90.0)
		var el := 0
		var a: Array = []
		if elite == 1:
			el = 1
			a = affs
		elif elite == 2 and i == 0:
			el = 2
			a = affs
		elif elite == 2 and no_normals:
			el = 1
			a = champ_affs
		spawn_enemy(str(members[i]), pos, level, el, a, pid, false)


## Хаос: босс вместо стаи. Спит, пока не подойдёшь, портал за него не появляется.
func _spawn_wander_boss(level: int, center: Vector2) -> void:
	var b := Boss.new()
	b.position = zone.random_free_near(center, 0.0, 60.0)
	b.setup_boss(level, rng)
	b.awake = false
	b.aggro = false
	b.pack = 1000000 + rng.randi() % 1000000   # своя «стая», чтобы не будить чужих
	b.set_physics_process(false)
	enemy_layer.add_child(b)
	enemies.append(b)


func spawn_enemy(t: String, pos: Vector2, level: int, elite: int, affixes: Array, pack_id: int = -1,
		aggro: bool = false) -> Enemy:
	var e := Enemy.new()
	e.position = pos
	e.setup(t, level, elite, affixes)
	e.pack = pack_id
	enemy_layer.add_child(e)
	enemies.append(e)
	if aggro:
		e.aggro = true
		e.awake = true
		e.set_physics_process(true)
	else:
		e.awake = false
		e.set_physics_process(false)
	return e


func _spawn_chest(pos: Vector2, golden: bool) -> void:
	var c := Chest.new()
	c.position = pos
	c.golden = golden
	item_layer.add_child(c)
	chests.append(c)


func _spawn_portal(pos: Vector2, target: int) -> void:
	portal = Portal.new()
	portal.position = pos
	portal.target_level = target
	item_layer.add_child(portal)


# --- Лут ------------------------------------------------------------------------

func drop_gun(g: Gun, pos: Vector2, pop: bool = true) -> void:
	var it := GroundItem.new()
	it.gun = g
	it.position = pos
	if pop:
		it.vel = Vector2.from_angle(randf() * TAU) * randf_range(120.0, 220.0)
	item_layer.add_child(it)
	items.append(it)
	if g.rarity >= GunData.R_LEGENDARY:
		Sfx.ui("pickup/legendary", -3.0, 1.0, 0.3)
		Game.say("%s! %s" % [g.rarity_name().to_upper(), g.gun_name], g.rarity_color())
		fx.ring(pos, 80.0, g.rarity_color(), 0.6)


func spawn_orb(pos: Vector2) -> void:
	if orbs_spawned >= MAX_ORBS_PER_ZONE or bool(Game.run["no_heal"]):
		return
	orbs_spawned += 1
	var o := HealthOrb.new()
	o.position = pos
	o.vel = Vector2.from_angle(randf() * TAU) * randf_range(60.0, 140.0)
	item_layer.add_child(o)
	orbs.append(o)


func remove_orb(o: HealthOrb) -> void:
	orbs.erase(o)
	o.queue_free()


## Новая лут-пушка: по умолчанию с пустым магазином (патроны — только дроп и разбор).
func _loot(g: Gun) -> Gun:
	if not GunData.LOOT_GUN_LOADED:
		g.ammo = 0
	return g


## Тип патронов для дропа: в основном под пушки в слотах.
func _pick_ammo_type() -> String:
	var held: Array = []
	for o in player.guns:
		if o != null:
			var g: Gun = o
			held.append(g.ammo_type())
	if not held.is_empty() and rng.randf() < 0.75:
		return held[rng.randi() % held.size()]
	var keys: Array = GunData.ARCH.keys()
	var k: String = keys[rng.randi() % keys.size()]
	# у некоторых основ патроны чужие (миномёт -> гранаты)
	return str(GunData.ARCH[k].get("ammo", k))


## mags — сколько базовых магазинов этого типа в коробке.
func spawn_ammo(pos: Vector2, mags: float, t: String = "") -> void:
	var at := t if t != "" else _pick_ammo_type()
	var b := AmmoBox.new()
	b.ammo_type = at
	b.amount = maxi(1, ceili(float(GunData.base_mag(at)) * mags))
	b.position = pos
	b.vel = Vector2.from_angle(randf() * TAU) * randf_range(60.0, 150.0)
	item_layer.add_child(b)
	ammo_boxes.append(b)


func remove_ammo(b: AmmoBox) -> void:
	ammo_boxes.erase(b)
	b.queue_free()


## X — разобрать лежащую рядом пушку на патроны.
func player_scrap_near() -> void:
	if player.dead or transitioning:
		return
	if near_item == null or not is_instance_valid(near_item):
		return
	var it := near_item
	player.scrap(it.gun)
	fx.ring(it.position, 30.0, GunData.AMMO_COL[it.gun.ammo_type()], 0.3)
	_remove_item(it)


func _remove_item(it: GroundItem) -> void:
	items.erase(it)
	if near_item == it:
		near_item = null
	it.queue_free()


func open_chest(c: Chest) -> void:
	if c.opened:
		return
	c.opened = true
	c.queue_redraw()
	Sfx.at("world/chest", c.position, -2.0, 0.9, 0.05, 2, 0.1)
	var lvl: int = Game.zone_level
	var n := rng.randi_range(2, 3) + (1 if c.golden else 0)
	for i in n:
		var g := _loot(GunGen.generate(lvl, rng, 2.5 if c.golden else 1.0, 2 if c.golden else 1))
		drop_gun(g, c.position + Vector2(0, 8))
	if rng.randf() < 0.25:
		spawn_orb(c.position)
	fx.ring(c.position, 50.0, Color(1.0, 0.85, 0.4))
	near_chest = null


## E — подобрать в рюкзак, F — заменить текущую пушку.
func player_interact(swap: bool) -> void:
	if player.dead or transitioning:
		return
	if near_item != null and is_instance_valid(near_item):
		var it := near_item
		var g: Gun = it.gun
		if swap:
			var old := player.gun()
			player.guns[player.active] = g
			player.on_gun_changed()
			_remove_item(it)
			if old != null:
				drop_gun(old, player.position + player.aim * 20.0, true)
			Game.say(U.t("В руках: ") + g.gun_name, g.rarity_color())
			Sfx.ui("pickup/gun", -4.0)
		else:
			if player.add_gun(g):
				_remove_item(it)
				Game.say(U.t("Подобрано: ") + g.gun_name, g.rarity_color())
				Sfx.ui("pickup/gun", -4.0)
			else:
				Game.say(U.t("Рюкзак полон! [F] — заменить текущую, [X] — разобрать на патроны"), Color(1.0, 0.5, 0.4))
				Sfx.ui("ui/error", -6.0)
				return
		Game.note_gun(g)
		return
	if near_chest != null and is_instance_valid(near_chest) and not near_chest.opened:
		open_chest(near_chest)


# --- События ---------------------------------------------------------------------

func on_enemy_killed(e: Enemy, by_player: bool = true) -> void:
	enemies.erase(e)
	if e.elite != 3:
		# крупные — ниже и громче
		Sfx.at("enemy/death", e.position, -9.0 if e.elite == 0 else -5.0, clampf(18.0 / e.radius, 0.7, 1.3), 0.08, 3, 0.04)
	fx.death_burst(e.position, e.color, e.radius)
	if e.elite == 3:
		_boss_dead(e)
		return
	if not by_player:
		return
	Game.kills += 1
	var lvl: int = Game.zone_level
	var chance := 0.055
	var bonus := 0.0
	if e.elite == 1:
		chance = 0.4
		bonus = 0.6
	elif e.elite == 2:
		chance = 1.0
		bonus = 1.3
	if rng.randf() < chance:
		drop_gun(_loot(GunGen.generate(lvl, rng, bonus)), e.position)
	if e.elite == 2 and rng.randf() < 0.5:
		drop_gun(_loot(GunGen.generate(lvl, rng, bonus)), e.position)
	var orb_chance := 0.03 if e.elite == 0 else 0.25
	if rng.randf() < orb_chance:
		spawn_orb(e.position)
	# патроны: обычный — 15% на полмагазина, чемпион — 60% на магазин, вожак — 2 магазина
	if e.elite == 0:
		if rng.randf() < 0.15:
			spawn_ammo(e.position, 0.5)
	elif e.elite == 1:
		if rng.randf() < 0.6:
			spawn_ammo(e.position, 1.0)
	else:
		spawn_ammo(e.position, 1.0)
		spawn_ammo(e.position, 1.0)


func _boss_dead(b: Enemy) -> void:
	if boss == b:
		boss = null
	Game.kills += 1
	Game.bosses += 1
	var lvl: int = Game.zone_level
	fx.explosion(b.position, 220.0, b.color, true)
	fx.shake(18.0)
	Game.say(U.t("Босс повержен: ") + b.title, Color(1.0, 0.85, 0.3))
	Sfx.ui("boss/death", -2.0)
	Sfx.at("explosion_big", b.position, 0.0, 0.7, 0.05, 2, 0.1)
	if not Game.is_boss_zone(lvl):
		# бродячий босс хаоса: лут поскромнее, без портала и смены музыки
		drop_gun(_loot(GunGen.generate(lvl + 1, rng, 3.0, GunData.R_EPIC if rng.randf() < 0.3 else GunData.R_RARE)), b.position)
		spawn_orb(b.position)
		for i in 2:
			spawn_ammo(b.position, 1.0)
		return
	music.on_boss_dead()
	var top := GunData.R_LEGENDARY if rng.randf() < 0.4 else GunData.R_EPIC
	drop_gun(_loot(GunGen.generate(lvl + 1, rng, 4.0, top)), b.position)
	for i in 2:
		drop_gun(_loot(GunGen.generate(lvl, rng, 3.0, GunData.R_RARE)), b.position)
	for i in 2:
		spawn_orb(b.position)
	for i in 4:
		spawn_ammo(b.position, 1.0)
	_spawn_portal(zone.random_free_near(b.position + Vector2(0, -90), 0.0, 60.0), lvl + 1)


func on_player_died() -> void:
	var rec: bool = Game.record_death()
	hud.show_death(rec)
	music.on_death()


# --- Цикл ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	zone_time += delta
	if not player.dead:
		Game.run_time += delta
	grid_hash.clear()
	for o in enemies:
		var e: Enemy = o
		if e.awake and not e.dead:
			grid_hash.insert(e)
	_flow_t -= delta
	if _flow_t <= 0.0:
		_flow_t = 0.25
		if not player.dead:
			zone.update_flow(player.position)
	_wake_t -= delta
	if _wake_t <= 0.0:
		_wake_t = 0.3
		_update_wake()
	_explore_t -= delta
	if _explore_t <= 0.0:
		_explore_t = 0.2
		if not player.dead:
			zone.explore(player.position, 11)
	_update_near()


func _update_wake() -> void:
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


func _update_near() -> void:
	var prev := near_item
	near_item = null
	near_chest = null
	if player.dead:
		return
	var best := 70.0
	for o in items:
		var it: GroundItem = o
		var d := it.position.distance_to(player.position)
		if d < best:
			best = d
			near_item = it
	if prev != near_item:
		if prev != null and is_instance_valid(prev):
			prev.highlight = false
		if near_item != null:
			near_item.highlight = true
	if near_item == null:
		for o in chests:
			var c: Chest = o
			if not c.opened and c.position.distance_to(player.position) < 60.0:
				near_chest = c
				break


func _process(delta: float) -> void:
	if player == null:
		return
	var mp := get_global_mouse_position()
	var look := (mp - player.position).limit_length(500.0) * 0.22
	var target := player.position + look
	camera.position = camera.position.lerp(target, 1.0 - exp(-delta * 10.0))
	camera.offset = fx.shake_offset()
