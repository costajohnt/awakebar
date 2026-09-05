# AwakeBar doesn't come back after a restart

Almost always one of the causes below, in rough order of likelihood on a
managed (work) Mac. Run `./doctor.sh` first — it checks every one of them and
tells you which applies.

## 1. The app bundle was never code signed

This is the big one, and it's what the old install instructions produced.

`swiftc` ad-hoc signs the *executable*, but hand-assembling a bundle by copying
that executable next to an `Info.plist` leaves the **bundle** unsigned. Since
macOS 13, Login Items live in the Background Task Management database and are
keyed to the bundle's code signature. An unsigned bundle is dropped at login —
silently, with no error and no notification. The app looks fine when you launch
it by hand and simply never appears after a reboot.

Fix: reinstall with `./install.sh`, which signs the bundle and verifies it.

## 2. The login item went stale after a rebuild

An ad-hoc signature (`codesign -s -`) is a *new identity every time you build*.
Register the login item, rebuild the app, and the registration now points at a
signature that no longer matches what's on disk — so it stops launching, again
without an error.

Two fixes, use either:

- AwakeBar now re-registers itself on launch when it finds the registration
  missing, so opening the app once after a reinstall repairs it.
- Or give it a stable identity. Create a self-signed code signing certificate
  in Keychain Access (Certificate Assistant → Create a Certificate, type "Code
  Signing"), then install with:

  ```bash
  CODESIGN_IDENTITY="My Code Signing Cert" ./install.sh
  ```

  Now the signature is the same across rebuilds and the registration sticks.

## 3. Login item needs approval, or IT policy is blocking it

Check **System Settings → General → Login Items & Extensions**. AwakeBar should
be listed and switched on under "Open at Login".

If the menu bar item reads "Open at Login — Approve in System Settings…", macOS
registered it but approval was withheld. Click it to jump straight to the pane.

On a work Mac this toggle can be forced off by an MDM configuration profile, in
which case flipping it locally won't hold across a reboot. `./doctor.sh` reports
whether the machine is MDM-enrolled and whether managed preferences are present.
If it is, you need IT to allowlist `com.costajohnt.AwakeBar` as a permitted
background item — a locally built, unnotarized app is exactly what those
policies are written to stop.

## 4. Quarantine flag

If the source tree was downloaded, AirDropped, or synced from cloud storage
rather than cloned with git, `com.apple.quarantine` may be set on the bundle and
Gatekeeper will refuse to launch it in the background.

```bash
xattr -dr com.apple.quarantine ~/Applications/AwakeBar.app
```

`install.sh` clears this automatically.

## 5. Gatekeeper rejects an unnotarized app

`spctl --assess` will report AwakeBar as rejected. That's expected for anything
built locally and not notarized by Apple, and it isn't fatal on its own — the
app runs once you've approved it. It becomes fatal when combined with a strict
MDM Gatekeeper policy (see #3).

## 6. Installed in the wrong place

`~/Applications` works, and that's where `install.sh` puts it. `/Applications`
works too and is less likely to be treated as unusual by endpoint security
tooling; install there with:

```bash
INSTALL_DIR=/Applications ./install.sh
```

Do **not** run it from your Downloads folder, a Desktop folder synced to iCloud,
or an external volume — login items pointing into those locations are
unreliable, and a volume that isn't mounted at login guarantees failure.

## Still stuck?

Run `./doctor.sh` and read the "Recent launch errors" section. Entries from
`launchd`, `taskgated`, or your endpoint security agent mentioning AwakeBar name
the actual blocker. If IT tooling is killing the process, no change on this side
will fix it — that one needs an allowlist entry.
