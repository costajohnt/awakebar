# AwakeBar

A tiny macOS menu bar app that keeps your Mac awake (even with the lid closed on battery).

Uses `caffeinate -dimu` under the hood. No dependencies, no Amphetamine needed.

## Options

- 30 Minutes
- 1 Hour
- 2 Hours
- 3 Hours
- 6 Hours

## Build

```bash
swiftc -o AwakeBar main.swift -framework Cocoa
```

## Install as .app

```bash
mkdir -p ~/Applications/AwakeBar.app/Contents/MacOS
cp AwakeBar ~/Applications/AwakeBar.app/Contents/MacOS/
cp Info.plist ~/Applications/AwakeBar.app/Contents/
```

Then open from Spotlight or `open ~/Applications/AwakeBar.app`.

## Notes

- `LSUIElement = true` in the plist means no Dock icon, menu bar only.
- Works on battery (no `-s` flag).
- Add to Login Items for auto-start.
