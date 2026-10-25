import AppKit
import SwiftUI
import LodestarCore

/// Clipboard History: entries grouped by date on the left, a preview and an
/// Information table for the selection on the right, a type filter in the
/// search bar and every action in the ⌘K popover.
final class ClipboardHistoryScreen: ListScreen, FilterableScreen, SplitDetailScreen {
    let title = "Clipboard History"
    let placeholder = "Type to filter entries…"
    let showsBreadcrumb = false
    let presentation = ScreenPresentation.split
    weak var host: ScreenHost?

    private let history: ClipboardHistory
    private var filter: ClipboardTypeFilter = .all
    private var lastQuery = ""
    private var entriesByItemID: [String: ClipboardEntry] = [:]
    /// Rows are capped so a huge history stays snappy; search reaches all entries.
    private let maxRows = 500

    init(history: ClipboardHistory, filter: ClipboardTypeFilter = .all) {
        self.history = history
        self.filter = filter
        history.onChange = { [weak self] in self?.reload() }
    }

    func dismissed() {
        history.onChange = nil
    }

    private func reload() {
        host?.setItems(search(lastQuery), for: self)
    }

    // MARK: FilterableScreen

    var filterOptions: [ScreenFilterOption] {
        ClipboardTypeFilter.allCases.map { ScreenFilterOption(id: $0.rawValue, title: $0.title, symbol: ClipboardHistoryScreen.symbol(for: $0)) }
    }
    var selectedFilterID: String { filter.rawValue }
    func selectFilter(_ id: String) { filter = ClipboardTypeFilter(rawValue: id) ?? .all }

    static func symbol(for filter: ClipboardTypeFilter) -> String {
        switch filter {
        case .all: return "line.3.horizontal.decrease"
        case .text: return "text.alignleft"
        case .images: return "photo"
        case .links: return "link"
        case .colors: return "paintpalette"
        case .files: return "doc"
        }
    }

    var emptyMessage: String {
        if !history.entries.isEmpty { return "No entries match" }
        return "Nothing copied yet.\nCopied text, links, colors, images and files show up here."
    }

    // MARK: Items

    func search(_ query: String) -> [LauncherItem] {
        lastQuery = query
        let matches = ClipboardTypeFilter.filter(history.entries, type: filter, query: query.trimmingCharacters(in: .whitespaces))
        var rows: [LauncherItem] = []
        var byID: [String: ClipboardEntry] = [:]
        for group in ClipboardSection.group(Array(matches.prefix(maxRows)), now: Date()) {
            for entry in group.entries {
                let item = self.item(for: entry, section: group.section.title)
                byID[item.id] = entry
                rows.append(item)
            }
        }
        entriesByItemID = byID
        return rows
    }

    private func item(for entry: ClipboardEntry, section: String) -> LauncherItem {
        LauncherItem(id: "clip:\(entry.id.uuidString)", title: entry.title, subtitle: nil,
                     icon: icon(for: entry), accessory: nil, actions: actions(for: entry),
                     tracksUsage: false, section: section)
    }

    private func icon(for entry: ClipboardEntry) -> ItemIcon {
        switch entry.kind {
        case .text: return .symbol("text.alignleft")
        case .link: return .tinted("link", .blue)
        case .color:
            guard let c = ClipboardClassifier.color(in: entry.text ?? "") else { return .symbol("paintpalette") }
            return .swatch(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
        case .image:
            if let thumb = entry.image?.thumbnailFileName ?? entry.image?.fileName { return .thumbnail(history.fileURL(thumb).path) }
            return .symbol("photo")
        case .file:
            guard let path = entry.filePaths.first, FileManager.default.fileExists(atPath: path) else { return .symbol("doc") }
            return .file(path)
        }
    }

    // MARK: Actions

    private func actions(for entry: ClipboardEntry) -> [LauncherAction] {
        let history = self.history
        var actions: [LauncherAction] = [
            LauncherAction("Paste", symbol: "doc.on.clipboard") { ClipboardHistoryScreen.paste(entry, history: history, plainText: false) },
            LauncherAction("Copy to Clipboard", symbol: "doc.on.doc") {
                history.write(entry)
                return .closeThen { HUD.show("Copied to Clipboard", symbol: "doc.on.doc") }
            },
        ]
        switch entry.kind {
        case .text:
            actions.append(LauncherAction("Paste as Plain Text", symbol: "textformat", shortcut: .pastePlain) {
                ClipboardHistoryScreen.paste(entry, history: history, plainText: true)
            })
        case .link:
            if let url = ClipboardClassifier.link(in: entry.text ?? "") {
                actions.append(LauncherAction("Open Link", symbol: "safari", shortcut: .open, startsSection: true) {
                    SystemActions.open(url); return .close
                })
            }
            actions.append(LauncherAction("Paste as Plain Text", symbol: "textformat", shortcut: .pastePlain) {
                ClipboardHistoryScreen.paste(entry, history: history, plainText: true)
            })
        case .color:
            if let color = ClipboardClassifier.color(in: entry.text ?? "") {
                let copies: [(String, String, ActionShortcut?)] = [
                    ("Copy Color as HEX", color.hex, .copyHex),
                    ("Copy Color as RGB", color.cssRGB, .copyRGB),
                    ("Copy Color as HSL", color.cssHSL, nil),
                ]
                for (index, (title, text, shortcut)) in copies.enumerated() {
                    actions.append(LauncherAction(title, symbol: index == 0 ? "number" : "paintpalette", shortcut: shortcut,
                                                  startsSection: index == 0) {
                        SystemActions.copy(text)
                        return .toast("Copied \(text)")
                    })
                }
            }
        case .image:
            if let image = entry.image {
                let url = history.fileURL(image.fileName)
                actions.append(LauncherAction("Open in Preview", symbol: "photo", shortcut: .open, startsSection: true) {
                    let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
                    NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
                    return .close
                })
            }
        case .file:
            let paths = entry.filePaths
            actions.append(LauncherAction(paths.count > 1 ? "Open Files" : "Open File", symbol: "arrow.up.forward.app",
                                          shortcut: .open, startsSection: true) {
                paths.forEach { NSWorkspace.shared.open(URL(fileURLWithPath: $0)) }
                return .close
            })
            actions.append(LauncherAction("Show in Finder", symbol: "folder", shortcut: .reveal) {
                NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
                return .close
            })
            actions.append(LauncherAction("Paste Path as Text", symbol: "textformat", shortcut: .pastePlain) {
                ClipboardHistoryScreen.paste(entry, history: history, plainText: true)
            })
        }
        actions.append(LauncherAction(entry.pinned ? "Unpin Entry" : "Pin Entry", symbol: entry.pinned ? "pin.slash" : "pin",
                                      shortcut: .pin, startsSection: true) { [weak self] in
            history.setPinned(!entry.pinned, id: entry.id)
            self?.reload()
            return .toast(entry.pinned ? "Unpinned" : "Pinned")
        })
        actions.append(LauncherAction("Delete Entry", symbol: "trash", shortcut: .deleteEntry, isDestructive: true, startsSection: true) { [weak self] in
            history.remove(entry.id)
            self?.reload()
            return .toast("Entry deleted")
        })
        actions.append(LauncherAction("Clear All History", symbol: "trash.slash", shortcut: .clearAll, isDestructive: true) { [weak self] in
            guard SystemActions.confirm("Clear clipboard history?",
                                        info: "All \(history.entries.count) entries, pinned ones included, are deleted. This cannot be undone.",
                                        button: "Clear All") else { return .stay }
            history.clear()
            self?.reload()
            return .toast("History cleared")
        })
        return actions
    }

    /// Paste needs Accessibility (to send ⌘V); without it, copy and say so.
    private static func paste(_ entry: ClipboardEntry, history: ClipboardHistory, plainText: Bool) -> ActionOutcome {
        history.write(entry, plainText: plainText)
        guard SystemActions.ensureAccessibility(prompt: false) else {
            return .toast("Copied — allow Accessibility in Settings to paste directly")
        }
        return .closeThen { SystemActions.pressPaste() }
    }

    // MARK: Detail

    func detailView(for item: LauncherItem?) -> AnyView {
        guard let item, let entry = entriesByItemID[item.id] else { return AnyView(Color.clear) }
        return AnyView(ClipboardDetailView(entry: entry, fileURL: history.fileURL))
    }
}

// MARK: - Detail pane

struct ClipboardDetailView: View {
    let entry: ClipboardEntry
    let fileURL: (String) -> URL

    var body: some View {
        VStack(spacing: 0) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(0.6)
            information
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        switch entry.kind {
        case .text:
            ScrollView {
                Text(verbatim: String((entry.text ?? "").prefix(20_000)))
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        case .image:
            imagePreview
        case .color:
            colorPreview
        case .link:
            centered {
                TintedSymbolTile(symbol: "link", tint: .blue, size: 46)
                Text(verbatim: entry.text ?? "")
                    .font(.system(size: 12.5, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .padding(.horizontal, 22)
            }
        case .file:
            centered {
                if let path = entry.filePaths.first, FileManager.default.fileExists(atPath: path) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 64, height: 64)
                } else {
                    Image(systemName: "questionmark.folder").font(.system(size: 40)).foregroundStyle(.tertiary)
                }
                Text(entry.title).font(.system(size: 13, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 12) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let info = entry.image, let image = NSImage(contentsOf: fileURL(info.fileName)) {
            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
            // Never upscaled past the image's own size (in points at 2x).
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
                .frame(maxWidth: max(CGFloat(info.width) / 2, 24), maxHeight: max(CGFloat(info.height) / 2, 24))
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            centered {
                Image(systemName: "photo.badge.exclamationmark").font(.system(size: 34)).foregroundStyle(.tertiary)
                Text("Image file is missing").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var colorPreview: some View {
        if let color = ClipboardClassifier.color(in: entry.text ?? "") {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            VStack(spacing: 10) {
                shape.fill(color.swiftUIColor)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                    .frame(width: 120, height: 120)
                    .shadow(color: color.swiftUIColor.opacity(0.35), radius: 10, y: 3)
                Text(color.hex).font(.system(size: 14, weight: .semibold, design: .monospaced)).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Information

    private var information: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Information")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().opacity(0.45) }
                HStack(spacing: 8) {
                    Text(row.label).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    row.value
                }
                .font(.system(size: 12))
                .frame(height: 23)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 8)
    }

    private struct Row {
        let label: String
        let value: AnyView
    }

    private func text(_ s: String, mono: Bool = false) -> AnyView {
        AnyView(Text(verbatim: s)
            .font(.system(size: 12, design: mono ? .monospaced : .default))
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled))
    }

    private var rows: [Row] {
        var rows = [Row(label: "Source", value: sourceValue), Row(label: "Content type", value: text(entry.kind.displayName))]
        switch entry.kind {
        case .text:
            let stats = ClipboardTextStats(entry.text ?? "")
            rows.append(Row(label: "Characters", value: text(stats.characters.formatted())))
            rows.append(Row(label: "Words", value: text(stats.words.formatted())))
            rows.append(Row(label: "Lines", value: text(stats.lines.formatted())))
        case .link:
            if let url = ClipboardClassifier.link(in: entry.text ?? "") {
                rows.append(Row(label: "Domain", value: text(url.host ?? url.absoluteString)))
            }
        case .color:
            if let c = ClipboardClassifier.color(in: entry.text ?? "") {
                rows.append(Row(label: "HEX", value: text(c.hex, mono: true)))
                rows.append(Row(label: "RGB", value: text(c.cssRGB, mono: true)))
            }
        case .image:
            if let info = entry.image {
                rows.append(Row(label: "Dimensions", value: text("\(info.width)×\(info.height)")))
                rows.append(Row(label: "Image size", value: text(ByteCountFormatter.string(fromByteCount: Int64(info.byteSize), countStyle: .file))))
            }
        case .file:
            let paths = entry.filePaths
            if paths.count > 1 { rows.append(Row(label: "Files", value: text("\(paths.count)"))) }
            if let path = paths.first {
                rows.append(Row(label: "Path", value: text((path as NSString).abbreviatingWithTildeInPath)))
                if let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64, paths.count == 1,
                   !path.hasSuffix(".app") {
                    rows.append(Row(label: "Size", value: text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))))
                } else if !FileManager.default.fileExists(atPath: path) {
                    rows.append(Row(label: "Status", value: text("Moved or deleted")))
                }
            }
        }
        rows.append(Row(label: "Copied", value: AnyView(Text(ClipboardDetailView.relative(entry.date))
            .font(.system(size: 12))
            .help(entry.date.formatted(date: .abbreviated, time: .shortened)))))
        return rows
    }

    private var sourceValue: AnyView {
        guard let name = entry.sourceApp else { return text("Unknown") }
        let path = entry.sourceBundleID.flatMap { IconCache.shared.appPath(bundleID: $0) }
        return AnyView(HStack(spacing: 5) {
            if let path { Image(nsImage: IconCache.shared.icon(forPath: path)).resizable().frame(width: 15, height: 15) }
            Text(verbatim: name).font(.system(size: 12)).lineLimit(1)
        })
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 45 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
