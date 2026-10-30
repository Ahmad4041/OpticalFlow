import AVFoundation
import Foundation
import OpticalFlowKit

/// Trims a recording, and lays the camera track over it as a picture-in-picture when given one.
/// Trim alone is a passthrough export (no re-encode). With a camera it re-encodes as HEVC.
enum Exporter {
    /// `cameraOffset`: seconds the camera's first frame came after the screen started.
    static func export(screen: URL, camera: URL? = nil, cameraOffset: TimeInterval = 0, layout: CameraLayout = CameraLayout(),
                       start: TimeInterval, end: TimeInterval, to output: URL) async throws {
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
                let cameraDuration = try await cameraAsset.load(.duration).seconds
                // Camera time = screen time - offset. Clamp to what the camera has, keep it aligned.
                let cameraStart = max(0, start - cameraOffset)
                let cameraEnd = min(cameraDuration, end - cameraOffset)
                if cameraEnd > cameraStart {
                    let at = CMTime(seconds: cameraStart + cameraOffset - start, preferredTimescale: 600)
                    try pip.insertTimeRange(CMTimeRange(start: CMTime(seconds: cameraStart, preferredTimescale: 600),
                                                        end: CMTime(seconds: cameraEnd, preferredTimescale: 600)),
                                            of: cameraTrack, at: at)
                }
                let size = try await screenTrack.load(.naturalSize)
                let cameraTransform = try await cameraTrack.load(.preferredTransform)
                let studio = AVMutableVideoComposition()
                studio.customVideoCompositorClass = StudioCompositor.self
                studio.renderSize = size
                studio.frameDuration = CMTime(value: 1, timescale: 30)
                studio.instructions = [StudioInstruction(timeRange: CMTimeRange(start: .zero, duration: composition.duration),
                                                         screenID: video.trackID, cameraID: pip.trackID,
                                                         cameraTransform: cameraTransform, layout: layout)]
                videoComposition = studio
            }
        }

        let preset = camera == nil ? AVAssetExportPresetPassthrough : AVAssetExportPresetHEVCHighestQuality
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else { throw ExportError.noSession }
        session.videoComposition = videoComposition
        try? FileManager.default.removeItem(at: output)
        try await session.export(to: output, as: .mp4)
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
