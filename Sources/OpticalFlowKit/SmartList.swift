import Foundation

/// The four smart lists. One rule each, over plain values so tests need no database.
public enum SmartList: String, CaseIterable, Sendable {
    case inbox, today, upcoming, someday

    public var title: String {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .someday: "Someday"
        }
    }

    public var symbol: String {
        switch self {
        case .inbox: "tray"
        case .today: "star"
        case .upcoming: "calendar"
        case .someday: "archivebox"
        }
    }

    /// Done tasks never match. Inbox = no project and not someday. Today = due today or overdue.
    /// Upcoming = due after today. Someday = the someday flag.
    public func contains(hasProject: Bool, due: Date?, someday: Bool, done: Bool,
                         now: Date = .now, calendar: Calendar = .current) -> Bool {
        if done { return false }
        switch self {
        case .inbox: return !hasProject && !someday
        case .someday: return someday
        case .today:
            guard let due else { return false }
            return calendar.startOfDay(for: due) <= calendar.startOfDay(for: now)
        case .upcoming:
            guard let due else { return false }
            return calendar.startOfDay(for: due) > calendar.startOfDay(for: now)
        }
    }
}
