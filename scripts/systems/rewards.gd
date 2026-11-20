class_name Rewards
extends RefCounted
## Награды за убийства: опыт, монеты, патроны, фляги, пушки, добыча боссов, заказ Шерифа, смерть героя.
## Враги зовут `Main.rewards.on_enemy_killed(e)`, герой — `on_player_died()`. Экземпляр — `Main.rewards`.

var main: Main


func _init(m: Main) -> void:
	main = m


func on_enemy_killed(e: Enemy, by_player: bool = true) -> void:
	main.enemies.erase(e)
	if e.elite != 3:
		# крупные — ниже и громче
		Sfx.at("enemy/death", e.position, -9.0 if e.elite == 0 else -5.0, clampf(18.0 / e.radius, 0.7, 1.3), 0.08, 3, 0.04)
	main.fx.death_burst(e.position, e.color, e.radius)
	if by_player and not e.summoned:
		Game.add_xp(main.director.kill_xp(e.level, e.elite))
	if e.elite == 3:
		_boss_dead(e)
		return
	if not by_player:
		return
	Game.state.kills += 1
	Quests.progress("kills")
	if e.elite == 1 or e.elite == 2:
		Quests.progress("elites")
	var lvl: int = Game.state.zone_level
	var chance := 0.055
	var bonus := 0.0
	if e.elite == 1:
		chance = 0.4
		bonus = 0.6
	elif e.elite == 2:
		chance = 1.0
		bonus = 1.3
	if main.rng.randf() < chance:
		main.loot.drop_gun(main.loot.loot_gun(GunGen.generate(lvl, main.rng, bonus)), e.position)
	if e.elite == 2 and main.rng.randf() < 0.5:
		main.loot.drop_gun(main.loot.loot_gun(GunGen.generate(lvl, main.rng, bonus)), e.position)
	# фляги: обычный — 3%, чемпион — 25% (в пределах лимита зоны), вожак — одна всегда
	if e.elite == 2:
		main.loot.spawn_flask(e.position, true)
	elif main.rng.randf() < (0.03 if e.elite == 0 else 0.25):
		main.loot.spawn_flask(e.position)
	# монеты (на первом этапе): обычный — в среднем 0.35, чемпион — 2–4, вожак — 5–8 и иногда древняя.
	# Balance.kill_coins: ×1.2 за этап и делится на рост числа врагов в зоне
	var coin_total := Balance.kill_coin_value(lvl, e.elite, main.rng)
	if e.elite == 0:
		main.loot.drop_coins(e.position, coin_total)
	elif e.elite == 1:
		main.loot.drop_coins(e.position, coin_total, 3)
	else:
		main.loot.drop_coins(e.position, coin_total, 5)
		if main.rng.randf() < 0.15:
			main.loot.drop_coins(e.position, 1, 1, true)
	if e.bounty:
		_pay_bounty(e, coin_total)
	# патроны: обычный — 15% на полмагазина, чемпион — 60% на магазин, вожак — 2 магазина
	if e.elite == 0:
		if main.rng.randf() < 0.15:
			main.loot.spawn_ammo(e.position, 0.5)
	elif e.elite == 1:
		if main.rng.randf() < 0.6:
			main.loot.spawn_ammo(e.position, 1.0)
	else:
		main.loot.spawn_ammo(e.position, 1.0)
		main.loot.spawn_ammo(e.position, 1.0)


## Цель заказа Шерифа (узел «Охотник за головами») убита: добавка к монетам и гарантированная пушка.
func _pay_bounty(e: Enemy, coin_total: float) -> void:
	var extra := maxf(1.0, Balance.money(coin_total * LevelTree.stat("bounty_coins")))
	main.loot.drop_coins(e.position, extra, 4)
	if LevelTree.stat("bounty_gun") > 0.0:
		main.loot.drop_gun(main.loot.loot_gun(GunGen.generate(Game.state.zone_level, main.rng, 0.6)), e.position)
	main.fx.ring(e.position, 90.0, Color(1.0, 0.35, 0.25), 0.5)
	Game.say(U.t("Bounty collected!"), Color(1.0, 0.45, 0.35))


## Заказ на зону: цель — случайный чемпион (нет их — любой обычный враг). Рандом — глобальный, чтобы не сбивать сид забега.
func mark_bounty() -> void:
	if LevelTree.stat("bounty_gun") <= 0.0 and LevelTree.stat("bounty_coins") <= 0.0:
		return
	var pool: Array = []
	var champs: Array = []
	for o in main.enemies:
		var e: Enemy = o
		if e.summoned or e.dead or e.elite >= 3:
			continue
		pool.append(e)
		if e.elite >= 1:
			champs.append(e)
	var from: Array = champs if not champs.is_empty() else pool
	if from.is_empty():
		return
	var t: Enemy = from[randi() % from.size()]
	t.bounty = true
	t.queue_redraw()
	Game.say(U.t("Bounty: %s") % t.title, Color(1.0, 0.45, 0.35))


func _boss_dead(b: Enemy) -> void:
	if main.boss == b:
		main.boss = null
	Game.state.kills += 1
	Game.state.bosses += 1
	Quests.progress("kills")
	if RunConfig.is_boss_zone(Game.state.zone_level):
		Quests.progress("boss")
	var lvl: int = Game.state.zone_level
	main.fx.explosion(b.position, 220.0, b.color, true)
	main.fx.shake(18.0)
	Game.say(U.t("Boss defeated: ") + b.title, Color(1.0, 0.85, 0.3))
	Sfx.ui("boss/death", -2.0)
	Sfx.at("explosion_big", b.position, 0.0, 0.7, 0.05, 2, 0.1)
	if not RunConfig.is_boss_zone(lvl):
		# бродячий босс хаоса: лут поскромнее, без портала и смены музыки
		main.loot.drop_gun(main.loot.loot_gun(GunGen.generate(lvl + 1, main.rng, 3.0, GunData.R_EPIC if main.rng.randf() < 0.3 else GunData.R_RARE)), b.position)
		for i in 2:
			main.loot.spawn_flask(b.position, true)
		main.loot.drop_coins(b.position, Balance.kill_coin_value(lvl, 3, main.rng), 6)
		main.loot.drop_coins(b.position, 1, 1, true)
		for i in 2:
			main.loot.spawn_ammo(b.position, 1.0)
		return
	main.music.on_boss_dead()
	var top := GunData.R_LEGENDARY if main.rng.randf() < 0.4 else GunData.R_EPIC
	main.loot.drop_gun(main.loot.loot_gun(GunGen.generate(lvl + 1, main.rng, 4.0, top)), b.position)
	for i in 2:
		main.loot.drop_gun(main.loot.loot_gun(GunGen.generate(lvl, main.rng, 3.0, GunData.R_RARE)), b.position)
	for i in 2:
		main.loot.spawn_flask(b.position, true)
	for i in 4:
		main.loot.spawn_ammo(b.position, 1.0)
	# босс этапа: горсть монет и древние монеты (чем глубже, тем больше)
	main.loot.drop_coins(b.position, Balance.kill_coin_value(lvl, 3, main.rng), 8)
	main.loot.drop_coins(b.position, 3 + lvl / 5, mini(5, 3 + lvl / 5), true)
	main.loader.spawn_portal(main.zone.random_free_near(b.position + Vector2(0, -90), 0.0, 60.0), lvl + 1)


func on_player_died() -> void:
	var rec: bool = Game.record_death()
	main.hud.show_death(rec)
	main.music.on_death()
