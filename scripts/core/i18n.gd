class_name I18n
extends RefCounted
## Локализация. Исходный язык — английский: строки в коде и в data/*.json и есть ключи перевода.
## Переводы — lang/<код>.json (из игры и из модов, слоями):
##   {"meta": {"code": "ru", "name": "Русский"},
##    "templates": {"gun_adj": "{adj} {type_l} {maker}-{num}", ...},   — порядок слов в именах
##    "strings": {"New game": "Новая игра",
##                "Pistol": {"text": "Пистолет", "lower": "пистолет", "g": "m"},   — существительное с родом
##                "Heavy": {"m": "Тяжёлый", "f": "Тяжёлая"}}}                       — прилагательное по родам
## В коде: U.t("Text") — перевод; шаблоны с %d/%s переводятся ДО подстановки: U.t("Zone %d") % n.
## Нет строки в словаре — показывается английский оригинал.
## TranslationServer не используем: у него своя fallback-локаль, и он подсовывал бы чужой язык.

## Английские шаблоны имён (язык-источник). Языки переопределяют их в "templates".
const EN_TEMPLATES := {
	"gun_plain": "{maker}-{num} {type}",
	"gun_adj": "{maker}-{num} {adj} {type}",
	"gun_nick": "{adj} {type} \"{nick}\"",
	"gun_nick2": "{adj} {adj2} {type} \"{nick}\"",
	"gun_legendary": "\"{name}\"",
	"type_hybrid": "{a}-{b}",
	"elite": "{prefix} {type}",
	"rare": "{first} {last}",
	"boss": "{name} the {title}",
}

static var lang := "en"
static var langs := {}      # код -> {"name": ..., "strings": {}, "templates": {}}


## Прочитать все lang/*.json из игры и включённых модов.
static func load_all() -> void:
	langs = {"en": {"name": "English", "strings": {}, "templates": {}}}
	for f in Mods.files("lang", ["json"]):
		var v: Variant = Mods.read_json(str(f[1]))
		if not (v is Dictionary):
			continue
		var d: Dictionary = v
		var meta: Dictionary = d.get("meta", {}) if d.get("meta") is Dictionary else {}
		var code := str(meta.get("code", str(f[0]).get_basename())).to_lower()
		if not langs.has(code):
			langs[code] = {"name": code, "strings": {}, "templates": {}}
		var L: Dictionary = langs[code]
		if meta.has("name"):
			L["name"] = str(meta["name"])
		if d.get("strings") is Dictionary:
			(L["strings"] as Dictionary).merge(d["strings"], true)
		if d.get("templates") is Dictionary:
			(L["templates"] as Dictionary).merge(d["templates"], true)
	if not langs.has(lang):
		lang = "en"


## Коды языков: английский первым, остальные по алфавиту.
static func available() -> Array:
	var out: Array = langs.keys()
	out.erase("en")
	out.sort()
	out.push_front("en")
	return out


static func lang_name(code: String) -> String:
	return str(langs.get(code, {}).get("name", code))


## "" — язык системы, если для него есть перевод, иначе английский.
static func resolve(code: String) -> String:
	if langs.has(code):
		return code
	var os_lang := OS.get_locale_language()
	if os_lang in ["uk", "be"] and langs.has("ru") and not langs.has(os_lang):
		os_lang = "ru"
	return os_lang if langs.has(os_lang) else "en"


static func apply(code: String) -> void:
	lang = resolve(code)


static func current() -> String:
	return lang


static func is_en() -> bool:
	return lang == "en"


static func _entry(s: String) -> Variant:
	var L: Dictionary = langs.get(lang, {})
	var st: Dictionary = L.get("strings", {})
	return st.get(s)


## Перевод строки.
static func t(s: String) -> String:
	var e: Variant = _entry(s)
	if e is String:
		return e
	if e is Dictionary:
		return str(e.get("text", e.get("m", s)))
	if DebugLog.enabled and lang != "en" and s != "":
		DebugLog.missing(lang, s)
	return s


## Форма слова: "lower" (строчная форма существительного), "m"/"f"/"n" (род прилагательного).
static func word(s: String, form: String) -> String:
	var e: Variant = _entry(s)
	if e is Dictionary:
		return str(e.get(form, e.get("text", e.get("m", s))))
	if e is String:
		return (e as String).to_lower() if form == "lower" else e
	return s


## Род существительного ("m" по умолчанию).
static func gender(s: String) -> String:
	var e: Variant = _entry(s)
	if e is Dictionary:
		return str(e.get("g", "m"))
	return "m"


## Шаблон из перевода (или английский) с подстановкой {ключей}.
static func tpl(name: String, vars: Dictionary) -> String:
	var L: Dictionary = langs.get(lang, {})
	var tp: Dictionary = L.get("templates", {})
	return str(tp.get(name, EN_TEMPLATES.get(name, ""))).format(vars)
