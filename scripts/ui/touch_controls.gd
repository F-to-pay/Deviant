class_name TouchControls
extends CanvasLayer
## Экранное управление для телефона/планшета.
##  Левая часть экрана — плавающий стик бега (где коснулся, там и стик).
##  Правая часть — стик прицела: отклонил — целишься и стреляешь.
##  С автоприцелом (настройка auto_aim) правый стик стреляет сразу, как коснулся, и сам
##  целится в ближайшего врага; отклонишь — целишься вручную.
##  Кнопки: рывок, перезарядка, смена пушки, инвентарь, пауза; рядом с пушкой на земле —
##  «Взять / Заменить / Разобрать», у сундука — «Открыть», на экране смерти — «Ещё раз / В меню».
## Кнопки нажимают обычные действия (Controls.press), так что игра не отличает их от клавиатуры.
## Пока экранные кнопки активны, Godot не имитирует мышь из касаний (иначе любое касание = ЛКМ = огонь);
## в меню и инвентаре имитация включена — там пальцем жмут обычные кнопки.

const STICK_R := 115.0
const BTN_R := 54.0
const SMALL_R := 40.0
const PILL := Vector2(190, 64)
const DEAD := 0.25
const COL := Color(1, 1, 1, 0.55)
const COL_DIM := Color(1, 1, 1, 0.18)
const ACCENT := Color(1.0, 0.55, 0.2)

var _root: Control
var _touches := {}           # индекс пальца -> {"role": "move"/"aim"/"btn", "base": Vector2, "pos": Vector2, "action": String}
var _was_active := false


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.draw.connect(_draw_ui)


func _scale() -> float:
	return clampf(float(Game.setting("touch_scale")), 0.5, 2.0)


func _vp() -> Vector2:
	return _root.get_viewport_rect().size


## Показывать ли экранные кнопки вообще (настройка + чем играют).
func _enabled() -> bool:
	match str(Game.setting("touch_controls")):
		"on":
			return true
		"off":
			return false
	return Controls.mode == "touch"


## Идёт ли игра (а не меню / инвентарь / пауза), где кнопки работают.
func _in_game() -> bool:
	var main: Main = Game.main
	if main == null or not main.hud.visible or main.menu.visible:
		return false
	if main.hud.inv.visible:
		return false
	return true


func _active() -> bool:
	return _enabled() and _in_game()


func _process(_delta: float) -> void:
	var act := _active()
	if act != _was_active:
		_was_active = act
		if not act:
			_release_all()
	# пока кнопки на экране — касание не превращается в ЛКМ (а то любой тап — выстрел)
	Input.emulate_mouse_from_touch = not act
	_root.visible = act
	if act:
		_root.queue_redraw()


func _release_all() -> void:
	for i in _touches:
		var t: Dictionary = _touches[i]
		if str(t["role"]) == "btn":
			Controls.press(str(t["action"]), false)
	_touches.clear()
	Controls.touch_move = Vector2.ZERO
	Controls.touch_aim = Vector2.ZERO
	Controls.touch_fire = false


# --- Раскладка ------------------------------------------------------------------------

## Центр правого стика (там же рисуется, когда пальца нет).
func _aim_home() -> Vector2:
	var s := _scale()
	return _vp() - Vector2(240, 240) * s


func _move_home() -> Vector2:
	var s := _scale()
	return Vector2(240 * s, _vp().y - 240 * s)


## Кнопки: [действие, подпись, центр, радиус] — подпись "" рисуется значком.
func _buttons() -> Array:
	var s := _scale()
	var vp := _vp()
	var main: Main = Game.main
	var out: Array = []
	if main.hud.dead_screen:
		if main.hud.death_t > 0.6:
			out.append(["restart", U.t("One more time"), Vector2(vp.x * 0.5 - 130 * s, vp.y - 150 * s), -1.0])
			out.append(["pause", U.t("Main menu"), Vector2(vp.x * 0.5 + 130 * s, vp.y - 150 * s), -1.0])
		return out
	var c := _aim_home()
	var r := 225.0 * s
	out.append(["dodge", U.t("Dodge"), c + Vector2.from_angle(PI) * r, BTN_R * s])
	out.append(["reload", U.t("Reload"), c + Vector2.from_angle(PI * 1.25) * r, BTN_R * s])
	out.append(["next_weapon", "", c + Vector2.from_angle(PI * 1.5) * r, BTN_R * s])
	out.append(["inventory", U.t("Bag"), Vector2(vp.x * 0.5 - 60 * s, 56 * s), SMALL_R * s])
	out.append(["pause", "II", Vector2(vp.x * 0.5 + 60 * s, 56 * s), SMALL_R * s])
	var y := vp.y - 330 * s
	if main.near_item != null and is_instance_valid(main.near_item):
		out.append(["interact", U.t("Take"), Vector2(vp.x * 0.5 - 210 * s, y), -1.0])
		out.append(["swap", U.t("Swap"), Vector2(vp.x * 0.5, y), -1.0])
		out.append(["scrap", U.t("Scrap"), Vector2(vp.x * 0.5 + 210 * s, y), -1.0])
	elif main.near_chest != null and is_instance_valid(main.near_chest):
		out.append(["interact", U.t("Open"), Vector2(vp.x * 0.5, y), -1.0])
	return out


## Кнопка под точкой (радиус -1 — «пилюля» PILL), или [].
func _button_at(p: Vector2) -> Array:
	var s := _scale()
	for b in _buttons():
		var r := float(b[3])
		var c: Vector2 = b[2]
		if r < 0.0:
			if Rect2(c - PILL * s * 0.5, PILL * s).grow(8.0).has_point(p):
				return b
		elif p.distance_to(c) <= r * 1.2:
			return b
	return []


# --- Касания ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# первое же касание переключает игру на сенсор — и сразу обрабатывается кнопками
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		Controls._set_mode("touch")
	if not _active():
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touch_down(st.index, st.position)
		else:
			_touch_up(st.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touch_move(sd.index, sd.position)
		get_viewport().set_input_as_handled()


func _touch_down(i: int, p: Vector2) -> void:
	var b := _button_at(p)
	if not b.is_empty():
		_touches[i] = {"role": "btn", "action": str(b[0]), "base": p, "pos": p}
		Controls.press(str(b[0]), true)
		Sfx.ui("ui/click", -14.0)
		return
	if p.x < _vp().x * 0.45:
		_touches[i] = {"role": "move", "base": p, "pos": p, "action": ""}
	else:
		_touches[i] = {"role": "aim", "base": p, "pos": p, "action": ""}
		if bool(Game.setting("auto_aim")):
			Controls.touch_fire = true    # автоприцел: стреляем сразу
	_update_sticks()


func _touch_up(i: int) -> void:
	if not _touches.has(i):
		return
	var t: Dictionary = _touches[i]
	_touches.erase(i)
	if str(t["role"]) == "btn":
		Controls.press(str(t["action"]), false)
	_update_sticks()


func _touch_move(i: int, p: Vector2) -> void:
	if not _touches.has(i):
		return
	var t: Dictionary = _touches[i]
	t["pos"] = p
	if str(t["role"]) != "btn":
		# палец ушёл дальше радиуса — стик едет за ним
		var r := STICK_R * _scale()
		var base: Vector2 = t["base"]
		var d := p - base
		if d.length() > r:
			t["base"] = p - d.normalized() * r
	_update_sticks()


func _update_sticks() -> void:
	var mv := Vector2.ZERO
	var aim := Vector2.ZERO
	var aiming := false
	var r := STICK_R * _scale()
	for i in _touches:
		var t: Dictionary = _touches[i]
		var base: Vector2 = t["base"]
		var pos: Vector2 = t["pos"]
		var v := ((pos - base) / r).limit_length(1.0)
		match str(t["role"]):
			"move":
				mv = v if v.length() > 0.1 else Vector2.ZERO
			"aim":
				aiming = true
				aim = v if v.length() > DEAD else Vector2.ZERO
	Controls.touch_move = mv
	Controls.touch_aim = aim
	if bool(Game.setting("auto_aim")):
		Controls.touch_fire = aiming
	else:
		Controls.touch_fire = aim != Vector2.ZERO


# --- Отрисовка -------------------------------------------------------------------------

func _stick_of(role: String) -> Dictionary:
	for i in _touches:
		var t: Dictionary = _touches[i]
		if str(t["role"]) == role:
			return t
	return {}


func _draw_ui() -> void:
	var c := _root
	var s := _scale()
	var main: Main = Game.main
	var fb := U.font_bold()
	if not main.hud.dead_screen:
		var auto := bool(Game.setting("auto_aim"))
		_draw_stick(c, _stick_of("move"), _move_home(), "")
		_draw_stick(c, _stick_of("aim"), _aim_home(), U.t("FIRE") if auto else "")
	var held := {}
	for i in _touches:
		var t: Dictionary = _touches[i]
		if str(t["role"]) == "btn":
			held[str(t["action"])] = true
	for b in _buttons():
		var act := str(b[0])
		var ctr: Vector2 = b[2]
		var r := float(b[3])
		var on := held.has(act)
		var fill := Color(ACCENT, 0.45) if on else Color(0, 0, 0, 0.35)
		if r < 0.0:
			var rect := Rect2(ctr - PILL * s * 0.5, PILL * s)
			c.draw_rect(rect, fill)
			c.draw_rect(rect, COL, false, 2.0)
			U.draw_text_c(c, fb, ctr + Vector2(0, 7), str(b[1]), 20, Color.WHITE, 3)
			continue
		c.draw_circle(ctr, r, fill)
		c.draw_arc(ctr, r, 0.0, TAU, 40, COL, 2.0, true)
		var label := str(b[1])
		if act == "next_weapon":
			label = str(main.player.active + 1) + " »"
		elif act == "dodge" and main.player.dodge_cd > 0.0:
			var k := clampf(main.player.dodge_cd / Player.DODGE_CD, 0.0, 1.0)
			c.draw_arc(ctr, r - 5.0, -PI * 0.5, -PI * 0.5 + TAU * k, 32, Color(ACCENT, 0.9), 5.0)
		U.draw_text_c(c, fb, ctr + Vector2(0, 6), label, 16 if label.length() > 3 else 20, Color.WHITE, 3)


func _draw_stick(c: CanvasItem, t: Dictionary, home: Vector2, text: String) -> void:
	var r := STICK_R * _scale()
	var base: Vector2 = t.get("base", home)
	var pos: Vector2 = t.get("pos", home)
	var knob := base + (pos - base).limit_length(r)
	var touched := not t.is_empty()
	c.draw_circle(base, r, Color(0, 0, 0, 0.22 if touched else 0.12))
	c.draw_arc(base, r, 0.0, TAU, 48, COL if touched else COL_DIM, 2.0, true)
	c.draw_circle(knob, r * 0.42, Color(1, 1, 1, 0.45 if touched else 0.2))
	if text != "":
		U.draw_text_c(c, U.font_bold(), knob + Vector2(0, 6), text, 16, Color.WHITE, 3)
