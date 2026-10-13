# Changelog

## Unreleased

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
