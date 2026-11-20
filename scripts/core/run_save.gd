class_name RunSave
extends RefCounted
## Сохранения забегов: по слоту на забег, сколько угодно (папка `user://saves/`). Новая игра создаёт новый слот и ничего не стирает.
## На слот два файла: `<id>.save` — весь забег (заголовок `DEVRUN1:` и base64 от `var_to_bytes`: бинарно, чтобы числа возвращались
## бит в бит, а текст `var_to_str` теряет последний разряд) и `<id>.meta` — маленькое описание (JSON) для списка. Список читает только
## `.meta`, поэтому тысяча слотов открывается мгновенно. Файл `latest` хранит id последнего слота (кнопка «Продолжить»).
## Контрольная точка ставится при старте забега и при входе в каждую зону и город (`Main.checkpoint`); продолжить можно только с начала
## локации (враги и лут на карте не сохраняются — иначе «сейв-скам»). Смерть стирает слот, если в параметрах забега не включено
## `keep_save` (оставлять сейв: −50% опыта и рейтинга, рекорды не засчитываются). Загрузка — `Main.continue_run(id)`.
## В слоте: параметры забега, `RunState`, герой, пушки целиком (`Gun.to_dict`, а не сид — генератор меняется), запас патронов, фляги,
## перки навыка и состояние ГСЧ ДО генерации локации — по нему карта и товар города получаются теми же.

const DIR := "user://saves"
const LEGACY_PATH := "user://run.save"   # одиночный сейв первой версии: переносится в слот при первом обращении
const VERSION := 1
const MAGIC := "DEVRUN1:"


# --- Слоты ---------------------------------------------------------------------------

## Новый уникальный id слота (время в мс + случайный хвост; глобальный randi, чтобы не трогать ГСЧ забега).
static func new_id() -> String:
	return "%d_%04x" % [int(Time.get_unix_time_from_system() * 1000.0), randi() & 0xffff]


static func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)


static func _save_path(id: String) -> String:
	return DIR.path_join(id + ".save")


static func _meta_path(id: String) -> String:
	return DIR.path_join(id + ".meta")


static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(_abs(DIR))


## id годится как имя файла (мы сами их создаём, но удаление по id из внешнего ввода не должно выходить из папки).
static func _safe_id(id: String) -> bool:
	return id != "" and not id.contains("/") and not id.contains("\\") and not id.contains("..")


static func exists(id: String) -> bool:
	return _safe_id(id) and FileAccess.file_exists(_save_path(id))


## Сколько слотов (быстро: только считаем файлы описаний).
static func count() -> int:
	_migrate_legacy()
	var n := 0
	for f in DirAccess.get_files_at(_abs(DIR)):
		if str(f).ends_with(".meta"):
			n += 1
	return n


## Описания всех слотов, новые сверху. Нечитаемые описания и описания без файла сейва пропускаются.
static func list_slots() -> Array:
	_migrate_legacy()
	var out: Array = []
	for f in DirAccess.get_files_at(_abs(DIR)):
		var name := str(f)
		if not name.ends_with(".meta"):
			continue
		var id := name.trim_suffix(".meta")
		var m := _read_meta(id)
		if m.is_empty() or not FileAccess.file_exists(_save_path(id)):
			continue
		out.append(m)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["saved_at"]) > int(b["saved_at"]) or (int(a["saved_at"]) == int(b["saved_at"]) and str(a["id"]) > str(b["id"])))
	return out


## Описание последнего сохранённого слота ({} — слотов нет).
static func latest() -> Dictionary:
	_migrate_legacy()
	var ptr := _abs(DIR.path_join("latest"))
	if FileAccess.file_exists(DIR.path_join("latest")):
		var id := FileAccess.get_file_as_string(DIR.path_join("latest")).strip_edges()
		if _safe_id(id) and exists(id):
			var m := _read_meta(id)
			if not m.is_empty():
				return m
	var all := list_slots()
	return all[0] if not all.is_empty() else {}


static func _read_meta(id: String) -> Dictionary:
	if not FileAccess.file_exists(_meta_path(id)):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(_meta_path(id)))
	if not (v is Dictionary) or not (v as Dictionary).has("saved_at") or not (v as Dictionary).has("zone"):
		return {}
	var m: Dictionary = v
	m["id"] = id
	for k in ["saved_at", "started_at", "zone", "hero_level"]:
		m[k] = int(m.get(k, 0))
	return m


static func delete(id: String) -> void:
	if not _safe_id(id):
		return
	for p in [_save_path(id), _meta_path(id)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(_abs(p))


## Стереть все слоты (кнопка «Удалить все»). Возвращает, сколько их было.
static func delete_all() -> int:
	var n := 0
	for f in DirAccess.get_files_at(_abs(DIR)):
		var name := str(f)
		if name.ends_with(".meta"):
			n += 1
		DirAccess.remove_absolute(_abs(DIR.path_join(name)))
	if FileAccess.file_exists(LEGACY_PATH):
		DirAccess.remove_absolute(_abs(LEGACY_PATH))
	return n


## Одиночный `user://run.save` из первой версии становится обычным слотом.
static func _migrate_legacy() -> void:
	if not FileAccess.file_exists(LEGACY_PATH):
		return
	var r := _read_path(LEGACY_PATH)
	DirAccess.remove_absolute(_abs(LEGACY_PATH))
	if not bool(r["ok"]):
		return
	var d: Dictionary = r["data"]
	var id := new_id()
	_ensure_dir()
	var f := FileAccess.open(_save_path(id), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(encode(d))
	f.close()
	_write_meta(id, meta_of(d, id))


# --- Содержимое ----------------------------------------------------------------------

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


## Описание слота для списка: всё, что нужно показать, не читая сам сейв.
static func meta_of(d: Dictionary, id: String) -> Dictionary:
	var st: Dictionary = d["state"]
	return {"id": id, "saved_at": int(d.get("saved_at", 0)), "started_at": int(st.get("started_at", d.get("saved_at", 0))),
		"zone": int((d["checkpoint"] as Dictionary)["level"]), "town": bool((d["checkpoint"] as Dictionary).get("town", false)),
		"hero": str((d["player"] as Dictionary).get("hero", Heroes.DEFAULT)), "hero_level": int(st.get("hero_level", 1)),
		"keep": bool((d["run"] as Dictionary).get("keep_save", false))}


static func _write_meta(id: String, m: Dictionary) -> void:
	var tmp := _meta_path(id) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(m))
	f.close()
	if FileAccess.file_exists(_meta_path(id)):
		DirAccess.remove_absolute(_abs(_meta_path(id)))
	DirAccess.rename_absolute(_abs(tmp), _abs(_meta_path(id)))


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


## Записать контрольную точку в слот текущего забега (`Game.state.save_id`; пустой — выдаётся новый). Сначала сейв во временный файл
## и переименование: если процесс убьют посреди записи, прежний сейв цел. Потом описание и указатель на последний слот.
static func write(main: Main, level: int, to_town: bool) -> bool:
	if Game.state.save_id == "":
		Game.state.save_id = new_id()
	var id: String = Game.state.save_id
	_ensure_dir()
	var snap := snapshot(main, level, to_town)
	var tmp := _save_path(id) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		Game.debug_log.warn("run save: cannot write %s" % tmp, "save")
		return false
	f.store_string(encode(snap))
	f.close()
	if FileAccess.file_exists(_save_path(id)):
		DirAccess.remove_absolute(_abs(_save_path(id)))
	if DirAccess.rename_absolute(_abs(tmp), _abs(_save_path(id))) != OK:
		return false
	_write_meta(id, meta_of(snap, id))
	var lf := FileAccess.open(DIR.path_join("latest"), FileAccess.WRITE)
	if lf != null:
		lf.store_string(id)
		lf.close()
	return true


## Прочитать и проверить сейв слота. {"ok": bool, "reason": "none" / "corrupt" / "version" / "invalid", "data": {...}, "warnings": [строки]}.
static func read(id: String) -> Dictionary:
	if not exists(id):
		return {"ok": false, "reason": "none", "data": {}, "warnings": []}
	return _read_path(_save_path(id))


static func _read_path(path: String) -> Dictionary:
	var res := {"ok": false, "reason": "none", "data": {}, "warnings": []}
	if not FileAccess.file_exists(path):
		return res
	var v: Variant = decode(FileAccess.get_file_as_string(path))
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


# --- Подписи -------------------------------------------------------------------------

## «Зона 12 · Первопроходец · уровень 9» (по описанию слота).
static func summary(m: Dictionary) -> String:
	return U.t("Zone %d · %s · level %d") % [int(m["zone"]), Heroes.hero_name(str(m.get("hero", Heroes.DEFAULT))), int(m.get("hero_level", 1))]


## Дата и время по местным часам: «21.11 14:05».
static func when(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var dt := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%02d.%02d %02d:%02d" % [int(dt["day"]), int(dt["month"]), int(dt["hour"]), int(dt["minute"])]


## Строка слота в списке: описание, время, пометка «сейв остаётся после смерти».
static func slot_title(m: Dictionary) -> String:
	var t := "%s · %s" % [summary(m), when(int(m["saved_at"]))]
	if bool(m.get("keep", false)):
		t += " · " + U.t("keeps save")
	return t


# --- Загрузка ------------------------------------------------------------------------

## Развернуть сейв в игре: параметры, состояние забега, герой с пушками. Локацию грузит вызывающий (`Main.continue_run`).
static func restore(main: Main, d: Dictionary, id: String) -> void:
	Game.run = RunConfig.DEFAULTS.duplicate()
	Game.run.merge(d["run"], true)
	var st: Dictionary = d["state"]
	Game.state.seed_value = int(st.get("seed_value", 0))
	main.rng.seed = Game.state.seed_value
	Game.new_run()
	Game.state.from_dict(st)
	Game.state.save_id = id   # продолжение пишет в тот же слот
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
