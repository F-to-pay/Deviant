extends SceneTree
## Таблицы врагов и героев: все поля с точными типами и порядок записей (от него зависит выбор по сидированному rng), плюс то, что
## из них считается: описания навыков, предложения Мистика, выбор типа врага и состав пака по уровням. При переносе таблиц из кода
## в JSON вывод до и после должен совпасть построчно. Запуск: godot --headless --path . -s res://tests/data_tables.gd

func tbl(path: String, name: String) -> Variant:
	var sc: GDScript = load(path)
	var consts: Dictionary = sc.get_script_constant_map()
	return consts[name] if consts.has(name) else sc.get(name)


func plain(d: Dictionary) -> String:
	var out := {}
	for k in d:
		if str(k).begins_with("_"):
			continue   # служебные поля слоёв (_root)
		out[k] = d[k]
	var keys: Array = out.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s=%s" % [k, var_to_str(out[k])])
	return " ".join(parts)


func _initialize() -> void:
	await process_frame
	var G: Node = root.get_node("Game")
	var ED := "res://scripts/entities/enemy_data.gd"
	var HR := "res://scripts/entities/heroes.gd"
	var types: Dictionary = tbl(ED, "TYPES")
	print("SMOKE enemy order: ", types.keys())
	for k in types:
		print("SMOKE enemy ", k, ": ", plain(types[k]))
	var aff: Dictionary = tbl(ED, "AFFIXES")
	print("SMOKE affixes: ", aff)
	var list: Dictionary = tbl(HR, "LIST")
	var order: Array = tbl(HR, "ORDER")
	print("SMOKE hero order: ", order, " default=", tbl(HR, "DEFAULT"), " list keys=", list.keys())
	for k in list:
		print("SMOKE hero ", k, ": ", plain(list[k]))
	var perks: Dictionary = tbl(HR, "PERKS")
	print("SMOKE perk order: ", perks.keys())
	for k in perks:
		print("SMOKE perk ", k, ": ", plain(perks[k]))
	print("SMOKE elements: ", tbl(HR, "ELEMENTS"))
	var H: GDScript = load(HR)
	for h in order:
		print("SMOKE describe ", h, ": ", H.call("describe", h), " | ", H.call("hero_name", h), " | ", H.call("color", h))
		for pid in perks:
			print("SMOKE   perk ", pid, " fits=", H.call("perk_fits", pid, h), " open0=", H.call("perk_open", pid, h, 0), " open1=", H.call("perk_open", pid, h, 1),
				" name='", H.call("perk_name", pid, h), "' d0='", str(H.call("perk_desc", pid, 0)).substr(0, 30), "' d1='", str(H.call("perk_desc", pid, 1)).substr(0, 30), "'")
		var rng := RandomNumberGenerator.new()
		rng.seed = 17
		print("SMOKE offer ", h, ": ", H.call("perk_offer", h, {"hand": 1}, rng, 3), " ", H.call("perk_offer", h, {}, rng, 5))
	print("SMOKE get_hero(unknown) keys: ", (H.call("get_hero", "nope") as Dictionary).get("name"))
	var E: GDScript = load(ED)
	for chaos in [false, true]:
		G.run["chaos"] = chaos
		for level in [1, 2, 3, 4, 6, 8, 12, 30]:
			var rng := RandomNumberGenerator.new()
			rng.seed = 100 + level
			var picks: Array = []
			for i in 12:
				picks.append(E.call("pick_type", level, rng))
			var packs: Array = []
			for i in 4:
				var pk: Dictionary = E.call("roll_pack", level, rng, 1.6)
				packs.append("%s:%d:%d:%d" % [str(pk.get("members", [])), int(pk.get("elite", 0)), int(pk.get("affixes", 0)), 1 if pk.has("boss") else 0])
			print("SMOKE chaos=", chaos, " L", level, " picks=", picks, " packs=", packs)
	G.run["chaos"] = false
	print("SMOKE DONE")
	quit()
