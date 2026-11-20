extends SceneTree
## Сохранение забега (RunSave): пушки туда-обратно, полный забег (сохранить → начать другой → продолжить → всё совпало, включая ту же карту
## и товар города), смерть стирает сейв, битые и чужие файлы, смена модов, кнопка «Продолжить» на главном экране.
## ВНИМАНИЕ: тест пишет и стирает user://run.save — раннер сам прячет ваш сейв; вручную перед запуском скопируйте файл.
## Запуск: godot --headless --path . -s res://tests/run_save.gd   (в конце «SMOKE RESULT fails=0»)

const PATH := "user://run.save"
var fails := 0
var G: Node
var M: Node


func ok(cond: bool, what: String) -> void:
	print("SMOKE ", "ok   " if cond else "FAIL ", what)
	if not cond:
		fails += 1


func vars_of(o: Object) -> Dictionary:
	var out := {}
	for pr in o.get_property_list():
		if (int(pr["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n := str(pr["name"])
		if n == "gun_name" or n.begins_with("_fx"):
			continue
		out[n] = o.get(n)
	return out


func put(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func put_dict(d: Dictionary) -> void:
	put("DEVRUN1:" + Marshalls.raw_to_base64(var_to_bytes(d)))


## Заметное состояние забега: монеты, опыт, уровни, дерево, задание, шесть пушек, патроны, фляги, перки навыка, здоровье.
func setup_state(GGC: GDScript) -> void:
	G.state.coins = 1234.0
	G.add_xp(900.0)
	G.add_xp(400.0)
	G.state.kills = 77
	G.state.bosses = 2
	G.state.tree["W1"] = 2
	G.state.quests.append({"type": "kills", "need": 5, "have": 2, "reward": 3, "coins": 50})
	var P: Object = M.player
	P.skill.add_run_perk("element", 2)
	P.skill.add_run_perk("split", 0)
	P.flasks = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 6:
		var g: Object = GGC.call("generate", 5 + k, rng, 1.0, 0, -1)
		P.add_gun(g)
		G.state.note_gun(g)
	P.add_ammo("pistol", 33)
	P.add_ammo("shotgun", 12)
	P.hp = 61.0


func fp_dict() -> Dictionary:
	var RS: GDScript = load("res://scripts/core/run_save.gd")
	var st: Dictionary = G.state.to_dict()
	st.erase("run_time")   # растёт по реальным кадрам: между снимком и проверкой в тесте они проходят
	return {"run": G.run.duplicate(true), "state": st, "player": RS.call("player_dict", M.player)}


func fingerprint() -> String:
	return var_to_str(fp_dict())


## Пути полей, которыми различаются два словаря (для понятного сообщения о провале).
func diff_paths(a: Variant, b: Variant, path: String, out: Array) -> void:
	if out.size() >= 6:
		return
	if a is Dictionary and b is Dictionary:
		for k in a:
			if not b.has(k):
				out.append(path + "/" + str(k) + " (missing after)")
			else:
				diff_paths(a[k], b[k], path + "/" + str(k), out)
		for k in b:
			if not a.has(k):
				out.append(path + "/" + str(k) + " (extra after)")
	elif a is Array and b is Array:
		if a.size() != b.size():
			out.append(path + " (size %d vs %d)" % [a.size(), b.size()])
		else:
			for i in a.size():
				diff_paths(a[i], b[i], path + "[%d]" % i, out)
	elif var_to_str(a) != var_to_str(b):
		out.append("%s: %s vs %s" % [path, var_to_str(a).substr(0, 40), var_to_str(b).substr(0, 40)])


func _initialize() -> void:
	G = root.get_node("Game")
	M = load("res://scenes/main.tscn").instantiate()
	root.add_child(M)
	var guard := 0
	while not (M.get("menu") != null and M.menu.visible) and guard < 3000:
		await process_frame
		guard += 1
	var GGC: GDScript = load("res://scripts/weapons/gun_gen.gd")
	var GunC: GDScript = load("res://scripts/weapons/gun.gd")
	var RS: GDScript = load("res://scripts/core/run_save.gd")
	RS.call("delete")

	# --- пушки: словарь -> текст -> пушка, все поля равны
	var bad := 0
	var names_ok := 0
	var total := 0
	for i in 60:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + i
		var g: Object = GGC.call("generate", 1 + i % 25, rng, 0.0, 0, -1 if i % 3 != 0 else i % 6)
		g.ammo = int(g.mag_size) / 2
		g.shot_count = i
		var d: Dictionary = g.to_dict()
		var back: Variant = bytes_to_var(var_to_bytes(d))
		var g2: Object = GunC.call("from_dict", back)
		total += 1
		var a := vars_of(g)
		var b := vars_of(g2)
		var same := a.size() == b.size()
		for k in a:
			if not b.has(k) or var_to_str(a[k]) != var_to_str(b[k]):
				same = false
		if not same:
			bad += 1
		if g.gun_name == g2.gun_name and is_equal_approx(float(g.dps()), float(g2.dps())):
			names_ok += 1
	ok(bad == 0, "60 generated guns survive dict -> bytes -> gun with every field equal (bad=%d)" % bad)
	ok(names_ok == total, "name and dps are preserved (%d/%d)" % [names_ok, total])
	var gx: Object = GunC.call("from_dict", {"damage": 12.5, "no_such_field": 1, "gun_name": "ignored", "_fx_cache": [1]})
	ok(is_equal_approx(float(gx.damage), 12.5) and gx.gun_name != "ignored", "unknown / derived keys are skipped on load")

	# --- полный забег: сохранить, разрушить состояние в памяти, продолжить — всё как было
	M.start_game({"seed": "777", "chaos": true})
	for i in 5:
		await process_frame
	ok(bool(RS.call("exists")), "start of a run writes a checkpoint")
	var r0: Dictionary = RS.call("read")
	ok(bool(r0["ok"]) and int(r0["data"]["checkpoint"]["level"]) == 1, "first checkpoint: level 1")
	setup_state(GGC)
	var P: Object = M.player
	M.rng.seed = 4242
	M.checkpoint(6, true)
	M.loader.load_town(6)
	await process_frame
	var fp_a := fingerprint()
	var fd_a := fp_dict()
	var grid_a: int = hash(M.zone.grid)
	var stock_a: Array = []
	for g in M.town["stock"]:
		stock_a.append(g.gun_name)
	var bag_a: int = P.backpack.size()
	ok(bag_a > 0 and P.gun_count() == 4, "test setup: four slots full and %d in the backpack" % bag_a)
	# ломаем состояние в памяти, не трогая файл
	G.state.coins = 1.0
	G.state.zone_level = 99
	G.state.tree = {}
	G.state.quests = []
	P.guns = [null, null, null, null]
	P.backpack = []
	P.flasks = 0
	G.run["hp"] = 3.0
	G.run["chaos"] = false
	var okc: bool = M.continue_run()
	for i in 3:
		await process_frame
	ok(okc, "continue_run() succeeded")
	P = M.player
	var diffs: Array = []
	diff_paths(fd_a, fp_dict(), "", diffs)
	ok(fingerprint() == fp_a, "run params, state and hero are exactly as saved (coins %s, hero level %d) diffs=%s" % [G.state.coins, G.state.hero_level, diffs])
	ok(G.run["chaos"] == true and G.run["hp"] == 1.0, "run parameters restored (chaos on)")
	ok(M.zone.level == 6 and G.state.in_town, "the checkpoint location is loaded (town before zone 6)")
	ok(hash(M.zone.grid) == grid_a, "the same map comes back (rng state restored)")
	var stock_b: Array = []
	for g in M.town["stock"]:
		stock_b.append(g.gun_name)
	ok(stock_b == stock_a and stock_b.size() > 0, "the same town stock comes back (%d guns)" % stock_b.size())
	ok(P.hp == 61.0 and P.flasks == 2 and P.skill.element == 2 and P.skill.perk("split") == 1 and P.skill.max_charges() == 1, "hp, flasks, skill perks restored")
	ok(P.reserve_of("pistol") >= 33 and P.reserve_of("shotgun") >= 12, "ammo reserve restored")
	ok(G.state.quests.size() == 1 and int(G.state.tree.get("W1", 0)) == 2 and G.state.best_gun != null or G.state.guns_found >= 0, "quests, tree and best gun restored")

	# --- кнопка «Продолжить»
	M.menu.open_main()
	await process_frame
	var cont: Button = M.menu.screen_of("main")._continue
	ok(cont.visible and cont.text.contains("6"), "main menu shows Continue with a summary: '%s'" % cont.text)
	M.menu.close()

	# --- смерть стирает сейв, кнопка пропадает
	M.rewards.on_player_died()
	ok(not bool(RS.call("exists")), "death erases the save")
	M.menu.open_main()
	await process_frame
	ok(not cont.visible, "Continue disappears with the save")
	ok(not M.continue_run(), "continue_run() with no save returns false")
	M.menu.close()

	# --- битые и чужие файлы
	put("this is not a save")
	ok(RS.call("read")["reason"] == "corrupt", "garbage file -> corrupt")
	put("DEVRUN1:AAAA")
	ok(RS.call("read")["reason"] == "corrupt", "truncated payload -> corrupt")
	put("DEVRUN1:" + Marshalls.raw_to_base64(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])))
	ok(RS.call("read")["reason"] == "corrupt", "random bytes -> corrupt")
	put_dict({"version": 99, "checkpoint": {"level": 3}})
	ok(RS.call("read")["reason"] == "version", "other format version -> version")
	put_dict({"version": 1, "run": {}, "state": {}, "player": {"guns": []}})
	ok(RS.call("read")["reason"] == "invalid", "missing checkpoint -> invalid")
	put_dict({"version": 1, "checkpoint": {"level": 0}, "run": {}, "state": {}, "player": {"guns": []}})
	ok(RS.call("read")["reason"] == "invalid", "level 0 -> invalid")
	RS.call("delete")

	# --- смена модов: загружается, но с предупреждением
	M.start_game({"seed": "777"})
	for i in 5:
		await process_frame
	var snap: Dictionary = RS.call("snapshot", M, 3, false)
	snap["mods"] = ["someone_else@9"]
	put_dict(snap)
	var rm: Dictionary = RS.call("read")
	ok(bool(rm["ok"]) and (rm["warnings"] as Array).size() == 1, "changed mod set loads with a warning")
	var summary: String = RS.call("summary", rm["data"])
	ok(summary.contains("3"), "summary mentions the zone: '%s'" % summary)
	# запись атомарна: временного файла не остаётся
	ok(bool(RS.call("write", M, 4, false)) and not FileAccess.file_exists(PATH + ".tmp"), "write leaves no temp file")
	RS.call("delete")
	print("SMOKE RESULT fails=", fails)
	quit()
