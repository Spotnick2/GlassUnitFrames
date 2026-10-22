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

**Status (2026-10-19): a working addon, in daily use by the owner.** The glass look is settled and
tuned in game (LibGlass's `docs/GLASS-MATERIAL.md`; the material is now the embedded library
LibGlass-1.0, see "The glass material"). Frames: player, target, pet, targettarget,
targettargettarget, focus, focustarget. Every "Owner's picks" item in `docs/SUF-INVENTORY.md` is
done, plus: an options panel (Options > AddOns > Glass Unit Frames), unlock mode (movers, group
moves, nudging, grid snap, alignment guides, player/target mirroring), the red health-loss
segment, the hidden-power fade, neutral NPCs red in a fight, raid mark / target level / pet
happiness placement, per-frame health text, combo points, the druid mana strip, and the group
layout (#132, `Link.lua`: player and target beside Glass Raid Frames' grid, in sync with
GlassActionBars and Glass UI). (Hosted shaman totems were removed in #58: `TotemFrame` is a
managed frame, see `Blizzard.lua` below.)

- **Awaiting in-game checks** (built and tested offline only): combo pips (rogue, cat druid), the
  druid mana strip (bear/cat).

Work goes through GitHub issues and PRs at `github.com/Spotnick2/GlassUnitFrames` (private).

## Layout

TOC load order: `Libs\LibGlass-1.0\LibGlass-1.0.xml` (the embedded material) → `Compat.lua` →
`Glass.lua` → `Engine.lua` → `Frames.lua` → `Castbar.lua` → `Swing.lua` → `Timer.lua` → `FiveSecond.lua` → `Zoom.lua` → `Link.lua` → `Preview.lua` → `Auras.lua` → `Blizzard.lua` →
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
    combo pips use it. Nothing may depend on `Enum.LuaCurveType.Step` existing. `ManaAlpha` is
    the same over MANA by type (1 below full, 0 at full): `PowerAlpha` reads the current bar, rage
    or energy for a druid in a form;
  - `SafeFrame(type, parent, template, proof)`: a template that may be missing returns a bare
    frame rather than throwing, so `proof` names a field the template would make.

  It also holds `MEASURED_ON_BUILD`.
- **`Glass.lua`**: `GlassUF.Glass`, this addon's instance of the embedded material (see below).
  Every call site dot-calls it (`Glass.Apply`, `Glass.Bar`, `Glass.MEDIA`, ...).
  - It's a **forwarding handle** (#102) to the instance in use. `GlassUF.UseLook(look, body)`
    builds it at ADDON_LOADED, before anything is built, from `db.look` (`/glass look`, an options
    radio, after `/reload`).
  - **The looks** are LibGlass presets: **Pearl** (the default, not saved; owner, #129), **Clean**
    and **Classic** (both saved). A profile that never chose a look gets Pearl; there's no
    migration.
    - Pearl needs LibGlass r11. With an older copy winning (MINOR below `GlassUF.PEARL_MINOR`),
      or Pearl's `New` failing under pcall, the look is Clean.
    - That case sets `GlassUF.lookFallback` ("Pearl needs LibGlass r11 or newer: Clean in use",
      the same text as GRF), which is said once at load, on `/glass look` and under Look on the
      options page.
    - Classic omits the preset: r6-r10 refuse `"classic"`.
  - The glass body works the same way (#101), from `db.glassBody`. Clear is LibGlass's own
    default (tint alpha 0.24). "smoked" passes `bodyAlpha = GlassUF.SMOKED` (0.65, the middle of
    the 0.50–0.80 LibGlass explored). It's set with `/glass body` and a Body radio, after
    `/reload`. `GlassUF.UseLook(look, body)` builds one instance with both.
  - The instance's functions are closures bound to it, so forwarding is enough.
  - Never keep `Glass.TUNABLES` / `STYLE` from file load: read them when used.
  - **Following Glass UI** (#129, the contract is GlassUI's `docs/SUITE.md`, API 1; don't
    paraphrase or extend it). `GlassUF.UseSuite(ADDON)` runs first at ADDON_LOADED, once a session.
    - **The check:** `rawget(_G, "GlassUI").Suite` must be a table with `API == 1` exactly, and
      `Theme` / `Report` must be functions; anything else counts as absent. Then
      `pcall(Theme, ADDON)`, and only an answer whose `preset` is `"pearl"` (read under pcall)
      counts.
    - **Told Pearl:**
      - LibGlass's winning MINOR below `GlassUF.PEARL_MINOR` (11) is `"library-too-old"`, and
        `New` is never asked.
      - `pcall(lib.New, lib, { preset = "pearl" })` erroring is `"build-failed"`.
      - Either failure leaves `GlassUF.suiteFailure` set and the local look built.
      - Success sets `GlassUF.following = "pearl"`.
    - **While following**, the look, body, ramp and knobs are suspended but kept:
      - `ensureDefaults` neither applies nor prunes the knobs, and the saved ramp isn't applied.
      - `Settings.SetLook`, `SetGlassBody`, `SetTrackRamp`, `SetTunable` and `ResetLook` refuse.
      - `/glass look|body|ramp|<knob>` says `GlassUF.SuiteStatus()`.
      - The options page shows that note and disables those controls, dimmed (0.5) with grey labels:
        `SetEnabled(false)` alone shows nothing (our labels are font strings), as GRF measured.
    - **Glass UI settings**, a button under Look (`GlassUF.OpenSuite`), calls `Suite.Open()`
      under pcall. It's shown whenever the Suite has `Open` (GlassUI bcbd20f, still API 1), following
      or not: GRF's button, with the same label.
      - The font, cast colours and aggro red apply as usual.
    - **Report:** under pcall, right after the build: `{ api = 1, built, reason, minor, options,
      layout = { linked, placing } }`. A report replaces the last, so `GlassUF.ReportSuite()` sends the
      whole table again whenever the group layout's link changes (#132).
    - **The TOC** has `## OptionalDeps: GlassUI`, so Glass UI's `Theme` is ready first.
    - Glass UI's SkinProbe reads `GlassUF.Glass.preset` / `STYLE` and the saved look keys: keep
      those names.
  - **A bar's empty part** (#117). LibGlass's track ramp (the bar's colour fading to clear across
    the bar) made a 9% mana bar read as half full. Every health and power bar draws it at 0.25
    (`Frames.lua`'s `QUIET_TRACK`) through **the track's clip frame** (`bar.trackClip:SetAlpha`):
    the track texture's own `SetAlpha` changed nothing in game. `db.trackRamp` ("edge", saved;
    the whole bar is the default) moves the ramp to the fill's moving edge over
    `GlassUF.RAMP_LENGTH` (5%) of the bar, live, through LibGlass r10's `SetTrackLength`
    (`Settings.SetTrackRamp`, `/glass ramp whole|edge`, the main page's Fade radio). With an
    older LibGlass winning, "edge" is refused and a saved "edge" is kept, but "whole" (and Reset
    look) still clears it: that copy draws the whole bar anyway.
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
  - `Engine.OnTokenChanged(base)` is the hook for per-token reactions: target and focus
    changes, and a new pet (`UNIT_PET` for the player). Every one resets that frame's cast
    state (`Castbar.TokenChanged`); the target's also refreshes its auras and plays the sheen.
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
  tall at the default UI scale**: check new frames in those units, not on the owner's 4K screen.
  The defaults are the owner's tested setup (#141): player and target at (∓304, −272), focus at
  (96, 98) from the target, focus target at (208, −1) from focus. The old rule (everything above
  y = −280) is retired.
- **`Frames.lua`** (frames): `LAYOUT`, the secure buttons (`SecureUnitButtonTemplate`, `"AnyUp"` clicks,
  `RegisterUnitWatch`), and the painters. The glass hosts are mouse-less children, so a click
  anywhere, portrait included, reaches the button. **Hover tooltip** (#80): `OnEnter` / `OnLeave`
  post-hooks call Blizzard's `UnitFrame_OnEnter` / `UnitFrame_OnLeave` (they read `self.unit`),
  never on a forbidden `GameTooltip`, under `pcall` (an error goes to `API.Fail("tooltip")`),
  as SUF and DinoUF do.
  **Click-casting** (#125): each button registers itself in Clique's `ClickCastFrames` table
  (`registry[b] = true`, created with `rawset` only when absent), so GlassRaidFrames or Clique
  binds it. The table is read at registration time, and the entry is a plain assignment, never
  `rawset`: GlassRaidFrames sees entries only through its `__newindex`. It sets only
  modifier-specific attributes, so `*type1` / `*type2` keep plain clicks.
- **Portraits** (`Frames.lua`): the 3D model via SUF's sequence (`ClearModel`, `SetUnit`,
  `SetPortraitZoom(1)`, `SetPosition`).
  - Some units get **no model at all**. Measured on 70338 (#82): an Earthborer's
    `GetModelFileID()` was nil while it was visible and in range.
  - A model without a file gets one retry 0.3 s later (`portraitToken`: a newer paint cancels
    it), then the client's **2D portrait** (`SetPortraitTexture` on `b.portrait2D`, a tile
    texture under the model's frame), cropped to the square inside its disc so it fills the tile
    (#84).
  - An out-of-range unit gets the 2D portrait at once.
  - An unreadable file id counts as a model: a working 3D portrait is never swapped for a guess.
  - **Modes** (#97), per portrait frame (player, target, pet), saved in `db.portrait[unit]`
    ("2d" | "none"; 3D is the default and isn't saved):
    - **2D:** the painter always uses the 2D path and never loads the model.
    - **none:** the tile is hidden and the secure button narrows to the body.
    - `Frames.portraitReq` is what was asked; `b.portraitMode` is what's applied. 3D ↔ 2D applies
      live, in combat too. To or from "none" resizes the protected button, so in combat it waits in
      `WhenOutOfCombat("portrait:<unit>")`, and the last request wins.
    - Every applied change bumps `portraitToken` (a pending retry never lands).
    - **With no tile:**
      - the level "on the portrait" shows on the power line (`Frames.LevelPosOf`, used by
        `placeLevel` and the painters);
      - PvP and resting move to the body's top glass layer;
      - happiness anchors to the frame.
    - Mirroring stays centre mirroring for a mixed pair.
- **`Castbar.lua`**: the player, target, focus and pet cast bars (#72 moved them out of
  `Frames.lua`; pet and focus came in #76, each a 16 px pill (`LAYOUT.castH`): the pet's under
  its body, the focus's **above** it (`castAbove`: under it would cover the ToT row). They detach
  like the others and never get a latency block):
  the inside player row and the target's pill (`Castbar.Build`, `Castbar.CastingRows`), and the
  `cast` channel's painter. It paints through `Frames.attempt`, and Frames resolves it at build
  time.
  - **Detachable** (#74): each bar's host is a mouse-less **child of its unit button** (so it
    hides with it: no target, no target bar), with a glass pill of its own (`c.skin`).
    - **Docked:** the player's row inside the body (pill hidden; health and power shrink only
      while it's docked inside AND shown), the target's pill under its aura rows.
    - **Detached:** its own pill, CENTER on the screen centre. Every bar starts **docked**
      (owner, #142). A detached player's or target's bar defaults to the owner's tested spot
      (#141): 340×20, scale 1.5, at (0, −182) / (0, −152).
    - **Scale** 0.5–2 (0.05 steps), shown only while detached (`Castbar.SetScale`). The spot
      stays in screen (UIParent) units at any scale: SetPoint offsets are in the host's own
      scaled units, so `Place` / `SetPosition` divide them by the scale. Movers convert a scaled
      frame's rect for alignment (`GetEffectiveScale` ratio). `Castbar.CenterX` puts a detached
      bar in the exact horizontal middle.
    - Saved in `db.castBars[unit] = { detached, x, y, w, h, scale }`, each field validated against
      `Castbar.LIMITS` (junk falls back to its default), pruned when empty. Only what the
      player set is saved (typing W leaves H on its default). "Reset frame positions"
      (`/glass reset`) also resets every bar's spot and size (`Castbar.ResetPositions`); it
      stays detached. A unit without `DETACHED` defaults gets a generic one.
    - `Castbar.Place(c)` lays a bar out for its mode and reconciles the rows. Levels are fixed at
      build: host H, pill H (rims H + 10), bar H + 2, text H + 11.
    - Detach and attach work **in combat**: a cast host is never protected (measured with
      CastProbe `hier`, #74).
    - In unlock mode a detached bar is a mover source `cast:<unit>` (`Castbar.MoverSource`: W/H,
      Attach).
  - **Quartz's look and options** (#78), on every bar unless noted:
    - **Spell icon** at either end, as tall as the bar, which is shortened to make room
      (`placeBar`). Yours and the pet's are on the left, the target's and the focus's on the right
      (the mirrored pair), and it can be set to "none" (`castBars[unit].icon`, saved only when not
      the default). The texture goes from `UnitCastingInfo` / `UnitChannelInfo` straight to
      `SetTexture` (never read in Lua).
    - **`Spell -> Target`** on the player's bar only, from SENT's target name (plain for the
      player, "First Surname" in the traces), matched to the START by castGUID. Never for a
      self-cast, matched against every form of our name (`GetUnitName`, `UnitName`'s first name,
      and first + surname). A nil name never reaches `%s`.
    - **`remaining / total`** (`GetRemainingDuration`, `GetTotalDuration` straight to
      `SetFormattedText`: secret-safe). The precision is 0–3 decimals; the formats are built once
      per change (`FMT`).
    - **Spark:** a 2 px ADD line anchored to the fill texture's moving edge (no Lua geometry).
    - **Complete flash:** a short full bar in the complete colour when a **cast** (not a channel)
      STOPs without failing. The first INTERRUPTED / FAILED arrives with the cast still live, so
      it marks the newest cast failed (`c.failedGUID`, forgotten on a token change), and its STOP
      then doesn't flash green. The player's bar also needs that cast's SUCCEEDED
      (`c.succeededGUID`): a cast that fails as it lands gets none. Other units have no
      SUCCEEDED for us, so their STOP flashes, as in Quartz.
    - **Colours** (`db.castColors[key] = { r, g, b, a }`, validated, saved only when set): spell
      text, time text, casting, channeling, complete, failed, spark, and background. The
      background is the pill's own glass tint, through LibGlass's `SetSurfaceTint(g, ...)`;
      `SetSurfaceTint(g)` gives the built tint back. **No border colour:** LibGlass has no
      per-surface rim setter, so it waits on LibGlass.
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
      figure sits **inside the block, at its bottom corner** (Quartz) on a bar at least 20 tall (`MS_INSIDE`),
      just above a smaller detached bar, and never on the docked 14 px row.
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
    `Castbar.TokenChanged`) forgets the newest guid and hides the old unit's icon (a later FAILED
    with no START would flash it); an ordinary full repaint doesn't.
  - **Batch craft count** (#91): `Name (3/5)` on the player's bar.
    - **Source:** the client's own batch state. At each craft's START,
      `C_TradeSkillUI.GetRemainingRecasts()` is the casts left after it (measured 4, 3, 2, 1, 0 for
      a batch of 5, plain), and `UnitCastingInfo`'s **6th** return (`isTradeskill`) is plain
      true.
    - **Batch identity:** a batch continues only with the same recipe and a count exactly one lower;
      anything else starts a new one (`c.craft = { spellID, total, left, guid }`).
    - **End:** a matched FAILED / INTERRUPTED; a non-craft START or a CHANNEL_START; the matched
      craft's STOP with `left == 0`; or `UPDATE_TRADESKILL_CAST_STOPPED(false)`, a world event
      Engine hands to `Engine.OnTradeskillStopped`. Scrapping (`true`) is left alone.
    - **Late events:** an older craft's late STOP or INTERRUPTED and an unrelated FAILED never end
      it.
    - **Flash and target:** crafts with more of their batch to come don't flash "complete" (the next
      starts about 0.1 s later), and a craft never shows "-> target".
  - **Merged batch bar** (#93, option `craftMerge`, on by default): one duration for the whole
    batch.
    - **The estimate** is re-anchored at every craft START and DELAYED: this craft's plain end +
      `left` × (its base total + the gap). The gap is the running mean of STOP→next-START gaps in
      this batch: 0.1 s to start (measured), clamped to 0.5.
    - **Display:** `showCast` attaches the batch duration (fill and time text). The latency block
      and the pushback prefix are hidden.
    - **Hold:** a matched intermediate STOP sets a persistent `k.holding` (armed once), and the
      no-cast branch keeps the bar as it is through the gap.
    - **Guard:** a hold with no next craft START within 1.5 s ends the merge for the batch. It
      checks its own generation (`k.holdGen`), never `c.token`.
    - **Sticky per batch:** it's decided at the batch's first START. Unreadable timing, the guard,
      or the option turned off end it for the rest of the batch; turning the option on applies from
      the next batch.
    - `UPDATE_TRADESKILL_CAST_STOPPED` repaints the player's bar, so a held bar hides while a flash
      or a replacement cast stays.
  - **Options:** `latency`, `latencyText`, `pushback`, `targetName`, `totalTime`, `complete`,
    `craftCount`, `craftMerge` (`Castbar.SetOption`, saved only when off).
  - Measuring tool: `Tools/CastProbe`.
- **`Swing.lua`** (#87): the player's swing timer.
  - **Rows:** main hand, off hand and ranged, drawn from the client's own `PLAYER_SWING(duration,
    type)`. It's plain in combat, and it still arrives with Blizzard's "Enable Swing Timer" off
    (both measured).
  - **GUF never touches Blizzard's swing frames** (Edit Mode managed frames). The player turns them
    off with Blizzard's option, which the Cast bars page mirrors as a checkbox: `showSwingTimer`,
    set only by a click, out of combat, synced on `CVAR_UPDATE` and combat changes.
  - **Visibility:** a row appears on its first swing and stays until combat ends, then hides once
    its swing is over. A swing is the proof its weapon exists, so the attack speeds (secret in
    combat) are never read. Combat state for visibility is `UnitAffectingCombat` /
    `PLAYER_IN_COMBAT_CHANGED`. A weapon swap or death idles the rows; out of combat, they go at
    once.
  - **Fill:** a `C_DurationUtil` duration on `SetTimerDuration`. Idle is a finished duration
    counting down. One 20 Hz ticker runs only while a swing is in flight.
  - **Range:** out of reach dims a row to 0.4.
    - GUF only ever calls `EnableRangeCheck(type, true)`: on a row's first show, on target change,
      on world entry, and on `CVAR_UPDATE` of `showSwingTimer`.
    - A Blizzard `false` is answered on the next frame (a post-hook, coalesced per type, and only
      while the rows are on and that row shows).
  - **Docked (default):** 3 px rows with 1 px gaps inside the player frame, under the power bar, or
    under the docked cast row while it shows.
    - **`Frames.ReflowRows(b)` owns the body's rows**: Castbar sets `b.castShown`, Swing sets
      `b.swingCount`.
    - Health gives the room, never under 12 px; below that, power gives the rest, down to 6.
  - **Detached:** a glass pill of stacked rows, through Castbar's detach machinery as the bar
    `swing`.
    - `Castbar.bars.swing` places itself (`c.place`) and paints its own colours (`c.paintColors`).
    - Saved in `db.castBars.swing`; `h` is one row, 2–20 (`Castbar.LIMITS_FOR`).
    - The mover is `cast:swing`. While unlocked, the pill shows every row.
    - Time text shows on rows at least 8 px tall.
  - **Colours:** `castColors` keys `swingMH`, `swingOH`, `swingRanged`. The option is
    `db.swingTimer` (saved only when off).
- **`Timer.lua`** (#120): the combat timer, a small glass pill (52×18) **over the player's
  portrait** with the fight's time (`00:07`, `1:00:05` past an hour), from our own `GetTime()`
  stamp (plain). With the portrait set to "none", over the frame's top-left, 10 up (clear of the
  leader crown); `applyPortrait` calls `Timer.Place()`. Not movable: a detached timer is a
  GlassPanel plugin's business.
  - **It opens** when combat starts (0.25 s ease-out: a circle growing into the pill, fading in)
    and **closes** the same way when it ends, frozen on the fight's final time. A fight starting
    mid-close reopens it from where it was. One OnUpdate inside the host drives the animation and
    the clock (written once per second), and rests while the player frame is hidden.
  - **What shows** is one resolver over independent inputs: off -> closed; preview (counts from
    00:00) -> combat -> closed. Combat is recorded whatever shows, so the dispatcher's order
    (Preview stop, the timer's own frame) never loses a start. A `/reload` mid-fight counts from
    the reload; a loading screen inside a timed fight keeps its start (`live = live or GetTime()`).
  - **Option:** `db.combatTimer` (saved only when off), `Settings.SetCombatTimer`, `/glass timer
    on|off`, a checkbox on the main page (the Cast bars page doesn't scroll and is full: a test keeps
    its controls inside the canvas). Idempotent; off -> on in a fight starts counting
    from now.
  - `Timer.enabled` is public: ForeverCombatAssistant hides its own timer while it's true.
- **`FiveSecond.lua`** (#94): the five-second rule, for mana users only (none for warriors or rogues).
  - **The strip:** 2 px red along the bottom of the player's power bar, or of the druid mana strip in
    a form (chosen by power token; `UNIT_DISPLAYPOWER` re-picks it). An `OverlayBar` inside the
    bar's rounded mask. It drains (`RemainingTime`) for the 5 s after a likely spend, then hides.
  - **No tick timer.** Forever's regen is continuous (measured, #108). While regenerating, about 7
    `UNIT_POWER_FREQUENT` per second arrive: one per mana point at 6.5/s, 14–15 between two
    `UNIT_POWER_UPDATE`s. None arrive inside the 5 s, and they restart about 5.0–5.2 s after the
    last spend. The ~2 s UPDATE cadence is the server's sync, not a tick.
  - **Mana is secret** in and out of combat (measured), so it's never read. **A spend:** a player
    `UNIT_SPELLCAST_SUCCEEDED` whose `C_Spell.GetSpellPowerCost` (measured plain) has a mana
    entry with a cost or `costPerSec` > 0, or a secret amount. The whole traversal is under
    `pcall`, secrecy-checked step by step; unknown is not a spend. A new spend restarts it.
  - **Ending it:** the window's timer (generation-checked), combat exit (regen was measured
    resuming about 2 s after a killing spend), death, and the option off.
  - **Full mana** hides it through `API.ManaAlpha` on the strip's clip frame, refreshed on
    `UNIT_POWER_UPDATE("MANA")`.
  - **Its own event frame:** the order of SUCCEEDED and combat changes matters, so it doesn't go
    through Engine.
  - **Options:** `db.fiveSecondRule` and `db.fsrCombatOnly` (on by default, each saved only when
    off), on the main page, only for mana users.
  - **The regen segment** (#118), in the same file (it shares the window, the bar choice, the
    events and preview): a faint bar past the mana fill as wide as the next 2 s of regen.
    - **No arithmetic:** `GetManaRegen()` is secret in combat, so the bar is **twice the mana bar's
      width** (`b.healthWidth`, the druid strip's `b.druidMana.width`) with the range
      `(0, UnitPowerMax)` and the rate as its value: it draws `rate / max * 2W`. Anchored to the
      fill's moving edge, top and bottom (it follows `ReflowRows`), clipped at the bar's end
      (`Frames.OverlayBar`, level +3).
    - **The rate:** inside the window `castingManaRegen`, else `baseManaRegen`, chosen by an
      explicit `if` on our plain state (never `a and secret or b`).
    - Hidden at full mana (`API.ManaAlpha`, no preview override: it's past the end anyway), when
      dead or a ghost, and on the druid strip during a preview (that strip is sampled at 60%).
      In a preview its own events (mana and max mana updates, form, death, alive) still repaint
      it.
    - Repaints on `UNIT_POWER_UPDATE` / `UNIT_MAXPOWER` ("MANA"), form changes, the window,
      `PLAYER_ALIVE` / `PLAYER_UNGHOST`.
    - **Tracking vs showing:** the events and the window serve both, kept while either is on.
      The last one off unregisters and idles; the first one on registers, re-reads combat and
      idles; otherwise the window is kept. The strip turned off during a preview still ends its
      sample loop.
    - `db.manaRegen` (saved only when off), `Settings.SetManaRegen`, `/glass regen on|off`, a
      checkbox in the main page's "Mana" section.
- **`Zoom.lua`** (#89): combat zoom, per bar (player, target, focus, pet, swing): on for the player and
  target by default, at scale 1.5 and the owner's tested spots (0, −182) / (0, −152) (#141), off
  for the rest. The global `on` is saved only when it
  differs from the bar's default.
  - **What it does:** in combat, a bar is laid out **detached at its zoom spot** (x, y, scale) and
    goes home when combat ends.
  - **Placement:** `Castbar.Place` and the swing rows' `place` read `Castbar.EffectiveGeometry(unit)`,
    which overrides the geometry with `Zoom.Target(unit)`. `Castbar.PlaceAt(host, x, y, scale)` is
    the one detached placement (Place, SetPosition, the swing pill, the glide and the outlines). That's an
    **effective** detach: the saved one is untouched. So a zoomed player row gives the body its
    room back, and the docked swing rows leave too.
  - **Glide:** a visible bar glides (0.3 s ease-out cubic, centre and scale, in UIParent units
    through the effective-scale ratio). A docked-inside row, the docked swing host, a hidden host,
    or an unreadable rect snaps.
  - **Placement and glides:** any `Place` cancels that bar's glide (`Zoom.Cancel`) and snaps; a
    mode change retargets from the glide's current point. `Castbar.SetPosition` / `CenterX` save
    the home spot but don't move a zoomed host.
  - **Triggers:** the combat dispatcher calls `Movers.OnCombat()` then `Zoom.OnCombat(true)`. On
    regen, `Zoom.OnCombat(false)` runs **before** the lockdown guard and the combat queue. `PLAYER_ENTERING_WORLD` sets the
    initial state.
  - **Settings:** `db.zoom[global|healer|tank|dps][bar] = { on, x, y, scale }`, sparse, each field
    validated (scale 0.5–2.5). `db.zoomRole[guid]` is this character's role (read at
    `PLAYER_LOGIN`; a secret or absent GUID means global).
    - A role's entry, when there is one, is used whole; else the global one.
    - A role's first edit copies the bar's resolved global entry.
    - You edit the table of this character's role (`Zoom.EditedKey()`).
  - **Unlock mode:** each bar with its zoom on gets a yellow outline (a proxy frame on UIParent) and
    a mover `zoom:<bar>`: position, scale, reset, no W/H. `Movers.SyncBars` adds and removes it.
    "Reset frame positions" also resets the zoom spots of the edited table.
  - **Options:** its own sub-page, "Combat zoom" (registered after Cast bars): per bar, "zoom in
    combat" and a combat scale; this character's role.
- **`Link.lua`** (#132): the group layout. The plan is GlassUI's `docs/GROUP-LAYOUT.md` (sections 4
  and 5, GlassUI#28; Codex consensus). Don't extend it here: changes go through the Glass UI session.
  - **The state:** GRF announces `GlassRaidFrames.LayoutChanged(role, l, b, w, h, top, base, mode)`
    on `EventRegistry` (never in combat), and answers `GlassRaidFrames.LayoutState()` (the same
    fields, a fresh table, or nil before it built). UIParent units from its bottom-left; l, b, w, h
    are the grid plus its pets, `top` the grid's own top. Subscribed at file load; read under pcall
    after the (possibly deferred) build (`Link.Built`, the end of `Frames.Build`). Anything but a
    valid state (finite, plain, w and h > 0, a mode) counts as none, and only `"hud"` places.
  - **Placing** (`Link.applied`, a session-only override, never saved), out of combat through
    `WhenOutOfCombat("link")`:
    - **horizontal only** (GlassUI#32: at `base + 98` the player landed on the chat tabs, M5): the
      player's centre x at `l - 24 - width/2` from UIParent's left, the target's at
      `l + w + 24 + width/2`. The height stays the frame's own: `applyPosition` keeps its own
      anchor's vertical part (saved or default; `TOP` / `BOTTOM` / middle on UIParent's
      `TOPLEFT` / `BOTTOMLEFT` / `LEFT`, its own y), so it also follows a UI scale change.
      `Frames.WidthOf` is 365 with the tile, 300 without, and a portrait change re-places
      (`Link.WidthChanged`). Followers ride their leaders.
    - the player and target cast bars: **never placed, only lifted** (owner, #142). Each keeps its
      own spot (docked, detached, or the zoom's in combat). While linked, a detached or zoomed pair
      rises by one amount (`Castbar.Lift`, partner re-placed by `Castbar.PlaceStack`) until the
      lowest one's bottom is `Link.CLEAR` (6) over the grid's top (`Link.GridTop`). A docked bar
      stays docked. `EffectiveGeometry`: zoom, then saves, then the lift. The zoom outlines show
      the lift as it will be in combat (`Castbar.Lift(true)`, from `Zoom.Spot`). Their movers
      (cast and zoom) work where the bar shows; a drop or typed spot takes off only the lift the
      partner imposes (`Castbar.PartnerLift`), so it lands where it was dropped. Any change to one
      bar, a zoom setting included, re-places both (Codex, #143).
  - **Set aside, kept intact:** `Frames.ApplyPosition` asks `Link.PointOf` first. While linked,
    `Frames.SetPosition` / `SavePosition` / `ResetPosition` are refused for the player and target
    frames (the cast bars stay fully the player's: nothing of theirs is set aside, #142).
    `ResetPositions` keeps the frames' saves; `NormalizeSaves` skips them, and a follower
    saved on UIParent while its leader is linked (`Link.Carried`). Movers sources have `locked()`:
    the mover selects but doesn't drag, and the panel says `Link.NOTE` with its buttons off.
    Letting go re-applies each frame's own validated tuple (`applyPosition`).
  - **The glide:** the buttons snap; each visible button's body and tile (one point on the button,
    `b.bodyPoint` / `b.tilePoint`) are offset by old minus new and eased to zero (0.3 s, cubic
    ease-out, the zoom's). The cast bars glide through the zoom's own controller (`Zoom.Move`). The
    places while a loading screen is up snap, and so does the first one after it lifts, frames and
    cast bars alike: no glide behind any loading screen (GlassUI#38, #39 and its follow-up; GRF#74
    does the same). At login GRF's first announcements can come before the party is listed, the real
    one ~1.7 s later; an instance can change the layout behind the screen. The build and every
    `LOADING_SCREEN_ENABLED` arm `snapNext`; only a place with the screen gone spends it. Decorations anchor to visuals, never the button
    (`Frames.EdgeVisual`: the right-hand raid mark, pet happiness, the portraitless timer), and no
    protected frame anchors to a visual. `Link.Snap(b)` (any other place) drops a glide.
  - **Our own announcement** (the plan's section 5b, GlassUI#33 and #34; GlassActionBars' stance
    and pet bars follow the player and pet frames, GAB#30): `GlassUnitFrames.LayoutChanged(linked,
    player l, b, w, h, pet l, b, w, h, dx, petDx)` on `EventRegistry`, after every reconcile, width
    change and, while linked, pet position change (`Link.Moved`: a drop, a reset; Codex, #133), so
    out of combat; a place queued by combat announces once when it runs.
    `GlassUF.LayoutState()` answers `{ linked, player = { l, b, w, h }, pet = { ... }, dx, petDx }`
    (fresh; nil before the build). Rects in UIParent units from its bottom-left. `dx` is the
    player's move: its linked centre x minus `Frames.OwnCenterX("player")`; `petDx` the pet's, `dx`
    when it rides the player, 0 when it's saved on the screen (`Frames.RidesLeader`). Both 0 when
    unlinked. Trailing arguments only grow.
  - **Setting:** `db.groupLink` (false when off), `Settings.SetGroupLink`, `/glass link on|off`, a
    checkbox and status under Positions.
  - **Measuring:** `Tools/LayoutProbe` (`/fp steps layout glide`, M5) announces a fake layout
    through the real event; `/fp layout pet|stance <dx>|off` fakes our own announcement for GlassActionBars.
    M5 passed on 70450 (2026-10-18, four runs): the player's frame, a hunter's pet with its
    happiness icon, and (run #241, step 1 waiting for a target) the target's frame glide like the
    zoom, nothing jumps or is covered, home exactly; horizontal only, the height held.
    The real layout (`/fp steps layout real`, GRF#72, run #274-278, 2026-10-19): placed exactly
    (player right at `l - 24`, target left at `l + w + 24`) at load, after a reload, and after a
    `/reload` mid-fight (placed, nothing blocked); with GRF turned off, own positions and nothing
    blocked. GUF can't be loaded before GRF in game (by name); the reload covers the late
    announcement that order relies on. A mid-fight `/reload` loads with the lockdown OFF (porting
    guide). GlassActionBars' pet bar, under the player and pet
    frames, stays put while they move (owner: a GlassActionBars question, not GUF's).
- **`Preview.lua`** (#109): every frame and bar with sample data, out of combat, session-only
  (`/glass preview`, a button on the main, Cast bars and Combat zoom pages that closes Settings, and
  a switch on the unlock dialog). DBM's simulated test bars were the idea.
  - **Frames:** every unit button but the player's leaves its unit watch (`UnregisterUnitWatch`,
    `Show`) and shows `Frames.SAMPLES` through `Frames.PaintSample` (plain values: name, health,
    power, text in the frame's format, level, loss segment, heal prediction, a skull, happiness,
    three combo pips). The portrait honours the applied mode: the player's model or 2D portrait.
    The player's frame stays live but for its cast bar and druid mana strip.
  - **One gate:** Engine's `paint` asks `Engine.Owned` (= `Preview.Owns`) first. A repaint with no
    event (a setting changed, a frame shown) refreshes the sample instead, so settings changes show
    on it. `Castbar.Place` calls `Preview.Placed`. `Engine.OnTokenChanged` doesn't reset a sample bar.
  - **Cast bars** loop `Preview.CYCLES` on durations we own: `Castbar.ShowSample` (showCast's look),
    `Castbar.SampleEnd` (the real flash, no guid), one generation per bar. `Castbar.ResetForPreview`
    clears every cast state on the way in and out.
  - **Swing** and **FiveSecond** have `SetPreview`: their event handlers ignore real events (FiveSecond
    still tracks combat), the swing range hook and its queued callback make no call, and the strip
    shows out of combat and at full mana.
  - **Ending it:** the toggle, `PLAYER_REGEN_DISABLED` (first in the dispatcher, before Movers: the
    lockdown isn't on yet there), `PLAYER_ENTERING_WORLD`. Stop hides the frames whose unit is
    plainly gone, re-registers the unit watch (queued under `WhenOutOfCombat("preview")` if the
    lockdown is somehow on), resets the bars and repaints everything for real.
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
  scale and Attach for a cast bar; **Center X** for anything, the exact horizontal middle of
  what it's placed on, alone: never mirrored). While unlocked, a glass **unlock dialog** at the top centre
  (Quartz's idea) holds Lock and the switches. It sits under the nudge panel and over the
  movers, and can be dragged aside (not saved).
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
  - `GlassUnitFramesDB` (`font`, `pos`, `hideBlizzard`, `hideBlizzardCast` (true by default, #141; `false` when shown), `mark`, `aggroRed`, `level`, `healthText[unit]`,
    `castLatency|castLatencyText|castPushback|castTargetName|castTotalTime|castComplete|castCraftCount|castCraftMerge` (saved only when off), `castBars[unit]` (#74; `castBars.swing` is the swing pill, #87), `castColors[key]`, `castPrecision` (#78), `swingTimer` (#87, saved only when off), `combatTimer` (#120, saved only when off), `fiveSecondRule` / `fsrCombatOnly` (#94, saved only when off), `manaRegen` (#118, saved only when off), `look` (#102, #129: "clean", "classic" or nil = Pearl), `glassBody` (#101, "smoked" or nil), `trackRamp` (#117, "edge" or nil), `groupLink` (#132, false when off), `portrait[unit]` (#97, "2d" | "none"), `zoom` / `zoomRole` (#89), and the material knobs `fill|rim|track|fade|edge`, saved only once set);
  - the frames are built at `ADDON_LOADED`, before any lockdown;
  - **the addon's one combat queue**, `GlassUF.WhenOutOfCombat(key, fn, message)`: ordered, the
    build first, `message = false` for silent. Don't add a second one;
  - `/glass options|font|mark|level|text <unit> <format>|reset|blizzard show|hide|secrets|totem|frame <Name>|ramp whole|edge|timer on|off|regen on|off|link on|off`, plus the live
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
  `SetCastOption`, `SetCastDetached`, `SetCastScale`, `CenterCast`, `SetCastSize`, `SetCastIcon`,
  `SetCastColor`, `ResetCastColors`, `SetCastPrecision`, `SetTrackRamp`, `SetCombatTimer`, `SetManaRegen`). The cast bars have their
  own **sub-page**, "Cast bars": one set of per-bar controls behind a "Settings for" picker
  (Detached, icon side, width, height, scale, Center), and the shared text, colour and extras
  sections. Colour swatches open `ColorPickerFrame:SetupColorPickerAndShow` (DinoUF's way on
  Forever) above the Settings window. The picker is shared, so its strata is given back on
  `OnHide` (one hook). It reports its starting colour when it opens, and an unchanged default
  is never saved. A change refreshes only that swatch. The page is registered with
  `RegisterCanvasLayoutSubcategory`, right after the main page, and hidden at creation. The column helpers take the page they lay out on (`column(x, y, parent)`),
  and `slider` takes `{ label, min, max, step, get, set }` (`tunableSlider` for the material
  knobs).
- **`tests/`**: see Testing. `Tools/CastProbe/` is the throwaway probe: the cast, swing, craft and
  mana event trace behind #72–#108. It's a **ForeverProbe module** (#112; the shared host at
  `..\ForeverProbe`, `C:\Projects\WoW\References\Docs\PROBES.md`): `/fp cast` lists its commands
  (`status`, `mark <text>`, `cd`, `hier`, `clear`), its lines go to the `/fp` console and
  `CastProbeDB.log`, never chat. Deploy it with `Tools\deploy.ps1 -Probe` (the host first). A
  new in-game experiment is a guided procedure (`Probe:Steps`), not a chat checklist. Its test
  (`test_castprobe.lua`) loads the host from the checkout, so it runs locally only (CI sets
  `FOREVERPROBE_OPTIONAL=1`). `Tools/BarProbe/` (`/fp bar`, #117) shows sample glass frames at
  5–80% with live controls for the empty part's strength and ramp, applied to the real bars too
  and saved in `BarProbeDB.settings` (re-applied at login while it's deployed); `/fp bar reset`
  (or Forget) drops them, and `/reload` gives the bars back to GUF. Same host, same local-only test (`test_barprobe.lua`).
  GlassProbe, the material probe from before LibGlass, was retired in
  #112 (LibGlass's own probe, `/fp lg`, replaced it; its files are in history).

Forever is **Vanilla content running on Blizzard's Retail (Mainline) codebase**: assume Vanilla
content and the Retail API. `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`. Advice that cites a TBC or
Classic API is usually stale.

## References: read these before touching an unfamiliar API

- `C:\Projects\WoW\References\Docs\PORTING-TBC-TO-FOREVER.md` holds the canonical addon-agnostic field
  notes, measured on the live client. Treat them as fact; don't re-derive them. Other sessions
  edit this file, so write new addon-agnostic findings there, not into a copy in this repo.
- `C:\Projects\WoW\References\Forever\api\forever-api-1.60.1.70450.md` is the full API dump for the current
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

These live in `C:\Projects\WoW\References\Addons` (its `INDEX.md` lists versions). They show what works on this client *in practice*,
which the dump can't tell you. Reason about what they do rather than copying it. **None is
licensed for reuse:** SUF and DinoUF ship no license, and EllesmereUI is "all rights reserved".
Write our own code.

- **`ShadowedUnitFrames` is the design reference.** It's upstream SUF, cloned from
  `github.com/Nevcairiel/ShadowedUnitFrames` (`master` targets Retail 11.x; there's also a
  `classic` branch). It's the source of truth for *what* a unit frame addon does and how SUF
  structures it. It doesn't run on Forever: `units.lua` uses `SecureHandlerBaseTemplate`,
  `WrapScript` and `RegisterStateDriver`, which are all broken here.
- **`UnitFrames\DinoUnitFrames-Forever` is the Forever reference.** It's SUF's classic branch
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
- **`UISuites\EllesmereUI-9.3` is for inspiration** on architecture and visual style. It's a
  Retail-first suite with Forever support (`## Interface: …, 16001`, `EllesmereUI.IS_FOREVER`
  from `EllesmereUI_ClientGate.lua`). The useful part is `EllesmereUIUnitFrames\`, especially
  `EUI_UnitFrames_Engine.lua`, a clean update engine:
  - one tracker frame per unit token, using `RegisterUnitEvent` so the client filters events;
  - events grouped into *channels* (health, power, text, …), each with a registered painter;
  - repeated triggers in the same frame collapse into one paint;
  - one shared 0.5 s ticker for event-less units (`targettarget`), idle while hidden.

  `EllesmereUIRaidFrames\` covers party and raid frames. `EllesmereUI_ForeverLayout.lua` shows
  default positions coexisting with Edit Mode.

Keep a `MEASURED_ON_BUILD` constant in the source, matching the dump's build (`1.60.1.70450`),
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
pwsh Tools\deploy.ps1                                                # the addon + its LibGlass into AddOns (-Probe adds CastProbe + ForeverProbe)
bash tests/fetch_libglass.sh <dir>                                   # clone LibGlass at the .pkgmeta pin (what CI does)
```

The tests and the deploy need a LibGlass checkout: `..\LibGlass`, or `$env:LIBGLASS`. Without one
they fail loudly rather than skip. The probe's test and `-Probe` also need a ForeverProbe checkout
(`..\ForeverProbe`, or `$env:FOREVERPROBE`).

The retired GlassProbe's rim and sheen iterations are frozen in history (`Tools\GlassProbe\Media\`
before #112; the generator that made them at `09b6f0d`). Textures are generated, never
hand-edited: LibGlass's `Tools\make_textures.py`. On 70009 a **new texture file
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
- One global namespace table, `GlassUF`. Every file starts `GlassUF = GlassUF or {}`, and the
  TOC order is the load order.
  The one other global is `ClickCastFrames`, the name of a shared convention (Clique's), not an
  API alias.
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
- **Projects:** Wago `4N2bV0NL` (`## X-Wago-ID`, checked by `test_toc.lua`); the CurseForge project id
  goes in `## X-Curse-Project-ID` once it exists (#144).
- Releases are built by **CurseForge's own packager from the tag webhook**, reading `.pkgmeta`.
  Don't add a GitHub release workflow. CI (`package-check.yml`) only dry-runs
  `BigWigsMods/packager` with `-d`. The packager derives the `forever` flavor from
  `## Interface: 16001`.
- **Every tag needs a `CHANGELOG.md` entry committed first**, written for players. The tag name
  sets the channel: `alpha` / `beta` / anything else → Release. That's a distribution channel,
  not a stability claim.
- `.pkgmeta` ignores `.github`, `docs`, `tests`, `Tools`, `AGENTS.md`, `CLAUDE.md`, `README.md`, `README.curseforge.md` (untracked: the CurseForge description, in `.git/info/exclude`),
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
