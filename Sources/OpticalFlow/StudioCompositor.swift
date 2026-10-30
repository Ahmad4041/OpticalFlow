import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import OpticalFlowKit

/// One frame recipe: the screen track, an optional camera track laid over it with a shape.
nonisolated final class StudioInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    let screenID: CMPersistentTrackID
    let cameraID: CMPersistentTrackID?
    let cameraTransform: CGAffineTransform
    let layout: CameraLayout
    /// Follow-cursor zoom: the smoothed pointer path and the time the trim starts at in it.
    let cursor: CursorTrack?
    let cursorOffset: TimeInterval
    let zoom: CGFloat

    init(timeRange: CMTimeRange, screenID: CMPersistentTrackID, cameraID: CMPersistentTrackID?,
         cameraTransform: CGAffineTransform, layout: CameraLayout,
         cursor: CursorTrack? = nil, cursorOffset: TimeInterval = 0, zoom: CGFloat = 2) {
        self.timeRange = timeRange
        self.screenID = screenID
        self.cameraID = cameraID
        self.cameraTransform = cameraTransform
        self.layout = layout
        self.cursor = cursor?.smoothed()
        self.cursorOffset = cursorOffset
        self.zoom = zoom
        requiredSourceTrackIDs = ([screenID] + (cameraID.map { [$0] } ?? [])).map { NSNumber(value: $0) }
    }
}

/// Draws each export frame with Core Image: screen, then the camera in its corner, masked to a circle
/// or rounded rectangle, with the person kept sharp over a blurred background when asked.
nonisolated final class StudioCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let queue = DispatchQueue(label: "studio.compositor")
    private let segmentation: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { [self] in
            guard let instruction = request.videoCompositionInstruction as? StudioInstruction,
                  let screen = request.sourceFrame(byTrackID: instruction.screenID),
                  let output = request.renderContext.newPixelBuffer() else {
                request.finish(with: CompositorError.missingFrame)
                return
            }
            let canvas = request.renderContext.size
            var image = CIImage(cvPixelBuffer: screen)
            if let cursor = instruction.cursor {
                let v = cursor.viewport(at: request.compositionTime.seconds + instruction.cursorOffset, zoom: instruction.zoom)
                let px = CGRect(x: v.minX * canvas.width, y: (1 - v.minY - v.height) * canvas.height,
                                width: v.width * canvas.width, height: v.height * canvas.height)
                let scale = canvas.width / px.width
                image = image.cropped(to: px)
                    .transformed(by: CGAffineTransform(translationX: -px.minX, y: -px.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale)))
            }
            if let cameraID = instruction.cameraID, let camera = request.sourceFrame(byTrackID: cameraID) {
                image = overlay(camera: camera, transform: instruction.cameraTransform, layout: instruction.layout,
                                on: image, canvas: canvas)
            }
            context.render(image, to: output, bounds: CGRect(origin: .zero, size: canvas), colorSpace: CGColorSpaceCreateDeviceRGB())
            request.finish(withComposedVideoFrame: output)
        }
    }

    private func overlay(camera buffer: CVPixelBuffer, transform: CGAffineTransform, layout: CameraLayout,
                         on screen: CIImage, canvas: CGSize) -> CIImage {
        var camera = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
        camera = camera.transformed(by: CGAffineTransform(translationX: -camera.extent.minX, y: -camera.extent.minY))
        if layout.blurBackground { camera = blurredBackground(camera, buffer: buffer) }

        let frame = layout.frame(in: canvas, cameraAspect: camera.extent.width / camera.extent.height)
        // Aspect fill into the frame, then crop and mask.
        let scale = max(frame.width / camera.extent.width, frame.height / camera.extent.height)
        let scaled = camera.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offset = CGAffineTransform(translationX: frame.midX - scaled.extent.width / 2, y: frame.midY - scaled.extent.height / 2)
        let placed = scaled.transformed(by: offset).cropped(to: frame)

        let mask = CIFilter.roundedRectangleGenerator()
        mask.extent = frame
        mask.radius = Float(layout.cornerRadius(for: frame))
        mask.color = .white
        let blend = CIFilter.blendWithMask()
        blend.inputImage = placed
        blend.backgroundImage = screen
        blend.maskImage = mask.outputImage
        return blend.outputImage ?? screen
    }

    /// The person stays sharp; everything behind them is blurred.
    private func blurredBackground(_ camera: CIImage, buffer: CVPixelBuffer) -> CIImage {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
        guard (try? handler.perform([segmentation])) != nil,
              let maskBuffer = segmentation.results?.first?.pixelBuffer else { return camera }
        var mask = CIImage(cvPixelBuffer: maskBuffer)
        mask = mask.transformed(by: CGAffineTransform(scaleX: camera.extent.width / mask.extent.width,
                                                      y: camera.extent.height / mask.extent.height))
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = camera.clampedToExtent()
        blur.radius = Float(camera.extent.width / 40)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = camera
        blend.backgroundImage = blur.outputImage?.cropped(to: camera.extent)
        blend.maskImage = mask
        return blend.outputImage ?? camera
    }

    enum CompositorError: Error { case missingFrame }
}
