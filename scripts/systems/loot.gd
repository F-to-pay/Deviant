class_name Loot
extends RefCounted
## Лут на земле: пушки, монеты, фляги, патроны, сундуки. Владеет списками предметов и их узлами, раздаёт награды
## (`drop_*`, `spawn_*`), подбирает (`pick_coin`, `remove_*`), открывает сундуки. Единственный экземпляр — `Main.loot`.

var main: Main

const MAX_FLASKS_PER_ZONE := 2   # фляг за зону со случайных дропов (вожаки и боссы — сверх этого)
var items: Array = []
var flask_drops: Array = []
var ammo_boxes: Array = []
var chests: Array = []
var coins: Array = []
var flasks_spawned := 0


func _init(m: Main) -> void:
	main = m


## Убрать весь лут и его узлы (смена зоны).
func clear() -> void:
	for it in items:
		if is_instance_valid(it):
			it.queue_free()
	items.clear()
	for o in flask_drops:
		if is_instance_valid(o):
			o.queue_free()
	flask_drops.clear()
	for a in ammo_boxes:
		if is_instance_valid(a):
			a.queue_free()
	ammo_boxes.clear()
	for c in chests:
		if is_instance_valid(c):
			c.queue_free()
	chests.clear()
	for o in coins:
		if is_instance_valid(o):
			o.queue_free()
	coins.clear()


func spawn_chest(pos: Vector2, golden: bool) -> void:
	var c := Chest.new()
	c.position = pos
	c.golden = golden
	main.item_layer.add_child(c)
	chests.append(c)


func drop_gun(g: Gun, pos: Vector2, pop: bool = true) -> void:
	var it := GroundItem.new()
	it.gun = g
	it.position = pos
	if pop:
		it.vel = Vector2.from_angle(randf() * TAU) * randf_range(120.0, 220.0)
	main.item_layer.add_child(it)
	items.append(it)
	if g.rarity >= GunData.R_LEGENDARY:
		Sfx.ui("pickup/legendary", -3.0, 1.0, 0.3)
		Game.say("%s! %s" % [g.rarity_name().to_upper(), g.gun_name], g.rarity_color())
		main.fx.ring(pos, 80.0, g.rarity_color(), 0.6)


## total монет россыпью из pieces штук (не больше 8 — чтобы не плодить узлы). meta — древние.
func drop_coins(pos: Vector2, total: float, pieces: int = 1, meta: bool = false) -> void:
	if total <= 0.0:
		return
	if not meta:
		total = minf(total * float(LevelTree.coin_mult()), Balance.MONEY_MAX)   # узел «Жадность»: шанс удвоить дроп
	var n := clampi(pieces, 1, clampi(int(minf(total, 8.0)), 1, 8))   # не больше монеток, чем монет
	var left := total
	for i in n:
		var c := Coin.new()
		c.meta = meta
		c.value = floorf(left / float(n - i)) if total < 1.0e15 else left / float(n - i)
		left -= c.value
		c.position = pos
		c.vel = Vector2.from_angle(randf() * TAU) * randf_range(70.0, 170.0)
		main.item_layer.add_child(c)
		coins.append(c)


## Монета долетела до игрока.
func pick_coin(c: Coin) -> void:
	coins.erase(c)
	if c.meta:
		Game.add_meta(int(c.value))
		Sfx.ui("pickup/relic", -6.0, 1.0, 0.05)
		main.fx.text(c.position + Vector2(0, -20), "+%d %s" % [int(c.value), U.t("ancient")], Color(0.6, 1.0, 1.0), 14, 1.0)
	else:
		var v := c.value
		Game.state.add_coins(v)
		Quests.progress("coins", v)
		Sfx.at("pickup/coin", c.position, -12.0, 1.0, 0.06, 3, 0.03)
		main.fx.text(c.position + Vector2(0, -16), "+" + U.money(v), Color(1.0, 0.85, 0.3), 14, 0.7)
	c.queue_free()


## Фляга лечения на земле. forced — вне лимита MAX_FLASKS_PER_ZONE (вожаки, боссы). Хардкор — без фляг.
func spawn_flask(pos: Vector2, forced: bool = false) -> void:
	if bool(Game.run["no_heal"]):
		return
	if not forced:
		if flasks_spawned >= MAX_FLASKS_PER_ZONE:
			return
		flasks_spawned += 1
	var o := FlaskDrop.new()
	o.position = pos
	o.vel = Vector2.from_angle(randf() * TAU) * randf_range(60.0, 140.0)
	main.item_layer.add_child(o)
	flask_drops.append(o)


func remove_flask(o: FlaskDrop) -> void:
	flask_drops.erase(o)
	o.queue_free()


## Новая лут-пушка: по умолчанию с пустым магазином (патроны — только дроп и разбор).
func loot_gun(g: Gun) -> Gun:
	if not GunData.LOOT_GUN_LOADED:
		g.ammo = 0
	return g


## Тип патронов для дропа: в основном под пушки в слотах.
func _pick_ammo_type() -> String:
	var held: Array = []
	for o in main.player.guns:
		if o != null:
			var g: Gun = o
			if not g.free_ammo:   # безлимитной пушке патроны ни к чему
				held.append(g.ammo_type())
	if not held.is_empty() and main.rng.randf() < 0.75:
		return held[main.rng.randi() % held.size()]
	var keys: Array = GunData.ARCH.keys()
	var k: String = keys[main.rng.randi() % keys.size()]
	# у некоторых основ патроны чужие (миномёт -> гранаты)
	return str(GunData.ARCH[k].get("ammo", k))


## mags — сколько базовых магазинов этого типа в коробке.
func spawn_ammo(pos: Vector2, mags: float, t: String = "") -> void:
	var at := t if t != "" else _pick_ammo_type()
	var b := AmmoBox.new()
	b.ammo_type = at
	b.amount = maxi(1, ceili(float(GunData.base_mag(at)) * mags))
	b.position = pos
	b.vel = Vector2.from_angle(randf() * TAU) * randf_range(60.0, 150.0)
	main.item_layer.add_child(b)
	ammo_boxes.append(b)


func remove_ammo(b: AmmoBox) -> void:
	ammo_boxes.erase(b)
	b.queue_free()


## X — разобрать лежащую рядом пушку на патроны.
func scrap_near() -> void:
	if main.player.dead or main.transitioning:
		return
	if main.near_item == null or not is_instance_valid(main.near_item):
		return
	var it := main.near_item
	main.player.scrap(it.gun)
	main.fx.ring(it.position, 30.0, GunData.ammo_color(it.gun.ammo_type()), 0.3)
	remove_item(it)


func remove_item(it: GroundItem) -> void:
	items.erase(it)
	if main.near_item == it:
		main.near_item = null
	it.queue_free()


func open_chest(c: Chest) -> void:
	if c.opened:
		return
	c.opened = true
	c.queue_redraw()
	Quests.progress("chests")
	Sfx.at("world/chest", c.position, -2.0, 0.9, 0.05, 2, 0.1)
	var lvl: int = Game.state.zone_level
	var n := main.rng.randi_range(2, 3) + (1 if c.golden else 0)
	for i in n:
		var g := loot_gun(GunGen.generate(lvl, main.rng, 2.5 if c.golden else 1.0, 2 if c.golden else 1))
		drop_gun(g, c.position + Vector2(0, 8))
	if main.rng.randf() < 0.25:
		spawn_flask(c.position)
	drop_coins(c.position, Balance.coins_for(lvl, float(main.rng.randi_range(4, 7) * (2 if c.golden else 1)), main.rng), 5)
	if c.golden:
		drop_coins(c.position, 1, 1, true)
	main.fx.ring(c.position, 50.0, Color(1.0, 0.85, 0.4))
	main.near_chest = null
