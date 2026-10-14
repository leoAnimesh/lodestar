import AppKit
import SwiftUI
import LodestarCore

/// Picks a color from anywhere on screen with the system loupe
/// (NSColorSampler), copies it as HEX and remembers the last 20 picks in
/// ~/Library/Application Support/Lodestar/colors.json.
final class ColorPicker {
    private(set) var history: ColorHistory
    /// nil keeps the history in memory only (used by the snapshot tour).
    private let storeURL: URL?
    private var sampler: NSColorSampler?

    init(storeURL: URL?, history: ColorHistory? = nil) {
        self.storeURL = storeURL
        self.history = history ?? ColorHistory.decoded(from: storeURL.flatMap { try? Data(contentsOf: $0) })
    }

    /// Shows the loupe. Call with the launcher already hidden so it isn't
    /// sampled. On a pick: records the color, copies HEX and shows a HUD.
    func pick() {
        let sampler = NSColorSampler()
        self.sampler = sampler  // keep alive until the user picks or cancels
        sampler.show { [weak self] picked in
            guard let self else { return }
            self.sampler = nil
            guard let picked, let color = ColorPicker.srgb(from: picked) else { return }  // nil = cancelled (Esc)
            self.record(color)
            SystemActions.copy(color.hex)
            HUD.show("Copied \(color.hex)", swatch: color.swiftUIColor)
        }
    }

    func record(_ color: SRGBColor) {
        history.add(color)
        save()
    }

    func remove(_ color: SRGBColor) { history.remove(color); save() }
    func clear() { history.clear(); save() }

    /// Converts whatever space the sampler returns (usually the display's own
    /// profile, e.g. Display P3) to sRGB through ColorSync, then quantizes.
    static func srgb(from color: NSColor) -> SRGBColor? {
        if let s = color.usingColorSpace(.sRGB) {
            return SRGBColor(srgbRed: Double(s.redComponent), green: Double(s.greenComponent), blue: Double(s.blueComponent))
        }
        if let p3 = color.usingColorSpace(.displayP3) {
            return SRGBColor.fromDisplayP3(red: Double(p3.redComponent), green: Double(p3.greenComponent), blue: Double(p3.blueComponent))
        }
        return nil
    }

    private func save() {
        guard let storeURL else { return }
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try history.encoded().write(to: storeURL, options: .atomic)
        } catch {
            NSLog("Lodestar: failed to save color history: \(error)")
        }
    }
}

extension SRGBColor {
    var swiftUIColor: Color { Color(.sRGB, red: redComponent, green: greenComponent, blue: blueComponent, opacity: 1) }
}

/// Launcher commands for the color picker (registered by RootScreen).
enum ColorPickerCommands {
    static let pickID = "cmd:pick-color"
    static let historyID = "cmd:color-history"

    static let summaries: [String: String] = [
        pickID: "Hides Lodestar and opens the system color loupe. Click any pixel to copy its sRGB HEX code; Esc cancels.",
        historyID: "Your last 20 picked colors. Copy any of them as HEX, rgb(), hsl(), a SwiftUI Color or an NSColor initializer.",
    ]

    static func items(_ picker: ColorPicker) -> [LauncherItem] {
        let latest = picker.history.latest
        return [
            LauncherItem(
                id: pickID, title: "Pick Color", subtitle: latest.map { "Last: \($0.hex)" }, icon: .symbol("eyedropper"),
                accessory: "Command", keywords: ["color picker", "eyedropper", "colour", "hex", "sample", "pipette"],
                actions: [
                    LauncherAction("Pick Color", symbol: "eyedropper") { .closeThen { picker.pick() } },
                    LauncherAction("Show Color History", symbol: "clock.arrow.circlepath") { .push(ColorHistoryScreen(picker: picker)) },
                ]),
            LauncherItem(
                id: historyID, title: "Color History",
                subtitle: picker.history.entries.isEmpty ? nil : "\(picker.history.entries.count) colors",
                icon: .symbol("paintpalette"), accessory: "Command",
                keywords: ["colors", "colour", "picked", "swatches", "palette"],
                actions: [LauncherAction("Open Color History", symbol: "paintpalette") { .push(ColorHistoryScreen(picker: picker)) }]),
        ]
    }
}

/// The list of picked colors with a swatch per row; ⌘K offers every format.
final class ColorHistoryScreen: ListScreen {
    let title = "Color History"
    let placeholder = "Search colors by HEX, rgb or hsl…"
    weak var host: ScreenHost?
    private let picker: ColorPicker

    init(picker: ColorPicker) { self.picker = picker }

    func search(_ query: String) -> [LauncherItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var rows: [LauncherItem] = []
        if q.isEmpty || "pick color".contains(q) || "new".hasPrefix(q) {
            rows.append(LauncherItem(
                id: "color:pick", title: "Pick New Color", subtitle: "Opens the loupe; the color is copied as HEX",
                icon: .tinted("eyedropper", .pink),
                actions: [LauncherAction("Pick Color", symbol: "eyedropper") { [picker] in .closeThen { picker.pick() } }],
                tracksUsage: false))
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        for entry in picker.history.entries {
            let color = entry.color
            if !q.isEmpty {
                let haystack = ColorFormat.allCases.map { $0.string(for: color) }.joined(separator: " ").lowercased()
                let bareHex = String(color.hex.dropFirst()).lowercased()
                guard haystack.contains(q) || bareHex.hasPrefix(q.replacingOccurrences(of: "#", with: "")) else { continue }
            }
            var actions = ColorFormat.allCases.map { format -> LauncherAction in
                let text = format.string(for: color)
                return LauncherAction("Copy as \(format.title)", symbol: format == .hex ? "number" : "doc.on.doc") {
                    SystemActions.copy(text)
                    return .toast("Copied \(text)")
                }
            }
            actions.append(LauncherAction("Paste HEX", symbol: "doc.on.clipboard") { .closeThen { SystemActions.paste(color.hex) } })
            actions.append(LauncherAction("Delete Color", symbol: "trash") { [weak self] in
                guard let self else { return .stay }
                self.picker.remove(color)
                self.host?.setItems(self.search(query), for: self)
                return .toast("Deleted \(color.hex)")
            })
            actions.append(LauncherAction("Clear Color History", symbol: "trash.slash") { [weak self] in
                guard let self, SystemActions.confirm("Clear color history?", button: "Clear") else { return .stay }
                self.picker.clear()
                self.host?.setItems(self.search(""), for: self)
                return .toast("Color history cleared")
            })
            rows.append(LauncherItem(
                id: "color:\(color.hex)", title: color.hex, subtitle: "\(color.cssRGB)  ·  \(color.cssHSL)",
                icon: .swatch(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent),
                accessory: formatter.localizedString(for: entry.date, relativeTo: Date()),
                actions: actions, tracksUsage: false))
        }
        return rows
    }
}
