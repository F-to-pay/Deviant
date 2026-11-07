class_name InputSetup
extends RefCounted
## Раскладка управления создаётся кодом, чтобы не возиться с project.godot.
## Клавиатура — физические клавиши: на русской раскладке WASD тоже работает.
## У каждого действия две колонки привязок: "kb" (клавиатура и мышь) и "pad" (геймпад).
## Переназначенное игроком хранится в настройке "binds" (JSON {действие: {kb: [...], pad: [...]}});
## чего там нет — берётся из DEFAULTS. Меню «Управление» — Menu._build_controls.
## Событие в JSON: {"t": "key", "k": физический код} · {"t": "mouse", "b": кнопка} ·
##   {"t": "jb", "b": кнопка геймпада} · {"t": "ja", "a": ось, "v": -1 или 1}.

## Мёртвая зона стиков для движения и прицела (у остальных действий — 0.5).
const STICK_DEADZONE := 0.2

## Действие -> {kb: [...], pad: [...]}. Ключи — KEY_*, мышь — "m" + номер кнопки,
## геймпад — JOY_BUTTON_* или [ось, направление].
const DEFAULTS := {
	"move_up": {"kb": [KEY_W, KEY_UP], "pad": [[JOY_AXIS_LEFT_Y, -1], JOY_BUTTON_DPAD_UP]},
	"move_down": {"kb": [KEY_S, KEY_DOWN], "pad": [[JOY_AXIS_LEFT_Y, 1], JOY_BUTTON_DPAD_DOWN]},
	"move_left": {"kb": [KEY_A, KEY_LEFT], "pad": [[JOY_AXIS_LEFT_X, -1], JOY_BUTTON_DPAD_LEFT]},
	"move_right": {"kb": [KEY_D, KEY_RIGHT], "pad": [[JOY_AXIS_LEFT_X, 1], JOY_BUTTON_DPAD_RIGHT]},
	"aim_up": {"kb": [], "pad": [[JOY_AXIS_RIGHT_Y, -1]]},
	"aim_down": {"kb": [], "pad": [[JOY_AXIS_RIGHT_Y, 1]]},
	"aim_left": {"kb": [], "pad": [[JOY_AXIS_RIGHT_X, -1]]},
	"aim_right": {"kb": [], "pad": [[JOY_AXIS_RIGHT_X, 1]]},
	"shoot": {"kb": ["m1"], "pad": [[JOY_AXIS_TRIGGER_RIGHT, 1]]},
	"dodge": {"kb": [KEY_SPACE, KEY_SHIFT, "m2"], "pad": [JOY_BUTTON_A, [JOY_AXIS_TRIGGER_LEFT, 1]]},
	"reload": {"kb": [KEY_R], "pad": [JOY_BUTTON_X]},
	"interact": {"kb": [KEY_E], "pad": [JOY_BUTTON_Y]},
	"swap": {"kb": [KEY_F], "pad": [JOY_BUTTON_RIGHT_STICK]},
	"scrap": {"kb": [KEY_X], "pad": [JOY_BUTTON_B]},
	"inventory": {"kb": [KEY_TAB, KEY_I], "pad": [JOY_BUTTON_BACK]},
	"next_weapon": {"kb": ["m5"], "pad": [JOY_BUTTON_RIGHT_SHOULDER]},
	"prev_weapon": {"kb": ["m4"], "pad": [JOY_BUTTON_LEFT_SHOULDER]},
	"last_weapon": {"kb": [KEY_Q], "pad": [JOY_BUTTON_LEFT_STICK]},
	"slot_1": {"kb": [KEY_1], "pad": []},
	"slot_2": {"kb": [KEY_2], "pad": []},
	"slot_3": {"kb": [KEY_3], "pad": []},
	"slot_4": {"kb": [KEY_4], "pad": []},
	"pause": {"kb": [KEY_ESCAPE], "pad": [JOY_BUTTON_START]},
	"restart": {"kb": [KEY_ENTER], "pad": [JOY_BUTTON_A]},
	"debug": {"kb": [KEY_F3], "pad": []},
	"music_down": {"kb": [KEY_MINUS, KEY_KP_SUBTRACT], "pad": []},
	"music_up": {"kb": [KEY_EQUAL, KEY_KP_ADD], "pad": []},
	"music_mute": {"kb": [KEY_M], "pad": []},
	"sfx_down": {"kb": [KEY_BRACKETLEFT], "pad": []},
	"sfx_up": {"kb": [KEY_BRACKETRIGHT], "pad": []},
	"mod_console": {"kb": [KEY_F8], "pad": []},
}

## Что можно переназначить в меню, по порядку: [действие, подпись].
const REBINDABLE := [
	["move_up", "Move up"], ["move_down", "Move down"], ["move_left", "Move left"], ["move_right", "Move right"],
	["aim_up", "Aim up"], ["aim_down", "Aim down"], ["aim_left", "Aim left"], ["aim_right", "Aim right"],
	["shoot", "Shoot"], ["dodge", "Dodge"], ["reload", "Reload"],
	["interact", "Pick up / open"], ["swap", "Swap with current"], ["scrap", "Scrap for ammo"],
	["next_weapon", "Next weapon"], ["prev_weapon", "Previous weapon"], ["last_weapon", "Last weapon"],
	["slot_1", "Weapon 1"], ["slot_2", "Weapon 2"], ["slot_3", "Weapon 3"], ["slot_4", "Weapon 4"],
	["inventory", "Inventory"], ["pause", "Pause"],
]

const PAD_BUTTONS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓",
	JOY_BUTTON_DPAD_LEFT: "D-pad ←", JOY_BUTTON_DPAD_RIGHT: "D-pad →",
	JOY_BUTTON_MISC1: "Share", JOY_BUTTON_PADDLE1: "P1", JOY_BUTTON_PADDLE2: "P2",
	JOY_BUTTON_PADDLE3: "P3", JOY_BUTTON_PADDLE4: "P4", JOY_BUTTON_TOUCHPAD: "Touchpad",
}
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel ↑", MOUSE_BUTTON_WHEEL_DOWN: "Wheel ↓",
	MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_XBUTTON2: "Mouse 5",
}


static func setup() -> void:
	apply({})


## Пересобрать InputMap: DEFAULTS, поверх — переназначенное игроком (из настройки "binds").
static func apply(binds: Dictionary) -> void:
	for action in DEFAULTS:
		var dz := STICK_DEADZONE if (action.begins_with("move_") or action.begins_with("aim_")) else 0.5
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
			InputMap.action_set_deadzone(action, dz)
		else:
			InputMap.add_action(action, dz)
		var b: Dictionary = binds.get(action, {}) if binds.get(action) is Dictionary else {}
		for col in ["kb", "pad"]:
			if b.has(col) and b[col] is Array:
				for d in b[col]:
					var ev := from_dict(d)
					if ev != null:
						InputMap.action_add_event(action, ev)
			else:
				for v in DEFAULTS[action][col]:
					var ev := _default_event(v, col)
					if ev != null:
						InputMap.action_add_event(action, ev)


## Из настройки (JSON-строка).
static func apply_setting(json: String) -> void:
	var v: Variant = JSON.parse_string(json) if json != "" else {}
	apply(v if v is Dictionary else {})


## Значение из DEFAULTS: в колонке "pad" число — кнопка геймпада, в "kb" — клавиша.
static func _default_event(v: Variant, col: String) -> InputEvent:
	if v is int:
		if col == "pad":
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(v)
			return jb
		var k := InputEventKey.new()
		k.physical_keycode = int(v)
		return k
	if v is String and (v as String).begins_with("m"):
		var mb := InputEventMouseButton.new()
		mb.button_index = int((v as String).substr(1))
		return mb
	if v is Array:
		var jm := InputEventJoypadMotion.new()
		jm.axis = int(v[0])
		jm.axis_value = float(v[1])
		return jm
	return null


## События по умолчанию для колонки: kb -> клавиши/мышь, pad -> кнопки/оси.
static func default_events(action: String, col: String) -> Array:
	var out: Array = []
	for v in DEFAULTS.get(action, {}).get(col, []):
		var ev := _default_event(v, col)
		if ev != null:
			out.append(ev)
	return out


# --- Сохранение / загрузка ----------------------------------------------------------

static func to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return {"t": "key", "k": int(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)}
	if ev is InputEventMouseButton:
		return {"t": "mouse", "b": int((ev as InputEventMouseButton).button_index)}
	if ev is InputEventJoypadButton:
		return {"t": "jb", "b": int((ev as InputEventJoypadButton).button_index)}
	if ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		return {"t": "ja", "a": int(jm.axis), "v": 1 if jm.axis_value > 0.0 else -1}
	return {}


static func from_dict(d: Variant) -> InputEvent:
	if not (d is Dictionary):
		return null
	match str(d.get("t", "")):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("k", 0))
			return k
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(d.get("b", 1))
			return mb
		"jb":
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(d.get("b", 0))
			return jb
		"ja":
			var jm := InputEventJoypadMotion.new()
			jm.axis = int(d.get("a", 0))
			jm.axis_value = float(d.get("v", 1))
			return jm
	return null


## События действия из одной колонки: "kb" (клавиатура и мышь) или "pad".
static func events_of(action: String, col: String) -> Array:
	var out: Array = []
	if not InputMap.has_action(action):
		return out
	for ev in InputMap.action_get_events(action):
		if is_col(ev, col):
			out.append(ev)
	return out


static func is_col(ev: InputEvent, col: String) -> bool:
	if col == "pad":
		return ev is InputEventJoypadButton or ev is InputEventJoypadMotion
	return ev is InputEventKey or ev is InputEventMouseButton


## Текущее InputMap для настройки "binds": только действия из REBINDABLE, отличающиеся от умолчания.
static func current_binds() -> Dictionary:
	var out := {}
	for row in REBINDABLE:
		var action := str(row[0])
		var entry := {}
		for col in ["kb", "pad"]:
			var cur: Array = []
			for ev in events_of(action, col):
				cur.append(to_dict(ev))
			var def: Array = []
			for ev in default_events(action, col):
				def.append(to_dict(ev))
			if JSON.stringify(cur) != JSON.stringify(def):
				entry[col] = cur
		if not entry.is_empty():
			out[action] = entry
	return out


## Заменить привязку колонки одним событием (из меню «Управление»). Пустое — очистить колонку.
static func rebind(action: String, col: String, ev: InputEvent) -> void:
	for old in events_of(action, col):
		InputMap.action_erase_event(action, old)
	if ev != null:
		InputMap.action_add_event(action, ev)


# --- Подписи ------------------------------------------------------------------------

## Подпись события: "E", "LMB", "A", "RT", "LS ←".
static func event_name(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode
		if code != KEY_NONE:
			var shown := DisplayServer.keyboard_get_keycode_from_physical(code)
			return OS.get_keycode_string(shown if shown != KEY_NONE else code)
		return OS.get_keycode_string(k.keycode)
	if ev is InputEventMouseButton:
		var b := (ev as InputEventMouseButton).button_index
		return U.t(str(MOUSE_NAMES.get(b, "Mouse %d" % b)))
	if ev is InputEventJoypadButton:
		var jb := (ev as InputEventJoypadButton).button_index
		return str(PAD_BUTTONS.get(jb, "Button %d" % jb))
	if ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		var neg := jm.axis_value < 0.0
		match jm.axis:
			JOY_AXIS_LEFT_X:
				return "LS ←" if neg else "LS →"
			JOY_AXIS_LEFT_Y:
				return "LS ↑" if neg else "LS ↓"
			JOY_AXIS_RIGHT_X:
				return "RS ←" if neg else "RS →"
			JOY_AXIS_RIGHT_Y:
				return "RS ↑" if neg else "RS ↓"
			JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
		return "Axis %d%s" % [jm.axis, "-" if neg else "+"]
	return "?"


## Подпись действия для колонки: первые две привязки через "/" ("Space/Shift"), "—" если пусто.
static func action_label(action: String, col: String, limit: int = 2) -> String:
	var names := PackedStringArray()
	for ev in events_of(action, col):
		var n := event_name(ev)
		if not (n in names):
			names.append(n)
		if names.size() >= limit:
			break
	return "/".join(names) if not names.is_empty() else "—"
