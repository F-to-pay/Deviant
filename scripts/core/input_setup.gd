class_name InputSetup
extends RefCounted
## Раскладка управления создаётся кодом, чтобы не возиться с project.godot.
## Используются физические клавиши — на русской раскладке WASD тоже работает.


static func setup() -> void:
	_key("move_up", [KEY_W, KEY_UP])
	_key("move_down", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("dodge", [KEY_SPACE, KEY_SHIFT])
	_mouse("dodge", MOUSE_BUTTON_RIGHT)
	_mouse("shoot", MOUSE_BUTTON_LEFT)
	_key("reload", [KEY_R])
	_key("interact", [KEY_E])
	_key("swap", [KEY_F])
	_key("scrap", [KEY_X])
	_key("inventory", [KEY_TAB, KEY_I])
	_key("slot_1", [KEY_1])
	_key("slot_2", [KEY_2])
	_key("slot_3", [KEY_3])
	_key("slot_4", [KEY_4])
	_key("last_weapon", [KEY_Q])
	_mouse("next_weapon", MOUSE_BUTTON_WHEEL_DOWN)
	_mouse("prev_weapon", MOUSE_BUTTON_WHEEL_UP)
	_key("pause", [KEY_ESCAPE])
	_key("restart", [KEY_ENTER])
	_key("debug", [KEY_F3])
	_key("music_down", [KEY_MINUS, KEY_KP_SUBTRACT])
	_key("music_up", [KEY_EQUAL, KEY_KP_ADD])
	_key("music_mute", [KEY_M])
	_key("sfx_down", [KEY_BRACKETLEFT])
	_key("sfx_up", [KEY_BRACKETRIGHT])
	_key("mod_console", [KEY_F8])


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


static func _key(action: String, keys: Array) -> void:
	_ensure(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


static func _mouse(action: String, button: MouseButton) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
