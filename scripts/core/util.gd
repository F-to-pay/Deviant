class_name U
extends RefCounted
## Общие утилиты: шрифты, стихии, форматирование чисел.

const EL_NONE := -1
const EL_FIRE := 0
const EL_SHOCK := 1
const EL_ACID := 2
const EL_CRYO := 3
const EL_CURSE := 4

const EL_NAMES := ["Огонь", "Электричество", "Кислота", "Холод", "Проклятие"]
const EL_COLORS := [
	Color(1.0, 0.45, 0.12),
	Color(0.45, 0.75, 1.0),
	Color(0.6, 1.0, 0.2),
	Color(0.72, 0.95, 1.0),
	Color(0.7, 0.25, 0.95),
]

const SUFFIXES := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]

static var _font: Font = null
static var _font_bold: Font = null


## Системный шрифт с кириллицей (Segoe UI на винде), фолбэк — встроенный.
static func font() -> Font:
	if _font == null:
		_font = _make_font(400)
	return _font


static func font_bold() -> Font:
	if _font_bold == null:
		_font_bold = _make_font(700)
	return _font_bold


static func _make_font(weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI", "Arial", "Noto Sans", "DejaVu Sans", "Liberation Sans", "sans-serif"])
	f.font_weight = weight
	var fb: Array[Font] = [ThemeDB.fallback_font]
	f.fallbacks = fb
	return f


static func el_color(el: int) -> Color:
	if el < 0 or el >= EL_COLORS.size():
		return Color(1.0, 0.65, 0.25)
	return EL_COLORS[el]


static func el_name(el: int) -> String:
	if el < 0 or el >= EL_NAMES.size():
		return ""
	return t(EL_NAMES[el])


## Перевод строки на текущий язык (см. I18n). Русский — исходный.
static func t(s: String) -> String:
	return I18n.tr_text(s)


## 1234567 -> "1.23M". Бесконечный рогалик — бесконечные цифры.
static func fmt(x: float) -> String:
	var ax := absf(x)
	if ax < 1000.0:
		if ax < 10.0 and absf(x - roundf(x)) > 0.05:
			return "%.1f" % x
		return str(roundi(x))
	var tier := 0
	while ax >= 1000.0 and tier < SUFFIXES.size() - 1:
		ax /= 1000.0
		tier += 1
	if ax >= 1000.0:
		return String.num_scientific(x)
	var s: String
	if ax < 10.0:
		s = "%.2f" % ax
	elif ax < 100.0:
		s = "%.1f" % ax
	else:
		s = "%.0f" % ax
	return ("-" if x < 0.0 else "") + s + str(SUFFIXES[tier])


static func fmt_time(sec: float) -> String:
	var s := int(sec)
	return "%d:%02d" % [s / 60, s % 60]


## Взвешенный выбор индекса.
static func weighted(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for wv in weights:
		total += float(wv)
	if total <= 0.0:
		return 0
	var r := rng.randf() * total
	for i in weights.size():
		r -= float(weights[i])
		if r <= 0.0:
			return i
	return weights.size() - 1


static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Ширина строки, чтобы центрировать текст руками.
static func text_w(f: Font, text: String, fsize: int) -> float:
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x


## Текст с обводкой по центру точки.
static func draw_text_c(ci: CanvasItem, f: Font, at: Vector2, text: String, fsize: int, col: Color, outline: int = 4) -> void:
	var tw := text_w(f, text, fsize)
	var p := Vector2(at.x - tw * 0.5, at.y)
	if outline > 0:
		ci.draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, Color(0, 0, 0, col.a * 0.85))
	ci.draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


static func draw_text(ci: CanvasItem, f: Font, at: Vector2, text: String, fsize: int, col: Color, outline: int = 0) -> void:
	if outline > 0:
		ci.draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, Color(0, 0, 0, col.a * 0.85))
	ci.draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


static func draw_text_r(ci: CanvasItem, f: Font, at: Vector2, text: String, fsize: int, col: Color, outline: int = 0) -> void:
	var tw := text_w(f, text, fsize)
	draw_text(ci, f, Vector2(at.x - tw, at.y), text, fsize, col, outline)


## Правильный многоугольник (для врагов и прочего).
static func ngon(sides: int, r: float, rot: float = 0.0, star: bool = false) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := sides * 2 if star else sides
	for i in n:
		var rr := r
		if star and i % 2 == 1:
			rr = r * 0.5
		pts.append(Vector2.from_angle(rot + TAU * float(i) / float(n)) * rr)
	return pts


static func closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if pts.size() > 0:
		out.append(pts[0])
	return out
