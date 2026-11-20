class_name SavesScreen
extends MenuScreen
## «Загрузить игру»: все сейвы забегов (`RunSave`), новые сверху. Слотов может быть сколько угодно, поэтому список постраничный
## (читается только маленький `.meta` слота). У каждой строки — кнопка загрузки и «✕» быстрого удаления без подтверждения;
## «Удалить все» просит второго нажатия.

const PAGE := 10

var _list: VBoxContainer
var _title: Label
var _prev: Button
var _next: Button
var _page_label: Label
var _delete_all: Button
var _page := 0
var _confirm_all := false


func build(root: Control) -> void:
	var box := _screen(root, "saves")
	box.add_child(MenuKit.label(U.t("LOAD GAME"), 52, ACCENT, true))
	_title = MenuKit.label("", 20, DIM)
	box.add_child(_title)
	box.add_child(MenuKit.gap(8))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	box.add_child(_list)
	box.add_child(MenuKit.gap(6))
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 14)
	_prev = MenuKit.button("◀", func() -> void: _go(-1))
	_next = MenuKit.button("▶", func() -> void: _go(1))
	_page_label = MenuKit.label("", 20, TEXT)
	nav.add_child(_prev)
	nav.add_child(_page_label)
	nav.add_child(_next)
	box.add_child(nav)
	box.add_child(MenuKit.gap(6))
	_delete_all = MenuKit.button(U.t("Delete all saves"), _on_delete_all)
	box.add_child(_delete_all)
	var back := MenuKit.button(U.t("Back"), menu.back)
	box.add_child(back)
	menu.first_focus["saves"] = back


func on_town_open(_sname: String) -> void:
	_page = 0


func refresh(_sname: String = "") -> void:
	_confirm_all = false
	_delete_all.text = U.t("Delete all saves")
	var all := RunSave.list_slots()
	var pages := maxi(1, ceili(float(all.size()) / float(PAGE)))
	_page = clampi(_page, 0, pages - 1)
	MenuKit.clear_box(_list)
	_title.text = U.t("Saves: %d") % all.size() if not all.is_empty() else U.t("No saves yet")
	var first: Button = null
	for i in range(_page * PAGE, mini(all.size(), (_page + 1) * PAGE)):
		var m: Dictionary = all[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var load_b := MenuKit.button(RunSave.slot_title(m), _load.bind(str(m["id"])))
		load_b.custom_minimum_size = Vector2(760, 54)
		row.add_child(load_b)
		var del := MenuKit.button("✕", _delete.bind(str(m["id"])))
		del.custom_minimum_size = Vector2(64, 54)
		row.add_child(del)
		_list.add_child(row)
		if first == null:
			first = load_b
	_page_label.text = "%d / %d" % [_page + 1, pages]
	_prev.disabled = _page <= 0
	_next.disabled = _page >= pages - 1
	_delete_all.disabled = all.is_empty()
	_delete_all.visible = not all.is_empty()
	if first != null:
		menu.first_focus["saves"] = first
	if first != null and Game.controls.mode == "pad":
		first.grab_focus.call_deferred()


func _go(d: int) -> void:
	_page += d
	refresh()


func _load(id: String) -> void:
	if not Game.main.continue_run(id):
		Sfx.ui("ui/error", -6.0)
		Game.say(U.t("This save cannot be loaded"), Color(1.0, 0.5, 0.4))
		refresh()


func _delete(id: String) -> void:
	RunSave.delete(id)
	Sfx.ui("ui/error", -10.0)
	refresh()


func _on_delete_all() -> void:
	if not _confirm_all:
		_confirm_all = true
		_delete_all.text = U.t("Really delete all saves? Press again")
		return
	RunSave.delete_all()
	_page = 0
	refresh()
