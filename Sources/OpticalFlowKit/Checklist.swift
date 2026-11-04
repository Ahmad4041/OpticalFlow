import Foundation

/// One step inside a task. Stored as a Codable array on the task.
public struct ChecklistItem: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var isDone: Bool

    public init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

public enum Checklist {
    /// (done, total).
    public static func progress(_ items: [ChecklistItem]) -> (done: Int, total: Int) {
        (items.filter(\.isDone).count, items.count)
    }

    /// True when there is at least one item and every item is done.
    public static func isComplete(_ items: [ChecklistItem]) -> Bool {
        !items.isEmpty && items.allSatisfy(\.isDone)
    }

    /// "a; b; c" or one per line, blanks dropped.
    public static func parse(_ text: String) -> [ChecklistItem] {
        text.split(whereSeparator: { $0 == ";" || $0.isNewline })
            .compactMap { TaskTitle.clean(String($0)) }
            .map { ChecklistItem(title: $0) }
    }

    /// The item whose title contains `text` (case-insensitive), or the 1-based index when `text` is a number.
    public static func index(of text: String, in items: [ChecklistItem]) -> Int? {
        if let n = Int(text), n >= 1, n <= items.count { return n - 1 }
        let lower = text.lowercased()
        return items.firstIndex { $0.title.lowercased().contains(lower) }
    }
}
