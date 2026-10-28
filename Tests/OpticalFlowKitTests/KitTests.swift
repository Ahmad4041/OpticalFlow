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
