class_name MenuKit
extends RefCounted
## Общие виджеты и цвета экранов меню: подписи, кнопки, рамки, тема, строки списков пушек. Только статические функции
## без состояния — ими пользуются и `Menu` (оболочка), и экраны (`ui/screens/*.gd`).

const ACCENT := Color(1.0, 0.55, 0.2)
const TEXT := Color(0.9, 0.9, 0.95)
const DIM := Color(0.6, 0.6, 0.68)
## Панели экранов — как карточка пушки (GunCard): тёмный фон, цветная полоса сверху и рамка того же цвета.
const PANEL_BG := Color(0.05, 0.05, 0.07, 0.94)
const SCREEN_ACCENT := {"shop": Color(1.0, 0.62, 0.25), "mystic": Color(0.78, 0.45, 1.0), "workshop": Color(0.45, 0.75, 1.0),
	"guild": Color(0.5, 0.9, 0.45), "healer": Color(1.0, 0.4, 0.45), "heroes": Color(0.4, 0.85, 1.0), "custom": Color(1.0, 0.82, 0.35)}


static func label(text: String, fsize: int, col: Color, bold: bool = false,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", U.font_bold())
		l.add_theme_constant_override("outline_size", 10)
	return l


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	b.pressed.connect(Callable(MenuKit, "_click_sfx"))
	hover_sfx(b)
	return b


## Звук наведения на кнопку (не на заблокированную).
static func hover_sfx(b: Button) -> void:
	b.mouse_entered.connect(Callable(MenuKit, "_on_hover").bind(b))


static func _on_hover(b: Button) -> void:
	if not b.disabled:
		Sfx.ui("ui/hover", -12.0, 1.0, 0.05)


static func _click_sfx() -> void:
	Sfx.ui("ui/click", -6.0)


static func gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func box(bgc: Color, border: Color, bw: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bgc
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## Рамка как у карточки пушки: фон PANEL_BG, полоса accent сверху (6 px), рамка accent (2 px).
static func card_style(accent: Color, mx: int = 14, my: int = 10, top_bar: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = Color(accent, 0.85)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_width_top = top_bar
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	return sb


static func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = U.font()
	th.default_font_size = 22
	th.set_font("font", "Button", U.font_bold())
	th.set_font_size("font_size", "Button", 26)
	th.set_stylebox("normal", "Button", box(Color(0.07, 0.07, 0.11, 0.88), Color(0.3, 0.3, 0.42)))
	th.set_stylebox("hover", "Button", box(Color(0.16, 0.12, 0.2, 0.95), ACCENT))
	th.set_stylebox("pressed", "Button", box(Color(0.35, 0.18, 0.08, 0.95), ACCENT))
	th.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), ACCENT.lightened(0.2), 3))
	th.set_stylebox("disabled", "Button", box(Color(0.05, 0.05, 0.07, 0.6), Color(0.2, 0.2, 0.25)))
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color(1.0, 0.85, 0.55))
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_focus_color", "Button", Color(1.0, 0.85, 0.55))
	th.set_color("font_disabled_color", "Button", Color(0.4, 0.4, 0.45))
	th.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	th.set_constant("outline_size", "Label", 4)
	var track := box(Color(0.12, 0.12, 0.18), Color(0.3, 0.3, 0.42), 1)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	th.set_stylebox("slider", "HSlider", track)
	var fill := box(ACCENT.darkened(0.2), ACCENT, 1)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return th


## Прокручиваемый список: [ScrollContainer, VBoxContainer внутри].
static func list_box(minw: float, minh: float) -> Array:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.custom_minimum_size = Vector2(minw, minh)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	return [sc, vb]


static func clear_box(b: Container) -> void:
	for c in b.get_children():
		b.remove_child(c)
		c.queue_free()


## Кнопка-строка пушки: цвет редкости, наведение/фокус — карточка в preview.
static func gun_row(g: Gun, text: String, cb: Callable, preview: GunPreview) -> Button:
	var b := button(text, cb)
	b.custom_minimum_size = Vector2(440, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", g.rarity_color())
	b.mouse_entered.connect(Callable(MenuKit, "_show_card").bind(g, preview))
	b.focus_entered.connect(Callable(MenuKit, "_show_card").bind(g, preview))
	return b


static func _show_card(g: Gun, preview: GunPreview) -> void:
	preview.show_gun(g, Game.main.player.gun() if Game.main.player.gun() != g else null)


static func small_button(text: String, cb: Callable, w: float = 440.0) -> Button:
	var b := button(text, cb)
	b.custom_minimum_size = Vector2(w, 44)
	b.add_theme_font_size_override("font_size", 17)
	return b


## Все пушки игрока: [пушка, "slot"/"bag", индекс].
static func player_guns() -> Array:
	var p: Player = Game.main.player
	var out: Array = []
	for i in 4:
		if p.guns[i] != null:
			out.append([p.guns[i], "slot", i])
	for i in p.backpack.size():
		out.append([p.backpack[i], "bag", i])
	return out


static func gun_where(e: Array) -> String:
	return (U.t("slot %d") % (int(e[2]) + 1)) if str(e[1]) == "slot" else U.t("backpack")


## Геймпад: фокус на первую доступную кнопку списка (с мышью и сенсором фокус не нужен).
static func grab_first(box_node: Container) -> void:
	if Game.controls.mode != "pad":
		return
	for c in box_node.get_children():
		if c is Button and not (c as Button).disabled:
			(c as Button).grab_focus.call_deferred()
			return


static func fmt(v: float, f: String) -> String:
	if f == "pct":
		return "%d%%" % roundi(v * 100.0)
	if f == "px":
		return "%d" % roundi(v)
	return str(v)
