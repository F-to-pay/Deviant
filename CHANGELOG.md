# Changelog

## Unreleased

### Run saves
- **Continue and Load game.** The run is saved at every checkpoint (start of a run, entrance to each zone and town). Every run has its own slot in `user://saves/`; there can be
  any number of them. The main menu gets **Continue** (the latest save) and **Load game** (a paged list, newest first, one-click delete, "Delete all" with a second press). Resuming starts the
  location from its beginning (no mid-zone saves: enemies and loot are not stored).
- **New game never overwrites a save.** A slot is erased by itself only when that run dies (and only that run's slot).
- **Autosave toggle** (Settings, on by default). Off: checkpoints wait in memory and are written only by **Save game** in the pause menu (it saves the last checkpoint, so loading still starts at the beginning of that location).
- **Keep the save after death** (Custom start): the slot survives death, in exchange for −50% rating (and therefore XP); such runs do not count for records.
- Everything about the run is stored: run parameters, XP and levels, skill tree, contracts, coins, all guns exactly (`Gun.to_dict`, not a seed), ammo, flasks, skill perks,
  health and the random state before the location was generated, so the same map and the same town stock come back. The format is binary (numbers bit for bit), versioned and
  written atomically; a broken or foreign file is ignored; a changed set of mods gives a warning. An old single `run.save` is moved into a slot.
- Fixed: a seed did not fully repeat a run — the shotgun's slug chance used the global random generator instead of the run's. Guns generated from the same seed are now identical.

### Data and structure
- Enemies, heroes and hero perks are data (`data/enemies.json`, `heroes.json`, `hero_perks.json`); mods can add and change them. Behaviour (enemy `ai`, hero `skill`) stays in code.
- Internal: `Game` split into `Settings` / `Profile` / `RunState` / `RunConfig` / `Balance` / `Save`; the menu into screens (`ui/screens/`); `Main` into `Loot` / `Interact` /
  `Rewards` / `ZoneLoader` (+ `ZoneSource`); `Player` into `HeroSkill` / `Shooting`. Test suite: `tests/run_all.ps1` with golden fingerprints in `tests/golden/`.

## 0.2

### Common guns
- **White (Common) guns never go out of date**: their level and damage are fitted to the current zone (in town — to the next one) whenever you enter a zone or a town and when you pick one up
  (`Gun.sync_level`, `Main.sync_white_guns`). A white gun's damage multiplier is that of the zone you are in (×1.18 per zone), so it keeps up with the enemies. Higher rarities still age as before.
  The price in the shop follows the gun's level too. Raising a white gun's rarity in the Workshop ends this: it keeps the level it had at that moment.

### Director
- The Director now sets the pace of levelling: a fully cleared zone gives about **1.5 hero levels** (`Director.LEVELS_PER_ZONE`, counted from your level on entering the zone, rating multiplier included).
  After the zone is laid out, `finish_zone()` computes `xp_scale`, so the XP of all its enemies adds up to exactly that budget; a kill gives `Game.enemy_xp × xp_scale` (`Director.kill_xp`). The F3 line shows the scale.
- The Director likes elites: champion and leader packs come up 1.6× as often (`Director.ELITE_LOVE`; capped at 45% and 32% per pack). Normal packs are still the majority only in the first zones.
- Boss zones follow the same rule: the boss pays out the whole budget.
- The debug command `skip` pays like a cleared zone: every skipped zone gives the Director's budget (1.5 levels) instead of the old average formula, and a skipped boss zone pays the stage-boss coins (30, was 15). The coin formula for kills now lives in one place (`Balance.kill_coin_value`).

### Languages
- Norwegian Bokmål is split out of the base game into the mod `Mods/Norwegian/` (strings, codex and modding guide). It is enabled by default, but **frozen**: new strings are no longer translated and show in English. The base game now has English and Russian only.

### Skill tree
- Hero levels now give **5 skill points** each. New skill tree (`K`, D-pad down, or Pause → Skill tree): four branches on four screens
  (Weapon, Vitality, Abilities, Utility). A level of a tier 1 skill costs N points, of a tier 2 skill 2×N; a tier 2 skill needs a level in each parent;
  skills of one class exclude each other; personal skills exist for one hero only. The tree resets with the run.
- Skills: Firepower, Toughness, Skill Power, Greed (tier 1) and Executioner (Assassin), Thrifty Gunner (Engineer), Treasure Hunter, Steady Aim / Hip Fire,
  Bigger Belt / Quick Sip, Strong Brew, Chilling Touch, Shrapnel Shield (Pioneer), Second Wind, Bounty Hunter (Sheriff).
- Firepower, Toughness and Skill Power also grow with the hero's level (effect field `per_hero`: bonus = skill level × hero level × base bonus); health and bonuses are recomputed on every level-up.
- New: temporary health (shown as a blue part of the health bar), speed boost after a flask, slow on enemies, a bounty target in each zone (red mark).
- HUD: hero level and XP bar, a hint with free points.
- **Modding**: branches and skills are data (`data/skill_branches.json`, `data/skill_tree.json`) merged by id from all layers; `validate` checks them.
  Effects are `{stat, first, step, fmt}` entries (see `LevelTree.KNOWN_STATS`).
- Codex page «Skill tree».

### Heroes
- **Engineer** (35 ancient coins). Skill — a turret, lobbed like a mortar shell to the aim point (10 s cooldown). It takes all the rounds left in your
  active gun's magazine and you reload (free for a Synergis gun), has your health and shoots the nearest visible enemies with a copy of your gun.
  Enemies go for whichever is closer — the turret or you. It stands until smashed, but is destroyed the moment the magazine runs dry. Its bullets deal 50% of the gun's damage and it fires at the gun's effective range. Taking a hit knocks nearby enemies away and stuns them for 1 s.
  At most as many turrets as skill charges; a new one beyond the limit removes the oldest. Skill perks: Extra Hand, Economy (+40% rounds), Mad Scientist (a random Synergis gun
  one rarity higher, nothing taken from your reserve, once), Element. Grievous Wounds is now offered only to the Pioneer, Sheriff and Assassin.
- Turret bullets (and its Last Word nuke) never give the hero lifesteal.
- Enemies and bosses now pick the nearest target (`Main.target_for`): the hero or a turret.

### Touch controls
- **Aimed skills.** On touch the Pioneer's grenade and the Assassin's slash get their own aim stick: hold the Skill button and drag, release to throw / strike.
  A preview is drawn while you aim (landing circle and range ring for the grenade, strike sector for the slash). A plain tap uses the gun's aim, as before.
  The Sheriff's blessing has no direction and still fires instantly.
- **Tap a weapon slot** at the bottom of the screen to select that gun.

### Bosses
- Fixed bosses running into walls: the charge now only starts with a clear line to you and enough room ahead,
  stops before obstacles, and otherwise the boss walks to a good position along the A* path first (and skips the charge if it can't get one in 3 s).
- Fixed the boss pathfinding failing in tight arenas (the search for the nearest free spot is now wider for large bodies).
- New boss **Anti-Player** (from zone 10, 50% instead of the usual boss): a mirror of you that shoots the best gun you found from its effective range (max 15 m), backs off and dashes, and uses your hero's skill. Its health grows with the zone like any enemy's.
- New boss pattern **Seekers**: a ring of slow orbs (8, 12 when enraged) that curve towards you at about 10° per second. Described in the Codex.

### New gun types
- **Ship Cannon**: one huge cannonball (damage 200, the highest single hit; knockback 260), 4 in the magazine, reload 3.6 s, slow (move ×0.7). New stat `recoil`: every shot throws you back about 11–14 m (an impulse that fades like a knockback; walls stop you).
- **Crossbow** (Chu-Ko-Nu): damage 18.45 (the Pistol's ×1.5), 1.8 shots/s, magazine 20, **infinite ammo**, a **reload of 15 s** that is a **rhythm game**: a ring shrinks every second (`Gun.RHYTHM_PERIOD`),
  press [R] **or fire** (the mouse button, the trigger, the on-screen fire button: you cannot shoot while reloading anyway) when it meets the target ring (±0.18 s) to cut 2 s off the reload (once per beat). A miss or an extra press locks the cut for 4 s. Every **hit on the beat** (every cut of the reload) gives **+8% damage to the next magazine** and the bonuses stack (a 15 s reload allows about 6 hits: +48%); a miss only locks the cut, it does not take the bonus away. Synergis never makes a crossbow (`no_makers` in the archetype, the maker is rerolled), no hybrids.
  No other restrictions: all perks (pellets, piercing, splitting...) are allowed.
- New perk **Rhythmic** (`rhythm`, Rare and up): gives the rhythm reload to any gun that does not have it (the crossbow has it innately).
- Perk **Drum-Fed** changed: magazine +2, then ×2.3 (+130%), reload time +60% (was magazine ×1.9 +1, reload +15%).
- Neither type makes hybrids (`no_hybrid`; the Workshop does not combine them either). Archetype fields `recoil`, `free_ammo`, `rhythm`, `no_hybrid` and `sound.bank` are documented for modders.

### Knockback and pellets
- Knockback of a multi-pellet volley no longer adds up per pellet: the total push is `knock × (1 + 5 × k / (k + 8))`, where `k` is the number of pellets beyond the first.
  It grows slower and slower and never exceeds `knock × 6` (8 pellets ×3.3, 20 ×4.5, 60 ×5.4); one pellet is unchanged. The result is shared between the pellets (`Gun.volley_knock`).
- Every pellet beyond the first adds +1% damage to each pellet (the hero's and the turret's guns; DPS on the card includes it).
- Knockback by gun type (`knock` in `archetypes.json`): SMG 30 (weakest), Assault Rifle and Machine Gun 50 (a bit below normal), Pistol 60 (normal), Revolver 100,
  Rocket Launcher and Grenade Launcher 100 (strong; their explosions still add +120), Shotgun 55 (8 pellets ≈ 183 in total, strong), Sniper 200 and Mortar 200 (strongest).
  Before, rockets pushed harder than mortar shells and a shotgun volley harder than anything. A slug round pushes like the whole volley it replaces.
- New perk **Concussive** (`knock_boost`): multiplies the total knockback of a volley by `1 + 0.8 × 150 / knockback`, i.e. inversely proportional to the knockback itself:
  SMG 30 → ×5, Assault Rifle 50 → ×3.4, Pistol 60 → ×3, Revolver 100 → ×2.2, a 40-pellet shotgun (≈283) → ×1.4. The weaker the gun, the bigger the boost.
- Guns without damage falloff (Revolver and its hybrids) have a range of 1000 m (more than any map): the bullet flies until it hits a wall (or 5 s) at full damage.
- The turret's firing range is the gun's effective range, but at least 10 m and at most 40 m (a short-range gun still reaches 10 m, a Revolver doesn't snipe across the map).

### Growth at depth
- Enemy health grew ×1.2 per zone, new guns ×1.18, while the skill tree grows only about zone^1.5: past zone ~250 the hero could not hurt anything (at zone 1001: enemy health ~10^80 against a hit of ~10^76).
  Enemy damage was linear, so the hero's health from the tree ran ahead of it. Now, **after zone 200** (`Game.FLAT_FROM`) the curves are tied to a **reference hero** (level ≈ 0.88 × zone^0.92, a third of the points in Firepower and in Toughness; `Game.ref_*`):
  enemy health grows like the damage of a fresh gun × the damage of the reference tree, enemy damage grows like the reference hero's health, and on top of that comes a slow rise of +20% per 100 zones (`FLAT_RISE`). Up to zone 200 nothing changes.
- Result (hits needed relative to the start, 1.0): zone 100 — 0.30, 200 — 0.63, 500 — 1.0, 1000 — 1.6, 1200 — 1.9 (it used to be 1.9 at zone 300 and 5×10^4 at zone 1000). Enemy damage relative to hero health: 0.47 at zone 200, 0.75 at 500, 1.4 at 1200.
- Curves are capped at 10^300 (past zone ~4000 `pow` overflows).

### Interface in the style of the gun card
- Every menu screen except the main menu (Skills, Gun Shop, Workshop, Mystic, Healer, Guild, Recruiter, Custom start, Settings, Pause…) now sits in a panel like the gun card: dark background, a coloured bar on top and a frame of the same colour (the stall's colour, the branch colour on the skill screens). The shop titles take the same colour.
- **Skills**: a vertical list of cards. A card has a frame in the branch colour (dimmed for locked skills), the name and level, rows "Now" / "Next level ▲" / "Hero level" / "Requires" like the rows of the gun card, and the upgrade button on the right.
- **HUD**: the minimap has a frame in the biome colour; the weapon slots have the rarity bar on top and a rarity frame, like the card. The status block at the top left (health, zone, coins, level) stays unframed.

- New perk **Laser** (`beam`, Epic and up, group `kind`: not with Rocket, Grenade or Orb; not for mines): changes only the flight speed of the bullet, it is instant. Everything else is as for an ordinary bullet: it stops at the first enemy (it pierces only if the gun has Armor-Piercing), ricochets, falls off beyond the gun's effective range and is stopped by walls. A line is drawn to where the bullet ended. Because it is a perk, it can be rerolled in the Workshop and rolled on any bullet or pellet gun. A beam gun also works for the turret; enemies (e.g. the Anti-Player) shoot ordinary bullets. It does not combine with **Homing** (new perk field `excludes`, documented for modders); on Absurd guns, where nothing is excluded, the laser bullet simply ignores homing.

### Hybrids and the Workshop
- **Workshop: combine guns.** Pick a gun, then a partner (both must be ordinary, not hybrids or legendaries, of different types), then choose who shoots and who loads:
  the fire pattern and the maker come from the first gun, the projectile and the ammo from the second (Machine Gun & Sniper Rifle ≠ Sniper Rifle & Machine Gun).
  Both guns are consumed, the result takes the better rarity and level and the perks of both (as many as the rarity allows, one per group); the price is 50% of the price of such a gun.
- **Workshop: rerolling a perk now offers three perks to choose from** (that fit the gun and are not on it yet) instead of a random one. The price is paid when the three are shown;
  leave and come back, and you still pick from the same three.
- Hybrid guns (not legendaries) can no longer have a raw DPS (damage × projectiles × shots/s) above the blend of their two bases. A machine-gun pattern with sniper rounds fired
  1.9 shots a second with a sniper's 78 damage, i.e. 3–5 times the DPS of ordinary guns (a Synergis Machine Gun & Sniper Rifle showed 133 DPS when the average Synergis gun has about 30).
- Hybrid gun types are written with an ampersand ("Pistol & SMG", ru «Пистолет & пулемёт») instead of a hyphen: "Pistol-SMG" was easy to mistake for the Russian «пистолет-пулемёт» (= SMG). The template is `type_hybrid`.

### Gun card and menus
- New row **Knockback** (the total push of a volley). Accuracy can be negative (a 110° fan shows −142%), it is only a number: the spread itself is unchanged.
  Range shows "-" for guns without damage falloff and counts as infinite when guns are compared.
- The bottom of the card lists what the maker and every perk do in words, e.g. "Heavy: damage +35%, fire rate −15%" (generated from the perk operations, the same text as in the Codex).
- Gun Shop and Workshop screens are anchored to the top and the gun card gets a fixed slot (760 px): a tall card (Chaos Forge, many perks) no longer stretches the screen and moves
  the title and the lists. A card taller than the slot is shifted up so it stays on the screen; effect lines on a card take at most 4 lines each.

### Town and map
- **A trader on every map.** Every ordinary zone (not a boss zone) has a random stall somewhere on the map, far from the entrance and the portal, marked on the minimap: the Gun Shop or the Workshop (50/50); while you have no Guild contract, in half of the cases it is the Guild instead. A message at the start of the zone tells which one. The stall sells the same stock as a town stall (stock and contracts are made when the zone loads); the town healer and the Mystic stay in towns.
- The first (starting) town never sells Legendary or Absurd guns, and you now start a run with **120 coins** (was 100): `Game.START_COINS`.
- **Ultra coins.** Money is no longer an `int`: deep in the run prices (1.2^stage) overflowed int64 around zone 1200 and turned negative (−9223372036854775808; the Deal of the day then showed "— 1"). Coins, prices, rewards and kill income are now doubles (`Game.coins`, `Game.money()`, cap 10^300), and **10^17 coins = 1 ultra coin**: amounts from 10^17 are written in ultra coins ("60.5 UC", ru «УМ») on the HUD, in shops, in the Guild and on pickups; smaller amounts as before (exact up to a million, then 1.20M, 5.00Qa…). Integers stay exact up to 9×10^15.
- **Deal of the day.** The Gun Shop now has 11 guns (was 8). The rarest one (a random one among equals) is the deal: it sits in its own gold frame above the list and costs 50% (`Shops.DEAL_SHARE`, the old price is shown next to it). A new stock picks a new deal. The list of the other guns no longer scrolls (all 10 fit), the ammo list moved under "Your guns — sell".
- The restart stone in the starting town stands in the middle of the square (the nearest free spot if the centre has a pond or a monument), not next to the entrance.
- The minimap is open from the start (no fog of war) and shows every enemy as a red pixel; champions, leaders and bosses are still drawn as bigger dots.

### Zones and pacing
- Zones are smaller and have fewer enemies, aiming at ~4 minutes per zone instead of ~6:
  map side `64 + zone` (max 88) instead of `90 + zone` (max 120); packs `14 + zone/2` (max 28) instead of `20 + zone` (max 42).
- Coin income per zone is unchanged: every kill pays proportionally more (`Game.COIN_REF_ENEMIES`).

### Legendaries
- **Granny's Surprise** and **Monday** are always made by Dandy; Monday has at least 85% accuracy.
- **Bee Swarm** is always made by Errosion and always has acid.
- **Toaster of Fate**: the bullet ring now deals 100% damage (was 40%).
- **Neighbor with a Hammer Drill**: ricochets no longer reduce damage (new special `bounce_keep`).
- **Hedgehog in the Fog**: fixed the base order, it now fires grenades with the SMG pattern instead of plain SMG bullets.
- **Quantum** perk reworked: projectiles blink only to the nearest enemy ahead (up to 260 px) and stop right in front of it; no more overshooting and no hit-list reset.
- **Black hole** (Pocket Singularity, Gravity perk) is weaker as crowd control: smaller radius (120), half the pull, 1.2 s, max 4 at once, nearby holes merge instead of stacking, and elites resist the pull.
- New legendary **Flashlight** (assault rifle): Scattering, Precise (a narrow cone, accuracy at least 80%), Volley (a burst of 3) and the new perk **Laser** (instant bullets).
- Legendary modding: new `maker` and `min_accuracy` fields, new special `bounce_keep` (see the guide).

### Experience
- XP is counted per run and gives skill points: an enemy gives `1 + 0.1 × (level − 1)` (elites and bosses weighted), a level needs `40 × L^1.1`.
  Summoned enemies give no XP.
- New `Director` (`scripts/systems/director.gd`) measures how much XP each zone holds. Debug overlay (F3) shows `LV / XP` and the zone's XP pool.

### Balance and other changes in this build
- **XP multiplier:** the hero's experience is multiplied by the run's rating multiplier (Custom start: harder settings level you up faster, easier ones slower; default ×1).
- **Chests are off by default** and are an option of Custom start (rating multiplier −20% when on). The Guild no longer offers the «open chests» contract while they are off. The old «no chests +25%» rating bonus is gone.
- **Trial:** the base health of all regular enemy types is cut to 50% (Runner 32 → 16, Brute 150 → 75 and so on; `EnemyData.TYPES`). Zone growth, elite multipliers and bosses are unchanged.
- Synergis guns (infinite ammo) now use their own ammo type, energy: no ammo drops or sells for them any more, and the starter Synergis no longer fills the reserve of its base type. Hybrid names (mortar-machine gun and so on) are unchanged; recycling a Synergis still gives rounds of its base type.
- Guns with infinite ammo (Synergis) no longer roll perks that spend more rounds per shot for more damage or projectiles (Double-Barreled and the like): with free ammo the cost was zero.
- Workshop no longer raises a gun's level (guns are meant to go stale); it still rerolls perks and raises rarity.
- Skill changes: grenade explosion damage is flat across its radius; smoke grenade ticks 5 times a second; skill hits build up less elemental effect.
- Gun generator: shotguns roll a random pellet count with the same total volley damage; a mortar in a hybrid always makes the shot arc.
- Enemy types have innate element resistances (that element is 50% weaker on them): brute — cryo, kamikaze — fire, gunner / spreader / mortarman — shock, shaman — curse, runner / charger — acid. Shown in the Codex enemy table.
- Skill elements now work like guns: 35% chance per hit, build-up scales with the skill's cooldown. Pioneer's grenade 35 → 30 damage; Poison perk +30% → +50%.
- Android export preset now includes x86_64.

*Not in this build:* meta perks (Relic Keeper), run saves, XP level effects.
