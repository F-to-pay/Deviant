class_name TouchControls
extends CanvasLayer
## Экранное управление для телефона/планшета.
##  Стик бега и стик прицела: «плавающие» (где коснулся — там и стик) или неподвижные
##  (настройка touch_static — стик хватается только у своего места).
##  Стик прицела: отклонил — целишься и стреляешь. С автоприцелом (auto_aim) стреляет сразу,
##  как коснулся, и сам целится в ближайшего врага.
##  «Стрельба по тапу» (touch_tap_fire): вместо правого стика — палец справа = огонь в точку под ним.
##  Автоогонь (auto_fire) — в Controls: сам стреляет по видимым врагам.
##  Кнопки: рывок, перезарядка, смена пушки, рюкзак, пауза; у пушки на земле — «Взять / Заменить /
##  Разобрать», у сундука — «Открыть», на экране смерти — «Ещё раз / В меню».
## Расположение и размер каждого элемента — редактор (start_edit, кнопка в «Управлении»),
## хранится в настройке touch_layout: {id: {"x": 0..1, "y": 0..1, "s": масштаб}} внутри отступов экрана.
## Кнопки нажимают обычные действия (Controls.press), так что игра не отличает их от клавиатуры.
## Пока кнопки активны, Godot не имитирует мышь из касаний (иначе любое касание = ЛКМ = огонь).

const STICK_R := 115.0
const BTN_R := 54.0
const SMALL_R := 40.0
const PILL := Vector2(190, 64)
const DEAD := 0.25
const GRAB := 1.6               # неподвижный стик хватается в радиусе R × GRAB
const COL := Color(1, 1, 1, 0.55)
const COL_DIM := Color(1, 1, 1, 0.18)
const ACCENT := Color(1.0, 0.55, 0.2)
## Элементы раскладки: id -> [x, y (доли области внутри отступов), базовый радиус, подпись].
## Радиус -1 — «пилюля» (прямоугольная кнопка PILL × масштаб). Пилюли interact/swap/scrap видны в игре,
## только когда рядом пушка (или сундук — тогда interact = «Открыть», лавка — «Говорить»), в редакторе — всегда.
const ELEMENTS := {
	"move": [0.125, 0.78, STICK_R, ""],
	"aim": [0.875, 0.78, STICK_R, ""],
	"dodge": [0.758, 0.78, BTN_R, "Dodge"],
	"skill": [0.712, 0.635, BTN_R, "Skill"],
	"flask": [0.275, 0.88, SMALL_R, ""],
	"reload": [0.792, 0.633, BTN_R, "Reload"],
	"next_weapon": [0.875, 0.572, BTN_R, ""],
	"inventory": [0.465, 0.06, SMALL_R, "Bag"],
	"pause": [0.535, 0.06, SMALL_R, "II"],
	"interact": [0.39, 0.66, -1.0, "Take"],
	"swap": [0.5, 0.66, -1.0, "Swap"],
	"scrap": [0.61, 0.66, -1.0, "Scrap"],
}
const EDIT_TOOLS := ["reset", "done"]

var _root: Control
var _touches := {}           # палец -> {"role": move/aim/tap/btn, "base", "pos" (локально), "vpos" (вьюпорт), "action"}
var _was_active := false
var _layout := {}            # id -> {"x", "y", "s"}
var _editing := false
var _edit_done: Callable
var _sel := ""               # выбранный в редакторе элемент
var _drag := false
var _drag_off := Vector2.ZERO


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.draw.connect(_draw_ui)
	_load_layout()
	Game.settings_changed.connect(_on_setting)
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	UiFit.fit(self, [], [_root])


func _on_setting(key: String) -> void:
	if key in UiFit.KEYS:
		_fit()
	elif key == "touch_layout" and not _editing:
		_load_layout()


# --- Раскладка ---------------------------------------------------------------------------

func _load_layout() -> void:
	_layout = {}
	var v: Variant = JSON.parse_string(str(Game.setting("touch_layout"))) if str(Game.setting("touch_layout")) != "" else {}
	var saved: Dictionary = v if v is Dictionary else {}
	for id in ELEMENTS:
		var d: Array = ELEMENTS[id]
		var e := {"x": float(d[0]), "y": float(d[1]), "s": 1.0}
		if saved.get(id) is Dictionary:
			var sv: Dictionary = saved[id]
			e["x"] = clampf(float(sv.get("x", e["x"])), 0.0, 1.0)
			e["y"] = clampf(float(sv.get("y", e["y"])), 0.0, 1.0)
			e["s"] = clampf(float(sv.get("s", 1.0)), 0.4, 2.5)
		_layout[id] = e


func _save_layout() -> void:
	Game.set_setting("touch_layout", JSON.stringify(_layout))


func _pos(id: String) -> Vector2:
	var e: Dictionary = _layout[id]
	return Vector2(float(e["x"]), float(e["y"])) * _root.size


func _radius(id: String) -> float:
	return float(ELEMENTS[id][2]) * float(_layout[id]["s"]) * _gscale()


func _gscale() -> float:
	return clampf(float(Game.setting("touch_scale")), 0.5, 2.0)


func _tap_fire() -> bool:
	return bool(Game.setting("touch_tap_fire"))


# --- Когда показывать --------------------------------------------------------------------

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
	return not main.hud.inv.visible


func _active() -> bool:
	return not _editing and _enabled() and _in_game()


func _process(_delta: float) -> void:
	var act := _active()
	if act != _was_active:
		_was_active = act
		if not act:
			_release_all()
	# пока кнопки на экране — касание не превращается в ЛКМ (а то любой тап — выстрел)
	Input.emulate_mouse_from_touch = not act
	_root.visible = act or _editing
	if act:
		_update_tap_targets()
	if _root.visible:
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
	Controls.touch_target = null


# --- Кнопки ----------------------------------------------------------------------------

## Кнопки: [действие, подпись, центр, радиус] — отрицательный радиус у «пилюль»: -масштаб.
func _buttons() -> Array:
	var s := _gscale()
	var vp := _root.size
	var main: Main = Game.main
	var out: Array = []
	if main.hud.dead_screen:
		if main.hud.death_t > 0.6:
			out.append(["restart", U.t("One more time"), Vector2(vp.x * 0.5 - 130 * s, vp.y - 150 * s), -s])
			out.append(["pause", U.t("Main menu"), Vector2(vp.x * 0.5 + 130 * s, vp.y - 150 * s), -s])
		return out
	for id in ["dodge", "skill", "flask", "reload", "next_weapon", "inventory", "pause"]:
		out.append([id, _label_of(id), _pos(id), _radius(id)])
	if main.near_item != null and is_instance_valid(main.near_item):
		for id in ["interact", "swap", "scrap"]:
			out.append([id, _label_of(id), _pos(id), _radius(id)])
	elif main.near_chest != null and is_instance_valid(main.near_chest):
		out.append(["interact", U.t("Open"), _pos("interact"), _radius("interact")])
	elif main.near_reset:
		out.append(["interact", U.t("Restart"), _pos("interact"), _radius("interact")])
	elif main.near_stall != null and is_instance_valid(main.near_stall):
		out.append(["interact", U.t("Close") if main.hud.stall == main.near_stall else U.t("Talk"), _pos("interact"), _radius("interact")])
	return out


func _label_of(id: String) -> String:
	var l := str(ELEMENTS[id][3])
	return l if l == "II" or l == "" else U.t(l)


## Прямоугольник «пилюли» с масштабом k.
func _pill(ctr: Vector2, k: float) -> Rect2:
	return Rect2(ctr - PILL * k * 0.5, PILL * k)


## Попадает ли точка в кнопку [.., центр, радиус].
func _hits(c: Vector2, r: float, p: Vector2, slack: float = 1.2) -> bool:
	if r < 0.0:
		return _pill(c, -r).grow(8.0).has_point(p)
	return p.distance_to(c) <= r * slack


func _button_at(p: Vector2) -> Array:
	for b in _buttons():
		if _hits(b[2], float(b[3]), p):
			return b
	return []


# --- Касания в игре ---------------------------------------------------------------------

func _local(vpos: Vector2) -> Vector2:
	return _root.get_global_transform_with_canvas().affine_inverse() * vpos


func _input(event: InputEvent) -> void:
	if _editing:
		_edit_input(event)
		return
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


func _touch_down(i: int, vpos: Vector2) -> void:
	var p := _local(vpos)
	var b := _button_at(p)
	if not b.is_empty():
		_touches[i] = {"role": "btn", "action": str(b[0]), "base": p, "pos": p, "vpos": vpos}
		Controls.press(str(b[0]), true)
		Sfx.ui("ui/click", -14.0)
		return
	var role := ""
	var base := p
	if bool(Game.setting("touch_static")):
		if p.distance_to(_pos("move")) <= _radius("move") * GRAB:
			role = "move"
			base = _pos("move")
		elif not _tap_fire() and p.distance_to(_pos("aim")) <= _radius("aim") * GRAB:
			role = "aim"
			base = _pos("aim")
		elif _tap_fire() and p.x >= _root.size.x * 0.45:
			role = "tap"
	else:
		if p.x < _root.size.x * 0.45:
			role = "move"
		else:
			role = "tap" if _tap_fire() else "aim"
	if role == "":
		return
	_touches[i] = {"role": role, "base": base, "pos": p, "vpos": vpos, "action": ""}
	_update_sticks()


func _touch_up(i: int) -> void:
	if not _touches.has(i):
		return
	var t: Dictionary = _touches[i]
	_touches.erase(i)
	if str(t["role"]) == "btn":
		Controls.press(str(t["action"]), false)
	elif str(t["role"]) == "aim" and Controls.release_fire():
		# «стрельба по отпусканию»: отпустил отклонённый стик — один выстрел туда, куда он смотрел
		var base: Vector2 = t["base"]
		var pos: Vector2 = t["pos"]
		if ((pos - base) / _radius("aim")).length() > DEAD:
			Controls.queue_shot()
	_update_sticks()


func _touch_move(i: int, vpos: Vector2) -> void:
	if not _touches.has(i):
		return
	var t: Dictionary = _touches[i]
	var p := _local(vpos)
	t["pos"] = p
	t["vpos"] = vpos
	var role := str(t["role"])
	if (role == "move" or role == "aim") and not bool(Game.setting("touch_static")):
		# палец ушёл дальше радиуса — плавающий стик едет за ним
		var r := _radius(role)
		var base: Vector2 = t["base"]
		var d := p - base
		if d.length() > r:
			t["base"] = p - d.normalized() * r
	_update_sticks()


## «Стрельба по тапу»: мировая точка под пальцем — каждый кадр (камера едет за игроком).
func _update_tap_targets() -> void:
	var target: Variant = null
	for i in _touches:
		var t: Dictionary = _touches[i]
		if str(t["role"]) == "tap":
			var vpos: Vector2 = t["vpos"]
			target = get_viewport().get_canvas_transform().affine_inverse() * vpos
	Controls.touch_target = target


func _update_sticks() -> void:
	var mv := Vector2.ZERO
	var aim := Vector2.ZERO
	var aiming := false
	var tapping := false
	for i in _touches:
		var t: Dictionary = _touches[i]
		var role := str(t["role"])
		if role == "tap":
			tapping = true
			continue
		if role != "move" and role != "aim":
			continue
		var base: Vector2 = t["base"]
		var pos: Vector2 = t["pos"]
		var v := ((pos - base) / _radius(role)).limit_length(1.0)
		if role == "move":
			mv = v if v.length() > 0.1 else Vector2.ZERO
		else:
			aiming = true
			aim = v if v.length() > DEAD else Vector2.ZERO
	Controls.touch_move = mv
	Controls.touch_aim = aim
	if Controls.release_fire():
		Controls.touch_fire = tapping   # стиком только целимся, выстрел — при отпускании (_touch_up)
	elif bool(Game.setting("auto_aim")):
		Controls.touch_fire = aiming or tapping
	else:
		Controls.touch_fire = aim != Vector2.ZERO or tapping
	_update_tap_targets()


# --- Редактор раскладки ------------------------------------------------------------------

## Открыть редактор (из «Настройки» → «Управление»); done — что сделать по «Готово».
func start_edit(done: Callable) -> void:
	_release_all()
	_editing = true
	_edit_done = done
	_sel = ""
	_drag = false


func _end_edit() -> void:
	_editing = false
	_drag = false
	_save_layout()
	Sfx.ui("ui/click", -6.0)
	if _edit_done.is_valid():
		_edit_done.call()


func _edit_ids() -> Array:
	var out: Array = []
	for id in ELEMENTS:
		if id == "aim" and _tap_fire():
			continue
		out.append(id)
	return out


## Панель редактора: [инструмент, подпись, прямоугольник]. «−» и «+» — рядом с выбранной кнопкой.
func _tools() -> Array:
	var out: Array = []
	var w := 170.0
	var x0 := _root.size.x * 0.5 - (w + 12.0)
	var names := {"reset": U.t("Reset"), "done": U.t("Done")}
	for k in EDIT_TOOLS.size():
		out.append([EDIT_TOOLS[k], str(names[EDIT_TOOLS[k]]), Rect2(x0 + k * (w + 12.0), _root.size.y * 0.42, w, 64)])
	if _sel != "":
		var p := _pos(_sel)
		var r := _radius(_sel)
		var half := (PILL.y * -r * 0.5) if r < 0.0 else r
		var bw := 84.0
		# под кнопкой, а если не влезает — над ней
		var y := p.y + half + 18.0
		if y + 64.0 > _root.size.y:
			y = p.y - half - 18.0 - 64.0
		var x := clampf(p.x - bw - 60.0, 0.0, _root.size.x - bw * 2.0 - 120.0)
		out.append(["smaller", "−", Rect2(x, y, bw, 64)])
		out.append(["size", "%d%%" % roundi(float(_layout[_sel]["s"]) * 100.0), Rect2(x + bw, y, 120, 64)])
		out.append(["bigger", "+", Rect2(x + bw + 120.0, y, bw, 64)])
	return out


func _edit_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_end_edit()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		var p := _local(mb.position)
		get_viewport().set_input_as_handled()
		if not mb.pressed:
			if _drag:
				_drag = false
				_save_layout()
			return
		for tl in _tools():
			if (tl[2] as Rect2).has_point(p):
				_tool(str(tl[0]))
				return
		_sel = ""
		var ids := _edit_ids()
		for k in range(ids.size() - 1, -1, -1):
			var id := str(ids[k])
			if _hits(_pos(id), _radius(id), p, 1.15):
				_sel = id
				_drag = true
				_drag_off = _pos(id) - p
				Sfx.ui("ui/grab", -8.0)
				return
	elif event is InputEventMouseMotion and _drag and _sel != "":
		var p := _local((event as InputEventMouseMotion).position) + _drag_off
		var sz := _root.size
		_layout[_sel]["x"] = clampf(p.x / sz.x, 0.0, 1.0)
		_layout[_sel]["y"] = clampf(p.y / sz.y, 0.0, 1.0)
		get_viewport().set_input_as_handled()


func _tool(t: String) -> void:
	Sfx.ui("ui/click", -6.0)
	match t:
		"smaller", "bigger":
			if _sel != "":
				var e: Dictionary = _layout[_sel]
				e["s"] = clampf(float(e["s"]) + (0.1 if t == "bigger" else -0.1), 0.4, 2.5)
				_save_layout()
		"size":
			pass
		"reset":
			Game.set_setting("touch_layout", "")
			_load_layout()
			_sel = ""
		"done":
			_end_edit()


# --- Отрисовка -------------------------------------------------------------------------

func _stick_of(role: String) -> Dictionary:
	for i in _touches:
		var t: Dictionary = _touches[i]
		if str(t["role"]) == role:
			return t
	return {}


func _draw_ui() -> void:
	if _editing:
		_draw_editor()
		return
	var c := _root
	var s := _gscale()
	var main: Main = Game.main
	var fb := U.font_bold()
	if not main.hud.dead_screen:
		var auto := bool(Game.setting("auto_aim"))
		_draw_stick(c, _stick_of("move"), _pos("move"), _radius("move"), "")
		if not _tap_fire():
			_draw_stick(c, _stick_of("aim"), _pos("aim"), _radius("aim"), U.t("FIRE") if auto else "")
		var tap := _stick_of("tap")
		if not tap.is_empty():
			var tp: Vector2 = tap["pos"]
			c.draw_arc(tp, 34.0 * s, 0.0, TAU, 32, Color(ACCENT, 0.8), 3.0, true)
	var held := {}
	for i in _touches:
		var t: Dictionary = _touches[i]
		if str(t["role"]) == "btn":
			held[str(t["action"])] = true
	for b in _buttons():
		_draw_button(c, b, held.has(str(b[0])), fb, s)


func _draw_button(c: CanvasItem, b: Array, on: bool, fb: Font, _s: float) -> void:
	var main: Main = Game.main
	var act := str(b[0])
	var ctr: Vector2 = b[2]
	var r := float(b[3])
	var fill := Color(ACCENT, 0.45) if on else Color(0, 0, 0, 0.35)
	if r < 0.0:
		var rect := _pill(ctr, -r)
		c.draw_rect(rect, fill)
		c.draw_rect(rect, COL, false, 2.0)
		U.draw_text_c(c, fb, ctr + Vector2(0, 7), str(b[1]), 20 if -r >= 0.8 else 16, Color.WHITE, 3)
		return
	c.draw_circle(ctr, r, fill)
	c.draw_arc(ctr, r, 0.0, TAU, 40, COL, 2.0, true)
	var label := str(b[1])
	if act == "next_weapon":
		label = str(main.player.active + 1) + " »"
	elif act == "dodge" and main.player.dodge_cd > 0.0 and not _editing:
		var k := clampf(main.player.dodge_cd / main.player.dodge_max_cd(), 0.0, 1.0)
		c.draw_arc(ctr, r - 5.0, -PI * 0.5, -PI * 0.5 + TAU * k, 32, Color(ACCENT, 0.9), 5.0)
	elif act == "flask":
		FlaskDrop.draw_icon(c, ctr + Vector2(0, 2), r / 22.0, 1.0 if main.player.flasks > 0 or _editing else 0.0)
		label = ""
		if not _editing:
			U.draw_text_c(c, fb, ctr + Vector2(r * 0.55, r * 0.75), str(main.player.flasks), 16, Color.WHITE, 3)
	elif act == "skill" and not _editing:
		var hc := Heroes.color(main.player.hero)
		if main.player.skill_charges <= 0:
			var k := clampf(main.player.skill_cd / main.player.skill_max_cd(), 0.0, 1.0)
			c.draw_arc(ctr, r - 5.0, -PI * 0.5, -PI * 0.5 + TAU * k, 32, Color(hc, 0.9), 5.0)
		else:
			c.draw_arc(ctr, r - 4.0, 0.0, TAU, 32, Color(hc, 0.6), 3.0)
	U.draw_text_c(c, fb, ctr + Vector2(0, 6), label, 16 if label.length() > 3 else 20, Color.WHITE, 3)


func _draw_stick(c: CanvasItem, t: Dictionary, home: Vector2, r: float, text: String) -> void:
	var base: Vector2 = t.get("base", home)
	var pos: Vector2 = t.get("pos", home)
	var knob := base + (pos - base).limit_length(r)
	var touched := not t.is_empty()
	c.draw_circle(base, r, Color(0, 0, 0, 0.22 if touched else 0.12))
	c.draw_arc(base, r, 0.0, TAU, 48, COL if touched else COL_DIM, 2.0, true)
	c.draw_circle(knob, r * 0.42, Color(1, 1, 1, 0.45 if touched else 0.2))
	if text != "":
		U.draw_text_c(c, U.font_bold(), knob + Vector2(0, 6), text, 16, Color.WHITE, 3)


func _draw_editor() -> void:
	var c := _root
	var fb := U.font_bold()
	var s := _gscale()
	var big := Rect2(-_root.position - Vector2(64, 64), get_viewport().get_visible_rect().size / scale + Vector2(128, 128))
	c.draw_rect(big, Color(0, 0, 0, 0.55))
	# граница области (внутри отступов от краёв экрана)
	c.draw_rect(Rect2(Vector2.ZERO, _root.size), Color(1, 1, 1, 0.25), false, 2.0)
	U.draw_text_c(c, fb, Vector2(_root.size.x * 0.5, _root.size.y * 0.32),
		U.t("Drag the controls. Tap one, then − / + next to it to change its size."), 20, Color.WHITE, 3)
	for id in _edit_ids():
		var p := _pos(id)
		var r := _radius(id)
		if id == "move" or id == "aim":
			_draw_stick(c, {}, p, r, "")
		else:
			_draw_button(c, [id, _label_of(id), p, r], false, fb, s)
		if id == _sel:
			if r < 0.0:
				c.draw_rect(_pill(p, -r).grow(6.0), ACCENT, false, 4.0)
			else:
				c.draw_arc(p, r + 8.0, 0.0, TAU, 48, ACCENT, 4.0, true)
	for tl in _tools():
		var rect: Rect2 = tl[2]
		var plain: bool = tl[0] == "size"
		c.draw_rect(rect, Color(0, 0, 0, 0.35 if plain else 0.7))
		if not plain:
			c.draw_rect(rect, Color(1, 1, 1, 0.7), false, 2.0)
		U.draw_text_c(c, fb, rect.get_center() + Vector2(0, 8), str(tl[1]), 20, Color(1, 1, 1), 3)
