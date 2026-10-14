import SwiftUI

struct LauncherView: View {
    @ObservedObject var model: LauncherViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.5)
            if let detail = model.detail {
                DetailView(title: detail.title, text: detail.text)
            } else if model.items.isEmpty {
                emptyState
            } else {
                resultsList
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: LauncherPanel.size.width, height: LauncherPanel.size.height, alignment: .top)
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { _ in searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            if let crumb = model.breadcrumb {
                Text(crumb)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                    .lineLimit(1)
            } else {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 18))
            }
            TextField(model.placeholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .light))
                .focused($searchFocused)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
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

    private var footer: some View {
        HStack(spacing: 14) {
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
            } else {
                Text("Lodestar").foregroundStyle(.tertiary)
            }
            Spacer()
            if let item = model.selectedItem, model.detail == nil {
                if let first = item.actions.first { hint(first.title, "↩") }
                if item.actions.count > 1 { hint("Actions", "⌘K") }
            }
            hint(model.detail != nil || model.stack.count > 1 ? "Back" : "Close", "esc")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .frame(height: 34)
    }

    private func hint(_ label: String, _ key: String) -> some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary)
            Text(key)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                .foregroundStyle(.secondary)
        }
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

    var body: some View {
        switch icon {
        case .file(let path):
            Image(nsImage: IconCache.shared.icon(forPath: path)).resizable().aspectRatio(contentMode: .fit)
        case .tinted(let name, let tint):
            TintedSymbolTile(symbol: name, tint: tint, size: 26)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
        case .text(let text):
            Text(text).font(.system(size: 18))
        case .swatch(let r, let g, let b):
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.sRGB, red: r, green: g, blue: b, opacity: 1))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                .frame(width: 22, height: 22)
                .frame(width: 26, height: 26)
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
