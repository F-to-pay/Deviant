class_name HealerScreen
extends MenuScreen
## Лекарь: лечение и фляги.

var _healer_box: VBoxContainer
var _healer_info: Label


func build(root: Control) -> void:
	var box := _screen(root, "healer")
	menu.town_head(box, "healer", U.t("HEALER"))
	_healer_info = MenuKit.label("", 22, TEXT)
	box.add_child(_healer_info)
	box.add_child(MenuKit.gap(6))
	_healer_box = VBoxContainer.new()
	_healer_box.add_theme_constant_override("separation", 8)
	box.add_child(_healer_box)
	var back := MenuKit.button(U.t("Back"), menu.back)
	box.add_child(back)
	menu.first_focus["healer"] = back


func refresh(_sname: String = "") -> void:
	menu.refresh_town_head("healer")
	MenuKit.clear_box(_healer_box)
	var p: Player = Game.main.player
	var lvl := int(Game.main.town.get("level", 1))
	_healer_info.text = U.t("Health: %s / %s   ·   Flasks: %d / %d") % [U.fmt(ceilf(p.hp)), U.fmt(p.max_hp), p.flasks, p.flask_max()]
	if bool(Game.run["no_heal"]):
		_healer_box.add_child(MenuKit.label(U.t("Hardcore run — the healer won't touch you."), 18, DIM))
		return
	var hp_price := Shops.heal_price(lvl, 1.0 - p.hp / p.max_hp)
	var hb := MenuKit.small_button(U.tm("Heal to full — %d", [U.money(hp_price)]) if hp_price > 0 else U.t("Health is full"), _heal_full, 560.0)
	hb.disabled = hp_price <= 0 or Game.state.coins < hp_price
	_healer_box.add_child(hb)
	var fp := Shops.flask_price(lvl)
	var need := p.flask_max() - p.flasks
	var fb := MenuKit.small_button(U.tm("Fill a flask — %d", [U.money(fp)]) if need > 0 else U.t("Flasks are full"), _buy_flask.bind(1), 560.0)
	fb.disabled = need <= 0 or Game.state.coins < fp
	_healer_box.add_child(fb)
	if need > 1:
		var ab := MenuKit.small_button(U.tm("Fill all (%d) — %d", [str(need), U.money(fp * need)]), _buy_flask.bind(need), 560.0)
		ab.disabled = Game.state.coins < fp * need
		_healer_box.add_child(ab)
	MenuKit.grab_first(_healer_box)


func _heal_full() -> void:
	var p: Player = Game.main.player
	var price := Shops.heal_price(int(Game.main.town.get("level", 1)), 1.0 - p.hp / p.max_hp)
	if price <= 0 or Game.state.coins < price:
		Sfx.ui("ui/error", -6.0)
		return
	Game.state.add_coins(-price)
	p.heal(p.max_hp, true)
	refresh()


func _buy_flask(n: int) -> void:
	var p: Player = Game.main.player
	var price := Shops.flask_price(int(Game.main.town.get("level", 1))) * n
	if Game.state.coins < price or p.flasks + n > p.flask_max():
		Sfx.ui("ui/error", -6.0)
		return
	Game.state.add_coins(-price)
	p.add_flask(n)
	Sfx.ui("pickup/heal", -6.0, 1.2)
	refresh()
