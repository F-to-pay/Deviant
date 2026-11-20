class_name Profile
extends RefCounted
## Профиль игрока — то, что переживает забег и сохраняется в `user://deviant.cfg`: древние монеты, герои, рекорды
## и последний «настраиваемый старт». Логики игры здесь нет, только данные и правила их изменения.
## Любое изменение, которое надо сохранить, сообщает сигналом `changed` (`Game` подписан и пишет файл).

signal changed

var meta_coins: int = 0                       # древние монеты — копятся между забегами
var hero: String = Heroes.DEFAULT             # выбранный герой
var heroes_open: Array = [Heroes.DEFAULT]     # открытые герои
var best_zone: int = 0
var best_kills: int = 0
var best_rating: int = 0
var custom: Dictionary = RunConfig.DEFAULTS.duplicate()   # последний «настраиваемый старт» (правится меню прямо в словаре)


## Выбранный герой должен существовать и быть открытым, иначе — герой по умолчанию (зовётся после загрузки данных и модов).
func validate_heroes() -> void:
	if not Heroes.LIST.has(hero) or not hero_unlocked(hero):
		hero = Heroes.DEFAULT


## Герой открыт (бесплатный — всегда).
func hero_unlocked(id: String) -> bool:
	return id in heroes_open or int(Heroes.get_hero(id).get("price", 0)) <= 0


## Открыть героя за древние монеты. free — без оплаты (команда отладчика). true — открыт.
func unlock_hero(id: String, free: bool = false) -> bool:
	if not Heroes.LIST.has(id) or hero_unlocked(id):
		return Heroes.LIST.has(id)
	var price := int(Heroes.LIST[id]["price"])
	if not free:
		if meta_coins < price:
			return false
		meta_coins -= price
	heroes_open.append(id)
	changed.emit()
	return true


## Выбрать героя (только открытого). Текущий забег подхватывает `Game.select_hero` — см. Player.set_hero.
func select_hero(id: String) -> bool:
	if not hero_unlocked(id):
		return false
	hero = id
	changed.emit()
	return true


## Древние монеты сохраняются сразу при подборе — их не теряешь ни при смерти, ни при вылете.
## Счёт «за этот забег» (RunState.meta_run) ведёт `Game.add_meta`.
func add_meta(n: int) -> void:
	meta_coins = maxi(0, meta_coins + n)
	changed.emit()


## Занести итог забега. Рейтинг пишется для любого забега, рекорды по зонам и убийствам — только при обычной
## сложности (counts). Возвращает {"rating_record": новый рекорд рейтинга, "zone_record": новый рекорд по зонам}.
func record_run(rating: int, zone: int, kills: int, counts: bool) -> Dictionary:
	var res := {"rating_record": rating > best_rating, "zone_record": false}
	best_rating = maxi(best_rating, rating)
	if counts:
		res["zone_record"] = zone > best_zone
		best_zone = maxi(best_zone, zone)
		best_kills = maxi(best_kills, kills)
	changed.emit()
	return res


## Прочитать профиль из ConfigFile (секции records, meta, custom).
func read(cf: ConfigFile) -> void:
	best_zone = int(cf.get_value("records", "best_zone", 0))
	best_kills = int(cf.get_value("records", "best_kills", 0))
	best_rating = int(cf.get_value("records", "best_rating", 0))
	meta_coins = int(cf.get_value("meta", "coins", 0))
	hero = str(cf.get_value("meta", "hero", Heroes.DEFAULT)).replace("cultist", "sheriff")   # старое имя героя
	# герои читаются до загрузки данных (моды ещё не просканированы): открытые id храним как есть, даже героев выключенного мода;
	# выбранного героя проверяет validate_heroes() после загрузки контента
	for h in str(cf.get_value("meta", "heroes", "")).replace("cultist", "sheriff").split(",", false):
		if not (h in heroes_open):
			heroes_open.append(h)
	for k in RunConfig.DEFAULTS:
		custom[k] = U.typed(RunConfig.DEFAULTS[k], cf.get_value("custom", str(k), RunConfig.DEFAULTS[k]))


## Рекорды и мета (секции records, meta).
func write_core(cf: ConfigFile) -> void:
	cf.set_value("records", "best_zone", best_zone)
	cf.set_value("records", "best_kills", best_kills)
	cf.set_value("records", "best_rating", best_rating)
	cf.set_value("meta", "coins", meta_coins)
	cf.set_value("meta", "hero", hero)
	cf.set_value("meta", "heroes", ",".join(PackedStringArray(heroes_open)))


## Последний «настраиваемый старт» (секция custom).
func write_custom(cf: ConfigFile) -> void:
	for k in custom:
		cf.set_value("custom", str(k), custom[k])
