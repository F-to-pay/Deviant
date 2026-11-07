class_name Enemy
extends Actor
## Враг. Поведение выбирается по etype. Элитные аффиксы — как в Диабло.

const S_MOVE := 0
const S_WINDUP := 1
const S_ACTION := 2
const S_RECOVER := 3

var etype: String = "runner"
var def: Dictionary = {}
var level: int = 1
var dmg: float = 10.0
var speed: float = 100.0
var color: Color = Color.RED
var elite: int = 0          # 0 обычный, 1 чемпион, 2 редкий вожак, 3 босс
var affixes: Array = []
var title: String = ""
var aggro: bool = false
var awake: bool = false
var pack: int = -1
var knock: Vector2 = Vector2.ZERO
var state: int = S_MOVE
var st: float = 0.0
var atk_cd: float = 1.0
var contact_cd: float = 0.0
var los_t: float = 0.0
var has_los: bool = false
var move_los: bool = false
var strafe: float = 1.0
var charge_dir: Vector2 = Vector2.RIGHT
var tele_cd: float = 3.0
var tele_t: float = 0.0              # телеграф телепорта: сколько осталось до прыжка
var tele_pos: Vector2 = Vector2.ZERO # куда прыгнет
const TELE_WARN := 0.9
var shield_cd: float = 4.0
var shield_t: float = 0.0
var ring_cd: float = 3.0
var orbit_ang: float = 0.0
var summons: Array = []
var anim: float = 0.0
var look: Vector2 = Vector2.RIGHT
var _shield_msg_cd: float = 0.0


func setup(t: String, lvl: int, el: int, affs: Array) -> void:
	etype = t
	def = EnemyData.TYPES[t]
	level = lvl
	elite = el
	affixes = affs
	radius = def["r"]
	color = def["col"]
	speed = float(def["speed"]) * randf_range(0.92, 1.08)
	var hpm: float = Game.enemy_hp_mult(lvl)
	var dmgm: float = Game.enemy_dmg_mult(lvl)
	max_hp = float(def["hp"]) * hpm
	dmg = float(def["dmg"]) * dmgm
	if elite == 1:
		max_hp *= 3.0
		dmg *= 1.25
		radius *= 1.2
		status_resist = 1.5
	elif elite == 2:
		max_hp *= 5.0
		dmg *= 1.35
		radius *= 1.35
		status_resist = 2.0
	elif elite == 3:
		status_resist = 3.0
	if has_affix("tough"):
		max_hp *= 1.8
	if has_affix("fast"):
		speed *= 1.4
	hp = max_hp
	atk_cd = randf_range(0.6, 2.0)
	strafe = 1.0 if randf() < 0.5 else -1.0
	orbit_ang = randf() * TAU
	anim = randf() * 10.0
	if elite == 1 or elite == 2:
		title = EnemyData.elite_title(etype, elite, affixes, Game.rng)
	else:
		title = U.t(str(def["n"]))


func has_affix(a: String) -> bool:
	return a in affixes


func set_aggro() -> void:
	if aggro:
		return
	aggro = true
	# Будим весь пак
	if pack >= 0:
		for o in Game.main.enemies:
			var e: Enemy = o
			if e.pack == pack and not e.aggro and not e.dead:
				e.aggro = true


# --- Урон ---------------------------------------------------------------------

func hurt(amount: float, crit: bool, el: int, kb: Vector2, quiet: bool = false, st: float = 0.1) -> void:
	if dead:
		return
	var main: Main = Game.main
	if shield_t > 0.0:
		if _shield_msg_cd <= 0.0:
			_shield_msg_cd = 0.6
			main.fx.text(position + Vector2(0, -radius - 10.0), U.t("SHIELD"), Color(0.6, 0.85, 1.0), 14, 0.5)
		return
	var a := amount * vulnerability()
	hp -= a
	flash = 0.07
	set_aggro()
	if elite != 3:
		knock += kb * (7.0 / radius)
	if not quiet or crit:
		main.fx.damage_number(position + Vector2(0, -radius), a, crit, el)
	if el >= 0:
		apply_element(el, a, st)
	if hp <= 0.0:
		die()


func on_curse(amount: float) -> void:
	if dead:
		return
	Game.main.fx.ring(position, radius + 30.0, U.el_color(U.EL_CURSE), 0.4)
	Game.main.fx.death_burst(position, U.el_color(U.EL_CURSE), radius * 0.6)
	if amount > 0.0:
		on_dot(amount, U.EL_CURSE)


func on_dot(amount: float, el: int) -> void:
	if dead or shield_t > 0.0:
		return
	var a := amount * vulnerability()
	hp -= a
	Game.main.fx.damage_number(position + Vector2(0, -radius), a, false, el)
	if hp <= 0.0:
		die()


func die() -> void:
	if dead:
		return
	dead = true
	var main: Main = Game.main
	if has_affix("explosive"):
		main.projectiles.add_blast(position, 95.0, dmg * 1.2, 0.7, 1)
		_ring(12, 210.0, 0.0)
	main.on_enemy_killed(self)
	queue_free()


# --- Мозги ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		return
	var main: Main = Game.main
	var player: Player = main.player
	anim += delta
	if _shield_msg_cd > 0.0:
		_shield_msg_cd -= delta
	tick_status(delta)
	if dead:
		return
	if has_affix("regen") and hp < max_hp:
		hp = minf(max_hp, hp + max_hp * 0.02 * delta)
	if contact_cd > 0.0:
		contact_cd -= delta
	if knock.length_squared() > 1.0:
		position = main.zone.move_circle(position, knock * delta, radius)
		knock = knock.move_toward(Vector2.ZERO, 1800.0 * delta)
	var sm := slow_mult()
	if sm <= 0.0 or player == null or player.dead:
		queue_redraw()
		return
	var to_p := player.position - position
	var dist := to_p.length()
	if dist > 1.0:
		look = to_p / dist
	if not aggro:
		if dist < 600.0:
			set_aggro()
		else:
			queue_redraw()
			return
	var d2 := delta * sm
	if atk_cd > 0.0:
		atk_cd -= d2 * (1.4 if has_affix("fast") else 1.0)
	los_t -= delta
	if los_t <= 0.0:
		los_t = randf_range(0.18, 0.3)
		has_los = main.zone.ray_clear(position, player.position)
		move_los = has_los and main.zone.ray_clear(position, player.position, true)
	_tick_affixes(d2, player, dist)
	_behave(d2, player, to_p, dist)
	if dead:
		return
	# Контактный урон
	if dist < radius + player.radius + 2.0 and contact_cd <= 0.0:
		var k := 1.0 if etype == "runner" else 0.5
		player.take_damage(dmg * k)
		contact_cd = 0.8
	queue_redraw()


func _behave(delta: float, player: Player, to_p: Vector2, dist: float) -> void:
	match etype:
		"runner":
			_chase(delta, player, speed)
		"brute":
			_brute(delta, player, dist)
		"gunner":
			_ranged(delta, player, to_p, dist, 300.0)
			if has_los and dist < 650.0 and atk_cd <= 0.0:
				atk_cd = 1.3
				if has_affix("multishot"):
					_shoot_at(player.position, 3, 24.0, 400.0)
				else:
					_shoot_at(player.position, 1, 0.0, 400.0)
		"spreader":
			_ranged(delta, player, to_p, dist, 250.0)
			if has_los and dist < 560.0 and atk_cd <= 0.0:
				atk_cd = 1.9
				_shoot_at(player.position, 9 if has_affix("multishot") else 5, 70.0 if has_affix("multishot") else 50.0, 310.0)
		"bomber":
			_bomber(delta, player, dist)
		"charger":
			_charger(delta, player, to_p, dist)
		"mortar":
			_ranged(delta, player, to_p, dist, 440.0)
			if dist < 720.0 and atk_cd <= 0.0:
				atk_cd = 2.5
				var lead := player.vel * 0.45
				Game.main.projectiles.add_blast(player.position + lead, 75.0, dmg, 1.15, 1)
				if has_affix("multishot"):
					for i in 2:
						Game.main.projectiles.add_blast(player.position + Vector2.from_angle(randf() * TAU) * 110.0, 65.0, dmg, 1.4, 1)
		"summoner":
			_ranged(delta, player, to_p, dist, 420.0)
			_summoner(player)
		_:
			_chase(delta, player, speed)


func _chase(delta: float, player: Player, spd: float) -> void:
	var dir: Vector2
	if move_los:
		dir = (player.position - position).normalized()
	else:
		dir = Game.main.zone.flow_dir(position)
		if dir == Vector2.ZERO:
			dir = (player.position - position).normalized()
	_move(dir * spd, delta)


## Держим дистанцию, стрейфим.
func _ranged(delta: float, player: Player, to_p: Vector2, dist: float, want: float) -> void:
	if dist > want + 90.0 or not has_los:
		_chase(delta, player, speed)
	elif dist < want - 90.0:
		_move(-to_p.normalized() * speed * 0.85, delta)
	else:
		if randf() < delta * 0.5:
			strafe = -strafe
		_move(to_p.normalized().orthogonal() * strafe * speed * 0.6, delta)


func _brute(delta: float, player: Player, dist: float) -> void:
	match state:
		S_MOVE:
			if dist < radius + 70.0 and atk_cd <= 0.0:
				state = S_WINDUP
				Sfx.at("enemy/windup", position, -8.0, 1.0, 0.06, 2, 0.15)
				st = 0.55
			else:
				_chase(delta, player, speed)
		S_WINDUP:
			st -= delta
			if st <= 0.0:
				Combat.explode(position, 100.0, dmg * 1.6, false, -1, 1, 0.0)
				state = S_RECOVER
				st = 0.45
				atk_cd = 1.6
		S_RECOVER:
			st -= delta
			if st <= 0.0:
				state = S_MOVE


func _bomber(delta: float, player: Player, dist: float) -> void:
	if state == S_MOVE:
		if dist < radius + player.radius + 34.0:
			state = S_WINDUP
			Sfx.at("enemy/windup", position, -8.0, 1.0, 0.06, 2, 0.15)
			st = 0.45
		else:
			_chase(delta, player, speed)
	elif state == S_WINDUP:
		st -= delta
		if st <= 0.0:
			Combat.explode(position, 88.0, dmg, false, -1, 1, 0.0)
			dead = true
			Game.main.on_enemy_killed(self, false)
			queue_free()


func _charger(delta: float, player: Player, to_p: Vector2, dist: float) -> void:
	match state:
		S_MOVE:
			if has_los and move_los and dist < 400.0 and atk_cd <= 0.0:
				state = S_WINDUP
				Sfx.at("enemy/windup", position, -8.0, 1.0, 0.06, 2, 0.15)
				st = 0.7
				charge_dir = to_p.normalized()
			elif dist > 180.0:
				_chase(delta, player, speed)
			else:
				_move(to_p.normalized().orthogonal() * strafe * speed * 0.7, delta)
		S_WINDUP:
			st -= delta
			if st > 0.35:
				charge_dir = (player.position - position).normalized()
			if st <= 0.0:
				state = S_ACTION
				st = 0.5
		S_ACTION:
			st -= delta
			var before := position
			position = Game.main.zone.move_circle(position, charge_dir * speed * 4.2 * delta, radius)
			if position.distance_to(player.position) < radius + player.radius + 4.0 and contact_cd <= 0.0:
				player.take_damage(dmg * 1.5)
				contact_cd = 0.6
			if st <= 0.0 or position.distance_squared_to(before) < 1.0:
				state = S_RECOVER
				st = 0.8
				atk_cd = 2.0
		S_RECOVER:
			st -= delta
			if st <= 0.0:
				state = S_MOVE


func _summoner(_player: Player) -> void:
	var alive: Array = []
	for s in summons:
		if is_instance_valid(s) and not s.dead:
			alive.append(s)
	summons = alive
	if atk_cd <= 0.0:
		atk_cd = 4.0
		if summons.size() < 6:
			for i in 2:
				var p: Vector2 = Game.main.zone.random_free_near(position, 30.0, 70.0)
				var e: Enemy = Game.main.spawn_enemy("runner", p, level, 0, [], pack, true)
				summons.append(e)
			Game.main.fx.ring(position, 60.0, color)
			Sfx.at("enemy/summon", position, -6.0)
		else:
			_ring(8, 170.0, randf() * TAU)


func _tick_affixes(delta: float, player: Player, dist: float) -> void:
	if affixes.is_empty():
		return
	var main: Main = Game.main
	if has_affix("teleport"):
		if tele_t > 0.0:
			# телеграф: точка прыжка подсвечена TELE_WARN секунд, потом — прыжок
			tele_t -= delta
			if tele_t <= 0.0:
				main.fx.blink(position, tele_pos, Color(0.7, 0.4, 1.0))
				position = tele_pos
		else:
			tele_cd -= delta
			if tele_cd <= 0.0 and dist > 220.0:
				tele_cd = randf_range(4.0, 5.5)
				var np: Vector2 = main.zone.random_free_near(player.position, 150.0, 230.0)
				if np != player.position:
					tele_pos = np
					tele_t = TELE_WARN
					Sfx.at("enemy/shield", np, -10.0, 1.8, 0.05, 2, 0.2)
	if has_affix("shielded"):
		if shield_t > 0.0:
			shield_t -= delta
		else:
			shield_cd -= delta
			if shield_cd <= 0.0:
				shield_t = 1.8
				Sfx.at("enemy/shield", position, -9.0, 1.0, 0.05, 2, 0.2)
				shield_cd = 7.0
	if has_affix("frost") and dist < 170.0:
		player.chill = 0.35
	if has_affix("orbit"):
		orbit_ang += delta * 2.6
		for i in 3:
			var op := position + Vector2.from_angle(orbit_ang + TAU * float(i) / 3.0) * (radius + 34.0)
			if op.distance_to(player.position) < 9.0 + player.radius:
				player.take_damage(dmg * 0.6)
	if has_affix("multishot") and etype in ["runner", "brute", "bomber", "charger"]:
		ring_cd -= delta
		if ring_cd <= 0.0 and has_los:
			ring_cd = 3.2
			_ring(6, 200.0, randf() * TAU)


# --- Стрельба ------------------------------------------------------------------

func _bullet_col() -> Color:
	if elite == 2:
		return Color(1.0, 0.85, 0.3)
	if elite == 1:
		return Color(0.45, 0.65, 1.0)
	return Color(1.0, 0.32, 0.35)


func _shoot_at(target: Vector2, n: int, arc_deg: float, spd: float, size: float = 6.0) -> void:
	var base := (target - position).angle()
	var arc := deg_to_rad(arc_deg)
	for i in n:
		var a := base
		if n > 1:
			a = base - arc * 0.5 + arc * float(i) / float(n - 1)
		var dir := Vector2.from_angle(a)
		Game.main.projectiles.enemy_shot(position + dir * radius, dir, spd, dmg, size, _bullet_col())


func _ring(n: int, spd: float, offset: float, size: float = 6.0) -> void:
	for i in n:
		var dir := Vector2.from_angle(offset + TAU * float(i) / float(n))
		Game.main.projectiles.enemy_shot(position + dir * radius, dir, spd, dmg * 0.8, size, _bullet_col())


func _move(vel: Vector2, delta: float) -> void:
	var main: Main = Game.main
	var sep := Vector2.ZERO
	for o in main.grid_hash.query(position, radius + 30.0):
		if o == self:
			continue
		var e: Enemy = o
		var d := position - e.position
		var l := d.length()
		var min_d := radius + e.radius
		if l < min_d and l > 0.01:
			sep += d / l * (min_d - l) * 8.0
	position = main.zone.move_circle(position, (vel + sep) * delta, radius)


# --- Отрисовка ----------------------------------------------------------------

## Куда прыгнет телепортёр: сходящееся кольцо в точке назначения, силуэт и пунктир от врага.
func _draw_tele_warn() -> void:
	var k := 1.0 - tele_t / TELE_WARN          # 0 -> 1 к моменту прыжка
	var to := tele_pos - global_position
	var pc := Color(0.75, 0.45, 1.0)
	var blink_on := fmod(anim * 10.0, 1.0) < 0.5
	draw_circle(to, radius * 1.2, Color(pc, 0.12 + 0.18 * k))
	draw_arc(to, radius + 4.0 + 46.0 * (1.0 - k), 0.0, TAU, 28, Color(pc, 0.5 + 0.5 * k), 3.0)
	draw_arc(to, radius, 0.0, TAU, 20, Color(pc, 0.9 if blink_on else 0.5), 2.0)
	var n := 12
	for i in n:
		if i % 2 == 0:
			draw_line(to * (float(i) / n), to * (float(i + 1) / n), Color(pc, 0.35 * k + 0.15), 2.0)
	# сам враг мерцает перед прыжком
	if blink_on:
		draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 20, Color(pc, 0.8), 2.0)


func _draw() -> void:
	var col := color
	if flash > 0.0:
		col = Color.WHITE
	elif frozen_time > 0.0:
		col = Color(0.78, 0.95, 1.0)
	draw_circle(Vector2(0, radius * 0.55), radius * 0.9, Color(0, 0, 0, 0.25))
	if tele_t > 0.0:
		_draw_tele_warn()
	# Телеграфы атак
	if state == S_WINDUP:
		match etype:
			"brute":
				var k := 1.0 - st / 0.55
				draw_circle(Vector2.ZERO, 100.0, Color(1, 0.2, 0.15, 0.1))
				draw_circle(Vector2.ZERO, 100.0 * k, Color(1, 0.2, 0.15, 0.2))
				draw_arc(Vector2.ZERO, 100.0, 0.0, TAU, 36, Color(1, 0.3, 0.2, 0.8), 2.0)
			"charger":
				draw_line(Vector2.ZERO, charge_dir * speed * 4.2 * 0.5, Color(1, 0.2, 0.3, 0.35), radius * 2.0)
			"bomber":
				draw_arc(Vector2.ZERO, 88.0, 0.0, TAU, 32, Color(1, 0.3, 0.1, 0.7), 2.0)
				if fmod(anim * 12.0, 1.0) < 0.5:
					col = Color(1, 1, 1)
	# Аура элиток
	if elite == 1:
		draw_circle(Vector2.ZERO, radius + 7.0, Color(0.3, 0.55, 1.0, 0.18))
		draw_arc(Vector2.ZERO, radius + 7.0, 0.0, TAU, 32, Color(0.4, 0.65, 1.0, 0.8), 2.5)
	elif elite == 2:
		draw_circle(Vector2.ZERO, radius + 8.0, Color(1.0, 0.8, 0.2, 0.18))
		draw_arc(Vector2.ZERO, radius + 8.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.3, 0.9), 3.0)
	if has_affix("frost"):
		draw_circle(Vector2.ZERO, 170.0, Color(0.6, 0.9, 1.0, 0.06))
	# Тело
	var sides: int = def["sides"]
	var rot := anim * 0.8 if etype in ["summoner", "charger"] else look.angle()
	if sides <= 0:
		draw_circle(Vector2.ZERO, radius, col.darkened(0.15))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, col.lightened(0.3), 2.0)
	else:
		var pts := U.ngon(sides, radius, rot, bool(def["star"]))
		draw_colored_polygon(pts, col.darkened(0.15))
		draw_polyline(U.closed(pts), col.lightened(0.3), 2.0)
	# Глаз
	draw_circle(look * radius * 0.4, radius * 0.24, Color(1, 1, 1, 0.95))
	draw_circle(look * radius * 0.48, radius * 0.11, Color(0.05, 0.05, 0.05))
	draw_statuses(anim)
	if shield_t > 0.0:
		draw_circle(Vector2.ZERO, radius + 10.0, Color(0.5, 0.8, 1.0, 0.18))
		draw_arc(Vector2.ZERO, radius + 10.0, 0.0, TAU, 32, Color(0.6, 0.9, 1.0, 0.9), 2.0)
	if has_affix("orbit"):
		for i in 3:
			var op := Vector2.from_angle(orbit_ang + TAU * float(i) / 3.0) * (radius + 34.0)
			draw_circle(op, 8.0, Color(1.0, 0.4, 0.6))
			draw_circle(op, 4.0, Color(1, 1, 1))
	# Полоска HP
	if hp < max_hp:
		var bw := radius * 2.0 + 10.0
		var y := -radius - 12.0
		draw_rect(Rect2(-bw * 0.5, y, bw, 4.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-bw * 0.5, y, bw * clampf(hp / max_hp, 0.0, 1.0), 4.0), Color(0.95, 0.25, 0.25))
	if elite == 1 or elite == 2:
		var tc := Color(0.55, 0.75, 1.0) if elite == 1 else Color(1.0, 0.85, 0.3)
		U.draw_text_c(self, U.font_bold(), Vector2(0, -radius - 18.0), title, 13, tc, 3)
