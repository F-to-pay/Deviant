class_name ShopScreen
extends MenuScreen
## Оружейная: покупка и продажа пушек, патроны, переброс товара. Товар — Game.main.town (Shops.make_town).

var _shop_buy: VBoxContainer
var _shop_deal_panel: PanelContainer   # «Товар дня» — отдельный блок над списком
var _shop_deal: VBoxContainer
var _shop_sell: VBoxContainer
var _shop_prev: GunPreview
var _shop_reroll: Button
var _shop_ammo: VBoxContainer
var _shop_status: Label


func build(root: Control) -> void:
	var box := _screen(root, "shop", true)
	menu.town_head(box, "shop", U.t("GUN SHOP"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.add_child(MenuKit.label(U.t("For sale"), 22, TEXT))
	# «Товар дня» — своя рамка над списком; сам список без прокрутки: в нём все остальные пушки сразу
	_shop_deal_panel = PanelContainer.new()
	_shop_deal_panel.add_theme_stylebox_override("panel", MenuKit.box(Color(0.22, 0.17, 0.05, 0.55), Color(1.0, 0.82, 0.35), 3))
	_shop_deal = VBoxContainer.new()
	_shop_deal.add_theme_constant_override("separation", 6)
	_shop_deal_panel.add_child(_shop_deal)
	left.add_child(_shop_deal_panel)
	_shop_buy = VBoxContainer.new()
	_shop_buy.add_theme_constant_override("separation", 6)
	_shop_buy.custom_minimum_size = Vector2(460, 0)
	left.add_child(_shop_buy)
	_shop_reroll = MenuKit.small_button("", _reroll_stock, 460.0)
	left.add_child(_shop_reroll)
	row.add_child(left)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 6)
	mid.add_child(MenuKit.label(U.t("Your guns — sell"), 22, TEXT))
	var mb := MenuKit.list_box(460, 380)
	mid.add_child(mb[0])
	_shop_sell = mb[1]
	mid.add_child(MenuKit.label(U.t("Ammo — one magazine"), 22, TEXT))
	_shop_ammo = VBoxContainer.new()
	_shop_ammo.add_theme_constant_override("separation", 6)
	_shop_ammo.custom_minimum_size = Vector2(460, 0)
	mid.add_child(_shop_ammo)
	row.add_child(mid)
	_shop_prev = GunPreview.new()
	row.add_child(_shop_prev)
	_shop_status = MenuKit.label("", 18, DIM)
	box.add_child(_shop_status)
	var back := MenuKit.button(U.t("Back"), menu.back)
	box.add_child(back)
	menu.first_focus["shop"] = back


func refresh(_sname: String = "") -> void:
	menu.refresh_town_head("shop")
	MenuKit.clear_box(_shop_buy)
	MenuKit.clear_box(_shop_deal)
	MenuKit.clear_box(_shop_sell)
	var town: Dictionary = Game.main.town
	var stock: Array = town.get("stock", [])
	if stock.is_empty():
		_shop_buy.add_child(MenuKit.label(U.t("Sold out"), 18, DIM))
	for o in stock:
		var g: Gun = o
		var price := Shops.buy_price(g, town)
		var is_deal: bool = g == town.get("deal")
		var b := MenuKit.gun_row(g, ("%s — %s" % [g.gun_name, U.money(price)]) if not is_deal else U.tm("%s — %d (was %d)", [g.gun_name, U.money(price), U.money(Shops.gun_price(g))]),
			_buy_gun.bind(g), _shop_prev)
		b.disabled = Game.state.coins < price
		if is_deal:
			_shop_deal.add_child(MenuKit.label(U.t("Deal of the day: 50% off"), 16, Color(1.0, 0.82, 0.35), true, HORIZONTAL_ALIGNMENT_LEFT))
			_shop_deal.add_child(b)
		else:
			_shop_buy.add_child(b)
	_shop_deal_panel.visible = _shop_deal.get_child_count() > 0
	var p: Player = Game.main.player
	for e in MenuKit.player_guns():
		var g: Gun = e[0]
		var b := MenuKit.gun_row(g, "+%s · %s (%s)" % [U.money(Shops.sell_price(g)), g.gun_name, MenuKit.gun_where(e)], _sell_gun.bind(g), _shop_prev)
		# последнюю пушку в руках не продать — стрелять будет нечем
		b.disabled = str(e[1]) == "slot" and p.gun_count() <= 1
		_shop_sell.add_child(b)
	var lvl := int(town.get("level", 1))
	var rp := Shops.stock_reroll_price(lvl, int(town.get("rerolls", 0)))
	_shop_reroll.text = U.tm("New stock — %d", [U.money(rp)])
	_shop_reroll.disabled = Game.state.coins < rp
	# патроны: по магазину к каждой пушке в слотах
	MenuKit.clear_box(_shop_ammo)
	for i in 4:
		var g: Gun = p.guns[i]
		if g == null or g.free_ammo:
			continue
		var t := g.ammo_type()
		var n := mini(g.mag_size, GunData.ammo_cap(t) - p.reserve_of(t))
		var b: Button
		if n <= 0:
			b = MenuKit.gun_row(g, U.t("%s: reserve full") % g.ammo_name(), func() -> void: pass, _shop_prev)
			b.disabled = true
		else:
			var price := Shops.ammo_price(g, n)
			b = MenuKit.gun_row(g, "+%d %s — %s  (%s)" % [n, g.ammo_name(), U.money(price), g.gun_name], _buy_ammo.bind(g), _shop_prev)
			b.disabled = Game.state.coins < price
		_shop_ammo.add_child(b)
	if _shop_ammo.get_child_count() == 0:
		_shop_ammo.add_child(MenuKit.label(U.t("Your guns don't need ammo"), 16, DIM))
	if not stock.is_empty():
		_shop_prev.show_gun(stock[0], p.gun())
	MenuKit.grab_first(_shop_deal if _shop_deal_panel.visible else _shop_buy)


func _reroll_stock() -> void:
	var town: Dictionary = Game.main.town
	var lvl := int(town.get("level", 1))
	var rp := Shops.stock_reroll_price(lvl, int(town.get("rerolls", 0)))
	if Game.state.coins < rp:
		Sfx.ui("ui/error", -6.0)
		return
	Game.state.add_coins(-rp)
	town["rerolls"] = int(town.get("rerolls", 0)) + 1
	town["stock"] = Shops.make_stock(lvl, Game.main.rng)
	town["deal"] = (town["stock"] as Array)[0]
	_shop_status.text = U.t("New stock arrived")
	Sfx.ui("world/chest", -6.0)
	refresh()


## Один магазин патронов к пушке (сколько влезет в запас).
func _buy_ammo(g: Gun) -> void:
	var p: Player = Game.main.player
	var t := g.ammo_type()
	var n := mini(g.mag_size, GunData.ammo_cap(t) - p.reserve_of(t))
	var price := Shops.ammo_price(g, n)
	if n <= 0 or Game.state.coins < price:
		Sfx.ui("ui/error", -6.0)
		return
	Game.state.add_coins(-price)
	p.add_ammo(t, n)
	_shop_status.text = U.t("Bought: +%d %s") % [n, g.ammo_name()]
	Sfx.ui("pickup/ammo", -6.0)
	refresh()


func _buy_gun(g: Gun) -> void:
	var town: Dictionary = Game.main.town
	var price := Shops.buy_price(g, town)
	var stock: Array = town.get("stock", [])
	if Game.state.coins < price or not (g in stock):
		Sfx.ui("ui/error", -6.0)
		return
	Game.state.add_coins(-price)
	stock.erase(g)
	if g == town.get("deal"):
		town["deal"] = null
	var p: Player = Game.main.player
	if p.add_gun(g):
		_shop_status.text = U.t("Bought: %s") % g.gun_name
	else:
		Game.main.loot.drop_gun(g, p.position + p.aim * 30.0, true)
		_shop_status.text = U.t("Backpack full — %s is on the ground") % g.gun_name
	Game.state.note_gun(g)
	Sfx.ui("pickup/gun", -4.0)
	refresh()


func _sell_gun(g: Gun) -> void:
	var p: Player = Game.main.player
	var i := p.guns.find(g)
	if i >= 0:
		if p.gun_count() <= 1:
			return
		p.guns[i] = null
		p.on_gun_changed()
	else:
		i = p.backpack.find(g)
		if i < 0:
			return
		p.backpack.remove_at(i)
	Game.state.add_coins(Shops.sell_price(g))
	_shop_status.text = U.tm("Sold: %s (+%d)", [g.gun_name, U.money(Shops.sell_price(g))])
	Sfx.at("pickup/coin", p.position, -6.0)
	refresh()


func on_town_open(sname: String) -> void:
	if sname in ["shop", "workshop"]:
		_shop_status.text = ""
