class_name UiFit
extends RefCounted
## Размер интерфейса и отступы от краёв экрана.
##  ui_scale — масштаб всего интерфейса (HUD, меню, инвентарь, экранные кнопки): слой CanvasLayer
##  масштабируется, а его корневые Control получают размер «экран / масштаб». Мир не трогается.
##  ui_margin_x / ui_margin_y — отступ от краёв (в пикселях базового экрана 1920×1080), чтобы
##  скруглённые углы и вырезы телефона не съедали интерфейс. ui_safe_area — на телефоне ещё и
##  учесть безопасную зону, которую сообщает система (вырез под камеру и т.п.).
## Кто использует: HUD, Menu, TouchControls — зовут fit() при запуске, смене настроек и размера окна.

const KEYS := ["ui_scale", "ui_margin_x", "ui_margin_y", "ui_safe_area"]


static func scale() -> float:
	return clampf(float(Game.setting("ui_scale")), 0.7, 1.5)


## Отступы (слева, сверху, справа, снизу) в координатах вьюпорта.
static func insets(vp: Viewport) -> Vector4:
	var size := vp.get_visible_rect().size
	var mx := float(Game.setting("ui_margin_x"))
	var my := float(Game.setting("ui_margin_y"))
	var out := Vector4(mx, my, mx, my)
	if bool(Game.setting("ui_safe_area")) and (OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")):
		var safe := DisplayServer.get_display_safe_area()
		var wpos := DisplayServer.window_get_position()
		var wsize := DisplayServer.window_get_size()
		if wsize.x > 0 and wsize.y > 0 and safe.size.x > 0:
			var k := size / Vector2(wsize)
			out.x = maxf(out.x, float(safe.position.x - wpos.x) * k.x)
			out.y = maxf(out.y, float(safe.position.y - wpos.y) * k.y)
			out.z = maxf(out.z, float((wpos.x + wsize.x) - (safe.position.x + safe.size.x)) * k.x)
			out.w = maxf(out.w, float((wpos.y + wsize.y) - (safe.position.y + safe.size.y)) * k.y)
	return out


## Слой — в масштаб; full — на весь экран, safe — внутри отступов. Координаты Control — в единицах слоя.
static func fit(layer: CanvasLayer, full: Array, safe: Array) -> void:
	var s := scale()
	layer.scale = Vector2(s, s)
	var vp := layer.get_viewport()
	if vp == null:
		return
	var size := vp.get_visible_rect().size / s
	var ins := insets(vp) / s
	for o in full:
		var c: Control = o
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		c.position = Vector2.ZERO
		c.size = size
	for o in safe:
		var c: Control = o
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		c.position = Vector2(ins.x, ins.y)
		c.size = Vector2(maxf(100.0, size.x - ins.x - ins.z), maxf(100.0, size.y - ins.y - ins.w))


## Для Control внутри уже подогнанного корня: на весь родитель, но с отступами.
static func inset(c: Control) -> void:
	var vp := c.get_viewport()
	if vp == null:
		return
	var ins := insets(vp) / scale()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = ins.x
	c.offset_top = ins.y
	c.offset_right = -ins.z
	c.offset_bottom = -ins.w
