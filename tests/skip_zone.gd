extends SceneTree
## Пропуск зон (команда отладчика skip): каждая пропущенная зона платит бюджет судьи (1,5 уровня), как полная зачистка.
## Запуск: godot --headless --path . -s res://tests/skip_zone.gd   (в конце «SMOKE RESULT fails=0»). Пользовательский сейв не трогает.

var fails := 0


func ok(cond: bool, what: String) -> void:
	print("SMOKE ", "ok   " if cond else "FAIL ", what)
	if not cond:
		fails += 1


func _initialize() -> void:
	var G: Node = root.get_node("Game")
	var M: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(M)
	var guard := 0
	while not (M.get("menu") != null and M.menu.visible) and guard < 3000:
		await process_frame
		guard += 1
	M.start_game({"seed": "123"})
	for i in 5:
		await process_frame
	M.rng.seed = 1001
	M.loader.load_zone(1)
	await process_frame
	var coins0: float = G.state.coins
	ok(G.state.hero_level == 1, "start at level 1")
	M.skip_zone(3)   # зона 1 (враги остаются) + пропущенные 2 и 3 -> цель 4
	await process_frame
	# 3 зоны по 1,5 уровня с первого: 1 + 4,5 = 5,5 -> уровень 5 и полполоски
	ok(G.state.hero_level == 5, "3 zones x 1.5 levels from level 1 -> level 5 (got %d)" % G.state.hero_level)
	ok(G.state.xp > 0.0 and G.state.xp < float(G.state.xp_total), "partial progress into level 6 (xp %.1f)" % G.state.xp)
	ok(G.state.coins > coins0, "skipped zones paid coins")
	ok(G.state.kills > 0, "kills counted (%d)" % G.state.kills)
	print("SMOKE RESULT fails=", fails)
	quit()
