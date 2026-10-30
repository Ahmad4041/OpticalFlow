import AppKit
import AVFoundation
import ScreenCaptureKit
import OpticalFlowKit
import UserNotifications

/// Screen, system audio, and mic to one MP4 with ScreenCaptureKit. The system picker
/// chooses the display or window, so there is no Screen Recording prompt and no monthly nag.
@Observable
final class Recorder {
    var micEnabled = UserDefaults.standard.object(forKey: "micEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(micEnabled, forKey: "micEnabled") }
    }
    var cameraEnabled = UserDefaults.standard.object(forKey: "cameraEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(cameraEnabled, forKey: "cameraEnabled") }
    }
    /// Opt-in: when the pointer moves to another display, the capture follows it.
    /// Listing displays needs the Screen Recording permission the picker otherwise avoids.
    var followsDisplay = UserDefaults.standard.bool(forKey: "followsDisplay") {
        didSet { UserDefaults.standard.set(followsDisplay, forKey: "followsDisplay") }
    }
    var cameraLayout: CameraLayout = {
        guard let data = UserDefaults.standard.data(forKey: "cameraLayout"),
              let layout = try? JSONDecoder().decode(CameraLayout.self, from: data) else { return CameraLayout() }
        return layout
    }() {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(cameraLayout), forKey: "cameraLayout")
            camera.bubble.apply(cameraLayout)
        }
    }
    /// The row for the capture in progress. Set by onStart, cleared on stop.
    var recording: Recording?
    var lastError: String?
    var isRecording: Bool { stream != nil }

    var onStart: ((URL) -> Recording?)?
    var onStop: ((Recording, TimeInterval) -> Void)?

    private var stream: SCStream?
    private var output: SCRecordingOutput?
    /// Set before the first await in start: the picker can call back more than once.
    private var starting = false
    private var startedAt: Date?
    private var screenStartedAt: Date?
    private var cursor = CursorTrack()
    private var cursorTimer: Timer?
    private var cursorURL: URL?
    /// The captured rect in CG coordinates (y from the top); moves when the capture follows the pointer.
    private var capturedRect = CGRect.zero
    private var switching = false
    private let observer = PickerObserver()
    private let streamDelegate = StreamDelegate()
    private let camera = CameraRecorder()

    init() {
        observer.onPick = { [weak self] filter in Task { await self?.start(with: filter) } }
        streamDelegate.onStop = { [weak self] in Task { await self?.stop() } }
        SCContentSharingPicker.shared.add(observer)   // once; adding per pick doubled the callbacks
    }

    /// Takes the start lock. False while a capture is starting or running.
    func claimStart() -> Bool {
        guard !isRecording, !starting else { return false }
        starting = true
        return true
    }

    /// ~/Movies/OpticalFlow, or /tmp when tests override the store.
    static var directory: URL {
        Store.isOverridden
            ? URL(fileURLWithPath: "/tmp/OpticalFlow-movies")
            : URL.moviesDirectory.appending(path: "OpticalFlow", directoryHint: .isDirectory)
    }

    /// How many times the picker was asked for. Test runs count but never show the system picker.
    private(set) var pickRequests = 0

    func pick() {
        guard !isRecording, !starting else { return }
        pickRequests += 1
        if Store.isOverridden { return }
        lastError = nil
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleDisplay, .singleWindow]
        config.allowsChangingSelectedContent = false
        let picker = SCContentSharingPicker.shared
        picker.defaultConfiguration = config
        picker.isActive = true
        picker.present()
    }

    func start(with filter: SCContentFilter) async {
        guard claimStart() else { return }
        defer { starting = false }
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
        // ScreenCaptureKit does not raise the microphone prompt itself: without this, the mic track is silence.
        if micEnabled, !(await AVCaptureDevice.requestAccess(for: .audio)) {
            lastError = "No microphone: allow OpticalFlow in System Settings > Privacy & Security > Microphone."
        }
        config.captureMicrophone = micEnabled && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        config.excludesCurrentProcessAudio = true
        config.queueDepth = 6

        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(Date.FormatStyle().year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        let url = Self.directory.appending(path: "\(stamp).mp4")
        // The camera starts first: its permission prompt must not delay the screen capture.
        let cameraURL = Self.directory.appending(path: "\(stamp)-camera.mov")
        let cameraStarted = cameraEnabled ? await camera.start(to: cameraURL, layout: cameraLayout) : false
        if cameraEnabled, !cameraStarted {
            lastError = "No camera: allow OpticalFlow in System Settings > Privacy & Security > Camera."
        }
        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = url
        outputConfig.outputFileType = .mp4
        outputConfig.videoCodecType = .h264   // hardware-encoded on Intel too, and what YouTube recommends
        let output = SCRecordingOutput(configuration: outputConfig, delegate: streamDelegate)
        let stream = SCStream(filter: filter, configuration: config, delegate: streamDelegate)
        do {
            try stream.addRecordingOutput(output)
            try await stream.startCapture()
        } catch {
            lastError = error.localizedDescription
            if cameraStarted { await camera.stop() }
            return
        }
        self.stream = stream
        self.output = output
        startedAt = .now
        recording = onStart?(url)
        if cameraStarted { recording?.cameraPath = cameraURL.path }
        screenStartedAt = startedAt
        SCContentSharingPicker.shared.isActive = false
        trackCursor(in: filter.contentRect, to: Self.directory.appending(path: "\(stamp)-cursor.json"))
    }

    /// Ten pointer samples a second, as fractions of the captured rect (CG coordinates, y from the top).
    private func trackCursor(in rect: CGRect, to url: URL) {
        cursor = CursorTrack()
        cursorURL = url
        capturedRect = rect
        recording?.cursorPath = url.path
        let started = Date.now
        var tick = 0
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let cg = Self.cgPoint(NSEvent.mouseLocation)
                let p = CursorTrack.normalize(cg, in: self.capturedRect)
                self.cursor.samples.append(.init(t: Date.now.timeIntervalSince(started), x: p.x, y: p.y))
                tick += 1
                if self.followsDisplay, tick % 5 == 0, !self.capturedRect.contains(cg) { Task { await self.follow(to: cg) } }
            }
        }
    }

    /// Cocoa (bottom-left) to CG (top-left) coordinates on the primary display.
    private static func cgPoint(_ p: NSPoint) -> CGPoint {
        CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.height ?? 0) - p.y)
    }

    private static func cgFrame(_ screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
    }

    /// Switches the live capture to the display under the pointer. Only when the capture was a whole display.
    private func follow(to point: CGPoint) async {
        guard let stream, !switching,
              let screen = NSScreen.screens.first(where: { Self.cgFrame($0).contains(point) }),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              NSScreen.screens.contains(where: { Self.cgFrame($0) == capturedRect }) else { return }
        switching = true
        defer { switching = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == id }) else { return }
            try await stream.updateContentFilter(SCContentFilter(display: display, excludingWindows: []))
            capturedRect = Self.cgFrame(screen)
        } catch {
            lastError = "Could not follow the pointer to the other display: \(error.localizedDescription)"
        }
    }

    private func stopCursorTracking() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        if let cursorURL, let data = try? JSONEncoder().encode(cursor) { try? data.write(to: cursorURL) }
        cursorURL = nil
    }

    func stop() async {
        guard let stream, let output else { return }
        self.stream = nil
        self.output = nil
        try? await stream.stopCapture()
        try? stream.removeRecordingOutput(output)
        stopCursorTracking()
        await camera.stop()
        let duration = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        if let recording, let screenStartedAt, let firstFrame = camera.firstFrameAt {
            recording.cameraOffset = firstFrame.timeIntervalSince(screenStartedAt)
        }
        if let recording { onStop?(recording, duration) }
        recording = nil
        startedAt = nil
    }
}

/// The camera to a sidecar .mov, video only: the mic already goes into the screen recording.
final class CameraRecorder {
    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let delegate = CameraDelegate()
    let bubble = CameraBubble()
    /// When the first camera frame hit the file. Webcams warm up late; the export uses this to stay in sync.
    private(set) var firstFrameAt: Date?

    /// False when there is no camera or no permission.
    func start(to url: URL, layout: CameraLayout) async -> Bool {
        guard await AVCaptureDevice.requestAccess(for: .video),
              let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720   // ponytail: 720p keeps an Intel Mac smooth beside the screen capture
        if session.canAddInput(input) { session.addInput(input) }
        if session.outputs.isEmpty, session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        session.startRunning()   // ponytail: blocks the main thread for ~100 ms; move to a queue if it shows
        firstFrameAt = nil
        delegate.onStart = { [weak self] in self?.firstFrameAt = .now }
        output.startRecording(to: url, recordingDelegate: delegate)
        bubble.show(session: session, layout: layout)
        return true
    }

    func stop() async {
        bubble.hide()
        if output.isRecording {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                delegate.onFinish = { done.resume() }
                output.stopRecording()
            }
        }
        session.stopRunning()
        for input in session.inputs { session.removeInput(input) }
    }
}

final class CameraDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        Task { @MainActor in self.onStart?() }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection], error: (any Error)?) {
        if let error { print("camera: \(error)") }
        Task { @MainActor in
            self.onFinish?()
            self.onFinish = nil
        }
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
    static let sessionDone = "sessionDone"
    static let breakFive = "break5"
    static let breakFifteen = "break15"
    static let idle = "idle"
    static let keepIdle = "keepIdle"
    static let discardIdle = "discardIdle"

    static func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([
            UNNotificationCategory(identifier: sessionDone, actions: [
                UNNotificationAction(identifier: breakFive, title: "Break 5 min"),
                UNNotificationAction(identifier: breakFifteen, title: "Break 15 min"),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: idle, actions: [
                UNNotificationAction(identifier: keepIdle, title: "Keep"),
                UNNotificationAction(identifier: discardIdle, title: "Discard"),
            ], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ title: String, _ body: String, category: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
