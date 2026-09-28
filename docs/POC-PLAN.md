# Liquid Glass proof of concept: plan

> **Historical.** The POC is answered: yes, convincing liquid-glass unit frames are possible with
> layered textures (no live backdrop blur), at acceptable cost. GlassUnitFrames is now a working
> addon; see CLAUDE.md's Status, `docs/GLASS-MATERIAL.md` for the material as built, and
> `docs/FOREVER-PROBE.md` for the measurements. This plan is kept for its reasoning.

_Revised after a Codex adversarial review on 2026-09-27. Changes: the capture candidates, mask
caveats, probe coverage, the test stub's limits, and deferring Blizzard frame hiding._

**What the POC answers:** can a WoW: Forever addon draw unit frames that convincingly read as
Apple-style "liquid glass" (the mockup in `docs/mockup.png`), at acceptable cost, on client
1.60.1.70009? The secondary question is what the smallest useful core in the style of Shadowed
Unit Frames looks like.

A POC can be rough in features but not in correctness. Secret values, secure frames and combat
lockdown are handled properly from day one, because retrofitting them is the expensive part.

## 1. What is and isn't possible

Real liquid glass is a **backdrop effect**. It blurs and refracts whatever is drawn *behind*
the element, live. A WoW addon has no shader access, and no API binds the rendered scene to a
texture live.

| Effect in the mockup | Achievable? | How |
|---|---|---|
| Blur / refraction of the world behind the frame | **No** (expected, not proven) | Candidates are one-shot at best: `OffScreenFrame` snapshots (declared, contents unknown) and the screenshot-preview setters `C_PhotoSharing.SetScreenshotPreviewTexture` / `C_ReportSystem` (tied to Blizzard flows). Probe 2 checks them, time-boxed. |
| Translucent tinted body with the world visible through it | Yes | A dark or cool tint texture at ~30–45% alpha. This is most of the "glass" read. |
| Thick bevelled rim with a specular edge (bright top-left, dim bottom-right) | Yes | A pre-rendered 32-bit TGA, 9-sliced with `Texture:SetTextureSliceMargins` so it scales to any frame size. |
| Rounded corners on the body and bar fills | Yes, with a caveat | `MaskTexture` (`CreateMaskTexture` / `AddMaskTexture`) on the body and on each `StatusBar:GetStatusBarTexture()`. A fixed mask rounds only the bar's *outer* outline; the moving fill edge stays square, as in the mockup. A stretched mask distorts corner radii, so size masks per aspect ratio. |
| Glossy highlight band on bars, inner shadow | Yes | Gradient textures and pre-rendered overlays, with `SetBlendMode("ADD")` for highlights. `SetGradient(orientation, minColor, maxColor)` takes **color objects** on this API, not numeric RGBA. |
| Soft outer drop shadow | Yes | A 9-sliced shadow TGA outside the frame. |
| Faint frosted grain | Approximated | A static noise texture at low alpha. It doesn't track the background. |
| "Liquid" motion (a sheen sliding across on change) | Yes | An `AnimationGroup` with Translation + Alpha on a masked specular streak. The mask stays anchored to the frame, and events trigger it, not a per-frame `OnUpdate`. |
| Portrait in a glass tile | Yes | 3D `PlayerModel:SetUnit` with portrait zoom, or 2D `SetPortraitTexture`. The mockup's painted art isn't reachable; a live model is. |
| Numbers "1.24k \| 80%", cast timer | Yes, secret-safe | `SetFormattedText` / `AbbreviateNumbers` / `UnitHealthPercent` with a curve for text; `UnitCastingDuration` + `StatusBar:SetTimerDuration` for the cast bar. |

My hypothesis before building, which is an artistic guess rather than a measurement: **most
of the mockup is reachable**, and the missing part is true background blur and refraction. The
POC exists to check that with real pixels, and to judge whether the faked version still reads
as glass over busy zones (Elwynn grass, snow, dark caves).

## 2. Probes first (a throwaway `Tools/GlassProbe` addon)

Each probe answers a yes/no question before the design depends on it. Results go to
`docs/FOREVER-PROBE.md`, with the build number.

1. **One representative glass frame, early.** It combines:
   - the 9-sliced rim and the masked body;
   - a masked StatusBar fill shown empty, tiny, half and full;
   - the ADD gloss, the gradient, and the **animated masked sheen**.

   Place it over busy scenery (bright grass, snow, a dark cave), at the owner's UI scale and at
   a fractional one. A visual failure here ends the POC cheaply, which is why it comes before
   any engine work. Also check:
   - halos from the alpha export (straight vs premultiplied alpha, RGB at transparent edges);
   - pixel snapping on thin rims;
   - whether **new** texture files load after `/reload` or need a full client restart.
     Historically, new files need a restart and changed files don't.
2. **Scene capture, time-boxed to one sitting.** Does `OffScreenFrame`'s `TakeSnapshot` /
   `ApplySnapshot` capture anything beyond its own children? Do the screenshot-preview setters
   work from addon code at all? I expect UI-only captures, or protected calls. If something
   does capture the scene, that becomes a separate spike, not part of this POC.
3. **`SecureUnitButtonTemplate` + `RegisterUnitWatch`** on player, target, pet and
   targettarget. Frames should show and hide with their unit; left-click targets and
   right-click opens the menu. Include acquiring and losing a target **during combat**, and
   summoning and dismissing a pet. Both reference addons ship this pattern; this probe confirms
   it ourselves.
4. **Secret values end to end.** Out of combat and in combat, on player, target and an enemy:
   - Which of `UnitHealth`, `UnitHealthMax`, `UnitPower`, `UnitPowerMax` come back secret
     (`issecretvalue`)?
   - Do `StatusBar:SetMinMaxValues` / `SetValue`, `UnitHealthPercent(unit, true, curve)`,
     `AbbreviateNumbers`, `SetFormattedText` and `string.format` accept them?
   - Does the full cast path work: `UnitCastingDuration` / `UnitChannelDuration` →
     `SetTimerDuration`, the timer text, an interrupt, and switching target mid-cast?
5. **Cost, a quick sanity check.** Compare FPS with 5 glass frames (portraits included), sheen
   on and off, against Blizzard's frames. `debugprofilestop` measures only Lua painter time, not
   GPU compositing or native animation cost. This is not a benchmarking exercise.

## 3. The POC addon itself

**Units:** player, pet, target and targettarget, with a cast bar on target and player. No party
or raid frames and no auras in the first cut. A target aura row via
`CustomAuraContainerTemplate` is a stretch goal.

**Layers per frame, bottom to top:** drop shadow → glass body (tint + grain, masked) → health
bar (masked fill + gloss + inner shadow) → power bar (same) → specular sheen (masked, animated)
→ rim (9-slice) → text. The portrait is a separate glass tile with the same rim.

**Architecture (the seed of the streamlined SUF):**

- **`Compat.lua`:** the namespace adapter (`GlassUF.API`) and an event-registration wrapper that
  reports rejected events.
- **`Engine.lua`:** EllesmereUI-style event routing.
  - One tracker per unit token, via `RegisterUnitEvent`.
  - Events grouped into channels (`health`, `power`, `name`, `cast`, `portrait`), with one
    painter per channel.
  - Same-frame dedupe of dirty **channels**, never by comparing values, which may be secret.
  - A shared 0.5 s ticker for `targettarget`, running only while it's shown.
  - A full repaint of every channel on `PLAYER_TARGET_CHANGED`, `UNIT_PET` and `OnShow`.
  - The sheen triggers on the event, never by comparing old and new health.
- **`Glass.lua`:** the material. It builds the layer stack on any frame from a style table
  (tint, rim, radius, gloss strength). All textures live in `Media/`.
- **`Frames.lua`:** creates the secure unit buttons from a layout table, applies `Glass` and
  binds the painters. The layout is a hardcoded Lua table: no options UI, no AceDB.
- **`GlassUnitFrames.lua`:** bootstrap and the `/glass` slash command:
  - `test`: fake values, so frames show without a target;
  - `layers <name>`: toggle one layer for A/B comparison;
  - `reset`.

  Anything that touches the secure frames or their ancestors is refused in combat and queued
  for `PLAYER_REGEN_ENABLED`.
- **Blizzard's player and target frames stay visible** in the POC. Hiding them is where taint
  starts, and both references need several steps to do it safely:
  - DinoUF unregisters UnitWatch and events, hides, reparents, and adds an out-of-combat
    `OnShow` hook.
  - EllesmereUI defers the reparenting until Edit Mode and combat are over.

  This is deferred to the real addon, and will be tested against Edit Mode enter/exit then.

**Assets:** generated reproducibly by `Tools/make_textures.py` (Pillow + numpy): rim, shadow,
mask, gloss, grain and sheen, as uncompressed 32-bit TGAs in power-of-two sizes. The generator
is the source; the TGAs are committed outputs.

**Tests:** a Priestly-style Lua 5.1 harness.
- The stub models secrets as `newproxy(true)` userdata whose metamethods error. That makes
  **arithmetic, ordering, `tostring`, concatenation and `string.format`** throw, verified in
  Lua 5.1.
- **Lua 5.1 cannot make truth tests or `==` throw**, so the stub can't catch `if secret then` or
  `secret == x`. Only the in-game combat probe and code review catch those.
- Tests also run every handler.
- Visual correctness is judged in game, from screenshots.

## 4. Deliverables and exit criteria

- Probe results written up, with each §2 question answered yes or no, plus the build number.
- Side-by-side screenshots of the mockup and the in-game version over three backgrounds (bright
  grass, snow, dark).
- A verdict: *glass reads convincingly*, *reads as "glossy dark UI"*, or *not worth it*, plus a
  rough cost figure.
- If the verdict is yes: an inventory of SUF features (a Fable-assisted read of upstream SUF and
  DinoUF) and the owner's list of what the real addon keeps.

## 5. Out of scope for the POC

Options UI, profiles, party and raid headers, auras (beyond the stretch goal), a tags DSL, range
fading, combo points and class resources, localisation, packaging and CurseForge.
