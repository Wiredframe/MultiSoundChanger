import AppKit

/// Intercepts the volume keys (hardware and F-keys) through a session event tap.
/// Needs Accessibility access. The handler decides per key press whether to swallow it;
/// keys that are passed on reach macOS as usual.
@MainActor
final class MediaKeys {
    enum Key { case up, down, mute }

    /// Return true to consume the key press.
    var handler: (_ key: Key, _ fine: Bool, _ isRepeat: Bool) -> Bool = { _, _, _ in false }
    private var tap: CFMachPort?
    private var retry: Timer?

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Starts the tap, asking for Accessibility access once and retrying until it is granted.
    func start() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        guard !install() else { return }
        retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                if self.install() { self.retry?.invalidate(); self.retry = nil }
            }
        }
    }

    /// Re-enables or recreates the tap, e.g. after sleep, when macOS may have switched it off.
    func ensureRunning() {
        if let tap, !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
        if !isRunning { tap = nil; _ = install() }
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func install() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.systemDefined.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    fileprivate func handle(_ event: CGEvent) -> Bool {
        guard let event = NSEvent(cgEvent: event), event.subtype.rawValue == 8 else { return false }
        let data = event.data1
        let key: Key
        switch (data & 0xFFFF_0000) >> 16 {
        case Int(NX_KEYTYPE_SOUND_UP): key = .up
        case Int(NX_KEYTYPE_SOUND_DOWN): key = .down
        case Int(NX_KEYTYPE_MUTE): key = .mute
        default: return false
        }
        let isDown = (data & 0xFF00) >> 8 == 0xA
        let isRepeat = data & 0x1 == 1
        let fine = event.modifierFlags.isSuperset(of: [.shift, .option])
        // Ask on key down only; key up follows the same decision so macOS never sees half a press.
        if isDown { lastDecision = handler(key, fine, isRepeat) }
        return lastDecision
    }

    private var lastDecision = false
}

private func tapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let keys = Unmanaged<MediaKeys>.fromOpaque(refcon).takeUnretainedValue()
    // The tap's run loop source is on the main run loop, so this runs on the main thread.
    nonisolated(unsafe) let event = event
    let consume: Bool = MainActor.assumeIsolated {
        // macOS disables a tap that is too slow or after secure input; switch it straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            keys.reenable()
            return false
        }
        return keys.handle(event)
    }
    return consume ? nil : Unmanaged.passUnretained(event)
}
