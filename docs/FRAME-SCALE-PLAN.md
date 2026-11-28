# Unit frame scale (#217)

A player asked on CurseForge how to make the unit frames smaller. Today nothing scales the unit
frames: only the detached cast bars, the swing rows and the combat zoom spots have a scale.

## 1. What the player gets

- **Two scales, one per group** (owner's pick, 2026-11-28):
  - **Your frames:** player and pet.
  - **Target frames:** target, target of target, target of target of target, focus, focus target.
  - A follower always has its leader's scale, so a cluster shrinks or grows around its leader's
    centre and keeps its gaps.
- **Range:** 0.5 to 2, in 0.05 steps, as the detached cast bars. The default is 1, which isn't
  saved.
- **Where:** two sliders on the main options page under Positions ("Size of your frames", "Size
  of the target's frames"), `/guf scale [player|target <0.5-2>]` (no argument prints both), and a
  scale field in unlock mode's nudge panel for the player and target movers (the panel already has
  a scale-only row for the zoom spots).
- **When:** out of combat. In combat the change is queued (`WhenOutOfCombat("scale:<group>")`,
  the last request wins) and the player is told the frames resize when combat ends.
- **The leader keeps its anchor.** A scale change keeps the point each leader is anchored by
  where it is: its centre for a default or a canonical (`CENTER`) save, its corner for an older
  corner save, and its **grid-facing edge** while the group layout places it (the layout places
  an edge, so a wider or narrower frame moves its centre). Screen clamping
  (`SetClampedToScreen`) can still push a large frame in from the edge, as today.

## 2. Saved data

`db.frameScale = { player = s, target = s }`. Each value is validated (a plain finite number,
clamped to 0.5–2, rounded to 0.05). A value of 1 is removed, and the table goes when empty.
Junk falls back to 1. `GlassUF.Settings.SetFrameScale(group, s)` is the one setter that saves.

The **position saves keep their format** (`{ "CENTER", rel, "CENTER", x, y }`) and change no
meaning at scale 1. Their units at another scale:

- **A save on UIParent** (leaders, and a follower an older save left on the screen): **UIParent
  units**, as today. Applied as `SetPoint(p1, UIParent, p3, x / s, y / s)`, because SetPoint
  offsets are in the frame's own (scaled) units.
- **A save on the leader** (followers): **design units** (the frame's own units at scale 1).
  Applied raw: `SetPoint("CENTER", leader, "CENTER", x, y)`, which the client scales with the
  frame. That's what keeps a shrunk cluster tight.
- The **defaults** follow the same two rules: a leader's default point is divided by `s`, and a
  follower's default offset is applied raw.

## 3. The Frames API stays in UIParent units

Callers (Movers, the nudge panel, mirroring, Link) keep working in UIParent units. Frames
converts:

- **Requested and applied scale are two things.** `Frames.scaleReq[group]` is what was asked
  (and saved); `Frames.scaleApplied[group]` is what the buttons carry now. Every conversion uses
  the **applied** scale: while a combat-queued change waits, the buttons still have the old one.
  `Frames.ScaleOf(unit)` is the applied scale of its group (a follower's root leader, from
  `LAYOUT`, so it works inside `build` before `byUnit` is filled).
- `Frames.PositionOf(unit)`: a canonical follower save returns `x * s, y * s`. The default
  offsets likewise. A non-canonical save measured from live rects converts both centres with
  `GetEffectiveScale() / UIParent:GetEffectiveScale()` (today it subtracts two `GetCenter`s that
  are in different units once a frame is scaled).
- `Frames.SetPosition(unit, x, y, live)`: round to 0.5 in UIParent units, as today. The **live
  write** converts too: `SetPoint("CENTER", rel, "CENTER", x / s, y / s)` for **every** unit,
  leader or follower, since `SetPoint` offsets are in the button's own units either way (a drag
  runs this path before anything is saved). It returns the rounded **UIParent-unit** offsets, as
  today (mirroring and `endDrag` use them).
- `Frames.SavePosition(unit, x, y)`: the save is `x, y` for a UIParent anchor and `x / s, y / s`
  for a leader anchor. The bound is checked on the **stored** value (`sane`, ±4096): an input that
  would store outside it is refused, so a save is never written that `validSaved` would then drop
  on the next apply or reload.
- **`SetPosition` checks the same bound first.** It rounds, converts to the stored value, and
  refuses (returns false) when that isn't `sane`, **before** `Link.Snap` or any anchor change,
  for live and committed moves alike. So a refused nudge doesn't move the frame, and a drag never
  records a refused spot as `lastX` for the combat save to try later. One local helper
  (`stored(unit, x, y)`) does the conversion for both.
- `Frames.WidthOf(unit)` stays the unscaled width. A new `Frames.ScaledWidthOf(unit)` is
  `WidthOf * s`, used by `Link.PointOf` and `Frames.OwnCenterX`.

## 4. Applying a scale

`Frames.SetScale(group, s)` records the request; `applyScale(group)` runs now out of combat, or
through `WhenOutOfCombat("scale:" .. group)` in combat (the queue keeps one entry per key, so the
last request wins, and the build drains first):

0. Finish any drag in flight (a new `Movers.FinishDrag()`, the existing `endDrag(true)`), while
   the old applied scale still describes it: it saves the last accepted spot (and its mirror
   partner's), drops the cached alignment lines and re-attaches the mover. Otherwise step 2 would
   re-apply the pre-drag save under a held mover, and `follow` would skip the write that brings
   the frame back (the offset it reads hasn't changed).
1. `scaleApplied[group] = scaleReq[group]`, then `b:SetScale(s)` on every built button of the
   group.
2. `applyPosition` for each of them, in `Frames.ORDER` (leaders before followers, focus before
   focustarget). This re-reads `Link.PointOf` with the scaled width, so a linked leader is placed
   by its edge, and it stops any link glide (`Link.Snap`): a scale change snaps.
3. `Castbar.Place` for every bar whose host's owning button is in the group (`c.b`, so the
   player's pass includes the bar keyed `"swing"`). That also moves the shown zoom outlines and a
   preview sample.
4. `Movers.Refresh()` (an open nudge panel shows the new offsets and scale). No `SyncBars`: the
   set of detached bars and zoom spots hasn't changed.
5. One announcement (`Link._announce`), linked or not: GlassActionBars follows the player and pet
   rects, and ThreatView re-docks on it (it subscribes). Not `Link.WidthChanged`: step 2 already
   placed the frame, and it would announce twice. (Step 0 can announce on its own when it commits
   a linked pet's drag, through `Link.Moved`: that's the drop's own announcement, as on any drop.
   It's left alone. The announcement is a state, not a delta: each one carries the full rects and
   replaces the last, so a stale one followed by the final one does no harm.)

**At build:** the addon's load path can itself be queued under lockdown (`whenOutOfCombat("build",
...)`), so the initial scale isn't an ADDON_LOADED step: `build(unit)` calls `b:SetScale` with
its group's saved scale **before its first `applyPosition`**, and sets `scaleApplied`.

## 5. What's a child of the buttons, and what that means

- **Inherits the scale, by design:** the body, the tile and portrait, every bar and text, the
  aura rows and the crowd-control icon, the DoT marker and kill icon, the five-second strip and
  regen segment, the combat timer (and its glow), the docked cast bars (the player's inside row,
  the target's pill under the auras, the pet's under it, the focus's above it), and the docked
  swing rows. Their anchors and offsets are in the button's units, so they stay laid out as at
  scale 1.
- **Must not inherit it:** a **detached cast bar or swing pill**. Its host is a child of its unit
  button (so it hides with it), but its spot, size and scale are in screen units and its own.
  Today `Castbar.PlaceAt(host, x, y, scale)` sets `host:SetScale(scale)` and offsets
  `x / scale, y / scale`, which assumes a parent at scale 1. Changed to
  `k = host:GetParent():GetEffectiveScale() / UIParent:GetEffectiveScale()`,
  `host:SetScale(scale / k)`, offsets `x / scale, y / scale` (the host's effective scale
  relative to UIParent is then `scale`, so the offsets land in UIParent units as before).
  `PlaceAt` is the one detached placement (Place, `Castbar.SetPosition`, the swing pill, the zoom
  glide and the outlines), so this one change covers them.
- **The zoom's glide** (`Zoom.lua`'s `rectOf`) reads the host's current scale with
  `host:GetScale()`. Once the parent is scaled that's the relative scale, not the bar's, so the
  glide would start from the wrong size. It becomes `he / ue` (the effective ratio it already
  computes), for **both** endpoints, including a glide home to a docked target, pet or focus pill
  (whose effective scale is then the group's).
- **UIParent children, unaffected:** the mirror timers' pill, the zoom outlines, the threat plate
  and window, the movers, the unlock dialog and the grid.

## 6. Other places that read the frames' geometry

- **Movers:** `offsetsFromMover` subtracts `relFrame:GetCenter()` from the mover's centre. The
  mover is a UIParent child, while a leader rel is a scaled button reporting its own units, so
  convert the rel centre by its effective ratio. `alignLines` already converts each source's rect.
  A mover covers its frame with `SetAllPoints`, which the client resolves on screen, so its size
  follows.
- **The nudge panel's scale field** for the player and target movers stays **enabled while the
  group layout owns the frame**: today `refreshPanel` disables every field, `panel.s` included,
  when `isLocked`. The position fields stay locked; the scale is the player's.
- **Mirroring:** `mirrorOf` compares `PositionOf` (UIParent units): unchanged. With different
  scales the two centres stay symmetric, not their edges. That's fine: mirroring places centres.
- **Link:** `PointOf` uses the scaled width. `applyPosition`'s linked branch divides `lx` and the
  own anchor's y by `s`. `OwnCenterX` uses the scaled width for a non-CENTER point. `rectOf`,
  `capture` and `glideFrom` already work through effective scales.
- **ThreatView:** its dock reads the target body's effective scale for the row offset. Its
  `setDock` direction guess also uses it. Nothing to change but the re-anchor.
- **Preview, Blizzard, Clique, Engine:** nothing reads geometry.

## 7. Tests (offline, `WoW.layout = true`)

- The saves at another scale: a leader at 0.7 keeps its on-screen centre (default and canonical
  save) and an older `TOPLEFT` save keeps its corner; a follower's on-screen offset from its
  leader is its design offset × 0.7. `PositionOf` / `SetPosition` round-trip in UIParent units for
  a follower.
- A live drag at 0.7: the on-screen centre **during** the drag (`live = true`) and after the
  save is re-applied are both where the mover is; for a leader and for a follower
  (`offsetsFromMover`).
- The stored bound: at 0.5, a follower input that would store past ±4096 is refused by
  `SetPosition` (live and committed) and `SavePosition`, leaving **both the anchor and the previous
  save** intact; one just inside survives a re-apply (a rebuilt `validSaved`).
- Edge snapping at 0.7: a scaled frame's mover, with explicit scaled mover dimensions (the stub's
  edge accessors use `_width` / `_height`, as `test_movers.lua`'s existing fixture sets them),
  snaps edge to edge onto another frame's edge, not centre to centre.
- Link at 0.7, the scale changed from the nudge panel while linked: the player's right edge at
  `l - 24`, the target's left edge at `l + w + 24`, one announcement, and the announced rects are
  the scaled ones.
- A scale change mid-drag: a follower moved live (`follow`), then the scale changes before mouse
  up. The accepted spot is saved and survives the re-apply, and the mover is back on its frame.
- A build deferred by combat (`whenOutOfCombat("build")`) comes up at the saved scale.
- A scale request in combat, then a `SavePosition` before combat ends (`endDrag`'s combat path):
  the save is converted with the **applied** scale, and lands right once the queued scale runs.
- A detached cast bar and the swing pill keep their screen spot and size when their unit's group
  scale changes; a docked one scales with the frame. The zoom glide's first frame is where the bar
  was.
- In combat: refused and queued; applied at `PLAYER_REGEN_ENABLED`, last request wins, nothing
  in `WoW.blocked`.
- Validation and pruning of `db.frameScale`; the slash command's usage line passes the stray-`|`
  check; the options sliders sync on show.
- Mutation-test the conversions: drop each `/ s` and watch a test go red.

## 8. In-game checks after the build

- The look at 0.6 and 1.4: the glass rims (LibGlass's 9-slice) and the 1 px lines at a
  non-integer scale. The detached cast bars already run at 0.5–2, so no surprise is expected.
- The 3D portrait at a small scale.
- A scale change while the group layout places the frames, and GlassActionBars' pet and stance
  bars following.
- A change in combat waits for combat to end, with nothing blocked (Bugsy).

## 9. Out of scope

- A scale per frame (the owner chose groups).
- Scaling the threat plate or window with the target (they're UIParent children with their own
  saved positions).
- Changing the mirror timers, the zoom spots or a detached bar's own scale.

## 10. Review

### Round 1 (Codex gpt-6.2-astra): REVISE, all taken

- The live write in `SetPosition` must divide by `s` for every unit, not only the save (§3).
- The ±4096 bound must hold for the stored value, or a follower save at 0.5 is dropped on reload
  (§3).
- "The leader keeps its centre" was too strong: a corner save keeps its corner, a linked leader
  its grid-facing edge, and clamping still applies (§1).
- The build can itself be queued under lockdown: the initial scale goes in `build(unit)`, before
  its first `applyPosition` (§4).
- Conversions use the applied scale, not the requested one, while a queued change waits (§3).
- The nudge panel's scale stays editable while the layout owns the frame (§6).
- No `Link.WidthChanged` after `applyPosition` (a double announcement), no `Movers.SyncBars`
  (§4).
- Re-place bars by their owning button, so the player's group includes `"swing"` (§4); the zoom
  glide's both endpoints use the effective ratio (§5).
- Codex noted the stub's edge accessors don't resolve `SetAllPoints` sizes, so a scaled mover's
  edge snapping needs its own test setup (§7).

### Round 2: REVISE, both taken

- The stored-bound refusal was only in `SavePosition`, after `SetPosition` had already moved the
  frame: `SetPosition` now checks the converted value before touching any anchor (§3), and the
  test asserts the anchor and the old save survive a refusal (§7).
- The edge-snapping test named in round 1 wasn't in §7: added.
- Confirmed sound: the live-write conversion, mirroring under unequal scales (both save on
  UIParent), the requested/applied split with a deferred build, the single announcement in place
  of `WidthChanged`, the `c.b` selection, `PlaceAt` and the zoom endpoints.

### Round 3: REVISE, taken

- A scale change during a drag (a key-bound macro while the mouse is held) re-applied the
  pre-drag save under the mover. The apply now finishes the drag first (§4 step 0), with a test
  (§7). Every earlier fix was confirmed as written.

### Round 4: REVISE, not taken

- Codex: a linked pet mid-drag when the player group's scale changes gets two announcements (the
  drop's, at the old scale, then the scale's). **Not taken:** the announcement is a full state
  that replaces the last (GlassUI's `docs/GROUP-LAYOUT.md` §5b; `GlassUF.LayoutState()` answers
  the same), the final one is correct, and the case needs a key-bound scale macro pressed during a
  drag. Coalescing would add a suppression flag through `endDrag` → `SetPosition` → `Link.Moved`
  for no visible effect. Noted in §4.

### Round 5: APPROVE

- Codex accepted the round-4 pushback: both announcements run in the same call before the next
  frame renders; GlassActionBars replaces its offsets on each event (`Follow.lua`), and ThreatView
  re-docks from current geometry without saving. No other blocker.

### PR #218's review (Codex, bb1e49e): two P2s

- **A frame too wide for the room beside the grid: taken.** At 1.4 the player is 511 wide and the
  fixture leaves 376 each side, so the client's screen clamp pushed it over the grid while the
  `dx` we announced (GlassActionBars' stance bar) still said the unclamped spot. `Link.PointOf` now
  stops the frame at the screen's edge itself, so the place and the announcement agree. It still
  overlaps the grid: at that scale there's no room, and its own position overlaps the grid too.
  `test_link.lua`'s synthetic `l = 300` layout put the player 89 off screen at scale 1 (a spot the
  client never drew), so it moves to a layout that fits.
- **Unlock rewrites a corner save as `CENTER` before the Scale field is used: not taken.** That's
  `NormalizeSaves` (#52, 2026-09-28): unlock has always put older saves in the current form,
  without moving anything. The current form arrived before the first release (v0.1.0-alpha1,
  2026-10-21), so no player has such a save, and once converted the frame scales around its centre
  like every save made since. Codex withdrew it in the follow-up.

### PR #218's follow-up (Codex, 247149c): one P2, taken

- `playerDX()` measured the clamped linked centre against an unclamped own centre: saved at -450
  and scaled to 1.4, both sit at the screen's edge (255.5), yet `dx` said 22.5. One helper,
  `Frames.ClampCenterX`, now clamps both `Link.PointOf` and `Frames.OwnCenterX`, with a test for
  that case.
