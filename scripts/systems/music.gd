class_name Music
extends Node
## Музыка: сама находит треки в music/ игры и включённых модов (Mods/<мод>/music/) и раскладывает
## их по категориям. Чтобы мод заменил категорию целиком — "replace_music": ["zone"] в mod.json.
##  Категория — по префиксу имени файла (zone_, boss_, calm_, death_), иначе по имени папки.
##  zone  — обычные зоны, перемешанный плейлист, трек не рвётся при смене зоны.
##  boss  — арена с боссом.        calm  — пауза (Esc) и передышка после босса.
##  death — экран смерти.          menu  — главное меню (нет своих — играет calm).
## Пауза уводит в calm и потом возвращает прерванный трек с того же места.
## Инвентарь — музыка глохнет (приглушение + фильтр низких частот).
## Шины Music и SFX создаются кодом; громкость — в настройках Game (deviant.cfg).
## Без фризов: следующий трек каждой категории выбирается заранее и грузится в фоне
## (res:// — ResourceLoader.load_threaded_request, файлы модов — WorkerThreadPool). Смена трека
## берёт уже загруженный и сразу ставит в очередь следующий. Первую партию ждёт экран загрузки (Warmup).

const CATS := ["zone", "boss", "calm", "death", "menu"]
const FADE := 1.5            # кроссфейд по умолчанию, с
const MUFFLE_CUTOFF := 700.0
const MUFFLE_GAIN := 0.45
const VOL_STEP := 0.1
const ANNOUNCE_COL := Color(0.75, 0.7, 1.0)

const TITLES := {
	"zone_grieg_mountain_king": "Grieg — In the Hall of the Mountain King",
	"zone_beethoven5_i": "Beethoven — Symphony No. 5, I",
	"zone_beethoven5_iii": "Beethoven — Symphony No. 5, III",
	"zone_mozart40_i": "Mozart — Symphony No. 40, I",
	"zone_mozart40_iv": "Mozart — Symphony No. 40, IV",
	"zone_vivaldi_summer_presto": "Vivaldi — Summer, Presto",
	"zone_mendelssohn_saltarello": "Mendelssohn — Saltarello",
	"zone_eroica_iv": "Beethoven — Eroica, Finale",
	"zone_brahms4_iv": "Brahms — Symphony No. 4, IV",
	"zone_dvorak_carnival": "Dvořák — Carnival Overture",
	"zone_tchaikovsky6_iii": "Tchaikovsky — Pathétique, III",
	"boss_danse_macabre": "Saint-Saëns — Danse Macabre",
	"boss_bald_mountain": "Mussorgsky — Night on Bald Mountain",
	"boss_toccata": "Bach — Toccata and Fugue in D minor",
	"boss_toccata_brass": "Bach — Toccata and Fugue (brass)",
	"boss_moonlight_presto": "Beethoven — Moonlight Sonata, Presto",
	"boss_coriolan": "Beethoven — Coriolan Overture",
	"boss_brahms_tragic": "Brahms — Tragic Overture",
	"calm_satie_gymnopedie1": "Satie — Gymnopédie No. 1",
	"calm_grieg_morning": "Grieg — Morning Mood",
	"calm_chopin_op48_1": "Chopin — Nocturne Op. 48 No. 1",
	"calm_chopin_op55_1": "Chopin — Nocturne Op. 55 No. 1",
	"calm_goldberg_aria": "Bach — Goldberg Variations, Aria",
	"death_grieg_aase": "Grieg — The Death of Åse",
	"death_eroica_funebre": "Beethoven — Funeral March",
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
var _next := {}              # категория -> путь следующего трека (уже грузится)
var _raw_tasks := {}         # путь -> id задачи WorkerThreadPool (файл мода)
var _raw_done := {}          # путь -> AudioStream из рабочего потока (под _mutex)
var _mutex := Mutex.new()


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
	rescan()
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
		return U.t("off")
	return "%d%%" % roundi(float(Game.setting("music_volume")) * 100.0)


# --- Воспроизведение ---------------------------------------------------------------

func play_category(c: String, fade: float = FADE, announce: bool = true) -> void:
	cat = c
	var path: String = _next.get(c, "")
	_next.erase(c)
	if path == "":
		path = _pick(c)
	if path == "":
		_fade_out(fade)
		track = ""
		return
	var s := _take(path)
	_prepare(c)              # следующий трек этой категории — сразу в фон
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


# --- Фоновая подгрузка -------------------------------------------------------------

## Выбрать следующий трек категории и начать грузить его в фоне.
func _prepare(c: String) -> void:
	if _next.has(c):
		return
	var path := _pick(c)
	if path == "":
		return
	_next[c] = path
	if path.begins_with("res://"):
		if ResourceLoader.load_threaded_request(path, "AudioStream") != OK:
			DebugLog.warn("cannot start loading %s" % path, "music")
	elif not _raw_tasks.has(path):
		_raw_tasks[path] = WorkerThreadPool.add_task(_load_raw.bind(path), false, "music " + path.get_file())


## В рабочем потоке: файл мода с диска.
func _load_raw(path: String) -> void:
	var s := Mods.load_audio(path)
	_mutex.lock()
	_raw_done[path] = s
	_mutex.unlock()


## Загружен ли уже трек (не блокирует).
func _is_loaded(path: String) -> bool:
	if path.begins_with("res://"):
		return ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS
	if _raw_tasks.has(path):
		return WorkerThreadPool.is_task_completed(int(_raw_tasks[path]))
	return true


## Забрать трек. Если фоновая загрузка ещё идёт — дождаться её; если её не было — загрузить сразу.
func _take(path: String) -> AudioStream:
	var s: AudioStream = null
	if path.begins_with("res://"):
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			s = ResourceLoader.load_threaded_get(path) as AudioStream
	elif _raw_tasks.has(path):
		WorkerThreadPool.wait_for_task_completion(int(_raw_tasks[path]))
		_raw_tasks.erase(path)
		_mutex.lock()
		s = _raw_done.get(path)
		_raw_done.erase(path)
		_mutex.unlock()
	if s == null:
		s = Mods.load_audio(path)
	return s


## Для экрана загрузки: выбрать и начать грузить по треку на каждую категорию.
func prepare_all() -> void:
	for c in CATS:
		_prepare(c)


## Доля уже загруженных заготовленных треков (0..1).
func prepared_ratio() -> float:
	if _next.is_empty():
		return 1.0
	var n := 0
	for c in _next:
		if _is_loaded(str(_next[c])):
			n += 1
	return float(n) / float(_next.size())


## Забросить заготовки (перед пересканом): дождаться и выкинуть, чтобы не висели в загрузчике.
func _drop_prepared() -> void:
	for c in _next:
		var path := str(_next[c])
		if path.begins_with("res://"):
			if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				ResourceLoader.load_threaded_get(path)
		elif _raw_tasks.has(path):
			WorkerThreadPool.wait_for_task_completion(int(_raw_tasks[path]))
	_next.clear()
	_raw_tasks.clear()
	_mutex.lock()
	_raw_done.clear()
	_mutex.unlock()


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
	Game.say(U.t("Music: ") + volume_text(), ANNOUNCE_COL)


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


## Перечитать треки игры и модов (при старте и после включения/выключения модов).
func rescan() -> void:
	_drop_prepared()
	tracks.clear()
	_bags.clear()
	for c in CATS:
		tracks[c] = []
	var replace := {}       # корень мода -> категории, которые он заменяет
	for m in Mods.list:
		if bool(m["enabled"]):
			var info: Dictionary = m["info"]
			var rl: Variant = info.get("replace_music", [])
			replace[str(m["path"])] = rl if rl is Array else []
	var cleared := {}
	for f in Mods.files("music", Mods.AUDIO_EXTS, true):
		var rel := str(f[0])
		var full := str(f[1])
		var c := _cat_of(rel.get_file().get_basename(), "music/" + rel.get_base_dir())
		for root in replace:
			if full.begins_with(str(root)) and (replace[root] as Array).has(c) and not cleared.has(root + c):
				cleared[root + c] = true
				tracks[c] = []
		(tracks[c] as Array).append(full)
	prepare_all()


func _cat_of(stem: String, dir: String) -> String:
	for c in CATS:
		if stem.begins_with(c + "_"):
			return c
	var folder := dir.trim_suffix("/").get_file()
	return folder if CATS.has(folder) else "zone"
