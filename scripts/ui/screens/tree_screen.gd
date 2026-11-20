class_name TreeScreen
extends MenuScreen
## Дерево навыков: по экрану на ветку (id `tree_<ветка>`), карточки навыков и покупка.

var _tree_ui := {}        # ветка дерева навыков -> {head: Label, rows: VBoxContainer}


func build(root: Control) -> void:
	_tree_ui.clear()
	for b in LevelTree.branches:
		var bid := str(b["id"])
		var box := _screen(root, "tree_" + bid)
		(menu.panels["tree_" + bid] as PanelContainer).add_theme_stylebox_override("panel", MenuKit.card_style(LevelTree.branch_color(b), 30, 18))
		box.add_child(MenuKit.label(U.t("SKILLS"), 52, LevelTree.branch_color(b), true))
		var tabs := HBoxContainer.new()
		tabs.alignment = BoxContainer.ALIGNMENT_CENTER
		tabs.add_theme_constant_override("separation", 10)
		box.add_child(tabs)
		for o in LevelTree.branches:
			var oid := str(o["id"])
			var tb := MenuKit.small_button(LevelTree.branch_name(o), menu.show_screen.bind("tree_" + oid), 210.0)
			if oid == bid:
				var col := LevelTree.branch_color(o)
				tb.add_theme_stylebox_override("normal", MenuKit.box(Color(col, 0.28), col, 3))
				tb.add_theme_stylebox_override("hover", MenuKit.box(Color(col, 0.38), col, 3))
				tb.add_theme_color_override("font_color", Color.WHITE)
			tabs.add_child(tb)
		var head := MenuKit.label("", 20, Color(0.75, 1.0, 0.55))
		box.add_child(head)
		var lb := MenuKit.list_box(1060, 440)
		box.add_child(lb[0])
		var back := MenuKit.button(U.t("Back"), menu.back)
		box.add_child(back)
		menu.first_focus["tree_" + bid] = back
		_tree_ui[bid] = {"head": head, "rows": lb[1]}


func refresh(sname: String = "") -> void:
	var bid := sname.substr(5)
	var ui: Dictionary = _tree_ui.get(bid, {})
	if ui.is_empty():
		return
	var head: Label = ui["head"]
	var rows: VBoxContainer = ui["rows"]
	head.text = U.t("Level %d   ·   Skill points: %d   ·   Spent: %d") % [Game.state.hero_level, LevelTree.free_points(), LevelTree.spent_points()]
	MenuKit.clear_box(rows)
	var bcol := LevelTree.branch_color(LevelTree.branch(bid))
	for n in LevelTree.branch_nodes(bid, LevelTree.current_hero()):
		rows.add_child(_tree_row(n, bid, bcol))
	MenuKit.grab_first(rows)


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
	card.add_theme_stylebox_override("panel", MenuKit.card_style(Color(0.4, 0.4, 0.46) if locked else (bcol if lv > 0 or why == "" else bcol.darkened(0.45)), 16, 10, 4))
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
	var tl := MenuKit.label(title, 22, DIM if locked else (bcol.lightened(0.3) if lv > 0 else TEXT), true, HORIZONTAL_ALIGNMENT_LEFT)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tl)
	th.add_child(MenuKit.label((U.t("Lv %d/%d") % [lv, mx]) if mx > 0 else (U.t("Lv %d") % lv), 20, bcol.lightened(0.2) if lv > 0 else DIM, true, HORIZONTAL_ALIGNMENT_RIGHT))
	info.add_child(th)
	if lv > 0:
		info.add_child(_tree_stat_row(U.t("Now"), LevelTree.describe(n, lv), TEXT if not locked else DIM, false))
	if why != "max":
		info.add_child(_tree_stat_row(U.t("Next level") if lv > 0 else U.t("Level 1"), LevelTree.describe(n, lv + 1),
			Color(0.6, 0.95, 0.7) if not locked else DIM, not locked))
	if LevelTree.scales_with_hero(n):
		info.add_child(_tree_stat_row(U.t("Hero level"), "×" + U.fmt(float(Game.state.hero_level)), DIM, false))
	if why == "req":
		var names: Array = []
		for r in n.get("requires", []):
			if LevelTree.level(str(r)) <= 0:
				names.append(U.t(str(LevelTree.node(str(r)).get("name", r))))
		info.add_child(_tree_stat_row(U.t("Requires"), ", ".join(PackedStringArray(names)), Color(1.0, 0.6, 0.45), false))
	elif why == "class":
		var rival := LevelTree.node(LevelTree.class_rival(n))
		info.add_child(_tree_stat_row(U.t("Excluded by"), U.t(str(rival.get("name", "?"))), Color(1.0, 0.6, 0.45), false))
	var btn := MenuKit.small_button(
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
	var t := MenuKit.label(tag, 15, DIM, false, HORIZONTAL_ALIGNMENT_LEFT)
	t.custom_minimum_size = Vector2(120, 0)
	t.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(t)
	var v := MenuKit.label(text, 17, col, false, HORIZONTAL_ALIGNMENT_LEFT)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	if arrow:
		var ar := MenuKit.label("▲", 14, Color(0.45, 1.0, 0.5), false, HORIZONTAL_ALIGNMENT_RIGHT)
		ar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(ar)
	return row


func _tree_buy(id: String, bid: String) -> void:
	if LevelTree.buy(id):
		Sfx.ui("pickup/relic", -8.0, 1.2)
	else:
		Sfx.ui("ui/error", -6.0)
	refresh("tree_" + bid)
