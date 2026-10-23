# Threat meter and probe (#86)

## Current implementation (2026-10-22 redesign)

Settings: Options > AddOns > Glass Unit Frames > Threat. Group combat defaults on;
Off disables the feature, and Combat, including solo extends it to solo fights.
There is no idle display. The legacy `always` setting/command now means solo combat,
not permanent display; the obsolete showOutOfCombat field is ignored.

The meter reveals away from the target with a 250 ms fade/size animation.
The default right-side dock opens left-to-right. Custom placements infer left/right/
up/down from their position relative to the target, holding the near edge in place. Combat end starts a configurable 0-60 second grace period (default 10),
then the same animation closes it in reverse. Re-entering combat reverses an
unfinished close. The last meaningful combat snapshot is frozen during the grace period and closing
animation, including when the kill clears live threat data. Clearing the target hides
the meter immediately. Target changes discard the snapshot; a new fight starts fresh. Previews bypass combat visibility.

A new profile defaults to compact: rank and scaled percentage, with a matching thin
strip. Hover shows the target's full name, explicit aggro holder if known, your
summary, up to five ranking rows, the percentage definition and a click hint.
Clicking expands; the silver chevron collapses. These clicks save the view.
Automatic combat expansion remains an explicit option, retaining existing per-role
settings. Existing explicit expansion settings select Automatic until a view is chosen.

Both views now dock eight UI units to the RIGHT of the target's outer visual edge,
beyond the portrait, aligned with the health/name row. Native anchoring follows
layout movement; portrait and row-size changes update alignment. Cast-bar visibility
and target-of-target visibility do not shift the dock. Existing saved positions are
preserved; Reset applies this new placement. No coordinate polling is used.
The expanded panel grows up/right and fits its rows (24 units per row, 26-unit header,
6-unit lower padding), scrolling above eight rows by default. The upper-left resize
grip sets width and row limit. Native screen clamping is requested for both views
and the hover panel; actual edge behavior still needs in-game inspection.

Old compact/expanded custom placements stay independent until Reset or a new drag.
Reset applies the new target anchor. Compact and expanded views now save independent bottom-left positions. Dragging
one never moves the other; an old shared save remains the fallback until each view
is moved. Both live and preview views are movable outside combat. Resize width and row limit persist separately. Preview allows placement
out of combat. The component uses LibGlass Pearl, with the unit-frame font, a neutral
dark backing, subdued class fills, a pale local-player edge and explicit holder marker.

Semantics are unchanged: rank is descending raw threat, including pets; percentage
is UnitDetailedThreatSituation's scaled progress toward pulling aggro, NOT percentage
of the leader. Text preserves values above 100; graphical fills clamp to 0-100.
The `isTanking` return marks holders, independently of rank/status. Missing data shows
a dash, distinct from a genuine zero. Unknown raw threat disables ranks and keeps
roster order. Secret percentages/names go only to native widgets; Lua does not compare
them or use them for sounds. Full names use GetUnitName, as the unit frames do.
Non-tanks warn at 90%, rearming below 85%; tanks use the existing threat-lead state.
The optional Boxing Arena Gong defaults on, requires group combat, and has a five-second
cooldown. Preview never sounds.

Useful commands after /reload:
- /glass threat view compact|expanded|auto
- /glass threat delay 10
- /glass threat preview compact|expanded|off
- /glass threat reset
- /glass threat on|off|always (always now includes solo combat)
- /glass threat sound on|off
- /glass threat test

Stop the separate diagnostic preview with /fp threat preview off before testing.

Offline tests cover two-row and raid panels, pets, full/long names, explicit holder
versus rank one, nil/zero/secret values, target switch/death/clear, hover enter/leave,
click while hovering, configuration restoration, old/custom/reset placement,
target-of-target clearance, native target attachment, grace periods, reversing
animations, settings and native method availability. Screen clamping requests and
frame reuse are asserted. These are mocked tests, not visual in-game validation.

The captures below establish outdoor party data on build 70532. Redesigned appearance,
actual screen-edge positioning, layout glides, reload persistence, animation timing,
dungeon/raid restrictions and role warning behavior remain in-game acceptance checks.

## Original probe milestone

Milestone 1 is a development-only experiment in `Tools/ThreatProbe`, excluded
from release packages. It measures the current client and previews the proposed
layout. It does not enable a production threat meter, alerts, or combat expansion.

## Agreed behavior for the live feature

- **Enabled by default**, with an explicit Off setting. Permanent display is opt-in.
- Normal operation is party/raid only: compact between pulls, expanding during
  combat with per-role control consistent with GUF's combat zoom.
- Compact shows your raw-threat rank and scaled percentage to pull, for example
  `#3 · 82%`. Rank includes pets separately. A restricted rank is `#—`, never a
  guessed position. The percentage can remain available independently.
- Placement feedback (2026-10-22): prefer compact **left of the player frame**.
  The below-pet prototype overlaps the hunter pet action bar. Keep an independent
  position override; final placement is deferred until live access.
- Expanded replaces compact. It belongs below the player, between chat and action
  bars. The owner will shorten chat manually to make room.
- The owner's TBC screenshot is the expanded-placement reference: TinyThreat is
  directly below the player/pet/pet-action-bar stack, immediately right of chat
  and left of the main action bars. Use that arrangement, not screenshot pixel
  coordinates, when tuning the Forever layout.
- Compact must change colour with threat. Add an optional warning sound,
  **enabled by default**, when approaching aggro; the intended sound is
  **Boxing Arena Gong**, as shown in the owner's settings screenshot. Do not play
  it continuously on each update. Exact colour bands and rearming behavior remain
  decisions for the live implementation, informed by available threat data.
- Always keeps expanded visible outside combat and when solo; an unsuitable
  target or absent data produces an empty state.

These are requirements for the next milestone, not settings implemented by this
probe. The probe addon loads normally, but samples, tracing and native rendering
are opt-in every session. They never resume from saved variables.

## Install and commands

With GUF installed, deploy the development probes and their existing host:

```powershell
pwsh Tools/deploy.ps1 -ProbeOnly
```

The default destination is the Forever beta AddOns directory. Use `-AddOnsPath`
for another installation. This deploys ForeverProbe and all GUF probe modules;
it does not deploy GUF itself in `-ProbeOnly` mode. Enable ThreatProbe,
ForeverProbe and GlassUnitFrames in the client, then reload. GlassUI is optional.

| Command | Purpose |
|---|---|
| `/fp threat scan` | Snapshot build/context, four threat APIs, policies and victim identity |
| `/fp threat watch on` / `off` | Event-triggered snapshots, at most four per second |
| `/fp threat render on` / `off` | Live native-rendering experiment in roster order, without ranking |
| `/fp threat preview compact` / `expanded` / `off` | Show or close deterministic samples |
| `/fp threat scenario party` / `raid` / `restricted` / `empty` | Five rows, forty rows, unranked, or empty samples |
| `/fp threat reset` | Forget only prototype placement and dimensions |
| `/fp threat clear` | Clear the saved diagnostic log |

Drag either preview to place it; use the expanded window's bottom-right handle
to resize. Mouse-wheel or drag the scrollbar to inspect raid rows. The header
button minimizes the body. Expanded starts at 300 × 180 UI units with 24-unit rows,
a 32-unit header, and Blizzard's 200–600 width / 120–400 height limits.

Samples close on entering combat or a loading screen and cannot start in combat.
Diagnostic rendering is explicitly allowed in combat and ends on a world
transition or `render off`. Starting a sample ends diagnostic rendering.
`watch off` stops tracing independently. Output goes to ForeverProbe's console
and `ThreatProbeDB.log` (maximum 4,000 sanitized lines), never to chat.
`ThreatProbeDB.compact` and `.expanded` hold prototype geometry only. No GUF,
GlassUI, chat, action-bar, or damage-meter saved settings are changed.

## In-game acceptance checklist

1. **Appearance:** open the actual GlassUI-skinned damage meter beside
   `/fp threat preview expanded`. Match size and compare glass, header, title
   accent, row artwork, fonts, minimize control and resize handle. Try Clear,
   Smoked, Class and accent changes. Repeat without GlassUI. This preview uses
   Blizzard's artwork and public Suite appearance APIs, not the damage meter's
   session-window mixin or private GlassUI skin methods.
2. **Placement:** try compact without a pet, with a pet, with a docked pet cast,
   and with a detached cast. Confirm it clears the stack; drag it to test an
   override. Reset should restore docking. Reposition/resize expanded, reload,
   reopen it, and confirm geometry survives while all experiments stay stopped.
3. **Samples:** check party, raid scrolling, restricted and empty scenarios.
   Restricted has no ranks; compact retains a sample percentage. Combat must hide
   samples immediately. Sample data must never appear as live threat.
4. **Solo:** target an enemy outdoors and scan before/during/after combat, with
   and without a pet. Enable rendering to check percentage fills and text.
5. **Party:** repeat with a tank outdoors and in a dungeon. Start a short watch,
   allow aggro to change, change targets, then stop watching. Compare player,
   party and pet results. Compare `target` and `targettargettarget` only when
   `sameAsTarget=true` is plain.
6. **Raid, when available:** repeat, including the player's `raidN` alias. Scan
   intentionally includes aliases; rendering excludes a player alias only when
   `UnitIsUnit` establishes it plainly. Unknown identity can therefore produce
   duplicate diagnostic rows, not an invented rank.
7. **Native rendering:** record SetValue, SetFormattedText, GetThreatStatusColor
   and SetStatusBarColor outcomes separately. A successful call still needs
   visual confirmation. Nil/error reads must clear old values; target and roster
   changes clear old diagnostic values immediately.

Use short watch captures: a full raid snapshot is large and the bounded log
retains the most recent lines. Send the saved log and preview screenshots,
including build, group type and outdoor/instance context. Do not infer group
support from a successful solo test.

## Evidence and next milestone gate

### Owner feedback, build 1.60.1.70532 (2026-10-22)

- Screenshots confirm expanded party samples and the compact `#3 · 82%` readout
  render in the client. The owner reports completing the other checks, but the
  supplied log contains only one scan: party, outdoors, out of combat, no target.
- That scan returns nil from all four threat APIs for player, pet and party1.
  Both secrecy policies are false for `target` and true for
  `targettargettarget`. Neither token identifies an existing target; this is
  empty-state evidence, not proof of readable or restricted combat values.
- That initial extract contained no watch snapshots or rendering outcomes.
  Subsequent captures from both accounts establish the results below.
- Positioning will be revisited when the game is live. The beta compact placement
  overlaps hunter pet buttons; the TBC screenshot provides the intended expanded
  arrangement described above. No runtime placement change is made in this pass.

### Party combat captures, build 1.60.1.70532 (2026-10-22)

The original saved logs are preserved as data, not executable addon code:
[first fight](threat-70532-party-first.log),
[multiple participants](threat-70532-party-multi.log). Both are outdoor party
captures (`inside=false`, `type=none`), not dungeon or raid tests.

- First fight, snapshots 14–15, session #486: player on `target` has plain
  `tanking=true`, `status=3`, `scaled=100`, `rawPct=255`, and raw threat 108 then
  109. Pet/party entries remain nil. All four player rendering operations succeed.
- Multiple participants, snapshots 19–20, session #342: the same `target` returns
  plain detailed values for player, party1 and partypet1:

  | Unit | Raw threat (19 → 20) | Scaled percentage (19 → 20) | Tanking |
  |---|---|---|---|
  | player | 0 → 0 | 0 → 0 | false |
  | party1 | 192 → 192 | 100 → 100 | true |
  | partypet1 | 94 → 112 | 43.63636 → 52.72727 | false |

- `party2` has no detailed threat entry. `SetValue`, `SetFormattedText`,
  `GetThreatStatusColor` and `SetStatusBarColor` report success for player,
  party1 and partypet1. These logs prove accepted native calls, not visual
  inspection of the live diagnostic rows.
- **Token choice matters:** `targettargettarget` is confirmed to identify the
  same mob (`sameAsTarget=true`), yet its populated detailed entries are secret.
  Both policy queries are false for `target` and true for the chained token.
  Diagnostic rendering reads only `target`, so secret-value rendering remains
  untested; do not count these successful plain-value calls as that proof.
- Earlier transition snapshots include `tanking=false`, `status=3`,
  `scaled=231.81817626953`, `rawPct=255`, `rawThreat=0` for player. Do not infer
  tanking from status alone, assume percentages are bounded by 100, or derive
  raw threat from a percentage. Preserve API fields independently. The cause of
  these transitional combinations is not established by the log.
- A ranking by the API's raw threat is feasible in the tested conditions:
  party1, then partypet1, then player. General dungeon/raid availability and the
  approaching-aggro threshold still need validation. No more beta testing is
  required to retain this evidence and proceed with a guarded implementation.

### Blizzard progressive aggro reference

The local `wow-ui-source` forever branch wires
`Enum.NamePlateThreatDisplay.Progressive` to `displayAggroHighlight` in
`Blizzard_NamePlateUnitFrame.lua:UpdateThreatDisplay`.
`Blizzard_UnitFrame/Shared/CompactUnitFrame.lua:GetAggroHighlightThreatSituation`
uses `UnitThreatSituation("player", displayedUnit)` for a non-tank and
`UnitThreatLeadSituation("player", displayedUnit)` for an effective tank.
It then chooses an aggro-highlight colour by status. This is role-aware status
feedback, not a separate full-threat-table API or a continuous percentage curve.

Use that distinction for GUF's future warning colours. Blizzard's Lua branches
and table indexing must not be copied onto potentially secret addon values.
Plain status permits ordinary logic; secret status needs a separately validated
native rendering path. Sound still needs a readable trigger and must not fire
merely because a tank correctly holds aggro.

### WeakAura warning reference

The supplied `!WA:2!` export was decoded as data using the installed WeakAuras
LibDeflate and LibSerialize libraries; no aura code was executed. Aura `Aggro`
uses `Threat Situation` on `target`, with scaled `threatpct >= 90`,
`use_threatpct=true`, `use_aggro=true`, and a start sound (`do_sound=true`).

There is a sound discrepancy to preserve:

- The export saves `Interface\\Addons\\WeakAuras\\PowerAurasMedia\\Sounds\\aggro.ogg`,
  registered by WeakAuras as **Aggro**.
- The owner's screenshot selects **Boxing Arena Gong**, which the local
  WeakAuras registration maps to
  `Interface\\AddOns\\WeakAuras\\Media\\Sounds\\BoxingArenaSound.ogg`.

Prefer the screenshot's explicit sound selection for the future setting. The
90% scaled threshold is a useful starting point from the export, not a newly
validated Forever warning threshold. A secret percentage must never be compared
in Lua to decide whether to play a sound. Do not add a WeakAuras dependency or
copy a sound asset into the release without checking its redistribution terms.

### Reference inspection

Source inspection, **not new in-game measurements**:

- ForeverThreat 1.6.11 reads `UnitDetailedThreatSituation` and discards restricted
  values before sorting. Its status-based fallback bar sizes are not measured
  percentages and are not adopted here.
- The supplied TinyThreat reads the same API and compares/sorts numeric results;
  it does not establish current group availability.
- Local ForeverUI has an unsorted native-rendering path. `wow-ui-source` is on
  `forever`; its generated docs mark threat returns as conditionally secret.
- GlassUI keeps Blizzard's row appearance and controls, adds glass body/header
  panels, uses suite body backing (not the opaque window floor), and accents the
  title. No sibling repository changes are needed for this probe.

| Evidence needed | Current result |
|---|---|
| Multiple detailed threat entries in outdoor party combat | Plain values confirmed for player, party1 and partypet1 on `target`; sortable in those samples |
| Native rendering calls with plain percentages/status colours | Successful for all three populated units; live visual confirmation not supplied |
| Secret-value rendering and dungeon/raid restrictions | Pending; same-mob chained token restrictions confirmed |
| Sample rendering at the owner's scale | Confirmed by supplied screenshots; compact overlaps hunter pet buttons; final placement deferred |
| Lua 5.1 syntax and offline behavior | Automated by `tests/test_threatprobe.lua` and `tests/run.ps1` |

After measurement, use ranked display only where comparable raw values are
available for the roster. Otherwise keep rank unavailable and use group-order
bars only if native rendering was confirmed. Live warnings, enabled-by-default/
Off settings, Always mode and actual combat transitions are the next milestone.
No combat-log reconstruction or dependency on ForeverThreat/Details is introduced.

Recommended next prompt: “Use these threat probe results and screenshots to
implement the live threat display for issue 86, enabled by default with Off and
Always options.”
