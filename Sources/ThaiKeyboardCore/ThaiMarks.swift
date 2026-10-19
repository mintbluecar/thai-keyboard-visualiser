/// Classification of Thai combining marks (vowels and tone marks that attach
/// above or below a base consonant and must never be drawn with a dotted
/// circle, box, or ghost base letter).
public enum ThaiMarks {
    /// `true` when `s` is a single Unicode scalar that is a Thai combining
    /// mark: U+0E31, U+0E33–U+0E3A (vowel signs, including sara am), or
    /// U+0E47–U+0E4E (tone marks and other combining signs).
    public static func isCombiningMark(_ s: String) -> Bool {
        guard let scalar = s.unicodeScalars.first, s.unicodeScalars.count == 1 else {
            return false
        }
        switch scalar.value {
        case 0x0E31, 0x0E33...0x0E3A, 0x0E47...0x0E4E:
            return true
        default:
            return false
        }
    }
}
