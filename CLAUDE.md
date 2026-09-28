# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GlassUnitFrames is a **unit frames addon for World of Warcraft: Forever 1.60.1** (Interface
`16001`), written in **Lua 5.1**. Single owner (Spotnick), same stack and conventions as the
sibling Forever addons `..\AltStable` and `..\Priestly`. When this file doesn't cover
something, check how those two handle it before you invent a new idiom. For unit-frame
technique, the reference is DinoUnitFrames (see "Reference addons" below).

**Goal, in two parts:**
1. A **proof of concept for "liquid glass" unit frames**, per `docs/mockup.png`. Real backdrop
   blur and refraction are expected to be impossible for an addon, so the glass is faked with
   layered textures: a translucent tint, a 9-sliced specular rim, masked rounded bars, gloss and
   an animated sheen. `docs/POC-PLAN.md` is the plan, already reviewed by Codex.
2. A **streamlined Shadowed Unit Frames**. The owner uses a small fraction of SUF, so keep only
   what earns its place. Don't port SUF's module zoo, tag DSL or options tree by default.
   **Party and raid frames are out of scope**: the owner uses Cell for group frames. If group
   frames ever happen, they would be a glass-styled port of Cell, not SUF's headers. The feature
   choices live in `docs/SUF-INVENTORY.md` ("Owner's picks").

**Status: proof of concept.** The look is settled (`docs/FOREVER-PROBE.md`). The addon skeleton
runs on live unit data for player, target, pet, targettarget, targettargettarget, focus and
focustarget. The roadmap is
`docs/SUF-INVENTORY.md` ("Owner's picks"), one issue each. Work goes through
GitHub issues and PRs at `github.com/Spotnick2/GlassUnitFrames` (private).

## Layout

TOC load order: `Compat.lua` → `Glass.lua` → `Engine.lua` → `Frames.lua` → `Auras.lua` →
`Blizzard.lua` → `Movers.lua` → `GlassUnitFrames.lua` → `Options.lua`.

- **`Compat.lua`**: `GlassUF.API`, the only route to client APIs that moved or may be absent:
  - `IsSecret`;
  - event registration that reports failures;
  - `ClickEdges`;
  - `HealthPercent` / `PowerPercent` via a 0..100 curve;
  - `CastDuration` (a `LuaDurationObject`);
  - `ClassColor`;
  - `Fail(key, err)`: the **one** failure recorder (`GlassUF.paintFailures`, read by
    `/glass secrets`). Engine, Frames and Auras all report through it;
  - `LoadBlizzardAddOn`, `AuraSort` (sort method and direction, both or neither), `FlowLayout`;
  - `NewHealCalculator` / `IncomingHeals`: heal prediction via `CreateUnitHealPredictionCalculator`
    and `UnitGetDetailedHealPrediction` (the first return of `GetIncomingHeals`, clamped to max
    health). Optional APIs are presence-checked with `rawget`.

  It also holds `MEASURED_ON_BUILD`.
- **`Glass.lua`**: the material (see below). Self-contained.
- **`Engine.lua`**: who gets painted and when:
  - one tracker per unit (`RegisterUnitEvent`);
  - events grouped into channels (name, health, power, portrait, indicators, cast);
    `UNIT_FACTION` feeds both name and indicators. Each painter runs under `pcall`, so one that
    throws is recorded in `GlassUF.paintFailures` and the rest of the flush still paints;
  - dirty channels flushed once per rendered frame;
  - the cast channel painted immediately with its event;
  - one shared 0.5 s ticker for event-less chained tokens (`targettarget`, `targettargettarget`,
    `focustarget`);
  - full repaints when a token changes meaning. One rule, `repaintChain`: when `base` changes
    (`PLAYER_TARGET_CHANGED`, `PLAYER_FOCUS_CHANGED`, or `UNIT_TARGET` registered per base unit),
    every token starting with `base.."target"` repaints too. Plus `UNIT_PET`, `OnShow`, and
    `PLAYER_ENTERING_WORLD`. Every world event has an **explicit** branch: a catch-all `else`
    once turned any unhandled event into a full repaint and hid a wiring mistake;
  - `Engine.RepaintChannel(channel, only)` repaints one channel on every frame (optionally
    filtered). `GROUP_ROSTER_UPDATE` repaints only the name line of frames showing a group number,
    so it doesn't reload portraits. `PLAYER_FLAGS_CHANGED` (AFK) fires with group tokens, never
    target/focus, so it repaints every name line;
  - `Engine.OnTokenChanged(base)` is the hook for per-token reactions (the target sheen).
  - group-wide events (`RAID_TARGET_UPDATE`, `PARTY_LEADER_CHANGED`, `PARTY_LOOT_METHOD_CHANGED`,
    `GROUP_ROSTER_UPDATE`) repaint one channel on every frame: `Engine.RepaintChannel`.
- **`Frames.lua`**: text formats are a fixed set named after the owner's SUF tags (`Frames.TEXT`:
  `curhp`, `curmaxhp`, `curmaxhp_perhp`, `perpp`, `curpp`, `curmaxpp`; `powerLevel = true` puts level and
  classification in their own string on the power line),
  picked per slot by `LAYOUT[unit].text`. **Not a tag language**: every format hands client values
  to `SetFormattedText` / `AbbreviateNumbers`, because health and power are secret. The name
  carries an AFK tag, and a raid group number on the player.
- **Heal prediction** (player, target, focus) is a translucent bar with the **full health-bar
  width**, anchored to the health fill's moving edge and clipped at the bar's edge (a bar squeezed
  into the remaining gap would understate heals). It snaps, and it refreshes on
  `UNIT_HEAL_PREDICTION` / health events, **never on spellcast events** (DinoUF saw damage casts
  show up as heals there). Its own `heal` channel exists only on frames that predict. The
  calculator gets `SetIncomingHealOverflowPercent(1)`: DinoUF recorded an empty bar on Forever
  without it. The bar is cleared on a failed read and for offline or dead units.
- **Default positions** in `Frames.LAYOUT` are sized for WoW's UIParent, which is **768 units
  tall at the default UI scale**. Every frame, including the target's cast lane and aura rows,
  stays above y = −280, clear of the action bars. Check new frames against that, not against the
  owner's 4K screen.
- **`Frames.lua`** (frames): `LAYOUT`, the secure buttons (`SecureUnitButtonTemplate`, `"AnyUp"` clicks,
  `RegisterUnitWatch`), and the painters. The glass hosts are mouse-less children, so a click
  anywhere, portrait included, reaches the button.
- **`Auras.lua`**: the target's buffs and debuffs, drawn by Blizzard's managed aura container
  (`CreateFrame("AuraContainer", …, "CustomAuraContainerTemplate")`, from load-on-demand
  `Blizzard_AuraContainer`). The client picks, sorts and draws the auras, so secret aura data
  never reaches Lua.
  - **Order matters:** `AddAuraGroup` first, then `SetUnit`, then `UpdateAllAuras`. Binding the
    unit first leaves `UNIT_AURA` unregistered.
  - `UpdateAllAuras()` on every target change.
  - **Never anchor anything to an aura container.** The client refuses it ("Anchoring disallowed
    as dependent object would inherit forbidden aspects: UntrustedLayoutScriptExecution"),
    measured on 70009. The rows are fixed, each anchored to our own body frame: **buffs right under
    the target, debuffs below**, then the target's cast bar. Targettarget and targettargettarget
    sit side by side *above* the target, with focus above them (owner's layout, #32).
  - Optional features (auras, indicators, heal prediction) build under `attempt()`, so a refusal
    can't abort a frame's build before `RegisterUnitWatch` / `Engine.Register`, or the frames
    built after it.
  - We only style the client's buttons (`SetIcon`, `SetDurationCooldown`, `SetDurationText`,
    `SetApplicationCount`). **No scripts on them, no aura reads, no filtering** (impossible
    under secrecy).
  - The container API isn't in the dump; `test_methods.lua` allowlists exactly those methods,
    with DinoUF as the evidence.
- **Class resources** (#29): combo pips on the target frame for rogues and cat-form druids, each
  pip's alpha from a client colour curve (`API.ComboAlpha`, DinoUF's
  `UnitPowerPercent("player", 4, true, curve)`); a thin druid mana strip under the player frame
  outside caster form. Built only for those classes; the player's power/form events reach them
  through Engine's `resourceWatcher` (the target's tracker would never see player events).
- **Positions** (`Frames.lua`): every frame sits CENTER-on-CENTER on its leader (`LAYOUT[unit].anchorTo`:
  pet→player, ToT/ToTT/focus→target, focustarget→focus) or on UIParent, so moving a leader carries
  its group. Saved as `{ "CENTER", "UIParent"|leaderUnit, "CENTER", x, y }`; saved entries are
  **validated** (a malformed one falls back to the default instead of aborting the build), and
  old-style saves are still honoured. Positions change only through `Frames.SetPosition` /
  `ResetPosition` / `ResetPositions`, **out of combat**.
- **`Movers.lua`**: unlock mode (`/glass unlock|lock`, the options panel's Unlock button). One
  plain, insecure mover per frame on UIParent, **anchored to the button, never the reverse** (a
  frame a protected frame anchors to becomes protected). Dragging moves the mover; the button
  follows through `Frames.SetPosition`. **Nothing starts the client's own drag on a protected
  button** (a drag combat interrupts can't be stopped; there is no shift-drag any more). Clicking
  a mover opens the nudge panel (X/Y offsets, arrows 1 / Shift 10, reset this frame, lock).
  Unlock and nudges are refused in combat; a combat start locks.
- **`Blizzard.lua`**: hides the Blizzard frames that GlassUF **replaces** (`FRAMES` map).
  - Only frames we draw a replacement for (player, pet, target, ToT, focus, focus target):
    `ComboFrame` is hidden only once our combo pips exist (rogues and druids). Party is never touched, since the owner uses
    Cell.
  - The steps: `UnregisterUnitWatch`, unregister events, hide, reparent to a hidden frame.
  - A `SetParent` post-hook undoes Edit Mode's reparenting **on a timer, never
    synchronously**: doing it inside the caller taints secret reads for the session
    (EllesmereUI's finding). It waits while Edit Mode is open, and a protected frame waits for
    combat to end through `GlassUF.WhenOutOfCombat`.
  - **Shaman totems** (#18): `Blizzard.HostTotems` reparents Blizzard's own `TotemFrame` into a
    holder under our player frame (GlassUF can't draw totems: `GetTotemInfo` is secret), with the
    decorative glass as `TotemFrame`'s child so Blizzard's shown state carries it. `Update`,
    `SetParent` and `SetPoint` hooks schedule one **deferred** repair (Edit Mode wait; the combat
    queue if protected, unmeasured with totems down).
  - `Blizzard.active` records whether anything was hidden this session. Hiding is one-way per
    session.
- **`GlassUnitFrames.lua`**:
  - `GlassUnitFramesDB` (`font`, `pos`, `hideBlizzard`, `hideBlizzardCast`, `mark`, `aggroRed`, `level`, `healthText[unit]`, and the
    material knobs `fill|rim|track|fade`, saved only once set);
  - the frames are built at `ADDON_LOADED`, before any lockdown;
  - **the addon's one combat queue**, `GlassUF.WhenOutOfCombat(key, fn, message)`: ordered, the
    build first, `message = false` for silent. Don't add a second one;
  - `/glass options|font|mark|level|text <unit> <format>|reset|blizzard show|hide|secrets|totem|frame <Name>`, plus the live
    material tweaks `fill|rim|track|fade` (one `TWEAKS` table; saved only once set, so a new
    default still reaches everyone). `totem` / `frame` report where a Blizzard frame lives.
- **`Options.lua`**: the options panel under Game Menu > Options > AddOns > Glass Unit Frames
  (`/glass options`). A canvas panel (`Settings.RegisterCanvasLayoutCategory` +
  `RegisterAddOnCategory`, registered at `PLAYER_LOGIN`, as Priestly does), two columns so it fits
  the canvas. Check and radio buttons use `UICheckButtonTemplate` / `UIRadioButtonTemplate` (the
  porting guide lists the option templates as present), with our own art only as a fallback. The
  slider is hand-built on purpose (compact label + value line). No `UIDropDownMenu`: choices are
  radio groups. Built on first show, **re-synced from the current state on every show** (a
  `refreshing` guard keeps that from saving). Every control goes through **`GlassUF.Settings`**,
  the apply-and-save helpers `/glass` also uses (`SetFont`, `SetMark`, `SetTunable`, `ResetLook`,
  `ResetPositions`, `SetHideBlizzard`, `SetAggroRed`, `SetHealthFormat`, `SetLevelPosition`).
- **`tests/`**: see Testing. `Tools/GlassProbe/` is the throwaway material probe.

Forever is **Vanilla content running on Blizzard's Retail (Mainline) codebase**: assume Vanilla
content and the Retail API. `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`. Advice that cites a TBC or
Classic API is usually stale.

## References: read these before touching an unfamiliar API

- `C:\Projects\References\PORTING-TBC-TO-FOREVER.md` holds the canonical addon-agnostic field
  notes, measured on the live client. Treat them as fact; don't re-derive them. Other sessions
  edit this file, so write new addon-agnostic findings there, not into a copy in this repo.
- `C:\Projects\References\forever-api-1.60.1.70009.md` is the full API dump for the current
  build: documented functions and events, enums, **widget methods** (the only list of those), and
  the `_G` walk. It proves a name exists, not that it works. **Presence is not a contract.**
- For a live check in game: `/api search <name>`, `/api system list`, `/api <system> list`
  (system names omit `C_`).
- Use the Retail branch of `Gethe/wow-ui-source` for Blizzard FrameXML. Stock `Blizzard_*` code
  lives inside CASC, not on disk.

## The glass material

`docs/GLASS-MATERIAL.md` is the reusable write-up of the glass effect: textures, generator
parameters, the layer stack, how to lift `Glass.lua` into another addon, gotchas, and the
iteration history. The owner reuses it across addons. **Any change to `Glass.lua`,
`Tools/make_textures.py` or the material parameters updates that document in the same commit.**
Keep `Glass.lua` self-contained: no dependency on the engine, the frames, or units.

## Reference addons

These live in `C:\Projects\References`. They show what works on this client *in practice*,
which the dump can't tell you. Reason about what they do rather than copying it. **None is
licensed for reuse:** SUF and DinoUF ship no license, and EllesmereUI is "all rights reserved".
Write our own code.

- **`ShadowedUnitFrames` is the design reference.** It's upstream SUF, cloned from
  `github.com/Nevcairiel/ShadowedUnitFrames` (`master` targets Retail 11.x; there's also a
  `classic` branch). It's the source of truth for *what* a unit frame addon does and how SUF
  structures it. It doesn't run on Forever: `units.lua` uses `SecureHandlerBaseTemplate`,
  `WrapScript` and `RegisterStateDriver`, which are all broken here.
- **`DinoUnitFrames_Forever_Beta_v3.0` is the Forever reference.** It's SUF's classic branch
  (`ShadowUF` namespace) ported to this client. Read it for *how* to make each SUF piece work on
  Forever; diff it against upstream to isolate the port. There's one module per element in
  `DinoUnitFrames\modules\`: `units.lua` handles frame lifecycle and headers, plus
  `health.lua`, `power.lua`, `cast.lua`, `auras.lua`, `incheal.lua`, `tags.lua` and others.
  Options are a separate load-on-demand addon, `DinoUF_Options`, built on AceConfig. The
  Forever-specific code is gated on `ShadowUF_Forever` and commented `Forever:`, so grep for
  those. `CHANGELOG.md` records its port history, including which approaches broke and which
  worked. Don't inherit these parts:
  - It injects shims into `_G` (`ForeverCompat.lua`); we use a namespace adapter instead.
  - It ships a `_Camelot.toc`, which only the packager uses.
  - `ForeverPersistence.lua` mirrors the profile into CVars. It's dead code (not in the TOC)
    and obsolete now that SavedVariables work.
  - The `1.42` "render correction" scales frames to match imported TBC profiles, not a
    property of the client.
- **`EllesmereUI-v9.3` is for inspiration** on architecture and visual style. It's a
  Retail-first suite with Forever support (`## Interface: …, 16001`, `EllesmereUI.IS_FOREVER`
  from `EllesmereUI_ClientGate.lua`). The useful part is `EllesmereUIUnitFrames\`, especially
  `EUI_UnitFrames_Engine.lua`, a clean update engine:
  - one tracker frame per unit token, using `RegisterUnitEvent` so the client filters events;
  - events grouped into *channels* (health, power, text, …), each with a registered painter;
  - repeated triggers in the same frame collapse into one paint;
  - one shared 0.5 s ticker for event-less units (`targettarget`), idle while hidden.

  `EllesmereUIRaidFrames\` covers party and raid frames. `EllesmereUI_ForeverLayout.lua` shows
  default positions coexisting with Edit Mode.

Keep a `MEASURED_ON_BUILD` constant in the source, matching the dump's build (`1.60.1.70009`),
and warn at login when `GetBuildInfo()` differs, as the siblings do. Bump it only after
re-measuring in game. Matching dumps don't prove runtime behaviour.

## Toolchain and commands

There is no build system, compiler or package manager; the client interprets the Lua directly.
The Lua 5.1 toolchain is at `C:\Program Files (x86)\Lua\5.1\` (`lua.exe`, `luac.exe`). Use it,
not a newer Lua that may be first on `PATH`.

```powershell
& 'C:\Program Files (x86)\Lua\5.1\luac.exe' -p File.lua             # syntax check; silent on success
pwsh tests\run.ps1                                                   # luac -p on TOC files + every tests\test_*.lua
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_frames.lua    # one test, run from the repo root
python Tools\make_textures.py                                        # regenerate Media\*.tga (Pillow + numpy)
pwsh Tools\deploy.ps1                                                # copy the addon + Media into AddOns (-Probe adds GlassProbe)
```

`Tools\GlassProbe\` is the throwaway material probe (`/gprobe help` in game). Textures are generated, never hand-edited: change
`Tools\make_textures.py` and rerun it. On 70009 a **new texture file loads after `/reload`**
(measured, `docs\FOREVER-PROBE.md`); only a brand-new addon folder needs a full client restart.

- **Default AddOns path:** `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`.
  The deploy script takes `-AddOnsPath`.
- **Deploy** rewrites `## Version: @project-version@` to `dev` in the deployed copy only. Never
  commit a literal version over that token; the packager needs it.
- **In game:** `/console scriptErrors 1` first, because errors are off by default. Then `/reload`.
  Check the AddOns list shows the addon enabled **and not flagged out of date**. The client
  doesn't block a wrong interface number, so "it loaded" proves nothing. Error delivery stops
  after 100 errors in a session. BugGrabber + BugSack capture locals, which helps with
  secret-value bugs.

## Addon basics

- One plain `GlassUnitFrames.toc`, with no `_Forever` or `_Camelot` suffix, because the client
  ignores `_Forever`. Use `## Interface: 16001` (`%d%02d%02d` of 1.60.1). **`11601` is a
  transposed-digit bug** seen in the wild.
- One global namespace table. Every file starts `GlassUnitFrames = GlassUnitFrames or {}`, and
  the TOC order is the load order.
- Put a compat or adapter layer first (like the siblings' `Compat.lua` → `<Addon>.API`) for any
  API that moved from Classic. Consumers reach it through the namespace, not by injecting
  globals into `_G`. Read the porting guide's "False friends" section before aliasing anything:
  some moved APIs keep their name but return a struct instead of a tuple, and positional
  destructuring then fails silently.
- If a shared library is ever used (LibGroupBuffs is the precedent), don't copy its functions
  into locals (`local F = API.F`). A newer embedded copy upgrades the table in place, and a copy
  keeps the old version. Call through the table, or wrap it.
- Keep a `_test` seam table at the bottom of a file to expose file-local internals to tests.
  Don't promote internals to globals.

## Forever facts that matter for unit frames

These are measured or declared on this client. They are what makes a Classic unit frame addon
not port cleanly.

- **Secret values.** Some unit numbers come back as values you can hold but not read.
  Arithmetic, comparison, `tostring`, concatenation and **truth-testing** all throw, and a
  `x or 0` guard doesn't help. `UnitHealthMax` was measured secret for the player's own
  character. Retail's answer is to hand the secret straight back to the client, and both
  reference addons do this:
  - **Bars:** `StatusBar:SetMinMaxValues` / `SetValue` accept secrets directly.
  - **Percent and colour:** `UnitHealthPercent(unit, usePredicted, curve)` /
    `UnitPowerPercent` with `C_CurveUtil.CreateCurve` / `CreateColorCurve`. Use this instead of
    dividing health by max health.
  - **Text:** `FontString:SetFormattedText` and `AbbreviateNumbers`. EllesmereUI also passes
    percents through `string.format` and relies on a `CurveConstants.ScaleTo100` global. The
    dump lists neither as secret-safe, so measure before relying on them.
  - **Cast bars:** `UnitCastingDuration` / `UnitChannelDuration` return a `LuaDurationObject`.
    Pass it to `StatusBar:SetTimerDuration`, and read time left with `GetRemainingDuration`
    into `SetFormattedText`. Never read start/end times in Lua. See DinoUF `modules\cast.lua`.
  - **Heal prediction:** `CreateUnitHealPredictionCalculator` +
    `UnitGetDetailedHealPrediction(unit, healer, calc)`, feeding the calculator's values
    straight into a StatusBar. See DinoUF `modules\incheal.lua`.

  Test with `issecretvalue(v)` and query policy under `C_Secrets` (`ShouldUnitHealthMaxBeSecret`,
  `ShouldUnitPowerBeSecret`, `ShouldUnitSpellCastingBeSecret`, …). Which unit APIs are secret,
  for which units and when, is **per-API and largely unmeasured**. Probe it; don't assume.
  Store `nil` for unknown, never `0`.
- **Auras are unreadable in combat for every unit**, not just the player.
  `C_UnitAuras.GetAuraDataByIndex` throws; `GetAuraDataBySpellName` quietly returns nil, which
  looks like "not buffed". The `UNIT_AURA` payload is secret too (`isFullUpdate`,
  `updatedAuraInstanceIDs`). Every touch of client data goes **inside one `pcall`**, and
  checking the result a line later is too late. **For unit frame aura icons, don't read auras
  in Lua at all.** Both references use Blizzard's managed container:
  `CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")`. The client picks,
  sorts and renders the auras. The addon supplies the button look (`SetIcon`,
  `SetDurationCooldown`) and options processed through `C_AuraContainerUtil.*`. See DinoUF
  `modules\auras.lua` (`ForeverEnsureAuraContainer`) and EllesmereUI
  `EUI_UnitFrames_AuraContainers.lua`. A GUID-keyed cache with an "unknown" state is only
  needed for logic that must *know* about an aura.
- **Secure snippets are broken.** `loadstring_untainted` is missing, so
  `SecureHandlerWrapScript`, `_onstate-*` attributes and `RegisterStateDriver` throw. **Don't
  introduce a `SecureHandler*`.** Plain `SecureActionButtonTemplate` + `SetAttribute` + insecure
  `PreClick`/`PostClick` **works**, in and out of combat.
- **Single-unit frames:** `SecureUnitButtonTemplate` + `RegisterUnitWatch(frame)` for
  show/hide. Both references ship this on Forever, and DinoUF's changelog calls its UnitWatch
  path the stable baseline. We haven't measured it ourselves.
- **Party and raid headers: the evidence conflicts. Measure before choosing.** DinoUF found
  that `SecureGroupHeaderTemplate` can't run its restricted `initialConfigFunction` on Forever.
  It builds party and raid children by hand instead: `SecureUnitButtonTemplate` buttons bound
  to fixed `party1-4` / `raid1-40` tokens, with roster-driven visibility and explicit anchoring
  (`modules\units.lua`, changelog v2.10–v2.34). EllesmereUI's raid frames do use
  `SecureGroupHeaderTemplate` with `initialConfigFunction` and claim 16001 support. Probe
  whether a header spawns children on the current build. The manual approach needs every
  layout change deferred out of combat.
- **Combat lockdown:** `SetAttribute` does nothing under `InCombatLockdown()`. A frame that
  parents secure buttons is protected: hiding, moving, re-anchoring or unclamping it in combat
  is silently refused, with `ADDON_ACTION_BLOCKED` blamed on someone else's taint. Parking it
  off screen at alpha 0 doesn't work either. Record the request and apply it on
  `PLAYER_REGEN_ENABLED`. A mid-combat roster change can point a `party2`/`raid3` token at a
  different player; nothing fixes that until combat ends.
- **Click edges depend on the template.** For `SecureActionButtonTemplate` (spell buttons),
  register **both** mouse edges: its handler acts on exactly one, according to
  `ActionButtonUseKeyDown` (measured in Priestly). For **`SecureUnitButtonTemplate`** (our unit
  frames), register **`"AnyUp"`** only, as SUF and DinoUF do. That handler dispatches on every
  registered edge, so both edges could open the menu on press and toggle it shut on release.
  **Never set `typerelease`** on either.
- **`UnitName(unit)` returns only the first name**, with the surname where the realm should be.
  Characters have surnames and first names aren't unique. Display with `GetUnitName(unit, false)`
  and key caches on `UnitGUID`.
- **`RegisterEvent` throws on unknown names and returns `false` for refusals.** Wrap it, treat
  both as failures, and report them. Registering `COMBAT_LOG_EVENT_UNFILTERED` is forbidden, so
  use `UNIT_DIED` for deaths.
- No talent spec API. `MAX_PLAYER_LEVEL` is nil, so use `GetMaxPlayerLevel()` (60). The live
  beta cap is lower, so never hardcode it. `MouseIsOver` is absent (use `frame:IsMouseOver()`).
  `ReloadUI()` is protected. `SetRaidTarget` is protected.
- `GetInstanceInfo()` returns the continent outdoors, so gate on `instanceType ~= "none"`.
- Options use the Retail `Settings.RegisterAddOnCategory`, not `InterfaceOptions_AddCategory`.
  Tooltips use `TooltipDataProcessor`: hooking `OnTooltipSetItem` at load can abort
  registration. **Edit Mode is live**, so Blizzard's player and target frames can be moved or
  reset out from under anything anchored to them, and Edit Mode reparents the frames we hide
  (see `Blizzard.lua`).
- **SavedVariables persist as of 70009** (broken through 69977). Code may read them but must cope
  when they're absent. CVar persistence has not been re-measured. **Verify persistence only
  with a full client exit**, never `/reload` or by reading the SV file. Count loads inside the
  addon, or check a key that defaults to nil.

## Testing

The `tests\` harness is modelled on Priestly's: plain Lua 5.1 scripts with no dependencies, a
`tests\wow_stubs.lua` API mock driven through an exported `WoW` table, `tests\harness.lua`
(`check` / `eq` / `loadAddon` / `standardUnits`), and `tests\run.ps1` to run them all. The stub
does four more things:
- It validates event names against the API dump when the dump is present.
- It records any touch of a protected frame in combat in `WoW.blocked`.
- It models `FontString:SetFormattedText` taking secrets without formatting them in Lua.
- It records every widget method called. `test_methods.lua` checks each one exists in the dump,
  closing the gap where a catch-all stub silently swallows a method Forever lacks.

`GlassUF.paintFailures` collects the errors that `attempt()` swallows in painters, so
`test_secrets.lua` asserts it stays empty. Before trusting a new test, **mutation-test it**:
break the behaviour and confirm it goes red.

- **The stub is an allowlist and must model the client's absences.** It should fail on any read
  of an unstubbed global. Before stubbing one, confirm it exists in the current API dump and
  copy its exact signature. Defining something Forever lacks (like `MouseIsOver`) lets a broken
  call pass.
- **Stub secrets as `newproxy(true)` userdata with metamethods that error.** Don't use a table,
  which `type(v) == "table"` filters would skip. Don't use a coroutine either: it only throws on
  arithmetic and ordering. The proxy also throws on `tostring`, concatenation and
  `string.format` (verified in Lua 5.1). **No Lua 5.1 value can make a truth test or `==`
  throw**, so the stub can't catch `if secret then` or `secret == x`. Those are caught only by
  in-game combat testing and review.
- **Strict globals don't cover methods.** A catch-all `__index` swallows calls to widget methods
  this client lacks. For handlers built on widget methods, **run the handler and assert what it
  produced**, and check the method against the dump's widget-method section.
- Keep one test file that executes every script handler and event the addon installs, because
  strict globals only catch code that actually runs.
- Offline tests can't cover secure clicks, combat lockdown, real secret behaviour or rendering.
  Those need an in-game checklist and a throwaway probe addon under `Tools\`, like the siblings'
  `PriestlyProbe`.

## Workflow and releasing (sibling conventions)

- Issue → branch off `main` → PR with `Closes #N` → review (owner-launched) → squash-merge (by
  the owner). Never commit to `main`.
  Commit or push only when asked. Before committing, `luac -p` must be clean and the tests green.
- Review policy: use the shared `$wow-addon-review` skill for PR reviews.
- **The owner merges and closes PRs, and launches reviews.** Claude opens the issue, branch and
  PR, runs the tests, and stops there: never `gh pr merge` or close a PR, and never start a Codex
  or Fable review on its own. When the owner posts or points to a review, reconcile it
  (below) and push the fixes to the PR.
- **Adversarial review is mandatory** for plans and significant diffs, **launched by the owner**.
  When asked, run it through the project's `/codex-consult` skill
  (`.claude/skills/codex-consult/`), because Codex is a different model family and so has
  different blind spots. Always hand it `CLAUDE.md` and the porting guide. If Codex is
  unavailable, fall back to Fable. Then reconcile:
  - Verify its claims before acting. It has been right, and it has been confidently wrong.
  - Take its bug-catching seriously.
  - Push back when it adds complexity to a single-owner addon.
- **Fable** is worth using for long-context reading across many files, such as the SUF-vs-DinoUF
  feature inventory. Review use is default-on. Implementation use needs the owner's explicit
  approval each turn.
- Releases are built by **CurseForge's own packager from the tag webhook**, reading `.pkgmeta`.
  Don't add a GitHub release workflow. CI (`package-check.yml`) only dry-runs
  `BigWigsMods/packager` with `-d`. The packager derives the `forever` flavor from
  `## Interface: 16001`.
- **Every tag needs a `CHANGELOG.md` entry committed first**, written for players. The tag name
  sets the channel: `alpha` / `beta` / anything else → Release. That's a distribution channel,
  not a stability claim.
- `.pkgmeta` ignores `.github`, `docs`, `tests`, `Tools`, `AGENTS.md`, `CLAUDE.md`, `README.md`,
  `CHANGELOG.md` and `LICENSE`.

## Conventions

- **Right-size for a single maintainer.** Do the simplest thing that works, with no speculative
  abstraction or config.
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it. The
  porting guide has already had to reverse reasoned conclusions (click-casting, "park it off
  screen", persistence).
- Match the surrounding code's idiom. Keep pure refactors in their own commit.
