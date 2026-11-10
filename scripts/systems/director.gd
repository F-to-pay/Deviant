class_name Director
extends RefCounted
## «Судья» забега: считает, сколько опыта (XP) заложено во врагах зоны. ПОКА ТОЛЬКО НАБЛЮДАЕТ — ни на спавн, ни на статы врагов не влияет.
## Цель: подогнать по этим цифрам кривую так, чтобы запас XP в зоне вёл героя по задуманной кривой уровней,
## а потом уже отдавать судье решение «сколько и каких врагов ставить» (бюджет кредитов, как в Risk of Rain 2).
## Сейчас 1 кредит = 1 XP (цена врага = его награда). Вывод — в оверлее отладки (F3), строка `describe()`.

var packs: int = 0
var enemies: int = 0
var pool_xp: float = 0.0         # сколько XP во всех врагах зоны (без призванных — за них опыта нет)
var by_elite: Array = [0, 0, 0, 0]


func begin_zone() -> void:
	packs = 0
	enemies = 0
	pool_xp = 0.0
	by_elite = [0, 0, 0, 0]


func note_pack() -> void:
	packs += 1


func note_spawn(level: int, elite: int) -> void:
	enemies += 1
	pool_xp += Game.enemy_xp(level, elite)
	by_elite[clampi(elite, 0, 3)] += 1


## Сколько уровней героя дал бы весь запас XP зоны из текущего состояния (дробное: остаток — доля следующего).
func levels_worth() -> float:
	var x: float = Game.xp + pool_xp
	var lvl: int = Game.hero_level
	while x >= Game.xp_need(lvl):
		x -= Game.xp_need(lvl)
		lvl += 1
	return float(lvl - Game.hero_level) + x / Game.xp_need(lvl)


func describe() -> String:
	return "pool %.0f XP · %d en/%d packs · ch %d ld %d bs %d · ≈%.2f lvl" % [pool_xp, enemies, packs,
		by_elite[1], by_elite[2], by_elite[3], levels_worth()]
