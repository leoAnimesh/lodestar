import AppKit
import Combine
import LodestarCore

/// Drives the launcher UI: a stack of list screens, the query, selection,
/// detail view and toasts. Everything here runs on the main thread.
final class LauncherViewModel: ObservableObject, ScreenHost {
    @Published var query: String = "" {
        didSet { if query != oldValue { refresh() } }
    }
    @Published private(set) var items: [LauncherItem] = [] {
        didSet { gridSections = LauncherViewModel.sections(of: items) }
    }
    /// Consecutive runs of `items` that share a `section` (grid screens).
    private(set) var gridSections: [GridSection] = []
    @Published var selectedIndex: Int = 0
    @Published private(set) var detail: (title: String, text: String)?
    @Published private(set) var toast: String?
    @Published private(set) var focusToken = 0
    @Published private(set) var stack: [ListScreen]
    /// The ⌘K popover, when open. It floats over the list; the list keeps its
    /// selection so the actions apply to the selected item.
    @Published private(set) var actionPanel: ActionPanelState?
    /// The filter dropdown of a `FilterableScreen`, when open: the highlighted option.
    @Published private(set) var filterMenuHighlight: Int?

    let frecency: FrecencyStore
    var onHide: (() -> Void)?

    private var savedQueries: [String] = []
    /// The selected item's ID on each screen below the top, restored on pop.
    private var savedSelections: [String?] = []
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
    var presentation: ScreenPresentation { currentScreen.presentation }
    var filterableScreen: FilterableScreen? { currentScreen as? FilterableScreen }
    var isActionPanelOpen: Bool { actionPanel != nil }

    struct ActionPanelState {
        let item: LauncherItem
        var query = ""
        var selected = 0

        struct Row: Identifiable {
            /// Index in `item.actions`.
            let index: Int
            let action: LauncherAction
            /// "↩", "⌘↩" or the action's own shortcut.
            let shortcut: String?
            /// Separator above (only when unfiltered).
            let separated: Bool
            var id: Int { index }
        }

        var rows: [Row] {
            let all = item.actions.enumerated().map { index, action in
                Row(index: index, action: action,
                    shortcut: index == 0 ? "↩" : index == 1 ? "⌘↩" : action.shortcut?.label,
                    separated: index > 0 && action.startsSection)
            }
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { return all }
            return all.filter { FuzzyMatcher.match(q, in: $0.action.title) != nil }
                .map { Row(index: $0.index, action: $0.action, shortcut: $0.shortcut, separated: false) }
        }
    }

    struct GridSection: Identifiable {
        let title: String
        let range: Range<Int>
        var id: String { "\(range.lowerBound):\(title)" }
    }

    static func sections(of items: [LauncherItem]) -> [GridSection] {
        var result: [GridSection] = []
        var start = 0
        for i in items.indices where i == items.count - 1 || items[i + 1].section != items[i].section {
            result.append(GridSection(title: items[i].section ?? "", range: start..<(i + 1)))
            start = i + 1
        }
        return result
    }

    // MARK: Lifecycle

    /// Called each time the panel is shown.
    func prepareForShow() {
        closeOverlays()
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
        closeOverlays()
        screen.host = self
        savedQueries.append(query)
        savedSelections.append(selectedItem?.id)
        stack.append(screen)
        query = ""
        refresh()
        focusToken += 1
    }

    func pop() {
        guard stack.count > 1 else { return }
        closeOverlays()
        stack.removeLast().dismissed()
        let selectedID = savedSelections.popLast() ?? nil
        query = savedQueries.popLast() ?? ""
        refresh()
        // Come back to the item that was selected (e.g. after ⌘K in a grid).
        if let selectedID, let index = items.firstIndex(where: { $0.id == selectedID }) { selectedIndex = index }
        focusToken += 1
    }

    func popToRoot() {
        while stack.count > 1 { stack.removeLast().dismissed() }
        savedQueries.removeAll()
        savedSelections.removeAll()
    }

    // MARK: Keyboard

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + items.count) % items.count
    }

    /// Arrow keys on a grid screen. Returns false on list screens, where
    /// left/right belong to the text field.
    func moveInGrid(_ direction: SectionedGrid.Direction) -> Bool {
        guard case .grid(let columns) = presentation, detail == nil, !items.isEmpty else { return false }
        let grid = SectionedGrid(sectionSizes: gridSections.map(\.range.count), columns: columns)
        selectedIndex = grid.move(from: selectedIndex, direction)
        return true
    }

    /// Backspace with an empty query goes back from a pushed screen.
    func backspaceOnEmptyQuery() -> Bool {
        guard query.isEmpty, detail == nil, stack.count > 1, actionPanel == nil, filterMenuHighlight == nil else { return false }
        pop()
        return true
    }

    /// Escape: close a popover, then detail, then pop, then clear query, then hide.
    func escape() {
        if actionPanel != nil { closeActionPanel(); return }
        if filterMenuHighlight != nil { filterMenuHighlight = nil; return }
        if detail != nil { detail = nil; focusToken += 1; return }
        if stack.count > 1 { pop(); return }
        if !query.isEmpty { query = ""; return }
        hideLauncher()
    }

    func runSelected(actionIndex: Int = 0) {
        guard let item = selectedItem, item.actions.indices.contains(actionIndex) else { return }
        run(item.actions[actionIndex], of: item)
    }

    // MARK: Action popover (⌘K)

    /// ⌘K or the footer's Actions button: opens or closes the popover.
    func toggleActionPanel() {
        if actionPanel != nil { closeActionPanel(); return }
        guard detail == nil, let item = selectedItem, !item.actions.isEmpty else { return }
        filterMenuHighlight = nil
        actionPanel = ActionPanelState(item: item)
    }

    func closeActionPanel() {
        guard actionPanel != nil else { return }
        actionPanel = nil
        focusToken += 1
    }

    var actionPanelQuery: String {
        get { actionPanel?.query ?? "" }
        set {
            guard actionPanel != nil, newValue != actionPanel?.query else { return }
            actionPanel?.query = newValue
            actionPanel?.selected = 0
        }
    }

    func moveActionSelection(_ delta: Int) {
        guard let panel = actionPanel else { return }
        let count = panel.rows.count
        guard count > 0 else { return }
        actionPanel?.selected = (panel.selected + delta + count) % count
    }

    /// Runs the highlighted row (or the row at `rowIndex` when clicked).
    func runActionPanelRow(_ rowIndex: Int? = nil) {
        guard let panel = actionPanel else { return }
        let rows = panel.rows
        let index = rowIndex ?? panel.selected
        guard rows.indices.contains(index) else { return }
        let action = rows[index].action
        closeActionPanel()
        run(action, of: panel.item)
    }

    /// A key bound to one of the selected item's actions (e.g. ⌃X). Works
    /// with or without the popover open.
    func runShortcut(_ event: NSEvent) -> Bool {
        guard detail == nil, let item = actionPanel?.item ?? selectedItem,
              let action = item.actions.first(where: { $0.shortcut?.matches(event) == true }) else { return false }
        closeActionPanel()
        run(action, of: item)
        return true
    }

    // MARK: Filter dropdown (⌘P)

    func toggleFilterMenu() {
        guard let screen = filterableScreen else { return }
        if filterMenuHighlight != nil { filterMenuHighlight = nil; return }
        closeActionPanel()
        filterMenuHighlight = screen.filterOptions.firstIndex { $0.id == screen.selectedFilterID } ?? 0
    }

    func moveFilterHighlight(_ delta: Int) {
        guard let highlight = filterMenuHighlight, let count = filterableScreen?.filterOptions.count, count > 0 else { return }
        filterMenuHighlight = (highlight + delta + count) % count
    }

    func highlightFilter(_ index: Int) {
        guard filterMenuHighlight != nil, filterMenuHighlight != index else { return }
        filterMenuHighlight = index
    }

    func chooseFilter(_ index: Int? = nil) {
        guard let screen = filterableScreen, let i = index ?? filterMenuHighlight,
              screen.filterOptions.indices.contains(i) else { return }
        filterMenuHighlight = nil
        screen.selectFilter(screen.filterOptions[i].id)
        refresh()
        focusToken += 1
    }

    private func closeOverlays() {
        actionPanel = nil
        filterMenuHighlight = nil
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
