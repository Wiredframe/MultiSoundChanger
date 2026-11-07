import AppKit

/// A small volume indicator in the top right corner of the screen with the mouse pointer.
/// Replaces the private OSD framework, which no longer shows anything on current macOS.
@MainActor
final class HUD {
    private let panel: NSPanel
    private let icon = NSImageView()
    private let bar = LevelBar()
    private var hideTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 24
        background.layer?.cornerCurve = .continuous
        panel.contentView = background

        icon.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        icon.contentTintColor = .labelColor
        for view in [icon, bar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            bar.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            bar.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            bar.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: 6)
        ])
    }

    func show(level: Float, muted: Bool) {
        icon.image = NSImage(systemSymbolName: Symbol.speaker(level: level, muted: muted), accessibilityDescription: nil)
        bar.level = muted ? 0 : CGFloat(level)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.maxX - panel.frame.width - 12, y: area.maxY - panel.frame.height - 12))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [panel] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await NSAnimationContext.runAnimationGroup { $0.duration = 0.3; panel.animator().alphaValue = 0 }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }
}

private final class LevelBar: NSView {
    var level: CGFloat = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        guard level > 0 else { return }
        var filled = bounds
        filled.size.width = max(bounds.height, bounds.width * min(level, 1))
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}

enum Symbol {
    static func speaker(level: Float, muted: Bool) -> String {
        if muted || level < 0.001 { return "speaker.slash.fill" }
        if level < 1 / 3 { return "speaker.wave.1.fill" }
        if level < 2 / 3 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
