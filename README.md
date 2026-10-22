<p align="center">
  <img src="docs/assets/icon.png" width="128" height="128" alt="Sysbar icon">
</p>

<h1 align="center">Sysbar</h1>

<p align="center">
  <a href="https://github.com/Atanur/sysbar/releases"><img src="https://img.shields.io/github/downloads/atanur/sysbar/total?label=downloads&color=4c8f66" alt="Downloads"></a>
  <a href="https://github.com/Atanur/sysbar/releases/latest"><img src="https://img.shields.io/github/v/release/atanur/sysbar?label=release&color=4c8f66" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B%20%C2%B7%20Apple%20silicon-555" alt="macOS 14+ on Apple silicon">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/atanur/sysbar?color=555" alt="MIT license"></a>
  <a href="https://github.com/Atanur/sysbar/stargazers"><img src="https://img.shields.io/github/stars/atanur/sysbar?style=flat&color=555" alt="GitHub stars"></a>
</p>

<p align="center">
  A tiny, native system monitor for the macOS menu bar.<br>
  <a href="https://sysbar.atanur.dev">sysbar.atanur.dev</a><br>
  CPU, GPU, memory, power, disk and network at a glance — and your servers over SSH when you need them.
</p>

---

## Why Sysbar

- **Glanceable.** Each metric is a thin level bar and a fixed-width number, so the menu bar never shifts as values change. Bars can be tinted by load or follow the menu bar's own colour.
- **Light.** Written in Swift against the system's own counters. With the popover closed it uses about 1% of a single core and around 14 MB of memory, and it stops sampling while the Mac or its screens sleep.
- **Honest.** It shows what can be measured and hides what cannot. Values that are estimates are labelled as such.
- **Private.** No accounts, no analytics. Besides the SSH connections you set up, the only request is a once-a-day check for a new release on GitHub, which you can turn off; nothing about your Mac is sent.

## Features

**Menu bar**
- Choose any of CPU, GPU, memory, power, disk and network, and drag them into the order you like.
- Fixed-width slots: no jitter between `3%` and `100%`.
- Optional load colours (muted green → amber → red), adapted for light and dark menu bars.
- On battery, the charge can join the menu bar once it drops to a level you choose (always, 80%, 50% or 20%), coloured from green to red.

**Popover**
- One card per metric with a graph of the last 150 samples, so its span follows the refresh rate (15 seconds at 0.1 s, 5 minutes at 2 s). Cards can be reordered and laid out automatically (two columns for an even count, one for an odd), in one column, or in two.
- Click a card to open the matching tab in Activity Monitor (or Battery settings).
- Power reacts to how the Mac is powered: charge and time left on battery, adapter and wall draw when plugged in.
- **Top apps** table with CPU, memory, GPU and estimated energy per app; helper processes fold into their app. Columns are configurable.

**Settings**
- About links to the website, the source, release notes, and GitHub forms for problems and ideas that come with your version and Mac filled in. **Copy diagnostic info** adds the rest, without any device names or addresses.
- Reset all settings, keeping or removing remote devices.

**Updates**
- Checks GitHub for a new release once a day and offers it in the popover. Updating downloads the release, installs it only if it is signed by the same developer, and relaunches.

**Remote devices over SSH**
- Watch a Linux server or another Mac: CPU, memory, load average, network, disk and NVIDIA GPU where available, plus the busiest processes.
- Nothing to install on the server — a small read-only script is sent over `ssh` for each sample.
- Sampled while its tab is shown, and for a chosen time after the popover closes (off, 1 minute to 1 hour, or always; 5 minutes by default), so its graphs are still there when you come back. Switching to This Mac keeps the session going. The ssh connection is shared, so reopening does not log in again.
- Uses your existing ssh keys or ssh-agent. Passwords are never asked for or stored; unknown host keys are never accepted automatically.

**Settings**
- A full settings window: menu bar preview, which cards and columns to show, separate refresh rates for this Mac and for remote devices, launch at login.
- 13 languages: English, Türkçe, Deutsch, Français, Español, Italiano, Português (Brasil), Nederlands, Русский, 日本語, 한국어, 简体中文 and العربية. Follows the system language, or pick one in Settings.

## Requirements

- macOS 14 Sonoma or later
- Apple silicon (M1 or later)

## Install

With [Homebrew](https://brew.sh):

```bash
brew install --cask atanur/sysbar/sysbar
```

Or build it from source:

```bash
git clone https://github.com/atanur/sysbar.git
cd sysbar
./scripts/bundle.sh
open build/Sysbar.app
```

Move `build/Sysbar.app` to `/Applications` to keep it, and turn on **Launch at login** in Settings. Sysbar is not on the App Store: it reads power data through a private system interface that the App Store does not allow.

## Releasing

`scripts/release.sh <version>` sets the version, builds and zips `Sysbar.app`, and writes the Homebrew cask to `packaging/homebrew/Casks/sysbar.rb` with the zip's checksum. It publishes nothing; it prints the remaining steps:

1. Commit the version bump, tag it `v<version>` and push.
2. `gh release create v<version> build/Sysbar-<version>.zip` to attach the zip to a GitHub release.
3. Copy the cask into the tap repository `atanur/homebrew-sysbar`, under `Casks/`, and push.

Set `SIGN_IDENTITY` (a Developer ID Application certificate) and `NOTARY_PROFILE` (from `xcrun notarytool store-credentials`) to sign and notarize the build. Without them it is ad-hoc signed and macOS blocks it on first launch, so a public release should be notarized.

## What can and cannot be measured

| Metric | Source |
|---|---|
| CPU, memory, disk, network | macOS kernel counters |
| GPU usage | the graphics driver's statistics |
| Total power | the System Management Controller |
| GPU and Neural Engine power | energy counters |
| Battery | the battery's registry entry |
| Per-app values | the kernel, for your own user's processes |

On current macOS, CPU and memory power counters cannot be read without root, so Sysbar does not show them rather than guess. Per-app energy is the system's own estimate and is lower than total power.

## Development

```bash
swift build                  # debug build
swift test                   # unit tests for the core library
./scripts/bundle.sh          # release app in build/Sysbar.app
./scripts/make-icon.sh       # redraw the icon from scripts/make-icon.swift
./scripts/strings.py extract # refresh the English source strings
./scripts/strings.py check   # verify every translation is complete
```

`Sources/SysbarCore` holds the samplers, parsers and formatting, with no UI, and is what the tests cover. `Sources/Sysbar` is the AppKit and SwiftUI app. Every user-facing string goes through `L("English text")`; translations live in `Resources/Localization/<language>.lproj/Localizable.strings`.

Diagnostic flags, handy when checking a new Mac or server:

| Flag | What it does |
|---|---|
| `--probe` | prints every raw sensor reading once |
| `--remote-test HOST [USER [PORT [KEY]]]` | samples a server twice over ssh, exactly as the app does |
| `--remote-script` | prints the script sent to servers |
| `--smc-keys=PREFIX` | lists readable SMC keys, e.g. `Tp` for CPU temperatures |
| `--l10n-sample` | prints a few strings and numbers in the current language |
| `--open-popover` | opens the popover right after launch, for measuring its cost |
| `--render-menubar PATH` | writes the menu bar readout, battery included, as a PNG in light and dark |
| `--update-now` | checks for a release at once and installs it, as the Update button does |

## Website

[sysbar.atanur.dev](https://sysbar.atanur.dev) is the single page in `docs/`, served by Cloudflare. `wrangler.jsonc` deploys it as static assets on that custom domain:

```bash
npx wrangler deploy
```

## License

[MIT](LICENSE)
