class_name Menu
extends CanvasLayer
## Главное меню, пауза и экраны лавок: оболочка. Что именно на экране — решают экраны (`ui/screens/*.gd`, основа
## `MenuScreen`), общие виджеты и цвета — `MenuKit`. Здесь: навигация, режимы, жизненный цикл, перестройка при смене языка.
## Режимы: "main" — главное меню (фон MenuBg), "pause" — поверх игры (затемнение),
## "town" — экран, открытый лавкой в городе (герои, настраиваемый старт): «Назад» возвращает в игру.
## Экран настроек общий, «Назад» возвращает в текущий режим.
##
## Новый экран: класс-наследник `MenuScreen` в `ui/screens/`, создать в `_make_screens()`, построить в `build()`
## через `_screen(root, "id")`, открыть `show_screen("id")` (из лавки — `open_town("id")`).

var mode := "main"
var current := ""
var bg: MenuBg
var dim: ColorRect
var cursor: CursorDraw
var screens := {}         # id экрана -> корневой Control (показывается и прячется)
var panels := {}          # id -> PanelContainer-рамка (цвет полосы меняет дерево навыков по ветке)
var first_focus := {}     # id -> кнопка, получающая фокус
var logic := {}           # id -> MenuScreen, который обслуживает экран
var _all: Array = []      # все экраны в порядке построения
var _main: MainScreen
var _pause: PauseScreen
var _town_sub := {}       # экран лавки -> Label с репликой торговца
var _town_coins := {}     # экран лавки -> Label с монетами
var _root: Control
var _refit_pending := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_screens()
	_build_ui()
	visible = false
	Game.settings.changed.connect(_on_setting)
	Game.controls.mode_changed.connect(_on_input_mode)
	get_viewport().size_changed.connect(_fit)


## Экраны создаются один раз и живут, пока живо меню: их состояние (страница справочника, выбранная пушка Мастерской)
## переживает перестройку при смене языка. Порядок важен: «Управление» берёт ползунки из «Настроек».
func _make_screens() -> void:
	_main = MainScreen.new(self)
	_pause = PauseScreen.new(self)
	_all = [_main, CustomScreen.new(self), HeroesScreen.new(self), TreeScreen.new(self), ShopScreen.new(self),
		MysticScreen.new(self), WorkshopScreen.new(self), GuildScreen.new(self), HealerScreen.new(self),
		SettingsScreen.new(self), _pause, ModsScreen.new(self), CodexScreen.new(self), ControlsScreen.new(self),
		ReleaseScreen.new(self)]


## Экран по id (например, "settings"), null — если такого нет.
func screen_of(id: String) -> MenuScreen:
	return logic.get(id)


## Сменили устройство: подсказки паузы — под него; на геймпаде фокус нужен на кнопке.
func _on_input_mode(m: String) -> void:
	if not visible:
		return
	for s in _all:
		(s as MenuScreen).on_input_mode(m)
	if m == "pad" and get_viewport().gui_get_focus_owner() == null:
		var b: Control = first_focus.get(current)
		if b != null:
			b.grab_focus()


## Весь UI строится заново при смене языка — так переводятся и форматированные подписи.
func _build_ui() -> void:
	var root := Control.new()
	_root = root
	root.theme = MenuKit.make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# переводим сами через U.t — авто-перевод Godot отключаем, чтобы не было двойного
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg = MenuBg.new()
	root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # клики не проходят в игру
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in _all:
		(s as MenuScreen).build(root)
	cursor = CursorDraw.new()
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cursor)
	cursor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fit()


## Масштаб и отступы (UiFit): фон — на весь экран, экраны меню — внутри отступов.
func _fit() -> void:
	_refit_pending = false
	if _root == null:
		return
	UiFit.fit(self, [_root], [])
	for k in screens:
		UiFit.inset(screens[k])


func _on_setting(key: String) -> void:
	if key == "language":
		rebuild.call_deferred()
	elif key in UiFit.KEYS:
		# пока тянешь ползунок размера — не перестраиваем (меню уехало бы из-под мыши)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_refit_pending = true
		else:
			_fit()


## Перестроить все экраны (смена языка, включение модов).
func rebuild() -> void:
	var was := current
	remove_child(_root)
	_root.queue_free()
	screens.clear()
	panels.clear()
	first_focus.clear()
	logic.clear()
	_town_sub.clear()
	_town_coins.clear()
	_build_ui()
	bg.visible = mode == "main"
	dim.visible = mode == "pause"
	for s in _all:
		(s as MenuScreen).after_rebuild()
	show_screen(was if was != "" else mode)


func lang_text() -> String:
	return U.t("Language") + ": " + I18n.lang_name(I18n.current())


## Следующий язык из найденных в lang/ (игра + моды).
func cycle_lang() -> void:
	var codes := I18n.available()
	var i := codes.find(I18n.current())
	Game.settings.set_value("language", str(codes[(i + 1) % codes.size()]))


# --- Открытие / закрытие --------------------------------------------------------

func open_main() -> void:
	mode = "main"
	visible = true
	bg.visible = true
	dim.visible = false
	_main.refresh_records()
	show_screen("main")


func open_pause() -> void:
	mode = "pause"
	visible = true
	bg.visible = false
	dim.visible = true
	_pause.on_pause_open()
	show_screen("pause")


func close() -> void:
	visible = false


## Экран меню из лавки в городе: игра на паузе, «Назад» / Esc — обратно в город.
## line — реплика торговца (подпись под заголовком), col — её цвет.
func open_town(sname: String, line: String = "", col: Color = MenuKit.DIM) -> void:
	var sub: Label = _town_sub.get(sname)
	if sub != null:
		sub.text = "«%s»" % line if line != "" else ""
		sub.add_theme_color_override("font_color", col.lightened(0.2))
	for s in _all:
		(s as MenuScreen).on_town_open(sname)
	mode = "town"
	visible = true
	bg.visible = false
	dim.visible = true
	get_tree().paused = true
	Game.main.music.set_muffled(true)
	Sfx.ui("ui/open", -8.0)
	show_screen(sname)


func close_town() -> void:
	visible = false
	mode = "pause"
	get_tree().paused = false
	Game.main.music.set_muffled(false)
	Sfx.ui("ui/close", -8.0)


## «Назад» с экрана: в город, если пришли из лавки, иначе на экран режима.
func back() -> void:
	if mode == "town":
		close_town()
	else:
		show_screen(mode)


func show_screen(sname: String) -> void:
	current = sname
	for k in screens:
		(screens[k] as Control).visible = k == sname
	var s: MenuScreen = logic.get(sname)
	if s != null:
		s.refresh(sname)
	var b: Control = first_focus.get(sname)
	if b != null:
		b.grab_focus.call_deferred()


func _process(delta: float) -> void:
	if visible:
		cursor.queue_redraw()
	if _refit_pending and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_fit()
	var s: MenuScreen = logic.get(current)
	if s != null:
		s.process(delta)


## Пока экран ждёт нажатия (переназначение клавиш) — событие уходит ему раньше всех.
## Геймпад без фокуса: первое нажатие ставит фокус на кнопку экрана, иначе A/B/крестовине некуда идти.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var s: MenuScreen = logic.get(current)
	if s != null and s.captures_input():
		s.handle_input(event)
		return
	if (event is InputEventJoypadButton and event.is_pressed()) or \
			(event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		if get_viewport().gui_get_focus_owner() == null:
			var fb: Control = first_focus.get(current)
			if fb != null and fb.is_visible_in_tree():
				fb.grab_focus()
				get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		var s: MenuScreen = logic.get(current)
		if s != null and s.captures_input():
			return   # в меню «Управление» ждём кнопку — Esc/B тоже можно назначить
		if s != null and s.on_back():
			pass   # экран обработал сам (например, «Настраиваемый старт» сохраняет выбор)
		elif mode == "town":
			close_town()
		elif s != null and s.back_target() != "":
			show_screen(s.back_target())
		elif current != mode:
			show_screen(mode)
		elif mode == "pause":
			Game.main.hud.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("skill_tree") and current.begins_with("tree_"):
		back()   # та же клавиша закрывает дерево
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") or event.is_action_pressed("debug"):
		get_viewport().set_input_as_handled()


# --- Для экранов ------------------------------------------------------------------

## Заголовок лавки: название, реплика торговца (подставляется при открытии), монеты.
func town_head(box: VBoxContainer, sname: String, title: String) -> void:
	box.add_child(MenuKit.label(title, 48, MenuKit.SCREEN_ACCENT.get(sname, MenuKit.ACCENT), true))
	var sub := MenuKit.label("", 18, MenuKit.DIM)
	box.add_child(sub)
	_town_sub[sname] = sub
	var coins := MenuKit.label("", 20, Color(1.0, 0.85, 0.35))
	box.add_child(coins)
	_town_coins[sname] = coins


func town_coins_text() -> String:
	return U.t("Coins: %s") % U.money(Game.state.coins) + "   ·   " + U.t("Ancient coins: %s") % U.fmt(float(Game.profile.meta_coins))


## Обновить шапку лавки (монеты) после покупки.
func refresh_town_head(sname: String) -> void:
	var l: Label = _town_coins.get(sname)
	if l != null:
		l.text = town_coins_text()


## Рамка экрана и его регистрация (owner — экран, который им управляет).
## top = true: экран прижат к верху, а не по центру. Нужен экранам с карточкой пушки: высота их содержимого не должна
## двигать заголовок и списки, когда карточка меняется (у Кузни хаоса она выше обычных).
## Все экраны, кроме главного, стоят в рамке-панели «как у карточки пушки» (цвет — лавка или ветка дерева).
func add_screen(root: Control, sname: String, owner: MenuScreen, top: bool = false) -> VBoxContainer:
	logic[sname] = owner
	var framed := sname != "main"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var holder: Control = box
	if framed:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", MenuKit.card_style(MenuKit.SCREEN_ACCENT.get(sname, MenuKit.ACCENT), 30, 18))
		panel.add_child(box)
		holder = panel
		panels[sname] = panel
	if top:
		var wrap := VBoxContainer.new()
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.alignment = BoxContainer.ALIGNMENT_BEGIN
		root.add_child(wrap)
		wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		wrap.add_child(holder)
		screens[sname] = wrap
		return box
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(holder)
	screens[sname] = center
	return box
