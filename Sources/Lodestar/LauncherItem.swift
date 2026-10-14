import AppKit

/// What happens after an action runs.
enum ActionOutcome {
    /// Hide the launcher.
    case close
    /// Hide the launcher, then run the closure (e.g. paste or move a window
    /// once the user's app is frontmost again).
    case closeThen(() -> Void)
    /// Keep the launcher open, unchanged.
    case stay
    /// Push a new list screen (sub-command, extension, clipboard history...).
    case push(ListScreen)
    /// Show a full-text detail view.
    case detail(title: String, text: String)
    /// Keep open and flash a short message.
    case toast(String)
}

struct LauncherAction {
    let title: String
    let symbol: String
    let perform: () -> ActionOutcome

    init(_ title: String, symbol: String = "return", perform: @escaping () -> ActionOutcome) {
        self.title = title
        self.symbol = symbol
        self.perform = perform
    }
}

enum ItemIcon: Equatable {
    case file(String)
    case symbol(String)
    /// A white symbol on a colored tile (built-in commands; see IconTint).
    case tinted(String, IconTint)
    case text(String)
    /// A filled color swatch (sRGB components 0...1), e.g. Color History rows.
    case swatch(red: Double, green: Double, blue: Double)

    /// Extension/script icons may be an emoji, an SF Symbol name prefixed
    /// with "sf:", or an absolute file path.
    static func parse(_ raw: String?, fallback: String) -> ItemIcon {
        guard let raw, !raw.isEmpty else { return .symbol(fallback) }
        if raw.hasPrefix("sf:") { return .symbol(String(raw.dropFirst(3))) }
        if raw.hasPrefix("/") { return .file(raw) }
        return .text(raw)
    }
}

struct LauncherItem: Identifiable {
    let id: String
    var title: String
    var subtitle: String?
    var icon: ItemIcon
    var accessory: String?
    var keywords: [String] = []
    /// First action runs on Return, second on ⌘Return, all on ⌘K.
    var actions: [LauncherAction]
    var matchedIndices: [Int] = []
    /// Whether launching this item counts toward frecency ranking.
    var tracksUsage = true
}

/// One level of the launcher's navigation stack.
protocol ListScreen: AnyObject {
    var title: String { get }
    var placeholder: String { get }
    /// Weak back-reference so async screens can push results and messages.
    var host: ScreenHost? { get set }
    /// Called whenever the query changes. Screens may call
    /// `host?.setItems(_:for:)` later for asynchronous results.
    func search(_ query: String) -> [LauncherItem]
    /// Called when the screen is popped or the launcher hides.
    func dismissed()
}

extension ListScreen {
    func dismissed() {}
}

protocol ScreenHost: AnyObject {
    func setItems(_ items: [LauncherItem], for screen: ListScreen)
    func showToast(_ message: String)
    func showDetail(title: String, text: String)
    func hideLauncher()
}

/// Caches app/file icons; NSWorkspace icon lookup is relatively slow.
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(forPath path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 32, height: 32)
        cache[path] = image
        return image
    }
}
