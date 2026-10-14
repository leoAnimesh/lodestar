import AppKit
import SwiftUI
import LodestarCore

/// Settings › Extensions: every command (built-in, window, system, script and
/// extension) in a searchable, grouped table with enable toggles, aliases and
/// hotkeys, plus a detail pane for the selected command.
struct ExtensionsSettingsPage: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var capture: ShortcutCapture
    @State private var query = ""
    @State private var kind: CommandKind?
    @State private var selection: String?
    @State private var collapsed: Set<String> = []

    init(model: SettingsModel) {
        self.model = model
        self.capture = model.capture
    }

    private var entriesByID: [String: RootScreen.CatalogEntry] {
        Dictionary(model.catalog.map { ($0.descriptor.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var sections: [CommandCatalog.Section] {
        CommandCatalog.sections(model.catalog.map(\.descriptor), query: query, kind: kind, preferences: model.preferences)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                header
                Divider()
                list
                Divider()
                footer
            }
            .frame(width: 560)
            Divider()
            DetailPane(model: model, capture: capture, entry: selection.flatMap { entriesByID[$0] })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selection == nil { selection = sections.first?.commands.first?.id }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search commands", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))

            Picker("", selection: $kind) {
                Text("All Types").tag(CommandKind?.none)
                Divider()
                ForEach(CommandKind.allCases, id: \.self) { Text($0.displayName).tag(CommandKind?.some($0)) }
            }
            .labelsHidden()
            .frame(width: 112)

            Menu {
                Button("Reveal Script Commands Folder") { reveal(LodestarPaths.scriptsDirectory) }
                Button("Reveal Extensions Folder") { reveal(LodestarPaths.extensionsDirectory) }
                Divider()
                Button("Reload Scripts and Extensions") { model.reloadExtensions() }
            } label: {
                Image(systemName: "plus.rectangle.on.folder")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 34)
            .help("Folders and reload")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Type").frame(width: Col.type, alignment: .leading)
            Text("Alias").frame(width: Col.alias, alignment: .leading)
            Text("Hotkey").frame(width: Col.hotkey, alignment: .leading)
            Text("Enabled").frame(width: Col.enabled)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections, id: \.title) { section in
                    Section {
                        if !collapsed.contains(section.title) || !query.isEmpty {
                            ForEach(section.commands) { d in
                                if let entry = entriesByID[d.id] {
                                    CommandRow(model: model, capture: capture, entry: entry, selected: selection == d.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selection = d.id }
                                }
                            }
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }
                if sections.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 22)).foregroundStyle(.tertiary)
                        Text("No commands match “\(query)”").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
        }
    }

    private func sectionHeader(_ section: CommandCatalog.Section) -> some View {
        let ids = section.commands.map(\.id)
        let enabledCount = ids.filter(model.isEnabled).count
        let isCollapsed = collapsed.contains(section.title) && query.isEmpty
        return HStack(spacing: 6) {
            Button {
                if collapsed.contains(section.title) { collapsed.remove(section.title) } else { collapsed.insert(section.title) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .foregroundStyle(.secondary)
                    Text(section.title).font(.system(size: 12, weight: .semibold))
                    Text("\(section.commands.count)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Toggle("", isOn: Binding(get: { enabledCount == ids.count }, set: { model.setEnabled($0, forAll: ids) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(enabledCount == ids.count ? "Disable all in \(section.title)" : "Enable all in \(section.title)")
                .frame(width: Col.enabled)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.bar)
    }

    private func reveal(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private var footer: some View {
        let total = model.catalog.count
        let disabled = model.catalog.filter { !model.isEnabled($0.descriptor.id) }.count
        return HStack {
            Text("\(total) commands" + (disabled > 0 ? " · \(disabled) disabled" : ""))
            Spacer()
            Text("Applications are always searchable")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
    }
}

private enum Col {
    static let type: CGFloat = 64
    static let alias: CGFloat = 76
    static let hotkey: CGFloat = 92
    static let enabled: CGFloat = 50
}

private struct CommandRow: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var capture: ShortcutCapture
    let entry: RootScreen.CatalogEntry
    let selected: Bool

    var body: some View {
        let d = entry.descriptor
        let enabled = model.isEnabled(d.id)
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                ItemIconView(icon: entry.icon)
                    .frame(width: 20, height: 20)
                    .scaleEffect(0.8)
                Text(d.title).lineLimit(1)
                    .foregroundStyle(enabled ? .primary : .secondary)
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(d.kind.displayName)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: Col.type, alignment: .leading)
            AliasField(model: model, id: d.id, compact: true)
                .frame(width: Col.alias, alignment: .leading)
            ShortcutField(capture: capture, target: d.id, spec: model.preferences.hotkey(for: d.id),
                          placeholder: "Record", compact: true) {
                model.toggleCommandRecording(d.id)
            }
            .frame(width: Col.hotkey, alignment: .leading)
            Toggle("", isOn: Binding(get: { enabled }, set: { model.setEnabled($0, for: d.id) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: Col.enabled)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
            .padding(.horizontal, 4))
    }
}

/// An alias text field that saves on Return or when it loses focus.
struct AliasField: View {
    @ObservedObject var model: SettingsModel
    let id: String
    var compact = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(compact ? "Add" : "e.g. ch", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: compact ? 11.5 : 13, design: .rounded))
            .padding(.horizontal, 6)
            .frame(height: compact ? 20 : 24)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(focused ? 0.08 : (text.isEmpty ? 0 : 0.05))))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(model.aliasErrors[id] != nil ? Color.red.opacity(0.7)
                              : focused ? Color.accentColor : Color.primary.opacity(text.isEmpty ? 0.1 : 0), lineWidth: 1))
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { isFocused in if !isFocused { commit() } }
            .onAppear { text = model.preferences.alias(for: id) ?? "" }
            .onChange(of: model.preferences.alias(for: id)) { text = $0 ?? "" }
            .help(model.aliasErrors[id] ?? "Type an alias, then press Return. Typing it in the launcher puts this command first.")
    }

    private func commit() {
        guard text != (model.preferences.alias(for: id) ?? "") || model.aliasErrors[id] != nil else { return }
        model.setAlias(text, for: id)
    }
}

private struct DetailPane: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var capture: ShortcutCapture
    let entry: RootScreen.CatalogEntry?

    var body: some View {
        if let entry {
            let d = entry.descriptor
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        ItemIconView(icon: entry.icon)
                            .frame(width: 26, height: 26)
                            .scaleEffect(1.5)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.title).font(.system(size: 15, weight: .semibold))
                            Text("\(d.group) · \(d.kind.displayName)").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                    }
                    Text(entry.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    field("Enabled") {
                        Toggle("Show in search", isOn: Binding(get: { model.isEnabled(d.id) }, set: { model.setEnabled($0, for: d.id) }))
                            .toggleStyle(.switch).controlSize(.small)
                    }
                    field("Alias") {
                        AliasField(model: model, id: d.id).frame(width: 140)
                        if let error = model.aliasErrors[d.id] {
                            Text(error).font(.system(size: 11)).foregroundStyle(.red)
                        } else {
                            Text("Type it in the launcher to jump straight to this command.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    field("Hotkey") {
                        HStack(spacing: 6) {
                            ShortcutField(capture: capture, target: d.id, spec: model.preferences.hotkey(for: d.id)) {
                                model.toggleCommandRecording(d.id)
                            }
                            if model.preferences.hotkey(for: d.id) != nil && !capture.isRecording(d.id) {
                                Button { model.setCommandHotkey(nil, for: d.id) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove hotkey")
                            }
                        }
                        if let error = capture.errorMessage(for: d.id) {
                            Text(error).font(.system(size: 11)).foregroundStyle(.red)
                        } else {
                            Text("Runs the command from anywhere.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    field("Command ID") {
                        Text(d.id).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .foregroundStyle(.secondary).lineLimit(3)
                    }
                    if let location = entry.location {
                        field(d.kind == .script ? "Script" : "Folder") {
                            Text((location.path as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                .textSelection(.enabled).lineLimit(3)
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([location]) }
                                .controlSize(.small)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension").font(.system(size: 30)).foregroundStyle(.tertiary)
                Text("Select a command").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            content()
        }
    }
}
