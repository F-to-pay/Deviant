class_name Boss
extends Enemy
## Босс каждые 5 зон. Набор паттернов случайный, на 50% HP — ярость.

const PATTERNS := ["radial", "spiral", "shotgun", "charge", "summon", "mortar", "wall"]
const DURATION := {"radial": 3.0, "spiral": 3.5, "shotgun": 3.0, "charge": 5.0, "summon": 0.6, "mortar": 2.6, "wall": 3.6}

var patterns: Array = []
var pat: String = ""
var pat_t: float = 0.0
var shot_t: float = 0.0
var spiral_a: float = 0.0
var enraged: bool = false
var rest: float = 2.0
var charges: int = 0


func setup_boss(lvl: int, rng: RandomNumberGenerator) -> void:
	setup("brute", lvl, 3, [])
	radius = 46.0
	var hpm: float = Game.enemy_hp_mult(lvl)
	var dmgm: float = Game.enemy_dmg_mult(lvl)
	max_hp = 3200.0 * hpm
	hp = max_hp
	dmg = 16.0 * dmgm
	speed = 85.0
	color = Color.from_hsv(rng.randf(), 0.65, 0.9)
	title = EnemyData.boss_name(rng)
	var pool: Array = PATTERNS.duplicate()
	U.shuffle(pool, rng)
	patterns = pool.slice(0, mini(3 + lvl / 10, pool.size()))
	# Чардж всегда в наборе — иначе босс превращается в турель.
	if not ("charge" in patterns):
		patterns[0] = "charge"
	awake = true
	aggro = true
	rest = 2.5  # даём осмотреться перед мясом


func _behave(delta: float, player: Player, to_p: Vector2, dist: float) -> void:
	var rate_k := 1.35 if enraged else 1.0
	if not enraged and hp < max_hp * 0.5:
		enraged = true
		Game.say(U.t("%s is enraged!") % title, Color(1.0, 0.35, 0.25))
		Game.main.fx.shake(10.0)
		Sfx.ui("boss/enrage", -2.0)
		_ring(24, 240.0, 0.0, 7.0)
	if pat == "":
		rest -= delta
		if dist > 240.0:
			_chase(delta, player, speed * 0.7)
		else:
			_move(to_p.normalized().orthogonal() * strafe * speed * 0.6, delta)
		if rest <= 0.0:
			pat = patterns[randi() % patterns.size()]
			pat_t = float(DURATION[pat])
			shot_t = 0.2
			state = S_MOVE
			st = 0.0
			charges = 3 if not enraged else 4
		return
	pat_t -= delta
	shot_t -= delta * rate_k
	match pat:
		"radial":
			if shot_t <= 0.0:
				shot_t = 0.55
				_ring(24 if enraged else 16, 230.0, spiral_a, 7.0)
				spiral_a += 0.2
			_chase(delta, player, speed * 0.3)
		"spiral":
			if shot_t <= 0.0:
				shot_t = 0.07
				var arms := 3 if enraged else 2
				for k in arms:
					var dir := Vector2.from_angle(spiral_a + TAU * float(k) / float(arms))
					Game.main.projectiles.enemy_shot(position + dir * radius, dir, 210.0, dmg * 0.8, 6.0, Color(1.0, 0.45, 0.8))
				spiral_a += 0.23
		"shotgun":
			if shot_t <= 0.0:
				shot_t = 0.85
				_shoot_at(player.position, 11, 70.0, 300.0)
				_shoot_at(player.position, 7, 40.0, 220.0, 8.0)
			_chase(delta, player, speed * 0.8)
		"charge":
			_boss_charge(delta, player, to_p, dist)
		"summon":
			if state == S_MOVE:
				state = S_ACTION
				var n := 4 if not enraged else 6
				for i in n:
					var t := EnemyData.pick_type(level, Game.rng, ["summoner", "mortar"])
					var p: Vector2 = Game.main.zone.random_free_near(position, 60.0, 140.0)
					Game.main.spawn_enemy(t, p, level, 0, [], -1, true)
				Game.main.fx.ring(position, 120.0, color, 0.5)
				_ring(12, 190.0, randf() * TAU)
		"mortar":
			if shot_t <= 0.0:
				shot_t = 0.3
				var off := Vector2.from_angle(randf() * TAU) * randf_range(0.0, 130.0)
				Game.main.projectiles.add_blast(player.position + off, 70.0, dmg * 1.4, 1.0, 1)
		"wall":
			if shot_t <= 0.0:
				shot_t = 1.1
				_wall(player)
	if pat_t <= 0.0 or (pat == "charge" and charges <= 0 and state == S_MOVE):
		pat = ""
		rest = randf_range(0.6, 1.1) / rate_k
		state = S_MOVE


func _boss_charge(delta: float, player: Player, to_p: Vector2, _dist: float) -> void:
	match state:
		S_MOVE:
			if charges > 0:
				state = S_WINDUP
				st = 0.6
				charge_dir = to_p.normalized()
		S_WINDUP:
			st -= delta
			if st > 0.3:
				charge_dir = (player.position - position).normalized()
			if st <= 0.0:
				state = S_ACTION
				st = 0.55
		S_ACTION:
			st -= delta
			var before := position
			position = Game.main.zone.move_circle(position, charge_dir * speed * 5.5 * delta, radius)
			if position.distance_to(player.position) < radius + player.radius and contact_cd <= 0.0:
				player.take_damage(dmg * 2.0)
				contact_cd = 0.5
			if st <= 0.0 or position.distance_squared_to(before) < 1.0:
				state = S_RECOVER
				st = 0.35
				charges -= 1
				_ring(10, 200.0, randf() * TAU)
				Game.main.fx.shake(6.0)
		S_RECOVER:
			st -= delta
			if st <= 0.0:
				state = S_MOVE


## Стена пуль с дыркой — ищи проход.
func _wall(player: Player) -> void:
	var dir := (player.position - position).normalized()
	var perp := dir.orthogonal()
	var n := 24
	var gap := randi_range(4, n - 7)
	for i in n:
		if i >= gap and i < gap + 3:
			continue
		var off := (float(i) - float(n) * 0.5) * 26.0
		Game.main.projectiles.enemy_shot(position + perp * off + dir * radius, dir, 170.0, dmg, 7.0, Color(1.0, 0.6, 0.2))


func _draw() -> void:
	var col := color
	if flash > 0.0:
		col = Color.WHITE
	elif frozen_time > 0.0:
		col = Color(0.78, 0.95, 1.0)
	draw_circle(Vector2(0, radius * 0.5), radius * 0.95, Color(0, 0, 0, 0.3))
	if enraged:
		draw_circle(Vector2.ZERO, radius + 18.0 + sin(anim * 8.0) * 4.0, Color(1.0, 0.2, 0.1, 0.18))
	if pat == "charge" and state == S_WINDUP:
		draw_line(Vector2.ZERO, charge_dir * speed * 5.5 * 0.55, Color(1, 0.2, 0.2, 0.3), radius * 2.0)
	# Шипастое тело
	var pts := U.ngon(9, radius, anim * 0.6, true)
	for i in pts.size():
		if i % 2 == 1:
			pts[i] = pts[i] * 1.5
	draw_colored_polygon(pts, col.darkened(0.25))
	draw_polyline(U.closed(pts), col.lightened(0.3), 3.0)
	draw_circle(Vector2.ZERO, radius * 0.75, col.darkened(0.05))
	# Корона
	for i in 3:
		var x := (float(i) - 1.0) * 16.0
		draw_colored_polygon(PackedVector2Array([Vector2(x - 8, -radius * 0.7), Vector2(x + 8, -radius * 0.7),
			Vector2(x, -radius * 0.7 - 18.0)]), Color(1.0, 0.85, 0.25))
	# Глаз
	draw_circle(look * radius * 0.3, radius * 0.3, Color(1, 1, 1))
	draw_circle(look * radius * 0.38, radius * 0.14, Color(0.8, 0.05, 0.05) if enraged else Color(0.05, 0.05, 0.05))
	draw_statuses(anim)
