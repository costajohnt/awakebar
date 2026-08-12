import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var caffeinateProcess: Process?
    var timer: Timer?
    var remainingSeconds: Int = 0
    var timerMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "AwakeBar")
        }
        buildMenu()
    }

    func buildMenu() {
        let menu = NSMenu()

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

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func startAwake(_ sender: NSMenuItem) {
        stopAwake()

        let seconds = sender.tag
        remainingSeconds = seconds

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-dimu", "-t", "\(seconds)"]
        try? process.run()
        caffeinateProcess = process

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "AwakeBar Active")
        }

        updateTimerDisplay()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.remainingSeconds -= 60
            if let self = self, self.remainingSeconds <= 0 {
                self.stopAwake()
            } else {
                self?.updateTimerDisplay()
            }
        }
    }

    func updateTimerDisplay() {
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        if hours > 0 {
            timerMenuItem?.title = "Awake: \(hours)h \(minutes)m remaining"
        } else {
            timerMenuItem?.title = "Awake: \(minutes)m remaining"
        }
    }

    @objc func stopAwake() {
        caffeinateProcess?.terminate()
        caffeinateProcess = nil
        timer?.invalidate()
        timer = nil
        remainingSeconds = 0
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
