# Changelog

What changed in each release of Sysbar, newest first. The app shows the notes of its own version in
Settings › About, and the website and GitHub releases show the same text.

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
