class_name ControlsScreen
extends MenuScreen
## «Управление»: автоприцел, экранные кнопки, переназначение клавиш и кнопок геймпада.

var _bind_buttons := {}   # "действие:колонка" -> кнопка
var _listening := ""      # "действие:колонка", пока ждём нажатия; "" — не ждём
var _listen_t := 0.0
var _controls_status: Label
var _touch_opt: Button
const LISTEN_TIME := 6.0
var _settings: SettingsScreen   # ползунки и переключатели «Управления» живут в реестре настроек


## Экран «Управление»: автоприцел, экранные кнопки и переназначение клавиш и кнопок геймпада.
func build(root: Control) -> void:
	_settings = menu.screen_of("settings") as SettingsScreen
	_bind_buttons.clear()
	_listening = ""
	var holder := MarginContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		holder.add_theme_constant_override("margin_" + side, 40)
	root.add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_register("controls", holder)
	var panel := PanelContainer.new()
	var sb := MenuKit.box(Color(0.035, 0.035, 0.06, 0.95), Color(0.3, 0.3, 0.42))
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)
	var title := MenuKit.label(U.t("CONTROLS"), 40, ACCENT, true, HORIZONTAL_ALIGNMENT_LEFT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var reset := MenuKit.button(U.t("Reset to defaults"), _reset_binds)
	reset.custom_minimum_size = Vector2(0, 48)
	top.add_child(reset)
	var back := MenuKit.button(U.t("Back"), func() -> void: menu.show_screen("settings"))
	back.custom_minimum_size = Vector2(200, 48)
	top.add_child(back)
	menu.first_focus["controls"] = back

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
	_settings.check(opts, "auto_aim", U.t("Auto-aim (gamepad and touch)"))
	_settings.check(opts, "auto_fire", U.t("Auto-fire at visible enemies (gamepad and touch)"))
	opts.add_child(MenuKit.label(U.t("Touch controls"), 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	_touch_opt = Button.new()
	_touch_opt.custom_minimum_size = Vector2(340, 40)
	_touch_opt.add_theme_font_size_override("font_size", 20)
	_touch_opt.pressed.connect(_cycle_touch)
	_touch_opt.pressed.connect(func() -> void: Sfx.ui("ui/click", -6.0))
	opts.add_child(_touch_opt)
	opts.add_child(Control.new())
	_settings.check(opts, "touch_static", U.t("Fixed sticks (don't follow the finger)"))
	_settings.check(opts, "touch_tap_fire", U.t("Tap to shoot at that point (instead of the right stick)"))
	_settings.slider(opts, "touch_scale", U.t("Touch controls size"), 0.6, 1.6, 0.05, "pct")
	opts.add_child(Control.new())
	var edit := MenuKit.button(U.t("Edit touch layout"), _edit_touch_layout)
	edit.custom_minimum_size = Vector2(340, 48)
	edit.add_theme_font_size_override("font_size", 20)
	opts.add_child(edit)
	opts.add_child(Control.new())
	opts.add_child(Control.new())
	var rel := MenuKit.button(U.t("Fire on release…"), func() -> void: menu.show_screen("release"))
	rel.custom_minimum_size = Vector2(340, 48)
	rel.add_theme_font_size_override("font_size", 20)
	opts.add_child(rel)
	opts.add_child(MenuKit.label(U.t("per gun type"), 16, DIM, false, HORIZONTAL_ALIGNMENT_LEFT))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	inner.add_child(grid)
	grid.add_child(MenuKit.label("", 18, DIM))
	grid.add_child(MenuKit.label(U.t("Keyboard and mouse"), 18, DIM, true))
	grid.add_child(MenuKit.label(U.t("Gamepad"), 18, DIM, true))
	for row in InputSetup.REBINDABLE:
		var action := str(row[0])
		var name_l := MenuKit.label(U.t(str(row[1])), 20, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_l)
		for col in ["kb", "pad"]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(300, 38)
			b.add_theme_font_size_override("font_size", 18)
			b.pressed.connect(_start_listening.bind(action, col))
			MenuKit.hover_sfx(b)
			if action.begins_with("aim_") and col == "kb":
				b.disabled = true    # прицел с клавиатуры — мышью
			grid.add_child(b)
			_bind_buttons[action + ":" + col] = b
	_controls_status = MenuKit.label(U.t("Click a binding, then press a key or a gamepad button. Delete — clear."), 16, DIM, false,
		HORIZONTAL_ALIGNMENT_LEFT)
	_controls_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_controls_status)


func refresh(_sname: String = "") -> void:
	_settings.refresh()
	_touch_opt.text = U.t({"auto": "Auto (when playing with fingers)", "on": "Always", "off": "Off"}.get(
		str(Game.settings.get_value("touch_controls")), "Auto (when playing with fingers)"))
	for key in _bind_buttons:
		var parts := str(key).split(":")
		var b: Button = _bind_buttons[key]
		if b.disabled:
			b.text = U.t("mouse")
		else:
			b.text = InputSetup.action_label(parts[0], parts[1], 3)


func _edit_touch_layout() -> void:
	menu.visible = false
	Game.main.touch.start_edit(_end_touch_edit)


func _end_touch_edit() -> void:
	menu.visible = true
	menu.show_screen("controls")


func _cycle_touch() -> void:
	var order := ["auto", "on", "off"]
	var i := order.find(str(Game.settings.get_value("touch_controls")))
	Game.settings.set_value("touch_controls", order[(i + 1) % order.size()])
	refresh()


func _start_listening(action: String, col: String) -> void:
	_stop_listening()
	_listening = action + ":" + col
	_listen_t = LISTEN_TIME


func _stop_listening() -> void:
	_listening = ""
	if menu.current == "controls":
		refresh()


func _apply_bind(action: String, col: String, ev: InputEvent) -> void:
	InputSetup.rebind(action, col, ev)
	_listening = ""
	Game.settings.set_value("binds", JSON.stringify(InputSetup.current_binds()))
	Sfx.ui("ui/click", -6.0)
	if ev != null:
		_controls_status.text = U.t("%s: %s") % [U.t(_action_title(action)), InputSetup.event_name(ev)]
	refresh()


func _action_title(action: String) -> String:
	for row in InputSetup.REBINDABLE:
		if str(row[0]) == action:
			return str(row[1])
	return action


func _reset_binds() -> void:
	_listening = ""
	Game.settings.set_value("binds", "")
	_controls_status.text = U.t("Controls reset to defaults.")
	refresh()


# --- Лавки города: Оружейная, Мистик, Мастерская, Гильдия ------------------------------
## Товар — Game.main.town (Shops.make_town), цены — Shops, задания — Quests.


func back_target() -> String:
	return "settings"


## Пока ждём нажатия клавиши, меню не обрабатывает Esc и отдаёт событие сюда.
func captures_input() -> bool:
	return _listening != ""


func process(delta: float) -> void:
	if _listening != "":
		_listen_t -= delta
		var b: Button = _bind_buttons.get(_listening)
		if _listen_t <= 0.0:
			_stop_listening()
		elif b != null:
			b.text = U.t("Press… %d") % ceili(_listen_t)


## Ждём клавишу или кнопку для привязки: ловим событие раньше всех (меню и кнопки его не получат).
func handle_input(event: InputEvent) -> void:
	var parts := _listening.split(":")
	var action := parts[0]
	var col := parts[1]
	var ev: InputEvent = null
	if col == "kb":
		if event is InputEventKey and event.is_pressed() and not event.is_echo():
			var k := event as InputEventKey
			if k.physical_keycode == KEY_DELETE or k.keycode == KEY_DELETE:
				_apply_bind(action, col, null)
				menu.get_viewport().set_input_as_handled()
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
			menu.get_viewport().set_input_as_handled()
			return
	if ev == null:
		return
	menu.get_viewport().set_input_as_handled()
	_apply_bind(action, col, ev)
