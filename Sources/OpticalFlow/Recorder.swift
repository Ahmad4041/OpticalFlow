import AppKit
import ScreenCaptureKit
import UserNotifications

/// Screen, system audio, and mic to one MP4 with ScreenCaptureKit. The system picker
/// chooses the display or window, so there is no Screen Recording prompt and no monthly nag.
@Observable
final class Recorder {
    var micEnabled = UserDefaults.standard.object(forKey: "micEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(micEnabled, forKey: "micEnabled") }
    }
    /// The row for the capture in progress. Set by onStart, cleared on stop.
    var recording: Recording?
    var lastError: String?
    var isRecording: Bool { stream != nil }

    var onStart: ((URL) -> Recording?)?
    var onStop: ((Recording, TimeInterval) -> Void)?

    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var startedAt: Date?
    private let observer = PickerObserver()
    private let streamDelegate = StreamDelegate()

    init() {
        observer.onPick = { [weak self] filter in Task { await self?.start(with: filter) } }
        streamDelegate.onStop = { [weak self] in Task { await self?.stop() } }
    }

    /// ~/Movies/OpticalFlow, or /tmp when tests override the store.
    static var directory: URL {
        Store.isOverridden
            ? URL(fileURLWithPath: "/tmp/OpticalFlow-movies")
            : URL.moviesDirectory.appending(path: "OpticalFlow", directoryHint: .isDirectory)
    }

    func pick() {
        guard !isRecording else { return }
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleDisplay, .singleWindow]
        config.allowsChangingSelectedContent = false
        let picker = SCContentSharingPicker.shared
        picker.defaultConfiguration = config
        picker.add(observer)
        picker.isActive = true
        picker.present()
    }

    func start(with filter: SCContentFilter) async {
        guard !isRecording else { return }
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        var width = filter.contentRect.width * scale
        var height = filter.contentRect.height * scale
        if width > 1920 { height *= 1920 / width; width = 1920 }   // ponytail: 1080p cap, add a quality setting if 4K is asked for
        config.width = Int(width) & ~1
        config.height = Int(height) & ~1
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.captureMicrophone = micEnabled

        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(Date.FormatStyle().year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        let url = Self.directory.appending(path: "\(stamp).mp4")
        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = url
        outputConfig.outputFileType = .mp4
        outputConfig.videoCodecType = .hevc
        let output = SCRecordingOutput(configuration: outputConfig, delegate: streamDelegate)
        let stream = SCStream(filter: filter, configuration: config, delegate: streamDelegate)
        do {
            try stream.addRecordingOutput(output)
            try await stream.startCapture()
        } catch {
            lastError = error.localizedDescription
            return
        }
        self.stream = stream
        self.output = output
        startedAt = .now
        recording = onStart?(url)
        SCContentSharingPicker.shared.isActive = false
    }

    func stop() async {
        guard let stream, let output else { return }
        self.stream = nil
        self.output = nil
        try? await stream.stopCapture()
        try? stream.removeRecordingOutput(output)
        let duration = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        if let recording { onStop?(recording, duration) }
        recording = nil
        startedAt = nil
    }
}

/// Carries a non-Sendable value across an isolation boundary we control.
nonisolated struct Unchecked<T>: @unchecked Sendable {
    let value: T
}

final class PickerObserver: NSObject, SCContentSharingPickerObserver {
    var onPick: ((SCContentFilter) -> Void)?

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {}

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        let box = Unchecked(value: filter)
        Task { @MainActor in self.onPick?(box.value) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        print("picker failed: \(error)")
    }
}

final class StreamDelegate: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    var onStop: (() -> Void)?

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        print("stream stopped: \(error)")
        Task { @MainActor in self.onStop?() }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        print("recording failed: \(error)")
        Task { @MainActor in self.onStop?() }
    }
}

/// Session-end notifications. Needs the signed .app bundle, so test runs skip it.
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
