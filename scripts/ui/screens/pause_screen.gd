class_name PauseScreen
extends MenuScreen
## Пауза: продолжить, дерево навыков, перезапуск, подсказки по управлению.

var _pause_tree_btn: Button
var _pause_restart_btn: Button   # «Начать заново»: первое нажатие просит подтверждения
var _pause_save_btn: Button      # «Сохранить»: виден при выключенном автосейве
var _restart_armed := false
var _pause_info: Label
var _help_box: VBoxContainer


func build(root: Control) -> void:
	var box := _screen(root, "pause")
	box.add_child(MenuKit.label(U.t("PAUSED"), 72, Color.WHITE, true))
	box.add_child(MenuKit.gap(20))
	var b := MenuKit.button(U.t("Resume"), func() -> void: Game.main.hud.toggle_pause())
	box.add_child(b)
	menu.first_focus["pause"] = b
	_pause_tree_btn = MenuKit.button(U.t("Skill tree"), func() -> void: menu.show_screen("tree_" + str(LevelTree.branches[0]["id"])))
	_pause_tree_btn.visible = not LevelTree.branches.is_empty()
	box.add_child(_pause_tree_btn)
	_pause_save_btn = MenuKit.button(U.t("Save game"), _on_save_pressed)
	box.add_child(_pause_save_btn)
	_pause_restart_btn = MenuKit.button(U.t("Restart run"), _on_restart_pressed)
	box.add_child(_pause_restart_btn)
	box.add_child(MenuKit.button(U.t("Settings"), func() -> void: menu.show_screen("settings")))
	box.add_child(MenuKit.button(U.t("Codex"), func() -> void: menu.show_screen("codex")))
	box.add_child(MenuKit.button(U.t("Main menu"), func() -> void: Game.main.to_menu()))
	box.add_child(MenuKit.gap(16))
	_pause_info = MenuKit.label("", 18, ACCENT)
	box.add_child(_pause_info)
	box.add_child(MenuKit.gap(12))
	_help_box = VBoxContainer.new()
	_help_box.add_theme_constant_override("separation", 4)
	box.add_child(_help_box)


## «Сохранить» (виден при выключенном автосейве): записать последнюю контрольную точку — загрузка начнёт с начала текущей локации.
func _on_save_pressed() -> void:
	if Game.main.save_now():
		Game.say(U.t("Saved: loading continues from the start of this location"), Color(0.7, 1.0, 0.7))
	else:
		Sfx.ui("ui/error", -6.0)
		Game.say(U.t("Could not save"), Color(1.0, 0.5, 0.4))


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
	match Game.controls.mode:
		"kbm":
			lines = [
				U.t("%s — move, mouse — aim, %s — shoot") % [Game.controls.move_label(), Game.controls.label("shoot")],
				U.t("%s — dodge: 4 s cooldown, 0.5 s if you actually dodged something") % Game.controls.label("dodge"),
				_skill_help(Game.controls.label("skill")),
				U.t("%s — reload · %s, %s — switch weapons") % [Game.controls.label("reload"), Game.controls.weapons_label(), Game.controls.label("last_weapon")],
				U.t("%s — pick up / open chest · %s — swap with current · %s — scrap for ammo") % [
					Game.controls.label("interact"), Game.controls.label("swap"), Game.controls.label("scrap")],
				U.t("%s — inventory · F3 — debug · %s — resume") % [Game.controls.label("inventory"), Game.controls.label("pause")],
				U.t("− / + and M — music · [ / ] — sounds"),
			]
		"pad":
			lines = [
				U.t("Left stick — move, right stick — aim, %s — shoot") % Game.controls.label("shoot"),
				U.t("%s — dodge: 4 s cooldown, 0.5 s if you actually dodged something") % Game.controls.label("dodge"),
				_skill_help(Game.controls.label("skill")),
				U.t("%s — reload · %s — switch weapons") % [Game.controls.label("reload"), Game.controls.weapons_label()],
				U.t("%s — pick up / open chest · %s — swap with current · %s — scrap for ammo") % [
					Game.controls.label("interact"), Game.controls.label("swap"), Game.controls.label("scrap")],
				U.t("%s — inventory · %s — resume") % [Game.controls.label("inventory"), Game.controls.label("pause")],
			]
			if bool(Game.settings.get_value("auto_aim")):
				lines.append(U.t("Auto-aim: shoot without the right stick — the gun aims at the nearest enemy"))
		"touch":
			lines = [
				U.t("Left stick — move, right stick — aim and shoot"),
				U.t("Dodge: 4 s cooldown, 0.5 s if you actually dodged something"),
				_skill_help(U.t("Skill")),
			]
			if bool(Game.settings.get_value("auto_aim")):
				lines[0] = U.t("Left stick — move, hold FIRE — shoot at the nearest enemy")
	lines.append("")
	lines.append(U.t("No regen. Flasks heal 20%: up to 3, refilled by the town healer. Levels only give skill points — the rest is guns."))
	for l in lines:
		_help_box.add_child(MenuKit.label(str(l), 17, DIM))


## Строка помощи про навык героя: «ПКМ — Граната (Первопроходец): ...».
func _skill_help(key: String) -> String:
	var id := Game.main.player.hero if Game.main != null and Game.main.player != null else Game.profile.hero
	return U.t("%s — %s (%s): %s") % [key, U.t(str(Heroes.get_hero(id)["skill_name"])), Heroes.hero_name(id), Heroes.describe(id)]


## Строка о забеге: сид и отличия от обычной игры.
static func run_info() -> String:
	var parts := PackedStringArray([U.t("Seed: %d") % Game.state.seed_value, U.t("rating and XP ×%.2f") % RunConfig.rating_mult(Game.run)])
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


## Пауза открыта: строка о забеге, подсказки, число свободных очков дерева, сброс подтверждения перезапуска.
func on_pause_open() -> void:
	_pause_info.text = run_info()
	_fill_help()
	var fp := LevelTree.free_points()
	_pause_tree_btn.text = U.t("Skill tree") + (" (%d)" % fp if fp > 0 else "")
	_restart_armed = false
	_pause_restart_btn.text = U.t("Restart run")
	_pause_save_btn.visible = not bool(Game.settings.get_value("autosave"))


func after_rebuild() -> void:
	_pause_info.text = run_info()
	_fill_help()


func on_input_mode(_m: String) -> void:
	if menu.mode == "pause":
		_fill_help()
