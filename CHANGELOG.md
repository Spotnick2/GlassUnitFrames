# Changelog

## v1.1.0 - 2026-11-12

- **Will my DoTs kill it?** On your target's and focus's health bars, a striped red marker shows
  how much health your own damage-over-time spells will still take, with a thin line for each
  tick to come. When the marker covers the whole bar, a skull appears on the portrait (beside the
  frame without one): your DoTs will finish it on their own. The skull waits until it has seen
  one of your DoTs tick.
  - **The spells:** Corruption, Bane of Agony, Immolate, Siphon Life, Shadow Word: Pain,
    Devouring Plague, Holy Fire, Moonfire, Insect Swarm, Rip, Rake, Pounce, Rend, Rupture, Garrote,
    Serpent Sting and Flame Shock.
  - **It's an estimate, and it leans low:** talents, crits and debuffs on the mob aren't counted,
    a missed or resisted cast is dropped, and a cast whose mob it can't be sure of isn't counted.
  - **The skull can still come too early:** a heal, a shield or a dispel can save the mob; a
    partial resist or a damage reduction makes the ticks smaller than the spell's formula; spell
    power that drops mid-fight (a trinket or proc ending) makes later casts count high; and another
    player's hit can pass for your DoT's tick, since the game doesn't say whose damage it was.
  - **Settings:** a new DoTs page under Options > AddOns > Glass Unit Frames turns each part on or
    off (the marker, the tick lines, the skull, the focus frame), or use `/glass dots on|off`.

## v1.0.0 - 2026-11-07

The first release out of beta.

- **Absorb shields on the health bar.** On your frame, your target's and your focus's, a Power
  Word: Shield (or any absorb) shows as a darker shade of the health colour just past the health
  fill, after any incoming heal. It shrinks as the shield soaks damage and goes when it breaks.
  Near full health only the missing part shows, and at full health there's no room for it. Turn
  it off under Colours on the options page ("Absorb shields on the health bars") or with
  `/glass absorb off`.

## v1.0.0-beta1 - 2026-11-03

The first beta. Glass Unit Frames now also ships on Wago and as a GitHub release, next to
CurseForge.

- **Global cooldown line.** A thin line along the top of your power bar (or along the bottom of
  your cast bar when it's detached) runs down the global cooldown after each spell. Turn it off
  on the main Options > AddOns > Glass Unit Frames page (not its Cast bars page), in the Cast bars
  section: "Global cooldown line on your cast bar".
- **Who interrupted it.** When a cast is kicked, the bar says "Interrupted by <name>" when the game
  tells us who it was, and plain "Interrupted" otherwise.
- **Out of range.** Your cast bar turns grey while the target or focus you're casting on is out
  of the spell's range, and back to its colour when you're in range again. Turn it off with "Grey
  your cast bar out of range", next to the GCD line option.
- **Glass breath, fatigue and feign death bars** replace Blizzard's, near the top of the screen,
  with the time left. Move and resize them in unlock mode. Turn them off under Combat timer
  ("Glass breath and fatigue bars") or with `/glass breath off`.
- **Crowd-control icon** for your target and focus, off by default: a stun, fear or root with its
  timer, picked by the game, over the portrait or beside it. Choose it under Crowd control
  icon on the options page, or with `/glass cc target portrait` (`focus`, `beside`, `off`).

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
- **Cast bars** for you, your target, focus and pet, with these touches: spell icon, "Spell ->
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
