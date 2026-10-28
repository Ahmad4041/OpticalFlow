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

/// Day headings for Upcoming.
public enum DayGroup {
    /// "Today", "Tomorrow", then "Thursday 30 Oct" within a week, then "30 Oct 2026".
    public static func label(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        default: return date.formatted(.dateTime.day().month(.abbreviated).year())
        }
    }
}
