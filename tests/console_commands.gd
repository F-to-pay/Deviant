extends SceneTree
## Команды консоли отладчика: каждую подаём в `DebugConsole._on_submit` и печатаем, что попало в журнал и как изменилось
## состояние игры (монеты, древние монеты, герой, пушки). При рефакторинге консоли вывод до и после должен совпасть построчно.
## ВНИМАНИЕ: unlock / hero / ancient пишут в user://deviant.cfg — сделай копию файла перед запуском и верни после.
## Запуск: godot --headless --path . -s res://tests/console_commands.gd

var G: Node
var M: Node


func entries() -> Array:
	return G.debug_log.entries


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
	var con: Node = G.debug_console
	if con == null:
		var DC: GDScript = load("res://scripts/ui/debug_console.gd")
		con = DC.new()
		root.add_child(con)
		await process_frame
	print("SMOKE console ready: ", con != null)
	var cmds := ["help", "foo bar", "Clear", "list", "list perks", "list legendaries", "list arch", "list makers", "list langs", "list mods",
		"lang zz", "lang", "coins 77", "coins", "ancient 3", "ancient", "unlock engineer", "unlock nobody", "hero engineer", "hero",
		"hero nobody", "skillperk", "skillperk nonexistent", "missing", "missing ru", "give", "give pistol", "give random synergis 2",
		"give nosuchtype", "perk", "perk nonexistent", "legendary", "legendary nonexistent", "skip abc", "skip 0", "skip --boss x",
		"validate", "skip 2", "town"]
	for c in cmds:
		M.rng.seed = 4242
		seed(77)
		G.debug_log.clear()   # DebugLog схлопывает одинаковые строки: чистим, чтобы каждый ответ был виден
		var before: int = entries().size()
		con.call("_on_submit", c)
		await process_frame
		var es: Array = entries()
		var out := ""
		for i in range(before, es.size()):
			var en: Dictionary = es[i]
			# строки движка (warn/error из журнала Godot, «Not supported by this display server») приходят асинхронно — не считаем
			if not (str(en.get("level", "")) in ["cmd", "tr", "info"]):
				continue
			out += " | " + str(en.get("text", "")).substr(0, 90)
		var guns: Array = []
		for g in M.player.guns:
			guns.append("-" if g == null else "%s/%d/%s" % [g.gun_name.substr(0, 14), g.rarity, g.special])
		print("SMOKE [", c, "] ->", out)
		print("SMOKE    coins=", snappedf(float(G.state.coins), 0.1), " meta=", G.profile.meta_coins, " hero=", G.profile.hero, " open=",
			G.profile.heroes_open.size(), " guns=", guns, " bag=", M.player.backpack.size(), " level=", G.state.hero_level)
	print("SMOKE DONE")
	quit()
