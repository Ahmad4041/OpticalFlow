import Foundation

/// The kanban columns of a project. One rule maps a task's flags to a column, and back.
public enum BoardColumn: String, CaseIterable, Codable, Sendable {
    case backlog, todo, doing, done

    public var title: String {
        switch self {
        case .backlog: "Backlog"
        case .todo: "To Do"
        case .doing: "Doing"
        case .done: "Done"
        }
    }

    public var symbol: String {
        switch self {
        case .backlog: "archivebox"
        case .todo: "circle"
        case .doing: "timer"
        case .done: "checkmark.circle"
        }
    }

    /// Done wins, then Doing, then Backlog (someday), else To Do.
    public static func column(someday: Bool, doing: Bool, done: Bool) -> BoardColumn {
        if done { return .done }
        if doing { return .doing }
        if someday { return .backlog }
        return .todo
    }
}
