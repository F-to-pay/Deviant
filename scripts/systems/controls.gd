class_name Controls
extends Node
## Единая точка ввода для игрока: клавиатура+мышь, геймпад и сенсор.
## mode — чем играли последним ("kbm" / "pad" / "touch"); от него зависят прицел, подсказки
## с названиями кнопок, курсор и экранные стики. Переключается само по первому же событию.
##  Прицел: мышь — точка под курсором; геймпад — правый стик (направление и дальность по наклону);
##  сенсор — правый экранный стик. Автоприцел (настройка "auto_aim") на геймпаде и сенсоре:
##  если правый стик не трогаешь, а стреляешь — ствол сам смотрит на ближайшего видимого врага.
##  Огонь: действие shoot (ЛКМ, RT) или палец на правом экранном стике / кнопке огня.
##  Автоогонь (настройка "auto_fire", геймпад и сенсор): пока на экране есть видимый враг —
##  стреляем сами и целимся в него (стик вручную по-прежнему важнее).
##  «Стрельба по тапу» (сенсор): палец справа = прицел в точку под пальцем + огонь (touch_target).
##  Движение: действия move_* (клавиши, левый стик, крестовина) + левый экранный стик.

signal mode_changed(mode: String)

const AIM_MIN := 110.0           # дальность прицела геймпада/сенсора при лёгком наклоне
const AIM_MAX := 520.0           # ... и при полном (миномёт падает в эту точку)
const AUTO_RANGE := 760.0        # автоприцел видит врагов не дальше
const PAD_MOTION_MIN := 0.35     # наклон стика, с которого считаем, что взяли геймпад

static var mode := "kbm"
static var touch_move := Vector2.ZERO    # левый экранный стик, длина 0..1
static var touch_aim := Vector2.ZERO     # правый экранный стик
static var touch_fire := false           # палец на правом стике (дальше мёртвой зоны) или на кнопке огня
static var _aim_dir := Vector2.RIGHT
static var _aim_len := 0.6
static var _auto_target: Variant = null  # Vector2 ближайшего врага или null
static var _manual_aim := false          # в этом кадре прицел ведётся стиком вручную
static var _self: Controls = null
static var _frame := -1                  # кадр, для которого уже посчитан прицел
static var touch_target: Variant = null  # «стрельба по тапу»: мировая точка под пальцем (или null)
static var _visible_target: Variant = null  # ближайший враг на экране в прямой видимости (для автоогня)


func _ready() -> void:
	_self = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		_set_mode("touch")


static func _set_mode(m: String) -> void:
	if m == mode:
		return
	mode = m
	if _self != null:
		_self.mode_changed.emit(m)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_set_mode("touch")
	elif event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			_set_mode("pad")
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > PAD_MOTION_MIN:
			_set_mode("pad")
	elif event is InputEventKey:
		if (event as InputEventKey).pressed:
			_set_mode("kbm")
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		# мышь, сымитированная из касания, — это всё ещё сенсор
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			if event is InputEventMouseButton or (event as InputEventMouseMotion).relative.length() > 2.0:
				_set_mode("kbm")


## Прицел считается один раз за кадр, при первом обращении — порядок узлов не важен.
static func _update_aim() -> void:
	var f := Engine.get_process_frames()
	if f == _frame:
		return
	_frame = f
	_manual_aim = false
	var v := Vector2.ZERO
	if mode == "pad":
		v = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	elif mode == "touch":
		v = touch_aim
	if v.length() > 0.15:
		_aim_dir = v.normalized()
		_aim_len = clampf(v.length(), 0.0, 1.0)
		_manual_aim = true
	_auto_target = null
	_visible_target = null
	if mode == "kbm":
		return
	var auto_fire := bool(Game.setting("auto_fire"))
	if auto_fire:
		_visible_target = _nearest_visible()
	if touch_target != null:
		return   # тап в точку — целимся туда, автоприцел не нужен
	if not _manual_aim:
		if auto_fire and _visible_target != null:
			_auto_target = _visible_target
		elif bool(Game.setting("auto_aim")) and (Input.is_action_pressed("shoot") or touch_fire):
			_auto_target = _nearest_enemy()


## Ближайший живой враг на экране и в прямой видимости (для автоогня), или null.
static func _nearest_visible() -> Variant:
	var main: Main = Game.main
	if main == null or main.player == null or main.player.dead or _self == null:
		return null
	var vp := _self.get_viewport()
	var view := vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	view = view.grow(-20.0)
	var pp := main.player.position
	var best: Variant = null
	var best_d := INF
	for o in main.enemies:
		var e: Enemy = o
		if e.dead or not view.has_point(e.position):
			continue
		var d2 := pp.distance_squared_to(e.position)
		if d2 < best_d and main.zone.ray_clear(pp, e.position):
			best_d = d2
			best = e.position
	return best


## Ближайший живой враг в пределах AUTO_RANGE, лучше — в прямой видимости.
static func _nearest_enemy() -> Variant:
	var main: Main = Game.main
	if main == null or main.player == null or main.player.dead:
		return null
	var pp := main.player.position
	var best: Variant = null
	var best_d := AUTO_RANGE * AUTO_RANGE
	var blind: Variant = null
	var blind_d := AUTO_RANGE * AUTO_RANGE
	for o in main.enemies:
		var e: Enemy = o
		if e.dead:
			continue
		var d2 := pp.distance_squared_to(e.position)
		if d2 >= blind_d and d2 >= best_d:
			continue
		if main.zone.ray_clear(pp, e.position):
			if d2 < best_d:
				best_d = d2
				best = e.position
		elif d2 < blind_d:
			blind_d = d2
			blind = e.position
	return best if best != null else blind


## Куда целится игрок (мировые координаты).
static func aim_world(from: Vector2) -> Vector2:
	if mode == "kbm":
		if _self == null:
			return from + _aim_dir * AIM_MAX
		var vp := _self.get_viewport()
		return vp.get_canvas_transform().affine_inverse() * vp.get_mouse_position()
	_update_aim()
	if touch_target != null:
		return touch_target
	if _auto_target != null:
		return _auto_target
	return from + _aim_dir * lerpf(AIM_MIN, AIM_MAX, _aim_len)


## Направление движения, длина 0..1.
static func move_vector() -> Vector2:
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return (v + touch_move).limit_length(1.0)


## Зажат ли огонь.
static func firing() -> bool:
	if Input.is_action_pressed("shoot") or touch_fire:
		return true
	if mode != "kbm" and bool(Game.setting("auto_fire")):
		_update_aim()
		return _visible_target != null
	return false


## Курсор-прицел на экране: мышь, а на геймпаде и сенсоре — точка прицела.
static func cursor_screen(ci: CanvasItem) -> Vector2:
	if mode == "kbm" or Game.main == null or Game.main.player == null:
		return ci.get_local_mouse_position()
	var w := aim_world(Game.main.player.position)
	return ci.get_global_transform_with_canvas().affine_inverse() * (ci.get_viewport().get_canvas_transform() * w)


## Нажать / отпустить действие так, будто это кнопка (для экранных кнопок): и состояние, и событие.
static func press(action: String, on: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = on
	Input.parse_input_event(ev)


# --- Подписи кнопок для подсказок -------------------------------------------------------

## Подпись действия в текущем режиме: "E" / "Y". На сенсоре — пусто (там подписаны сами кнопки).
static func label(action: String) -> String:
	if mode == "touch":
		return ""
	return InputSetup.action_label(action, "pad" if mode == "pad" else "kb")


## Подпись движения: "WASD" / "LS".
static func move_label() -> String:
	if mode == "pad":
		return "LS"
	var parts := PackedStringArray()
	for a in ["move_up", "move_left", "move_down", "move_right"]:
		parts.append(InputSetup.action_label(a, "kb", 1))
	var s := "".join(parts)
	return s if s.length() == 4 else "/".join(parts)


## Подпись смены оружия: "1-4/Wheel" / "LB/RB".
static func weapons_label() -> String:
	if mode == "pad":
		return InputSetup.action_label("prev_weapon", "pad", 1) + "/" + InputSetup.action_label("next_weapon", "pad", 1)
	return "1-4/" + InputSetup.action_label("next_weapon", "kb", 1)
