class_name Projectiles
extends Node2D
## Все снаряды игры живут здесь как данные (без нод) — так тысячи пуль не тормозят.
## Тут же отложенные взрывы-предупреждения (миномёты, босс) и чёрные дыры.

const MAX_PROJ := 2600
const MAX_VORTEX := 10
const MAX_LIFE := 5.0      # «бесконечная» дальность: летим до стены или 5 с
const FAR := 1.0e9
const RICOCHET_MULT := 0.7   # каждый рикошет пули срезает 30% урона (гранаты — нет)
const PIERCE_MULT := 0.6     # каждое пробитие врага срезает 40% урона снаряда

const K_BULLET := 0
const K_PELLET := 1
const K_ROCKET := 2
const K_GRENADE := 3
const K_ORB := 4
const K_ENEMY := 5
const K_BOMBLET := 6
const K_NEEDLE := 7
const K_SHELL := 8


class Proj:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var team := 0
	var kind := 0
	var dmg := 1.0
	var radius := 3.0
	var size := 3.0
	var color := Color.WHITE
	var life := 1.0
	var max_life := 1.0
	var age := 0.0
	var pierce := 0
	var bounces := 0
	var explode_r := 0.0
	var explode_chance := 1.0
	var explode_on_expire := false
	var eff_range := 1.0e9
	var traveled := 0.0
	var homing := 0.0
	var accel := 0.0
	var max_speed := 1700.0
	var drag := 0.0
	var sine := 0.0
	var sine_phase := 0.0
	var boomerang := false
	var returning := false
	var split_n := 0
	var split_depth := 0
	var chain_n := 0
	var cluster_n := 0
	var leech := 0.0
	var vortex := 0.0
	var seeder := 0.0
	var seeder_t := 0.0
	var teleport := 0.0
	var tele_t := 0.0
	var element := -1
	var elem_chance := 0.0
	var proc := 1.0          # коэффициент срабатывания эффектов по шансу
	var st := 0.1            # сколько кислоты/холода даёт попадание
	var crit_chance := 0.05
	var crit_mult := 2.0
	var knock := 0.0
	var nuke := false
	var chaos := false
	var no_falloff := false   # револьвер: урон не падает за дальностью
	var range_dmg := 0.0      # снайперка: урон растёт с пролётом от этой доли до 100% на половине eff_range
	var skill := false        # снаряд навыка героя: попадания и взрыв — через Skills (перки навыка)
	var hit: Dictionary = {}
	var start := Vector2.ZERO   # мина: откуда летит
	var target := Vector2.ZERO  # мина: куда падает
	var dead := false


var list: Array[Proj] = []
var _pending: Array[Proj] = []
var blasts: Array = []
var vortices: Array = []
var clouds: Array = []       # дым «Дымовой гранаты»: {pos, r, dmg (за тик), t, max, tick, every, st, first}
var _t := 0.0


func count() -> int:
	return list.size() + _pending.size()


func clear_all() -> void:
	list.clear()
	_pending.clear()
	blasts.clear()
	vortices.clear()
	clouds.clear()
	queue_redraw()


func _add(p: Proj) -> void:
	if count() < MAX_PROJ:
		_pending.append(p)


# --- Создание снарядов ---------------------------------------------------------

## Мина в конкретную точку (миномёт). Цель уже с учётом разброса — её считает стрелок.
func fire_shell(g: Gun, pos: Vector2, target: Vector2, dmg_mult: float = 1.0) -> Proj:
	var p := fire_gun(g, pos, (target - pos).normalized(), 0, dmg_mult)
	if p != null:
		p.target = target
	return p


## Граната героя (навык Первопроходца): летит дугой, как мина, и взрывается в точке падения
## через Skills.explode (перки навыка). Урон фиксированный — от уровня зоны не зависит.
func throw_grenade(pos: Vector2, target: Vector2, dmg: float, r: float, col: Color) -> void:
	if count() >= MAX_PROJ:
		return
	var p := Proj.new()
	p.skill = true
	p.team = 0
	p.kind = K_SHELL
	p.pos = pos
	p.start = pos
	p.target = target
	p.dmg = dmg
	p.explode_r = r
	p.size = 5.0
	p.radius = 8.0
	p.color = col
	p.life = clampf(pos.distance_to(target) / 650.0, 0.3, 0.7)
	p.max_life = p.life
	p.eff_range = FAR
	p.crit_chance = 0.0
	p.knock = 60.0
	_add(p)


func fire_gun(g: Gun, pos: Vector2, dir: Vector2, team: int, dmg_mult: float = 1.0) -> Proj:
	if count() >= MAX_PROJ:
		return null
	var p := Proj.new()
	p.team = team
	p.pos = pos
	var spd := g.proj_speed
	if g.pellets > 1:
		spd *= randf_range(0.85, 1.12)
	else:
		spd *= randf_range(0.97, 1.03)
	p.vel = dir * spd
	p.kind = g.proj_kind
	p.dmg = g.damage * dmg_mult
	p.proc = clampf(g.proc_coef() * dmg_mult, 0.08, 1.0)
	# секунда стрельбы = +10% кислоты/холода, независимо от скорострельности
	p.st = 0.1 * g.elem_mult / maxf(0.25, g.fire_rate * float(g.pellets))
	p.size = g.proj_size
	p.radius = g.proj_size + 3.0
	p.color = g.proj_color
	if p.kind == K_SHELL:
		# по умолчанию (кольцо «Тостера» и т.п.) мина падает по направлению на 60% дальности
		p.life = GunData.SHELL_TIME
		p.eff_range = FAR
		p.start = pos
		p.target = pos + dir * g.eff_range() * 0.6
	elif p.kind == K_GRENADE:
		# у гранат lifetime — это запал
		p.life = g.lifetime * randf_range(0.85, 1.15)
		p.eff_range = maxf(60.0, g.eff_range())
	else:
		p.life = MAX_LIFE
		p.eff_range = maxf(60.0, g.eff_range())
	p.max_life = p.life
	p.pierce = g.pierce
	p.bounces = g.bounces
	p.explode_r = g.explode_r
	p.explode_chance = g.explode_chance
	p.explode_on_expire = g.explode_on_expire
	p.homing = g.homing
	p.accel = g.accel
	p.drag = g.drag
	p.sine = g.sine
	p.sine_phase = randf() * TAU
	p.boomerang = g.boomerang
	p.split_n = g.split_n
	p.split_depth = g.split_depth
	p.chain_n = g.chain_n
	p.cluster_n = g.cluster_n
	p.leech = g.leech
	p.vortex = g.vortex_chance()
	p.seeder = g.seeder
	p.seeder_t = g.seeder
	p.teleport = g.teleport
	p.element = g.element
	p.elem_chance = g.elem_chance * g.elem_mult
	p.crit_chance = g.crit_chance
	p.crit_mult = g.crit_mult
	p.knock = g.knock
	p.chaos = g.special == "chaos"
	p.no_falloff = g.no_falloff
	p.range_dmg = g.range_dmg if p.kind != K_SHELL else 0.0
	_add(p)
	return p


## Каждый 10-й выстрел «Последнего Слова».
func fire_nuke(g: Gun, pos: Vector2, dir: Vector2) -> void:
	var p := fire_gun(g, pos, dir, 0)
	if p == null:
		return
	p.kind = K_ROCKET
	p.size = 7.0
	p.radius = 10.0
	p.vel = dir * 600.0
	p.accel = 1.5
	p.life = 1.5
	p.max_life = 1.5
	var lvl_mult: float = Game.gun_dmg_mult(g.level)
	p.dmg = Gun.NUKE_COST * 0.4 * lvl_mult
	p.proc = 1.0
	p.eff_range = FAR
	p.explode_chance = 1.0
	p.explode_r = 230.0
	p.pierce = 0
	p.split_n = 0
	p.nuke = true
	p.color = Color(1.0, 0.9, 0.3)


func enemy_shot(pos: Vector2, dir: Vector2, speed: float, dmg: float, size: float = 6.0,
		col: Color = Color(1.0, 0.3, 0.35)) -> void:
	if count() >= MAX_PROJ:
		return
	Sfx.at("enemy/shot", pos, -15.0, 1.0, 0.08, 3, 0.06)
	var p := Proj.new()
	p.team = 1
	p.kind = K_ENEMY
	p.pos = pos
	p.vel = dir * speed
	p.dmg = dmg
	p.size = size
	p.radius = size
	p.color = col
	p.life = 4.0
	p.max_life = 4.0
	_add(p)


## Медленный вражеский снаряд, который плавно доворачивает к игроку (turn_deg — градусов в секунду).
## Пока летит — его можно обойти по дуге; живёт долго, поэтому висит над ареной и давит пространство.
func enemy_seeker(pos: Vector2, dir: Vector2, speed: float, dmg: float, size: float, col: Color,
		turn_deg: float, life: float) -> void:
	if count() >= MAX_PROJ:
		return
	var p := Proj.new()
	p.team = 1
	p.kind = K_ENEMY
	p.pos = pos
	p.vel = dir * speed
	p.dmg = dmg
	p.size = size
	p.radius = size
	p.color = col
	p.life = life
	p.max_life = life
	p.homing = deg_to_rad(turn_deg)
	_add(p)


func add_blast(pos: Vector2, r: float, dmg: float, delay: float, team: int) -> void:
	blasts.append({"pos": pos, "r": r, "dmg": dmg, "t": delay, "max": delay, "team": team})


func add_vortex(pos: Vector2, r: float, dps: float, dur: float) -> void:
	Sfx.at("fx/vortex", pos, -4.0, 1.0, 0.05, 2, 0.2)
	if vortices.size() >= MAX_VORTEX:
		return
	vortices.append({"pos": pos, "r": r, "dps": dps, "t": dur, "max": dur, "tick": 0.0})


func _clone(p: Proj) -> Proj:
	var c := Proj.new()
	c.pos = p.pos
	c.vel = p.vel
	c.team = p.team
	c.kind = p.kind
	c.dmg = p.dmg
	c.radius = p.radius
	c.size = p.size
	c.color = p.color
	c.life = p.life
	c.max_life = p.max_life
	c.pierce = p.pierce
	c.bounces = p.bounces
	c.explode_r = p.explode_r
	c.explode_chance = p.explode_chance
	c.explode_on_expire = p.explode_on_expire
	c.eff_range = p.eff_range
	c.homing = p.homing
	c.accel = p.accel
	c.drag = p.drag
	c.sine = p.sine
	c.sine_phase = randf() * TAU
	c.boomerang = false
	c.split_n = p.split_n
	c.split_depth = p.split_depth
	c.chain_n = p.chain_n
	c.cluster_n = p.cluster_n
	c.leech = p.leech
	c.vortex = p.vortex
	c.seeder = 0.0
	c.teleport = p.teleport
	c.element = p.element
	c.elem_chance = p.elem_chance
	c.proc = p.proc
	c.st = p.st
	c.crit_chance = p.crit_chance
	c.crit_mult = p.crit_mult
	c.knock = p.knock * 0.5
	c.chaos = p.chaos
	c.no_falloff = p.no_falloff
	c.range_dmg = 0.0   # осколки и копии бьют в полную силу с места разделения
	return c


# --- Симуляция -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var main: Main = Game.main
	if main == null:
		return
	_t += delta
	var zone: Zone = main.zone
	var player: Player = main.player
	for p in list:
		if not p.dead:
			_step(p, delta, zone, player, main)
	var alive: Array[Proj] = []
	for p in list:
		if not p.dead:
			alive.append(p)
	alive.append_array(_pending)
	_pending.clear()
	list = alive
	_update_blasts(delta)
	_update_vortices(delta, main)
	if not clouds.is_empty():
		_update_clouds(delta, main)
	queue_redraw()


## Облако дыма навыка: dmg — урон за тик всем внутри, every — секунд между тиками, st — стихии за тик.
func add_smoke(pos: Vector2, r: float, dmg: float, dur: float, every: float, st: float) -> void:
	clouds.append({"pos": pos, "r": r, "dmg": dmg, "t": dur, "max": dur, "tick": 0.0, "every": every, "st": st, "first": true})


func _update_clouds(delta: float, main: Main) -> void:
	var keep: Array = []
	for c in clouds:
		c["t"] = float(c["t"]) - delta
		c["tick"] = float(c["tick"]) - delta
		if float(c["tick"]) <= 0.0:
			c["tick"] = float(c["tick"]) + float(c["every"])
			var pos: Vector2 = c["pos"]
			var r := float(c["r"])
			for o in main.grid_hash.query(pos, r + 50.0):
				var e: Enemy = o
				if not e.dead and pos.distance_to(e.position) < r + e.radius:
					Skills.hit(e, float(c["dmg"]), Vector2.ZERO, bool(c["first"]), float(c["st"]), true)
			c["first"] = false
		if float(c["t"]) > 0.0:
			keep.append(c)
	clouds = keep


## Парирование Ассасина: вражеские снаряды в дуге удара разворачиваются и летят во врагов.
## mult — урон отражённого снаряда относительно исходного. Возвращает, сколько отразили.
func reflect(from: Vector2, dir: Vector2, r: float, half_arc: float, mult: float) -> int:
	var n := 0
	for p in list + _pending:
		if p.dead or p.team != 1:
			continue
		var to := p.pos - from
		if to.length() > r or (to.length() > 20.0 and absf(dir.angle_to(to)) > half_arc):
			continue
		var tgt := _nearest_enemy(p.pos, 700.0, Game.main)
		var out := (tgt.position - p.pos).normalized() if tgt != null else -p.vel.normalized()
		p.team = 0
		p.kind = K_BULLET
		p.vel = out * maxf(p.vel.length(), 700.0) * 1.2
		p.dmg *= mult
		p.color = Color(0.85, 0.7, 1.0)
		p.life = MAX_LIFE
		p.max_life = MAX_LIFE
		p.eff_range = FAR
		p.crit_chance = 0.0
		p.hit = {}
		Game.main.fx.spark(p.pos, out, p.color, 4, 220.0)
		n += 1
	return n


func _step(p: Proj, delta: float, zone: Zone, player: Player, main: Main) -> void:
	if p.kind == K_SHELL:
		# мина летит над всем, ни во что не врезается и взрывается в точке падения
		p.age += delta
		p.life -= delta
		p.pos = p.start.lerp(p.target, clampf(p.age / p.max_life, 0.0, 1.0))
		if p.life <= 0.0:
			p.pos = p.target
			_detonate(p, p.target)
			p.dead = true
		return
	p.age += delta
	p.life -= delta
	if p.life <= 0.0:
		if p.team == 0 and (p.explode_on_expire or p.kind == K_ROCKET):
			_detonate(p, p.pos, _falloff(p))
		p.dead = true
		return

	if p.team == 1 and p.homing > 0.0 and player != null and not player.dead:
		# вражеский самонаводящийся: поворот к игроку с ограниченной угловой скоростью
		var seek_diff := wrapf((player.position - p.pos).angle() - p.vel.angle(), -PI, PI)
		p.vel = p.vel.rotated(clampf(seek_diff, -p.homing * delta, p.homing * delta))

	if p.team == 0:
		if p.homing > 0.0 and not p.returning:
			var tgt := _nearest_enemy(p.pos, 380.0, main)
			if tgt != null:
				var want := (tgt.position - p.pos).angle()
				var diff := wrapf(want - p.vel.angle(), -PI, PI)
				p.vel = p.vel.rotated(clampf(diff, -p.homing * delta, p.homing * delta))
		if p.boomerang:
			if not p.returning and p.traveled > p.eff_range * 0.5:
				p.returning = true
				p.hit.clear()
				p.pierce += 2
			if p.returning:
				var to := player.position - p.pos
				var spd := maxf(p.vel.length(), 500.0)
				p.vel = p.vel.lerp(to.normalized() * spd, minf(1.0, delta * 8.0))
				p.life = maxf(p.life, 0.2)
				if to.length() < 26.0:
					p.dead = true
					return
		if p.teleport > 0.0:
			p.tele_t -= delta
			if p.tele_t <= 0.0:
				p.tele_t = 0.2
				if randf() < p.teleport:
					var jump := p.pos + p.vel.normalized() * 110.0
					if not zone.blocks_shot_at(jump):
						main.fx.blink(p.pos, jump, p.color)
						p.pos = jump
						p.hit.clear()
		if p.seeder > 0.0 and p.traveled <= p.eff_range:
			p.seeder_t -= delta
			if p.seeder_t <= 0.0:
				p.seeder_t = p.seeder
				_seed(p)

	if p.accel != 0.0:
		var sp := p.vel.length() * (1.0 + p.accel * delta)
		p.vel = p.vel.normalized() * minf(sp, p.max_speed)
	if p.drag > 0.0:
		p.vel *= maxf(0.0, 1.0 - p.drag * delta)

	var move := p.vel * delta
	if p.sine > 0.0 and p.vel.length_squared() > 1.0:
		var perp := p.vel.normalized().orthogonal()
		# Боковое смещение A*sin(wt) -> скорость A*w*cos(wt); A ~ 3.5*sine пикселей.
		move += perp * cos(p.age * 14.0 + p.sine_phase) * (p.sine * 3.5) * 14.0 * delta
	var np := p.pos + move

	# Стены
	if zone.blocks_shot_at(np):
		if p.bounces > 0:
			p.bounces -= 1
			var bx := zone.blocks_shot_at(Vector2(np.x, p.pos.y))
			var by := zone.blocks_shot_at(Vector2(p.pos.x, np.y))
			if bx:
				p.vel.x = -p.vel.x
			if by:
				p.vel.y = -p.vel.y
			if not bx and not by:
				p.vel = -p.vel
			p.hit.clear()
			if p.kind == K_GRENADE or p.kind == K_BOMBLET:
				p.vel *= 0.7  # гранаты катятся по полу — урон не теряют
			else:
				p.dmg *= RICOCHET_MULT
				if p.team == 0:
					Sfx.at("hit/wall", p.pos, -16.0, 1.3, 0.1, 2, 0.06)
			return
		if p.team == 0:
			if p.explode_r <= 0.0 and p.kind != K_ROCKET and p.kind != K_GRENADE:
				Sfx.at("hit/wall", p.pos, -14.0, 1.0, 0.1, 3, 0.05)
			_impact(p, p.pos)
		else:
			main.fx.spark(p.pos, -p.vel.normalized(), p.color, 3, 120.0)
		p.dead = true
		return
	p.pos = np
	p.traveled += move.length()

	# Попадания
	if p.team == 0:
		var cands: Array = main.grid_hash.query(p.pos, p.radius + 50.0)
		for o in cands:
			var e: Enemy = o
			if e.dead:
				continue
			var id := e.get_instance_id()
			if p.hit.has(id):
				continue
			var rr := e.radius + p.radius
			if p.pos.distance_squared_to(e.position) < rr * rr:
				_hit_enemy(p, e, main)
				if p.dead:
					return
	elif not player.dead:
		var rr := player.radius * 0.7 + p.radius
		if p.pos.distance_squared_to(player.position) < rr * rr:
			# во время переката пуля пролетает насквозь (и засчитывает уклон)
			if player.take_damage(p.dmg):
				p.dead = true


func _roll_el(p: Proj) -> int:
	if p.element < 0:
		return -1
	# кислота и холод копятся линейно с каждым попаданием — без броска шанса
	if p.element == U.EL_ACID or p.element == U.EL_CRYO or p.element == U.EL_CURSE:
		return p.element
	if randf() < p.elem_chance * p.proc:
		return p.element
	return -1


## Урон после эффективной дальности: +33% дальности -> 37%, x2 -> 5% (минимум).
## Множитель урона от пролёта: за эффективной дальностью урон падает (кроме no_falloff),
## у снайперки — растёт от range_dmg до 100% к половине эффективной дальности.
func _falloff(p: Proj) -> float:
	var k := 1.0
	if p.range_dmg > 0.0:
		k = lerpf(p.range_dmg, 1.0, clampf(p.traveled / maxf(1.0, p.eff_range * 0.5), 0.0, 1.0))
	if p.traveled <= p.eff_range or p.no_falloff:
		return k
	return k * maxf(0.05, exp(-3.0 * (p.traveled - p.eff_range) / p.eff_range))


func _hit_enemy(p: Proj, e: Enemy, main: Main) -> void:
	p.hit[e.get_instance_id()] = true
	var fo := _falloff(p)
	if p.explode_r > 0.0 and p.explode_chance >= 1.0:
		_detonate(p, p.pos, fo)
	else:
		var crit := randf() < p.crit_chance
		var d := p.dmg * fo * (p.crit_mult if crit else 1.0)
		if p.chaos:
			d *= randf_range(0.0, 2.0)
		var el := _roll_el(p)
		if p.skill:
			Skills.hit(e, d, p.vel.normalized() * maxf(p.knock, 60.0) * fo)
		else:
			Combat.hit_enemy(e, d, crit, el, p.vel.normalized() * p.knock * fo, false, p.st)
		Sfx.at("hit/enemy", e.position, -12.0 if not crit else -8.0, 1.0, 0.1, 3, 0.035)
		if p.leech > 0.0:
			main.player.leech(d, p.leech)
		if p.chain_n > 0 and randf() < p.proc:
			Combat.chain(e, d * 0.6, p.chain_n, p.element if p.element >= 0 else U.EL_SHOCK, p.st)
		if p.vortex > 0.0 and randf() < p.vortex:
			add_vortex(e.position, 150.0, p.dmg * 0.8 * fo, 1.6)
			p.vortex = 0.0
		# взрыв по шансу — поверх обычного попадания
		if p.explode_r > 0.0 and randf() < p.explode_chance * p.proc:
			_detonate(p, p.pos, fo * 0.6, true)
	if p.split_n > 0 and p.split_depth > 0:
		_split(p, true)
	if p.pierce > 0:
		p.pierce -= 1
		p.dmg *= PIERCE_MULT   # каждое пробитие срезает урон снаряда
	else:
		p.dead = true


## Взрыв снаряда игрока (гранаты, ракеты, «Взрывной» мод, кассеты...).
## secondary = взрыв «по шансу» поверх попадания: без повторных цепей/дыр/вампиризма.
func _detonate(p: Proj, pos: Vector2, mult: float = 1.0, secondary: bool = false) -> void:
	var main: Main = Game.main
	var r := p.explode_r if p.explode_r > 0.0 else 40.0
	if p.skill and not secondary:
		Skills.explode(pos, r, p.dmg * mult, p.color)
		p.skill = false   # кассеты и прочее после взрыва — уже обычные
		if p.cluster_n > 0 and p.kind != K_BOMBLET:
			for i in p.cluster_n:
				_bomblet(p, pos)
		return
	var crit := randf() < p.crit_chance
	var d := p.dmg * mult * (p.crit_mult if crit else 1.0)
	if p.chaos:
		d *= randf_range(0.0, 2.0)
	var el := _roll_el(p)
	var total := Combat.explode(pos, r, d, crit, el, 0, (p.knock + 120.0) * minf(mult, 1.0), p.nuke, p.st)
	if not secondary:
		if p.leech > 0.0 and total > 0.0:
			main.player.leech(total, p.leech)
		if p.chain_n > 0 and randf() < p.proc:
			var t := _nearest_enemy(pos, r + 60.0, main)
			if t != null:
				Combat.chain(t, d * 0.5, p.chain_n, p.element if p.element >= 0 else U.EL_SHOCK, p.st)
		if p.vortex > 0.0 and randf() < p.vortex:
			add_vortex(pos, 160.0, p.dmg * 0.8 * mult, 1.6)
			p.vortex = 0.0
	if p.cluster_n > 0 and p.kind != K_BOMBLET:
		for i in p.cluster_n:
			_bomblet(p, pos)


## Удар о стену.
func _impact(p: Proj, pos: Vector2) -> void:
	var fo := _falloff(p)
	if (p.explode_r > 0.0 and p.explode_chance >= 1.0) or p.kind == K_ROCKET or p.kind == K_GRENADE:
		_detonate(p, pos, fo)
	elif p.explode_r > 0.0 and randf() < p.explode_chance * p.proc:
		_detonate(p, pos, fo * 0.6, true)
	else:
		Game.main.fx.spark(pos, -p.vel.normalized(), p.color, 3, 160.0)
	if p.split_n > 0 and p.split_depth > 0:
		_split(p, false)


func _split(p: Proj, forward: bool) -> void:
	var n := p.split_n
	var base := p.vel.angle() if forward else (-p.vel).angle()
	var spd := maxf(p.vel.length(), 300.0)
	for i in n:
		var a := base
		if n > 1:
			a = base + lerpf(-0.6, 0.6, (float(i) + 0.5) / float(n))
		var c := _clone(p)
		c.pos = p.pos - p.vel.normalized() * (0.0 if forward else 6.0)
		c.vel = Vector2.from_angle(a) * spd
		c.dmg = p.dmg * 0.45 * _falloff(p)
		c.proc = maxf(0.08, p.proc * 0.45)
		c.st = p.st * 0.45
		c.eff_range = maxf(60.0, p.eff_range * 0.6)
		c.traveled = 0.0
		c.size = maxf(1.5, p.size * 0.75)
		c.radius = c.size + 2.0
		c.split_depth = p.split_depth - 1
		c.life = maxf(0.25, p.max_life * 0.55)
		c.max_life = c.life
		c.hit = p.hit.duplicate()
		c.pierce = 0
		c.cluster_n = 0
		_add(c)


func _bomblet(p: Proj, pos: Vector2) -> void:
	var c := Proj.new()
	c.team = p.team
	c.kind = K_BOMBLET
	c.pos = pos
	c.vel = Vector2.from_angle(randf() * TAU) * randf_range(180.0, 340.0)
	c.dmg = p.dmg * 0.35
	c.size = 4.0
	c.radius = 6.0
	c.color = p.color
	c.life = randf_range(0.35, 0.65)
	c.max_life = c.life
	c.explode_r = maxf(30.0, p.explode_r * 0.5)
	c.explode_on_expire = true
	c.drag = 3.0
	c.bounces = 2
	c.element = p.element
	c.elem_chance = p.elem_chance
	c.proc = maxf(0.08, p.proc * 0.35)
	c.st = p.st * 0.35
	c.crit_chance = p.crit_chance
	c.crit_mult = p.crit_mult
	_add(c)


## «Сеющие» снаряды плюются иглами вбок.
func _seed(p: Proj) -> void:
	for s in [-1.0, 1.0]:
		var c := Proj.new()
		c.team = p.team
		c.kind = K_NEEDLE
		c.pos = p.pos
		c.vel = p.vel.normalized().orthogonal() * float(s) * 700.0
		c.dmg = p.dmg * 0.12
		c.proc = maxf(0.08, p.proc * 0.12)
		c.st = p.st * 0.12
		c.size = 2.0
		c.radius = 4.0
		c.color = p.color.lightened(0.3)
		c.life = 0.35
		c.max_life = 0.35
		c.element = p.element
		c.elem_chance = p.elem_chance * 0.5
		c.crit_chance = p.crit_chance
		c.crit_mult = p.crit_mult
		_add(c)


func _nearest_enemy(pos: Vector2, r: float, main: Main) -> Enemy:
	var best: Enemy = null
	var bd := r * r
	for o in main.grid_hash.query(pos, r):
		var e: Enemy = o
		if e.dead:
			continue
		var d2 := pos.distance_squared_to(e.position)
		if d2 < bd:
			bd = d2
			best = e
	return best


func _update_blasts(delta: float) -> void:
	# Взрыв может убить «взрывного» элитника, который добавит новые взрывы —
	# поэтому итерируемся по снимку, а новые подклеиваем в конце.
	var cur := blasts
	blasts = []
	var keep: Array = []
	for b in cur:
		b["t"] -= delta
		if float(b["t"]) <= 0.0:
			Combat.explode(b["pos"], b["r"], b["dmg"], false, -1, int(b["team"]), 0.0, false)
		else:
			keep.append(b)
	keep.append_array(blasts)
	blasts = keep


func _update_vortices(delta: float, main: Main) -> void:
	var cur := vortices
	vortices = []
	var keep: Array = []
	for v in cur:
		v["t"] -= delta
		v["tick"] -= delta
		var pos: Vector2 = v["pos"]
		var r: float = v["r"]
		var do_tick := float(v["tick"]) <= 0.0
		if do_tick:
			v["tick"] = 0.25
		for o in main.grid_hash.query(pos, r + 50.0):
			var e: Enemy = o
			if e.dead:
				continue
			var d := pos - e.position
			var l := d.length()
			if l < r:
				if l > 6.0 and e.elite != 3:
					e.position = main.zone.move_circle(e.position, d / l * minf(l, 280.0 * delta), e.radius)
				if do_tick:
					Combat.hit_enemy(e, float(v["dps"]) * 0.25, false, -1, Vector2.ZERO, true)
		if float(v["t"]) > 0.0:
			keep.append(v)
	keep.append_array(vortices)
	vortices = keep


# --- Отрисовка --------------------------------------------------------------------

func _draw() -> void:
	for c in clouds:
		var pos: Vector2 = c["pos"]
		var r := float(c["r"])
		var fade := clampf(float(c["t"]) / 0.6, 0.0, 1.0) * clampf((float(c["max"]) - float(c["t"])) / 0.3, 0.0, 1.0)
		draw_circle(pos, r, Color(0.62, 0.64, 0.68, 0.16 * fade))
		for i in 7:
			var a := _t * 0.4 + TAU * float(i) / 7.0
			var q := pos + Vector2.from_angle(a) * r * (0.35 + 0.25 * sin(_t * 0.7 + float(i)))
			draw_circle(q, r * 0.28, Color(0.7, 0.72, 0.76, 0.12 * fade))
		draw_arc(pos, r, 0.0, TAU, 48, Color(0.8, 0.82, 0.86, 0.35 * fade), 2.0)
	for b in blasts:
		var pos: Vector2 = b["pos"]
		var r: float = b["r"]
		var k := 1.0 - float(b["t"]) / maxf(0.01, float(b["max"]))
		var col := Color(1.0, 0.25, 0.15) if int(b["team"]) == 1 else Color(1.0, 0.7, 0.2)
		draw_circle(pos, r, Color(col, 0.10))
		draw_circle(pos, r * k, Color(col, 0.22))
		draw_arc(pos, r, 0.0, TAU, 40, Color(col, 0.85), 2.0)
	for v in vortices:
		var pos: Vector2 = v["pos"]
		var r: float = v["r"]
		var fade := clampf(float(v["t"]) / 0.3, 0.0, 1.0)
		draw_circle(pos, r * 0.32, Color(0.03, 0.0, 0.07, 0.9 * fade))
		for i in 4:
			var a := _t * 5.0 + TAU * float(i) / 4.0
			draw_arc(pos, r * (0.4 + 0.15 * float(i)), a, a + 1.6, 12, Color(0.7, 0.35, 1.0, 0.6 * fade), 2.0)
	for p in list:
		_draw_proj(p)


func _draw_proj(p: Proj) -> void:
	if p.team == 0 and p.traveled > p.eff_range:
		# за эффективной дальностью пуля «выдыхается» и визуально
		var c := p.color
		c.a = maxf(0.25, _falloff(p))
		p.color = c
	match p.kind:
		K_SHELL:
			var k := clampf(p.age / p.max_life, 0.0, 1.0)
			var r := p.explode_r if p.explode_r > 0.0 else 40.0
			# метка падения
			draw_circle(p.target, r, Color(p.color, 0.08))
			draw_circle(p.target, r * k, Color(p.color, 0.16))
			draw_arc(p.target, r, 0.0, TAU, 32, Color(p.color, 0.7), 1.5)
			# мина по дуге + тень
			var h := sin(PI * k) * clampf(p.start.distance_to(p.target) * 0.35, 40.0, 220.0)
			draw_circle(p.pos, p.size * 0.8, Color(0, 0, 0, 0.3))
			draw_circle(p.pos - Vector2(0, h), p.size + 1.5, Color(0.12, 0.12, 0.14))
			draw_circle(p.pos - Vector2(0, h), p.size * 0.6, p.color)
		K_BULLET, K_NEEDLE:
			var dir := p.vel.normalized()
			var tail := dir * minf(p.vel.length() * 0.022, 26.0)
			draw_line(p.pos - tail, p.pos, Color(p.color, 0.35), p.size * 2.4)
			draw_line(p.pos - tail * 0.6, p.pos, p.color.lightened(0.45), p.size)
		K_PELLET:
			draw_circle(p.pos, p.size * 1.7, Color(p.color, 0.3))
			draw_circle(p.pos, p.size, p.color.lightened(0.35))
		K_ROCKET:
			var dir := p.vel.normalized()
			var flick := randf_range(0.0, 3.0)
			draw_circle(p.pos - dir * (12.0 + p.size), p.size + 2.0 + flick, Color(1.0, 0.55, 0.1, 0.8))
			draw_line(p.pos - dir * (10.0 + p.size), p.pos, Color(0.85, 0.85, 0.88), p.size + 2.5)
			draw_circle(p.pos, p.size * 0.8 + 1.0, p.color)
		K_GRENADE, K_BOMBLET:
			draw_circle(p.pos, p.size + 2.5, Color(0.1, 0.1, 0.12))
			draw_circle(p.pos, p.size + 1.0, p.color.darkened(0.15))
			if fmod(p.age * 8.0, 1.0) < 0.5:
				draw_circle(p.pos, 2.0, Color(1.0, 0.25, 0.2))
		K_ORB:
			draw_circle(p.pos, p.size * 1.5, Color(p.color, 0.22))
			draw_circle(p.pos, p.size, p.color)
			draw_circle(p.pos, p.size * 0.45, Color(1, 1, 1, 0.9))
		K_ENEMY:
			draw_circle(p.pos, p.size + 3.0, Color(p.color, 0.3))
			draw_circle(p.pos, p.size, p.color)
			draw_circle(p.pos, p.size * 0.45, Color(1, 1, 1, 0.9))
			if p.homing > 0.0:   # самонаводящийся: кольцо-«прицел» вокруг, чтобы отличать от обычных
				draw_arc(p.pos, p.size + 6.0, 0.0, TAU, 16, Color(p.color, 0.85), 2.0)
