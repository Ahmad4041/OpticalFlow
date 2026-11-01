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

    /// Done tasks never match. Inbox = no project and not someday. Today = planned for today or overdue,
    /// or a deadline today or passed. Upcoming = planned or due after today. Someday = the someday flag.
    public func contains(hasProject: Bool, due: Date?, someday: Bool, done: Bool, deadline: Date? = nil,
                         now: Date = .now, calendar: Calendar = .current) -> Bool {
        if done { return false }
        let day = calendar.startOfDay(for: now)
        switch self {
        case .inbox: return !hasProject && !someday
        case .someday: return someday
        case .today:
            let planned = due.map { calendar.startOfDay(for: $0) <= day } ?? false
            let hard = deadline.map { calendar.startOfDay(for: $0) <= day } ?? false
            return planned || hard
        case .upcoming:
            let planned = due.map { calendar.startOfDay(for: $0) > day }
            let hard = deadline.map { calendar.startOfDay(for: $0) > day }
            // Planned today is Today, not Upcoming, even with a later deadline.
            if planned == false { return false }
            return planned ?? hard ?? false
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
