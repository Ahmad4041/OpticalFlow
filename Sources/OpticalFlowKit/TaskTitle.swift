import Foundation

/// Rules for task titles.
public enum TaskTitle {
    /// Trims and collapses whitespace. nil when nothing is left: an empty title is rejected.
    public static func clean(_ text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}
