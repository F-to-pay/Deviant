extends SceneTree
## Утечки за время игры: многократная загрузка одной и той же зоны (тот же сид — тот же состав врагов) не должна
## раздувать число объектов, узлов и «сирот» (узлов вне дерева, которые забыли освободить). Рост считаем после прогрева —
## первые загрузки наполняют кэши. Утечка в один узел за зону здесь уже заметна (допуск маленький).
## Запуск: godot --headless --path . -s res://tests/leak_check.gd   (в конце «SMOKE RESULT fails=0»). Пользовательский сейв не трогает.

const ZONES := 40                # сколько раз загрузить зону после прогрева
const WARM := 6                 # прогрев: кэши шейдеров, шрифтов, таблиц
const LEVEL := 8
const MAX_OBJECT_GROWTH := 12   # допустимый рост числа объектов между точками замера (шум счётчиков)
const MAX_NODE_GROWTH := 12

var fails := 0


func ok(cond: bool, what: String) -> void:
	print("SMOKE ", "ok   " if cond else "FAIL ", what)
	if not cond:
		fails += 1


## Снимок счётчиков движка.
func snap() -> Dictionary:
	return {
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}


func _initialize() -> void:
	var M: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(M)
	var guard := 0
	while not (M.get("menu") != null and M.menu.visible) and guard < 3000:
		await process_frame
		guard += 1
	M.start_game({"seed": "777"})
	for i in 5:
		await process_frame
	var base := {}
	for n in WARM + ZONES:
		M.rng.seed = 4242
		M.loader.load_zone(LEVEL)
		await process_frame
		await process_frame
		if n == WARM - 1:
			base = snap()
			print("LEAK base  ", base)
	var last := snap()
	print("LEAK last  ", last)
	ok(int(last["objects"]) - int(base["objects"]) <= MAX_OBJECT_GROWTH,
		"objects after %d zones: %d -> %d" % [ZONES, base["objects"], last["objects"]])
	ok(int(last["nodes"]) - int(base["nodes"]) <= MAX_NODE_GROWTH,
		"nodes after %d zones: %d -> %d" % [ZONES, base["nodes"], last["nodes"]])
	ok(int(last["orphans"]) - int(base["orphans"]) <= 5,
		"orphan nodes after %d zones: %d -> %d" % [ZONES, base["orphans"], last["orphans"]])
	print("SMOKE RESULT fails=", fails)
	quit()
