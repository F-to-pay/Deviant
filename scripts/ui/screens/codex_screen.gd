class_name CodexScreen
extends MenuScreen
## Справочник: слева разделы и страницы (data/codex.json игры и модов), справа текст.

var _codex_page := ""
var _codex_text: RichTextLabel
var _codex_actions: HBoxContainer
var _codex_status: Label
var _codex_buttons := {}  # id страницы -> кнопка в списке
## Кнопки, которые страница справочника может попросить в "actions" (data/codex.json).
const CODEX_ACTIONS := {
	"write_guide": ["Create modding guide", "_codex_write_guide"],
	"open_mods_folder": ["Open mods folder", "_open_mods_folder"],
	"open_game_folder": ["Open game folder", "_open_game_folder"],
}


## Окно справочника: слева разделы и страницы (data/codex.json игры и модов), справа текст.
func build(root: Control) -> void:
	_codex_buttons.clear()
	var holder := MarginContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		holder.add_theme_constant_override("margin_" + side, 40)
	root.add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_register("codex", holder)
	var panel := PanelContainer.new()
	var sb := MenuKit.box(Color(0.035, 0.035, 0.06, 0.95), Color(0.3, 0.3, 0.42))
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)
	var title := MenuKit.label(U.t("CODEX"), 40, ACCENT, true, HORIZONTAL_ALIGNMENT_LEFT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var back := MenuKit.button(U.t("Back"), func() -> void: menu.show_screen(menu.mode))
	back.custom_minimum_size = Vector2(200, 48)
	top.add_child(back)
	menu.first_focus["codex"] = back

	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	hb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var group := ButtonGroup.new()
	for sec in Codex.sections:
		var pg := Codex.pages_of(str(sec["id"]))
		if pg.is_empty():
			continue
		if list.get_child_count() > 0:
			list.add_child(MenuKit.gap(6))
		list.add_child(MenuKit.label(Codex.loc(sec.get("title", sec["id"])).to_upper(), 16, DIM, true, HORIZONTAL_ALIGNMENT_LEFT))
		for p in pg:
			var id := str(p["id"])
			var b := Button.new()
			b.text = Codex.loc(p.get("title", id))
			b.toggle_mode = true
			b.button_group = group
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(300, 40)
			b.add_theme_font_size_override("font_size", 19)
			b.pressed.connect(_codex_open.bind(id))
			b.pressed.connect(func() -> void: Sfx.ui("ui/click", -8.0))
			MenuKit.hover_sfx(b)
			list.add_child(b)
			_codex_buttons[id] = b
			if _codex_page == "":
				_codex_page = id

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	hb.add_child(right)
	_codex_text = RichTextLabel.new()
	_codex_text.bbcode_enabled = true
	_codex_text.selection_enabled = true
	_codex_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_codex_text.add_theme_font_override("normal_font", U.font())
	_codex_text.add_theme_font_override("bold_font", U.font_bold())
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "mono_font_size"]:
		_codex_text.add_theme_font_size_override(k, 19)
	_codex_text.add_theme_color_override("default_color", TEXT)
	_codex_text.add_theme_constant_override("line_separation", 3)
	_codex_text.add_theme_constant_override("table_h_separation", 4)
	_codex_text.add_theme_constant_override("table_v_separation", 2)
	right.add_child(_codex_text)
	_codex_actions = HBoxContainer.new()
	_codex_actions.add_theme_constant_override("separation", 12)
	right.add_child(_codex_actions)
	_codex_status = MenuKit.label("", 16, ACCENT, false, HORIZONTAL_ALIGNMENT_LEFT)
	_codex_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_codex_status)


func show_page(id: String) -> void:
	_codex_page = id
	menu.show_screen("codex")


func _codex_open(id: String) -> void:
	var p := Codex.page(id)
	if p.is_empty():
		if Codex.pages.is_empty():
			_codex_text.text = U.t("The codex is empty.")
			return
		p = Codex.pages[0]
		id = str(p["id"])
	_codex_page = id
	for k in _codex_buttons:
		(_codex_buttons[k] as Button).set_pressed_no_signal(k == id)
	_codex_text.text = Codex.page_text(p)
	_codex_text.scroll_to_line(0)
	for c in _codex_actions.get_children():
		_codex_actions.remove_child(c)
		c.queue_free()
	_codex_status.text = ""
	for a in p.get("actions", []):
		var spec: Array = CODEX_ACTIONS.get(str(a), [])
		if spec.is_empty():
			continue
		var b := MenuKit.button(U.t(str(spec[0])), Callable(self, str(spec[1])))
		b.custom_minimum_size = Vector2(0, 48)
		b.add_theme_font_size_override("font_size", 20)
		_codex_actions.add_child(b)
	_codex_actions.visible = _codex_actions.get_child_count() > 0


func _open_mods_folder() -> void:
	ModsScreen.open_mods_folder()


func _open_game_folder() -> void:
	ModsScreen.open_game_folder()


func _codex_write_guide() -> void:
	var path := Codex.write_guide()
	if path == "":
		_codex_status.text = U.t("Could not write the guide. Is the game folder read-only?")
		_codex_status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		return
	_codex_status.text = U.t("Guide saved: %s") % path
	_codex_status.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	OS.shell_open(path)


func refresh(_sname: String = "") -> void:
	_codex_open(_codex_page)


## Геймпад: правый стик листает текст справочника.
func process(delta: float) -> void:
	if menu.visible and Game.controls.mode == "pad" and _codex_text != null:
		var v := Input.get_axis("aim_up", "aim_down")
		if absf(v) > 0.2:
			var bar := _codex_text.get_v_scroll_bar()
			bar.value += v * 1400.0 * delta
