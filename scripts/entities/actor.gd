class_name Actor
extends Node2D
## База для всего, что живёт и умирает: здоровье и стихийные статусы.
##  Огонь — урон со временем. Шок — мгновенная цепь (в Combat).
##  Кислота и холод копятся ЛИНЕЙНО: секунда стрельбы любой пушкой даёт +10%
##  (каждое попадание — 10% / выстрелов в секунду). Элитки и боссы делят набор на status_resist.
##  Кислота: +уязвимость до 50%. Холод: замедление до 40%, на 50% — заморозка.
##  Проклятие: копится в 4 раза быстрее (+40%/с); на 100% бьёт на CURSE_HIT от потерянного
##  здоровья и обнуляется. status_resist режет и скорость набора, и урон.

const ACID_MAX := 0.5
const CRYO_SLOW_MAX := 0.4
const CRYO_FREEZE := 0.5
const CURSE_RATE := 0.4      # доля шкалы за секунду попаданий
const CURSE_HIT := 0.3       # доля потерянного здоровья
const STUN_TIME := 0.5       # электричество: стан
const STUN_IMMUNE := 1.0     # после стана — иммунитет, чтобы не держать врага в вечном стане

var radius: float = 14.0
var max_hp: float = 100.0
var hp: float = 100.0
var dead: bool = false
var flash: float = 0.0

var burn_dps: float = 0.0
var burn_time: float = 0.0
var acid: float = 0.0        # доп. уязвимость, 0..ACID_MAX
var acid_time: float = 0.0
var cryo: float = 0.0        # накопленный холод, 0..CRYO_FREEZE
var cryo_time: float = 0.0
var curse: float = 0.0       # шкала проклятия, 0..1
var curse_time: float = 0.0
var frozen_time: float = 0.0
var shock_time: float = 0.0
var stun_time: float = 0.0
var _stun_cd: float = 0.0
var status_resist: float = 1.0   # 1 — обычный, больше — стаки копятся медленнее
var wound: float = 0.0           # «Опасные раны» (перк навыка): вечное замедление, до 0.3
var delayed: Array = []          # «Ядовитый снаряд»: отложенный урон [осталось секунд, урон, стихия]
var _burn_tick: float = 0.0


func vulnerability() -> float:
	return 1.0 + acid


func slow_mult() -> float:
	if frozen_time > 0.0 or stun_time > 0.0:
		return 0.0
	return (1.0 - minf(cryo, CRYO_SLOW_MAX)) * (1.0 - wound)


## Отложенный урон навыка (перк «Ядовитый снаряд/разрез»): ляжет через t секунд.
func delay_damage(dmg: float, t: float, el: int) -> void:
	delayed.append([t, dmg, el])


## st — сколько кислоты/холода добавляет попадание (0.1 = секунда стрельбы).
func apply_element(el: int, hit_dmg: float, st: float = 0.1) -> void:
	if el == U.EL_FIRE:
		var cur := burn_dps if burn_time > 0.0 else 0.0
		if burn_time <= 0.0:
			Sfx.at("el/fire", position, -10.0, 1.0, 0.08, 3, 0.08)
		burn_dps = maxf(cur, hit_dmg * 0.45)
		burn_time = 3.0
	elif el == U.EL_ACID:
		if acid <= 0.0:
			Sfx.at("el/acid", position, -11.0, 1.0, 0.1, 3, 0.08)
		acid = minf(ACID_MAX, acid + st / status_resist)
		acid_time = 3.0
	elif el == U.EL_CRYO:
		if frozen_time <= 0.0:
			cryo += st / status_resist
			cryo_time = 3.0
			if cryo >= CRYO_FREEZE:
				cryo = 0.0
				frozen_time = 1.3
				Sfx.at("el/cryo", position, -6.0, 1.0, 0.08, 3, 0.06)
	elif el == U.EL_CURSE:
		curse += st * (CURSE_RATE / 0.1) / status_resist
		curse_time = 3.0
		if curse >= 1.0:
			curse = 0.0
			Sfx.at("el/curse", position, -6.0, 1.0, 0.08, 2, 0.1)
			var missing := maxf(0.0, max_hp - hp)
			on_curse(missing * CURSE_HIT / status_resist)
	elif el == U.EL_SHOCK:
		shock_time = 0.35
		if _stun_cd <= 0.0:
			# стан короче у элиток/боссов; иммунитет у них, наоборот, длиннее
			stun_time = STUN_TIME / status_resist
			Sfx.at("el/shock", position, -10.0, 1.0, 0.1, 3, 0.06)
			_stun_cd = stun_time + STUN_IMMUNE * status_resist
			shock_time = maxf(shock_time, stun_time)


func tick_status(delta: float) -> void:
	if flash > 0.0:
		flash -= delta
	if burn_time > 0.0:
		burn_time -= delta
		_burn_tick -= delta
		if _burn_tick <= 0.0:
			_burn_tick = 0.33
			on_dot(burn_dps * 0.33, U.EL_FIRE)
	if acid_time > 0.0:
		acid_time -= delta
		if acid_time <= 0.0:
			acid = 0.0
	if cryo_time > 0.0:
		cryo_time -= delta
		if cryo_time <= 0.0:
			cryo = 0.0
	if curse_time > 0.0:
		curse_time -= delta
		if curse_time <= 0.0:
			curse = 0.0
	if frozen_time > 0.0:
		frozen_time -= delta
	if shock_time > 0.0:
		shock_time -= delta
	if stun_time > 0.0:
		stun_time -= delta
	if _stun_cd > 0.0:
		_stun_cd -= delta
	if not delayed.is_empty():
		_tick_delayed(delta)


func _tick_delayed(delta: float) -> void:
	var keep: Array = []
	var land := 0.0
	var el := -1
	for d in delayed:
		d[0] = float(d[0]) - delta
		if float(d[0]) <= 0.0:
			land += float(d[1])
			el = int(d[2])
		else:
			keep.append(d)
	delayed = keep
	if land > 0.0 and not dead:
		on_dot(land, el)
		if dead and Game.main != null:
			Game.main.player.on_skill_kill(self)


## Переопределяется наследниками.
func on_dot(_amount: float, _el: int) -> void:
	pass


## Срабатывание проклятия: по умолчанию — как DoT.
func on_curse(amount: float) -> void:
	if amount > 0.0:
		on_dot(amount, U.EL_CURSE)


## Мелкие индикаторы статусов вокруг тела.
func draw_statuses(t: float) -> void:
	if burn_time > 0.0:
		for i in 3:
			var a := t * 6.0 + float(i) * 2.1
			draw_circle(Vector2(cos(a) * radius * 0.6, -radius * 0.4 - fmod(t * 30.0 + float(i) * 7.0, 14.0)), 3.0,
				Color(1.0, 0.5 + 0.2 * float(i % 2), 0.1, 0.8))
	if acid > 0.0:
		draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU * acid / ACID_MAX, 20, U.el_color(U.EL_ACID), 2.0)
	if curse > 0.0:
		draw_arc(Vector2.ZERO, radius + 7.0, -PI * 0.5, -PI * 0.5 + TAU * curse, 24, U.el_color(U.EL_CURSE), 2.5)
	if cryo > 0.0 or frozen_time > 0.0:
		var n := 5 if frozen_time > 0.0 else mini(5, int(cryo * 10.0) + 1)
		for i in n:
			var a := TAU * float(i) / 5.0 - PI * 0.5
			draw_circle(Vector2.from_angle(a) * (radius + 6.0), 2.5, U.el_color(U.EL_CRYO))
	if wound > 0.0:
		draw_arc(Vector2(0, 2), radius + 2.0, PI * 0.15, PI * 0.15 + PI * 0.7 * wound / 0.3, 12, Color(0.75, 0.05, 0.1, 0.9), 3.0)
	if not delayed.is_empty():
		var pulse := 0.5 + sin(t * 8.0) * 0.3
		draw_arc(Vector2.ZERO, radius + 10.0, 0.0, TAU, 20, Color(0.45, 1.0, 0.3, pulse), 2.0)
	if shock_time > 0.0:
		for i in 2:
			var a := randf() * TAU
			draw_line(Vector2.from_angle(a) * radius * 0.4, Vector2.from_angle(a + 0.4) * (radius + 6.0), U.el_color(U.EL_SHOCK), 1.5)
