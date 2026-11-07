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
				g.pellets = maxi(1, g.pellets + int(o[1]))
				var keep := float(o[2]) if o.size() >= 3 else 1.0
				g.damage *= float(old) * keep / float(g.pellets)
			"set", "add", "mul", "min", "max":
				if o.size() >= 3:
					_stat(g, kind, str(o[1]), o[2], rng)
			_:
				push_warning("GunOps: неизвестная операция %s" % str(o))


static func _stat(g: Gun, kind: String, stat: String, v: Variant, rng: RandomNumberGenerator) -> void:
	if not (stat in g):
		push_warning("GunOps: у пушки нет свойства %s" % stat)
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
		push_warning("GunOps: неизвестное условие %s" % str(c))
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
