import AVFoundation
import Foundation
import OpticalFlowKit

/// Trims a recording, and lays the camera track over it as a picture-in-picture when given one.
/// Trim alone is a passthrough export (no re-encode). With a camera, or with cuts, it re-encodes as HEVC.
enum Exporter {
    /// `cameraOffset`: seconds the camera's first frame came after the screen started.
    /// `keep`: the ranges of the original that go into the file, in order (silence removal); default the whole trim.
    static func export(screen: URL, camera: URL? = nil, cameraOffset: TimeInterval = 0, layout: CameraLayout = CameraLayout(),
                       cursor: CursorTrack? = nil, youtube: Bool = false, start: TimeInterval, end: TimeInterval,
                       keep: [ClosedRange<TimeInterval>]? = nil, to output: URL) async throws {
        let asset = AVURLAsset(url: screen)
        let composition = AVMutableComposition()
        let segments = keep ?? [start...end]
        func time(_ seconds: TimeInterval) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }
        guard let screenTrack = try await asset.loadTracks(withMediaType: .video).first,
              let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.noVideo }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let audio = audioTracks.map { _ in composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) }

        // The track only weakly holds its asset: the asset stays in scope until the inserts are done.
        let cameraAsset = camera.map { AVURLAsset(url: $0) }
        var cameraTrack: AVAssetTrack?, cameraDuration: TimeInterval = 0
        var pip: AVMutableCompositionTrack?
        var cameraLayer: (id: CMPersistentTrackID, transform: CGAffineTransform)?
        if let cameraAsset {
            if let track = try await cameraAsset.loadTracks(withMediaType: .video).first,
               let overlay = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                cameraTrack = track
                pip = overlay
                cameraDuration = try await cameraAsset.load(.duration).seconds
                cameraLayer = (overlay.trackID, try await track.load(.preferredTransform))
            }
        }

        var placed: [(at: TimeInterval, segment: ClosedRange<TimeInterval>)] = []
        var at: TimeInterval = 0
        for segment in segments {
            let range = CMTimeRange(start: time(segment.lowerBound), end: time(segment.upperBound))
            try video.insertTimeRange(range, of: screenTrack, at: time(at))
            for (track, source) in zip(audio, audioTracks) { try track?.insertTimeRange(range, of: source, at: time(at)) }
            if let cameraTrack, let pip {
                // Camera time = screen time - offset. Clamp to what the camera has, keep it aligned.
                let cameraStart = max(0, segment.lowerBound - cameraOffset)
                let cameraEnd = min(cameraDuration, segment.upperBound - cameraOffset)
                if cameraEnd > cameraStart {
                    try pip.insertTimeRange(CMTimeRange(start: time(cameraStart), end: time(cameraEnd)),
                                            of: cameraTrack, at: time(at + cameraStart + cameraOffset - segment.lowerBound))
                }
            }
            placed.append((at, segment))
            at += segment.upperBound - segment.lowerBound
        }
        // Instructions tile the composition exactly: the last one ends where the tracks end.
        let instructions = placed.enumerated().map { i, p in
            StudioInstruction(timeRange: CMTimeRange(start: time(p.at), end: i == placed.count - 1 ? composition.duration : time(placed[i + 1].at)),
                              screenID: video.trackID, cameraID: cameraLayer?.id,
                              cameraTransform: cameraLayer?.transform ?? .identity, layout: layout,
                              cursor: cursor, cursorOffset: p.segment.lowerBound - p.at)
        }

        var videoComposition: AVVideoComposition?
        if cameraLayer != nil || cursor != nil {
            videoComposition = AVVideoComposition(configuration: .init(
                customVideoCompositorClass: StudioCompositor.self, frameDuration: CMTime(value: 1, timescale: 30),
                instructions: instructions, renderSize: try await screenTrack.load(.naturalSize)))
        }

        // YouTube's recommendation is H.264 at up to 1080p with AAC; that preset re-encodes to exactly that.
        // A cut file is re-encoded too: a passthrough copy breaks the frames after every cut until the next keyframe.
        let preset = youtube ? AVAssetExportPreset1920x1080
            : videoComposition == nil && segments.count == 1 ? AVAssetExportPresetPassthrough : AVAssetExportPresetHEVCHighestQuality
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else { throw ExportError.noSession }
        session.videoComposition = videoComposition
        try? FileManager.default.removeItem(at: output)
        try await session.export(to: output, as: .mp4)
    }

    /// Audio loudness of a file as one RMS value (0 to 1) per `step` seconds of mixed-down audio, or nil without audio.
    nonisolated static func levels(of url: URL, step: TimeInterval = SilenceCut.step) async throws -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: 16000,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ExportError.noSession }
        let window = Int(16000 * step)
        var levels: [Float] = [], sum: Float = 0, count = 0
        while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
            var length = 0, pointer: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
            guard let pointer else { continue }
            pointer.withMemoryRebound(to: Float.self, capacity: length / 4) { floats in
                for i in 0..<(length / 4) {
                    sum += floats[i] * floats[i]
                    count += 1
                    if count == window { levels.append((sum / Float(count)).squareRoot()); sum = 0; count = 0 }
                }
            }
        }
        if count > 0 { levels.append((sum / Float(count)).squareRoot()) }
        return levels
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
