class_name InventoryUI
extends Control
## Инвентарь (ставит игру на паузу). Слева 4 слота, справа рюкзак, под ним — зоны
## «Выбросить» и «Переработать».
##  Перетаскивание (ЛКМ с зажатием): куда угодно — в слот, в ячейку рюкзака (обмен местами),
##  в зону «Выбросить» или за пределы окна — на землю, в «Переработать» — на патроны.
##  Клик ЛКМ: по слоту — сделать активным, по рюкзаку — взять в активный слот (обмен).
##  ПКМ: слот -> рюкзак, рюкзак -> свободный (или активный) слот. X над пушкой — переработать.
## Рюкзак — плотный массив без дыр: бросок на пустую ячейку кладёт пушку в конец.

const PANEL := Vector2(1060, 640)
const SLOT := Vector2(440, 104)
const CELL := Vector2(126, 100)
const COLS := 4
const DRAG_START := 6.0      # px — дальше это уже перетаскивание, а не клик
const OK_COL := Color(0.4, 1.0, 0.5)
const BAD_COL := Color(1.0, 0.4, 0.35)

var hud: HUD
var hover_kind := ""          # slot / bag / drop / scrap / out / ""
var hover_idx := -1

var _press := false
var _press_pos := Vector2.ZERO
var _src_kind := ""
var _src_idx := -1
var dragging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visibility_changed.connect(_cancel_drag)


func _vp() -> Vector2:
	return get_viewport_rect().size


func _panel() -> Rect2:
	return Rect2((_vp() - PANEL) * 0.5, PANEL)


func _slot_rect(i: int) -> Rect2:
	var pr := _panel()
	return Rect2(pr.position + Vector2(24, 70 + i * (SLOT.y + 14)), SLOT)


func _bag_rect(i: int) -> Rect2:
	var pr := _panel()
	var col := i % COLS
	var row := i / COLS
	return Rect2(pr.position + Vector2(496 + col * (CELL.x + 8), 70 + row * (CELL.y + 10)), CELL)


func _drop_rect() -> Rect2:
	var pr := _panel()
	return Rect2(pr.position + Vector2(496, 418), Vector2(255, 120))


func _scrap_rect() -> Rect2:
	var pr := _panel()
	return Rect2(pr.position + Vector2(496 + 255 + 26, 418), Vector2(255, 120))


func _update_hover(p: Vector2) -> void:
	hover_kind = ""
	hover_idx = -1
	for i in 4:
		if _slot_rect(i).has_point(p):
			hover_kind = "slot"
			hover_idx = i
			return
	for i in Player.BACKPACK_SIZE:
		if _bag_rect(i).has_point(p):
			hover_kind = "bag"
			hover_idx = i
			return
	if _drop_rect().has_point(p):
		hover_kind = "drop"
	elif _scrap_rect().has_point(p):
		hover_kind = "scrap"
	elif not _panel().has_point(p):
		hover_kind = "out"


func _player() -> Player:
	return Game.main.player


## Пушка в позиции (slot/bag + индекс) или null.
func _gun_at(kind: String, idx: int) -> Gun:
	var p := _player()
	if kind == "slot" and idx >= 0 and idx < 4:
		return p.guns[idx]
	if kind == "bag" and idx >= 0 and idx < p.backpack.size():
		return p.backpack[idx]
	return null


func _hovered_gun() -> Gun:
	return _gun_at(hover_kind, hover_idx)


# --- Ввод -----------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_update_hover(mm.position)
		if _press and not dragging and mm.position.distance_to(_press_pos) > DRAG_START:
			dragging = true
			Sfx.ui("ui/grab", -6.0)
		queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_update_hover(mb.position)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _hovered_gun() != null:
					_press = true
					_press_pos = mb.position
					_src_kind = hover_kind
					_src_idx = hover_idx
			elif _press:
				if dragging:
					_drop_on(hover_kind, hover_idx)
				else:
					_click_left()
				_cancel_drag()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not dragging:
			_click_right()
		accept_event()
		queue_redraw()


## X над пушкой — переработать (клавиши сюда не доходят через _gui_input, ловим здесь).
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("scrap"):
		var g: Gun = _gun_at(_src_kind, _src_idx) if dragging else _hovered_gun()
		if g != null:
			if dragging:
				_drop_on("scrap", -1)
				_cancel_drag()
			else:
				_scrap_from(hover_kind, hover_idx)
		get_viewport().set_input_as_handled()
		queue_redraw()


func _cancel_drag() -> void:
	_press = false
	dragging = false
	_src_kind = ""
	_src_idx = -1


func _click_left() -> void:
	var p := _player()
	if _src_kind == "slot":
		p.switch_to(_src_idx)
	elif _src_kind == "bag":
		_move_bag_to_slot(_src_idx, p.active)


func _click_right() -> void:
	var p := _player()
	if hover_kind == "slot" and _gun_at("slot", hover_idx) != null:
		_move_slot_to_bag(hover_idx, p.backpack.size())
	elif hover_kind == "bag" and _gun_at("bag", hover_idx) != null:
		var target := p.active
		for i in 4:
			if p.guns[i] == null:
				target = i
				break
		_move_bag_to_slot(hover_idx, target)


# --- Перекладывание ---------------------------------------------------------------

func _drop_on(kind: String, idx: int) -> void:
	var p := _player()
	if _gun_at(_src_kind, _src_idx) == null:
		return
	match kind:
		"slot":
			if _src_kind == "slot":
				_swap_slots(_src_idx, idx)
			else:
				_move_bag_to_slot(_src_idx, idx)
		"bag":
			if _src_kind == "slot":
				_move_slot_to_bag(_src_idx, idx)
			else:
				_move_in_bag(_src_idx, idx)
		"drop", "out":
			_throw_from(_src_kind, _src_idx)
			Sfx.ui("ui/put", -6.0, 0.75)
		"scrap":
			_scrap_from(_src_kind, _src_idx)
	if kind in ["slot", "bag"]:
		Sfx.ui("ui/put", -6.0)
	p.queue_redraw()


func _swap_slots(a: int, b: int) -> void:
	var p := _player()
	if a == b:
		return
	var tmp: Variant = p.guns[a]
	p.guns[a] = p.guns[b]
	p.guns[b] = tmp
	# активной остаётся та же пушка
	if p.active == a:
		p.active = b
	elif p.active == b:
		p.active = a
	p.on_gun_changed()


func _move_bag_to_slot(bi: int, si: int) -> void:
	var p := _player()
	var g: Gun = p.backpack[bi]
	var old: Variant = p.guns[si]
	p.guns[si] = g
	if old != null:
		p.backpack[bi] = old
	else:
		p.backpack.remove_at(bi)
	p.on_gun_changed()


## bi >= размера рюкзака — в конец. Если там пушка — обмен (она уходит в слот).
func _move_slot_to_bag(si: int, bi: int) -> void:
	var p := _player()
	var g: Gun = p.guns[si]
	if bi < p.backpack.size():
		p.guns[si] = p.backpack[bi]
		p.backpack[bi] = g
		p.on_gun_changed()
		return
	if p.gun_count() <= 1:
		_last_gun_msg()
		return
	if p.backpack.size() >= Player.BACKPACK_SIZE:
		Game.say(U.t("Рюкзак полон."), BAD_COL)
		Sfx.ui("ui/error", -6.0)
		return
	p.backpack.append(g)
	p.guns[si] = null
	p.on_gun_changed()


func _move_in_bag(from: int, to: int) -> void:
	var p := _player()
	to = mini(to, p.backpack.size() - 1)
	if from == to:
		return
	var g: Variant = p.backpack[from]
	p.backpack.remove_at(from)
	p.backpack.insert(to, g)


## Убрать пушку из инвентаря (для выброса/переработки). null — нельзя (последняя в руках).
func _take(kind: String, idx: int) -> Gun:
	var p := _player()
	var g := _gun_at(kind, idx)
	if g == null:
		return null
	if kind == "slot":
		if p.gun_count() <= 1:
			_last_gun_msg()
			return null
		p.guns[idx] = null
		p.on_gun_changed()
	else:
		p.backpack.remove_at(idx)
	return g


func _throw_from(kind: String, idx: int) -> void:
	var g := _take(kind, idx)
	if g != null:
		var p := _player()
		Game.main.drop_gun(g, p.position + p.aim * 26.0, true)


func _scrap_from(kind: String, idx: int) -> void:
	var g := _take(kind, idx)
	if g != null:
		_player().scrap(g)


func _last_gun_msg() -> void:
	Game.say(U.t("Последнюю пушку не отдам. Ты что, голыми руками?"), BAD_COL)
	Sfx.ui("ui/error", -6.0)


## Сколько патронов даст переработка (та же формула, что в Player.scrap, с учётом места в запасе).
func _scrap_preview(g: Gun) -> int:
	var p := _player()
	var t := g.ammo_type()
	var n := g.ammo + ceili(float(GunData.base_mag(t)) * (0.75 + 0.25 * float(g.rarity)))
	return mini(n, maxi(0, GunData.ammo_cap(t) - p.reserve_of(t)))


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


# --- Отрисовка -------------------------------------------------------------------

func _draw() -> void:
	var main: Main = Game.main
	if main == null:
		return
	var p: Player = main.player
	var f := U.font()
	var fb := U.font_bold()
	var dg: Gun = _gun_at(_src_kind, _src_idx) if dragging else null
	draw_rect(Rect2(Vector2.ZERO, _vp()), Color(0, 0, 0, 0.65))
	var pr := _panel()
	draw_rect(pr, Color(0.07, 0.07, 0.1, 0.97))
	draw_rect(pr, Color(0.5, 0.45, 0.7, 0.6), false, 2.0)
	U.draw_text(self, fb, pr.position + Vector2(24, 44), U.t("ИНВЕНТАРЬ"), 26, Color.WHITE)
	U.draw_text(self, f, pr.position + Vector2(496, 44), U.t("Рюкзак %d/%d") % [p.backpack.size(), Player.BACKPACK_SIZE], 18, Color(0.8, 0.8, 0.85))

	for i in 4:
		var r := _slot_rect(i)
		var g: Gun = p.guns[i]
		var hov := hover_kind == "slot" and hover_idx == i
		var is_src := dragging and _src_kind == "slot" and _src_idx == i
		draw_rect(r, Color(1, 1, 1, 0.08 if hov else 0.04))
		if hov and dg != null:
			draw_rect(r, OK_COL, false, 2.0)
		elif i == p.active:
			draw_rect(r, Color(1, 1, 1, 0.9), false, 2.0)
		U.draw_text(self, fb, r.position + Vector2(10, 22), str(i + 1), 16, Color(1, 1, 1, 0.6))
		if g == null:
			U.draw_text(self, f, r.position + Vector2(40, 58), U.t("пусто"), 16, Color(1, 1, 1, 0.3))
			continue
		if is_src:
			modulate_src(r)
			continue
		var rc := g.rarity_color()
		draw_rect(Rect2(r.position, Vector2(5, r.size.y)), rc)
		var sc := clampf(130.0 / maxf(60.0, float(g.vis.get("len", 80.0))), 0.6, 1.5)
		GunIcon.draw_gun(self, g, r.position + Vector2(95, 58), sc, 0.0, false, true)
		draw_multiline_string(fb, r.position + Vector2(180, 30), g.gun_name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 190, 15, 2, rc)
		U.draw_text(self, f, r.position + Vector2(180, 74), U.t("%s · ур. %d") % [g.type_name(), g.level], 13, Color(0.75, 0.75, 0.8))
		U.draw_text(self, f, r.position + Vector2(180, 94), U.t("Урон/с: %s   Маг: %d/%d   Запас: %s") % [U.fmt(g.dps()), g.ammo, g.mag_size, "∞" if g.free_ammo else str(p.reserve_of(g.ammo_type()))], 13, Color(0.9, 0.9, 0.9))

	for i in Player.BACKPACK_SIZE:
		var r := _bag_rect(i)
		var hov := hover_kind == "bag" and hover_idx == i
		draw_rect(r, Color(1, 1, 1, 0.08 if hov else 0.035))
		if hov and dg != null:
			draw_rect(r, OK_COL, false, 2.0)
		if i >= p.backpack.size():
			continue
		if dragging and _src_kind == "bag" and _src_idx == i:
			modulate_src(r)
			continue
		var g: Gun = p.backpack[i]
		var rc := g.rarity_color()
		if not (hov and dg != null):
			draw_rect(r, Color(rc, 0.85), false, 2.0)
		var sc := clampf(100.0 / maxf(60.0, float(g.vis.get("len", 80.0))), 0.45, 1.2)
		GunIcon.draw_gun(self, g, r.get_center() + Vector2(0, -10), sc, 0.0, false, true)
		U.draw_text_c(self, f, r.get_center() + Vector2(0, 34), U.fmt(g.dps()) + U.t(" у/с"), 13, Color(0.9, 0.9, 0.9), 2)
		if g.dps() > (p.gun().dps() if p.gun() != null else 0.0):
			draw_colored_polygon(PackedVector2Array([r.end + Vector2(-16, -8), r.end + Vector2(-6, -8), r.end + Vector2(-11, -16)]),
				Color(0.35, 1.0, 0.45))

	# Зоны: выбросить / переработать
	var preview: Gun = dg if dg != null else _hovered_gun()
	_zone(_drop_rect(), U.t("Выбросить"), U.t("перетащи сюда или за окно"), Color(1.0, 0.75, 0.35),
		hover_kind in ["drop", "out"] and dg != null, f, fb)
	var scrap_sub := U.t("перетащи сюда или нажми [X]")
	if preview != null:
		scrap_sub = U.t("+%d патр. (%s)") % [_scrap_preview(preview), preview.ammo_name()]
	_zone(_scrap_rect(), U.t("Переработать"), scrap_sub, GunData.AMMO_COL.get(preview.ammo_type(), OK_COL) if preview != null else OK_COL,
		hover_kind == "scrap" and dg != null, f, fb)

	U.draw_text_c(self, f, Vector2(pr.get_center().x, pr.end.y - 18),
		U.t("Перетаскивай пушки мышью · ЛКМ — выбрать / взять в руки · ПКМ — слот ↔ рюкзак · X — переработать · Tab/Esc — закрыть"),
		14, Color(0.75, 0.75, 0.8))

	if dg != null:
		# пушка «в руке» под курсором
		var m := get_local_mouse_position()
		var sc := clampf(120.0 / maxf(60.0, float(dg.vis.get("len", 80.0))), 0.5, 1.4)
		GunIcon.draw_gun(self, dg, m + Vector2(0, -6), sc, 0.0, false, true)
		var hint := ""
		var hc := Color.WHITE
		if hover_kind in ["drop", "out"]:
			hint = U.t("выбросить")
			hc = Color(1.0, 0.75, 0.35)
		elif hover_kind == "scrap":
			hint = U.t("переработать")
			hc = OK_COL
		if hint != "":
			U.draw_text_c(self, fb, m + Vector2(0, 34), hint, 15, hc, 3)
		return

	# Карточка под курсором
	var hg := _hovered_gun()
	if hg != null:
		var m := get_local_mouse_position()
		var ch := GunCard.height(hg)
		var cx := m.x + 24.0
		if cx + GunCard.W > _vp().x - 10.0:
			cx = m.x - GunCard.W - 24.0
		var cy := clampf(m.y - ch * 0.3, 10.0, _vp().y - ch - 10.0)
		GunCard.draw_card(self, hg, Vector2(cx, cy), p.gun() if hg != p.gun() else null)


## Место, откуда тащим: пустая рамка-пунктир.
func modulate_src(r: Rect2) -> void:
	draw_rect(r.grow(-4.0), Color(1, 1, 1, 0.25), false, 1.5)


func _zone(r: Rect2, title: String, sub: String, col: Color, active: bool, f: Font, fb: Font) -> void:
	draw_rect(r, Color(col, 0.16 if active else 0.05))
	draw_rect(r, Color(col, 0.95 if active else 0.4), false, 3.0 if active else 1.5)
	U.draw_text_c(self, fb, r.get_center() + Vector2(0, -4), title, 20, Color(col, 1.0 if active else 0.8), 3)
	U.draw_text_c(self, f, r.get_center() + Vector2(0, 22), sub, 13, Color(0.8, 0.8, 0.85), 2)
