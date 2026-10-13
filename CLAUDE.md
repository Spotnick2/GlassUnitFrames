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
   **Party and raid frames are out of scope here**: they are a separate addon,
   **GlassRaidFrames** (`..\GlassRaidFrames`, its own sessions; #37 closed), a glass-styled,
   streamlined take on Cell. The feature choices live in `docs/SUF-INVENTORY.md` ("Owner's
   picks").

**Status (2026-09-28): a working addon, in daily use by the owner.** The glass look is settled and
tuned in game (LibGlass's `docs/GLASS-MATERIAL.md`; the material is now the embedded library
LibGlass-1.0, see "The glass material"). Frames: player, target, pet, targettarget,
targettargettarget, focus, focustarget. Every "Owner's picks" item in `docs/SUF-INVENTORY.md` is
done, plus: an options panel (Options > AddOns > Glass Unit Frames), unlock mode (movers, group
moves, nudging, grid snap, alignment guides, player/target mirroring), the red health-loss
segment, the hidden-power fade, neutral NPCs red in a fight, raid mark / target level / pet
happiness placement, per-frame health text, combo points and the druid mana strip. (Hosted shaman
totems were removed in #58: `TotemFrame` is a managed frame, see `Blizzard.lua` below.)

- **Awaiting in-game checks** (built and tested offline only): combo pips (rogue, cat druid), the
  druid mana strip (bear/cat).
- **Parked:** #35, healer/DPS layouts by spec. It waits for GlassRaidFrames; the two addons
  will need one role source and a way to talk (sketch on #35: a shared embedded role helper, and
  Retail's `EventRegistry`).

Work goes through GitHub issues and PRs at `github.com/Spotnick2/GlassUnitFrames` (private).

## Layout

TOC load order: `Libs\LibGlass-1.0\LibGlass-1.0.xml` (the embedded material) → `Compat.lua` →
`Glass.lua` → `Engine.lua` → `Frames.lua` → `Castbar.lua` → `Auras.lua` → `Blizzard.lua` →
`Movers.lua` → `GlassUnitFrames.lua` → `Options.lua`.

- **`Compat.lua`**: `GlassUF.API`, the only route to client APIs that moved or may be absent:
  - `IsSecret`;
  - event registration that reports failures;
  - `UnitButtonClicks` (`"AnyUp"`);
  - `HealthPercent` / `PowerPercent` via a 0..100 curve;
  - `CastDuration` (a `LuaDurationObject`);
  - `ClassColor`;
  - `Fail(key, err)`: the **one** failure recorder (`GlassUF.paintFailures`, read by
    `/glass secrets`). Engine, Frames and Auras all report through it;
  - `LoadBlizzardAddOn`, `AuraSort` (sort method and direction, both or neither), `FlowLayout`;
  - `NewHealCalculator` / `IncomingHeals`: heal prediction via `CreateUnitHealPredictionCalculator`
    and `UnitGetDetailedHealPrediction` (the first return of `GetIncomingHeals`, clamped to max
    health). Optional APIs are presence-checked with `rawget`.

  - `PowerAlpha` / `ComboAlpha`: an opacity the **client** computes from a step colour curve over
    a power fraction (`UnitPowerPercent(unit, type, unmodified, curve)` → `GetRGBA` alpha), handed
    straight to `SetAlpha` even when secret. Measured working (#42): the hidden-power fade and the
    combo pips use it. Nothing may depend on `Enum.LuaCurveType.Step` existing;
  - `SafeFrame(type, parent, template, proof)`: a template that may be missing returns a bare
    frame rather than throwing, so `proof` names a field the template would make.

  It also holds `MEASURED_ON_BUILD`.
- **`Glass.lua`**: one line that matters, `GlassUF.Glass = LibStub("LibGlass-1.0"):New()`: this
  addon's instance of the embedded material (see below). Every call site dot-calls it
  (`Glass.Apply`, `Glass.Bar`, `Glass.MEDIA`, ...).
- **`Engine.lua`**: who gets painted and when:
  - one tracker per unit (`RegisterUnitEvent`);
  - events grouped into channels (name, color, health, heal, power, portrait, indicators,
    happiness, combo, druidmana, cast), each registered only on frames that have it. `color`
    repaints just the health colour (a neutral NPC's fight state). `resourceWatcher` routes the
    PLAYER's power/form events to channels drawn on other frames (combo pips on the target),
    filtered by power type (`Engine.PLAYER_DRIVEN`);
    `UNIT_FACTION` feeds both name and indicators. Each painter runs under `pcall`, so one that
    throws is recorded in `GlassUF.paintFailures` and the rest of the flush still paints;
  - dirty channels flushed once per rendered frame;
  - the cast channel painted immediately with its event **and its payload** (castGUID, ...).
    The player's tracker also registers `UNIT_SPELLCAST_SENT` / `SUCCEEDED`
    (`Engine.PLAYER_CAST_EVENTS`), and the world frame hands `CURRENT_SPELL_CAST_CHANGED` to
    `Engine.OnCastChanged` (Castbar's latency stamp);
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
- **`Castbar.lua`**: the player and target cast bars (#72 moved them out of `Frames.lua`):
  the inside player row and the target's pill (`Castbar.Build`, `Castbar.CastingRows`), and the
  `cast` channel's painter. It paints through `Frames.attempt`, and Frames resolves it at build
  time.
  - **Detachable** (#74): each bar's host is a mouse-less **child of its unit button** (so it
    hides with it: no target, no target bar), with a glass pill of its own (`c.skin`).
    - **Docked:** the player's row inside the body (pill hidden; health and power shrink only
      while it's docked inside AND shown), the target's pill under its aura rows.
    - **Detached:** its own pill, CENTER on the screen centre. Defaults follow the owner's Quartz
      layout: player 340×20 at (0, −47), target at (0, −23).
    - Saved in `db.castBars[unit] = { detached, x, y, w, h }`, each field validated against
      `Castbar.LIMITS` (junk falls back to its default), pruned when empty.
    - `Castbar.Place(c)` lays a bar out for its mode and reconciles the rows. Levels are fixed at
      build: host H, pill H (rims H + 10), bar H + 2, text H + 11.
    - Detach and attach work **in combat**: a cast host is never protected (measured with
      CastProbe `hier`, #74).
    - In unlock mode a detached bar is a mover source `cast:<unit>` (`Castbar.MoverSource`: W/H,
      Attach).
  - On the **player's** bar (#72):
  - **Latency block:** a red overlay (`Frames.OverlayBar`) over the end the cast heads for:
    reverse fill for casts, normal for channels. It estimates the tail you probably can't
    cancel, so it's the **key press → cast start** interval, not a network RTT.
    - Measured: SENT and START share a frame, so send→start is always 0. The interval from
      `CURRENT_SPELL_CAST_CHANGED(false)` to SENT has a median of 139 ms, where `GetNetStats`
      says 33 ms.
    - A sample is taken at every player SENT. The stamp is consumed by every SENT. A sample is
      rejected when stale (over 1 s), and when it's 0 (same frame): a queued cast's handoff
      frame always fires `CAST_CHANGED(false)` just before its SENT (measured). Don't detect
      queuing by "an end event in the SENT frame": an unrelated SUCCEEDED (Auto Shot) would drop
      real samples.
    - Shown: the median of the last 7 samples; `GetNetStats` (`~`) before the first. The `ms`
      figure sits just above the block's end, **only on a detached bar** (the docked row is
      14 px).
    - `Frames.OverlayBar` places only its clip frame: the caller anchors the bar it returns.
  - **Pushback:** `+0.4` / `-0.4` before the time. It's **assigned** from the cumulative
    `delayTimeMs` (the 11th return of `UnitCastingInfo`), or from how far a channel's end moved.
    It resets on START, and on the STOP of the newest cast.
  - **The interrupt flash:** the client repeats INTERRUPTED after the STOP. A FAILED or
    INTERRUPTED flashes only for the newest cast's guid (`latestGUID`, or the player's last
    SENT `sentGUID`, for an instant refused after SENT), and only once (`flashedGUID`). An
    unreadable guid keeps the old behaviour, and a rejected attempt (client-side
    `Cast-2-0-0-0-…` guid, never SENT) no longer flashes. A flashed guid never flashes again,
    even when the newest guid is unknown. A target change (`Engine.OnTokenChanged` →
    `Castbar.TokenChanged`) forgets the newest guid; an ordinary full repaint doesn't.
  - **Options:** `latency`, `latencyText`, `pushback` (`Castbar.SetOption`).
  - Measuring tool: `Tools/CastProbe`.
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
  plain, insecure mover per **source** on UIParent, **anchored to its frame, never the reverse**
  (a frame a protected frame anchors to becomes protected). A source is the adapter a mover
  moves through (`label`, `frame`, `rel`, `position`, `set`, `save`, `reset`, `follows`), keyed
  by an id. A unit's id is its unit name; a detached cast bar's is `cast:<unit>`, with `size`,
  `setSize` and `attach` as well. Dragging moves the mover; the frame follows through its
  source (`Frames.SetPosition` for a unit). **Nothing starts the client's own drag on a protected
  button** (a drag combat interrupts can't be stopped; there is no shift-drag any more). Clicking
  a mover opens the nudge panel (X/Y offsets, arrows 1 / Shift 10, reset this frame, lock; W/H
  and Attach for a cast bar). While unlocked, a glass **unlock dialog** at the top centre
  (Quartz's idea) holds Lock and the switches.
  Unlock and nudges are refused in combat; a combat start locks. While dragging, a frame's
  edges/centre **align** to other frames' (and the screen centre) within 8 units with a yellow guide
  line, else its centre snaps to a 16-unit **grid** drawn over the screen; the frame's own
  followers aren't alignment targets; **Alt** places freely. Both switches are on the unlock
  dialog (saved only when off: `db.snapGrid`, `db.snapAlign`). **Mirroring** (on by default,
  `db.mirror` when off, `/glass mirror`): moving the player or target frame (drag, arrows, typed
  X/Y, reset) places the other at the mirrored spot (-x, same y), but only while the pair IS
  symmetric (a custom asymmetric layout is never overwritten). Alt at the start of a drag moves one
  alone, fixed for the whole drag; the drag's partner isn't an alignment target. Cast bars never
  mirror.
- **`Blizzard.lua`**: hides the Blizzard frames that GlassUF **replaces** (`FRAMES` map).
  - Only frames we draw a replacement for (player, pet, target, ToT, focus, focus target):
    `ComboFrame` is hidden only once our combo pips exist (rogues and druids). Party is never touched, since the owner uses
    Cell.
  - The steps: `UnregisterUnitWatch`, unregister events, hide, reparent to a hidden frame.
  - **Kept parents** (#58): every **managed frame** (`isManagedFrame`, set by
    `ManagedFrameTemplate`: PetFrame, PlayerCastingBarFrame) and the `KEEP_PARENT` names
    (TargetFrameToT, FocusFrameToT) are never reparented or `SetParent`-hooked. A managed frame is
    put back in its container on every show (`ManagedFrameSystem` `UpdateFrame`) inside Edit
    Mode's secure pass, and a hook fighting that threw "attempt to call a nil value" on Edit Mode
    exit. The ToT frames call `GetParent():ConfigureAuraContainer()`. **Never reparent a managed
    frame, or a frame whose code calls into its parent** (GlassPanel #39 is the same trap). They
    stay hidden by their hidden parent. Where Blizzard moves one out (a PetFrame moved in Edit Mode
    lives under UIParent, and Edit Mode's exit shows it), an `OnShow` hook hides it again,
    deferred and through `whenSafe`.
  - A `SetParent` post-hook undoes Edit Mode's reparenting **on a timer, never
    synchronously**: doing it inside the caller taints secret reads for the session
    (EllesmereUI's finding). It waits while Edit Mode is open, and a protected frame waits for
    combat to end through `GlassUF.WhenOutOfCombat`.
  - **Totems:** not shown while Blizzard's frames are hidden. GlassUF can't draw them
    (`GetTotemInfo` is secret), and hosting Blizzard's `TotemFrame` (#18/#54) was removed in #58:
    it's a managed frame like PetFrame. `/glass totem` still reports where it lives.
  - `Blizzard.active` records whether anything was hidden this session. Hiding is one-way per
    session.
- **`GlassUnitFrames.lua`**:
  - `GlassUnitFramesDB` (`font`, `pos`, `hideBlizzard`, `hideBlizzardCast`, `mark`, `aggroRed`, `level`, `healthText[unit]`,
    `castLatency|castLatencyText|castPushback` (saved only when off), `castBars[unit]` (#74), and the material knobs `fill|rim|track|fade|edge`, saved only once set);
  - the frames are built at `ADDON_LOADED`, before any lockdown;
  - **the addon's one combat queue**, `GlassUF.WhenOutOfCombat(key, fn, message)`: ordered, the
    build first, `message = false` for silent. Don't add a second one;
  - `/glass options|font|mark|level|text <unit> <format>|reset|blizzard show|hide|secrets|totem|frame <Name>`, plus the live
    material tweaks `fill|rim|track|fade|edge` (one `TWEAKS` table; saved only once set, so a new
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
  `ResetPositions`, `SetHideBlizzard`, `SetAggroRed`, `SetHealthFormat`, `SetLevelPosition`,
  `SetCastOption`, `SetCastDetached`).
- **`tests/`**: see Testing. `Tools/GlassProbe/` is the throwaway material probe;
  `Tools/CastProbe/` is the throwaway cast/swing event trace for #72 and the later cast-bar PRs
  (deployed with `Tools\deploy.ps1 -CastProbe`). Typed `/cprobe` didn't dispatch in game,
  although `SlashCmdList.CASTPROBE` was registered (cause unknown), so drive it with
  `/run SlashCmdList.CASTPROBE("status")` (or `hier`, `mark <text>`, `dump`).

Forever is **Vanilla content running on Blizzard's Retail (Mainline) codebase**: assume Vanilla
content and the Retail API. `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`. Advice that cites a TBC or
Classic API is usually stale.

## References: read these before touching an unfamiliar API

- `C:\Projects\WoW\References\PORTING-TBC-TO-FOREVER.md` holds the canonical addon-agnostic field
  notes, measured on the live client. Treat them as fact; don't re-derive them. Other sessions
  edit this file, so write new addon-agnostic findings there, not into a copy in this repo.
- `C:\Projects\WoW\References\forever-api-1.60.1.70338.md` is the full API dump for the current
  build: documented functions and events, enums, **widget methods** (the only list of those), and
  the `_G` walk. It proves a name exists, not that it works. **Presence is not a contract.**
- For a live check in game: `/api search <name>`, `/api system list`, `/api <system> list`
  (system names omit `C_`).
- Use the Retail branch of `Gethe/wow-ui-source` for Blizzard FrameXML. Stock `Blizzard_*` code
  lives inside CASC, not on disk.

## The glass material

The material is **LibGlass-1.0**, an embedded LibStub library (`..\LibGlass`,
github.com/Spotnick2/LibGlass, public, MIT) that every glass addon embeds. Its repo owns the code,
the textures, the generator (`Tools/make_textures.py`) and the write-up
(`docs/GLASS-MATERIAL.md`: layers, parameters, gotchas, history), and its `CLAUDE.md` holds the
contract (the API, region fields and texture names only grow; instances; upgrade rules).

- **Material changes are LibGlass PRs**, never edits here. A bug or a need found here goes on a
  LibGlass issue.
- **How it's embedded:** `.pkgmeta` externals put it in `Libs\LibGlass-1.0\` (the only supported
  path: `MEDIA` is derived from it), and the TOC loads its XML first. `Libs/` is gitignored; a dev
  copy comes from the LibGlass checkout (`$env:LIBGLASS`, default `..\LibGlass`) through its own
  `Tools\deploy.ps1`, which `Tools\deploy.ps1` here calls. The tests load the same checkout.
- **The pin:** `.pkgmeta` pins a commit or tag, **never `tag: latest`**. Bump it only in a release
  made anyway: players get library fixes earlier through whichever glass addon ships the newest
  copy (LibStub runs that one). CI reads the pin from `.pkgmeta` (`tests/fetch_libglass.sh`),
  tests against it, and asserts the zip's `Libs/LibGlass-1.0/` is exactly that commit's shipped
  files.
- **`GlassUF.Glass` is an instance**: `STYLE`, the `TUNABLES` setters and the font registry are
  this addon's own, so `/glass rim` never touches another glass addon. `Glass.MEDIA` resolves to
  the winning copy's `Media\`; use it only for library textures (`bar_fill`, `bar_edge`, ...).
- **Colours passed to a glass bar's `SetStatusBarColor` must be plain** (the library's hook
  compares them): never a secret.
- GlassUnitFrames is the library's **pilot consumer**: its CI is where the packaged library is
  checked.

## Reference addons

These live in `C:\Projects\WoW\References`. They show what works on this client *in practice*,
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

Keep a `MEASURED_ON_BUILD` constant in the source, matching the dump's build (`1.60.1.70338`),
and warn at login when `GetBuildInfo()` differs, **dev copies only** (`API.IsDevBuild`: version
`dev`, the unreplaced packager keyword, or unreadable), as AltStable does. Bump it only after
re-measuring in game. Matching dumps don't prove runtime behaviour.

## Toolchain and commands

There is no build system, compiler or package manager; the client interprets the Lua directly.
The Lua 5.1 toolchain is at `C:\Program Files (x86)\Lua\5.1\` (`lua.exe`, `luac.exe`). Use it,
not a newer Lua that may be first on `PATH`.

```powershell
& 'C:\Program Files (x86)\Lua\5.1\luac.exe' -p File.lua             # syntax check; silent on success
pwsh tests\run.ps1                                                   # luac -p on our TOC files + every tests\test_*.lua
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_frames.lua    # one test, run from the repo root
pwsh Tools\deploy.ps1                                                # the addon + its LibGlass into AddOns (-Probe adds GlassProbe)
bash tests/fetch_libglass.sh <dir>                                   # clone LibGlass at the .pkgmeta pin (what CI does)
```

The tests and the deploy need a LibGlass checkout: `..\LibGlass`, or `$env:LIBGLASS`. Without one
they fail loudly rather than skip.

`Tools\GlassProbe\` is the throwaway material probe (`/gprobe help` in game). Its earlier rim and
sheen iterations live in `Tools\GlassProbe\Media\` as frozen artefacts (the generator that made
them is in history at `09b6f0d`); its deploy adds LibGlass's current textures. Textures are
generated, never hand-edited: LibGlass's `Tools\make_textures.py`. On 70009 a **new texture file
loads after `/reload`** (measured, `docs\FOREVER-PROBE.md`); only a brand-new addon folder needs
a full client restart.

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
    into `SetFormattedText`. Never read start/end times in Lua, with **one measured exception**:
    the player's own cast. Its start/end, `delayTimeMs`, `isTradeskill` and castGUID came back
    plain in and out of combat on 1.60.1.70338 (#72, `Tools/CastProbe`), and
    `HasSecretValues()` is false. So `Castbar.lua` reads them for the latency block and the
    pushback, each behind an `IsSecret` guard (secret means not shown). Other units' casts stay
    unread. See DinoUF `modules\cast.lua`.
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
- Talent specs: `C_SpecializationInfo` is in the dump, but what it returns on Forever's Vanilla
  talent trees is **unmeasured** (#35 needs it). `MAX_PLAYER_LEVEL` is nil, so use `GetMaxPlayerLevel()` (60). The live
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
  `CHANGELOG.md` and `LICENSE`, plus the library's non-dot dev files under `Libs/LibGlass-1.0/`
  (CurseForge's packager doesn't apply an external's own ignore list). Patterns match the whole
  path from the package root, so the top-level `LICENSE` ignore never strips
  `Libs/LibGlass-1.0/LICENSE`, which ships (MIT).

## Conventions

- **Right-size for a single maintainer.** Do the simplest thing that works, with no speculative
  abstraction or config.
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it. The
  porting guide has already had to reverse reasoned conclusions (click-casting, "park it off
  screen", persistence).
- Match the surrounding code's idiom. Keep pure refactors in their own commit.
