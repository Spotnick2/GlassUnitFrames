# Changelog

## Unreleased

- **Follow Glass UI's theme.** With Glass UI installed, turn on **Follow Glass UI** for Glass Unit
  Frames there, and after a `/reload` your frames use the suite's Pearl glass. Your own look,
  body, fade and material sliders are kept and come back when you stop following; until then
  they're greyed out and say "set in Glass UI". Your font, cast bar colours and aggro red still
  apply. Without Glass UI, nothing changes.
- Fixed: health and power fills drew solid after their first colour change instead of at their
  fill opacity (the "Bar fill opacity" slider). They're see-through again.
- **See your next 2 seconds of mana regen.** A faint segment just past your mana bar's fill shows
  how much mana the next 2 seconds will give you, so you can tell whether to wait or drink. It
  shrinks to almost nothing during the five-second rule, hides at full mana, and sits on the
  druid mana strip in bear or cat form. It's on by default: turn it off under Options > AddOns >
  Glass Unit Frames > Mana, or with `/glass regen off`. Mana users only.
- **Combat timer over your portrait.** A small glass pill above your portrait opens when a fight
  starts and counts up (00:07), then closes when it ends, still showing how long the fight lasted.
  With your portrait set to none, it sits above the frame instead. Turn it off under Options >
  AddOns > Glass Unit Frames > Combat timer, or with `/glass timer off`.
- **Low mana and health now look low.** The empty part of your health and power bars showed the
  bar's colour fading across the whole bar, so 9% mana looked about half full. That colour is now
  much fainter. A new **Fade** choice (Options > AddOns > Glass Unit Frames > Look, or
  `/glass ramp edge`) puts it just past the fill instead, fading out over a short stretch.
  "Whole bar" stays the default.
- Fixed: opened during a fight right after logging in or reloading, the Cast bars options page
  could show no bars to pick for the rest of the session.
- **See-through glass bars.** Health, power, cast and druid mana bars now let the scene show
  through a little (they draw at 60% opacity), as the glass was always meant to: until now they
  drew fully opaque. Prefer them solid? `/glass fill 1` (or "Bar fill opacity" in the options),
  and the slider now really changes them. This comes with the glass library's update to LibGlass
  r10, which your other glass addons pick up too: the newest copy installed is the one that runs.
- **Preview every frame and bar.** `/glass preview`, or "Preview all frames" in the options, shows
  every frame with sample data, even with no target, focus or pet: the cast bars loop sample casts
  (with the latency block, pushback, the green and red flashes, a channel and a craft count), the
  swing timer runs all three rows, and the five-second line drains. So you can check a colour, a
  size or a spot without setting up the fight that shows it. Your own frame keeps its real numbers.
  It works with unlock mode (a Preview switch on the unlock box), and a fight or a loading screen
  ends it. Out of combat only.
- **The five-second rule on your mana bar.** A thin red line along the bottom of your mana bar
  drains through the 5 seconds after a spell that costs mana, while your spirit regen is paused.
  When it's gone, regen is back. It hides at full mana. As a druid in bear or cat form, it shows
  on the mana strip under your frame. On by default, in combat only; both switches are under
  Options > AddOns > Glass Unit Frames > Five-second rule.
- **Portraits: 3D, 2D or none.** Choose per frame (player, target, pet) under Options > AddOns >
  Glass Unit Frames > Portraits, or `/glass portrait target 2d`.
  - **2D** always shows the flat portrait: lighter, and the same look on every unit.
  - **None** removes the portrait, and the frame narrows to its bar. Changed during a fight, it
    waits until combat ends.
  - The level, PvP and resting icons that sit on the portrait move onto the frame when it's gone.
- **Clear or smoked glass.** Options > AddOns > Glass Unit Frames > Look > Body: **Smoked** (or
  `/glass body smoked`), then `/reload`, for a darker glass behind the bars and text. It works
  with either the Classic or the Clean look. "Reset look to defaults" puts it back to clear.
- **A clean glass look to try.** Options > AddOns > Glass Unit Frames > Look > Glass: **Clean**
  (or `/glass look clean`), then `/reload`. It gives thin square rims, no grain, and softer gloss
  and shading. Classic stays the default.
- **One cast bar for a whole craft batch.** Smelting 50 ores now shows a single bar for the batch,
  counting down to when the last one lands. The estimate corrects itself at every craft. The latency
  block and pushback text are hidden on it. Prefer one bar per craft? Untick "One bar for a whole
  batch" under Options > AddOns > Glass Unit Frames > Cast bars.
- **Craft count on your cast bar.** Making several of something shows **Heavy Linen Bandage
  (3/5)** while it crafts. A single craft shows just its name. The green "complete" flash now
  comes once, at the end of the batch, not between every craft. Turn the count off under Options >
  AddOns > Glass Unit Frames > Cast bars ("Craft count (3/5)").
- **Combat zoom.** Pick bars (your cast bar, target, focus, pet, the swing timer) to move to a
  combat spot and grow while you're in combat. Each glides there when the fight starts and back
  home when it ends.
  - Turn it on per bar, with a combat scale, in Options > AddOns > Glass Unit Frames > **Combat
    zoom**.
  - Unlock the frames to drag each bar's combat spot: the yellow outline.
  - Set this character's role (Healer, Tank or DPS) to give that role its own spots and scales; a
    role starts from the global settings.
- **Swing timer, in glass.** Main hand, off hand and ranged rows, drawn from the game's own swing
  timer.
  - A row shows from its first swing until the fight ends: a caster who never meleed gets none, a
    wand user gets ranged.
  - By default they're thin lines inside your player frame, under the power bar (and under your cast
    bar while you cast).
  - Detach them from Options > AddOns > Glass Unit Frames > **Cast bars** ("Settings for: Swing")
    to get a glass bar of their own you can drag, size and scale. Their row heights are set there
    too.
  - Out of melee or shooting range, a row dims.
  - Colours for each hand are on the same page.
  - **Blizzard's own swing bars** are Blizzard's option (Options > Swing Timer > Enable Swing
    Timer). Untick it to see only the glass ones; the Cast bars page has the same checkbox.
- Fixed: hovering a unit frame now shows the unit's tooltip.
- Fixed: a portrait no longer stays empty for creatures the client has no 3D portrait model for
  (an Earthborer, for one), or for a unit out of range. It shows the 2D portrait instead.
- **Detachable cast bars.** Cast bar options now have their own page: Options > AddOns > Glass
  Unit Frames > **Cast bars**. Detach your own cast bar or your target's, and it becomes a glass
  bar of its own. Its default spot is just under the middle of the screen (340×20), with the
  target's just above it. **Scale** it (0.5–2) and **center it horizontally** from that page.
  Unlock the frames to drag it, type its position, width, height or scale, or click **Center X**
  (also there for every frame). **Attach** puts it back
  on its frame. Detaching and attaching work in combat too. **Reset frame positions** also puts
  detached bars back at their default spot and size.
- **Quartz's look and options for the cast bars** (Options > AddOns > Glass Unit Frames > Cast
  bars):
  - the **spell icon**, on the left of your bar and the right of your target's (or none);
  - **"Spell -> Target"** on your bar;
  - **"remaining / total"** time, with a **precision** slider;
  - a **spark** on the moving edge;
  - a short **green flash** when a cast completes;
  - the latency **ms** inside the red block;
  - **width and height** sliders;
  - **colours** for the spell text, time text, casting, channeling, complete, failed, spark and
    background (the client's colour picker).

  The page now has a "Settings for" row to pick which bar you're setting up.
- **Pet and focus cast bars.** Your pet's casts show in a thin glass bar under the pet frame,
  your focus's in one above the focus frame. Both can be detached, scaled and centred like the
  others.
- Fixed: the **Unlock frames** button in the options no longer causes an "AddOn tried to call the
  protected function SpellStopCasting()" error when the options were opened from the game menu.
- A detached player cast bar shows your **latency in ms** above the end of the bar (it can be
  turned off).
- **Unlock dialog.** While the frames are unlocked, a glass panel at the top of the screen says
  so. It has a **Lock** button and the snap-to-grid, align and mirror switches, which used to sit
  in each frame's small panel. Drag it aside if it covers a frame.
- Your cast bar now shows a red **latency block** at its end: roughly the last part of the cast
  that is too late to cancel, measured from your own key presses (median of your last few
  casts). Channels show it at the end they drain toward.
- Your cast bar shows **pushback** in red before the time: `+0.8` when a hit delays a cast, `-0.5`
  when a hit shortens a channel.
- The red "Interrupted" flash now shows once per cast. Repeated interrupt messages, and spells
  refused before they started, no longer flash it.
- The latency block and the pushback text can each be turned off in Options > AddOns > Glass
  Unit Frames > Cast bar.
- Under the hood: the glass look now comes from LibGlass, a small library shared by the Glass
  addons and included in the download (nothing extra to install). The frames look and behave
  exactly as before; a future fix to the glass reaches every Glass addon you use.
