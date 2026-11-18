class_name GunPreview
extends Control
## Карточка пушки внутри экранов меню (лавки): та же GunCard, что и в игре, со сравнением.
## Высота у места под карточку всегда одна (H): иначе высокая карточка (Кузня хаоса, много перков) растягивала бы экран
## и сдвигала заголовок со списками. Если карточка выше места, она просто выходит вниз, не выходя за экран.

const H := 760.0

var gun: Gun = null
var cmp: Gun = null


func _init() -> void:
	custom_minimum_size = Vector2(GunCard.W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_gun(g: Gun, compare: Gun = null) -> void:
	gun = g
	cmp = compare
	queue_redraw()


func _draw() -> void:
	if gun == null:
		return
	# карточка не должна уходить за нижний край экрана: поднимаем её, но верх не выше края
	var off := 0.0
	var vp := get_viewport()
	if vp != null and is_inside_tree():
		var top := get_global_transform_with_canvas().origin.y
		var s := get_global_transform_with_canvas().get_scale().y
		var vh := vp.get_visible_rect().size.y
		off = maxf(8.0 - top, minf(0.0, (vh - 8.0 - top) / maxf(s, 0.01) - GunCard.height(gun))) if s > 0.0 else 0.0
		off = minf(off, 0.0)
	GunCard.draw_card(self, gun, Vector2(0.0, off), cmp)
