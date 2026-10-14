import Foundation

/// An opaque color in the sRGB color space, quantized to 8 bits per channel
/// (what a screen pixel and a hex code can express). Picked colors are
/// converted to sRGB before they get here; see `fromDisplayP3` for the math.
public struct SRGBColor: Codable, Equatable, Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// From gamma-encoded sRGB components in 0...1. Out-of-gamut values
    /// (below 0 or above 1, as extended-sRGB conversions can produce) are
    /// clamped to the nearest displayable value.
    public init(srgbRed r: Double, green g: Double, blue b: Double) {
        self.init(red: SRGBColor.quantize(r), green: SRGBColor.quantize(g), blue: SRGBColor.quantize(b))
    }

    static func quantize(_ c: Double) -> UInt8 {
        guard c.isFinite else { return 0 }
        return UInt8((min(max(c, 0), 1) * 255).rounded())
    }

    // MARK: Hex

    /// Accepts "#3A7BFF", "3a7bff", "#38F" (short form). Returns nil otherwise.
    public init?(hex raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, s.allSatisfy(\.isHexDigit), let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: UInt8(v >> 16 & 0xFF), green: UInt8(v >> 8 & 0xFF), blue: UInt8(v & 0xFF))
    }

    /// "#3A7BFF"
    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

    // MARK: Components

    public var redComponent: Double { Double(red) / 255 }
    public var greenComponent: Double { Double(green) / 255 }
    public var blueComponent: Double { Double(blue) / 255 }

    /// "rgb(58, 123, 255)"
    public var cssRGB: String { "rgb(\(red), \(green), \(blue))" }

    /// Hue in degrees [0, 360), saturation and lightness in [0, 1].
    public var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let r = redComponent, g = greenComponent, b = blueComponent
        let maxC = max(r, g, b), minC = min(r, g, b)
        let l = (maxC + minC) / 2
        let d = maxC - minC
        guard d > 0 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        switch maxC {
        case r: h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h *= 60
        if h < 0 { h += 360 }
        return (h, min(s, 1), l)
    }

    /// "hsl(220, 100%, 61%)"
    public var cssHSL: String {
        let (h, s, l) = hsl
        var hue = Int(h.rounded())
        if hue == 360 { hue = 0 }
        return "hsl(\(hue), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
    }

    /// "Color(red: 0.227, green: 0.482, blue: 1.000)" (SwiftUI's default
    /// initializer is sRGB, so no color-space argument is needed).
    public var swiftUI: String {
        "Color(red: \(SRGBColor.decimal(redComponent)), green: \(SRGBColor.decimal(greenComponent)), blue: \(SRGBColor.decimal(blueComponent)))"
    }

    /// "NSColor(srgbRed: 0.227, green: 0.482, blue: 1.000, alpha: 1.0)"
    public var nsColor: String {
        "NSColor(srgbRed: \(SRGBColor.decimal(redComponent)), green: \(SRGBColor.decimal(greenComponent)), blue: \(SRGBColor.decimal(blueComponent)), alpha: 1.0)"
    }

    static func decimal(_ v: Double) -> String { String(format: "%.3f", v) }

    /// Relative luminance (WCAG), handy for picking legible text on a swatch.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { SRGBColor.srgbToLinear(c) }
        return 0.2126 * lin(redComponent) + 0.7152 * lin(greenComponent) + 0.0722 * lin(blueComponent)
    }

    // MARK: Color-space conversion

    /// sRGB and Display P3 share this transfer function (IEC 61966-2-1).
    public static func srgbToLinear(_ c: Double) -> Double {
        let a = abs(c)
        let v = a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4)
        return c < 0 ? -v : v
    }

    public static func linearToSRGB(_ c: Double) -> Double {
        let a = abs(c)
        let v = a <= 0.0031308 ? a * 12.92 : 1.055 * pow(a, 1 / 2.4) - 0.055
        return c < 0 ? -v : v
    }

    /// Linear Display P3 → linear sRGB (both D65), i.e. sRGB⁻¹ · P3 RGB→XYZ.
    static let p3ToSRGB: [[Double]] = [
        [1.2249401762805598, -0.22494017628055996, 0.0],
        [-0.04205695470968816, 1.0420569547096882, 0.0],
        [-0.019637554590334432, -0.07863604555063188, 1.0982736001409663],
    ]

    /// Converts gamma-encoded Display P3 components (0...1) to sRGB.
    /// P3 colors outside the sRGB gamut are clamped per channel.
    public static func fromDisplayP3(red: Double, green: Double, blue: Double) -> SRGBColor {
        let (r, g, b) = displayP3ToSRGBComponents(red: red, green: green, blue: blue)
        return SRGBColor(srgbRed: r, green: g, blue: b)
    }

    /// The unclamped gamma-encoded sRGB components for a Display P3 color.
    public static func displayP3ToSRGBComponents(red: Double, green: Double, blue: Double) -> (Double, Double, Double) {
        let lin = [srgbToLinear(red), srgbToLinear(green), srgbToLinear(blue)]
        let m = p3ToSRGB
        let out = m.map { row in row[0] * lin[0] + row[1] * lin[1] + row[2] * lin[2] }
        return (linearToSRGB(out[0]), linearToSRGB(out[1]), linearToSRGB(out[2]))
    }
}

/// The text formats a picked color can be copied as.
public enum ColorFormat: String, CaseIterable, Sendable {
    case hex, rgb, hsl, swiftUI, nsColor

    public var title: String {
        switch self {
        case .hex: return "HEX"
        case .rgb: return "RGB"
        case .hsl: return "HSL"
        case .swiftUI: return "SwiftUI Color"
        case .nsColor: return "NSColor"
        }
    }

    public func string(for color: SRGBColor) -> String {
        switch self {
        case .hex: return color.hex
        case .rgb: return color.cssRGB
        case .hsl: return color.cssHSL
        case .swiftUI: return color.swiftUI
        case .nsColor: return color.nsColor
        }
    }
}

/// A picked color and when it was picked.
public struct PickedColor: Codable, Equatable, Sendable {
    public var color: SRGBColor
    public var date: Date

    public init(color: SRGBColor, date: Date) {
        self.color = color
        self.date = date
    }
}

/// The most recent picked colors, newest first, without duplicates.
public struct ColorHistory: Equatable, Sendable {
    public static let defaultLimit = 20

    public private(set) var entries: [PickedColor]
    public let limit: Int

    public init(entries: [PickedColor] = [], limit: Int = ColorHistory.defaultLimit) {
        self.limit = max(limit, 1)
        self.entries = Array(entries.prefix(self.limit))
    }

    /// Adds `color` at the front; picking the same color again moves it up.
    public mutating func add(_ color: SRGBColor, at date: Date = Date()) {
        entries.removeAll { $0.color == color }
        entries.insert(PickedColor(color: color, date: date), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    public mutating func remove(_ color: SRGBColor) { entries.removeAll { $0.color == color } }
    public mutating func clear() { entries.removeAll() }

    public var latest: SRGBColor? { entries.first?.color }

    // MARK: Persistence (JSON array of entries)

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }

    /// Unreadable data gives an empty history rather than an error.
    public static func decoded(from data: Data?, limit: Int = ColorHistory.defaultLimit) -> ColorHistory {
        guard let data else { return ColorHistory(limit: limit) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = (try? decoder.decode([PickedColor].self, from: data)) ?? []
        return ColorHistory(entries: entries, limit: limit)
    }
}
