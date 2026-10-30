import CoreGraphics
import Foundation

/// Where and how big the camera sits over the screen, live and in the export.
public struct CameraLayout: Codable, Equatable, Sendable {
    public enum Corner: String, CaseIterable, Codable, Sendable { case topLeft, topRight, bottomLeft, bottomRight }
    public enum Size: String, CaseIterable, Codable, Sendable {
        case small, medium, large
        /// Fraction of the canvas width.
        public var fraction: CGFloat {
            switch self {
            case .small: 1 / 6
            case .medium: 1 / 4
            case .large: 1 / 3
            }
        }
    }
    public enum Shape: String, CaseIterable, Codable, Sendable { case circle, rounded }

    public var corner: Corner
    public var size: Size
    public var shape: Shape
    public var blurBackground: Bool

    public init(corner: Corner = .bottomRight, size: Size = .medium, shape: Shape = .circle, blurBackground: Bool = false) {
        self.corner = corner
        self.size = size
        self.shape = shape
        self.blurBackground = blurBackground
    }

    public static let margin: CGFloat = 0.02

    /// The camera's frame in a canvas with a bottom-left origin (Core Image and AppKit).
    /// A circle is a square; rounded keeps the camera's own aspect.
    public func frame(in canvas: CGSize, cameraAspect: CGFloat = 16 / 9) -> CGRect {
        let width = (canvas.width * size.fraction).rounded()
        let height = shape == .circle ? width : (width / cameraAspect).rounded()
        let margin = (canvas.width * Self.margin).rounded()
        let x = corner == .topLeft || corner == .bottomLeft ? margin : canvas.width - width - margin
        let y = corner == .bottomLeft || corner == .bottomRight ? margin : canvas.height - height - margin
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Corner radius for the shape.
    public func cornerRadius(for frame: CGRect) -> CGFloat {
        shape == .circle ? frame.width / 2 : (frame.width * 0.08).rounded()
    }
}
