class_name ModsScreen
extends MenuScreen
## Список модов из папки Mods/ с переключателями; изменения применяются сразу.

## Сколько модов включено (для надписи на главном экране).
static func enabled_count() -> int:
	var n := 0
	for m in Mods.list:
		if bool(m["enabled"]):
			n += 1
	return n


## Список модов из папки Mods/ с переключателями. Изменения применяются сразу:
## перечитываются данные, переводы, звуки и музыка.
func build(root: Control) -> void:
	var box := _screen(root, "mods")
	box.add_child(MenuKit.label(U.t("MODS"), 56, ACCENT, true))
	box.add_child(MenuKit.label(U.t("Folder: %s") % Mods.root(), 16, DIM))
	box.add_child(MenuKit.gap(12))
	if Mods.list.is_empty():
		box.add_child(MenuKit.label(U.t("No mods found. Put a mod folder into the Mods folder and press Rescan."), 20, TEXT))
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
			var lb := MenuKit.label(line, 22, TEXT, false, HORIZONTAL_ALIGNMENT_LEFT)
			if info.has("description"):
				lb.tooltip_text = str(info["description"])
			grid.add_child(lb)
	box.add_child(MenuKit.gap(16))
	# отладчик модов: включается только перезапуском, чтобы в обычной игре ничего лишнего не грузилось
	var dbg := CheckButton.new()
	dbg.text = U.t("Mod debugger (F8)")
	dbg.button_pressed = bool(Game.settings.get_value("mod_debug"))
	dbg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dbg.add_theme_font_size_override("font_size", 22)
	dbg.toggled.connect(_on_debug_toggled)
	box.add_child(dbg)
	var pending := bool(Game.settings.get_value("mod_debug")) != Game.debug_log.enabled
	var note := MenuKit.label(U.t("Takes effect after restart"), 16, ACCENT)
	note.visible = pending
	box.add_child(note)
	var rb := MenuKit.button(U.t("Restart now"), Game.restart)
	rb.visible = pending
	box.add_child(rb)
	box.add_child(MenuKit.button(U.t("How to make mods"), _open_modding_page))
	box.add_child(MenuKit.button(U.t("Open mods folder"), open_mods_folder))
	box.add_child(MenuKit.button(U.t("Rescan"), _reload_mods))
	var back := MenuKit.button(U.t("Back"), func() -> void: menu.show_screen(menu.mode))
	box.add_child(back)
	menu.first_focus["mods"] = back


func _on_debug_toggled(on: bool) -> void:
	Game.settings.set_value("mod_debug", on)
	menu.rebuild.call_deferred()


func _on_mod_toggled(on: bool, id: String) -> void:
	Mods.set_enabled(id, on)
	_reload_mods()


func _reload_mods() -> void:
	Game.reload_content()
	menu.rebuild.call_deferred()


static func open_mods_folder() -> void:
	var path := Mods.root()
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
	OS.shell_open(path)


static func open_game_folder() -> void:
	OS.shell_open(Mods.base_dir())


## Справочник строится после списка модов, поэтому берём его экран только по нажатию.
func _open_modding_page() -> void:
	(menu.screen_of("codex") as CodexScreen).show_page("modding")
