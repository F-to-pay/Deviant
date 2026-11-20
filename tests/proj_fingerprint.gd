extends SceneTree
## Отпечаток снарядов: пушки всех типов, легендарки и абсурдные стреляют по неподвижным неубиваемым врагам, а вражеские пули
## летят в героя. Снаряды шагают синхронно (прямой вызов `Projectiles._physics_process` по 1/60 с, 120 шагов)
## (Sfx ограничивает частоту по счётчику кадров, а не по реальному времени), ГСЧ засеян, так что результат не зависит от кадров и реального времени. Печатается сумма урона по целям, потеря
## здоровья героя и число снарядов в контрольных точках. При рефакторинге `Projectiles._step` вывод должен совпасть построчно.
## Запуск: godot --headless --path . -s res://tests/proj_fingerprint.gd   (пользовательский сейв не трогает)

const HP := 1.0e9

var G: Node
var M: Node
var k_shell := 0   # GunData.K_SHELL (читается из скрипта: в режиме -s типы проекта напрямую недоступны)
var targets: Array = []
var origin := Vector2.ZERO


func _initialize() -> void:
	G = root.get_node("Game")
	M = load("res://scenes/main.tscn").instantiate()
	root.add_child(M)
	var guard := 0
	while not (M.get("menu") != null and M.menu.visible) and guard < 3000:
		await process_frame
		guard += 1
	M.start_game({"seed": "123"})
	for i in 5:
		await process_frame
	M.rng.seed = 555
	M.load_zone(2)
	await process_frame
	seed(2024)   # арена строится от глобального randf() (random_free_near): без сида цели каждый раз стоят по-разному
	setup_arena()
	var GD: GDScript = load("res://scripts/weapons/gun_data.gd")
	var GGC: GDScript = load("res://scripts/weapons/gun_gen.gd")
	k_shell = int(GD.get_script_constant_map()["K_SHELL"])
	var archs: Array = (GD.get("ARCH") as Dictionary).keys()
	archs.sort()
	var cases: Array = []
	for a in archs:
		cases.append(["epic:" + str(a), 3, str(a)])
	for n in 8:
		cases.append(["legendary#%d" % n, 4, ""])
	for n in 5:
		cases.append(["absurd#%d" % n, 5, ""])
	for c in cases:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(c[0]))
		seed(hash(str(c[0])) + 1)   # генератор пушек тоже берёт глобальный randf()
		var g: Object = GGC.call("generate", 12, rng, 0.0, 0, int(c[1]), str(c[2]))
		run_case(str(c[0]), g)   # без await: между случаями не должно проходить реальных кадров (иначе тикают таймеры героя и статусы)
	print("SMOKE DONE")
	quit()


## Герой в открытом месте, пять неподвижных «неубиваемых» целей на прямой видимости впереди.
func setup_arena() -> void:
	var p: Object = M.player
	p.position = M.zone.random_free_near(M.zone.cell_center(Vector2i(M.zone.w / 2, M.zone.h / 2)), 0.0, 200.0)
	origin = p.position
	p.max_hp = HP
	p.hp = HP
	for k in 5:
		var pos: Vector2 = M.zone.random_free_near(origin + Vector2(260.0 + 60.0 * k, (k - 2) * 90.0), 0.0, 60.0)
		var tries := 0
		while not M.zone.ray_clear(origin, pos) and tries < 12:
			pos = origin + (pos - origin) * 0.8
			tries += 1
		var e: Object = M.spawn_enemy("brute", pos, 12, 0, [], -1, false)
		e.awake = true                 # в сетке попаданий...
		e.set_physics_process(false)   # ...но неподвижна: результат не зависит от ИИ
		e.max_hp = HP
		targets.append(e)


func run_case(name: String, g: Object) -> void:
	var proj: Object = M.projectiles
	var p: Object = M.player
	proj.list.clear()
	(proj.get("_pending") as Array).clear()
	for e in targets:
		e.hp = HP
	p.hp = HP
	p.invuln = 0.0
	M.grid_hash.clear()
	for e in targets:
		M.grid_hash.insert(e)
	seed(hash(name))
	M.rng.seed = hash(name)
	var eg: Object = g.clone() if g.has_method("clone") else g
	var counts: Array = []
	var volley := 0
	for f in 120:
		if f % 5 == 0 and volley < 6:
			var tgt: Object = targets[volley % targets.size()]
			var dir: Vector2 = (tgt.position - origin).normalized()
			if g.proj_kind == k_shell:
				proj.fire_shell(g, origin, tgt.position)
			else:
				for i in g.pellets:
					proj.fire_gun(g, origin, dir.rotated(0.04 * float(i % 5 - 2)), 0)
			volley += 1
		if f == 0:
			# вражеские пули в героя (прямые и самонаводящиеся, если у пушки есть наведение)
			for k in 3:
				var from: Vector2 = targets[k].position
				proj.fire_gun(eg, from, (origin - from).normalized(), 1)
		proj.call("_physics_process", 1.0 / 60.0)
		if f % 30 == 29:
			counts.append(proj.count())
	var dealt := 0.0
	for e in targets:
		dealt += HP - float(e.hp)
	print("SMOKE ", name, " rar=", g.rarity, " pellets=", g.pellets, " dealt=", snappedf(dealt, 0.01), " player_lost=",
		snappedf(HP - float(p.hp), 0.01), " proj=", counts, " left=", proj.count())
