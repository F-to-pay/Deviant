class_name CustomScreen
extends MenuScreen
## «Настраиваемый старт»: сложность, переключатели, стартовая пушка, сид. Значения правятся прямо в Game.profile.custom.

var _custom_ui := {}      # ключ Game.profile.custom -> [контрол, ...]
var _custom_preset: Label
var _custom_seed: LineEdit
var _custom_rating: Label


## Настраиваемый старт: сложность, переключатели, стартовая пушка, сид.
## Значения правятся прямо в Game.profile.custom и сохраняются при старте.
func build(root: Control) -> void:
	_custom_ui.clear()
	var box := _screen(root, "custom")
	box.add_child(MenuKit.label(U.t("CUSTOM START"), 52, ACCENT, true))
	box.add_child(MenuKit.gap(8))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)

	# Сложность: пресеты + ручные ползунки
	grid.add_child(MenuKit.label(U.t("Difficulty"), 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	for i in RunConfig.DIFFICULTY.size():
		var d: Dictionary = RunConfig.DIFFICULTY[i]
		var pb := MenuKit.button(U.t(str(d["n"])), _on_preset.bind(i))
		pb.custom_minimum_size = Vector2(150, 46)
		pb.add_theme_font_size_override("font_size", 20)
		presets.add_child(pb)
	grid.add_child(presets)
	_custom_preset = MenuKit.label("", 20, DIM, false, HORIZONTAL_ALIGNMENT_LEFT)
	_custom_preset.custom_minimum_size = Vector2(130, 0)
	grid.add_child(_custom_preset)
	_custom_slider(grid, "hp", U.t("Enemy health"))
	_custom_slider(grid, "dmg", U.t("Enemy damage"))

	_custom_check(grid, "zone_heal", U.t("Full heal when entering a new zone"))
	_custom_check(grid, "no_normals", U.t("No regular enemies (elites only)"))
	_custom_check(grid, "chests", U.t("Chests"))
	_custom_check(grid, "no_heal", U.t("Hardcore: no flasks, healer or lifesteal"))
	_custom_check(grid, "chaos", U.t("Chaos: all gun rarities and enemy types equally likely"))
	_custom_check(grid, "towns", U.t("Towns between stages"))

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
	grid.add_child(MenuKit.label(U.t("Seed"), 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	_custom_seed = LineEdit.new()
	_custom_seed.placeholder_text = U.t("empty — random")
	_custom_seed.custom_minimum_size = Vector2(340, 44)
	_custom_seed.max_length = 40
	_custom_seed.text_changed.connect(func(t: String) -> void: Game.profile.custom["seed"] = t)
	grid.add_child(_custom_seed)
	grid.add_child(MenuKit.label(U.t("number or text"), 16, DIM, false, HORIZONTAL_ALIGNMENT_LEFT))

	box.add_child(MenuKit.gap(10))
	_custom_rating = MenuKit.label("", 24, ACCENT, true)
	box.add_child(_custom_rating)
	box.add_child(MenuKit.gap(8))
	var start := MenuKit.button(U.t("Start"), _start_custom)
	box.add_child(start)
	menu.first_focus["custom"] = start
	box.add_child(MenuKit.button(U.t("Reset"), _reset_custom))
	box.add_child(MenuKit.button(U.t("Back"), _back_custom))


func _custom_slider(grid: GridContainer, key: String, title: String) -> void:
	grid.add_child(MenuKit.label(title, 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	var s := HSlider.new()
	s.min_value = 0.1
	s.max_value = 2.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(340, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := MenuKit.label("", 20, DIM, false, HORIZONTAL_ALIGNMENT_LEFT)
	s.value_changed.connect(_on_custom_slider.bind(key, val))
	grid.add_child(s)
	grid.add_child(val)
	_custom_ui[key] = [s, val]


func _custom_check(grid: GridContainer, key: String, title: String) -> void:
	grid.add_child(MenuKit.label(title, 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	var c := CheckButton.new()
	c.toggled.connect(_on_custom_check.bind(key))
	grid.add_child(c)
	grid.add_child(MenuKit.label(_bonus_text(key), 18, DIM, false, HORIZONTAL_ALIGNMENT_LEFT))
	_custom_ui[key] = [c, null]


func _on_custom_check(on: bool, key: String) -> void:
	Game.profile.custom[key] = on
	_update_preset_label()


## Подсказка, как переключатель влияет на рейтинг.
func _bonus_text(key: String) -> String:
	for b in RunConfig.RATING_BONUS:
		if b[0] == key:
			var v := float(b[2])
			var when := "" if bool(b[1]) else U.t("if off: ")
			return U.t("%srating %s%d%%") % [when, "+" if v > 0.0 else "−", roundi(absf(v) * 100.0)]
	return ""


## ids[i] — значение в Game.profile.custom; dflt — что значит пустая строка (обычный старт).
func _custom_option(grid: GridContainer, key: String, title: String, ids: Array, names: Array, dflt: String) -> void:
	grid.add_child(MenuKit.label(title, 22, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(340, 46)
	for i in names.size():
		o.add_item(str(names[i]), i)
	o.item_selected.connect(func(i: int) -> void: Game.profile.custom[key] = str(ids[i]))
	grid.add_child(o)
	grid.add_child(Control.new())
	_custom_ui[key] = [o, ids, dflt]


func _on_preset(i: int) -> void:
	var d: Dictionary = RunConfig.DIFFICULTY[i]
	Game.profile.custom["hp"] = float(d["hp"])
	Game.profile.custom["dmg"] = float(d["dmg"])
	refresh()


func _on_custom_slider(v: float, key: String, val: Label) -> void:
	Game.profile.custom[key] = v
	val.text = MenuKit.fmt(v, "pct")
	_update_preset_label()


func _update_preset_label() -> void:
	if _custom_rating != null:
		_custom_rating.text = U.t("Rating and XP multiplier: ×%.2f") % RunConfig.rating_mult(Game.profile.custom)
	var t := U.t("custom")
	for d in RunConfig.DIFFICULTY:
		if is_equal_approx(float(d["hp"]), float(Game.profile.custom["hp"])) and is_equal_approx(float(d["dmg"]), float(Game.profile.custom["dmg"])):
			t = U.t(str(d["n"])).to_lower()
	_custom_preset.text = t


func refresh(_sname: String = "") -> void:
	for key in _custom_ui:
		var row: Array = _custom_ui[key]
		var v: Variant = Game.profile.custom.get(key, RunConfig.DEFAULTS[key])
		if row[0] is HSlider:
			(row[0] as HSlider).set_value_no_signal(float(v))
			(row[1] as Label).text = MenuKit.fmt(float(v), "pct")
		elif row[0] is CheckButton:
			(row[0] as CheckButton).set_pressed_no_signal(bool(v))
		elif row[0] is OptionButton:
			var ids: Array = row[1]
			var id := str(v) if str(v) != "" else str(row[2])
			(row[0] as OptionButton).select(maxi(0, ids.find(id)))
	_custom_seed.text = str(Game.profile.custom.get("seed", ""))
	_update_preset_label()


func _reset_custom() -> void:
	Game.profile.custom = RunConfig.DEFAULTS.duplicate()
	refresh()


func _back_custom() -> void:
	Game.save()
	menu.back()


func _start_custom() -> void:
	Game.save()
	Game.main.start_game(Game.profile.custom.duplicate())


## Esc / «назад» с этого экрана сохраняет выбор.
func on_back() -> bool:
	_back_custom()
	return true
