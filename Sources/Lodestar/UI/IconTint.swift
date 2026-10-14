import SwiftUI

/// Tile colors for built-in command icons (a white SF Symbol on a colored,
/// gently graded rounded square). This file is the single place that maps
/// commands to colors: add a rule to `forItem(_:)` when adding a command.
enum IconTint: String, CaseIterable {
    case orange, blue, indigo, purple, red, pink, green, teal, slate, yellow, gray

    /// Bottom (base) color of the tile.
    var base: Color {
        switch self {
        case .orange: return Color(red: 0.96, green: 0.50, blue: 0.13)
        case .blue: return Color(red: 0.16, green: 0.47, blue: 0.96)
        case .indigo: return Color(red: 0.35, green: 0.34, blue: 0.90)
        case .purple: return Color(red: 0.62, green: 0.32, blue: 0.90)
        case .red: return Color(red: 0.92, green: 0.26, blue: 0.27)
        case .pink: return Color(red: 0.93, green: 0.27, blue: 0.53)
        case .green: return Color(red: 0.19, green: 0.70, blue: 0.36)
        case .teal: return Color(red: 0.10, green: 0.62, blue: 0.68)
        case .slate: return Color(red: 0.33, green: 0.45, blue: 0.53)
        case .yellow: return Color(red: 0.93, green: 0.66, blue: 0.08)
        case .gray: return Color(red: 0.45, green: 0.46, blue: 0.50)
        }
    }

    /// Top of the gradient: the base color lifted toward white.
    var top: Color {
        let ns = NSColor(base).usingColorSpace(.sRGB) ?? .gray
        return Color(ns.blended(withFraction: 0.28, of: .white) ?? ns)
    }

    /// The color for a launcher item ID such as "cmd:clipboard" or "wm:Left Half".
    static func forItem(_ id: String) -> IconTint {
        if let exact = exact[id] { return exact }
        if id.hasPrefix("wm:") { return .indigo }
        if id.hasPrefix("sys:") { return systemTint(id) }
        if id.hasPrefix("script:") { return .slate }
        if id.hasPrefix("ext:") {
            // Stable per extension: hash the extension name, not the command.
            let name = id.dropFirst(4).split(separator: "/").first.map(String.init) ?? id
            return hashed(name)
        }
        if id.hasPrefix("fallback:") { return .gray }
        if id.hasPrefix("cmd:") { return .purple }
        return .gray
    }

    private static let exact: [String: IconTint] = [
        "cmd:clipboard": .orange,
        "cmd:files": .blue,
        "cmd:emoji": .yellow,
        "cmd:reload": .teal,
        "cmd:config": .slate,
        "cmd:new-script": .slate,
        "cmd:settings": .gray,
        "cmd:welcome": .purple,
        "cmd:quit": .red,
        "calc": .green,
        "fallback:web": .blue,
    ]

    private static func systemTint(_ id: String) -> IconTint {
        switch id {
        case "sys:lock", "sys:sleep", "sys:displaysleep": return .pink
        case "sys:dark": return .indigo
        case "sys:trash", "sys:restart", "sys:shutdown", "sys:logout", "sys:quitall": return .red
        default: return .pink
        }
    }

    /// FNV-1a so the color is stable across launches (Swift's hashValue isn't).
    static func hashed(_ s: String) -> IconTint {
        let palette: [IconTint] = [.orange, .blue, .indigo, .purple, .pink, .green, .teal, .yellow]
        var h: UInt32 = 2_166_136_261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return palette[Int(h % UInt32(palette.count))]
    }
}

/// The colored tile itself.
struct TintedSymbolTile: View {
    let symbol: String
    let tint: IconTint
    var size: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
            .frame(width: size, height: size)
            .background(shape.fill(LinearGradient(colors: [tint.top, tint.base], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: tint.base.opacity(0.25), radius: 1, y: 0.5)
    }
}

extension ItemIcon {
    /// Turns a plain symbol into a colored tile for `id`; app icons, emoji and
    /// images are returned unchanged.
    func tinted(for id: String) -> ItemIcon {
        if case .symbol(let name) = self { return .tinted(name, IconTint.forItem(id)) }
        return self
    }
}
