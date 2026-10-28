# Contributing to Sysbar

Thanks for helping. Bug reports, translations and pull requests are all welcome.

## Before you start

- **Bugs and ideas:** open an issue with the templates under [Issues](https://github.com/Atanur/sysbar/issues/new/choose).
  For a bug, include the Sysbar version (Settings › About), your Mac model and macOS version.
- **Security problems:** do not open an issue; see [SECURITY.md](.github/SECURITY.md).
- **Larger changes:** open an issue first, so we can agree on the approach before you write it.
  Small fixes can go straight to a pull request.

## Setting up

You need a Mac with Apple silicon, macOS 14 or later, and Swift 6 (Xcode 16 or its command line
tools). Sysbar has no outside dependencies.

```bash
swift build                  # debug build
swift test                   # unit tests
./scripts/bundle.sh          # release app in build/Sysbar.app
```

The diagnostic flags in the [README](README.md#development) help when checking sensors, fans or a
remote server.

## How the code is laid out

- `Sources/SysbarCore` holds the samplers, parsers and formatting, with no UI. Logic goes here,
  where it can be tested.
- `Sources/Sysbar` is the AppKit and SwiftUI app.
- `Sources/SysbarFanHelper` is the root helper for fan speeds and keeping the lid closed awake.
  Changes to it need extra care; keep what it can do as narrow as it is today.
- `Tests/SysbarCoreTests` covers the core library with Swift Testing.

## Making a change

1. **Test it.** Add or update tests in `Tests/SysbarCoreTests` for any logic you change, and run
   `swift test`.
2. **Translate it.** Every string people see goes through `L("English text")`. After adding or
   changing one, run `./scripts/strings.py extract`, add the translation to every language in
   `Resources/Localization`, and check with `./scripts/strings.py check`. If you cannot translate a
   language, say so in the pull request and it will be filled in.
3. **Commit it.** Messages follow `type: what changed`, with `feat`, `fix`, `perf`, `refactor`,
   `docs`, `test` or `chore`, for example `fix: keep the website from scrolling sideways on phones`.
4. **Check it in the app.** Build with `./scripts/bundle.sh`, open `build/Sysbar.app`, and try the
   change, with VoiceOver too if it touches the UI (see [ACCESSIBILITY.md](ACCESSIBILITY.md)).
5. **Describe it.** In the pull request, say what people will notice. The maintainer writes the
   [CHANGELOG.md](CHANGELOG.md) entry when the release is cut.

Keep Sysbar light: it runs all day, so new work should not sample more often, keep more in memory,
or wake the CPU when nothing is shown.

## Code of conduct

Everyone taking part is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## License

By contributing, you agree that your work is released under the [MIT license](LICENSE).
