class_name GunGen
extends RefCounted
## Генератор пушек в духе «чем дальше, тем абсурднее».
## Порядок: редкость -> основа (или гибрид двух основ) -> производитель -> моды
## -> легендарная фишка -> разброс статов -> масштаб по уровню -> имя.

const ABSURD_FLAVOR := [
	"Инженеры до сих пор в шоке.",
	"Собрано из того, что было.",
	"Не спрашивай, как это работает.",
	"Сертификат соответствия: потерян.",
	"Работает на чистом безумии.",
	"Техника безопасности рыдает в углу.",
]


static func roll_rarity(level: int, rng: RandomNumberGenerator, bonus: float) -> int:
	if bool(Game.run["chaos"]):
		return rng.randi_range(0, GunData.RARITIES.size() - 1)   # Хаос: все редкости равновероятны
	var b := bonus + minf(float(level) * 0.03, 1.2)
	var weights: Array = []
	for i in GunData.RARITIES.size():
		var w: float = GunData.RARITIES[i]["w"]
		w *= 1.0 + b * float(i) * 0.6
		if i == GunData.R_ABSURD and level < 8 and bonus < 3.0:
			w = 0.0
		weights.append(w)
	return U.weighted(weights, rng)


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
	g.maker = force_maker if force_maker != "" else _pick_maker(g.rarity, rng)

	var leg: Dictionary = {}
	if g.rarity == GunData.R_LEGENDARY:
		leg = GunData.LEGENDARIES[rng.randi() % GunData.LEGENDARIES.size()]
		# Синергис не делает ничего взрывного — взрывной легендарке достаётся другая марка
		var guard_m := 0
		while g.maker == "synergis" and _leg_explosive(leg) and guard_m < 20:
			g.maker = _pick_maker(g.rarity, rng)
			guard_m += 1
		g.legendary = leg["id"]
		g.archetype = leg["a"]
		g.archetype2 = leg["a2"]
		g.special = leg["sp"]
	else:
		var no_boom := g.maker == "synergis"
		g.archetype = force_arch if force_arch != "" else _pick_arch(rng, no_boom)
		if force_arch == "" and rng.randf() < float(GunData.HYBRID_CHANCE[g.rarity]):
			var a2 := _pick_arch(rng, no_boom)
			var guard := 0
			while a2 == g.archetype and guard < 10:
				a2 = _pick_arch(rng, no_boom)
				guard += 1
			if a2 != g.archetype:
				g.archetype2 = a2
		# Гипернова делает из любой основы ракетницу: узор стрельбы свой, снаряд — ракета
		if g.maker == "hypernova" and g.archetype != "rocket" and force_arch == "":
			g.archetype2 = "rocket"

	_apply_base(g)
	_apply_maker(g, rng)

	if not leg.is_empty():
		for m in leg["mods"]:
			if not (str(m) in g.mods):
				_add_mod(g, str(m))
	var n: int = GunData.RARITIES[g.rarity]["mods"]
	# Сначала ставим «статовые» моды (они меняют скорострельность и число пуль),
	# моды-эффекты откладываем и проверяем по итоговому числу пуль в секунду.
	var deferred: Array = []
	var tries := 0
	while n > 0 and tries < 40:
		tries += 1
		var id := _roll_mod(g, rng, deferred)
		if id == "":
			break
		if id in PROC_MODS:
			deferred.append(id)
		else:
			_add_mod(g, id)
		n -= 1
	for d in deferred:
		if rng.randf() < proc_keep_chance(g):
			_add_mod(g, str(d))
		else:
			# не прошёл — слот достаётся обычному моду
			var alt := _roll_mod(g, rng, [], true)
			if alt != "":
				_add_mod(g, alt)


	_apply_special(g)
	_randomize(g, rng)
	_finalize(g, rng, leg)
	return g


# --- Основа -------------------------------------------------------------------

static func _apply_base(g: Gun) -> void:
	var a: Dictionary = GunData.ARCH[g.archetype]
	if g.archetype2 == "":
		g.damage = a["dmg"]
		g.fire_rate = a["rate"]
		g.pellets = a["pel"]
		g.spread = a["spr"]
		g.proj_speed = a["spd"]
		g.lifetime = a["life"]
		g.mag_size = a["mag"]
		g.reload_time = a["rel"]
		g.crit_chance = a["crit"]
		g.crit_mult = a["critm"]
		g.proj_kind = a["kind"]
		g.proj_size = a["size"]
		g.knock = a["knock"]
		g.move_mult = a["move"]
		g.shake = a["shake"]
		g.pierce = int(a.get("pierce", 0))
		g.explode_r = float(a.get("explode", 0.0))
		g.bounces = int(a.get("bounce", 0))
		g.drag = float(a.get("drag", 0.0))
	else:
		# Гибрид: узор стрельбы от первой основы, снаряд — от второй.
		var b: Dictionary = GunData.ARCH[g.archetype2]
		g.fire_rate = a["rate"]
		g.pellets = a["pel"]
		g.spread = a["spr"]
		g.mag_size = a["mag"]
		g.reload_time = (float(a["rel"]) + float(b["rel"])) * 0.5
		g.proj_kind = b["kind"]
		g.proj_speed = b["spd"]
		g.lifetime = b["life"]
		g.proj_size = b["size"]
		g.crit_chance = maxf(float(a["crit"]), float(b["crit"]))
		g.crit_mult = maxf(float(a["critm"]), float(b["critm"]))
		g.knock = (float(a["knock"]) + float(b["knock"])) * 0.5
		g.move_mult = minf(float(a["move"]), float(b["move"]))
		g.shake = maxf(float(a["shake"]), float(b["shake"]))
		g.pierce = int(b.get("pierce", 0))
		g.explode_r = float(b.get("explode", 0.0))
		g.bounces = int(b.get("bounce", 0))
		g.drag = float(b.get("drag", 0.0))
		# Нормируем урон, чтобы гибрид не был ни имбой, ни мусором.
		var dps_a := float(a["dmg"]) * float(a["pel"]) * float(a["rate"])
		var dps_b := float(b["dmg"]) * float(b["pel"]) * float(b["rate"])
		var target := (dps_a + dps_b) * 0.5 * 1.1
		g.damage = target / (float(g.pellets) * g.fire_rate)
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
	# Пулевой дробовик: вся дробь в одном снаряде, точно и дальше
	if g.archetype == "shotgun" and g.legendary == "" and g.pellets > 1 and randf() < GunData.SLUG_CHANCE:
		g.damage *= float(g.pellets) * 0.85
		g.pellets = 1
		g.spread *= 0.12
		g.lifetime *= 2.0
		g.mods.append("slug")


# --- Производитель ------------------------------------------------------------

const CURSE_DMG := 0.8   # проклятая пушка бьёт на 20% слабее
const EXPLOSIVE_MODS := ["blast", "cluster", "nuke", "grenade", "rocket"]
const EXPLOSIVE_ARCH := ["rocket", "launcher", "mortar"]


static func _pick_arch(rng: RandomNumberGenerator, no_boom: bool) -> String:
	var a := _pick_key(GunData.ARCH, rng)
	var guard := 0
	while no_boom and a in EXPLOSIVE_ARCH and guard < 30:
		a = _pick_key(GunData.ARCH, rng)
		guard += 1
	return a


static func _leg_explosive(leg: Dictionary) -> bool:
	if str(leg["a"]) in EXPLOSIVE_ARCH or str(leg["a2"]) in EXPLOSIVE_ARCH or str(leg["sp"]) == "nuke10":
		return true
	for m in leg["mods"]:
		if str(m) in EXPLOSIVE_MODS:
			return true
	return false


static func _pick_maker(rarity: int, rng: RandomNumberGenerator) -> String:
	var keys: Array = []
	var weights: Array = []
	for k in GunData.MAKERS.keys():
		var row: Dictionary = GunData.MAKERS[k]
		if rarity == GunData.R_LEGENDARY and not bool(row["leg"]):
			continue
		keys.append(k)
		weights.append(float(row["w"]))
	return keys[U.weighted(weights, rng)]


static func _apply_maker(g: Gun, rng: RandomNumberGenerator) -> void:
	match g.maker:
		"synergis":
			g.damage *= 0.6
			g.free_ammo = true
			g.proc_mult *= 0.5
		"hypernova":
			# ракета уже назначена основой (archetype2 = rocket), тратит ракетные патроны
			g.damage *= 2.0
			g.fire_rate *= 0.5
			g.ammo_per_shot *= 2
		"shabash":
			g.reload_time *= 0.3
			g.damage *= 0.9
		"chaos":
			g.damage *= 0.6
			var leg: Dictionary = GunData.LEGENDARIES[rng.randi() % GunData.LEGENDARIES.size()]
			g.legend_perk = leg["n"]
			g.special = leg["sp"]
			for m in leg["mods"]:
				if not (str(m) in g.mods):
					_add_mod(g, str(m))
		"erosion":
			if g.element < 0:
				g.element = rng.randi_range(0, U.EL_CURSE)
			g.elem_chance += 0.35
			g.elem_mult = 2.0
			g.damage *= 0.75
		"atlant":
			g.damage *= 1.2
		"liven":
			g.fire_rate *= 1.6
			g.damage *= 0.8
		"dandy":
			# Дробь — ДО остальных модов, чтобы моды-эффекты проверялись уже по числу дробин
			_add_mod(g, "scatter")
			g.damage *= 0.85
		"noname":
			pass  # без фирменного перка
		"godforce":
			g.damage *= 3.0
			g.fire_rate *= 0.3
			g.ammo_per_shot *= 3
			g.crit_mult *= 1.5
		"abordage":
			g.mag_size = maxi(1, roundi(float(g.mag_size) * 0.3))
			g.proj_speed *= 3.0
			if g.proj_kind != GunData.K_GRENADE:
				g.lifetime /= 3.0   # дальность та же: пуля быстрее, но не дальше
			g.damage *= 1.4
			g.knock *= 2.0


# --- Моды ---------------------------------------------------------------------

static func _mod_def(id: String) -> Dictionary:
	for md in GunData.MODS:
		if md["id"] == id:
			return md
	return {}


static func _roll_mod(g: Gun, rng: RandomNumberGenerator, pending: Array = [], no_proc: bool = false) -> String:
	var absurd := g.rarity == GunData.R_ABSURD
	var used: Dictionary = {}
	var taken: Array = g.mods + pending
	for m in taken:
		var d := _mod_def(str(m))
		if not d.is_empty() and str(d["grp"]) != "":
			used[d["grp"]] = true
	if g.element >= 0:
		used["el"] = true
	var cands: Array = []
	var weights: Array = []
	for md in GunData.MODS:
		var id: String = md["id"]
		if id in taken:
			continue
		if (no_proc or g.maker == "atlant") and id in PROC_MODS:
			continue
		if g.maker == "synergis" and id in EXPLOSIVE_MODS:
			continue
		if id == "vamp" and bool(Game.run["no_heal"]):
			continue   # хардкор: без лечения — и без вампиризма
		if int(md["min"]) > g.rarity:
			continue
		var grp: String = md["grp"]
		if grp != "" and used.has(grp) and not absurd:
			continue
		if not absurd and not _mod_fits(g, id):
			continue
		cands.append(id)
		weights.append(md["w"])
	if cands.is_empty():
		return ""
	return cands[U.weighted(weights, rng)]


## Моды-эффекты: их шанс выпасть падает у пушек, выпускающих много пуль.
const PROC_MODS := ["homing", "split", "fractal", "chain", "cluster", "gravity", "seeder", "ricochet",
	"pierce", "vamp", "blast", "boomerang", "wave", "quantum", "nuke", "fire", "shock", "acid", "cryo", "curse"]


## Шанс удержать мод-эффект = PROC_BULLETS / (скорострельность × пуль за выстрел), макс. 100%.
## Снайперка/пистолет (≤4 пуль/с) — 100%, автомат 7/с — 57%, пулемёт 14/с — 29%,
## двуствольный автомат 30/с — 13%.
const PROC_BULLETS := 4.0


static func proc_keep_chance(g: Gun) -> float:
	var bullets := maxf(0.1, g.fire_rate * float(g.pellets))
	return clampf(PROC_BULLETS / bullets, 0.0, 1.0)


## Отсекаем совсем бессмысленные сочетания (абсурдным можно всё).
## Мины летят над стенами и взрываются в точке — им бессмысленны «пулевые» моды.
const SHELL_USELESS := ["rocket", "grenade", "big", "homing", "ricochet", "pierce", "boomerang", "wave",
	"quantum", "seeder", "split", "fractal", "long", "sawn"]


static func _mod_fits(g: Gun, id: String) -> bool:
	if g.proj_kind == GunData.K_SHELL and id in SHELL_USELESS:
		return false
	match id:
		"scatter":
			return g.pellets < 12
		"precise":
			return g.spread > 1.0
		"burst":
			return g.fire_rate >= 1.2
		"drum":
			return g.mag_size < 80
		"rocket":
			return g.proj_kind != GunData.K_ROCKET
		"grenade":
			return g.proj_kind != GunData.K_GRENADE
		"big":
			return g.proj_kind != GunData.K_ORB
		"homing":
			return g.homing < 2.0
	return true


static func _add_mod(g: Gun, id: String) -> void:
	g.mods.append(id)
	match id:
		"heavy":
			g.damage *= 1.35
			g.fire_rate *= 0.85
		"rapid":
			g.fire_rate *= 1.4
			g.damage *= 0.88
		"precise":
			g.spread *= 0.35
			g.proj_speed *= 1.2
			g.crit_chance += 0.03
		"drum":
			g.mag_size = int(g.mag_size * 1.9) + 1
			g.reload_time *= 1.15
		"quick":
			g.reload_time *= 0.6
		"mean":
			g.crit_chance += 0.1
			g.crit_mult += 0.75
		"long":
			g.lifetime *= 1.3
			g.proj_speed *= 1.3
			g.damage *= 1.1
		"sawn":
			var old_p := g.pellets
			g.pellets += 2
			g.damage *= float(old_p) * 1.15 / float(g.pellets)
			g.spread = g.spread * 1.4 + 6.0
			g.lifetime *= 0.7
		"double":
			g.pellets *= 2
			g.ammo_per_shot *= 2
			g.spread = g.spread * 1.3 + 2.0
			g.mag_size = maxi(g.mag_size, 2)
		"scatter":
			var old_s := g.pellets
			g.pellets += 5
			g.damage *= float(old_s) * 1.3 / float(g.pellets)
			g.spread += 22.0
			g.lifetime *= 0.85
		"burst":
			g.burst = 3
			g.damage *= 1.05
			g.mag_size = maxi(3, g.mag_size)
		"armored":
			g.armor = minf(0.5, g.armor + 0.15)
		"light":
			g.move_mult *= 1.15
		"fire":
			g.element = U.EL_FIRE
			g.elem_chance += 0.45
		"shock":
			g.element = U.EL_SHOCK
			g.elem_chance += 0.45
		"acid":
			g.element = U.EL_ACID
			g.elem_chance += 0.45
		"cryo":
			g.element = U.EL_CRYO
			g.elem_chance += 0.45
		"curse":
			g.element = U.EL_CURSE
			g.elem_chance += 0.45
		"ricochet":
			g.bounces += 3
		"pierce":
			g.pierce += 2
		"vamp":
			g.leech += 0.02
		"blast":
			if g.explode_r <= 0.0:
				g.explode_r = 50.0
				g.explode_chance = 0.25
			elif g.explode_chance < 1.0:
				g.explode_chance = minf(1.0, g.explode_chance + 0.2)
			else:
				g.explode_r *= 1.25
		"grenade":
			g.proj_kind = GunData.K_GRENADE
			g.explode_r = maxf(g.explode_r, 70.0)
			g.explode_chance = 1.0
			g.explode_on_expire = true
			g.bounces += 2
			g.drag = 1.4
			g.lifetime = clampf(g.lifetime * 1.2, 0.8, 1.4)
			g.proj_speed *= 0.65
			g.damage *= 1.25
			g.fire_rate *= 0.75
			g.proj_size = maxf(g.proj_size, 4.0)
			g.pierce = 0
		"rocket":
			g.proj_kind = GunData.K_ROCKET
			g.explode_r = maxf(g.explode_r, 60.0)
			g.explode_chance = 1.0
			g.accel = 2.8
			g.proj_speed *= 0.45
			g.lifetime = maxf(g.lifetime, 1.2)
			g.damage *= 1.3
			g.fire_rate *= 0.72
			g.pierce = 0
		"split":
			g.split_n = 3
			g.split_depth = maxi(g.split_depth, 1)
		"fractal":
			g.split_n = 2
			g.split_depth = 3
		"homing":
			g.homing += 4.0
			g.proj_speed *= 0.9
		"boomerang":
			g.boomerang = true
			g.lifetime *= 1.3
		"wave":
			g.sine = 9.0
		"chain":
			g.chain_n += 3
			if g.element < 0:
				g.element = U.EL_SHOCK
			g.elem_chance += 0.1
		"cluster":
			g.cluster_n += 4
			if g.explode_r <= 0.0:
				g.explode_r = 45.0
				g.explode_chance = maxf(g.explode_chance, 0.35)
		"gravity":
			g.vortex += 0.25
		"seeder":
			g.seeder = 0.15
		"big":
			g.proj_kind = GunData.K_ORB
			g.proj_size = maxf(12.0, g.proj_size * 4.0)
			g.proj_speed *= 0.35
			g.pierce += 99
			g.damage *= 2.2
			g.fire_rate *= 0.4
			g.lifetime *= 2.5
			g.bounces += 1
		"nuke":
			if g.explode_r <= 0.0:
				g.explode_r = 60.0
				g.explode_chance = maxf(g.explode_chance, 0.35)
			g.explode_r *= 3.0
			g.fire_rate *= 0.5
			g.damage *= 1.5
			g.shake += 6.0
		"quantum":
			g.teleport = 0.35


static func _apply_special(g: Gun) -> void:
	match g.special:
		"expert":
			g.chain_n = maxi(g.chain_n, 8)
			g.element = U.EL_SHOCK
			g.elem_chance = 1.0
		"singularity":
			g.vortex = 1.0


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
	if bool(Game.run["no_heal"]):
		g.leech = 0.0   # и у легендарок
	if g.element == U.EL_CURSE:
		g.damage *= CURSE_DMG   # цена проклятия — откуда бы оно ни взялось (мод, Эррозия)
	var lvl_mult: float = Game.gun_dmg_mult(g.level)
	g.damage *= lvl_mult * float(rar["mult"])
	g.fire_rate = clampf(g.fire_rate, 0.25, 30.0)
	g.spread = clampf(g.spread, 0.0, 110.0)
	g.pellets = clampi(g.pellets, 1, 40)
	g.ammo_per_shot = maxi(1, g.ammo_per_shot)
	# магазин кратен расходу на выстрел (двуствольная снайперка Бога силы: x6 -> 6, 12...)
	g.mag_size = maxi(g.ammo_per_shot, ceili(float(g.mag_size) / float(g.ammo_per_shot)) * g.ammo_per_shot)
	g.reload_time = clampf(g.reload_time, 0.35, 6.0)
	g.crit_chance = clampf(g.crit_chance, 0.0, 0.75)
	g.elem_chance = clampf(g.elem_chance, 0.0, 1.0)
	g.proj_speed = clampf(g.proj_speed, 120.0, 3200.0)
	g.lifetime = clampf(g.lifetime, 0.2, 4.0)
	if g.element >= 0 and g.elem_chance <= 0.0:
		g.elem_chance = 0.35
	if g.maker == "synergis":
		g.explode_r = 0.0
		g.cluster_n = 0
		if g.proj_kind == GunData.K_ROCKET or g.proj_kind == GunData.K_GRENADE:
			g.proj_kind = GunData.K_BULLET
			g.explode_on_expire = false
			g.accel = 0.0
			g.drag = 0.0
		if g.special == "nuke10":
			g.special = ""
	g.explode_chance = clampf(g.explode_chance, 0.0, 1.0) if g.explode_r > 0.0 else 0.0

	var mk: Dictionary = GunData.MAKERS[g.maker]
	g.body_color = mk["body"]
	g.dark_color = mk["dark"]
	if g.element >= 0:
		g.proj_color = U.el_color(g.element)
	else:
		g.proj_color = mk["proj"]

	_build_vis(g, rng)
	_make_name(g, rng, leg)
	if not leg.is_empty():
		g.flavor = leg["fl"]
	elif g.rarity == GunData.R_ABSURD:
		g.flavor = ABSURD_FLAVOR[rng.randi() % ABSURD_FLAVOR.size()]
	else:
		g.flavor = mk["motto"]
	g.ammo = g.mag_size


static func _build_vis(g: Gun, rng: RandomNumberGenerator) -> void:
	var a: Dictionary = GunData.ARCH[g.archetype]
	var b: Dictionary = a
	if g.archetype2 != "":
		b = GunData.ARCH[g.archetype2]
	var v: Dictionary = {}
	var body := float(a["body"]) * rng.randf_range(0.9, 1.15)
	var barrel := float(b["barrel"]) * rng.randf_range(0.85, 1.2)
	if "long" in g.mods:
		barrel *= 1.4
	if "sawn" in g.mods:
		barrel *= 0.55
	var stock := float(a["stock"])
	var nb := 1
	if "double" in g.mods:
		nb += 1
	if g.pellets >= 10 or "scatter" in g.mods:
		nb += 1
	v["body"] = body
	v["bh"] = float(a["bh"]) * rng.randf_range(0.9, 1.1)
	v["barrel"] = barrel
	v["bt"] = float(b["bt"])
	v["stock"] = stock
	v["nb"] = mini(nb, 3)
	v["drum"] = g.mag_size >= 50 or "drum" in g.mods
	v["scope"] = g.archetype == "sniper" or g.archetype2 == "sniper" or "precise" in g.mods
	v["tube"] = g.proj_kind == GunData.K_ROCKET
	v["gl"] = g.proj_kind == GunData.K_GRENADE
	v["orb"] = g.proj_kind == GunData.K_ORB
	v["cyl"] = g.archetype == "revolver"
	v["mortar"] = g.archetype == "mortar" or g.archetype2 == "mortar"
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
		var d := _mod_def(str(m))
		if d.is_empty():
			continue
		var w: float = d["w"]
		if str(d["grp"]) == "kind":
			w -= 100.0  # «Гранатный»/«Реактивный» важнее всего для имени
		if w < best_w:
			best_w = w
			best = str(m)
	return best


static func _adj(id: String, gen: String) -> String:
	var d := _mod_def(id)
	if d.is_empty():
		return ""
	if I18n.is_en():
		return U.t(str(d["m"]))   # в английском у прилагательных нет рода
	return str(d["f"]) if gen == "f" else str(d["m"])


## Запоминает «детали» имени; сама строка собирается в build_name() на текущем языке.
static func _make_name(g: Gun, rng: RandomNumberGenerator, leg: Dictionary) -> void:
	var num := rng.randi_range(2, 99)
	var nick: String = GunData.NICKNAMES[rng.randi() % GunData.NICKNAMES.size()]
	var parts := {"kind": "plain", "num": num, "nick": nick, "adj": "", "adj2": ""}
	if not leg.is_empty():
		parts = {"kind": "leg", "leg": str(leg["n"])}
	elif not g.mods.is_empty():
		var prim := _primary_mod(g)
		parts["adj"] = prim
		parts["kind"] = "adj"
		if g.rarity == GunData.R_ABSURD:
			parts["kind"] = "nick"
			for m in g.mods:
				if str(m) != prim:
					parts["adj2"] = str(m)
					break
		elif g.rarity == GunData.R_EPIC:
			parts["kind"] = "nick"
	g.name_parts = parts


## Имя пушки на текущем языке.
##  ru: «Бронированный гранатомёт-ракетница Гипернова-38», «Злая снайперка «Ипотека»»
##  en: "Hypernova-38 Armored Grenade Launcher-Rocket Launcher", "Mean Sniper Rifle "Mortgage""
static func build_name(g: Gun) -> String:
	var p := g.name_parts
	var kind := str(p.get("kind", "plain"))
	if kind == "leg":
		return ("\"%s\"" if I18n.is_en() else "«%s»") % U.t(str(p["leg"]))
	var maker := U.t(GunData.MAKERS[g.maker]["n"])
	var num := int(p.get("num", 0))
	var nick := U.t(str(p.get("nick", "")))
	var a1 := str(p.get("adj", ""))
	var a2 := str(p.get("adj2", ""))
	if I18n.is_en():
		var noun := g.type_name()
		var adj := (_adj(a1, "m") + " ") if a1 != "" else ""
		if a2 != "":
			adj += _adj(a2, "m") + " "
		if kind == "nick":
			return "%s%s \"%s\"" % [adj, noun, nick]
		return "%s-%d %s%s" % [maker, num, adj, noun]
	var gen := g.gender()
	var noun_l := g.type_name_lower()
	if kind == "plain":
		return "%s %s-%d" % [g.type_name(), maker, num]
	var adj_r := _adj(a1, gen)
	if kind == "nick":
		if a2 != "":
			return "%s %s %s «%s»" % [adj_r, _adj(a2, gen).to_lower(), noun_l, nick]
		return "%s %s «%s»" % [adj_r, noun_l, nick]
	return "%s %s %s-%d" % [adj_r, noun_l, maker, num]


static func _pick_key(table: Dictionary, rng: RandomNumberGenerator) -> String:
	var keys: Array = table.keys()
	var weights: Array = []
	for k in keys:
		var row: Dictionary = table[k]
		weights.append(float(row.get("w", 1.0)))
	return keys[U.weighted(weights, rng)]
