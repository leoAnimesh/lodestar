import AppKit
import SwiftUI

/// The README hero banner (docs/hero.jpg), drawn in code like the app icon.
///
///   swift run Lodestar --snapshot <dir> --snapshot-only hero   # captures hero-*.png
///   swift run Lodestar --render-hero /tmp/hero.png <dir>       # composites the banner
///   sips -s format jpeg -s formatOptions 88 /tmp/hero.png --out docs/hero.jpg
///
/// The screenshots are real launcher windows captured over `HeroBackground`
/// (so their translucency picks up the banner's colors) with sample data only.
enum HeroArt {
    static let size = CGSize(width: 2400, height: 1200)

    @MainActor
    static func render(to output: URL, shots directory: URL) throws {
        func image(_ name: String) throws -> NSImage {
            let url = directory.appendingPathComponent("\(name).png")
            guard let image = NSImage(contentsOf: url) else {
                throw NSError(domain: "Lodestar", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(url.path)"])
            }
            return image
        }
        let banner = HeroBanner(launcher: try image("hero-launcher"), clipboard: try image("hero-clipboard"),
                                emoji: try image("hero-emoji"))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: banner)
        renderer.scale = 1
        guard let cg = renderer.cgImage else {
            throw NSError(domain: "Lodestar", code: 2, userInfo: [NSLocalizedDescriptionKey: "rendering failed"])
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Lodestar", code: 3, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
        }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: output)
    }
}

/// Night-sky gradient with a warm horizon glow, matching the app icon.
struct HeroBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.06, blue: 0.20), Color(red: 0.13, green: 0.10, blue: 0.34),
                                    Color(red: 0.24, green: 0.15, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.98, green: 0.55, blue: 0.36).opacity(0.38), .clear],
                           center: UnitPoint(x: 0.78, y: 1.15), startRadius: 0, endRadius: 900)
            RadialGradient(colors: [Color(red: 0.45, green: 0.50, blue: 1).opacity(0.22), .clear],
                           center: UnitPoint(x: 0.12, y: 0.1), startRadius: 0, endRadius: 800)
        }
    }
}

/// A few faint four-pointed stars, deterministic so the art never changes.
private struct StarField: View {
    let size: CGSize
    var body: some View {
        let spots: [(CGFloat, CGFloat, CGFloat, Double)] = [
            (0.05, 0.08, 16, 0.5), (0.31, 0.06, 10, 0.35), (0.44, 0.17, 14, 0.4), (0.09, 0.55, 8, 0.3),
            (0.40, 0.88, 12, 0.35), (0.52, 0.04, 8, 0.3), (0.97, 0.07, 12, 0.4), (0.03, 0.93, 10, 0.3),
            (0.47, 0.60, 7, 0.25), (0.26, 0.97, 7, 0.25),
        ]
        ZStack {
            ForEach(Array(spots.enumerated()), id: \.offset) { _, s in
                GuideStar(waist: 0.28)
                    .fill(Color.white.opacity(s.3))
                    .frame(width: s.2 * 2, height: s.2 * 2)
                    .position(x: size.width * s.0, y: size.height * s.1)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct HeroBanner: View {
    let launcher: NSImage
    let clipboard: NSImage
    let emoji: NSImage

    private let width = HeroArt.size.width
    private let height = HeroArt.size.height

    var body: some View {
        ZStack(alignment: .topLeading) {
            HeroBackground()
            StarField(size: HeroArt.size)

            // Left column: mark, name, promise, features.
            VStack(alignment: .leading, spacing: 0) {
                LodestarMark(size: 150)
                    .shadow(color: Color(red: 0.55, green: 0.55, blue: 1).opacity(0.45), radius: 40, y: 10)
                Text("Lodestar")
                    .font(.system(size: 132, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 34)
                Text("The free, open-source launcher for Mac.")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 6)
                HStack(spacing: 14) {
                    Text("Press").foregroundStyle(.white.opacity(0.72))
                    HeroKey("⌥")
                    HeroKey("Space")
                    Text("and type.").foregroundStyle(.white.opacity(0.72))
                }
                .font(.system(size: 34, weight: .regular))
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 44) {
                        HeroFeature(symbol: "app.badge", tint: Color(red: 0.36, green: 0.52, blue: 1), title: "Open any app")
                        HeroFeature(symbol: "doc.on.clipboard", tint: Color(red: 0.96, green: 0.55, blue: 0.25), title: "Clipboard history")
                    }
                    HStack(spacing: 44) {
                        HeroFeature(symbol: "face.smiling", tint: Color(red: 0.98, green: 0.76, blue: 0.20), title: "Emoji & symbols")
                        HeroFeature(symbol: "eyedropper", tint: Color(red: 0.86, green: 0.36, blue: 0.62), title: "Color picker")
                    }
                }
                .padding(.top, 64)

                Spacer()
                HStack(spacing: 18) {
                    Text("macOS 13+")
                    Text("·").foregroundStyle(.white.opacity(0.4))
                    Text("Free & open source")
                    Text("·").foregroundStyle(.white.opacity(0.4))
                    Text("No tracking")
                }
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color(red: 0.74, green: 0.76, blue: 1))
            }
            .padding(.leading, 130)
            .padding(.top, 150)
            .padding(.bottom, 120)
            .frame(width: 1100, height: height, alignment: .topLeading)

            // Right: real windows, stacked.
            shot(clipboard, width: 980).offset(x: 1370, y: 64)
            shot(launcher, width: 1060).offset(x: 1050, y: 300)
            shot(emoji, width: 660).offset(x: 1690, y: 780)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private func shot(_ image: NSImage, width: CGFloat) -> some View {
        let aspect = image.size.height / max(image.size.width, 1)
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: width * aspect)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.018, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: width * 0.018, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.45), radius: 50, y: 24)
    }
}

private struct HeroKey: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minWidth: 62, minHeight: 58)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5))
    }
}

private struct HeroFeature: View {
    let symbol: String
    let tint: Color
    let title: String
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .top, endPoint: .bottom)))
            Text(title)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 440, alignment: .leading)
    }
}
