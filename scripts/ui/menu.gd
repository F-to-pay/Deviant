class_name Menu
extends CanvasLayer
## Главное меню, пауза и настройки. Обычные Control-ы с темой из кода.
## Режимы: "main" — главное меню (фон MenuBg), "pause" — поверх игры (затемнение).
## Экран настроек общий, «Назад» возвращает в текущий режим.

const ACCENT := Color(1.0, 0.55, 0.2)
const TEXT := Color(0.9, 0.9, 0.95)
const DIM := Color(0.6, 0.6, 0.68)

var mode := "main"
var current := ""
var bg: MenuBg
var dim: ColorRect
var cursor: CursorDraw
var screens := {}
var records: Label
var _settings_ui := {}    # ключ -> [контрол, подпись значения или null, формат]
var _first_focus := {}    # экран -> кнопка, получающая фокус
var _custom_ui := {}      # ключ Game.custom -> [контрол, ...]
var _custom_preset: Label
var _custom_seed: LineEdit
var _custom_rating: Label
var _pause_info: Label
var _root: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	Game.settings_changed.connect(_on_setting)


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
	_build_settings(root)
	_build_pause(root)
	_build_mods(root)
	cursor = CursorDraw.new()
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cursor)
	cursor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_setting(key: String) -> void:
	if key == "language":
		_rebuild.call_deferred()


func _rebuild() -> void:
	var was := current
	remove_child(_root)
	_root.queue_free()
	screens.clear()
	_settings_ui.clear()
	_first_focus.clear()
	_custom_ui.clear()
	_build_ui()
	bg.visible = mode == "main"
	dim.visible = mode == "pause"
	records.text = _records_text()
	_pause_info.text = run_info()
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
	show_screen("pause")


func close() -> void:
	visible = false


func show_screen(sname: String) -> void:
	current = sname
	for k in screens:
		(screens[k] as Control).visible = k == sname
	if sname == "settings":
		_refresh_settings()
	elif sname == "custom":
		_refresh_custom()
	var b: Control = _first_focus.get(sname)
	if b != null:
		b.grab_focus.call_deferred()


func _process(_delta: float) -> void:
	if visible:
		cursor.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		if current == "custom":
			_back_custom()
		elif current != mode:
			show_screen(mode)
		elif mode == "pause":
			Game.main.hud.toggle_pause()
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
	_custom_check(grid, "no_heal", U.t("Hardcore: no health orbs or lifesteal"))
	_custom_check(grid, "chaos", U.t("Chaos: all gun rarities and enemy types equally likely"))

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
		_custom_rating.text = U.t("Rating multiplier: ×%.2f") % Game.rating_mult(Game.custom)
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
	show_screen(mode)


func _start_custom() -> void:
	Game.save_custom()
	Game.main.start_game(Game.custom.duplicate())


func _build_settings(root: Control) -> void:
	var box := _screen(root, "settings")
	box.add_child(_label(U.t("SETTINGS"), 56, ACCENT, true))
	box.add_child(_gap(16))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 14)
	box.add_child(grid)
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
	box.add_child(_gap(20))
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
	box.add_child(_button(U.t("Settings"), func() -> void: show_screen("settings")))
	box.add_child(_button(U.t("Main menu"), func() -> void: Game.main.to_menu()))
	box.add_child(_gap(16))
	_pause_info = _label("", 18, ACCENT)
	box.add_child(_pause_info)
	box.add_child(_gap(12))
	for l in [
		U.t("WASD — move, mouse — aim, LMB — shoot"),
		U.t("Space / Shift / RMB — dodge: 4 s cooldown, 0.5 s if you actually dodged something"),
		U.t("R — reload · 1-4, wheel, Q — switch weapons"),
		U.t("E — pick up / open chest · F — swap with current · X — scrap for ammo"),
		U.t("Tab / I — inventory · F3 — debug · Esc — resume"),
		U.t("− / + and M — music · [ / ] — sounds"),
		"",
		U.t("No regen. Max 2 health orbs per zone. No levels — only guns."),
	]:
		box.add_child(_label(str(l), 17, DIM))


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
	return str(v)


## Строка о забеге: сид и отличия от обычной игры.
static func run_info() -> String:
	var parts := PackedStringArray([U.t("Seed: %d") % Game.seed_value, U.t("rating ×%.2f") % Game.rating_mult()])
	var r := Game.run
	if not (is_equal_approx(float(r["hp"]), 1.0) and is_equal_approx(float(r["dmg"]), 1.0)):
		parts.append(U.t("enemies: health %d%%, damage %d%%") % [roundi(float(r["hp"]) * 100.0), roundi(float(r["dmg"]) * 100.0)])
	if bool(r["zone_heal"]):
		parts.append(U.t("heal between zones"))
	if bool(r["no_normals"]):
		parts.append(U.t("elites only"))
	if not bool(r["chests"]):
		parts.append(U.t("no chests"))
	if bool(r["no_heal"]):
		parts.append(U.t("hardcore"))
	if bool(r["chaos"]):
		parts.append(U.t("chaos"))
	return " · ".join(parts)


func _records_text() -> String:
	if Game.best_zone <= 0 and Game.best_rating <= 0:
		return U.t("No records yet")
	return U.t("Best: zone %d · kills in a run: %d · best rating: %s") % [
		Game.best_zone, Game.best_kills, U.fmt(float(Game.best_rating))]


# --- Конструкторы ---------------------------------------------------------------

func _screen(root: Control, sname: String) -> VBoxContainer:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	screens[sname] = center
	return box


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
