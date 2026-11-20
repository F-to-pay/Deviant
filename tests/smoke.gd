extends SceneTree
## Дымовой тест: настоящий Main, забег с фиксированным сидом, зоны 1..400, убийства, город. Печатает «отпечаток»
## (строки SMOKE ...): при рефакторинге без смены баланса вывод до и после должен совпасть построчно
## (сравнивать по ASCII: консоль Windows портит юникод). Пользовательский сейв не трогает (смерть, мета, настройки не вызываются).
## Запуск: godot --headless --path . -s res://tests/smoke.gd   (шум «Not supported by this display server» — от прогрева без экрана)
## Читает поля Game через gv(): ищет в Game, затем в state/profile/settings.

var G: Node
var M: Node


func gv(name: String) -> Variant:
	if name in G:
		return G.get(name)
	for sub in ["state", "profile", "settings"]:
		var o: Variant = G.get(sub)
		if o != null and name in o:
			return o.get(name)
	return "?"


func _initialize() -> void:
	G = root.get_node("Game")
	M = load("res://scenes/main.tscn").instantiate()
	root.add_child(M)
	var guard := 0
	while not (M.get("menu") != null and M.menu.visible) and guard < 3000:
		await process_frame
		guard += 1
	print("SMOKE menu after frames: ", guard)
	M.start_game({"seed": "123"})
	for i in 5:
		await process_frame
	print("SMOKE start hero_level=", gv("hero_level"), " coins=", gv("coins"), " zone_level=", gv("zone_level"), " in_town=", gv("in_town"))
	print("SMOKE guns: ", M.player.guns.map(func(g): return [g.rarity, g.level, snappedf(g.damage, 0.001)] if g != null else null))
	var zones := [1, 2, 3, 5, 6, 10, 11, 25, 100, 250, 400]
	for z in zones:
		if M.get("zone") == null:
			break
		if bool(G.call("town_before", z)) if G.has_method("town_before") else false:
			pass
		M.rng.seed = 1000 + int(z)   # лут при убийствах тянет случайные числа — без пересева зоны плывут
		M.loader.load_zone(z)
		await process_frame
		var hp_sum := 0.0
		var first := 0.0
		for e in M.enemies:
			var h := float(e.get("max_hp"))
			hp_sum += h
			if first == 0.0:
				first = h
		var d: String = M.director.describe()
		print("SMOKE zone ", z, " en=", M.enemies.size(), " hp_sum=", snappedf(hp_sum, 0.01), " first=", snappedf(first, 0.01), " | ", d)
		print("SMOKE   player max_hp=", snappedf(float(M.player.max_hp), 0.01), " guns=", M.player.guns.map(func(g): return [g.rarity, g.level, snappedf(g.damage, 0.001)] if g != null else null))
		# убить всех: XP, уровни, лут
		var lv0: int = int(gv("hero_level"))
		var killed := 0
		for e in M.enemies.duplicate():
			if is_instance_valid(e):
				e.dead = true
				M.rewards.on_enemy_killed(e, true)
				killed += 1
		print("SMOKE   killed=", killed, " hero_level ", lv0, "->", gv("hero_level"), " xp=", snappedf(float(gv("xp")), 0.01), " kills=", gv("kills"), " coins~", snappedf(float(gv("coins")), 1.0) >= 0.0)
	M.loader.load_town(6)
	await process_frame
	print("SMOKE town stock=", M.town.get("stock", []).size(), " in_town=", gv("in_town"), " zone.level=", M.zone.level)
	print("SMOKE rating=", G.call("rating") if G.has_method("rating") else (G.state.rating(G.run) if G.get("state") != null else "n/a"))
	print("SMOKE DONE")
	quit()
