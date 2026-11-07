class_name I18n
extends RefCounted
## Локализация. Исходный язык — русский: строки в коде и есть ключи перевода.
## Английский — словарь LangEn.EN (русская строка -> английская). В коде: U.t("строка").
## Шаблоны с %d/%s переводятся ДО подстановки: U.t("Зона %d") % n.
## TranslationServer не используем: у него fallback-локаль "en", и при русском языке
## он всё равно подсовывал бы английский.

const LANGS := ["ru", "en"]
const LANG_NAMES := {"ru": "Русский", "en": "English"}

static var lang := "ru"


## "" — по языку системы (русский/украинский/белорусский -> ru, иначе en).
static func resolve(code: String) -> String:
	if code in LANGS:
		return code
	var os_lang := OS.get_locale_language()
	return "ru" if os_lang in ["ru", "uk", "be"] else "en"


static func apply(code: String) -> void:
	lang = resolve(code)


static func current() -> String:
	return lang


static func is_en() -> bool:
	return lang == "en"


static func tr_text(s: String) -> String:
	if lang == "en":
		return str(LangEn.EN.get(s, s))
	return s
