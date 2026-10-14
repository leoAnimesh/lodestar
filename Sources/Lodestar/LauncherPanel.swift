import AppKit
import SwiftUI

/// A borderless, floating, non-activating panel. Non-activating means the
/// user's current app stays frontmost while we take keyboard focus, so
/// "paste" and "window management" actions target the right app.
final class LauncherPanel: NSPanel {
    static let size = NSSize(width: 700, height: 440)

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(origin: .zero, size: LauncherPanel.size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        let visual = NSVisualEffectView()
        visual.material = .popover
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 14
        visual.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: visual.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: visual.bottomAnchor),
        ])
        contentView = visual
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Centers horizontally on the screen containing the mouse, in the upper third.
    func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.minY + visible.height * 0.68 - frame.height / 2
        )
        setFrameOrigin(origin)
    }
}
