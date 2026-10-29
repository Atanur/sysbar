# Changelog

What changed in each release of Sysbar, newest first. The app shows the notes of its own version in
Settings › About, and the website and GitHub releases show the same text.

## 0.5.9 — 2026-10-30

- The Top apps table has a **Net** column: each app's network use, with download and upload split in the tooltip and read by VoiceOver. Click the heading to sort by it.
- With three or more table columns shown, memory and power stay short: `0.7G` rather than `700M`, and `0.7W` rather than `743mW`. With fewer columns the longer values come back.
- VoiceOver names every switch, menu and slider in Settings after its setting, and moves between pages and groups by their headings. Popover cards and each row of the apps table are read as one item, with rates in words, and the results of checking a device or copying a command are announced.
- Reduce Motion now also stops the values counting up in the popover and the pulse of a live device's dot. With Differentiate Without Color on, a device's status dot draws a different symbol for each state.
- Text fields in Settings take the usual ⌘C, ⌘V, ⌘A and ⌘Z, and ⌘W closes the window.
- [ACCESSIBILITY.md](https://github.com/Atanur/sysbar/blob/main/ACCESSIBILITY.md) describes what works and what is still missing, and security problems can be reported privately on GitHub.

## 0.5.8 — 2026-10-29

- Settings is laid out around your devices. The sidebar lists this Mac and every remote device, each with a page of its own, and the + beside Devices adds one by hand or from those found on your network. Menu Bar and Window are split into short pages, and Temperature and fans and Keep awake have their own under Tools.
- A device's page checks it as it opens and shows whether it answers, with a green or red dot in the sidebar. Its cards, refresh rate and keep-monitoring time are set right there, and you can give it an icon: server, cloud, NAS, PC or a Mac.
- This Mac's page shows what the Mac is, which cards its tab shows and how often it is sampled.
- Sysbar suggests devices to add: Macs with Remote Login on in this network, and your Macs and Linux machines in Tailscale, each with the commands to connect it filled in.

## 0.5.7 — 2026-10-28

- This Mac is listed first in Settings › Devices, and you can rename it: its tab in the popover shows the name you give it instead of This Mac. Leave the name empty to go back.

## 0.5.6 — 2026-10-28

- Remote Macs list their apps the way Activity Monitor does: helper processes count toward their app, and memory is each app's footprint, so Arc or Claude show their full size instead of one helper's.
- The processes table of a remote device is right whichever column it is sorted by: Sysbar now gets the busiest apps and the largest ones, from every process rather than the first twelve. Linux servers no longer list idle kernel threads.

## 0.5.5 — 2026-10-28

- Settings › Devices has a short guide, How to connect a device, folded under the list: the few commands to run once on a Mac or a Linux server and on this Mac, each with a copy button. It notices a key you already have and works on a local network or over a VPN such as Tailscale. Sysbar runs none of it and never sees your password.

## 0.5.4 — 2026-10-27

- What's new, in the app: Settings › About shows the changes in the version you run, and the update banner's **What's new** unfolds the notes of the new release before you install it.
- A changelog for every release, on the website and in [CHANGELOG.md](https://github.com/Atanur/sysbar/blob/main/CHANGELOG.md).
- The website and the README describe everything Sysbar does today, from temperature and fans to keep awake.

## 0.5.3 — 2026-10-27

- The Power card's corner shows a bolt whenever the Mac runs on its adapter: green while the battery charges, plain once it is full or macOS holds the charge. A Mac without a battery always shows the plain bolt.

## 0.5.2 — 2026-10-27

- CPU in the Top apps table is now a share of the whole Mac, like the CPU card above it, so the apps no longer seem to add up to more than the total. Shares under 10% keep one decimal.
- Remote devices divide their processes' CPU over the server's cores in the same way.

## 0.5.1 — 2026-10-26

- Lighter on the CPU: the kind of network connection is looked up once per connection instead of on every sample.
- The fan icon no longer spins. It is drawn still, and turns amber, orange and red as the fans work harder.
- App memory switches to gigabytes from 1000 MB, so "1023M" reads "1.0G".

## 0.5.0 — 2026-10-26

- A calmer look: cards are black, white and grey, and colour appears only where it means something, as load turns amber, orange and red, and charge turns green.
- Disk, Network and Power draw both directions either side of a zero line: read and write, download and upload, and what the Mac uses next to what goes into the battery.
- The Disk card shows the room left on the disk, the Network card whether you are on Wi-Fi or Ethernet, and the GPU card its temperature.
- Right-click the menu bar item for Settings, Check for updates, About and Quit.

## 0.4.0 — 2026-10-26

- Keep awake can move the mouse when the Mac is idle, so chat apps do not show you as away. About once a minute the cursor takes a short curved trip and comes back. Nothing is clicked or typed, and it needs the Accessibility permission, which Sysbar asks for only when you turn it on.

## 0.3.3 — 2026-10-26

- Keep awake works on Macs without a lid (Mac mini, Studio, iMac): it keeps them from sleeping while idle.
- A new MacBook icon for keep awake, struck through while the Mac is kept awake.
- The popover closes when you click outside it.

## 0.3.2 — 2026-10-24

- Keep awake has a menu with two new choices: until a time of day, and while the charger is connected.
- "While an app is open" no longer ends when the app briefly disappears, and keep awake records why it ended by itself.

## 0.3.1 — 2026-10-24

- Fixed: while the fans ran, the spinning fan icon made the whole popover slide around and use a lot of CPU.

## 0.3.0 — 2026-10-23

- Keep the Mac awake with its lid closed: for 1 hour, 4 hours, until you turn it off, or while an app you pick stays open. It never stays on by itself: it ends when Sysbar quits or crashes, and on low battery.
- Three menu bar styles: bars and values, bars only, or values only.
- Small animations throughout: bars glide to new levels, the logo waves until the first reading, and pickers and tabs slide. All of them follow Reduce Motion.
- The fan and keep-awake buttons can each be hidden in Settings.

## 0.2.0 — 2026-10-23

- A temperature panel that names what is warming the Mac, such as processor work, graphics work or cooling down, with CPU, GPU, memory and battery temperatures and the fans.
- A thermometer appears in the menu bar only when the heat is out of the ordinary.
- Manual fan control with one slider, through a small helper you approve once. The fans return to automatic when Sysbar quits, crashes or the Mac sleeps.
- The popover frees its memory completely when it closes.

## 0.1.2 — 2026-10-22

- Drag the menu bar readouts and the popover cards into any order.
- Lay the cards out automatically, in one column or in two.
- A fuller About page: version, links, problem and idea forms with your Mac filled in, and Copy diagnostic info.
- Reset all settings, with or without your remote devices.

## 0.1.1 — 2026-10-22

- The battery charge can join the menu bar while unplugged, once it drops to a level you choose.
- In-app updates: Sysbar checks GitHub once a day and installs a new release only if it is signed by the same developer.
- Decimals follow the app's language, such as "10,9G" in Turkish and German.

## 0.1.0 — 2026-10-22

- First release: CPU, GPU, memory, power, disk and network in the menu bar, a popover with live graphs and the busiest apps, remote Linux servers and Macs over SSH, and 13 languages.
