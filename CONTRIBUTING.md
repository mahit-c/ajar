# Contributing to Ajar

Thanks for helping. Ajar is small on purpose: it does one job (keep a Mac awake with the lid closed) and should do it reliably and safely. Changes that make it more reliable, safer or clearer are the most welcome.

## Code layout

| Path | What it is |
|---|---|
| `Sources/AjarShared` | XPC protocol, constants (bundle ID, helper label, team ID), battery sensor |
| `Sources/AjarHelper` | Root LaunchDaemon. Only ever runs `pmset -a disablesleep 0\|1` |
| `Sources/Ajar` | SwiftUI menu bar app: sessions, safety rules, settings and welcome windows |
| `Resources/` | Info.plist, launchd plists, app icon (`AppIcon.svg` is the source) |
| `scripts/` | `build.sh`, `release.sh`, `make-icon.sh`, `uninstall.sh` |

## Building

Xcode isn't required; the Command Line Tools are enough.

```bash
scripts/build.sh      # ad-hoc signed build/Ajar.app
open build/Ajar.app
```

Notes:
- Ad-hoc builds install the helper as a classic LaunchDaemon via an admin prompt. Developer ID-signed builds use `SMAppService` (one-time approval in System Settings → Login Items).
- Don't use SwiftUI property-wrapper macros such as `@State`. The Command Line Tools ship without the SwiftUI macro plugin, so keep view state in `SessionController` instead.
- Helper logs: `log stream --predicate 'eventMessage CONTAINS "ajar-helper"'`
- To reset everything: `scripts/uninstall.sh`, then `defaults delete io.github.mahit-c.ajar`.

## Ground rules for the helper

The helper runs as root, so changes to `Sources/AjarHelper` get extra scrutiny:

- It must never execute anything other than `/usr/bin/pmset` with fixed arguments.
- Every new code path that disables sleep needs a matching path that restores it.
- Keep the XPC interface minimal. Bump `AjarConstants.helperVersion` when it changes.

## Testing a change

Before opening a pull request, please check the relevant items:

- [ ] Start a session, close the lid for a few minutes, then reopen: still running
- [ ] Plug in or unplug power mid-session: session survives
- [ ] `kill -9` the app mid-session: `pmset -g | grep SleepDisabled` returns to `0` within about 60 s
- [ ] Reboot mid-session: sleep is restored after boot
- [ ] Quit normally: sleep restored immediately

## Releasing (maintainers)

1. Have a Developer ID Application certificate and a notarytool profile: `xcrun notarytool store-credentials ajar-notary ...`
2. Set `AjarConstants.teamID`. `release.sh` refuses to run without it, because otherwise the helper would trust any app claiming Ajar's bundle ID.
3. `AJAR_SIGN_IDENTITY="Developer ID Application: … (TEAMID)" scripts/release.sh` produces a notarized, stapled DMG.
4. Bump `CFBundleShortVersionString` in `Resources/Info.plist`, update `CHANGELOG.md`, and tag `vX.Y.Z`.
