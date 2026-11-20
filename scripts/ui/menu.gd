class_name Menu
extends CanvasLayer
## Главное меню, пауза и настройки. Обычные Control-ы с темой из кода.
## Режимы: "main" — главное меню (фон MenuBg), "pause" — поверх игры (затемнение),
## "town" — экран, открытый лавкой в городе (герои, настраиваемый старт): «Назад» возвращает в игру.
## Экран настроек общий, «Назад» возвращает в текущий режим.

const ACCENT := Color(1.0, 0.55, 0.2)
const TEXT := Color(0.9, 0.9, 0.95)
const DIM := Color(0.6, 0.6, 0.68)
## Панели экранов — как карточка пушки (GunCard): тёмный фон, цветная полоса сверху и рамка того же цвета.
const PANEL_BG := Color(0.05, 0.05, 0.07, 0.94)
const SCREEN_ACCENT := {"shop": Color(1.0, 0.62, 0.25), "mystic": Color(0.78, 0.45, 1.0), "workshop": Color(0.45, 0.75, 1.0),
	"guild": Color(0.5, 0.9, 0.45), "healer": Color(1.0, 0.4, 0.45), "heroes": Color(0.4, 0.85, 1.0), "custom": Color(1.0, 0.82, 0.35)}

var mode := "main"
var current := ""
var bg: MenuBg
var dim: ColorRect
var cursor: CursorDraw
var screens := {}
var _panels := {}         # экран -> PanelContainer-рамка (цвет полосы меняет дерево навыков по ветке)
var records: Label
var _settings_ui := {}    # ключ -> [контрол, подпись значения или null, формат]
var _first_focus := {}    # экран -> кнопка, получающая фокус
var _custom_ui := {}      # ключ Game.custom -> [контрол, ...]
var _custom_preset: Label
var _custom_seed: LineEdit
var _custom_rating: Label
var _heroes_list: VBoxContainer
var _heroes_coins: Label
var _tree_ui := {}        # ветка дерева навыков -> {head: Label, rows: VBoxContainer}
var _pause_tree_btn: Button
var _pause_restart_btn: Button   # «Начать заново»: первое нажатие просит подтверждения
var _restart_armed := false
var _town_sub := {}       # экран лавки -> Label с репликой торговца
var _town_coins := {}     # экран лавки -> Label с монетами
var _shop_buy: VBoxContainer
var _shop_deal_panel: PanelContainer   # «Товар дня» — отдельный блок над списком
var _shop_deal: VBoxContainer
var _shop_sell: VBoxContainer
var _shop_prev: GunPreview
var _shop_reroll: Button
var _shop_ammo: VBoxContainer
var _shop_status: Label
var _mystic_box: VBoxContainer
var _mystic_owned: Label
var _mystic_element := false   # Мистик: выбираем стихию для перка «Стихия»
var _ws_list: VBoxContainer
var _ws_actions: VBoxContainer
var _ws_prev: GunPreview
var _ws_status: Label
var _ws_gun: Gun = null
var _ws_partner: Gun = null      # вторая пушка при объединении (ждём выбора, кто стреляет, а кто заряжает)
var _ws_pick: Dictionary = {}    # оплаченная переброска: {"gun", "drop", "options"} — осталось выбрать перк из трёх
var _guild_offers: VBoxContainer
var _guild_active: VBoxContainer
var _guild_active_title: Label
var _release_grid: GridContainer
var _healer_box: VBoxContainer
var _healer_info: Label
var _pause_info: Label
var _help_box: VBoxContainer
var _root: Control
var _codex_page := ""
var _codex_text: RichTextLabel
var _codex_actions: HBoxContainer
var _codex_status: Label
var _codex_buttons := {}  # id страницы -> кнопка в списке
var _bind_buttons := {}   # "действие:колонка" -> кнопка
var _listening := ""      # "действие:колонка", пока ждём нажатия; "" — не ждём
var _listen_t := 0.0
var _controls_status: Label
var _touch_opt: Button
var _refit_pending := false
var _card_opt: Button
const CARD_MODES := {"right": "On the right", "left": "On the left", "above": "Above the gun"}
const LISTEN_TIME := 6.0

## Кнопки, которые страница справочника может попросить в "actions" (data/codex.json).
const CODEX_ACTIONS := {
	"write_guide": ["Create modding guide", "_codex_write_guide"],
	"open_mods_folder": ["Open mods folder", "_open_mods_folder"],
	"open_game_folder": ["Open game folder", "_open_game_folder"],
}


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	Game.settings_changed.connect(_on_setting)
	Game.main.controls.mode_changed.connect(_on_input_mode)
	get_viewport().size_changed.connect(_fit)


## Сменили устройство: подсказки паузы — под него; на геймпаде фокус нужен на кнопке.
func _on_input_mode(m: String) -> void:
	if not visible:
		return
	if mode == "pause":
		_fill_help()
	if m == "pad" and get_viewport().gui_get_focus_owner() == null:
		var b: Control = _first_focus.get(current)
		if b != null:
			b.grab_focus()


## Весь UI строится заново при смене языка — так переводятся и форматированные подписи.
func _build_ui() -> void:
	var root := Control.new()
	_root = root
	root.theme = _make_theme()
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
	_build_main(root)
	_build_custom(root)
	_build_heroes(root)
	_build_tree(root)
	_build_shop(root)
	_build_mystic(root)
	_build_workshop(root)
	_build_guild(root)
	_build_healer(root)
	_build_settings(root)
	_build_pause(root)
	_build_mods(root)
	_build_codex(root)
	_build_controls(root)
	_build_release(root)
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
		_rebuild.call_deferred()
	elif key in UiFit.KEYS:
		# пока тянешь ползунок размера — не перестраиваем (меню уехало бы из-под мыши)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_refit_pending = true
		else:
			_fit()


func _rebuild() -> void:
	var was := current
	remove_child(_root)
	_root.queue_free()
	screens.clear()
	_settings_ui.clear()
	_first_focus.clear()
	_custom_ui.clear()
	_town_sub.clear()
	_town_coins.clear()
	_tree_ui.clear()
	_codex_buttons.clear()
	_bind_buttons.clear()
	_listening = ""
	_build_ui()
	bg.visible = mode == "main"
	dim.visible = mode == "pause"
	records.text = _records_text()
	_pause_info.text = run_info()
	_fill_help()
	show_screen(was if was != "" else mode)


func _lang_text() -> String:
	return U.t("Language") + ": " + I18n.lang_name(I18n.current())


## Следующий язык из найденных в lang/ (игра + моды).
func _cycle_lang() -> void:
	var codes := I18n.available()
	var i := codes.find(I18n.current())
	Game.set_setting("language", str(codes[(i + 1) % codes.size()]))


# --- Открытие / закрытие --------------------------------------------------------

func open_main() -> void:
	mode = "main"
	visible = true
	bg.visible = true
	dim.visible = false
	records.text = _records_text()
	show_screen("main")


func open_pause() -> void:
	mode = "pause"
	visible = true
	bg.visible = false
	dim.visible = true
	_pause_info.text = run_info()
	_fill_help()
	var fp := LevelTree.free_points()
	_pause_tree_btn.text = U.t("Skill tree") + (" (%d)" % fp if fp > 0 else "")
	_restart_armed = false
	_pause_restart_btn.text = U.t("Restart run")
	show_screen("pause")


func close() -> void:
	visible = false


## Экран меню из лавки в городе: игра на паузе, «Назад» / Esc — обратно в город.
## line — реплика торговца (подпись под заголовком), col — её цвет.
func open_town(sname: String, line: String = "", col: Color = DIM) -> void:
	var sub: Label = _town_sub.get(sname)
	if sub != null:
		sub.text = "«%s»" % line if line != "" else ""
		sub.add_theme_color_override("font_color", col.lightened(0.2))
	_mystic_element = false
	if sname in ["shop", "workshop"]:
		_shop_status.text = ""
		_ws_status.text = ""
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
func _back() -> void:
	if mode == "town":
		close_town()
	else:
		show_screen(mode)


func show_screen(sname: String) -> void:
	current = sname
	for k in screens:
		(screens[k] as Control).visible = k == sname
	if sname == "settings":
		_refresh_settings()
	elif sname == "custom":
		_refresh_custom()
	elif sname == "heroes":
		_refresh_heroes()
	elif sname.begins_with("tree_"):
		_refresh_tree(sname.substr(5))
	elif sname == "shop":
		_refresh_shop()
	elif sname == "mystic":
		_refresh_mystic()
	elif sname == "workshop":
		_refresh_workshop()
	elif sname == "guild":
		_refresh_guild()
	elif sname == "healer":
		_refresh_healer()
	elif sname == "codex":
		_codex_open(_codex_page)
	elif sname == "controls":
		_refresh_controls()
	elif sname == "release":
		_refresh_release()
	var b: Control = _first_focus.get(sname)
	if b != null:
		b.grab_focus.call_deferred()


func _process(delta: float) -> void:
	if visible:
		cursor.queue_redraw()
	if _refit_pending and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_fit()
	# геймпад: правый стик листает текст справочника
	if visible and current == "codex" and Controls.mode == "pad" and _codex_text != null:
		var v := Input.get_axis("aim_up", "aim_down")
		if absf(v) > 0.2:
			var bar := _codex_text.get_v_scroll_bar()
			bar.value += v * 1400.0 * delta
	if _listening != "":
		_listen_t -= delta
		var b: Button = _bind_buttons.get(_listening)
		if _listen_t <= 0.0:
			_stop_listening()
		elif b != null:
			b.text = U.t("Press… %d") % ceili(_listen_t)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if _listening != "":
			return   # в меню «Управление» ждём кнопку — Esc/B тоже можно назначить
		if current == "custom":
			_back_custom()
		elif mode == "town":
			close_town()
		elif current == "controls":
			show_screen("settings")
		elif current == "release":
			show_screen("controls")
		elif current != mode:
			show_screen(mode)
		elif mode == "pause":
			Game.main.hud.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("skill_tree") and current.begins_with("tree_"):
		_back()   # та же клавиша закрывает дерево
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") or event.is_action_pressed("debug"):
		get_viewport().set_input_as_handled()


# --- Экраны ---------------------------------------------------------------------

func _build_main(root: Control) -> void:
	var box := _screen(root, "main")
	box.add_child(_label("DEVIANT", 104, ACCENT, true))
	box.add_child(_label(U.t("an endless diablo-like with absurd guns"), 22, DIM))
	box.add_child(_gap(36))
	var b := _button(U.t("New game"), func() -> void: Game.main.start_game())
	box.add_child(b)
	_first_focus["main"] = b
	box.add_child(_button(U.t("Custom start"), func() -> void: show_screen("custom")))
	box.add_child(_button(U.t("Codex"), func() -> void: show_screen("codex")))
	box.add_child(_button(U.t("Settings"), func() -> void: show_screen("settings")))
	box.add_child(_button(U.t("Mods") + " (%d)" % _mods_on(), func() -> void: show_screen("mods")))
	box.add_child(_button(U.t("Quit"), func() -> void: get_tree().quit()))
	box.add_child(_button(_lang_text(), _cycle_lang))
	box.add_child(_gap(30))
	records = _label("", 18, DIM)
	box.add_child(records)


# --- Моды ---------------------------------------------------------------------------

func _mods_on() -> int:
	var n := 0
	for m in Mods.list:
		if bool(m["enabled"]):
			n += 1
	return n


## Список модов из папки Mods/ с переключателями. Изменения применяются сразу:
## перечитываются данные, переводы, звуки и музыка.
func _build_mods(root: Control) -> void:
	var box := _screen(root, "mods")
	box.add_child(_label(U.t("MODS"), 56, ACCENT, true))
	box.add_child(_label(U.t("Folder: %s") % Mods.root(), 16, DIM))
	box.add_child(_gap(12))
	if Mods.list.is_empty():
		box.add_child(_label(U.t("No mods found. Put a mod folder into the Mods folder and press Rescan."), 20, TEXT))
	else:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 8)
		box.add_child(grid)
		for m in Mods.list:
			var c := CheckButton.new()
			c.button_pressed = bool(m["enabled"])
			c.toggled.connect(_on_mod_toggled.bind(str(m["id"])))
			grid.add_child(c)
			var info: Dictionary = m["info"]
			var line := str(m["name"])
			if info.has("version"):
				line += "  v" + str(info["version"])
			if info.has("author"):
				line += "  · " + str(info["author"])
			var lb := _label(line, 22, TEXT, false, HORIZONTAL_ALIGNMENT_LEFT)
			if info.has("description"):
				lb.tooltip_text = str(info["description"])
			grid.add_child(lb)
	box.add_child(_gap(16))
	# отладчик модов: включается только перезапуском, чтобы в обычной игре ничего лишнего не грузилось
	var dbg := CheckButton.new()
	dbg.text = U.t("Mod debugger (F8)")
	dbg.button_pressed = bool(Game.setting("mod_debug"))
	dbg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dbg.add_theme_font_size_override("font_size", 22)
	dbg.toggled.connect(_on_debug_toggled)
	box.add_child(dbg)
	var pending := bool(Game.setting("mod_debug")) != DebugLog.enabled
	var note := _label(U.t("Takes effect after restart"), 16, ACCENT)
	note.visible = pending
	box.add_child(note)
	var rb := _button(U.t("Restart now"), Game.restart)
	rb.visible = pending
	box.add_child(rb)
	box.add_child(_button(U.t("How to make mods"), _codex_show.bind("modding")))
	box.add_child(_button(U.t("Open mods folder"), _open_mods_folder))
	box.add_child(_button(U.t("Rescan"), _reload_mods))
	var back := _button(U.t("Back"), func() -> void: show_screen(mode))
	box.add_child(back)
	_first_focus["mods"] = back


func _on_debug_toggled(on: bool) -> void:
	Game.set_setting("mod_debug", on)
	_rebuild.call_deferred()


func _on_mod_toggled(on: bool, id: String) -> void:
	Mods.set_enabled(id, on)
	_reload_mods()


func _reload_mods() -> void:
	Game.reload_content()
	_rebuild.call_deferred()


func _open_mods_folder() -> void:
	var path := Mods.root()
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
	OS.shell_open(path)


func _open_game_folder() -> void:
	OS.shell_open(Mods.base_dir())


# --- Справочник -----------------------------------------------------------------------

## Окно справочника: слева разделы и страницы (data/codex.json игры и модов), справа текст.
func _build_codex(root: Control) -> void:
	var holder := MarginContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		holder.add_theme_constant_override("margin_" + side, 40)
	root.add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screens["codex"] = holder
	var panel := PanelContainer.new()
	var sb := _box(Color(0.035, 0.035, 0.06, 0.95), Color(0.3, 0.3, 0.42))
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)
	var title := _label(U.t("CODEX"), 40, ACCENT, true, HORIZONTAL_ALIGNMENT_LEFT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var back := _button(U.t("Back"), func() -> void: show_screen(mode))
	back.custom_minimum_size = Vector2(200, 48)
	top.add_child(back)
	_first_focus["codex"] = back

	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	hb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var group := ButtonGroup.new()
	for sec in Codex.sections:
		var pg := Codex.pages_of(str(sec["id"]))
		if pg.is_empty():
			continue
		if list.get_child_count() > 0:
			list.add_child(_gap(6))
		list.add_child(_label(Codex.loc(sec.get("title", sec["id"])).to_upper(), 16, DIM, true, HORIZONTAL_ALIGNMENT_LEFT))
		for p in pg:
			var id := str(p["id"])
			var b := Button.new()
			b.text = Codex.loc(p.get("title", id))
			b.toggle_mode = true
			b.button_group = group
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(300, 40)
			b.add_theme_font_size_override("font_size", 19)
			b.pressed.connect(_codex_open.bind(id))
			b.pressed.connect(func() -> void: Sfx.ui("ui/click", -8.0))
			b.mouse_entered.connect(_on_hover.bind(b))
			list.add_child(b)
			_codex_buttons[id] = b
			if _codex_page == "":
				_codex_page = id

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	hb.add_child(right)
	_codex_text = RichTextLabel.new()
	_codex_text.bbcode_enabled = true
	_codex_text.selection_enabled = true
	_codex_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_codex_text.add_theme_font_override("normal_font", U.font())
	_codex_text.add_theme_font_override("bold_font", U.font_bold())
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "mono_font_size"]:
		_codex_text.add_theme_font_size_override(k, 19)
	_codex_text.add_theme_color_override("default_color", TEXT)
	_codex_text.add_theme_constant_override("line_separation", 3)
	_codex_text.add_theme_constant_override("table_h_separation", 4)
	_codex_text.add_theme_constant_override("table_v_separation", 2)
	right.add_child(_codex_text)
	_codex_actions = HBoxContainer.new()
	_codex_actions.add_theme_constant_override("separation", 12)
	right.add_child(_codex_actions)
	_codex_status = _label("", 16, ACCENT, false, HORIZONTAL_ALIGNMENT_LEFT)
	_codex_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_codex_status)


func _codex_show(id: String) -> void:
	_codex_page = id
	show_screen("codex")


func _codex_open(id: String) -> void:
	var p := Codex.page(id)
	if p.is_empty():
		if Codex.pages.is_empty():
			_codex_text.text = U.t("The codex is empty.")
			return
		p = Codex.pages[0]
		id = str(p["id"])
	_codex_page = id
	for k in _codex_buttons:
		(_codex_buttons[k] as Button).set_pressed_no_signal(k == id)
	_codex_text.text = Codex.page_text(p)
	_codex_text.scroll_to_line(0)
	for c in _codex_actions.get_children():
		_codex_actions.remove_child(c)
		c.queue_free()
	_codex_status.text = ""
	for a in p.get("actions", []):
		var spec: Array = CODEX_ACTIONS.get(str(a), [])
		if spec.is_empty():
			continue
		var b := _button(U.t(str(spec[0])), Callable(self, str(spec[1])))
		b.custom_minimum_size = Vector2(0, 48)
		b.add_theme_font_size_override("font_size", 20)
		_codex_actions.add_child(b)
	_codex_actions.visible = _codex_actions.get_child_count() > 0


func _codex_write_guide() -> void:
	var path := Codex.write_guide()
	if path == "":
		_codex_status.text = U.t("Could not write the guide. Is the game folder read-only?")
		_codex_status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		return
	_codex_status.text = U.t("Guide saved: %s") % path
	_codex_status.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	OS.shell_open(path)


# --- Управление ---------------------------------------------------------------------

## Экран «Управление»: автоприцел, экранные кнопки и переназначение клавиш и кнопок геймпада.
func _build_controls(root: Control) -> void:
	var holder := MarginContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		holder.add_theme_constant_override("margin_" + side, 40)
	root.add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screens["controls"] = holder
	var panel := PanelContainer.new()
	var sb := _box(Color(0.035, 0.035, 0.06, 0.95), Color(0.3, 0.3, 0.42))
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)
	var title := _label(U.t("CONTROLS"), 40, ACCENT, true, HORIZONTAL_ALIGNMENT_LEFT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var reset := _button(U.t("Reset to defaults"), _reset_binds)
	reset.custom_minimum_size = Vector2(0, 48)
	top.add_child(reset)
	var back := _button(U.t("Back"), func() -> void: show_screen("settings"))
	back.custom_minimum_size = Vector2(200, 48)
	top.add_child(back)
	_first_focus["controls"] = back

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	vb.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 14)
	scroll.add_child(inner)

	var opts := GridContainer.new()
	opts.columns = 3
	opts.add_theme_constant_override("h_separation", 24)
	opts.add_theme_constant_override("v_separation", 8)
	inner.add_child(opts)
	_check(opts, "auto_aim", U.t("Auto-aim (gamepad and touch)"))
	_check(opts, "auto_fire", U.t("Auto-fire at visible enemies (gamepad and touch)"))
	opts.add_child(_label(U.t("Touch controls"), 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	_touch_opt = Button.new()
	_touch_opt.custom_minimum_size = Vector2(340, 40)
	_touch_opt.add_theme_font_size_override("font_size", 20)
	_touch_opt.pressed.connect(_cycle_touch)
	_touch_opt.pressed.connect(func() -> void: Sfx.ui("ui/click", -6.0))
	opts.add_child(_touch_opt)
	opts.add_child(Control.new())
	_check(opts, "touch_static", U.t("Fixed sticks (don't follow the finger)"))
	_check(opts, "touch_tap_fire", U.t("Tap to shoot at that point (instead of the right stick)"))
	_slider(opts, "touch_scale", U.t("Touch controls size"), 0.6, 1.6, 0.05, "pct")
	opts.add_child(Control.new())
	var edit := _button(U.t("Edit touch layout"), _edit_touch_layout)
	edit.custom_minimum_size = Vector2(340, 48)
	edit.add_theme_font_size_override("font_size", 20)
	opts.add_child(edit)
	opts.add_child(Control.new())
	opts.add_child(Control.new())
	var rel := _button(U.t("Fire on release…"), func() -> void: show_screen("release"))
	rel.custom_minimum_size = Vector2(340, 48)
	rel.add_theme_font_size_override("font_size", 20)
	opts.add_child(rel)
	opts.add_child(_label(U.t("per gun type"), 16, DIM, false, HORIZONTAL_ALIGNMENT_LEFT))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	inner.add_child(grid)
	grid.add_child(_label("", 18, DIM))
	grid.add_child(_label(U.t("Keyboard and mouse"), 18, DIM, true))
	grid.add_child(_label(U.t("Gamepad"), 18, DIM, true))
	for row in InputSetup.REBINDABLE:
		var action := str(row[0])
		var name_l := _label(U.t(str(row[1])), 20, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_l)
		for col in ["kb", "pad"]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(300, 38)
			b.add_theme_font_size_override("font_size", 18)
			b.pressed.connect(_start_listening.bind(action, col))
			b.mouse_entered.connect(_on_hover.bind(b))
			if action.begins_with("aim_") and col == "kb":
				b.disabled = true    # прицел с клавиатуры — мышью
			grid.add_child(b)
			_bind_buttons[action + ":" + col] = b
	_controls_status = _label(U.t("Click a binding, then press a key or a gamepad button. Delete — clear."), 16, DIM, false,
		HORIZONTAL_ALIGNMENT_LEFT)
	_controls_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_controls_status)


func _refresh_controls() -> void:
	_refresh_settings()
	_touch_opt.text = U.t({"auto": "Auto (when playing with fingers)", "on": "Always", "off": "Off"}.get(
		str(Game.setting("touch_controls")), "Auto (when playing with fingers)"))
	for key in _bind_buttons:
		var parts := str(key).split(":")
		var b: Button = _bind_buttons[key]
		if b.disabled:
			b.text = U.t("mouse")
		else:
			b.text = InputSetup.action_label(parts[0], parts[1], 3)


func _cycle_card() -> void:
	var order: Array = CARD_MODES.keys()
	var i := order.find(str(Game.setting("gun_card")))
	Game.set_setting("gun_card", order[(i + 1) % order.size()])
	_card_opt.text = U.t(str(CARD_MODES.get(str(Game.setting("gun_card")), "On the right")))


func _edit_touch_layout() -> void:
	visible = false
	Game.main.touch.start_edit(_end_touch_edit)


func _end_touch_edit() -> void:
	visible = true
	show_screen("controls")


func _cycle_touch() -> void:
	var order := ["auto", "on", "off"]
	var i := order.find(str(Game.setting("touch_controls")))
	Game.set_setting("touch_controls", order[(i + 1) % order.size()])
	_refresh_controls()


func _start_listening(action: String, col: String) -> void:
	_stop_listening()
	_listening = action + ":" + col
	_listen_t = LISTEN_TIME


func _stop_listening() -> void:
	_listening = ""
	if current == "controls":
		_refresh_controls()


## Пока ждём нажатия — ловим его раньше всех (и кнопки меню его не получат).
## Геймпад без фокуса: первое нажатие ставит фокус на кнопку экрана, иначе A/B/крестовине некуда идти.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _listening == "":
		if (event is InputEventJoypadButton and event.is_pressed()) or \
				(event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
			if get_viewport().gui_get_focus_owner() == null:
				var fb: Control = _first_focus.get(current)
				if fb != null and fb.is_visible_in_tree():
					fb.grab_focus()
					get_viewport().set_input_as_handled()
		return
	var parts := _listening.split(":")
	var action := parts[0]
	var col := parts[1]
	var ev: InputEvent = null
	if col == "kb":
		if event is InputEventKey and event.is_pressed() and not event.is_echo():
			var k := event as InputEventKey
			if k.physical_keycode == KEY_DELETE or k.keycode == KEY_DELETE:
				_apply_bind(action, col, null)
				get_viewport().set_input_as_handled()
				return
			var nk := InputEventKey.new()
			nk.physical_keycode = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			ev = nk
		elif event is InputEventMouseButton and event.is_pressed():
			var nm := InputEventMouseButton.new()
			nm.button_index = (event as InputEventMouseButton).button_index
			ev = nm
	else:
		if event is InputEventJoypadButton and event.is_pressed():
			var nb := InputEventJoypadButton.new()
			nb.button_index = (event as InputEventJoypadButton).button_index
			ev = nb
		elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6:
			var jm := event as InputEventJoypadMotion
			var na := InputEventJoypadMotion.new()
			na.axis = jm.axis
			na.axis_value = signf(jm.axis_value)
			ev = na
		elif event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_DELETE:
			_apply_bind(action, col, null)
			get_viewport().set_input_as_handled()
			return
	if ev == null:
		return
	get_viewport().set_input_as_handled()
	_apply_bind(action, col, ev)


func _apply_bind(action: String, col: String, ev: InputEvent) -> void:
	InputSetup.rebind(action, col, ev)
	_listening = ""
	Game.set_setting("binds", JSON.stringify(InputSetup.current_binds()))
	Sfx.ui("ui/click", -6.0)
	if ev != null:
		_controls_status.text = U.t("%s: %s") % [U.t(_action_title(action)), InputSetup.event_name(ev)]
	_refresh_controls()


func _action_title(action: String) -> String:
	for row in InputSetup.REBINDABLE:
		if str(row[0]) == action:
			return str(row[1])
	return action


## «Стрельба по отпусканию» (сенсор): для каждого типа пушки — стрелять, пока держишь правый стик,
## или целиться стиком и выстрелить один раз, когда отпустил. Настройка touch_release_fire (JSON).
func _build_release(root: Control) -> void:
	var box := _screen(root, "release")
	box.add_child(_label(U.t("FIRE ON RELEASE"), 48, ACCENT, true))
	var info := _label(U.t("Touch: aim with the right stick and fire one shot when you let go. Hybrids follow their first type. Does not work with tap-to-shoot; auto-fire is off for these guns."), 18, DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(900, 0)
	box.add_child(info)
	box.add_child(_gap(8))
	_release_grid = GridContainer.new()
	_release_grid.columns = 4
	_release_grid.add_theme_constant_override("h_separation", 18)
	_release_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_release_grid)
	box.add_child(_gap(8))
	var back := _button(U.t("Back"), func() -> void: show_screen("controls"))
	box.add_child(back)
	_first_focus["release"] = back


func _refresh_release() -> void:
	for c in _release_grid.get_children():
		_release_grid.remove_child(c)
		c.queue_free()
	var on := Controls.release_types()
	for k in GunData.ARCH:
		_release_grid.add_child(_label(U.t(str(GunData.ARCH[k].get("name", k))), 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
		var c := CheckButton.new()
		c.focus_mode = Control.FOCUS_ALL
		c.button_pressed = bool(on.get(k, false))
		c.toggled.connect(_set_release.bind(str(k)))
		_release_grid.add_child(c)


func _set_release(enabled: bool, arch: String) -> void:
	var d := Controls.release_types().duplicate()
	if enabled:
		d[arch] = true
	else:
		d.erase(arch)
	Game.set_setting("touch_release_fire", JSON.stringify(d) if not d.is_empty() else "")


func _reset_binds() -> void:
	_listening = ""
	Game.set_setting("binds", "")
	_controls_status.text = U.t("Controls reset to defaults.")
	_refresh_controls()


# --- Лавки города: Оружейная, Мистик, Мастерская, Гильдия ------------------------------
## Товар — Game.main.town (Shops.make_town), цены — Shops, задания — Quests.

## Заголовок лавки: название, реплика торговца (подставляется при открытии), монеты.
func _shop_head(box: VBoxContainer, sname: String, title: String) -> void:
	box.add_child(_label(title, 48, SCREEN_ACCENT.get(sname, ACCENT), true))
	var sub := _label("", 18, DIM)
	box.add_child(sub)
	_town_sub[sname] = sub
	var coins := _label("", 20, Color(1.0, 0.85, 0.35))
	box.add_child(coins)
	_town_coins[sname] = coins


func _shop_coins_text() -> String:
	return U.t("Coins: %s") % U.money(Game.coins) + "   ·   " + U.t("Ancient coins: %s") % U.fmt(float(Game.meta_coins))


## Обновить шапку лавки (монеты) после покупки.
func _shop_refresh_head(sname: String) -> void:
	var l: Label = _town_coins.get(sname)
	if l != null:
		l.text = _shop_coins_text()


func _list_box(minw: float, minh: float) -> Array:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.custom_minimum_size = Vector2(minw, minh)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	return [sc, vb]


func _clear_box(b: Container) -> void:
	for c in b.get_children():
		b.remove_child(c)
		c.queue_free()


## Кнопка-строка пушки: цвет редкости, наведение/фокус — карточка в preview.
func _gun_row(g: Gun, text: String, cb: Callable, preview: GunPreview) -> Button:
	var b := _button(text, cb)
	b.custom_minimum_size = Vector2(440, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", g.rarity_color())
	var show_card := func() -> void: preview.show_gun(g, Game.main.player.gun() if Game.main.player.gun() != g else null)
	b.mouse_entered.connect(show_card)
	b.focus_entered.connect(show_card)
	return b


func _small_button(text: String, cb: Callable, w: float = 440.0) -> Button:
	var b := _button(text, cb)
	b.custom_minimum_size = Vector2(w, 44)
	b.add_theme_font_size_override("font_size", 17)
	return b


## Все пушки игрока: [пушка, "slot"/"bag", индекс].
func _player_guns() -> Array:
	var p: Player = Game.main.player
	var out: Array = []
	for i in 4:
		if p.guns[i] != null:
			out.append([p.guns[i], "slot", i])
	for i in p.backpack.size():
		out.append([p.backpack[i], "bag", i])
	return out


func _gun_where(e: Array) -> String:
	return (U.t("slot %d") % (int(e[2]) + 1)) if str(e[1]) == "slot" else U.t("backpack")


func _grab_first(box: Container) -> void:
	if Controls.mode != "pad":
		return
	for c in box.get_children():
		if c is Button and not (c as Button).disabled:
			(c as Button).grab_focus.call_deferred()
			return


# --- Оружейная ---

func _build_shop(root: Control) -> void:
	var box := _screen(root, "shop", true)
	_shop_head(box, "shop", U.t("GUN SHOP"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.add_child(_label(U.t("For sale"), 22, TEXT))
	# «Товар дня» — своя рамка над списком; сам список без прокрутки: в нём все остальные пушки сразу
	_shop_deal_panel = PanelContainer.new()
	_shop_deal_panel.add_theme_stylebox_override("panel", _box(Color(0.22, 0.17, 0.05, 0.55), Color(1.0, 0.82, 0.35), 3))
	_shop_deal = VBoxContainer.new()
	_shop_deal.add_theme_constant_override("separation", 6)
	_shop_deal_panel.add_child(_shop_deal)
	left.add_child(_shop_deal_panel)
	_shop_buy = VBoxContainer.new()
	_shop_buy.add_theme_constant_override("separation", 6)
	_shop_buy.custom_minimum_size = Vector2(460, 0)
	left.add_child(_shop_buy)
	_shop_reroll = _small_button("", _reroll_stock, 460.0)
	left.add_child(_shop_reroll)
	row.add_child(left)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 6)
	mid.add_child(_label(U.t("Your guns — sell"), 22, TEXT))
	var mb := _list_box(460, 380)
	mid.add_child(mb[0])
	_shop_sell = mb[1]
	mid.add_child(_label(U.t("Ammo — one magazine"), 22, TEXT))
	_shop_ammo = VBoxContainer.new()
	_shop_ammo.add_theme_constant_override("separation", 6)
	_shop_ammo.custom_minimum_size = Vector2(460, 0)
	mid.add_child(_shop_ammo)
	row.add_child(mid)
	_shop_prev = GunPreview.new()
	row.add_child(_shop_prev)
	_shop_status = _label("", 18, DIM)
	box.add_child(_shop_status)
	var back := _button(U.t("Back"), _back)
	box.add_child(back)
	_first_focus["shop"] = back


func _refresh_shop() -> void:
	_shop_refresh_head("shop")
	_clear_box(_shop_buy)
	_clear_box(_shop_deal)
	_clear_box(_shop_sell)
	var town: Dictionary = Game.main.town
	var stock: Array = town.get("stock", [])
	if stock.is_empty():
		_shop_buy.add_child(_label(U.t("Sold out"), 18, DIM))
	for o in stock:
		var g: Gun = o
		var price := Shops.buy_price(g, town)
		var is_deal: bool = g == town.get("deal")
		var b := _gun_row(g, ("%s — %s" % [g.gun_name, U.money(price)]) if not is_deal else U.tm("%s — %d (was %d)", [g.gun_name, U.money(price), U.money(Shops.gun_price(g))]),
			_buy_gun.bind(g), _shop_prev)
		b.disabled = Game.coins < price
		if is_deal:
			_shop_deal.add_child(_label(U.t("Deal of the day: 50% off"), 16, Color(1.0, 0.82, 0.35), true, HORIZONTAL_ALIGNMENT_LEFT))
			_shop_deal.add_child(b)
		else:
			_shop_buy.add_child(b)
	_shop_deal_panel.visible = _shop_deal.get_child_count() > 0
	var p: Player = Game.main.player
	for e in _player_guns():
		var g: Gun = e[0]
		var b := _gun_row(g, "+%s · %s (%s)" % [U.money(Shops.sell_price(g)), g.gun_name, _gun_where(e)], _sell_gun.bind(g), _shop_prev)
		# последнюю пушку в руках не продать — стрелять будет нечем
		b.disabled = str(e[1]) == "slot" and p.gun_count() <= 1
		_shop_sell.add_child(b)
	var lvl := int(town.get("level", 1))
	var rp := Shops.stock_reroll_price(lvl, int(town.get("rerolls", 0)))
	_shop_reroll.text = U.tm("New stock — %d", [U.money(rp)])
	_shop_reroll.disabled = Game.coins < rp
	# патроны: по магазину к каждой пушке в слотах
	_clear_box(_shop_ammo)
	for i in 4:
		var g: Gun = p.guns[i]
		if g == null or g.free_ammo:
			continue
		var t := g.ammo_type()
		var n := mini(g.mag_size, GunData.ammo_cap(t) - p.reserve_of(t))
		var b: Button
		if n <= 0:
			b = _gun_row(g, U.t("%s: reserve full") % g.ammo_name(), func() -> void: pass, _shop_prev)
			b.disabled = true
		else:
			var price := Shops.ammo_price(g, n)
			b = _gun_row(g, "+%d %s — %s  (%s)" % [n, g.ammo_name(), U.money(price), g.gun_name], _buy_ammo.bind(g), _shop_prev)
			b.disabled = Game.coins < price
		_shop_ammo.add_child(b)
	if _shop_ammo.get_child_count() == 0:
		_shop_ammo.add_child(_label(U.t("Your guns don't need ammo"), 16, DIM))
	if not stock.is_empty():
		_shop_prev.show_gun(stock[0], p.gun())
	_grab_first(_shop_deal if _shop_deal_panel.visible else _shop_buy)


func _reroll_stock() -> void:
	var town: Dictionary = Game.main.town
	var lvl := int(town.get("level", 1))
	var rp := Shops.stock_reroll_price(lvl, int(town.get("rerolls", 0)))
	if Game.coins < rp:
		Sfx.ui("ui/error", -6.0)
		return
	Game.add_coins(-rp)
	town["rerolls"] = int(town.get("rerolls", 0)) + 1
	town["stock"] = Shops.make_stock(lvl, Game.main.rng)
	town["deal"] = (town["stock"] as Array)[0]
	_shop_status.text = U.t("New stock arrived")
	Sfx.ui("world/chest", -6.0)
	_refresh_shop()


## Один магазин патронов к пушке (сколько влезет в запас).
func _buy_ammo(g: Gun) -> void:
	var p: Player = Game.main.player
	var t := g.ammo_type()
	var n := mini(g.mag_size, GunData.ammo_cap(t) - p.reserve_of(t))
	var price := Shops.ammo_price(g, n)
	if n <= 0 or Game.coins < price:
		Sfx.ui("ui/error", -6.0)
		return
	Game.add_coins(-price)
	p.add_ammo(t, n)
	_shop_status.text = U.t("Bought: +%d %s") % [n, g.ammo_name()]
	Sfx.ui("pickup/ammo", -6.0)
	_refresh_shop()


func _buy_gun(g: Gun) -> void:
	var town: Dictionary = Game.main.town
	var price := Shops.buy_price(g, town)
	var stock: Array = town.get("stock", [])
	if Game.coins < price or not (g in stock):
		Sfx.ui("ui/error", -6.0)
		return
	Game.add_coins(-price)
	stock.erase(g)
	if g == town.get("deal"):
		town["deal"] = null
	var p: Player = Game.main.player
	if p.add_gun(g):
		_shop_status.text = U.t("Bought: %s") % g.gun_name
	else:
		Game.main.drop_gun(g, p.position + p.aim * 30.0, true)
		_shop_status.text = U.t("Backpack full — %s is on the ground") % g.gun_name
	Game.note_gun(g)
	Sfx.ui("pickup/gun", -4.0)
	_refresh_shop()


func _sell_gun(g: Gun) -> void:
	var p: Player = Game.main.player
	var i := p.guns.find(g)
	if i >= 0:
		if p.gun_count() <= 1:
			return
		p.guns[i] = null
		p.on_gun_changed()
	else:
		i = p.backpack.find(g)
		if i < 0:
			return
		p.backpack.remove_at(i)
	Game.add_coins(Shops.sell_price(g))
	_shop_status.text = U.tm("Sold: %s (+%d)", [g.gun_name, U.money(Shops.sell_price(g))])
	Sfx.at("pickup/coin", p.position, -6.0)
	_refresh_shop()


# --- Мистик ---

func _build_mystic(root: Control) -> void:
	var box := _screen(root, "mystic")
	_shop_head(box, "mystic", U.t("MYSTIC"))
	box.add_child(_label(U.t("One gift for your hero's skill per town. Gifts last until the end of the run."), 18, DIM))
	box.add_child(_gap(6))
	_mystic_box = VBoxContainer.new()
	_mystic_box.add_theme_constant_override("separation", 10)
	box.add_child(_mystic_box)
	box.add_child(_gap(6))
	_mystic_owned = _label("", 18, TEXT)
	_mystic_owned.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mystic_owned.custom_minimum_size = Vector2(1100, 0)
	box.add_child(_mystic_owned)
	var back := _button(U.t("Back"), _back)
	box.add_child(back)
	_first_focus["mystic"] = back


func _refresh_mystic() -> void:
	_shop_refresh_head("mystic")
	_clear_box(_mystic_box)
	var town: Dictionary = Game.main.town
	var p: Player = Game.main.player
	# перки — под текущего героя (в стартовом городе героя могли сменить)
	if str(town.get("mystic_for", "")) != p.hero:
		town["mystic_for"] = p.hero
		town["mystic"] = Heroes.perk_offer(p.hero, p.run_perks, Game.main.rng, Shops.MYSTIC_OFFER)
	var price := Shops.mystic_price(int(town.get("level", 1)), p.run_perk_count())
	var done := bool(town.get("mystic_done", false))
	if _mystic_element:
		# выбор стихии для перка «Стихия»
		_mystic_box.add_child(_label(U.t("Choose the element of your skill:"), 20, TEXT))
		for el in Heroes.ELEMENTS:
			var eb := _small_button(U.t(str(U.EL_NAMES[int(el)])), _buy_mystic.bind("element", int(el)), 420.0)
			eb.add_theme_color_override("font_color", U.el_color(int(el)))
			_mystic_box.add_child(eb)
		_mystic_box.add_child(_small_button(U.t("Cancel"), _mystic_cancel, 420.0))
		_grab_first(_mystic_box)
		return
	var offer: Array = town.get("mystic", [])
	if offer.is_empty():
		_mystic_box.add_child(_label(U.t("The spirits have nothing more for this hero."), 18, DIM))
	for o in offer:
		var id := str(o)
		var have := int(p.run_perks.get(id, 0))
		var t := "%s%s — %s   ·   %s" % [Heroes.perk_name(id, p.hero), (" ×%d" % (have + 1)) if have > 0 else "",
			Heroes.perk_desc(id, have), U.money(price)]
		var b := _small_button(t, _buy_mystic.bind(id, -1), 1100.0)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(1100, 58)
		b.disabled = done or Game.coins < price or not Heroes.perk_open(id, p.hero, have)
		_mystic_box.add_child(b)
	if done:
		_mystic_box.add_child(_label(U.t("The spirits are tired. Come back in the next town."), 18, DIM))
	var owned := PackedStringArray()
	for id in p.run_perks:
		var nm := Heroes.perk_name(str(id), p.hero) + " ×%d" % int(p.run_perks[id])
		if str(id) == "element" and p.skill_element >= 0:
			nm += " (%s)" % U.t(str(U.EL_NAMES[p.skill_element]))
		if not Heroes.perk_fits(str(id), p.hero):
			nm += " " + U.t("(not for this hero)")
		owned.append(nm)
	_mystic_owned.text = U.t("Your gifts: %s") % (", ".join(owned) if not owned.is_empty() else U.t("none"))
	_grab_first(_mystic_box)


func _mystic_cancel() -> void:
	_mystic_element = false
	_refresh_mystic()


## Купить перк навыка. Для «Стихии» сначала выбор стихии (element = -1 -> показать выбор).
func _buy_mystic(id: String, element: int) -> void:
	var town: Dictionary = Game.main.town
	var p: Player = Game.main.player
	var price := Shops.mystic_price(int(town.get("level", 1)), p.run_perk_count())
	if bool(town.get("mystic_done", false)) or Game.coins < price:
		Sfx.ui("ui/error", -6.0)
		return
	if id == "element" and element < 0:
		_mystic_element = true
		_refresh_mystic()
		return
	_mystic_element = false
	Game.add_coins(-price)
	p.add_run_perk(id, element)
	town["mystic_done"] = true
	Sfx.ui("pickup/legendary", -6.0)
	Game.say(U.t("Gift: %s") % Heroes.perk_name(id, p.hero), Color(0.78, 0.45, 1.0))
	_refresh_mystic()


# --- Мастерская ---

func _build_workshop(root: Control) -> void:
	var box := _screen(root, "workshop", true)
	_shop_head(box, "workshop", U.t("WORKSHOP"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var left := VBoxContainer.new()
	left.add_child(_label(U.t("Your guns"), 22, TEXT))
	var lb := _list_box(440, 560)
	left.add_child(lb[0])
	_ws_list = lb[1]
	row.add_child(left)
	_ws_prev = GunPreview.new()
	row.add_child(_ws_prev)
	var right := VBoxContainer.new()
	right.add_child(_label(U.t("Work"), 22, TEXT))
	_ws_actions = VBoxContainer.new()
	_ws_actions.add_theme_constant_override("separation", 6)
	right.add_child(_ws_actions)
	row.add_child(right)
	_ws_status = _label("", 18, DIM)
	box.add_child(_ws_status)
	var back := _button(U.t("Back"), _back)
	box.add_child(back)
	_first_focus["workshop"] = back


func _refresh_workshop() -> void:
	_shop_refresh_head("workshop")
	_clear_box(_ws_list)
	var guns := _player_guns()
	var still := false
	for e in guns:
		var g: Gun = e[0]
		if g == _ws_gun:
			still = true
		var b := _gun_row(g, "%s (%s)" % [g.gun_name, _gun_where(e)], _ws_select.bind(g), _ws_prev)
		_ws_list.add_child(b)
	if not still:
		_ws_gun = Game.main.player.gun()
	_ws_fill_actions()
	_grab_first(_ws_list)


func _ws_select(g: Gun) -> void:
	_ws_gun = g
	_ws_partner = null
	_ws_fill_actions()


func _ws_fill_actions() -> void:
	_clear_box(_ws_actions)
	var g := _ws_gun
	if g == null:
		return
	_ws_prev.show_gun(g)
	_ws_actions.add_child(_label(g.gun_name, 18, g.rarity_color(), false, HORIZONTAL_ALIGNMENT_LEFT))
	if _ws_pick.get("gun") == g:
		_ws_fill_pick(g)
		return
	if _ws_partner != null and _ws_player_has(_ws_partner):
		_ws_fill_combine(g, _ws_partner)
		return
	_ws_partner = null
	if Shops.can_rarity_up(g):
		var rp := Shops.rarity_up_price(g)
		var rb := _small_button(U.tm("Raise rarity: %s — %d", [U.t(str(GunData.RARITIES[g.rarity + 1]["name"])), U.money(rp)]),
			_ws_rarity, 460.0)
		rb.disabled = Game.coins < rp
		_ws_actions.add_child(rb)
	var rr := Shops.reroll_price(g)
	var perks := GunGen.rerollable(g)
	if perks.is_empty():
		_ws_actions.add_child(_label(U.t("No perks to reroll"), 16, DIM, false, HORIZONTAL_ALIGNMENT_LEFT))
	for id in perks:
		var nm := I18n.word(str(GunData.perk(str(id)).get("name", id)), "m")
		var pb := _small_button(U.tm("Reroll «%s» (pick 1 of 3) — %d", [nm, U.money(rr)]), _ws_reroll.bind(str(id)), 460.0)
		pb.disabled = Game.coins < rr
		_ws_actions.add_child(pb)
	_ws_fill_combine_list(g)


func _ws_player_has(g: Gun) -> bool:
	var p: Player = Game.main.player
	return p.guns.has(g) or p.backpack.has(g)


## Три перка на выбор вместо сброшенного (деньги уже заплачены).
func _ws_fill_pick(g: Gun) -> void:
	var drop := str(_ws_pick["drop"])
	var dn := I18n.word(str(GunData.perk(drop).get("name", drop)), "m")
	var hd := _label(U.t("Pick a replacement for «%s»:") % dn, 17, Color(0.75, 1.0, 0.55), false, HORIZONTAL_ALIGNMENT_LEFT)
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ws_actions.add_child(hd)
	for id in _ws_pick["options"]:
		var d := GunData.perk(str(id))
		var nm := I18n.word(str(d.get("name", id)), "m")
		_ws_actions.add_child(_small_button(nm, _ws_choose.bind(str(id)), 460.0))
		var fx := _label(", ".join(PackedStringArray(GunOps.describe(d.get("ops", [])))), 14, DIM, false, HORIZONTAL_ALIGNMENT_LEFT)
		fx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fx.custom_minimum_size = Vector2(460, 0)
		_ws_actions.add_child(fx)


func _ws_choose(id: String) -> void:
	var g: Gun = _ws_pick.get("gun")
	if g == null or not _ws_player_has(g):
		_ws_pick = {}
		_refresh_workshop()
		return
	var drop := str(_ws_pick["drop"])
	_ws_pick = {}
	var ng := GunGen.rebuild(g, g.rarity, drop, Game.main.rng, id)
	_ws_replace(g, ng)
	_ws_status.text = U.t("Rebuilt: %s") % ng.gun_name
	_refresh_workshop()


## Список «с чем объединить»: другие обычные пушки, которые подходят (хотя бы в одну сторону).
func _ws_fill_combine_list(g: Gun) -> void:
	_ws_actions.add_child(_gap(6))
	_ws_actions.add_child(_label(U.t("Combine guns"), 18, TEXT, false, HORIZONTAL_ALIGNMENT_LEFT))
	if g.legendary != "" or g.archetype2 != "":
		_ws_actions.add_child(_label(U.t("Legendary and hybrid guns can't be combined"), 16, DIM, false, HORIZONTAL_ALIGNMENT_LEFT))
		return
	var any := false
	for e in _player_guns():
		var h: Gun = e[0]
		if GunGen.combine_block(g, h) != "" and GunGen.combine_block(h, g) != "":
			continue
		any = true
		var price := Shops.combine_price(g, h)
		var b := _small_button(U.tm("With «%s» — %d", [h.gun_name, U.money(price)]), _ws_pick_partner.bind(h), 460.0)
		b.disabled = Game.coins < price
		_ws_actions.add_child(b)
	if not any:
		_ws_actions.add_child(_label(U.t("No suitable gun to combine with"), 16, DIM, false, HORIZONTAL_ALIGNMENT_LEFT))


func _ws_pick_partner(h: Gun) -> void:
	_ws_partner = h
	_ws_fill_actions()


## Выбор, как объединить: кто даёт узор стрельбы (и марку), а чьи снаряд и патроны.
func _ws_fill_combine(g: Gun, h: Gun) -> void:
	var price := Shops.combine_price(g, h)
	var hd := _label(U.t("Who shoots and who loads? Both guns are consumed — {0}").replace("{0}", U.tm("price %d", [U.money(price)])),
		16, Color(0.75, 1.0, 0.55), false, HORIZONTAL_ALIGNMENT_LEFT)
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hd.custom_minimum_size = Vector2(460, 0)
	_ws_actions.add_child(hd)
	for dir in [[g, h], [h, g]]:
		var pat: Gun = dir[0]
		var am: Gun = dir[1]
		if GunGen.combine_block(pat, am) != "":
			continue
		var t := Gun.new()
		t.archetype = pat.archetype
		t.archetype2 = am.archetype
		var l := _label(U.t("«%s» shoots, «%s» loads") % [pat.gun_name, am.gun_name], 14, DIM, false, HORIZONTAL_ALIGNMENT_LEFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(460, 0)
		_ws_actions.add_child(l)
		var b := _small_button(t.type_name(), _ws_combine.bind(pat, am), 460.0)
		b.disabled = Game.coins < price
		_ws_actions.add_child(b)
	_ws_actions.add_child(_small_button(U.t("Cancel"), _ws_cancel_combine, 460.0))


func _ws_cancel_combine() -> void:
	_ws_partner = null
	_ws_fill_actions()


## Объединить: результат встаёт на место выбранной пушки (_ws_gun), вторая пропадает.
func _ws_combine(pat: Gun, am: Gun) -> void:
	var g := _ws_gun
	var other: Gun = am if pat == g else pat
	if g == null or not (pat == g or am == g) or not _ws_player_has(other) or GunGen.combine_block(pat, am) != "":
		return
	if not _ws_pay(Shops.combine_price(pat, am)):
		return
	var ng := GunGen.combine(pat, am, Game.main.rng)
	var p: Player = Game.main.player
	var i := p.guns.find(other)
	if i >= 0:
		p.guns[i] = null
		p.on_gun_changed()
	else:
		i = p.backpack.find(other)
		if i >= 0:
			p.backpack.remove_at(i)
	_ws_partner = null
	_ws_replace(g, ng)
	_ws_status.text = U.t("Combined: %s") % ng.gun_name
	_refresh_workshop()


## Заменить пушку игрока (там же, где лежала) на новую.
func _ws_replace(old: Gun, g: Gun) -> void:
	var p: Player = Game.main.player
	var i := p.guns.find(old)
	if i >= 0:
		p.guns[i] = g
		p.on_gun_changed()
	else:
		i = p.backpack.find(old)
		if i >= 0:
			p.backpack[i] = g
	_ws_gun = g
	Game.note_gun(g)


func _ws_pay(price: int) -> bool:
	if price <= 0 or Game.coins < price:
		Sfx.ui("ui/error", -6.0)
		return false
	Game.add_coins(-price)
	Sfx.ui("ui/scrap", -4.0)
	return true


func _ws_rarity() -> void:
	var g := _ws_gun
	if g == null or not Shops.can_rarity_up(g) or not _ws_pay(Shops.rarity_up_price(g)):
		return
	var ng := GunGen.rebuild(g, g.rarity + 1, "", Game.main.rng)
	_ws_replace(g, ng)
	_ws_status.text = U.t("Rebuilt: %s") % ng.gun_name
	_refresh_workshop()


func _ws_reroll(id: String) -> void:
	var g := _ws_gun
	if g == null or not (id in g.mods):
		return
	var opts := GunGen.reroll_options(g, id, Game.main.rng)
	if opts.is_empty():
		_ws_status.text = U.t("No perk fits this gun")
		Sfx.ui("ui/error", -6.0)
		return
	if not _ws_pay(Shops.reroll_price(g)):
		return
	_ws_pick = {"gun": g, "drop": id, "options": opts}   # платим сразу: закрыть и открыть заново — не способ получить другие три перка
	_ws_status.text = ""
	_ws_fill_actions()


# --- Дерево навыков (LevelTree): по экрану на ветку, вкладки сверху ---

func _build_tree(root: Control) -> void:
	for b in LevelTree.branches:
		var bid := str(b["id"])
		var box := _screen(root, "tree_" + bid)
		(_panels["tree_" + bid] as PanelContainer).add_theme_stylebox_override("panel", _card_style(LevelTree.branch_color(b), 30, 18))
		box.add_child(_label(U.t("SKILLS"), 52, LevelTree.branch_color(b), true))
		var tabs := HBoxContainer.new()
		tabs.alignment = BoxContainer.ALIGNMENT_CENTER
		tabs.add_theme_constant_override("separation", 10)
		box.add_child(tabs)
		for o in LevelTree.branches:
			var oid := str(o["id"])
			var tb := _small_button(LevelTree.branch_name(o), show_screen.bind("tree_" + oid), 210.0)
			if oid == bid:
				var col := LevelTree.branch_color(o)
				tb.add_theme_stylebox_override("normal", _box(Color(col, 0.28), col, 3))
				tb.add_theme_stylebox_override("hover", _box(Color(col, 0.38), col, 3))
				tb.add_theme_color_override("font_color", Color.WHITE)
			tabs.add_child(tb)
		var head := _label("", 20, Color(0.75, 1.0, 0.55))
		box.add_child(head)
		var lb := _list_box(1060, 440)
		box.add_child(lb[0])
		var back := _button(U.t("Back"), _back)
		box.add_child(back)
		_first_focus["tree_" + bid] = back
		_tree_ui[bid] = {"head": head, "rows": lb[1]}


func _refresh_tree(bid: String) -> void:
	var ui: Dictionary = _tree_ui.get(bid, {})
	if ui.is_empty():
		return
	var head: Label = ui["head"]
	var rows: VBoxContainer = ui["rows"]
	head.text = U.t("Level %d   ·   Skill points: %d   ·   Spent: %d") % [Game.hero_level, LevelTree.free_points(), LevelTree.spent_points()]
	_clear_box(rows)
	var bcol := LevelTree.branch_color(LevelTree.branch(bid))
	for n in LevelTree.branch_nodes(bid, LevelTree.current_hero()):
		rows.add_child(_tree_row(n, bid, bcol))
	_grab_first(rows)


## Карточка навыка (как карточка пушки): рамка цвета ветки, название и уровень, строки «сейчас / дальше ▲», справа кнопка покупки.
func _tree_row(n: Dictionary, bid: String, bcol: Color) -> Control:
	var id := str(n["id"])
	var lv := LevelTree.level(id)
	var mx := LevelTree.max_level(n)
	var why := LevelTree.block(id)
	var locked := why == "req" or why == "class"
	var outer := HBoxContainer.new()
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(26.0 * float(int(n.get("tier", 1)) - 1), 0)
	outer.add_child(pad)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_style(Color(0.4, 0.4, 0.46) if locked else (bcol if lv > 0 or why == "" else bcol.darkened(0.45)), 16, 10, 4))
	outer.add_child(card)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	card.add_child(hb)
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(760, 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	hb.add_child(info)
	# название слева, уровень справа
	var th := HBoxContainer.new()
	var title := U.t(str(n.get("name", id)))
	var hero := str(n.get("hero", ""))
	if hero != "":
		title += "   · " + Heroes.hero_name(hero)
	var tl := _label(title, 22, DIM if locked else (bcol.lightened(0.3) if lv > 0 else TEXT), true, HORIZONTAL_ALIGNMENT_LEFT)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tl)
	th.add_child(_label((U.t("Lv %d/%d") % [lv, mx]) if mx > 0 else (U.t("Lv %d") % lv), 20, bcol.lightened(0.2) if lv > 0 else DIM, true, HORIZONTAL_ALIGNMENT_RIGHT))
	info.add_child(th)
	if lv > 0:
		info.add_child(_tree_stat_row(U.t("Now"), LevelTree.describe(n, lv), TEXT if not locked else DIM, false))
	if why != "max":
		info.add_child(_tree_stat_row(U.t("Next level") if lv > 0 else U.t("Level 1"), LevelTree.describe(n, lv + 1),
			Color(0.6, 0.95, 0.7) if not locked else DIM, not locked))
	if LevelTree.scales_with_hero(n):
		info.add_child(_tree_stat_row(U.t("Hero level"), "×" + U.fmt(float(Game.hero_level)), DIM, false))
	if why == "req":
		var names: Array = []
		for r in n.get("requires", []):
			if LevelTree.level(str(r)) <= 0:
				names.append(U.t(str(LevelTree.node(str(r)).get("name", r))))
		info.add_child(_tree_stat_row(U.t("Requires"), ", ".join(PackedStringArray(names)), Color(1.0, 0.6, 0.45), false))
	elif why == "class":
		var rival := LevelTree.node(LevelTree.class_rival(n))
		info.add_child(_tree_stat_row(U.t("Excluded by"), U.t(str(rival.get("name", "?"))), Color(1.0, 0.6, 0.45), false))
	var btn := _small_button(
		U.t("MAX") if why == "max" else (U.t("Locked") if locked else U.t("Upgrade — %d") % LevelTree.cost_of(n, lv + 1)),
		_tree_buy.bind(id, bid), 230.0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.disabled = why != ""
	hb.add_child(btn)
	return outer


## Строка карточки: подпись слева (серым), значение справа; у «дальше» зелёная стрелка ▲, как в карточке пушки.
func _tree_stat_row(tag: String, text: String, col: Color, arrow: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var t := _label(tag, 15, DIM, false, HORIZONTAL_ALIGNMENT_LEFT)
	t.custom_minimum_size = Vector2(120, 0)
	t.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(t)
	var v := _label(text, 17, col, false, HORIZONTAL_ALIGNMENT_LEFT)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	if arrow:
		var ar := _label("▲", 14, Color(0.45, 1.0, 0.5), false, HORIZONTAL_ALIGNMENT_RIGHT)
		ar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(ar)
	return row


func _tree_buy(id: String, bid: String) -> void:
	if LevelTree.buy(id):
		Sfx.ui("pickup/relic", -8.0, 1.2)
	else:
		Sfx.ui("ui/error", -6.0)
	_refresh_tree(bid)


# --- Лекарь ---

func _build_healer(root: Control) -> void:
	var box := _screen(root, "healer")
	_shop_head(box, "healer", U.t("HEALER"))
	_healer_info = _label("", 22, TEXT)
	box.add_child(_healer_info)
	box.add_child(_gap(6))
	_healer_box = VBoxContainer.new()
	_healer_box.add_theme_constant_override("separation", 8)
	box.add_child(_healer_box)
	var back := _button(U.t("Back"), _back)
	box.add_child(back)
	_first_focus["healer"] = back


func _refresh_healer() -> void:
	_shop_refresh_head("healer")
	_clear_box(_healer_box)
	var p: Player = Game.main.player
	var lvl := int(Game.main.town.get("level", 1))
	_healer_info.text = U.t("Health: %s / %s   ·   Flasks: %d / %d") % [U.fmt(ceilf(p.hp)), U.fmt(p.max_hp), p.flasks, p.flask_max()]
	if bool(Game.run["no_heal"]):
		_healer_box.add_child(_label(U.t("Hardcore run — the healer won't touch you."), 18, DIM))
		return
	var hp_price := Shops.heal_price(lvl, 1.0 - p.hp / p.max_hp)
	var hb := _small_button(U.tm("Heal to full — %d", [U.money(hp_price)]) if hp_price > 0 else U.t("Health is full"), _heal_full, 560.0)
	hb.disabled = hp_price <= 0 or Game.coins < hp_price
	_healer_box.add_child(hb)
	var fp := Shops.flask_price(lvl)
	var need := p.flask_max() - p.flasks
	var fb := _small_button(U.tm("Fill a flask — %d", [U.money(fp)]) if need > 0 else U.t("Flasks are full"), _buy_flask.bind(1), 560.0)
	fb.disabled = need <= 0 or Game.coins < fp
	_healer_box.add_child(fb)
	if need > 1:
		var ab := _small_button(U.tm("Fill all (%d) — %d", [str(need), U.money(fp * need)]), _buy_flask.bind(need), 560.0)
		ab.disabled = Game.coins < fp * need
		_healer_box.add_child(ab)
	_grab_first(_healer_box)


func _heal_full() -> void:
	var p: Player = Game.main.player
	var price := Shops.heal_price(int(Game.main.town.get("level", 1)), 1.0 - p.hp / p.max_hp)
	if price <= 0 or Game.coins < price:
		Sfx.ui("ui/error", -6.0)
		return
	Game.add_coins(-price)
	p.heal(p.max_hp, true)
	_refresh_healer()


func _buy_flask(n: int) -> void:
	var p: Player = Game.main.player
	var price := Shops.flask_price(int(Game.main.town.get("level", 1))) * n
	if Game.coins < price or p.flasks + n > p.flask_max():
		Sfx.ui("ui/error", -6.0)
		return
	Game.add_coins(-price)
	p.add_flask(n)
	Sfx.ui("pickup/heal", -6.0, 1.2)
	_refresh_healer()


# --- Гильдия ---

func _build_guild(root: Control) -> void:
	var box := _screen(root, "guild")
	_shop_head(box, "guild", U.t("GUILD"))
	box.add_child(_label(U.t("A contract pays the moment it is done. One contract at a time."), 18, DIM))
	box.add_child(_gap(6))
	box.add_child(_label(U.t("Contracts on the board"), 22, TEXT))
	_guild_offers = VBoxContainer.new()
	_guild_offers.add_theme_constant_override("separation", 6)
	box.add_child(_guild_offers)
	box.add_child(_gap(6))
	_guild_active_title = _label("", 22, TEXT)
	box.add_child(_guild_active_title)
	_guild_active = VBoxContainer.new()
	_guild_active.add_theme_constant_override("separation", 6)
	box.add_child(_guild_active)
	var back := _button(U.t("Back"), _back)
	box.add_child(back)
	_first_focus["guild"] = back


func _refresh_guild() -> void:
	_shop_refresh_head("guild")
	_clear_box(_guild_offers)
	_clear_box(_guild_active)
	var offers: Array = Game.main.town.get("guild", [])
	if offers.is_empty():
		_guild_offers.add_child(_label(U.t("The board is empty."), 18, DIM))
	for q in offers:
		var b := _small_button(U.tm("Take: %s — +%d ancient coins, +%d coins", [Quests.text(q), str(int(q["reward"])), U.money(float(q["coins"]))]),
			_take_quest.bind(q), 1000.0)
		b.disabled = not Quests.can_take() or Quests.has_type(str(q["type"]))
		_guild_offers.add_child(b)
	_guild_active_title.text = U.t("Your contracts (%d/%d)") % [Quests.active.size(), Quests.MAX_ACTIVE]
	for i in Quests.active.size():
		var q: Dictionary = Quests.active[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := _label(U.tm("%s — +%d ancient, +%d coins", [Quests.line(q), str(int(q["reward"])), U.money(float(q["coins"]))]), 18, Color(0.6, 1.0, 1.0), false, HORIZONTAL_ALIGNMENT_LEFT)
		l.custom_minimum_size = Vector2(700, 0)
		row.add_child(l)
		row.add_child(_small_button(U.t("Abandon"), _abandon_quest.bind(i), 190.0))
		_guild_active.add_child(row)
	_grab_first(_guild_offers)


func _take_quest(q: Dictionary) -> void:
	if Quests.take(q):
		var offers: Array = Game.main.town.get("guild", [])
		offers.erase(q)
		Sfx.ui("ui/put", -6.0)
	else:
		Sfx.ui("ui/error", -6.0)
	_refresh_guild()


func _abandon_quest(i: int) -> void:
	Quests.abandon(i)
	Sfx.ui("ui/close", -8.0)
	_refresh_guild()


## Вербовщик в стартовом городе: герои, их навыки, открытие за древние монеты, выбор.
## Список строится заново при каждом открытии (_refresh_heroes).
func _build_heroes(root: Control) -> void:
	var box := _screen(root, "heroes")
	box.add_child(_label(U.t("HEROES"), 52, ACCENT, true))
	_heroes_coins = _label("", 20, Color(0.6, 1.0, 1.0))
	box.add_child(_heroes_coins)
	box.add_child(_gap(8))
	_heroes_list = VBoxContainer.new()
	_heroes_list.add_theme_constant_override("separation", 12)
	box.add_child(_heroes_list)
	box.add_child(_gap(8))
	var back := _button(U.t("Back"), _back)
	box.add_child(back)
	_first_focus["heroes"] = back


func _refresh_heroes() -> void:
	_heroes_coins.text = U.t("Ancient coins: %s") % U.fmt(float(Game.meta_coins))
	for c in _heroes_list.get_children():
		_heroes_list.remove_child(c)
		c.queue_free()
	var first: Button = null
	for id in Heroes.ORDER:
		var h := Heroes.get_hero(str(id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		var info := VBoxContainer.new()
		info.custom_minimum_size = Vector2(720, 0)
		info.add_child(_label(Heroes.hero_name(str(id)), 26, Heroes.color(str(id)), true, HORIZONTAL_ALIGNMENT_LEFT))
		var d := _label(U.t(str(h["skill_name"])) + ": " + Heroes.describe(str(id)), 18, TEXT, false, HORIZONTAL_ALIGNMENT_LEFT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(720, 0)
		info.add_child(d)
		row.add_child(info)
		var b: Button
		if Game.hero == str(id):
			b = _button(U.t("Selected"), func() -> void: pass)
			b.disabled = true
		elif Game.hero_unlocked(str(id)):
			b = _button(U.t("Choose"), _choose_hero.bind(str(id)))
		else:
			var price := int(h["price"])
			b = _button(U.t("Unlock: %d ancient coins") % price, _unlock_hero.bind(str(id)))
			b.disabled = Game.meta_coins < price
		b.custom_minimum_size = Vector2(340, 58)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
		_heroes_list.add_child(row)
		if first == null and not b.disabled:
			first = b
	if first != null and Controls.mode == "pad":
		first.grab_focus.call_deferred()


func _choose_hero(id: String) -> void:
	if Game.select_hero(id):
		Game.say(U.t("Hero: %s") % Heroes.hero_name(id), Heroes.color(id))
	_refresh_heroes()


func _unlock_hero(id: String) -> void:
	if Game.unlock_hero(id):
		Sfx.ui("pickup/relic", -4.0)
		Game.select_hero(id)
		Game.say(U.t("Unlocked: %s") % Heroes.hero_name(id), Heroes.color(id))
	else:
		Sfx.ui("ui/error", -6.0)
	_refresh_heroes()


## Настраиваемый старт: сложность, переключатели, стартовая пушка, сид.
## Значения правятся прямо в Game.custom и сохраняются при старте.
func _build_custom(root: Control) -> void:
	var box := _screen(root, "custom")
	box.add_child(_label(U.t("CUSTOM START"), 52, ACCENT, true))
	box.add_child(_gap(8))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)

	# Сложность: пресеты + ручные ползунки
	grid.add_child(_label(U.t("Difficulty"), 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	for i in Game.DIFFICULTY.size():
		var d: Dictionary = Game.DIFFICULTY[i]
		var pb := _button(U.t(str(d["n"])), _on_preset.bind(i))
		pb.custom_minimum_size = Vector2(150, 46)
		pb.add_theme_font_size_override("font_size", 20)
		presets.add_child(pb)
	grid.add_child(presets)
	_custom_preset = _label("", 20, DIM, false, HORIZONTAL_ALIGNMENT_LEFT)
	_custom_preset.custom_minimum_size = Vector2(130, 0)
	grid.add_child(_custom_preset)
	_custom_slider(grid, "hp", U.t("Enemy health"))
	_custom_slider(grid, "dmg", U.t("Enemy damage"))

	_custom_check(grid, "zone_heal", U.t("Full heal when entering a new zone"))
	_custom_check(grid, "no_normals", U.t("No regular enemies (elites only)"))
	_custom_check(grid, "chests", U.t("Chests"))
	_custom_check(grid, "no_heal", U.t("Hardcore: no flasks, healer or lifesteal"))
	_custom_check(grid, "chaos", U.t("Chaos: all gun rarities and enemy types equally likely"))
	_custom_check(grid, "towns", U.t("Towns between stages"))

	# Стартовая пушка
	var arch_ids: Array = ["random"]
	var arch_names: Array = [U.t("Random")]
	for k in GunData.ARCH:
		arch_ids.append(k)
		arch_names.append(U.t(str(GunData.ARCH[k].get("name", k))))
	_custom_option(grid, "arch", U.t("Starting gun: type"), arch_ids, arch_names, "pistol")
	var mk_ids: Array = ["random"]
	var mk_names: Array = [U.t("Random")]
	for k in GunData.MAKERS:
		mk_ids.append(k)
		mk_names.append(U.t(str(GunData.MAKERS[k].get("name", k))))
	_custom_option(grid, "maker", U.t("Starting gun: brand"), mk_ids, mk_names, "synergis")

	# Сид
	grid.add_child(_label(U.t("Seed"), 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	_custom_seed = LineEdit.new()
	_custom_seed.placeholder_text = U.t("empty — random")
	_custom_seed.custom_minimum_size = Vector2(340, 44)
	_custom_seed.max_length = 40
	_custom_seed.text_changed.connect(func(t: String) -> void: Game.custom["seed"] = t)
	grid.add_child(_custom_seed)
	grid.add_child(_label(U.t("number or text"), 16, DIM, false, HORIZONTAL_ALIGNMENT_LEFT))

	box.add_child(_gap(10))
	_custom_rating = _label("", 24, ACCENT, true)
	box.add_child(_custom_rating)
	box.add_child(_gap(8))
	var start := _button(U.t("Start"), _start_custom)
	box.add_child(start)
	_first_focus["custom"] = start
	box.add_child(_button(U.t("Reset"), _reset_custom))
	box.add_child(_button(U.t("Back"), _back_custom))


func _custom_slider(grid: GridContainer, key: String, title: String) -> void:
	grid.add_child(_label(title, 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	var s := HSlider.new()
	s.min_value = 0.1
	s.max_value = 2.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(340, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := _label("", 20, DIM, false, HORIZONTAL_ALIGNMENT_LEFT)
	s.value_changed.connect(_on_custom_slider.bind(key, val))
	grid.add_child(s)
	grid.add_child(val)
	_custom_ui[key] = [s, val]


func _custom_check(grid: GridContainer, key: String, title: String) -> void:
	grid.add_child(_label(title, 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	var c := CheckButton.new()
	c.toggled.connect(_on_custom_check.bind(key))
	grid.add_child(c)
	grid.add_child(_label(_bonus_text(key), 18, DIM, false, HORIZONTAL_ALIGNMENT_LEFT))
	_custom_ui[key] = [c, null]


func _on_custom_check(on: bool, key: String) -> void:
	Game.custom[key] = on
	_update_preset_label()


## Подсказка, как переключатель влияет на рейтинг.
func _bonus_text(key: String) -> String:
	for b in Game.RATING_BONUS:
		if b[0] == key:
			var v := float(b[2])
			var when := "" if bool(b[1]) else U.t("if off: ")
			return U.t("%srating %s%d%%") % [when, "+" if v > 0.0 else "−", roundi(absf(v) * 100.0)]
	return ""


## ids[i] — значение в Game.custom; dflt — что значит пустая строка (обычный старт).
func _custom_option(grid: GridContainer, key: String, title: String, ids: Array, names: Array, dflt: String) -> void:
	grid.add_child(_label(title, 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(340, 46)
	for i in names.size():
		o.add_item(str(names[i]), i)
	o.item_selected.connect(func(i: int) -> void: Game.custom[key] = str(ids[i]))
	grid.add_child(o)
	grid.add_child(Control.new())
	_custom_ui[key] = [o, ids, dflt]


func _on_preset(i: int) -> void:
	var d: Dictionary = Game.DIFFICULTY[i]
	Game.custom["hp"] = float(d["hp"])
	Game.custom["dmg"] = float(d["dmg"])
	_refresh_custom()


func _on_custom_slider(v: float, key: String, val: Label) -> void:
	Game.custom[key] = v
	val.text = _fmt(v, "pct")
	_update_preset_label()


func _update_preset_label() -> void:
	if _custom_rating != null:
		_custom_rating.text = U.t("Rating and XP multiplier: ×%.2f") % Game.rating_mult(Game.custom)
	var t := U.t("custom")
	for d in Game.DIFFICULTY:
		if is_equal_approx(float(d["hp"]), float(Game.custom["hp"])) and is_equal_approx(float(d["dmg"]), float(Game.custom["dmg"])):
			t = U.t(str(d["n"])).to_lower()
	_custom_preset.text = t


func _refresh_custom() -> void:
	for key in _custom_ui:
		var row: Array = _custom_ui[key]
		var v: Variant = Game.custom.get(key, Game.RUN_DEFAULTS[key])
		if row[0] is HSlider:
			(row[0] as HSlider).set_value_no_signal(float(v))
			(row[1] as Label).text = _fmt(float(v), "pct")
		elif row[0] is CheckButton:
			(row[0] as CheckButton).set_pressed_no_signal(bool(v))
		elif row[0] is OptionButton:
			var ids: Array = row[1]
			var id := str(v) if str(v) != "" else str(row[2])
			(row[0] as OptionButton).select(maxi(0, ids.find(id)))
	_custom_seed.text = str(Game.custom.get("seed", ""))
	_update_preset_label()


func _reset_custom() -> void:
	Game.custom = Game.RUN_DEFAULTS.duplicate()
	_refresh_custom()


func _back_custom() -> void:
	Game.save_custom()
	_back()


func _start_custom() -> void:
	Game.save_custom()
	Game.main.start_game(Game.custom.duplicate())


func _build_settings(root: Control) -> void:
	var box := _screen(root, "settings")
	box.add_child(_label(U.t("SETTINGS"), 56, ACCENT, true))
	box.add_child(_gap(16))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.custom_minimum_size = Vector2(900, 620)
	box.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 14)
	sc.add_child(grid)
	_slider(grid, "master", U.t("Master volume"), 0.0, 1.0, 0.05, "pct")
	_slider(grid, "music_volume", U.t("Music"), 0.0, 1.0, 0.05, "pct")
	_check(grid, "music_muted", U.t("Music muted"))
	_slider(grid, "sfx_volume", U.t("Game sounds"), 0.0, 1.0, 0.05, "pct")
	_slider(grid, "ui_volume", U.t("Interface"), 0.0, 1.0, 0.05, "pct")
	_check(grid, "fullscreen", U.t("Fullscreen"))
	_check(grid, "vsync", U.t("V-Sync"))
	_slider(grid, "shake", U.t("Screen shake"), 0.0, 1.5, 0.05, "pct")
	_check(grid, "damage_numbers", U.t("Damage numbers"))
	_check(grid, "show_fps", U.t("Show FPS"))
	_slider(grid, "ui_scale", U.t("Interface size"), 0.7, 1.5, 0.05, "pct")
	_slider(grid, "ui_margin_x", U.t("Screen edge margin: sides"), 0.0, 160.0, 4.0, "px")
	_slider(grid, "ui_margin_y", U.t("Screen edge margin: top and bottom"), 0.0, 120.0, 4.0, "px")
	_check(grid, "ui_safe_area", U.t("Avoid the phone's notch and rounded corners"))
	grid.add_child(_label(U.t("Gun card on the ground"), 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	_card_opt = Button.new()
	_card_opt.custom_minimum_size = Vector2(340, 40)
	_card_opt.add_theme_font_size_override("font_size", 20)
	_card_opt.pressed.connect(_cycle_card)
	_card_opt.pressed.connect(func() -> void: Sfx.ui("ui/click", -6.0))
	grid.add_child(_card_opt)
	grid.add_child(Control.new())
	box.add_child(_gap(20))
	box.add_child(_button(U.t("Controls"), func() -> void: show_screen("controls")))
	var back := _button(U.t("Back"), func() -> void: show_screen(mode))
	box.add_child(back)
	_first_focus["settings"] = back


func _build_pause(root: Control) -> void:
	var box := _screen(root, "pause")
	box.add_child(_label(U.t("PAUSED"), 72, Color.WHITE, true))
	box.add_child(_gap(20))
	var b := _button(U.t("Resume"), func() -> void: Game.main.hud.toggle_pause())
	box.add_child(b)
	_first_focus["pause"] = b
	_pause_tree_btn = _button(U.t("Skill tree"), func() -> void: show_screen("tree_" + str(LevelTree.branches[0]["id"])))
	_pause_tree_btn.visible = not LevelTree.branches.is_empty()
	box.add_child(_pause_tree_btn)
	_pause_restart_btn = _button(U.t("Restart run"), _on_restart_pressed)
	box.add_child(_pause_restart_btn)
	box.add_child(_button(U.t("Settings"), func() -> void: show_screen("settings")))
	box.add_child(_button(U.t("Codex"), func() -> void: show_screen("codex")))
	box.add_child(_button(U.t("Main menu"), func() -> void: Game.main.to_menu()))
	box.add_child(_gap(16))
	_pause_info = _label("", 18, ACCENT)
	box.add_child(_pause_info)
	box.add_child(_gap(12))
	_help_box = VBoxContainer.new()
	_help_box.add_theme_constant_override("separation", 4)
	box.add_child(_help_box)


## «Начать заново» из паузы: забег с теми же настройками (Main.start_run). Первое нажатие только просит подтвердить —
## потерять забег одним случайным кликом слишком легко.
func _on_restart_pressed() -> void:
	if not _restart_armed:
		_restart_armed = true
		_pause_restart_btn.text = U.t("Restart? Click again")
		return
	_restart_armed = false
	Game.main.hud.toggle_pause()   # снять паузу и закрыть меню
	Game.main.start_run()


## Подсказка по управлению в паузе — под то, чем играют сейчас (клавиатура / геймпад / сенсор).
func _fill_help() -> void:
	for c in _help_box.get_children():
		_help_box.remove_child(c)
		c.queue_free()
	var lines: Array = []
	match Controls.mode:
		"kbm":
			lines = [
				U.t("%s — move, mouse — aim, %s — shoot") % [Controls.move_label(), Controls.label("shoot")],
				U.t("%s — dodge: 4 s cooldown, 0.5 s if you actually dodged something") % Controls.label("dodge"),
				_skill_help(Controls.label("skill")),
				U.t("%s — reload · %s, %s — switch weapons") % [Controls.label("reload"), Controls.weapons_label(), Controls.label("last_weapon")],
				U.t("%s — pick up / open chest · %s — swap with current · %s — scrap for ammo") % [
					Controls.label("interact"), Controls.label("swap"), Controls.label("scrap")],
				U.t("%s — inventory · F3 — debug · %s — resume") % [Controls.label("inventory"), Controls.label("pause")],
				U.t("− / + and M — music · [ / ] — sounds"),
			]
		"pad":
			lines = [
				U.t("Left stick — move, right stick — aim, %s — shoot") % Controls.label("shoot"),
				U.t("%s — dodge: 4 s cooldown, 0.5 s if you actually dodged something") % Controls.label("dodge"),
				_skill_help(Controls.label("skill")),
				U.t("%s — reload · %s — switch weapons") % [Controls.label("reload"), Controls.weapons_label()],
				U.t("%s — pick up / open chest · %s — swap with current · %s — scrap for ammo") % [
					Controls.label("interact"), Controls.label("swap"), Controls.label("scrap")],
				U.t("%s — inventory · %s — resume") % [Controls.label("inventory"), Controls.label("pause")],
			]
			if bool(Game.setting("auto_aim")):
				lines.append(U.t("Auto-aim: shoot without the right stick — the gun aims at the nearest enemy"))
		"touch":
			lines = [
				U.t("Left stick — move, right stick — aim and shoot"),
				U.t("Dodge: 4 s cooldown, 0.5 s if you actually dodged something"),
				_skill_help(U.t("Skill")),
			]
			if bool(Game.setting("auto_aim")):
				lines[0] = U.t("Left stick — move, hold FIRE — shoot at the nearest enemy")
	lines.append("")
	lines.append(U.t("No regen. Flasks heal 20%: up to 3, refilled by the town healer. Levels only give skill points — the rest is guns."))
	for l in lines:
		_help_box.add_child(_label(str(l), 17, DIM))


## Строка помощи про навык героя: «ПКМ — Граната (Первопроходец): ...».
func _skill_help(key: String) -> String:
	var id := Game.main.player.hero if Game.main != null and Game.main.player != null else Game.hero
	return U.t("%s — %s (%s): %s") % [key, U.t(str(Heroes.get_hero(id)["skill_name"])), Heroes.hero_name(id), Heroes.describe(id)]


# --- Настройки: строки ------------------------------------------------------------

func _slider(grid: GridContainer, key: String, title: String, lo: float, hi: float, step: float, fmt: String) -> void:
	grid.add_child(_label(title, 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(340, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := _label("", 20, DIM, false, HORIZONTAL_ALIGNMENT_LEFT)
	val.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(_on_slider.bind(key, val, fmt))
	grid.add_child(s)
	grid.add_child(val)
	_settings_ui[key] = [s, val, fmt]


func _check(grid: GridContainer, key: String, title: String) -> void:
	grid.add_child(_label(title, 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	var c := CheckButton.new()
	c.focus_mode = Control.FOCUS_ALL
	c.toggled.connect(func(on: bool) -> void: Game.set_setting(key, on))
	grid.add_child(c)
	grid.add_child(Control.new())
	_settings_ui[key] = [c, null, ""]


func _on_slider(v: float, key: String, val: Label, fmt: String) -> void:
	val.text = _fmt(v, fmt)
	Game.set_setting(key, v)


## Подтянуть значения: громкость могли поменять горячими клавишами.
func _refresh_settings() -> void:
	if _card_opt != null:
		_card_opt.text = U.t(str(CARD_MODES.get(str(Game.setting("gun_card")), "On the right")))
	for key in _settings_ui:
		var row: Array = _settings_ui[key]
		var v: Variant = Game.setting(str(key))
		if row[0] is HSlider:
			(row[0] as HSlider).set_value_no_signal(float(v))
			(row[1] as Label).text = _fmt(float(v), str(row[2]))
		else:
			(row[0] as CheckButton).set_pressed_no_signal(bool(v))


func _fmt(v: float, fmt: String) -> String:
	if fmt == "pct":
		return "%d%%" % roundi(v * 100.0)
	if fmt == "px":
		return "%d" % roundi(v)
	return str(v)


## Строка о забеге: сид и отличия от обычной игры.
static func run_info() -> String:
	var parts := PackedStringArray([U.t("Seed: %d") % Game.seed_value, U.t("rating and XP ×%.2f") % Game.rating_mult()])
	var r := Game.run
	if not (is_equal_approx(float(r["hp"]), 1.0) and is_equal_approx(float(r["dmg"]), 1.0)):
		parts.append(U.t("enemies: health %d%%, damage %d%%") % [roundi(float(r["hp"]) * 100.0), roundi(float(r["dmg"]) * 100.0)])
	if bool(r["zone_heal"]):
		parts.append(U.t("heal between zones"))
	if bool(r["no_normals"]):
		parts.append(U.t("elites only"))
	if bool(r["chests"]):
		parts.append(U.t("chests"))
	if bool(r["no_heal"]):
		parts.append(U.t("hardcore"))
	if bool(r["chaos"]):
		parts.append(U.t("chaos"))
	if not bool(r.get("towns", true)):
		parts.append(U.t("no towns"))
	return " · ".join(parts)


func _records_text() -> String:
	var meta := U.t("Ancient coins: %s") % U.fmt(float(Game.meta_coins)) if Game.meta_coins > 0 else ""
	if Game.best_zone <= 0 and Game.best_rating <= 0:
		return U.t("No records yet") + ("  ·  " + meta if meta != "" else "")
	return U.t("Best: zone %d · kills in a run: %d · best rating: %s") % [
		Game.best_zone, Game.best_kills, U.fmt(float(Game.best_rating))] + ("  ·  " + meta if meta != "" else "")


# --- Конструкторы ---------------------------------------------------------------

## top = true: экран прижат к верху, а не по центру. Нужен экранам с карточкой пушки: высота их содержимого не должна
## двигать заголовок и списки, когда карточка меняется (у Кузни хаоса она выше обычных).
## Все экраны, кроме главного, стоят в рамке-панели «как у карточки пушки» (цвет — лавка или ветка дерева).
func _screen(root: Control, sname: String, top: bool = false) -> VBoxContainer:
	var framed := sname != "main"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var holder: Control = box
	if framed:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", _card_style(SCREEN_ACCENT.get(sname, ACCENT), 30, 18))
		panel.add_child(box)
		holder = panel
		_panels[sname] = panel
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


## Рамка как у карточки пушки: фон PANEL_BG, полоса accent сверху (6 px), рамка accent (2 px).
func _card_style(accent: Color, mx: int = 14, my: int = 10, top_bar: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = Color(accent, 0.85)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_width_top = top_bar
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	return sb


func _label(text: String, fsize: int, col: Color, bold: bool = false,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", U.font_bold())
		l.add_theme_constant_override("outline_size", 10)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	b.pressed.connect(func() -> void: Sfx.ui("ui/click", -6.0))
	b.mouse_entered.connect(_on_hover.bind(b))
	return b


func _on_hover(b: Button) -> void:
	if not b.disabled:
		Sfx.ui("ui/hover", -12.0, 1.0, 0.05)


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _box(bgc: Color, border: Color, bw: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bgc
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = U.font()
	th.default_font_size = 22
	th.set_font("font", "Button", U.font_bold())
	th.set_font_size("font_size", "Button", 26)
	th.set_stylebox("normal", "Button", _box(Color(0.07, 0.07, 0.11, 0.88), Color(0.3, 0.3, 0.42)))
	th.set_stylebox("hover", "Button", _box(Color(0.16, 0.12, 0.2, 0.95), ACCENT))
	th.set_stylebox("pressed", "Button", _box(Color(0.35, 0.18, 0.08, 0.95), ACCENT))
	th.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), ACCENT.lightened(0.2), 3))
	th.set_stylebox("disabled", "Button", _box(Color(0.05, 0.05, 0.07, 0.6), Color(0.2, 0.2, 0.25)))
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color(1.0, 0.85, 0.55))
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_focus_color", "Button", Color(1.0, 0.85, 0.55))
	th.set_color("font_disabled_color", "Button", Color(0.4, 0.4, 0.45))
	th.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	th.set_constant("outline_size", "Label", 4)
	var track := _box(Color(0.12, 0.12, 0.18), Color(0.3, 0.3, 0.42), 1)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	th.set_stylebox("slider", "HSlider", track)
	var fill := _box(ACCENT.darkened(0.2), ACCENT, 1)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return th
