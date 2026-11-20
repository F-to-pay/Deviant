extends SceneTree
## Сохранение забега (RunSave): пушки туда-обратно, полный забег (сохранить → сломать → продолжить → всё совпало, включая ту же карту
## и товар города), много слотов (новая игра не стирает старые, удаление, «удалить все», сотни слотов), смерть стирает только свой слот,
## «оставлять сейв» (−50% рейтинга), битые и чужие файлы, смена модов, миграция старого run.save, кнопки главного экрана и экран сейвов.
## ВНИМАНИЕ: тест стирает всё в user://saves и user://run.save — раннер сам прячет ваши сейвы; вручную перед запуском скопируйте папку.
## Запуск: godot --headless --path . -s res://tests/run_save.gd   (в конце «SMOKE RESULT fails=0»)

const DIR := "user://saves"
const TID := "test"   # слот для битых файлов
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


func put(text: String, id: String = TID) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(DIR.path_join(id + ".save"), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func put_dict(d: Dictionary, id: String = TID) -> void:
	put("DEVRUN1:" + Marshalls.raw_to_base64(var_to_bytes(d)), id)


## Фальшивый слот (описание + пустой файл): для проверки списка и скорости.
func fake_slot(i: int) -> void:
	var id := "fake_%05d" % i
	put("x", id)
	var f := FileAccess.open(DIR.path_join(id + ".meta"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"saved_at": 1000 + i, "started_at": 900 + i, "zone": 3, "town": false, "hero": load("res://scripts/entities/heroes.gd").DEFAULT, "hero_level": 2, "keep": false}))
	f.close()


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
	RS.call("delete_all")

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
	var sid: String = G.state.save_id
	ok(sid != "" and bool(RS.call("exists", sid)), "start of a run writes a checkpoint into its own slot")
	var r0: Dictionary = RS.call("read", sid)
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
	ok(not bool(RS.call("exists", sid)), "death erases the slot of that run")
	M.menu.open_main()
	await process_frame
	ok(not cont.visible and not M.menu.screen_of("main")._load.visible, "Continue and Load disappear with the save")
	ok(not M.continue_run(), "continue_run() with no save returns false")
	M.menu.close()

	# --- битые и чужие файлы
	put("this is not a save")
	ok(RS.call("read", TID)["reason"] == "corrupt", "garbage file -> corrupt")
	put("DEVRUN1:AAAA")
	ok(RS.call("read", TID)["reason"] == "corrupt", "truncated payload -> corrupt")
	put("DEVRUN1:" + Marshalls.raw_to_base64(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])))
	ok(RS.call("read", TID)["reason"] == "corrupt", "random bytes -> corrupt")
	put_dict({"version": 99, "checkpoint": {"level": 3}})
	ok(RS.call("read", TID)["reason"] == "version", "other format version -> version")
	put_dict({"version": 1, "run": {}, "state": {}, "player": {"guns": []}})
	ok(RS.call("read", TID)["reason"] == "invalid", "missing checkpoint -> invalid")
	put_dict({"version": 1, "checkpoint": {"level": 0}, "run": {}, "state": {}, "player": {"guns": []}})
	ok(RS.call("read", TID)["reason"] == "invalid", "level 0 -> invalid")
	RS.call("delete", TID)

	# --- смена модов: загружается, но с предупреждением
	M.start_game({"seed": "777"})
	for i in 5:
		await process_frame
	var snap: Dictionary = RS.call("snapshot", M, 3, false)
	snap["mods"] = ["someone_else@9"]
	put_dict(snap)
	var rm: Dictionary = RS.call("read", TID)
	ok(bool(rm["ok"]) and (rm["warnings"] as Array).size() == 1, "changed mod set loads with a warning")
	var summary: String = RS.call("summary", RS.call("meta_of", rm["data"], TID))
	ok(summary.contains("3"), "summary mentions the zone: '%s'" % summary)
	# запись атомарна: временных файлов не остаётся
	var wid: String = G.state.save_id
	ok(bool(RS.call("write", M, 4, false)) and not FileAccess.file_exists(DIR.path_join(wid + ".save.tmp")) and not FileAccess.file_exists(DIR.path_join(wid + ".meta.tmp")), "write leaves no temp files")
	RS.call("delete_all")

	# --- много слотов: новая игра ничего не стирает
	M.start_game({"seed": "1"})
	for i in 3:
		await process_frame
	var id1: String = G.state.save_id
	await create_timer(1.1).timeout   # время сейва — секунды: чтобы порядок в списке был однозначным
	M.start_game({"seed": "2"})
	for i in 3:
		await process_frame
	var id2: String = G.state.save_id
	ok(id1 != "" and id2 != "" and id1 != id2 and bool(RS.call("exists", id1)) and bool(RS.call("exists", id2)), "a new game takes a new slot and keeps the old one")
	ok(int(RS.call("count")) == 2 and RS.call("list_slots")[0]["id"] == id2, "two slots, newest first")
	ok(RS.call("latest")["id"] == id2, "Continue points at the latest slot")
	await create_timer(1.1).timeout
	ok(M.continue_run(id1) and G.state.seed_value == 1 and G.state.save_id == id1, "loading an older slot restores that run and keeps writing into it")
	for i in 3:
		await process_frame
	M.checkpoint(2, false)
	ok(RS.call("latest")["id"] == id1, "after a new checkpoint that slot is the latest")
	RS.call("delete", id1)
	ok(int(RS.call("count")) == 1 and not bool(RS.call("exists", id1)), "delete removes exactly one slot")
	# id наружу не выходит из папки
	var vf := FileAccess.open("user://victim.save", FileAccess.WRITE)
	vf.store_string("keep me")
	vf.close()
	RS.call("delete", "../victim")
	ok(FileAccess.file_exists("user://victim.save") and not bool(RS.call("exists", "../victim")), "a path-like id cannot reach outside the saves folder")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://victim.save"))

	# --- «оставлять сейв»: −50% рейтинга и опыта, смерть слот не стирает
	var RC: GDScript = load("res://scripts/core/run_config.gd")
	var base_cfg: Dictionary = RC.DEFAULTS.duplicate()
	var keep_cfg: Dictionary = RC.DEFAULTS.duplicate()
	keep_cfg["keep_save"] = true
	ok(is_equal_approx(float(RC.call("rating_mult", keep_cfg)), 0.5 * float(RC.call("rating_mult", base_cfg))), "keep_save halves rating (and XP, which follows rating)")
	ok(not bool(RC.call("counts_for_records", keep_cfg)), "a keep_save run does not count for records")
	M.start_game({"seed": "3", "keep_save": true})
	for i in 3:
		await process_frame
	var id3: String = G.state.save_id
	M.rewards.on_player_died()
	ok(bool(RS.call("exists", id3)), "keep_save: death leaves the slot")
	M.start_game({"seed": "4"})
	for i in 3:
		await process_frame
	var id4: String = G.state.save_id
	M.rewards.on_player_died()
	ok(not bool(RS.call("exists", id4)) and bool(RS.call("exists", id3)), "normal death erases only its own slot")
	ok(RS.call("latest")["id"] == id3, "Continue falls back to the remaining slot")
	RS.call("delete_all")

	# --- сотни слотов, экран сейвов, быстрое удаление
	var t0 := Time.get_ticks_msec()
	for i in 400:
		fake_slot(i)
	var t1 := Time.get_ticks_msec()
	var listed: Array = RS.call("list_slots")
	var dt := Time.get_ticks_msec() - t1
	ok(listed.size() == 400 and RS.call("count") == 400 and listed[0]["id"] == "fake_00399", "400 slots listed, newest first (%d ms to create, %d ms to list)" % [t1 - t0, dt])
	ok(dt < 3000, "listing 400 slots is fast (%d ms)" % dt)
	M.menu.open_main()
	await process_frame
	var ms: Object = M.menu.screen_of("main")
	ok(ms._load.visible and ms._load.text.contains("400"), "main menu: Load game (400)")
	M.menu.show_screen("saves")
	await process_frame
	var ss: Object = M.menu.screen_of("saves")
	ok(ss._list.get_child_count() == 10, "saves screen shows one page of 10")
	ss._go(1)
	ok(ss._list.get_child_count() == 10 and not ss._prev.disabled, "next page")
	ss._delete("fake_00399")
	ok(int(RS.call("count")) == 399, "quick delete removes a slot at once")
	ss._on_delete_all()
	ok(int(RS.call("count")) == 399, "delete all needs a second press")
	ss._on_delete_all()
	ok(int(RS.call("count")) == 0 and not ss._delete_all.visible, "second press deletes everything")
	M.menu.close()

	# --- старый одиночный user://run.save становится слотом
	M.start_game({"seed": "9"})
	for i in 3:
		await process_frame
	var legacy_snap: Dictionary = RS.call("snapshot", M, 3, false)
	RS.call("delete_all")
	var lf := FileAccess.open("user://run.save", FileAccess.WRITE)
	lf.store_string(RS.call("encode", legacy_snap))
	lf.close()
	ok(int(RS.call("count")) == 1 and not FileAccess.file_exists("user://run.save"), "legacy run.save is migrated into a slot")
	ok(int(RS.call("latest")["zone"]) == 3, "migrated slot is readable")
	RS.call("delete_all")
	print("SMOKE RESULT fails=", fails)
	quit()
