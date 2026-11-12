# Will my DoTs kill it? (#175)

The target and focus frames show how much health the player's own damage-over-time spells still
have to take, and a kill icon once that is enough to kill the unit.

Status: **built** (2026-11-08). Milestone 1: the generated data (`DotSpells.lua`, build 70862),
the estimate, their fixtures, and the probe (`/fp steps cast dots`, run in game: section 8.1).
Milestone 2: the tracker (`Dots.lua`), the view (`DotView.lua`), the options, and their tests
(`test_dots.lua`, `test_dotview.lua`, both mutation-tested). Still to check in game: P6 on screen
(`/fp steps cast dotview`: the marker, and the kill icon's boundary at two UI scales), then a
real fight.

## 1. What the player sees

- **The marker:** a striped segment on the health bar, the size of the damage the player's DoTs
  still have to deal on that unit, on the max-health scale. It sits **on the health fill, ending at
  the fill's moving edge**: the part of the bar it covers is health the DoTs are going to take.
  It's clipped at the bar's start, so **when it covers the whole fill, the DoTs are expected to
  finish the unit.** The health-loss segment, heal prediction and absorb all sit past the edge,
  so nothing overlaps.
- **Tick lines** (on by default): thin dividers inside the marker, one per upcoming tick in time
  order (all DoTs merged; the next tick is nearest the moving edge). Counting lines to the bar's
  start tells you which tick is expected to kill. Up to 12 (the next 12 ticks); a line whose
  cumulative damage equals the previous one's isn't drawn. Lines past the unit's health fall
  outside the bar's clip on their own.
- **The kill icon:** a skull (the client's raid-target skull) centred on the target's portrait
  tile, or where the tile would be with the portrait off. Focus has no tile, so its icon sits
  outside the frame on the tile side. It shows only when the **committed** estimate (section 6.3)
  reaches the current health, and pulses slowly.

**What the icon promises:** "if the DoTs we inferred keep ticking for their expected size until
they end, this unit dies." A tick is **inferred** from a hit's school and timing, never identified
(the client names no spell or caster on a hit). Its **named limits**, each a way to show a false
icon that the client gives us no means to see:
- a heal or an absorb shield on the unit (it delays death);
- a reduction of our damage or of the damage the unit takes (a debuff on us, a defensive buff on
  it, a partial resist): the estimate is the raw formula;
- a DoT removed (dispel, early end) shows until its second missed observed tick (6.5), and one
  removed while neither target nor focus showed its mob shows until two observed misses after it
  comes back;
- another source hitting in the same school at the same rhythm keeps a lost DoT alive, and **one**
  unrelated hit in the right school and window can commit an application whose resist we didn't
  see, or fill another application's slot. Either lasts until the loss rule catches it (two
  observed misses);
- a cast sent at a mob that is neither target nor focus but has the same name as one of them is
  put on that one (SENT gives only a name). The mouseover guard (12.3) refuses the case it can
  see, a same-name mob under the cursor at SENT; another token aimed at by a macro, or a cursor
  moved between the key press and SENT (a queued spell), is still this limit;
- **spell power falling below the fight snapshot** (section 2) during the fight, mainly a buff
  up at the pull that ends mid-fight (a trinket, a proc, a temporary buff): a cast after the drop
  is priced with the snapshot, so its ticks are high by up to
  `floor((B + coef × snapshot) × shape[k]) − floor((B + coef × actual) × shape[k])` each. The
  snapshot is gone when the fight ends, but an application priced with it keeps those estimates
  until its own end (6.5). Our auras can't be read in combat, so the addon can't see the drop.

## 2. The rule: err low

A false kill icon is worse than a missing one. Every uncertainty lowers the estimate or leaves a
DoT out:

- A cast whose target can't be attributed to exactly one of target or focus is **not tracked**.
- Unknown combo points take 1 point.
- No learned or talent modifier is applied: the estimate is the client's base plus the spell
  power share, rounded down per tick. Talents and debuffs that add damage make the real number
  higher; the ones that reduce it are a named limit (section 1).
- A DoT that may have been resisted or removed is dropped (section 6.4).
- **Spell power** (amended after P2, section 8.1; it's secret in combat) comes from, in order:
  1. a plain read in the cast's own `UNIT_SPELLCAST_SENT` (the opening cast of a fight is out of
     combat: measured plain);
  2. the **fight snapshot**: one read per school index inside `PLAYER_REGEN_DISABLED` (measured
     plain there), kept for that fight only and dropped at `PLAYER_REGEN_ENABLED`. Never a read
     from before the fight, never one from an earlier fight;
  3. else 0.
  A multi-school spell takes the lowest of its schools from one source; any school unreadable
  there means the next source. The risk this takes is a named limit (section 1): a spell power
  buff up at the pull that ends mid-fight.
- Only spells on the supported list (section 5) are tracked.

## 3. Forever constraints

| Fact | Status | Consequence |
|---|---|---|
| Unit health and max health are secret, in and out of combat | measured (porting guide, #171) | No Lua comparison of damage vs health: StatusBars do it |
| `StatusBar:SetMinMaxValues` / `SetValue` take secrets | measured (every GUF bar) | The marker and the kill icon are StatusBars |
| Auras are unreadable in combat, for every unit | measured | DoT state is tracked from our own casts, never read back |
| `UNIT_COMBAT` (unit, action, flags, amount, schoolMask): no spell, no caster | dump | Ticks are matched by school and timing only |
| `UNIT_COMBAT` amount secret in combat; action and school plain | reported by another Forever addon, **not measured here** (P1) | The amount is never read |
| `GetSpellBonusDamage(school index)` | **measured** (P2): plain out of combat, secret in combat, plain inside `PLAYER_REGEN_DISABLED` and the opening cast's SENT | SENT read, else the fight snapshot, else 0 (section 2) |
| `UnitAttackPower` | measured plain out of combat, secret in combat (P2) | AP shares aren't used (errs low) |
| The player's own cast times and castGUID | measured plain (#72) | — |
| Combo points | `UnitPower("player", 4)` plain in combat for a priest; a rogue or druid **unmeasured** (P3) | Read at SENT if plain, else 1 point |
| `UnitGUID` for mobs | plain outdoors; in instances **unmeasured** (P5) | A per-token fallback key (6.1) |
| `COMBAT_LOG_EVENT_UNFILTERED` | forbidden | Not used |

## 4. Scope of this first version

In: the player's own single-target DoTs that land on a targeted enemy (Corruption, Shadow Word:
Pain, Bane of Agony, Immolate's periodic part, Moonfire's, Insect Swarm, Rend, Rip, Rupture,
Garrote, Rake's bleed, Pounce Bleed, Serpent Sting, Flame Shock, Devouring Plague, Holy Fire's
periodic part, Siphon Life), on target and focus. Nothing joins automatically: a new spell is a
reviewed edit of the supported list (section 5).

Out (follow-ups, each only if the owner asks): channels (Drain Life, Mind Flay), DoTs while being
cast, a learned per-spell modifier from the damage meter, duration-extending talents, other
players' and the pet's DoTs, traps, nameplates, AoE DoTs, direct damage in flight.

## 5. The spell data: generated from the client's tables

`DotSpells.lua` is generated by `Tools/dot_spells.py` from one coherent set of the client's DB2
tables (all from **one build**, fetched by the wago-tools skill into `References\Forever\db`; the
script refuses a mixed set). Its header names that build. No tooltip parsing: no locale tables,
no regexes, no hand-kept tick intervals or schools.

- **The universe:** class spells only (`SkillLineAbility` rows with a class mask), plus the
  spells their `Effect` 64 triggers. A same-name NPC spell (Corruption 18376: target 22, base
  ~351) is never a rank.
- **Which spells: a supported list, generated fields.** `Tools/dot_spells.py` holds the list of
  supported spell families by name (Corruption, Shadow Word: Pain, Bane of Agony, Immolate, Siphon
  Life, Moonfire, Insect Swarm, Rend, Rip, Rupture, Garrote, Rake, Pounce Bleed, Serpent Sting,
  Flame Shock, Devouring Plague, Holy Fire), applied to that universe. Each family's ranks are its
  rows there; the numbers come from the tables.
- **Candidates it reports, never adds:** class spells (`SkillLineAbility` rows with a class mask)
  with a `SpellEffect` (DifficultyID 0) of aura 3 (periodic damage) or 53 (periodic leech) on
  `ImplicitTarget_0` 6 (the enemy target), not channelled (`SpellMisc.Attributes_1` bit 0x4 or
  0x40), that aren't on the list. A candidate whose description uses a formula variable
  (`$<power>`, `$<damagepower>`: Living Bomb, Sunfire, Void Plague) scales its own way and is
  marked so. Joining the list is a reviewed edit with a fixture.
- **A supported row is refused** (the script fails) when its description uses a formula
  variable (`$<…>`) other than its family's reviewed exceptions, when it's channelled, or when its
  aura isn't 3 or 53 on target 6. The one exception today: Immolate's `$<mult>`, which belongs to
  its direct part (`${$m2*$<mult>}`); its periodic part is the plain `$o1` of the periodic row.
- **Triggered auras:** a targeted cast with an `Effect` 64 (trigger spell) whose triggered spell
  qualifies maps to it (Pounce 9005 → Pounce Bleed 9007). The triggered spell's own duration,
  period and base are used, never the parent's (Pounce's 2 s stun).
- **Per aura spell**, joined by SpellID:
  - `school`: `SpellMisc.SchoolMask`, converted to `GetSpellBonusDamage`'s index (1 → 1, 2 → 2,
    4 → 3, 8 → 4, 16 → 5, 32 → 6, 64 → 7). A multi-school mask keeps every index; the cast uses
    the **lowest** plain read among them;
  - `period` (`EffectAuraPeriod`, ms);
  - `duration` (`SpellDuration.Duration`) and `durationPerCombo` (`DurationPerResource`), capped
    at `MaxDuration`. Ticks = duration ÷ period, rounded down;
  - `base` per tick (`EffectBasePointsF`, as is: no Classic "+1"), `perLevel`
    (`EffectRealPointsPerLevel`) with `SpellLevels.BaseLevel`, `MaxLevel` and `SpellLevel`;
  - `perCombo` (`EffectPointsPerResource`);
  - `coef`, the spell power coefficient **per tick** (`EffectBonusCoefficient`);
  - `travel`: true when `SpellMisc.Speed` > 0 or `LaunchDelay` > 0;
  - `family`: the lowest spellID sharing the aura's name, so ranks replace each other.
- **Per-tick estimate** (in Lua, all plain):
  `floor((base + perLevel × L + perCombo × points + coef × spellPower) × shape[k])` for tick k
  (shape 1 for an even DoT), where `L = max(0, min(playerLevel, cap) − SpellLevel)` with
  `cap = MaxLevel` when `MaxLevel > 0`, else no cap (an explicit branch, never `MaxLevel or …`),
  and the tick count is `floor((duration + durationPerCombo × points) ÷ period)`, the duration
  capped at `MaxDuration`. Every periodic row in 70532 has `perLevel` 0, so the level term is
  covered by synthetic fixtures.
- **Hand-kept, measured facts** (a small table in `Dots.lua`, each with its source): Bane of
  Agony's back-loaded shape (0.5 ×4, 1 ×4, 1.5 ×4; measured on Forever by another addon's logs,
  re-checked by P4).
- **Numeric fixtures** (a Lua test over the generated file, values at 70862; 70532 had Rip at
  3 + 4.4, Serpent Sting at 2 and Pounce Bleed at 15): Corruption 172 (4 ticks of 10 every 3 s,
  coefficient 0.2, Shadow → 6), Rip 1079 (6 ticks every 2 s, 4 + 5.5 per point), Rupture 1943
  (6 s + 2 s per point, max 16 s), Pounce 9005 → 9007 (6 ticks of 19 every 3 s), Immolate 348 (5
  ticks of 3, coefficient 0.13; the direct part ignored), Serpent Sting 1978 (5 ticks of 3,
  coefficient 0, travel). Rupture's `$<bloodS>` is a reviewed exception like Immolate's: it only
  lengthens the duration (more ticks than we count, so it errs low). They test **computed** results too: Rip at 1 and 5 points, Rupture's
  capped duration and tick count, Corruption with spell power 100, Agony's twelve shaped ticks,
  and synthetic level rows (below `SpellLevel`, above a `MaxLevel`, `MaxLevel` 0 uncapped). A
  failing fixture after a regeneration means the client's data changed meaning: read it, don't
  loosen the test.

## 6. The tracker (`Dots.lua`, `GlassUF.Dots`)

Its own event frame (like `FiveSecond.lua`): it needs every payload in order, which Engine's
dirty channels discard.

### 6.1 Keys

A DoT belongs to a mob key: the GUID when `UnitGUID` is plain; else the token with a
**generation** (`"target#7"`), bumped whenever that token changes. A SENT record, a pending
application or an active one with an older generation is discarded at its next step, so a cast
sent at mob A never lands on mob B. A target and a focus on the same GUID share one key. The hook
is chained into `Engine.OnTokenChanged`, after what it already does (the cast reset, the target's
auras and sheen).

### 6.2 Applying

- `UNIT_SPELLCAST_SENT` records castGUID → key. The cast's target name is matched against target
  and focus with GUF's `isNameOf` (the cast bar's). **Exactly one** match picks that unit; both
  (same name, different GUIDs), neither, a secret name, or an unattackable unit records nothing,
  and the cast isn't tracked. Combo points are read here (`UnitPower("player", 4)`, plain or 1),
  and spell power for the cast's schools (plain, else the fight snapshot, section 2).
- `UNIT_SPELLCAST_SUCCEEDED` for a recorded castGUID whose spell maps to an aura applies it,
  **pending** until its outcome (6.4). A pending application never touches the one it would
  refresh: on confirmation it replaces the same `family` on that key; on failure it's discarded
  and the old one keeps ticking.
- The application is fixed then: start time, its tick slots (time and estimate each), end time.
- **Two cutoffs per slot.** Its **damage** stops counting at the earlier of a matched hit or the
  start of its window (the slot's time − 0.45 s, after the bounded rhythm shift): from then on the
  tick may already have landed unseen, so it's no longer "remaining". Its **evidence** window runs
  to the slot's time + 0.45 s (the first slot: + 1.5 s for `travel`): until then a hit can still
  match it, which commits the application and anchors the rhythm, but never gives damage back.
  `remaining` = the estimates of the slots whose damage still counts, whether or not the mob is
  watched, and every `Estimate` call first applies both cutoffs, so a health repaint between
  passes never uses a stale total.

### 6.3 Committed vs shown

An application shows on the marker once confirmed. It counts toward the kill icon ("committed")
only once a tick of it was **matched** (6.5). An application never seen ticking (the mob was out
of sight) stays on the marker only. The removal cases in section 1's named limits are the
remaining ways a committed DoT can be gone.

### 6.4 Outcomes

`UNIT_COMBAT` on the key's canonical token (6.5), within 0.4 s after the SUCCEEDED (0.25 s
before it):

- `RESIST`, `IMMUNE`, `MISS`, `EVADE`, `REFLECT`, `DEFLECT` → the pending application fails.
  `DODGE` / `PARRY` fail only a Physical one (spells can't be dodged).
- Anything else, or nothing → confirmed at the window's end. Err-low note: someone else's resist
  in that window drops ours. That's a lost DoT, never a false kill.

### 6.5 Ticks and loss

- **Canonical token:** for each key, events are taken from one token only, the target if it shows
  that key, else the focus. Every event from that token counts, so two same-school ticks in one
  frame are two ticks.
- A `WOUND` or `ABSORB` in an application's school fills that application's earliest unfilled
  slot whose evidence window holds the hit (6.2). **One event fills at most one slot:** among the eligible applications, the one whose slot time is nearest,
  ties to the oldest application. The amount is never read in combat. The **end time never
  moves**: a matched tick may shift the remaining slots' times by at most ±0.25 s in total from
  the start rhythm, never their count.
- **Loss:** two consecutive slots that fell inside an observable window (the key's canonical
  token existed for the slot's whole window) with no matching hit drop the application. That
  covers a resist we didn't attribute, an immune, a dispel and an early removal, unless another
  source keeps hitting in that school at the same rhythm (the named limit).
- Other ends: the end time, the mob's death (`UNIT_DIED` with its GUID, or the unit plainly
  dead), `PLAYER_ENTERING_WORLD`, and a per-token key's token changing.

### 6.6 What it hands out

`Dots.Estimate(unit)` → `shown, committed` (plain totals) and the upcoming ticks as a list of
cumulative shown damage, in time order. A change marks the `dots` channel dirty on the frames
showing that key (`Engine.MarkDirty`). A 4 Hz pass (ticks fall due, slots expire) runs only while
any application exists, and idles otherwise.

## 7. The view (`DotView.lua`, `GlassUF.DotView`)

Built for target and focus at `Frames.Build` under `attempt`, like the crowd-control icon.

- **Marker:** `Frames.OverlayBar` on the health bar, full health-bar width, **reverse fill**,
  anchored TOPRIGHT to the health fill texture's TOPRIGHT, inside the overlay's clip (the bar's
  bounds) and its rounded mask, level +3. Two layers on the fill's span: `bar_fill` tinted (red,
  translucent), and over it the client's tiling stripe, the atlas `RaidFrame-Shield-Overlay` with
  wrap address modes and tiling on (run #111: faint light diagonal stripes, which the tint barely
  colours; `RaidFrame-Absorb-Overlay` draws plus signs). If `SetAtlas` fails, the tinted fill
  alone. P6 tunes the alphas on the bar. Values: `SetMinMaxValues(0, UnitHealthMax(unit))`,
  `SetValue(shown)`, snapped.
- **Tick lines:** up to 12 reverse-fill StatusBars in the same clip, with the marker's size,
  anchor and max, each with a **transparent fill texture** (the bar itself stays visible) filled
  to the cumulative damage up to tick k, and a 1 px line texture anchored to that fill's left
  end, masked by the same rounded mask. Unused bars are hidden.
- **Kill icon:** a clip window the icon's size `S` (70% of the tile's inner square), holding a
  **normal-fill** StatusBar of length `L` = 10,000 px whose right end is the window's right edge,
  with the skull's **right edge** anchored to the fill texture's right end (`S` and `L` in the
  same units: both are children of the window, unscaled). `SetMinMaxValues(0, UnitHealth(unit))`
  and `SetValue(committed × (1 − S / L))` (plain arithmetic on our own number): in ideal geometry,
  the skull starts to enter the window only once `committed` exceeds health, and is fully in once
  `committed ≥ health / (1 − S/L)`, late by `(S/L) / (1 − S/L)` (about 0.2–0.4%). P6 checks the
  boundary.
  The window sits above the portrait model, under the tile rim, under the crowd-control icon.
- **Placement** of the icon window is out of combat: `DotView.Place(b)` defers through
  `GlassUF.WhenOutOfCombat("dots:<unit>")` when the lockdown is on (as `Auras.PlaceCC`), called at
  build and from `applyPortrait`.
- **The painter** (`dots` channel): health values straight to the bars inside one `attempt`; a
  plain non-number, a dead, offline or non-attackable unit, or a failed paint **clears every bar
  and hides the icon window**.
- **Engine wiring:** `dots` is added to `Engine.CHANNEL_EVENTS` (`UNIT_HEALTH`, `UNIT_MAXHEALTH`,
  `UNIT_FACTION`, `UNIT_CONNECTION`) and to `Engine.ORDER`, registered only on target and focus.
  Token changes come through `Engine.OnTokenChanged` (a repaint; the tracker keeps its state by
  GUID).
- **Preview:** `Frames.PaintSample` shows a sample marker at 35% with four tick lines on target
  (`Engine.Owned` gates the real painter), and the kill icon on focus.

## 8. Probe (`Tools/CastProbe`, `/fp steps cast dots`), before anything is trusted

- **P1** `UNIT_COMBAT` on the target in combat: amount, school and action, plain or secret; their
  timing against SUCCEEDED and the period (first tick within the window? a projectile's lateness?
  a refresh: does the rhythm restart?). Two same-school DoTs ticking together: two events?
- **P2** `GetSpellBonusDamage(2..7)` plain or secret, in and out of combat.
- **P3** `UnitPower("player", 4)` at `UNIT_SPELLCAST_SENT`, in combat.
- **P4** Our per-tick estimate vs the meter's per-spell total for Corruption, Shadow Word: Pain,
  Agony (shape), Rend and Rip, logged after combat (diagnostic only).
- **P5** `UnitGUID("target")` in a dungeon: plain or secret.
- **P6** Screenshots, at UI scale 1 and 0.64: the marker and tick lines on a mob; the kill icon
  with the estimate just below, equal to and just above the health, on a low-health mob (tens of
  health) and a high-health one (thousands); a dead (0 health) unit; whether the stripe texture is
  present. The preview's sample values drive the boundary cases, so they don't need a lucky
  fight.

### 8.1 Results, run #108 (2026-11-08, 70862, a level-18 priest's Shadow Word: Pain, outdoors, solo)

The facts are in the porting guide ("Damage over time", the cast section).

- **P1:** `UNIT_COMBAT`'s amount is secret in combat; the action, the flag and the school are plain.
  The first tick came 3.05 s after SUCCEEDED, then every 3.0 s (±0.04). A refresh restarts the
  rhythm (ticks at +3.07 and +6.00 from the recast). Ticks can crit. In one run the first tick
  never reached `UNIT_COMBAT`, while the next seven did. The loss rule needs two observed misses,
  so that run would still commit on the second tick.
- **P2:** spell power is plain out of combat (22) and secret in combat, yet plain inside
  `PLAYER_REGEN_DISABLED` and in the SENT of the opening cast. With the plan's rule (0 when not
  plain), a cast in combat estimated 18 per tick where the real tick was about 23.
- **P3:** combo points read plain 0 in combat for a priest; a rogue or druid is unmeasured.
- **P4:** Shadow Word: Pain rank 970: estimate 22 per tick (18 + 0.2 × 22). The meter's 186 over
  8 ticks is 23.25 a tick, and 81 over 3 ticks with one crit fits about 23 a tick. So the estimate
  is about 5% low (talents, crits), which errs on the right side. The tables say 18 s (6 ticks),
  but it ticked for 24 s (8 ticks): a duration talent (Improved Shadow Word: Pain?). Our count stops
  two ticks early, which also errs low.
- **P5:** creature GUIDs are plain outdoors. Instances are unmeasured.
- **P6 (texture):** `Interface\RaidFrame\Absorb-Overlay` isn't in the client as a file. Run #111
  (`/fp cast dots stripe`): the atlases `RaidFrame-Absorb-Overlay` (7539063) and
  `RaidFrame-Shield-Overlay` (7539079) resolve, 32×32 and tiling both ways, and so does the file
  `Interface\RaidFrame\Shield-Overlay` (798065). On screen, the absorb atlas draws yellow plus
  signs (untinted), and the shield atlas and file draw faint diagonal stripes. The marker uses the
  shield atlas over a tinted fill; its look on the bar is P6's screenshot in milestone 2.
- **Untested** (no character for it): combo points, projectile DoTs, two same-school DoTs
  together, instances. Each keeps the plan's err-low default.

## 9. Settings

`db.dots = { marker, ticks, icon, focus }`, each saved only when off, all on by default:
`Settings.SetDots(key, on)`, `/glass dots on|off|marker|ticks|icon|focus on|off`, and checkboxes
on a small **DoTs** sub-page registered after Threat.

## 10. Files and tests

- **New:** `DotSpells.lua` (generated), `Dots.lua`, `DotView.lua`, `Tools/dot_spells.py`,
  `tests/test_dots.lua`, `tests/test_dotview.lua`, `tests/test_dotspells.lua`.
- **Changed:** the TOC (`DotSpells.lua` → `Dots.lua` → `DotView.lua`, after `ThreatView.lua`),
  `Engine.lua` (the channel), `Frames.lua` (build hook, `applyPortrait` → `DotView.Place`,
  `PaintSample`), `Compat.lua` (`API.SpellPower(indices)`, `API.ComboPoints()`: presence-checked,
  pcall, plain or nil), `GlassUnitFrames.lua` (db, `/glass dots`, `Settings.SetDots`),
  `Options.lua` (the sub-page), `Preview.lua`, `tests/wow_stubs.lua` (`UNIT_COMBAT` driving,
  `GetSpellBonusDamage`), `Tools/CastProbe` (the procedure), `CLAUDE.md`.
- **Tracker tests:** apply → ticks by time → remaining; refresh only on confirmation; a failed
  refresh keeps the old one; resist / immune / dodge on a spell and on a bleed; an ambiguous cast
  target isn't tracked; two consecutive observed misses drop; unobserved slots never drop; the
  end time never moves; an early matched tick stops counting at once (the 49 → 39 health case);
  a tick due while the mob was out of sight stops counting at its window's start (Corruption: 39
  health, first tick matched, the second lands unseen at 6 s, retarget at 6.1 s: committed is 20,
  not 30); an early tick missed in an observation gap; a hit in a retired slot's evidence window
  commits but adds nothing; one unrelated same-school hit commits a resisted application (the
  named limit, cleared by two observed misses); a same-name cast off target and focus lands on the
  watched one (the named limit);
  `Estimate` retires due slots by itself; one event fills one slot, two events fill two;
  same-school ticks in one frame; target and focus on one GUID counted once; committed only after
  a matched tick; a stale-generation SENT, pending and active application on a token change;
  spell power: a plain SENT read wins, a secret one takes the fight snapshot, no snapshot (the
  `PLAYER_REGEN_DISABLED` read was secret, or the fight ended) means 0, and a snapshot never
  outlives its fight; a multi-school spell with one school unreadable in a source takes the next
  source; the measured order (SENT → SUCCEEDED → `PLAYER_REGEN_DISABLED`, lockdown false in the
  handler): the opener keeps its SENT value, a later secret SENT takes the snapshot;
  `PLAYER_REGEN_DISABLED` before any cast, with a plain and with a secret read; a load already in
  combat (no `PLAYER_REGEN_DISABLED` this session): a secret SENT means 0; a cast's spell power
  stays fixed when a snapshot is taken or dropped after it; combo points plain and secret; `UNIT_COMBAT` with a
  secret amount (a proxy that throws on any use).
- **View tests:** only StatusBar calls touch health (secret proxies throughout); the anchors and
  fill directions; the icon's value is `committed × (1 − S/L)`; clearing on a failed paint; tick
  lines; the preview; the methods against the dump.

## 11. Review reconciliation

### Round 1 (Codex gpt-6-astra: REVISE)

Taken:
- Builders use power type 4, not 14 (verified: Sinister Strike, Shred). The builder table went
  with combo counting (below), and combo points are read at SENT instead.
- The skull bar is normal fill, and the trick reveals early by `S/L`: the value is now scaled by
  `1 − S/L`, and P6 checks the boundary.
- An ambiguous cast target is untracked, not "the target".
- Pending applications never replace committed state; a failed refresh keeps the old one.
- The end time is fixed; rhythm shifts are bounded; ticks are consumed by time.
- Loss after the first tick: two consecutive observed misses (dispel, removal).
- One canonical token per key, keeping every event from it (the same-school collapse).
- Committed vs shown: the icon needs a seen tick or an unobservable first slot (superseded in
  round 2: a matched tick only).
- The generator: one build's tables, DifficultyID 0, the triggered aura's own data, level scaling
  bounds, school index conversion, the channel bits, a rank family, numeric fixtures.
- The integration: Engine's `ORDER`, the combat queue for placement, clearing on failure, Compat
  guards, the full list of changed files.
- Cut from the first version: the meter modifier (contamination across mobs and sessions), extra
  ticks, combo counting, cast-time and channel contributions.

Not taken:
- Deferring tick lines: they're cheap, and they need no data the marker doesn't already have. P6
  checks them with the marker.

### Round 2 (Codex gpt-6-astra: REVISE)

Taken, all seven:
- Commitment needs a matched tick; the unseen-first-tick exception is gone, and the false-icon
  intervals of removal are named limits (section 1).
- Slots are consumed at the earlier of a match or the deadline; `Estimate` retires due slots; one
  event fills one slot, nearest first.
- Spell power not plain at the cast is 0 (any unreadable school of a multi-school spell too).
- A supported list of families with generated numbers; other candidates are reported, never
  added. Verified: Living Bomb's and Sunfire's descriptions use `$<power>` / `$<damagepower>`.
- Mitigation is a named limit, and section 2 no longer claims omitted modifiers only add damage.
- Agony's shape is inside the floor; computed and synthetic level fixtures; P6's boundary set.
- The per-token fallback key carries a generation, checked at every step.
### Round 3 (Codex gpt-6-astra: REVISE)

Taken, all four:
- Damage and evidence cutoffs are separate: an unmatched slot stops counting at its window's
  start, and stays matchable for evidence to its end (the retarget case is a test).
- The generator's universe is class spells plus their triggered children (verified: Corruption
  18376 is an NPC spell); the formula-variable refusal has reviewed per-family exceptions
  (verified: Immolate's `$<mult>` is in its direct part).
- The named limits cover one-hit false commitment, a wrong slot and same-name off-token casts;
  ticks are called inferred.
- The stale wording is gone (cached spell power, automatic additions, round 1's unobservable
  first slot), and the skull's right-edge anchor is explicit.

### Round 4 (Codex gpt-6-astra: APPROVE)

No new blocking defect; approval is for implementation behind P1–P6. Two implementation notes,
kept:
- `isNameOf` is local to `Castbar.lua`: it moves to `Compat.lua` (`API.IsNameOf`), used by both.
- A late match after a slot's damage cutoff must never reactivate it, rhythm shift included: a
  test.
- The generated file keeps the tables' full precision (the fixtures above are rounded
  descriptions).

### Amendment after the probe: spell power (owner's pick, 2026-11-08)

P2 measured spell power secret in combat, so the plan's "0 when not plain" priced every cast
after the opener at base only (Shadow Word: Pain at level 18: 18 a tick against a real 23; at 60,
about half). The owner picked the fight snapshot read inside `PLAYER_REGEN_DISABLED` (section 2),
with the buff-ending case as a named limit.
Codex (gpt-6-astra) on the amendment: no defect in the precedence or the event order (the log
shows SENT → SUCCEEDED → `PLAYER_REGEN_DISABLED` for both openers). Taken: the named limit is
stated as a drop below the snapshot, with the floor and shape in its bound, and an application
priced with the snapshot keeps its estimates past the fight; four transition tests. Not taken
(Codex agreed): a minimum with an earlier out-of-combat read (the same buff can be in both), and
the snapshot for the marker only (it brings back the base-only icon).

## 12. Open leads (2026-11-11, not built)

These came from comparing how another DoT tracker handles finishers and mouseover casts, then one
Codex round (gpt-6-astra: REVISE, folded in below, each claim checked against the code). Each lead
needs the owner's go-ahead, and all but 12.1 need a measurement first. Until then the err-low
behaviour above stands.

### 12.1 A defect: the lookback kept only the newest avoid (fixed in #176)

`onAvoided` overwrote `lastAvoid[key]` with each avoid. Our Corruption's `RESIST` at −0.20 s,
then anyone's `DODGE` at −0.10 s, then SUCCEEDED: the lookback saw only the dodge, which doesn't
fail a spell, so a resisted Corruption was confirmed. A later stray Shadow hit could then commit
it (the one-hit named limit). The lookback test had one avoid. Fixed: `lastAvoid[key]` keeps the
newest time per rule, `all` for the avoids that fail anything (`AVOIDED`) and `melee` for the
physical-only ones (`MELEE_ONLY`), and `avoidedBefore` checks both. `test_dots.lua` covers the
sequence (red on the old code), a dodge just before a bleed and before a spell, and an avoid
older than the lookback. A school filter (12.2) must keep the same property: a newer, unrelated
avoid never erases an older one that applies.

### 12.2 Someone else's avoid fails our pending cast

`UNIT_COMBAT` on a unit reports what happens to that unit, from any attacker. Its payload has no
attacker or spell, and Blizzard's combat feedback shows it unfiltered. `onCombat` hands every
avoid on the mob to `onAvoided` without its school, and `MISS` / `RESIST` fail an application of
any school. So a white-swing miss inside the window (ours, a party member's, a hunter's Auto Shot)
drops our Corruption or Serpent Sting (Nature), not just a bleed. That errs low. How often it
happens in a group is unmeasured (the probes were solo).

- **A school filter, for spell DoTs (dropped by the probe, 12.5: every avoid carries school 1):**
  an avoid is not ours only when its school is plain,
  **positive**, and shares no bit with the application's mask (`bit.band`: the `bit` table is in
  the dump's `_G` walk, and Blizzard's UI calls it). A school of 0, malformed or unreadable, keeps
  today's rule.
  - **It's limited to the actions measured.** Measure `MISS` and `RESIST` first. `IMMUNE`,
    `EVADE`, `REFLECT` and `DEFLECT` keep today's rule until each is measured: Blizzard's feedback
    never reads their school.
  - **The probe (a P1 extension), `/fp steps cast avoids`** (`Tools/CastProbe/DotLeads.lua`):
    the school on our own resisted DoT, and on unrelated melee and Auto Shot misses, in a party.
    Also check that Serpent Sting's own miss arrives as Nature, not physical, and when it arrives.
    Each avoid on the mob is logged against our newest DoT's SENT and SUCCEEDED, and against our
    own swing (`PLAYER_SWING`) or ranged attack. The summary counts the avoids that landed
    inside a cast's outcome window, and the flagged `WOUND`s.
  - **Not for physical bleeds:** a white swing has their school.
- **Combo points, for physical bleeds: deferred.** The idea was to re-read the points after a
  bleed fails: a finisher (Rip, Rupture) that landed spends them, and an opener or builder
  (Garrote, Rake, Pounce) that landed adds one. Rend has no such signal. Codex's case against
  building it now holds:
  - **What the points are tied to is unknown.** Forever's own combo frame reads
    `GetComboPoints("player", "target")` (Camelot `ComboFrame.lua:101`), so the points may follow
    the target; ours reads `UnitPower("player", 4)`.
  - **Order and identity:** the order of SENT, SUCCEEDED and the point update is unmeasured.
    Ruthlessness, Seal Fate and Premeditation also move points.
  - **Changes that leave no trace:** a GUID key never goes stale, so A → B → A passes an endpoint
    check.
  - **Hard vetoes:** a recovery would have to keep a later `IMMUNE` as a hard veto.

  That's a resource-attribution subsystem to rescue applications that are dropped on purpose
  today. Revisit only if a rogue or druid probe shows a narrow case worth it: points at SENT,
  SUCCEEDED and each power event, plus which token they follow. If it's built: a reviewed
  finisher/builder list (not `perCombo`, which only scales damage); the original `castAt`, slots
  and estimate kept; the old application kept until recovery succeeds; the recovered one
  uncommitted; cleared on every reset.
- **A projectile that fails late:** `TRAVEL` stretches the first tick's evidence window, but not
  the 0.4 s outcome window, so a Serpent Sting that misses later is already confirmed. Its timing
  is in the probe above. Until then it's a gap, not a measured defect.
- **Resists inside a `WOUND`:** Blizzard's feedback handles a `WOUND` with a resist flag (a partial
  resist), and Dots ignores flags. The probe should check whether a full application failure ever
  arrives that way. A partial resist is a hit, so the flag alone fails nothing.

### 12.3 Mouseover casts (built in #176, 2026-11-12)

**As built** (`Dots.lua`'s `mouseoverElsewhere`). Codex, three rounds: REVISE (the name check
below), REVISE (a raw surname compared to nil, which throws when secret), APPROVE. At SENT, once exactly one of target and focus is bound:
1. `UnitExists("mouseover")` plain false: tracked. Not plain: untracked.
2. `UnitIsUnit("mouseover", unit)` plain true: tracked (the cursor on the bound mob or its frame).
3. The name, in `API.IsNameOf`'s three forms, read under pcall: a plain match counts; a mismatch
   counts only when the display name and the first name are plain and the surname is plain or
   absent. A plain mismatch: tracked.
4. Otherwise (same name, or a name we couldn't rule out), tracked only if `UnitCanAttack` is
   plainly false. Not `API.CanAttack`, which reads unknown as false.

The guard runs after the SENT sweep and the spell lookup, and before the combo and spell-power
reads; a refused cast leaves no SENT record, so its SUCCEEDED does nothing and an existing
application is kept. `test_dots.lua` covers each branch, the focus, the ambiguity rule, the
unreadable reads and the timing; five mutations went red (no guard, the looser name rule,
`API.CanAttack`, an unknown `UnitExists` passing, no identity pass). Still to see in game: a
same-name mob under the cursor and a `[@mouseover,harm]` macro.

The design, as proposed:

Section 1's same-name limit, with a way to show a **false** icon: a `[@mouseover,harm]` macro (the
porting guide measured one working in combat) or the client's mouseover casting (CVar
`enableMouseoverCast`, read by Blizzard's `SecureTemplates.lua`) aimed at a same-name mob that's
neither target nor focus is credited to the watched one. A guard: at SENT, when `mouseover`
carries the cast's name and is attackable, the cast is tracked only if `UnitIsUnit("mouseover",
unit)` says plainly that it's the bound unit. Anything else (another mob, a secret or failed read)
leaves it untracked. Not gated on the CVar, which would miss macros. Its cost: a hard cast at the
target while the cursor rests on another same-name mob isn't tracked (errs low).

**The probe, `/fp steps cast mouseover`** (`Tools/CastProbe/DotLeads.lua`): at each DoT's SENT,
the mouseover's name, GUID, hostility and death, `UnitIsUnit` against target and focus, the
SENT's name, GUF's `API.IsNameOf` match, the CVar and `IsMouseoverCastSupported()`, each plain
or secret, in and out of combat. The cursor goes on the target, on another mob (same name if
possible), through a mouseover macro, and over nothing. The guard is worth building only if
`UnitIsUnit("mouseover", "target")` is plain in combat: if it's secret, the guard would leave
nearly every cast untracked.

### 12.5 Probe results (2026-11-12, 70888)

Run #253 (`/fp steps cast avoids`): a priest, solo, Shadow Word: Pain, Holy Fire, wand and melee
on orange Snapjaws, in water. Steps 5 to 7 (Serpent Sting, an immune mob, a party) were skipped.
Runs #204 and #207: a paladin in melee (Seal of Righteousness), from the same module's trace,
outside a procedure. The mouseover procedure wasn't run, but the module logs the mouseover at
every DoT SENT, so its key reading is in.

- **Every avoid came with school 1.** 24 avoids over the three runs (`MISS` 12, `PARRY` 7,
  `DODGE` 5), all `schoolMask = 1`. No `RESIST` arrived, and no `IMMUNE`. The flagged `WOUND`s
  carry their real school (Holy 2 and Fire 4 crits, physical glancing blows), so the field is
  plain and specific on hits, just not on avoids.
- **Ours, melee and wand:** our swing's avoid arrives 0.1 to 0.6 s after its `PLAYER_SWING`
  (paladin `DODGE` +0.5 and +0.13 s; priest `PARRY` +0.6, `DODGE` +0.6), and a wand's `MISS`
  0.6 s after its shot (four times). The probe's 0.3 s swing match (`NEAR_SWING`) was too
  tight, so step 3's check failed on our own parry.
- **Someone else's:** before we entered combat, the first mob took `GLANCING` wounds (school 1)
  and a `PARRY` and two `MISS`es. Glancing blows come only from players and pets, and we weren't
  fighting, so these were another attacker's. One of those `MISS`es landed 0.8 s after a SENT of
  ours that never succeeded, and step 2's check passed on it: it wasn't our resist.
- **Probably our own spells:** three `MISS`es (school 1) arrived **in the same frame as our
  SUCCEEDED**: one Shadow Word: Pain and both Holy Fires. No wand shot or swing of ours fits
  them, and the Shadow Word: Pain was cast again 8 s later, well inside its duration. So a spell
  that fails its hit roll on Forever most likely reports `MISS` with school 1, not `RESIST` with
  its own school. The probe doesn't log plain `WOUND`s, so whether those casts ticked afterwards
  is unrecorded.
- **The mouseover, in combat:** with the cursor on the target, `UnitIsUnit("mouseover",
  "target")` read **plain true** (four casts), and the name, GUID and `UnitCanAttack` were plain.
  With no mouseover, `UnitExists` was plainly false. `enableMouseoverCast` read 0, and
  `IsMouseoverCastSupported()` true.
- **The mouseover procedure** (run #255, the same priest on Gray Bears): out of combat and in
  combat with the cursor on the target, `isTarget` plain true; in combat with the cursor on
  another mob (a Forest Moss Creeper) while casting at the target, `UnitIsUnit` read **plain
  false**, with its own name, GUID and `UnitCanAttack` plain; the cursor over nothing,
  `UnitExists` plainly false. Not seen: a **same-name** mob under the cursor, and the
  `[@mouseover,harm]` macro (skipped). With the CVar at 0, a plain key press goes to the target
  whatever the cursor is on.

**What this decides:**

- **12.2's school filter is dropped.** Its gate was "our own resist carries its own positive
  school". Every avoid carried 1, our own spell misses most likely included, so a filter would
  drop exactly the misses it must keep, and show a false skull. Today's rule stands: any `MISS`
  or `RESIST` on the mob inside the window fails the pending cast, whoever's it was. That errs
  low: with a group's melee on the mob, some real applications are dropped, so the icon shows
  later or not at all. It's a missing icon, never a false one, so it isn't one of section 1's
  named limits.
- **12.2's late projectile and resist flags:** nothing seen (no hunter, no partial resist). They
  stay gaps.
- **12.3's guard passes its gate:** the reading it relies on is plain in combat, true on the
  target and false on another mob, so a cast with the cursor on the target stays tracked and
  one with it on another mob can be told apart. Building it is the owner's call. The macro and
  a same-name mob weren't seen; the guard reads only what was measured (name, attackability,
  `UnitIsUnit`), and the macro's own behaviour is the porting guide's.

### 12.6 Not proposed

A stray physical hit before a bleed's first tick commits it early and shifts its rhythm (at most
±0.25 s). That's already a named limit (section 1, one unrelated hit).
