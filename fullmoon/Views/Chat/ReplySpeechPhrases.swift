import Foundation

/// A model publishes growing snapshots. Commit each complete sentence once and hold its unfinished suffix.
struct ReplySpeechPhrases {
    private var committed = ""
    private var finished = false
    private static let maximumLength = 180

    /// A rewritten, already committed prefix cannot be played back faithfully. Let the caller cancel that turn.
    mutating func take(from text: String, isFinal: Bool) -> [String]? {
        guard !finished else { return [] }
        guard text.hasPrefix(committed) else { return nil }
        let start = text.index(text.startIndex, offsetBy: committed.count)
        var consumed = start
        var phrases: [String] = []
        let options: String.EnumerationOptions = [.bySentences, .substringNotRequired]
        text.enumerateSubstrings(in: start..<text.endIndex, options: options) { _, _, range, _ in
            let sentence = text[range]
            let complete = isFinal || range.upperBound < text.endIndex || Self.hasEndBoundary(sentence)
            var remaining = sentence
            while remaining.count > Self.maximumLength {
                let limit = remaining.index(remaining.startIndex, offsetBy: Self.maximumLength)
                let split = remaining[..<limit].lastIndex(where: \.isWhitespace)
                let end = split.map { remaining.index(after: $0) } ?? limit
                Self.append(remaining[..<end], to: &phrases)
                consumed = end
                remaining = remaining[end...]
            }
            if complete {
                Self.append(remaining, to: &phrases)
                consumed = range.upperBound
            }
        }
        committed += text[start..<consumed]
        finished = isFinal
        return phrases
    }

    private static func hasEndBoundary(_ sentence: Substring) -> Bool {
        guard let last = sentence.last, last.isWhitespace else { return false }
        if last.isNewline { return true }
        let closingMarks = CharacterSet(charactersIn: "»”’\"')]}")
        let words = sentence.trimmingCharacters(in: .whitespacesAndNewlines.union(closingMarks))
        guard let mark = words.last else { return false }
        return ".!?…".contains(mark)
    }

    private static func append(_ slice: Substring, to phrases: inout [String]) {
        let words = slice.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty { phrases.append(words) }
    }
}
