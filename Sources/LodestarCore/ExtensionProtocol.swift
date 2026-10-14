import Foundation

// Lodestar extension protocol, version 1.
//
// An extension is a directory containing `manifest.json` plus any program.
// For each command invocation the host spawns the program and exchanges
// newline-delimited JSON messages over stdin/stdout. stderr is logged.
//
//   host -> ext   {"type":"run","command":"search","query":"","protocol":1}
//   host -> ext   {"type":"query","text":"cat"}             (list commands, as the user types)
//   host -> ext   {"type":"callback","id":"refresh"}        (user picked a "callback" action)
//   ext  -> host  {"type":"items","items":[...]}            (replace the visible list)
//   ext  -> host  {"type":"detail","markdown":"..."}        (show a text detail view)
//   ext  -> host  {"type":"toast","message":"Copied"}
//   ext  -> host  {"type":"close"}                          (hide the launcher)
//   ext  -> host  {"type":"error","message":"..."}
//
// Actions are declarative so the host can perform privileged work (opening,
// copying, pasting) without the extension needing macOS permissions.

public struct ExtensionManifest: Codable, Equatable, Sendable {
    public struct Command: Codable, Equatable, Sendable {
        public enum Mode: String, Codable, Sendable {
            /// Shows a list that the extension updates as the user types.
            case list
            /// Runs once without UI (it may still send a toast).
            case noView = "no-view"
        }
        public var name: String
        public var title: String
        public var subtitle: String?
        public var icon: String?
        public var mode: Mode
        public var keywords: [String]?
    }

    public var name: String
    public var title: String
    public var description: String?
    public var icon: String?
    /// argv to launch, relative paths resolved against the extension dir,
    /// e.g. ["node", "index.js"] or ["./my-binary"].
    public var run: [String]
    public var commands: [Command]
}

public enum ExtensionAction: Codable, Equatable, Sendable {
    case open(url: String)
    case copy(text: String)
    case paste(text: String)
    case callback(id: String)

    enum CodingKeys: String, CodingKey { case type, url, text, id, title }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "open": self = .open(url: try c.decode(String.self, forKey: .url))
        case "copy": self = .copy(text: try c.decode(String.self, forKey: .text))
        case "paste": self = .paste(text: try c.decode(String.self, forKey: .text))
        case "callback": self = .callback(id: try c.decode(String.self, forKey: .id))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown action type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .open(let url): try c.encode("open", forKey: .type); try c.encode(url, forKey: .url)
        case .copy(let text): try c.encode("copy", forKey: .type); try c.encode(text, forKey: .text)
        case .paste(let text): try c.encode("paste", forKey: .type); try c.encode(text, forKey: .text)
        case .callback(let id): try c.encode("callback", forKey: .type); try c.encode(id, forKey: .id)
        }
    }
}

public struct ExtensionItem: Codable, Equatable, Sendable {
    public var id: String?
    public var title: String
    public var subtitle: String?
    public var icon: String?
    public var accessory: String?
    /// First action runs on Return; the rest are reachable with ⌘K.
    public var actions: [ExtensionAction]?

    public init(id: String? = nil, title: String, subtitle: String? = nil, icon: String? = nil, accessory: String? = nil, actions: [ExtensionAction]? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accessory = accessory
        self.actions = actions
    }
}

/// Messages sent from the host to the extension process.
public enum HostMessage: Encodable, Equatable, Sendable {
    case run(command: String, query: String)
    case query(text: String)
    case callback(id: String)

    enum CodingKeys: String, CodingKey { case type, command, query, text, id, `protocol` }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .run(let command, let query):
            try c.encode("run", forKey: .type)
            try c.encode(command, forKey: .command)
            try c.encode(query, forKey: .query)
            try c.encode(1, forKey: .protocol)
        case .query(let text):
            try c.encode("query", forKey: .type)
            try c.encode(text, forKey: .text)
        case .callback(let id):
            try c.encode("callback", forKey: .type)
            try c.encode(id, forKey: .id)
        }
    }

    /// One JSON object followed by a newline.
    public func encodedLine() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var data = (try? encoder.encode(self)) ?? Data("{}".utf8)
        data.append(0x0A)
        return data
    }
}

/// Messages sent from the extension process to the host.
public enum ExtensionMessage: Decodable, Equatable, Sendable {
    case items([ExtensionItem], placeholder: String?)
    case detail(markdown: String)
    case toast(message: String)
    case close
    case error(message: String)

    enum CodingKeys: String, CodingKey { case type, items, placeholder, markdown, message }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "items":
            self = .items(try c.decode([ExtensionItem].self, forKey: .items),
                          placeholder: try c.decodeIfPresent(String.self, forKey: .placeholder))
        case "detail": self = .detail(markdown: try c.decode(String.self, forKey: .markdown))
        case "toast": self = .toast(message: try c.decode(String.self, forKey: .message))
        case "close": self = .close
        case "error": self = .error(message: try c.decode(String.self, forKey: .message))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown message type \(other)")
        }
    }
}

/// Splits a byte stream into newline-delimited JSON messages.
public struct LineBuffer: Sendable {
    private var buffer = Data()
    public init() {}

    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            if !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D }) { lines.append(Data(line)) }
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        return lines
    }
}
