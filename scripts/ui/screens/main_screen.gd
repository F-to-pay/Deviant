class_name MainScreen
extends MenuScreen
## Главный экран: заголовок, кнопки, строка рекордов.

var records: Label


func build(root: Control) -> void:
	var box := _screen(root, "main")
	box.add_child(MenuKit.label("DEVIANT", 104, ACCENT, true))
	box.add_child(MenuKit.label(U.t("an endless diablo-like with absurd guns"), 22, DIM))
	box.add_child(MenuKit.gap(36))
	var b := MenuKit.button(U.t("New game"), func() -> void: Game.main.start_game())
	box.add_child(b)
	menu.first_focus["main"] = b
	box.add_child(MenuKit.button(U.t("Custom start"), func() -> void: menu.show_screen("custom")))
	box.add_child(MenuKit.button(U.t("Codex"), func() -> void: menu.show_screen("codex")))
	box.add_child(MenuKit.button(U.t("Settings"), func() -> void: menu.show_screen("settings")))
	box.add_child(MenuKit.button(U.t("Mods") + " (%d)" % ModsScreen.enabled_count(), func() -> void: menu.show_screen("mods")))
	box.add_child(MenuKit.button(U.t("Quit"), func() -> void: menu.get_tree().quit()))
	box.add_child(MenuKit.button(menu.lang_text(), menu.cycle_lang))
	box.add_child(MenuKit.gap(30))
	records = MenuKit.label("", 18, DIM)
	box.add_child(records)


func _records_text() -> String:
	var meta := U.t("Ancient coins: %s") % U.fmt(float(Game.profile.meta_coins)) if Game.profile.meta_coins > 0 else ""
	if Game.profile.best_zone <= 0 and Game.profile.best_rating <= 0:
		return U.t("No records yet") + ("  ·  " + meta if meta != "" else "")
	return U.t("Best: zone %d · kills in a run: %d · best rating: %s") % [
		Game.profile.best_zone, Game.profile.best_kills, U.fmt(float(Game.profile.best_rating))] + ("  ·  " + meta if meta != "" else "")


func refresh_records() -> void:
	records.text = _records_text()


func after_rebuild() -> void:
	refresh_records()
