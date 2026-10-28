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
