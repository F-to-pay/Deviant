class_name Shops
extends RefCounted
## Цены и товар городских лавок (экраны — в Menu: _build_shop, _build_mystic, _build_workshop).
##  Оружейная — купить пушку из ассортимента / продать свою, обновить ассортимент, купить магазин патронов.
##  Мистик — один перк навыка героя за город (1 из 3, Heroes.PERKS), на забег; каждый следующий дороже.
##  Мастерская — перебросить перк, поднять редкость (подтягивать уровень нельзя — пушки должны устаревать).
##  Лекарь — вылечить до полного, наполнить фляги (в хардкоре не работает).
## Все цены — в обычных монетах и растут с этапом так же, как доход (Game.econ: ×1.2 за этап).
## Ассортимент города создаётся при входе в него (Main.load_town -> make_town) и живёт до выхода.

## Цена пушки по редкости (обычная ... абсурдная) при стоимости монетки 1.
const RARITY_PRICE := [15, 30, 60, 120, 300, 500]
const SELL_SHARE := 0.25        # продажа — четверть цены
const STOCK := 8                # пушек в Оружейной
const REROLL_STOCK_BASE := 10   # обновить ассортимент; каждое следующее обновление в этом городе — +50%
const AMMO_MARKUP := 1.5        # патроны дороже, чем их «стоимость» при разборе (см. ammo_price)
const HEAL_FULL := 40           # Лекарь: вылечить с нуля до полного (меньше — пропорционально)
const FLASK_PRICE := 20         # Лекарь: наполнить одну флягу
const MYSTIC_OFFER := 3         # перков на выбор у Мистика
const MYSTIC_BASE := 40         # первый перк; каждый следующий за забег — +50%
const REROLL_SHARE := 0.35      # переброс перка — доля цены пушки
const RARITY_UP_SHARE := 0.7    # повышение редкости — доля цены пушки новой редкости

static func cv(level: int) -> float:
	return Game.econ(level)


static func price_of(rarity: int, level: int) -> int:
	return roundi(float(RARITY_PRICE[clampi(rarity, 0, RARITY_PRICE.size() - 1)]) * cv(level))


static func gun_price(g: Gun) -> int:
	return price_of(g.rarity, g.level)


static func sell_price(g: Gun) -> int:
	return maxi(1, roundi(float(gun_price(g)) * SELL_SHARE))


static func reroll_price(g: Gun) -> int:
	return maxi(1, roundi(float(gun_price(g)) * REROLL_SHARE))


## Поднять редкость можно до эпической и не у легендарок/абсурдных.
static func can_rarity_up(g: Gun) -> bool:
	return g.legendary == "" and g.rarity < GunData.R_EPIC


static func rarity_up_price(g: Gun) -> int:
	return maxi(1, roundi(float(price_of(g.rarity + 1, g.level)) * RARITY_UP_SHARE))


static func stock_reroll_price(level: int, done: int) -> int:
	return roundi(float(REROLL_STOCK_BASE) * cv(level) * (1.0 + 0.5 * float(done)))


## Сколько патронов даёт разбор пушки сам по себе (без патронов в магазине) — как в Player.scrap.
static func scrap_rounds(g: Gun) -> int:
	return ceili(float(GunData.base_mag(g.ammo_type())) * (0.75 + 0.25 * float(g.rarity)))


## Один магазин патронов к пушке: цена патрона = цена продажи / патроны с разбора × AMMO_MARKUP.
## Так разобрать пушку на патроны всегда выгоднее, чем купить их, но не в разы.
static func ammo_price(g: Gun, rounds: int) -> int:
	var per := float(sell_price(g)) / float(maxi(1, scrap_rounds(g)))
	return maxi(1, ceili(per * float(rounds) * AMMO_MARKUP))


## Вылечить до полного: цена пропорциональна недостающему здоровью.
static func heal_price(level: int, missing_frac: float) -> int:
	if missing_frac <= 0.0:
		return 0
	return maxi(1, ceili(float(HEAL_FULL) * cv(level) * missing_frac))


static func flask_price(level: int) -> int:
	return roundi(float(FLASK_PRICE) * cv(level))


static func mystic_price(level: int, bought: int) -> int:
	return roundi(float(MYSTIC_BASE) * cv(level) * (1.0 + 0.5 * float(bought)))


## Товар города перед зоной level: пушки Оружейной, перки Мистика, задания Гильдии.
## Перки Мистика подбираются под героя при первом заходе к нему (Menu._refresh_mystic) —
## в стартовом городе героя ещё могут сменить.
static func make_town(level: int, rng: RandomNumberGenerator) -> Dictionary:
	return {"level": level, "stock": make_stock(level, rng), "rerolls": 0,
		"mystic": [], "mystic_for": "", "mystic_done": false, "guild": Quests.make_offers(level, rng)}


## Ассортимент Оружейной: STOCK пушек, одна — не хуже редкой, остальные с «магик файндом» как у чемпиона.
static func make_stock(level: int, rng: RandomNumberGenerator) -> Array:
	var stock: Array = []
	for i in STOCK:
		var g := GunGen.generate(level, rng, 2.0 if i == 0 else 1.0, GunData.R_RARE if i == 0 else 0)
		g.ammo = g.mag_size
		stock.append(g)
	return stock
