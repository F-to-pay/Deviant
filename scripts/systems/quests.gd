class_name Quests
extends RefCounted
## Задания Гильдии. Берутся в городе (одно за раз), засчитываются в момент выполнения —
## где бы ты ни был — и дают древние монеты и обычные. Действуют до выполнения или отказа,
## новый забег их сбрасывает.
## Задание: {"type", "need", "have", "reward" (древние), "coins"}. Прогресс — progress(type, n) из Main и Player.

const MAX_ACTIVE := 1
const COINS_REWARD := 50    # обычных монет за контракт при стоимости монетки 1
const OFFERS := 3
## text — с %d (сколько нужно), если min/max > 1. reward — древних монет (плюс 2 за каждый этап глубины).
const TYPES := {
	"kills": {"text": "Kill %d enemies", "min": 60, "max": 120, "reward": 4},
	"elites": {"text": "Kill %d champions or leaders", "min": 8, "max": 14, "reward": 6},
	"chests": {"text": "Open %d chests", "min": 4, "max": 7, "reward": 4},
	"zones": {"text": "Clear %d zones", "min": 2, "max": 3, "reward": 4},
	"flawless": {"text": "Clear a zone without taking damage", "min": 1, "max": 1, "reward": 8},
	"boss": {"text": "Kill a stage boss", "min": 1, "max": 1, "reward": 8},
	"coins": {"text": "Collect %d coins", "min": 120, "max": 240, "reward": 4},
}

## Предложения Гильдии в городе перед зоной level: разные виды, не совпадающие с уже взятыми.
static func make_offers(level: int, rng: RandomNumberGenerator) -> Array:
	var kinds: Array = TYPES.keys()
	U.shuffle(kinds, rng)
	var out: Array = []
	for k in kinds:
		if out.size() >= OFFERS:
			break
		if has_type(str(k)):
			continue
		if k == "chests" and not bool(Game.run["chests"]):
			continue   # сундуки включаются только в настраиваемом старте — без них задание невыполнимо
		var t: Dictionary = TYPES[k]
		var need := rng.randi_range(int(t["min"]), int(t["max"]))
		if k == "coins":
			need = int(minf(Balance.money(float(need) * Balance.econ(level)), 1.0e15))
		out.append({"type": str(k), "need": need, "have": 0, "reward": int(t["reward"]) + 2 * ((level - 1) / RunConfig.TOWN_EVERY),
			"coins": Balance.money(float(COINS_REWARD) * Balance.econ(level))})
	return out


static func has_type(t: String) -> bool:
	for q in Game.state.quests:
		if str(q["type"]) == t:
			return true
	return false


static func can_take() -> bool:
	return Game.state.quests.size() < MAX_ACTIVE


static func take(q: Dictionary) -> bool:
	if not can_take() or has_type(str(q["type"])):
		return false
	var c := q.duplicate()
	c["have"] = 0
	Game.state.quests.append(c)
	return true


static func abandon(i: int) -> void:
	if i >= 0 and i < Game.state.quests.size():
		Game.state.quests.remove_at(i)


## Что-то произошло: засчитать задания этого вида. Выполненное — награда сразу.
static func progress(t: String, n: float = 1.0) -> void:
	if Game.state.quests.is_empty() or n <= 0:
		return
	for q in Game.state.quests.duplicate():
		if str(q["type"]) != t:
			continue
		q["have"] = int(minf(float(q["need"]), float(q["have"]) + minf(n, 1.0e15)))
		if int(q["have"]) >= int(q["need"]):
			Game.state.quests.erase(q)
			Game.add_meta(int(q["reward"]))
			Game.state.add_coins(float(q.get("coins", 0.0)))
			Game.say(U.tm("Quest complete: %s — +%d ancient coins, +%d coins", [text(q), str(int(q["reward"])), U.money(float(q.get("coins", 0.0)))]),
				Color(0.6, 1.0, 1.0))
			Sfx.ui("pickup/relic", -3.0)


static func text(q: Dictionary) -> String:
	var t: Dictionary = TYPES.get(str(q["type"]), {})
	var s := U.t(str(t.get("text", "?")))
	return s.replace("%d", U.money(float(q["need"]))) if s.contains("%d") else s


## Строка с прогрессом для HUD и Гильдии.
static func line(q: Dictionary) -> String:
	if int(q["need"]) <= 1:
		return text(q)
	return text(q) + "  %d/%d" % [int(q["have"]), int(q["need"])]
