class_name HeroesScreen
extends MenuScreen
## Вербовщик: выбор героя и открытие новых за древние монеты.

var _heroes_list: VBoxContainer
var _heroes_coins: Label


## Вербовщик в стартовом городе: герои, их навыки, открытие за древние монеты, выбор.
## Список строится заново при каждом открытии (_refresh_heroes).
func build(root: Control) -> void:
	var box := _screen(root, "heroes")
	box.add_child(MenuKit.label(U.t("HEROES"), 52, ACCENT, true))
	_heroes_coins = MenuKit.label("", 20, Color(0.6, 1.0, 1.0))
	box.add_child(_heroes_coins)
	box.add_child(MenuKit.gap(8))
	_heroes_list = VBoxContainer.new()
	_heroes_list.add_theme_constant_override("separation", 12)
	box.add_child(_heroes_list)
	box.add_child(MenuKit.gap(8))
	var back := MenuKit.button(U.t("Back"), menu.back)
	box.add_child(back)
	menu.first_focus["heroes"] = back


func refresh(_sname: String = "") -> void:
	_heroes_coins.text = U.t("Ancient coins: %s") % U.fmt(float(Game.profile.meta_coins))
	for c in _heroes_list.get_children():
		_heroes_list.remove_child(c)
		c.queue_free()
	var first: Button = null
	for id in Heroes.ORDER:
		var h := Heroes.get_hero(str(id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		var info := VBoxContainer.new()
		info.custom_minimum_size = Vector2(720, 0)
		info.add_child(MenuKit.label(Heroes.hero_name(str(id)), 26, Heroes.color(str(id)), true, HORIZONTAL_ALIGNMENT_LEFT))
		var d := MenuKit.label(U.t(str(h["skill_name"])) + ": " + Heroes.describe(str(id)), 18, TEXT, false, HORIZONTAL_ALIGNMENT_LEFT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(720, 0)
		info.add_child(d)
		row.add_child(info)
		var b: Button
		if Game.profile.hero == str(id):
			b = MenuKit.button(U.t("Selected"), func() -> void: pass)
			b.disabled = true
		elif Game.profile.hero_unlocked(str(id)):
			b = MenuKit.button(U.t("Choose"), _choose_hero.bind(str(id)))
		else:
			var price := int(h["price"])
			b = MenuKit.button(U.t("Unlock: %d ancient coins") % price, _unlock_hero.bind(str(id)))
			b.disabled = Game.profile.meta_coins < price
		b.custom_minimum_size = Vector2(340, 58)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
		_heroes_list.add_child(row)
		if first == null and not b.disabled:
			first = b
	if first != null and Game.controls.mode == "pad":
		first.grab_focus.call_deferred()


func _choose_hero(id: String) -> void:
	if Game.select_hero(id):
		Game.say(U.t("Hero: %s") % Heroes.hero_name(id), Heroes.color(id))
	refresh()


func _unlock_hero(id: String) -> void:
	if Game.profile.unlock_hero(id):
		Sfx.ui("pickup/relic", -4.0)
		Game.select_hero(id)
		Game.say(U.t("Unlocked: %s") % Heroes.hero_name(id), Heroes.color(id))
	else:
		Sfx.ui("ui/error", -6.0)
	refresh()
