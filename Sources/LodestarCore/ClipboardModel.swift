import Foundation

// Pure clipboard-history logic: the entry model and its on-disk format
// (including migration from the old text-only file), content detection for
// links and colors, date grouping, type filters, search and pruning.
// Reading the pasteboard, writing image files and drawing live in the app.

/// What kind of thing an entry holds.
public enum ClipboardKind: String, Codable, CaseIterable, Sendable {
    case text, link, color, image, file

    public var displayName: String {
        switch self {
        case .text: return "Text"
        case .link: return "Link"
        case .color: return "Color"
        case .image: return "Image"
        case .file: return "File"
        }
    }
}

/// An image entry's files (names relative to the clipboard folder) and metadata.
public struct ClipboardImageInfo: Codable, Equatable, Sendable {
    public var fileName: String
    public var thumbnailFileName: String?
    public var width: Int
    public var height: Int
    /// Size of the stored image file in bytes.
    public var byteSize: Int
    /// Hex SHA-256 of the image file, used to de-duplicate repeated copies.
    public var digest: String

    public init(fileName: String, thumbnailFileName: String?, width: Int, height: Int, byteSize: Int, digest: String) {
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.width = width
        self.height = height
        self.byteSize = byteSize
        self.digest = digest
    }

    /// Every file this image owns.
    public var fileNames: [String] { [fileName] + (thumbnailFileName.map { [$0] } ?? []) }
}

/// Formatted text that came with a text entry (RTF or HTML), stored as a
/// side file so Paste can restore formatting and Paste as Plain Text can drop it.
public struct ClipboardRichText: Codable, Equatable, Sendable {
    public enum Format: String, Codable, Sendable { case rtf, html }
    public var format: Format
    public var fileName: String

    public init(format: Format, fileName: String) {
        self.format = format
        self.fileName = fileName
    }
}

public struct ClipboardEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ClipboardKind
    /// The text (text/link/color), or the file paths joined by newlines (file).
    /// Image entries have no text.
    public var text: String?
    public var date: Date
    /// Localized name of the frontmost app when the entry was copied.
    public var sourceApp: String?
    public var sourceBundleID: String?
    public var pinned: Bool
    public var image: ClipboardImageInfo?
    public var richText: ClipboardRichText?

    public init(id: UUID = UUID(), kind: ClipboardKind, text: String?, date: Date, sourceApp: String? = nil,
                sourceBundleID: String? = nil, pinned: Bool = false, image: ClipboardImageInfo? = nil,
                richText: ClipboardRichText? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.date = date
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.pinned = pinned
        self.image = image
        self.richText = richText
    }

    /// A text-like entry whose kind is detected from its content.
    public static func text(_ text: String, date: Date, sourceApp: String? = nil, sourceBundleID: String? = nil) -> ClipboardEntry {
        ClipboardEntry(kind: ClipboardClassifier.kind(of: text), text: text, date: date,
                       sourceApp: sourceApp, sourceBundleID: sourceBundleID)
    }

    public var filePaths: [String] {
        guard kind == .file, let text else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    /// Files in the clipboard folder this entry owns (deleted with it).
    public var ownedFileNames: [String] {
        (image?.fileNames ?? []) + (richText.map { [$0.fileName] } ?? [])
    }

    /// Two entries are the same content if a new copy should replace the old one.
    public func hasSameContent(as other: ClipboardEntry) -> Bool {
        if let a = image, let b = other.image { return a.digest == b.digest }
        guard image == nil, other.image == nil else { return false }
        return text == other.text
    }

    /// The one-line title shown in the list.
    public var title: String {
        switch kind {
        case .image:
            guard let image else { return "Image" }
            return "Image (\(image.width)×\(image.height))"
        case .file:
            let paths = filePaths
            let first = paths.first.map { ($0 as NSString).lastPathComponent } ?? "File"
            return paths.count > 1 ? "\(first) and \(paths.count - 1) more" : first
        case .color:
            return (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case .text, .link:
            let collapsed = (text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return String(collapsed.prefix(200))
        }
    }

    /// Text that a search query is matched against.
    public var searchText: String {
        switch kind {
        case .image: return [title, sourceApp ?? ""].joined(separator: " ")
        case .file: return (filePaths.map { ($0 as NSString).lastPathComponent } + filePaths).joined(separator: " ")
        default: return text ?? ""
        }
    }

    // MARK: Codable (lenient, so the old text-only format still decodes)

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, date, sourceApp, sourceBundleID, pinned, image, richText
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let text = try c.decodeIfPresent(String.self, forKey: .text)
        let image = try? c.decodeIfPresent(ClipboardImageInfo.self, forKey: .image)
        let storedKind = (try? c.decodeIfPresent(String.self, forKey: .kind)).flatMap { $0 }.flatMap(ClipboardKind.init(rawValue:))
        let kind: ClipboardKind
        if let storedKind {
            kind = storedKind
        } else if image != nil {
            kind = .image
        } else if let text {
            kind = ClipboardClassifier.kind(of: text)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .text, in: c, debugDescription: "Entry has neither text nor image")
        }
        if kind == .image, image == nil {
            throw DecodingError.dataCorruptedError(forKey: .image, in: c, debugDescription: "Image entry without image info")
        }
        if kind != .image, text == nil {
            throw DecodingError.dataCorruptedError(forKey: .text, in: c, debugDescription: "Entry without text")
        }
        self.id = (try? c.decodeIfPresent(UUID.self, forKey: .id)).flatMap { $0 } ?? UUID()
        self.kind = kind
        self.text = text
        self.date = (try? c.decodeIfPresent(Date.self, forKey: .date)).flatMap { $0 } ?? Date(timeIntervalSinceReferenceDate: 0)
        self.sourceApp = (try? c.decodeIfPresent(String.self, forKey: .sourceApp)).flatMap { $0 }
        self.sourceBundleID = (try? c.decodeIfPresent(String.self, forKey: .sourceBundleID)).flatMap { $0 }
        self.pinned = (try? c.decodeIfPresent(Bool.self, forKey: .pinned)).flatMap { $0 } ?? false
        self.image = image
        self.richText = (try? c.decodeIfPresent(ClipboardRichText.self, forKey: .richText)).flatMap { $0 }
    }
}

// MARK: - Archive

/// Reads and writes clipboard.json. The file is a JSON array of entries; the
/// first version stored only `text`, `date` and `sourceApp` per entry, and
/// those decode into text/link/color entries with fresh IDs.
public enum ClipboardArchive {
    public struct Decoded: Equatable {
        public var entries: [ClipboardEntry]
        /// True when the file was in an older format (or had unreadable
        /// entries) and should be written back in the current one.
        public var needsResave: Bool
    }

    public enum ArchiveError: Error { case unreadable }

    /// Decodes each element on its own so one bad entry doesn't lose the rest.
    /// Throws only if the data isn't a JSON array at all.
    public static func decode(_ data: Data) throws -> Decoded {
        guard let raw = try? JSONSerialization.jsonObject(with: data), let array = raw as? [Any] else {
            throw ArchiveError.unreadable
        }
        let decoder = JSONDecoder()
        var entries: [ClipboardEntry] = []
        var needsResave = false
        for element in array {
            guard let object = element as? [String: Any],
                  let elementData = try? JSONSerialization.data(withJSONObject: object),
                  let entry = try? decoder.decode(ClipboardEntry.self, from: elementData) else {
                needsResave = true
                continue
            }
            if object["kind"] == nil || object["id"] == nil { needsResave = true }
            entries.append(entry)
        }
        return Decoded(entries: entries, needsResave: needsResave)
    }

    public static func encode(_ entries: [ClipboardEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(entries)
    }

    /// Files in the clipboard folder no entry refers to (left behind by a
    /// crash between writing an image and saving the list).
    public static func orphanedFiles(_ fileNames: [String], entries: [ClipboardEntry]) -> [String] {
        let owned = Set(entries.flatMap(\.ownedFileNames))
        return fileNames.filter { !owned.contains($0) && !$0.hasPrefix(".") }
    }
}

// MARK: - Insert & prune

public enum ClipboardHistoryLogic {
    public struct Change: Equatable {
        public var entries: [ClipboardEntry]
        /// Files (in the clipboard folder) no remaining entry uses; delete them.
        public var removedFiles: [String]
    }

    /// Adds `entry` at the top. A copy of something already in the history
    /// replaces the old entry (keeping its ID and pin) instead of adding a
    /// duplicate. Then prunes to `limit`.
    public static func insert(_ entry: ClipboardEntry, into entries: [ClipboardEntry], limit: Int) -> Change {
        var entries = entries
        var removedFiles: [String] = []
        var new = entry
        if let index = entries.firstIndex(where: { $0.hasSameContent(as: entry) }) {
            let old = entries.remove(at: index)
            new.id = old.id
            new.pinned = old.pinned
            let keep = Set(new.ownedFileNames)
            removedFiles += old.ownedFileNames.filter { !keep.contains($0) }
        }
        entries.insert(new, at: 0)
        let pruned = prune(entries, limit: limit)
        return Change(entries: pruned.entries, removedFiles: removedFiles + pruned.removedFiles)
    }

    /// Keeps at most `limit` entries by dropping the oldest unpinned ones.
    /// Pinned entries are never pruned, so with many pins the history can
    /// exceed the limit.
    public static func prune(_ entries: [ClipboardEntry], limit: Int) -> Change {
        let limit = max(limit, 0)
        guard entries.count > limit else { return Change(entries: entries, removedFiles: []) }
        var keep = entries
        var removed: [ClipboardEntry] = []
        var index = keep.count - 1
        while keep.count > limit && index >= 0 {
            if !keep[index].pinned { removed.append(keep.remove(at: index)) }
            index -= 1
        }
        return Change(entries: keep, removedFiles: removed.flatMap(\.ownedFileNames))
    }

    /// Removes one entry.
    public static func remove(_ id: UUID, from entries: [ClipboardEntry]) -> Change {
        guard let entry = entries.first(where: { $0.id == id }) else { return Change(entries: entries, removedFiles: []) }
        return Change(entries: entries.filter { $0.id != id }, removedFiles: entry.ownedFileNames)
    }

    public static func setPinned(_ pinned: Bool, id: UUID, in entries: [ClipboardEntry]) -> [ClipboardEntry] {
        entries.map { entry in
            guard entry.id == id else { return entry }
            var copy = entry
            copy.pinned = pinned
            return copy
        }
    }

    /// Moves an entry to the top with a new date (after copying it again from the history).
    public static func promote(_ id: UUID, in entries: [ClipboardEntry], date: Date) -> [ClipboardEntry] {
        var entries = entries
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return entries }
        var entry = entries.remove(at: index)
        entry.date = date
        entries.insert(entry, at: 0)
        return entries
    }

    /// Clearing keeps nothing (pinned entries included), as the action says.
    public static func clear(_ entries: [ClipboardEntry]) -> Change {
        Change(entries: [], removedFiles: entries.flatMap(\.ownedFileNames))
    }
}

// MARK: - Content detection

public enum ClipboardClassifier {
    public static func kind(of text: String) -> ClipboardKind {
        if color(in: text) != nil { return .color }
        if link(in: text) != nil { return .link }
        return .text
    }

    /// A single web/mail URL with nothing else around it.
    public static func link(in text: String) -> URL? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 2048, !s.contains(where: { $0.isWhitespace }) else { return nil }
        let lower = s.lowercased()
        let candidate: String
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("ftp://") {
            candidate = s
        } else if lower.hasPrefix("mailto:") {
            return s.count > 7 && s.contains("@") ? URL(string: s) : nil
        } else if lower.hasPrefix("www.") {
            candidate = "https://" + s
        } else {
            return nil
        }
        guard let url = URL(string: candidate), let host = url.host, !host.isEmpty else { return nil }
        guard host.contains(".") || host == "localhost" || url.port != nil else { return nil }
        return url
    }

    /// A color written as `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb()/rgba()` or
    /// `hsl()/hsla()`. Hex needs the `#` so numbers like 123456 stay text.
    /// Alpha is ignored (history colors are opaque).
    public static func color(in text: String) -> SRGBColor? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty, s.count <= 64 else { return nil }
        if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            guard hex.allSatisfy(\.isHexDigit) else { return nil }
            switch hex.count {
            case 3, 6: return SRGBColor(hex: hex)
            case 4: return SRGBColor(hex: String(hex.prefix(3)))
            case 8: return SRGBColor(hex: String(hex.prefix(6)))
            default: return nil
            }
        }
        for (prefix, isHSL) in [("rgba(", false), ("rgb(", false), ("hsla(", true), ("hsl(", true)] where s.hasPrefix(prefix) {
            guard s.hasSuffix(")") else { return nil }
            let body = s.dropFirst(prefix.count).dropLast()
            // Commas or the CSS4 space syntax ("rgb(58 123 255 / 50%)").
            let parts = body.replacingOccurrences(of: "/", with: " ")
                .replacingOccurrences(of: ",", with: " ")
                .split(separator: " ").map(String.init)
            guard parts.count == 3 || parts.count == 4 else { return nil }
            return isHSL ? hslColor(parts) : rgbColor(parts)
        }
        return nil
    }

    private static func rgbColor(_ parts: [String]) -> SRGBColor? {
        var channels: [Double] = []
        for part in parts.prefix(3) {
            if part.hasSuffix("%") {
                guard let v = Double(part.dropLast()), (0...100).contains(v) else { return nil }
                channels.append(v / 100)
            } else {
                guard let v = Double(part), (0...255).contains(v) else { return nil }
                channels.append(v / 255)
            }
        }
        guard parts.count < 4 || alphaIsValid(parts[3]) else { return nil }
        return SRGBColor(srgbRed: channels[0], green: channels[1], blue: channels[2])
    }

    private static func hslColor(_ parts: [String]) -> SRGBColor? {
        let hueText = parts[0].hasSuffix("deg") ? String(parts[0].dropLast(3)) : parts[0]
        guard let hue = Double(hueText),
              parts[1].hasSuffix("%"), let sat = Double(parts[1].dropLast()), (0...100).contains(sat),
              parts[2].hasSuffix("%"), let light = Double(parts[2].dropLast()), (0...100).contains(light),
              parts.count < 4 || alphaIsValid(parts[3]) else { return nil }
        let (r, g, b) = hslToRGB(hue: hue, saturation: sat / 100, lightness: light / 100)
        return SRGBColor(srgbRed: r, green: g, blue: b)
    }

    private static func alphaIsValid(_ s: String) -> Bool {
        if s.hasSuffix("%") { return Double(s.dropLast()).map { (0...100).contains($0) } ?? false }
        return Double(s).map { (0...1).contains($0) } ?? false
    }

    static func hslToRGB(hue: Double, saturation s: Double, lightness l: Double) -> (Double, Double, Double) {
        var h = hue.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}

// MARK: - Text statistics

public struct ClipboardTextStats: Equatable, Sendable {
    public var characters: Int
    public var words: Int
    public var lines: Int

    public init(_ text: String) {
        characters = text.count
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .localized]) { _, _, _, _ in words += 1 }
        self.words = words
        if text.isEmpty {
            lines = 0
        } else {
            var count = 0
            text.enumerateLines { _, _ in count += 1 }
            lines = max(count, 1)
        }
    }
}

// MARK: - Grouping & filtering

/// The section an entry is listed under.
public enum ClipboardSection: Equatable, Hashable, Sendable {
    case pinned, today, yesterday, thisWeek, older

    public var title: String {
        switch self {
        case .pinned: return "Pinned"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .older: return "Older"
        }
    }

    /// Today / Yesterday / This Week (the previous 7 days) / Older.
    public static func forDate(_ date: Date, now: Date, calendar: Calendar = .current) -> ClipboardSection {
        let startOfToday = calendar.startOfDay(for: now)
        if date >= startOfToday { return .today }  // includes clock skew into the future
        if let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday), date >= startOfYesterday {
            return .yesterday
        }
        if let weekStart = calendar.date(byAdding: .day, value: -7, to: startOfToday), date >= weekStart {
            return .thisWeek
        }
        return .older
    }

    /// Pinned entries first, then by date section. Within a section the
    /// input order (newest first) is kept.
    public static func group(_ entries: [ClipboardEntry], now: Date, calendar: Calendar = .current) -> [(section: ClipboardSection, entries: [ClipboardEntry])] {
        let order: [ClipboardSection] = [.pinned, .today, .yesterday, .thisWeek, .older]
        var buckets: [ClipboardSection: [ClipboardEntry]] = [:]
        for entry in entries {
            let section = entry.pinned ? .pinned : forDate(entry.date, now: now, calendar: calendar)
            buckets[section, default: []].append(entry)
        }
        return order.compactMap { section in buckets[section].map { (section, $0) } }
    }
}

/// The type dropdown in the clipboard search bar.
public enum ClipboardTypeFilter: String, CaseIterable, Sendable {
    case all, text, images, links, colors, files

    public var title: String {
        switch self {
        case .all: return "All Types"
        case .text: return "Text"
        case .images: return "Images"
        case .links: return "Links"
        case .colors: return "Colors"
        case .files: return "Files"
        }
    }

    public func matches(_ kind: ClipboardKind) -> Bool {
        switch self {
        case .all: return true
        case .text: return kind == .text
        case .images: return kind == .image
        case .links: return kind == .link
        case .colors: return kind == .color
        case .files: return kind == .file
        }
    }

    /// Entries of the right type whose content contains every word of the query.
    public static func filter(_ entries: [ClipboardEntry], type: ClipboardTypeFilter, query: String) -> [ClipboardEntry] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return entries.filter { entry in
            guard type.matches(entry.kind) else { return false }
            guard !words.isEmpty else { return true }
            let haystack = entry.searchText.lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}
