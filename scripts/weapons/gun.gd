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
var _fixed_name: String = "Пушка"
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
	return GunData.RARITIES[rarity]["col"]


func rarity_name() -> String:
	return U.t(GunData.RARITIES[rarity]["n"])


func maker_name() -> String:
	return U.t(GunData.MAKERS[maker]["n"])


func gender() -> String:
	return GunData.ARCH[archetype]["g"]


## Тип патронов = тип снаряда. Гибрид ест патроны второй основы
## (дробовик-гранатомёт стреляет гранатами -> гранаты).
## Исключение — Гипернова: ракеты у неё «пули-ракеты», ест патроны своей основы (ПП -> патроны ПП).
func ammo_type() -> String:
	var base := archetype
	if maker != "hypernova" and archetype2 != "":
		base = archetype2
	# у некоторых основ патроны чужие (миномёт ест гранаты)
	return str(GunData.ARCH[base].get("ammo", base))


func ammo_name() -> String:
	return U.t(GunData.ARCH[ammo_type()]["nl"])


## «Дробовик-гранатомёт» и прочие мутанты.
func type_name() -> String:
	if I18n.is_en():
		var e := U.t(GunData.ARCH[archetype]["n"])
		if archetype2 != "":
			e += "-" + U.t(GunData.ARCH[archetype2]["n"])
		return e
	var a: String = GunData.ARCH[archetype]["n"]
	if archetype2 != "":
		a += "-" + str(GunData.ARCH[archetype2]["nl"])
	return a


func type_name_lower() -> String:
	if I18n.is_en():
		return type_name()
	var a: String = GunData.ARCH[archetype]["nl"]
	if archetype2 != "":
		a += "-" + str(GunData.ARCH[archetype2]["nl"])
	return a


## Эффективная дальность (px). Дальше пуля летит, но урон резко падает.
func eff_range() -> float:
	return proj_speed * lifetime


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
		return U.t("%s +%d%%/с") % [U.el_name(element), roundi(10.0 * elem_mult)]
	if element == U.EL_CURSE:
		return U.t("%s +%d%%/с") % [U.el_name(element), roundi(100.0 * Actor.CURSE_RATE * elem_mult)]
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
		out.append([U.t("Снаряды — прыгучие гранаты"), w])
	elif proj_kind == GunData.K_ROCKET:
		out.append([U.t("Снаряды — ракеты"), w])
	elif proj_kind == GunData.K_ORB:
		out.append([U.t("Огромные медленные шары"), w])
	elif proj_kind == GunData.K_SHELL:
		out.append([U.t("Мина: взрыв в точке прицела через %.0f с") % GunData.SHELL_TIME, w])
		out.append([U.t("Разброс = отклонение точки падения"), w])
	if "slug" in mods:
		out.append([U.t("Пулевой: один целый снаряд вместо дроби"), w])
	if explode_r > 0.0 and explode_chance >= 1.0:
		out.append([U.t("Взрыв, радиус %d") % roundi(explode_r), w])
	elif explode_r > 0.0:
		out.append([U.t("Взрыв с шансом %d%%, радиус %d") % [roundi(explode_chance * proc_coef() * 100.0), roundi(explode_r)], w])
	if cluster_n > 0:
		out.append([U.t("Кассета: +%d мини-бомб") % cluster_n, w])
	if pierce >= 50:
		out.append([U.t("Пробивает всё"), w])
	elif pierce > 0:
		out.append([U.t("Пробивает врагов: %d") % pierce, w])
	if bounces > 0 and proj_kind != GunData.K_GRENADE:
		out.append([U.t("Рикошет от стен ×%d") % bounces, w])
	if split_n > 0 and split_depth > 1:
		out.append([U.t("Фрактальное деление ×%d, глубина %d") % [split_n, split_depth], w])
	elif split_n > 0:
		out.append([U.t("Делится на %d при попадании") % split_n, w])
	if homing > 0.0:
		out.append([U.t("Самонаведение"), w])
	if boomerang:
		out.append([U.t("Возвращается бумерангом"), w])
	if sine > 0.0:
		out.append([U.t("Летит змейкой"), w])
	if chain_n > 0:
		out.append([U.t("Цепная молния: %d целей, шанс %d%%") % [chain_n, roundi(proc_coef() * 100.0)], w])
	if leech > 0.0:
		out.append([U.t("Вампиризм %.1f%%") % (leech * 100.0), good])
	if vortex > 0.0:
		out.append([U.t("Чёрная дыра: %.1f%% за снаряд") % (vortex_chance() * 100.0), w])
	if seeder > 0.0:
		out.append([U.t("Снаряды на лету стреляют вбок"), w])
	if teleport > 0.0:
		out.append([U.t("Снаряды телепортируются вперёд"), w])
	if burst > 1:
		out.append([U.t("Очередь по %d") % burst, w])
	if ammo_per_shot > 1:
		out.append([U.t("Расход: %d патр. за выстрел") % ammo_per_shot, bad])
	if legend_perk != "":
		out.insert(0, [U.t("Легендарный перк: «%s»") % U.t(legend_perk), Color(1.0, 0.6, 0.15)])
	if free_ammo:
		out.append([U.t("Не тратит запас патронов"), good])
	if element == U.EL_CURSE:
		out.append([U.t("Проклятие: −20% урона пушки"), bad])
	if proc_mult < 0.99:
		out.append([U.t("Эффекты срабатывают в %.1f раза реже") % (1.0 / proc_mult), bad])
	elif proc_mult > 1.01:
		out.append([U.t("Эффекты срабатывают в %.1f раза чаще") % proc_mult, good])
	if elem_mult > 1.01:
		out.append([U.t("Шанс стихии ×%.0f") % elem_mult, good])
	if armor > 0.0:
		out.append([U.t("Броня: −%d%% входящего урона") % roundi(armor * 100.0), good])
	if move_mult > 1.01:
		out.append([U.t("+%d%% к скорости бега") % roundi((move_mult - 1.0) * 100.0), good])
	elif move_mult < 0.99:
		out.append([U.t("−%d%% к скорости бега") % roundi((1.0 - move_mult) * 100.0), bad])
	match special:
		"ring":
			out.append([U.t("Кольцо пуль (40%% урона), шанс %d%% на выстрел") % roundi(GunGen.proc_keep_chance(self) * 100.0), Color(1.0, 0.7, 0.3)])
		"nuke10":
			out.append([U.t("Копит урон: ядерка ~ раз в %d выстр.") % shots_per_nuke(), Color(1.0, 0.7, 0.3)])
		"chaos":
			out.append([U.t("Урон каждой пули: от 0 до ×2"), Color(1.0, 0.7, 0.3)])
		"expert":
			out.append([U.t("Молния бьёт всех, кто рядом"), Color(1.0, 0.7, 0.3)])
		"singularity":
			out.append([U.t("Каждый шар — чёрная дыра"), Color(1.0, 0.7, 0.3)])
	return out
