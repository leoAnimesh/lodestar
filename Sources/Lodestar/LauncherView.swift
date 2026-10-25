import SwiftUI

/// A `.split` screen supplies the right-hand pane for the selected item.
protocol SplitDetailScreen: ListScreen {
    func detailView(for item: LauncherItem?) -> AnyView
    /// Shown in the list area when there are no items.
    var emptyMessage: String { get }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherViewModel
    @FocusState private var focus: Focus?

    enum Focus: Hashable { case search, actions }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.5)
            content
            Divider().opacity(0.5)
            footer
        }
        .frame(width: LauncherPanel.size.width, height: LauncherPanel.size.height, alignment: .top)
        .overlay { dimming }
        .overlay(alignment: .bottomTrailing) {
            ActionPopover(model: model, filterFocused: $focus)
                .padding(.trailing, 10)
                .padding(.bottom, LauncherView.footerHeight + 6)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottomTrailing)))
        }
        .overlay(alignment: .topTrailing) {
            FilterMenu(model: model)
                .padding(.trailing, 14)
                .padding(.top, LauncherView.searchBarHeight - 6)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
        }
        .animation(.easeOut(duration: 0.12), value: model.isActionPanelOpen)
        .animation(.easeOut(duration: 0.12), value: model.filterMenuHighlight != nil)
        .onAppear { focus = .search }
        .onChange(of: model.focusToken) { _ in focus = .search }
        .onChange(of: model.isActionPanelOpen) { open in focus = open ? .actions : .search }
    }

    static let searchBarHeight: CGFloat = 54
    static let footerHeight: CGFloat = 36

    @ViewBuilder
    private var content: some View {
        if let detail = model.detail {
            DetailView(title: detail.title, text: detail.text)
        } else if model.presentation == .split, let screen = model.currentScreen as? SplitDetailScreen {
            SplitListView(model: model, screen: screen)
        } else if model.items.isEmpty {
            emptyState
        } else if case .grid(let columns) = model.presentation {
            GlyphGrid(model: model, columns: columns)
        } else {
            resultsList
        }
    }

    /// The list stays visible, slightly dimmed, behind an open popover.
    @ViewBuilder
    private var dimming: some View {
        if model.isActionPanelOpen || model.filterMenuHighlight != nil {
            Color.black.opacity(0.10)
                .contentShape(Rectangle())
                .onTapGesture { model.escape() }
                .transition(.opacity)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            if model.stack.count > 1 {
                Button { model.pop() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back (esc)")
                .accessibilityLabel("Back")
            } else {
                LodestarStarIcon(size: 21).foregroundStyle(.secondary)
            }
            if let crumb = model.breadcrumb, model.currentScreen.showsBreadcrumb {
                Text(crumb)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                    .lineLimit(1)
            }
            TextField(model.placeholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: model.presentation == .split ? 18 : 22, weight: .light))
                .focused($focus, equals: .search)
            FilterDropdownButton(model: model)
        }
        .padding(.horizontal, 16)
        .frame(height: LauncherView.searchBarHeight)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ResultRow(item: item, selected: index == model.selectedIndex)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedIndex = index
                                model.runSelected()
                            }
                    }
                }
                .padding(8)
            }
            .onChange(of: model.selectedIndex) { newValue in
                guard model.items.indices.contains(newValue) else { return }
                proxy.scrollTo(model.items[newValue].id)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "sparkle.magnifyingglass").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "Start typing to search" : "No results")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            footerLeading.layoutPriority(-1)
            Spacer(minLength: 8)
            if model.detail == nil, let item = model.selectedItem, let primary = item.actions.first {
                Button { model.runSelected() } label: {
                    HStack(spacing: 6) {
                        Text(primary.title).foregroundStyle(.primary.opacity(0.85)).lineLimit(1)
                        KeyCap(text: "↩")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Rectangle().fill(Color.primary.opacity(0.14)).frame(width: 1, height: 14)
                Button { model.toggleActionPanel() } label: {
                    HStack(spacing: 6) {
                        Text("Actions").foregroundStyle(.secondary)
                        HStack(spacing: 3) { KeyCap(text: "⌘"); KeyCap(text: "K") }
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(model.isActionPanelOpen ? 0.12 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show all actions (⌘K)")
            } else {
                hint(model.detail != nil || model.stack.count > 1 ? "Back" : "Close", "esc")
            }
        }
        .font(.system(size: 12))
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: LauncherView.footerHeight)
    }

    @ViewBuilder
    private var footerLeading: some View {
        if let toast = model.toast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .lineLimit(1)
        } else if case .grid = model.presentation, model.detail == nil, let item = model.selectedItem {
            // Grid cells have no room for names: show the selection's here.
            HStack(spacing: 6) {
                Text(item.title).fontWeight(.medium).lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        } else {
            HStack(spacing: 6) {
                LodestarStarIcon(size: 13).foregroundStyle(.tertiary)
                Text(model.stack.count > 1 ? model.currentScreen.title : "Lodestar")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func hint(_ label: String, _ key: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            KeyCap(text: key)
        }
    }
}

/// The left half of a `.split` screen: a compact list under section headers.
struct SplitListView: View {
    @ObservedObject var model: LauncherViewModel
    let screen: SplitDetailScreen

    static let listWidth: CGFloat = 284

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if model.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 26)).foregroundStyle(.tertiary)
                        Text(screen.emptyMessage).font(.system(size: 12.5)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .frame(width: SplitListView.listWidth)
            Divider().opacity(0.6)
            screen.detailView(for: model.selectedItem)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(model.selectedItem?.id ?? "none")
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.gridSections) { section in
                        Text(section.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, section.range.lowerBound == 0 ? 4 : 10)
                            .padding(.bottom, 3)
                            .id(section.id)
                        ForEach(section.range, id: \.self) { index in
                            let item = model.items[index]
                            SplitRow(item: item, selected: index == model.selectedIndex)
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    model.selectedIndex = index
                                    model.runSelected()
                                }
                                .onTapGesture { model.selectedIndex = index }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: model.selectedIndex) { newValue in
                guard model.items.indices.contains(newValue) else { return }
                if let section = model.gridSections.first(where: { $0.range.lowerBound == newValue }) {
                    proxy.scrollTo(section.id)
                } else {
                    proxy.scrollTo(model.items[newValue].id)
                }
            }
        }
    }
}

struct SplitRow: View {
    let item: LauncherItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ItemIconView(icon: item.icon, size: 22)
            Text(item.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let accessory = item.accessory {
                Image(systemName: accessory)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.24) : Color.clear))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

struct ResultRow: View {
    let item: LauncherItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ItemIconView(icon: item.icon).frame(width: 26, height: 26)
            highlightedTitle
                .font(.system(size: 14))
                .lineLimit(1)
            if let subtitle = item.subtitle {
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let accessory = item.accessory {
                Text(accessory).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
    }

    /// Bolds the characters the fuzzy matcher aligned with the query.
    private var highlightedTitle: Text {
        guard !item.matchedIndices.isEmpty else { return Text(item.title) }
        var attributed = AttributedString()
        let matched = Set(item.matchedIndices)
        for (i, ch) in item.title.enumerated() {
            var piece = AttributedString(String(ch))
            if matched.contains(i) { piece.font = .system(size: 14, weight: .bold) }
            attributed += piece
        }
        return Text(attributed)
    }
}

struct ItemIconView: View {
    let icon: ItemIcon
    var size: CGFloat = 26

    var body: some View {
        switch icon {
        case .file(let path):
            Image(nsImage: IconCache.shared.icon(forPath: path)).resizable().aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case .tinted(let name, let tint):
            TintedSymbolTile(symbol: name, tint: tint, size: size)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.54, weight: .medium))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.23).fill(Color.primary.opacity(0.08)))
        case .text(let text):
            Text(text).font(.system(size: size * 0.7))
        case .swatch(let r, let g, let b):
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(Color(.sRGB, red: r, green: g, blue: b, opacity: 1))
                .overlay(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous).strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                .frame(width: size * 0.85, height: size * 0.85)
                .frame(width: size, height: size)
        case .thumbnail(let path):
            let shape = RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            Group {
                if let image = IconCache.shared.thumbnail(forPath: path) {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo").font(.system(size: size * 0.5)).foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.06))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
        }
    }
}

struct DetailView: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(text)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
        }
    }
}

/// The grid used by glyph screens (emoji & symbols): big cells under
/// pinned section headers, with the selection kept in view.
struct GlyphGrid: View {
    @ObservedObject var model: LauncherViewModel
    let columns: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Headers scroll with the cells (pinned headers covered the first row).
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                    ForEach(model.gridSections) { section in
                        Section {
                            ForEach(section.range, id: \.self) { index in
                                cell(index)
                            }
                        } header: {
                            header(section.title).id(section.id)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .onChange(of: model.selectedIndex) { newValue in
                guard model.items.indices.contains(newValue) else { return }
                // On a section's first row, bring its header into view too.
                if let section = model.gridSections.first(where: { $0.range.contains(newValue) }),
                   newValue - section.range.lowerBound < columns {
                    proxy.scrollTo(section.id)
                }
                proxy.scrollTo(model.items[newValue].id)
            }
            .onChange(of: model.items.first?.id) { _ in
                if let first = model.gridSections.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        let item = model.items[index]
        let selected = index == model.selectedIndex
        GlyphCell(icon: item.icon, selected: selected)
            .id(item.id)
            .help(item.title)
            .accessibilityElement()
            .accessibilityLabel(item.title)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .onTapGesture {
                model.selectedIndex = index
                model.runSelected()
            }
    }
}

struct GlyphCell: View {
    let icon: ItemIcon
    let selected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if case .text(let glyph) = icon {
                Text(glyph)
                    .font(.system(size: 34))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            } else {
                ItemIconView(icon: icon)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(shape.fill(selected ? Color.accentColor.opacity(0.26) : Color.primary.opacity(0.045)))
        .overlay(shape.strokeBorder(selected ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 2))
        .contentShape(shape)
    }
}
