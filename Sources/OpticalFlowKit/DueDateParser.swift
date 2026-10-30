import Foundation

/// Natural-language dates and times anywhere in a task title, typed or spoken:
/// "Fix login tomorrow", "Call Anna fri at 3pm", "Ship in 3 days", "Review next week",
/// "Pay rent on the 5th of November", "tomorrow at 10 call the bank", "Standup at 9:30 on Monday".
/// The date words and the time words come out of the title; the rest stays as written.
public enum DueDateParser {
    public struct Result: Equatable, Sendable {
        public var title: String
        public var due: Date?
        /// True when a clock time was given, so views show it.
        public var hasTime: Bool = false

        public init(title: String, due: Date?, hasTime: Bool = false) {
            self.title = title
            self.due = due
            self.hasTime = hasTime
        }
    }

    public static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> Result {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2 else { return Result(title: text, due: nil) }
        let today = calendar.startOfDay(for: now)

        var dayOffset: Date?
        var time: (hour: Int, minute: Int)?
        // Up to two phrases: a date and a time, in either order, each the longest match in the sentence.
        for _ in 0..<2 {
            if dayOffset == nil, let (range, date) = find(in: words, longest: 5, { dateWords($0, atEnd: $1, today: today, calendar: calendar) }) {
                words.removeSubrange(range)
                dayOffset = date
                continue
            }
            if time == nil, let (range, clock) = find(in: words, longest: 3, { phrase, _ in timeWords(phrase) }) {
                words.removeSubrange(range)
                time = clock
                continue
            }
            if dayOffset == nil, time == nil, let (range, clock) = find(in: words, longest: 1, { phrase, _ in tonightWords(phrase) }) {
                words.removeSubrange(range)
                dayOffset = today
                time = clock
            }
            break
        }
        guard dayOffset != nil || time != nil else { return Result(title: text, due: nil) }
        // A dangling connective at the join or the end: "call the bank on", "meet at".
        while let last = words.last, fillers.contains(last.lowercased()) { words.removeLast() }
        let title = words.joined(separator: " ")
        guard !title.isEmpty else { return Result(title: text, due: nil) }

        var due = dayOffset ?? today
        if let time {
            due = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: due) ?? due
            // A bare time that already passed today means tomorrow.
            if dayOffset == nil, due <= now { due = calendar.date(byAdding: .day, value: 1, to: due) ?? due }
        }
        return Result(title: title, due: due, hasTime: time != nil)
    }

    // MARK: Matching

    private static let fillers: Set<String> = ["on", "at", "by", "due", "for", "the", "this", "next", "of", "in"]

    /// The longest run of words (up to `longest`) anywhere in `words` that the matcher accepts, earliest first.
    private static func find<T>(in words: [String], longest: Int, _ match: ([String], _ atEnd: Bool) -> T?) -> (Range<Int>, T)? {
        let lower = words.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: ":."))) }
        guard words.count >= 2 else { return nil }
        for take in stride(from: min(longest, words.count - 1), through: 1, by: -1) {
            for start in 0...(words.count - take) {
                let phrase = Array(lower[start..<start + take])
                if let value = match(phrase, start + take == words.count) { return (start..<start + take, value) }
            }
        }
        return nil
    }

    private static let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    private static let fullNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let fullMonths = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]

    /// 0-based month for "nov", "november", "sept"; nil for "decks".
    private static func month(_ word: String) -> Int? {
        let w = word.trimmingCharacters(in: .punctuationCharacters)
        return fullMonths.firstIndex(of: w) ?? months.firstIndex(of: w) ?? (w == "sept" ? 8 : nil)
    }

    /// "5th" → 5, "5" → 5.
    private static func ordinal(_ word: String) -> Int? {
        var w = word
        for suffix in ["st", "nd", "rd", "th"] where w.hasSuffix(suffix) && w.count > suffix.count { w.removeLast(suffix.count) }
        return Int(w)
    }

    private static func dateWords(_ input: [String], atEnd: Bool, today: Date, calendar: Calendar) -> Date? {
        func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: today)! }
        var words = input
        // Leading connectives belong to the phrase so they leave the title too: "on friday", "by the 5th".
        var hadPrefix = false
        while let first = words.first, ["on", "by", "due", "for", "the"].contains(first), words.count > 1 {
            words.removeFirst()
            hadPrefix = true
        }
        let joined = words.joined(separator: " ")
        switch joined {
        case "today", "tod": return today
        case "tomorrow", "tom", "tmr": return day(1)
        case "day after tomorrow", "the day after tomorrow": return day(2)
        case "next week": return day(7)
        case "next month": return calendar.date(byAdding: .month, value: 1, to: today)
        case "end of week", "end of the week", "this friday": return weekday(5, from: today, calendar: calendar)
        default: break
        }
        if words.count == 3, words[0] == "in", let n = Int(words[1]) {
            if words[2].hasPrefix("day") { return day(n) }
            if words[2].hasPrefix("week") { return day(n * 7) }
            return nil
        }
        if words.count == 2, words[0] == "in", words[1] == "a" { return nil }
        // Weekdays: "friday" anywhere; "fri" only at the end or after a connective, so "sun" mid-sentence is not a date.
        if words.count == 1 || (words.count == 2 && ["next", "this", "on"].contains(words[0])) {
            let w = words.last!
            if let index = fullNames.firstIndex(of: w) ?? (hadPrefix || atEnd || words.count == 2 ? weekdays.firstIndex(of: w) : nil) {
                return weekday(index + 1, from: today, calendar: calendar)
            }
        }
        if words.count == 1, hadPrefix, let d = ordinal(words[0]), (1...31).contains(d), words[0] != String(d) {
            return nextDayOfMonth(d, today: today, calendar: calendar)   // "the 5th"
        }
        if words.count == 2 || (words.count == 3 && words[1] == "of") {
            let a = words[0], b = words.last!
            if let d = ordinal(a), let m = month(b) {
                return monthDay(day: d, month: m + 1, today: today, calendar: calendar)
            }
            if words.count == 2, let d = ordinal(b), let m = month(a) {
                return monthDay(day: d, month: m + 1, today: today, calendar: calendar)
            }
        }
        if words.count == 1, words[0].count == 10, words[0].dropFirst(4).first == "-" {
            var parts = DateComponents()
            let bits = words[0].split(separator: "-").compactMap { Int($0) }
            if bits.count == 3 { parts.year = bits[0]; parts.month = bits[1]; parts.day = bits[2]; return calendar.date(from: parts) }
        }
        return nil
    }

    /// "at 3pm", "3:30 pm", "at 15:30", "at noon", "at 3" (afternoon when small), "in 2 hours".
    private static func timeWords(_ input: [String]) -> (hour: Int, minute: Int)? {
        var words = input
        var hadAt = false
        if words.first == "at", words.count > 1 { words.removeFirst(); hadAt = true }
        if words.count == 3, words[0] == "in", let n = Int(words[1]) {
            if words[2].hasPrefix("hour") { return inHours(Double(n)) }
            if words[2].hasPrefix("min") { return inHours(Double(n) / 60) }
            return nil
        }
        switch words.joined(separator: " ") {
        case "noon", "midday": return (12, 0)
        case "midnight": return (0, 0)
        case "morning", "in the morning": return hadAt || input.count > 1 ? (9, 0) : nil
        case "afternoon", "in the afternoon": return hadAt || input.count > 1 ? (14, 0) : nil
        case "evening", "in the evening": return hadAt || input.count > 1 ? (18, 0) : nil
        default: break
        }
        guard words.count <= 2 else { return nil }
        var text = words[0]
        var meridiem: String?
        if words.count == 2 {
            guard ["am", "pm", "a.m.", "p.m.", "a.m", "p.m"].contains(words[1]) else { return nil }
            meridiem = String(words[1].prefix(1))
        }
        for suffix in ["am", "pm", "a.m.", "p.m.", "a.m", "p.m"] where text.hasSuffix(suffix) {
            meridiem = String(suffix.prefix(1))
            text.removeLast(suffix.count)
        }
        let parts = text.split(separator: ":").map(String.init)
        guard (1...2).contains(parts.count), let hour = Int(parts[0]), (0...23).contains(hour) else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) : 0
        guard let minute, (0...59).contains(minute) else { return nil }
        // A bare number needs "at" or a colon to count as a time: "call 3 friends" is not 3 o'clock.
        guard meridiem != nil || hadAt || parts.count == 2 else { return nil }
        var h = hour
        if meridiem == "p", h < 12 { h += 12 }
        if meridiem == "a", h == 12 { h = 0 }
        if meridiem == nil, parts.count == 1, hadAt, h >= 1, h <= 6 { h += 12 }   // "at 3" is the afternoon
        return (h, minute)
    }

    /// "tonight" and "this evening": today, in the evening.
    private static func tonightWords(_ words: [String]) -> (hour: Int, minute: Int)? {
        words == ["tonight"] ? (20, 0) : nil
    }

    private static func inHours(_ hours: Double) -> (hour: Int, minute: Int) {
        let date = Date.now.addingTimeInterval(hours * 3600)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0, parts.minute ?? 0)
    }

    /// The next such weekday (1 = Sunday), never today.
    private static func weekday(_ target: Int, from today: Date, calendar: Calendar) -> Date {
        let ahead = (target - calendar.component(.weekday, from: today) + 7) % 7
        return calendar.date(byAdding: .day, value: ahead == 0 ? 7 : ahead, to: today)!
    }

    /// This year, or next year when the date has passed.
    private static func monthDay(day: Int, month: Int, today: Date, calendar: Calendar) -> Date? {
        guard (1...31).contains(day) else { return nil }
        let year = calendar.component(.year, from: today)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return date < today ? calendar.date(byAdding: .year, value: 1, to: date) : date
    }

    /// The next time this day-of-month comes around.
    private static func nextDayOfMonth(_ day: Int, today: Date, calendar: Calendar) -> Date? {
        var parts = calendar.dateComponents([.year, .month], from: today)
        parts.day = day
        guard let thisMonth = calendar.date(from: parts) else { return nil }
        return thisMonth >= today ? thisMonth : calendar.date(byAdding: .month, value: 1, to: thisMonth)
    }
}
