extends SceneTree
## Герой: навыки всех героев с каждым перком и стрельба разными пушками. Враги неподвижные и неубиваемые, ГСЧ засеян, всё шагает
## синхронно (без реальных кадров), так что результат детерминирован. Печатает состояние героя, снарядов и урон по целям.
## При рефакторинге `Player` вывод до и после должен совпасть построчно. Работает до и после выноса навыков и стрельбы из `Player`
## (адаптеры ниже ищут поле/метод и в `Player`, и в `player.skill` / `player.shooting`).
## Запуск: godot --headless --path . -s res://tests/player_state.gd   (пользовательский сейв не трогает)

const HP := 1.0e9

var G: Node
var M: Node
var P: Object
var targets: Array = []
var origin := Vector2.ZERO
var k_shell := 0
# имена в старом Player -> имена в HeroSkill
const SKILL_OLD := {"charges": "skill_charges", "cd": "skill_cd", "gap": "skill_gap", "element": "skill_element",
	"blessed": "blessed", "slash_t": "slash_t", "parry_cd": "parry_cd", "trophy_bonus": "trophy_bonus"}


# --- адаптеры --------------------------------------------------------------------------
func has_skill() -> bool:
	return P.get("skill") != null


func has_shooting() -> bool:
	return P.get("shooting") != null


func skv(n: String) -> Variant:
	return P.skill.get(n) if has_skill() else P.get(SKILL_OLD[n])


func shv(n: String) -> Variant:
	return P.shooting.get(n) if has_shooting() else P.get(n)


func use_skill(cast: Variant) -> void:
	if has_skill():
		P.skill.call("use", cast)
	else:
		P.call("_use_skill", cast)


func add_perk(id: String, el: int) -> void:
	if has_skill():
		P.skill.call("add_run_perk", id, el)
	else:
		P.call("add_run_perk", id, el)


func perk_of(id: String) -> int:
	return int(P.skill.call("perk", id) if has_skill() else P.call("perk", id))


func dmg_mult() -> float:
	return float(P.skill.call("dmg_mult") if has_skill() else P.call("skill_dmg_mult"))


func update_gun(d: float) -> void:
	if has_shooting():
		P.shooting.call("update", d)
	else:
		P.call("_update_gun", d)


func fire_once(g: Object) -> void:
	if has_shooting():
		P.shooting.call("fire", g)
	else:
		P.call("_fire", g)


func make_turret_spec() -> Dictionary:
	return P.skill.call("make_turret_spec") if has_skill() else P.call("_make_turret_spec")


# --- сцена -----------------------------------------------------------------------------
func _initialize() -> void:
	G = root.get_node("Game")
	M = load("res://scenes/main.tscn").instantiate()
	root.add_child(M)
	var guard := 0
	while not (M.get("menu") != null and M.menu.visible) and guard < 3000:
		await process_frame
		guard += 1
	M.start_game({"seed": "123"})
	for i in 5:
		await process_frame
	P = M.player
	M.rng.seed = 555
	M.loader.load_zone(4)
	await process_frame
	seed(2024)
	setup_arena()
	var GD: GDScript = load("res://scripts/weapons/gun_data.gd")
	k_shell = int(GD.get_script_constant_map()["K_SHELL"])
	var HR: GDScript = load("res://scripts/entities/heroes.gd")
	var perks: Array = (HR.get("PERKS") as Dictionary).keys()
	var order: Array = HR.get("ORDER")
	var GGC: GDScript = load("res://scripts/weapons/gun_gen.gd")

	# --- навыки: каждый герой, без перков и с каждым подходящим перком
	for hero in order:
		skill_case(GGC, HR, str(hero), "")
		for pid in perks:
			if bool(HR.call("perk_fits", str(pid), str(hero))):
				skill_case(GGC, HR, str(hero), str(pid))
	# турель: сценарии выдачи патронов
	turret_cases(GGC)
	# благословение Шерифа: выстрел с усилением
	bless_case(GGC)

	# --- стрельба
	var GDa: Dictionary = GD.get("ARCH")
	var archs: Array = GDa.keys()
	archs.sort()
	for a in archs:
		shoot_case(GGC, "epic:" + str(a), 3, str(a))
	for n in 4:
		shoot_case(GGC, "legendary#%d" % n, 4, "")
	for n in 3:
		shoot_case(GGC, "absurd#%d" % n, 5, "")
	reload_cases(GGC)
	print("SMOKE DONE")
	quit()


func setup_arena() -> void:
	P.position = M.zone.random_free_near(M.zone.cell_center(Vector2i(M.zone.w / 2, M.zone.h / 2)), 0.0, 200.0)
	origin = P.position
	for k in 5:
		var pos: Vector2 = M.zone.random_free_near(origin + Vector2(200.0 + 50.0 * k, (k - 2) * 70.0), 0.0, 50.0)
		var tries := 0
		while not M.zone.ray_clear(origin, pos) and tries < 12:
			pos = origin + (pos - origin) * 0.8
			tries += 1
		var e: Object = M.loader.spawn_enemy("brute", pos, 12, 0, [], -1, false)
		e.awake = true
		e.set_physics_process(false)
		e.max_hp = HP
		targets.append(e)


func fresh_player(GGC: GDScript, hero: String, seed_name: String, rarity: int = 3, arch: String = "pistol") -> Object:
	P.call("reset")
	P.call("set_hero", hero)
	P.max_hp = HP
	P.hp = HP
	P.invuln = 0.0
	P.position = origin
	P.aim = Vector2.RIGHT
	seed(hash(seed_name) + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_name)
	var g: Object = GGC.call("generate", 12, rng, 0.0, 0, rarity, arch)
	g.ammo = g.mag_size
	P.add_gun(g)
	P.reserve = {}
	P.reserve[g.ammo_type()] = 200
	M.projectiles.list.clear()
	(M.projectiles.get("_pending") as Array).clear()
	for t in M.turrets.duplicate():
		if is_instance_valid(t):
			t.queue_free()
	M.turrets.clear()
	for e in targets:
		e.hp = HP
	M.grid_hash.clear()
	for e in targets:
		M.grid_hash.insert(e)
	G.controls.touch_fire = false
	seed(hash(seed_name) + 2)
	M.rng.seed = hash(seed_name)
	return g


func step_projectiles(n: int) -> void:
	for f in n:
		M.projectiles.call("_physics_process", 1.0 / 60.0)


func dealt() -> float:
	var d := 0.0
	for e in targets:
		d += HP - float(e.hp)
	return d


func skill_state() -> String:
	return "ch=%s cd=%s gap=%s el=%s bl=%s sl=%s pr=%s tb=%s" % [skv("charges"), snappedf(float(skv("cd")), 0.001), snappedf(float(skv("gap")), 0.001),
		skv("element"), skv("blessed"), snappedf(float(skv("slash_t")), 0.001), snappedf(float(skv("parry_cd")), 0.001), snappedf(float(skv("trophy_bonus")), 0.0001)]


func skill_case(GGC: GDScript, _HR: GDScript, hero: String, perk_id: String) -> void:
	var name: String = "skill:%s+%s" % [hero, perk_id]
	var g: Object = fresh_player(GGC, hero, name)
	if perk_id != "":
		add_perk(perk_id, 0)   # стихия 0 — огонь (для перка «Стихия»)
	var before := skill_state()
	# применить навык дважды (с разными прицелами): без стика и со стиком
	use_skill(null)
	step_projectiles(5)
	var mid := skill_state()
	if has_skill():
		P.skill.set("gap", 0.0)
	else:
		P.set("skill_gap", 0.0)
	use_skill({"dir": Vector2(1, 0.25), "len": 0.7})
	step_projectiles(120)
	print("SMOKE ", name, " mult=", snappedf(dmg_mult(), 0.0001), " [", before, "] -> [", mid, "] -> [", skill_state(), "] dealt=", snappedf(dealt(), 0.01),
		" proj=", M.projectiles.count(), " turrets=", M.turrets.size(), " ammo=", g.ammo, " reload=", snappedf(float(shv("reload_t")), 0.001),
		" coins=", snappedf(float(G.state.coins), 0.1))


func turret_cases(GGC: GDScript) -> void:
	for variant in ["full mag", "empty mag", "reloading", "scientist", "economy+hand"]:
		var name: String = "turret:" + str(variant)
		var g: Object = fresh_player(GGC, "engineer", name)
		match variant:
			"empty mag":
				g.ammo = 0
			"reloading":
				if has_shooting():
					P.shooting.call("start_reload", true)
				else:
					P.call("start_reload", true)
			"scientist":
				add_perk("scientist", 0)
			"economy+hand":
				add_perk("economy", 0)
				add_perk("hand", 0)
		var spec := make_turret_spec()
		var info := "empty"
		if not spec.is_empty():
			info = "ammo=%d gun=%s rar=%d" % [int(spec["ammo"]), str(spec["gun"].gun_name).substr(0, 16), int(spec["gun"].rarity)]
		print("SMOKE ", name, " spec: ", info, " | player gun ammo=", g.ammo, " reload=", snappedf(float(shv("reload_t")), 0.001), " burst=", shv("burst_left"))


func bless_case(GGC: GDScript) -> void:
	for pid in ["", "split", "precise", "poison"]:
		var name: String = "bless:" + str(pid)
		var g: Object = fresh_player(GGC, "sheriff", name)
		if pid != "":
			add_perk(pid, 0)
		use_skill(null)   # «благословить» следующий выстрел
		var n_before: int = M.projectiles.count()
		fire_once(g)
		var after: int = M.projectiles.count()
		step_projectiles(60)
		print("SMOKE ", name, " blessed_after_fire=", skv("blessed"), " proj ", n_before, "->", after, " dealt=", snappedf(dealt(), 0.01), " ", skill_state())


func shoot_case(GGC: GDScript, name: String, rarity: int, arch: String) -> void:
	var g: Object = fresh_player(GGC, "pioneer", name, rarity, arch)
	G.controls.touch_fire = true
	var snaps: Array = []
	for f in 420:
		update_gun(1.0 / 60.0)
		step_projectiles(1)
		if f % 105 == 104:
			snaps.append("%d/%s/%s" % [g.ammo, snappedf(float(shv("reload_t")), 0.01), M.projectiles.count()])
	G.controls.touch_fire = false
	print("SMOKE ", name, " mag=", g.mag_size, " ", snaps, " reserve=", P.reserve.get(g.ammo_type(), 0), " dealt=", snappedf(dealt(), 0.01),
		" bloom=", snappedf(float(shv("bloom")), 0.001), " kick=", snappedf(P.kick.length(), 0.01), " shots=", g.shot_count, " cd=", snappedf(float(shv("fire_cd")), 0.001))


func reload_cases(GGC: GDScript) -> void:
	# ручная перезарядка, нет патронов, ритм-перезарядка арбалета с нажатием в такт
	var g: Object = fresh_player(GGC, "pioneer", "reload:manual", 2, "pistol")
	g.ammo = 3
	update_gun(1.0 / 60.0)
	if has_shooting():
		P.shooting.call("start_reload", true)
	else:
		P.call("start_reload", true)
	for f in 400:
		update_gun(1.0 / 60.0)
	print("SMOKE reload:manual ammo=", g.ammo, "/", g.mag_size, " reserve=", P.reserve.get(g.ammo_type(), 0), " reload_t=", snappedf(float(shv("reload_t")), 0.001))
	g = fresh_player(GGC, "pioneer", "reload:dry", 2, "pistol")
	g.ammo = 0
	P.reserve[g.ammo_type()] = 0
	update_gun(1.0 / 60.0)
	print("SMOKE reload:dry reload_t=", snappedf(float(shv("reload_t")), 0.001), " dry_cd>0=", float(shv("_dry_cd")) > 0.0 if (has_shooting() or "_dry_cd" in P) else "n/a")
	g = fresh_player(GGC, "pioneer", "reload:crossbow", 3, "crossbow")
	g.ammo = 0
	var rl_t := 0.0
	var beats: Array = []
	for f in 1000:
		update_gun(1.0 / 60.0)
		if float(shv("reload_t")) > 0.0:
			rl_t = float(shv("reload_t"))
		if f % 100 == 0:
			beats.append("%s/%s/%s" % [snappedf(float(shv("reload_t")), 0.01), snappedf(float(shv("rhythm_phase")), 0.01), shv("rhythm_hits")])
	print("SMOKE reload:crossbow ", beats, " ammo=", g.ammo, "/", g.mag_size, " bonus=", snappedf(float(g.rhythm_bonus), 0.001))
