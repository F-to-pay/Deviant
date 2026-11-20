class_name RunSave
extends RefCounted
## Сохранение забега: один слот, файл `user://run.save`: заголовок `DEVRUN1:` и base64 от `var_to_bytes` (бинарно, чтобы числа
## возвращались бит в бит: текст `var_to_str` теряет последний разряд). Версия формата — поле `version`.
## Контрольная точка ставится при входе в каждую зону и город (`Main.checkpoint`) и при старте забега; продолжить можно только
## с начала локации (враги и лут на карте не сохраняются — иначе «сейв-скам»). Смерть стирает сейв (`Rewards.on_player_died`).
## В сейве: параметры забега (`Game.run`), `RunState`, герой, пушки целиком (`Gun.to_dict`, а не сид — генератор меняется),
## запас патронов, фляги, перки навыка, и состояние ГСЧ ДО генерации локации — по нему зона получается той же.
## Продолжить: `Main.continue_run()`; кнопка — на главном экране (`MainScreen`).

const PATH := "user://run.save"
const VERSION := 1
const MAGIC := "DEVRUN1:"


static func exists() -> bool:
	return FileAccess.file_exists(PATH)


static func delete() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## Подпись набора включённых модов: если она изменилась, сейв загрузится, но с предупреждением.
static func mods_signature() -> Array:
	var out: Array = []
	for m in Mods.list:
		if bool(m["enabled"]):
			out.append("%s@%s" % [str(m["id"]), str((m["info"] as Dictionary).get("version", ""))])
	out.sort()
	return out


## Снимок забега перед входом в локацию level (to_town — это город перед зоной level).
static func snapshot(main: Main, level: int, to_town: bool) -> Dictionary:
	return {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"mods": mods_signature(),
		"checkpoint": {"level": level, "town": to_town, "rng": main.rng.state, "game_rng": Game.rng.state},
		"run": Game.run.duplicate(true),
		"state": Game.state.to_dict(),
		"player": player_dict(main.player),
	}


static func player_dict(p: Player) -> Dictionary:
	var guns: Array = []
	for g in p.guns:
		guns.append((g as Gun).to_dict() if g != null else null)
	var bag: Array = []
	for g in p.backpack:
		bag.append((g as Gun).to_dict())
	return {"hero": p.hero, "guns": guns, "backpack": bag, "active": p.active, "last_active": p.last_active,
		"reserve": p.reserve.duplicate(), "flasks": p.flasks, "hp": p.hp,
		"run_perks": p.skill.run_perks.duplicate(), "element": p.skill.element, "trophy_bonus": p.skill.trophy_bonus}


## Словарь -> текст файла и обратно. decode: null, если заголовка нет или данные повреждены.
static func encode(d: Dictionary) -> String:
	return MAGIC + Marshalls.raw_to_base64(var_to_bytes(d))


static func decode(text: String) -> Variant:
	if not text.begins_with(MAGIC):
		return null
	var raw := Marshalls.base64_to_raw(text.substr(MAGIC.length()).strip_edges())
	if raw.size() < 8:
		return null
	return bytes_to_var(raw)


## Записать контрольную точку. Пишем во временный файл и переименовываем: если процесс убьют посреди записи, старый сейв цел.
static func write(main: Main, level: int, to_town: bool) -> bool:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		Game.debug_log.warn("run save: cannot write %s" % tmp, "save")
		return false
	f.store_string(encode(snapshot(main, level, to_town)))
	f.close()
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	var abs_dst := ProjectSettings.globalize_path(PATH)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(abs_dst)
	return DirAccess.rename_absolute(abs_tmp, abs_dst) == OK


## Прочитать и проверить сейв. {"ok": bool, "reason": "none" / "corrupt" / "version" / "invalid", "data": {...}, "warnings": [строки]}.
static func read() -> Dictionary:
	var res := {"ok": false, "reason": "none", "data": {}, "warnings": []}
	if not exists():
		return res
	var v: Variant = decode(FileAccess.get_file_as_string(PATH))
	if not (v is Dictionary):
		res["reason"] = "corrupt"
		return res
	var d: Dictionary = v
	if int(d.get("version", 0)) != VERSION:
		res["reason"] = "version"
		return res
	var cp: Variant = d.get("checkpoint")
	if not (cp is Dictionary) or int((cp as Dictionary).get("level", 0)) < 1 or not ((d.get("run") is Dictionary) and (d.get("state") is Dictionary) \
			and (d.get("player") is Dictionary)) or not ((d["player"] as Dictionary).get("guns") is Array):
		res["reason"] = "invalid"
		return res
	res["ok"] = true
	res["reason"] = ""
	res["data"] = d
	if d.get("mods") != mods_signature():
		(res["warnings"] as Array).append(U.t("Mods changed since this save: some guns and heroes may look different"))
	return res


## Короткое описание для кнопки «Продолжить»: «Зона 12 · Первопроходец · уровень 9».
static func summary(d: Dictionary) -> String:
	var cp: Dictionary = d["checkpoint"]
	var st: Dictionary = d["state"]
	return U.t("Zone %d · %s · level %d") % [int(cp["level"]), Heroes.hero_name(str((d["player"] as Dictionary).get("hero", Heroes.DEFAULT))),
		int(st.get("hero_level", 1))]


## Развернуть сейв в игре: параметры, состояние забега, герой с пушками. Локацию грузит вызывающий (`Main.continue_run`).
static func restore(main: Main, d: Dictionary) -> void:
	Game.run = RunConfig.DEFAULTS.duplicate()
	Game.run.merge(d["run"], true)
	var st: Dictionary = d["state"]
	Game.state.seed_value = int(st.get("seed_value", 0))
	main.rng.seed = Game.state.seed_value
	Game.new_run()
	Game.state.from_dict(st)
	LevelTree.recompute()
	main.player.reset()
	apply_player(main.player, d["player"])
	var cp: Dictionary = d["checkpoint"]
	main.rng.state = int(cp["rng"])
	Game.rng.state = int(cp["game_rng"])


static func apply_player(p: Player, d: Dictionary) -> void:
	var hero := str(d.get("hero", Heroes.DEFAULT))
	p.set_hero(hero if Heroes.LIST.has(hero) else Heroes.DEFAULT)
	var guns: Array = d["guns"]
	for i in 4:
		var gd: Variant = guns[i] if i < guns.size() else null
		p.guns[i] = Gun.from_dict(gd) if gd is Dictionary else null
	p.backpack = []
	for gd in d.get("backpack", []):
		p.backpack.append(Gun.from_dict(gd))
	p.active = clampi(int(d.get("active", 0)), 0, 3)
	p.last_active = clampi(int(d.get("last_active", 0)), 0, 3)
	p.reserve = {}
	var rv: Dictionary = d.get("reserve", {})
	for k in rv:
		p.reserve[str(k)] = int(rv[k])
	p.flasks = int(d.get("flasks", p.flasks))
	p.skill.run_perks = {}
	var rp: Dictionary = d.get("run_perks", {})
	for k in rp:
		p.skill.run_perks[str(k)] = int(rp[k])
	p.skill.element = int(d.get("element", -1))
	p.skill.trophy_bonus = float(d.get("trophy_bonus", 0.0))
	p.skill.charges = p.skill.max_charges()   # «Дополнительная рука» уже учтена в run_perks
	p.on_gun_changed()
	p.hp = minf(float(d.get("hp", p.max_hp)), p.max_hp)
