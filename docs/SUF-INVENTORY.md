# Shadowed Unit Frames feature inventory (for WoW: Forever 1.60.1 / 16001)

Produced 2026-09-27 by a Fable long-context read of upstream SUF (`master`) and DinoUnitFrames Forever
beta v3.0, against the 70009 API dump and `docs/FOREVER-PROBE.md`. Spot-checked by Claude:
- `focus` exists;
- the DinoUF fader compares secret health;
- the boss path still calls `WrapScript`;
- the aura container is given empty filters;
- `GetPetHappiness` is absent.

**Purpose:** decide which ~10% of SUF GlassUnitFrames keeps. The tables are the evidence; the
checklist below is where the owner decides.

---

## What the owner's SUF actually uses

Read from the owner's Anniversary SavedVariables (`ShadowedUnitFrames.lua`) on 2026-09-27.
Profiles **Paladin** (most characters) and **Default** are the same apart from player cast-bar
auto-hide. SUF (AceDB) saves only what differs from its defaults, so each profile was read as
SUF's defaults (classic branch, `DinoUnitFrames.lua:382-482`) plus these overrides:

| Area | In use | Evidence |
|---|---|---|
| Units | **player, pet, target, targettarget, targettargettarget, focus, focustarget** | on by default; only `party.enabled = false` overridden (Cell does groups). raid off by default. arena/battleground/boss on but N/A on Forever |
| Portraits | **3D** on player and target | `portrait.enabled = true`, `type = 3D` |
| Health colour | **class for players, reaction for NPCs** | `colorType = class`, `reactionType = npc` (pet: none) |
| Power colour | by power type | `powerBar.colorType = type` |
| Cast bars | **player and target**, name + time, **no spell icon** | player `castBar.enabled = true`; `icon = HIDE` everywhere |
| Auras | **target buffs + debuffs only**, player auras off | target `auras.buffs/debuffs.enabled = true`; player not enabled |
| Player text | name with AFK tag and group number; power as **percent** | `[(()afk() )][name][( ()group())]`, `[perpp]` |
| Target text | name with AFK; health **"cur/max pct"**; power line **"level classification pwr%"** | `[( )curmaxhp][( )perhp]`, `[level( )][classification( )][perpp]` |
| ToT / focus text | name, **current health**, power % and value | `[curhp]`, `[perpp]`, `[curpp]` |
| ToTT | name only | its other texts blanked |
| Pet text | name, power % | `[name]`, `[perpp]` |
| Indicators | SUF defaults: raid target, leader, master looter, PvP, role, resurrect; ready check **off** on player; combat/rest status **off** (default) | only `indicators.ready.enabled = false` overridden |
| Hidden Blizzard frames | SUF defaults (player, pet, target, focus, boss, arena, player power) with **party NOT hidden** | `hidden.party = false` |
| Class bars | druid / rune / totem bars on per default layout | not deliberately changed |
| Not used | fader, range fading, XP bar, aura indicators, highlights, player auras | never enabled |
| Look | Minimalist bar texture, Myriad Condensed Web 11, shadow, dark 0.8 backdrop | `bars`, `font`, `backdrop` |

## Owner's picks

Agreed 2026-09-27 ("I agree with your list"), refined by the profile evidence above. Build it
incrementally: one small PR per item, in this order. *have* = already in GlassUnitFrames.

**Already done:** player / target / pet / targettarget frames; class/reaction/tapped/offline
health colours and power-type colours; 3D portraits; cast bars with name, time and interrupt
flash; drag positioning.

**Next, in order**
1. [x] Hide Blizzard player / pet / target / focus frames (SUF's default set; party stays for
       Cell). Measure Edit Mode behaviour. (S)
2. [x] Focus + focustarget frames. (S)
3. [x] targettargettarget frame, name only. (S)
4. [x] Text formats from the profile: AFK tag and group number on names; target health
       "cur/max | pct"; a "level classification pwr%" line; power as percent; ToT/focus current
       health. (S–M)
5. [ ] Indicators: raid target and leader (+ PvP, master looter as defaults had them). (S)
6. [ ] Target buffs and debuffs via the managed AuraContainer (no filtering possible). (M)
7. [ ] Incoming heal bar via the heal calculator (Paladin). (M)
8. [ ] Smooth bar animation via StatusBar interpolation. (S)

**Dropped on evidence:** cast bar spell icon (`icon = HIDE` everywhere), combat/rest status icon
(off), player auras, fader, range fading, XP bar, ready check on player.

**Open:** combo points and druid mana bar. They depend on which classes you play on Forever.

**Out of scope by choice: party and raid frames** (decided 2026-09-27). The owner uses
**Cell** for group frames. If group frames ever happen, the plan is a glass-styled port of Cell
(no Forever port exists yet), not SUF's headers. That also drops everything that only serves
group frames: party/raid headers, partypet/partytarget, maintank/mainassist, party range fading,
target/focus highlights on party frames, sorting and group filters, and Clique registration.

**Not feasible under secrecy** (listed so nobody tries): aura filtering and white/black lists,
aura indicators, dispel-coloured health or borders, combat fader on health/power, cast pushback
display, totem timers, hiding the power bar when max power is 0, and the health gradient without a
colour curve.

---

Legend.
- **Forever**: works / patched / broken / N/A / unknown.
- **Secret**: none / client path (what it uses) / impossible.
- **Effort**: S / M / L.
- **Glass**: already in GlassUnitFrames? yes / partial / no.
- "SUF" means an upstream file; "DUF" means a DinoUnitFrames file. Line numbers are as read on
  2026-09-27.

## 1. Feature tables

### 1.1 Unit types

| Feature | Where | Forever status | Secret | Effort | Glass |
|---|---|---|---|---|---|
| player, target, pet frames (`SecureUnitButtonTemplate` + `RegisterUnitWatch`) | SUF `modules/units.lua:957-970`; DUF `units.lua:1002-1014` | **patched**: DUF drops `hasStateWatch` (pet) and all state drivers; plain `RegisterUnitWatch` | none | S | yes |
| targettarget / targettargettarget / pettarget (0.5 s poll "fake units") | SUF `units.lua:428-432, 588-611`; DUF `units.lua:359-376` | **patched**: the ticker must not Show/Hide protected frames (ADDON_ACTION_BLOCKED) | none | S | partial (ToT only) |
| focus / focustarget | SUF `units.lua:540-543, 603-605`; DUF `DinoUnitFrames.lua:466-472` | **works** unchanged: `FocusUnit`, `PLAYER_FOCUS_CHANGED` and `FocusFrame` are all in the dump; the unit menu shows "Set Focus". Not measured live | none | S | no |
| party (header) | SUF `units.lua:1064-1155` (`SecureGroupHeaderTemplate` + `initialConfigFunction` + state drivers) | **patched**: DUF builds 4–5 manual `SecureUnitButtonTemplate` children under a 1x1 plain parent, with a roster watcher on `GROUP_ROSTER_UPDATE` (`units.lua:1343-1524`, `683-771`) | none | L | no |
| party: show player in party, hide in raid | SUF `units.lua:783-796, 1121-1139`; DUF `units.lua:774-793` | **patched**: Lua `IsInRaid()` / `GetNumGroupMembers()` + Show/Hide out of combat | none | S (on top of party) | no |
| partypet / partytarget / partytargettarget | SUF `units.lua:1279-1321`; DUF `units.lua:1700-1742` | **unknown**: DUF unchanged; depends on `SecureButton_GetModifiedUnit` under a manual parent; not exercised | none | M | no |
| raid (header, combined) | SUF `units.lua:1064-1155` | **patched**: 40 manual `raid1..40` buttons, roster-driven visibility, explicit anchoring (DUF `units.lua:1113-1308`; CHANGELOG v2.10–v2.18) | none | L | no |
| raid: separate frames per group | SUF `units.lua:1000-1061, 815-865` | **patched**: geometry only (DUF `units.lua:1177-1193`); no per-group headers | none | M | no |
| raid: sort by group/class/role, group filters, units per column | SUF `units.lua:868-901` | **partial**: group filters and column geometry work; sorting by class/role is **broken** (it needs the header) | none | M | no |
| raidpet (`SecureGroupPetHeaderTemplate`) | SUF `units.lua:1086, 1106-1108` | **broken**: DUF leaves it on the secure template (`units.lua:1343`) | none | L | no |
| maintank / mainassist | SUF `units.lua:868-901` | **broken**: still `SecureGroupHeaderTemplate` in DUF; `GetPartyAssignment` exists | none | M | no |
| boss1–5 | SUF `units.lua:1158-1276`; DUF `units.lua:1572-1697` | **likely broken**: DUF still calls `stateMonitor:WrapScript` (`units.lua:1644`), and Vanilla has no boss frames | none | M | no |
| arena, battleground | SUF `units.lua:1183-1275` | **N/A** | – | – | no |
| vehicle swap | SUF `units.lua:313-367, 490-531` | **N/A** | – | – | no |
| pet-battle wrapper (`RegisterStateDriver`) | SUF `units.lua:18-30` | **N/A / broken** | – | – | no |
| zone-based unit enable | SUF `ShadowedUnitFrames.lua:260-288`; DUF `344-375` | **patched**: the master Enabled flag wins (v2.7) | none | S | no |
| per-module zone visibility | SUF `units.lua:246-311` | **works** | none | M | no |
| full update on GUID change / target change | SUF `units.lua:370-379, 534-538` | **works** | none | S | yes (Engine full repaint) |
| unit tooltip on hover, hide tooltips in combat | SUF `units.lua:671-683` | **works** (`UnitFrame_OnEnter` in dump) | none | S | no |
| right-click menu, left-click target | SUF `units.lua:733-737` | **works** (measured; `"AnyUp"` only) | none | S | yes |

### 1.2 Bars & elements

| Feature | Where | Forever status | Secret | Effort | Glass |
|---|---|---|---|---|---|
| health bar | SUF `modules/health.lua:150-170` | **works** (the StatusBar accepts secrets) | client path | S | yes |
| health colour by class | SUF `health.lua:118-120` | **works** | none | S | yes |
| health colour by reaction | SUF `health.lua:101-117` | **works** | none | S | yes |
| health colour: tapped, offline, unattackable, static | SUF `health.lua:88-100, 138-139` | **works** | none | S | partial |
| health gradient by percent | SUF `health.lua:5-27` | **degraded**: DUF returns plain green when the percent is secret (`health.lua:7-20`) | client path: `C_CurveUtil.CreateColorCurve` + `UnitHealthPercent` (DUF uses this trick for combo points, `basecombopoints.lua:184-212`); untested for the bar | M | no |
| health colour on aggro | SUF `health.lua:94-96` | **unknown**: threat may be secret | possibly impossible | S | no |
| health colour on curable debuff | SUF `health.lua:58-78`; DUF `75-104` | **broken in combat** (aura reads) | impossible | – | no |
| bar texture / background / invert | SUF `layout.lua:366-402` | **works** | none | S | partial (Glass material) |
| vertical orientation, reverse fill | SUF `layout.lua:381-382` | **works** | none | S | no |
| bar alpha, background alpha, spacing | SUF `config.lua:933-995` | **works** | none | S | no |
| smooth bar animation | – | **not a SUF feature** | – | – | no (candidate: StatusBar interpolation) |
| power bar, coloured by type / class | SUF `modules/power.lua:34-73, 95-102` | **works** | client path | S | yes |
| power: only show when mana | SUF `power.lua:44-47` | **works** | none | S | no |
| power: hide when max is 0 | SUF `power.lua:75-93` | **impossible**: max power is secret for others | impossible | – | no |
| empty spacer bar | SUF `modules/empty.lua` | **works** | none | S | no |
| 3D portrait | SUF `modules/portrait.lua:62-96` | **works** (measured) | none | S | yes |
| 2D portrait / class icon | SUF `portrait.lua:65-80` | **works** (measured; circular unless `disableMasking`) | none | S | no |
| portrait placement / width / ordering | SUF `layout.lua:534-605` | **works** | none | M | partial |
| incoming heal bar | SUF `modules/incheal.lua:137-146` | **patched**: heal calculator + `UnitGetDetailedHealPrediction`, clipped to the health texture (DUF `incheal.lua:151-298`; v2.1–v2.9, v2.32) | client path | M | no |
| incoming heal overflow cap | SUF `incheal.lua:41-83` | **partial**: DUF uses a 6 px end-cap while the player casts | impossible to size by amount | S | no |
| absorb / heal-absorb bars | SUF `incabsorb.lua`, `healabsorb.lua` | **unknown**: APIs in dump; values expected secret | client path | M | no |
| alt power bar | SUF `modules/altpower.lua` | **N/A** | – | – | no |
| XP / rested bar | SUF `modules/xp.lua:109-137` | **unknown**: uses `MAX_PLAYER_LEVEL` (nil) and XP arithmetic (secrecy unmeasured) | possibly client path | M | no |
| reputation bar | SUF `xp.lua:87-107` | **patched**: `C_Reputation.GetWatchedFactionData`; unmeasured | none expected | S | no |
| druid mana bar | SUF `modules/druid.lua` | **works** | client path | S | no |
| priest / shaman secondary mana | SUF `priest.lua`, `shaman.lua` | **N/A** | – | – | no |

### 1.3 Text / tags

| Feature | Where | Forever status | Secret | Effort | Glass |
|---|---|---|---|---|---|
| tag DSL (~110 tags compiled with `loadstring`) | SUF `modules/tags.lua:395-1064` | **patched piecemeal**: ~15 tags guarded; percent tags via `UnitHealthPercent` + `CurveConstants.ScaleTo100`; `string.format("%s", secret)` unmeasured | client path; deficit/missing tags **impossible** | L | no (fixed painters) |
| tag event auto-registration | SUF `tags.lua:33-92, 1479-1572` | **works** | none | L | no |
| frequently updated tags (afk, offline, pvp timer) | SUF `tags.lua:1148-1159` | **works** | none | S | no |
| user-defined custom tags | SUF `config.lua:5800-6200` | **works**, but every user tag is a secret trap | user-dependent | L | no |
| text rows: anchor, width weight, size, offset | SUF `layout.lua:421-490` | **works** | none | M | partial |
| name: first name vs full "First Last" | DUF `DinoUnitFrames.lua:127-160` | **patched** (Forever-only option) | none | S | yes |
| name colour by class | SUF `tags.lua:573-597` | **works** | none | S | no |
| level / classification / rare / elite | SUF `tags.lua:698-727, 833-874` | **patched** (nil guard) | none | S | no |
| health value + percent text | SUF `curhp` / `perhp` | **patched** | client path | S | yes (measured) |
| Dead / Ghost / Offline text | SUF `tags.lua:800-808` | **works** | none | S | partial |
| threat tags | SUF `tags.lua:454-516` | **unknown** | possibly impossible | S | no |
| druid form tag (aura lookup) | SUF `tags.lua:407-446` | **broken in combat** | impossible | – | no |
| group, guild, race, sex, faction, creature type | SUF `tags.lua:447-451, 719, 796-890` | **works** | none | S | no |
| font face / size / outline / shadow (LibSharedMedia) | SUF `layout.lua:405-418` | **works** | none | S | partial (2 fonts) |

### 1.4 Auras

| Feature | Where | Forever status | Secret | Effort | Glass |
|---|---|---|---|---|---|
| buff / debuff icons | SUF `modules/auras.lua:588-614` | **patched wholesale**: `CustomAuraContainerTemplate` renders; the legacy scan is disabled (DUF `auras.lua:363-662, 946-950`) | client path | M | no |
| size, per row, rows, growth, anchor | SUF `auras.lua:24-180` | **patched**: mapped to the container flow layout | none | M | no |
| timers / duration text | SUF `auras.lua:554-559` | **patched**: `SetDurationCooldown`, `SetDurationText` | client path | S | no |
| stack count | SUF `auras.lua:583` | **patched**: `SetApplicationCount` | client path | S | no |
| filtering: player-only / boss / curable / smart | SUF `auras.lua:503-534` | **broken**: DUF passes `candidateFilters = {}` (`auras.lua:558`); `C_AuraContainerUtil` options unmapped | impossible in Lua; container options unknown | M–L | no |
| white / black / override lists | SUF `auras.lua:487-501, 528-534` | **broken** | impossible | – | no |
| enlarge own / boss auras | SUF `auras.lua:562-568` | **broken** | impossible | – | no |
| border colour by dispel type | SUF `auras.lua:542-551` | **broken** in DUF; `ProcessCustomAuraButtonDispelTypeTextureOptions` exists | unknown via the container | S–M | no |
| right-click to cancel a buff | SUF `auras.lua:211-217` | **broken**: no handlers allowed on managed buttons | impossible | – | no |
| aura tooltips | SUF `auras.lua:184-209` | **unknown**: container tooltip options exist | – | S | no |
| temporary weapon enchants | SUF `auras.lua:375-481` | **dropped** | unknown | M | no |
| anchor debuffs to buffs | SUF `auras.lua:618-645` | **patched** (v2.33) | none | S | no |
| aura indicators (corner squares, missing buffs) | SUF `modules/auraindicators.lua` | **broken in combat** | impossible | L | no |

### 1.5 Indicators & icons

| Feature | Where | Forever status | Secret | Effort | Glass |
|---|---|---|---|---|---|
| raid target icon | SUF `modules/indicators.lua:101-110` | **works** | none (unmeasured) | S | no |
| leader / assistant | SUF `indicators.lua:163-184` | **works** | none | S | no |
| combat / resting | SUF `indicators.lua:220-251, 332-351` | **works** | none | S | no |
| PvP flag | SUF `indicators.lua:193-208` | **works** | none | S | no |
| master looter | SUF `indicators.lua:79-99` | **works** | none | S | no |
| ready check | SUF `indicators.lua:254-316` | **works** | none | S | no |
| main tank / main assist icon | SUF `indicators.lua:147-161` | **works** | none | S | no |
| class icon | SUF `indicators.lua:18-30` | **works** | none | S | no |
| resurrection incoming | SUF `indicators.lua:44-52` | **works** | none | S | no |
| LFD role | SUF `indicators.lua:122-145` | **N/A** | – | – | no |
| phase icon | SUF `indicators.lua:32-42` | **broken** in DUF (`UnitInPhase` absent); upstream's `UnitPhaseReason` is in the dump, untried | none | S | no |
| quest boss | SUF `indicators.lua:112-120` | **unknown**: API present | none | S | no |
| pet happiness | DUF `indicators.lua:248-263` | **N/A** (`GetPetHappiness` absent) | – | – | no |
| highlight: mouseover | SUF `modules/highlight.lua:9-25` | **works** | none | S | no |
| highlight: aggro | SUF `highlight.lua:78-81` | **unknown** (threat secrecy) | possibly impossible | S | no |
| highlight: target/focus on party | SUF `highlight.lua:83-87` | **works** | none | S | no |
| highlight: rare / elite | SUF `highlight.lua:102-105` | **works** | none | S | no |
| highlight: curable debuff | SUF `highlight.lua:89-92` | **broken in combat** | impossible | – | no |
| combat text over frame | SUF `modules/combattext.lua` | **works** (Blizzard's `CombatFeedback_OnCombatEvent`) | none expected | S | no |

### 1.6 Casting

| Feature | Where | Forever status | Secret | Effort | Glass |
|---|---|---|---|---|---|
| cast / channel progress | SUF `modules/cast.lua:215-276` | **patched**: `SetTimerDuration` | client path | S | yes (measured) |
| time remaining | SUF `cast.lua:225-234` | **patched**: `GetRemainingDuration` → `SetFormattedText` | client path | S | yes |
| spell name and icon | SUF `cast.lua:124-166, 421-437` | **works** | none | S | partial (no icon) |
| interrupt flash | SUF `cast.lua:347-367` | **patched** (addon-owned state) | none | S | yes (measured) |
| colours: cast / channel / uninterruptible / finished / interrupted | SUF `cast.lua:466-472, 370-389` | **patched**: colour applied after the timer | none | S | partial |
| pushback display | SUF `cast.lua:391-410` | **impossible** (start-time arithmetic) | impossible | – | no |
| uninterruptible detection | SUF `cast.lua:97-98, 378-389` | **unknown**: events in dump | none | S | no |
| auto-hide when idle | SUF `cast.lua:171-173` | **works** | none | S | yes |
| cast bar on ToT (polls end times) | SUF `cast.lua:8-64` | **broken as written**; could poll `UnitCastingDuration` existence | client path | S | no |
| Classic reskin of Blizzard's player cast bar | DUF `ForeverClassicCastbar.lua` | **Forever-only feature** | none | M | no |

### 1.7 Range / fading / visibility

| Feature | Where | Forever status | Secret | Effort | Glass |
|---|---|---|---|---|---|
| range fading (LibSpellRange, `UnitInRange`) | SUF `modules/range.lua:62-114` | **unknown**: DUF nil-calls `UnitInPhase`; `C_Spell.IsSpellInRange` secrecy unmeasured | possibly none | M | no |
| custom range spell per class | SUF `config.lua:1380-1466` | **unknown** | – | S | no |
| combat fader | SUF `modules/fader.lua:142-162` | **broken**: compares secret health/power (`fader.lua:150-153`) | health/power conditions impossible; combat/target/casting fine | S (reduced) | no |
| hide Blizzard player/pet/target/ToT/focus | SUF `ShadowedUnitFrames.lua:689-708, 775-803` | **works in practice** (DUF ships it); Edit Mode taint unmeasured | none | S | no |
| hide Blizzard party frames | SUF `716-741` | **patched** | none | S | no |
| hide Blizzard raid frames | SUF `743-769` | **works** | none | S | no |
| hide Blizzard buff frame | SUF `771-773` | **works** | none | S | no |
| hide Blizzard player cast bar | SUF `712-714` | **silent no-op** in DUF (`CastingBarFrame` is nil; it's `PlayerCastingBarFrame` on this codebase) | none | S | no |
| zone-based visibility overrides | SUF `ShadowedUnitFrames.lua:268-287` | **works** | none | M | no |

### 1.8 Class resources

| Feature | Where | Forever status | Secret | Effort | Glass |
|---|---|---|---|---|---|
| combo points | SUF `modules/basecombopoints.lua` | **patched**: per-point alpha from `UnitPowerPercent` + a step colour curve (DUF `174-289`) | client path | M | no |
| hide combo points at 0 | SUF `basecombopoints.lua:183-185` | **impossible** | impossible | – | no |
| totem bar | SUF `modules/totems.lua` | **broken**: `GetTotemInfo` returns secrets | impossible in Lua | – | no |
| runes, shards, holy power, chi, essence, stagger… | SUF various | **N/A** | – | – | no |
| spec-gated modules | SUF `units.lua:283-285` | **N/A** (no specs) | – | – | no |

### 1.9 Layout / positioning / movers

| Feature | Where | Forever status | Secret | Effort | Glass |
|---|---|---|---|---|---|
| per-unit width / height / scale | SUF `layout.lua:321-347` | **patched**: DUF's 1.42 factor is a profile artefact | none | S | partial |
| bar ordering, height weights | SUF `layout.lua:499-608` | **works** | none | M | no |
| backdrop / border (LibSharedMedia) | SUF `layout.lua:33-45` | **works** | none | S | no (Glass material) |
| anchor to another frame | SUF `layout.lua:267-318` | **works** | none | M | no |
| clamp to screen | SUF `layout.lua:335-337` | **works** | none | S | yes |
| unlock / config mode with fake data | SUF `modules/movers.lua` | **patched heavily**: no attribute writes, synthetic previews | none | L | no (shift-drag instead) |
| drag, save position | SUF `movers.lua:389-462` | **patched** | none | S | yes |
| auto-lock in combat | SUF `movers.lua:483-491` | **works** | none | S | yes |

### 1.10 Profiles & options

| Feature | Where | Forever status | Secret | Effort | Glass |
|---|---|---|---|---|---|
| AceDB profiles | SUF `ShadowedUnitFrames.lua:51-54, 627-668` | **patched**: `GetCurrentRegion` shim; SavedVariables persist since 70009 | none | M | no |
| layout import / export | SUF `config.lua:543-687` | **patched**: import needs `/reload` (DUF `config.lua:638-648`) | none | M | no |
| enable / disable units at runtime | SUF `config.lua:4761-4860` | **patched**: needs `/reload` | none | S | no |
| full AceConfig options tree (~7.6k lines) | SUF `options/config.lua` | **works** | none | L | no (`/glass`) |
| colour pickers | SUF `config.lua:993-1379` | **works** | none | M | no |
| slash commands | SUF `ShadowedUnitFrames.lua:915-943` | **works** | none | S | yes |

### 1.11 Integrations

| Feature | Forever status | Effort | Glass |
|---|---|---|---|
| Clique (`ClickCastFrames`) | **partial**: table registration kept; header wiring skipped; Clique on Forever unmeasured | S | no |
| LibSharedMedia | **works** | S | no |
| LibDualSpec | **N/A** | – | no |
| LibSpellRange | **unknown** | – | no |
| OmniCC / Blizzard cooldown count | **patched** | S | no |
| `PingableUnitFrameTemplate` | **unknown** | S | no |

## 2. Unit types on Forever

| Unit | Meaningful? | Evidence |
|---|---|---|
| player, pet, target, targettarget, targettargettarget, pettarget | **yes** | 4 measured in `docs/FOREVER-PROBE.md`; DUF ships all |
| focus, focustarget | **yes** (client feature) | `FocusUnit`, `PLAYER_FOCUS_CHANGED`, `FocusFrame` in dump; "Set Focus" in the unit menu. Not measured live |
| party + child units | **yes** | manual children (DUF); child units unverified |
| raid, raidpet | **yes** | manual 40 buttons; raidpet broken |
| maintank, mainassist | in principle | DUF header path broken |
| boss1-5 | doubtful | Vanilla predates boss frames; DUF path throws |
| arena, battleground, vehicle | **no** | N/A |

## 3. Hidden complexity on Forever

1. **Party/raid without the secure group header.** SUF gets roster, sorting, spawning, show/hide
   and Clique wiring from one template. DUF needed ~600 lines and 14 releases to hand-build
   `party1-4` / `raid1-40` with roster watchers and synthetic unlock previews (`units.lua:683-1308`,
   `movers.lua:329-604`). Sorting by class/role and mid-combat roster changes remain unsolved.
   EllesmereUI claims the header works: measure first.
2. **Auras under secrecy.** The managed container makes icons easy, but it removes all of SUF's aura
   logic: filters, lists, enlarge-own, dispel borders, right-click cancel, temporary enchants and
   indicators. DUF then spent many releases on bootstrap timing and growth geometry.
3. **Tag DSL vs arithmetic.** ~60 of the ~110 default tags do arithmetic on health/power. The DSL's
   value was flexibility, and secrecy removes most of it. User tags are a permanent secret trap.
4. **Hiding Blizzard frames with Edit Mode live.** On this codebase `CastingBarFrame` is nil
   (DUF's hide is a silent no-op), and Edit Mode can move or reset hidden frames. Taint follows.
5. **Cast bar details.** Progress and time are solved; pushback, ToT cast polling and "finished"
   colour need secret timing.
6. **Runtime reconfiguration of secure frames.** Enabling a unit or importing a layout from an
   options UI reaches restricted attribute writes; DUF asks for `/reload`. An options tree that edits
   live frames is a taint minefield.
7. **Heal prediction.** The calculator works but took DUF ten releases to get right (which
   aggregate, healer semantics, clipping, damage casts appearing as heals).
8. **Conditional fading and highlighting.** Health/power conditions are impossible; threat is
   unmeasured.
9. **Config/unlock mode.** SUF previews by setting unit attributes; DUF keeps Lua-side fake
   identities instead.
10. **Class resources.** Combo points need the colour-curve alpha trick and can't hide at 0.
    Totems are impossible.

## 4. Suggested minimal core

The suggestion is pre-filled into **Owner's picks** at the top. The owner decides.
