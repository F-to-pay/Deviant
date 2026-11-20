class_name Director
extends RefCounted
## «Судья» забега: решает, сколько опыта (XP) зона отдаёт герою, и любит ставить элитных врагов.
##  1. Бюджет: зона, зачищенная целиком, даёт LEVELS_PER_ZONE уровней героя (считается от его уровня на входе в зону).
##  2. Вкус: паки с чемпионами и вожаками выпадают в ELITE_LOVE раз чаще обычного (`EnemyData.roll_pack`).
##  3. Выравнивание: когда зона расставлена, `finish_zone()` считает множитель `xp_scale`, при котором сумма XP всех
##     её врагов ровно равна бюджету. Награда за врага = `Balance.enemy_xp` × `xp_scale` (`kill_xp`). Так кривая уровней
##     не зависит от того, сколько и каких врагов выпало: чем глубже зона, тем дороже каждый убитый.
## Призванные враги опыта не дают и в запас не входят. Вывод — в оверлее отладки (F3), строка `describe()`.

## Сколько уровней героя отдаёт зона при полной зачистке (ориентир, а не гарантия: часть врагов можно обойти).
const LEVELS_PER_ZONE := 1.5
## Во сколько раз судья чаще обычного ставит паки с чемпионами и вожаками (потолок шансов — в `EnemyData.roll_pack`).
const ELITE_LOVE := 1.6

var packs: int = 0
var enemies: int = 0
var pool_xp: float = 0.0         # сколько «сырого» XP во всех врагах зоны (без xp_scale и рейтинга; призванные не в счёт)
var by_elite: Array = [0, 0, 0, 0]
var xp_scale: float = 1.0        # множитель награды за убийство в этой зоне (1.0 до расстановки)


func begin_zone() -> void:
	packs = 0
	enemies = 0
	pool_xp = 0.0
	by_elite = [0, 0, 0, 0]
	xp_scale = 1.0


func note_pack() -> void:
	packs += 1


func note_spawn(level: int, elite: int) -> void:
	enemies += 1
	pool_xp += Balance.enemy_xp(level, elite)
	by_elite[clampi(elite, 0, 3)] += 1


## Сколько «сырого» XP (до множителя рейтинга) отдаёт зона, зачищенная целиком, герою уровня hero_level — бюджет судьи.
## Им же платит пропущенная зона (`Main.skip_zone`).
static func zone_xp(hero_level: int) -> float:
	return Balance.xp_span(hero_level, LEVELS_PER_ZONE)


## Зона расставлена: подогнать награду так, чтобы вся она стоила LEVELS_PER_ZONE уровней (с учётом множителя рейтинга,
## который `Game.add_xp` применяет сам).
func finish_zone() -> void:
	var raw := pool_xp * maxf(0.05, RunConfig.rating_mult(Game.run))
	if raw <= 0.0:
		xp_scale = 1.0
		return
	xp_scale = zone_xp(Game.state.hero_level) / raw


## Награда героя за убийство врага в этой зоне (до множителя рейтинга).
func kill_xp(level: int, elite: int) -> float:
	return Balance.enemy_xp(level, elite) * xp_scale


## Сколько уровней героя дал бы весь запас XP зоны из текущего состояния (дробное: остаток — доля следующего).
func levels_worth() -> float:
	var x: float = Game.state.xp + pool_xp * xp_scale * RunConfig.rating_mult(Game.run)   # опыт в зоне идёт с множителем рейтинга
	var lvl: int = Game.state.hero_level
	while x >= Balance.xp_need(lvl):
		x -= Balance.xp_need(lvl)
		lvl += 1
	return float(lvl - Game.state.hero_level) + x / Balance.xp_need(lvl)


func describe() -> String:
	return "pool %.0f XP ×%.2f · %d en/%d packs · ch %d ld %d bs %d · ≈%.2f lvl" % [pool_xp, xp_scale, enemies, packs,
		by_elite[1], by_elite[2], by_elite[3], levels_worth()]
