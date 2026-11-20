extends SceneTree
## Отпечаток экранов меню: для каждого экрана (en и ru) печатает дерево узлов с текстами, потом нажимает по очереди
## первые безопасные кнопки лавок и дерева навыков и снова печатает. При рефакторинге меню вывод до и после должен
## совпасть построчно. Сравнивать по ASCII (консоль Windows портит юникод): LC_ALL=C tr -cd '\11\12\40-\176'.
## Запуск: godot --headless --path . -s res://tests/ui_screens.gd
## Безопасно для сейва: не нажимает героев, «Настраиваемый старт», перезапуск и выход; язык меняет без записи (I18n.apply).

var G: Node
var M: Node
var menu: Node


func dump(node: Node, depth: int, out: Array) -> void:
	var line := "  ".repeat(depth) + node.get_class()
	if node is Label:
		line += " L:" + (node as Label).text.replace("\n", "|")
	elif node is Button:
		line += " B:" + (node as Button).text.replace("\n", "|") + (" [off]" if (node as Button).disabled else "")
		if node is CheckButton:
			line += " pressed=" + str((node as CheckButton).button_pressed)
	elif node is RichTextLabel:
		var t := (node as RichTextLabel).get_parsed_text()
		line += " R:" + str(t.length()) + ":" + t.substr(0, 60).replace("\n", "|")
	elif node is HSlider:
		line += " S:" + str((node as HSlider).value)
	elif node is LineEdit:
		line += " E:" + (node as LineEdit).text
	elif node is OptionButton:
		line += " O:" + (node as OptionButton).text
	out.append(line)
	for c in node.get_children():
		if c is Control and not (c as Control).visible and c != node:
			out.append("  ".repeat(depth + 1) + "(hidden) " + c.get_class())
			continue
		dump(c, depth + 1, out)


func buttons(node: Node, out: Array) -> void:
	if node is Button and not (node as Button).disabled and (node as Button).visible and not (node is CheckButton):
		out.append(node)
	for c in node.get_children():
		buttons(c, out)


func snap(tag: String) -> void:
	var lines: Array = []
	var cur: String = menu.current
	var root_ctl: Control = menu.screens.get(cur)
	lines.append("== " + tag + " current=" + cur + " mode=" + str(menu.mode))
	if root_ctl != null:
		dump(root_ctl, 0, lines)
	for l in lines:
		print("SMOKE ", l)


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
	G.profile.meta_coins = max(G.profile.meta_coins, 50)
	M.rng.seed = 77
	M.load_town(6)
	await process_frame
	await process_frame
	var ids: Array = menu.screens.keys()
	ids.sort()
	print("SMOKE screen ids: ", ids)
	var I18nC: GDScript = load("res://scripts/core/i18n.gd")
	var town_ids := ["shop", "mystic", "workshop", "guild", "healer", "heroes", "custom"]
	for lang in ["en", "ru"]:
		I18nC.call("apply", lang)
		menu.call("rebuild")
		await process_frame
		for id in ids:
			if id in town_ids:
				menu.open_town(id, "line for " + id)
			elif id == "pause":
				menu.open_pause()
			elif id == "main":
				menu.open_main()
			else:
				menu.open_pause()
				menu.show_screen(id)
			await process_frame
			snap(lang + ":" + id)
			if id in ["shop", "mystic", "workshop", "guild", "healer"] or str(id).begins_with("tree_"):
				for k in 5:
					var bl: Array = []
					buttons(menu.screens[id], bl)
					# последняя кнопка — «Назад»: не нажимаем
					if bl.size() <= 1:
						break
					var b: Button = bl[mini(k, bl.size() - 2)]
					print("SMOKE press ", id, " #", k, " ", b.text.replace("\n", "|"))
					b.pressed.emit()
					await process_frame
					snap(lang + ":" + id + " after press " + str(k))
			if menu.mode == "town":
				menu.close_town()
			menu.close()
			await process_frame
	print("SMOKE DONE")
	quit()
