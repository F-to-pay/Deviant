class_name SettingsScreen
extends MenuScreen
## Настройки: громкость, экран, интерфейс. Ползунки и переключатели регистрируются в `_settings_ui` и обновляются в `refresh()`.

var _settings_ui := {}    # ключ -> [контрол, подпись значения или null, формат]
var _card_opt: Button
const CARD_MODES := {"right": "On the right", "left": "On the left", "above": "Above the gun"}


func _cycle_card() -> void:
	var order: Array = CARD_MODES.keys()
	var i := order.find(str(Game.settings.get_value("gun_card")))
	Game.settings.set_value("gun_card", order[(i + 1) % order.size()])
	_card_opt.text = U.t(str(CARD_MODES.get(str(Game.settings.get_value("gun_card")), "On the right")))


func build(root: Control) -> void:
	_settings_ui.clear()
	var box := _screen(root, "settings")
	box.add_child(MenuKit.label(U.t("SETTINGS"), 56, ACCENT, true))
	box.add_child(MenuKit.gap(16))
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
	slider(grid, "master", U.t("Master volume"), 0.0, 1.0, 0.05, "pct")
	slider(grid, "music_volume", U.t("Music"), 0.0, 1.0, 0.05, "pct")
	check(grid, "music_muted", U.t("Music muted"))
	slider(grid, "sfx_volume", U.t("Game sounds"), 0.0, 1.0, 0.05, "pct")
	slider(grid, "ui_volume", U.t("Interface"), 0.0, 1.0, 0.05, "pct")
	check(grid, "fullscreen", U.t("Fullscreen"))
	check(grid, "vsync", U.t("V-Sync"))
	slider(grid, "shake", U.t("Screen shake"), 0.0, 1.5, 0.05, "pct")
	check(grid, "damage_numbers", U.t("Damage numbers"))
	check(grid, "show_fps", U.t("Show FPS"))
	check(grid, "autosave", U.t("Autosave at the start of each zone and town"))
	slider(grid, "ui_scale", U.t("Interface size"), 0.7, 1.5, 0.05, "pct")
	slider(grid, "ui_margin_x", U.t("Screen edge margin: sides"), 0.0, 160.0, 4.0, "px")
	slider(grid, "ui_margin_y", U.t("Screen edge margin: top and bottom"), 0.0, 120.0, 4.0, "px")
	check(grid, "ui_safe_area", U.t("Avoid the phone's notch and rounded corners"))
	grid.add_child(MenuKit.label(U.t("Gun card on the ground"), 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	_card_opt = Button.new()
	_card_opt.custom_minimum_size = Vector2(340, 40)
	_card_opt.add_theme_font_size_override("font_size", 20)
	_card_opt.pressed.connect(_cycle_card)
	_card_opt.pressed.connect(func() -> void: Sfx.ui("ui/click", -6.0))
	grid.add_child(_card_opt)
	grid.add_child(Control.new())
	box.add_child(MenuKit.gap(20))
	box.add_child(MenuKit.button(U.t("Controls"), func() -> void: menu.show_screen("controls")))
	var back := MenuKit.button(U.t("Back"), func() -> void: menu.show_screen(menu.mode))
	box.add_child(back)
	menu.first_focus["settings"] = back


func slider(grid: GridContainer, key: String, title: String, lo: float, hi: float, step: float, fmt: String) -> void:
	grid.add_child(MenuKit.label(title, 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(340, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := MenuKit.label("", 20, DIM, false, HORIZONTAL_ALIGNMENT_LEFT)
	val.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(_on_slider.bind(key, val, fmt))
	grid.add_child(s)
	grid.add_child(val)
	_settings_ui[key] = [s, val, fmt]


func check(grid: GridContainer, key: String, title: String) -> void:
	grid.add_child(MenuKit.label(title, 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	var c := CheckButton.new()
	c.focus_mode = Control.FOCUS_ALL
	c.toggled.connect(func(on: bool) -> void: Game.settings.set_value(key, on))
	grid.add_child(c)
	grid.add_child(Control.new())
	_settings_ui[key] = [c, null, ""]


func _on_slider(v: float, key: String, val: Label, fmt: String) -> void:
	val.text = MenuKit.fmt(v, fmt)
	Game.settings.set_value(key, v)


## Подтянуть значения: громкость могли поменять горячими клавишами.
func refresh(_sname: String = "") -> void:
	if _card_opt != null:
		_card_opt.text = U.t(str(CARD_MODES.get(str(Game.settings.get_value("gun_card")), "On the right")))
	for key in _settings_ui:
		var row: Array = _settings_ui[key]
		var v: Variant = Game.settings.get_value(str(key))
		if row[0] is HSlider:
			(row[0] as HSlider).set_value_no_signal(float(v))
			(row[1] as Label).text = MenuKit.fmt(float(v), str(row[2]))
		else:
			(row[0] as CheckButton).set_pressed_no_signal(bool(v))
