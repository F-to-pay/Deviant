class_name WorkshopScreen
extends MenuScreen
## Мастерская: пересборка, объединение и повышение редкости пушек.

var _ws_list: VBoxContainer
var _ws_actions: VBoxContainer
var _ws_prev: GunPreview
var _ws_status: Label
var _ws_gun: Gun = null
var _ws_partner: Gun = null      # вторая пушка при объединении (ждём выбора, кто стреляет, а кто заряжает)
var _ws_pick: Dictionary = {}    # оплаченная переброска: {"gun", "drop", "options"} — осталось выбрать перк из трёх


func build(root: Control) -> void:
	var box := _screen(root, "workshop", true)
	menu.town_head(box, "workshop", U.t("WORKSHOP"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var left := VBoxContainer.new()
	left.add_child(MenuKit.label(U.t("Your guns"), 22, TEXT))
	var lb := MenuKit.list_box(440, 560)
	left.add_child(lb[0])
	_ws_list = lb[1]
	row.add_child(left)
	_ws_prev = GunPreview.new()
	row.add_child(_ws_prev)
	var right := VBoxContainer.new()
	right.add_child(MenuKit.label(U.t("Work"), 22, TEXT))
	_ws_actions = VBoxContainer.new()
	_ws_actions.add_theme_constant_override("separation", 6)
	right.add_child(_ws_actions)
	row.add_child(right)
	_ws_status = MenuKit.label("", 18, DIM)
	box.add_child(_ws_status)
	var back := MenuKit.button(U.t("Back"), menu.back)
	box.add_child(back)
	menu.first_focus["workshop"] = back


func refresh(_sname: String = "") -> void:
	menu.refresh_town_head("workshop")
	MenuKit.clear_box(_ws_list)
	var guns := MenuKit.player_guns()
	var still := false
	for e in guns:
		var g: Gun = e[0]
		if g == _ws_gun:
			still = true
		var b := MenuKit.gun_row(g, "%s (%s)" % [g.gun_name, MenuKit.gun_where(e)], _ws_select.bind(g), _ws_prev)
		_ws_list.add_child(b)
	if not still:
		_ws_gun = Game.main.player.gun()
	_ws_fill_actions()
	MenuKit.grab_first(_ws_list)


func _ws_select(g: Gun) -> void:
	_ws_gun = g
	_ws_partner = null
	_ws_fill_actions()


func _ws_fill_actions() -> void:
	MenuKit.clear_box(_ws_actions)
	var g := _ws_gun
	if g == null:
		return
	_ws_prev.show_gun(g)
	_ws_actions.add_child(MenuKit.label(g.gun_name, 18, g.rarity_color(), false, HORIZONTAL_ALIGNMENT_LEFT))
	if _ws_pick.get("gun") == g:
		_ws_fill_pick(g)
		return
	if _ws_partner != null and _ws_player_has(_ws_partner):
		_ws_fill_combine(g, _ws_partner)
		return
	_ws_partner = null
	if Shops.can_rarity_up(g):
		var rp := Shops.rarity_up_price(g)
		var rb := MenuKit.small_button(U.tm("Raise rarity: %s — %d", [U.t(str(GunData.RARITIES[g.rarity + 1]["name"])), U.money(rp)]),
			_ws_rarity, 460.0)
		rb.disabled = Game.state.coins < rp
		_ws_actions.add_child(rb)
	var rr := Shops.reroll_price(g)
	var perks := GunGen.rerollable(g)
	if perks.is_empty():
		_ws_actions.add_child(MenuKit.label(U.t("No perks to reroll"), 16, DIM, false, HORIZONTAL_ALIGNMENT_LEFT))
	for id in perks:
		var nm := I18n.word(str(GunData.perk(str(id)).get("name", id)), "m")
		var pb := MenuKit.small_button(U.tm("Reroll «%s» (pick 1 of 3) — %d", [nm, U.money(rr)]), _ws_reroll.bind(str(id)), 460.0)
		pb.disabled = Game.state.coins < rr
		_ws_actions.add_child(pb)
	_ws_fill_combine_list(g)


func _ws_player_has(g: Gun) -> bool:
	var p: Player = Game.main.player
	return p.guns.has(g) or p.backpack.has(g)


## Три перка на выбор вместо сброшенного (деньги уже заплачены).
func _ws_fill_pick(g: Gun) -> void:
	var drop := str(_ws_pick["drop"])
	var dn := I18n.word(str(GunData.perk(drop).get("name", drop)), "m")
	var hd := MenuKit.label(U.t("Pick a replacement for «%s»:") % dn, 17, Color(0.75, 1.0, 0.55), false, HORIZONTAL_ALIGNMENT_LEFT)
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ws_actions.add_child(hd)
	for id in _ws_pick["options"]:
		var d := GunData.perk(str(id))
		var nm := I18n.word(str(d.get("name", id)), "m")
		_ws_actions.add_child(MenuKit.small_button(nm, _ws_choose.bind(str(id)), 460.0))
		var fx := MenuKit.label(", ".join(PackedStringArray(GunOps.describe(d.get("ops", [])))), 14, DIM, false, HORIZONTAL_ALIGNMENT_LEFT)
		fx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fx.custom_minimum_size = Vector2(460, 0)
		_ws_actions.add_child(fx)


func _ws_choose(id: String) -> void:
	var g: Gun = _ws_pick.get("gun")
	if g == null or not _ws_player_has(g):
		_ws_pick = {}
		refresh()
		return
	var drop := str(_ws_pick["drop"])
	_ws_pick = {}
	var ng := GunGen.rebuild(g, g.rarity, drop, Game.main.rng, id)
	_ws_replace(g, ng)
	_ws_status.text = U.t("Rebuilt: %s") % ng.gun_name
	refresh()


## Список «с чем объединить»: другие обычные пушки, которые подходят (хотя бы в одну сторону).
func _ws_fill_combine_list(g: Gun) -> void:
	_ws_actions.add_child(MenuKit.gap(6))
	_ws_actions.add_child(MenuKit.label(U.t("Combine guns"), 18, TEXT, false, HORIZONTAL_ALIGNMENT_LEFT))
	if g.legendary != "" or g.archetype2 != "":
		_ws_actions.add_child(MenuKit.label(U.t("Legendary and hybrid guns can't be combined"), 16, DIM, false, HORIZONTAL_ALIGNMENT_LEFT))
		return
	var any := false
	for e in MenuKit.player_guns():
		var h: Gun = e[0]
		if GunGen.combine_block(g, h) != "" and GunGen.combine_block(h, g) != "":
			continue
		any = true
		var price := Shops.combine_price(g, h)
		var b := MenuKit.small_button(U.tm("With «%s» — %d", [h.gun_name, U.money(price)]), _ws_pick_partner.bind(h), 460.0)
		b.disabled = Game.state.coins < price
		_ws_actions.add_child(b)
	if not any:
		_ws_actions.add_child(MenuKit.label(U.t("No suitable gun to combine with"), 16, DIM, false, HORIZONTAL_ALIGNMENT_LEFT))


func _ws_pick_partner(h: Gun) -> void:
	_ws_partner = h
	_ws_fill_actions()


## Выбор, как объединить: кто даёт узор стрельбы (и марку), а чьи снаряд и патроны.
func _ws_fill_combine(g: Gun, h: Gun) -> void:
	var price := Shops.combine_price(g, h)
	var hd := MenuKit.label(U.t("Who shoots and who loads? Both guns are consumed — {0}").replace("{0}", U.tm("price %d", [U.money(price)])),
		16, Color(0.75, 1.0, 0.55), false, HORIZONTAL_ALIGNMENT_LEFT)
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hd.custom_minimum_size = Vector2(460, 0)
	_ws_actions.add_child(hd)
	for dir in [[g, h], [h, g]]:
		var pat: Gun = dir[0]
		var am: Gun = dir[1]
		if GunGen.combine_block(pat, am) != "":
			continue
		var t := Gun.new()
		t.archetype = pat.archetype
		t.archetype2 = am.archetype
		var l := MenuKit.label(U.t("«%s» shoots, «%s» loads") % [pat.gun_name, am.gun_name], 14, DIM, false, HORIZONTAL_ALIGNMENT_LEFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(460, 0)
		_ws_actions.add_child(l)
		var b := MenuKit.small_button(t.type_name(), _ws_combine.bind(pat, am), 460.0)
		b.disabled = Game.state.coins < price
		_ws_actions.add_child(b)
	_ws_actions.add_child(MenuKit.small_button(U.t("Cancel"), _ws_cancel_combine, 460.0))


func _ws_cancel_combine() -> void:
	_ws_partner = null
	_ws_fill_actions()


## Объединить: результат встаёт на место выбранной пушки (_ws_gun), вторая пропадает.
func _ws_combine(pat: Gun, am: Gun) -> void:
	var g := _ws_gun
	var other: Gun = am if pat == g else pat
	if g == null or not (pat == g or am == g) or not _ws_player_has(other) or GunGen.combine_block(pat, am) != "":
		return
	if not _ws_pay(Shops.combine_price(pat, am)):
		return
	var ng := GunGen.combine(pat, am, Game.main.rng)
	var p: Player = Game.main.player
	var i := p.guns.find(other)
	if i >= 0:
		p.guns[i] = null
		p.on_gun_changed()
	else:
		i = p.backpack.find(other)
		if i >= 0:
			p.backpack.remove_at(i)
	_ws_partner = null
	_ws_replace(g, ng)
	_ws_status.text = U.t("Combined: %s") % ng.gun_name
	refresh()


## Заменить пушку игрока (там же, где лежала) на новую.
func _ws_replace(old: Gun, g: Gun) -> void:
	var p: Player = Game.main.player
	var i := p.guns.find(old)
	if i >= 0:
		p.guns[i] = g
		p.on_gun_changed()
	else:
		i = p.backpack.find(old)
		if i >= 0:
			p.backpack[i] = g
	_ws_gun = g
	Game.state.note_gun(g)


func _ws_pay(price: int) -> bool:
	if price <= 0 or Game.state.coins < price:
		Sfx.ui("ui/error", -6.0)
		return false
	Game.state.add_coins(-price)
	Sfx.ui("ui/scrap", -4.0)
	return true


func _ws_rarity() -> void:
	var g := _ws_gun
	if g == null or not Shops.can_rarity_up(g) or not _ws_pay(Shops.rarity_up_price(g)):
		return
	var ng := GunGen.rebuild(g, g.rarity + 1, "", Game.main.rng)
	_ws_replace(g, ng)
	_ws_status.text = U.t("Rebuilt: %s") % ng.gun_name
	refresh()


func _ws_reroll(id: String) -> void:
	var g := _ws_gun
	if g == null or not (id in g.mods):
		return
	var opts := GunGen.reroll_options(g, id, Game.main.rng)
	if opts.is_empty():
		_ws_status.text = U.t("No perk fits this gun")
		Sfx.ui("ui/error", -6.0)
		return
	if not _ws_pay(Shops.reroll_price(g)):
		return
	_ws_pick = {"gun": g, "drop": id, "options": opts}   # платим сразу: закрыть и открыть заново — не способ получить другие три перка
	_ws_status.text = ""
	_ws_fill_actions()


func on_town_open(sname: String) -> void:
	if sname in ["shop", "workshop"]:
		_ws_status.text = ""
