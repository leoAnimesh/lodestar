import SwiftUI

/// The small floating surface shared by the ⌘K action popover and the filter
/// dropdown: material background, hairline border, soft shadow.
struct PopoverSurface: ViewModifier {
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(.regularMaterial))
            .background(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.55)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.13), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
    }
}

extension View {
    func popoverSurface(cornerRadius: CGFloat = 10) -> some View { modifier(PopoverSurface(cornerRadius: cornerRadius)) }
}

/// A key hint such as "⌘K" in a small rounded cap.
struct KeyCap: View {
    let text: String
    var prominent = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(prominent ? 0.14 : 0.08)))
    }
}

/// The ⌘K popover: the selected item's actions, a filter field at the bottom.
struct ActionPopover: View {
    @ObservedObject var model: LauncherViewModel
    var filterFocused: FocusState<LauncherView.Focus?>.Binding

    static let width: CGFloat = 320
    private let rowHeight: CGFloat = 30
    private let maxListHeight: CGFloat = 300

    var body: some View {
        if let panel = model.actionPanel {
            let rows = panel.rows
            VStack(spacing: 0) {
                header(panel)
                list(rows, selected: panel.selected, emptyText: panel.submenu != nil && panel.query.isEmpty
                     ? "No apps can open this item" : panel.submenu != nil ? "No matching apps" : "No matching actions")
                Divider().opacity(0.6)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                    TextField(panel.submenu != nil ? "Search apps…" : "Search for actions…", text: Binding(
                        get: { model.actionPanelQuery }, set: { model.actionPanelQuery = $0 }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .focused(filterFocused, equals: .actions)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
            }
            .frame(width: ActionPopover.width)
            .popoverSurface()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Actions for \(panel.item.title)")
        }
    }

    /// The item's title; in a nested list, a back button with the list's title.
    @ViewBuilder
    private func header(_ panel: LauncherViewModel.ActionPanelState) -> some View {
        if let submenu = panel.submenu {
            Button { model.actionPanelBack() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text(submenu.title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(panel.item.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to actions (esc)")
            .accessibilityLabel("Back to actions")
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 3)
        } else {
            Text(panel.item.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 9)
                .padding(.bottom, 3)
        }
    }

    @ViewBuilder
    private func list(_ rows: [LauncherViewModel.ActionPanelState.Row], selected: Int, emptyText: String) -> some View {
        if rows.isEmpty {
            Text(emptyText)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: rowHeight + 8)
        } else {
            let separators = rows.filter(\.separated).count
            let height = min(CGFloat(rows.count) * rowHeight + CGFloat(separators) * 9 + 10, maxListHeight)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
                            if row.separated {
                                Divider().opacity(0.6).padding(.vertical, 4).padding(.horizontal, 10)
                            }
                            ActionPopoverRow(row: row, selected: position == selected, height: rowHeight)
                                .id(row.id)
                                .contentShape(Rectangle())
                                .onTapGesture { model.runActionPanelRow(position) }
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 5)
                }
                .scrollDisabledIfAvailable(CGFloat(rows.count) * rowHeight + CGFloat(separators) * 9 + 10 <= maxListHeight)
                .frame(height: height)
                .onChange(of: selected) { newValue in
                    if rows.indices.contains(newValue) { proxy.scrollTo(rows[newValue].id) }
                }
            }
        }
    }
}

struct ActionPopoverRow: View {
    let row: LauncherViewModel.ActionPanelState.Row
    let selected: Bool
    let height: CGFloat

    var body: some View {
        let tint: Color = row.action.isDestructive ? .red : .primary
        HStack(spacing: 9) {
            if let icon = row.action.icon {
                ItemIconView(icon: icon, size: 16)
            } else {
                Image(systemName: row.action.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(row.action.isDestructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                    .frame(width: 16, height: 16)
            }
            Text(row.action.title)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let badge = row.action.badge {
                Text(badge)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if row.action.submenu != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            if let shortcut = row.shortcut {
                HStack(spacing: 3) {
                    ForEach(Array(ActionPopoverRow.keys(shortcut).enumerated()), id: \.offset) { _, key in
                        KeyCap(text: key, prominent: selected)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(selected ? Color.primary.opacity(0.11) : Color.clear))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// "⌃⇧X" → ["⌃", "⇧", "X"], so each key gets its own cap.
    static func keys(_ shortcut: String) -> [String] {
        var keys: [String] = []
        var rest = Substring(shortcut)
        let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        while let first = rest.first, modifiers.contains(first), rest.count > 1 {
            keys.append(String(first))
            rest = rest.dropFirst()
        }
        if !rest.isEmpty { keys.append(String(rest)) }
        return keys
    }
}

/// The filter dropdown's button in the search bar ("All Types ⌄").
struct FilterDropdownButton: View {
    @ObservedObject var model: LauncherViewModel

    var body: some View {
        if let screen = model.filterableScreen {
            let option = screen.filterOptions.first { $0.id == screen.selectedFilterID }
            let open = model.filterMenuHighlight != nil
            Button { model.toggleFilterMenu() } label: {
                HStack(spacing: 6) {
                    Image(systemName: option?.symbol ?? "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(option?.title ?? "All")
                        .font(.system(size: 12.5))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(open ? 0.13 : 0.07)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Filter by type (⌘P)")
            .accessibilityLabel("Filter: \(option?.title ?? "All")")
        }
    }
}

/// The open filter dropdown, anchored under its button.
struct FilterMenu: View {
    @ObservedObject var model: LauncherViewModel

    var body: some View {
        if let screen = model.filterableScreen, let highlight = model.filterMenuHighlight {
            VStack(spacing: 0) {
                ForEach(Array(screen.filterOptions.enumerated()), id: \.element.id) { index, option in
                    HStack(spacing: 8) {
                        Image(systemName: option.symbol)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(option.title).font(.system(size: 13))
                        Spacer(minLength: 6)
                        if option.id == screen.selectedFilterID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(index == highlight ? Color.primary.opacity(0.11) : Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture { model.chooseFilter(index) }
                    .onHover { inside in if inside { model.highlightFilter(index) } }
                }
            }
            .padding(5)
            .frame(width: 184)
            .popoverSurface(cornerRadius: 9)
        }
    }
}

extension View {
    /// `scrollDisabled` is macOS 13+; this keeps call sites tidy.
    @ViewBuilder
    func scrollDisabledIfAvailable(_ disabled: Bool) -> some View {
        if #available(macOS 13.0, *) { self.scrollDisabled(disabled) } else { self }
    }
}
