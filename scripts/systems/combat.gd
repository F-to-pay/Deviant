class_name Combat
extends RefCounted
## Нанесение урона: попадания, взрывы, цепные молнии.

const SELF_DAMAGE := 0.1   # доля урона своих взрывов по герою


static func hit_enemy(e: Enemy, dmg: float, crit: bool, el: int, kb: Vector2, quiet: bool = false,
		st: float = 0.1) -> void:
	if e.dead:
		return
	e.hurt(dmg, crit, el, kb, quiet, st)
	# Электричество при срабатывании бьёт ещё пару соседей (без рекурсии).
	if el == U.EL_SHOCK:
		chain(e, dmg * 0.35, 2, U.EL_NONE)


static func chain(from: Enemy, dmg: float, count: int, el: int, st: float = 0.1) -> void:
	var main: Main = Game.main
	var cur := from.position
	var visited: Dictionary = {from.get_instance_id(): true}
	var col := U.el_color(el) if el >= 0 else U.el_color(U.EL_SHOCK)
	for i in count:
		var best: Enemy = null
		var bd := 210.0 * 210.0
		for o in main.grid_hash.query(cur, 210.0):
			var e: Enemy = o
			if e.dead or visited.has(e.get_instance_id()):
				continue
			var d2 := cur.distance_squared_to(e.position)
			if d2 < bd:
				bd = d2
				best = e
		if best == null:
			break
		visited[best.get_instance_id()] = true
		main.fx.lightning(cur, best.position, col)
		var target_pos := best.position
		best.hurt(dmg, false, el, Vector2.ZERO, false, st)
		cur = target_pos


## Взрыв. team 0 бьёт врагов, team 1 — игрока. Возвращает суммарный урон.
static func explode(pos: Vector2, r: float, dmg: float, crit: bool, el: int, team: int, knock: float,
		big: bool = false, st: float = 0.1) -> float:
	var main: Main = Game.main
	var col := Color(1.0, 0.6, 0.2)
	if el >= 0:
		col = U.el_color(el)
	elif team == 1:
		col = Color(1.0, 0.3, 0.2)
	main.fx.explosion(pos, r, col, big)
	main.sfx.explosion(pos, r, big)
	main.fx.shake(minf(2.0 + r / 30.0, 16.0 if big else 9.0))
	var total := 0.0
	if team == 0:
		for o in main.grid_hash.query(pos, r + 50.0):
			var e: Enemy = o
			if e.dead:
				continue
			var dist := pos.distance_to(e.position)
			if dist > r + e.radius:
				continue
			# урон падает от эпицентра к краю: 100% -> 20%
			var k := lerpf(1.0, 0.2, clampf(dist / r, 0.0, 1.0))
			var dir := Vector2.RIGHT
			if dist > 1.0:
				dir = (e.position - pos) / dist
			e.hurt(dmg * k, crit, el, dir * knock, false, st)
			total += dmg * k
		# Свои взрывы задевают и героя: x10 слабее, урон нормирован к уровню
		# (иначе на 30-й зоне своя граната ваншотила бы).
		var pl: Player = main.player
		var pd := pos.distance_to(pl.position)
		# hurt_dot, а не take_damage: самоподрыв не должен давать i-frames (абуз). Перекат спасает.
		if not pl.dead and pl.dodge_t <= 0.0 and pd < r + pl.radius * 0.6:
			var lvl_mult: float = Game.gun_dmg_mult(Game.zone_level)
			var pk := lerpf(1.0, 0.2, clampf(pd / r, 0.0, 1.0))
			pl.hurt_dot(dmg / lvl_mult * pk * SELF_DAMAGE, -1)
	else:
		var p: Player = main.player
		if not p.dead and pos.distance_to(p.position) < r + p.radius * 0.6:
			p.take_damage(dmg)
	return total
