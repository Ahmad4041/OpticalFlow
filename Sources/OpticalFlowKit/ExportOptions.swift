import Foundation

/// What goes into an exported copy of a recording besides the time range.
public struct ExportOptions: Equatable, Sendable {
    public var camera = false
    public var followCursor = false
    public var youtube = false
    public var removeSilence = false

    public init(camera: Bool = false, followCursor: Bool = false, youtube: Bool = false, removeSilence: Bool = false) {
        self.camera = camera
        self.followCursor = followCursor
        self.youtube = youtube
        self.removeSilence = removeSilence
    }

    /// The file name's tail after the range: " with camera zoomed youtube no silence", for the options that applied.
    public var suffix: String {
        [camera ? " with camera" : "", followCursor ? " zoomed" : "", youtube ? " youtube" : "", removeSilence ? " no silence" : ""].joined()
    }
}
