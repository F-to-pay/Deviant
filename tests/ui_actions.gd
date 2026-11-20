extends SceneTree
## Сценарии ввода в меню: Esc-навигация, ползунки и переключатели настроек, переназначение клавиши, подтверждение
## перезапуска, страницы справочника, смена языка, экран «Настраиваемый старт». Печатает состояние после каждого шага
## (строки SMOKE ...): при рефакторинге меню вывод до и после должен совпасть построчно.
## ВНИМАНИЕ: нажатия пишут в user://deviant.cfg (настройки, «настраиваемый старт»). Перед запуском сделай копию файла
## и верни её после: тест язык и настройки сам не откатывает.
## Запуск: godot --headless --path . -s res://tests/ui_actions.gd

var G: Node
var M: Node
var menu: Node


func find_all(node: Node, cls: String, out: Array) -> void:
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		find_all(c, cls, out)


func find_button(node: Node, prefix: String) -> Button:
	var bl: Array = []
	find_all(node, "Button", bl)
	for b in bl:
		if (b as Button).text.begins_with(prefix) and not (b is CheckButton):
			return b
	return null


func esc() -> void:
	var ev := InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	root.push_input(ev)


func key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	root.push_input(ev)


func st(tag: String) -> void:
	print("SMOKE ", tag, " | current=", menu.current, " mode=", menu.mode, " visible=", menu.visible, " paused=", paused)


func sv(k: String) -> String:
	return str(G.settings.get_value(k))


func _initialize() -> void:
	G = root.get_node("Game")
	M = load("res://scenes/main.tscn").instantiate()
	root.add_child(M)
	var guard := 0
	while not (M.get("menu") != null and M.menu.visible) and guard < 3000:
		await process_frame
		guard += 1
	menu = M.menu
	M.start_game({"seed": "123"})
	for i in 5:
		await process_frame
	G.state.coins = 5000.0
	M.load_town(6)
	await process_frame
	G.settings.set_value("language", "en")
	for i in 4:
		await process_frame

	# --- Esc-навигация в паузе
	menu.open_pause()
	await process_frame
	st("pause opened")
	menu.show_screen("settings")
	esc()
	await process_frame
	st("esc from settings")
	menu.show_screen("settings")
	menu.show_screen("controls")
	esc()
	await process_frame
	st("esc from controls")
	menu.show_screen("release")
	esc()
	await process_frame
	st("esc from release")
	menu.show_screen("codex")
	esc()
	await process_frame
	st("esc from codex")
	menu.show_screen("tree_W")
	esc()
	await process_frame
	st("esc from tree")

	# --- настройки: ползунки, переключатели, обновление при показе, кнопка карточки пушки
	menu.show_screen("settings")
	await process_frame
	var sc: Control = menu.screens["settings"]
	var sl: Array = []
	find_all(sc, "HSlider", sl)
	var cb: Array = []
	find_all(sc, "CheckButton", cb)
	print("SMOKE settings widgets: sliders=", sl.size(), " checks=", cb.size())
	(sl[0] as HSlider).value = 0.35
	print("SMOKE slider0 -> master=", sv("master"))
	(cb[0] as CheckButton).button_pressed = not (cb[0] as CheckButton).button_pressed
	print("SMOKE check0 -> music_muted=", sv("music_muted"))
	G.settings.set_value("master", 0.9)
	menu.show_screen("pause")
	menu.show_screen("settings")
	print("SMOKE refresh on show: slider0=", (sl[0] as HSlider).value, " check0=", (cb[0] as CheckButton).button_pressed)
	var card := find_button(sc, "On the")
	print("SMOKE card button: ", card.text if card != null else "none")
	if card != null:
		card.pressed.emit()
		print("SMOKE card after press: ", card.text, " gun_card=", sv("gun_card"))

	# --- управление: переназначение, сброс, цикл экранных кнопок
	menu.show_screen("controls")
	await process_frame
	var cs: Control = menu.screens["controls"]
	var bl: Array = []
	find_all(cs, "Button", bl)
	var bind_btn: Button = null
	for b in bl:
		if not (b is CheckButton) and not (b as Button).disabled and (b as Button).custom_minimum_size.x == 300:
			bind_btn = b
			break
	print("SMOKE first bind button: ", bind_btn.text if bind_btn != null else "none")
	if bind_btn != null:
		bind_btn.pressed.emit()
		await process_frame
		print("SMOKE listening step -> captures: ", bind_btn.text)
		key(KEY_J)
		await process_frame
		print("SMOKE after key J: ", bind_btn.text, " binds_set=", sv("binds") != "", " current=", menu.current)
	var reset := find_button(cs, "Reset to defaults")
	if reset != null:
		reset.pressed.emit()
		await process_frame
		print("SMOKE after reset: binds='", sv("binds"), "' first bind button=", bind_btn.text if bind_btn != null else "none")
	var touch := find_button(cs, "Auto (when")
	if touch != null:
		touch.pressed.emit()
		print("SMOKE touch opt: ", touch.text, " setting=", sv("touch_controls"))
		touch.pressed.emit()
		touch.pressed.emit()
		print("SMOKE touch opt cycled: ", touch.text, " setting=", sv("touch_controls"))
	# листание: Esc во время ожидания не уходит с экрана
	if bind_btn != null:
		bind_btn.pressed.emit()
		key(KEY_ESCAPE)   # как в игре: Esc приходит клавишей и во время ожидания становится привязкой
		await process_frame
		st("Esc key while listening (becomes the binding)")
		print("SMOKE after Esc binding: ", bind_btn.text, " current=", menu.current)
		menu.show_screen("controls")
		var rst := find_button(cs, "Reset to defaults")
		if rst != null:
			rst.pressed.emit()

	# --- «Стрельба по отпусканию»
	menu.show_screen("release")
	await process_frame
	var rl: Array = []
	find_all(menu.screens["release"], "CheckButton", rl)
	print("SMOKE release checks=", rl.size())
	if rl.size() > 0:
		(rl[0] as CheckButton).button_pressed = true
		print("SMOKE release on: ", sv("touch_release_fire"))
		(rl[0] as CheckButton).button_pressed = false
		print("SMOKE release off: '", sv("touch_release_fire"), "'")

	# --- пауза: подтверждение перезапуска
	menu.open_pause()
	await process_frame
	var rb := find_button(menu.screens["pause"], "Restart")
	print("SMOKE restart btn: ", rb.text if rb != null else "none")
	if rb != null:
		rb.pressed.emit()
		print("SMOKE restart armed: ", rb.text)
		menu.close()
		menu.open_pause()
		print("SMOKE restart after reopen: ", rb.text)
	var tb := find_button(menu.screens["pause"], "Skill tree")
	print("SMOKE skill tree btn: ", tb.text if tb != null else "none")

	# --- справочник
	menu.show_screen("codex")
	await process_frame
	var pages: Array = []
	var cl: Array = []
	find_all(menu.screens["codex"], "Button", cl)
	for b in cl:
		if (b as Button).toggle_mode:
			pages.append(b)
	var rt: Array = []
	find_all(menu.screens["codex"], "RichTextLabel", rt)
	print("SMOKE codex pages=", pages.size())
	for k in mini(6, pages.size()):
		(pages[k] as Button).pressed.emit()
		await process_frame
		var t: String = (rt[0] as RichTextLabel).get_parsed_text()
		print("SMOKE codex page ", k, " ", (pages[k] as Button).text, " len=", t.length(), " pressed=", (pages[k] as Button).button_pressed)
	# страница «Моддинг» через экран модов
	menu.show_screen("mods")
	var hb := find_button(menu.screens["mods"], "How to make mods")
	if hb != null:
		hb.pressed.emit()
		await process_frame
		st("mods -> how to make mods")
		print("SMOKE codex text after: ", (rt[0] as RichTextLabel).get_parsed_text().substr(0, 40).replace("\n", "|"))

	# --- «Настраиваемый старт» из города
	menu.open_town("custom")
	await process_frame
	var cu: Control = menu.screens["custom"]
	var csl: Array = []
	find_all(cu, "HSlider", csl)
	print("SMOKE custom sliders=", csl.size())
	if csl.size() > 0:
		(csl[0] as HSlider).value = 0.5 if (csl[0] as HSlider).value != 0.5 else 0.6
		print("SMOKE custom slider0 -> profile.custom hp/dmg: ", G.profile.custom["hp"], "/", G.profile.custom["dmg"])
	var rs := find_button(cu, "Reset")
	if rs != null:
		rs.pressed.emit()
		print("SMOKE custom reset -> hp/dmg: ", G.profile.custom["hp"], "/", G.profile.custom["dmg"])
	esc()
	await process_frame
	st("esc from custom (town)")

	# --- герои из города: Esc закрывает
	menu.open_town("heroes")
	await process_frame
	st("heroes opened")
	esc()
	await process_frame
	st("esc from heroes (town)")

	# --- смена языка: меню перестраивается и остаётся на том же экране
	menu.open_pause()
	menu.show_screen("codex")
	await process_frame
	var tx_en := ((menu.screens["codex"] as Control).get_child(0) as Node).get_class()
	G.settings.set_value("language", "ru")
	for i in 4:
		await process_frame
	st("after language ru")
	var rl2: Array = []
	find_all(menu.screens["codex"], "RichTextLabel", rl2)
	print("SMOKE codex still has text after rebuild: ", (rl2[0] as RichTextLabel).get_parsed_text().length() > 10, " ", tx_en)
	menu.show_screen("pause")
	var lb: Array = []
	find_all(menu.screens["pause"], "Label", lb)
	var labels: Array = []
	for l in lb:
		labels.append((l as Label).text)
	print("SMOKE pause labels ru: ", labels.slice(0, 4))
	menu.show_screen("main")
	var cyc := find_button(menu.screens["main"], "Язык")
	print("SMOKE lang button: ", cyc.text if cyc != null else "none")
	G.settings.set_value("language", "en")
	for i in 4:
		await process_frame
	st("after language en")
	print("SMOKE DONE")
	quit()
