class_name Balance
extends RefCounted
## Числа баланса: опыт, кривые сложности, экономика и деньги. Только константы и чистые статические функции —
## никакого состояния и обращений к Game (множители забега приходят параметрами), поэтому формулы легко проверять
## из тестов и считать «на сухую». Параметры забега и его структура (этапы, рейтинг) — в `RunConfig`.

# --- Опыт героя: уровни дают очки дерева навыков (LevelTree) -----------------------------
## Враг даёт XP_BASE + XP_PER_LEVEL × (уровень − 1), умноженное на XP_ELITE_MULT[elite]
## (0 обычный, 1 чемпион, 2 вожак, 3 босс — множители пока заглушки).
## До следующего уровня L → L+1 нужно XP_NEED_BASE × L ^ XP_NEED_POW (1.1): сначала растёт быстро, потом всё медленнее.
const XP_BASE := 1.0
const XP_PER_LEVEL := 0.1
const XP_ELITE_MULT := [1.0, 3.0, 6.0, 25.0]
const XP_NEED_BASE := 40.0
const XP_NEED_POW := 1.1


## Сколько XP нужно, чтобы подняться с уровня lvl на lvl+1.
static func xp_need(lvl: int) -> float:
	return XP_NEED_BASE * pow(float(lvl), XP_NEED_POW)


## Сколько XP нужно, чтобы пройти `levels` уровней (дробное число) с начала уровня lvl: целые уровни по xp_need,
## дробный остаток — долей следующего. Нужен судье: «1,5 уровня за зону» = xp_need(L) + 0,5 × xp_need(L+1).
static func xp_span(lvl: int, levels: float) -> float:
	var total := 0.0
	var l := lvl
	var left := maxf(0.0, levels)
	while left >= 1.0:
		total += xp_need(l)
		l += 1
		left -= 1.0
	return total + left * xp_need(l)


## Сколько XP даёт убийство врага уровня lvl (elite: 0 обычный … 3 босс).
static func enemy_xp(lvl: int, elite: int) -> float:
	return (XP_BASE + XP_PER_LEVEL * float(maxi(0, lvl - 1))) * float(XP_ELITE_MULT[clampi(elite, 0, 3)])


# --- Кривые сложности -------------------------------------------------------
# До зоны FLAT_FROM: здоровье врагов растёт чуть быстрее урона пушек (старые стволы устаревают, приходится лутаться),
# урон врагов — линейно. Дальше кривые «сшиты» с силой героя: см. enemy_hp_mult / enemy_dmg_mult и ref_*.

## Рост за зону. Пушка с зоны N на зоне N+k: враги толще в ENEMY_HP_GROWTH^k — через 4 зоны ×2,
## новая пушка той же зоны отстаёт от врагов на (1.20/1.18)^k — лутаться и менять стволы надо постоянно.
const ENEMY_HP_GROWTH := 1.20
const GUN_DMG_GROWTH := 1.18

## Ровный рост на глубине. Экспонента врагов (1.2^зона) обгоняла и пушки (1.18^зона), и дерево навыков (оно растёт ~ зона^1.5),
## и после зоны ~250 урона у героя не оставалось. Теперь после FLAT_FROM сложность считается от «эталонной сборки»:
##  · HP врага растёт так же, как урон свежей пушки × урон дерева эталона (врагам та же экспонента пушек, что и пушкам);
##  · урон врага растёт так же, как HP героя от дерева эталона;
##  · плюс медленный подъём FLAT_RISE за каждые 100 зон — сложность растёт, но не рвётся.
## Эталон — герой с уровнем ref_level(зона), у которого по трети очков в W1 и V1 (так играют в среднем; REF_W1 / REF_V1 — базовые бонусы узлов).
const FLAT_FROM := 200
const FLAT_RISE := 0.2          # +20% сложности за каждые 100 зон после FLAT_FROM
const REF_LEVEL_K := 0.88       # уровень героя на зоне z ≈ K × z^POW (по замерам: зона 40 — 31, 1000 — ~500)
const REF_LEVEL_POW := 0.92
const REF_SHARE := 1.0 / 3.0    # доля очков эталона в W1 и (отдельно) в V1
const REF_W1 := 0.02            # +к урону за уровень навыка и уровень героя (W1 Firepower)
const REF_V1 := 2.0             # +HP за уровень навыка и уровень героя (V1 Toughness)
const FLOAT_CAP := 1.0e300      # потолок кривых: pow() на глубине тысяч зон даёт inf


static func ref_level(z: int) -> float:
	return maxf(1.0, REF_LEVEL_K * pow(float(z), REF_LEVEL_POW))


## Уровень навыка тира 1 у эталона (цена уровня N — N очков, всего L(L+1)/2).
static func ref_skill_level(z: int) -> float:
	var p := float(LevelTree.POINTS_PER_LEVEL) * (ref_level(z) - 1.0) * REF_SHARE
	return (sqrt(1.0 + 8.0 * p) - 1.0) * 0.5


## Во сколько раз эталонный герой на зоне z бьёт сильнее (множитель «Огневой мощи»).
static func ref_dmg_mult(z: int) -> float:
	return 1.0 + REF_W1 * ref_skill_level(z) * ref_level(z)


## HP эталонного героя на зоне z.
static func ref_hero_hp(z: int) -> float:
	return Player.BASE_HP + REF_V1 * ref_skill_level(z) * ref_level(z)


static func _flat_rise(level: int) -> float:
	return 1.0 + FLAT_RISE * float(level - FLAT_FROM) / 100.0


## Множитель здоровья врага зоны level. hp_mult — множитель сложности забега (`Game.run["hp"]`).
static func enemy_hp_mult(level: int, hp_mult: float = 1.0) -> float:
	var k := pow(ENEMY_HP_GROWTH, float(level - 1))
	if level > FLAT_FROM:
		k = pow(ENEMY_HP_GROWTH, float(FLAT_FROM - 1)) * pow(GUN_DMG_GROWTH, float(level - FLAT_FROM)) \
			* ref_dmg_mult(level) / ref_dmg_mult(FLAT_FROM) * _flat_rise(level)
	return minf(k, FLOAT_CAP) * hp_mult


## Множитель урона врага зоны level. dmg_mult — множитель сложности забега (`Game.run["dmg"]`).
static func enemy_dmg_mult(level: int, dmg_mult: float = 1.0) -> float:
	var k := 1.0 + 0.1 * float(level - 1)
	if level > FLAT_FROM:
		k = (1.0 + 0.1 * float(FLAT_FROM - 1)) * ref_hero_hp(level) / ref_hero_hp(FLAT_FROM) * _flat_rise(level)
	return minf(k, FLOAT_CAP) * dmg_mult


static func gun_dmg_mult(level: int) -> float:
	return minf(pow(GUN_DMG_GROWTH, float(level - 1)), FLOAT_CAP)


# --- Монеты ---------------------------------------------------------------------

## Экономика: доход и цены растут на ECON_GROWTH за этап (10:12), а не с каждой зоной.
## Монеты с врагов ещё и делятся на рост числа врагов в зоне — иначе доход рос бы вместе с ним.
const ECON_GROWTH := 1.2

## Эталон «врагов в зоне» для монет: столько их было на 1-й зоне до сокращения карт (21 пак × 5). Доход с зоны
## остаётся прежним, хотя врагов стало меньше, — каждый убитый приносит соответственно больше.
const COIN_REF_ENEMIES := 105.0

## Деньги — дробные числа (double): цены растут как 1.2^этап, а int64 кончается на 9.2e18 (зона ~1200) — там они уходили в минус.
## Целые до 9×10^15 хранятся точно, дальше — приблизительно, как и должно быть у таких сумм. 10^17 монет = 1 ультамонета (U.ULTRA),
## при показе (U.money) большие суммы пишутся в ультамонетах. Потолок — MONEY_MAX, чтобы не получить inf.
const MONEY_MAX := 1.0e300


## Множитель цен и наград для зоны level: 1.0 на первом этапе, ×1.2 за каждый следующий.
static func econ(level: int) -> float:
	return pow(ECON_GROWTH, float(maxi(0, level - 1) / RunConfig.TOWN_EVERY))


## Сколько врагов в среднем в зоне (как в ZoneGen и EnemyData.roll_pack).
static func expected_enemies(level: int) -> float:
	return float(ZoneGen.pack_count(level)) * (10.0 + float(mini(level / 3, 5))) * 0.5


## Монеты из base «монет первого этапа»: × econ, дробная часть — случайно (0.4 — с шансом 40% одна монета).
static func coins_for(level: int, base: float, r: RandomNumberGenerator) -> float:
	return _round_rand(base * econ(level), r)


## То же для добычи с врагов: ещё и делится на рост числа врагов, чтобы доход за зону не рос с ним.
static func kill_coins(level: int, base: float, r: RandomNumberGenerator) -> float:
	return _round_rand(base * econ(level) * COIN_REF_ENEMIES / expected_enemies(level), r)


static func _round_rand(x: float, r: RandomNumberGenerator) -> float:
	if is_nan(x) or x >= MONEY_MAX:
		return MONEY_MAX
	if x >= 1.0e15:
		return roundf(x)   # такие суммы дробной части не имеют
	var n := floorf(x)
	return n + (1.0 if r.randf() < x - n else 0.0)


## Монеты за одного убитого врага зоны lvl (elite: 0 обычный, 1 чемпион, 2 вожак, 3 босс): в монетах первого этапа
## обычный — в среднем 0.35, чемпион 2–4, вожак 5–8, босс этапа 30, бродячий босс хаоса 15. Одна формула и для настоящих
## убийств (`Main.on_enemy_killed`, `_boss_dead`), и для пропуска зон (`Main.skip_zone`).
static func kill_coin_value(lvl: int, elite: int, r: RandomNumberGenerator) -> float:
	match elite:
		0:
			return kill_coins(lvl, 0.35, r)
		1:
			return kill_coins(lvl, float(r.randi_range(2, 4)), r)
		2:
			return kill_coins(lvl, float(r.randi_range(5, 8)), r)
	return coins_for(lvl, 30.0 if RunConfig.is_boss_zone(lvl) else 15.0, r)


## Сумму (цену, награду) — в целые монеты, не ниже 0 и не выше MONEY_MAX.
static func money(x: float) -> float:
	if is_nan(x) or x >= MONEY_MAX:
		return MONEY_MAX
	return maxf(0.0, roundf(x))
