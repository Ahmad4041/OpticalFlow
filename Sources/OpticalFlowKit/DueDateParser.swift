import Foundation

/// Natural-language due dates at the end of a task title:
/// "Fix login tomorrow", "Call Anna fri", "Ship in 3 days", "Review next week", "Pay rent 5 nov".
public enum DueDateParser {
    public struct Result: Equatable {
        public var title: String
        public var due: Date?
    }

    public static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> Result {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2 else { return Result(title: text, due: nil) }
        let today = calendar.startOfDay(for: now)
        func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: today)! }

        // Longest suffix first: "in 3 days", "next week", "5 nov", then one word.
        for take in stride(from: min(3, words.count - 1), through: 1, by: -1) {
            let suffix = words.suffix(take).map { $0.lowercased() }
            let title = words.dropLast(take).joined(separator: " ")
            if let due = date(for: suffix, today: today, day: day, calendar: calendar) {
                return Result(title: title, due: due)
            }
        }
        return Result(title: text, due: nil)
    }

    private static let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    private static let fullNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    private static func date(for words: [String], today: Date, day: (Int) -> Date, calendar: Calendar) -> Date? {
        switch words.joined(separator: " ") {
        case "today", "tod": return today
        case "tomorrow", "tom", "tmr": return day(1)
        case "next week": return day(7)
        default: break
        }
        if words.count == 3, words[0] == "in", let n = Int(words[1]) {
            if words[2] == "day" || words[2] == "days" { return day(n) }
            if words[2] == "week" || words[2] == "weeks" { return day(n * 7) }
            return nil
        }
        if words.count == 1, let index = weekdays.firstIndex(where: { full in
            // "fri", "friday"; not "sunlight".
            let w = words[0]
            return w == full || w == fullNames[weekdays.firstIndex(of: full)!]
        }) {
            // Next such weekday, never today.
            let ahead = (index + 1 - calendar.component(.weekday, from: today) + 7) % 7
            return day(ahead == 0 ? 7 : ahead)
        }
        if words.count == 2 {
            let (a, b) = (words[0], words[1])
            if let d = Int(a), let m = months.firstIndex(where: { b.hasPrefix($0) }) {
                return monthDay(day: d, month: m + 1, today: today, calendar: calendar)
            }
            if let d = Int(b), let m = months.firstIndex(where: { a.hasPrefix($0) }) {
                return monthDay(day: d, month: m + 1, today: today, calendar: calendar)
            }
        }
        return nil
    }

    /// This year, or next year when the date has passed.
    private static func monthDay(day: Int, month: Int, today: Date, calendar: Calendar) -> Date? {
        guard (1...31).contains(day) else { return nil }
        let year = calendar.component(.year, from: today)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return date < today ? calendar.date(byAdding: .year, value: 1, to: date) : date
    }
}
