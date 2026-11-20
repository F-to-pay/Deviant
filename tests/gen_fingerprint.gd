extends SceneTree
## Отпечаток генераторов карты и города: для набора уровней и сидов печатает хэш всего словаря зоны (сетка, вход, портал, паки,
## сундуки, лавки, декор, мостовая). Генераторы зависят от порядка бросков rng, поэтому при любой правке ZoneGen / TownGen
## вывод до и после должен совпасть построчно. Запуск: godot --headless --path . -s res://tests/gen_fingerprint.gd

func _initialize() -> void:
	await process_frame
	var G: Node = root.get_node("Game")
	var ZG: GDScript = load("res://scripts/world/zone_gen.gd")
	var TG: GDScript = load("res://scripts/world/town_gen.gd")
	G.state.biome_offset = 3
	var levels := [1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 15, 16, 20, 21, 25, 31, 40, 55, 100]
	var seeds := [1, 2, 3, 7, 42]
	var zone_fail := 0
	for chaos in [false, true]:
		G.run["chaos"] = chaos
		for lvl in levels:
			var line := "SMOKE zone chaos=%s L%d:" % [chaos, lvl]
			for sd in seeds:
				var rng := RandomNumberGenerator.new()
				rng.seed = sd * 1000 + lvl
				var d: Dictionary = ZG.call("generate", lvl, rng)
				if d.is_empty():
					zone_fail += 1
					line += " -"
				else:
					line += " %d" % hash(var_to_str(_plain(d)))
				# состояние rng после генерации тоже часть контракта
				line += "/%d" % (rng.randi() % 100000)
			print(line)
	G.run["chaos"] = false
	for lvl in levels:
		var line := "SMOKE town L%d:" % lvl
		for sd in seeds:
			var rng := RandomNumberGenerator.new()
			rng.seed = sd * 7919 + lvl
			var d: Dictionary = TG.call("generate", lvl, rng)
			if d.is_empty():
				line += " -"
			else:
				line += " %d" % hash(var_to_str(_plain(d)))
			line += "/%d" % (rng.randi() % 100000)
		print(line)
	print("SMOKE zone failures: ", zone_fail)
	print("SMOKE DONE")
	quit()


## Словарь зоны без ссылок на ресурсы (биом — словарь с цветами: оставляем только его имя).
func _plain(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	if out.has("biome") and out["biome"] is Dictionary:
		out["biome"] = str((out["biome"] as Dictionary).get("name", "?"))
	return out
