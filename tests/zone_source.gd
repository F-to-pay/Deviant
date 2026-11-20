extends SceneTree
## ZoneLoader берёт карты из подставляемого источника (`ZoneLoader.source`, наследник `ZoneSource`): свой источник должен
## вызываться для зоны и для города, а результат — оказываться в игре. Запуск: godot --headless --path . -s res://tests/zone_source.gd

var fails := 0


func ok(cond: bool, what: String) -> void:
	print("SMOKE ", "ok   " if cond else "FAIL ", what)
	if not cond:
		fails += 1


func _initialize() -> void:
	var M: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(M)
	var guard := 0
	while not (M.get("menu") != null and M.menu.visible) and guard < 3000:
		await process_frame
		guard += 1
	M.start_game({"seed": "123"})
	for i in 5:
		await process_frame
	# источник-обёртка: считает вызовы и отдаёт процедурные карты
	var scr := GDScript.new()
	scr.source_code = "extends ZoneSource\nvar zone_calls := 0\nvar town_calls := 0\nvar last_level := 0\n" \
		+ "func zone(level, rng):\n\tzone_calls += 1\n\tlast_level = level\n\treturn ZoneGen.generate(level, rng)\n" \
		+ "func town(next_level, rng):\n\ttown_calls += 1\n\tlast_level = next_level\n\treturn TownGen.generate(next_level, rng)\n"
	ok(scr.reload() == OK, "custom ZoneSource compiles")
	var src: Object = scr.new()
	ok(M.loader.source != null, "loader has a default source")
	M.loader.source = src
	M.rng.seed = 321
	M.loader.load_zone(3)
	await process_frame
	ok(src.zone_calls == 1 and src.last_level == 3, "load_zone asked the custom source (level %d)" % src.last_level)
	ok(M.zone.level == 3 and M.enemies.size() > 0, "zone loaded from its data: level %d, %d enemies" % [M.zone.level, M.enemies.size()])
	M.loader.load_town(6)
	await process_frame
	ok(src.town_calls == 1 and src.last_level == 6, "load_town asked the custom source")
	ok(M.town.has("stock") and M.zone.level == 6, "town loaded")
	var base := ZoneSource.new()
	ok(base.zone(1, RandomNumberGenerator.new()).is_empty() and base.town(1, RandomNumberGenerator.new()).is_empty(), "base ZoneSource returns an empty dictionary")
	print("SMOKE RESULT fails=", fails)
	quit()
