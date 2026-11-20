extends SceneTree
## Состояние и подписи ввода (`Controls`): режим устройства, подписи кнопок, очередь навыка и выстрела «по отпусканию», тип
## пушки «по отпусканию», движение, прицел в режимах kbm / pad / touch, смена режима по событиям. Печатает значения; при
## переносе состояния ввода (статика -> экземпляр `Game.controls`) вывод должен совпасть построчно.
## Работает до и после переноса: ввод берётся как `Game.controls`, а если его нет — как статический класс.
## Запуск: godot --headless --path . -s res://tests/controls_state.gd   (пользовательский сейв не трогает)

var G: Node
var M: Node
var C: Object
var mode_log: Array = []


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
	C = G.get("controls")
	if C == null:
		C = load("res://scripts/systems/controls.gd")   # до переноса: статический класс
	var node: Node = M.get("controls") if M.get("controls") != null else G.get("controls")
	node.mode_changed.connect(func(m: String) -> void: mode_log.append(m))
	print("SMOKE start mode=", C.get("mode"))
	dump("kbm")
	C.call("_set_mode", "pad")
	dump("pad")
	C.call("_set_mode", "touch")
	dump("touch")
	C.call("_set_mode", "kbm")
	C.call("_set_mode", "kbm")
	print("SMOKE mode_changed log: ", mode_log)

	# очередь навыка и выстрела
	C.call("queue_skill", Vector2(1, 0), 0.5)
	print("SMOKE take_skill: ", C.call("take_skill"), " again: ", C.call("take_skill"))
	print("SMOKE take_shot none: ", C.call("take_shot", true))
	C.call("queue_shot")
	print("SMOKE take_shot not ready: ", C.call("take_shot", false), " ready: ", C.call("take_shot", true), " again: ", C.call("take_shot", true))

	# тип пушки «по отпусканию»
	G.settings.values["touch_release_fire"] = '{"pistol":true,"smg":false}'
	print("SMOKE release_types: ", C.call("release_types"))
	G.settings.values["touch_release_fire"] = "not json"
	print("SMOKE release_types bad json: ", C.call("release_types"))
	G.settings.values["touch_release_fire"] = ""
	print("SMOKE release_types empty: ", C.call("release_types"))
	print("SMOKE release_fire (kbm): ", C.call("release_fire"))

	# движение
	C.set("touch_move", Vector2(3, 4))
	print("SMOKE move_vector: ", C.call("move_vector"))
	C.set("touch_move", Vector2.ZERO)

	# огонь
	print("SMOKE firing idle: ", C.call("firing"))
	C.set("touch_fire", true)
	print("SMOKE firing touch_fire: ", C.call("firing"))
	C.set("touch_fire", false)

	# прицел: kbm (мышь), pad (правый стик, здесь не тронут), touch (правый экранный стик)
	print("SMOKE aim kbm: ", C.call("aim_world", Vector2(100, 100)))
	C.call("_set_mode", "pad")
	await process_frame
	print("SMOKE aim pad idle: ", C.call("aim_world", Vector2(100, 100)))
	C.call("_set_mode", "touch")
	C.set("touch_aim", Vector2(0.5, 0))
	await process_frame
	print("SMOKE aim touch stick 0.5: ", C.call("aim_world", Vector2(100, 100)))
	C.set("touch_aim", Vector2(0, -1))
	await process_frame
	print("SMOKE aim touch stick up: ", C.call("aim_world", Vector2(100, 100)))
	C.set("touch_aim", Vector2.ZERO)
	C.set("touch_target", Vector2(777, 555))
	await process_frame
	print("SMOKE aim touch tap target: ", C.call("aim_world", Vector2(100, 100)))
	C.set("touch_target", null)
	C.set("skill_aim", Vector2(0.3, 0.4))
	print("SMOKE skill_aim: ", C.get("skill_aim"))
	C.set("skill_aim", Vector2.ZERO)
	C.call("_set_mode", "kbm")

	# смена режима по событиям
	mode_log.clear()
	var te := InputEventScreenTouch.new()
	te.pressed = true
	root.push_input(te)
	var jb := InputEventJoypadButton.new()
	jb.pressed = true
	root.push_input(jb)
	var jm := InputEventJoypadMotion.new()
	jm.axis = JOY_AXIS_LEFT_X
	jm.axis_value = 0.1
	root.push_input(jm)   # слабый наклон — режим не меняется
	var ke := InputEventKey.new()
	ke.pressed = true
	ke.keycode = KEY_A
	root.push_input(ke)
	print("SMOKE mode switching by events: ", mode_log, " now=", C.get("mode"))
	print("SMOKE DONE")
	quit()


func dump(tag: String) -> void:
	print("SMOKE [", tag, "] mode=", C.get("mode"), " label(shoot)='", C.call("label", "shoot"), "' label(interact)='", C.call("label", "interact"),
		"' label(dodge)='", C.call("label", "dodge"), "' move='", C.call("move_label"), "' weapons='", C.call("weapons_label"), "'")
