import Foundation

/// How urgent a task is. Stored as its raw number on the task.
public enum Priority: Int, CaseIterable, Codable, Sendable, Comparable {
    case none = 0, low, medium, high

    public var title: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    public static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }

    /// "high", "urgent", "asap", "p1" → high; "medium", "normal", "p2" → medium; "low", "p3" → low; "none" → none.
    public static func parse(_ text: String) -> Priority? {
        switch text.lowercased().trimmingCharacters(in: .whitespaces) {
        case "high", "urgent", "asap", "critical", "p1", "3": .high
        case "medium", "normal", "p2", "2": .medium
        case "low", "minor", "p3", "1": .low
        case "none", "clear", "0": Priority.none
        default: nil
        }
    }
}
