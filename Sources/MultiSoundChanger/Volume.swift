import CoreAudio

/// One settable volume control: the main element or a single channel of an output device.
struct Knob: Hashable {
    let device: AudioObjectID
    let element: AudioObjectPropertyElement

    var address: AudioObjectPropertyAddress {
        CA.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, element)
    }
}

/// Controls the volume of the default output device as a whole.
///
/// For a multi-output (aggregate) device every volume control of every sub-device is scaled
/// proportionally: the loudest control follows the group level and all others keep their ratio
/// to it. That preserves per-device levels and channel balance (including channels set to 0),
/// which the original app overwrote with one shared value.
@MainActor
final class VolumeController {
    /// Relative level of each control, the loudest one is 1.
    private var ratios: [Knob: Float] = [:]
    /// Values as last written (and read back), used to notice changes made elsewhere.
    private var written: [Knob: Float] = [:]
    private(set) var level: Float = 0
    /// Fallback mute for devices without a mute control: the level to restore.
    private var softMuteLevel: Float?

    var device: AudioObjectID { CA.defaultOutputDevice }
    var deviceName: String { CA.string(device, kAudioObjectPropertyName) ?? "" }
    var isAggregate: Bool { CA.isAggregate(device) }

    /// Output devices whose volume is controlled: the sub-devices of an aggregate, otherwise the device itself.
    var devices: [AudioObjectID] {
        let device = device
        guard CA.isAggregate(device) else { return [device] }
        let subs = CA.ids(device, CA.address(kAudioAggregateDevicePropertyActiveSubDeviceList))
        return subs.filter { CA.outputChannelCount($0) > 0 }
    }

    var knobs: [Knob] {
        devices.flatMap { device in
            (0...UInt32(CA.outputChannelCount(device)))
                .map { Knob(device: device, element: $0) }
                .filter { CA.isSettable(device, $0.address) }
        }
    }

    var isMuted: Bool {
        if softMuteLevel != nil { return true }
        let mutable = devices.filter { CA.isSettable($0, muteAddress) }
        return !mutable.isEmpty && mutable.allSatisfy { CA.value($0, muteAddress, UInt32(0)) == 1 }
    }

    /// Re-reads the hardware. Ratios are only re-derived when something changed outside this app,
    /// so they survive the group level passing through 0 and rounding by the devices.
    func sync() {
        let knobs = knobs
        let values = knobs.map { CA.value($0.device, $0.address, Float32(0)) ?? 0 }
        let changedElsewhere = Set(knobs) != Set(ratios.keys)
            || zip(knobs, values).contains { abs($1 - (written[$0] ?? -1)) > 0.01 }
        guard changedElsewhere else { return }

        let loudest = values.max() ?? 0
        level = loudest
        if loudest > 0.001 {
            ratios = Dictionary(uniqueKeysWithValues: zip(knobs, values.map { $0 / loudest }))
        } else {
            ratios = Dictionary(uniqueKeysWithValues: knobs.map { ($0, Float(1)) })
        }
        written = Dictionary(uniqueKeysWithValues: zip(knobs, values))
        if loudest > 0.001 { softMuteLevel = nil }
    }

    func setLevel(_ newLevel: Float) {
        sync()
        if isMuted { setMuted(false) }
        apply(min(max(newLevel, 0), 1))
    }

    /// Steps like macOS: 16 steps, or 64 with Shift and Option held.
    func step(up: Bool, fine: Bool) {
        sync()
        if isMuted { setMuted(false) }
        let size: Float = fine ? 1 / 64 : 1 / 16
        let current = (level / size).rounded() * size
        apply(min(max(current + (up ? size : -size), 0), 1))
    }

    func toggleMute() {
        sync()
        setMuted(!isMuted)
    }

    private let muteAddress = CA.address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)

    private func setMuted(_ muted: Bool) {
        let mutable = devices.filter { CA.isSettable($0, muteAddress) }
        if mutable.isEmpty {
            if muted {
                softMuteLevel = level
                apply(0, keepLevel: true)
            } else if let restore = softMuteLevel {
                softMuteLevel = nil
                apply(restore)
            }
        } else {
            for device in mutable { CA.set(device, muteAddress, UInt32(muted ? 1 : 0)) }
        }
    }

    private func apply(_ newLevel: Float, keepLevel: Bool = false) {
        for knob in knobs {
            CA.set(knob.device, knob.address, Float32(newLevel * (ratios[knob] ?? 1)))
            written[knob] = CA.value(knob.device, knob.address, Float32(0))
        }
        if !keepLevel { level = newLevel }
    }
}
