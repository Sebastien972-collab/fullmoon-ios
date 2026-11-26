// French rule table adapted from Soniqo speech-swift (Apache 2.0).
// See Kokoro-Licenses.txt for attribution and the license.
import Foundation

struct KokoroFrenchText {
    let lexicon: [String: String]
    let vocabulary: [String: Int32]

    /// The Core ML export takes phonemes, not ordinary written French.
    func tokens(for text: String) -> [Int32] {
        let words = text.lowercased(with: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "’", with: "'")
            .precomposedStringWithCanonicalMapping
            .matches(of: #/\p{L}+(?:'\p{L}+)*|\d+(?:[,.]\d+)?|[^\s]/#)
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = Locale(identifier: "fr_FR")
        numberFormatter.numberStyle = .spellOut
        let phonemes = words.compactMap { match -> String? in
            let word = String(match.output)
            if let first = word.first, first.isNumber {
                let normalized = word.replacingOccurrences(of: ",", with: ".")
                let number = NSDecimalNumber(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
                let expanded = numberFormatter.string(from: number) ?? word
                return expanded.split { !$0.isLetter }.map { pronunciation(of: String($0)) }.joined(separator: " ")
            }
            if word.first?.isLetter == true { return pronunciation(of: word) }
            switch word {
            case ",", ".", "!", "?", ";", ":": return word
            case "%": return "puɹ sɑ̃"
            case "€": return "øɹo"
            case "…": return "."
            default: return nil
            }
        }
        var result: [Int32] = []
        for symbol in phonemes.joined(separator: " ") {
            if let token = vocabulary[String(symbol)] {
                result.append(token)
            } else {
                // Combining IPA stress/diacritics can occupy separate vocabulary slots.
                result += symbol.unicodeScalars.compactMap { vocabulary[String($0)] }
            }
        }
        return result
    }

    private func pronunciation(of word: String) -> String {
        if word == "noctis" { return "nɔktˈis" }
        if let known = lexicon[word] { return known }
        if word.contains("'") {
            return word.split(separator: "'").map { part in
                let text = String(part)
                return Self.elisions[text] ?? pronunciation(of: text)
            }.joined()
        }
        return Self.approximate(word)
    }

    private static let elisions = ["l": "l", "d": "d", "j": "ʒ", "m": "m", "n": "n", "t": "t", "qu": "k", "s": "s"]
    private static let nasal = [
        "on": "ɔ̃", "om": "ɔ̃", "an": "ɑ̃", "am": "ɑ̃", "en": "ɑ̃", "em": "ɑ̃",
        "in": "ɛ̃", "im": "ɛ̃", "un": "œ̃", "um": "œ̃"
    ]
    private static let rules = [
        "eaux": "o", "eau": "o", "aux": "o", "eux": "ø", "oeu": "œ", "œu": "œ",
        "ain": "ɛ̃", "ein": "ɛ̃", "oin": "wɛ̃", "ien": "jɛ̃", "ion": "jɔ̃",
        "ou": "u", "oi": "wa", "ai": "ɛ", "ei": "ɛ", "au": "o", "eu": "ø",
        "ch": "ʃ", "ph": "f", "th": "t", "gn": "ɲ", "qu": "k", "gu": "ɡ",
        "ll": "l", "ss": "s", "tt": "t", "nn": "n", "mm": "m", "pp": "p", "rr": "ɹ", "ff": "f",
        "é": "e", "è": "ɛ", "ê": "ɛ", "ë": "ɛ", "à": "a", "â": "ɑ", "ù": "y", "û": "y",
        "î": "i", "ï": "i", "ô": "o", "ü": "y", "ç": "s", "c": "k", "e": "ə", "g": "ɡ",
        "h": "", "j": "ʒ", "r": "ɹ", "u": "y", "x": "ks", "y": "i"
    ]

    private static func approximate(_ word: String) -> String {
        var remaining = word[...]
        var result = ""
        while let letter = remaining.first {
            let next = remaining.dropFirst().first
            if let next, "eiéèêëîïy".contains(next), letter == "c" || letter == "g" {
                result += letter == "c" ? "s" : "ʒ"
                remaining = remaining.dropFirst()
                continue
            }
            if remaining.count == 1, word.count > 2, "dtsxzp".contains(letter) { break }
            let prefix = String(remaining.prefix(2))
            let after = remaining.dropFirst(2).first
            if let sound = nasal[prefix], after.map({ !"aeiouyéèêëàâùûîïôüœnm".contains($0) }) ?? true {
                result += sound
                remaining = remaining.dropFirst(2)
                continue
            }
            let length = (1...min(4, remaining.count)).reversed().first { rules[String(remaining.prefix($0))] != nil }
            let chunk = String(remaining.prefix(length ?? 1))
            result += rules[chunk] ?? chunk
            remaining = remaining.dropFirst(chunk.count)
        }
        return result
    }
}
