class_name MysticScreen
extends MenuScreen
## Мистик: перки навыков героя за монеты.

var _mystic_box: VBoxContainer
var _mystic_owned: Label
var _mystic_element := false   # Мистик: выбираем стихию для перка «Стихия»


func build(root: Control) -> void:
	var box := _screen(root, "mystic")
	menu.town_head(box, "mystic", U.t("MYSTIC"))
	box.add_child(MenuKit.label(U.t("One gift for your hero's skill per town. Gifts last until the end of the run."), 18, DIM))
	box.add_child(MenuKit.gap(6))
	_mystic_box = VBoxContainer.new()
	_mystic_box.add_theme_constant_override("separation", 10)
	box.add_child(_mystic_box)
	box.add_child(MenuKit.gap(6))
	_mystic_owned = MenuKit.label("", 18, TEXT)
	_mystic_owned.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mystic_owned.custom_minimum_size = Vector2(1100, 0)
	box.add_child(_mystic_owned)
	var back := MenuKit.button(U.t("Back"), menu.back)
	box.add_child(back)
	menu.first_focus["mystic"] = back


func refresh(_sname: String = "") -> void:
	menu.refresh_town_head("mystic")
	MenuKit.clear_box(_mystic_box)
	var town: Dictionary = Game.main.town
	var p: Player = Game.main.player
	# перки — под текущего героя (в стартовом городе героя могли сменить)
	if str(town.get("mystic_for", "")) != p.hero:
		town["mystic_for"] = p.hero
		town["mystic"] = Heroes.perk_offer(p.hero, p.skill.run_perks, Game.main.rng, Shops.MYSTIC_OFFER)
	var price := Shops.mystic_price(int(town.get("level", 1)), p.skill.run_perk_count())
	var done := bool(town.get("mystic_done", false))
	if _mystic_element:
		# выбор стихии для перка «Стихия»
		_mystic_box.add_child(MenuKit.label(U.t("Choose the element of your skill:"), 20, TEXT))
		for el in Heroes.ELEMENTS:
			var eb := MenuKit.small_button(U.t(str(U.EL_NAMES[int(el)])), _buy_mystic.bind("element", int(el)), 420.0)
			eb.add_theme_color_override("font_color", U.el_color(int(el)))
			_mystic_box.add_child(eb)
		_mystic_box.add_child(MenuKit.small_button(U.t("Cancel"), _mystic_cancel, 420.0))
		MenuKit.grab_first(_mystic_box)
		return
	var offer: Array = town.get("mystic", [])
	if offer.is_empty():
		_mystic_box.add_child(MenuKit.label(U.t("The spirits have nothing more for this hero."), 18, DIM))
	for o in offer:
		var id := str(o)
		var have := int(p.skill.run_perks.get(id, 0))
		var t := "%s%s — %s   ·   %s" % [Heroes.perk_name(id, p.hero), (" ×%d" % (have + 1)) if have > 0 else "",
			Heroes.perk_desc(id, have), U.money(price)]
		var b := MenuKit.small_button(t, _buy_mystic.bind(id, -1), 1100.0)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(1100, 58)
		b.disabled = done or Game.state.coins < price or not Heroes.perk_open(id, p.hero, have)
		_mystic_box.add_child(b)
	if done:
		_mystic_box.add_child(MenuKit.label(U.t("The spirits are tired. Come back in the next town."), 18, DIM))
	var owned := PackedStringArray()
	for id in p.skill.run_perks:
		var nm := Heroes.perk_name(str(id), p.hero) + " ×%d" % int(p.skill.run_perks[id])
		if str(id) == "element" and p.skill.element >= 0:
			nm += " (%s)" % U.t(str(U.EL_NAMES[p.skill.element]))
		if not Heroes.perk_fits(str(id), p.hero):
			nm += " " + U.t("(not for this hero)")
		owned.append(nm)
	_mystic_owned.text = U.t("Your gifts: %s") % (", ".join(owned) if not owned.is_empty() else U.t("none"))
	MenuKit.grab_first(_mystic_box)


func _mystic_cancel() -> void:
	_mystic_element = false
	refresh()


## Купить перк навыка. Для «Стихии» сначала выбор стихии (element = -1 -> показать выбор).
func _buy_mystic(id: String, element: int) -> void:
	var town: Dictionary = Game.main.town
	var p: Player = Game.main.player
	var price := Shops.mystic_price(int(town.get("level", 1)), p.skill.run_perk_count())
	if bool(town.get("mystic_done", false)) or Game.state.coins < price:
		Sfx.ui("ui/error", -6.0)
		return
	if id == "element" and element < 0:
		_mystic_element = true
		refresh()
		return
	_mystic_element = false
	Game.state.add_coins(-price)
	p.skill.add_run_perk(id, element)
	town["mystic_done"] = true
	Sfx.ui("pickup/legendary", -6.0)
	Game.say(U.t("Gift: %s") % Heroes.perk_name(id, p.hero), Color(0.78, 0.45, 1.0))
	refresh()


func on_town_open(_sname: String) -> void:
	_mystic_element = false
