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
- **At the top of the screen**, instead of the menu bar, the island's ears hold items you choose and
  order (see below): the System item (the readings) and a button for each feature (Stash, Clipboard),
  in either ear. While the island is closed the System item is one button named "Sysbar" with the
  readings as its value; each feature is a button named after its tab, with its state as the value (the
  stash's number of items). While the heat warning is on, or the Mac is kept awake, a button for it
  (named Heat warning, or Keep awake, with its state as the value and the hint "Opens the System page")
  is first in the right ear of the closed island; pressing it opens the System page with the fan or
  keep-awake panel unfolded. On the System page, the fan button (Temperature and fans) and the
  keep-awake button are buttons left of Settings, each with its state as the value, marked selected
  while its panel is unfolded. Pressing one of the items opens the panel on that tab, or closes it when that tab is
  already open, and the open tab's button is marked selected. They also have a tooltip. Once the island
  is open, the items stay where they are and are the panel's tabs, and the System item is then named
  System (marked selected when it is the open tab). An item set to "Only when open" is not on the closed
  island and is a button once it opens. The panel hangs from the bottom edge of that strip, in one
  outline with it, and its first row has the Settings button at the right end (the machine tabs, or the
  name of the tab shown, are at the left). Escape, or a click outside the panel, closes it. The panel
  is drawn down from under the strip like a sheet, which itself never moves; with Reduce Motion it
  appears at once.
- **Hiding the island**: in full screen, or when Show the island (Settings › Notch) is set to
  "Only when the pointer is on it", the island is invisible and takes no clicks until the pointer
  reaches the notch or the top edge of the screen above it, and it is hidden again a moment after the
  pointer leaves (never while its panel, the stash picker or its menu is open). Someone who cannot
  place the pointer there can still open the island's features with their global shortcuts (the stash
  picker and the clipboard history). The setting is a pop-up button named "Show the island".
- **Customising the island** (Settings › Notch): every control is named after its row,
  and the preview is one element named "Notch preview" whose value lists the items of each ear
  (closed or open, as its Closed/Open control says). *Left of the notch* and *Right of the notch* list
  the items as rows; each row has a "Visibility of …" menu (Always, Only when open), and an "Arrange …"
  menu to move it up or down or to the other side, so nothing needs dragging. The same commands are
  accessibility actions on the row (Move up, Move down, Move to the left or right of the notch);
  dragging a row is an extra, not the only way. An item whose feature is off is dimmed, says why, and
  cannot be changed until it is turned on on its own page. With
  several displays each island is its own "Sysbar" button, and opening one closes the others. Pressing
  the button always opens the panel, so choosing "click" for opening does not affect VoiceOver or
  keyboard use. State is never carried by colour alone: the monochrome style keeps every icon's
  state in its accessibility value. Black always uses the dark look; glass follows the
  system's light or dark look.
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
- **The stash** can be used without dragging: on the Stash tab of the Sysbar panel, every stash is a tab in the bar along the top, a button that VoiceOver reads by name and number of items, with the chosen one marked selected; New Stash makes one and puts its name in an edit field, Rename, Color and Delete Stash are in each stash's menu, with Rename and Delete Stash also VoiceOver actions, and Add Clipboard to Stash (or a shortcut you record) puts copied files or text in the chosen stash, or in the one Settings names for the shortcut. Each item is a button named with its kind, folder or link, or File not found; Open, Quick Look, Show in Finder, Move to and Remove from stash are in its menu, and Open, Quick Look, Show in Finder and Remove are VoiceOver actions. Colours are never the only difference between stashes: each also has its name, and the colour menu names every colour. Deleting a stash that holds items asks in a strip on the tab, not in a dialog, and says whether its items move to Main or go with it.
- **The clipboard history** works from the keyboard: its shortcut opens a panel where typing searches, ⌘1 to ⌘5 choose a kind filter (All, Text, Links, Images, Files, as far as there are items of that kind), the arrow keys choose an item, Return copies it, ⌘⌫ deletes it and Escape closes the panel. The filter chips are buttons VoiceOver reads by name, with the chosen one marked selected. Each item is a button VoiceOver reads by its text or file name, the app it came from and when; Copy, Add to Stash and Delete are in its menu. The copies are also on the Clipboard tab of the Sysbar panel, which is there while the history is on (in Settings › Features › Clipboard), with or without the stash. Add to Stash is in the menu only while the stash is on. That page's controls are named after their setting: each switch, menu and shortcut button, and the folder's Choose… button and its More menu, which name what they set the folder for; the shortcut button's value is the key combination. Moving the folder asks in a standard alert with labelled buttons, and Clear Clipboard History asks in a confirmation dialog.
- **Disclosures**, such as the connection guide and an update's What's new, say whether they are
  expanded or collapsed.

## Known limitations

These are known and planned; reports about any of them still help us decide what comes first.

- Some details appear only as a tooltip on hover: peak values, memory pressure, the power
  breakdown, each fan's speed, and an app's download and upload split (the table's Network column
  shows their sum). VoiceOver reads them, but a sighted keyboard user cannot see them.
- Moving a metric with the keyboard needs its row's menu, which Full Keyboard Access cannot always
  open; the Move up and Move down actions work with VoiceOver.
- Choosing a stash by dragging files over the island, or by shaking the pointer or holding a modifier key during a drag, needs a pointer, and the picker's tiles are drawn for the drag only, so VoiceOver cannot reach them. Use the Stash tab of the Sysbar panel instead: copy files in Finder, then Add Clipboard to Stash puts them in the stash you chose, or use the shortcut.
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
