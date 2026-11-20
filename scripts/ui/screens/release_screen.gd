class_name ReleaseScreen
extends MenuScreen
## «Стрельба по отпусканию» (сенсор): для каждого типа пушки — стрелять, пока держишь правый стик, или один раз при отпускании.

var _release_grid: GridContainer


## «Стрельба по отпусканию» (сенсор): для каждого типа пушки — стрелять, пока держишь правый стик,
## или целиться стиком и выстрелить один раз, когда отпустил. Настройка touch_release_fire (JSON).
func build(root: Control) -> void:
	var box := _screen(root, "release")
	box.add_child(MenuKit.label(U.t("FIRE ON RELEASE"), 48, ACCENT, true))
	var info := MenuKit.label(U.t("Touch: aim with the right stick and fire one shot when you let go. Hybrids follow their first type. Does not work with tap-to-shoot; auto-fire is off for these guns."), 18, DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(900, 0)
	box.add_child(info)
	box.add_child(MenuKit.gap(8))
	_release_grid = GridContainer.new()
	_release_grid.columns = 4
	_release_grid.add_theme_constant_override("h_separation", 18)
	_release_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_release_grid)
	box.add_child(MenuKit.gap(8))
	var back := MenuKit.button(U.t("Back"), func() -> void: menu.show_screen("controls"))
	box.add_child(back)
	menu.first_focus["release"] = back


func refresh(_sname: String = "") -> void:
	for c in _release_grid.get_children():
		_release_grid.remove_child(c)
		c.queue_free()
	var on := Game.controls.release_types()
	for k in GunData.ARCH:
		_release_grid.add_child(MenuKit.label(U.t(str(GunData.ARCH[k].get("name", k))), 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
		var c := CheckButton.new()
		c.focus_mode = Control.FOCUS_ALL
		c.button_pressed = bool(on.get(k, false))
		c.toggled.connect(_set_release.bind(str(k)))
		_release_grid.add_child(c)


func _set_release(enabled: bool, arch: String) -> void:
	var d := Game.controls.release_types().duplicate()
	if enabled:
		d[arch] = true
	else:
		d.erase(arch)
	Game.settings.set_value("touch_release_fire", JSON.stringify(d) if not d.is_empty() else "")


func back_target() -> String:
	return "controls"
