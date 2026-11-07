class_name Codex
extends RefCounted
## Справочник (меню «Справочник»): разделы и страницы из data/codex.json игры и модов.
## Тексты — прямо в JSON по языкам: {"en": [...строки...], "ru": [...]} (строка или массив строк, BBCode).
## Нет текста на текущем языке — берётся английский. Мод может добавить страницу или перевод
## существующей ({"id": "character", "text": {"nb": [...]}} — поля-словари сливаются).
## "auto" у страницы — таблица, которая собирается из текущих данных (с учётом модов):
##   archetypes, makers, rarities, perks, legendaries, enemies, elites, bosses, rating, mods.
## Гайд по моддингу — data/guide.json ({"en": [строки], "ru": [...]}, моды дописывают свои строки);
## кнопка на странице «Моддинг» пишет его в файл рядом с exe, дополняя справкой по текущим данным.

## Описания к автотаблицам: раздел -> {id: {"en": ..., "ru": ...}}. Разделы: archetypes, makers,
## perks, legendaries, enemies, affixes, bosses (у bosses — свои id паттернов, с "name").
const INFO_KINDS := ["archetypes", "makers", "perks", "legendaries", "enemies", "affixes", "bosses"]
const AUTO_KINDS := ["archetypes", "makers", "rarities", "perks", "legendaries", "enemies", "elites", "bosses",
	"rating", "mods"]
const ACTIONS := ["write_guide", "open_mods_folder", "open_game_folder"]

static var sections: Array = []
static var pages: Array = []
static var info: Dictionary = {}
static var guide: Dictionary = {}


static func load_data() -> void:
	sections = []
	pages = []
	info = {}
	for k in INFO_KINDS:
		info[k] = {}
	guide = {}
	for layer in Mods.json_layers("data/codex.json"):
		var d: Variant = layer["data"]
		if not (d is Dictionary):
			continue
		_merge_list(sections, d.get("sections", []))
		_merge_list(pages, d.get("pages", []))
		for k in INFO_KINDS:
			var src: Variant = d.get(k, {})
			if src is Dictionary:
				_deep_merge(info[k], src)
	for layer in Mods.json_layers("data/guide.json"):
		var g: Variant = layer["data"]
		if not (g is Dictionary):
			continue
		for code in g:
			if str(code).begins_with("_"):
				continue
			var lines: Variant = g[code]
			if not guide.has(code):
				guide[code] = []
			if lines is Array:
				(guide[code] as Array).append_array(lines)
			else:
				(guide[code] as Array).append(str(lines))
	# страница мода с несуществующим разделом попадает в «Другое»
	var known := {}
	for s in sections:
		known[str(s["id"])] = true
	for p in pages:
		if not known.has(str(p.get("section", ""))):
			p["section"] = "other"
			if not known.has("other"):
				sections.append({"id": "other", "title": {"en": "Other", "ru": "Другое", "nb": "Annet"}, "order": 999})
				known["other"] = true
	_sort(sections)
	_sort(pages)


## Устойчивая сортировка по "order" (по умолчанию 100): при равенстве — порядок из файлов.
static func _sort(arr: Array) -> void:
	for i in range(1, arr.size()):
		var cur: Dictionary = arr[i]
		var o := float(cur.get("order", 100))
		var j := i - 1
		while j >= 0 and float((arr[j] as Dictionary).get("order", 100)) > o:
			arr[j + 1] = arr[j]
			j -= 1
		arr[j + 1] = cur


static func _merge_list(out: Array, items: Variant) -> void:
	if not (items is Array):
		return
	for v in items:
		if not (v is Dictionary) or not (v as Dictionary).has("id"):
			continue
		var found := false
		for o in out:
			if str(o["id"]) == str(v["id"]):
				_deep_merge(o, v)
				found = true
				break
		if not found:
			out.append((v as Dictionary).duplicate(true))


static func _deep_merge(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		if dst.get(k) is Dictionary and src[k] is Dictionary:
			_deep_merge(dst[k], src[k])
		else:
			dst[k] = src[k]


## Текст на текущем языке: словарь языков (строка или массив строк) или обычная строка (через перевод).
static func loc(v: Variant) -> String:
	if v is Dictionary:
		var d: Dictionary = v
		var x: Variant = d.get(I18n.current(), d.get("en", d.values()[0] if not d.is_empty() else ""))
		if x is Array:
			return "\n".join(PackedStringArray(x))
		return str(x)
	if v is Array:
		return "\n".join(PackedStringArray(v))
	return U.t(str(v)) if v != null else ""


## Описание из codex.json (раздел kind, запись id), "" — если нет.
static func describe(kind: String, id: String) -> String:
	var d: Dictionary = info.get(kind, {})
	return loc(d[id]) if d.has(id) else ""


static func pages_of(section: String) -> Array:
	var out: Array = []
	for p in pages:
		if str(p.get("section", "")) == section:
			out.append(p)
	return out


static func page(id: String) -> Dictionary:
	for p in pages:
		if str(p["id"]) == id:
			return p
	return {}


## Полный текст страницы (BBCode): текст из JSON + автоматическая часть.
static func page_text(p: Dictionary) -> String:
	var out := "[font_size=30][b]%s[/b][/font_size]\n\n" % loc(p.get("title", p["id"]))
	out += loc(p.get("text", ""))
	var auto := str(p.get("auto", ""))
	if auto != "":
		out += "\n\n" + auto_text(auto)
	return out


# --- Автоматические разделы ------------------------------------------------------------

const H := "[color=#ff9a40][b]%s[/b][/color]"
const DIMC := "[color=#9aa0b0]%s[/color]"


static func _c(col: Color, s: String) -> String:
	return "[color=#%s]%s[/color]" % [col.to_html(false), s]


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


static func auto_text(kind: String) -> String:
	match kind:
		"archetypes":
			return _auto_archetypes()
		"makers":
			return _auto_makers()
		"rarities":
			return _auto_rarities()
		"perks":
			return _auto_perks()
		"legendaries":
			return _auto_legendaries()
		"enemies":
			return _auto_enemies()
		"elites":
			return _auto_dict(info["affixes"], EnemyData.AFFIXES)
		"bosses":
			return _auto_dict(info["bosses"], {})
		"rating":
			return _auto_rating()
		"mods":
			return _auto_mods()
	return ""


static func _auto_archetypes() -> String:
	var t := "[table=8]"
	for h in ["Type", "Damage", "Fire rate", "Pellets", "Magazine", "Reload", "Crit", "Ammo"]:
		t += "[cell]%s  [/cell]" % (H % U.t(h))
	for k in GunData.ARCH:
		var a: Dictionary = GunData.ARCH[k]
		t += "[cell]%s  [/cell]" % _c(a["ammo_color"], "[b]%s[/b]" % _esc(U.t(str(a["name"]))))
		t += "[cell]%s[/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell]" % [
			U.fmt(float(a.get("damage", 0))), U.t("%.1f/s") % float(a.get("fire_rate", 0)), str(a.get("pellets", 1)),
			str(a.get("mag", 0)), U.t("%.1f s") % float(a.get("reload", 0)),
			"%d%% ×%.1f" % [roundi(float(a.get("crit", 0)) * 100.0), float(a.get("crit_mult", 2))],
			_esc(GunData.ammo_label(str(a.get("ammo", k))))]
	t += "[/table]\n"
	for k in GunData.ARCH:
		var a: Dictionary = GunData.ARCH[k]
		var notes := PackedStringArray()
		var kind := int(a.get("kind", 0))
		if kind != GunData.K_BULLET and kind != GunData.K_PELLET:
			notes.append(U.t({GunData.K_ROCKET: "rockets", GunData.K_GRENADE: "bouncing grenades",
				GunData.K_ORB: "orbs", GunData.K_SHELL: "arcing shells"}.get(kind, "")))
		if float(a.get("explode", 0)) > 0.0:
			notes.append(U.t("explosion radius %d") % roundi(float(a["explode"])))
		if float(a.get("slug_chance", 0)) > 0.0:
			notes.append(U.t("%d%% chance to be a slug gun") % roundi(float(a["slug_chance"]) * 100.0))
		if str(a.get("ammo", k)) != str(k):
			notes.append(U.t("uses %s ammo") % GunData.ammo_label(str(a["ammo"])))
		var desc := describe("archetypes", str(k))
		if notes.is_empty() and desc == "":
			continue
		t += "\n" + _c(a["ammo_color"], "[b]%s[/b]" % _esc(U.t(str(a["name"])))) + ("  " + DIMC % _esc(", ".join(notes)) if not notes.is_empty() else "")
		if desc != "":
			t += "\n" + desc
	return t


static func _auto_makers() -> String:
	var t := ""
	for k in GunData.MAKERS:
		var m: Dictionary = GunData.MAKERS[k]
		t += _c(m["color"], "[b]%s[/b]" % _esc(U.t(str(m["name"])))) + "   " + DIMC % ("[i]%s[/i]" % _esc(U.t(str(m.get("motto", ""))))) + "\n"
		var fx := PackedStringArray(GunOps.describe(m.get("ops", [])))
		if bool(m.get("no_explosive", false)):
			fx.append(U.t("never explosive"))
		if bool(m.get("no_proc_perks", false)):
			fx.append(U.t("no effect perks"))
		if str(m.get("projectile_arch", "")) != "":
			fx.append(U.t("any type fires %s projectiles, but uses its own ammo") % U.t(str(GunData.ARCH.get(m["projectile_arch"], {}).get("name", m["projectile_arch"]))))
		if bool(m.get("random_legendary_perk", false)):
			fx.append(U.t("random legendary perk"))
		for p in m.get("perks", []):
			fx.append(U.t("always: %s") % U.t(str(GunData.perk(str(p)).get("name", p))))
		if not bool(m.get("legendary", true)):
			fx.append(U.t("never on legendaries"))
		if str(m.get("script", "")) != "":
			fx.append(U.t("+ script"))
		t += "   " + (_esc(", ".join(fx)) if not fx.is_empty() else U.t("no signature effect")) + "\n"
		var desc := describe("makers", str(k))
		if desc != "":
			t += "   " + desc + "\n"
		t += "\n"
	return t


static func _auto_rarities() -> String:
	var t := "[table=5]"
	for h in ["Rarity", "Base chance", "Damage", "Perks", "Hybrid chance"]:
		t += "[cell]%s  [/cell]" % (H % U.t(h))
	var total := 0.0
	for r in GunData.RARITIES:
		total += float(r.get("weight", 0))
	for r in GunData.RARITIES:
		t += "[cell]%s  [/cell][cell]%.1f%%[/cell][cell]×%.2f[/cell][cell]%d[/cell][cell]%d%%[/cell]" % [
			_c(r["color"], "[b]%s[/b]" % _esc(U.t(str(r["name"])))),
			100.0 * float(r.get("weight", 0)) / maxf(total, 0.001), float(r.get("damage_mult", 1)),
			int(r.get("perks", 0)), roundi(float(r.get("hybrid_chance", 0)) * 100.0)]
	return t + "[/table]"


static func _auto_perks() -> String:
	var t := ""
	for p in GunData.MODS:
		if float(p.get("weight", 0)) <= 0.0 and str(p["id"]) != "slug":
			continue
		var tags := PackedStringArray()
		for tg in p.get("tags", []):
			tags.append(U.t({"proc": "effect", "explosive": "explosive", "heal": "healing", "no_shell": "not for mortars"}.get(str(tg), str(tg))))
		var mr := int(p.get("min_rarity", 1))
		var from := (U.t("from %s") % _rar_name(mr)) if mr < GunData.RARITIES.size() else ""
		t += "[b]%s[/b]  %s%s\n" % [_esc(U.t(str(p["name"]))), DIMC % from,
			("  " + DIMC % _esc("· " + ", ".join(tags))) if not tags.is_empty() else ""]
		var desc := describe("perks", str(p["id"]))
		if desc != "":
			t += "   " + desc + "\n"
		var fx := PackedStringArray(GunOps.describe(p.get("ops", [])))
		if str(p.get("script", "")) != "":
			fx.append(U.t("+ script"))
		if str(p["id"]) == "slug":
			fx.append(U.t("shotgun only: all pellets in one solid round"))
		var line := _esc(", ".join(fx)) if not fx.is_empty() else "—"
		t += "   " + (DIMC % line if desc != "" else line) + "\n"
	return t


static func _rar_name(i: int) -> String:
	if GunData.RARITIES.is_empty():
		return str(i)
	var r: Dictionary = GunData.RARITIES[clampi(i, 0, GunData.RARITIES.size() - 1)]
	return _c(r["color"], _esc(U.t(str(r["name"]))))


const SPECIALS := {
	"ring": "Shoots a ring of 8 bullets (40% damage) by chance",
	"nuke10": "Stores damage and fires a nuke",
	"chaos": "Each bullet deals ×0 to ×2 damage",
	"expert": "Lightning hits everyone nearby",
	"singularity": "Every orb is a black hole",
}


static func _auto_legendaries() -> String:
	var t := ""
	var col: Color = GunData.RARITIES[GunData.R_LEGENDARY]["color"]
	for l in GunData.LEGENDARIES:
		var tn := U.t(str(GunData.ARCH.get(str(l.get("arch", "")), {}).get("name", l.get("arch", "?"))))
		if str(l.get("arch2", "")) != "":
			tn += " + " + U.t(str(GunData.ARCH.get(str(l["arch2"]), {}).get("name", l["arch2"])))
		t += _c(col, "[b]%s[/b]" % _esc(I18n.tpl("gun_legendary", {"name": U.t(str(l["name"]))}))) + "  " + DIMC % _esc(tn) + "\n"
		t += "   [i]%s[/i]\n" % _esc(U.t(str(l.get("flavor", ""))))
		var fx := PackedStringArray()
		for m in l.get("perks", []):
			fx.append(U.t(str(GunData.perk(str(m)).get("name", m))))
		fx.append_array(GunOps.describe(l.get("ops", [])))
		var sp := str(l.get("special", ""))
		if sp != "":
			fx.append(U.t(SPECIALS.get(sp, sp)))
		t += "   " + _esc(", ".join(fx)) + "\n"
		var desc := describe("legendaries", str(l["id"]))
		if desc != "":
			t += "   " + desc + "\n"
		t += "\n"
	return t


static func _auto_enemies() -> String:
	var t := "[table=5]"
	for h in ["Enemy", "Health", "Damage", "Speed", "From zone"]:
		t += "[cell]%s  [/cell]" % (H % U.t(h))
	for k in EnemyData.TYPES:
		var e: Dictionary = EnemyData.TYPES[k]
		t += "[cell]%s  [/cell][cell]%d[/cell][cell]%d[/cell][cell]%d[/cell][cell]%d[/cell]" % [
			_c(e["col"], "[b]%s[/b]" % _esc(U.t(str(e["n"])))), roundi(float(e["hp"])), roundi(float(e["dmg"])),
			roundi(float(e["speed"])), int(e["lvl"])]
	t += "[/table]\n" + DIMC % U.t("Health and damage at zone 1; they grow every zone.") + "\n"
	for k in EnemyData.TYPES:
		var desc := describe("enemies", str(k))
		if desc != "":
			t += "\n" + _c(EnemyData.TYPES[k]["col"], "[b]%s[/b]" % _esc(U.t(str(EnemyData.TYPES[k]["n"])))) + " — " + desc
	return t


## Список «имя — описание»: сначала id из кода (names), потом лишние id из описаний.
## Описание — {"en": ..., "ru": ...} или {"name": {...}, "text": {...}}.
static func _auto_dict(desc: Dictionary, names: Dictionary) -> String:
	var t := ""
	var ids: Array = names.keys()
	for k in desc:
		if not (k in ids):
			ids.append(k)
	for k in ids:
		var d: Dictionary = {}
		if desc.get(k) is Dictionary:
			d = desc[k]
		elif desc.has(k):
			d = {"en": str(desc[k])}
		var nm: String = U.t(str(names[k])) if names.has(k) else loc(d.get("name", k))
		var tx := loc(d.get("text", d)) if not d.is_empty() else DIMC % U.t("no description yet")
		t += "[b]%s[/b] — %s\n\n" % [_esc(nm), tx]
	return t


static func _auto_rating() -> String:
	var t := H % U.t("Points") + "\n"
	t += U.t("(zone − 1) × %d + kills × %d + bosses × %d") % [Game.POINTS_ZONE, Game.POINTS_KILL, Game.POINTS_BOSS] + "\n\n"
	t += H % U.t("Multiplier") + "\n" + U.t("enemy health × enemy damage × (1 + bonuses)") + "\n\n"
	for d in Game.DIFFICULTY:
		t += "%s — ×%.2f\n" % [U.t(str(d["n"])), float(d["hp"]) * float(d["dmg"])]
	t += "\n"
	for b in Game.RATING_BONUS:
		var v := float(b[2])
		t += "%s  %s%d%%\n" % [_esc(U.t(str(b[3]))), "+" if v > 0.0 else "−", roundi(absf(v) * 100.0)]
	return t


static func _auto_mods() -> String:
	var t := H % U.t("Installed mods") + "\n"
	if Mods.list.is_empty():
		t += DIMC % U.t("none") + "\n"
	for m in Mods.list:
		var mi: Dictionary = m["info"]
		t += "%s [b]%s[/b] %s\n" % ["[color=#77ee99]●[/color]" if bool(m["enabled"]) else "[color=#666666]○[/color]",
			_esc(str(m["name"])), DIMC % _esc(str(mi.get("description", "")))]
	t += "\n" + DIMC % (U.t("Folder: %s") % _esc(Mods.root()))
	return t


# --- Гайд в файл ----------------------------------------------------------------------

## Записывает гайд (текущий язык) + справку по загруженным данным рядом с exe. Возвращает путь или "".
static func write_guide() -> String:
	var lines: Array = guide.get(I18n.current(), guide.get("en", []))
	var out := PackedStringArray(lines)
	out.append("")
	out.append_array(_reference())
	var path := Mods.base_dir().path_join(U.t("modding_guide.txt"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		DebugLog.error("cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())], "codex")
		return ""
	var nl := "\r\n" if OS.get_name() == "Windows" else "\n"
	f.store_string(nl.join(out) + nl)
	f.close()
	return path


## Справка по тому, что сейчас загружено (игра + включённые моды) — id, поля, звуки.
static func _reference() -> PackedStringArray:
	var r := PackedStringArray()
	var bar := "=".repeat(78)
	r.append(bar)
	r.append(U.t("REFERENCE: what is loaded right now (game + enabled mods)"))
	r.append(bar)
	r.append("")
	r.append("[archetypes]  id — name — damage / fire rate / pellets / mag / reload / kind / ammo")
	for k in GunData.ARCH:
		var a: Dictionary = GunData.ARCH[k]
		r.append("  %-12s %-20s %6.1f / %5.2f / %d / %d / %.1f / %s / %s   [%s]" % [k, str(a["name"]), float(a.get("damage", 0)),
			float(a.get("fire_rate", 0)), int(a.get("pellets", 1)), int(a.get("mag", 0)), float(a.get("reload", 0)),
			_kind_name(int(a.get("kind", 0))), str(a.get("ammo", k)), Mods.source_of(str(a.get("_root", "res://")))])
	r.append("")
	r.append("[makers]  id — name — ops / flags")
	for k in GunData.MAKERS:
		var m: Dictionary = GunData.MAKERS[k]
		var flags := PackedStringArray()
		for fl in ["no_explosive", "no_proc_perks", "random_legendary_perk"]:
			if bool(m.get(fl, false)):
				flags.append(fl)
		if str(m.get("projectile_arch", "")) != "":
			flags.append("projectile_arch=" + str(m["projectile_arch"]))
		if not (m.get("perks", []) as Array).is_empty():
			flags.append("perks=" + JSON.stringify(m["perks"]))
		r.append("  %-12s %-14s %s %s   [%s]" % [k, str(m["name"]), JSON.stringify(m.get("ops", [])), " ".join(flags),
			Mods.source_of(str(m.get("_root", "res://")))])
	r.append("")
	r.append("[perks]  id — name — min_rarity / weight / group / tags — ops")
	for p in GunData.MODS:
		r.append("  %-12s %-18s %d / %s / %s / %s — %s   [%s]" % [str(p["id"]), str(p.get("name", "")), int(p.get("min_rarity", 1)),
			str(p.get("weight", 0)), str(p.get("group", "")), JSON.stringify(p.get("tags", [])), JSON.stringify(p.get("ops", [])),
			Mods.source_of(str(p.get("_root", "res://")))])
	r.append("")
	r.append("[legendaries]  id — name — arch(+arch2) — perks — special")
	for l in GunData.LEGENDARIES:
		r.append("  %-12s %-26s %s%s — %s — %s   [%s]" % [str(l["id"]), str(l.get("name", "")), str(l.get("arch", "")),
			("+" + str(l["arch2"])) if str(l.get("arch2", "")) != "" else "", JSON.stringify(l.get("perks", [])),
			str(l.get("special", "")), Mods.source_of(str(l.get("_root", "res://")))])
	r.append("")
	r.append("[specials]  " + ", ".join(PackedStringArray(SPECIALS.keys())))
	r.append("[enemy types]  " + ", ".join(PackedStringArray(EnemyData.TYPES.keys())))
	r.append("[elite affixes]  " + ", ".join(PackedStringArray(EnemyData.AFFIXES.keys())))
	r.append("[languages]  " + ", ".join(PackedStringArray(I18n.available())))
	r.append("")
	r.append("[gun stats for ops]")
	for s in GunOps.STAT_LABELS:
		r.append("  %-18s %s" % [s, U.t(str(GunOps.STAT_LABELS[s]))])
	if Game.main != null and Game.main.sfx != null:
		var keys: Array = Game.main.sfx.banks.keys()
		keys.sort()
		r.append("")
		r.append("[sound banks]  (sfx/<key>/ — folder = bank, file path without extension = single sound)")
		var row := PackedStringArray()
		for k in keys:
			row.append(str(k))
			if row.size() == 6:
				r.append("  " + ", ".join(row))
				row = PackedStringArray()
		if not row.is_empty():
			r.append("  " + ", ".join(row))
	r.append("")
	r.append("[mods]")
	for m in Mods.list:
		r.append("  %s %s  (%s)" % ["[on] " if bool(m["enabled"]) else "[off]", str(m["id"]), str(m["path"])])
	return r


static func _kind_name(k: int) -> String:
	for n in GunOps.KINDS:
		if int(GunOps.KINDS[n]) == k:
			return str(n)
	return str(k)
