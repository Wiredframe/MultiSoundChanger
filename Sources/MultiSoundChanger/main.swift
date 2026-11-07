import AppKit
import CoreAudio
import ServiceManagement

private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let volume = VolumeController()
    private let keys = MediaKeys()
    private let hud = HUD()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let deviceItem = NSMenuItem()
    private let loginItem = NSMenuItem(title: L("Open at Login"), action: #selector(toggleLogin), keyEquivalent: "")

    private var hideIcon: Bool {
        get { UserDefaults.standard.bool(forKey: "hideIcon") }
        set { UserDefaults.standard.set(newValue, forKey: "hideIcon"); statusItem.isVisible = !newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        statusItem.isVisible = !hideIcon

        keys.handler = { [unowned self] key, fine, isRepeat in
            // Only step in where macOS cannot: multi-output devices. Everything else stays native.
            guard volume.isAggregate, !volume.knobs.isEmpty else { return false }
            switch key {
            case .up: volume.step(up: true, fine: fine)
            case .down: volume.step(up: false, fine: fine)
            case .mute: if !isRepeat { volume.toggleMute() }
            }
            hud.show(level: volume.level, muted: volume.isMuted)
            refresh()
            return true
        }
        keys.start()

        // Follow output switches and devices coming and going (the original read them once at launch).
        CA.observe(CA.system, CA.address(kAudioHardwarePropertyDefaultOutputDevice)) { [unowned self] in refresh() }
        CA.observe(CA.system, CA.address(kAudioHardwarePropertyDevices)) { [unowned self] in refresh() }
        // macOS can switch the tap off during sleep (upstream issue #27).
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil
        )

        refresh()
    }

    /// Launching the app again while it runs brings a hidden menu bar icon back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        hideIcon = false
        return false
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        deviceItem.isEnabled = false
        menu.addItem(deviceItem)

        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.isContinuous = true
        slider.frame = NSRect(x: 18, y: 4, width: 220, height: 24)
        let sliderView = NSView(frame: NSRect(x: 0, y: 0, width: 256, height: 32))
        sliderView.addSubview(slider)
        let sliderItem = NSMenuItem()
        sliderItem.view = sliderView
        menu.addItem(sliderItem)

        menu.addItem(.separator())
        menu.addItem(item(L("Sound Settings…"), #selector(openSoundSettings)))
        menu.addItem(item(L("Audio MIDI Setup…"), #selector(openAudioMIDISetup)))
        menu.addItem(.separator())
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(item(L("Hide Menu Bar Icon"), #selector(hideMenuBarIcon)))
        menu.addItem(.separator())
        menu.addItem(item(L("Quit MultiSoundChanger"), #selector(NSApplication.terminate), "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate) ? NSApp : self
        return item
    }

    private func refresh() {
        volume.sync()
        let level = volume.isMuted ? 0 : volume.level
        statusItem.button?.image = NSImage(
            systemSymbolName: Symbol.speaker(level: volume.level, muted: volume.isMuted),
            accessibilityDescription: L("Volume")
        )
        slider.floatValue = level
        slider.isEnabled = !volume.knobs.isEmpty
        deviceItem.title = volume.deviceName
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc private func sliderMoved() {
        volume.setLevel(slider.floatValue)
        statusItem.button?.image = NSImage(
            systemSymbolName: Symbol.speaker(level: volume.level, muted: volume.isMuted),
            accessibilityDescription: L("Volume")
        )
    }

    @objc private func openSoundSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
    }

    @objc private func openAudioMIDISetup() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.audio.AudioMIDISetup") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        try? service.status == .enabled ? service.unregister() : service.register()
        refresh()
    }

    @objc private func didWake() { keys.ensureRunning() }

    @objc private func hideMenuBarIcon() { hideIcon = true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
