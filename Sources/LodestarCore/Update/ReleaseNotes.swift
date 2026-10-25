import Foundation

/// Release notes split into simple blocks, so the update window can render
/// headings and bullets (SwiftUI's `Text` only renders inline Markdown).
public enum ReleaseNoteBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case bullet(text: String)
    case paragraph(text: String)
}

public enum ReleaseNotes {
    /// Headings (`#`…`######`), bullets (`-`, `*`, `+`, `1.`) and paragraphs
    /// (consecutive lines joined). HTML tags GitHub uses for collapsible
    /// sections (`<details>`, `<summary>`), HTML comments and code fences are
    /// dropped; their text content is kept.
    public static func blocks(from markdown: String) -> [ReleaseNoteBlock] {
        var blocks: [ReleaseNoteBlock] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(text: paragraph.joined(separator: " "))) }
            paragraph = []
        }
        var inComment = false
        for raw in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if inComment {
                if line.contains("-->") { inComment = false }
                continue
            }
            if line.hasPrefix("<!--") {
                if !line.contains("-->") { inComment = true }
                continue
            }
            line = stripTags(line).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("---") && line.allSatisfy({ $0 == "-" }) { flush(); continue }
            if line.isEmpty { flush(); continue }
            if let heading = headingLevel(line) {
                flush()
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { blocks.append(.heading(level: heading, text: text)) }
                continue
            }
            if let item = bulletText(line) {
                flush()
                blocks.append(.bullet(text: item))
                continue
            }
            paragraph.append(line)
        }
        flush()
        return blocks
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
        if !digits.isEmpty, digits.count <= 3 {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Removes `<tag …>` / `</tag>` for a few block-level tags GitHub notes use.
    private static func stripTags(_ line: String) -> String {
        var result = line
        for tag in ["details", "summary", "br", "p", "div", "sub", "sup"] {
            result = result.replacingOccurrences(
                of: "</?\(tag)(\\s[^>]*)?/?>", with: tag == "br" ? " " : "", options: [.regularExpression, .caseInsensitive])
        }
        return result
    }
}
