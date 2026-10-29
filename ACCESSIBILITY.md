# Accessibility

Sysbar should be usable by everyone who uses a Mac, including people who use VoiceOver, the
keyboard instead of a pointer, or the display settings in System Settings › Accessibility. This
page says what works today, what does not yet, and how to tell us about a barrier.

The aim is [WCAG 2.2](https://www.w3.org/TR/WCAG22/) level AA, applied to a native macOS app, and
Apple's accessibility guidelines.

## Supported environments

- macOS 14 Sonoma or later, on Apple silicon
- VoiceOver and Voice Control
- Full Keyboard Access
- Reduce Motion, Differentiate Without Color and Reduce Transparency
- All 13 languages Sysbar is translated into; VoiceOver reads them in the language you choose

## What works

- **The menu bar item** is named "Sysbar" for VoiceOver, and its value is the readings shown, such
  as "CPU 23% · RAM 10.6G". The same text is its tooltip.
- **Settings** names every switch, menu, slider and stepper after its row, such as "Launch at login,
  switch". Page and group titles are headings, so VoiceOver's heading rotor moves between them. The
  sidebar is a standard list and works with the arrow keys.
- **Popover cards** are read as one item each: the metric, then its value in words, such as "Disk,
  read 1.2 MB per second, write 300 KB per second". Each top app is read as one row, such as
  "Safari, CPU 12%, Memory 340M", and the sorted column is marked as selected.
- **Colour is never the only signal.** Load is shown by the number and the bar height as well as
  its colour, and the two lines of a network or disk graph differ in weight and side, not only in
  hue. A device's status dot is spoken as Connected, Not reachable or Checking, and with
  Differentiate Without Color on it draws a different symbol for each.
- **Reduce Motion** stops the counting animation of values, the glide and pulse of the menu bar
  item, the pulse of a live device's dot, the launch animation and the press effects.
- **Announcements**: VoiceOver hears the result of checking a device or testing a connection, and
  when a command or text has been copied.
- **Keyboard**: every control is a standard button, menu, switch or slider. Reordering metrics,
  besides dragging, is offered as Move up and Move down in each row's menu and as VoiceOver
  actions. Text fields support the usual ⌘C, ⌘V, ⌘A and ⌘Z, and ⌘W closes the settings window.
- **Disclosures**, such as the connection guide and an update's What's new, say whether they are
  expanded or collapsed.

## Known limitations

These are known and planned; reports about any of them still help us decide what comes first.

- Some details appear only as a tooltip on hover: peak values, memory pressure, the power
  breakdown, each fan's speed, and an app's download and upload split (the table's Network column
  shows their sum). VoiceOver reads them, but a sighted keyboard user cannot see them.
- Moving a metric with the keyboard needs its row's menu, which Full Keyboard Access cannot always
  open; the Move up and Move down actions work with VoiceOver.
- Increase Contrast does not yet strengthen the card backgrounds or the custom colours of the
  load levels.
- A few small buttons, such as the settings gear in the popover and the copy buttons, have a click
  area only as large as their symbol.
- Card values and the apps table use fixed font sizes, and the popover has a fixed width.
- With many remote devices, the tabs at the top of the popover scroll sideways without a visible
  scroll bar.
- Sysbar has not yet been tested end to end with VoiceOver on every screen. The names and roles of
  the controls in Settings have been checked in the accessibility tree; where focus lands when the
  popover or a panel opens has not.

## Reporting a barrier

If something in Sysbar is hard or impossible to use with the way you use your Mac, please tell us:

- open an issue at [github.com/Atanur/sysbar/issues](https://github.com/Atanur/sysbar/issues/new/choose)
  and start the title with "Accessibility:", or
- email **atanur.ozkaldim@gmail.com** if you would rather not post publicly.

It helps to include the Sysbar version (Settings › About), your macOS version, the assistive
technology or setting you use, and what you were trying to do. Barriers that stop someone from
using a feature are treated as bugs and fixed ahead of new features.
