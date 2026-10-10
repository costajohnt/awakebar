# AwakeBar

A tiny macOS menu bar app that keeps your Mac awake for a set time: it prevents
idle sleep, display sleep and system sleep while the lid is open, on battery or
on power.

Uses `caffeinate -dimu` under the hood. No dependencies, no Amphetamine needed.

Closing the lid still sleeps the Mac. `caffeinate` assertions do not override
lid-close (clamshell) sleep unless the Mac is in clamshell mode with an external
display, power and input attached. Keeping a lid-closed laptop awake on battery
needs a root-level setting such as `pmset -b disablesleep 1`, which AwakeBar
does not do.

## Options

- 30 Minutes
- 1 Hour
- 2 Hours
- 3 Hours
- 6 Hours

## Install

```bash
./install.sh
```

This builds the app, assembles a **code signed** bundle in `~/Applications`,
clears any quarantine flag, and launches it. Signing is not optional: macOS
drops unsigned bundles from Login Items at boot without reporting an error.

Install somewhere else with `INSTALL_DIR=/Applications ./install.sh`.
Set `SKIP_LAUNCH=1` to build and sign without launching (used by CI).

## Start at login

Click the cup icon in the menu bar and turn on **Open at Login**. The app
registers itself with `SMAppService`, and re-registers on launch if a rebuild
invalidated the previous registration.

If the item instead reads "Open at Login — Approve in System Settings…",
approval was withheld; click it to open the right settings pane.

Not coming back after a restart? Run `./doctor.sh` — it checks the signature,
quarantine, Gatekeeper, the launchd registration, and MDM policy, and says which
one is the problem. [TROUBLESHOOTING.md](TROUBLESHOOTING.md) explains the fix for
each.

## Build only

```bash
swiftc -O -target "$(uname -m)-apple-macos13.0" -o AwakeBar main.swift -framework Cocoa
```

Note this produces a bare executable, not an installable bundle — use
`install.sh` for anything you want to launch at login.

## Notes

- `LSUIElement = true` in the plist means no Dock icon, menu bar only.
- Works on battery (no `-s` flag), lid open.
- `caffeinate` is started with `-w <AwakeBar pid>`, so it exits with the app
  however the app ends (Quit, force quit, crash, reinstall).
- Requires macOS 13 or later.
- Ad-hoc signatures change on every build. For a login item registration that
  survives rebuilds, sign with a stable self-signed identity:
  `CODESIGN_IDENTITY="My Cert" ./install.sh`.

## License

[MIT](LICENSE)
