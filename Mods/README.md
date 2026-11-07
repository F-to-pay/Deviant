# Моды Deviant

Собранная игра читает папку `Mods/` рядом с exe. В редакторе Godot — `Mods/` в корне проекта: в ней лежит `.gdignore`, поэтому редактор её не импортирует и не компилирует скрипты модов.

Мод — это папка `Mods/<ИмяМода>/`, повторяющая корень игры. Любая часть необязательна:

```
Mods/MyMod/
  mod.json              описание и настройки мода
  data/archetypes.json  основы пушек
  data/makers.json      марки
  data/perks.json       перки (моды пушек)
  data/legendaries.json легендарки
  data/rarities.json    редкости (правка по индексу, их всегда 6)
  data/names.json       прозвища, флейвор, имена элиток и боссов
  data/codex.json       страницы и описания для справочника
  data/guide.json       своя глава в гайде по моддингу
  lang/ru.json          перевод (дополняет русский) — или lang/de.json для нового языка
  sfx/...               звуки — те же папки-банки, что у игры (sfx/guns/pistol/*.wav)
  music/...             музыка — zone_/boss_/calm_/death_/menu_ по префиксу файла или по имени папки
  scripts/*.gd          скрипты перков/марок/легендарок (если данных не хватает)
```

Базовые файлы игры для образца — `data/*.json` и `lang/ru.json` в корне проекта. Готовый пример — `Mods/ExampleMod/` (выключен по умолчанию, включается в меню «Моды»).

**Полный гайд** — в игре: «Справочник» → «Как делать моды» → «Создать гайд по моддингу». Игра кладёт рядом с exe `гайд_по_модам.txt` (или `modding_guide.txt` на английском): все файлы и поля плюс справка по всем id, загруженным прямо сейчас — с учётом твоих модов. Текст гайда — `data/guide.json`.

## Отладчик модов

Меню «Моды» → «Отладчик модов (F8)» → «Перезапустить». Включается только после перезапуска, чтобы в обычной игре ничего лишнего не грузилось.

С ним игра при старте проверяет все данные и пишет журнал. **F8** открывает консоль, пока она открыта, игра стоит на паузе. Если есть предупреждения или ошибки, а консоль закрыта, в правом верхнем углу горит значок «⚠ N ✖ N».

**Что попадает в журнал:**
- ошибки JSON с файлом и строкой;
- неизвестные операции, статы и условия;
- ссылки на несуществующие перки, основы и звуки;
- скрипты, которые не собрались или в которых нет `apply`;
- непереведённые названия по каждому языку;
- ошибки и `print()` из скриптов модов — перехват ошибок движка работает в Godot 4.5+.

Каждая запись помечена модом-источником.

**Команды:**

| Команда | Что делает |
|---|---|
| `help` | список команд |
| `validate` | проверить данные заново |
| `reload` | перечитать данные, переводы, звуки и музыку модов на лету |
| `give <arch\|random> [maker] [rarity 0-5]` | бросить пушку рядом |
| `perk <id> [arch]` | бросить пушку с этим перком |
| `legendary <id>` | бросить легендарку |
| `list arch\|makers\|perks\|legendaries\|langs\|mods` | списки id |
| `lang <код>` | сменить язык |
| `missing [lang]` | строки, которые встретились в игре без перевода |
| `clear` | очистить журнал |

Стрелки ↑/↓ листают историю команд. Кнопка «Копировать» кладёт журнал в буфер обмена.

## mod.json

```json
{
	"name": "My Mod",
	"author": "Me",
	"version": "1.0",
	"description": "Что делает мод (видно в подсказке в меню)",
	"enabled": true,
	"replace_sfx": ["guns/pistol"],
	"replace_music": ["zone"]
}
```

- `enabled` — включён ли мод, пока игрок сам не переключил его в меню.
- `replace_sfx` — банки звуков, которые мод заменяет целиком; без этого звуки мода добавляются к игровым.
- `replace_music` — то же для категорий музыки.

Включение и выключение — в главном меню, раздел «Моды». Изменения применяются сразу. Кнопка «Обновить» перечитывает папку, если ты положил новый мод при запущенной игре.

## Как слои сливаются

Сначала читается игра, потом включённые моды по алфавиту. Поздний слой правит ранний.

- **Словари по id** (`archetypes.json`, `makers.json`). Запись с тем же id дополняется: указанные поля заменяются, остальные остаются. Новый id — новая запись. `"_remove": ["noname"]` — удалить запись.
- **Списки по id** (`perks.json`, `legendaries.json`). Так же по полю `id`. Элемент `{"remove": "vamp"}` удаляет запись.
- **`rarities.json`** — правка по индексу: 0 обычная … 5 абсурдная.
- **`names.json`** — списки дописываются. `"replace": true` в файле заменяет их целиком.

То есть, чтобы поменять урон дробовика, достаточно `data/archetypes.json`: `{"shotgun": {"damage": 9}}`.

## Основа (archetypes.json)

```json
"nailgun": {
	"name": "Nailgun", "weight": 6,
	"damage": 9, "fire_rate": 6, "pellets": 1, "spread": 5, "speed": 1100, "lifetime": 0.7,
	"mag": 40, "reload": 1.8, "crit": 0.05, "crit_mult": 2.0,
	"kind": "bullet", "size": 3, "knock": 40, "move": 1.0, "shake": 1.2,
	"explode": 0, "bounce": 0, "drag": 0, "pierce": 1,
	"ammo": "nailgun", "ammo_name": "nails", "ammo_color": "#c0c0c0",
	"explosive": false, "slug_chance": 0,
	"icon": {"body": 36, "bh": 11, "barrel": 18, "bt": 5, "stock": 6, "scope": false, "cylinder": false, "mortar": false},
	"sound": {"vol": -7, "pitch": 1.2, "reload": "reload/rifle", "reload_done": "reload/done"}
}
```

- `kind` — тип снаряда: `bullet`, `pellet`, `rocket`, `grenade`, `orb`, `shell` (мина по дуге).
- `ammo` — чьи патроны ест основа (миномёт ест `launcher`). По умолчанию свои.
- `explosive` — основа взрывная: её не получает Синергис и другие марки с `no_explosive`.
- `slug_chance` — шанс родиться «пулевой»: вся дробь в одном снаряде.
- Звуки выстрела — папка `sfx/guns/<id основы>/`.

## Марка (makers.json)

```json
"acme": {
	"name": "ACME", "motto": "Beep beep.",
	"color": "#d04020", "dark": "#301008", "projectile_color": "#ffa080",
	"weight": 10, "legendary": true,
	"ops": [["mul", "damage", 1.1]],
	"perks": ["scatter"],
	"no_explosive": false, "no_proc_perks": false,
	"projectile_arch": "", "random_legendary_perk": false,
	"sound": {"vol": 0, "pitch": 1.0},
	"script": ""
}
```

- `legendary` — может ли марка встретиться на легендарке.
- `perks` — перки, которые марка ставит всегда (Щеголь → `scatter`).
- `no_explosive` — никаких взрывов (Синергис).
- `no_proc_perks` — без перков-эффектов (Атлант).
- `projectile_arch` — любая основа стреляет снарядом этой основы, но ест свои патроны (Гипернова → `rocket`).
- `random_legendary_perk` — случайный перк легендарки (Кузня хаоса).

## Перк (perks.json)

```json
{
	"id": "bouncy", "name": "Bouncy",
	"weight": 6, "min_rarity": 1, "group": "",
	"tags": ["proc"],
	"fits": [["proj_kind", "!=", "shell"]],
	"ops": [["add", "bounces", 5], ["mul", "damage", 0.9]],
	"script": ""
}
```

- `name` — прилагательное для имени пушки («Bouncy Pistol»). В переводе задаётся по родам: `{"m": "Прыгучий", "f": "Прыгучая"}`.
- `min_rarity` — с какой редкости выпадает (1 — необычная). `weight` 0 — никогда не выпадает сам.
- `group` — перки одной группы не сочетаются (кроме абсурдных пушек). Группа `kind` важнее всего для имени, `el` — стихии.
- `tags`:
  - `proc` — эффект: его шанс падает у скорострельных пушек;
  - `explosive` — запрещён марками без взрывов;
  - `heal` — убирается в хардкоре;
  - `no_shell` — бессмыслен для мин.
- `fits` — условия, при которых перк может выпасть (все должны выполняться).

## Легендарка (legendaries.json)

```json
{
	"id": "duck", "name": "Rubber Duck", "flavor": "Squeaks menacingly.",
	"arch": "pistol", "arch2": "", "perks": ["bouncy"],
	"special": "ring", "ops": [["set", "element", "cryo"]], "script": ""
}
```

`special` — фишки, зашитые в код:

| special | Что делает |
|---|---|
| `ring` | Кольцо пуль по шансу |
| `nuke10` | Копит урон и стреляет ядеркой |
| `chaos` | Урон каждой пули от ×0 до ×2 |
| `expert` | Цепная молния бьёт всех рядом |
| `singularity` | Каждый шар — чёрная дыра |

Для `expert` и `singularity` нужны ещё и `ops` — смотри базовый `data/legendaries.json`.

## Операции (ops)

| Операция | Что делает |
|---|---|
| `["mul", "damage", 1.35]` | умножить (целые статы округляются) |
| `["add", "pierce", 2]` | прибавить |
| `["set", "element", "fire"]` | задать |
| `["min", "armor", 0.5]` | не больше |
| `["max", "mag_size", 3]` | не меньше |
| `["pellets", 5, 1.3]` | +5 дробин, общий урон залпа ×1.3 |
| `["if", условие, [операции], [иначе]]` | ветвление |

**Условия:** `["mag_size", "<", 80]`, `["arch", "==", "shotgun"]`, `["maker", "!=", "synergis"]`, `["rarity", ">=", 3]`, а также `["and", …]`, `["or", …]`, `["not", …]`.

**Статы пушки** (поля `Gun`, см. `scripts/weapons/gun.gd`):
- урон и стрельба: `damage`, `fire_rate`, `pellets`, `spread`, `burst`, `ammo_per_shot`, `crit_chance`, `crit_mult`;
- магазин: `mag_size`, `reload_time`, `free_ammo`;
- снаряд: `proj_speed`, `lifetime`, `proj_kind`, `proj_size`, `knock`, `pierce`, `bounces`, `homing`, `accel`, `drag`, `sine`, `boomerang`, `split_n`, `split_depth`, `teleport`;
- взрывы и спецэффекты: `explode_r`, `explode_chance`, `explode_on_expire`, `chain_n`, `cluster_n`, `vortex`, `seeder`;
- стихии: `element`, `elem_chance`, `elem_mult`, `proc_mult`;
- носитель: `leech`, `armor`, `move_mult`, `shake`.

`proj_kind` задаётся словами `bullet`/`pellet`/`rocket`/`grenade`/`orb`/`shell`. `element` — словами `none`/`fire`/`shock`/`acid`/`cryo`/`curse`/`random`.

## Скрипты

Если данных не хватает, укажи `"script": "scripts/my_perk.gd"` (путь от корня мода) у перка, марки или легендарки:

```gdscript
extends RefCounted

func apply(g, rng) -> void:
	g.crit_chance += 0.15
	g.crit_mult += rng.randf_range(0.2, 1.0)
```

`apply(gun, rng)` вызывается, когда пушка получает этот перк, марку или легендарку — после операций `ops`.

Скрипт мода — обычный код с полными правами. Ставь моды только из источников, которым доверяешь.

## Справочник (data/codex.json)

Справочник в игре (главное меню или пауза → «Справочник») собирается из `data/codex.json` игры и модов.

```json
{
	"sections": [{"id": "mymod", "order": 60, "title": {"en": "My Mod", "ru": "Мой мод"}}],
	"pages": [
		{"id": "nailguns", "section": "weapons", "order": 15,
		 "title": {"en": "Nailguns", "ru": "Гвоздомёты"},
		 "text": {"en": ["[b]Nails[/b] go through everyone."], "ru": ["[b]Гвозди[/b] прошивают всех."]}},
		{"id": "character", "title": {"de": "Charakter"}, "text": {"de": ["Ein einsamer Schütze..."]}}
	],
	"archetypes": {"nailgun": {"en": "Pins enemies to walls.", "ru": "Прибивает врагов к стенам."}},
	"perks": {"bouncy": {"en": "Bounces a lot."}}
}
```

- **Разделы игры:** `basics` 10, `weapons` 20, `enemies` 30, `rating` 40, `modding` 50. Страница с неизвестным разделом попадает в «Другое».
- **Страницы игры:** `character`, `combat`, `world`, `archetypes`, `makers`, `generation`, `perks`, `legendaries`, `enemies`, `elites`, `bosses`, `rating`, `modding`. Существующий id сливается вглубь — можно добавить только перевод (вторая страница в примере).
- **`title` / `text`** — по языкам, строка или массив строк, BBCode. Нет текущего языка — показывается английский. Символ `[` пишется как `[lb]`.
- **`auto`** — таблица из текущих данных со всеми модами: `archetypes`, `makers`, `rarities`, `perks`, `legendaries`, `enemies`, `elites`, `bosses`, `rating`, `mods`.
- **`actions`** — кнопки под страницей: `write_guide`, `open_mods_folder`, `open_game_folder`.
- **Описания для автотаблиц:** `archetypes`, `makers`, `perks`, `legendaries`, `enemies`, `affixes` — `{id: {язык: текст}}`; `bosses` — `{паттерн: {"name": {...}, "text": {...}}}`.

Новые типы, перки и производители появляются в таблицах сами — `codex.json` только добавляет слова.

Своя глава в гайде — `data/guide.json`: `{"en": ["строки"], "ru": ["строки"]}`, дописывается после текста игры.

## Переводы (lang/<код>.json)

```json
{
	"meta": {"code": "ru", "name": "Русский"},
	"templates": {"gun_adj": "{adj} {type_l} {maker}-{num}"},
	"strings": {
		"Nailgun": {"text": "Гвоздомёт", "lower": "гвоздомёт", "g": "m"},
		"Bouncy": {"m": "Прыгучий", "f": "Прыгучая"},
		"nails": "гвозди",
		"ACME": "АКМЕ"
	}
}
```

- **Ключ** — английский текст из игры или из `data/*.json`. Значение — перевод.
- **Существительное** (основа пушки, тип врага): `text`, строчная форма `lower` и род `g` (`m`, `f`, `n`).
- **Прилагательное** (перк, префикс элитки): формы по родам `m`, `f`, `n`.
- **`templates`** — порядок слов в именах. Ключи: `gun_plain`, `gun_adj`, `gun_nick`, `gun_nick2`, `gun_legendary`, `type_hybrid`, `elite`, `rare`, `boss`.
- **Подстановки:**
  - в именах пушек: `{type}`, `{type_l}`, `{maker}`, `{num}`, `{adj}`, `{adj2}`, `{adj2_l}`, `{nick}`, `{name}`;
  - в `type_hybrid`: `{a}`, `{b}`, `{a_l}`, `{b_l}`;
  - в `elite`: `{prefix}`, `{type}`, `{type_l}`; в `rare`: `{first}`, `{last}`; в `boss`: `{title}`, `{name}`.
- **Новый язык** — новый файл `lang/<код>.json`. Он сразу появится в переключателе языка в главном меню.
