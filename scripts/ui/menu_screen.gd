class_name MenuScreen
extends RefCounted
## Основа экрана меню. Экран строит свои узлы в `build(root)` (при старте и после смены языка), обновляет их в
## `refresh()` (каждый раз, когда его показывают) и реагирует на события `Menu` через необязательные хуки ниже.
## Навигация, режимы и жизненный цикл — в `Menu`; общие виджеты — в `MenuKit`.
## Один объект может обслуживать несколько экранов (дерево навыков — по экрану на ветку): id регистрируются в `add_screen`.

const ACCENT := MenuKit.ACCENT
const TEXT := MenuKit.TEXT
const DIM := MenuKit.DIM
const PANEL_BG := MenuKit.PANEL_BG
const SCREEN_ACCENT := MenuKit.SCREEN_ACCENT

var menu: Menu


func _init(m: Menu = null) -> void:
	menu = m


## Построить узлы экрана в root (вызывается заново при каждой перестройке меню).
func build(_root: Control) -> void:
	pass


## Экран показывают (или переключаются на него): подтянуть значения. sname — id показанного экрана.
func refresh(_sname: String = "") -> void:
	pass


## Лавка или экран из города открывается через `Menu.open_town(sname)` (любой экран: сбросить временное состояние).
func on_town_open(_sname: String) -> void:
	pass


## Меню перестроено (язык): подписи, которые заполняются не в build().
func after_rebuild() -> void:
	pass


## Сменили устройство ввода (kbm / pad / touch).
func on_input_mode(_m: String) -> void:
	pass


## Кадр, пока этот экран текущий.
func process(_delta: float) -> void:
	pass


## Нажали Esc / «назад», пока экран текущий. true — экран обработал сам (меню ничего больше не делает).
func on_back() -> bool:
	return false


## Куда ведёт «назад», если не в режим меню (например, «Управление» → «Настройки»). "" — в режим.
func back_target() -> String:
	return ""


## Экран ждёт нажатия клавиши (переназначение): меню не обрабатывает Esc и отдаёт ему событие `handle_input`.
func captures_input() -> bool:
	return false


func handle_input(_event: InputEvent) -> void:
	pass


## Рамка экрана и его регистрация в меню (см. `Menu.add_screen`).
func _screen(root: Control, sname: String, top: bool = false) -> VBoxContainer:
	return menu.add_screen(root, sname, self, top)


## Экран с собственной раскладкой (без рамки-панели): регистрируем корневой узел сами.
func _register(sname: String, ctl: Control) -> void:
	menu.screens[sname] = ctl
	menu.logic[sname] = self
