# Changelog

## 0.1.1

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

### Pellets
- Knockback of a multi-pellet volley no longer adds up per pellet: the total push is `knock × (1 + 5 × k / (k + 8))`, where `k` is the number of pellets beyond the first. It grows slower and slower and never exceeds `knock × 6` (8 pellets ×3.3, 20 ×4.5, 60 ×5.4); one pellet is unchanged. The result is shared between the pellets.
- Every pellet beyond the first adds +1% damage to each pellet (the hero's and the turret's guns; DPS on the card includes it).
- Knockback by gun type (`knock` in `archetypes.json`): SMG 30 (weakest), Assault Rifle and Machine Gun 50 (a bit below normal), Pistol 60 (normal), Revolver 100, Rocket Launcher and Grenade Launcher 100 (strong; their explosions add +120 as before), Shotgun 55 (8 pellets ≈ 183 in total, strong), Sniper 200 and Mortar 200 (strongest). Before, rockets pushed harder than mortar shells and a shotgun volley harder than anything. A slug round pushes like the whole volley it replaces.
- The bottom of the gun card now lists what the maker and every perk do in words, e.g. "Heavy: damage +35%, fire rate −15%" (generated from the perk operations, the same text as in the Codex).
- Gun Shop and Workshop screens are anchored to the top and the gun card gets a fixed slot (760 px): a tall card (Chaos Forge, many perks) no longer stretches the screen and moves the title and the lists. A card that is taller than the slot is shifted up so it stays on the screen; effect lines on a card take at most 4 lines each.
- The restart stone in the starting town stands in the middle of the square (the nearest free spot if the centre has a pond or a monument), not next to the entrance.
- Guns without damage falloff (Revolver and its hybrids) have a range of 1000 m (more than any map): the bullet flies until it hits a wall (or 5 s) at full damage. The card shows "-" as range and counts it as infinite when guns are compared; the turret is limited to 40 m (see below).
- The turret's firing range is the gun's effective range, but at least 10 m and at most 40 m (so a short-range gun still reaches 10 m and a Revolver doesn't snipe across the map).
- The minimap is open from the start (no fog of war) and shows every enemy as a red pixel; champions, leaders and bosses are still drawn as bigger dots.
- Hybrid guns (not legendaries) can no longer have a raw DPS (damage × projectiles × shots/s) above the blend of their two bases: an MG-pattern gun with sniper rounds fired at 1.9 shots/s with a sniper's 78 damage, i.e. 3–5 times the DPS of ordinary guns (a Synergis Machine Gun-Sniper Rifle showed 133 DPS when the average Synergis gun has about 30).
- New perk **Concussive** (`knock_boost`): multiplies the total knockback of a volley by `1 + 0.8 × 150 / knockback`, i.e. inversely proportional to the knockback itself: SMG 30 → ×5, Assault Rifle 50 → ×3.4, Pistol 60 → ×3, Revolver 100 → ×2.2, a 40-pellet shotgun (≈283) → ×1.4. The weaker the gun, the bigger the boost. The gun card has a new row **Knockback** (the total push of a volley).
- Accuracy on the gun card can be negative (a 110° fan shows −142%), it is only a number: the spread itself is unchanged.

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
