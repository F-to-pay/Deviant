extends SceneTree
## Юнит-проверки ядра: сохранение (круговой обход реального user://deviant.cfg во временный файл — сам он не меняется),
## профиль, настройки, баланс, правила забега, состояние забега. Свежие объекты, без записи на диск.
## Запуск: godot --headless --path . -s res://tests/unit_core.gd   (в конце «SMOKE RESULT fails=0»)
## После добавления нового class_name сначала один раз: godot --headless --path . --import
## Классы грузятся через load(): в режиме -s скрипт компилируется раньше, чем регистрируются автозагрузки.

var fails := 0


func ok(cond: bool, what: String) -> void:
	print("SMOKE ", "ok   " if cond else "FAIL ", what)
	if not cond:
		fails += 1


func _initialize() -> void:
	await process_frame
	var G: Node = root.get_node("Game")
	var SaveC: GDScript = load("res://scripts/core/save.gd")
	var ProfileC: GDScript = load("res://scripts/core/profile.gd")
	var SettingsC: GDScript = load("res://scripts/core/settings.gd")
	var BalanceC: GDScript = load("res://scripts/core/balance.gd")
	var RunConfigC: GDScript = load("res://scripts/core/run_config.gd")
	var RunStateC: GDScript = load("res://scripts/core/run_state.gd")

	# --- Save: пишем свежие объекты со своими значениями во временный файл, читаем в другие объекты, пишем снова — файлы совпадают
	var tmp1 := ProjectSettings.globalize_path("user://_test_roundtrip1.cfg")
	var tmp2 := ProjectSettings.globalize_path("user://_test_roundtrip2.cfg")
	var p: RefCounted = ProfileC.new()
	var s: RefCounted = SettingsC.new()
	p.set("meta_coins", 41)
	p.set("best_zone", 12)
	p.set("best_kills", 345)
	p.set("best_rating", 6789)
	p.set("hero", "engineer")
	p.set("heroes_open", ["pioneer", "engineer", "mod_hero"])
	(p.get("custom") as Dictionary)["hp"] = 1.2
	(p.get("custom") as Dictionary)["seed"] = "abc"
	s.call("set_value", "shake", 0.25)
	s.call("set_value", "language", "ru")
	SaveC.call("write", p, s, "user://_test_roundtrip1.cfg")
	var p2: RefCounted = ProfileC.new()
	var s2: RefCounted = SettingsC.new()
	SaveC.call("read", p2, s2, "user://_test_roundtrip1.cfg")
	SaveC.call("write", p2, s2, "user://_test_roundtrip2.cfg")
	var a := FileAccess.get_file_as_string(tmp1)
	var b := FileAccess.get_file_as_string(tmp2)
	ok(a == b and a.length() > 100, "save roundtrip is byte-identical (%d bytes)" % a.length())
	ok(int(p2.get("meta_coins")) == 41 and int(p2.get("best_zone")) == 12 and str(p2.get("hero")) == "engineer", "profile fields survive the roundtrip")
	ok("mod_hero" in (p2.get("heroes_open") as Array), "unknown (mod) hero id stays unlocked after reading")
	ok(is_equal_approx(float(s2.call("get_value", "shake")), 0.25) and str(s2.call("get_value", "language")) == "ru", "settings survive the roundtrip")
	ok(is_equal_approx(float((p2.get("custom") as Dictionary)["hp"]), 1.2) and str((p2.get("custom") as Dictionary)["seed"]) == "abc", "custom start survives the roundtrip")
	DirAccess.remove_absolute(tmp1)
	DirAccess.remove_absolute(tmp2)

	# --- Profile: правила (без записи на диск — свежий объект без подписчиков)
	var pr: RefCounted = ProfileC.new()
	var fired := [0]
	pr.connect("changed", func() -> void: fired[0] += 1)
	ok(pr.call("hero_unlocked", "pioneer"), "default hero is unlocked")
	ok(not pr.call("hero_unlocked", "engineer"), "engineer locked at start")
	ok(not pr.call("unlock_hero", "engineer"), "cannot unlock engineer without coins")
	pr.call("add_meta", 40)
	ok(pr.call("unlock_hero", "engineer") and pr.get("meta_coins") == 5, "engineer unlocked for 35, 5 coins left")
	ok(pr.call("select_hero", "engineer") and pr.get("hero") == "engineer", "select unlocked hero")
	ok(not pr.call("select_hero", "assassin"), "cannot select a locked hero")
	var rr: Dictionary = pr.call("record_run", 1000, 7, 50, true)
	ok(rr["rating_record"] and rr["zone_record"] and pr.get("best_zone") == 7, "first run sets records")
	rr = pr.call("record_run", 500, 9, 10, false)
	ok(not rr["rating_record"] and not rr["zone_record"] and pr.get("best_zone") == 7, "non-counting run sets no zone record")
	ok(fired[0] >= 5, "profile.changed fired (%d)" % fired[0])

	# --- Settings
	var st: RefCounted = SettingsC.new()
	var ch := []
	st.connect("changed", func(k: String) -> void: ch.append(k))
	st.call("set_value", "shake", 0.5)
	st.call("set_value", "shake", 0.5)
	ok(ch == ["shake"] and is_equal_approx(float(st.call("get_value", "shake")), 0.5), "set_value emits once, ignores same value")
	ok(st.call("get_value", "no_such_key") == null, "unknown setting is null")

	# --- Balance / RunConfig: чистые функции
	ok(is_equal_approx(BalanceC.call("xp_need", 1), 40.0), "xp_need(1) = 40")
	ok(is_equal_approx(BalanceC.call("xp_span", 3, 1.5), float(BalanceC.call("xp_need", 3)) + 0.5 * float(BalanceC.call("xp_need", 4))), "xp_span 1.5 levels")
	ok(is_equal_approx(BalanceC.call("enemy_hp_mult", 5, 1.0), pow(1.2, 4.0)), "enemy_hp_mult(5) = 1.2^4")
	ok(is_equal_approx(BalanceC.call("enemy_hp_mult", 5, 2.0), 2.0 * pow(1.2, 4.0)), "enemy_hp_mult applies run multiplier")
	ok(is_equal_approx(BalanceC.call("enemy_dmg_mult", 11, 0.5), 1.0), "enemy_dmg_mult(11, 0.5) = 2.0 * 0.5")
	ok(BalanceC.call("gun_dmg_mult", 1) == 1.0, "gun_dmg_mult(1) = 1")
	ok(BalanceC.call("money", -5.0) == 0.0 and BalanceC.call("money", 2.6) == 3.0, "money clamps and rounds")
	# одна формула монет за убийство: совпадает с прямыми вызовами при том же сиде
	var ra := RandomNumberGenerator.new()
	var rb := RandomNumberGenerator.new()
	ra.seed = 9
	rb.seed = 9
	ok(is_equal_approx(BalanceC.call("kill_coin_value", 7, 0, ra), BalanceC.call("kill_coins", 7, 0.35, rb)), "kill_coin_value(normal) = kill_coins(0.35)")
	ra.seed = 9
	rb.seed = 9
	ok(is_equal_approx(BalanceC.call("kill_coin_value", 10, 3, ra), BalanceC.call("coins_for", 10, 30.0, rb)), "stage boss pays 30 base")
	ra.seed = 9
	rb.seed = 9
	ok(is_equal_approx(BalanceC.call("kill_coin_value", 11, 3, ra), BalanceC.call("coins_for", 11, 15.0, rb)), "wandering boss pays 15 base")
	var DirectorC: GDScript = load("res://scripts/systems/director.gd")
	ok(is_equal_approx(DirectorC.call("zone_xp", 3), BalanceC.call("xp_span", 3, 1.5)), "Director.zone_xp = xp_span(L, 1.5)")
	var d: Dictionary = RunConfigC.get("DEFAULTS").duplicate()
	ok(RunConfigC.call("counts_for_records", d), "defaults count for records")
	d["chaos"] = true
	ok(not RunConfigC.call("counts_for_records", d), "chaos does not count")
	ok(is_equal_approx(RunConfigC.call("rating_mult", d), 1.25), "chaos rating bonus x1.25")
	ok(RunConfigC.call("town_before", RunConfigC.get("DEFAULTS"), 1) and RunConfigC.call("town_before", RunConfigC.get("DEFAULTS"), 6) and not RunConfigC.call("town_before", RunConfigC.get("DEFAULTS"), 3), "town before zones 1, 6, not 3")
	ok(RunConfigC.call("is_boss_zone", 10) and not RunConfigC.call("is_boss_zone", 11), "boss zones")
	ok(RunConfigC.call("seed_from", "123") == 123 and RunConfigC.call("seed_from", "abc") == hash("abc"), "seed_from")

	# --- RunState
	var rs: RefCounted = RunStateC.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	rs.call("reset", rng)
	ok(rs.get("coins") == 120.0 and rs.get("hero_level") == 1, "reset: 120 coins, level 1")
	(rs.get("quests") as Array).append({"type": "kills"})
	rs.call("reset", rng)
	ok((rs.get("quests") as Array).is_empty(), "reset clears the Guild contracts (RunState.quests)")
	var ups: int = rs.call("gain_xp", 130.0)
	ok(ups == 2 and rs.get("hero_level") == 3 and is_equal_approx(float(rs.get("xp")), 130.0 - 40.0 - float(BalanceC.call("xp_need", 2))), "gain_xp 130 -> 2 levels")
	ok(rs.call("gain_xp", -500.0) == 0 and float(rs.get("xp")) < 0.0 and rs.get("hero_level") == 3, "negative xp (debt) does not drop the level")
	rs.set("zone_level", 3)
	rs.set("kills", 10)
	rs.set("bosses", 1)
	ok(rs.call("points") == 200 + 10 + 250, "points = zones + kills + bosses")
	ok(rs.call("rating", RunConfigC.get("DEFAULTS")) == 460, "rating at defaults")
	rs.call("add_coins", 1.0e305)
	ok(float(rs.get("coins")) == 1.0e300, "coins capped at MONEY_MAX")

	# --- живой Game: рейтинг и согласованность
	ok(G.state != null and G.profile != null and G.settings != null, "Game exposes state/profile/settings")
	print("SMOKE RESULT fails=", fails)
	quit()
