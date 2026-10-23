# Changelog

## v0.1.0-alpha2 - 2026-10-22

- **Target threat**, enabled by default in group combat. A Pearl plate beside the target shows
  your rank and progress toward pulling aggro, with a thin matching fill. Hover for details;
  click for a ranking of players and pets, sized to its contents. The actual aggro holder is
  marked independently of rank. Both views default to an anchor eight units right of the target's
  outer edge, beyond its portrait, aligned with the health/name row. Expanded grows upward.
  Dragging compact or expanded saves its position independently. Cast-bar visibility does not shift this dock; existing custom positions stay until reset.
  Non-tank colors progress smoothly from mint through amber at the existing 90% warning point
  to coral at 100%; tank lead colors are unchanged.
  Combat opens the meter with a 250 ms reveal away from the target (left-to-right at the default side dock); it closes in reverse after a configurable delay
  (10 seconds by default).
  The last combat values remain visible during that delay and closing animation. Clearing
  the target hides the meter immediately; changing targets discards the saved combat values.
  Options include solo combat, Off, saved compact/expanded views, automatic per-role expansion,
  previews, and the optional Boxing Arena Gong (on by default).
  Restricted data stays unranked. Outdoor party data, the redesigned UI, and the gong were checked
  in game; dungeon and raid behavior still need validation.

- **Your flight on your cast bar.** On a flight master's flight, your cast bar shows "Flight to
  Orgrimmar", the flight master's icon and the time left (`~` when it's an estimate, `+0:07` once
  it runs past it). It empties as you fly, steps aside for a cast you make on the way, and zooms
  like in combat when your cast bar's combat zoom is on. The game gives no flight times, so they
  come from each route's length (checked against InFlight's measured Classic times), then from
  your own landings, shared with Glass Panel's flight timer if you use it. Turn it off under
  Options > AddOns > Glass Unit Frames > Combat timer, or with `/glass flight off`.

## v0.1.0-alpha1 - 2026-10-21

The first alpha. Glass Unit Frames replaces Blizzard's player, pet, target, target of target,
focus and focus target frames with liquid-glass ones (plus your target's target's target).

- **Seven glass frames**: name and health on all of them, power on the player, target, pet and
  focus, and 3D, 2D or no portraits on the player, target and pet. Also health and power text in a
  few formats, a red segment for health just lost, incoming heals, the target's buffs and debuffs,
  raid marks, leader, PvP, resting and AFK, combo points for rogues and cat druids, a mana strip
  for druids in bear or cat form, and your hunter pet's happiness. Neutral creatures turn red
  while they fight you.
- **Pearl glass** by default, or Clean and Classic, with a clear or smoked body (Options > AddOns
  > Glass Unit Frames > Look). With Glass UI installed, it can set the glass for all your Glass
  addons.
- **Cast bars** for you, your target, focus and pet, in Quartz's style: spell icon, "Spell ->
  Target", remaining / total time, spark, complete and interrupt flashes, pushback, a latency
  block on your own bar, and a craft count with one bar for a whole batch. Dock them on their
  frames or detach, drag, size, scale and colour them (the Cast bars options page).
- **Combat zoom:** in a fight, your cast bar and your target's glide above your frames and grow,
  then go home after. On by default; per bar, with per-role spots, on the Combat zoom page.
- **Swing timer, five-second rule, mana regen and a combat timer** for your own frame.
- **Unlock mode and preview:** `/glass unlock` to drag, nudge, snap, align and mirror frames and
  bars; `/glass preview` to see everything with sample data.
- **With Glass Raid Frames' centred layout**, your frame and your target's sit beside the raid
  grid, and your cast bars are lifted clear of it if they'd overlap. `/glass link off` keeps them
  where you put them.
- Blizzard's own player cast bar is hidden by default ("Hide Blizzard's player cast bar" in the
  options).
