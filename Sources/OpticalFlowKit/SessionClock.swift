import Foundation

/// The arithmetic of one focus session: banked seconds plus live time since the last resume.
/// Plain values, no actors, so the rules test without the app. AppModel owns one and feeds it `now`.
public struct SessionClock: Equatable, Sendable {
    public var planned: Int
    /// Seconds already worked and banked by a pause or stop.
    public var banked: Int = 0
    /// When the clock last started running; nil while paused or stopped.
    public var resumedAt: Date?

    public init(planned: Int, startedAt: Date) {
        self.planned = planned
        self.resumedAt = startedAt
    }

    public var isPaused: Bool { resumedAt == nil }

    public func elapsed(at now: Date) -> Int {
        banked + Int(resumedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    public func isOver(at now: Date) -> Bool { elapsed(at: now) >= planned }

    public mutating func pause(at now: Date) {
        guard let resumedAt else { return }
        banked += Int(now.timeIntervalSince(resumedAt))
        self.resumedAt = nil
    }

    public mutating func resume(at now: Date) {
        if resumedAt == nil { resumedAt = now }
    }

    /// Stops and returns the total worked seconds.
    public mutating func stop(at now: Date) -> Int {
        pause(at: now)
        return banked
    }
}
