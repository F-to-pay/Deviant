class_name GunGen
extends RefCounted
## Генератор пушек в духе «чем дальше, тем абсурднее».
## Порядок: редкость -> основа (или гибрид двух основ) -> производитель -> моды
## -> легендарная фишка -> разброс статов -> масштаб по уровню -> имя.
## Все таблицы — в GunData (из data/*.json и модов); эффекты — операции GunOps.

const BURST_MAX := 7    # дольше очередь не бывает (перк «Залповый» кидает 2–7)
const HYBRID_AMMO_RATE := 0.7   # доля основы патронов в скорострельности гибрида (см. _apply_base)
const CURSE_DMG := 0.8   # проклятая пушка бьёт на 20% слабее

## Отладчик: следующая легендарка будет именно этой (id), "" — случайная.
static var force_legendary := ""


static func roll_rarity(level: int, rng: RandomNumberGenerator, bonus: float) -> int:
	if bool(Game.run["chaos"]):
		return rng.randi_range(0, GunData.RARITIES.size() - 1)   # Хаос: все редкости равновероятны
	var b := bonus + minf(float(level) * 0.03, 1.2)
	var weights: Array = []
	for i in GunData.RARITIES.size():
		var w := float(GunData.RARITIES[i].get("weight", 0.0))
		w *= 1.0 + b * float(i) * 0.6
		if i == GunData.R_ABSURD and level < 8 and bonus < 3.0:
			w = 0.0
		weights.append(w)
	return U.weighted(weights, rng)


static func _maker(g: Gun) -> Dictionary:
	return GunData.MAKERS.get(g.maker, {})


## Главная точка входа.
## bonus — «магик файнд» (элитки, сундуки, боссы), min_rarity — нижняя планка.
static func generate(level: int, rng: RandomNumberGenerator, bonus: float = 0.0, min_rarity: int = 0,
		force_rarity: int = -1, force_arch: String = "", force_maker: String = "") -> Gun:
	var g := Gun.new()
	g.level = maxi(1, level)
	if force_rarity >= 0:
		g.rarity = force_rarity
	else:
		g.rarity = maxi(min_rarity, roll_rarity(level, rng, bonus))
	if not GunData.ARCH.has(force_arch):
		force_arch = ""
	if not GunData.MAKERS.has(force_maker):
		force_maker = ""
	g.maker = force_maker if force_maker != "" else _pick_maker(g.rarity, rng)

	var leg: Dictionary = {}
	if g.rarity == GunData.R_LEGENDARY and not GunData.LEGENDARIES.is_empty():
		leg = GunData.LEGENDARIES[rng.randi() % GunData.LEGENDARIES.size()]
		for l in GunData.LEGENDARIES:
			if force_legendary != "" and str(l["id"]) == force_legendary:
				leg = l
		# марка без взрывов (Синергис) не достаётся взрывной легендарке
		var guard_m := 0
		while bool(_maker(g).get("no_explosive", false)) and _leg_explosive(leg) and guard_m < 20:
			g.maker = _pick_maker(g.rarity, rng)
			guard_m += 1
		# легендарка может быть привязана к марке ("maker": "dandy")
		var lm := str(leg.get("maker", ""))
		if lm != "" and GunData.MAKERS.has(lm):
			g.maker = lm
		g.legendary = str(leg["id"])
		g.archetype = str(leg.get("arch", "pistol"))
		g.archetype2 = str(leg.get("arch2", ""))
		g.special = str(leg.get("special", ""))
		if not GunData.ARCH.has(g.archetype):
			g.archetype = _pick_arch(rng, false)
		if g.archetype2 != "" and not GunData.ARCH.has(g.archetype2):
			g.archetype2 = ""
	else:
		if g.rarity == GunData.R_LEGENDARY:
			g.rarity = GunData.R_EPIC   # легендарок нет вовсе (мод всё убрал)
		var no_boom := bool(_maker(g).get("no_explosive", false))
		g.archetype = force_arch if force_arch != "" else _pick_arch(rng, no_boom)
		var hyb := float(GunData.RARITIES[g.rarity].get("hybrid_chance", 0.0))
		if force_arch == "" and rng.randf() < hyb:
			var a2 := _pick_arch(rng, no_boom)
			var guard := 0
			while a2 == g.archetype and guard < 10:
				a2 = _pick_arch(rng, no_boom)
				guard += 1
			if a2 != g.archetype:
				g.archetype2 = a2
		# Гипернова делает из любой основы ракетницу: узор стрельбы свой, снаряд — ракета
		var pa := str(_maker(g).get("projectile_arch", ""))
		if pa != "" and GunData.ARCH.has(pa) and g.archetype != pa and force_arch == "":
			g.archetype2 = pa
	_build(g, rng, leg)
	return g


## Всё после выбора «личности» пушки (редкость, основа, марка, легендарка): статы, перки, разброс, имя.
## keep — перки, которые надо оставить (пересборка в Мастерской), ban — какие не выдавать.
static func _build(g: Gun, rng: RandomNumberGenerator, leg: Dictionary, keep: Array = [], ban: Array = []) -> void:
	_apply_base(g, rng)
	var leg_ops: Array = []
	if not leg.is_empty():
		leg_ops.append(leg)
	var chaos_leg := _apply_maker(g, rng)
	if not chaos_leg.is_empty():
		leg_ops.append(chaos_leg)

	if not leg.is_empty():
		for m in leg.get("perks", []):
			if not (str(m) in g.mods):
				_add_mod(g, str(m), rng)
	var n := int(GunData.RARITIES[g.rarity].get("perks", 0))
	for m in keep:
		var kid := str(m)
		if kid != "slug" and not (kid in g.mods) and not GunData.perk(kid).is_empty():
			_add_mod(g, kid, rng)
			n -= 1
	# Сначала ставим «статовые» моды (они меняют скорострельность и число пуль),
	# моды-эффекты (тег proc) откладываем и проверяем по итоговому числу пуль в секунду.
	var deferred: Array = []
	var tries := 0
	while n > 0 and tries < 40:
		tries += 1
		var id := _roll_mod(g, rng, deferred + ban)
		if id == "":
			break
		if GunData.perk_has_tag(id, "proc"):
			deferred.append(id)
		else:
			_add_mod(g, id, rng)
		n -= 1
	for d in deferred:
		if rng.randf() < proc_keep_chance(g):
			_add_mod(g, str(d), rng)
		else:
			# не прошёл — слот достаётся обычному моду
			var alt := _roll_mod(g, rng, ban, true)
			if alt != "":
				_add_mod(g, alt, rng)

	# фишка легендарки (и перк, доставшийся от Кузни хаоса) — поверх модов
	for l in leg_ops:
		GunOps.run(g, l.get("ops", []), rng)
		Mods.run_entry_script(l, g, rng)
	_randomize(g, rng)
	_finalize(g, rng, leg)


# --- Мастерская --------------------------------------------------------------------

## Перки, которые можно перебросить: без перков марки и легендарки (они вернутся сами) и без «пули».
static func rerollable(g: Gun) -> Array:
	var fixed: Array = ["slug"]
	fixed.append_array(_maker(g).get("perks", []))
	for l in GunData.LEGENDARIES:
		if str(l["id"]) == g.legendary:
			fixed.append_array(l.get("perks", []))
	var out: Array = []
	for m in g.mods:
		if not (str(m) in fixed) and not GunData.perk(str(m)).is_empty():
			out.append(str(m))
	return out


## Пересобрать пушку с той же основой, маркой, легендаркой и уровнем, но редкостью rarity:
## перки сохраняются, кроме drop (он меняется на другой случайный). Разброс статов и имя — новые.
static func rebuild(old: Gun, rarity: int, drop: String, rng: RandomNumberGenerator) -> Gun:
	var g := Gun.new()
	g.level = old.level
	g.rarity = rarity
	g.maker = old.maker
	g.archetype = old.archetype
	g.archetype2 = old.archetype2
	var leg: Dictionary = {}
	for l in GunData.LEGENDARIES:
		if str(l["id"]) == old.legendary:
			leg = l
	if not leg.is_empty():
		g.legendary = old.legendary
		g.special = str(leg.get("special", ""))
	var keep: Array = []
	for m in old.mods:
		if str(m) != drop:
			keep.append(m)
	_build(g, rng, leg, keep, [drop] if drop != "" else [])
	g.ammo = mini(old.ammo, g.mag_size)
	return g


# --- Основа -------------------------------------------------------------------

## Число дробин основы: "pellets_roll": [мин, макс, обычно] — случайно (GunOps.roll_int), иначе pellets.
static func _roll_pellets(a: Dictionary, base: int, rng: RandomNumberGenerator) -> int:
	var spec: Variant = a.get("pellets_roll", null)
	if spec is Array and (spec as Array).size() >= 2:
		return maxi(1, GunOps.roll_int(spec, rng))
	return base


## Основа стреляет навесными минами. kind при загрузке уже превращён в число (GunOps.kind_id).
static func _is_shell(a: Dictionary) -> bool:
	return int(a.get("kind", -1)) == GunData.K_SHELL

static func _apply_base(g: Gun, rng: RandomNumberGenerator = null) -> void:
	var a: Dictionary = GunData.ARCH[g.archetype]
	if g.archetype2 == "":
		g.damage = float(a.get("damage", 10.0))
		g.fire_rate = float(a.get("fire_rate", 2.0))
		g.pellets = int(a.get("pellets", 1))
		g.spread = float(a.get("spread", 3.0))
		g.proj_speed = float(a.get("speed", 900.0))
		g.lifetime = float(a.get("lifetime", 0.75))
		g.mag_size = int(a.get("mag", 10))
		g.reload_time = float(a.get("reload", 1.5))
		g.crit_chance = float(a.get("crit", 0.05))
		g.crit_mult = float(a.get("crit_mult", 2.0))
		g.proj_kind = int(a.get("kind", 0))
		g.proj_size = float(a.get("size", 3.0))
		g.knock = float(a.get("knock", 60.0))
		g.move_mult = float(a.get("move", 1.0))
		g.shake = float(a.get("shake", 1.5))
		g.pierce = int(a.get("pierce", 0))
		g.explode_r = float(a.get("explode", 0.0))
		g.bounces = int(a.get("bounce", 0))
		g.drag = float(a.get("drag", 0.0))
		# случайное число дробин основы (pellets_roll): общий урон залпа тот же
		var n0 := g.pellets
		g.pellets = _roll_pellets(a, g.pellets, rng)
		g.damage *= float(n0) / float(g.pellets)
	else:
		# Гибрид: узор стрельбы от первой основы, снаряд — от второй.
		var b: Dictionary = GunData.ARCH[g.archetype2]
		g.fire_rate = float(a.get("fire_rate", 2.0))
		g.pellets = _roll_pellets(a, int(a.get("pellets", 1)), rng)
		g.spread = float(a.get("spread", 3.0))
		g.mag_size = int(a.get("mag", 10))
		g.reload_time = (float(a.get("reload", 1.5)) + float(b.get("reload", 1.5))) * 0.5
		g.proj_kind = int(b.get("kind", 0))
		g.proj_speed = float(b.get("speed", 900.0))
		g.lifetime = float(b.get("lifetime", 0.75))
		g.proj_size = float(b.get("size", 3.0))
		g.crit_chance = maxf(float(a.get("crit", 0.05)), float(b.get("crit", 0.05)))
		g.crit_mult = maxf(float(a.get("crit_mult", 2.0)), float(b.get("crit_mult", 2.0)))
		g.knock = (float(a.get("knock", 60.0)) + float(b.get("knock", 60.0))) * 0.5
		g.move_mult = minf(float(a.get("move", 1.0)), float(b.get("move", 1.0)))
		g.shake = maxf(float(a.get("shake", 1.5)), float(b.get("shake", 1.5)))
		g.pierce = int(b.get("pierce", 0))
		g.explode_r = float(b.get("explode", 0.0))
		g.bounces = int(b.get("bounce", 0))
		g.drag = float(b.get("drag", 0.0))
		# Урон — от патронов, которые ест гибрид: один патрон бьёт как выстрел той основы, чьи это патроны,
		# и делится между снарядами узора стрельбы. Снайперка с патронами пулемёта бьёт как пулемёт,
		# пулемёт с патронами снайперки — как снайперка, но патронов к нему мало.
		var am: Dictionary = a if str(_maker(g).get("projectile_arch", "")) != "" else b
		g.damage = float(am.get("damage", 10.0)) * float(am.get("pellets", 1)) / float(maxi(1, g.pellets))
		# скорострельность — смесь с уклоном к основе патронов (30% узора, 70% патронов, геометрически):
		# пулемёт на минах — 1.5 выстр/с, а не 14; снайперка на патронах ПП — 5, а не 0.8
		g.fire_rate = pow(float(a.get("fire_rate", 2.0)), 1.0 - HYBRID_AMMO_RATE) * pow(float(am.get("fire_rate", 2.0)), HYBRID_AMMO_RATE)
		# Навесная мина — снаряд с первым приоритетом: если в гибриде есть миномёт (с любой стороны),
		# он стреляет минами вместо пуль, дроби, ракет и гранат. Патроны, урон и узор — по обычным правилам.
		var sh: Dictionary = a if _is_shell(a) else (b if _is_shell(b) else {})
		if not sh.is_empty():
			g.proj_kind = GunData.K_SHELL
			g.proj_speed = float(sh.get("speed", 900.0))
			g.lifetime = float(sh.get("lifetime", 0.75))
			g.proj_size = float(sh.get("size", 3.0))
			g.explode_r = float(sh.get("explode", 0.0))
			g.drag = 0.0
		# пулемёт отдаёт гибриду огромный магазин
		if bool(b.get("big_mag", false)):
			g.mag_size = maxi(g.mag_size, int(b.get("mag", 10)))
	# особенности основ — у гибрида от обеих
	var b2: Dictionary = GunData.ARCH.get(g.archetype2, {}) if g.archetype2 != "" else {}
	g.light = bool(a.get("light", false)) or bool(b2.get("light", false))
	g.no_falloff = bool(a.get("no_falloff", false)) or bool(b2.get("no_falloff", false))
	var rd := maxf(float(a.get("range_dmg", 0.0)), float(b2.get("range_dmg", 0.0)))
	g.range_dmg = clampf(rd, 0.0, 1.0)
	if g.proj_kind == GunData.K_ROCKET:
		g.accel = 2.8
		g.explode_chance = 1.0
	if g.proj_kind == GunData.K_GRENADE:
		g.explode_on_expire = true
		g.explode_chance = 1.0
	if g.proj_kind == GunData.K_SHELL:
		g.explode_on_expire = true
		g.explode_chance = 1.0
		g.pierce = 0
		g.bounces = 0
	# Пулевой дробовик (slug_chance основы): вся дробь в одном снаряде, точно и дальше
	if g.legendary == "" and g.pellets > 1 and randf() < float(a.get("slug_chance", 0.0)):
		g.damage *= float(g.pellets) * 0.85
		g.pellets = 1
		g.spread *= 0.12
		g.lifetime *= 2.0
		g.mods.append("slug")


# --- Производитель ------------------------------------------------------------

static func _arch_explosive(id: String) -> bool:
	return bool(GunData.ARCH.get(id, {}).get("explosive", false))


static func _pick_arch(rng: RandomNumberGenerator, no_boom: bool) -> String:
	var a := _pick_key(GunData.ARCH, rng)
	var guard := 0
	while no_boom and _arch_explosive(a) and guard < 30:
		a = _pick_key(GunData.ARCH, rng)
		guard += 1
	return a


static func _leg_explosive(leg: Dictionary) -> bool:
	if _arch_explosive(str(leg.get("arch", ""))) or _arch_explosive(str(leg.get("arch2", ""))):
		return true
	if str(leg.get("special", "")) in GunData.EXPLOSIVE_SPECIALS:
		return true
	for m in leg.get("perks", []):
		if GunData.perk_has_tag(str(m), "explosive"):
			return true
	return false


static func _pick_maker(rarity: int, rng: RandomNumberGenerator) -> String:
	var keys: Array = []
	var weights: Array = []
	for k in GunData.MAKERS.keys():
		var row: Dictionary = GunData.MAKERS[k]
		if rarity == GunData.R_LEGENDARY and not bool(row.get("legendary", true)):
			continue
		keys.append(k)
		weights.append(float(row.get("weight", 10.0)))
	if keys.is_empty():
		return str(GunData.MAKERS.keys()[0])
	return keys[U.weighted(weights, rng)]


## Фирменный эффект марки. Возвращает легендарку, чей перк достался (Кузня хаоса), или {}.
static func _apply_maker(g: Gun, rng: RandomNumberGenerator) -> Dictionary:
	var mk := _maker(g)
	GunOps.run(g, mk.get("ops", []), rng)
	# перки, которые марка ставит всегда — ДО остальных модов, чтобы моды-эффекты
	# проверялись уже по итоговому числу дробин (Щеголь -> «Дробящий»)
	for p in mk.get("perks", []):
		if not GunData.perk(str(p)).is_empty() and not (str(p) in g.mods):
			_add_mod(g, str(p), rng)
	Mods.run_entry_script(mk, g, rng)
	if bool(mk.get("random_legendary_perk", false)) and not GunData.LEGENDARIES.is_empty():
		var leg: Dictionary = GunData.LEGENDARIES[rng.randi() % GunData.LEGENDARIES.size()]
		g.legend_perk = str(leg.get("name", ""))
		g.special = str(leg.get("special", ""))
		for m in leg.get("perks", []):
			if not (str(m) in g.mods):
				_add_mod(g, str(m), rng)
		return leg
	return {}


# --- Моды ---------------------------------------------------------------------

static func _roll_mod(g: Gun, rng: RandomNumberGenerator, pending: Array = [], no_proc: bool = false) -> String:
	var absurd := g.rarity == GunData.R_ABSURD
	var mk := _maker(g)
	no_proc = no_proc or bool(mk.get("no_proc_perks", false))
	var no_boom := bool(mk.get("no_explosive", false))
	var used: Dictionary = {}
	var taken: Array = g.mods + pending
	for m in taken:
		var grp := str(GunData.perk(str(m)).get("group", ""))
		if grp != "":
			used[grp] = true
	if g.element >= 0:
		used["el"] = true
	var cands: Array = []
	var weights: Array = []
	for md in GunData.MODS:
		var id := str(md["id"])
		var w := float(md.get("weight", 0.0))
		if w <= 0.0 or id in taken:
			continue
		if no_proc and GunData.perk_has_tag(id, "proc"):
			continue
		if no_boom and GunData.perk_has_tag(id, "explosive"):
			continue
		if bool(Game.run["no_heal"]) and GunData.perk_has_tag(id, "heal"):
			continue   # хардкор: без лечения — и без вампиризма
		if int(md.get("min_rarity", 1)) > g.rarity:
			continue
		var grp := str(md.get("group", ""))
		if grp != "" and used.has(grp) and not absurd:
			continue
		if not absurd and not _mod_fits(g, md):
			continue
		cands.append(id)
		weights.append(w)
	if cands.is_empty():
		return ""
	return cands[U.weighted(weights, rng)]


## Шанс удержать мод-эффект = PROC_BULLETS / (скорострельность × пуль за выстрел), макс. 100%.
## Снайперка/пистолет (≤4 пуль/с) — 100%, автомат 7/с — 57%, пулемёт 14/с — 29%,
## двуствольный автомат 30/с — 13%.
const PROC_BULLETS := 4.0


static func proc_keep_chance(g: Gun) -> float:
	var bullets := maxf(0.1, g.fire_rate * float(g.pellets))
	return clampf(PROC_BULLETS / bullets, 0.0, 1.0)


## Отсекаем бессмысленные сочетания (абсурдным можно всё): условия "fits" перка
## и тег no_shell — мины летят над стенами и взрываются в точке, «пулевые» моды им ни к чему.
static func _mod_fits(g: Gun, md: Dictionary) -> bool:
	if g.proj_kind == GunData.K_SHELL and GunData.perk_has_tag(str(md["id"]), "no_shell"):
		return false
	for c in md.get("fits", []):
		if not GunOps.check(g, c):
			return false
	return true


static func _add_mod(g: Gun, id: String, rng: RandomNumberGenerator = null) -> void:
	g.mods.append(id)
	var md := GunData.perk(id)
	if md.is_empty():
		return
	GunOps.run(g, md.get("ops", []), rng)
	Mods.run_entry_script(md, g, rng)


static func _randomize(g: Gun, rng: RandomNumberGenerator) -> void:
	var lo := 0.9
	var hi := 1.1
	g.damage *= rng.randf_range(lo, hi)
	g.fire_rate *= rng.randf_range(lo, hi)
	g.spread *= rng.randf_range(lo, hi)
	g.proj_speed *= rng.randf_range(lo, hi)
	g.reload_time *= rng.randf_range(lo, hi)
	g.mag_size = maxi(1, roundi(float(g.mag_size) * rng.randf_range(lo, hi)))


# --- Финал: уровень, цвета, имя ----------------------------------------------

static func _finalize(g: Gun, rng: RandomNumberGenerator, leg: Dictionary) -> void:
	var rar: Dictionary = GunData.RARITIES[g.rarity]
	var mk := _maker(g)
	if bool(Game.run["no_heal"]):
		g.leech = 0.0   # и у легендарок
	if g.element == U.EL_CURSE:
		g.damage *= CURSE_DMG   # цена проклятия — откуда бы оно ни взялось (мод, Эррозия)
	var lvl_mult: float = Game.gun_dmg_mult(g.level)
	g.damage *= lvl_mult * float(rar.get("damage_mult", 1.0))
	g.fire_rate = clampf(g.fire_rate, 0.25, 30.0)
	g.spread = clampf(g.spread, 0.0, 110.0)
	g.pellets = clampi(g.pellets, 1, 60)
	g.ammo_per_shot = maxi(1, g.ammo_per_shot)
	# очередь не длиннее 7 и не растягивает паузу между очередями дольше ~2.5 с (очередь из n при скорострельности f — n/f)
	g.burst = clampi(g.burst, 1, mini(BURST_MAX, maxi(2, floori(g.fire_rate * 2.5))))
	# магазин кратен расходу очереди = выстрелов в очереди × патронов на выстрел, чтобы очередь не обрывалась
	# (двуствольная снайперка Бога силы: x6 -> 6, 12...; очередь по 3 с x2 -> 6, 12...)
	var unit := g.ammo_per_shot * g.burst
	g.mag_size = maxi(unit, ceili(float(g.mag_size) / float(unit)) * unit)
	g.reload_time = clampf(g.reload_time, 0.35, 6.0)
	g.crit_chance = clampf(g.crit_chance, 0.0, 0.75)
	g.elem_chance = clampf(g.elem_chance, 0.0, 1.0)
	g.proj_speed = clampf(g.proj_speed, 120.0, 3200.0)
	g.lifetime = clampf(g.lifetime, 0.2, 4.0)
	# нижняя планка точности легендарки: точность = 100 - разброс * 2.2
	var min_acc := float(leg.get("min_accuracy", 0.0))
	if min_acc > 0.0:
		g.spread = minf(g.spread, (100.0 - min_acc) / 2.2)
	if g.element >= 0 and g.elem_chance <= 0.0:
		g.elem_chance = 0.35
	if bool(mk.get("no_explosive", false)):
		g.explode_r = 0.0
		g.cluster_n = 0
		if g.proj_kind == GunData.K_ROCKET or g.proj_kind == GunData.K_GRENADE:
			g.proj_kind = GunData.K_BULLET
			g.explode_on_expire = false
			g.accel = 0.0
			g.drag = 0.0
		if g.special in GunData.EXPLOSIVE_SPECIALS:
			g.special = ""
	g.explode_chance = clampf(g.explode_chance, 0.0, 1.0) if g.explode_r > 0.0 else 0.0

	g.body_color = mk.get("color", Color.GRAY)
	g.dark_color = mk.get("dark", Color.DIM_GRAY)
	if g.element >= 0:
		g.proj_color = U.el_color(g.element)
	else:
		g.proj_color = mk.get("projectile_color", Color.WHITE)

	_build_vis(g, rng)
	_make_name(g, rng, leg)
	if not leg.is_empty():
		g.flavor = str(leg.get("flavor", ""))
	elif g.rarity == GunData.R_ABSURD:
		g.flavor = str(GunData.ABSURD_FLAVOR[rng.randi() % GunData.ABSURD_FLAVOR.size()])
	else:
		g.flavor = str(mk.get("motto", ""))
	g.ammo = g.mag_size


static func _build_vis(g: Gun, rng: RandomNumberGenerator) -> void:
	var a: Dictionary = GunData.ARCH[g.archetype].get("icon", {})
	var b: Dictionary = a
	if g.archetype2 != "":
		b = GunData.ARCH[g.archetype2].get("icon", {})
	var v: Dictionary = {}
	var body := float(a.get("body", 30.0)) * rng.randf_range(0.9, 1.15)
	var barrel := float(b.get("barrel", 16.0)) * rng.randf_range(0.85, 1.2)
	if "long" in g.mods:
		barrel *= 1.4
	if "sawn" in g.mods:
		barrel *= 0.55
	var stock := float(a.get("stock", 0.0))
	# Число стволов на иконке: «Двуствольный» — ровно 2 (иначе его дробины, удвоенные им же, дорисовывали бы третий);
	# дробовик с разбросом или кучей дробин — тоже 2; три — только у обычного (не двуствольного) с 30+ дробинами.
	var nb := 1
	if "double" in g.mods or "scatter" in g.mods or g.pellets >= 10:
		nb = 2
	if g.pellets >= 30 and not ("double" in g.mods):
		nb = 3
	v["body"] = body
	v["bh"] = float(a.get("bh", 10.0)) * rng.randf_range(0.9, 1.1)
	v["barrel"] = barrel
	v["bt"] = float(b.get("bt", 4.0))
	v["stock"] = stock
	v["nb"] = mini(nb, 3)
	v["drum"] = g.mag_size >= 50 or "drum" in g.mods
	v["scope"] = bool(a.get("scope", false)) or bool(b.get("scope", false)) or "precise" in g.mods
	v["tube"] = g.proj_kind == GunData.K_ROCKET
	v["gl"] = g.proj_kind == GunData.K_GRENADE
	v["orb"] = g.proj_kind == GunData.K_ORB
	v["cyl"] = bool(a.get("cylinder", false))
	v["mortar"] = bool(a.get("mortar", false)) or bool(b.get("mortar", false))
	v["fins"] = rng.randi_range(0, 2)
	var x0 := -10.0 - stock
	var x1 := -10.0 + body + barrel
	v["cx"] = (x0 + x1) * 0.5
	v["len"] = x1 - x0
	g.vis = v


static func _primary_mod(g: Gun) -> String:
	var best := ""
	var best_w := 1e9
	for m in g.mods:
		var d := GunData.perk(str(m))
		if d.is_empty():
			continue
		var w := float(d.get("weight", 1.0))
		if str(d.get("group", "")) == "kind":
			w -= 100.0  # «Гранатный»/«Реактивный» важнее всего для имени
		if w < best_w:
			best_w = w
			best = str(m)
	return best


## Название перка-прилагательного в нужном роде ("m"/"f"/"n").
static func _adj(id: String, gen: String) -> String:
	var d := GunData.perk(id)
	if d.is_empty():
		return ""
	return I18n.word(str(d.get("name", id)), gen)


## Запоминает «детали» имени; сама строка собирается в build_name() на текущем языке.
static func _make_name(g: Gun, rng: RandomNumberGenerator, leg: Dictionary) -> void:
	var num := rng.randi_range(2, 99)
	var nick := str(GunData.NICKNAMES[rng.randi() % GunData.NICKNAMES.size()])
	var parts := {"kind": "plain", "num": num, "nick": nick, "adj": "", "adj2": ""}
	if not leg.is_empty():
		parts = {"kind": "leg", "leg": str(leg.get("name", "?"))}
	elif not g.mods.is_empty():
		var prim := _primary_mod(g)
		if prim != "":
			parts["adj"] = prim
			parts["kind"] = "adj"
			if g.rarity == GunData.R_ABSURD:
				parts["kind"] = "nick"
				for m in g.mods:
					if str(m) != prim and not GunData.perk(str(m)).is_empty():
						parts["adj2"] = str(m)
						break
			elif g.rarity == GunData.R_EPIC:
				parts["kind"] = "nick"
	g.name_parts = parts


## Имя пушки на текущем языке — по шаблонам языка (I18n.tpl):
##  en: "Hypernova-38 Armored Grenade Launcher-Rocket Launcher", "Mean Sniper Rifle "Mortgage""
##  ru: «Бронированный гранатомёт-ракетница Гипернова-38», «Злая снайперка «Ипотека»»
static func build_name(g: Gun) -> String:
	var p := g.name_parts
	var kind := str(p.get("kind", "plain"))
	if kind == "leg":
		return I18n.tpl("gun_legendary", {"name": U.t(str(p["leg"]))})
	var gen := g.gender()
	var a2 := str(p.get("adj2", ""))
	var adj2 := _adj(a2, gen)
	var vars := {
		"type": g.type_name(),
		"type_l": g.type_name_lower(),
		"maker": g.maker_name(),
		"num": str(p.get("num", 0)),
		"nick": U.t(str(p.get("nick", ""))),
		"adj": _adj(str(p.get("adj", "")), gen),
		"adj2": adj2,
		"adj2_l": adj2.to_lower(),
	}
	match kind:
		"adj":
			return I18n.tpl("gun_adj", vars)
		"nick":
			return I18n.tpl("gun_nick2" if a2 != "" else "gun_nick", vars)
	return I18n.tpl("gun_plain", vars)


static func _pick_key(table: Dictionary, rng: RandomNumberGenerator) -> String:
	var keys: Array = table.keys()
	var weights: Array = []
	for k in keys:
		var row: Dictionary = table[k]
		weights.append(float(row.get("weight", 1.0)))
	return keys[U.weighted(weights, rng)]
