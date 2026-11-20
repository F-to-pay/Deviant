class_name GuildScreen
extends MenuScreen
## Гильдия: задания (Quests).

var _guild_offers: VBoxContainer
var _guild_active: VBoxContainer
var _guild_active_title: Label


func build(root: Control) -> void:
	var box := _screen(root, "guild")
	menu.town_head(box, "guild", U.t("GUILD"))
	box.add_child(MenuKit.label(U.t("A contract pays the moment it is done. One contract at a time."), 18, DIM))
	box.add_child(MenuKit.gap(6))
	box.add_child(MenuKit.label(U.t("Contracts on the board"), 22, TEXT))
	_guild_offers = VBoxContainer.new()
	_guild_offers.add_theme_constant_override("separation", 6)
	box.add_child(_guild_offers)
	box.add_child(MenuKit.gap(6))
	_guild_active_title = MenuKit.label("", 22, TEXT)
	box.add_child(_guild_active_title)
	_guild_active = VBoxContainer.new()
	_guild_active.add_theme_constant_override("separation", 6)
	box.add_child(_guild_active)
	var back := MenuKit.button(U.t("Back"), menu.back)
	box.add_child(back)
	menu.first_focus["guild"] = back


func refresh(_sname: String = "") -> void:
	menu.refresh_town_head("guild")
	MenuKit.clear_box(_guild_offers)
	MenuKit.clear_box(_guild_active)
	var offers: Array = Game.main.town.get("guild", [])
	if offers.is_empty():
		_guild_offers.add_child(MenuKit.label(U.t("The board is empty."), 18, DIM))
	for q in offers:
		var b := MenuKit.small_button(U.tm("Take: %s — +%d ancient coins, +%d coins", [Quests.text(q), str(int(q["reward"])), U.money(float(q["coins"]))]),
			_take_quest.bind(q), 1000.0)
		b.disabled = not Quests.can_take() or Quests.has_type(str(q["type"]))
		_guild_offers.add_child(b)
	_guild_active_title.text = U.t("Your contracts (%d/%d)") % [Game.state.quests.size(), Quests.MAX_ACTIVE]
	for i in Game.state.quests.size():
		var q: Dictionary = Game.state.quests[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := MenuKit.label(U.tm("%s — +%d ancient, +%d coins", [Quests.line(q), str(int(q["reward"])), U.money(float(q["coins"]))]), 18, Color(0.6, 1.0, 1.0), false, HORIZONTAL_ALIGNMENT_LEFT)
		l.custom_minimum_size = Vector2(700, 0)
		row.add_child(l)
		row.add_child(MenuKit.small_button(U.t("Abandon"), _abandon_quest.bind(i), 190.0))
		_guild_active.add_child(row)
	MenuKit.grab_first(_guild_offers)


func _take_quest(q: Dictionary) -> void:
	if Quests.take(q):
		var offers: Array = Game.main.town.get("guild", [])
		offers.erase(q)
		Sfx.ui("ui/put", -6.0)
	else:
		Sfx.ui("ui/error", -6.0)
	refresh()


func _abandon_quest(i: int) -> void:
	Quests.abandon(i)
	Sfx.ui("ui/close", -8.0)
	refresh()
