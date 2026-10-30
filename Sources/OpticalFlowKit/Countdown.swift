import Foundation

/// Text for the menu bar timer.
public enum Countdown {
    /// "24:59" while time remains, "+00:05" in overflow. Paused adds "⏸ ", recording adds "● ".
    public static func label(planned: Int, elapsed: Int, paused: Bool = false, recording: Bool = false) -> String {
        let remaining = planned - elapsed
        let time = remaining >= 0 ? clock(remaining) : "+" + clock(-remaining)
        return (recording ? "● " : "") + (paused ? "⏸ " : "") + time
    }

    /// Seconds as "mm:ss" (padded, for a menu bar label that must not jump) or "m:ss",
    /// and "h:mm:ss" from one hour.
    public static func clock(_ seconds: Int, padded: Bool = true) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: padded ? "%02d:%02d" : "%d:%02d", m, sec)
    }
}

/// Totals for the Sessions page.
public enum SessionStats {
    public struct Day: Equatable, Sendable {
        public var date: Date
        public var seconds: Int
    }

    /// Worked seconds for each of the last `days` days (oldest first), from (start, seconds) pairs.
    public static func perDay(_ sessions: [(Date, Int)], days: Int = 7, now: Date = .now, calendar: Calendar = .current) -> [Day] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            let total = sessions.filter { calendar.isDate($0.0, inSameDayAs: day) }.reduce(0) { $0 + $1.1 }
            return Day(date: day, seconds: total)
        }
    }

    /// "1h 05m", "45m", "0m".
    public static func hours(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? String(format: "%dh %02dm", h, m) : "\(m)m"
    }
}
