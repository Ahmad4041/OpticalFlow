import AVFoundation
import Foundation

/// Trims a recording, and lays the camera track over it as a picture-in-picture when given one.
/// Trim alone is a passthrough export (no re-encode). With a camera it re-encodes as HEVC.
enum Exporter {
    static func export(screen: URL, camera: URL? = nil, start: TimeInterval, end: TimeInterval, to output: URL) async throws {
        let asset = AVURLAsset(url: screen)
        let composition = AVMutableComposition()
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                end: CMTime(seconds: end, preferredTimescale: 600))
        guard let screenTrack = try await asset.loadTracks(withMediaType: .video).first,
              let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.noVideo }
        try video.insertTimeRange(range, of: screenTrack, at: .zero)
        for audioTrack in try await asset.loadTracks(withMediaType: .audio) {
            let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try audio?.insertTimeRange(range, of: audioTrack, at: .zero)
        }

        var videoComposition: AVMutableVideoComposition?
        if let camera {
            let cameraAsset = AVURLAsset(url: camera)
            if let cameraTrack = try await cameraAsset.loadTracks(withMediaType: .video).first,
               let pip = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let cameraDuration = try await cameraAsset.load(.duration)
                let cameraRange = CMTimeRange(start: range.start, end: CMTimeMinimum(range.end, cameraDuration))
                try pip.insertTimeRange(cameraRange, of: cameraTrack, at: .zero)
                videoComposition = try await pictureInPicture(screen: screenTrack, screenLayer: video,
                                                              camera: cameraTrack, cameraLayer: pip,
                                                              duration: composition.duration)
            }
        }

        let preset = camera == nil ? AVAssetExportPresetPassthrough : AVAssetExportPresetHEVCHighestQuality
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else { throw ExportError.noSession }
        session.videoComposition = videoComposition
        try? FileManager.default.removeItem(at: output)
        try await session.export(to: output, as: .mp4)
    }

    /// The camera in the bottom-right corner, a quarter of the screen width, with a margin.
    private static func pictureInPicture(screen: AVAssetTrack, screenLayer: AVMutableCompositionTrack,
                                         camera: AVAssetTrack, cameraLayer: AVMutableCompositionTrack,
                                         duration: CMTime) async throws -> AVMutableVideoComposition {
        let size = try await screen.load(.naturalSize)
        let cameraSize = try await camera.load(.naturalSize)
        let cameraTransform = try await camera.load(.preferredTransform)
        let scale = (size.width / 4) / cameraSize.width
        let margin = size.width * 0.02   // ponytail: fixed corner and size, add a position picker when asked
        let transform = cameraTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: size.width - cameraSize.width * scale - margin,
                                             y: size.height - cameraSize.height * scale - margin))

        let screenInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: screenLayer)
        let cameraInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: cameraLayer)
        cameraInstruction.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [cameraInstruction, screenInstruction]

        let composition = AVMutableVideoComposition()
        composition.renderSize = size
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.instructions = [instruction]
        return composition
    }

    enum ExportError: LocalizedError {
        case noVideo, noSession
        var errorDescription: String? {
            switch self {
            case .noVideo: "The recording has no video track."
            case .noSession: "Export is not available for this file."
            }
        }
    }
}
