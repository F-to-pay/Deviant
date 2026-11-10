class_name AntiPlayer
extends Boss
## Антиигрок — босс-«зеркало»: стреляет из лучшей пушки, найденной игроком (Game.best_gun), и пользуется навыком его героя.
## Держится на эффективной дальности пушки, но не дальше 15 м (MAX_RANGE), пятится, если подошли вплотную,
## уходит рывками. Здоровье — как у мобов: растёт с зоной (Game.enemy_hp_mult). Появляется вместо обычного босса (roll).
## Урон его пушки нормирован: устойчивый урон в секунду ≈ урон босса × GUN_DPS_K (иначе пушка за 200 урона убивала бы с трёх выстрелов).
## Навык героя: граната — мина с задержкой под игроком, благословение — следующий залп втрое сильнее, удар — рубит вплотную
## с замахом. Перки навыков не копируются. Стрелять из пушек с миной / взрывом — через Projectiles (team 1).

const ANTI_MIN_ZONE := 10          # с какой боссовой зоны может появиться
const ANTI_CHANCE := 0.5           # шанс вместо обычного босса
const MAX_RANGE := 600.0           # 15 м: 40 пикселей на метр
const GUN_DPS_K := 2.5
const FIRE_RATE_CAP := 7.0         # выстрелов в секунду не больше (дальше пушка стреляла бы сплошной стеной)
const HP_BASE := 3400.0
const HP_DIV := 15.0               # урон и подвижность у него были слишком сильными — здоровье урезано в 15 раз
const MOVE_SPEED := 150.0
const DASH_SPEED := 760.0
const DASH_TIME := 0.18
const DASH_CD := 3.5
const BLESS_MULT := 3.0
const SLASH_R := 95.0
const SLASH_ARC := 130.0
const SLASH_WINDUP := 0.35
const SLASH_CD := 3.5

var gun_ref: Gun = null
var hero_id: String = ""
var mag_cap: int = 1
var mag_left: int = 1
var reload_left: float = 0.0
var fire_cd: float = 1.0
var skill_cd: float = 3.0
var dash_cd: float = 2.0
var dash_t: float = 0.0
var dash_dir: Vector2 = Vector2.RIGHT
var blessed: bool = false
var slash_w: float = 0.0
var slash_dir: Vector2 = Vector2.RIGHT
var strafe_t: float = 0.0
var dmg_mult: float = 1.0


## Выпал ли Антиигрок на этой боссовой зоне.
static func roll(level: int, rng: RandomNumberGenerator) -> bool:
	return level >= ANTI_MIN_ZONE and Game.best_gun != null and rng.randf() < ANTI_CHANCE


func setup_anti(lvl: int, rng: RandomNumberGenerator) -> void:
	setup_boss(lvl, rng)    # тело, урон по зоне, имя; набор паттернов Boss здесь не используется
	patterns = []
	radius = 15.0
	speed = MOVE_SPEED
	max_hp = HP_BASE * Game.enemy_hp_mult(lvl) / HP_DIV
	hp = max_hp
	title = U.t("Anti-Player")
	hero_id = Game.main.player.hero
	var hc := Heroes.color(hero_id)
	color = Color.from_hsv(fposmod(hc.h + 0.5, 1.0), clampf(hc.s, 0.3, 0.9), 0.85)   # цвет героя наизнанку
	gun_ref = Game.best_gun
	var g := gun_ref
	var fr := minf(g.fire_rate, FIRE_RATE_CAP)
	dmg_mult = dmg * GUN_DPS_K / maxf(1.0, g.dps()) * g.fire_rate / fr
	mag_cap = clampi(g.mag_size / maxi(1, g.ammo_per_shot), 1, 40)
	mag_left = mag_cap
	rest = 0.0


func _check_enrage() -> void:
	if not enraged and hp < max_hp * 0.5:
		enraged = true
		Game.say(U.t("%s is enraged!") % title, Color(1.0, 0.35, 0.25))
		Game.main.fx.shake(10.0)
		Sfx.ui("boss/enrage", -2.0)
		_ring(16, 220.0, 0.0, 7.0)


func _behave(delta: float, player: Player, to_p: Vector2, dist: float) -> void:
	var g := gun_ref
	if g == null:
		return
	_check_enrage()
	var rate_k := 1.3 if enraged else 1.0
	var dir := to_p.normalized()
	# замах удара: стоит на месте, потом рубит
	if slash_w > 0.0:
		slash_w -= delta
		if slash_w <= 0.0:
			_slash_strike(player)
		return
	# рывок
	if dash_t > 0.0:
		dash_t -= delta
		position = Game.main.zone.move_circle(position, dash_dir * DASH_SPEED * delta, radius)
		return
	fire_cd -= delta * rate_k
	skill_cd -= delta * rate_k
	dash_cd -= delta * rate_k
	strafe_t -= delta
	if strafe_t <= 0.0:
		strafe = -strafe
		strafe_t = randf_range(0.8, 2.0)
	var range_max := minf(g.eff_range(), MAX_RANGE)
	var pref := range_max * 0.8
	var near := range_max * 0.35
	# движение: подойти / пятиться / крутиться на дистанции
	if not has_los or dist > pref + 40.0:
		_chase(delta, player, speed)
	elif dist < near:
		_move(-dir * speed * 0.9, delta)
	else:
		_move(dir.orthogonal() * strafe * speed * 0.6, delta)
	# рывок: прочь, если подошли вплотную, иначе иногда в сторону
	if dash_cd <= 0.0 and (dist < near * 0.8 or (has_los and randf() < delta * 0.35)):
		var away := dist < near * 0.8
		var base_dir := -dir if away else dir.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
		for off in [0.0, 0.6, -0.6, 1.2, -1.2]:
			var d := base_dir.rotated(float(off))
			if _clear_len(d, 140.0) >= 110.0:
				dash_dir = d
				dash_t = DASH_TIME
				dash_cd = DASH_CD
				Game.main.fx.ring(position, radius + 12.0, color, 0.25)
				break
	# навык героя
	if skill_cd <= 0.0 and has_los:
		_cast(player, dist, dir, range_max)
	# выстрел
	if reload_left > 0.0:
		reload_left -= delta
	elif fire_cd <= 0.0 and has_los and dist <= range_max:
		_shoot(player, dist)


func _shoot(player: Player, dist: float) -> void:
	var g := gun_ref
	var main: Main = Game.main
	var lead := player.vel * clampf(dist / maxf(100.0, g.proj_speed), 0.0, 0.6) * 0.6
	var dir := (player.position + lead - position).normalized()
	var base := dir.angle()
	var spr := deg_to_rad(g.spread) + 0.04
	var n := g.pellets
	var mpos := position + dir * (radius + 10.0)
	var mult := dmg_mult * (BLESS_MULT if blessed else 1.0)
	if g.proj_kind == GunData.K_SHELL:
		# миномёт: мины с задержкой вокруг игрока (как Бомбёжка), а не снаряды, летящие по полу
		var dev := dist * tan(clampf(spr * 0.5, 0.0, 1.2))
		for i in n:
			var off := Vector2.from_angle(randf() * TAU) * dev * sqrt(randf())
			main.projectiles.add_blast(player.position + off, maxf(50.0, g.explode_r), g.damage * mult, 1.0, 1)
	else:
		for i in n:
			var a := base
			if n > 1:
				a += lerpf(-spr * 0.5, spr * 0.5, (float(i) + 0.5) / float(n)) + randf_range(-0.08, 0.08) * spr
			else:
				a += randf_range(-spr * 0.5, spr * 0.5)
			main.projectiles.fire_gun(g, mpos, Vector2.from_angle(a), 1, mult)
	if blessed:
		blessed = false
		main.fx.ring(mpos, 24.0, Color(1.0, 0.8, 0.3), 0.3)
	main.fx.muzzle_flash(mpos, dir, g.proj_color)
	main.sfx.gun_shot(g, mpos)
	mag_left -= 1
	fire_cd = 1.0 / minf(g.fire_rate, FIRE_RATE_CAP)
	if mag_left <= 0:
		mag_left = mag_cap
		reload_left = minf(g.reload_time, 2.5)


func _cast(player: Player, dist: float, dir: Vector2, range_max: float) -> void:
	var h := Heroes.get_hero(hero_id)
	var main: Main = Game.main
	match str(h["skill"]):
		"grenade":
			if dist > 650.0:
				return
			skill_cd = float(h["cd"]) * 0.8
			var n := 3 if enraged else 1
			for i in n:
				var off := Vector2.ZERO if i == 0 else Vector2.from_angle(randf() * TAU) * randf_range(60.0, 130.0)
				main.projectiles.add_blast(player.position + player.vel * 0.5 + off, 70.0, dmg * 1.6, 0.9, 1)
			Sfx.at("player/dodge", position, -6.0, 1.4, 0.06, 1, 0.1)
		"bless":
			if dist > range_max:
				return
			skill_cd = float(h["cd"])
			blessed = true
			main.fx.ring(position, 34.0, Color(1.0, 0.8, 0.3), 0.4)
			Sfx.at("player/perfect", position, -6.0, 0.7, 0.04, 1, 0.1)
		"slash":
			if dist > SLASH_R + 30.0:
				return
			skill_cd = SLASH_CD
			slash_w = SLASH_WINDUP
			slash_dir = dir


func _slash_strike(player: Player) -> void:
	var main: Main = Game.main
	main.fx.ring(position, SLASH_R, Heroes.color(hero_id), 0.25)
	Sfx.at("player/dodge", position, -5.0, 1.6, 0.08, 2, 0.05)
	var to := player.position - position
	var half := deg_to_rad(SLASH_ARC) * 0.5
	if to.length() <= SLASH_R + player.radius and (to.length() < radius + player.radius or absf(slash_dir.angle_to(to)) <= half):
		if player.take_damage(dmg * 2.2):
			main.fx.shake(5.0)


func _draw() -> void:
	var col := color
	if flash > 0.0:
		col = Color.WHITE
	elif frozen_time > 0.0:
		col = Color(0.78, 0.95, 1.0)
	draw_circle(Vector2(0, 9), 13.0, Color(0, 0, 0, 0.3))
	if enraged:
		draw_circle(Vector2.ZERO, radius + 12.0 + sin(anim * 8.0) * 3.0, Color(1.0, 0.2, 0.1, 0.18))
	if blessed:
		draw_circle(Vector2.ZERO, radius + 8.0, Color(1.0, 0.8, 0.3, 0.22))
		draw_arc(Vector2.ZERO, radius + 8.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.4, 0.8), 2.0)
	if dash_t > 0.0:
		for i in 3:
			draw_circle(-dash_dir * float(i + 1) * 10.0, radius * (0.9 - 0.2 * float(i)), Color(col, 0.25 - 0.07 * float(i)))
	if slash_w > 0.0:
		# предупреждение об ударе: сектор наливается к моменту удара
		var k := 1.0 - clampf(slash_w / SLASH_WINDUP, 0.0, 1.0)
		var half := deg_to_rad(SLASH_ARC) * 0.5
		var pts := PackedVector2Array([Vector2.ZERO])
		for s in 13:
			pts.append(Vector2.from_angle(slash_dir.angle() - half + half * 2.0 * float(s) / 12.0) * SLASH_R)
		draw_colored_polygon(pts, Color(1.0, 0.2, 0.2, 0.12 + 0.3 * k))
		draw_arc(Vector2.ZERO, SLASH_R, slash_dir.angle() - half, slash_dir.angle() + half, 20, Color(1.0, 0.3, 0.3, 0.8), 2.0)
	var bob := sin(anim * 14.0) * 1.5
	draw_circle(Vector2(0, bob), radius, col.darkened(0.2))
	draw_arc(Vector2(0, bob), radius, 0.0, TAU, 24, col.lightened(0.4), 2.5)
	draw_arc(Vector2(0, bob), radius * 0.6, look.angle() - 0.7, look.angle() + 0.7, 10, Color(1, 1, 1, 0.9), 4.0)
	if gun_ref != null:
		var hand := look * 12.0 + Vector2(0, bob + 2.0)
		GunIcon.draw_gun(self, gun_ref, hand, 0.38, look.angle(), look.x < 0.0, false)
	if reload_left > 0.0:
		draw_arc(Vector2(0, bob), radius + 8.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(1.0 - reload_left / 2.5, 0.0, 1.0), 24, Color(1, 1, 1, 0.8), 3.0)
	draw_statuses(anim)
