class_name Warmup
extends Node
## Прогрев под экраном загрузки: при запуске (перед главным меню) и после каждого перескана модов
## (включил/выключил мод, «Обновить», команда reload) — Main.warmup().
## Всё, что иначе грузилось или компилировалось бы впервые посреди боя и давало фриз:
##  1. Скрипты модов — собираются заранее, а не на первой выпавшей пушке с таким перком.
##  2. Музыка — по следующему треку каждой категории грузится в фоне (Music.prepare_all);
##     дальше Music сам держит следующий трек наготове.
##  3. Шрифты — все буквы (латиница, кириллица, норвежские, символы) во всех размерах и обводках,
##     которыми рисуют HUD, инвентарь, карточки и цифры урона: иначе первый крит или первое
##     сообщение растеризует глифы прямо в бою.
##     Набор букв собирается из всех загруженных переводов и данных — буквы из модов тоже.
##  4. Графика — по разу каждый вид отрисовки (круги, дуги, линии, полилинии, прямоугольники,
##     полигоны, текстуры, сглаживание, трансформы): Vulkan собирает вариант шейдера при первом
##     использовании — пусть это будет здесь. Собранное драйвер кладёт в кэш на диске.
##  5. Пушки — все объекты игры и модов хотя бы раз: пушка каждого типа, каждого производителя,
##     с каждым перком, каждая легендарка. Генерация гоняет их операции и скрипты, а иконка и
##     карточка рисуются по-настоящему (с переводами имён и строк перков).
## Прогрев рисуется на слое под экраном загрузки, игрок его не видит. Ввод пока глушится.

signal finished

const LAYER_WARM := 99
const LAYER_SCREEN := 100
const BG := Color(0.02, 0.02, 0.03)
const ACCENT := Color(1.0, 0.55, 0.2)
const DIM := Color(0.6, 0.6, 0.68)
const MUSIC_TIMEOUT_MS := 20000
const FONT_JOBS_PER_FRAME := 3
const GRAPHICS_FRAMES := 2
const GUNS_PER_FRAME := 8

## [размер, обводка] — ровно те сочетания, которыми рисует игра (U.draw_text*, draw_multiline_string).
## Добавил в коде новый текст другого размера — допиши сюда.
const REGULAR := [[12, 0], [12, 2], [13, 0], [13, 2], [13, 3], [14, 0], [14, 3], [14, 4], [15, 3],
	[16, 0], [18, 0], [18, 3], [22, 3], [22, 4]]
const BOLD := [[13, 3], [14, 0], [14, 2], [14, 4], [15, 0], [15, 3], [15, 4], [16, 0], [16, 3], [16, 4],
	[17, 0], [17, 3], [17, 4], [18, 4], [20, 3], [22, 4], [24, 4], [26, 0], [28, 4], [48, 6], [60, 7]]
## Базовый набор символов; к нему добавляются все буквы из переводов и данных (с модами).
const CHARSET := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~" \
	+ "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя" \
	+ "ÆØÅæøåÄÖÜäöüáéëř«»±·×–—•№→←↔−∞○●♪⚠✖…"

var _screen: Control          # экран загрузки
var _warm: Node2D             # то, что рисуется под ним ради прогрева
var _step := ""
var _progress := 0.0
var _shown := 0.0
var _fade := 1.0
var _done := false
var _jobs: Array = []         # [шрифт, размер, обводка] на этот кадр
var _graphics := false
var _lines := PackedStringArray()
var _tex: ImageTexture
var _guns: Array = []         # пушки на этот кадр
var _was_paused := false
var _glyphs := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true
	var lw := CanvasLayer.new()
	lw.layer = LAYER_WARM
	add_child(lw)
	_warm = Node2D.new()
	lw.add_child(_warm)
	_warm.draw.connect(_draw_warm)

	var ls := CanvasLayer.new()
	ls.layer = LAYER_SCREEN
	add_child(ls)
	_screen = Control.new()
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	ls.add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.draw.connect(_draw_screen)

	var chars := charset()
	_glyphs = chars.length()
	for i in range(0, chars.length(), 40):
		_lines.append(chars.substr(i, 40))
	var img := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0.5))
	_tex = ImageTexture.create_from_image(img)
	_run()


func _input(_event: InputEvent) -> void:
	if not _done:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_shown = move_toward(_shown, _progress, delta * 2.5)
	if _done:
		_fade = maxf(0.0, _fade - delta * 4.0)
		_screen.modulate.a = _fade
		if _fade <= 0.0:
			queue_free()
	_screen.queue_redraw()


func _step_to(text: String, p: float) -> void:
	_step = U.t(text)
	_progress = maxf(_progress, p)


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	await get_tree().process_frame                      # первый кадр — уже экран загрузки

	_step_to("Compiling mod scripts", 0.02)
	await get_tree().process_frame
	compile_scripts()

	_step_to("Loading music", 0.05)
	var music: Music = Game.main.music
	music.prepare_all()
	var tm := Time.get_ticks_msec()
	while music.prepared_ratio() < 1.0 and Time.get_ticks_msec() - tm < MUSIC_TIMEOUT_MS:
		_progress = 0.05 + 0.3 * music.prepared_ratio()
		await get_tree().process_frame
	if music.prepared_ratio() < 1.0:
		DebugLog.warn("music is still loading after %.0f s — continuing" % (MUSIC_TIMEOUT_MS / 1000.0), "warmup")

	_step_to("Preparing fonts", 0.35)
	var jobs: Array = []
	for fs in REGULAR:
		jobs.append([U.font(), int(fs[0]), int(fs[1])])
	for fs in BOLD:
		jobs.append([U.font_bold(), int(fs[0]), int(fs[1])])
	var i := 0
	while i < jobs.size():
		_jobs = jobs.slice(i, i + FONT_JOBS_PER_FRAME)
		i += FONT_JOBS_PER_FRAME
		_warm.queue_redraw()
		await get_tree().process_frame
		_progress = 0.35 + 0.45 * float(mini(i, jobs.size())) / float(jobs.size())
	_jobs = []

	_step_to("Warming up shaders", 0.65)
	_graphics = true
	for k in GRAPHICS_FRAMES:
		_warm.queue_redraw()
		await get_tree().process_frame
	_graphics = false

	_step_to("Trying out every gun", 0.7)
	await get_tree().process_frame
	var guns := make_guns()
	i = 0
	while i < guns.size():
		_guns = guns.slice(i, i + GUNS_PER_FRAME)
		i += GUNS_PER_FRAME
		_warm.queue_redraw()
		await get_tree().process_frame
		_progress = 0.7 + 0.3 * float(mini(i, guns.size())) / float(guns.size())
	_guns = []
	_warm.queue_redraw()

	_step_to("Ready", 1.0)
	DebugLog.info("warmup: %d ms, %d glyphs, %d guns" % [Time.get_ticks_msec() - t0, _glyphs, guns.size()], "warmup")
	await get_tree().process_frame
	_done = true
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().paused = _was_paused
	finished.emit()


## Собрать все скрипты модов заранее (перки, марки, легендарки). Зовётся и после перескана модов.
static func compile_scripts() -> void:
	var entries: Array = GunData.MODS + GunData.LEGENDARIES + GunData.MAKERS.values()
	for e in entries:
		var d: Dictionary = e
		var rel := str(d.get("script", ""))
		if rel != "":
			Mods.script_instance(str(d.get("_root", "res://")), rel)


## Все объекты игры и модов: пушка каждого типа, каждого производителя, с каждым перком
## и каждая легендарка. Генерация прогоняет их операции и скрипты.
static func make_guns() -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1342
	for k in GunData.ARCH:
		out.append(GunGen.generate(1, rng, 0.0, 0, GunData.R_EPIC, str(k)))
	for k in GunData.MAKERS:
		out.append(GunGen.generate(1, rng, 0.0, 0, GunData.R_RARE, "", str(k)))
	for l in GunData.LEGENDARIES:
		GunGen.force_legendary = str(l["id"])
		out.append(GunGen.generate(1, rng, 0.0, 0, GunData.R_LEGENDARY))
	GunGen.force_legendary = ""
	for p in GunData.MODS:
		var id := str(p["id"])
		var g := GunGen.generate(1, rng, 0.0, 0, GunData.R_UNCOMMON)
		if not (id in g.mods):
			GunGen._add_mod(g, id, rng)
			GunGen._finalize(g, rng, {})     # пересобрать иконку и имя уже с этим перком
		out.append(g)
	return out


## Символы для прогрева шрифтов: базовый набор + всё, что есть в переводах (все языки, с модами),
## в именах пушек, перков, производителей, легендарок и в списках имён.
static func charset() -> String:
	var texts := PackedStringArray([CHARSET])
	for code in I18n.langs:
		var L: Dictionary = I18n.langs[code]
		for k in L.get("strings", {}):
			texts.append(str(k))
			var v: Variant = L["strings"][k]
			if v is Dictionary:
				for form in v:
					texts.append(str(v[form]))
			else:
				texts.append(str(v))
		for k in L.get("templates", {}):
			texts.append(str(L["templates"][k]))
	for k in GunData.ARCH:
		texts.append(str(GunData.ARCH[k].get("name", "")) + str(GunData.ARCH[k].get("ammo_name", "")))
	for k in GunData.MAKERS:
		texts.append(str(GunData.MAKERS[k].get("name", "")) + str(GunData.MAKERS[k].get("motto", "")))
	for p in GunData.MODS:
		texts.append(str(p.get("name", "")))
	for l in GunData.LEGENDARIES:
		texts.append(str(l.get("name", "")) + str(l.get("flavor", "")))
	for arr in [GunData.NICKNAMES, GunData.ABSURD_FLAVOR, EnemyData.ELITE_PREFIX, EnemyData.RARE_FIRST,
			EnemyData.RARE_LAST, EnemyData.BOSS_TITLES, EnemyData.BOSS_NAMES]:
		for v in arr:
			texts.append(str(v))
	var seen := {}
	var out := ""
	for t in texts:
		for ch in t:
			if not seen.has(ch) and ch != "\n" and ch != "\t":
				seen[ch] = true
				out += ch
	return out


# --- Отрисовка ----------------------------------------------------------------------

func _draw_screen() -> void:
	var vp := _screen.size
	_screen.draw_rect(Rect2(Vector2.ZERO, vp), BG)
	U.draw_text_c(_screen, U.font_bold(), Vector2(vp.x * 0.5, vp.y * 0.46), "DEVIANT", 96, ACCENT, 0)
	var w := minf(640.0, vp.x * 0.6)
	var r := Rect2(vp.x * 0.5 - w * 0.5, vp.y * 0.53, w, 6.0)
	_screen.draw_rect(r, Color(1, 1, 1, 0.08))
	_screen.draw_rect(Rect2(r.position, Vector2(w * _shown, r.size.y)), ACCENT)
	U.draw_text_c(_screen, U.font(), Vector2(vp.x * 0.5, r.end.y + 34.0), _step, 18, DIM, 0)


func _draw_warm() -> void:
	var c := _warm
	var y := 24.0
	for j in _jobs:
		var f: Font = j[0]
		var fs: int = j[1]
		var ol: int = j[2]
		for line in _lines:
			U.draw_text(c, f, Vector2(16.0, y), line, fs, Color(1, 1, 1, 0.8), ol)
			y += float(fs) + 4.0
	if _graphics:
		_draw_primitives(c, Vector2(80.0, 420.0))
	var x := 40.0
	for k in _guns.size():
		var g: Gun = _guns[k]
		GunIcon.draw_gun(c, g, Vector2(x + 60.0, 120.0), 1.5)
		GunCard.draw_card(c, g, Vector2(x, 180.0), _guns[(k + 1) % _guns.size()])
		x += 240.0


## Каждый вид рисования, которым пользуется игра, — с толщиной -1 (тонкие линии),
## с толщиной, со сглаживанием, с полупрозрачностью и под поворотом/масштабом.
func _draw_primitives(c: CanvasItem, o: Vector2) -> void:
	var col := Color(1.0, 0.55, 0.2, 0.8)
	c.draw_circle(o, 12.0, col)
	c.draw_circle(o + Vector2(40, 0), 12.0, col, false, -1.0)
	c.draw_circle(o + Vector2(80, 0), 12.0, col, false, 3.0, true)
	c.draw_circle(o + Vector2(120, 0), 12.0, col, true, -1.0, true)
	c.draw_arc(o + Vector2(160, 0), 12.0, 0.0, TAU, 24, col, -1.0)
	c.draw_arc(o + Vector2(200, 0), 12.0, 0.0, PI, 12, col, 3.0)
	c.draw_arc(o + Vector2(240, 0), 12.0, 0.0, PI, 12, col, 3.0, true)
	c.draw_line(o + Vector2(270, -10), o + Vector2(290, 10), col, -1.0)
	c.draw_line(o + Vector2(300, -10), o + Vector2(320, 10), col, 2.0)
	c.draw_line(o + Vector2(330, -10), o + Vector2(350, 10), col, 2.0, true)
	var pl := PackedVector2Array([o + Vector2(370, 0), o + Vector2(390, -12), o + Vector2(410, 10), o + Vector2(430, -4)])
	c.draw_polyline(pl, col, -1.0)
	c.draw_polyline(pl, col, 3.0)
	c.draw_polyline(pl, col, 3.0, true)
	c.draw_multiline(pl, col, -1.0)
	c.draw_multiline(pl, col, 2.0)
	c.draw_rect(Rect2(o + Vector2(450, -12), Vector2(24, 24)), col)
	c.draw_rect(Rect2(o + Vector2(480, -12), Vector2(24, 24)), col, false, -1.0)
	c.draw_rect(Rect2(o + Vector2(510, -12), Vector2(24, 24)), col, false, 2.0)
	var poly := U.ngon(6, 14.0)
	var cols := PackedColorArray()
	for k in poly.size():
		cols.append(Color.from_hsv(float(k) / float(poly.size()), 0.7, 1.0, 0.8))
	c.draw_set_transform(o + Vector2(560, 0), 0.6, Vector2(1.2, 0.8))
	c.draw_colored_polygon(poly, col)
	c.draw_polygon(poly, cols)
	c.draw_polyline(U.closed(poly), col, 2.0)
	c.draw_set_transform(o + Vector2(600, 0), 0.0, Vector2.ONE)
	c.draw_colored_polygon(U.ngon(5, 14.0, 0.0, true), col)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	c.draw_texture_rect(_tex, Rect2(o + Vector2(630, -16), Vector2(32, 32)), false)
	c.draw_texture_rect(_tex, Rect2(o + Vector2(670, -16), Vector2(32, 32)), false, Color(1, 0.5, 0.5, 0.6))
