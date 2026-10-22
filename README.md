# Glass Unit Frames

Liquid-glass unit frames for **World of Warcraft: Forever**: your player, pet, target, target of
target (and its target), focus and focus target, in the glass look shared by the Glass addons.
It is a streamlined take on Shadowed Unit Frames: the parts that earn their place, and no party
or raid frames (that's Glass Raid Frames).

> **Alpha.** It's in daily use, but it is young: expect rough edges, and please report them.

![Every frame in glass, in preview mode: the player with its pet below and a combat timer over the portrait, the target with its target and its target's target above it, the focus and focus target higher up, and two detached cast bars](https://raw.githubusercontent.com/Spotnick2/GlassUnitFrames/main/docs/screenshots/frames.png)

## Install

Install **Glass Unit Frames** from CurseForge, with the CurseForge app or by unzipping it into the
`Interface\AddOns` folder inside your Forever game folder. Then `/reload`, or start the game.
Your Blizzard player, pet, target and focus frames are replaced at once; there is nothing to set
up. `/glass options` (or Esc > Options > AddOns > Glass Unit Frames) has every setting.

## What it does

**Seven frames in glass.** Player, pet, target, target of target, target of target of target,
focus and focus target. Each is a rounded glass body with the unit's name and health. The player,
target, pet and focus add a power bar; the player, target and pet a 3D portrait (or 2D, or none,
per frame); the target its level and classification. The target's target's target is just a name
over its health. Clicks work as on Blizzard's frames
(left to target, right for the menu), and hovering shows the unit's tooltip.

**The look.** **Pearl** glass by default, or **Clean** and **Classic**; a clear or **smoked**
body; the empty part of a bar either fading across the whole bar or just past the fill; two
fonts. With **Glass UI** installed you can let it set the glass for every Glass addon at once.

**What the frames show**:
- health and power text in a few fixed formats per frame (current, current/max, percent);
- a red segment for health just lost, and incoming heals on the player, target and focus;
- the target's buffs and debuffs in two rows under it (the game picks and sorts them);
- raid marks, leader and master looter, PvP and resting icons, AFK and your raid group number;
- neutral creatures turn red while they fight you or your group;
- combo points on the target for rogues and cat-form druids, and a thin mana strip under your
  frame for a druid in bear or cat form;
- your hunter pet's happiness.

**Cast bars** for you, your target, your focus and your pet, with Quartz's touches: spell icon,
"Spell -> Target", remaining / total time, a spark, a green flash when a cast lands and a red one
when it fails, pushback (`+0.4`), a craft count (`Heavy Linen Bandage (3/5)`) and one bar for a
whole craft batch. Your own bar shows a red **latency block**: roughly the end of the cast that is
too late to cancel, measured from your own key presses. Each bar can stay docked on its frame or
be **detached** into its own glass bar you can drag, size and scale. Colours for every part are
on the Cast bars options page.

**Combat zoom.** In combat, your cast bar and your target's glide to a spot above your frames and
grow (1.5×), then glide home when the fight ends. Turn it on or off per bar, with your own spot
and scale, on the Combat zoom options page; a Healer, Tank or DPS role can have its own.

![In a fight: the player's cast bar, zoomed, sits above the player and target frames, with its spell icon, "Smite -> Scorpid Worker", the time and the latency in ms](https://raw.githubusercontent.com/Spotnick2/GlassUnitFrames/main/docs/screenshots/combat-zoom.png)

**Your flight on your cast bar.** On a flight master's flight, your cast bar shows "Flight to
Orgrimmar", the flight master's icon and the time left (`~` when it's an estimate, `+0:07` past
it), emptying as you fly, and zoomed like in combat when your cast bar's zoom is on. A cast you
make on the way takes the bar; the flight comes back after it. The game gives no flight times, so
they come from each route's length, then from your own landings (`/glass flight off` to turn it
off).

**For casters and fighters**:
- a **swing timer** (main hand, off hand, ranged) inside your frame, or detached;
- the **five-second rule**: a thin red line on your mana bar while spirit regen is paused;
- your **next 2 seconds of mana regen**, a faint segment just past your mana fill;
- a **combat timer** over your portrait, counting the fight.

**Place everything.** `/glass unlock` (or Unlock frames in the options) shows a handle on every
frame and detached bar. Drag them, or click one to type its position or nudge it with the arrows.
Frames snap to a grid and align to each other's edges (hold Alt to place freely), the target
carries its group and the player its pet, and moving the player or target mirrors the other while
the pair is symmetric. `/glass preview` shows every frame and bar with sample data, so you can
place and colour things without a target, a pet or a fight.

**With the other Glass addons**:
- When **Glass Raid Frames** shows its centred raid layout, your frame and your target's slide
  to sit just left and right of the raid grid, at their own height, and come back when it goes
  away (`/glass link off` to keep them where you put them). Your cast bars stay where you put
  them; if the grid would cover them, they're lifted just clear of it.
- **Glass Action Bars'** stance and pet bars follow your player and pet frames.
- **Glass Panel's** flight timer and your cast bar share the same flight times (below).
- Click-casting addons that use Clique's convention (Clique, Glass Raid Frames) bind the frames.

## Commands

`/glass help` lists them all; the same settings are on the options page.

- `/glass options` - the options page
- `/glass unlock`, `/glass lock` - move the frames and bars
- `/glass preview` - every frame and bar with sample data (out of combat)
- `/glass reset` - every frame and bar back to the default layout
- `/glass look pearl|clean|classic`, `/glass body clear|smoked` - the glass (after a `/reload`)
- `/glass ramp whole|edge` - how the empty part of a bar shows
- `/glass font arial|friz`
- `/glass portrait player|target|pet 3d|2d|none`
- `/glass text <unit> curhp|curmaxhp|perhp|curmaxhp_perhp` - a frame's health text
- `/glass level power|name|portrait`, `/glass mark name|top|right`,
  `/glass happiness left|right|under` - where the target's level, raid marks and pet happiness go
- `/glass timer on|off`, `/glass regen on|off` - the combat timer and the mana regen segment
- `/glass flight on|off` - a taxi flight on your cast bar
- `/glass link on|off` - the frames beside Glass Raid Frames' layout
- `/glass mirror on|off`, `/glass snap grid|align on|off` - unlock mode's mirroring and snapping
- `/glass blizzard show|hide` - Blizzard's own frames back, or hidden again (after a `/reload`)

## Good to know

- **No party or raid frames.** Glass Raid Frames does those. Blizzard's party frames are left
  alone.
- **The glass is painted, not real.** The game gives addons no blur, so the glass is built from
  layered textures: it doesn't blur what's behind it.
- **The numbers stay the game's.** Forever hides many unit values from addons (health, power, cast
  times...): the frames hand them straight to the game to draw. That's why the text comes in a few
  fixed formats rather than a custom tag language, and why there are no aura filters: the game
  chooses and sorts the target's buffs and debuffs.
- **Some changes wait for combat to end:** moving frames, a portrait set to none, `/glass reset`.
  The game doesn't let addons move these frames in combat. You're told when one is waiting.
- **Shaman totems** don't show while Blizzard's frames are hidden. The game hides totem details
  from addons, so Glass Unit Frames can't draw them.
- **Not yet checked in game:** the combo points and the druid mana strip are built and tested
  offline only. Reports welcome.

## Bugs and ideas

Open an issue on [GitHub](https://github.com/Spotnick2/GlassUnitFrames/issues). With
`/console scriptErrors 1` on, the error text helps a lot; `/glass secrets` lists anything the
frames failed to draw.

## Credits

- The design follows [Shadowed Unit Frames](https://github.com/Nevcairiel/ShadowedUnitFrames) and
  its Forever port, DinoUnitFrames; the cast bars follow Quartz. No code is copied from them.
- The glass comes from [LibGlass-1.0](https://github.com/Spotnick2/LibGlass), and the flight times
  from [LibTaxiTime-1.0](https://github.com/Spotnick2/LibTaxiTime), both included in the download.
  The flight times were checked against InFlight's measured Classic times.

## Development

Lua 5.1, no build step. The tests run with a plain Lua 5.1 and checkouts of LibGlass and
LibTaxiTime next to this one (`..\LibGlass` and `..\LibTaxiTime`, or `$env:LIBGLASS` and
`$env:LIBTAXITIME`):

```powershell
pwsh tests\run.ps1        # syntax check plus every tests\test_*.lua
pwsh Tools\deploy.ps1     # the addon and its LibGlass into your AddOns folder
```

## Licence

MIT; see [LICENSE](LICENSE). LibGlass-1.0, LibTaxiTime-1.0 and LibStub ship under their own terms (listed there).
