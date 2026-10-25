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
    /// A key that runs this action directly (shown in the ⌘K popover). The
    /// first and second actions always also run on ↩ and ⌘↩.
    var shortcut: ActionShortcut?
    /// Drawn in red in the action popover (delete, clear).
    var isDestructive = false
    /// Draws a separator above this action in the popover.
    var startsSection = false
    /// Drawn instead of `symbol` in the popover (e.g. an app's icon).
    var icon: ItemIcon?
    /// A short label at the right of the popover row, e.g. "Default".
    var badge: String?
    /// When set, choosing the action opens this nested list inside the ⌘K
    /// popover (Esc or ← goes back) instead of running `perform`.
    var submenu: (() -> [LauncherAction])?
    let perform: () -> ActionOutcome

    init(_ title: String, symbol: String = "return", shortcut: ActionShortcut? = nil,
         isDestructive: Bool = false, startsSection: Bool = false,
         icon: ItemIcon? = nil, badge: String? = nil,
         perform: @escaping () -> ActionOutcome) {
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.isDestructive = isDestructive
        self.startsSection = startsSection
        self.icon = icon
        self.badge = badge
        self.perform = perform
    }

    /// An action that opens a nested list in the popover.
    init(_ title: String, symbol: String, shortcut: ActionShortcut? = nil, startsSection: Bool = false,
         submenu: @escaping () -> [LauncherAction]) {
        self.init(title, symbol: symbol, shortcut: shortcut, startsSection: startsSection) { .stay }
        self.submenu = submenu
    }
}

/// A key combination bound to an action, e.g. ⌃X for Delete Entry.
struct ActionShortcut: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    /// The key's symbol, e.g. "X" or "↩".
    let key: String

    /// "⌃⇧X", in the standard modifier order.
    var label: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key
    }

    func matches(_ event: NSEvent) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        return event.keyCode == keyCode && event.modifierFlags.intersection(relevant) == modifiers
    }

    static let deleteEntry = ActionShortcut(keyCode: 7, modifiers: [.control], key: "X")
    static let clearAll = ActionShortcut(keyCode: 7, modifiers: [.control, .shift], key: "X")
    static let pin = ActionShortcut(keyCode: 35, modifiers: [.command, .shift], key: "P")
    static let pastePlain = ActionShortcut(keyCode: 9, modifiers: [.command, .shift], key: "V")
    static let open = ActionShortcut(keyCode: 31, modifiers: [.command], key: "O")
    static let reveal = ActionShortcut(keyCode: 3, modifiers: [.command, .shift], key: "F")
    static let openWith = ActionShortcut(keyCode: 31, modifiers: [.command, .shift], key: "O")
    static let copyHex = ActionShortcut(keyCode: 8, modifiers: [.command, .shift], key: "C")
    static let copyRGB = ActionShortcut(keyCode: 8, modifiers: [.command, .option], key: "C")
}

enum ItemIcon: Equatable {
    case file(String)
    case symbol(String)
    /// A white symbol on a colored tile (built-in commands; see IconTint).
    case tinted(String, IconTint)
    case text(String)
    /// A filled color swatch (sRGB components 0...1), e.g. Color History rows.
    case swatch(red: Double, green: Double, blue: Double)
    /// A small image file drawn as a thumbnail (clipboard images).
    case thumbnail(String)

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
    /// Grid screens: the section header this item appears under. Items of a
    /// section must be consecutive.
    var section: String? = nil
}

/// How the launcher draws a screen's items.
enum ScreenPresentation: Equatable {
    case list
    /// Large glyph cells, grouped by `LauncherItem.section`. Arrow keys move
    /// in two dimensions and the footer shows the selected item's title.
    case grid(columns: Int)
    /// A compact list (grouped by `LauncherItem.section`) on the left and a
    /// detail pane for the selection on the right. The screen must conform
    /// to `SplitDetailScreen`.
    case split
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
    var presentation: ScreenPresentation { get }
    /// Whether the screen's title is shown as a pill in the search bar.
    var showsBreadcrumb: Bool { get }
}

extension ListScreen {
    func dismissed() {}
    var presentation: ScreenPresentation { .list }
    var showsBreadcrumb: Bool { true }
}

/// A screen with a dropdown filter at the right of the search bar (⌘P opens it).
protocol FilterableScreen: ListScreen {
    var filterOptions: [ScreenFilterOption] { get }
    var selectedFilterID: String { get }
    func selectFilter(_ id: String)
}

struct ScreenFilterOption: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
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
    private var appPaths: [String: String?] = [:]
    private let thumbnails = NSCache<NSString, NSImage>()

    func icon(forPath path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 32, height: 32)
        cache[path] = image
        return image
    }

    /// The installed app's path for a bundle ID, if any.
    func appPath(bundleID: String) -> String? {
        if let cached = appPaths[bundleID] { return cached }
        let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
        appPaths[bundleID] = path
        return path
    }

    /// A small image file (e.g. a clipboard thumbnail), cached by path.
    func thumbnail(forPath path: String) -> NSImage? {
        if let cached = thumbnails.object(forKey: path as NSString) { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        thumbnails.setObject(image, forKey: path as NSString)
        return image
    }
}
