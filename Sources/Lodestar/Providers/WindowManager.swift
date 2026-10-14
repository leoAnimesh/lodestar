import AppKit
import ApplicationServices

/// Moves/resizes the focused window of the frontmost app through the
/// Accessibility API (AXUIElement). Requires the Accessibility permission.
enum WindowManager {
    enum Layout: String, CaseIterable {
        case leftHalf = "Left Half", rightHalf = "Right Half"
        case topHalf = "Top Half", bottomHalf = "Bottom Half"
        case leftThird = "First Third", centerThird = "Center Third", rightThird = "Last Third"
        case leftTwoThirds = "First Two Thirds", rightTwoThirds = "Last Two Thirds"
        case maximize = "Maximize", almostMaximize = "Almost Maximize"
        case center = "Center", nextDisplay = "Next Display"

        var symbol: String {
            switch self {
            case .leftHalf: return "rectangle.lefthalf.filled"
            case .rightHalf: return "rectangle.righthalf.filled"
            case .topHalf: return "rectangle.tophalf.filled"
            case .bottomHalf: return "rectangle.bottomhalf.filled"
            case .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds: return "rectangle.split.3x1"
            case .maximize: return "rectangle.fill"
            case .almostMaximize: return "rectangle.inset.filled"
            case .center: return "rectangle.center.inset.filled"
            case .nextDisplay: return "display.2"
            }
        }

        /// Target rect in Cocoa coordinates (bottom-left origin) within `visible`.
        func frame(in visible: CGRect, current: CGRect) -> CGRect {
            let v = visible
            switch self {
            case .leftHalf: return CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height)
            case .rightHalf: return CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height)
            case .topHalf: return CGRect(x: v.minX, y: v.midY, width: v.width, height: v.height / 2)
            case .bottomHalf: return CGRect(x: v.minX, y: v.minY, width: v.width, height: v.height / 2)
            case .leftThird: return CGRect(x: v.minX, y: v.minY, width: v.width / 3, height: v.height)
            case .centerThird: return CGRect(x: v.minX + v.width / 3, y: v.minY, width: v.width / 3, height: v.height)
            case .rightThird: return CGRect(x: v.minX + 2 * v.width / 3, y: v.minY, width: v.width / 3, height: v.height)
            case .leftTwoThirds: return CGRect(x: v.minX, y: v.minY, width: 2 * v.width / 3, height: v.height)
            case .rightTwoThirds: return CGRect(x: v.minX + v.width / 3, y: v.minY, width: 2 * v.width / 3, height: v.height)
            case .maximize: return v
            case .almostMaximize: return v.insetBy(dx: v.width * 0.05, dy: v.height * 0.05)
            case .center, .nextDisplay:
                let w = min(current.width, v.width), h = min(current.height, v.height)
                return CGRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h)
            }
        }
    }

    enum WMError: Error, CustomStringConvertible {
        case notTrusted, noFrontApp, noWindow, failed
        var description: String {
            switch self {
            case .notTrusted: return "Grant Accessibility access to Lodestar in System Settings › Privacy & Security."
            case .noFrontApp: return "No frontmost application."
            case .noWindow: return "The frontmost app has no focused window."
            case .failed: return "The window could not be moved."
            }
        }
    }

    static func apply(_ layout: Layout) -> Result<Void, WMError> {
        guard SystemActions.ensureAccessibility(prompt: true) else { return .failure(.notTrusted) }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .failure(.noFrontApp) }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef else { return .failure(.noWindow) }
        let window = windowRef as! AXUIElement

        guard let axFrame = frame(of: window) else { return .failure(.failed) }
        let cocoaFrame = toCocoa(axFrame)
        let screens = NSScreen.screens
        let center = CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)
        var screenIndex = screens.firstIndex { $0.frame.contains(center) } ?? 0
        if layout == .nextDisplay, screens.count > 1 { screenIndex = (screenIndex + 1) % screens.count }
        guard screens.indices.contains(screenIndex) else { return .failure(.failed) }

        let target = layout.frame(in: screens[screenIndex].visibleFrame, current: cocoaFrame)
        let axTarget = toAX(target)
        // Size → position → size: some apps clamp size against the old position.
        setSize(window, axTarget.size)
        setPosition(window, axTarget.origin)
        setSize(window, axTarget.size)
        return .success(())
    }

    // AX uses a top-left origin anchored at the primary display; Cocoa uses
    // bottom-left. Both share the primary screen's height as the pivot.
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private static func toCocoa(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    private static func toAX(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    private static func setPosition(_ window: AXUIElement, _ point: CGPoint) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    private static func setSize(_ window: AXUIElement, _ size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
    }
}
