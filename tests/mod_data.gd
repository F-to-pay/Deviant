extends SceneTree
## Данные врагов, героев и перков навыков из слоёв мода: добавление, правка, удаление, порядок, нормализация типов, поведение
## нового врага (`ai`) и героя в игре, предупреждения `Mods.validate`. Мод временный (user://_test_mod), настройки и сейв не трогает.
## Запуск: godot --headless --path . -s res://tests/mod_data.gd   (в конце «SMOKE RESULT fails=0»)

const DIR := "user://_test_mod"
var fails := 0


func ok(cond: bool, what: String) -> void:
	print("SMOKE ", "ok   " if cond else "FAIL ", what)
	if not cond:
		fails += 1


func put(rel: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR.path_join(rel).get_base_dir()))
	var f := FileAccess.open(DIR.path_join(rel), FileAccess.WRITE)
	f.store_string(text)
	f.close()


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
	var ModsC: GDScript = load("res://scripts/core/mods.gd")
	var ED: GDScript = load("res://scripts/entities/enemy_data.gd")
	var HR: GDScript = load("res://scripts/entities/heroes.gd")
	var base_n := int((ED.get("TYPES") as Dictionary).size())
	var base_heroes := int((HR.get("LIST") as Dictionary).size())
	var base_perks := int((HR.get("PERKS") as Dictionary).size())
	var base_runner_hp := float(ED.get("TYPES")["runner"]["hp"])

	put("data/enemies.json", '{"zz_test": {"name": "Test Blob", "ai": "runner", "hp": 50, "dmg": 7, "speed": 160, "r": 15, "color": "#ff00ff", '
		+ '"lvl": 1, "sides": 5, "star": true, "w": 3, "res": "cryo"}, "zz_badai": {"ai": "teleporter", "hp": 5}, "runner": {"hp": 99}, "_remove": ["spreader"]}')
	put("data/heroes.json", '{"zz_hero": {"name": "Test Hero", "price": 5, "color": [1, 0, 0], "skill": "grenade", "skill_name": "Boom", "cd": 3, '
		+ '"dmg": 10, "r": 50, "range": 300, "aimed": true, "desc": "Boom: %d damage, radius %d, cooldown %s s."}, "zz_badskill": {"skill": "teleport"}}')
	put("data/hero_perks.json", '{"zz_perk": {"name": "Zz", "heroes": ["zz_hero", "ghost"], "max": 2, "desc": "d", "more": "m"}}')
	var mods: Array = ModsC.get("list")
	mods.append({"id": "zz", "name": "ZZ test mod", "path": DIR, "enabled": true, "info": {}})
	ED.call("load_data")
	HR.call("load_data")

	var types: Dictionary = ED.get("TYPES")
	ok(types.has("zz_test") and types.has("zz_badai"), "mod enemies added")
	ok(not types.has("spreader"), "_remove removed 'spreader'")
	ok(types.size() == base_n + 2 - 1, "enemy count %d (base %d +2 -1)" % [types.size(), base_n])
	ok(types.keys()[types.size() - 2] == "zz_test", "new enemies come last, in file order")
	var z: Dictionary = types["zz_test"]
	ok(z["color"] == Color(1, 0, 1) and typeof(z["lvl"]) == TYPE_INT and typeof(z["sides"]) == TYPE_INT and typeof(z["res"]) == TYPE_INT, "colour from hex, int fields are ints")
	ok(int(z["res"]) == 3 and bool(z["star"]) and float(z["hp"]) == 50.0 and typeof(z["hp"]) == TYPE_FLOAT, "res 'cryo' -> 3, star, hp float")
	ok(float(types["runner"]["hp"]) == 99.0 and float(types["runner"]["dmg"]) == 12.0, "runner hp overridden, dmg kept")
	ok(float(types["zz_badai"]["dmg"]) == 5.0 and bool(types["zz_badai"]["star"]) == false, "missing fields get defaults")

	var list: Dictionary = HR.get("LIST")
	var order: Array = HR.get("ORDER")
	ok(list.has("zz_hero") and order[order.size() - 2] == "zz_hero" and order.size() == base_heroes + 2, "mod hero added to ORDER last")
	ok(int(list["zz_hero"]["price"]) == 5 and list["zz_hero"]["color"] == Color(1, 0, 0), "hero price int, colour from array")
	ok(HR.call("describe", "zz_hero") == "Boom: 10 damage, radius 50, cooldown 3 s.", "describe formats the mod hero: " + str(HR.call("describe", "zz_hero")))
	var perks: Dictionary = HR.get("PERKS")
	ok(perks.has("zz_perk") and perks.size() == base_perks + 1, "mod perk added")
	ok(HR.call("perk_fits", "zz_perk", "zz_hero") and not HR.call("perk_fits", "zz_perk", "pioneer"), "perk fits only listed heroes")
	ok(HR.call("perk_open", "zz_perk", "zz_hero", 1) and not HR.call("perk_open", "zz_perk", "zz_hero", 2), "max 2 respected")

	# враг из данных живёт в игре: поведение по ai
	M.rng.seed = 5
	M.loader.load_zone(3)
	await process_frame
	var e: Object = M.loader.spawn_enemy("zz_test", M.player.position + Vector2(300, 0), 4, 0, [], -1, false)
	ok(e != null and e.ai == "runner" and e.etype == "zz_test" and e.radius == 15.0 and e.color == Color(1, 0, 1), "spawned: ai=runner, radius and colour from data")
	ok(e.elem_res == 3, "innate resistance from data (cryo)")
	# герой из данных: выбрать и применить навык
	M.player.set_hero("zz_hero")
	ok(M.player.hero == "zz_hero" and M.player.skill.max_cd() == 3.0, "mod hero selectable, cooldown from data")
	var charges: int = M.player.skill.charges
	M.player.skill.use(null)
	ok(M.player.skill.charges == charges - 1, "mod hero's grenade skill fires")
	M.player.set_hero("pioneer")

	# выбранный герой выключенного мода -> герой по умолчанию; открытые id сохраняются
	var pr: RefCounted = G.profile
	var keep_hero: String = pr.hero
	var keep_open: Array = pr.heroes_open.duplicate()
	pr.hero = "zz_hero"
	pr.heroes_open.append("zz_hero")
	mods.pop_back()
	HR.call("load_data")
	pr.validate_heroes()
	ok(pr.hero == "pioneer" and "zz_hero" in pr.heroes_open, "unknown selected hero falls back; its unlock is kept")
	pr.hero = keep_hero
	pr.heroes_open = keep_open

	# validate: предупреждения о неизвестных ai / skill / герое
	mods.append({"id": "zz", "name": "ZZ test mod", "path": DIR, "enabled": true, "info": {}})
	ED.call("load_data")
	HR.call("load_data")
	G.debug_log.clear()
	ModsC.call("validate")
	var texts: Array = []
	for en in G.debug_log.entries:
		texts.append(str(en["text"]))
	var joined := "\n".join(PackedStringArray(texts))
	ok(joined.contains("enemy 'zz_badai': unknown ai 'teleporter'"), "validate: unknown ai")
	ok(joined.contains("hero 'zz_badskill': unknown skill 'teleport'"), "validate: unknown skill")
	ok(joined.contains("hero perk 'zz_perk': unknown hero 'ghost'"), "validate: perk for an unknown hero")

	# убрать мод: всё как было
	mods.pop_back()
	ED.call("load_data")
	HR.call("load_data")
	G.debug_log.clear()
	ok((ED.get("TYPES") as Dictionary).size() == base_n and float(ED.get("TYPES")["runner"]["hp"]) == base_runner_hp, "base enemy table restored")
	ok((HR.get("LIST") as Dictionary).size() == base_heroes and (HR.get("PERKS") as Dictionary).size() == base_perks, "base heroes and perks restored")
	for f in ["data/enemies.json", "data/heroes.json", "data/hero_perks.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join("data")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	print("SMOKE RESULT fails=", fails)
	quit()
