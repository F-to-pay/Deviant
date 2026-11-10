class_name Gun
extends RefCounted
## Одна пушка: итоговые характеристики после генерации + рантайм (патроны).

var level: int = 1
var rarity: int = 0
var archetype: String = "pistol"
var archetype2: String = ""
var maker: String = "atlant"
var mods: Array = []
var legendary: String = ""
var legend_perk: String = ""     # «Кузня хаоса»: чей легендарный перк достался
var special: String = ""
## Имя собирается на лету из name_parts (см. GunGen.build_name) — так оно всегда
## на текущем языке. Присвоение строки задаёт имя напрямую (без перевода).
var name_parts: Dictionary = {}
var _fixed_name: String = "Gun"
var gun_name: String:
	get:
		return GunGen.build_name(self) if not name_parts.is_empty() else _fixed_name
	set(value):
		_fixed_name = value
		name_parts = {}
var flavor: String = ""

# --- Стрельба
var damage: float = 10.0
var fire_rate: float = 4.0
var pellets: int = 1
var spread: float = 3.0
var proj_speed: float = 900.0
var lifetime: float = 0.8
var mag_size: int = 12
var reload_time: float = 1.2
var crit_chance: float = 0.05
var crit_mult: float = 2.0
var element: int = -1
var elem_chance: float = 0.0
var burst: int = 1
var ammo_per_shot: int = 1
var knock: float = 60.0

# --- Снаряд
var proj_kind: int = 0
var proj_size: float = 3.0
var proj_color: Color = Color.WHITE
var pierce: int = 0
var bounces: int = 0
var explode_r: float = 0.0
var explode_chance: float = 0.0   # 1.0 у ракет/гранат, у пуль — шанс
var explode_on_expire: bool = false
var homing: float = 0.0
var accel: float = 0.0
var drag: float = 0.0
var sine: float = 0.0
var boomerang: bool = false
var split_n: int = 0
var split_depth: int = 0
var chain_n: int = 0
var cluster_n: int = 0
var leech: float = 0.0
var vortex: float = 0.0
var seeder: float = 0.0
var teleport: float = 0.0

# --- Бонусы владельцу, пока пушка в руках
var armor: float = 0.0          # доля срезаемого входящего урона
var free_ammo: bool = false     # «Синергис»: не тратит запас
var proc_mult: float = 1.0      # множитель коэффициента срабатывания (марки)
var elem_mult: float = 1.0      # множитель шанса стихии («Эррозия»)
var move_mult: float = 1.0
# --- Особенности основы (archetypes.json; у гибрида — от обеих основ)
var light := false               # пистолет, ПП: стрельба не замедляет героя
var no_falloff := false          # револьвер: урон не падает за эффективной дальностью
var range_dmg: float = 0.0       # снайперка: урон растёт с пролётом — от этой доли до 100% на половине эффективной дальности
var shake: float = 1.0

# --- Внешний вид
var body_color: Color = Color.GRAY
var dark_color: Color = Color.DIM_GRAY
var vis: Dictionary = {}

# --- Рантайм
var ammo: int = 12
var shot_count: int = 0
var nuke_charge: float = 0.0

const PROC_REF := 40.0     # «вес» снаряда, при котором эффекты срабатывают на полную
const NUKE_COST := 600.0   # сколько нормированного урона копится на одну ядерку


func rarity_color() -> Color:
	return GunData.RARITIES[rarity].get("color", Color.WHITE)


func rarity_name() -> String:
	return U.t(str(GunData.RARITIES[rarity].get("name", "?")))


func maker_name() -> String:
	return U.t(str(GunData.MAKERS.get(maker, {}).get("name", maker)))


func _arch_name(id: String) -> String:
	return str(GunData.ARCH.get(id, {}).get("name", id))


## Грамматический род основы в текущем языке (для прилагательных в имени).
func gender() -> String:
	return I18n.gender(_arch_name(archetype))


## Тип патронов = тип снаряда. Гибрид ест патроны второй основы
## (дробовик-гранатомёт стреляет гранатами -> гранаты).
## Исключение — марки с projectile_arch (Гипернова): ракеты у неё «пули-ракеты»,
## ест патроны своей основы (ПП -> патроны ПП).
func ammo_type() -> String:
	var base := archetype
	if str(GunData.MAKERS.get(maker, {}).get("projectile_arch", "")) == "" and archetype2 != "":
		base = archetype2
	# у некоторых основ патроны чужие (миномёт ест гранаты)
	return str(GunData.ARCH.get(base, {}).get("ammo", base))


func ammo_name() -> String:
	return GunData.ammo_label(ammo_type())


## «Дробовик-гранатомёт» и прочие мутанты (порядок — шаблон языка type_hybrid).
func type_name() -> String:
	var a := _arch_name(archetype)
	if archetype2 == "":
		return U.t(a)
	var b := _arch_name(archetype2)
	return I18n.tpl("type_hybrid", {"a": U.t(a), "b": U.t(b), "a_l": I18n.word(a, "lower"), "b_l": I18n.word(b, "lower")})


## Строчная форма — для имён вида «Злой дробовик-гранатомёт» (в английском = type_name()).
func type_name_lower() -> String:
	if I18n.is_en():
		return type_name()
	var a := _arch_name(archetype)
	if archetype2 == "":
		return I18n.word(a, "lower")
	var b := _arch_name(archetype2)
	var al := I18n.word(a, "lower")
	return I18n.tpl("type_hybrid", {"a": al, "b": I18n.word(b, "lower"), "a_l": al, "b_l": I18n.word(b, "lower")})


## Эффективная дальность (px). Дальше пуля летит, но урон резко падает.
## Эффективная дальность: дальше урон падает (кроме no_falloff). 0.7 — общий срез дальности всех пушек.
const RANGE_MULT := 0.7


func eff_range() -> float:
	return proj_speed * lifetime * RANGE_MULT


## Урон одного снаряда без учёта уровня (с редкостью) — мера «веса» выстрела.
func norm_damage() -> float:
	var lvl_mult: float = Game.gun_dmg_mult(level)
	return damage / lvl_mult


## Коэффициент срабатывания (как proc coefficient в Risk of Rain): все эффекты
## «по шансу» умножаются на него. Мелкие быстрые пули прокают редко, тяжёлые — часто,
## поэтому срабатываний в секунду у пулемёта и снайперки примерно поровну.
func proc_coef() -> float:
	return clampf(norm_damage() / PROC_REF, 0.08, 1.0) * proc_mult


func elem_proc() -> float:
	return clampf(elem_chance * elem_mult * proc_coef(), 0.0, 1.0)


## Строка стихии для карточки. Кислота/холод — линейный набор, огонь/ток — шанс.
func elem_text() -> String:
	if element == U.EL_ACID or element == U.EL_CRYO:
		return U.t("%s +%d%%/s") % [U.el_name(element), roundi(10.0 * elem_mult)]
	if element == U.EL_CURSE:
		return U.t("%s +%d%%/s") % [U.el_name(element), roundi(100.0 * Actor.CURSE_RATE * elem_mult)]
	return "%s %d%%" % [U.el_name(element), roundi(elem_proc() * 100.0)]


## Сколько выстрелов в среднем на одну ядерку «Последнего Слова».
func shots_per_nuke() -> int:
	return maxi(1, ceili(NUKE_COST / maxf(0.1, norm_damage() * float(pellets))))


## Шанс чёрной дыры на снаряд: зависит от «веса» одного снаряда без учёта
## уровня, поэтому пулемёт с мелкими пулями прокает её редко, а снайперка — часто.
func vortex_chance() -> float:
	if vortex <= 0.0:
		return 0.0
	return vortex * clampf(pow(norm_damage() / 60.0, 1.5), 0.01, 1.0) * proc_mult


func accuracy() -> int:
	return clampi(roundi(100.0 - spread * 2.2), 0, 100)


## Оценка устойчивого урона в секунду (с перезарядкой).
func dps() -> float:
	var per_shot := damage * float(pellets) * (1.0 + crit_chance * (crit_mult - 1.0))
	if explode_r > 0.0:
		per_shot *= 1.0 + 0.3 * explode_chance
	if split_n > 0 and split_depth > 0:
		per_shot *= 1.0 + 0.2 * float(split_n * split_depth)
	if chain_n > 0:
		per_shot *= 1.0 + 0.15 * float(chain_n)
	var shots_per_mag := maxf(1.0, float(mag_size) / float(maxi(1, ammo_per_shot)))
	var cycle := shots_per_mag / fire_rate + reload_time
	return per_shot * shots_per_mag / cycle


## Строки особенностей для карточки: [текст, цвет].
func perk_lines() -> Array:
	var out: Array = []
	var w := Color(0.82, 0.88, 1.0)
	var good := Color(0.45, 1.0, 0.5)
	var bad := Color(1.0, 0.45, 0.4)
	if proj_kind == GunData.K_GRENADE:
		out.append([U.t("Projectiles — bouncy grenades"), w])
	elif proj_kind == GunData.K_ROCKET:
		out.append([U.t("Projectiles — rockets"), w])
	elif proj_kind == GunData.K_ORB:
		out.append([U.t("Huge slow orbs"), w])
	elif proj_kind == GunData.K_SHELL:
		out.append([U.t("Shell: explodes at the aim point after %.0f s") % GunData.SHELL_TIME, w])
		out.append([U.t("Spread = landing point deviation"), w])
	if "slug" in mods:
		out.append([U.t("Slug: one solid round instead of pellets"), w])
	if range_dmg > 0.0:
		out.append([U.t("Damage grows with distance: %d%% → 100%% at %d m") % [roundi(range_dmg * 100.0), roundi(eff_range() * 0.5 / 40.0)], w])
	if no_falloff:
		out.append([U.t("No damage falloff with range"), good])
	if light:
		out.append([U.t("Light: no slowdown while shooting"), good])
	if explode_r > 0.0 and explode_chance >= 1.0:
		out.append([U.t("Explosion, radius %d") % roundi(explode_r), w])
	elif explode_r > 0.0:
		out.append([U.t("%d%% chance to explode, radius %d") % [roundi(explode_chance * proc_coef() * 100.0), roundi(explode_r)], w])
	if cluster_n > 0:
		out.append([U.t("Cluster: +%d bomblets") % cluster_n, w])
	if pierce >= 50:
		out.append([U.t("Pierces everything"), w])
	elif pierce > 0:
		out.append([U.t("Pierces enemies: %d (−40%% damage each)") % pierce, w])
	if bounces > 0 and proj_kind != GunData.K_GRENADE:
		out.append([U.t("Ricochets off walls ×%d") % bounces, w])
	if split_n > 0 and split_depth > 1:
		out.append([U.t("Fractal split ×%d, depth %d") % [split_n, split_depth], w])
	elif split_n > 0:
		out.append([U.t("Splits into %d on hit") % split_n, w])
	if homing > 0.0:
		out.append([U.t("Homing projectiles"), w])
	if boomerang:
		out.append([U.t("Returns like a boomerang"), w])
	if sine > 0.0:
		out.append([U.t("Flies in a wave"), w])
	if chain_n > 0:
		out.append([U.t("Chain lightning: %d targets, %d%% chance") % [chain_n, roundi(proc_coef() * 100.0)], w])
	if leech > 0.0:
		out.append([U.t("Lifesteal %.1f%%") % (leech * 100.0), good])
	if vortex > 0.0:
		out.append([U.t("Black hole: %.1f%% per projectile") % (vortex_chance() * 100.0), w])
	if seeder > 0.0:
		out.append([U.t("Projectiles shoot sideways mid-flight"), w])
	if teleport > 0.0:
		out.append([U.t("Projectiles teleport forward"), w])
	if burst > 1:
		out.append([U.t("Bursts of %d") % burst, w])
	if ammo_per_shot > 1:
		out.append([U.t("Uses %d rounds per shot") % ammo_per_shot, bad])
	if legend_perk != "":
		out.insert(0, [U.t("Legendary perk: \"%s\"") % U.t(legend_perk), Color(1.0, 0.6, 0.15)])
	if free_ammo:
		out.append([U.t("Doesn't use reserve ammo"), good])
	if element == U.EL_CURSE:
		out.append([U.t("Curse: −20% gun damage"), bad])
	if proc_mult < 0.99:
		out.append([U.t("Effects proc %.1f× less often") % (1.0 / proc_mult), bad])
	elif proc_mult > 1.01:
		out.append([U.t("Effects proc %.1f× more often") % proc_mult, good])
	if elem_mult > 1.01:
		out.append([U.t("Element chance ×%.0f") % elem_mult, good])
	if armor > 0.0:
		out.append([U.t("Armor: −%d%% damage taken") % roundi(armor * 100.0), good])
	if move_mult > 1.01:
		out.append([U.t("+%d%% move speed") % roundi((move_mult - 1.0) * 100.0), good])
	elif move_mult < 0.99:
		out.append([U.t("−%d%% move speed") % roundi((1.0 - move_mult) * 100.0), bad])
	match special:
		"ring":
			out.append([U.t("Bullet ring (100%% damage), %d%% chance per shot") % roundi(GunGen.proc_keep_chance(self) * 100.0), Color(1.0, 0.7, 0.3)])
		"nuke10":
			out.append([U.t("Stores damage: a nuke every ~%d shots") % shots_per_nuke(), Color(1.0, 0.7, 0.3)])
		"chaos":
			out.append([U.t("Each bullet deals ×0 to ×2 damage"), Color(1.0, 0.7, 0.3)])
		"expert":
			out.append([U.t("Lightning hits everyone nearby"), Color(1.0, 0.7, 0.3)])
		"singularity":
			out.append([U.t("Every orb is a black hole"), Color(1.0, 0.7, 0.3)])
		"bounce_keep":
			out.append([U.t("Ricochets do not reduce damage"), Color(1.0, 0.7, 0.3)])
	return out
