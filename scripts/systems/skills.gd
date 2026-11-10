class_name Skills
extends RefCounted
## Попадание навыком героя и все перки, которые на него влияют (Heroes.PERKS):
## стихия, опасные раны, яд (отложенный урон), оглушение тяжёлого снаряда, отбрасывание вандализма,
## трофеи (через Player.on_skill_kill), готовность (Player.on_skill_damage).
## Сюда приходят: удар Ассасина, граната и дым Первопроходца, пули благословлённого выстрела Шерифа.

const WOUND_STEP := 0.1
const WOUND_MAX := 0.3
const POISON_DELAY := 5.0
const POISON_DELAY_MORE := 2.0
const STUN := 0.7
const STUN_MORE := 0.4
const VANDAL_KNOCK := 10.0
const SMOKE_R := 300.0
const SMOKE_TICK := 0.25     # доля урона гранаты за секунду дыма
const SMOKE_RATE := 5.0      # тиков дыма в секунду (урон и стихия делятся на них)
const SMOKE_TIME := 4.0
## Стихия навыка — как у обычной пушки: шанс наложить на попадание = 0.35 (шанс пушки по умолчанию), а накопление
## (кислота, холод, проклятие) зависит от «скорострельности» навыка: пушка копит 0.1 за секунду стрельбы,
## навык — 0.1 за секунду своей перезарядки на одно попадание (skill_st). Шанс общий для всех стихий, включая огонь;
## огонь не копится, поэтому сила его поджога (45% урона попадания в секунду) от перезарядки не зависит.
const SKILL_ELEM_CHANCE := 0.35


## Сколько стихии даёт одно попадание навыком: 0.1 × перезарядка навыка (с «Тяжёлым снарядом» — с учётом его +1 с).
static func skill_st(p: Player) -> float:
	return 0.1 * p.skill_max_cd()


## Ударить врага навыком. stun — можно ли оглушить (у дыма — только на первом тике).
## st — сколько стихии накладывает удар; tick — тик дыма: без цифр урона и без цепных молний шока.
## st < 0 — по умолчанию (skill_st); у тиков дыма накопление уже пересчитано и шанс не бросается.
static func hit(e: Enemy, dmg: float, kb: Vector2, stun: bool = true, st: float = -1.0, tick: bool = false) -> void:
	if e == null or e.dead:
		return
	var p: Player = Game.main.player
	if st < 0.0:
		st = skill_st(p)
	var el := p.skill_element
	# шанс стихии как у пушек; тики дыма — без броска (там шанс уже учтён в накоплении, а огонь за 3 с и так держится)
	if el >= 0 and not tick and randf() >= SKILL_ELEM_CHANCE:
		el = -1
	if p.perk("vandal") > 0:
		kb *= VANDAL_KNOCK
	var poison := p.perk("poison")
	if poison > 0:
		# урон ляжет позже; сейчас — только отбрасывание, стихия и агр
		e.delay_damage(dmg, POISON_DELAY + POISON_DELAY_MORE * float(poison - 1), el)
		e.set_aggro()
		if e.elite != 3:
			e.knock += kb * (7.0 / e.radius)
		if el >= 0:
			e.apply_element(el, dmg, st)
		if not tick:
			Game.main.fx.text(e.position + Vector2(0, -e.radius - 6.0), U.fmt(dmg * e.vulnerability()), Color(0.45, 1.0, 0.3, 0.8), 12, 0.5)
	elif tick:
		e.hurt(dmg, false, el, kb, true, st)
	else:
		Combat.hit_enemy(e, dmg, false, el, kb, false, st)
	var w := p.perk("wounds")
	if w > 0 and not e.dead:
		# элиткам нужно вдвое больше ударов на ступень, боссам — втрое
		var k := 1.0 if e.elite == 0 else (2.0 if e.elite < 3 else 3.0)
		e.wound = minf(WOUND_MAX, e.wound + WOUND_STEP / k)
	var hv := p.perk("heavy")
	if hv > 0 and stun and not e.dead:
		e.stun_time = maxf(e.stun_time, (STUN + STUN_MORE * float(hv - 1)) / e.status_resist)
		e.shock_time = maxf(e.shock_time, 0.15)
	p.on_skill_damage()
	if e.dead:
		p.on_skill_kill(e)


## Взрыв навыка (граната Первопроходца, ракета благословлённого выстрела). У гранаты урон по всему радиусу
## одинаковый, у взрывов Шерифа — от центра к краю 100% → 20%, как у обычных взрывов.
## С «Дымовой гранатой» вместо взрыва — облако дыма (Projectiles.add_smoke).
static func explode(pos: Vector2, r: float, dmg: float, col: Color) -> void:
	var main: Main = Game.main
	var p: Player = main.player
	var sm := p.perk("smoke")
	if sm > 0:
		main.projectiles.add_smoke(pos, SMOKE_R, dmg * SMOKE_TICK / SMOKE_RATE, SMOKE_TIME + float(sm - 1),
			1.0 / SMOKE_RATE, skill_st(p) * SKILL_ELEM_CHANCE / SMOKE_RATE)
		main.fx.ring(pos, 60.0, Color(0.75, 0.75, 0.8), 0.4)
		Sfx.at("player/dodge", pos, -4.0, 0.5, 0.06, 2, 0.1)
		return
	var flat := str(Heroes.get_hero(p.hero).get("skill", "")) == "grenade"
	var ecol := U.el_color(p.skill_element) if p.skill_element >= 0 else col
	main.fx.explosion(pos, r, ecol)
	main.sfx.explosion(pos, r, false)
	main.fx.shake(minf(2.0 + r / 30.0, 9.0))
	for o in main.grid_hash.query(pos, r + 50.0):
		var e: Enemy = o
		if e.dead:
			continue
		var dist := pos.distance_to(e.position)
		if dist > r + e.radius:
			continue
		var k := 1.0 if flat else lerpf(1.0, 0.2, clampf(dist / r, 0.0, 1.0))
		var dir := (e.position - pos) / dist if dist > 1.0 else Vector2.RIGHT
		hit(e, dmg * k, dir * 180.0)
	# своя граната задевает и героя — как любой свой взрыв (Combat.SELF_DAMAGE)
	if not p.dead and p.dodge_t <= 0.0 and pos.distance_to(p.position) < r + p.radius * 0.6:
		p.hurt_dot(dmg * Combat.SELF_DAMAGE, -1)
