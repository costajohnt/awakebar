#!/bin/bash
# Report why AwakeBar might not be launching at login.
# Read-only: this script inspects state, it never changes it.

APP_NAME="AwakeBar"
BUNDLE_ID="com.costajohnt.AwakeBar"
APP="${1:-$HOME/Applications/$APP_NAME.app}"

section() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
ok()      { printf '  \033[32mok\033[0m    %s\n' "$1"; }
warn()    { printf '  \033[33mwarn\033[0m  %s\n' "$1"; }
bad()     { printf '  \033[31mfail\033[0m  %s\n' "$1"; }

section "Bundle"
if [ -d "$APP" ]; then
    ok "found $APP"
    [ -x "$APP/Contents/MacOS/$APP_NAME" ] \
        && ok "executable present" \
        || bad "missing or non-executable $APP/Contents/MacOS/$APP_NAME"
else
    bad "no app bundle at $APP — run ./install.sh"
    exit 1
fi

section "Code signature"
# An unsigned or invalid bundle is silently dropped from Login Items at boot.
if codesign --verify --strict "$APP" 2>/dev/null; then
    ok "signature valid"
    codesign -dv "$APP" 2>&1 | grep -E '^(Identifier|Authority|Signature)' | sed 's/^/        /'
    if codesign -dv "$APP" 2>&1 | grep -q 'Signature=adhoc'; then
        warn "ad-hoc signature — identity changes on every rebuild, so the"
        warn "login item must be re-registered after each reinstall"
    fi
else
    bad "bundle is not validly signed — this alone breaks launch at login"
    bad "fix: ./install.sh"
fi

section "Quarantine"
if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
    bad "com.apple.quarantine is set — Gatekeeper will block it at login"
    bad "fix: xattr -dr com.apple.quarantine '$APP'"
else
    ok "not quarantined"
fi

section "Gatekeeper / assessment"
spctl --status 2>&1 | sed 's/^/        /'
assess_output=$(spctl --assess --type execute "$APP" 2>&1)
assess_status=$?
[ -n "$assess_output" ] && printf '        %s\n' "$assess_output"
if [ "$assess_status" -eq 0 ]; then
    ok "accepted by Gatekeeper"
else
    warn "rejected by Gatekeeper — expected for a locally built, unnotarized app."
    warn "It still runs once approved, but a managed Mac may enforce a stricter"
    warn "policy. See the MDM section below."
fi

section "Login item registration"
if launchctl print "gui/$UID" 2>/dev/null | grep -qi "$BUNDLE_ID"; then
    ok "registered with launchd for this user"
    launchctl print "gui/$UID" 2>/dev/null | grep -i "$BUNDLE_ID" | sed 's/^/        /'
else
    bad "no launchd entry for $BUNDLE_ID"
    bad "fix: open the app, then menu bar > Open at Login"
fi
echo "        (full list: System Settings > General > Login Items & Extensions)"

section "Currently running"
if pgrep -x "$APP_NAME" >/dev/null; then
    ok "running as pid $(pgrep -x "$APP_NAME" | tr '\n' ' ')"
else
    warn "not running right now"
fi

section "Managed Mac / MDM"
# Work Macs commonly ship a profile that forces Gatekeeper on or blocks
# unapproved background items, which overrides anything set locally.
if profiles status -type enrollment 2>/dev/null | sed 's/^/        /' | grep -q .; then
    profiles status -type enrollment 2>/dev/null | sed 's/^/        /'
else
    echo "        (could not read enrollment status without sudo)"
fi
if [ -d /Library/Managed\ Preferences ]; then
    warn "managed preferences present — IT policy may override Login Items"
fi

section "Recent launch errors (last 2h)"
errors=$(log show --last 2h --style compact \
    --predicate "eventMessage CONTAINS[c] \"$APP_NAME\" OR eventMessage CONTAINS[c] \"$BUNDLE_ID\"" \
    2>/dev/null | grep -iE 'error|denied|reject|invalid|refus|kill' | tail -20)
if [ -n "$errors" ]; then
    printf '%s\n' "$errors" | sed 's/^/        /'
else
    echo "        (none found)"
fi

printf '\nSee TROUBLESHOOTING.md for what to do about each of these.\n'
