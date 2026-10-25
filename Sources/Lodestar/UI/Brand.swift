import AppKit
import SwiftUI

/// A four-pointed "guiding star" with concave sides.
struct GuideStar: Shape {
    /// 0 = needle-thin points, 1 = a diamond.
    var waist: CGFloat = 0.22

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let w = r * waist
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + w, y: c.y - w))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + w, y: c.y + w))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - w, y: c.y + w))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - w, y: c.y - w))
        p.closeSubpath()
        return p
    }
}

/// The outline guiding star used as the search-bar glyph (in place of a
/// magnifying glass). Takes the surrounding foreground style.
struct LodestarStarIcon: View {
    var size: CGFloat = 20
    var lineWidth: CGFloat = 1.7

    var body: some View {
        GuideStar(waist: 0.3)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .padding(lineWidth / 2)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension NSImage {
    /// Outline guiding star for the menu bar, drawn as a template image so
    /// macOS tints it for light/dark menu bars like an SF Symbol.
    static func lodestarMenuBarStar(size: CGFloat = 18, lineWidth: CGFloat = 1.5) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let inset = rect.insetBy(dx: lineWidth / 2 + 0.5, dy: lineWidth / 2 + 0.5)
            // The star is symmetric, so SwiftUI's flipped coordinates don't matter.
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(GuideStar(waist: 0.3).path(in: inset).cgPath)
            ctx.setLineWidth(lineWidth)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Lodestar"
        return image
    }
}

/// Lodestar's app mark: a night-sky tile with a bright guiding star.
/// Drawn in code (no image assets) and also rendered into the .icns by
/// `Lodestar --render-icon` during bundling.
struct LodestarMark: View {
    var size: CGFloat = 96

    var body: some View {
        let corner = size * 0.225
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.13, blue: 0.42),
                                              Color(red: 0.06, green: 0.07, blue: 0.20)],
                                     startPoint: .top, endPoint: .bottom))
            // Warm horizon glow.
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(RadialGradient(colors: [Color(red: 0.98, green: 0.55, blue: 0.36).opacity(0.55), .clear],
                                     center: UnitPoint(x: 0.5, y: 1.05), startRadius: 0, endRadius: size * 0.62))
            // Faint background stars.
            ForEach(0..<6, id: \.self) { i in
                let spots: [(CGFloat, CGFloat, CGFloat)] = [(0.22, 0.24, 0.05), (0.78, 0.2, 0.04), (0.82, 0.62, 0.035),
                                                           (0.18, 0.68, 0.03), (0.68, 0.84, 0.03), (0.34, 0.86, 0.025)]
                let s = spots[i]
                GuideStar(waist: 0.3)
                    .fill(Color.white.opacity(0.55))
                    .frame(width: size * s.2 * 2, height: size * s.2 * 2)
                    .position(x: size * s.0, y: size * s.1)
            }
            // Glow behind the main star.
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.75, green: 0.8, blue: 1).opacity(0.75), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.3))
                .frame(width: size * 0.6, height: size * 0.6)
                .position(x: size * 0.5, y: size * 0.45)
            GuideStar(waist: 0.2)
                .fill(LinearGradient(colors: [.white, Color(red: 0.84, green: 0.87, blue: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.62, height: size * 0.62)
                .position(x: size * 0.5, y: size * 0.45)
                .shadow(color: Color(red: 0.6, green: 0.65, blue: 1).opacity(0.8), radius: size * 0.05)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: max(size * 0.01, 0.5))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    /// Writes a macOS .iconset (PNG per size) for `iconutil`. The art fills
    /// ~80% of the canvas, matching the standard macOS icon grid margin.
    @MainActor
    static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = CGFloat(base * scale)
                let view = ZStack {
                    LodestarMark(size: px * 0.8)
                        .shadow(color: .black.opacity(0.3), radius: px * 0.015, y: px * 0.01)
                }
                .frame(width: px, height: px)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                guard let cg = renderer.cgImage else { continue }
                let rep = NSBitmapImageRep(cgImage: cg)
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
            }
        }
    }
}

/// NSVisualEffectView for SwiftUI backgrounds.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// One rounded key, e.g. "⌥" or "Space".
struct Keycap: View {
    let label: String
    var size: CGFloat = 13

    var body: some View {
        Text(label)
            .font(.system(size: size, weight: .medium, design: .rounded))
            .padding(.horizontal, size * 0.55)
            .frame(minWidth: size * 1.9, minHeight: size * 1.9)
            .background(
                RoundedRectangle(cornerRadius: size * 0.4, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .shadow(color: .black.opacity(0.18), radius: 0, y: size * 0.08)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
    }
}

/// A shortcut drawn as separate keycaps, e.g. [⌥] [Space].
struct KeycapRow: View {
    let parts: [String]
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: size * 0.35) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, p in Keycap(label: p, size: size) }
        }
    }
}

extension Color {
    static let lodestarAccent = Color(red: 0.42, green: 0.40, blue: 0.98)
}
