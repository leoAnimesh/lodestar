import Foundation

/// A "script command": any executable script with metadata comments, e.g.
///
///     #!/bin/bash
///     # @lodestar.schemaVersion 1
///     # @lodestar.title Say Hello
///     # @lodestar.mode compact
///     # @lodestar.icon 👋
///     # @lodestar.description Prints a greeting
///     # @lodestar.keywords greet,hi
///
/// For interoperability, the publicly documented `@raycast.` prefix used by
/// the community script-command format is accepted as an alias.
public struct ScriptCommand: Equatable, Sendable {
    public enum OutputMode: String, Sendable {
        /// Run and close the launcher.
        case silent
        /// Show the last line of output as a toast.
        case compact
        /// Show the full output in a detail view.
        case fullOutput
    }

    public var path: String
    public var title: String
    public var mode: OutputMode
    public var icon: String?
    public var description: String?
    public var packageName: String?
    public var keywords: [String]
    public var needsArgument: Bool
    public var argumentPlaceholder: String?

    static let prefixes = ["@lodestar.", "@raycast."]

    /// Parses metadata from the first 40 lines of a script. Returns nil if
    /// the script has no title.
    public static func parse(contents: String, path: String) -> ScriptCommand? {
        var fields: [String: String] = [:]
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false).prefix(40) {
            var text = line.trimmingCharacters(in: .whitespaces)
            // Strip comment markers used by common script languages.
            for marker in ["#", "//", "--"] where text.hasPrefix(marker) {
                text = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                break
            }
            guard let prefix = prefixes.first(where: { text.hasPrefix($0) }) else { continue }
            let rest = text.dropFirst(prefix.count)
            guard let space = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let key = String(rest[..<space])
            let value = rest[space...].trimmingCharacters(in: .whitespaces)
            if fields[key] == nil { fields[key] = value }
        }
        guard let title = fields["title"], !title.isEmpty else { return nil }
        var argPlaceholder: String?
        if let arg = fields["argument1"],
           let data = arg.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            argPlaceholder = obj["placeholder"] as? String ?? "argument"
        }
        return ScriptCommand(
            path: path,
            title: title,
            mode: OutputMode(rawValue: fields["mode"] ?? "") ?? .compact,
            icon: fields["icon"],
            description: fields["description"],
            packageName: fields["packageName"],
            keywords: (fields["keywords"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            needsArgument: argPlaceholder != nil,
            argumentPlaceholder: argPlaceholder
        )
    }
}
