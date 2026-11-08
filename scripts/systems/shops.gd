class_name Shops
extends RefCounted
## Цены и товар городских лавок (экраны — в Menu: _build_shop, _build_mystic, _build_workshop).
##  Оружейная — купить пушку из ассортимента / продать свою, обновить ассортимент, купить магазин патронов.
##  Мистик — один перк героя на забег за город (1 из 3), каждый следующий дороже.
##  Мастерская — подтянуть уровень пушки, перебросить перк, поднять редкость.
## Все цены — в обычных монетах и растут с глубиной так же, как стоимость монетки (Game.coin_value).
## Ассортимент города создаётся при входе в него (Main.load_town -> make_town) и живёт до выхода.

## Цена пушки по редкости (обычная ... абсурдная) при стоимости монетки 1.
const RARITY_PRICE := [15, 30, 60, 120, 300, 500]
const SELL_SHARE := 0.25        # продажа — четверть цены
const STOCK := 8                # пушек в Оружейной
const REROLL_STOCK_BASE := 10   # обновить ассортимент; каждое следующее обновление в этом городе — +50%
const AMMO_MARKUP := 1.5        # патроны дороже, чем их «стоимость» при разборе (см. ammo_price)
const MYSTIC_OFFER := 3         # перков на выбор у Мистика
const MYSTIC_BASE := 40         # первый перк; каждый следующий за забег — +50%
const REROLL_SHARE := 0.35      # переброс перка — доля цены пушки
const RARITY_UP_SHARE := 0.7    # повышение редкости — доля цены пушки новой редкости

## Перки Мистика (на забег, складываются). stat — что меняет (Player.stat_mult), v — на сколько за штуку.
const MYSTIC := {
	"vitality": {"name": "Vitality", "desc": "+15% max health", "stat": "hp", "v": 0.15},
	"swift": {"name": "Swiftness", "desc": "+8% move speed", "stat": "speed", "v": 0.08},
	"focus": {"name": "Focus", "desc": "Skill cooldown −15%", "stat": "skill_cd", "v": -0.15},
	"zeal": {"name": "Zeal", "desc": "+25% skill damage", "stat": "skill_dmg", "v": 0.25},
	"power": {"name": "Power", "desc": "+10% gun damage", "stat": "dmg", "v": 0.1},
	"hands": {"name": "Quick Hands", "desc": "Reload time −15%", "stat": "reload", "v": -0.15},
	"reflex": {"name": "Reflexes", "desc": "Dodge cooldown −20%", "stat": "dodge_cd", "v": -0.2},
	"greed": {"name": "Greed", "desc": "+20% coins", "stat": "coins", "v": 0.2},
	"scavenger": {"name": "Scavenger", "desc": "+25% ammo from drops", "stat": "ammo", "v": 0.25},
}


static func cv(level: int) -> int:
	return Game.coin_value(level)


static func price_of(rarity: int, level: int) -> int:
	return int(RARITY_PRICE[clampi(rarity, 0, RARITY_PRICE.size() - 1)]) * cv(level)


static func gun_price(g: Gun) -> int:
	return price_of(g.rarity, g.level)


static func sell_price(g: Gun) -> int:
	return maxi(1, roundi(float(gun_price(g)) * SELL_SHARE))


## Подтянуть до уровня lvl: 15% цены пушки того уровня за каждый уровень, но не больше 75%.
static func upgrade_price(g: Gun, lvl: int) -> int:
	var dl := lvl - g.level
	if dl <= 0:
		return 0
	return maxi(1, roundi(float(price_of(g.rarity, lvl)) * clampf(0.15 * float(dl), 0.15, 0.75)))


static func reroll_price(g: Gun) -> int:
	return maxi(1, roundi(float(gun_price(g)) * REROLL_SHARE))


## Поднять редкость можно до эпической и не у легендарок/абсурдных.
static func can_rarity_up(g: Gun) -> bool:
	return g.legendary == "" and g.rarity < GunData.R_EPIC


static func rarity_up_price(g: Gun) -> int:
	return maxi(1, roundi(float(price_of(g.rarity + 1, g.level)) * RARITY_UP_SHARE))


static func stock_reroll_price(level: int, done: int) -> int:
	return roundi(float(REROLL_STOCK_BASE * cv(level)) * (1.0 + 0.5 * float(done)))


## Сколько патронов даёт разбор пушки сам по себе (без патронов в магазине) — как в Player.scrap.
static func scrap_rounds(g: Gun) -> int:
	return ceili(float(GunData.base_mag(g.ammo_type())) * (0.75 + 0.25 * float(g.rarity)))


## Один магазин патронов к пушке: цена патрона = цена продажи / патроны с разбора × AMMO_MARKUP.
## Так разобрать пушку на патроны всегда выгоднее, чем купить их, но не в разы.
static func ammo_price(g: Gun, rounds: int) -> int:
	var per := float(sell_price(g)) / float(maxi(1, scrap_rounds(g)))
	return maxi(1, ceili(per * float(rounds) * AMMO_MARKUP))


static func mystic_price(level: int, bought: int) -> int:
	return roundi(float(MYSTIC_BASE * cv(level)) * (1.0 + 0.5 * float(bought)))


static func mystic_name(id: String) -> String:
	return U.t(str(MYSTIC.get(id, {}).get("name", id)))


static func mystic_desc(id: String) -> String:
	return U.t(str(MYSTIC.get(id, {}).get("desc", "")))


## Товар города перед зоной level: пушки Оружейной, перки Мистика, задания Гильдии.
static func make_town(level: int, rng: RandomNumberGenerator) -> Dictionary:
	var ids: Array = MYSTIC.keys()
	U.shuffle(ids, rng)
	return {"level": level, "stock": make_stock(level, rng), "rerolls": 0,
		"mystic": ids.slice(0, MYSTIC_OFFER), "mystic_done": false, "guild": Quests.make_offers(level, rng)}


## Ассортимент Оружейной: STOCK пушек, одна — не хуже редкой, остальные с «магик файндом» как у чемпиона.
static func make_stock(level: int, rng: RandomNumberGenerator) -> Array:
	var stock: Array = []
	for i in STOCK:
		var g := GunGen.generate(level, rng, 2.0 if i == 0 else 1.0, GunData.R_RARE if i == 0 else 0)
		g.ammo = g.mag_size
		stock.append(g)
	return stock
