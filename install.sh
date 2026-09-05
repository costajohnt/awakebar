#!/bin/bash
# Build AwakeBar and install it as a signed .app bundle.
#
# The bundle MUST be code signed: macOS keeps login items in the Background
# Task Management database keyed by code signature, and an unsigned bundle is
# dropped at login without an error message.
#
# By default this uses an ad-hoc signature (`-`), which is enough to register a
# login item but changes identity on every build, so the login item has to be
# re-registered after each reinstall (the app does that for you on launch).
# For a signature that stays stable across rebuilds, create a self-signed code
# signing certificate in Keychain Access and run:
#
#     CODESIGN_IDENTITY="My Code Signing Cert" ./install.sh
#
set -euo pipefail

APP_NAME="AwakeBar"
BUNDLE_ID="com.costajohnt.AwakeBar"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP="$INSTALL_DIR/$APP_NAME.app"
IDENTITY="${CODESIGN_IDENTITY:--}"

echo "==> Building for $(uname -m)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
swiftc -O \
    -target "$(uname -m)-apple-macos13.0" \
    -o "$BUILD_DIR/$APP_NAME" \
    "$SRC_DIR/main.swift" \
    -framework Cocoa

echo "==> Assembling $APP"
# Quit any running copy so the bundle isn't replaced underneath it.
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SRC_DIR/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# A quarantine flag inherited from the source tree (cloned from a download,
# AirDropped, synced) makes Gatekeeper refuse the app at login.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> Signing with identity: $IDENTITY"
codesign --force \
    --identifier "$BUNDLE_ID" \
    --sign "$IDENTITY" \
    "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Launching"
open "$APP"

cat <<EOF

Installed to $APP

Next: click the cup icon in the menu bar and turn on "Open at Login".
If that fails or the app doesn't come back after a restart, run:

    $SRC_DIR/doctor.sh
EOF
