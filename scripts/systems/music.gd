class_name Music
extends Node
## Музыка: сама находит треки в res://music/ и раскладывает их по категориям.
##  Категория — по префиксу имени файла (zone_, boss_, calm_, death_), иначе по имени папки.
##  zone  — обычные зоны, перемешанный плейлист, трек не рвётся при смене зоны.
##  boss  — арена с боссом.        calm  — пауза (Esc) и передышка после босса.
##  death — экран смерти.          menu  — главное меню (нет своих — играет calm).
## Пауза уводит в calm и потом возвращает прерванный трек с того же места.
## Инвентарь — музыка глохнет (приглушение + фильтр низких частот).
## Шины Music и SFX создаются кодом; громкость — в настройках Game (deviant.cfg).

const CATS := ["zone", "boss", "calm", "death", "menu"]
const EXTS := ["ogg", "mp3", "wav"]
const ROOT := "res://music/"
const FADE := 1.5            # кроссфейд по умолчанию, с
const MUFFLE_CUTOFF := 700.0
const MUFFLE_GAIN := 0.45
const VOL_STEP := 0.1
const ANNOUNCE_COL := Color(0.75, 0.7, 1.0)

const TITLES := {
	"zone_grieg_mountain_king": "Григ — В пещере горного короля",
	"zone_beethoven5_i": "Бетховен — Симфония №5, I",
	"zone_beethoven5_iii": "Бетховен — Симфония №5, III",
	"zone_mozart40_i": "Моцарт — Симфония №40, I",
	"zone_mozart40_iv": "Моцарт — Симфония №40, IV",
	"zone_vivaldi_summer_presto": "Вивальди — «Лето», Presto",
	"zone_mendelssohn_saltarello": "Мендельсон — Сальтарелло",
	"zone_eroica_iv": "Бетховен — «Героическая», финал",
	"zone_brahms4_iv": "Брамс — Симфония №4, IV",
	"zone_dvorak_carnival": "Дворжак — «Карнавал»",
	"zone_tchaikovsky6_iii": "Чайковский — «Патетическая», III",
	"boss_danse_macabre": "Сен-Санс — Пляска смерти",
	"boss_bald_mountain": "Мусоргский — Ночь на Лысой горе",
	"boss_toccata": "Бах — Токката и фуга ре минор",
	"boss_toccata_brass": "Бах — Токката и фуга (медь)",
	"boss_moonlight_presto": "Бетховен — «Лунная», Presto",
	"boss_coriolan": "Бетховен — «Кориолан»",
	"boss_brahms_tragic": "Брамс — Трагическая увертюра",
	"calm_satie_gymnopedie1": "Сати — Гимнопедия №1",
	"calm_grieg_morning": "Григ — Утро",
	"calm_chopin_op48_1": "Шопен — Ноктюрн op. 48 №1",
	"calm_chopin_op55_1": "Шопен — Ноктюрн op. 55 №1",
	"calm_goldberg_aria": "Бах — Гольдберг-вариации, Ария",
	"death_grieg_aase": "Григ — Смерть Озе",
	"death_eroica_funebre": "Бетховен — Похоронный марш",
}

var tracks := {}             # категория -> Array путей
var cat := ""                # что играет сейчас
var track := ""              # путь текущего трека

var _players: Array = []
var _vol := [0.0, 0.0]
var _tgt := [0.0, 0.0]
var _rate := [1.0, 1.0]      # скорость фейда, 1/с
var _cur := 0
var _bags := {}
var _saved := {}             # прерванный паузой трек
var _muffled := false
var _duck := 1.0
var _cutoff := 20000.0
var _bus := -1
var _lp: AudioEffectLowPassFilter


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bus = _ensure_bus("Music")
	_ensure_bus("SFX")       # для будущих звуков
	_lp = AudioEffectLowPassFilter.new()
	_lp.cutoff_hz = _cutoff
	AudioServer.add_bus_effect(_bus, _lp)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		p.finished.connect(_on_finished.bind(i))
		_players.append(p)
	for c in CATS:
		tracks[c] = []
	_scan(ROOT)
	_apply_volume()


# --- Сценарии игры ---------------------------------------------------------------

func on_menu() -> void:
	_saved = {}
	set_muffled(false)
	var c := "menu" if not (tracks["menu"] as Array).is_empty() else "calm"
	if cat != c:
		play_category(c, 1.5, false)


func on_zone(is_boss: bool) -> void:
	_saved = {}
	set_muffled(false)
	if is_boss:
		play_category("boss", 1.2)
	elif cat != "zone" or not _players[_cur].playing:
		play_category("zone", 2.0)


func on_boss_dead() -> void:
	play_category("calm", 3.0)


func on_death() -> void:
	_saved = {}
	set_muffled(false)
	play_category("death", 2.0, false)


## Esc: в спокойную музыку и обратно, с того же места.
func set_paused(on: bool) -> void:
	if on:
		if cat == "zone" or cat == "boss":
			var p: AudioStreamPlayer = _players[_cur]
			_saved = {"cat": cat, "track": track, "stream": p.stream, "pos": p.get_playback_position()}
			play_category("calm", 0.8, false)
	elif not _saved.is_empty():
		cat = str(_saved["cat"])
		track = str(_saved["track"])
		_start(_saved["stream"], float(_saved["pos"]), 0.8)
		_saved = {}


## Инвентарь: музыка «за стенкой».
func set_muffled(on: bool) -> void:
	_muffled = on


func title() -> String:
	return title_of(track)


func title_of(path: String) -> String:
	if path == "":
		return ""
	var stem := path.get_file().get_basename()
	if TITLES.has(stem):
		return U.t(str(TITLES[stem]))
	for c in CATS:
		if stem.begins_with(c + "_"):
			stem = stem.substr(c.length() + 1)
	return stem.replace("_", " ").capitalize()


func volume_text() -> String:
	if bool(Game.setting("music_muted")):
		return U.t("выкл")
	return "%d%%" % roundi(float(Game.setting("music_volume")) * 100.0)


# --- Воспроизведение ---------------------------------------------------------------

func play_category(c: String, fade: float = FADE, announce: bool = true) -> void:
	cat = c
	var path := _pick(c)
	if path == "":
		_fade_out(fade)
		track = ""
		return
	var s := load(path) as AudioStream
	if s == null:
		return
	# зацикливание делаем сами — иначе не будет сигнала finished и смены трека
	if "loop" in s:
		s.set("loop", false)
	track = path
	_start(s, 0.0, fade)
	if announce:
		Game.say("♪ " + title(), ANNOUNCE_COL)


func _start(s: AudioStream, from: float, fade: float) -> void:
	var old := _cur
	_cur = 1 - _cur
	var p: AudioStreamPlayer = _players[_cur]
	p.stream = s
	p.play(from)
	_vol[_cur] = 0.0
	_tgt[_cur] = 1.0
	_rate[_cur] = 1.0 / maxf(fade, 0.01)
	_tgt[old] = 0.0
	_rate[old] = 1.0 / maxf(fade, 0.01)


func _fade_out(fade: float) -> void:
	for i in 2:
		_tgt[i] = 0.0
		_rate[i] = 1.0 / maxf(fade, 0.01)


func _on_finished(i: int) -> void:
	if i != _cur:
		return
	if cat == "death":
		_start(_players[i].stream, 0.0, 0.1)    # смерть крутится по кругу
	elif cat != "":
		play_category(cat, 0.5, cat != "calm")


## Перемешанный «мешок»: все треки категории по разу, без повтора подряд.
func _pick(c: String) -> String:
	var all: Array = tracks.get(c, [])
	if all.is_empty():
		return ""
	var bag: Array = _bags.get(c, [])
	if bag.is_empty():
		bag = all.duplicate()
		bag.shuffle()
		if bag.size() > 1 and bag.back() == track:
			bag.reverse()
		_bags[c] = bag
	return str(bag.pop_back())


func _process(delta: float) -> void:
	for i in 2:
		var p: AudioStreamPlayer = _players[i]
		_vol[i] = move_toward(_vol[i], _tgt[i], delta * _rate[i])
		p.volume_db = linear_to_db(maxf(_vol[i], 0.0001))
		if _tgt[i] <= 0.0 and _vol[i] <= 0.0 and p.playing:
			p.stop()
	var k := 1.0 - exp(-delta * 6.0)
	_duck = lerpf(_duck, MUFFLE_GAIN if _muffled else 1.0, k)
	_cutoff = lerpf(_cutoff, MUFFLE_CUTOFF if _muffled else 20000.0, k)
	_lp.cutoff_hz = _cutoff
	_apply_volume()


func _unhandled_input(event: InputEvent) -> void:
	var volume := float(Game.setting("music_volume"))
	if event.is_action_pressed("music_up"):
		_set_volume(volume + VOL_STEP, false)
	elif event.is_action_pressed("music_down"):
		_set_volume(volume - VOL_STEP, false)
	elif event.is_action_pressed("music_mute"):
		_set_volume(volume, not bool(Game.setting("music_muted")))
	else:
		return
	get_viewport().set_input_as_handled()
	Game.say(U.t("Музыка: ") + volume_text(), ANNOUNCE_COL)


func _set_volume(v: float, m: bool) -> void:
	Game.set_setting("music_volume", clampf(snappedf(v, 0.01), 0.0, 1.0))
	Game.set_setting("music_muted", m)
	_apply_volume()


func _apply_volume() -> void:
	var v := 0.0 if bool(Game.setting("music_muted")) else float(Game.setting("music_volume")) * _duck
	AudioServer.set_bus_mute(_bus, v <= 0.001)
	AudioServer.set_bus_volume_db(_bus, linear_to_db(maxf(v, 0.0001)))


# --- Служебное ------------------------------------------------------------------

func _ensure_bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	return i


## list_directory видит ресурсы и в экспортированной игре (там .ogg лежат как .import).
func _scan(dir: String) -> void:
	for n in ResourceLoader.list_directory(dir):
		var fname := str(n)
		if fname.ends_with("/"):
			_scan(dir + fname)
			continue
		if not EXTS.has(fname.get_extension().to_lower()):
			continue
		var c := _cat_of(fname.get_basename(), dir)
		(tracks[c] as Array).append(dir + fname)


func _cat_of(stem: String, dir: String) -> String:
	for c in CATS:
		if stem.begins_with(c + "_"):
			return c
	var folder := dir.trim_suffix("/").get_file()
	return folder if CATS.has(folder) else "zone"
