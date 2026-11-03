import Foundation

/// A task completed while recording, at an offset into the recording.
public struct ChapterMark: Codable, Hashable, Sendable {
    public var title: String
    public var offset: TimeInterval

    public init(title: String, offset: TimeInterval) {
        self.title = title
        self.offset = offset
    }
}

/// The chapter list YouTube reads from a video description: first line at 0:00,
/// every chapter at least 10 seconds after the one before.
public enum ChapterList {
    public static let minimumGap: TimeInterval = 10

    /// Marks sorted by offset. A mark closer than 10 s to the previous kept line is merged
    /// into it (the later title wins, the earlier offset stays). Marks under 10 s are absorbed
    /// by the opening line.
    public static func lines(opening: String, marks: [ChapterMark]) -> [ChapterMark] {
        var kept = [ChapterMark(title: opening, offset: 0)]
        for mark in marks.sorted(by: { $0.offset < $1.offset }) {
            if mark.offset - kept[kept.count - 1].offset < minimumGap {
                if kept.count > 1 { kept[kept.count - 1].title = mark.title }
            } else {
                kept.append(mark)
            }
        }
        return kept
    }

    public static func text(opening: String, marks: [ChapterMark]) -> String {
        lines(opening: opening, marks: marks)
            .map { "\(Countdown.clock(Int($0.offset), padded: false)) \($0.title)" }
            .joined(separator: "\n")
    }
}

extension ChapterList {
    /// Why YouTube would ignore this list, in plain words. Empty when it passes:
    /// first line at 0:00 (always true here), at least three chapters, each 10 s or more apart.
    public static func issues(opening: String, marks: [ChapterMark], duration: TimeInterval? = nil) -> [String] {
        let kept = lines(opening: opening, marks: marks)
        var issues: [String] = []
        if kept.count < 3 { issues.append("YouTube needs at least 3 chapters; this list has \(kept.count).") }
        if let duration, let last = kept.last, kept.count > 1, duration - last.offset < minimumGap {
            issues.append("The last chapter is shorter than 10 seconds.")
        }
        return issues
    }

    /// Chapters that survive a trim to [start, end): offsets move back by `start`.
    public static func trimmed(_ marks: [ChapterMark], start: TimeInterval, end: TimeInterval) -> [ChapterMark] {
        trimmed(marks, keep: [start...end])
    }

    /// Chapters that survive an export of the kept ranges, in export time. A mark inside a cut is dropped.
    public static func trimmed(_ marks: [ChapterMark], keep: [ClosedRange<TimeInterval>]) -> [ChapterMark] {
        marks.compactMap { mark in
            SilenceCut.mapped(mark.offset, keep: keep).map { ChapterMark(title: mark.title, offset: $0) }
        }
    }
}
