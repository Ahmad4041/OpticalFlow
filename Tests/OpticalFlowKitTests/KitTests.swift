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
    func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day(d))! }
    #expect(DueDateParser.parse("Call Anna fri at 3pm", now: now) == .init(title: "Call Anna", due: at(1, 15), hasTime: true))
    #expect(DueDateParser.parse("tomorrow at 10 call the bank", now: now) == .init(title: "call the bank", due: at(1, 10), hasTime: true))
    #expect(DueDateParser.parse("Standup at 9:30 on Monday", now: now) == .init(title: "Standup", due: at(4, 9, 30), hasTime: true))
    #expect(DueDateParser.parse("Pay rent on the 5th of November", now: now).due == cal.date(from: DateComponents(year: 2026, month: 11, day: 5)))
    #expect(DueDateParser.parse("Pay rent on the 5th of November", now: now).title == "Pay rent")
    #expect(DueDateParser.parse("Dentist November 5th 2 pm", now: now) == .init(title: "Dentist", due: cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 14)), hasTime: true))
    #expect(DueDateParser.parse("Buy milk at 3", now: now) == .init(title: "Buy milk", due: at(0, 15), hasTime: true))
    #expect(DueDateParser.parse("Lunch at noon", now: now) == .init(title: "Lunch", due: at(1, 12), hasTime: true))
    #expect(DueDateParser.parse("Fix login tonight", now: now) == .init(title: "Fix login", due: at(0, 20), hasTime: true))
    #expect(DueDateParser.parse("Rent on the 1st", now: now).due == cal.date(from: DateComponents(year: 2026, month: 11, day: 1)))
    #expect(DueDateParser.parse("Call 3 friends", now: now).due == nil)
    #expect(DueDateParser.parse("Sort 2 decks", now: now).due == nil)
    #expect(DueDateParser.parse("Release 2026-11-05", now: now).due == cal.date(from: DateComponents(year: 2026, month: 11, day: 5)))
    // Deadlines and repeats
    let byFri = DueDateParser.parse("Send the invoice by friday", now: now)
    #expect(byFri == .init(title: "Send the invoice", due: nil, deadline: day(1)))
    let planAndDeadline = DueDateParser.parse("Draft the talk tomorrow by the 5th of November", now: now)
    #expect(planAndDeadline.title == "Draft the talk" && planAndDeadline.due == day(1) && planAndDeadline.deadline == cal.date(from: DateComponents(year: 2026, month: 11, day: 5)))
    #expect(DueDateParser.parse("Sort the drawer by hand", now: now).due == nil)
    let rent = DueDateParser.parse("Pay rent every month on the 1st", now: now)
    #expect(rent.title == "Pay rent" && rent.repeatRule == .monthly && rent.due == cal.date(from: DateComponents(year: 2026, month: 11, day: 1)))
    let standup = DueDateParser.parse("Standup weekdays at 9:30", now: now)
    #expect(standup.title == "Standup" && standup.repeatRule == .weekdays && standup.due == at(0, 9, 30) || standup.due == at(1, 9, 30))
    #expect(DueDateParser.parse("Water the plants daily", now: now) == .init(title: "Water the plants", due: day(0), repeatRule: .daily))
}

@Test func repeats() {
    let cal = Calendar.current
    let fri = cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 9))!   // a Friday
    #expect(RepeatRule.parse("every month") == .monthly && RepeatRule.parse("weekdays") == .weekdays && RepeatRule.parse("soon") == nil)
    #expect(RepeatRule.daily.next(after: fri, notBefore: fri) == cal.date(byAdding: .day, value: 1, to: fri))
    #expect(RepeatRule.weekdays.next(after: fri, notBefore: fri) == cal.date(byAdding: .day, value: 3, to: fri))   // Monday
    #expect(RepeatRule.monthly.next(after: fri, notBefore: fri) == cal.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 9)))
    // Completed a month late: the next one is after today, not already overdue.
    let late = cal.date(byAdding: .day, value: 45, to: fri)!
    #expect(RepeatRule.weekly.next(after: fri, notBefore: late)! > late)
    #expect(RepeatRule.none.next(after: fri) == nil)
}

@Test func chapterIssues() {
    let two = [ChapterMark(title: "A", offset: 30)]
    #expect(ChapterList.issues(opening: "Start", marks: two) == ["YouTube needs at least 3 chapters; this list has 2."])
    let three = [ChapterMark(title: "A", offset: 30), ChapterMark(title: "B", offset: 60)]
    #expect(ChapterList.issues(opening: "Start", marks: three, duration: 120).isEmpty)
    #expect(ChapterList.issues(opening: "Start", marks: three, duration: 65) == ["The last chapter is shorter than 10 seconds."])
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

@Test func sessionClock() {
    let t0 = Date(timeIntervalSince1970: 1000)
    var clock = SessionClock(planned: 1500, startedAt: t0)
    #expect(clock.elapsed(at: t0.addingTimeInterval(10)) == 10)
    clock.pause(at: t0.addingTimeInterval(10))
    #expect(clock.isPaused && clock.elapsed(at: t0.addingTimeInterval(100)) == 10)
    clock.resume(at: t0.addingTimeInterval(100))
    #expect(clock.elapsed(at: t0.addingTimeInterval(105)) == 15)
    #expect(!clock.isOver(at: t0.addingTimeInterval(105)))
    #expect(clock.stop(at: t0.addingTimeInterval(1600)) == 1510)
    #expect(clock.isPaused && clock.elapsed(at: t0.addingTimeInterval(9999)) == 1510)
}

@Test func boardColumns() {
    #expect(BoardColumn.column(someday: false, doing: false, done: false) == .todo)
    #expect(BoardColumn.column(someday: true, doing: false, done: false) == .backlog)
    #expect(BoardColumn.column(someday: true, doing: true, done: false) == .doing)
    #expect(BoardColumn.column(someday: true, doing: true, done: true) == .done)
}

@Test func editDistance() {
    #expect(TaskTitle.distance("fordan", "forthan") == 2)
    #expect(TaskTitle.distance("stream", "stream") == 0)
    #expect(TaskTitle.distance("", "abc") == 3)
}

@Test func priorities() {
    #expect(Priority.parse("urgent") == .high && Priority.parse("P2") == .medium && Priority.parse("low") == .low)
    #expect(Priority.parse("none") == Priority.none && Priority.parse("later") == nil)
    #expect(Priority.high > Priority.low)
}

@Test("Voice intents", arguments: [
    ("Add a task fix the login loop tomorrow.", VoiceIntent.add(title: "fix the login loop tomorrow")),
    ("remind me to call the bank", .add(title: "call the bank")),
    ("Write the chapter export", .add(title: "Write the chapter export")),
    ("complete the login loop", .complete(match: "the login loop")),
    ("login loop is done", .complete(match: "login loop")),
    ("start a session on the chapter export", .start(match: "the chapter export")),
    ("work on the OBS scene", .start(match: "the obs scene")),
    ("stop the session", .stop),
    ("make the login loop urgent", .setPriority(match: "the login loop", .high)),
    ("mark chapter export as low priority", .setPriority(match: "chapter export", .low)),
    ("the picker API is medium priority", .setPriority(match: "the picker api", .medium)),
    ("add a note to the login loop: repro needs sign out first", .addNote(match: "the login loop", note: "repro needs sign out first")),
    ("note on chapter export saying use the youtube preset", .addNote(match: "chapter export", note: "use the youtube preset")),
    ("add a subtask to the login loop: write the regression test", .addSubtask(match: "the login loop", title: "write the regression test")),
    ("add a step under chapter export called upload the file", .addSubtask(match: "chapter export", title: "upload the file")),
    ("mark that", .mark(title: nil)),
    ("add a marker called the bug appears", .mark(title: "the bug appears")),
])
func voiceIntents(_ text: String, expected: VoiceIntent) {
    #expect(VoiceIntent.parse(text) == expected)
}

@Test func checklists() {
    let items = Checklist.parse("Write the test; Run it;\n\nShip")
    #expect(items.map(\.title) == ["Write the test", "Run it", "Ship"])
    var done = items; done[1].isDone = true
    #expect(Checklist.progress(done) == (1, 3))
    #expect(Checklist.index(of: "2", in: items) == 1 && Checklist.index(of: "ship", in: items) == 2 && Checklist.index(of: "nope", in: items) == nil)
}

@Test func silenceCut() {
    // 0.1 s windows: loud 0-1 s, quiet 1-4 s, loud 4-6 s, quiet 6-6.5 s (too short to cut).
    let levels: [Float] = Array(repeating: 0.3, count: 10) + Array(repeating: 0.001, count: 30)
        + Array(repeating: 0.3, count: 20) + Array(repeating: 0.001, count: 5)
    let keep = SilenceCut.keep(levels: levels, step: 0.1, start: 0, end: 6.5)
    #expect(keep.count == 2)
    #expect(abs(keep[0].lowerBound - 0) < 0.001 && abs(keep[0].upperBound - 1.2) < 0.001)
    #expect(abs(keep[1].lowerBound - 3.8) < 0.001 && abs(keep[1].upperBound - 6.5) < 0.001)
    #expect(abs(SilenceCut.length(keep) - 3.9) < 0.001)
    // Inside the trim window only; a pause cut off by the window edge still counts from the edge.
    let windowed = SilenceCut.keep(levels: levels, step: 0.1, start: 0.5, end: 2)
    #expect(windowed.count == 2 && abs(windowed[0].upperBound - 1.2) < 0.001 && abs(windowed[1].lowerBound - 1.8) < 0.001)
    #expect(SilenceCut.keep(levels: Array(repeating: 0.3, count: 60), step: 0.1, start: 1, end: 5) == [1...5])
    // Chapters: before the cut stays, inside the cut goes, after the cut moves back by the cut's length.
    let marks = [ChapterMark(title: "A", offset: 0.5), ChapterMark(title: "B", offset: 2), ChapterMark(title: "C", offset: 5)]
    let out = ChapterList.trimmed(marks, keep: keep)
    #expect(out.map(\.title) == ["A", "C"])
    #expect(abs(out[1].offset - 2.4) < 0.001)
    #expect(ChapterList.trimmed(marks, start: 1, end: 6) == [ChapterMark(title: "B", offset: 1), ChapterMark(title: "C", offset: 4)])
}

@Test func exportSuffix() {
    #expect(ExportOptions().suffix == "")
    #expect(ExportOptions(camera: true, followCursor: true, youtube: true, removeSilence: true).suffix == " with camera zoomed youtube no silence")
    #expect(ExportOptions(youtube: true).suffix == " youtube")
}

@Test func versions() {
    #expect(AppVersion("v0.2.0")! > AppVersion("0.1.1")!)
    #expect(AppVersion("0.10.0")! > AppVersion("0.9.9")!)
    #expect(AppVersion("0.2")! == AppVersion("0.2.0")!)
    #expect(!(AppVersion("0.2.0")! > AppVersion("0.2")!))
    #expect(AppVersion("beta") == nil && AppVersion("") == nil)
    #expect(AppVersion("v1.2.3")!.description == "1.2.3")
}

@Test func releaseFeed() {
    let json = """
    {"tag_name":"v0.2.0","body":"New things.\\n\\n## Install\\nDrag it.","html_url":"https://github.com/o/r/releases/tag/v0.2.0",
     "draft":false,"prerelease":false,"assets":[
       {"name":"OpticalFlow-0.2.0.dmg","browser_download_url":"https://x/OpticalFlow-0.2.0.dmg"},
       {"name":"OpticalFlow-0.2.0.zip","browser_download_url":"https://x/OpticalFlow-0.2.0.zip"},
       {"name":"OpticalFlow-0.2.0.zip.sha256","browser_download_url":"https://x/OpticalFlow-0.2.0.zip.sha256"}]}
    """
    let release = Release.parse(github: Data(json.utf8))
    #expect(release?.version == AppVersion("0.2.0"))
    #expect(release?.notes == "New things.")
    #expect(release?.zip.lastPathComponent == "OpticalFlow-0.2.0.zip")
    #expect(release?.checksum.lastPathComponent == "OpticalFlow-0.2.0.zip.sha256")
    // No checksum, no update; a prerelease is not offered.
    #expect(Release.parse(github: Data(json.replacingOccurrences(of: ".zip.sha256\"", with: ".txt\"").utf8)) == nil)
    #expect(Release.parse(github: Data(json.replacingOccurrences(of: "\"prerelease\":false", with: "\"prerelease\":true").utf8)) == nil)
    let hex = String(repeating: "ab", count: 32)
    #expect(Release.digest(inChecksumFile: "\(hex.uppercased())  OpticalFlow-0.2.0.zip\n") == hex)
    #expect(Release.digest(inChecksumFile: "not a sum") == nil)
}

@Test func checklistComplete() {
    #expect(!Checklist.isComplete([]))
    #expect(!Checklist.isComplete([ChecklistItem(title: "a", isDone: true), ChecklistItem(title: "b")]))
    #expect(Checklist.isComplete([ChecklistItem(title: "a", isDone: true), ChecklistItem(title: "b", isDone: true)]))
}
