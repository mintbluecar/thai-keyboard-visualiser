import CoreText
import Foundation

/// Chooses the font a key label is drawn in: the user's preferred family
/// when it can draw every scalar of the label, otherwise the system Thai
/// font.
public struct FontResolver: Sendable {
    private let preferredFamily: String?

    public init(preferredFamily: String?) {
        self.preferredFamily = preferredFamily
    }

    /// The preferred family at `size` if it is installed and has a glyph for
    /// every scalar in `text`; otherwise `systemThaiFont(size:)`.
    public func font(for text: String, size: CGFloat) -> CTFont {
        if let family = preferredFamily, let font = Self.installedFont(family: family, size: size),
           Self.hasGlyphs(font, for: text) {
            return font
        }
        return Self.systemThaiFont(size: size)
    }

    /// The font the system UI font cascades to for Thai text ("ก").
    public static func systemThaiFont(size: CGFloat) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let sample = "ก" as CFString
        return CTFontCreateForString(base, sample, CFRange(location: 0, length: CFStringGetLength(sample)))
    }

    /// Visible (non-dot-prefixed) font families whose character set contains
    /// U+0E01 THAI CHARACTER KO KAI, sorted.
    public static func thaiCapableFamilies() -> [String] {
        let thai = CFCharacterSetCreateWithCharactersInString(nil, "\u{0E01}" as CFString)
        let attributes = [kCTFontCharacterSetAttribute: thai] as CFDictionary
        let query = CTFontDescriptorCreateWithAttributes(attributes)
        guard let matches = CTFontDescriptorCreateMatchingFontDescriptors(query, nil) as? [CTFontDescriptor] else {
            return []
        }
        let families = matches.compactMap {
            CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String
        }
        return Set(families).filter { !$0.hasPrefix(".") }.sorted()
    }

    /// A font of exactly `family`, or `nil` when that family isn't installed
    /// (Core Text would otherwise silently substitute another family).
    private static func installedFont(family: String, size: CGFloat) -> CTFont? {
        let attributes = [kCTFontFamilyNameAttribute: family] as CFDictionary
        let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes), size, nil)
        return (CTFontCopyFamilyName(font) as String) == family ? font : nil
    }

    private static func hasGlyphs(_ font: CTFont, for text: String) -> Bool {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return true }
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
    }
}
