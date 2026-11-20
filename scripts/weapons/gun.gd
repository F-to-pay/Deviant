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
var recoil: float = 0.0        # отдача: выстрел отбрасывает стрелка назад (импульс, px/с); у корабельной пушки — космическая
var rhythm := false             # ритм-перезарядка (арбалет, перк «Ритмичный»): нажимай R в такт, см. Player._rhythm_update
var rhythm_bonus := 0.0          # прибавка к урону текущей обоймы: RHYTHM_BONUS за каждое попадание в такт при её перезарядке
var _fx_cache: Array = []       # effect_lines(): готовый текст и язык, на котором он собран
var _fx_lang: String = ""
var slug_n: int = 0           # у пулевого дробовика — сколько дробин было до слитка; толчок залпа считается по ним
var knock_boost: float = 0.0   # перк «Сотрясающий»: множитель толчка залпа обратно пропорционален самому толчку (слабой пушке — много, сильной — мало)

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
var beam := false                # перк «Лазерный»: скорость пули — мгновенная, остальное как у обычной (Projectiles._fire_beam)
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
const PELLET_KNOCK_CAP := 6.0      # потолок: суммарный толчок залпа не больше чем ×6 от толчка одной дробины
const KNOCK_BOOST_REF := 150.0     # «Сотрясающий»: толчок, при котором множитель = 1 + knock_boost (0.8 → ×1.8); слабее — множитель растёт, сильнее — падает
const PELLET_KNOCK_HALF := 8.0     # насколько быстро к нему подходим: при 8 дробинах сверх первой набрана половина прибавки
const PELLET_DMG_BONUS := 0.01     # +1% к урону дробины за каждую дробину сверх первой


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
## Безлимитная пушка (Синергис) — «энергия»: патроны под неё не падают и не продаются (иначе они достаются пустышке).
func ammo_type() -> String:
	if free_ammo:
		return GunData.ENERGY
	return base_ammo_type()


## Тип патронов по основе пушки (то, чем она была бы без бесконечных патронов). Остаётся для разбора:
## Синергис, пущенный на переработку, даёт патроны своей основы — их можно отдать другим пушкам.
func base_ammo_type() -> String:
	var base := archetype
	if str(GunData.MAKERS.get(maker, {}).get("projectile_arch", "")) == "" and archetype2 != "":
		base = archetype2
	# у некоторых основ патроны чужие (миномёт ест гранаты)
	return str(GunData.ARCH.get(base, {}).get("ammo", base))


func ammo_name() -> String:
	return GunData.ammo_label(ammo_type())


## «Дробовик & гранатомёт» и прочие мутанты (порядок — шаблон языка type_hybrid).
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
const RHYTHM_CUT := 2.0      # попадание в такт сокращает перезарядку на столько секунд
const RHYTHM_PERIOD := 1.0   # такт — раз в секунду
const RHYTHM_WINDOW := 0.18  # окно попадания: ±столько долей такта (0.18 = ±0.18 с) от момента такта
const RHYTHM_LOCK := 4.0     # промах: сокращать перезарядку нельзя столько секунд
const RHYTHM_BONUS := 0.08   # каждое попадание в такт (то есть каждое сокращение перезарядки) — +8% урона следующей обоймы, и они складываются
const RANGE_MULT := 0.7
const NO_FALLOFF_RANGE := 40000.0  # пушка без спада урона (револьвер): дальность 1000 м (1 м = 40 px), больше любой карты; на карточке пишем «-»


## На сколько метров отдача отбрасывает стрелка (торможение 1800 px/с², как у отбрасывания врагов).
func recoil_m() -> float:
	return recoil * recoil / (2.0 * 1800.0) / 40.0


## Независимая копия пушки (турель Инженера стреляет своей копией: свой магазин и свой счётчик ядерки).
func copy() -> Gun:
	var c := Gun.new()
	for pr in get_property_list():
		if (int(pr["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n := str(pr["name"])
		if n == "gun_name":   # геттер/сеттер: имя уже скопировано через name_parts и _fixed_name
			continue
		var v: Variant = get(n)
		if v is Array or v is Dictionary:
			v = v.duplicate(true)
		c.set(n, v)
	c.shot_count = 0
	return c


func eff_range() -> float:
	if no_falloff:
		return NO_FALLOFF_RANGE
	return proj_speed * lifetime * RANGE_MULT


## Урон одного снаряда без учёта уровня (с редкостью) — мера «веса» выстрела.
func norm_damage() -> float:
	var lvl_mult: float = Game.gun_dmg_mult(level)
	return damage / lvl_mult


## Белые пушки (Common) не устаревают: подгоняются под уровень зоны, где герой сейчас. Урон зашит в `damage` при
## генерации (× gun_dmg_mult(level)), поэтому меняем его на отношение множителей нового и старого уровня.
## Остальные редкости не трогаем — они обязаны стареть. true — уровень изменился.
func sync_level(new_level: int) -> bool:
	new_level = maxi(1, new_level)
	if rarity != GunData.R_COMMON or new_level == level:
		return false
	damage *= Game.gun_dmg_mult(new_level) / Game.gun_dmg_mult(level)
	level = new_level
	return true


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


## Отбрасывание одной дробины. Толчки дробин складываются, поэтому у веера на 60 дробин цель улетала через пол-карты.
## Отбрасывание одной дробины: суммарный толчок залпа (volley_knock), поделённый между дробинами.
func pellet_knock() -> float:
	return volley_knock() / float(maxi(1, pellets))


## Во сколько раз суммарный толчок залпа больше толчка одной дробины: 1 + (потолок − 1) × k / (k + HALF), k = дробин сверх первой.
func volley_knock_mult() -> float:
	var k := float(maxi(0, maxi(pellets, slug_n) - 1))
	return 1.0 + (PELLET_KNOCK_CAP - 1.0) * k / (k + PELLET_KNOCK_HALF)


## Суммарный толчок залпа по цели: knock × volley_knock_mult() (растёт с числом дробин всё медленнее, упирается в
## PELLET_KNOCK_CAP). Перк «Сотрясающий» (knock_boost) умножает его на 1 + boost × REF / толчок — обратно пропорционально
## самому толчку: ПП (30) вырастает в 5 раз, пистолет (60) — в 3, револьвер (100) — в 2.2, дробовик на 40 дробей (283) — в 1.4.
func volley_knock() -> float:
	var t := knock * volley_knock_mult()
	if knock_boost > 0.0:
		t *= 1.0 + knock_boost * KNOCK_BOOST_REF / maxf(t, 1.0)
	return t


## Бонус к урону каждой дробины за их число: +1% за каждую дробину сверх первой (у одной дробины — ×1).
func pellet_dmg_mult() -> float:
	return 1.0 + PELLET_DMG_BONUS * float(maxi(0, pellets - 1))


func accuracy() -> int:
	return mini(100, roundi(100.0 - spread * 2.2))   # снизу не обрезаем: у веера в 110° честные −142%, только для вида


## Оценка устойчивого урона в секунду (с перезарядкой).
func dps() -> float:
	var per_shot := damage * float(pellets) * pellet_dmg_mult() * (1.0 + crit_chance * (crit_mult - 1.0))
	if explode_r > 0.0:
		per_shot *= 1.0 + 0.3 * explode_chance
	if split_n > 0 and split_depth > 0:
		per_shot *= 1.0 + 0.2 * float(split_n * split_depth)
	if chain_n > 0:
		per_shot *= 1.0 + 0.15 * float(chain_n)
	var shots_per_mag := maxf(1.0, float(mag_size) / float(maxi(1, ammo_per_shot)))
	var cycle := shots_per_mag / fire_rate + reload_time
	return per_shot * shots_per_mag / cycle


## Что дают марка и перки пушки словами — для низа карточки: «Тяжёлый: урон +35%, скорострельность −15%».
## Текст берётся из операций перка (GunOps.describe), как в справочнике. Кэш — пока не сменился язык.
func effect_lines() -> Array:
	if _fx_lang == I18n.lang:
		return _fx_cache
	var out: Array = []
	var mk: Dictionary = GunData.MAKERS.get(maker, {})
	var mk_fx := GunOps.describe(mk.get("ops", []))
	if not mk_fx.is_empty():
		out.append("%s: %s" % [maker_name(), ", ".join(PackedStringArray(mk_fx))])
	for id in mods:
		var d := GunData.perk(str(id))
		if d.is_empty():
			continue
		var fx := GunOps.describe(d.get("ops", []))
		if not fx.is_empty():
			out.append("%s: %s" % [I18n.word(str(d.get("name", id)), "m"), ", ".join(PackedStringArray(fx))])
	_fx_cache = out
	_fx_lang = I18n.lang
	return out


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
	if rhythm:
		out.append([U.t("Rhythm reload: press [%s] or fire on the beat (once a second) to cut it by %d s; a miss locks it for %d s") % [Controls.label("reload"), roundi(RHYTHM_CUT), roundi(RHYTHM_LOCK)], good])
		out.append([U.t("Every hit on the beat: +%d%% damage to the next magazine (stacks)") % roundi(RHYTHM_BONUS * 100.0), good])
	if recoil > 0.0:
		out.append([U.t("Recoil: throws you back %d m") % roundi(recoil_m()), bad])
	if beam:
		out.append([U.t("Laser: the bullet flies instantly"), w])
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
	if knock_boost > 0.0:
		out.append([U.t("Concussive: weak knockback is boosted"), good])
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
