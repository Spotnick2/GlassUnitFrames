# Changelog

## Unreleased

- Your cast bar now shows a red **latency block** at its end: roughly the last part of the cast
  that is too late to cancel, measured from your own key presses (median of your last few
  casts). Channels show it at the end they drain toward.
- Your cast bar shows **pushback** in red before the time: `+0.8` when a hit delays a cast, `-0.5`
  when a hit shortens a channel.
- The red "Interrupted" flash now shows once per cast. Repeated interrupt messages, and spells
  refused before they started, no longer flash it.
- All three can be turned off in Options > AddOns > Glass Unit Frames > Cast bar.
- Under the hood: the glass look now comes from LibGlass, a small library shared by the Glass
  addons and included in the download (nothing extra to install). The frames look and behave
  exactly as before; a future fix to the glass reaches every Glass addon you use.
