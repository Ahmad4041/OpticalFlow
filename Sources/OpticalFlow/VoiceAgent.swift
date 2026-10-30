import AppKit
import AVFoundation
import CoreAudio
import Speech
import SwiftUI
import OpticalFlowKit

/// Which program turns a sentence into opticalflow commands.
enum Orchestrator: String, CaseIterable, Identifiable {
    case builtin, claude, codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtin: "Built in (no AI)"
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    var blurb: String {
        switch self {
        case .builtin: "Understands add, complete, start, stop, priority, and notes. Anything else becomes a new task."
        case .claude: "Runs `claude -p` with only the opticalflow command allowed. It reads your tasks, adds, updates, and sets priority as you asked."
        case .codex: "Runs `codex exec` in its workspace sandbox, with network on so it reaches the app. It reads your tasks, adds, updates, and sets priority as you asked."
        }
    }

    private var binary: String? {
        switch self {
        case .builtin: nil
        case .claude: "claude"
        case .codex: "codex"
        }
    }

    /// The executable on this Mac, looked up in the usual install folders.
    var path: String? {
        guard let binary else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin", "/usr/local/bin", "/opt/homebrew/bin", "\(home)/.claude/local", "\(home)/.npm-global/bin"]
            .map { "\($0)/\(binary)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var isInstalled: Bool { self == .builtin || path != nil }

    func arguments(prompt: String, workdir: String) -> [String] {
        switch self {
        case .builtin: []
        case .claude: ["-p", prompt, "--output-format", "text", "--allowedTools", "Bash(opticalflow:*)",
                       "--disallowedTools", "Edit,Write,NotebookEdit,WebFetch,WebSearch"]
        // The workspace sandbox blocks all network, which includes the app's socket; this lets the socket through.
        case .codex: ["exec", "--skip-git-repo-check", "-s", "workspace-write", "-c", "sandbox_workspace_write.network_access=true",
                      "-C", workdir, "--color", "never", prompt]
        }
    }
}

/// Control-Option-Space: listen, show the words, send them to the orchestrator, show its answer.
/// Speech runs on this Mac when the language supports it.
@Observable
final class VoiceAgent {
    var orchestrator: Orchestrator {
        didSet { UserDefaults.standard.set(orchestrator.rawValue, forKey: "voice.orchestrator") }
    }
    var transcript = ""
    var reply = ""
    var error: String?
    var listening = false
    var busy = false
    /// Off while a CLI probe listens, so nothing acts on noise.
    var autoSend = true
    /// What the last listen found, for `opticalflow agent diagnose`.
    private(set) var diagnostics: [String: String] = [:]

    private let model: AppModel
    private var panel: NSPanel?
    private let engine = AVAudioEngine()
    private var recognition: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?
    private var process: Process?

    init(model: AppModel) {
        self.model = model
        let saved = UserDefaults.standard.string(forKey: "voice.orchestrator").flatMap(Orchestrator.init(rawValue:))
        orchestrator = saved.map { $0.isInstalled ? $0 : .builtin } ?? (Orchestrator.claude.isInstalled ? .claude : .builtin)
    }

    var isShown: Bool { panel?.isVisible ?? false }

    /// Hotkey: open and listen; press again to send what was heard; a third press closes.
    func toggle() {
        if isShown {
            if listening, !transcript.isEmpty { send(transcript) } else { close() }
            return
        }
        show(listening: !Store.isOverridden)
    }

    func show(listening: Bool) {
        autoSend = true
        let panel = self.panel ?? makePanel()
        self.panel = panel
        transcript = ""
        reply = ""
        error = nil
        panel.center()
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x, y: screen.visibleFrame.midY + screen.visibleFrame.height * 0.15))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        if listening { Task { await startListening() } }
    }

    func close() {
        stopListening()
        process?.terminate()
        busy = false
        panel?.orderOut(nil)
    }

    // MARK: Speech

    func startListening() async {
        diagnostics = ["locale": Locale.current.identifier]
        // These three callbacks arrive on background queues; @Sendable keeps them off the main actor (the app's default).
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in cont.resume(returning: status) }
        }
        diagnostics["speechAuthorization"] = "\(speech.rawValue)"
        guard speech == .authorized else {
            error = "Allow Speech Recognition for OpticalFlow in System Settings > Privacy & Security > Speech Recognition. You can type instead."
            return
        }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        diagnostics["microphone"] = "\(mic)"
        guard mic else {
            error = "Allow the microphone for OpticalFlow in System Settings > Privacy & Security > Microphone. You can type instead."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer() else {
            error = "No speech recognizer for \(Locale.current.identifier). You can type instead."
            return
        }
        diagnostics["available"] = "\(recognizer.isAvailable)"
        diagnostics["onDevice"] = "\(recognizer.supportsOnDeviceRecognition)"
        guard recognizer.isAvailable else {
            error = "Speech recognition is off. Turn on Dictation in System Settings > Keyboard, or check the network. You can type instead."
            return
        }
        nonisolated(unsafe) let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On this Mac the on-device model may be missing even when supported; the server path still works.
        request.requiresOnDeviceRecognition = false
        request.addsPunctuation = true
        let input = engine.inputNode
        Microphone.apply(to: engine)
        let format = input.outputFormat(forBus: 0)
        diagnostics["inputFormat"] = "\(Int(format.sampleRate)) Hz, \(format.channelCount) ch, \(format.commonFormat == .pcmFormatFloat32 ? "float" : "int")"
        diagnostics["inputDevice"] = Microphone.active?.name ?? ((AVCaptureDevice.default(for: .audio)?.localizedName ?? "none") + " (system default)")
        guard format.sampleRate > 0, format.channelCount > 0 else {
            error = "No microphone input device. Pick one in System Settings > Sound > Input. You can type instead."
            return
        }
        input.removeTap(onBus: 0)
        nonisolated(unsafe) var peak: Float = 0
        nonisolated(unsafe) var buffers = 0
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [weak self] buffer, _ in
            request.append(buffer)
            // Loudest sample so far, so a silent transcript can be told apart from a silent microphone.
            if let data = buffer.floatChannelData?[0] {
                for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[i])) }
            }
            buffers += 1
            if buffers % 20 == 0 {
                let level = peak, count = buffers
                Task { @MainActor in
                    guard let self else { return }
                    self.diagnostics["inputPeak"] = String(format: "%.4f", level)
                    self.diagnostics["inputBuffers"] = "\(count)"
                    // Two seconds of exact zeros is a dead or muted microphone, not a quiet room.
                    if count == 80, level == 0, self.listening, self.error == nil {
                        self.error = "The microphone “\(self.diagnostics["inputDevice"] ?? "")” is silent. Pick another in Settings > Agent, or type instead."
                    }
                }
            }
        }
        engine.prepare()
        do { try engine.start() } catch {
            self.error = "No microphone input: \(error.localizedDescription)"
            diagnostics["engine"] = error.localizedDescription
            return
        }
        listening = true
        recognition = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failure = (error as NSError?).map { (code: $0.code, text: "\($0.domain) \($0.code): \($0.localizedDescription)") }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text, !text.isEmpty {
                    self.transcript = text
                    self.diagnostics["transcript"] = text
                    if self.listening, self.autoSend { self.restartSilenceTimer() }
                }
                if let failure {
                    self.diagnostics["recognizerError"] = failure.text
                    // 216 is the cancel we cause by finishing; 1110 is "no speech" after silence.
                    if self.listening, failure.code != 216, failure.code != 1110 {
                        self.error = "Speech recognition failed: \(failure.text). You can type instead."
                    }
                    self.stopListening()
                    return
                }
                if final, self.listening, self.autoSend { self.send(self.transcript) }
            }
        }
    }

    /// Diagnosis: recognizes a sound file, to tell a microphone problem from a recognition problem.
    func transcribe(file: URL) {
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer() else { diagnostics["fileTranscript"] = "no recognizer"; return }
        diagnostics["fileTranscript"] = "pending"
        let request = SFSpeechURLRecognitionRequest(url: file)
        request.requiresOnDeviceRecognition = false
        recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failure = (error as NSError?).map { "\($0.domain) \($0.code): \($0.localizedDescription)" }
            Task { @MainActor in
                if let text, final || self?.diagnostics["fileTranscript"] == "pending" { self?.diagnostics["fileTranscript"] = text }
                if let failure { self?.diagnostics["fileError"] = failure }
            }
        }
    }

    /// For the CLI: what the last listen saw.
    var state: [String: Any] {
        var json: [String: Any] = diagnostics
        json["listening"] = listening
        json["busy"] = busy
        json["transcript"] = transcript
        json["reply"] = reply
        json["orchestrator"] = orchestrator.rawValue
        json["hotkeyTaken"] = Hotkey.voiceTaken
        json["microphones"] = Microphone.devices().map(\.name)
        json["microphone"] = Microphone.active?.name ?? "system default"
        if let panel {
            json["panelVisible"] = panel.isVisible
            json["panelFrame"] = "\(Int(panel.frame.origin.x)),\(Int(panel.frame.origin.y)) \(Int(panel.frame.width))x\(Int(panel.frame.height))"
            json["panelOnScreen"] = panel.screen != nil
            json["panelKey"] = panel.isKeyWindow
        } else {
            json["panelVisible"] = false
        }
        json["screens"] = NSScreen.screens.map { "\(Int($0.frame.origin.x)),\(Int($0.frame.origin.y)) \(Int($0.frame.width))x\(Int($0.frame.height))" }
        if let error { json["error"] = error }
        return json
    }

    /// Sends after a pause in speech, so nobody has to press Return.
    private func restartSilenceTimer() {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, let self, self.listening else { return }
            self.send(self.transcript)
        }
    }

    func stopListening() {
        silence?.cancel()
        silence = nil
        guard listening else { return }
        listening = false
        recognition?.finish()
        recognition = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    // MARK: Orchestrator

    /// Runs the sentence through the chosen orchestrator and shows the answer.
    func send(_ text: String) {
        stopListening()
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !busy else { return }
        transcript = clean
        error = nil
        if orchestrator == .builtin || !orchestrator.isInstalled {
            reply = model.perform(VoiceIntent.parse(clean))
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if self?.busy == false, self?.listening == false { self?.close() }
            }
            return
        }
        busy = true
        let prompt = prompt(for: clean)
        let which = orchestrator
        Task { [weak self] in
            do {
                let answer = try await self?.run(which, prompt: prompt) ?? ""
                self?.reply = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                self?.error = error.localizedDescription
            }
            self?.busy = false
        }
    }

    private func prompt(for text: String) -> String {
        var context = "Open page: \(model.sidebar?.title ?? "none")."
        if let task = model.selectedTask { context += " Selected task: “\(task.title)” (id \(task.agentID.prefix(8)))." }
        return """
        You control the OpticalFlow task app on this Mac through the `opticalflow` command (run `opticalflow help` for the list; always add --json). \
        The user said, by voice: "\(text)". \(context) \
        Do what they asked with opticalflow commands only: find tasks with `tasks list --search`, add with `tasks add`, change with `tasks update` \
        (--priority high for urgent, --notes to guide the work, --due for dates), `tasks complete`, `session start --task <id>`, `session stop`. \
        Never delete anything. Then answer in one short spoken sentence, plain text, no markdown.
        """
    }

    private func run(_ which: Orchestrator, prompt: String) async throws -> String {
        guard let path = which.path else { throw VoiceError.notInstalled(which.title) }
        let workdir = Store.isOverridden ? "/tmp/OpticalFlow-agent"
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "OpticalFlow/agent").path
        try? FileManager.default.createDirectory(atPath: workdir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = which.arguments(prompt: prompt, workdir: workdir)
        process.currentDirectoryURL = URL(fileURLWithPath: workdir)
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = [env["PATH"] ?? "/usr/bin:/bin", "\(home)/.local/bin", "/usr/local/bin", "/opt/homebrew/bin"].joined(separator: ":")
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        self.process = process
        nonisolated(unsafe) let outHandle = out.fileHandleForReading
        nonisolated(unsafe) let errHandle = err.fileHandleForReading
        async let stdout = Task.detached { outHandle.readDataToEndOfFile() }.value
        async let stderr = Task.detached { errHandle.readDataToEndOfFile() }.value
        let (output, errors) = await (String(decoding: stdout, as: UTF8.self), String(decoding: stderr, as: UTF8.self))
        process.waitUntilExit()
        self.process = nil
        guard process.terminationStatus == 0 || !output.isEmpty else {
            throw VoiceError.failed(which.title, errors.split(separator: "\n").suffix(3).joined(separator: " "))
        }
        return output
    }

    // MARK: Panel

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 140),
                            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setFrameAutosaveName("VoicePanel")
        panel.contentView = NSHostingView(rootView: VoiceView().environment(model).themed())
        return panel
    }
}

enum VoiceError: LocalizedError {
    case notInstalled(String), failed(String, String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let name): "\(name) is not installed. Pick another orchestrator in Settings > Agent."
        case .failed(let name, let detail): "\(name) failed: \(detail)"
        }
    }
}

struct VoiceView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var voice = model.voice
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: voice.listening ? "waveform" : "mic.fill")
                    .symbolEffect(.variableColor.iterative, isActive: voice.listening)
                    .foregroundStyle(voice.listening ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: Space.xxl)
                TextField("Say or type what to do", text: $voice.transcript)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($focused)
                    .onSubmit { voice.send(voice.transcript) }
                    .onExitCommand { voice.close() }
            }
            if voice.busy {
                HStack(spacing: Space.sm) {
                    ProgressView().controlSize(.small)
                    Text("Asking \(voice.orchestrator.title)…")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } else if let error = voice.error {
                Text(error).font(.callout).foregroundStyle(.red)
            } else if !voice.reply.isEmpty {
                Label(voice.reply, systemImage: "checkmark.circle")
                    .font(.callout)
                    .textSelection(.enabled)
            }
            Text(voice.listening ? "Listening. Pause to send, or press Return. Escape cancels."
                 : "Return sends to \(voice.orchestrator.title). Escape closes. Change it in Settings > Agent.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(Space.xl)
        .frame(width: 520)
        .onAppear { focused = true }
    }
}

/// Which microphone the voice panel and the screen recorder read. nil follows the system default.
enum Microphone {
    static var preferredUID: String? {
        get { UserDefaults.standard.string(forKey: "microphone.uid") }
        set { UserDefaults.standard.set(newValue, forKey: "microphone.uid") }
    }

    /// (uid, name) for every input device.
    static func devices() -> [(uid: String, name: String)] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { ($0.uniqueID, $0.localizedName) }
    }

    /// The preferred device when it is present, else nil (the system default).
    static var active: (uid: String, name: String)? {
        guard let uid = preferredUID else { return nil }
        return devices().first { $0.uid == uid }
    }

    /// CoreAudio id for a device uid.
    static func deviceID(for uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), uidPointer, &size, &deviceID)
        }
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    /// Points an audio engine's input at the preferred device. Call before the engine starts.
    static func apply(to engine: AVAudioEngine) {
        guard let active, let id = deviceID(for: active.uid), let unit = engine.inputNode.audioUnit else { return }
        var deviceID = id
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                             &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
    }
}

/// System default or one input device. Shared by Settings > Agent and Settings > Sessions > Recording.
struct MicrophonePicker: View {
    @State private var uid: String? = Microphone.preferredUID
    @State private var devices = Microphone.devices()

    var body: some View {
        Picker("Microphone", selection: $uid) {
            Text("System default").tag(String?.none)
            ForEach(devices, id: \.uid) { device in
                Text(device.name).tag(Optional(device.uid))
            }
        }
        .onChange(of: uid) { Microphone.preferredUID = uid }
        .onAppear { devices = Microphone.devices(); uid = Microphone.preferredUID }
        .help("Used by the voice panel and by screen recordings")
    }
}
