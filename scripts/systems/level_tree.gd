class_name LevelTree
extends RefCounted
## Дерево навыков игрока: каждый уровень героя (Game.state.hero_level) даёт POINTS_PER_LEVEL очков, очки тратятся на узлы.
## Прокачка живёт один забег (Game.state.tree: id узла -> уровень) и сбрасывается новым забегом — это не метапрогрессия.
##
## Данные — в data/skill_branches.json (ветки: вкладки меню) и data/skill_tree.json (узлы); моды добавляют и правят
## записи по id так же, как перки пушек (GunData.merge_list). Узел:
##   id        — «W1», «WA2», «V2.1»… (буквы — ветки-корни, цифра — тир, «.N» — порядок ответвления); любая строка;
##   tier      — цена уровня: уровень N узла тира T стоит T × N очков (1, 2, 3… у тира 1; 2, 4, 6… у тира 2);
##   branches  — на каких вкладках узел показан (гибриды висят на каждой из родительских);
##   requires  — узлы, в которых нужен хотя бы 1 уровень, чтобы открыть этот;
##   max       — пиковый уровень (0 — бесконечно);
##   class     — узлы одного класса взаимоисключающи: брать можно только один из них;
##   hero      — узел личный: виден и работает только у этого героя (id из Heroes.LIST);
##   name/desc — текст; в desc «{0}», «{1}» — значения эффектов по порядку;
##   effects   — [{stat, first, step, fmt, per_hero}]: значение на уровне N = first + step × (N − 1);
##               с per_hero: true оно ещё умножается на уровень героя, то есть бонус = уровень навыка × уровень героя × базовый
##               бонус (first = step = базовый бонус) — так растут корни веток вместе с героем;
##               fmt — как писать в тексте: pct (доли → проценты), num, sec.
## Эффекты складываются по stat (stat(имя)); какие stat понимает игра — KNOWN_STATS, кто их читает — перечислено
## у каждого (Player, Projectiles, Enemy.hurt, Main.drop_coins, GunGen.roll_rarity…).

const POINTS_PER_LEVEL := 5

## Что читает игра. Незнакомый stat мода ничего не делает (validate предупредит).
const KNOWN_STATS := {
	"weapon_dmg": "+% к урону пуль героя и турели (Projectiles.fire_gun)",
	"max_hp": "+HP героя (Player.base_max_hp)",
	"skill_dmg": "+% к урону навыка (Player.skill_dmg_mult)",
	"coin_double": "шанс удвоить монеты с дропа; выше 100% — шанс утроить и т. д. (Main.drop_coins)",
	"exec_dmg": "до +% урона по цели в зависимости от потерянного ею здоровья (Enemy.hurt)",
	"free_shot": "шанс не потратить патрон на выстреле, герой и турель (Player._fire, Turret._fire)",
	"rare_luck": "сдвиг шансов редкостей к редким (GunGen.roll_rarity)",
	"accuracy": "+точность: разброс пушки × (1 − accuracy) (LevelTree.spread_mult)",
	"flask_max": "+фляг в запасе (Player.flask_max)",
	"flask_haste": "+скорость бега после фляги (Player.drink)",
	"flask_haste_time": "сколько секунд длится ускорение после фляги",
	"flask_heal": "+% к лечению флягой (Player.drink)",
	"skill_slow": "замедление цели попаданием навыка (Skills.hit)",
	"skill_slow_time": "сколько секунд держится замедление",
	"skill_temp_hp": "временное здоровье = % от урона навыка (Skills.hit)",
	"temp_hp_time": "через сколько секунд временное здоровье пропадает",
	"flask_skill_refund": "доля перезарядки навыка, снимаемая подбором фляги (FlaskDrop)",
	"bounty_coins": "+% монет с цели заказа (Main.on_enemy_killed)",
	"bounty_gun": "больше 0 — зона получает цель заказа, с неё падает пушка",
}
const KNOWN_FMT := ["pct", "num", "sec"]

static var branches: Array = []
static var nodes: Array = []
static var stats: Dictionary = {}
static var _by_id: Dictionary = {}


## Загрузить таблицы (игра + моды). Зовёт Game.load_content.
static func load_data() -> void:
	branches = GunData.merge_list("data/skill_branches.json")
	nodes = GunData.merge_list("data/skill_tree.json")
	_by_id.clear()
	for n in nodes:
		_by_id[str(n["id"])] = n
	recompute()


static func node(id: String) -> Dictionary:
	return _by_id.get(id, {})


static func branch(id: String) -> Dictionary:
	for b in branches:
		if str(b["id"]) == id:
			return b
	return {}


static func branch_name(b: Dictionary) -> String:
	return U.t(str(b.get("name", b.get("id", "?"))))


static func branch_color(b: Dictionary) -> Color:
	var s := str(b.get("color", "ffffff"))
	return Color.html(s) if Color.html_is_valid(s) else Color.WHITE


static func level(id: String) -> int:
	return int(Game.state.tree.get(id, 0))


static func max_level(n: Dictionary) -> int:
	return int(n.get("max", 0))


static func current_hero() -> String:
	if Game.main != null and Game.main.player != null:
		return Game.main.player.hero
	return Game.profile.hero


## Личный узел доступен только своему герою; общий — всем.
static func hero_ok(n: Dictionary, hero: String) -> bool:
	var h := str(n.get("hero", ""))
	return h == "" or h == hero


## Узлы вкладки для героя: по тиру, внутри тира — как в файле.
static func branch_nodes(bid: String, hero: String) -> Array:
	var out: Array = []
	for n in nodes:
		if bid in n.get("branches", []) and hero_ok(n, hero):
			out.append(n)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("tier", 1)) < int(b.get("tier", 1)))
	return out


# --- Очки ---------------------------------------------------------------------------

static func total_points() -> int:
	return POINTS_PER_LEVEL * maxi(0, Game.state.hero_level - 1)


## Цена уровня N узла тира T: T × N, всего до уровня L — T × L(L+1)/2.
static func cost_of(n: Dictionary, lvl: int) -> int:
	return maxi(1, int(n.get("tier", 1))) * lvl


static func spent_points() -> int:
	var s := 0
	for id in Game.state.tree:
		var n := node(str(id))
		if n.is_empty():
			continue
		var l := int(Game.state.tree[id])
		s += maxi(1, int(n.get("tier", 1))) * l * (l + 1) / 2
	return s


static func free_points() -> int:
	return total_points() - spent_points()


## Почему нельзя повысить узел: "" — можно; "none" (нет такого), "hero" (личный узел чужого героя), "max", "req" (нет родителя),
## "class" (занят класс), "pts" (мало очков).
static func block(id: String) -> String:
	var n := node(id)
	if n.is_empty():
		return "none"
	if not hero_ok(n, current_hero()):
		return "hero"
	var lv := level(id)
	var mx := max_level(n)
	if mx > 0 and lv >= mx:
		return "max"
	for r in n.get("requires", []):
		if level(str(r)) <= 0:
			return "req"
	if lv == 0 and class_rival(n) != "":
		return "class"
	if cost_of(n, lv + 1) > free_points():
		return "pts"
	return ""


## Id узла того же класса, в который уже вложены очки ("" — нет).
static func class_rival(n: Dictionary) -> String:
	var cls := str(n.get("class", ""))
	if cls == "":
		return ""
	for o in nodes:
		var oid := str(o["id"])
		if oid != str(n["id"]) and str(o.get("class", "")) == cls and level(oid) > 0:
			return oid
	return ""


## Потратить очки на следующий уровень узла. true — получилось.
static func buy(id: String) -> bool:
	if block(id) != "":
		return false
	Game.state.tree[id] = level(id) + 1
	recompute()
	if Game.main != null and Game.main.player != null:
		Game.main.player.on_tree_changed()
	return true


# --- Эффекты ------------------------------------------------------------------------

## Пересчитать сумму эффектов по stat. Зовётся при покупке, новом забеге, смене героя и перезагрузке данных.
static func recompute() -> void:
	stats.clear()
	var hero := current_hero()
	for id in Game.state.tree:
		var n := node(str(id))
		var lv := int(Game.state.tree[id])
		if n.is_empty() or lv <= 0 or not hero_ok(n, hero):
			continue
		for ef in n.get("effects", []):
			var st := str(ef.get("stat", ""))
			if st != "":
				stats[st] = float(stats.get(st, 0.0)) + effect_value(ef, lv)


static func stat(name: String) -> float:
	return float(stats.get(name, 0.0))


## Значение эффекта на уровне навыка lvl; с per_hero — ещё умноженное на текущий уровень героя.
static func effect_value(ef: Dictionary, lvl: int) -> float:
	var v := float(ef.get("first", 0.0)) + float(ef.get("step", 0.0)) * float(lvl - 1)
	if bool(ef.get("per_hero", false)):
		v *= float(maxi(1, Game.state.hero_level))
	return v


## Растёт ли узел с уровнем героя (есть эффект с per_hero) — для подписи в меню.
static func scales_with_hero(n: Dictionary) -> bool:
	for ef in n.get("effects", []):
		if bool(ef.get("per_hero", false)):
			return true
	return false


## Множитель разброса пушки: точность +10% — разброс −10%.
static func spread_mult() -> float:
	return clampf(1.0 - stat("accuracy"), 0.1, 3.0)


## Во сколько раз умножить монеты дропа: шанс 10% — ×2 с вероятностью 10%; от 100% ×2 гарантированно и т. д.
static func coin_mult() -> int:
	var c := stat("coin_double")
	if c <= 0.0:
		return 1
	var whole := int(c)
	return 1 + whole + (1 if randf() < c - float(whole) else 0)


## Шанс бесплатного выстрела (до 90%: совсем без патронов играть нельзя).
static func free_shot_chance() -> float:
	return minf(0.9, stat("free_shot"))


# --- Текст --------------------------------------------------------------------------

static func fmt_value(ef: Dictionary, lvl: int) -> String:
	var v := absf(effect_value(ef, lvl))
	match str(ef.get("fmt", "num")):
		"pct":
			return "%d%%" % roundi(v * 100.0)
		"sec":
			return U.t("%s s") % U.fmt(v)
	return U.fmt(v)


## Описание узла для уровня lvl: «{0}», «{1}» заменяются значениями эффектов.
static func describe(n: Dictionary, lvl: int) -> String:
	var s := U.t(str(n.get("desc", "")))
	var efs: Array = n.get("effects", [])
	for i in efs.size():
		s = s.replace("{%d}" % i, fmt_value(efs[i], lvl))
	return s


## Имена эффектов, которые читает игра, но не перечислены в KNOWN_STATS, и прочие огрехи данных — для Mods.validate.
static func problems() -> Array:
	var out: Array = []
	var bids: Array = []
	for b in branches:
		bids.append(str(b["id"]))
	for n in nodes:
		var id := str(n["id"])
		if not n.has("name") or not n.has("desc"):
			out.append("skill node '%s' has no name/desc" % id)
		if int(n.get("tier", 1)) < 1:
			out.append("skill node '%s': tier must be 1 or more" % id)
		for b in n.get("branches", []):
			if not (str(b) in bids):
				out.append("skill node '%s': unknown branch '%s'" % [id, str(b)])
		if (n.get("branches", []) as Array).is_empty():
			out.append("skill node '%s' is on no branch and will never be shown" % id)
		for r in n.get("requires", []):
			if not _by_id.has(str(r)):
				out.append("skill node '%s': unknown required node '%s'" % [id, str(r)])
		var h := str(n.get("hero", ""))
		if h != "" and not Heroes.LIST.has(h):
			out.append("skill node '%s': unknown hero '%s'" % [id, h])
		for ef in n.get("effects", []):
			if not (str(ef.get("stat", "")) in KNOWN_STATS):
				out.append("skill node '%s': unknown stat '%s' (known: %s)" % [id, str(ef.get("stat", "")),
					", ".join(PackedStringArray(KNOWN_STATS.keys()))])
			if not (str(ef.get("fmt", "num")) in KNOWN_FMT):
				out.append("skill node '%s': unknown fmt '%s' (known: %s)" % [id, str(ef.get("fmt", "")), ", ".join(PackedStringArray(KNOWN_FMT))])
	return out
