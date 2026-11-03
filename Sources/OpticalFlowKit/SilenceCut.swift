import Foundation

/// Finds the pauses in a recording from its audio levels and says which stretches to keep.
/// Levels are one number per fixed `step` of audio (RMS, 0 to 1). A pause is a run of quiet
/// windows at least `minimum` seconds long; a little of it stays on each side (`pad`) so
/// words are not clipped.
public enum SilenceCut {
    /// RMS below this is quiet: 0.01 is -40 dBFS, where room tone and mic hiss sit.
    /// ponytail: fixed threshold; make it a setting if a noisy mic ever cuts too little.
    public static let threshold: Float = 0.01
    public static let minimum: TimeInterval = 1
    /// Seconds of audio per level window.
    public static let step: TimeInterval = 0.05
    public static let pad: TimeInterval = 0.2

    /// The ranges of the original to keep, inside [start, end], in order. With no pauses, one range.
    public static func keep(levels: [Float], step: TimeInterval, start: TimeInterval, end: TimeInterval,
                            threshold: Float = threshold, minimum: TimeInterval = minimum, pad: TimeInterval = pad) -> [ClosedRange<TimeInterval>] {
        guard end > start else { return [] }
        var kept: [ClosedRange<TimeInterval>] = []
        var cursor = start
        var quietFrom: Int?
        func close(_ from: Int, _ to: Int) {
            let quietStart = max(start, Double(from) * step), quietEnd = min(end, Double(to) * step)
            let cutStart = quietStart + pad, cutEnd = quietEnd - pad
            guard quietEnd - quietStart >= minimum, cutEnd > cutStart else { return }
            if cutStart > cursor { kept.append(cursor...cutStart) }
            cursor = cutEnd
        }
        let first = Int(start / step), last = min(levels.count, Int((end / step).rounded(.up)))
        for i in first..<max(first, last) {
            if levels[i] < threshold {
                if quietFrom == nil { quietFrom = i }
            } else if let from = quietFrom {
                close(from, i)
                quietFrom = nil
            }
        }
        if let from = quietFrom { close(from, last) }
        if end > cursor { kept.append(cursor...end) }
        return kept
    }

    /// Seconds a set of kept ranges adds up to.
    public static func length(_ keep: [ClosedRange<TimeInterval>]) -> TimeInterval {
        keep.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
    }

    /// Where an offset in the original lands in the export; nil when it fell in a cut.
    public static func mapped(_ offset: TimeInterval, keep: [ClosedRange<TimeInterval>]) -> TimeInterval? {
        var at: TimeInterval = 0
        for range in keep {
            if range.contains(offset) { return at + offset - range.lowerBound }
            at += range.upperBound - range.lowerBound
        }
        return nil
    }
}
