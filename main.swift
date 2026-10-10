import Cocoa
import ServiceManagement

/// Remembers that the user asked for auto-start, independently of whether
/// launchd currently agrees. Rebuilding the app invalidates the registration
/// but must not silently discard the user's intent.
private let launchAtLoginKey = "LaunchAtLoginEnabled"

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var caffeinateProcess: Process?
    var timer: Timer?
    /// When the current awake period ends. The countdown is derived from this
    /// rather than decremented, so it stays correct even if timer ticks are
    /// delayed or skipped.
    var awakeUntil: Date?
    var timerMenuItem: NSMenuItem?
    var launchAtLoginItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "AwakeBar")
        }
        buildMenu()
        healLaunchAtLoginRegistration()
        refreshLaunchAtLoginItem()
    }

    func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        timerMenuItem = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
        timerMenuItem?.isEnabled = false
        menu.addItem(timerMenuItem!)
        menu.addItem(NSMenuItem.separator())

        let durations: [(String, Int)] = [
            ("30 Minutes", 1800),
            ("1 Hour", 3600),
            ("2 Hours", 7200),
            ("3 Hours", 10800),
            ("6 Hours", 21600),
        ]

        for (title, seconds) in durations {
            let item = NSMenuItem(title: title, action: #selector(startAwake(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let stopItem = NSMenuItem(title: "Stop", action: #selector(stopAwake), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        launchAtLoginItem = loginItem

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// Login-item approval can be revoked from System Settings or by an MDM
    /// policy at any time, so re-read the real state every time the menu opens
    /// rather than trusting what we cached at launch.
    func menuWillOpen(_ menu: NSMenu) {
        refreshLaunchAtLoginItem()
        if awakeUntil != nil {
            updateTimerDisplay()
        }
    }

    /// Covers termination paths other than the Quit item (logout, `NSApp`
    /// terminate requests). Kills and crashes are covered by `caffeinate -w`.
    func applicationWillTerminate(_ notification: Notification) {
        stopAwake()
    }

    // MARK: - Launch at login

    var wantsLaunchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: launchAtLoginKey) }
        set { UserDefaults.standard.set(newValue, forKey: launchAtLoginKey) }
    }

    /// launchd keys a login item to the bundle's code signature. An ad-hoc
    /// signature is regenerated on every build, so a registration made by a
    /// previous build no longer matches the bundle on disk and is dropped at
    /// the next login without any user-visible error. Re-register when the
    /// system has forgotten us but the user still wants auto-start.
    ///
    /// `.requiresApproval` is deliberately left alone: that state means a human
    /// (or an MDM profile) switched the item off in System Settings, and
    /// re-registering behind their back would not turn it back on anyway.
    func healLaunchAtLoginRegistration() {
        guard #available(macOS 13.0, *) else { return }
        guard wantsLaunchAtLogin else { return }
        let status = SMAppService.mainApp.status
        guard status == .notRegistered || status == .notFound else { return }
        try? SMAppService.mainApp.register()
    }

    func refreshLaunchAtLoginItem() {
        guard let item = launchAtLoginItem else { return }

        guard #available(macOS 13.0, *) else {
            item.title = "Open at Login (needs macOS 13+)"
            item.isEnabled = false
            return
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            item.title = "Open at Login"
            item.state = .on
        case .requiresApproval:
            item.title = "Open at Login — Approve in System Settings…"
            item.state = .mixed
        default:
            item.title = "Open at Login"
            item.state = .off
        }
    }

    @objc func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }

        // Approval was withheld, so there is nothing to toggle here — send the
        // user to the one place that can grant it.
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }

        let enabling = SMAppService.mainApp.status != .enabled
        do {
            if enabling {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            wantsLaunchAtLogin = enabling
        } catch {
            wantsLaunchAtLogin = false
            presentLaunchAtLoginFailure(error, whileEnabling: enabling)
        }

        refreshLaunchAtLoginItem()
    }

    /// Without this the failure is completely invisible: the app has no Dock
    /// icon and no window, so a rejected registration just looks like the
    /// setting refusing to stick.
    func presentLaunchAtLoginFailure(_ error: Error, whileEnabling enabling: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = enabling
            ? "Couldn't turn on Open at Login"
            : "Couldn't turn off Open at Login"
        alert.informativeText = """
            \(error.localizedDescription)

            This usually means the app bundle isn't code signed, or it was \
            rebuilt after the login item was registered. Reinstall with \
            ./install.sh and try again, then run ./doctor.sh if it still fails.
            """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Login Items…")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn, #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    // MARK: - Caffeinate

    @objc func startAwake(_ sender: NSMenuItem) {
        stopAwake()

        let seconds = sender.tag

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // `-w <pid>` ties caffeinate to this app's lifetime, so a force-quit,
        // crash or `pkill` cannot leave an orphan keeping the Mac awake.
        process.arguments = [
            "-dimu",
            "-t", "\(seconds)",
            "-w", "\(ProcessInfo.processInfo.processIdentifier)",
        ]
        // Return the UI to Idle whenever caffeinate exits on its own (timeout,
        // killed externally). A deliberate stopAwake() clears
        // caffeinateProcess first, so the identity check makes this a no-op.
        process.terminationHandler = { [weak self] exited in
            DispatchQueue.main.async {
                guard let self = self, self.caffeinateProcess === exited else { return }
                self.stopAwake()
            }
        }

        do {
            try process.run()
        } catch {
            presentCaffeinateFailure(error)
            return
        }
        caffeinateProcess = process
        awakeUntil = Date().addingTimeInterval(TimeInterval(seconds))

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "AwakeBar Active")
        }

        updateTimerDisplay()
        let tick = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.remainingSeconds <= 0 {
                self.stopAwake()
            } else {
                self.updateTimerDisplay()
            }
        }
        // .common keeps the countdown ticking while the menu is open (menu
        // tracking runs the loop in a mode the default mode excludes).
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    var remainingSeconds: Int {
        guard let end = awakeUntil else { return 0 }
        return max(0, Int(end.timeIntervalSinceNow.rounded(.up)))
    }

    func presentCaffeinateFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't keep the Mac awake"
        alert.informativeText = """
            /usr/bin/caffeinate failed to start: \(error.localizedDescription)
            """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func updateTimerDisplay() {
        // Round up to whole minutes so the menu never shows "0m remaining"
        // while still active.
        let totalMinutes = (remainingSeconds + 59) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            timerMenuItem?.title = "Awake: \(hours)h \(minutes)m remaining"
        } else {
            timerMenuItem?.title = "Awake: \(minutes)m remaining"
        }
    }

    @objc func stopAwake() {
        let process = caffeinateProcess
        caffeinateProcess = nil
        if let process = process, process.isRunning {
            process.terminate()
        }
        timer?.invalidate()
        timer = nil
        awakeUntil = nil
        timerMenuItem?.title = "Idle"
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "AwakeBar")
        }
    }

    @objc func quitApp() {
        stopAwake()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
