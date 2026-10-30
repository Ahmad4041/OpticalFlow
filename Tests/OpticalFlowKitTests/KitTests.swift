import Foundation
import Testing
@testable import OpticalFlowKit

@Test("Clean titles", arguments: [
    ("Buy milk", "Buy milk"), ("  Buy   milk \n", "Buy milk"), ("", nil), ("   ", nil),
])
func cleans(_ input: String, expected: String?) {
    #expect(TaskTitle.clean(input) == expected)
}

@Test func smartLists() {
    let cal = Calendar.current
    let now = Date.now
    let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
    let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
    #expect(SmartList.inbox.contains(hasProject: false, due: nil, someday: false, done: false))
    #expect(!SmartList.inbox.contains(hasProject: true, due: nil, someday: false, done: false))
    #expect(!SmartList.inbox.contains(hasProject: false, due: nil, someday: true, done: false))
    #expect(SmartList.today.contains(hasProject: true, due: now, someday: false, done: false))
    #expect(SmartList.today.contains(hasProject: true, due: yesterday, someday: false, done: false))
    #expect(!SmartList.today.contains(hasProject: true, due: tomorrow, someday: false, done: false))
    #expect(SmartList.upcoming.contains(hasProject: true, due: tomorrow, someday: false, done: false))
    #expect(!SmartList.upcoming.contains(hasProject: true, due: now, someday: false, done: false))
    #expect(SmartList.someday.contains(hasProject: true, due: nil, someday: true, done: false))
    #expect(!SmartList.today.contains(hasProject: true, due: now, someday: false, done: true))
}

@Test func countdown() {
    #expect(Countdown.label(planned: 1500, elapsed: 1) == "24:59")
    #expect(Countdown.label(planned: 1500, elapsed: 1505) == "+00:05")
    #expect(Countdown.label(planned: 1500, elapsed: 750, paused: true) == "⏸ 12:30")
    #expect(Countdown.label(planned: 1500, elapsed: 50, recording: true) == "● 24:10")
    #expect(Countdown.clock(3723) == "1:02:03")
    #expect(Countdown.clock(65, padded: false) == "1:05")
}

@Test func chapters() {
    let marks = [
        ChapterMark(title: "Fix login", offset: 95),
        ChapterMark(title: "Too early", offset: 4),
        ChapterMark(title: "Merged in", offset: 100),
        ChapterMark(title: "Ship", offset: 3725),
    ]
    let text = ChapterList.text(opening: "Session: auth", marks: marks)
    #expect(text == "0:00 Session: auth\n1:35 Merged in\n1:02:05 Ship")
    #expect(ChapterList.text(opening: "Only", marks: []) == "0:00 Only")
}

@Test func trimmedChapters() {
    let marks = [ChapterMark(title: "A", offset: 30), ChapterMark(title: "B", offset: 100), ChapterMark(title: "C", offset: 500)]
    let kept = ChapterList.trimmed(marks, start: 60, end: 400)
    #expect(kept == [ChapterMark(title: "B", offset: 40)])
    #expect(ChapterList.trimmed(marks, start: 0, end: 1000) == marks)
}

@Test func dayLabels() {
    let cal = Calendar.current
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12))!
    func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: now)! }
    #expect(DayGroup.label(for: day(0), now: now) == "Today")
    #expect(DayGroup.label(for: day(1), now: now) == "Tomorrow")
    #expect(DayGroup.label(for: day(2), now: now).hasPrefix("Saturday"))
    #expect(DayGroup.label(for: day(10), now: now).contains("2026"))
}

@Test func dueDates() {
    let cal = Calendar.current
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12))!   // a Thursday
    func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: now))! }
    #expect(DueDateParser.parse("Fix login tomorrow", now: now) == .init(title: "Fix login", due: day(1)))
    #expect(DueDateParser.parse("Call Anna fri", now: now) == .init(title: "Call Anna", due: day(1)))
    #expect(DueDateParser.parse("Standup thursday", now: now) == .init(title: "Standup", due: day(7)))
    #expect(DueDateParser.parse("Ship in 3 days", now: now) == .init(title: "Ship", due: day(3)))
    #expect(DueDateParser.parse("Review next week", now: now) == .init(title: "Review", due: day(7)))
    #expect(DueDateParser.parse("Pay rent 5 nov", now: now).due == cal.date(from: DateComponents(year: 2026, month: 11, day: 5)))
    #expect(DueDateParser.parse("Taxes mar 1", now: now).due == cal.date(from: DateComponents(year: 2027, month: 3, day: 1)))
    #expect(DueDateParser.parse("tomorrow", now: now) == .init(title: "tomorrow", due: nil))
    #expect(DueDateParser.parse("Buy milk", now: now) == .init(title: "Buy milk", due: nil))
    #expect(DueDateParser.parse("Read the book in sunlight", now: now).due == nil)
}

@Test func cameraLayoutFrames() {
    let canvas = CGSize(width: 1920, height: 1080)
    let br = CameraLayout(corner: .bottomRight, size: .medium, shape: .circle).frame(in: canvas)
    #expect(br == CGRect(x: 1920 - 480 - 38, y: 38, width: 480, height: 480))
    let tl = CameraLayout(corner: .topLeft, size: .small, shape: .rounded).frame(in: canvas)
    #expect(tl == CGRect(x: 38, y: 1080 - 180 - 38, width: 320, height: 180))
    #expect(CameraLayout(shape: .circle).cornerRadius(for: br) == 240)
    #expect(CameraLayout(shape: .rounded).cornerRadius(for: tl) == 26)
}

@Test func cursorViewport() {
    let track = CursorTrack(samples: [.init(t: 0, x: 0.5, y: 0.5), .init(t: 2, x: 0.02, y: 0.98)])
    #expect(track.viewport(at: 1, zoom: 2) == CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    #expect(track.viewport(at: 3, zoom: 2) == CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
    #expect(CursorTrack().viewport(at: 1, zoom: 2) == CGRect(x: 0, y: 0, width: 1, height: 1))
    let smooth = track.smoothed()
    #expect(smooth.samples[1].x > 0.02 && smooth.samples[1].x < 0.5)
}

@Test func normalizePoint() {
    let rect = CGRect(x: 1920, y: 0, width: 2560, height: 1440)   // a second display to the right
    #expect(CursorTrack.normalize(CGPoint(x: 3200, y: 720), in: rect) == CGPoint(x: 0.5, y: 0.5))
    #expect(CursorTrack.normalize(CGPoint(x: 100, y: 5000), in: rect) == CGPoint(x: 0, y: 1))
}

@Test func sessionStats() {
    let cal = Calendar.current
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!
    let days = SessionStats.perDay([(now, 1500), (now.addingTimeInterval(-3600), 600), (cal.date(byAdding: .day, value: -2, to: now)!, 900)], now: now)
    #expect(days.count == 7)
    #expect(days.last?.seconds == 2100)
    #expect(days[4].seconds == 900)
    #expect(days.reduce(0) { $0 + $1.seconds } == 3000)
    #expect(SessionStats.hours(3900) == "1h 05m")
    #expect(SessionStats.hours(2700) == "45m")
}
