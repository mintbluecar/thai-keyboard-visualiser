import CoreText
import Foundation
import ThaiKeyboardCore

/// Core Text drawing of key labels into a y-up `CGContext`. Text is drawn
/// in the context's current fill colour.
enum GlyphDrawing {
    /// Draws `text` centred in `rect`.
    ///
    /// A lone Thai combining mark is drawn as bare mark glyphs with
    /// `CTFontDrawGlyphs`, with their combined ink bounding box centred, so
    /// no dotted circle, box or base letter is ever drawn (see `markGlyphs`).
    /// Anything else is a `CTLine` centred on its typographic bounds.
    static func drawCentred(_ text: String, font: CTFont, in rect: CGRect, context: CGContext) {
        guard !text.isEmpty else { return }
        context.textMatrix = .identity

        if ThaiMarks.isCombiningMark(text), let mark = markGlyphs(text, font: font) {
            var glyphs = mark.glyphs
            var ink = CGRect.null
            for (i, glyph) in glyphs.enumerated() {
                var g = glyph
                let box = CTFontGetBoundingRectsForGlyphs(mark.font, .default, &g, nil, 1)
                ink = ink.union(box.offsetBy(dx: mark.positions[i].x, dy: mark.positions[i].y))
            }
            let shift = CGPoint(x: rect.midX - ink.midX, y: rect.midY - ink.midY)
            var positions = mark.positions.map { CGPoint(x: $0.x + shift.x, y: $0.y + shift.y) }
            CTFontDrawGlyphs(mark.font, &glyphs, &positions, glyphs.count, context)
            return
        }

        let line = makeLine(text, font: font)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        context.textPosition = CGPoint(x: rect.midX - width / 2, y: rect.midY - (ascent - descent) / 2)
        CTLineDraw(line, context)
    }

    /// Draws `text` as a single line whose ascent line touches `topLeft.y`
    /// and whose origin starts at `topLeft.x`.
    static func drawLine(_ text: String, font: CTFont, topLeft: CGPoint, context: CGContext) {
        guard !text.isEmpty else { return }
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: topLeft.x, y: topLeft.y - CTFontGetAscent(font))
        CTLineDraw(makeLine(text, font: font), context)
    }

    /// The bare glyphs (and their relative positions) that draw the
    /// combining mark `mark` without any base, or `nil` if none can be found.
    ///
    /// A font's cmap glyph for a mark can't be trusted: Apple's Thai fonts
    /// (`.ThonburiUI`, Thonburi) map U+0E31 etc. to keyboard-display glyphs
    /// that already contain a dotted circle. So the mark is shaped after a
    /// real consonant (อ), where the font must use its plain attaching
    /// glyph, and only the glyphs belonging to the mark are kept. A font
    /// that fuses the consonant and mark into one ligature (Thonburi) leaves
    /// no glyph for the mark; then the mark is shaped after U+00A0
    /// NO-BREAK SPACE instead, swapping any `<name>.key` dotted-circle glyph
    /// for the plain `<name>`. A shaper-inserted dotted circle (U+25CC) is
    /// always dropped.
    private static func markGlyphs(_ mark: String, font: CTFont) -> (font: CTFont, glyphs: [CGGlyph], positions: [CGPoint])? {
        shapedGlyphs(of: mark, after: "\u{0E2D}", font: font)
            ?? shapedGlyphs(of: mark, after: "\u{00A0}", font: font)
    }

    /// The glyphs Core Text produces for `mark` (only those whose string
    /// index falls in `mark`) when it follows `base`, or `nil` if none.
    private static func shapedGlyphs(of mark: String, after base: String, font: CTFont)
        -> (font: CTFont, glyphs: [CGGlyph], positions: [CGPoint])? {
        let markStart = base.utf16.count
        guard let runs = CTLineGetGlyphRuns(makeLine(base + mark, font: font)) as? [CTRun] else { return nil }

        for run in runs {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetStringIndices(run, CFRange(), &indices)
            CTRunGetPositions(run, CFRange(), &positions)
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont

            var dottedCircleChar: UniChar = 0x25CC
            var dottedCircle: CGGlyph = 0
            let hasDottedCircle = CTFontGetGlyphsForCharacters(runFont, &dottedCircleChar, &dottedCircle, 1)

            var kept: [CGGlyph] = []
            var keptPositions: [CGPoint] = []
            for i in 0..<count where indices[i] >= markStart {
                if hasDottedCircle && glyphs[i] == dottedCircle { continue }
                kept.append(plainGlyph(for: glyphs[i], in: runFont))
                keptPositions.append(positions[i])
            }
            if !kept.isEmpty { return (runFont, kept, keptPositions) }
        }
        return nil
    }

    /// `glyph`, or the plain glyph `<name>` when `glyph` is a keyboard-display
    /// glyph named `<name>.key` (Thonburi) that has a dotted circle drawn in.
    private static func plainGlyph(for glyph: CGGlyph, in font: CTFont) -> CGGlyph {
        guard let name = CTFontCopyNameForGlyph(font, glyph) as String?, name.hasSuffix(".key") else {
            return glyph
        }
        let plain = CTFontGetGlyphWithName(font, String(name.dropLast(4)) as CFString)
        return plain == 0 ? glyph : plain
    }

    private static func makeLine(_ text: String, font: CTFont) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}
