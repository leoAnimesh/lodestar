import AppKit
import SwiftUI
import LodestarCore

/// A borderless, floating, non-activating panel. Non-activating means the
/// user's current app stays frontmost while we take keyboard focus, so
/// "paste" and "window management" actions target the right app.
///
/// It is deliberately *not* `.titled`: a titled window (even with a hidden,
/// transparent title bar) makes SwiftUI reserve a ~28pt title-bar safe area,
/// which showed up as an empty band above the search field.
final class LauncherPanel: NSPanel {
    static let size = NSSize(width: 700, height: 440)

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(origin: .zero, size: LauncherPanel.size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
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
        visual.layer?.cornerCurve = .continuous
        visual.layer?.borderWidth = 0.5
        visual.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let hosting = NSHostingView(rootView: rootView.ignoresSafeArea())
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

    /// Places the panel on the screen containing the mouse (Settings › General › Launcher Position).
    func position(_ position: LauncherPosition) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        setFrameOrigin(position.origin(panelSize: frame.size, visibleFrame: visible))
    }
}
