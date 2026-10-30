import CoreGraphics
import Foundation

/// Where the pointer was during a recording, as fractions of the captured area (0...1, y from the top).
public struct CursorTrack: Codable, Equatable, Sendable {
    public struct Sample: Codable, Equatable, Sendable {
        public var t: TimeInterval
        public var x: CGFloat
        public var y: CGFloat
        public init(t: TimeInterval, x: CGFloat, y: CGFloat) { self.t = t; self.x = x; self.y = y }
    }

    public var samples: [Sample]

    public init(samples: [Sample] = []) { self.samples = samples }

    /// A copy with jitter smoothed out (exponential average), so the zoom glides instead of twitching.
    public func smoothed(alpha: CGFloat = 0.12) -> CursorTrack {
        guard var last = samples.first else { return self }
        var out: [Sample] = []
        for s in samples {
            last = Sample(t: s.t, x: last.x + (s.x - last.x) * alpha, y: last.y + (s.y - last.y) * alpha)
            out.append(last)
        }
        return CursorTrack(samples: out)
    }

    /// The pointer at a time: the latest sample at or before it (the first one before the track starts).
    public func position(at t: TimeInterval) -> CGPoint? {
        guard let first = samples.first else { return nil }
        var found = first
        for s in samples { if s.t <= t { found = s } else { break } }
        return CGPoint(x: found.x, y: found.y)
    }

    /// The crop to show at a time: 1/zoom of the frame, centered on the pointer, kept inside the frame.
    public func viewport(at t: TimeInterval, zoom: CGFloat) -> CGRect {
        let w = 1 / zoom, h = 1 / zoom
        guard let p = position(at: t) else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let x = min(max(p.x - w / 2, 0), 1 - w)
        let y = min(max(p.y - h / 2, 0), 1 - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

public extension CursorTrack {
    /// A point in the same coordinate space as `rect`, as fractions of it, clamped to 0...1.
    static func normalize(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: min(max((point.x - rect.minX) / rect.width, 0), 1),
                       y: min(max((point.y - rect.minY) / rect.height, 0), 1))
    }
}
