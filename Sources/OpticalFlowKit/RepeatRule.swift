import Foundation

/// How a task comes back after it is completed. Stored as its raw string on the task.
public enum RepeatRule: String, CaseIterable, Codable, Sendable {
    case none, daily, weekdays, weekly, monthly, yearly

    public var title: String {
        switch self {
        case .none: "Never"
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly: "Every week"
        case .monthly: "Every month"
        case .yearly: "Every year"
        }
    }

    /// "every day", "daily", "every week", "weekly", "every month", "monthly", "every year", "yearly",
    /// "every weekday", "weekdays". nil for anything else.
    public static func parse(_ text: String) -> RepeatRule? {
        switch text.lowercased().trimmingCharacters(in: .whitespaces) {
        case "daily", "every day", "each day", "everyday": .daily
        case "weekdays", "every weekday", "each weekday", "on weekdays": .weekdays
        case "weekly", "every week", "each week": .weekly
        case "monthly", "every month", "each month": .monthly
        case "yearly", "annually", "every year", "each year": .yearly
        case "never", "none", "no": RepeatRule.none
        default: nil
        }
    }

    /// The next occurrence after `date` (same clock time), and never before `after` so a task
    /// completed late does not come back already overdue.
    public func next(after date: Date, notBefore after: Date = .now, calendar: Calendar = .current) -> Date? {
        guard self != .none else { return nil }
        var candidate = date
        for _ in 0..<400 {
            switch self {
            case .daily: candidate = calendar.date(byAdding: .day, value: 1, to: candidate)!
            case .weekdays:
                repeat { candidate = calendar.date(byAdding: .day, value: 1, to: candidate)! }
                while calendar.isDateInWeekend(candidate)
            case .weekly: candidate = calendar.date(byAdding: .day, value: 7, to: candidate)!
            case .monthly: candidate = calendar.date(byAdding: .month, value: 1, to: candidate)!
            case .yearly: candidate = calendar.date(byAdding: .year, value: 1, to: candidate)!
            case .none: return nil
            }
            if calendar.startOfDay(for: candidate) > calendar.startOfDay(for: after) || candidate > after { return candidate }
        }
        return candidate
    }
}
