import Foundation

/// Instant, offline tidy-up used when the AI cleanup isn't ready in time:
/// drops "um/uh" and collapses stutters such as "let me let me look".
///
/// Deliberately conservative. It never reorders or rewrites, and repeated
/// single words are only collapsed for very common words, so phrases like
/// "very very good" or "had had" are left alone.
public enum LocalTextTidy {

    static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "er", "erm", "hmm"]

    /// Single words that are safe to collapse when spoken twice in a row.
    static let repeatable: Set<String> = [
        "i", "we", "you", "he", "she", "they", "it", "the", "a", "an", "and", "but", "so",
        "to", "of", "in", "on", "is", "are", "was", "be", "if", "or", "my", "this", "that", "for", "with",
    ]

    public static func tidy(_ text: String) -> String {
        var words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        words.removeAll { fillers.contains(normalise($0)) }

        var changed = true
        while changed {
            changed = false
            for length in [3, 2, 1] {
                var i = 0
                while i + 2 * length <= words.count {
                    let first = words[i..<(i + length)].map(normalise)
                    let second = words[(i + length)..<(i + 2 * length)].map(normalise)
                    let isRepeat = first == second
                        && !first.contains(where: \.isEmpty)
                        && (length > 1 || repeatable.contains(first[0]))
                    if isRepeat {
                        // Keep the second copy: it carries the trailing punctuation.
                        words.removeSubrange(i..<(i + length))
                        changed = true
                    } else {
                        i += 1
                    }
                }
            }
        }

        var result = words.joined(separator: " ")
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return result
    }

    private static func normalise(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "'" }
    }
}
