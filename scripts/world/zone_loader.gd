class_name ZoneLoader
extends RefCounted
## Загрузка зон и городов: данные карты берутся из `source` (`ZoneSource`: процедурная генерация, позже — карты редактора),
## затем расставляются враги, сундуки, портал, лавки, заказ. Экземпляр — `Main.loader`.

var main: Main

const ZONE_HEAL := 0.0         # хил при входе в новую зону (0 = хардкор). Крути, если станет нереально.
var source: ZoneSource = ProceduralZoneSource.new()   # откуда берутся карты


func _init(m: Main) -> void:
	main = m


func clear_zone() -> void:
	for e in main.enemies:
		if is_instance_valid(e):
			e.queue_free()
	main.enemies.clear()
	for o in main.turrets:
		if is_instance_valid(o):
			o.queue_free()
	main.turrets.clear()
	main.loot.clear()
	for o in main.stalls:
		if is_instance_valid(o):
			o.queue_free()
	main.stalls.clear()
	main.near_stall = null
	if main.reset_stone != null and is_instance_valid(main.reset_stone):
		main.reset_stone.queue_free()
	main.reset_stone = null
	main.near_reset = false
	main.hud.close_stall()
	if main.portal != null and is_instance_valid(main.portal):
		main.portal.queue_free()
	main.portal = null
	main.boss = null
	main.near_item = null
	main.near_chest = null
	main.projectiles.clear_all()
	main.fx.clear()
	main.grid_hash.clear()


func load_zone(level: int) -> void:
	main.player.trim_flasks()
	Game.state.zone_level = level
	Game.state.in_town = false
	main.town = {}
	main.player.hurt_this_zone = false
	main.zone_time = 0.0
	main.director.begin_zone()
	main.loot.flasks_spawned = 0
	if level > 1:
		if bool(Game.run["zone_heal"]):
			main.player.heal(main.player.max_hp, true)
		elif ZONE_HEAL > 0.0:
			main.player.heal(ZONE_HEAL)
	clear_zone()
	var data: Dictionary = source.zone(level, main.rng)
	_enter(data)
	var boss_title := ""
	if bool(data["boss"]):
		var b: Boss
		if AntiPlayer.roll(level, main.rng):
			var ap := AntiPlayer.new()   # зеркало игрока: его лучшая пушка и навык его героя
			ap.position = main.zone.cell_center(data["boss_cell"])
			ap.setup_anti(level, main.rng)
			b = ap
		else:
			b = Boss.new()
			b.position = main.zone.cell_center(data["boss_cell"])
			b.setup_boss(level, main.rng)
		main.enemy_layer.add_child(b)
		main.enemies.append(b)
		main.boss = b
		boss_title = b.title
		main.director.note_spawn(level, 3)
	else:
		for pk in data["packs"]:
			_spawn_pack(level, main.zone.cell_center(pk))
		for c in (data["chests"] if bool(Game.run["chests"]) else []):
			main.loot.spawn_chest(main.zone.cell_center(c), main.rng.randf() < 0.12 + float(level) * 0.004)
		spawn_portal(main.zone.cell_center(data["portal"]), level + 1)
		main.rewards.mark_bounty()
		_spawn_zone_stall(level)
	main.director.finish_zone()   # зона расставлена: судья подгоняет награду под 1,5 уровня
	main.zone.explore(main.player.position, 11)
	main.update_wake()
	main.music.on_zone(main.boss != null)
	if main.boss != null:
		Sfx.ui("boss/appear", -3.0)
	elif level > 1:
		Sfx.ui("world/zone", -8.0)
	main.hud.zone_banner(level, U.t(str(data["biome"]["name"])), boss_title)


## Случайная лавка на карте обычной зоны (не босса): Оружейная или Мастерская; если нет задания Гильдии — в половине случаев Гильдия.
## Товар — тот же, что в городе (Shops.make_town), он лежит в town, пока идёшь по этой зоне. Лавка видна на миникарте.
func _spawn_zone_stall(level: int) -> void:
	var kind := "shop" if main.rng.randf() < 0.5 else "workshop"
	if Quests.can_take() and main.rng.randf() < 0.5:
		kind = "guild"
	var pos := _stall_spot()
	if pos == Vector2.INF:
		return
	main.town = Shops.make_town(level, main.rng)
	var st := Stall.new()
	st.kind = kind
	st.position = pos
	main.item_layer.add_child(st)
	main.stalls.append(st)
	Game.say(U.t("A trader on this map: %s — see the minimap") % st.title(), st.color())


## Место для лавки: открытая площадка (стены не рядом, лавка рисуется выше точки), подальше от входа и портала. INF — не нашли.
func _stall_spot() -> Vector2:
	var far := 700.0
	for attempt in 60:
		var c := Vector2i(main.rng.randi_range(3, main.zone.w - 4), main.rng.randi_range(3, main.zone.h - 4))
		if main.zone.get_cell(c.x, c.y) != Zone.FLOOR:
			continue
		var p := main.zone.open_spot_near(main.zone.cell_center(c), 70.0, 120.0)
		if main.zone.circle_blocked(p, 70.0) or main.zone.circle_blocked(p + Vector2(0, -50.0), 55.0):
			continue
		if p.distance_to(main.player.position) < far * (1.0 - float(attempt) / 90.0):
			continue
		if main.portal != null and is_instance_valid(main.portal) and p.distance_to(main.portal.position) < 250.0:
			continue
		return p
	return Vector2.INF


## Город перед зоной next_level: лавки, портал дальше, врагов нет.
func load_town(next_level: int) -> void:
	var data: Dictionary = source.town(next_level, main.rng)
	if data.is_empty():   # не должно случаться, но лучше без города, чем падение
		load_zone(next_level)
		return
	Game.state.in_town = true
	main.player.trim_flasks()
	clear_zone()
	main.town = Shops.make_town(next_level, main.rng)
	Game.state.town_name = str(data["name"])
	_enter(data)
	for o in data["stalls"]:
		var st := Stall.new()
		st.kind = str(o[0])
		st.position = main.zone.cell_center(o[1])
		main.item_layer.add_child(st)
		main.stalls.append(st)
	spawn_portal(main.zone.cell_center(data["portal"]), next_level)
	if next_level == 1:
		main.reset_stone = ResetStone.new()
		# камень — в центре площади (на самом центре может быть пруд или памятник — берём ближайшую свободную точку)
		main.reset_stone.position = main.zone.open_spot_near(main.zone.cell_center(data.get("center", data["spawn"])), 34.0)
		main.item_layer.add_child(main.reset_stone)
	main.zone.explore(main.player.position, 11)
	main.music.on_town()
	if next_level > 1:
		Sfx.ui("world/zone", -8.0)
	main.hud.town_banner(Game.state.town_name, next_level, U.t(str(Biomes.for_level(next_level)["name"])))


## Белые пушки в руках и рюкзаке подгоняются под уровень новой зоны (города — следующей зоны), см. `Gun.sync_level`.
func sync_white_guns() -> void:
	var lvl := Game.white_level()
	for o in main.player.guns:
		if o != null:
			(o as Gun).sync_level(lvl)
	for o in main.player.backpack:
		(o as Gun).sync_level(lvl)


## Общее для зоны и города: карта, игрок на входе, границы камеры.
func _enter(data: Dictionary) -> void:
	main.zone.setup(data)
	sync_white_guns()
	main.player.position = main.zone.cell_center(data["spawn"])
	main.player.kick = Vector2.ZERO
	var ws := main.zone.world_size()
	main.camera.limit_left = 0
	main.camera.limit_top = 0
	main.camera.limit_right = int(ws.x)
	main.camera.limit_bottom = int(ws.y)
	main.camera.position = main.player.position
	main.camera.reset_smoothing()


func _spawn_pack(level: int, center: Vector2) -> void:
	var pk: Dictionary = EnemyData.roll_pack(level, main.rng, Director.ELITE_LOVE)
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
	var affs: Array = EnemyData.roll_affixes(n_aff, main.rng)
	var champ_affs: Array = EnemyData.roll_affixes(1, main.rng) if no_normals and elite == 2 else []
	var pid := main.rng.randi() % 1000000
	main.director.note_pack()
	for i in members.size():
		var pos := main.zone.random_free_near(center, 0.0, 90.0)
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
	b.position = main.zone.random_free_near(center, 0.0, 60.0)
	b.setup_boss(level, main.rng)
	b.awake = false
	b.aggro = false
	b.pack = 1000000 + main.rng.randi() % 1000000   # своя «стая», чтобы не будить чужих
	b.set_physics_process(false)
	main.enemy_layer.add_child(b)
	main.enemies.append(b)
	main.director.note_pack()
	main.director.note_spawn(level, 3)


func spawn_enemy(t: String, pos: Vector2, level: int, elite: int, affixes: Array, pack_id: int = -1,
		aggro: bool = false) -> Enemy:
	var e := Enemy.new()
	e.position = pos
	e.setup(t, level, elite, affixes)
	e.pack = pack_id
	if aggro:
		e.summoned = true   # призванные (босс, шаман) опыта не дают — иначе ферма
	else:
		main.director.note_spawn(level, elite)
	main.enemy_layer.add_child(e)
	main.enemies.append(e)
	if aggro:
		e.aggro = true
		e.awake = true
		e.set_physics_process(true)
	else:
		e.awake = false
		e.set_physics_process(false)
	return e


func spawn_portal(pos: Vector2, target: int) -> void:
	main.portal = Portal.new()
	main.portal.position = pos
	main.portal.target_level = target
	main.portal.to_town = not Game.state.in_town and RunConfig.town_before(Game.run, target)
	main.item_layer.add_child(main.portal)
