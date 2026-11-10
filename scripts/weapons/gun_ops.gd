class_name GunOps
extends RefCounted
## Операции над статами пушки — так перки, марки и легендарки описываются данными (data/*.json).
## Операция — массив:
##   ["mul", "damage", 1.35]          умножить (у целых статов результат округляется)
##   ["add", "pierce", 2]             прибавить
##   ["set", "element", "fire"]       задать (proj_kind и element можно словами, element ещё "random")
##   ["min", "armor", 0.5]            не больше
##   ["max", "mag_size", 3]           не меньше
##   ["pellets", 5, 1.3]              +5 дробин, общий урон залпа ×1.3 (урон одной дробины пересчитается)
##   ["pellets", [5, 30, 8], 1.3]     +случайно 5–30 дробин, половина бросков — не больше 8, в среднем ~11 (roll_int)
##   ["rand", "burst", 2, 7]          случайное целое от 2 до 7 включительно (из rng пушки — по сиду воспроизводится)
##   ["rand", "burst", 2, 7, 3]       ... но обычно около 3 (половина бросков — не больше 3)
##   ["if", условие, [операции], [операции иначе]]
## Условие: ["stat", "<", 12] — сравнение (==, !=, <, <=, >, >=); ["arch", "==", "shotgun"] — основа;
##   ["and", усл, усл...], ["or", усл, усл...], ["not", усл].
## stat — любое свойство Gun (см. weapons/gun.gd): damage, fire_rate, pellets, spread, proj_speed, lifetime,
##   mag_size, reload_time, crit_chance, crit_mult, element, elem_chance, burst, ammo_per_shot, knock,
##   proj_kind, proj_size, pierce, bounces, explode_r, explode_chance, explode_on_expire, homing, accel,
##   drag, sine, boomerang, split_n, split_depth, chain_n, cluster_n, leech, vortex, seeder, teleport,
##   armor, free_ammo, proc_mult, elem_mult, move_mult, shake.

const KINDS := {"bullet": 0, "pellet": 1, "rocket": 2, "grenade": 3, "orb": 4, "shell": 8}
const ELEMENTS := {"none": -1, "fire": 0, "shock": 1, "acid": 2, "cryo": 3, "curse": 4}


static func kind_id(v: Variant) -> int:
	if v is String:
		return int(KINDS.get(v, 0))
	return int(v)


static func _value(stat: String, v: Variant, rng: RandomNumberGenerator) -> Variant:
	if v is String:
		if stat == "proj_kind":
			return int(KINDS.get(v, 0))
		if stat == "element":
			if v == "random":
				return rng.randi_range(0, U.EL_CURSE) if rng != null else randi_range(0, U.EL_CURSE)
			return int(ELEMENTS.get(v, -1))
	return v


static func run(g: Gun, ops: Variant, rng: RandomNumberGenerator) -> void:
	if not (ops is Array):
		return
	for op in ops:
		if not (op is Array) or (op as Array).is_empty():
			continue
		var o: Array = op
		var kind := str(o[0])
		match kind:
			"if":
				if o.size() >= 3:
					if check(g, o[1], rng):
						run(g, o[2], rng)
					elif o.size() >= 4:
						run(g, o[3], rng)
			"pellets":
				var old := g.pellets
				g.pellets = maxi(1, g.pellets + roll_int(o[1], rng))
				var keep := float(o[2]) if o.size() >= 3 else 1.0
				g.damage *= float(old) * keep / float(g.pellets)
			"rand":
				if o.size() >= 4:
					_stat(g, "set", str(o[1]), roll_int(o.slice(2), rng), rng)
			"set", "add", "mul", "min", "max":
				if o.size() >= 3:
					_stat(g, kind, str(o[1]), o[2], rng)
			_:
				DebugLog.warn("unknown operation %s" % str(o), "ops")


## Число из описания: просто число или [мин, макс] (равномерно) или [мин, макс, обычно] — со смещением:
## половина бросков не больше «обычно», остальные тянутся до макс. (мин + (макс − мин) · u^k).
static func roll_int(spec: Variant, rng: RandomNumberGenerator) -> int:
	if not (spec is Array):
		return int(spec)
	var a: Array = spec
	if a.size() < 2:
		return int(a[0]) if a.size() == 1 else 0
	var lo := mini(int(a[0]), int(a[1]))
	var hi := maxi(int(a[0]), int(a[1]))
	var u := rng.randf() if rng != null else randf()
	if a.size() >= 3 and float(a[2]) > float(lo) and float(a[2]) < float(hi):
		var k := log((float(a[2]) - float(lo)) / float(hi - lo)) / log(0.5)
		return clampi(lo + floori(float(hi - lo + 1) * pow(u, k)), lo, hi)
	return clampi(lo + floori(float(hi - lo + 1) * u), lo, hi)


static func _spec_ok(v: Variant) -> bool:
	if v is float or v is int:
		return true
	if not (v is Array) or (v as Array).size() < 2:
		return false
	for x in v:
		if not (x is float or x is int):
			return false
	return true


## Как показать число из описания: «5», «5–30» или «5–30 (~10)».
static func spec_text(v: Variant) -> String:
	if not (v is Array) or (v as Array).size() < 2:
		return str(roundi(float(v))) if (v is float or v is int) else str(v)
	var a: Array = v
	var s := "%d–%d" % [mini(int(a[0]), int(a[1])), maxi(int(a[0]), int(a[1]))]
	if a.size() >= 3:
		s += " (~%d)" % int(a[2])
	return s


static func _stat(g: Gun, kind: String, stat: String, v: Variant, rng: RandomNumberGenerator) -> void:
	if not (stat in g):
		DebugLog.warn("gun has no stat '%s'" % stat, "ops")
		return
	var cur: Variant = g.get(stat)
	var val: Variant = _value(stat, v, rng)
	var res: Variant = val
	if kind != "set":
		var a := float(cur)
		var b := float(val)
		match kind:
			"add":
				res = a + b
			"mul":
				res = a * b
			"min":
				res = minf(a, b)
			"max":
				res = maxf(a, b)
	match typeof(cur):
		TYPE_INT:
			res = roundi(float(res))
		TYPE_FLOAT:
			res = float(res)
		TYPE_BOOL:
			res = bool(res)
	g.set(stat, res)


static func check(g: Gun, cond: Variant, rng: RandomNumberGenerator = null) -> bool:
	if not (cond is Array) or (cond as Array).is_empty():
		return true
	var c: Array = cond
	var head := str(c[0])
	match head:
		"and":
			for i in range(1, c.size()):
				if not check(g, c[i], rng):
					return false
			return true
		"or":
			for i in range(1, c.size()):
				if check(g, c[i], rng):
					return true
			return false
		"not":
			return c.size() < 2 or not check(g, c[1], rng)
	if c.size() < 3:
		return true
	var cmp := str(c[1])
	var cur: Variant
	var val: Variant = c[2]
	if head == "arch":
		cur = g.archetype
	elif head == "arch2":
		cur = g.archetype2
	elif head == "maker":
		cur = g.maker
	elif head == "rarity":
		cur = g.rarity
	elif head in g:
		cur = g.get(head)
		val = _value(head, val, rng)
	else:
		DebugLog.warn("unknown condition %s" % str(c), "ops")
		return true
	if (cur is int or cur is float or cur is bool) and (val is int or val is float or val is bool):
		var a := float(cur)
		var b := float(val)
		match cmp:
			"==": return is_equal_approx(a, b)
			"!=": return not is_equal_approx(a, b)
			"<": return a < b
			"<=": return a <= b
			">": return a > b
			">=": return a >= b
	else:
		match cmp:
			"==": return str(cur) == str(val)
			"!=": return str(cur) != str(val)
	return false


# --- Проверка (для отладчика модов) -------------------------------------------------

const OPS := ["set", "add", "mul", "min", "max", "pellets", "rand", "if"]
const CMPS := ["==", "!=", "<", "<=", ">", ">="]
static var _probe: Gun = null


static func _has_stat(stat: String) -> bool:
	if _probe == null:
		_probe = Gun.new()
	return stat in _probe


## Список проблем в операциях (пусто — всё хорошо).
static func problems(ops: Variant) -> Array:
	var out: Array = []
	if ops == null:
		return out
	if not (ops is Array):
		out.append("'ops' must be an array, got %s" % str(ops))
		return out
	for op in ops:
		if not (op is Array) or (op as Array).is_empty():
			out.append("operation must be a non-empty array: %s" % str(op))
			continue
		var o: Array = op
		var kind := str(o[0])
		if not (kind in OPS):
			out.append("unknown operation '%s' in %s" % [kind, str(o)])
		elif kind == "if":
			if o.size() < 3:
				out.append("'if' needs [\"if\", condition, [ops], [else ops]]: %s" % str(o))
			else:
				out.append_array(cond_problems(o[1]))
				out.append_array(problems(o[2]))
				if o.size() >= 4:
					out.append_array(problems(o[3]))
		elif kind == "pellets":
			if o.size() < 2 or not _spec_ok(o[1]):
				out.append("'pellets' needs [\"pellets\", count or [min, max, usual], damage_keep]: %s" % str(o))
		elif kind == "rand":
			if o.size() < 4 or not (o[2] is float or o[2] is int) or not (o[3] is float or o[3] is int):
				out.append("'rand' needs [\"rand\", stat, min, max]: %s" % str(o))
			elif not _has_stat(str(o[1])):
				out.append("unknown stat '%s' in %s" % [str(o[1]), str(o)])
		else:
			if o.size() < 3:
				out.append("'%s' needs [\"%s\", stat, value]: %s" % [kind, kind, str(o)])
			elif not _has_stat(str(o[1])):
				out.append("unknown stat '%s' in %s" % [str(o[1]), str(o)])
			elif str(o[1]) == "proj_kind" and o[2] is String and not KINDS.has(o[2]):
				out.append("unknown projectile kind '%s' (use %s)" % [str(o[2]), ", ".join(PackedStringArray(KINDS.keys()))])
			elif str(o[1]) == "element" and o[2] is String and not ELEMENTS.has(o[2]) and o[2] != "random":
				out.append("unknown element '%s' (use %s, random)" % [str(o[2]), ", ".join(PackedStringArray(ELEMENTS.keys()))])
	return out


static func cond_problems(cond: Variant) -> Array:
	var out: Array = []
	if not (cond is Array) or (cond as Array).is_empty():
		out.append("condition must be a non-empty array: %s" % str(cond))
		return out
	var c: Array = cond
	var head := str(c[0])
	if head in ["and", "or", "not"]:
		for i in range(1, c.size()):
			out.append_array(cond_problems(c[i]))
		return out
	if c.size() < 3:
		out.append("condition needs [stat, comparison, value]: %s" % str(c))
	elif not (str(c[1]) in CMPS):
		out.append("unknown comparison '%s' in %s (use %s)" % [str(c[1]), str(c), " ".join(PackedStringArray(CMPS))])
	elif not (head in ["arch", "arch2", "maker", "rarity"]) and not _has_stat(head):
		out.append("unknown stat '%s' in condition %s" % [head, str(c)])
	return out


# --- Описание словами (справочник) --------------------------------------------------

## Короткие названия статов (английский — ключ перевода). Порядок — как в справке гайда.
const STAT_LABELS := {
	"damage": "damage",
	"fire_rate": "fire rate",
	"pellets": "pellets",
	"spread": "spread",
	"proj_speed": "projectile speed",
	"lifetime": "range",
	"mag_size": "magazine",
	"reload_time": "reload time",
	"crit_chance": "crit chance",
	"crit_mult": "crit damage",
	"element": "element",
	"elem_chance": "element chance",
	"elem_mult": "element chance multiplier",
	"burst": "burst",
	"ammo_per_shot": "rounds per shot",
	"knock": "knockback",
	"proj_kind": "projectile kind",
	"proj_size": "projectile size",
	"pierce": "pierce",
	"bounces": "ricochets",
	"explode_r": "explosion radius",
	"explode_chance": "explosion chance",
	"explode_on_expire": "explodes at end of flight",
	"homing": "homing",
	"accel": "acceleration",
	"drag": "drag",
	"sine": "wave flight",
	"boomerang": "boomerang",
	"split_n": "split",
	"split_depth": "split depth",
	"chain_n": "chain lightning",
	"cluster_n": "cluster bomblets",
	"leech": "lifesteal",
	"vortex": "black holes",
	"seeder": "side shots",
	"teleport": "projectile teleport",
	"armor": "armor",
	"free_ammo": "doesn't use reserve ammo",
	"proc_mult": "effect chance",
	"move_mult": "move speed",
	"shake": "screen shake",
}
## Эти статы — доли (0.15 = 15%).
const PERCENT_STATS := ["crit_chance", "elem_chance", "explode_chance", "leech", "armor"]


static func _lbl(stat: String) -> String:
	return U.t(str(STAT_LABELS.get(stat, stat)))


static func _num(stat: String, v: float, signed: bool) -> String:
	var s := ""
	if stat in PERCENT_STATS:
		s = "%d%%" % roundi(absf(v) * 100.0)
	elif is_equal_approx(v, roundf(v)):
		s = str(roundi(absf(v)))
	else:
		s = ("%.2f" % absf(v)).rstrip("0").rstrip(".")
	if signed:
		return ("+" if v >= 0.0 else "−") + s
	return ("−" if v < 0.0 else "") + s


static func _word(stat: String, v: Variant) -> String:
	if stat == "element":
		if v is String:
			if v == "random":
				return U.t("random")
			v = ELEMENTS.get(v, -1)
		return U.t("none") if int(v) < 0 else U.el_name(int(v))
	if stat == "proj_kind":
		var k := kind_id(v)
		for n in KINDS:
			if int(KINDS[n]) == k:
				return U.t(str(n))
	return str(v)


## Операции → строки вида «damage +35%», «pierce +2», «element: Fire».
static func describe(ops: Variant) -> Array:
	var out: Array = []
	if not (ops is Array):
		return out
	for op in ops:
		if not (op is Array) or (op as Array).is_empty():
			continue
		var o: Array = op
		var kind := str(o[0])
		match kind:
			"if":
				if o.size() >= 3:
					var s := U.t("if %s: %s") % [describe_cond(o[1]), ", ".join(PackedStringArray(describe(o[2])))]
					if o.size() >= 4 and o[3] is Array and not (o[3] as Array).is_empty():
						s += "; " + U.t("otherwise: %s") % ", ".join(PackedStringArray(describe(o[3])))
					out.append("(" + s + ")")
			"pellets":
				var s := "%s %s" % [_lbl("pellets"), _num("pellets", float(o[1]), true) if not (o[1] is Array) else "+" + spec_text(o[1])]
				if o.size() >= 3 and not is_equal_approx(float(o[2]), 1.0):
					s += " (" + U.t("volley damage ×%s") % _num("", float(o[2]), false) + ")"
				out.append(s)
			"rand":
				if o.size() >= 4:
					out.append("%s: %s" % [_lbl(str(o[1])), spec_text(o.slice(2))])
			"mul":
				if o.size() >= 3:
					var v := float(o[2])
					if v >= 2.0 or v <= 0.0:
						out.append("%s ×%s" % [_lbl(str(o[1])), _num("", v, false)])
					else:
						out.append("%s %s%d%%" % [_lbl(str(o[1])), "+" if v >= 1.0 else "−", roundi(absf(v - 1.0) * 100.0)])
			"add":
				if o.size() >= 3:
					out.append("%s %s" % [_lbl(str(o[1])), _num(str(o[1]), float(o[2]), true)])
			"set":
				if o.size() >= 3:
					var stat := str(o[1])
					var v: Variant = o[2]
					if v is bool:
						out.append(_lbl(stat) if v else U.t("no %s") % _lbl(stat))
					elif stat in ["element", "proj_kind"]:
						out.append("%s: %s" % [_lbl(stat), _word(stat, v)])
					else:
						out.append("%s: %s" % [_lbl(stat), _num(stat, float(v), false)])
			"min":
				if o.size() >= 3:
					out.append(U.t("%s at most %s") % [_lbl(str(o[1])), _num(str(o[1]), float(o[2]), false)])
			"max":
				if o.size() >= 3:
					out.append(U.t("%s at least %s") % [_lbl(str(o[1])), _num(str(o[1]), float(o[2]), false)])
	return out


## Условие словами: «element is none», «spread > 1».
static func describe_cond(cond: Variant) -> String:
	if not (cond is Array) or (cond as Array).is_empty():
		return "?"
	var c: Array = cond
	var head := str(c[0])
	if head == "not":
		return U.t("not (%s)") % (describe_cond(c[1]) if c.size() > 1 else "?")
	if head in ["and", "or"]:
		var parts := PackedStringArray()
		for i in range(1, c.size()):
			parts.append(describe_cond(c[i]))
		return (" %s " % U.t(head)).join(parts)
	if c.size() < 3:
		return "?"
	var val := ""
	match head:
		"arch", "arch2":
			val = U.t(str(GunData.ARCH.get(str(c[2]), {}).get("name", c[2])))
			head = U.t("type") if head == "arch" else U.t("second type")
		"maker":
			val = U.t(str(GunData.MAKERS.get(str(c[2]), {}).get("name", c[2])))
			head = U.t("maker")
		"rarity":
			var r := clampi(int(c[2]), 0, GunData.RARITIES.size() - 1)
			val = U.t(str(GunData.RARITIES[r]["name"])) if not GunData.RARITIES.is_empty() else str(c[2])
			head = U.t("rarity")
		"element", "proj_kind":
			val = _word(head, c[2])
			head = _lbl(head)
		_:
			val = _num(head, float(c[2]), false) if (c[2] is float or c[2] is int) else str(c[2])
			head = _lbl(head)
	return "%s %s %s" % [head, str(c[1]), val]
