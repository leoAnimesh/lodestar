import AppKit
import Combine
import LodestarCore

/// Drives the launcher UI: a stack of list screens, the query, selection,
/// detail view and toasts. Everything here runs on the main thread.
final class LauncherViewModel: ObservableObject, ScreenHost {
    @Published var query: String = "" {
        didSet { if query != oldValue { refresh() } }
    }
    @Published private(set) var items: [LauncherItem] = []
    @Published var selectedIndex: Int = 0
    @Published private(set) var detail: (title: String, text: String)?
    @Published private(set) var toast: String?
    @Published private(set) var focusToken = 0
    @Published private(set) var stack: [ListScreen]

    let frecency: FrecencyStore
    var onHide: (() -> Void)?

    private var savedQueries: [String] = []
    private var toastWork: DispatchWorkItem?

    init(root: ListScreen, frecency: FrecencyStore) {
        self.stack = [root]
        self.frecency = frecency
        root.host = self
    }

    var currentScreen: ListScreen { stack[stack.count - 1] }
    var placeholder: String { currentScreen.placeholder }
    var breadcrumb: String? { stack.count > 1 ? currentScreen.title : nil }
    var selectedItem: LauncherItem? { items.indices.contains(selectedIndex) ? items[selectedIndex] : nil }

    // MARK: Lifecycle

    /// Called each time the panel is shown.
    func prepareForShow() {
        popToRoot()
        query = ""
        detail = nil
        refresh()
        focusToken += 1
    }

    func refresh() {
        items = currentScreen.search(query)
        selectedIndex = 0
    }

    // MARK: Navigation

    func push(_ screen: ListScreen) {
        screen.host = self
        savedQueries.append(query)
        stack.append(screen)
        query = ""
        refresh()
        focusToken += 1
    }

    func pop() {
        guard stack.count > 1 else { return }
        stack.removeLast().dismissed()
        query = savedQueries.popLast() ?? ""
        refresh()
        focusToken += 1
    }

    func popToRoot() {
        while stack.count > 1 { stack.removeLast().dismissed() }
        savedQueries.removeAll()
    }

    // MARK: Keyboard

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + items.count) % items.count
    }

    /// Escape: close detail, then pop, then clear query, then hide.
    func escape() {
        if detail != nil { detail = nil; focusToken += 1; return }
        if stack.count > 1 { pop(); return }
        if !query.isEmpty { query = ""; return }
        hideLauncher()
    }

    func runSelected(actionIndex: Int = 0) {
        guard let item = selectedItem, item.actions.indices.contains(actionIndex) else { return }
        run(item.actions[actionIndex], of: item)
    }

    /// ⌘K: show every action of the selected item as its own list.
    func showActionPanel() {
        guard let item = selectedItem, item.actions.count > 1 else { return }
        push(ActionPanelScreen(item: item, owner: self))
    }

    func run(_ action: LauncherAction, of item: LauncherItem) {
        if item.tracksUsage { frecency.recordUse(of: item.id) }
        handle(action.perform())
    }

    func handle(_ outcome: ActionOutcome) {
        switch outcome {
        case .close:
            hideLauncher()
        case .closeThen(let work):
            hideLauncher()
            // Give the window server a moment to return focus to the user's app.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        case .stay:
            break
        case .push(let screen):
            push(screen)
        case .detail(let title, let text):
            showDetail(title: title, text: text)
        case .toast(let message):
            showToast(message)
        }
    }

    // MARK: ScreenHost

    func setItems(_ newItems: [LauncherItem], for screen: ListScreen) {
        guard screen === currentScreen else { return }
        let previousID = selectedItem?.id
        items = newItems
        selectedIndex = newItems.firstIndex { $0.id == previousID } ?? 0
    }

    func showToast(_ message: String) {
        toast = message
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    func showDetail(title: String, text: String) {
        detail = (title, text)
    }

    func hideLauncher() {
        onHide?()
    }
}

/// The ⌘K action list for one item.
final class ActionPanelScreen: ListScreen {
    let title: String
    let placeholder = "Search actions…"
    weak var host: ScreenHost?
    private let item: LauncherItem
    private weak var owner: LauncherViewModel?

    init(item: LauncherItem, owner: LauncherViewModel) {
        self.item = item
        self.owner = owner
        self.title = "Actions — \(item.title)"
    }

    func search(_ query: String) -> [LauncherItem] {
        let base = item
        let rows = item.actions.enumerated().map { index, action -> LauncherItem in
            LauncherItem(
                id: "action:\(index)",
                title: action.title,
                subtitle: nil,
                icon: .symbol(action.symbol),
                accessory: index == 0 ? "↩" : index == 1 ? "⌘↩" : nil,
                actions: [LauncherAction(action.title, symbol: action.symbol) { [weak self] in
                    guard let owner = self?.owner else { return .stay }
                    owner.pop()
                    if base.tracksUsage { owner.frecency.recordUse(of: base.id) }
                    return action.perform()
                }],
                tracksUsage: false
            )
        }
        guard !query.isEmpty else { return rows }
        return rows.filter { FuzzyMatcher.match(query, in: $0.title) != nil }
    }
}
